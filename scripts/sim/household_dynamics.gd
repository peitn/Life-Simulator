extends RefCounted
## HouseholdDynamics – život pod jednou střechou mimo samotné rozhovory.
##
## Proč: když vztahy mění jen rozhovory, domácnost sklouzne do „studené války“ – hádka bere
## víc, než pohoda přidá, a nic jiného se neděje. Ve skutečnosti se lidé:
##   * otravují drobnostmi, které s rozhovorem nesouvisí (hluk v noci, koupelna, nádobí),
##   * sbližují i beze slov – společný film, vaření vedle sebe,
##   * nosí domů náladu zvenku (šéf, účty, hezká zpráva od kamaráda),
##   * a vztahy bez kontaktu pomalu vyprchávají.
## Tenhle modul to dodává jako systém kolem SimAgent. Běží jen na autoritě (offline / server),
## krok je TICK herních minut, náhoda jde výhradně přes rng postav (deterministické podle seedu).
## Hodnoty jsou v konstantách s popisem; žádná volba není dominantní – třenice nejsou trest,
## společné chvíle nejsou „farma vztahů“ (cooldown, násobí je živá křivda).
##
## Převzato a vyčištěno z experimentu FCCS v3/v4 (DEVLOG 20.–21. 10. 2026); FCCS zůstává jen
## volitelný modulátor výsledku rozhovoru (scripts/sim/fccs_oracle.gd).

const Grammar := preload("res://scripts/core/grammar_cs.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")

## Krok modulu v herních minutách.
const TICK := 10.0

# ---------------------------------------------------------------- třenice
## Akce, při kterých postava spí (hluk ji ruší).
const SLEEP_IDS := ["sleep", "sleep_sofa", "sleep_floor", "nap"]
## Hlučné akce (televize, běžecký pás, vaření – nádobí, digestoř).
const NOISY_IDS := ["watch_tv", "workout", "cook"]
## Do jaké vzdálenosti (m) je druhý „slyšet“ / vidět nepořádek.
const FRICTION_NEAR := 9.0
## Noc pro hluk: od NIGHT_FROM do NIGHT_TO hodin.
const NIGHT_FROM := 22
const NIGHT_TO := 6
## Hygiena, pod kterou postavu štve, že je koupelna obsazená.
const BATHROOM_NEED := 40.0
## Nádobí zůstane jen po skutečném vaření (aspoň tolik minut) – ne po příkazu „vař“ zrušeném
## po minutě (review Gemini běh 15: griefing třenicemi přes rychlé příkazy).
const DISHES_MIN_COOK := 20.0
## Základní šance za krok, že situace opravdu naštve (× dráždivost povahy).
const FRICTION_P := {"noise": 0.25, "bathroom": 0.2, "dishes": 0.12}
## Odstup mezi třenicemi stejného druhu u stejné dvojice (herní minuty) – jinak by jedno
## nádobí naštvalo desetkrát.
const FRICTION_COOLDOWN := {"noise": 360.0, "bathroom": 360.0, "dishes": 720.0}
## Následky jedné třenice pro toho, koho to štve.
const FRICTION_STRESS := 3.0
const FRICTION_GRUDGE := 2.0
const FRICTION_MOOD := -6.0
const FRICTION_MOOD_MINUTES := 120.0
## Jak dlouho platí stížnost do příštího oslovení: SimAgent.COMPLAINT_TTL.
## Kolik drobností za den člověka ještě „rozhodí“; další mají klesající váhu (v plném domě
## se postavy nehádají o každou maličkost – po pár třenicích to začnou přecházet).
const FRICTION_DAILY_SOFT := 2.0
## Ranní světlo: drobná radost pro toho, kdo je ráno vzhůru (podle citlivosti a toho, kolik radosti zrovna unese).
const MORNING_FROM := 6
const MORNING_TO := 10
const MORNING_LIGHT_MOOD := 4.0
const MORNING_LIGHT_MINUTES := 120.0
const COMPLAINT_LABEL := {"noise": "hluk v noci", "bathroom": "obsazená koupelna", "dishes": "nádobí po vaření"}

# ---------------------------------------------------------------- společné chvíle
## Oba dělají „gaučovou“ akci do SHARED_DIST m od sebe → film spolu; oba vaří → vaření spolu.
const SHARED_SOFA_IDS := ["watch_tv", "relax"]
const SHARED_DIST := 4.0
const SHARED_COOLDOWN := 240.0
## Jedna společná chvíle na osobu za tuto dobu (škálování s počtem lidí).
const SHARED_PERSON_COOLDOWN := 120.0
## Zisk vztahu (× warmth_mult – živá křivda ho brzdí), obroušení křivdy, moodlet.
const SHARED_REL := 2.0
const SHARED_SOFTEN := 2.0
## Se silnou živou křivdou (u kteréhokoli z dvojice) společné sezení nic nesbližuje – vedle
## někoho, na koho mám velký vztek, se nedívám na film „spolu“ (review Gemini běh 15: farmení vztahu).
## Práh je vysoký záměrně: při 30 (≈ 4 hádky) zmizela hlavní cesta zpět a hádky vyskočily
## z 37 na 46 % (DEVLOG běh 15); pod prahem zisk tlumí warmth_mult.
const SHARED_MAX_GRUDGE := 60.0
const SHARED_MOOD := 5.0
const SHARED_MOOD_MINUTES := 120.0

# ---------------------------------------------------------------- životní události
## Hazard za TICK (≈ 1,7 události na postavu za den), polovina dobrých, polovina špatných.
const EVENT_HAZARD := 0.012
const EVENT_GOOD_SHARE := 0.5
const EVENT_MIN_MINUTES := 240.0
const EVENT_MAX_MINUTES := 480.0
## Špatná událost přidá i trochu stresu (podíl síly moodletu).
const EVENT_STRESS_SHARE := 0.2
## [text, síla]. „(a)“ = koncovka příčestí, „{y}“ = koncovka přídavného jména podle rodu postavy.
const EVENTS_GOOD := [
	["Pochvala od šéfa", 12.0], ["Kamarád poslal vtipnou zprávu", 8.0], ["Venku konečně svítí", 7.0],
	["Vrátili mi přeplatek", 11.0], ["Někdo mi pochválil oblečení", 8.0], ["Dobrá zpráva od rodiny", 10.0],
]
const EVENTS_BAD := [
	["Přišel účet za elektřinu", -12.0], ["Nepříjemný telefonát z práce", -11.0], ["Bolí mě hlava", -8.0],
	["Zmokl(a) jsem jak pes", -7.0], ["Ztratil(a) jsem klíče", -9.0], ["Ex mi napsal blbou zprávu", -13.0],
]

# ---------------------------------------------------------------- zanedbání
## Kladný vztah bez kontaktu déle než NEGLECT_AFTER pomalu klesá k NEGLECT_FLOOR (staří
## přátelé se neztratí úplně, ale bez kontaktu už nejsou „nejlepší“).
const NEGLECT_AFTER := 4320.0  # 3 dny
const NEGLECT_FLOOR := 25.0
const NEGLECT_TAU := 43200.0  # ~30 dní

var _acc := 0.0
var _last_friction := {}  # "A>B>téma" -> čas
var _last_shared := {}    # "A+B" -> čas
var _prev_acting := {}    # jméno postavy -> id akce, kterou dělala v minulém kroku
var _friction_day := {}  # jméno postavy -> [den, počet třenic dnes]
var _morning := {}       # jméno postavy -> den, kdy už mělo ranní světlo
var _cooked := {}         # jméno postavy -> minuty nepřetržitého vaření (pro nádobí)
## Statistiky (testy, ladění, budoucí HUD „jak to doma vypadá“).
var stats := {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"talks": 0, "argues": 0, "deescalated": 0, "complaint_talks": 0, "complaint_argues": 0,
		"friction": {}, "shared": {}, "events": {"good": 0, "bad": 0},
		"by_mood": {"good": [0, 0], "mid": [0, 0], "bad": [0, 0]}}


## Napojí statistiku rozhovorů na postavu (SimAgent.conversation).
func register(sim) -> void:
	if sim.has_signal("conversation") and not sim.conversation.is_connected(_on_conversation):
		sim.conversation.connect(_on_conversation)


## Volá se s uplynulými herními minutami; sám si odpočítává TICK.
func advance(dm: float, sims: Array, clock) -> void:
	_acc += dm
	while _acc >= TICK - 1e-6:
		_acc -= TICK
		tick(sims, clock.get_hour(), float(clock.total_minutes))


## Jeden krok. sims = všechny postavy světa; loutky (klient) se ignorují.
func tick(all_sims: Array, hour: int, now: float) -> void:
	var sims: Array = []
	for s in all_sims:
		if is_instance_valid(s) and s.has_method("command") and s.is_inside_tree():
			sims.append(s)
	for o in sims:
		var oid := acting_id(o)
		var prev := String(_prev_acting.get(o.sim_name, ""))
		_prev_acting[o.sim_name] = oid
		var cooked: float = float(_cooked.get(o.sim_name, 0.0))
		_cooked[o.sim_name] = cooked + TICK if oid == "cook" else 0.0
		if prev == "cook" and cooked < DISHES_MIN_COOK:
			prev = ""  # krátce rozvařené a zrušené – žádné nádobí
		for s in sims:
			if s == o:
				continue
			var topic := friction_topic(s, o, hour, prev)
			if topic == "" or not can_friction(s, o, topic, now):
				continue
			var p := float(FRICTION_P[topic]) * irritability(s) * friction_weight(s, now)
			if topic == "noise":
				# Hluk: záleží na citlivosti, návyku a vzdálenosti; jeden spáč se kvůli hluku naštve
				# nejvýš jednou za cooldown, ať je zdrojů kolik chce.
				var d: float = s.global_position.distance_to(o.global_position)
				var fall := clampf(1.0 - d / FRICTION_NEAR, 0.0, 1.0)
				p *= sensory_noise(s) * fall * fall
				expose_noise(s, fall)
			if s.rng.randf() < p:
				apply_friction(s, o, topic, now)
	_morning_light(sims, hour, now)
	_shared_moments(sims, now)
	_neglect(sims, now)
	for x in sims:
		if not x._is_sleeping() and x.rng.randf() < EVENT_HAZARD:
			life_event(x, now)


## Id akce, kterou postava právě DĚLÁ (ne ke které jde), jinak "".
static func acting_id(s) -> String:
	if s.state != SimAgent.State.ACTING:
		return ""
	return String(s.current_action.get("id", ""))


## Dráždivost povahy (násobí šanci, že drobnost naštve). Parametr rysů `irritability`.
static func irritability(s) -> float:
	return Traits.mult_param(s.trait_ids, "irritability")


## Jaká drobnost by mohla `s` naštvat na `o` (bez náhody), nebo "". prev_o = co `o` dělal/a
## v minulém kroku (nádobí zůstane po dovaření).
static func friction_topic(s, o, hour: int, prev_o: String) -> String:
	var sid := acting_id(s)
	var oid := acting_id(o)
	var near: bool = s.global_position.distance_to(o.global_position) < FRICTION_NEAR
	var s_sleeps := SLEEP_IDS.has(sid)
	if (hour >= NIGHT_FROM or hour < NIGHT_TO) and s_sleeps and NOISY_IDS.has(oid) and near:
		return "noise"
	if s_sleeps:
		return ""
	if oid == "shower" and sid != "shower" and float(s.needs.values["hygiene"]) < BATHROOM_NEED:
		return "bathroom"
	if prev_o == "cook" and oid != "cook" and near:
		return "dishes"
	return ""


func can_friction(s, o, topic: String, now: float) -> bool:
	if topic == "noise" and now - float(_last_friction.get("%s>*>noise" % s.sim_name, -1.0e9)) < float(FRICTION_COOLDOWN["noise"]):
		return false
	return now - float(_last_friction.get(_fkey(s, o, topic), -1.0e9)) >= float(FRICTION_COOLDOWN[topic])


## Váha další třenice podle toho, kolik jich postava dnes už měla (1, 1, 0.5, 0.33…).
func friction_weight(s, now: float) -> float:
	var day := int(now / 1440.0)
	var e: Array = _friction_day.get(s.sim_name, [day, 0])
	if int(e[0]) != day:
		return 1.0
	return 1.0 / maxf(1.0, float(e[1]) - FRICTION_DAILY_SOFT + 1.0)


static func sensory_noise(s) -> float:
	var sp = s.get("sensory")
	return 1.0 if sp == null else float(sp.noise_factor())


static func expose_noise(s, amount: float) -> void:
	var sp = s.get("sensory")
	if sp != null and amount > 0.0:
		sp.expose_noise(amount)


## Ranní světlo – jednou za den pro toho, kdo je ráno vzhůru a nespí.
func _morning_light(sims: Array, hour: int, now: float) -> void:
	if hour < MORNING_FROM or hour >= MORNING_TO:
		return
	var day := int(now / 1440.0)
	for x in sims:
		if int(_morning.get(x.sim_name, -1)) == day or x._is_sleeping():
			continue
		_morning[x.sim_name] = day
		var sp = x.get("sensory")
		var ls: float = 1.0 if sp == null else float(sp.light_sens)
		if x.has_method("add_joy_moodlet"):
			x.add_joy_moodlet("ranni_svetlo", "Ranní světlo", "spokojeny", MORNING_LIGHT_MOOD * ls, MORNING_LIGHT_MINUTES)


## Následky třenice: `s` je naštvaný/á na `o` kvůli `topic`.
func apply_friction(s, o, topic: String, now: float) -> void:
	var cfg: Dictionary = s.mental_cfg()
	s.mental.on_stressor("friction", FRICTION_STRESS * Traits.mult_param(s.trait_ids, "stress_gain"), cfg)
	s.ledger.on_hurt_by(o.sim_name, FRICTION_GRUDGE, now)
	s.mood.add_moodlet("trenice_%s_%s" % [topic, o.name], "Štve mě %s (%s)" % [o.first_name(), COMPLAINT_LABEL[topic]],
		"nastvany", FRICTION_MOOD, FRICTION_MOOD_MINUTES)
	s.pending_complaints[o.sim_name] = {"topic": topic, "t": now}
	s._detail_dirty = true
	_last_friction[_fkey(s, o, topic)] = now
	if topic == "noise":
		_last_friction["%s>*>noise" % s.sim_name] = now
	var day := int(now / 1440.0)
	var e: Array = _friction_day.get(s.sim_name, [day, 0])
	if int(e[0]) != day:
		e = [day, 0]
	_friction_day[s.sim_name] = [day, int(e[1]) + 1]
	stats["friction"][topic] = int(stats["friction"].get(topic, 0)) + 1


static func _fkey(s, o, topic: String) -> String:
	return "%s>%s>%s" % [s.sim_name, o.sim_name, topic]


## Druh společné chvíle dvou postav, nebo "".
static func shared_kind(a, b) -> String:
	var ia := acting_id(a)
	var ib := acting_id(b)
	if a.global_position.distance_to(b.global_position) >= SHARED_DIST:
		return ""
	if SHARED_SOFA_IDS.has(ia) and SHARED_SOFA_IDS.has(ib):
		return "film"
	if ia == "cook" and ib == "cook":
		return "vaření"
	return ""


func _shared_moments(sims: Array, now: float) -> void:
	for i in sims.size():
		for j in range(i + 1, sims.size()):
			var a = sims[i]
			var b = sims[j]
			var kind := shared_kind(a, b)
			var key := "%s+%s" % [a.sim_name, b.sim_name]
			if kind == "" or now - float(_last_shared.get(key, -1.0e9)) < SHARED_COOLDOWN:
				continue
			# Jedna společná chvíle na osobu za čas – u filmu se sedmi lidmi nevzniká 21 „chvilek“ najednou.
			if now - float(_last_shared.get(a.sim_name, -1.0e9)) < SHARED_PERSON_COOLDOWN \
					or now - float(_last_shared.get(b.sim_name, -1.0e9)) < SHARED_PERSON_COOLDOWN:
				continue
			if a.ledger.grudge(b.sim_name) > SHARED_MAX_GRUDGE or b.ledger.grudge(a.sim_name) > SHARED_MAX_GRUDGE:
				continue
			_last_shared[key] = now
			_last_shared[a.sim_name] = now
			_last_shared[b.sim_name] = now
			for pr in [[a, b], [b, a]]:
				var x = pr[0]
				var y = pr[1]
				var cur := float(x.relationships.get(y.sim_name, 0.0))
				var nv := clampf(cur + SHARED_REL * x.ledger.warmth_mult(y.sim_name), -100.0, 100.0)
				x.relationships[y.sim_name] = nv
				x.last_talk[y.sim_name] = now  # být spolu je taky kontakt (proti „zanedbání“)
				x.ledger.soften(y.sim_name, SHARED_SOFTEN)
				x.add_joy_moodlet("spolu_%s_%s" % [kind, y.name], "Chvíle spolu: %s (%s)" % [y.first_name(), kind],
					"stastny", SHARED_MOOD, SHARED_MOOD_MINUTES)
				x.note_relationship_change(y, cur, nv)
				x._detail_dirty = true
			stats["shared"][kind] = int(stats["shared"].get(kind, 0)) + 1


func _neglect(sims: Array, now: float) -> void:
	var k := 1.0 - exp(-TICK / NEGLECT_TAU)
	for x in sims:
		for n in x.relationships:
			var r := float(x.relationships[n])
			if r <= NEGLECT_FLOOR or not x.last_talk.has(n):
				continue
			if now - float(x.last_talk[n]) > NEGLECT_AFTER:
				x.relationships[n] = r - (r - NEGLECT_FLOOR) * k


## Náhodná událost mimo domácnost – mění náladu (špatná i trochu stres).
func life_event(x, now: float) -> void:
	var good: bool = x.rng.randf() < EVENT_GOOD_SHARE
	var pool: Array = EVENTS_GOOD if good else EVENTS_BAD
	var e: Array = pool[x.rng.randi() % pool.size()]
	var label := Grammar.form(String(e[0]), x.grammar)
	var strength: float = float(e[1]) * x.rng.randf_range(0.7, 1.3)
	var dur: float = x.rng.randf_range(EVENT_MIN_MINUTES, EVENT_MAX_MINUTES)
	if good and x.has_method("add_joy_moodlet"):
		x.add_joy_moodlet("udalost_%d" % int(now), label, "stastny", strength, dur)
	else:
		x.mood.add_moodlet("udalost_%d" % int(now), label, "stastny" if good else "smutny", strength, dur)
	if not good:
		x.mental.on_stressor("life", absf(strength) * EVENT_STRESS_SHARE, x.mental_cfg())
	stats["events"]["good" if good else "bad"] += 1


## Kbelík nálady pro statistiku hádek (průměr nálady obou na začátku rozhovoru).
static func mood_bucket(avg_mood: float) -> String:
	if avg_mood > 30.0:
		return "good"
	if avg_mood < 5.0:
		return "bad"
	return "mid"


func _on_conversation(_sim, _partner, info: Dictionary) -> void:
	var ok := bool(info.get("success", true))
	stats["talks"] += 1
	if not ok:
		stats["argues"] += 1
	if bool(info.get("deescalated", false)):
		stats["deescalated"] += 1
	if String(info.get("complaint", "")) != "":
		stats["complaint_talks"] += 1
		if not ok:
			stats["complaint_argues"] += 1
	var b: Array = stats["by_mood"][mood_bucket(float(info.get("avg_mood", 0.0)))]
	b[0] += 1
	if not ok:
		b[1] += 1


## Podíl hádek ze všech běžných rozhovorů (bez urážek a omluv).
func argue_rate() -> float:
	return float(stats["argues"]) / maxf(1.0, float(stats["talks"]))
