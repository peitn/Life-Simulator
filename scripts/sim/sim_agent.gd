extends Node3D
## Postava (serverová / offline) – autonomní agent s potřebami, náladou, rysy, vztahy a pamětí.
## Logika běží v herních minutách (GameClock.time_advanced) a jen tam, kde je autorita
## (offline hra nebo server). Klienti v multiplayeru vidí jen SimPuppet, který dostává
## stav přes vlastnosti `net_*` (MultiplayerSynchronizer).
## Hráč může postavě zadávat příkazy (`command`) – validaci dělá NetSession.

const Needs := preload("res://scripts/sim/needs.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const PsycheModel := preload("res://scripts/psyche/psyche_model.gd")
const RelLedger := preload("res://scripts/sim/rel_ledger.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")
const SensoryProfile := preload("res://scripts/sim/sensory_profile.gd")
## Volitelné externí rozhodování sociálních interakcí (experiment FCCS, jen headless test).
static var social_oracle = null

signal action_started(sim: Node3D, action: Dictionary)
signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
signal memory_added(sim: Node3D, text: String)
## Sociální událost (pro zvuk/UI): positive = příjemný hovor, milestone = změna úrovně vztahu.
signal social_event(sim: Node3D, positive: bool, milestone: bool)
## Začátek/konec panické ataky (pro UI a statistiky; ostatní to vidí jen jako akci).
signal panic_changed(sim: Node3D, active: bool)
## Běžný rozhovor skončil (ne urážka/omluva/svěření): info = {success, avg_mood, complaint,
## deescalated, p} – statistiky domácnosti (HouseholdDynamics) a později HUD.
signal conversation(sim: Node3D, partner: Node3D, info: Dictionary)

enum State { IDLE, WALKING, ACTING }

const WALK_SPEED := 3.0  # metrů za herní minutu
const ARRIVE_DIST := 0.3
const MAX_WALK_MINUTES := 45.0
const MAX_MEMORIES := 40
const SOCIAL_TALK_DIST := 1.0
const MEMORABLE_STRENGTH := 14.0
const MAX_QUEUE := 3
const SPEECH_MINUTES := 25.0
const DETAIL_INTERVAL := 10.0  # herní minuty mezi obnovami net_detail
## Po urážce od stejné postavy oběť další urážky v tomto okně ignoruje (odejde) – proti griefingu.
const INSULT_IGNORE_MINUTES := 120.0
## Svědci panické ataky / hádky v tomto okruhu (m).
const WITNESS_DIST := 12.0
const CROWD_DIST := 2.5
const CROWD_INTERVAL := 15.0
## Stres z tlačenice za každého člověka navíc (× citlivost postavy na tlačenici).
const CROWD_STRESS := 1.0
## --- vyvážení vztahů (převzato z experimentu FCCS v3/v4, viz docs/relationships.md)
## Hádka ubere ×0,6 nominální ztráty – jinak při ~30 % hádek vztahy nutně padají („studená válka“).
const ARGUE_REL_MULT := 0.6
## Další hovor se stejnou postavou do REPEAT_TALK_WINDOW min má ×0,7 účinku (klesající výnos).
const REPEAT_TALK_WINDOW := 180.0
const REPEAT_TALK_MULT := 0.7
## Výchozí šance na dobrý rozhovor dvou neutrálních lidí v klidu (před povahou, náladou, vztahem).
## Kalibrace (běh 15, 20 seedů × 14 dní): 0,6 dávalo podle drobností v pořadí náhody 37–46 % hádek,
## 0,65 drží průměr uvnitř cílových 20–40 % s rezervou.
const TALK_BASE := 0.65
## Kolik může nálada obou (průměr, −100..100) posunout šanci na dobrý rozhovor (±20 p. b.).
const MOOD_WEIGHT := 0.2
## Stres nad TALK_STRESS_FREE u každého z dvojice ubírá (stres − práh) / TALK_STRESS_DIV.
## (Dřív práh 30 a dělitel 250 – stres z hádek pak sám živil další hádky, viz DEVLOG běh 15.)
const TALK_STRESS_FREE := 35.0
const TALK_STRESS_DIV := 320.0
## Penalizace podle dominantní emoce každého z dvojice: vztek nejvíc, únava a napětí méně
## (unavený nebo nervózní člověk je spíš stručný než útočný).
const TALK_EMOTION_PENALTY := {"nastvany": 0.12, "unaveny": 0.06, "napjaty": 0.06}
## De-eskalace: posluchač s náladou nad DEESCALATE_FROM může hádku utnout smířlivou odpovědí;
## šance roste lineárně do DEESCALATE_MAX při náladě DEESCALATE_FROM + DEESCALATE_SPAN.
const DEESCALATE_FROM := 20.0
const DEESCALATE_SPAN := 30.0
const DEESCALATE_MAX := 0.35
## Stížnost (třenice z domácnosti) jako tón oslovení: o tolik nižší šance na pohodu.
const COMPLAINT_PENALTY := 0.08
## Jak dlouho si postava stížnost „nese“ do příštího oslovení (pak to pustí z hlavy).
const COMPLAINT_TTL := 360.0
## Vyřešená stížnost (pohoda) obrousí křivdu o tolik.
const COMPLAINT_SOFTEN := 3.0
## Stres z hádky a jeho měkký strop: nad (strop − rampa) přibývá čím dál méně (min. ×0,15).
## Strop podle povahy (`argue_stress_cap`, vznětlivý 65: vybuchne a vyfučí, nekumuluje chronický stres).
const ARGUE_STRESS := 10.0
const ARGUE_STRESS_CAP := 85.0
const ARGUE_STRESS_RAMP := 25.0
const ARGUE_STRESS_MIN := 0.15
## Lineární návrat záporného vztahu k nule bez živé křivdy (bodů za den) navíc k exponenciálnímu hojení.
const DRIFT_NEG_PER_DAY := 2.0
## Od jaké hodnoty je vztah „přátelský“ (kamarád a výš) – pro text vzpomínek.
const FRIEND_LEVEL := 25.0
## Úroveň vztahu -> [mužský tvar, ženský tvar, neutrální opis] (sloupec podle gramatického rodu
## DRUHÉ postavy – Grammar.noun_col; neutrální opisy jsou ženského rodu → „moje blízká osoba“).
const REL_LEVELS := [
	[85.0, "nejlepší přítel", "nejlepší přítelkyně", "nejbližší osoba"],
	[60.0, "blízký přítel", "blízká přítelkyně", "blízká osoba"],
	[25.0, "kamarád", "kamarádka", "kamarádská duše"],
	[-24.9, "známý", "známá", "známá osoba"],
	[-60.0, "nepřítel", "nepřítelkyně", "nepřátelská osoba"],
	[-100.0, "úhlavní nepřítel", "úhlavní nepřítelkyně", "úhlavní nepřátelská osoba"],
]

var sim_name := "Postava"
## Gramatický rod postavy ("m"/"f"/"n"/"pl") – volba hráče z CharacterData, nezávislá na těle.
var grammar := "m"
## Zpětná kompatibilita (ženské tvary) – odvozené z rodu, nic jiného.
var female: bool:
	get:
		return grammar == "f"
## Veřejný vzhledový snapshot (CharacterData.public_snapshot) – vykreslení na všech peerech.
var look := {}
var body_color := Color(0.85, 0.55, 0.45)
var trait_ids: Array = []
var needs
var mood
var mental
## Individuální citlivosti (hluk, tlačenice, radost, práh těšení) a jejich návyky.
var sensory = SensoryProfile.new()
var _seed := 0
## Křivdy a vina (cesta zpět z konfliktu – omluva, usmíření).
var ledger
var rng := RandomNumberGenerator.new()
## Svět – musí mít get_smart_objects() a get_sims().
var world: Node = null

var state: int = State.IDLE
var current_action: Dictionary = {}
var target: Node3D = null
var target_point := Vector3.ZERO
var social_partner: Node3D = null
var action_elapsed := 0.0
var walk_elapsed := 0.0
var think_cooldown := 0.0
var last_action_id := ""
var action_counts := {}
var relationships := {}  # jméno postavy -> přátelství (-100 .. 100)
var last_talk := {}      # jméno postavy -> herní minuta posledního rozhovoru
var memories: Array = []  # {"t": herní minuty, "text": String}
var last_tag_time := {}  # tag akce -> herní minuta, kdy ji postava naposledy začala
## Fronta příkazů od hráče: [{"action": Dictionary, "target": Node3D|null}]
var player_queue: Array = []
var speech := ""
var speech_until := -1.0
## true = aktuální plán zadal hráč (nový příkaz ho nepřebije, jen se zařadí za něj).
var by_player := false
## jméno postavy -> herní minuta poslední urážky od ní
var insulted_by := {}
## jméno postavy -> {"topic", "t"}: co mě na ní štve (HouseholdDynamics); vyzní v příštím oslovení.
var pending_complaints := {}
## Aktivace na začátku rozhovoru (expozice) a jeho výsledek.
var _social_arousal_start := 0.0
var _social_positive := true
var _confide_dismissed := false
var _crowd_timer := 0.0
var _mind_sig := ""
var _helping_me := 0
## Číslo epizody ataky, u které už svědci reagovali (návrat do ataky po dýchání je stejná epizoda).
var _witnessed_episode := -1
## Poslední výsledek copingu (pro testy a UI).
var last_coping_result := {}
## Poslední prožitek dokončené akce {id, experienced, anticipated, surprise} a výsledek omluvy (testy).
var last_experience := {}
var last_apology := {}

# --- replikovaný stav (čte MultiplayerSynchronizer; na klientu ho zapisuje do SimPuppet)
var net_pos: Vector3:
	get:
		return position
var net_rot: float:
	get:
		return rotation.y
var net_label := ""
var net_emotion := "spokojeny"
var net_mood := 0
var net_posture := "stand"
var net_needs := PackedByteArray()
## "id_akce|index_objektu" během provádění akce (pro zvuky na klientech), jinak "".
var net_action := ""
var net_speech := ""
var net_detail := {}

var visual: Node3D
var _clock
var _detail_timer := 0.0
var _detail_dirty := true


## p_grammar: "m"/"f"/"n"/"pl" (starší volající můžou poslat bool = ženský rod).
func setup(p_name: String, p_grammar: Variant, p_traits: Array, p_color: Color, p_seed: int, p_world: Node) -> void:
	sim_name = p_name
	grammar = Grammar.norm(p_grammar) if typeof(p_grammar) == TYPE_STRING else ("f" if bool(p_grammar) else "m")
	trait_ids = p_traits
	body_color = p_color
	world = p_world
	rng.seed = p_seed
	_seed = p_seed
	needs = Needs.new(rng)
	mood = Mood.new()
	mental = MentalState.new(rng, grammar)
	mental.trait_vuln = Traits.sum_param(trait_ids, "vulnerability")
	mental.trait_dep = Traits.sum_param(trait_ids, "dep_vuln")
	mental.sensitivity = mental.baseline_sensitivity()
	ledger = RelLedger.new()
	Traits.apply_decay(trait_ids, needs)
	sensory.setup(trait_ids, {}, p_seed)
	name = node_name_for(p_name)


## Predispozice k duševním potížím: {"anxiety": 0.6}. Neznámé diagnózy ignoruje.
func set_conditions(conds: Dictionary) -> void:
	mental.conditions = {}
	for id in conds:
		if MentalState.CONDITIONS.has(String(id)) and (typeof(conds[id]) == TYPE_FLOAT or typeof(conds[id]) == TYPE_INT):
			mental.conditions[String(id)] = clampf(float(conds[id]), 0.0, 1.0)
	mental.sensitivity = mental.baseline_sensitivity(mental_cfg())
	sensory.setup(trait_ids, mental.conditions, _seed)


## Soukromá část CharacterData (jen server/offline): predispozice a vzorce z `mind`.
func apply_character_private(cd: Dictionary) -> void:
	var m = cd.get("mind", {})
	if typeof(m) != TYPE_DICTIONARY:
		return
	var p = m.get("predispositions", {})
	set_conditions(p if typeof(p) == TYPE_DICTIONARY else {})
	set_patterns({"morning_worse": bool(m.get("morning_worse", false))})
	# 1. osa psychiky (běh 20): individualita a explicitní osobnost jako háčky MentalState – pro všechny tři
	# režimy obsahu, MentalState si vybere podle aktuálního nastavení (přepnutí za běhu funguje hned).
	mental.set_psyche(PsycheModel.hooks_by_mode(cd))


## Individuální vzorce průběhu (ne univerzální příznaky): {"morning_worse": true}.
func set_patterns(p: Dictionary) -> void:
	mental.dep.morning_pattern = bool(p.get("morning_worse", false))


static func node_name_for(p_name: String) -> String:
	return p_name.validate_node_name().replace(" ", "_")


func _ready() -> void:
	_clock = get_node("/root/GameClock")
	visual = SimVisual.new()
	visual.configure(body_color, female)
	if not look.is_empty():
		visual.apply_look(look)
	add_child(visual)
	_clock.time_advanced.connect(sim_tick)
	_clock.day_changed.connect(_on_day_changed)
	think_cooldown = rng.randf_range(0.0, 3.0)
	for c in Traits.cravings(trait_ids):
		last_tag_time[c[0]] = _clock.total_minutes - rng.randf_range(0.0, float(c[1]) * 42.0)
	mood.evaluate(needs, trait_ids, _extra_moodlets())
	_update_net(0.0)
	_update_visual()


func _on_day_changed(_day: int) -> void:
	mental.new_day()


## Česká slovesa podle gramatického rodu: „Uvařil(a)“ -> „Uvařil“ / „Uvařila“ / „Uvařilo“ / „Uvařili“.
func gendered(text: String) -> String:
	return Grammar.form(text, grammar)


func first_name() -> String:
	return sim_name.split(" ")[0]


func display_action() -> String:
	if state == State.IDLE:
		return "Přemýšlí, co dál…"
	var label: String = current_action.get("label", "?")
	if state == State.WALKING:
		return "Jde: " + label.to_lower()
	return label


func get_mood_value() -> float:
	return mood.value


func get_emotion() -> String:
	return mood.emotion


## other_g: gramatický rod druhé postavy ("m"/"f"/"n"/"pl"; bool = ženský rod – zpětná kompatibilita).
static func relationship_label(value: float, other_g: Variant) -> String:
	var g: String = Grammar.norm(other_g) if typeof(other_g) == TYPE_STRING else ("f" if bool(other_g) else "m")
	var col := 1 + Grammar.noun_col(g)
	for lvl in REL_LEVELS:
		if value >= lvl[0]:
			return lvl[col]
	return REL_LEVELS[-1][col]


# ---------------------------------------------------------------- simulace

func sim_tick(dm: float) -> void:
	var suppress: Dictionary = {}
	if state == State.ACTING:
		suppress = current_action.get("suppress", {})
	# Cirkadiánní únava: v noci vzhůru energie ubývá rychleji.
	if _clock.is_night() and not (state == State.ACTING and current_action.get("tags", []).has("sleep")):
		suppress = suppress.duplicate()
		suppress["energy"] = float(suppress.get("energy", 1.0)) * 1.6
	# Napětí vyčerpává.
	suppress = suppress.duplicate()
	suppress["energy"] = float(suppress.get("energy", 1.0)) * mental.energy_drain_mult()
	needs.tick(dm, suppress)
	mood.tick(dm)
	sensory.tick(dm)
	_check_cravings()
	_mental_tick(dm)
	ledger.decay(dm, Traits.mult_param(trait_ids, "grudge_tau"), Traits.mult_param(trait_ids, "guilt_tau"))
	_heal_relationships(dm)
	mood.evaluate(needs, trait_ids, _extra_moodlets())
	if speech != "" and _clock.total_minutes > speech_until:
		speech = ""
	match state:
		State.IDLE:
			think_cooldown -= dm
			if not player_queue.is_empty():
				_run_queued()
			elif think_cooldown <= 0.0:
				_decide()
		State.WALKING:
			_walk(dm)
		State.ACTING:
			_act(dm)
	_update_net(dm)
	_update_visual()


## Aktuální herní čas v minutách.
## Kolik radosti postava právě dokáže prožít (anhedonie z deprese + stres + vlastní citlivost).
func joy_capacity() -> float:
	return sensory.joy_capacity(mental.dep.hedonic, mental.stress)


## Příjemný moodlet: síla podle toho, kolik radosti postava právě unese (ne každého potěší stejně).
func add_joy_moodlet(id: String, label: String, emo: String, strength: float, duration: float) -> void:
	var k := joy_capacity() if strength > 0.0 else 1.0
	if strength > 0.0 and strength * k < 1.0:
		return  # tak slabé, že to postava ani nevnímá
	mood.add_moodlet(id, label, emo, strength * k, duration)


func now() -> float:
	return _clock.total_minutes


## Čas hojí: záporný vztah bez živé křivdy se pomalu vrací k neutrálu (exponenciálně ~10 dní
## + lineárně DRIFT_NEG_PER_DAY). Dokud křivda trvá, nic se nehojí – proto má smysl ji uzavřít
## omluvou. Kladné vztahy se tu nemění (vyprchání bez kontaktu řeší HouseholdDynamics).
func _heal_relationships(dm: float) -> void:
	var k := 1.0 - exp(-dm / 14400.0)
	var lin := DRIFT_NEG_PER_DAY * dm / 1440.0
	for n in relationships:
		var r: float = float(relationships[n])
		if r < 0.0 and ledger.grudge(String(n)) < 5.0:
			relationships[n] = minf(r - r * k + lin, 0.0)


## Moodlety z jiných systémů: duševní stav + nejsilnější výčitky a křivda (přepočítávají se každý krok).
func _extra_moodlets() -> Array:
	var out: Array = mental.mood_entries()
	var gname := ""
	var gmax := 0.0
	for n in ledger.guilt:
		if float(ledger.guilt[n]) > gmax:
			gmax = float(ledger.guilt[n])
			gname = String(n)
	if gmax > 25.0:
		out.append({"id": "vycitky", "label": "Výčitky: " + gname.split(" ")[0], "emotion": "smutny",
			"strength": -lerpf(4.0, 12.0, clampf((gmax - 25.0) / 75.0, 0.0, 1.0)), "remaining": -1.0})
	var rname := ""
	var rmax := 0.0
	for n in ledger.grudges:
		if float(ledger.grudges[n]) > rmax:
			rmax = float(ledger.grudges[n])
			rname = String(n)
	if rmax > 30.0:
		out.append({"id": "krivda", "label": "Křivda: " + rname.split(" ")[0], "emotion": "nastvany",
			"strength": -lerpf(3.0, 10.0, clampf((rmax - 30.0) / 70.0, 0.0, 1.0)), "remaining": -1.0})
	return out


## Nastavení obsahu pro simulaci (na serveru platí nastavení serveru).
func mental_cfg() -> Dictionary:
	var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
	if gs == null:
		return {"conditions": true, "episodes": true, "thought_rate": 1.0}
	return {"conditions": gs.allows_conditions(), "episodes": gs.allows_episodes(), "thought_rate": gs.thought_rate()}


func content_allowed(tag: String) -> bool:
	if tag == "":
		return true
	var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
	return gs == null or gs.allows_content(tag)


func _is_sleeping() -> bool:
	return state == State.ACTING and current_action.get("tags", []).has("sleep")


func _in_panic_action() -> bool:
	return state == State.ACTING and bool(current_action.get("involuntary", false))


## Postava právě dělá něco, co během ataky pomáhá (dýchání, cesta za někým, komu se svěří).
func _grounding_now() -> bool:
	return state != State.IDLE and bool(current_action.get("usable_in_panic", false))


func _mental_tick(dm: float) -> void:
	var cfg := mental_cfg()
	var was_panic: bool = mental.panic_active
	var ctx := {"energy": needs.values["energy"], "hunger": needs.values["hunger"], "needs": needs.values,
		"sleeping": _is_sleeping(), "night": _clock.is_night(), "now": now(), "cfg": cfg, "hour": _clock.get_hour(),
		"grounding": _grounding_now() or _helping_me > 0}
	mental.tick(dm, ctx)
	# Tlačenice: kolik lidí je těsně kolem (sociální úzkost, samotáři).
	_crowd_timer -= dm
	if _crowd_timer <= 0.0 and world != null:
		_crowd_timer = CROWD_INTERVAL
		var near := 0.0
		var cnt := 0
		for o in world.get_sims():
			if o != self and o.global_position.distance_to(global_position) < CROWD_DIST:
				cnt += 1
				# Blízcy lidé nejsou „dav“ – oblíbený člověk vedle vadí jen napůl.
				near += 0.5 if float(relationships.get(o.sim_name, 0.0)) > 30.0 else 1.0
		if cnt >= 2:
			# Tlačenice nevyčerpává každého stejně (samotář vs. společenský) a člověk si zvyká.
			var amt := CROWD_STRESS * maxf(near - 1.0, 0.0) * sensory.crowd_factor()
			sensory.expose_crowd(CROWD_INTERVAL)
			if amt > 0.2:
				mental.on_stressor("crowd", amt, cfg)
	if mental.panic_active and not _in_panic_action() and not _grounding_now():
		_enter_panic()
	elif not mental.panic_active and was_panic:
		panic_changed.emit(self, false)
	if not mental.panic_active:
		_helping_me = 0  # samoléčení: bez ataky nikdo „nepomáhá“ (pojistka proti visícímu počítadlu)
	var sig := "%s|%d|%s" % [mental.state_label(), mental.thoughts.size(),
		mental.thoughts[-1]["text"] if not mental.thoughts.is_empty() else ""]
	if sig != _mind_sig:
		_mind_sig = sig
		_detail_dirty = true


## Panická ataka – mimovolný symptom. Přeruší, co postava dělá (hráčův rozdělaný příkaz
## vrátí na začátek fronty), hráč ale není zamčený: dýchání nebo svěření jde zadat i teď.
func _enter_panic() -> void:
	if not content_allowed("mental_health"):
		mental.end_panic()
		return
	var resume: Dictionary = {}
	if by_player and not current_action.is_empty() and not bool(current_action.get("involuntary", false)) \
			and not bool(current_action.get("system", false)) and String(current_action.get("object", "")) != "sim":
		resume = {"action": ActionLibrary.get_action(String(current_action.get("id", ""))), "target": target}
	if state == State.ACTING:
		_finish(true)
	elif state == State.WALKING:
		_abort()
	if not resume.is_empty() and not resume["action"].is_empty():
		player_queue.push_front(resume)
		while player_queue.size() > MAX_QUEUE:
			player_queue.pop_back()
	by_player = false
	current_action = ActionLibrary.get_action("panic").duplicate(true)
	target = null
	say(ActionLibrary.random_line("panic", rng))
	_begin_acting()
	# Návrat do ataky po dýchání je pořád stejná epizoda – svědci reagují jen jednou.
	if _witnessed_episode != mental.panic_count:
		_witnessed_episode = mental.panic_count
		remember("Panická ataka. Myslel(a) jsem, že umřu.")
		panic_changed.emit(self, true)
		_alert_witnesses()


## Svědci ataky reagují podle vztahu, povahy a vlastního stavu: pomoc, nebo stigma.
func _alert_witnesses() -> void:
	if world == null:
		return
	var cfg := mental_cfg()
	var helper_found := false
	for o in world.get_sims():
		if o == self or not o.has_method("command") or o.global_position.distance_to(global_position) > WITNESS_DIST:
			continue
		if o.by_player and o.state != State.IDLE:
			continue  # hráčova postava reaguje jen na hráčův příkaz
		if o._is_sleeping() or o.mental.panic_active:
			continue
		var rel: float = float(o.relationships.get(sim_name, 0.0))
		var stigma_p := clampf(0.08 + Traits.sum_param(o.trait_ids, "stigma") - rel / 150.0 + o.mental.stress / 300.0, 0.02, 0.8)
		var help_p := clampf(0.35 + rel / 100.0 - Traits.sum_param(o.trait_ids, "stigma"), 0.0, 0.9)
		if o.mental.arousal > 60.0:
			help_p *= 0.5  # kdo je sám v úzkosti, má málo sil pomáhat
		if rng.randf() < stigma_p:
			o.say(ActionLibrary.random_line("stigma", o.rng))
			mental.on_stressor("stigma", 10.0, cfg)
			mood.add_moodlet("stigma_" + String(o.name), "Zahanbení: " + o.first_name(), "smutny", -12.0, 480.0)
			relationships[o.sim_name] = clampf(float(relationships.get(o.sim_name, 0.0)) - 4.0, -100.0, 100.0)
			mental.add_thought("stigma", now(), {}, cfg)
			mental.dep.on_event(0.015, cfg)
			ledger.on_hurt_by(o.sim_name, 10.0, now())
			o.ledger.on_hurt_other(sim_name, 3.0)  # často si ani neuvědomí, jak moc ublížil/a
			remember("%s mi řekl%s, ať nedělám scény" % [o.sim_name, Grammar.past(o.grammar)])
		elif not helper_found and rng.randf() < help_p and o.state != State.WALKING:
			if o.state == State.ACTING:
				if not bool(o.current_action.get("interruptible", true)) or o.social_partner != null:
					continue
				o._finish(true)
			o.by_player = false
			o.start_plan(ActionLibrary.get_action("comfort_panic"), self)
			helper_found = true
	_detail_dirty = true


## Přijme někoho, kdo jde pomoct (jen během ataky).
func accepts_support() -> bool:
	return mental.panic_active or _in_panic_action()


func receive_support_from(helper: Node3D) -> void:
	var rel: float = float(helper.relationships.get(sim_name, 0.0))
	mental.receive_support(rel, Traits.mult_param(trait_ids, "support_accept"), now())
	add_joy_moodlet("pomoc_" + String(helper.name), "Někdo při mně stál", "spokojeny", 8.0, 600.0)
	remember("%s mi pomohl%s při panické atace" % [helper.sim_name, Grammar.past(helper.grammar)])
	for pair in [[self, helper], [helper, self]]:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var c0: float = float(a.relationships.get(b.sim_name, 0.0))
		a.relationships[b.sim_name] = clampf(c0 + 4.0, -100.0, 100.0)
		a.note_relationship_change(b, c0, float(a.relationships[b.sim_name]))
		a._detail_dirty = true
	helper.say(ActionLibrary.random_line("support", helper.rng))


## Bude partner naslouchat, nebo odbyde? (pro svěření se)
func dismisses_confide(asker: Node3D) -> bool:
	var rel: float = float(relationships.get(asker.sim_name, 0.0))
	var p := clampf(0.12 + Traits.sum_param(trait_ids, "stigma") - rel / 120.0 + mental.stress / 250.0, 0.03, 0.85)
	if mood.emotion == "nastvany":
		p += 0.15
	return rng.randf() < p


func _decide() -> void:
	var choice: Dictionary = Planner.choose(self, world.get_smart_objects(), world.get_sims(), rng, _clock.get_hour())
	if choice.is_empty():
		think_cooldown = 5.0
		return
	by_player = false
	start_plan(choice["action"], choice["target"])


func start_plan(action: Dictionary, tgt: Node3D) -> void:
	current_action = action
	target = tgt
	walk_elapsed = 0.0
	if tgt == null:
		_begin_acting()
		return
	if tgt.has_method("reserve"):
		if not tgt.reserve(self):
			_abort()
			return
		target_point = tgt.get_use_position(self)
	state = State.WALKING


# ---------------------------------------------------------------- příkazy hráče

## Příkaz od hráče (už zvalidovaný NetSession). action["id"] == "cancel" zruší frontu
## i probíhající akci. Ostatní akce se zařadí do fronty; přeruší přerušitelnou akci.
## Vrací false, když je fronta plná.
## Postava odchází ze světa (hráč s vlastní postavou se odpojil): ukončí akci, uvolní objekt
## a rozhovor, aby po ní nezůstaly rezervace ani „visící“ partner.
func leave_world() -> void:
	player_queue.clear()
	if state == State.ACTING:
		_finish(true)
	elif state == State.WALKING:
		_abort()
	_leave_target()
	target = null
	if _clock != null and _clock.time_advanced.is_connected(sim_tick):
		_clock.time_advanced.disconnect(sim_tick)
		_clock.day_changed.disconnect(_on_day_changed)


func command(action: Dictionary, tgt: Node3D) -> bool:
	if action.get("id", "") == "cancel":
		player_queue.clear()
		if _in_panic_action():
			return true  # symptom se zrušit nedá – fronta se vyprázdní, ataka doběhne
		if state == State.ACTING:
			if current_action.get("tags", []).has("sleep"):
				mood.add_moodlet("rozespaly", "Rozespalý – někdo ho vzbudil", "unaveny", -8.0, 120.0)
			_finish(true)
		elif state == State.WALKING:
			_abort()
		think_cooldown = 3.0
		return true
	# Během panické ataky: dýchání / svěření ji přeruší (hráč má vždy možnost jednat –
	# ani plná fronta to nezablokuje), ostatní příkazy počkají, až ataka odezní.
	if _in_panic_action() and bool(action.get("usable_in_panic", false)):
		player_queue.push_front({"action": action, "target": tgt})
		while player_queue.size() > MAX_QUEUE:
			player_queue.pop_back()
		_finish(true)
		_run_queued()
		return true
	if player_queue.size() >= MAX_QUEUE:
		return false
	if _in_panic_action():
		player_queue.append({"action": action, "target": tgt})
		return true
	player_queue.append({"action": action, "target": tgt})
	if state == State.IDLE:
		_run_queued()
	elif not by_player:
		# Vlastní rozhodnutí AI hráč přebije hned; hráčovy příkazy se řadí za sebe.
		if state == State.WALKING:
			_abort()
			_run_queued()
		elif bool(current_action.get("interruptible", true)):
			_finish(true)
			_run_queued()
	return true


func _run_queued() -> void:
	while not player_queue.is_empty():
		var cmd: Dictionary = player_queue.pop_front()
		var tgt = cmd["target"]
		if tgt != null and not is_instance_valid(tgt):
			continue
		if tgt != null and tgt.has_method("is_available") and not tgt.is_available(self):
			mood.add_moodlet("obsazeno", "Obsazeno! Někdo mě předběhl", "nesvuj", -4.0, 60.0)
			continue
		if tgt != null and _is_sim(tgt):
			if bool(cmd["action"].get("approach_only", false)):
				if not tgt.accepts_support():
					continue
			elif not tgt.can_join_social(self):
				continue
		by_player = true
		if _maybe_hesitate(cmd):
			return
		start_plan(cmd["action"], tgt)
		return


## Deprese: bariéra iniciace u hráčova příkazu. Příkaz se nikdy neodmítne – postava se jen
## může chvíli „nemoct dokopat“ (zrušitelné; po váhání příkaz provede). Ne vždy a ne u lehkých akcí.
func _maybe_hesitate(cmd: Dictionary) -> bool:
	if bool(cmd.get("hesitated", false)) or not content_allowed("mental_health"):
		return false
	if not bool(mental_cfg().get("episodes", true)):
		return false
	var b: float = mental.dep.barrier(ActionLibrary.effort(cmd["action"]))
	if b < 0.3 or rng.randf() > b * 1.4:
		return false
	cmd["hesitated"] = true
	player_queue.push_front(cmd)
	var h: Dictionary = ActionLibrary.get_action("hesitate").duplicate(true)
	h["duration"] = rng.randf_range(4.0, 6.0 + b * 30.0)
	h["label"] = "Nemůže se dokopat: " + String(cmd["action"].get("label", "")).to_lower()
	current_action = h
	target = null
	if rng.randf() < 0.5:
		say(ActionLibrary.random_line("hesitate", rng))
	_begin_acting()
	return true


# ---------------------------------------------------------------- pohyb a akce

func _walk(dm: float) -> void:
	walk_elapsed += dm
	if target == null or not is_instance_valid(target):
		_abort()
		return
	if _is_sim(target):
		var approach := bool(current_action.get("approach_only", false))
		if (approach and not target.accepts_support()) or (not approach and not target.can_join_social(self)):
			_abort()
			return
		var off := global_position - target.global_position
		off.y = 0.0
		if off.length() < 0.01:
			off = Vector3.RIGHT
		target_point = target.global_position + off.normalized() * SOCIAL_TALK_DIST
	var to := target_point - global_position
	to.y = 0.0
	var d := to.length()
	if d <= ARRIVE_DIST:
		global_position = Vector3(target_point.x, global_position.y, target_point.z)
		_arrive()
		return
	var dir := to / d
	global_position += dir * minf(d, WALK_SPEED * dm)
	_face(dir)
	if walk_elapsed > MAX_WALK_MINUTES:
		_abort()


func _arrive() -> void:
	if _is_sim(target) and bool(current_action.get("approach_only", false)):
		if not target.accepts_support():
			_abort()
			return
		current_action = current_action.duplicate(true)
		current_action["label"] = "Uklidňuje: " + target.first_name()
		target.receive_support_from(self)
		target._helping_me += 1
		_begin_acting()
		return
	if _is_sim(target):
		var partner: Node3D = target
		if not partner.can_join_social(self):
			_abort()
			return
		_start_social(partner)
		return
	_begin_acting()


func _begin_acting() -> void:
	state = State.ACTING
	action_elapsed = 0.0
	var id: String = current_action["id"]
	action_counts[id] = int(action_counts.get(id, 0)) + 1
	for t in current_action.get("tags", []):
		last_tag_time[t] = _clock.total_minutes
		mood.remove_moodlet("craving_" + t)
	if target != null and is_instance_valid(target):
		if target.has_method("get_pose_position") and current_action.get("posture", "stand") != "stand":
			global_position = target.get_pose_position(self)
		var look := target.global_position - global_position
		look.y = 0.0
		if look.length() > 0.05:
			_face(look.normalized())
		if current_action.get("posture", "stand") == "lie":
			rotation.y = target.rotation.y
	action_started.emit(self, current_action)


func _act(dm: float) -> void:
	action_elapsed += dm
	var dur: float = float(current_action.get("duration", 30.0))
	var eff: Dictionary = current_action.get("effects", {})
	for k in eff:
		var dv: float = float(eff[k]) * dm / dur
		if k == "fun" and dv > 0.0:
			dv *= mental.dep.fun_mult()  # anhedonie: totéž baví méně
		needs.add(k, dv)
	var rate: Dictionary = current_action.get("rate", {})
	var sq: float = mental.sleep_quality() if current_action.get("tags", []).has("sleep") else 1.0
	for k in rate:
		needs.add(k, float(rate[k]) * dm / 60.0 * (sq if k == "energy" else 1.0))
	# Panická ataka končí, když odezní aktivace (řídí MentalState).
	if bool(current_action.get("involuntary", false)) and not mental.panic_active:
		_finish(false)
		return
	# Pomoc při atace končí, když se postava uklidnila.
	if bool(current_action.get("approach_only", false)):
		if target == null or not is_instance_valid(target) or not target.accepts_support():
			_finish(false)
			return
	# Spánek do plna – ale v noci se nevstává (jen ráno nebo přes den).
	var uf: String = current_action.get("until_full", "")
	if uf != "" and needs.values[uf] >= 99.0 and action_elapsed > 30.0:
		var h: int = _clock.get_hour()
		if not current_action.get("tags", []).has("sleep") or (h >= 6 and h < 22):
			_finish(false)
			return
	# Spánek přes den jen do 75 % – aby postava večer zase usnula a rytmus se srovnal.
	if current_action.get("tags", []).has("sleep") and action_elapsed > 30.0:
		var hh: int = _clock.get_hour()
		if hh >= 9 and hh < 21 and needs.values["energy"] >= 75.0:
			_finish(false)
			return
	if action_elapsed >= dur:
		_finish(false)
		return
	if social_partner != null:
		if not is_instance_valid(social_partner) or social_partner.social_partner != self:
			_finish(false)
			return
	# Kritická potřeba přeruší akci, která ji neřeší (např. hlad během televize nebo spánku).
	if action_elapsed > 10.0:
		var low: String = needs.lowest()
		var limit := 8.0 if current_action.get("interruptible", true) else 3.0
		# Spánek budí jen tělo (hlad), ne samota, nuda nebo nepohodlí – jinak se z osamělosti
		# stane nespavost, která roztočí spirálu vyčerpání a stresu.
		var sleeping_now: bool = current_action.get("tags", []).has("sleep")
		if sleeping_now:
			if needs.values["hunger"] < limit:
				_finish(true)
		elif needs.values[low] < limit and not eff.has(low) and not rate.has(low):
			_finish(true)


func _finish(interrupted: bool) -> void:
	var id: String = current_action.get("id", "")
	var dur: float = maxf(float(current_action.get("duration", 30.0)), 1.0)
	var cop: String = current_action.get("coping", "")
	if cop != "":
		var frac := clampf(action_elapsed / dur, 0.0, 1.0) if interrupted else 1.0
		var cctx := {"now": now(), "energy": needs.values["energy"], "hunger": needs.values["hunger"],
			"day": _clock.get_day(), "cfg": mental_cfg()}
		if social_partner != null and is_instance_valid(social_partner):
			cctx["rel"] = float(relationships.get(social_partner.sim_name, 0.0))
			cctx["dismissed"] = _confide_dismissed
		last_coping_result = mental.apply_coping(cop, frac, cctx)
		last_coping_result["id"] = cop
		_detail_dirty = true
	if bool(current_action.get("involuntary", false)) and not interrupted:
		mental.end_panic()
	if bool(current_action.get("approach_only", false)) and target != null and is_instance_valid(target):
		target._helping_me = maxi(target._helping_me - 1, 0)
	if not interrupted and social_partner != null and is_instance_valid(social_partner) \
			and current_action.get("tags", []).has("social") and cop == "":
		var th: String = mental.on_social_completed(_social_positive, _social_arousal_start,
			social_partner.sim_name, social_partner.grammar, now(), mental_cfg())
		if th != "":
			_detail_dirty = true
	if not interrupted and not bool(current_action.get("system", false)) and not bool(current_action.get("involuntary", false)):
		_experience_finished()
	if not interrupted:
		var ml: Array = current_action.get("moodlet", [])
		if ml.size() == 5:
			var scale := Traits.moodlet_multiplier(trait_ids, current_action.get("tags", []))
			if float(ml[3]) > 0.0:
				scale *= joy_capacity()  # liking: prožitá radost (anhedonie a stres ji tlumí, citlivost postavy)
			mood.add_moodlet(ml[0], ml[1], ml[2], float(ml[3]) * scale, float(ml[4]))
			# Do paměti jen silné zážitky (např. gurmánovo vaření).
			var mem = current_action.get("memory", null)
			if mem != null and float(ml[3]) * scale >= MEMORABLE_STRENGTH:
				remember(String(mem))
	_leave_target()
	var partner := social_partner
	social_partner = null
	if partner != null and is_instance_valid(partner) and partner.social_partner == self:
		partner._finish(false)
	last_action_id = id
	current_action = {}
	target = null
	state = State.IDLE
	think_cooldown = rng.randf_range(1.0, 4.0)
	action_finished.emit(self, id, interrupted)


## Dokončená akce: prožitek vs. očekávání (učení wanting) a behaviorální aktivace.
func _experience_finished() -> void:
	var id: String = current_action.get("id", "")
	var tags: Array = current_action.get("tags", [])
	var prior := ActionLibrary.hedonic_prior(current_action) * Traits.moodlet_multiplier(trait_ids, tags)
	var res := {}
	if prior > 0.0:
		res = mental.dep.experience(id, prior)
	var eff := ActionLibrary.effort(current_action)
	var relief := 0.0
	if eff >= 0.1:
		relief = mental.dep.on_activity(id, eff, float(res.get("surprise", 0.0)), now())
	if float(res.get("surprise", 0.0)) > 3.0 and mental.dep.pessimism > 0.3:
		mood.add_moodlet("lepsi_nez_cekal", gendered("Bylo to lepší, než jsem čekal(a)"), "spokojeny", 5.0, 180.0)
	last_experience = res.duplicate()
	last_experience["id"] = id
	last_experience["relief"] = relief


func _abort() -> void:
	_leave_target()
	last_action_id = current_action.get("id", "")
	current_action = {}
	target = null
	state = State.IDLE
	think_cooldown = rng.randf_range(2.0, 5.0)


func _leave_target() -> void:
	if target != null and is_instance_valid(target) and target.has_method("release"):
		if current_action.get("posture", "stand") != "stand" and state == State.ACTING:
			global_position = target.get_use_position(self)
		target.release(self)


## Touhy povahy: když postava dlouho nedělá, co potřebuje (Aktivní – pohyb), znervózní.
func _check_cravings() -> void:
	for c in Traits.cravings(trait_ids):
		var tag: String = c[0]
		var since: float = _clock.total_minutes - float(last_tag_time.get(tag, _clock.total_minutes))
		if since > float(c[1]) * 60.0:
			mood.add_moodlet("craving_" + tag, c[2], c[3], float(c[4]), 5.0)


# ---------------------------------------------------------------- sociální

func _is_sim(n: Node) -> bool:
	return n != null and n.has_method("can_join_social")


func can_join_social(_asker: Node3D) -> bool:
	if social_partner != null:
		return false
	# Postava plní příkaz svého hráče – nikdo (AI ani jiný hráč) ji nepřeruší.
	if by_player and state != State.IDLE:
		return false
	if needs.values["energy"] < 5.0:
		return false
	if state == State.ACTING:
		return bool(current_action.get("interruptible", true))
	if state == State.WALKING and _is_sim(target):
		return false
	return true


## Postava přeruší, co dělá, a připojí se k rozhovoru.
func join_social(partner: Node3D, action: Dictionary) -> void:
	if state != State.IDLE:
		_leave_target()
	if state == State.ACTING and bool(current_action.get("approach_only", false)) and target != null and is_instance_valid(target):
		target._helping_me = maxi(target._helping_me - 1, 0)
	if state == State.ACTING and current_action.has("id"):
		# Přerušená akce musí skončit i pro posluchače (zvuky objektů, statistiky).
		action_finished.emit(self, String(current_action["id"]), true)
	by_player = false
	current_action = action
	target = partner
	social_partner = partner
	state = State.ACTING
	action_elapsed = 0.0
	action_counts["chat"] = int(action_counts.get("chat", 0)) + 1
	_social_arousal_start = mental.arousal
	_social_positive = true
	_confide_dismissed = false
	_face((partner.global_position - global_position).normalized())
	action_started.emit(self, current_action)


func say(text: String) -> void:
	speech = gendered(text)
	speech_until = _clock.total_minutes + SPEECH_MINUTES


func _start_social(partner: Node3D) -> void:
	var forced: String = current_action.get("forced_outcome", "")
	var act: Dictionary = current_action.duplicate(true)
	var partner_act: Dictionary
	_social_arousal_start = mental.arousal
	_social_positive = true
	_confide_dismissed = false
	if String(act.get("coping", "")) == "confide":
		_start_confide(partner, act)
		return
	if String(act.get("id", "")) == "apologize":
		_start_apology(partner, act)
		return
	if forced == "negative" and _clock.total_minutes - float(partner.insulted_by.get(sim_name, -1.0e9)) < INSULT_IGNORE_MINUTES:
		# Opakovaná urážka v krátké době: oběť se otočí a odejde. Útočník nadává do prázdna,
		# oběť to jen otráví – nepřeruší ji to (ochrana proti „zamykání“ cizí postavy).
		act["label"] = "Nadává do prázdna"
		act["duration"] = 6.0
		act["effects"] = {}
		say(ActionLibrary.random_line("insult", rng))
		partner.mood.add_moodlet("obtezuje_" + String(name), "Obtěžuje mě: " + first_name(), "nastvany", -6.0, 120.0)
		var rel: float = float(partner.relationships.get(sim_name, 0.0))
		partner.relationships[sim_name] = clampf(rel - 2.0, -100.0, 100.0)
		partner._detail_dirty = true
		current_action = act
		target = null
		_begin_acting()
		return
	if forced == "negative":
		# Urážka (příkaz hráče) – vždy konflikt, trvalý dopad na vztah.
		partner.insulted_by[sim_name] = _clock.total_minutes
		act["label"] = "Uráží: " + partner.first_name()
		partner_act = act.duplicate(true)
		partner_act["label"] = "Hádá se s: " + first_name()
		partner_act["effects"] = {"social": 2.0, "fun": -8.0}
		say(ActionLibrary.random_line("insult", rng))
		_social_outcome(partner, -rng.randf_range(9.0, 15.0), "insult")
		partner.join_social(self, partner_act)
		_social_positive = false
		partner._social_positive = false
		# Replika oběti mluví o útočníkovi – rod („řekl/řekla“) podle útočníka.
		partner.say(ActionLibrary.random_line("insulted", rng).replace("(a)", Grammar.past(grammar)))
	else:
		# Chemie: povahy + nálady + dosavadní vztah (+ stížnost z domácnosti). Může to být i hádka.
		var complaint := take_complaint(partner)
		var p := talk_success_chance(partner, complaint)
		if complaint != "":
			say(ActionLibrary.random_line("complaint_" + complaint, rng))
		var success := rng.randf() < p
		# Volitelný modulátor (--fccs, jen headless experiment): výsledek smíchá s FCCS mozkem partnera.
		if social_oracle != null:
			var od: Dictionary = social_oracle.decide(self, partner, p, complaint)
			if not od.is_empty():
				success = bool(od["success"])
		# De-eskalace: posluchač v dobré náladě ostrý tón občas přejde a odpoví smířlivě.
		var deesc := false
		if not success and rng.randf() < deescalation_chance(partner):
			success = true
			deesc = true
		if success:
			act["label"] = "Povídá si s: " + partner.first_name()
			_social_outcome(partner, rng.randf_range(2.0, 6.0), "chat")
			if complaint != "":
				# Stížnost vyřešená v klidu („jo, promiň, budu tišší“) – křivda se obrousí.
				ledger.soften(partner.sim_name, COMPLAINT_SOFTEN)
				partner.say(ActionLibrary.random_line("complaint_ok", partner.rng))
			elif deesc:
				partner.say(ActionLibrary.random_line("deescalate", partner.rng))
		else:
			act["label"] = "Hádá se s: " + partner.first_name()
			act["effects"] = {"social": 8.0, "fun": -6.0}
			act["duration"] = 15.0
			if complaint == "":
				say(ActionLibrary.random_line("argue", rng))
			_social_outcome(partner, -rng.randf_range(5.0, 10.0), "argue")
		partner_act = act.duplicate(true)
		partner_act["label"] = act["label"].split(":")[0] + ": " + first_name()
		partner.join_social(self, partner_act)
		_social_positive = success
		partner._social_positive = success
		if not success:
			partner.say(ActionLibrary.random_line("argue", partner.rng))
		conversation.emit(self, partner, {"success": success, "avg_mood": (mood.value + partner.mood.value) * 0.5,
			"complaint": complaint, "deescalated": deesc, "p": p})
	current_action = act
	social_partner = partner
	_begin_acting()


## Šance, že běžný rozhovor s `partner` dopadne dobře (0,08..0,92). complaint = téma stížnosti.
func talk_success_chance(partner: Node3D, complaint := "") -> float:
	var friendship: float = float(relationships.get(partner.sim_name, 0.0))
	var p := TALK_BASE
	p += Traits.chemistry(trait_ids) + Traits.chemistry(partner.trait_ids)
	# Nálada obou: v dobré náladě člověk víc snese, ve špatné vybuchne dřív (max ±MOOD_WEIGHT).
	p += clampf((mood.value + partner.mood.value) * 0.5 / 100.0, -1.0, 1.0) * MOOD_WEIGHT
	p += friendship / 300.0
	# Stres a vznětlivost zvyšují riziko hádky.
	p -= (maxf(mental.stress - TALK_STRESS_FREE, 0.0) + maxf(partner.mental.stress - TALK_STRESS_FREE, 0.0)) / TALK_STRESS_DIV
	p -= Traits.sum_param(trait_ids, "argue_bias") + Traits.sum_param(partner.trait_ids, "argue_bias")
	# Špatná nálada (naštvaný, unavený, napjatý) zvyšuje riziko konfliktu.
	for e in [mood.emotion, partner.mood.emotion]:
		p -= float(TALK_EMOTION_PENALTY.get(e, 0.0))
	if complaint != "":
		p -= COMPLAINT_PENALTY
	return clampf(p, 0.08, 0.92)


## Šance, že `listener` utne začínající hádku smířlivou odpovědí (podle jeho nálady).
static func deescalation_chance(listener: Node3D) -> float:
	return DEESCALATE_MAX * clampf((float(listener.mood.value) - DEESCALATE_FROM) / DEESCALATE_SPAN, 0.0, 1.0)


## Vybere (a spotřebuje) čerstvou stížnost na `partner`; prošlé zahodí. Vrací téma nebo "".
func take_complaint(partner: Node3D) -> String:
	var c = pending_complaints.get(partner.sim_name, null)
	pending_complaints.erase(partner.sim_name)
	if typeof(c) != TYPE_DICTIONARY:
		return ""
	if now() - float(c.get("t", -1.0e9)) > COMPLAINT_TTL:
		return ""
	return String(c.get("topic", ""))


## Stres z hádky podle aktuálního stresu a povahy (měkký strop – viz ARGUE_STRESS_CAP).
func argue_stress_amount() -> float:
	var cap := Traits.get_param(trait_ids, "argue_stress_cap", ARGUE_STRESS_CAP)
	var f := clampf((cap - mental.stress) / ARGUE_STRESS_RAMP, ARGUE_STRESS_MIN, 1.0)
	return ARGUE_STRESS * Traits.mult_param(trait_ids, "stress_gain") * f


## Zapíše do paměti změnu úrovně vztahu k `b` (cur → nv) podle SMĚRU i úrovně:
## zlepšení na přátelskou úroveň („je teď moje kamarádka“), zlepšení z nepřátelství („už není
## můj nepřítel“), ochlazení přátelství („už není moje nejlepší přítelkyně“) a zhoršení do
## nepřátelství („je teď můj nepřítel“). Beze změny úrovně nic.
func note_relationship_change(b: Node3D, cur: float, nv: float) -> void:
	var old_l := relationship_label(cur, b.grammar)
	var new_l := relationship_label(nv, b.grammar)
	if old_l == new_l or is_equal_approx(cur, nv):
		return
	var pron := Grammar.my(b.grammar)
	if nv > cur:
		if nv >= FRIEND_LEVEL:
			remember("%s je teď %s %s" % [b.sim_name, pron, new_l])
			add_joy_moodlet("novy_vztah_" + b.name, "Nové přátelství" if cur < FRIEND_LEVEL else "Sblížili jsme se",
				"stastny", 15.0, 360.0)
		else:
			remember("Vztah se zlepšil: %s už není %s %s" % [b.sim_name, pron, old_l])
	elif cur >= FRIEND_LEVEL:
		remember("Vztah se ochladil: %s už není %s %s" % [b.sim_name, pron, old_l])
	else:
		remember("Vztah se zhoršil: %s je teď %s %s" % [b.sim_name, pron, new_l])


## Svěření se: partner buď naslouchá, nebo odbyde (stigma). Výsledek ovlivní vztah i úlevu.
func _start_confide(partner: Node3D, act: Dictionary) -> void:
	var dismissed: bool = partner.dismisses_confide(self)
	_confide_dismissed = dismissed
	var partner_act: Dictionary = act.duplicate(true)
	partner_act.erase("coping")  # coping (úleva) patří jen tomu, kdo se svěřuje
	partner_act.erase("usable_in_panic")
	if dismissed:
		act["label"] = "Svěřuje se: " + partner.first_name()
		act["duration"] = 12.0
		partner_act["label"] = "Odbývá: " + first_name()
		partner_act["duration"] = 12.0
		partner_act["effects"] = {"social": 3.0}
		mood.add_moodlet("odbyti_" + String(partner.name), "Odbyl%s mě: %s" % [Grammar.past(partner.grammar), partner.first_name()],
			"smutny", -10.0, 360.0)
		var rc: float = float(relationships.get(partner.sim_name, 0.0))
		relationships[partner.sim_name] = clampf(rc - 4.0, -100.0, 100.0)
		note_relationship_change(partner, rc, float(relationships[partner.sim_name]))
		ledger.on_hurt_by(partner.sim_name, 8.0, now())
		remember("Svěřil(a) jsem se a %s to odbyl%s" % [partner.sim_name, Grammar.past(partner.grammar)])
		_social_positive = false
	else:
		act["label"] = "Svěřuje se: " + partner.first_name()
		partner_act["label"] = "Naslouchá: " + first_name()
		add_joy_moodlet("vyslechl_" + String(partner.name), "Někdo mě vyslechl", "spokojeny", 10.0, 480.0)
		for pair in [[self, partner], [partner, self]]:
			var a: Node3D = pair[0]
			var b: Node3D = pair[1]
			var c0: float = float(a.relationships.get(b.sim_name, 0.0))
			a.relationships[b.sim_name] = clampf(c0 + 3.0, -100.0, 100.0)
			a.note_relationship_change(b, c0, float(a.relationships[b.sim_name]))
		remember("Svěřil(a) jsem se – %s mě vyslechl%s" % [partner.sim_name, Grammar.past(partner.grammar)])
	_detail_dirty = true
	partner._detail_dirty = true
	partner.join_social(self, partner_act)
	partner.say(ActionLibrary.random_line("confide_dismiss" if dismissed else "confide_ok", partner.rng))
	partner._social_positive = not dismissed
	_social_positive = not dismissed
	current_action = act
	social_partner = partner
	_begin_acting()


## Omluva: přijetí / „uvidíme“ / odmítnutí podle křivdy, vztahu, povahy, stresu a upřímnosti
## (historie omluv a porušených omluv). Spam omluv oběť nepřeruší – jen ji otráví.
func _start_apology(partner: Node3D, act: Dictionary) -> void:
	var t := now()
	var cfg := mental_cfg()
	var rel_p: float = float(partner.relationships.get(sim_name, 0.0))
	var ev: Dictionary = partner.ledger.evaluate_apology(sim_name, t, rel_p,
		Traits.sum_param(partner.trait_ids, "forgiveness"), partner.mental.stress, partner.rng.randf())
	var outcome: String = ev["outcome"]
	last_apology = ev.duplicate()
	last_apology["target"] = partner.sim_name
	partner.ledger.receive_apology(sim_name, outcome, t)
	ledger.apology_given(partner.sim_name, outcome, t)
	var g := Grammar.past(grammar)
	var reply := ActionLibrary.random_line("apology_" + outcome, partner.rng).replace("(a)", g)
	say(ActionLibrary.random_line("apology", rng))
	act["label"] = "Omlouvá se: " + partner.first_name()
	_detail_dirty = true
	partner._detail_dirty = true
	# Spam a omluva „za nic“ druhého NEPŘERUŠÍ (nejde tím zdržovat cizí postavu) – jen odpoví.
	if outcome == "spam" or outcome == "none":
		act["label"] = "Omlouvá se do prázdna" if outcome == "spam" else "Omlouvá se: " + partner.first_name()
		act["duration"] = 6.0
		act["effects"] = {}
		if outcome == "spam":
			partner.mood.add_moodlet("otravuje_" + String(name), "Otravuje s omluvami: " + first_name(), "nesvuj", -4.0, 120.0)
			partner.relationships[sim_name] = clampf(rel_p - 1.0, -100.0, 100.0)
		partner.say(reply)
		current_action = act
		target = null
		_begin_acting()
		return
	var partner_act: Dictionary = act.duplicate(true)
	partner_act["label"] = "Poslouchá omluvu: " + first_name()
	partner_act["effects"] = {"social": 4.0}
	match outcome:
		"accepted":
			for pair in [[self, partner], [partner, self]]:
				var a: Node3D = pair[0]
				var b: Node3D = pair[1]
				var cur: float = float(a.relationships.get(b.sim_name, 0.0))
				var nv := clampf(cur + 8.0, -100.0, 100.0)
				a.relationships[b.sim_name] = nv
				a.add_joy_moodlet("usmireni_" + String(b.name), "Usmířili jsme se: " + b.first_name(), "spokojeny", 10.0, 480.0)
				a.remember("Usmířil(a) jsem se – %s" % b.sim_name)
				a.note_relationship_change(b, cur, nv)
				a.social_event.emit(a, true, relationship_label(cur, b.grammar) != relationship_label(nv, b.grammar))
				a.mood.remove_moodlet("hadka_" + String(b.name))
				a.mood.remove_moodlet("urazka_" + String(b.name))
			mood.remove_moodlet("vycitky_" + String(partner.name))
		"partial":
			partner.relationships[sim_name] = clampf(rel_p + 2.0, -100.0, 100.0)
			mood.add_moodlet("omluva_zkusil_" + String(partner.name), gendered("Aspoň jsem to zkusil(a)"), "spokojeny", 3.0, 240.0)
		"rejected":
			mood.add_moodlet("odmitnuta_omluva_" + String(partner.name), "Odmítnutá omluva", "smutny", -8.0, 300.0)
			remember("%s odmítl%s moji omluvu" % [partner.sim_name, Grammar.past(partner.grammar)])
			mental.dep.on_event(0.01, cfg)
			if Traits.mult_param(trait_ids, "pride") < 0.8:
				# Pyšného odmítnutí naštve – „tak si trhni“.
				relationships[partner.sim_name] = clampf(float(relationships.get(partner.sim_name, 0.0)) - 3.0, -100.0, 100.0)
	partner.join_social(self, partner_act)
	partner.say(reply)
	var ok := outcome != "rejected"
	_social_positive = ok
	partner._social_positive = ok
	current_action = act
	social_partner = partner
	_begin_acting()


## kind: "chat" (příjemný hovor), "argue" (hádka), "insult" (urážka od self směrem k partnerovi).
func _social_outcome(partner: Node3D, delta: float, kind: String) -> void:
	var now: float = _clock.total_minutes
	var positive := kind == "chat"
	var cfg := mental_cfg()
	# Stres z konfliktu (vznětliví ho nabírají rychleji, ale s nižším stropem) a svědci hádky.
	if kind == "argue":
		mental.on_stressor("argue", argue_stress_amount(), cfg)
		partner.mental.on_stressor("argue", partner.argue_stress_amount(), cfg)
	elif kind == "insult":
		mental.on_stressor("insult", 3.0 * Traits.mult_param(trait_ids, "stress_gain"), cfg)
		partner.mental.on_stressor("insulted", 16.0 * Traits.mult_param(partner.trait_ids, "stress_gain"), cfg)
	if not positive:
		_witness_conflict(partner, cfg)
	else:
		_check_jealousy(partner, cfg)
	# Křivdy a vina: hádka zraní oba, urážka hlavně oběť (útočník cítí vinu, pokud se zrovna „neulevil“).
	if kind == "argue":
		ledger.on_hurt_by(partner.sim_name, 8.0, now)
		partner.ledger.on_hurt_by(sim_name, 8.0, now)
		ledger.on_hurt_other(partner.sim_name, 5.0)
		partner.ledger.on_hurt_other(sim_name, 5.0)
	elif kind == "insult":
		partner.ledger.on_hurt_by(sim_name, 25.0, now)
		var vented: bool = trait_ids.has("brucoun") or mood.emotion == "nastvany"
		ledger.on_hurt_other(partner.sim_name, 6.0 if vented else 20.0)
	for pair in [[self, partner], [partner, self]]:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var cur: float = float(a.relationships.get(b.sim_name, 0.0))
		var d := delta
		# Klesající výnos: blízké vztahy rostou pomaleji, opakovaný hovor brzy po sobě skoro nic.
		if d > 0.0:
			d *= clampf(1.0 - cur / 110.0, 0.1, 1.0)
			# Nevyřešená křivda brzdí oteplování; příjemný hovor ji pomalu obrušuje.
			d *= a.ledger.warmth_mult(b.sim_name)
			a.ledger.soften(b.sim_name, 3.0)
		var since: float = now - float(a.last_talk.get(b.sim_name, -10000.0))
		if kind == "argue":
			d *= ARGUE_REL_MULT
		if since < REPEAT_TALK_WINDOW and kind != "insult":
			d *= REPEAT_TALK_MULT
		var nv := clampf(cur + d, -100.0, 100.0)
		a.relationships[b.sim_name] = nv
		a.last_talk[b.sim_name] = now
		a._detail_dirty = true
		var old_label := relationship_label(cur, b.grammar)
		var new_label := relationship_label(nv, b.grammar)
		a.social_event.emit(a, positive, new_label != old_label)
		if positive:
			a.add_joy_moodlet("rozhovor_" + b.name, "Příjemný rozhovor", "stastny", 10.0, 150.0)
		elif kind == "insult":
			if a == self:
				# Ten, kdo uráží: bručoun nebo naštvaný si uleví, ostatní mají výčitky.
				if trait_ids.has("brucoun") or mood.emotion == "nastvany":
					a.mood.add_moodlet("ulevil_" + b.name, "Ulevil(a) si".replace("(a)", Grammar.past(grammar)), "energicky", 5.0, 90.0)
				else:
					a.mood.add_moodlet("vycitky_" + b.name, "Výčitky svědomí", "smutny", -8.0, 240.0)
				a.remember("Urazil(a) – %s" % b.sim_name)
			else:
				a.mood.add_moodlet("urazka_" + b.name, "Urážka od: " + b.first_name(), "nastvany", -18.0, 360.0)
				a.remember("%s mě urazil%s" % [b.sim_name, Grammar.past(b.grammar)])
		else:
			a.mood.add_moodlet("hadka_" + b.name, "Nepříjemná hádka", "nastvany", -14.0, 200.0)
			a.remember("Pohádal(a) se – %s" % b.sim_name)
		a.note_relationship_change(b, cur, nv)


## Kdo stojí poblíž hádky, toho to taky rozhodí (úzkostné víc).
func _witness_conflict(partner: Node3D, cfg: Dictionary) -> void:
	if world == null:
		return
	for o in world.get_sims():
		if o == self or o == partner or not o.has_method("command") or o._is_sleeping():
			continue
		if o.global_position.distance_to(global_position) < WITNESS_DIST * 0.7:
			o.mental.on_stressor("witness_conflict", 3.0, cfg)


## Žárliví nesou těžce, když se jejich blízký (vztah ≥ 40) baví s někým jiným.
func _check_jealousy(partner: Node3D, cfg: Dictionary) -> void:
	if world == null:
		return
	for o in world.get_sims():
		if o == self or o == partner or not o.has_method("command") or not Traits.has_flag(o.trait_ids, "jealous"):
			continue
		if o._is_sleeping() or o.global_position.distance_to(global_position) > WITNESS_DIST:
			continue
		for pair in [[self, partner], [partner, self]]:
			var friend: Node3D = pair[0]
			var rival: Node3D = pair[1]
			if float(o.relationships.get(friend.sim_name, 0.0)) >= 40.0 and not o.mood.has_moodlet("zarli_" + String(rival.name)):
				o.mental.on_stressor("jealousy", 6.0, cfg)
				o.mood.add_moodlet("zarli_" + String(rival.name), "Žárlí na: " + rival.first_name(), "nastvany", -10.0, 240.0)
				o.relationships[rival.sim_name] = clampf(float(o.relationships.get(rival.sim_name, 0.0)) - 2.0, -100.0, 100.0)
				o.ledger.grudges[rival.sim_name] = clampf(o.ledger.grudge(rival.sim_name) + 3.0, 0.0, 100.0)
				o._detail_dirty = true
				if o.speech == "" and o.rng.randf() < 0.4:
					o.say(ActionLibrary.random_line("jealous", o.rng))
				break


func remember(text: String) -> void:
	var t := gendered(text)
	# Neopakovat stejnou vzpomínku během půl dne.
	for e in memories:
		if e["text"] == t and _clock.total_minutes - float(e["t"]) < 720.0:
			return
	memories.append({"t": _clock.total_minutes, "text": t})
	if memories.size() > MAX_MEMORIES:
		memories.pop_front()
	_detail_dirty = true
	memory_added.emit(self, t)


# ---------------------------------------------------------------- síť a HUD

func current_posture() -> String:
	return current_action.get("posture", "stand") if state == State.ACTING else "stand"


func _object_index(obj) -> int:
	if obj == null or world == null or not is_instance_valid(obj):
		return -1
	return world.get_smart_objects().find(obj)


## Přepočítá replikované vlastnosti. Synchronizer posílá jen změny (ON_CHANGE).
func _update_net(dm: float) -> void:
	net_label = display_action()
	net_emotion = mood.emotion
	net_mood = int(round(mood.value))
	net_posture = current_posture()
	net_speech = speech
	var nb := PackedByteArray()
	nb.resize(Needs.KEYS.size())
	for i in Needs.KEYS.size():
		nb[i] = int(round(clampf(needs.values[Needs.KEYS[i]], 0.0, 100.0)))
	net_needs = nb
	if state == State.ACTING and current_action.has("id"):
		net_action = "%s|%d" % [current_action["id"], _object_index(target)]
	else:
		net_action = ""
	_detail_timer -= dm
	if _detail_dirty or _detail_timer <= 0.0:
		_detail_timer = DETAIL_INTERVAL
		_detail_dirty = false
		net_detail = _build_detail()


func _build_detail() -> Dictionary:
	var ml: Array = []
	for m in mood.all_moodlets():
		ml.append([String(m["label"]), int(m["strength"])])
	var rel := {}
	for n in relationships:
		rel[n] = int(relationships[n])
	var mem: Array = []
	for e in memories.slice(-5):
		mem.append([float(e["t"]), String(e["text"])])
	var grudge := {}
	for n in ledger.grudges:
		if float(ledger.grudges[n]) >= 10.0:
			grudge[n] = true
	return {"traits": trait_ids.duplicate(), "moodlets": ml, "rel": rel, "mem": mem,
		"queue": player_queue.size(), "mind": mental.detail(mental_cfg()), "grudge": grudge}


## Data pro HUD – stejný formát vrací i SimPuppet na klientu.
func hud_info() -> Dictionary:
	var nv := {}
	for k in Needs.KEYS:
		nv[k] = float(needs.values[k])
	var d := _build_detail()
	d["name"] = sim_name
	d["mood"] = mood.value
	d["emotion"] = mood.emotion
	d["action"] = display_action()
	d["needs"] = nv
	d["private"] = true
	return d


# ---------------------------------------------------------------- vizuál

func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(dir.x, dir.z)


func _update_visual() -> void:
	if visual == null:
		return
	visual.apply(current_posture(), mood.value, mood.emotion, sim_name, display_action(), speech)
