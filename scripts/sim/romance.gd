extends RefCounted
## Romance – romantické vztahy dvojic: randění, vážný vztah, rozchod, „ex“.
##
## Proč: přitažlivost (CharacterData.identity.attracted_to, aromantic) a souhlas s intimitou už ve hře
## byly, ale žádný partnerský STAV. Skutečné vztahy mají průběh: někdo se odváží zeptat (a může dostat
## košem), chvíli spolu chodí, buď z toho je něco vážného, nebo spokojenost pomalu vyprchá – hádky,
## studená válka doma, zanedbávání – a jeden z nich to ukončí. Rozchod bolí podle toho, jak moc na
## tom komu záleželo, a pod jednou střechou po něm zůstává dusno a trapné chvíle s „ex“.
##
## Stavy dvojice: (žádný záznam) → "dating" → "partners" → "ex". Model je MONOGAMNÍ: kdo s někým
## je, nemůže začít jiný (veřejný) vztah. Nevěra – flirt, tajné schůzky, podezření a odhalení – žije
## zvlášť v scripts/sim/infidelity.gd a sem se promítá jen přes spokojenost (událost "betrayal").
##
## Spokojenost (0..1) má KAŽDÝ z dvojice zvlášť – vztah může jednomu vyhovovat a druhému ne.
##
## Běží jen na autoritě (offline / server) uvnitř HouseholdDynamics. Žádná náhoda zde – hody dodává
## volající (rng postavy) → deterministické podle seedu. Nic z toho hra neodměňuje body: rozchod není
## „správná volba“, randění není cíl ke splnění.
##
## Pravidla dospělosti a přitažlivosti: obě postavy musí být 18+ (hráčské postavy jsou vždy dospělé,
## tohle je pojistka pro poškozená data). Cíl s aromantic=true romantickou nabídku nepřijme. Pokud
## má cíl vyplněnou množinu romantické přitažlivosti, žadatel do ní musí patřit; NEUVEDENÁ skupina
## žadatele (gender_identity "neuvedeno") se nepovažuje za nesoulad – o datech, která nemáme, hra
## nerozhoduje. Prázdná množina přitažlivosti = neuvedeno (ne „nikdo“).

const STATUSES := ["dating", "partners", "ex"]
## Mapování gender_identity (CharacterSchema.GENDER_IDENTITY) na skupiny přitažlivosti (ATTRACTION).
const GROUP_OF := {"muz": "muzi", "zena": "zeny", "nebinarni": "nebinarni", "genderfluidni": "nebinarni",
	"agender": "nebinarni", "jine": "nebinarni", "neuvedeno": ""}

## Výchozí a „klidová“ spokojenost; časová konstanta návratu (min) bez nových událostí.
const SAT_START := 0.62
const SAT_BASE := 0.55
const SAT_TAU := 20160.0  # 14 dní
## Změny spokojenosti podle události mezi dvojicí: [pro iniciátora, pro druhého].
const SAT_EVENT := {
	"chat": [0.025, 0.025], "shared": [0.03, 0.03], "argue": [-0.05, -0.05],
	"insult": [-0.03, -0.12], "pressure": [-0.02, -0.08], "misunderstanding": [-0.01, -0.01],
	# Odhalená nevěra: [nevěrník, zrazený]. Křivě obviněný (bezdůvodná žárlivost): [obviňující, obviněný].
	"betrayal": [-0.06, -0.38], "false_accusation": [-0.02, -0.07],
	# Partner/ka viděl(a) flirt s někým jiným: [flirtující, svědek].
	"flirt_seen": [-0.01, -0.06],
}
const PRESSURE_KINDS := ["reproach", "guilt_trip", "blame_shift", "emotional_blackmail", "stonewalling"]
## Proti „farmení“ (Grok #548): příjemná událost se do spokojenosti počítá nejvýš jednou za
## POSITIVE_GAP minut a s klesajícím výnosem (× (1 − spokojenost) / (1 − SAT_BASE)); negativní vždy.
const POSITIVE_GAP := 120.0
## Úbytek za den podle stupně studené války (0/1/2) a za zanedbávání (bez kontaktu > NEGLECT_AFTER).
const SAT_COLD_WAR := [0.0, 0.012, 0.035]
const NEGLECT_AFTER := 2880.0
const SAT_NEGLECT := 0.02
## Nízká spokojenost: pod LOW začne „počítadlo“, nad LOW_EXIT se vynuluje.
const LOW := 0.3
const LOW_EXIT := 0.4
## Závazek roste s časem spolu (plný po 60 dnech), vážný vztah jej zrychlí.
const COMMIT_DAYS := 60.0
## Z randění vážný vztah: aspoň PARTNER_DAYS dní a obě spokojenosti ≥ PARTNER_SAT.
const PARTNER_DAYS := 14.0
const PARTNER_SAT := 0.6
## Pozvání: odstup po „ještě ne“ / „ne“, nové randění po rozchodu, okno pro „nedá si říct“.
const COOLDOWN_NOT_YET := 1440.0
const COOLDOWN_NO := 4320.0
const REDATE_AFTER := 10080.0  # 7 dní
const NO_WINDOW := 20160.0  # 14 dní
const PUSHY_NOES := 2
const NOT_YET_SHARE := 0.35
## AI: kdy vůbec uvažuje o pozvání / rozchodu.
const AI_ASK_REL := 45.0
const AI_ASK_TRUST := 50.0
const AI_ASK_EVERY := 4320.0  # jedna AI pozvánka na postavu za 3 dny
const AI_EX_PAUSE := 43200.0  # 30 dní po rozchodu AI nezve žádného bývalého
const AI_BREAKUP_LOW_DAYS := 1.0
const AI_ASK_URGENCY := 14.0
## Ex: trapas ve stejné místnosti po dobu EX_AWKWARD (min) po rozchodu.
const EX_AWKWARD := 20160.0
const NEAR := 9.0
const EX_MOOD := -3.0
const EX_STRESS := 0.15
const EX_MOOD_MINUTES := 60.0
## Plánovač: chuť na běžnou společenskou akci s partnerem / s čerstvým ex.
const PARTNER_CONTACT := 1.3
const EX_CONTACT := 0.6
const CONTACT_EXEMPT := ["ask_out", "break_up", "apologize", "clear_air", "confront_gossip", "comfort_panic",
	"flirt", "secret_date", "confront_cheating"]
## Limity uložených dat (hostile save / server).
const MAX_PAIRS := 256
const MAX_NAME := 64
const MAX_ASKS := 6

var pairs := {}        # "A|B" (seřazeno) -> záznam
var _last_ai_ask := {} # jméno -> čas poslední AI pozvánky
var stats := {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"asked": 0, "yes": 0, "not_yet": 0, "no": 0, "taken": 0, "pushy": 0, "blocked": 0,
		"became_partners": 0, "breakups": 0, "together_minutes": 0.0}


static func key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func group_of(gender_identity: String) -> String:
	return String(GROUP_OF.get(gender_identity, ""))


func _rec(a: String, b: String, create: bool) -> Dictionary:
	var k := key(a, b)
	if pairs.has(k):
		return pairs[k]
	if not create or a == b or a == "" or b == "" or pairs.size() >= MAX_PAIRS:
		return {}
	var r := {"status": "", "since": 0.0, "sat": {}, "low_since": {}, "commitment": 0.0,
		"last_contact": 0.0, "last_pos": -1.0e9, "last_breakup": -1.0e9, "dumper": "", "asks": []}
	pairs[k] = r
	return r


## "" (nic) / "dating" / "partners" / "ex".
func status(a: String, b: String) -> String:
	return String(_rec(a, b, false).get("status", ""))


func together(a: String, b: String) -> bool:
	return status(a, b) in ["dating", "partners"]


## S kým je `a` právě ve vztahu ("" = s nikým). Monogamní model → nejvýš jeden.
func partner_of(a: String) -> String:
	var ks: Array = pairs.keys()
	ks.sort()
	for k in ks:
		var r: Dictionary = pairs[k]
		if not String(r["status"]) in ["dating", "partners"]:
			continue
		var names: PackedStringArray = String(k).split("|")
		if names.size() == 2 and (names[0] == a or names[1] == a):
			return names[1] if names[0] == a else names[0]
	return ""


func satisfaction(a: String, b: String) -> float:
	return float((_rec(a, b, false).get("sat", {}) as Dictionary).get(a, SAT_BASE))


func commitment(a: String, b: String) -> float:
	return float(_rec(a, b, false).get("commitment", 0.0))


## Romantická „shoda“: přijal by `pb` vztah s `pa`? (dospělost, aromantičnost, přitažlivost cíle).
## Profil: {"age", "aromantic", "attracted_to": Array, "group": String}.
static func fits(pa: Dictionary, pb: Dictionary) -> bool:
	if int(pa.get("age", 0)) < 18 or int(pb.get("age", 0)) < 18:
		return false
	if bool(pb.get("aromantic", false)):
		return false
	var wants = pb.get("attracted_to", [])
	if typeof(wants) != TYPE_ARRAY or (wants as Array).is_empty():
		return true
	var g := String(pa.get("group", ""))
	return g == "" or (wants as Array).has(g)


## Šance, že cíl řekne „ano“: rel/trust cíle k žadateli (−100..100 / 0..100), nálada cíle (−100..100).
static func accept_p(rel_t: float, trust_t: float, mood_t: float) -> float:
	var p := 0.75 * clampf((rel_t - 20.0) / 80.0, 0.0, 1.0)
	p += 0.1 * clampf(trust_t / 100.0, 0.0, 1.0)
	p += clampf(mood_t, -100.0, 100.0) / 400.0
	return clampf(p, 0.02, 0.9)


## Kolik „ne“ dostal `a` od `b` za posledních NO_WINDOW minut.
func noes(a: String, b: String, now: float) -> int:
	var n := 0
	for e in _rec(a, b, false).get("asks", []):
		if String(e[0]) == a and String(e[2]) in ["no", "pushy"] and now - float(e[1]) <= NO_WINDOW and float(e[1]) <= now:
			n += 1
	return n


## Smí `a` teď pozvat `b`? "" = ano, jinak důvod: "self" / "already" / "taken_self" / "not_now".
## (Zadaný CÍL není blokace – odpověď „mám někoho“ je výsledek pokusu.)
func ask_block(a: String, b: String, now: float) -> String:
	if a == "" or b == "" or a == b:
		return "self"
	var mine := partner_of(a)
	if mine == b:
		return "already"
	if mine != "":
		return "taken_self"
	var r := _rec(a, b, false)
	if r.is_empty():
		return ""
	if String(r["status"]) == "ex" and now >= float(r["last_breakup"]) and now - float(r["last_breakup"]) < REDATE_AFTER:
		return "not_now"
	for e in r["asks"]:
		if String(e[0]) != a or float(e[1]) > now:
			continue
		var wait := COOLDOWN_NOT_YET if String(e[2]) == "not_yet" else (COOLDOWN_NO if String(e[2]) in ["no", "pushy", "taken"] else 0.0)
		if now - float(e[1]) < wait:
			return "not_now"
	return ""


## Výsledek pozvání `a` → `b`: "yes" / "not_yet" / "no" / "taken" / "pushy" (nebo blokace z ask_block,
## pak se nic nemění). p z accept_p, roll 0..1 dodá volající. Mění jen stav dvojice.
func resolve_ask(a: String, b: String, pa: Dictionary, pb: Dictionary, p: float, roll: float, now: float) -> String:
	var block := ask_block(a, b, now)
	if block != "":
		stats["blocked"] += 1
		return block
	var r := _rec(a, b, true)
	if r.is_empty():
		stats["blocked"] += 1
		return "not_now"
	stats["asked"] += 1
	var outcome := ""
	if noes(a, b, now) >= PUSHY_NOES:
		outcome = "pushy"
	elif partner_of(b) != "":
		outcome = "taken"
	elif not fits(pa, pb):
		outcome = "no"
	else:
		p = clampf(p, 0.0, 1.0)
		if roll < p:
			outcome = "yes"
		elif roll < p + (1.0 - p) * NOT_YET_SHARE:
			outcome = "not_yet"
		else:
			outcome = "no"
	var asks: Array = r["asks"]
	asks.append([a, now, outcome])
	while asks.size() > MAX_ASKS:
		asks.pop_front()
	if outcome == "yes":
		r["status"] = "dating"
		r["since"] = now
		r["sat"] = {a: SAT_START, b: SAT_START}
		r["low_since"] = {}
		r["commitment"] = 0.0
		r["last_contact"] = now
		r["dumper"] = ""
	stats[outcome] += 1
	return outcome


## Událost mezi dvojicí (rozhovor; kind = výsledek nebo druh nátlaku). `a` = iniciátor.
## Mimo vztah nic nedělá.
func note(a: String, b: String, kind: String, now: float) -> void:
	var r := _rec(a, b, false)
	if r.is_empty() or not String(r["status"]) in ["dating", "partners"]:
		return
	var k := "pressure" if PRESSURE_KINDS.has(kind) else kind
	if not SAT_EVENT.has(k):
		return
	var d: Array = SAT_EVENT[k]
	if k in ["chat", "shared"]:
		r["last_contact"] = maxf(float(r["last_contact"]), now)
		if now - float(r.get("last_pos", -1.0e9)) < POSITIVE_GAP and float(r.get("last_pos", -1.0e9)) <= now:
			return
		r["last_pos"] = now
		for i in 2:
			var who: String = a if i == 0 else b
			var v := float((r["sat"] as Dictionary).get(who, SAT_BASE))
			_add_sat(r, who, float(d[i]) * clampf((1.0 - v) / (1.0 - SAT_BASE), 0.0, 1.0), now)
		return
	_add_sat(r, a, float(d[0]), now)
	_add_sat(r, b, float(d[1]), now)


func _add_sat(r: Dictionary, who: String, delta: float, now: float) -> void:
	var sat: Dictionary = r["sat"]
	var v := clampf(float(sat.get(who, SAT_BASE)) + delta, 0.0, 1.0)
	sat[who] = v
	var low: Dictionary = r["low_since"]
	if v < LOW and not low.has(who):
		low[who] = now
	elif v >= LOW_EXIT and low.has(who):
		low.erase(who)


## Rozchod: `a` končí vztah s `b`. Vrací {} když spolu nejsou, jinak
## {"status_before", "days", "commitment", "sat_a", "sat_b"} (pro následky v SimAgent).
func breakup(a: String, b: String, now: float) -> Dictionary:
	var r := _rec(a, b, false)
	if r.is_empty() or not String(r["status"]) in ["dating", "partners"]:
		return {}
	var info := {"status_before": String(r["status"]), "days": maxf(0.0, now - float(r["since"])) / 1440.0,
		"commitment": float(r["commitment"]), "sat_a": satisfaction(a, b), "sat_b": satisfaction(b, a)}
	r["status"] = "ex"
	r["since"] = now
	r["last_breakup"] = now
	r["dumper"] = a
	r["low_since"] = {}
	stats["breakups"] += 1
	return info


## Chuť AI pozvat `other` na rande (0 = nechce). base = obecné násobiče akce.
func ai_ask_score(sim, other, base: float, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	if ask_block(a, b, now) != "" or partner_of(b) != "":
		return 0.0
	if now - float(_last_ai_ask.get(a, -1.0e12)) < AI_ASK_EVERY:
		return 0.0
	var r := _rec(a, b, false)
	if not r.is_empty():
		if String(r["status"]) == "ex" and now - float(r["last_breakup"]) < AI_EX_PAUSE:
			return 0.0
		if noes(a, b, now) > 0:
			return 0.0  # AI respektuje „ne“ (hráč může – ale nese následky)
	if other.has_method("romance_owned_by_player") and other.romance_owned_by_player():
		return 0.0  # postava jiného hráče odpovídá sama (v MP zatím bez potvrzovacího dialogu)
	var pa: Dictionary = sim.romance_profile()
	var pb: Dictionary = other.romance_profile()
	if bool(pa.get("aromantic", false)) or not fits(pb, pa) or not fits(pa, pb):
		return 0.0  # AI nezve, koho ji samu nepřitahuje, ani kde ví, že to nejde
	var rel: float = float(sim.relationships.get(b, 0.0))
	var trust: float = float(sim.ledger.trust_in(b))
	if rel < AI_ASK_REL or trust < AI_ASK_TRUST:
		return 0.0
	# Odvaha zeptat se: roste s blízkostí i důvěrou (měřítko jako u „vyříkat si to“ – jinak by
	# v plánovači vždy prohrála s běžnými potřebami a blízké dvojice by se nikdy neodhodlaly).
	var close := clampf((rel - AI_ASK_REL) / (100.0 - AI_ASK_REL), 0.05, 1.0)
	var sure := 0.5 + 0.5 * clampf((trust - AI_ASK_TRUST) / (100.0 - AI_ASK_TRUST), 0.0, 1.0)
	return base * AI_ASK_URGENCY * close * sure


func note_ai_ask(a: String, now: float) -> void:
	_last_ai_ask[a] = now


## Chuť AI rozejít se s `other` (0 = nechce). Jen při dlouhodobě nízké spokojenosti.
func ai_breakup_score(sim, other, base: float, now: float) -> float:
	var a := String(sim.sim_name)
	var b := String(other.sim_name)
	var r := _rec(a, b, false)
	if r.is_empty() or not String(r["status"]) in ["dating", "partners"]:
		return 0.0
	var low: Dictionary = r["low_since"]
	if not low.has(a):
		return 0.0
	var days := (now - float(low[a])) / 1440.0
	if days < AI_BREAKUP_LOW_DAYS:
		return 0.0
	var s := satisfaction(a, b)
	# Delší vztah se končí hůř (závazek tlumí, ne zakazuje).
	return base * 12.0 * clampf((LOW - s) / LOW + 0.2, 0.0, 1.2) * minf(days, 3.0) * (1.0 - 0.5 * float(r["commitment"]))


## Násobič chuti `a` oslovit `b` běžnou společenskou akcí (partner trochu víc, čerstvý ex míň).
func contact_weight(a: String, b: String, action_id: String, now: float) -> float:
	if CONTACT_EXEMPT.has(action_id):
		return 1.0
	var r := _rec(a, b, false)
	if r.is_empty():
		return 1.0
	match String(r["status"]):
		"dating", "partners":
			return PARTNER_CONTACT
		"ex":
			return EX_CONTACT if now >= float(r["last_breakup"]) and now - float(r["last_breakup"]) < EX_AWKWARD else 1.0
	return 1.0


## Jeden krok dynamiky (dt herních minut): spokojenost v čase, závazek, povýšení na vážný vztah,
## trapas s ex. sims = živé postavy na autoritě; cold_war (volitelné) = stupně studené války.
func tick(sims: Array, now: float, dt: float, cold_war = null) -> void:
	if dt <= 0.0 or pairs.is_empty():
		return
	var by_name := {}
	for s in sims:
		by_name[String(s.sim_name)] = s
	var ks: Array = pairs.keys()
	ks.sort()
	for k in ks:
		var r: Dictionary = pairs[k]
		var names: PackedStringArray = String(k).split("|")
		var st := String(r["status"])
		if st in ["dating", "partners"]:
			stats["together_minutes"] = float(stats["together_minutes"]) + dt
			var cw_stage := 0
			if cold_war != null:
				cw_stage = int(cold_war.stage(names[0], names[1]))
			var neglect := now - float(r["last_contact"]) > NEGLECT_AFTER
			for who in names:
				var v := float((r["sat"] as Dictionary).get(who, SAT_BASE))
				v = SAT_BASE + (v - SAT_BASE) * exp(-dt / SAT_TAU)
				var drain := float(SAT_COLD_WAR[clampi(cw_stage, 0, 2)]) + (SAT_NEGLECT if neglect else 0.0)
				(r["sat"] as Dictionary)[who] = v
				_add_sat(r, who, -drain * dt / 1440.0, now)
			var speed := 1.5 if st == "partners" else 1.0
			r["commitment"] = minf(1.0, float(r["commitment"]) + speed * dt / (COMMIT_DAYS * 1440.0))
			if st == "dating" and (now - float(r["since"])) / 1440.0 >= PARTNER_DAYS \
					and satisfaction(names[0], names[1]) >= PARTNER_SAT and satisfaction(names[1], names[0]) >= PARTNER_SAT:
				r["status"] = "partners"
				stats["became_partners"] += 1
				for pr in [[names[0], names[1]], [names[1], names[0]]]:
					if by_name.has(pr[0]) and by_name.has(pr[1]):
						var me = by_name[pr[0]]
						me.add_joy_moodlet("spolu_vazne_" + String(by_name[pr[1]].name), "Jsme spolu vážně: " + String(by_name[pr[1]].first_name()),
							"spokojeny", 10.0, 1440.0)
						me._detail_dirty = true
		elif st == "":
			# Jen historie pozvání bez vztahu: po vypršení okna odmítnutí se záznam uklidí (limit MAX_PAIRS).
			var fresh := false
			for e in r["asks"]:
				if now - float(e[1]) <= NO_WINDOW:
					fresh = true
			if not fresh:
				pairs.erase(k)
			continue
		elif st == "ex":
			if now - float(r["last_breakup"]) >= EX_AWKWARD or not by_name.has(names[0]) or not by_name.has(names[1]):
				continue
			var x = by_name[names[0]]
			var y = by_name[names[1]]
			if x._is_sleeping() or y._is_sleeping() or x.global_position.distance_to(y.global_position) >= NEAR:
				continue
			for pr2 in [[x, y], [y, x]]:
				var me2 = pr2[0]
				var other = pr2[1]
				me2.mental.on_stressor("ex_nearby", EX_STRESS, me2.mental_cfg())
				me2.mood.add_moodlet("ex_" + String(other.name), "Ex je tady: " + String(other.first_name()), "nesvuj",
					EX_MOOD, EX_MOOD_MINUTES)
				me2._detail_dirty = true


## Veřejný pohled pro HUD/testy: [{"a","b","status","days"}] seřazeno podle klíče (bez spokojenosti –
## ta je soukromá).
func summary(now: float) -> Array:
	var out: Array = []
	var ks: Array = pairs.keys()
	ks.sort()
	for k in ks:
		var r: Dictionary = pairs[k]
		if String(r["status"]) == "":
			continue
		var names: PackedStringArray = String(k).split("|")
		out.append({"a": names[0], "b": names[1], "status": String(r["status"]),
			"days": maxf(0.0, now - float(r["since"])) / 1440.0})
	return out


func to_dict() -> Dictionary:
	return {"pairs": pairs.duplicate(true), "last_ai_ask": _last_ai_ask.duplicate(true), "stats": stats.duplicate(true)}


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
## Monogamii vynutí i u poškozeného savu: druhý souběžný vztah téže postavy se změní na "ex".
func from_dict(d) -> void:
	pairs = {}
	_last_ai_ask = {}
	reset_stats()
	if typeof(d) != TYPE_DICTIONARY:
		return
	var src = d.get("pairs", {})
	if typeof(src) == TYPE_DICTIONARY:
		var ks: Array = src.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		var busy := {}
		for k in ks:
			if pairs.size() >= MAX_PAIRS or typeof(k) != TYPE_STRING:
				continue
			var names: PackedStringArray = String(k).split("|")
			if names.size() != 2 or not _valid_name(names[0]) or not _valid_name(names[1]) or names[0] == names[1]:
				continue
			var r = src[k]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var st := String(r.get("status", "")) if typeof(r.get("status")) == TYPE_STRING else ""
			if not st in STATUSES:
				st = ""
			if st in ["dating", "partners"]:
				if busy.has(names[0]) or busy.has(names[1]):
					st = "ex"
				else:
					busy[names[0]] = true
					busy[names[1]] = true
			var sat := {}
			var low := {}
			for who in names:
				if typeof(r.get("sat")) == TYPE_DICTIONARY and r["sat"].has(who):
					sat[who] = _fin(r["sat"][who], 0.0, 1.0, SAT_BASE)
				if typeof(r.get("low_since")) == TYPE_DICTIONARY and r["low_since"].has(who):
					var ls := _fin(r["low_since"][who], -1.0e9, 1.0e12, NAN)
					if is_finite(ls):
						low[who] = ls
			var asks: Array = []
			if typeof(r.get("asks")) == TYPE_ARRAY:
				for e in r["asks"]:
					if asks.size() >= MAX_ASKS or typeof(e) != TYPE_ARRAY or (e as Array).size() != 3:
						continue
					if typeof(e[0]) != TYPE_STRING or typeof(e[2]) != TYPE_STRING or not String(e[0]) in names:
						continue
					if not String(e[2]) in ["yes", "not_yet", "no", "taken", "pushy"]:
						continue
					var t := _fin(e[1], -1.0e9, 1.0e12, NAN)
					if is_finite(t):
						asks.append([String(e[0]), t, String(e[2])])
			var dumper := String(r.get("dumper", "")) if typeof(r.get("dumper")) == TYPE_STRING else ""
			if not dumper in names:
				dumper = ""
			pairs[key(names[0], names[1])] = {"status": st, "sat": sat, "low_since": low, "asks": asks,
				"since": _fin(r.get("since"), -1.0e9, 1.0e12, 0.0),
				"commitment": _fin(r.get("commitment"), 0.0, 1.0, 0.0),
				"last_contact": _fin(r.get("last_contact"), -1.0e9, 1.0e12, 0.0),
				"last_pos": _fin(r.get("last_pos"), -1.0e9, 1.0e12, -1.0e9),
				"last_breakup": _fin(r.get("last_breakup"), -1.0e9, 1.0e12, -1.0e9),
				"dumper": dumper}
	var la = d.get("last_ai_ask", {})
	if typeof(la) == TYPE_DICTIONARY:
		for n in la:
			if _last_ai_ask.size() < MAX_PAIRS and _valid_name(n):
				_last_ai_ask[n] = _fin(la[n], -1.0e12, 1.0e12, -1.0e12)
	var st2 = d.get("stats", {})
	if typeof(st2) == TYPE_DICTIONARY:
		for k in stats:
			if st2.has(k):
				stats[k] = _fin(st2[k], 0.0, 1.0e12, 0.0) if k == "together_minutes" else int(_fin(st2[k], 0.0, 1.0e9, 0.0))
