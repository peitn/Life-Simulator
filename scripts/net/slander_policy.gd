extends RefCounted
## SlanderPolicy – pravidla pomluvy soka přes hranici hráčů (multiplayer; drží ji jen server/host).
##
## Vychází z otevřeného nálezu auditu rivality (21. 11. 2026): pomluva postavě JINÉHO hráče nebyla ošetřená –
## AI za cizího hráče rozhodovala, zda pomluvě uvěří, a jednu postavu šlo „ušikanovat“ řečmi od více autorů.
## Pomluva mezi hráči ale zakázaná není: intriky k tónu hry patří. Pravidla:
##
## 1) Posluchač patří jinému hráči než autor (autor je hráč i AI): server drb předá (posluchač si pamatuje
##    „Drb od: X …“), ale dopad na vztahy ODLOŽÍ a otevře soukromý verdikt pro vlastníka posluchače:
##    "believe" (uvěřit), "dismiss" (nevěřit), "tell" (nevěřit a říct to oběti). Bez odpovědi do VERDICT_TTL
##    herních minut (12 h) platí výchozí „napůl zapochyboval(a)“ (stejně jako AI výsledek doubted).
## 2) Oběť (sok) patří hráči: nejvýš VICTIM_DAILY_CAP pomluv o ní za herní den napříč všemi autory.
##
## Čas je herní (GameClock.total_minutes) a určuje ho server. Politika rewindu je stejná jako v ostatních
## modulech (Rivalry, Romance, ColdWar…): záznamy „z budoucnosti“ se ignorují, dokud čas nedožene, nic se
## nevrací ani nezesiluje. Stav je běhový (jako rate limity): po restartu serveru se čekající verdikty
## vyhodnotí jako výchozí – nic se neukládá, a proto ani nic nemigruje.
##
## Bezpečnost: verdikt přichází od klienta → resolve() ověřuje typy (vid jen TYPE_INT, choice jen TYPE_STRING
## z CHOICES), existenci a VLASTNICTVÍ (vid patří přesně tomu peeru). Klientovi jde jen veřejně čitelné
## shrnutí (jména a věta drbu, kterou jeho postava stejně slyšela) – žádná čísla vztahů ani psychiky.

const VICTIM_DAILY_CAP := 3
const DAY := 1440.0
const VERDICT_TTL := 720.0
const MAX_PENDING_PER_PEER := 8
const MAX_PENDING_TOTAL := 256
const MAX_VICTIMS := 256
const CHOICES := ["believe", "dismiss", "tell"]
## Klientská strana: limity přijatého seznamu (server posílá max MAX_PENDING_PER_PEER).
const MAX_NAME_LEN := 40
const MAX_LINE_LEN := 200

## uzel postavy oběti -> Array[float] časů pomluv (herní minuty)
var _victims := {}
## vid -> {"owner": String (uzel postavy posluchače), "t": float, "data": Dictionary}
## Klíčem vlastnictví je POSTAVA, ne peer id: po znovupřipojení (nové peer id) hráč verdikty neztratí
## a server při rozhodnutí ověřuje, že peer tu postavu právě teď ovládá.
var _pending := {}
var _next_vid := 1
var stats := {"opened": 0, "resolved": 0, "expired": 0, "dropped": 0, "rejected": 0, "capped": 0}


# ------------------------------------------------------------------ strop na oběť

## Kolik pomluv o oběti padlo v posledním herním dni (jen záznamy t <= now; budoucí po rewindu se nepočítají).
func victim_count(victim: String, now: float) -> int:
	if victim == "" or not is_finite(now):
		return 0
	_prune_victim(victim, now)
	var n := 0
	for t in _victims.get(victim, []):
		if float(t) <= now and now - float(t) < DAY:
			n += 1
	return n


func victim_capped(victim: String, now: float) -> bool:
	return victim_count(victim, now) >= VICTIM_DAILY_CAP


## Zapíše pomluvu o oběti (volá autorita po proběhlé pomluvě oběti-hráče).
func note_victim(victim: String, now: float) -> void:
	if victim == "" or not is_finite(now):
		return
	_prune_victim(victim, now)
	if not _victims.has(victim):
		if _victims.size() >= MAX_VICTIMS:
			_evict_victim()
		_victims[victim] = []
	var arr: Array = _victims[victim]
	arr.append(now)
	# Víc než strop × 2 záznamů nemá smysl držet (strop je 3 za den) – ochrana paměti.
	while arr.size() > VICTIM_DAILY_CAP * 2:
		arr.pop_front()


## Smaže záznamy starší než den. Záznamy z budoucnosti (po rewindu) nechá – počítat se začnou, až čas dožene.
func _prune_victim(victim: String, now: float) -> void:
	if not _victims.has(victim):
		return
	var keep: Array = []
	for t in _victims[victim]:
		if float(t) > now - DAY:
			keep.append(float(t))
	if keep.is_empty():
		_victims.erase(victim)
	else:
		_victims[victim] = keep


func _evict_victim() -> void:
	# Deterministicky: vyhodí oběť s nejstarším posledním záznamem (při shodě podle jména).
	var worst := ""
	var worst_t := INF
	var ks: Array = _victims.keys()
	ks.sort()
	for k in ks:
		var arr: Array = _victims[k]
		var last: float = float(arr.back()) if not arr.is_empty() else -INF
		if last < worst_t:
			worst_t = last
			worst = String(k)
	if worst != "":
		_victims.erase(worst)


# ------------------------------------------------------------------ čekající verdikty

## Otevře verdikt pro vlastníka postavy posluchače `owner` (uzel postavy). data = cokoli, co autorita potřebuje k pozdějšímu vyhodnocení
## (uzly postav, rid drbu, odložené delty) + veřejné shrnutí "author_name", "rival_name", "line".
## Vrací {"vid": int (0 = neotevřeno), "dropped": Array záznamů, které se kvůli limitu musí vyhodnotit výchozím
## verdiktem}. Nejstarší záznam hráče se při přetečení „uzavře“ výchozím verdiktem – nic se neztratí potichu.
func open(owner: String, data: Dictionary, now: float) -> Dictionary:
	var dropped: Array = []
	if owner == "" or not is_finite(now) or typeof(data) != TYPE_DICTIONARY:
		return {"vid": 0, "dropped": dropped}
	var mine := _vids_of(owner)
	while mine.size() >= MAX_PENDING_PER_PEER:
		dropped.append(_take(int(mine.pop_front())))
		stats["dropped"] += 1
	while _pending.size() >= MAX_PENDING_TOTAL:
		var all: Array = _pending.keys()
		all.sort()
		dropped.append(_take(int(all[0])))
		stats["dropped"] += 1
	var vid := _next_vid
	_next_vid += 1
	if _next_vid > 2000000000:
		_next_vid = 1
	_pending[vid] = {"owner": owner, "t": now, "data": data.duplicate(true)}
	stats["opened"] += 1
	return {"vid": vid, "dropped": dropped}


## Vlastník postavy `owner` rozhodl o verdiktu `vid` (volající ověřil, že peer postavu ovládá). Vrací {"ok": bool, "reason": String, "entry": Dictionary}.
## reason: "type" (špatné typy), "choice" (neznámá volba), "unknown" (neexistuje / už vyřízeno), "owner"
## (verdikt patří jinému hráči – NEMĚNÍ se). Úspěch záznam odebere (dvojí vyřízení nejde).
func resolve(owner: String, vid: Variant, choice: Variant) -> Dictionary:
	if typeof(vid) != TYPE_INT or typeof(choice) != TYPE_STRING:
		stats["rejected"] += 1
		return {"ok": false, "reason": "type", "entry": {}}
	if not String(choice) in CHOICES:
		stats["rejected"] += 1
		return {"ok": false, "reason": "choice", "entry": {}}
	if not _pending.has(int(vid)):
		stats["rejected"] += 1
		return {"ok": false, "reason": "unknown", "entry": {}}
	if owner == "" or String(_pending[int(vid)]["owner"]) != owner:
		stats["rejected"] += 1
		return {"ok": false, "reason": "owner", "entry": {}}
	stats["resolved"] += 1
	return {"ok": true, "reason": "", "entry": _take(int(vid))}


## Verdikty, kterým vypršela lhůta (t <= now a now - t >= VERDICT_TTL), seřazené podle vid. Odebere je.
func expire(now: float) -> Array:
	var out: Array = []
	if not is_finite(now):
		return out
	var ks: Array = _pending.keys()
	ks.sort()
	for vid in ks:
		var t := float(_pending[vid]["t"])
		if t <= now and now - t >= VERDICT_TTL:
			out.append(_take(int(vid)))
			stats["expired"] += 1
	return out


## Postava posluchače zmizela natrvalo: její verdikty se uzavřou výchozím verdiktem (vrací je volajícímu).
func drop_owner(owner: String) -> Array:
	var out: Array = []
	for vid in _vids_of(owner):
		out.append(_take(int(vid)))
		stats["dropped"] += 1
	return out


## Veřejné shrnutí pro vlastníka: [[vid, autor, sok, věta], …] podle vid.
func pending_for(owner: String) -> Array:
	var out: Array = []
	for vid in _vids_of(owner):
		var d: Dictionary = _pending[vid]["data"]
		out.append([int(vid), String(d.get("author_name", "")).left(MAX_NAME_LEN),
			String(d.get("rival_name", "")).left(MAX_NAME_LEN), String(d.get("line", "")).left(MAX_LINE_LEN)])
	return out


func pending_count(owner: String = "") -> int:
	return _pending.size() if owner == "" else _vids_of(owner).size()


## Čekající verdikty, které se týkají postavy (uzel) – když postava zmizí, autorita je uzavře.
func vids_mentioning(node_name: String) -> Array:
	var out: Array = []
	var ks: Array = _pending.keys()
	ks.sort()
	for vid in ks:
		var d: Dictionary = _pending[vid]["data"]
		if node_name in [String(d.get("author_node", "")), String(d.get("listener_node", "")), String(d.get("rival_node", ""))]:
			out.append(int(vid))
	return out


func take(vid: int) -> Dictionary:
	return _take(vid) if _pending.has(vid) else {}


func _vids_of(owner: String) -> Array:
	var out: Array = []
	for vid in _pending.keys():
		if String(_pending[vid]["owner"]) == owner:
			out.append(int(vid))
	out.sort()
	return out


func _take(vid: int) -> Dictionary:
	var e: Dictionary = _pending[vid]
	_pending.erase(vid)
	return {"vid": vid, "owner": String(e["owner"]), "t": float(e["t"]), "data": e["data"]}


# ------------------------------------------------------------------ klient: validace přijatého seznamu

## Klient: z nedůvěryhodného (byť serverového) paketu udělá bezpečný seznam [[vid, autor, sok, věta], …].
## Neplatné položky zahodí, texty ořízne a zbaví řídicích a bidi znaků, nejvýš MAX_PENDING_PER_PEER položek.
static func sanitize_inbox(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for it in v:
		if out.size() >= MAX_PENDING_PER_PEER:
			break
		if typeof(it) != TYPE_ARRAY or it.size() != 4 or typeof(it[0]) != TYPE_INT or int(it[0]) <= 0:
			continue
		if typeof(it[1]) != TYPE_STRING or typeof(it[2]) != TYPE_STRING or typeof(it[3]) != TYPE_STRING:
			continue
		var a := clean_text(String(it[1]), MAX_NAME_LEN)
		var r := clean_text(String(it[2]), MAX_NAME_LEN)
		if a == "" or r == "":
			continue
		out.append([int(it[0]), a, r, clean_text(String(it[3]), MAX_LINE_LEN)])
	return out


## Odstraní řídicí znaky (C0/C1), bidi přepínače, neviditelné formátovací znaky a náhradní znak U+FFFD
## (vzniká z poškozeného UTF-8 / NUL); ořízne délku.
static func clean_text(s: String, max_len: int) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 0x20 or (c >= 0x7F and c <= 0x9F):
			continue
		if (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) \
				or c == 0x061C or c == 0xFEFF or c == 0xFFFD or c == 0xFFFE or c == 0xFFFF:
			continue
		out += String.chr(c)
		if out.length() >= max_len:
			break
	return out.strip_edges()
