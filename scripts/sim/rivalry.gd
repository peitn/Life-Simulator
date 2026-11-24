extends RefCounted
## Rivalry – soupeření, pomluvy jako zbraň a cesta ven ze soupeření.
##
## Proč: život není jen láska a hádky doma. Lidi soupeří – o stejného člověka, o postavení ve skupině –
## a někdy na to jdou špinavě: pomluvou, která má soka ztopit u ostatních. Pomluva ale není kouzlo:
## posluchač má vlastní hlavu (poctivost = hranice, vztah k oběti = podpora, důvěra v oběť = protidůkaz)
## a může to prokouknout – a donést to oběti. Pak se rivalita vrací jako bumerang. Hra za pomlouvání nic
## neodměňuje; dá se z toho i vystoupit („zakopat válečnou sekeru“).
##
## Model (jen autorita, uvnitř HouseholdDynamics; žádná náhoda zde – hody dodává volající):
## - RIVALITA je SMĚROVANÁ: "A>B" = A vnímá B jako soka (B o tom nemusí vůbec vědět). Dvě arény se
##   samostatným vyhasínáním: love (soupeření o stejného člověka, τ 14 dní – dokud soupeření trvá, denní sken
##   ho přiživuje) a status (hádky při špatném vztahu, odhalená pomluva, τ 21 dní). Celková intenzita
##   heat = 1 − (1 − love)(1 − status). Respekt 0..1 (po usmíření) tlumí další přírůstky.
## - POMLUVA: autor A řekne posluchači L něco na svého nejsilnějšího soka B (vybírá server, ne klient).
##   Samotný drb jde přes GossipNetwork (zbraň z pravdy, nebo výmysl s původcem A), reakci posluchače počítá
##   RivalryPressure.resolve_pressure → "swayed" / "doubted" / "saw_through".
## - USMÍŘENÍ: A nabídne B „zakopat válečnou sekeru“; úspěch tlumí rivalitu OBOU směrů a přidá respekt,
##   odmítnutí nastaví odstup (žádné dotírání).
##
## Data jsou soukromá (kdo koho bere jako soka): nereplikují se, vlastník je vidí jen v soukromých
## řádcích HUD bez čísel.

const RivalryPressure := preload("res://scripts/sim/rivalry_pressure.gd")
const Romance := preload("res://scripts/sim/romance.gd")

const VERSION := 1
const ARENAS := ["love", "status"]
const TAU := {"love": 20160.0, "status": 30240.0}   # 14 / 21 dní
const RIVAL_MIN := 0.25        # od kdy je to „sok“ (HUD, usmíření, pomluva)
const SLANDER_MIN := 0.35      # od kdy AI sáhne po pomluvě
const SLANDER_GAP := 120.0     # jeden autor pomlouvá nejvýš jednou za 2 h (i hráč – server)
const SLANDER_REPEAT := 1440.0 # stejnému posluchači o stejném sokovi nejvýš jednou denně
const HATCHET_GAP := 2880.0    # po odmítnutém usmíření 2 dny klid
const AI_SLANDER_EVERY := 1440.0
const AI_HATCHET_EVERY := 4320.0
## Přírůstky.
const LOVE_DAILY := 0.08       # × zájem 0..1, jednou denně, dokud soupeření trvá
const LOVE_INTEREST_REL := 45.0
const LOVE_INTEREST_SPARK := 0.3
const CONFLICT_GAIN := 0.06    # hádka při vztahu pod CONFLICT_REL
const CONFLICT_REL := 10.0
const LOVER_REVEALED := 0.5    # zrazený → milenec/milenka partnera
const SLANDER_EXPOSED := 0.4   # oběť → odhalený pomlouvač
const SLANDER_SELF := 0.05     # kdo pomlouvá, rivalitu v sobě živí
## Usmíření.
const HATCHET_DAMP := 0.35
const HATCHET_RESPECT := 0.3
## Napětí z blízkosti soka.
const NEAR := 8.0
const NEAR_PAUSE := 360.0
const NEAR_MIN := 0.4
## Limity (hostile save / server).
const MAX_RIVALS := 256
const MAX_TOLD := 256
const MAX_AI := 256
const MAX_NAME := 64
const T_MIN := -1.0e9
const T_MAX := 1.0e12
const SLANDER_OUTCOMES := ["swayed", "doubted", "saw_through"]
const HATCHET_OUTCOMES := ["accepted", "refused"]
const STAT_KEYS := ["love_scans", "love_feeds", "conflicts", "lovers_revealed", "slanders", "swayed", "doubted",
	"saw_through", "reported", "exposed", "hatchet", "accepted", "refused", "near"]

var rivals := {}   # "A>B" -> {"love", "status", "t", "respect", "last_slander", "last_hatchet"}
var told := {}     # "A>L>B" -> čas poslední pomluvy posluchači L o B
var _last_ai := {} # jméno -> {"slander": t, "hatchet": t}
var _near := {}    # "A>B" -> čas posledního napětí z blízkosti
var _last_scan := -1.0e12
var _last_gc := -1.0e12
var stats := {}
## Poslední načtení: "" = v pořádku / prázdné, jinak důvod zahození celé sekce ("future_version", "type").
var load_note := ""


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {}
	for k in STAT_KEYS:
		stats[k] = 0


static func key(a: String, b: String) -> String:
	return a + ">" + b


static func _valid_name(n) -> bool:
	return typeof(n) == TYPE_STRING and String(n) != "" and String(n).length() <= MAX_NAME \
		and not String(n).contains(">") and not String(n).contains("|")


static func _fin(v, lo: float, hi: float, dflt: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dflt
	var f := float(v)
	if not is_finite(f):
		return dflt
	return clampf(f, lo, hi)


static func _decay(v: float, t0: float, now: float, tau: float) -> float:
	# Zpětný chod času (rewind) nic nevrací ani nezesiluje: dt <= 0 = beze změny.
	var dt := now - t0
	if dt <= 0.0:
		return v
	return v * exp(-dt / tau)


# ------------------------------------------------------------------ stav

func arena(a: String, b: String, which: String, now: float) -> float:
	var r: Dictionary = rivals.get(key(a, b), {})
	if r.is_empty() or not which in ARENAS:
		return 0.0
	return _decay(float(r[which]), float(r["t"]), now, float(TAU[which]))


## Celková intenzita rivality A vůči B (0..1).
func heat(a: String, b: String, now: float) -> float:
	var r: Dictionary = rivals.get(key(a, b), {})
	if r.is_empty():
		return 0.0
	return clampf(1.0 - (1.0 - arena(a, b, "love", now)) * (1.0 - arena(a, b, "status", now)), 0.0, 1.0)


func respect(a: String, b: String) -> float:
	return float(rivals.get(key(a, b), {}).get("respect", 0.0))


## Hlavní aréna rivality A vůči B ("love" / "status" / "" když žádná).
func main_arena(a: String, b: String, now: float) -> String:
	var l := arena(a, b, "love", now)
	var s := arena(a, b, "status", now)
	if l <= 0.0 and s <= 0.0:
		return ""
	return "love" if l >= s else "status"


## Přidá rivalitu A vůči B v aréně (skládání s klesajícím výnosem; respekt přírůstky tlumí).
func feel(a: String, b: String, which: String, amount: float, now: float) -> float:
	if not _valid_name(a) or not _valid_name(b) or a == b or not which in ARENAS or not is_finite(now):
		return 0.0
	var amt := clampf(amount if is_finite(amount) else 0.0, 0.0, 1.0)
	if amt <= 0.0:
		return heat(a, b, now)
	var k := key(a, b)
	if not rivals.has(k):
		if rivals.size() >= MAX_RIVALS:
			_gc(now)
			if rivals.size() >= MAX_RIVALS:
				_evict_weakest(now)
		rivals[k] = {"love": 0.0, "status": 0.0, "t": now, "respect": 0.0, "last_slander": -1.0e9, "last_hatchet": -1.0e9}
	var r: Dictionary = rivals[k]
	# Nejdřív obě arény k času `now` (sdílený čas t), pak přírůstek.
	var l := arena(a, b, "love", now)
	var s := arena(a, b, "status", now)
	amt *= 1.0 - 0.6 * clampf(float(r["respect"]), 0.0, 1.0)
	if which == "love":
		l = clampf(l + amt * (1.0 - l), 0.0, 1.0)
	else:
		s = clampf(s + amt * (1.0 - s), 0.0, 1.0)
	r["love"] = l
	r["status"] = s
	r["t"] = maxf(float(r["t"]), now)
	return heat(a, b, now)


## Nejsilnější sok postavy A (heat >= RIVAL_MIN), kromě `exclude`. Shoda → abecedně (deterministicky).
func top_rival(a: String, now: float, exclude := "") -> String:
	var best := ""
	var best_h := RIVAL_MIN
	var prefix := a + ">"
	# O(n) bez řazení; shoda síly → abecedně menší jméno (deterministicky na všech strojích).
	for k in rivals.keys():
		if not String(k).begins_with(prefix):
			continue
		var b := String(k).substr(prefix.length())
		if b == exclude:
			continue
		var h := heat(a, b, now)
		if h < RIVAL_MIN:
			continue
		if best == "" or h > best_h or (h == best_h and b < best):
			best_h = h
			best = b
	return best


## Seznam soků postavy A seřazený od nejsilnějšího: [{"name", "heat", "arena"}].
func rivals_of(a: String, now: float, min_heat := RIVAL_MIN) -> Array:
	var out: Array = []
	var prefix := a + ">"
	for k in rivals.keys():
		if not String(k).begins_with(prefix):
			continue
		var b := String(k).substr(prefix.length())
		var h := heat(a, b, now)
		if h >= min_heat:
			out.append({"name": b, "heat": h, "arena": main_arena(a, b, now)})
	out.sort_custom(func(x, y): return float(x["heat"]) > float(y["heat"]) or (float(x["heat"]) == float(y["heat"]) and String(x["name"]) < String(y["name"])))
	return out


# ------------------------------------------------------------------ zdroje rivality

## Hádka mezi A a B: při špatném vztahu (rel < CONFLICT_REL) to živí rivalitu „o postavení“.
func on_conflict(a: String, b: String, rel_ab: float, rel_ba: float, now: float) -> void:
	if rel_ab < CONFLICT_REL:
		feel(a, b, "status", CONFLICT_GAIN, now)
	if rel_ba < CONFLICT_REL:
		feel(b, a, "status", CONFLICT_GAIN, now)
	stats["conflicts"] += 1


## Zrazený `p` se dozvěděl o milenci/milence `lover` svého partnera: soupeř v lásce.
func on_lover_revealed(p: String, lover: String, now: float) -> void:
	if p == "" or lover == "" or p == lover:
		return
	feel(p, lover, "love", LOVER_REVEALED, now)
	stats["lovers_revealed"] += 1


## Oběť `victim` zjistila, že ji `slanderer` pomlouval: rivalita oplátkou.
func on_slander_exposed(victim: String, slanderer: String, now: float) -> void:
	if victim == "" or slanderer == "" or victim == slanderer:
		return
	feel(victim, slanderer, "status", SLANDER_EXPOSED, now)
	stats["exposed"] += 1


## Zájem 0..1 postavy `a` o člověka `c`: vztah nad LOVE_INTEREST_REL nebo jiskra (Infidelity).
static func love_interest(rel_ac: float, spark_ac: float) -> float:
	var by_rel := clampf((rel_ac - LOVE_INTEREST_REL) / (100.0 - LOVE_INTEREST_REL), 0.0, 1.0) if rel_ac >= LOVE_INTEREST_REL else 0.0
	var by_spark := clampf((spark_ac - LOVE_INTEREST_SPARK) / (1.0 - LOVE_INTEREST_SPARK), 0.0, 1.0) if spark_ac >= LOVE_INTEREST_SPARK else 0.0
	var v := maxf(by_rel, by_spark)
	return clampf(0.35 + 0.65 * v, 0.0, 1.0) if (rel_ac >= LOVE_INTEREST_REL or spark_ac >= LOVE_INTEREST_SPARK) else 0.0


## Jednou denně: kdo má zájem o člověka, který chodí s někým jiným, bere toho „někoho“ jako soka.
## sims = živé postavy (autorita); ro = Romance; inf = Infidelity (jiskry) nebo null.
## Jen dospělí, jen kde přitažlivost sedí (aromantik nesoupeří), nikdy vlastní partner/ka.
func love_scan(sims: Array, ro, inf, now: float) -> int:
	if ro == null or (now - _last_scan < 1440.0 and _last_scan <= now):
		return 0
	_last_scan = now
	stats["love_scans"] += 1
	var fed := 0
	var by_name := {}
	var names: Array = []
	for s in sims:
		if s == null or not is_instance_valid(s) or not s.has_method("romance_profile"):
			continue
		var n := String(s.sim_name)
		if not _valid_name(n):
			continue
		by_name[n] = s
		names.append(n)
	names.sort()
	for a in names:
		var sa = by_name[a]
		var pa: Dictionary = sa.romance_profile()
		if int(pa.get("age", 0)) < 18 or bool(pa.get("aromantic", false)):
			continue
		var mine: String = ro.partner_of(a)
		for c in names:
			if c == a or c == mine:
				continue
			var b: String = ro.partner_of(c)
			if b == "" or b == a or not by_name.has(b):
				continue
			var sc = by_name[c]
			var pc: Dictionary = sc.romance_profile()
			if int(pc.get("age", 0)) < 18 or not Romance.fits(pc, pa):
				continue  # Romance.fits(pc, pa): přitahuje `a` člověk jako `c`?
			var rel_ac := float(sa.relationships.get(c, 0.0))
			var sp: float = inf.spark(a, c, now) if inf != null else 0.0
			var interest := love_interest(rel_ac, sp)
			if interest <= 0.0:
				continue
			feel(a, b, "love", LOVE_DAILY * interest, now)
			fed += 1
	stats["love_feeds"] += fed
	return fed


# ------------------------------------------------------------------ pomluva

## Smí `a` pomlouvat svého soka před `listener`? Vrací {"block": "" | důvod, "rival": jméno}.
## Důvody: "self" (sám sobě / neplatné), "no_rival", "not_now" (autorův odstup), "repeat" (tomuto
## posluchači o tomto sokovi už dnes).
func slander_block(a: String, listener: String, now: float) -> Dictionary:
	if not _valid_name(a) or not _valid_name(listener) or a == listener:
		return {"block": "self", "rival": ""}
	var rival := top_rival(a, now, listener)
	if rival == "":
		return {"block": "no_rival", "rival": ""}
	var last := -1.0e12
	var prefix := a + ">"
	for k in rivals.keys():
		if String(k).begins_with(prefix):
			last = maxf(last, float(rivals[k].get("last_slander", -1.0e9)))
	if now - last < SLANDER_GAP and last <= now:
		return {"block": "not_now", "rival": rival}
	var t := float(told.get(a + ">" + listener + ">" + rival, -1.0e12))
	if now - t < SLANDER_REPEAT and t <= now:
		return {"block": "repeat", "rival": rival}
	return {"block": "", "rival": rival}


## Vstupy obrany posluchače (0..1) z běžných čísel hry. rel_* -100..100, trust 0..100, honesty 0..1.
static func listener_inputs(rel_listener_teller: float, rel_listener_rival: float, trust_listener_rival: float,
		listener_honesty: float) -> Dictionary:
	var trust_t := clampf(0.5 + _fin(rel_listener_teller, -100.0, 100.0, 0.0) / 200.0, 0.1, 1.0)
	var plaus := clampf(1.0 - _fin(rel_listener_rival, -100.0, 100.0, 0.0) / 200.0, 0.3, 1.2)
	return {
		"credibility": clampf(trust_t * plaus, 0.0, 1.0),
		"boundaries": clampf(_fin(listener_honesty, 0.0, 1.0, 0.5), 0.0, 1.0),
		"support": clampf(_fin(rel_listener_rival, -100.0, 100.0, 0.0) / 100.0, 0.0, 1.0),
		"evidence": clampf((_fin(trust_listener_rival, 0.0, 100.0, 50.0) - 30.0) / 70.0, 0.0, 1.0),
	}


## Reakce posluchače na pomluvu: {"outcome", "attempt", "defense", "impact"}.
## saw_through = obrana zastavila víc než polovinu tlaku (prokoukl(a) to); swayed = dopad >= 0,25.
static func listener_reaction(heat_v: float, inputs: Dictionary) -> Dictionary:
	var res: Dictionary = RivalryPressure.resolve_pressure(heat_v, float(inputs.get("credibility", 0.0)),
		float(inputs.get("boundaries", 0.0)), float(inputs.get("support", 0.0)), float(inputs.get("evidence", 0.0)))
	var outcome := "doubted"
	if bool(res["resisted"]) or float(res["attempt"]) <= 0.0:
		outcome = "saw_through"
	elif float(res["impact"]) >= 0.25:
		outcome = "swayed"
	return {"outcome": outcome, "attempt": float(res["attempt"]), "defense": float(res["defense"]),
		"impact": float(res["impact"])}


## Šance, že posluchač, který pomluvu prokoukl, to řekne oběti: podpora oběti a poctivost.
static func report_p(inputs: Dictionary) -> float:
	return clampf(0.15 + 0.55 * float(inputs.get("support", 0.0)) + 0.25 * float(inputs.get("boundaries", 0.0)), 0.0, 0.95)


## Zapíše proběhlou pomluvu (volá autorita po vyhodnocení). Autor si tím rivalitu sám přiživuje.
func note_slander(a: String, listener: String, rival: String, outcome: String, now: float) -> void:
	if not outcome in SLANDER_OUTCOMES:
		return
	var k := key(a, rival)
	if rivals.has(k):
		rivals[k]["last_slander"] = now
	var tk := a + ">" + listener + ">" + rival
	if not told.has(tk) and told.size() >= MAX_TOLD:
		_prune_told(now)
	if told.size() < MAX_TOLD or told.has(tk):
		told[tk] = now
	feel(a, rival, "status", SLANDER_SELF, now)
	stats["slanders"] += 1
	stats[outcome] += 1


# ------------------------------------------------------------------ usmíření

## Smí `a` nabídnout `b` usmíření? "" = ano; "self" / "no_rivalry" (žádná rivalita ani jedním směrem) /
## "not_now" (po odmítnutí).
func hatchet_block(a: String, b: String, now: float) -> String:
	if not _valid_name(a) or not _valid_name(b) or a == b:
		return "self"
	if heat(a, b, now) < RIVAL_MIN and heat(b, a, now) < RIVAL_MIN:
		return "no_rivalry"
	for k in [key(a, b), key(b, a)]:
		var t := float(rivals.get(k, {}).get("last_hatchet", -1.0e12))
		if now - t < HATCHET_GAP and t <= now:
			return "not_now"
	return ""


## Šance, že `b` usmíření přijme. heat_ba = rivalita b vůči a, forgiveness_b (rys, -1..1), rel_ba,
## honesty_a 0..1 (upřímnost nabídky je znát).
static func hatchet_p(heat_ba: float, forgiveness_b: float, rel_ba: float, honesty_a: float) -> float:
	var p := 0.55 - 0.45 * clampf(heat_ba, 0.0, 1.0) + 0.25 * clampf(forgiveness_b, -1.0, 1.0) \
		+ clampf(rel_ba, -100.0, 100.0) / 400.0 + 0.15 * (clampf(honesty_a, 0.0, 1.0) - 0.5)
	return clampf(p, 0.05, 0.9)


func resolve_hatchet(a: String, b: String, p: float, roll: float, now: float) -> String:
	var block := hatchet_block(a, b, now)
	if block != "":
		return block
	stats["hatchet"] += 1
	var outcome := "accepted" if roll < clampf(p, 0.0, 1.0) else "refused"
	if outcome == "accepted":
		for pr in [[a, b], [b, a]]:
			var k := key(pr[0], pr[1])
			if not rivals.has(k):
				continue
			var r: Dictionary = rivals[k]
			r["love"] = arena(pr[0], pr[1], "love", now) * HATCHET_DAMP
			r["status"] = arena(pr[0], pr[1], "status", now) * HATCHET_DAMP
			r["t"] = maxf(float(r["t"]), now)
			r["respect"] = clampf(float(r["respect"]) + HATCHET_RESPECT, 0.0, 1.0)
	for k2 in [key(a, b), key(b, a)]:
		if rivals.has(k2):
			rivals[k2]["last_hatchet"] = now
	stats[outcome] += 1
	return outcome


# ------------------------------------------------------------------ AI

func note_ai(a: String, what: String, now: float) -> void:
	if not _last_ai.has(a):
		if _last_ai.size() >= MAX_AI or not _valid_name(a):
			return
		_last_ai[a] = {"slander": -1.0e12, "hatchet": -1.0e12}
	_last_ai[a][what] = now


func _ai_recent(a: String, what: String, every: float, now: float) -> bool:
	var t := float(_last_ai.get(a, {}).get(what, -1.0e12))
	return now - t < every and t <= now


## AI pomluva: jen nepoctivá postava (HEXACO poctivost < 0,5) se silným sokem; posluchač je pro ni
## „užitečný“, když má soka rád (pomluva má co zničit) a autora aspoň snese.
func ai_slander_score(sim, listener, base: float, now: float) -> float:
	var a := String(sim.sim_name)
	var l := String(listener.sim_name)
	if _ai_recent(a, "slander", AI_SLANDER_EVERY, now):
		return 0.0
	var sb := slander_block(a, l, now)
	if String(sb["block"]) != "":
		return 0.0
	var rival := String(sb["rival"])
	var h := heat(a, rival, now)
	if h < SLANDER_MIN:
		return 0.0
	var hon := float(sim.infidelity_profile("").get("honesty", 0.5)) if sim.has_method("infidelity_profile") else 0.5
	var temptation := clampf((0.5 - hon) * 2.2, 0.0, 1.0)
	if temptation <= 0.0:
		return 0.0
	temptation *= 1.0 - 0.7 * respect(a, rival)
	var rel_lt := float(listener.relationships.get(a, 0.0))
	if rel_lt < -20.0:
		return 0.0  # kdo autora nesnáší, tomu nic nevykládá
	var rel_lr := float(listener.relationships.get(rival, 0.0))
	var pref := clampf(1.0 + rel_lr / 100.0, 0.5, 2.0)
	return base * 6.0 * h * temptation * pref


## AI usmíření: smířlivější a poctivější postavy, když rivalita trvá a vztah není úplně rozbitý.
func ai_hatchet_score(sim, other, base: float, forgiveness: float, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	if _ai_recent(a, "hatchet", AI_HATCHET_EVERY, now) or hatchet_block(a, b, now) != "":
		return 0.0
	var h := maxf(heat(a, b, now), heat(b, a, now))
	var hon := float(sim.infidelity_profile("").get("honesty", 0.5)) if sim.has_method("infidelity_profile") else 0.5
	var will := clampf(0.1 + 0.6 * clampf(forgiveness, -1.0, 1.0) + 0.6 * (hon - 0.5), 0.0, 1.0)
	if will <= 0.05 or float(sim.relationships.get(b, 0.0)) < -60.0:
		return 0.0
	return base * 4.0 * h * will


## Váha běžného (nekonfliktního) kontaktu se sokem: lidi se sokům spíš vyhýbají (ne nulově).
func contact_weight(a: String, b: String, action_id: String, now: float) -> float:
	if action_id in ["slander_rival", "bury_hatchet"]:
		return 1.0
	var h := heat(a, b, now)
	if h < RIVAL_MIN:
		return 1.0
	return clampf(1.0 - 0.55 * h, 0.4, 1.0)


# ------------------------------------------------------------------ údržba a pohledy

## Krok domácnosti: denní sken soupeření v lásce, hodinové napětí z blízkosti soka, úklid.
func tick(sims: Array, ro, inf, now: float) -> void:
	love_scan(sims, ro, inf, now)
	_near_tension(sims, now)
	if now - _last_gc >= 1440.0 or now < _last_gc:
		_last_gc = now
		_gc(now)


## Sok poblíž (vzhůru, do NEAR metrů) = napětí: krátký moodlet, nejvýš jednou za NEAR_PAUSE na dvojici.
func _near_tension(sims: Array, now: float) -> void:
	if rivals.is_empty():
		return
	var by_name := {}
	for s in sims:
		if s != null and is_instance_valid(s) and s.has_method("command"):
			by_name[String(s.sim_name)] = s
	var ks: Array = rivals.keys()
	ks.sort()
	for k in ks:
		var parts: PackedStringArray = String(k).split(">")
		if parts.size() != 2 or not by_name.has(parts[0]) or not by_name.has(parts[1]):
			continue
		var h := heat(parts[0], parts[1], now)
		if h < NEAR_MIN:
			continue
		var last := float(_near.get(k, -1.0e12))
		if now - last < NEAR_PAUSE and last <= now:
			continue
		var sa = by_name[parts[0]]
		var sb = by_name[parts[1]]
		if sa._is_sleeping() or sb._is_sleeping() or sa.global_position.distance_to(sb.global_position) > NEAR:
			continue
		if _near.size() >= MAX_RIVALS and not _near.has(k):
			_near.clear()
		_near[k] = now
		sa.mood.add_moodlet("sok_" + String(sb.name), "Sok je nablízku: " + sb.first_name(), "nesvuj", -2.0 - 4.0 * h, 120.0)
		sa._detail_dirty = true
		stats["near"] += 1


func _gc(now: float) -> void:
	for k in rivals.keys():
		var parts: PackedStringArray = String(k).split(">")
		if parts.size() != 2:
			rivals.erase(k)
			continue
		var r: Dictionary = rivals[k]
		# Respekt a čerstvý odstup po usmíření jsou paměť – záznam zůstane, dokud mají význam.
		if heat(parts[0], parts[1], now) < 0.02 and float(r["respect"]) <= 0.0 \
				and now - float(r["last_hatchet"]) >= HATCHET_GAP:
			rivals.erase(k)
	_prune_told(now)
	for k in _near.keys():
		if now - float(_near[k]) >= NEAR_PAUSE or float(_near[k]) > now:
			_near.erase(k)


func _prune_told(now: float) -> void:
	for k in told.keys():
		if now - float(told[k]) >= SLANDER_REPEAT or float(told[k]) > now:
			told.erase(k)
	if told.size() >= MAX_TOLD:
		var ks: Array = told.keys()
		ks.sort_custom(func(x, y): return float(told[x]) < float(told[y]) or (float(told[x]) == float(told[y]) and str(x) < str(y)))
		told.erase(ks[0])


func _evict_weakest(now: float) -> void:
	var worst := ""
	var worst_v := INF
	var ks: Array = rivals.keys()
	ks.sort()
	for k in ks:
		var parts: PackedStringArray = String(k).split(">")
		if parts.size() != 2:
			worst = k
			break
		var v := heat(parts[0], parts[1], now)
		if v < worst_v:
			worst_v = v
			worst = k
	if worst != "":
		rivals.erase(worst)


## Soukromé věty pro vlastníka postavy (HUD; bez čísel). Nejvýš dva nejsilnější soci.
func private_lines(a: String, now: float) -> PackedStringArray:
	var out := PackedStringArray()
	for e in rivals_of(a, now):
		if out.size() >= 2:
			break
		var why := "kvůli lásce" if String(e["arena"]) == "love" else "o postavení"
		var strong := "Hořký sok" if float(e["heat"]) >= 0.6 else "Sok"
		out.append("%s: %s (%s)" % [strong, String(e["name"]).split(" ")[0], why])
	return out


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"version": VERSION, "rivals": rivals.duplicate(true), "told": told.duplicate(true),
		"last_ai": _last_ai.duplicate(true), "last_scan": _last_scan, "stats": stats.duplicate(true)}


## Striktní kontrola tvaru snapshotu (testy, nástroje, server): přesné klíče, typy, rozsahy, limity.
## Hra sama ukládá jen to, co projde; načítání (from_dict) je tolerantní a vadné záznamy zahazuje.
static func validate_snapshot(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var top := ["version", "rivals", "told", "last_ai", "last_scan", "stats"]
	if d.size() != top.size():
		return false
	for k in d.keys():
		if typeof(k) != TYPE_STRING or not top.has(k):
			return false
	if typeof(d["version"]) != TYPE_INT or int(d["version"]) != VERSION:
		return false
	if typeof(d["rivals"]) != TYPE_DICTIONARY or d["rivals"].size() > MAX_RIVALS:
		return false
	var rk := ["love", "status", "t", "respect", "last_slander", "last_hatchet"]
	for k in d["rivals"].keys():
		if typeof(k) != TYPE_STRING:
			return false
		var parts: PackedStringArray = String(k).split(">")
		if parts.size() != 2 or not _valid_name(parts[0]) or not _valid_name(parts[1]) or parts[0] == parts[1]:
			return false
		var r = d["rivals"][k]
		if typeof(r) != TYPE_DICTIONARY or r.size() != rk.size():
			return false
		for f in r.keys():
			if typeof(f) != TYPE_STRING or not rk.has(f):
				return false
			if typeof(r[f]) != TYPE_FLOAT and typeof(r[f]) != TYPE_INT:
				return false
			var v := float(r[f])
			if not is_finite(v):
				return false
			if f in ["love", "status", "respect"] and (v < 0.0 or v > 1.0):
				return false
			if f in ["t", "last_slander", "last_hatchet"] and (v < T_MIN or v > T_MAX):
				return false
	if typeof(d["told"]) != TYPE_DICTIONARY or d["told"].size() > MAX_TOLD:
		return false
	for k in d["told"].keys():
		if typeof(k) != TYPE_STRING:
			return false
		var p3: PackedStringArray = String(k).split(">")
		if p3.size() != 3:
			return false
		for n in p3:
			if not _valid_name(n):
				return false
		var tv = d["told"][k]
		if (typeof(tv) != TYPE_FLOAT and typeof(tv) != TYPE_INT) or not is_finite(float(tv)) \
				or float(tv) < T_MIN or float(tv) > T_MAX:
			return false
	if typeof(d["last_ai"]) != TYPE_DICTIONARY or d["last_ai"].size() > MAX_AI:
		return false
	for n in d["last_ai"].keys():
		if not _valid_name(n) or typeof(d["last_ai"][n]) != TYPE_DICTIONARY or d["last_ai"][n].size() != 2:
			return false
		for f in d["last_ai"][n].keys():
			if not f in ["slander", "hatchet"]:
				return false
			var av = d["last_ai"][n][f]
			if (typeof(av) != TYPE_FLOAT and typeof(av) != TYPE_INT) or not is_finite(float(av)) \
					or float(av) < -1.0e12 or float(av) > T_MAX:
				return false
	var ls = d["last_scan"]
	if (typeof(ls) != TYPE_FLOAT and typeof(ls) != TYPE_INT) or not is_finite(float(ls)) \
			or float(ls) < -1.0e12 or float(ls) > T_MAX:
		return false
	if typeof(d["stats"]) != TYPE_DICTIONARY:
		return false
	for k in d["stats"].keys():
		if typeof(k) != TYPE_STRING or not STAT_KEYS.has(k):
			return false
		var sv = d["stats"][k]
		if (typeof(sv) != TYPE_FLOAT and typeof(sv) != TYPE_INT) or not is_finite(float(sv)) or float(sv) < 0.0:
			return false
	return true


## Obnova z uložené hry. Starý save bez sekce (nebo prázdný slovník) = žádná rivalita. Snapshot z BUDOUCÍ
## verze nelze bezpečně vyložit → zahodí se celý (load_note = "future_version"). Jinak tolerantně:
## vadné záznamy se tiše zahodí, nic nespadne, limity se nepřekročí.
func from_dict(d) -> void:
	rivals = {}
	told = {}
	_last_ai = {}
	_near = {}
	_last_scan = -1.0e12
	_last_gc = -1.0e12
	load_note = ""
	reset_stats()
	if typeof(d) != TYPE_DICTIONARY:
		load_note = "type"
		return
	if d.is_empty():
		return
	var ver := int(_fin(d.get("version"), -1.0, 1.0e6, -1.0))
	if ver > VERSION:
		load_note = "future_version"
		return
	if ver < 1:
		load_note = "legacy_unversioned"  # verze 0 / bez verze: žádný starší formát neexistoval → nic k migraci
		return
	var rv = d.get("rivals", {})
	if typeof(rv) == TYPE_DICTIONARY:
		var ks: Array = rv.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks:
			if rivals.size() >= MAX_RIVALS or typeof(k) != TYPE_STRING:
				continue
			var parts: PackedStringArray = String(k).split(">")
			if parts.size() != 2 or not _valid_name(parts[0]) or not _valid_name(parts[1]) or parts[0] == parts[1]:
				continue
			var r = rv[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			rivals[key(parts[0], parts[1])] = {"love": _fin(r.get("love"), 0.0, 1.0, 0.0),
				"status": _fin(r.get("status"), 0.0, 1.0, 0.0), "t": _fin(r.get("t"), T_MIN, T_MAX, 0.0),
				"respect": _fin(r.get("respect"), 0.0, 1.0, 0.0),
				"last_slander": _fin(r.get("last_slander"), T_MIN, T_MAX, -1.0e9),
				"last_hatchet": _fin(r.get("last_hatchet"), T_MIN, T_MAX, -1.0e9)}
	var tl = d.get("told", {})
	if typeof(tl) == TYPE_DICTIONARY:
		var ks2: Array = tl.keys()
		ks2.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks2:
			if told.size() >= MAX_TOLD or typeof(k) != TYPE_STRING:
				continue
			var p3: PackedStringArray = String(k).split(">")
			if p3.size() != 3 or not _valid_name(p3[0]) or not _valid_name(p3[1]) or not _valid_name(p3[2]):
				continue
			var tv := _fin(tl[k], T_MIN, T_MAX, NAN)
			if is_finite(tv):
				told[k] = tv
	var la = d.get("last_ai", {})
	if typeof(la) == TYPE_DICTIONARY:
		var ks3: Array = la.keys()
		ks3.sort_custom(func(x, y): return str(x) < str(y))
		for n in ks3:
			if _last_ai.size() >= MAX_AI or not _valid_name(n) or typeof(la[n]) != TYPE_DICTIONARY:
				continue
			_last_ai[n] = {"slander": _fin(la[n].get("slander"), -1.0e12, T_MAX, -1.0e12),
				"hatchet": _fin(la[n].get("hatchet"), -1.0e12, T_MAX, -1.0e12)}
	_last_scan = _fin(d.get("last_scan"), -1.0e12, T_MAX, -1.0e12)
	var st = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in STAT_KEYS:
			if st.has(k):
				stats[k] = int(_fin(st[k], 0.0, 1.0e9, 0.0))
