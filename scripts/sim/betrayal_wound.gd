extends RefCounted
## BetrayalWound – psychické následky zrady (nevěry) pro zrazenou postavu (21. 11. 2026).
##
## Proč: Infidelity řeší, CO se stalo (románek, podezření, konfrontace) a SimAgent.on_betrayal okamžité
## dopady na vztah (důvěra, zášť, stres, moodlet). Zrada ale v člověku pracuje ještě týdny a měsíce:
## vracejí se otázky a obrazy (ruminace), člověk se stahuje, obrací to proti sobě („co je na mně
## špatně?“), sahá po úlevě, která nepomáhá, a v dalším vztahu hůř věří. Tohle je ta dlouhá stopa.
##
## Model – jedna „rána“ na člověka, který zradil (klíč = soukromé uid, jméno jen popisek):
##   acute     0..1  akutní bolest; vyhasíná s τ ACUTE_TAU, rychleji se zpracováním (processed);
##                   spouštěče (vidět je spolu, drb) ji znovu rozdírají;
##   scar      0..1  jizva – opatrnost v důvěře; vyhasíná velmi pomalu (SCAR_TAU), zpracování ji zmírní;
##   processed 0..1  pokrok zotavení: svěření, deník, terapie, přijatá upřímná omluva; zrada znovu ho srazí;
##   belief    0..1  soukromé self_defectiveness v okamžiku zrady (posuvník postavy se NIKDY nemění –
##                   rozhodnutí uživatelky); určuje, jak moc se bolest obrací proti sobě;
##   numb/rebound    alkohol bolest na pár hodin otupí, pak se vrátí o kus silnější (nezdravý coping).
##
## Zásady (konvence psychiky, viz psyche_ext.gd):
##   - nic se nevynucuje ani nezakazuje, mění se jen chuť na akce a výběr lidí (násobiče v mezích);
##   - režim obsahu k: 1 = plně, 0,5 = tlumeně, 0 = vypnuto (násobiče přesně 1, žádné řádky ani myšlenky);
##     čas hojí i ve vypnutém režimu (stav se dál vyvíjí, jen se neprojevuje);
##   - soukromé: nic z toho nejde do veřejné replikace; vlastník vidí jen slova, nikdy čísla;
##   - deterministické: žádná náhoda (výběr věty podle hashe), aby testy a MP byly reprodukovatelné;
##   - cesta k zotavení není nikdy uzavřená: akutní bolest vždy časem odezní, jizva také (velmi pomalu).

const MAX_WOUNDS := 4
const MAX_KEY := 64
const MAX_NAME := 64
const ACUTE_TAU := 20160.0        # 14 dní
const SCAR_TAU := 259200.0        # 180 dní
const NUMB_MIN := 180.0           # alkohol otupí na 3 h
const REBOUND := 0.08             # … pak se bolest vrátí silnější
const NUMB_TOLERANCE := 0.15      # každé další napití během otupení uleví méně (tolerance)
const REMINDER_GAP := 360.0       # spouštěč téhož člověka nejvýš jednou za 6 h
const THOUGHT_GAP := 60.0         # rušivá otázka nejvýš jednou za herní hodinu
const END := 0.02                 # pod tímto se rána (acute i scar) rozpustí

## Rušivé otázky po zradě ({name} = kdo zradil, {lover} = s kým; {g}/{ng} rod jako ve vnitřním hlase).
const INTRUSIVE := [
	"Jak dlouho mi to {name} tajil{ng}?",
	"Jak jsem to mohl{g} nevidět?",
	"Kolikrát mi {name} lhal{ng} do očí?",
	"Pořád se mi vrací, jak spolu byli.",
	"Myslel{ng} na mě vůbec, když byli spolu?",
	"Mám to někomu říct, nebo se stydět za to, že jsem to nevěděl{g}?",
]
## Obrácení proti sobě – jen při silnějším vnitřním přesvědčení (belief), jako zkreslená myšlenka.
## Texty nesou odstup („hlava mi vnucuje…“) – hra zkreslené přesvědčení nepotvrzuje jako pravdu (audit Gemini 21. 11.).
const SELF_BLAME := [
	"Hlava mi pořád vnucuje, že jsem pro {name} nebyl{g} dost. Je to vůbec fér?",
	"Zase ta myšlenka: co je na mně špatně, že to musel{ng} hledat jinde? Jako by to byla moje chyba.",
]
## Zpracování (svěření, terapie, omluva) – naděje z dat, ne náhodná výplň.
const HEALING := [
	"Mluvit o tom pomohlo. Pořád to bolí, ale už ne tak ostře.",
	"Nebyla to moje vina. Zkouším si to opakovat.",
	"Jednou to bude jen jizva.",
]

var wounds: Array = []


func is_empty() -> bool:
	return wounds.is_empty()


static func _fin(v, lo: float, hi: float, dflt: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dflt
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return dflt
	return clampf(f, lo, hi)


static func _valid_key(s) -> bool:
	return typeof(s) == TYPE_STRING and String(s) != "" and String(s).length() <= MAX_KEY


func find(about: String) -> Dictionary:
	for w in wounds:
		if String(w["about"]) == about:
			return w
	return {}


## Zrada odhalena: otevře novou ránu, nebo rozdře starou (opakovaná zrada od stejného člověka bolí víc
## a srazí dosavadní zpracování). sev 0..1 z SimAgent.on_betrayal (počet schůzek, způsob odhalení).
## Vrací záznam rány (pro volajícího jen ke čtení).
func open(about: String, about_name: String, lover: String, lover_name: String, sev: float, now: float,
		self_belief: float) -> Dictionary:
	if not _valid_key(about) or not is_finite(now):
		return {}
	sev = _fin(sev, 0.0, 1.0, 0.6)
	var w := find(about)
	if w.is_empty():
		if wounds.size() >= MAX_WOUNDS:
			_evict_weakest(now)
		w = {"about": about, "name": about_name.substr(0, MAX_NAME), "lover": "", "lover_name": "",
			"since": now, "t": now, "acute": 0.0, "scar": 0.0, "processed": 0.0, "belief": 0.0,
			"numb_until": -1.0e12, "numb_n": 0, "rebound": 0.0, "last_reminder": -1.0e12, "last_thought": -1.0e12, "count": 0}
		wounds.append(w)
	_settle(w, now)
	w["acute"] = clampf(1.0 - (1.0 - float(w["acute"])) * (1.0 - (0.55 + 0.4 * sev)), 0.0, 1.0)
	w["scar"] = clampf(maxf(float(w["scar"]), 0.3 + 0.4 * sev) + 0.1 * float(w["count"]), 0.0, 1.0)
	w["processed"] = float(w["processed"]) * 0.5
	w["belief"] = _fin(self_belief, 0.0, 1.0, 0.0)
	w["count"] = mini(int(w["count"]) + 1, 99)
	if _valid_key(lover) and lover != about:
		w["lover"] = lover
		w["lover_name"] = lover_name.substr(0, MAX_NAME)
	w["t"] = maxf(float(w["t"]), now)
	return w


## Doběhne časový vývoj rány do `now` (líně, při každém dotazu i v tick). Rewind (now < t) nic nemění.
func _settle(w: Dictionary, now: float) -> void:
	if not is_finite(now):
		return  # NaN/INF čas nesmí otrávit stav (audit Gemini)
	var dt := now - float(w["t"])
	if dt <= 0.0:
		return
	var pr := float(w["processed"])
	var ac := float(w["acute"]) * exp(-dt * (1.0 + 1.5 * pr) / ACUTE_TAU)
	# Otupení alkoholem skončilo: bolest se vrátí o kus silnější (jednou, pak se rebound vynuluje).
	if float(w["rebound"]) > 0.0 and now >= float(w["numb_until"]):
		ac = clampf(ac + float(w["rebound"]) * (1.0 - ac), 0.0, 1.0)
		w["rebound"] = 0.0
		w["numb_n"] = 0
	w["acute"] = ac
	w["scar"] = float(w["scar"]) * exp(-dt * (1.0 + pr) / SCAR_TAU)
	w["t"] = now


## Akutní bolest, jak ji postava právě cítí (alkohol ji dočasně tlumí – proto je lákavý).
## Řetězení pití nepomáhá: každé další napití během otupení uleví o NUMB_TOLERANCE méně (tolerance),
## a rebound se sčítá – „zapít to“ natrvalo nejde (audit Gemini 21. 11., nález 2).
func felt(w: Dictionary, now: float) -> float:
	var a := float(w["acute"])
	if now < float(w["numb_until"]) and now >= float(w["numb_until"]) - NUMB_MIN - 1.0:
		var n := maxi(int(w.get("numb_n", 1)), 1)
		a *= minf(1.0, 0.5 + NUMB_TOLERANCE * float(n - 1))
	return a


func max_felt(now: float) -> float:
	var m := 0.0
	for w in wounds:
		m = maxf(m, felt(w, now))
	return m


func max_scar() -> float:
	var m := 0.0
	for w in wounds:
		m = maxf(m, float(w["scar"]))
	return m


## Bolest obrácená proti sobě (0..1): akutní bolest × síla vnitřního přesvědčení (i bez něj trochu).
func self_worth_hit(now: float) -> float:
	var m := 0.0
	for w in wounds:
		m = maxf(m, felt(w, now) * (0.3 + 0.7 * float(w["belief"])))
	return clampf(m, 0.0, 1.0)


func tick(now: float) -> void:
	if not is_finite(now):
		return
	var keep: Array = []
	for w in wounds:
		_settle(w, now)
		if float(w["acute"]) >= END or float(w["scar"]) >= END or float(w["rebound"]) > 0.0:
			keep.append(w)
	wounds = keep


func _evict_weakest(now: float) -> void:
	var worst := -1
	var wv := INF
	for i in wounds.size():
		_settle(wounds[i], now)
		var v := float(wounds[i]["acute"]) + float(wounds[i]["scar"])
		if v < wv or (v == wv and String(wounds[i]["about"]) < String(wounds[worst]["about"])):
			wv = v
			worst = i
	if worst >= 0:
		wounds.remove_at(worst)


# ------------------------------------------------------------------ události

## Spouštěč (vidět je spolu, slyšet o tom drb, potkat milence): rozdře ránu, nejvýš jednou za 6 h.
## Vrací true, pokud se bolest skutečně zvedla.
func on_reminder(who: String, amount: float, now: float) -> bool:
	if not is_finite(now):
		return false
	var hit := false
	for w in wounds:
		if String(w["about"]) != who and String(w["lover"]) != who:
			continue
		_settle(w, now)
		var lr := float(w["last_reminder"])
		if now - lr < REMINDER_GAP and lr <= now:
			continue
		w["last_reminder"] = now
		var a := _fin(amount, 0.0, 0.5, 0.0) * (1.0 - 0.6 * float(w["processed"]))
		w["acute"] = clampf(float(w["acute"]) + a * (1.0 - float(w["acute"])), 0.0, 1.0)
		hit = hit or a > 0.0
	return hit


## Opora: svěření (0,5), deník (0,25), terapie (1,0). Zpracování roste s klesajícím výnosem; akutní bolest
## trochu povolí hned. `exclude` = komu se svěřuje (svěřit se právě tomu, kdo zradil, zpracování nepočítá).
func on_support(strength: float, now: float, exclude: String = "") -> bool:
	var s := _fin(strength, 0.0, 1.0, 0.0)
	if s <= 0.0 or wounds.is_empty() or not is_finite(now):
		return false
	var any := false
	for w in wounds:
		if exclude != "" and (String(w["about"]) == exclude or String(w["lover"]) == exclude):
			continue
		_settle(w, now)
		w["processed"] = clampf(float(w["processed"]) + 0.18 * s * (1.0 - float(w["processed"])), 0.0, 1.0)
		w["acute"] = float(w["acute"]) * (1.0 - 0.12 * s)
		any = true
	return any


## Přijatá omluva od toho, kdo zradil: zpracování hodně, jizva trochu (odpuštění neznamená zapomenout).
## Částečně přijatá omluva (partial) zhruba poloviční účinek.
func on_repair(who: String, accepted: bool, now: float) -> bool:
	var w := find(who)
	if w.is_empty() or not is_finite(now):
		return false
	_settle(w, now)
	var f := 1.0 if accepted else 0.45
	w["processed"] = clampf(float(w["processed"]) + 0.3 * f * (1.0 - float(w["processed"])), 0.0, 1.0)
	w["acute"] = float(w["acute"]) * (1.0 - 0.25 * f)
	w["scar"] = float(w["scar"]) * (1.0 - 0.1 * f)
	return true


## Alkohol při akutní bolesti: 3 h otupení, potom návrat bolesti (rebound). Jen pokud je co otupit.
func on_numb(now: float) -> bool:
	if not is_finite(now):
		return false
	var any := false
	for w in wounds:
		_settle(w, now)
		if float(w["acute"]) < 0.15:
			continue
		var still := now < float(w["numb_until"]) and now >= float(w["numb_until"]) - NUMB_MIN - 1.0
		w["numb_n"] = mini(int(w.get("numb_n", 0)) + 1, 10) if still else 1
		w["numb_until"] = now + NUMB_MIN
		w["rebound"] = clampf(float(w["rebound"]) + REBOUND, 0.0, 0.3)
		any = true
	return any


## Rušivá otázka pro vnitřní proud (nejvýš 1× za hodinu, jen při akutní bolesti > 0,3). Vrací
## {"text", "about", "self_blame"} nebo {}. Deterministická volba věty (hash), žádná náhoda.
func intrusive_thought(now: float, idle: bool, k: float) -> Dictionary:
	if k <= 0.0 or not is_finite(now):
		return {}
	var best := {}
	for w in wounds:
		if felt(w, now) > 0.3 and (best.is_empty() or felt(w, now) > felt(best, now)):
			best = w
	if best.is_empty():
		return {}
	var lt := float(best["last_thought"])
	if now - lt < THOUGHT_GAP and lt <= now:
		return {}
	# V rozptýlení se otázky vtírají méně: jen při silné bolesti.
	if not idle and felt(best, now) < 0.6:
		return {}
	best["last_thought"] = now
	var h := absi(hash(String(best["about"]) + str(int(now / 60.0))))
	var blame := float(best["belief"]) >= 0.35 and h % 3 == 0
	var pool: Array = SELF_BLAME if blame else INTRUSIVE
	var txt := String(pool[h % pool.size()])
	var nm := String(best["name"]).split(" ")[0] if String(best["name"]) != "" else "někdo"
	var lv := String(best["lover_name"]).split(" ")[0] if String(best["lover_name"]) != "" else "tím druhým"
	return {"text": txt.replace("{name}", nm).replace("{lover}", lv), "about": String(best["about"]), "self_blame": blame}


func healing_thought(now: float) -> String:
	return String(HEALING[absi(hash(str(int(now / 60.0)) + str(wounds.size()))) % HEALING.size()])


# ------------------------------------------------------------------ vliv na chování (omezené násobiče)

## Chuť na akci. Stažení: méně běžného sociálního kontaktu; víc chuti svěřit se, psát deník, jít ven;
## nezdravý coping (pití, doomscroll, schovat se) lákavější; jizva tlumí flirt a pozvání na rande.
func action_weight(act: Dictionary, k: float, now: float) -> float:
	if k <= 0.0 or wounds.is_empty():
		return 1.0
	var a := max_felt(now) * k
	var s := max_scar() * k
	var unproc := 1.0
	for w in wounds:
		unproc = minf(unproc, 1.0 - float(w["processed"]))
	var id := String(act.get("id", ""))
	var tags: Array = act.get("tags", [])
	var m := 1.0
	match id:
		"confide":
			m *= 1.0 + 0.6 * a
		"journal", "go_walk":
			m *= 1.0 + 0.3 * a
		"seek_help":
			m *= 1.0 + 0.6 * a * unproc
		"drink":
			m *= 1.0 + 0.35 * a
		"doomscroll", "hide":
			m *= 1.0 + 0.3 * a
		"flirt", "ask_out", "secret_date", "intimacy_offer":
			m *= 1.0 - 0.5 * maxf(s, a)
		_:
			if tags.has("social"):
				m *= 1.0 - 0.3 * a
	return clampf(m, 0.4, 2.0)


## Výběr člověka: toho, kdo zradil, a jeho milence se postava straní (povídat si, svěřovat se).
func target_weight(who_uid: String, act: Dictionary, k: float, now: float) -> float:
	if k <= 0.0 or who_uid == "" or wounds.is_empty():
		return 1.0
	var id := String(act.get("id", ""))
	if not (id in ["chat", "confide", "text_friend"] or (act.get("tags", []) as Array).has("social")):
		return 1.0
	var w := 1.0
	for wd in wounds:
		var a := felt(wd, now) * k
		if String(wd["about"]) == who_uid:
			w *= 1.0 - (0.8 if id == "confide" else 0.55) * a
		elif String(wd["lover"]) == who_uid:
			w *= 1.0 - 0.7 * a
	return clampf(w, 0.1, 1.0)


## Hypervigilance: podezření v (dalším) vztahu roste rychleji. Jen pro přírůstky podezření, ne důkazů.
func suspicion_mult(k: float) -> float:
	return 1.0 + 0.6 * max_scar() * clampf(k, 0.0, 1.0)


## Bariéra autonomní akce „vyhledat pomoc“: silná, nezpracovaná bolest.
func help_need(now: float) -> float:
	var m := 0.0
	for w in wounds:
		m = maxf(m, (felt(w, now) - 0.55) * 1.4 * (1.0 - float(w["processed"])))
	return clampf(m, 0.0, 1.0)


func sleep_quality_mult(k: float, now: float) -> float:
	return 1.0 - 0.12 * max_felt(now) * clampf(k, 0.0, 1.0)


## Moodlety (bez čísel v UI; síla jen pro výpočet nálady).
func mood_entries(k: float, now: float) -> Array:
	var out: Array = []
	if k <= 0.0:
		return out
	var a := max_felt(now)
	if a > 0.25:
		out.append({"id": "bw_zrada", "label": "Zrada pořád bolí", "emotion": "smutny",
			"strength": -lerpf(3.0, 10.0, clampf((a - 0.25) / 0.75, 0.0, 1.0)) * k, "remaining": -1.0})
	var sw := self_worth_hit(now)
	if sw > 0.35:
		out.append({"id": "bw_sebehodnota", "label": "Jako by chyba byla ve mně", "emotion": "smutny",
			"strength": -lerpf(2.0, 6.0, clampf((sw - 0.35) / 0.65, 0.0, 1.0)) * k, "remaining": -1.0})
	return out


## Soukromé věty pro vlastníka (slova, žádná čísla ani diagnózy).
func private_lines(k: float, now: float) -> PackedStringArray:
	var out := PackedStringArray()
	if k <= 0.0:
		return out
	var best := {}
	for w in wounds:
		if best.is_empty() or felt(w, now) > felt(best, now):
			best = w
	if best.is_empty():
		return out
	var nm := String(best["name"]).split(" ")[0]
	var a := felt(best, now)
	if a > 0.25:
		out.append("Zrada (%s) pořád bolí: vracejí se otázky a obrazy. Pomáhá svěřit se někomu blízkému, čas, případně terapie." % nm)
		if now < float(best["numb_until"]):
			out.append("Pití bolest jen na chvíli otupí – pak se vrací.")
	if self_worth_hit(now) > 0.35:
		out.append("Bolest se obrací proti sobě, jako by chyba byla ve mně. Tak se to cítí – neznamená to, že je to pravda.")
	if a <= 0.25 and max_scar() > 0.3:
		out.append("Po zradě se těžko znovu důvěřuje; podezření přichází snadněji než dřív.")
	if float(best["processed"]) > 0.6:
		out.append("Je to zpracovanější – jizva zůstává, ale už neřídí každý den.")
	return out


# ------------------------------------------------------------------ uložení

const W_KEYS := ["about", "name", "lover", "lover_name", "since", "t", "acute", "scar", "processed", "belief",
	"numb_until", "numb_n", "rebound", "last_reminder", "last_thought", "count"]


func to_dict() -> Dictionary:
	return {"wounds": wounds.duplicate(true)}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 2:
		return false
	for key in d:
		if key != "wounds":
			return false
	var ws = d.get("wounds", [])
	if typeof(ws) != TYPE_ARRAY or ws.size() > MAX_WOUNDS:
		return false
	for w in ws:
		if typeof(w) != TYPE_DICTIONARY or w.size() > W_KEYS.size():
			return false
		for key in w:
			if not W_KEYS.has(key):
				return false
		if not _valid_key(w.get("about")):
			return false
		for sk in ["name", "lover", "lover_name"]:
			if typeof(w.get(sk, "")) != TYPE_STRING or String(w.get(sk, "")).length() > MAX_NAME:
				return false
		for fk in ["acute", "scar", "processed", "belief"]:
			var v = w.get(fk, 0.0)
			if typeof(v) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(v)) or float(v) < 0.0 or float(v) > 1.0:
				return false
		var rb = w.get("rebound", 0.0)
		if typeof(rb) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(rb)) or float(rb) < 0.0 or float(rb) > 0.3:
			return false
		for tk in ["since", "t", "numb_until", "last_reminder", "last_thought"]:
			var tv = w.get(tk, 0.0)
			if typeof(tv) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(tv)) or absf(float(tv)) > 1.0e13:
				return false
		var c = w.get("count", 1)
		if typeof(c) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(c)) or float(c) < 0.0 or float(c) > 99.0:
			return false
		var nn = w.get("numb_n", 0)
		if typeof(nn) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(nn)) or float(nn) < 0.0 or float(nn) > 10.0:
			return false
	return true


func from_dict(d: Variant) -> bool:
	if not validate_snapshot(d):
		return false
	wounds = []
	var seen := {}
	for w in d.get("wounds", []):
		var about := String(w["about"])
		if seen.has(about):
			continue  # duplicitní rána téhož člověka se zahodí (deterministicky první vyhrává)
		seen[about] = true
		var lover := String(w.get("lover", ""))
		if lover == about:
			lover = ""
		wounds.append({"about": about, "name": String(w.get("name", "")), "lover": lover,
			"lover_name": String(w.get("lover_name", "")) if lover != "" else "",
			"since": float(w.get("since", 0.0)), "t": float(w.get("t", 0.0)),
			"acute": float(w.get("acute", 0.0)), "scar": float(w.get("scar", 0.0)),
			"processed": float(w.get("processed", 0.0)), "belief": float(w.get("belief", 0.0)),
			"numb_until": float(w.get("numb_until", -1.0e12)), "numb_n": int(w.get("numb_n", 0)), "rebound": float(w.get("rebound", 0.0)),
			"last_reminder": float(w.get("last_reminder", -1.0e12)), "last_thought": float(w.get("last_thought", -1.0e12)),
			"count": int(w.get("count", 1))})
	return true
