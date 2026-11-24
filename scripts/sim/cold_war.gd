extends RefCounted
## ColdWar – „dusno“ a „studená válka“ mezi dvěma lidmi pod jednou střechou.
##
## Proč: HouseholdDynamics drží domácnost v rovnováze průměrně, ale konkrétní DVOJICE se umí
## zaseknout ve spirále: hádka → křivda → další hádka. Skuteční lidé v ní nepokračují donekonečna
## stejně – začnou se vyhýbat, mluví spolu jen to nutné, v jedné místnosti je dusno a ostatní
## v domě to cítí. Ze spirály vedou tři cesty: vyříkat si to (může to i vybuchnout), čas
## (vychladne to) nebo drobné společné chvíle. Tenhle modul to modeluje jako stav dvojice.
##
## Stupně: 0 nic · 1 „dusno“ (napětí) · 2 „studená válka“ (vyhýbání).
##   * do 1: aspoň TENSE_ARGUES hádek v okně WINDOW,
##   * do 2: aspoň COLD_ARGUES hádek v okně, nebo dusno se „žárem“ ≥ COLD_HEAT,
##   * dolů (hystereze): žár pod EXIT_*_HEAT a málo čerstvých hádek.
## „Žár“ (heat 0..1) roste hádkami/urážkami/nátlakem, klesá časem a příjemnými rozhovory.
##
## Běží jen na autoritě (offline / server) uvnitř HouseholdDynamics. Žádná náhoda zde – výsledky
## „vyříkat si to“ dostávají hod zvenku (rng postavy) → deterministické podle seedu.
## Nic z toho není volba, kterou hra odměňuje: vyhýbání snižuje počet hádek, ale bere kontakt
## a nese napětí; vyříkat si to je riskantní; čekání je pomalé.

const Traits := preload("res://scripts/sim/traits.gd")

## Klouzavé okno počítání hádek (herní minuty) a nejvýš uložených časů na dvojici.
const WINDOW := 2880.0  # 48 h
const MAX_STAMPS := 8
## Přírůstky žáru podle druhu události (od kohokoli z dvojice ke druhému).
## "breakup" = rozchod dvojice, která spolu dál bydlí (Romance; jen žár, nepočítá se jako hádka).
const HEAT_GAIN := {"argue": 0.25, "insult": 0.35, "pressure": 0.12, "misunderstanding": 0.05, "breakup": 0.3,
	"betrayal": 0.55}
## Druhy nátlaku z SocialPressure (počítají se jako „pressure“).
const PRESSURE_KINDS := ["reproach", "guilt_trip", "blame_shift", "emotional_blackmail", "stonewalling"]
## Příjemný rozhovor žár ochladí; ve studené válce jen napůl (zdvořilé fráze, ne smír).
const HEAT_CHAT := 0.06
const TENSE_ARGUES := 2
const COLD_ARGUES := 3
const COLD_HEAT := 0.7
const EXIT_COLD_HEAT := 0.3
const EXIT_TENSE_HEAT := 0.2
## Časová konstanta chladnutí žáru podle stupně (studená válka „vydrží“ déle).
const HEAT_TAU := [1440.0, 4320.0, 8640.0]
## Kdy je ještě „ve stejné místnosti“ (m).
const NEAR := 9.0
## Napětí ve stejné místnosti za krok dynamiky (10 min) × (0,5 + 0,5 žáru).
const PAIR_STRESS := [0.0, 0.25, 0.5]
const PAIR_MOOD := [0.0, -3.0, -6.0]
const PAIR_MOOD_MINUTES := 60.0
## Atmosféra pro ostatní v domě (nezúčastnění, vzhůru, poblíž jednoho z dvojice).
const BYSTANDER_MOOD := -2.5
const BYSTANDER_MOOD_MINUTES := 90.0
const BYSTANDER_STRESS := 0.3
const BYSTANDER_COOLDOWN := 180.0
## Násobič chuti AI oslovit druhého z dvojice běžnou společenskou akcí.
const AVOID := [1.0, 0.6, 0.25]
## Akce, kterých se vyhýbání netýká (mají vlastní pravidla).
const AVOID_EXEMPT := ["apologize", "clear_air", "confront_gossip", "comfort_panic", "break_up", "confront_cheating"]
## Společná chvíle se při vysokém žáru nekoná („nebudu s ním/ní sedět na gauči“); jinak trochu ochladí.
const SHARED_BLOCK_HEAT := 0.5
const SHARED_COOL := 0.15
## „Vyříkat si to“: odstup pokusů v dvojici, útlum chuti AI hned po hádce, naléhavost.
const CLEAR_COOLDOWN := 360.0
const CLEAR_FRESH := 120.0
const CLEAR_URGENCY := 10.0
## První půlden studené války nikdo nechce udělat první krok (×CLEAR_FIRST_STEP_MULT).
const CLEAR_FIRST_STEP_DAYS := 0.5
const CLEAR_FIRST_STEP_MULT := 0.25
const CLEAR_TRUCE_SHARE := 0.55
## Opakované cykly „hádka → smíření“ v okně REPAIR_WINDOW berou smíření váhu: každý předchozí
## průlom/příměří sníží šanci na průlom o REPAIR_PENALTY (dolní mez zůstává 0,08 – cesta nikdy zavřená).
const REPAIR_WINDOW := 20160.0  # 14 dní
const REPAIR_PENALTY := 0.08
const MAX_REPAIRS := 6
## Limity uložených dat (hostile save / server).
const MAX_PAIRS := 256
const MAX_NAME := 64

var pairs := {}   # "A|B" (seřazeno) -> záznam
var _bystander := {}  # jméno -> čas posledního „dusna doma“
var stats := {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"entered_tense": 0, "entered_cold": 0, "thawed": 0, "breakthrough": 0, "truce": 0,
		"blowup": 0, "not_now": 0, "nothing": 0, "cold_minutes": 0.0}


static func key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _rec(a: String, b: String, create: bool) -> Dictionary:
	var k := key(a, b)
	if pairs.has(k):
		return pairs[k]
	if not create or a == b or pairs.size() >= MAX_PAIRS:
		return {}
	var r := {"stamps": [], "heat": 0.0, "stage": 0, "since": 0.0, "last_clear": -1.0e9, "last_argue": -1.0e9, "repairs": []}
	pairs[k] = r
	return r


func stage(a: String, b: String) -> int:
	return int(_rec(a, b, false).get("stage", 0))


func heat(a: String, b: String) -> float:
	return float(_rec(a, b, false).get("heat", 0.0))


## Počet hádek dvojice v okně WINDOW před `now`.
func recent_argues(a: String, b: String, now: float) -> int:
	var n := 0
	for t in _rec(a, b, false).get("stamps", []):
		if now - float(t) <= WINDOW and float(t) <= now:
			n += 1
	return n


## Událost mezi dvěma lidmi (z rozhovoru). kind = výsledek rozhovoru nebo druh nátlaku.
## Vrací nový stupeň dvojice.
func note(a: String, b: String, kind: String, now: float) -> int:
	if a == "" or b == "" or a == b:
		return 0
	var k := "pressure" if PRESSURE_KINDS.has(kind) else kind
	if k == "chat":
		var r0 := _rec(a, b, false)
		if r0.is_empty():
			return 0
		r0["heat"] = maxf(0.0, float(r0["heat"]) - HEAT_CHAT * (0.5 if int(r0["stage"]) == 2 else 1.0))
		return _update(r0, now)
	if not HEAT_GAIN.has(k):
		return stage(a, b)
	var r := _rec(a, b, true)
	if r.is_empty():
		return 0
	r["heat"] = minf(1.0, float(r["heat"]) + float(HEAT_GAIN[k]))
	if k == "argue" or k == "insult":
		var st: Array = r["stamps"]
		st.append(now)
		while st.size() > MAX_STAMPS:
			st.pop_front()
		r["last_argue"] = now
	return _update(r, now)


## Přepočet stupně (nahoru i dolů s hysterezí).
func _update(r: Dictionary, now: float) -> int:
	var n := 0
	for t in r["stamps"]:
		if now - float(t) <= WINDOW and float(t) <= now:
			n += 1
	var s0 := int(r["stage"])
	var s := s0
	var h := float(r["heat"])
	if s == 0 and n >= TENSE_ARGUES:
		s = 1
		r["since"] = now
		stats["entered_tense"] += 1
	# Přes žár jen z už existujícího dusna (eskalace po stupních); počtem hádek i rovnou.
	if s <= 1 and (n >= COLD_ARGUES or (s0 == 1 and h >= COLD_HEAT)):
		s = 2
		r["since"] = now
		stats["entered_cold"] += 1
	elif s == 2 and h < EXIT_COLD_HEAT and n < COLD_ARGUES:
		s = 1
		r["since"] = now
		stats["thawed"] += 1
	elif s == 1 and h < EXIT_TENSE_HEAT and n == 0:
		s = 0
		stats["thawed"] += 1
	r["stage"] = s
	return s


## Chladnutí v čase (volá se každým krokem dynamiky) + úklid prázdných záznamů.
func decay(dt: float, now: float) -> void:
	# A rewind must never turn exponential cooling into exponential heating.
	# Live timeline rewind policy (stage/cooldown) remains unresolved.
	if dt < 0.0:
		return
	for k in pairs.keys():
		var r: Dictionary = pairs[k]
		var s := int(r["stage"])
		r["heat"] = float(r["heat"]) * exp(-dt / float(HEAT_TAU[s]))
		var keep: Array = []
		for t in r["stamps"]:
			if now - float(t) <= WINDOW:
				keep.append(t)
		r["stamps"] = keep
		if s == 2:
			stats["cold_minutes"] = float(stats["cold_minutes"]) + dt
		_update(r, now)
		var rp_keep: Array = []
		for t in r.get("repairs", []):
			if now - float(t) <= REPAIR_WINDOW:
				rp_keep.append(t)
		r["repairs"] = rp_keep
		if int(r["stage"]) == 0 and float(r["heat"]) < 0.02 and keep.is_empty() and rp_keep.is_empty():
			pairs.erase(k)


## Násobič chuti `a` oslovit `b` běžnou společenskou akcí (vyhýbání). 1.0 = beze změny.
func avoid_weight(a: String, b: String, action_id: String) -> float:
	if AVOID_EXEMPT.has(action_id):
		return 1.0
	return float(AVOID[stage(a, b)])


func blocks_shared(a: String, b: String) -> bool:
	return stage(a, b) >= 1 and heat(a, b) > SHARED_BLOCK_HEAT


func on_shared(a: String, b: String, now: float) -> void:
	var r := _rec(a, b, false)
	if r.is_empty():
		return
	r["heat"] = maxf(0.0, float(r["heat"]) - SHARED_COOL)
	_update(r, now)


## Pravděpodobnost průlomu při „vyříkat si to“ (0,08..0,85). Vstupy: žár dvojice, odpouštění
## (Traits forgiveness, −1..1) toho, koho se to týká, i iniciátora, průměrný stres (0..100),
## průměrný vztah (−100..100), šance na de-eskalaci posluchače (0..1).
static func clear_air_p(h: float, forgive_target: float, forgive_self: float, stress_avg: float,
		rel_avg: float, deesc: float) -> float:
	var p := 0.30 + 0.30 * (1.0 - clampf(h, 0.0, 1.0))
	p += 0.12 * clampf(forgive_target, -1.0, 1.0) + 0.08 * clampf(forgive_self, -1.0, 1.0)
	p -= 0.25 * clampf(stress_avg / 100.0, 0.0, 1.0)
	p += clampf(rel_avg, -100.0, 100.0) / 400.0
	p += 0.15 * clampf(deesc, 0.0, 1.0)
	return clampf(p, 0.08, 0.85)


## Může `a` teď s `b` začít „vyříkat si to“? "" = ano, jinak "nothing" / "not_now".
func clear_air_block(a: String, b: String, now: float) -> String:
	var r := _rec(a, b, false)
	if r.is_empty() or int(r["stage"]) == 0:
		return "nothing"
	if now - float(r["last_clear"]) < CLEAR_COOLDOWN:
		return "not_now"
	return ""


## Výsledek pokusu „vyříkat si to“: "breakthrough" / "truce" / "blowup" (nebo blokace z
## clear_air_block). roll 0..1 dodá volající (rng postavy). Mění jen stav dvojice.
func resolve_clear_air(a: String, b: String, p: float, roll: float, now: float) -> String:
	var block := clear_air_block(a, b, now)
	if block != "":
		stats[block] += 1
		return block
	var r := _rec(a, b, false)
	r["last_clear"] = now
	p = clampf(p - REPAIR_PENALTY * float(recent_repairs(a, b, now)), 0.08, 0.85)
	var outcome := "blowup"
	if roll < p:
		outcome = "breakthrough"
	elif roll < p + (1.0 - p) * CLEAR_TRUCE_SHARE:
		outcome = "truce"
	match outcome:
		"breakthrough":
			r["stage"] = 0
			r["heat"] = 0.1
			r["stamps"] = []
		"truce":
			r["stage"] = 1
			r["since"] = now
			r["heat"] = float(r["heat"]) * 0.6
			var st: Array = r["stamps"]
			r["stamps"] = [st[st.size() - 1]] if not st.is_empty() else []
		"blowup":
			r["heat"] = 1.0
			var st2: Array = r["stamps"]
			st2.append(now)
			while st2.size() > MAX_STAMPS:
				st2.pop_front()
			r["last_argue"] = now
			if int(r["stage"]) < 2:
				r["stage"] = 2
				r["since"] = now
				stats["entered_cold"] += 1
	if outcome != "blowup":
		var rp: Array = r.get("repairs", [])
		rp.append(now)
		while rp.size() > MAX_REPAIRS:
			rp.pop_front()
		r["repairs"] = rp
	stats[outcome] += 1
	return outcome


## Kolik smíření (průlom/příměří) měla dvojice za posledních REPAIR_WINDOW minut.
func recent_repairs(a: String, b: String, now: float) -> int:
	var n := 0
	for t in _rec(a, b, false).get("repairs", []):
		if now - float(t) <= REPAIR_WINDOW and float(t) <= now:
			n += 1
	return n


## Chuť AI začít „vyříkat si to“ s `other`. base = obecné násobiče akce. 0 = nechce.
func ai_clear_air_score(sim, other, base: float, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	var r := _rec(a, b, false)
	if r.is_empty() or clear_air_block(a, b, now) != "":
		return 0.0
	var s := int(r["stage"])
	var h := float(r["heat"])
	if s == 1 and h < 0.5:
		return 0.0  # mírné dusno většinou přejde samo
	var days := clampf((now - float(r["since"])) / 1440.0, 0.0, 3.0)
	var sc := base * CLEAR_URGENCY * (0.5 + h) * (0.5 + 0.5 * days)
	sc *= Traits.mult_param(sim.trait_profile, "pride")
	if s == 2 and days < CLEAR_FIRST_STEP_DAYS:
		sc *= CLEAR_FIRST_STEP_MULT
	if now - float(r["last_argue"]) < CLEAR_FRESH:
		sc *= 0.1  # ještě to vře
	if sim.mental != null and float(sim.mental.stress) > 75.0:
		sc *= 0.3  # není na to kapacita
	return sc


## Jeden krok dynamiky domácnosti: chladnutí + napětí ve stejné místnosti + atmosféra pro ostatní.
## sims = živé postavy na autoritě. dt = krok v herních minutách.
func tick(sims: Array, now: float, dt: float) -> void:
	decay(dt, now)
	if pairs.is_empty():
		return
	var by_name := {}
	for s in sims:
		by_name[String(s.sim_name)] = s
	var tense_near: Array = []  # dvojice uzlů, které jsou spolu v napětí a blízko
	for k in pairs:
		var r: Dictionary = pairs[k]
		var st := int(r["stage"])
		if st == 0:
			continue
		var names: PackedStringArray = String(k).split("|")
		if names.size() != 2 or not by_name.has(names[0]) or not by_name.has(names[1]):
			continue
		var x = by_name[names[0]]
		var y = by_name[names[1]]
		if x._is_sleeping() or y._is_sleeping():
			continue
		if x.global_position.distance_to(y.global_position) >= NEAR:
			continue
		tense_near.append([x, y])
		var f := 0.5 + 0.5 * float(r["heat"])
		for pr in [[x, y], [y, x]]:
			var me = pr[0]
			var other = pr[1]
			me.mental.on_stressor("cold_war", float(PAIR_STRESS[st]) * f * Traits.mult_param(me.trait_profile, "stress_gain"), me.mental_cfg())
			var label := ("Dusno s: " if st == 1 else "Nemluvíme spolu: ") + String(other.first_name())
			me.mood.add_moodlet("dusno_" + String(other.name), label, "nesvuj" if st == 1 else "nastvany",
				float(PAIR_MOOD[st]) * f, PAIR_MOOD_MINUTES)
			me._detail_dirty = true
	if tense_near.is_empty():
		return
	for s in sims:
		if s._is_sleeping() or now - float(_bystander.get(String(s.sim_name), -1.0e9)) < BYSTANDER_COOLDOWN:
			continue
		for pr in tense_near:
			if s == pr[0] or s == pr[1]:
				continue
			if s.global_position.distance_to(pr[0].global_position) < NEAR or s.global_position.distance_to(pr[1].global_position) < NEAR:
				_bystander[String(s.sim_name)] = now
				s.mental.on_stressor("cold_war", BYSTANDER_STRESS, s.mental_cfg())
				s.mood.add_moodlet("dusno_doma", "Doma je dusno", "nesvuj", BYSTANDER_MOOD, BYSTANDER_MOOD_MINUTES)
				s._detail_dirty = true
				break


## Veřejný pohled pro HUD/testy: [{"a","b","stage","heat","days"}] seřazeno podle klíče.
func summary(now: float) -> Array:
	var out: Array = []
	var ks: Array = pairs.keys()
	ks.sort()
	for k in ks:
		var r: Dictionary = pairs[k]
		var names: PackedStringArray = String(k).split("|")
		out.append({"a": names[0], "b": names[1], "stage": int(r["stage"]), "heat": float(r["heat"]),
			"days": maxf(0.0, now - float(r["since"])) / 1440.0})
	return out


func to_dict() -> Dictionary:
	return {"pairs": pairs.duplicate(true), "bystander": _bystander.duplicate(true), "stats": stats.duplicate(true)}


static func _fin(v, lo: float, hi: float, dflt: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dflt
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return dflt
	return clampf(f, lo, hi)


static func _valid_name(n) -> bool:
	return typeof(n) == TYPE_STRING and String(n) != "" and String(n).length() <= MAX_NAME and not String(n).contains("|")


## Obnova z uložené hry. Cizí/poškozená data se tiše zahodí (nikdy nespadne, nikdy nepřekročí limity).
func from_dict(d) -> void:
	pairs = {}
	_bystander = {}
	reset_stats()
	if typeof(d) != TYPE_DICTIONARY:
		return
	var src = d.get("pairs", {})
	if typeof(src) == TYPE_DICTIONARY:
		for k in src:
			if pairs.size() >= MAX_PAIRS or typeof(k) != TYPE_STRING:
				continue
			var names: PackedStringArray = String(k).split("|")
			if names.size() != 2 or not _valid_name(names[0]) or not _valid_name(names[1]) or names[0] == names[1]:
				continue
			var r = src[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var stamps: Array = []
			if typeof(r.get("stamps")) == TYPE_ARRAY:
				for t in r["stamps"]:
					if stamps.size() < MAX_STAMPS and (typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_INT) and is_finite(float(t)):
						stamps.append(clampf(float(t), -1.0e9, 1.0e12))
			var repairs: Array = []
			if typeof(r.get("repairs")) == TYPE_ARRAY:
				for t in r["repairs"]:
					if repairs.size() < MAX_REPAIRS and (typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_INT) and is_finite(float(t)):
						repairs.append(clampf(float(t), -1.0e9, 1.0e12))
			pairs[key(names[0], names[1])] = {"stamps": stamps, "repairs": repairs,
				"heat": _fin(r.get("heat"), 0.0, 1.0, 0.0),
				"stage": int(_fin(r.get("stage"), 0.0, 2.0, 0.0)),
				"since": _fin(r.get("since"), -1.0e9, 1.0e12, 0.0),
				"last_clear": _fin(r.get("last_clear"), -1.0e9, 1.0e12, -1.0e9),
				"last_argue": _fin(r.get("last_argue"), -1.0e9, 1.0e12, -1.0e9)}
	var by = d.get("bystander", {})
	if typeof(by) == TYPE_DICTIONARY:
		for n in by:
			if _bystander.size() < MAX_PAIRS and _valid_name(n):
				_bystander[n] = _fin(by[n], -1.0e9, 1.0e12, -1.0e9)
	var st = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in stats:
			if st.has(k):
				stats[k] = _fin(st[k], 0.0, 1.0e12, 0.0) if k == "cold_minutes" else int(_fin(st[k], 0.0, 1.0e9, 0.0))
