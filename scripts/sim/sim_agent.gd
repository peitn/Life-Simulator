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
const Vigilance := preload("res://scripts/sim/vigilance.gd")
const RejectionResponse := preload("res://scripts/sim/rejection_response.gd")
const EmotionalState := preload("res://scripts/sim/emotional_state.gd")
const IntimacyState := preload("res://scripts/sim/intimacy_state.gd")
const AdultIntimacy := preload("res://scripts/sim/adult_intimacy_action.gd")
const SocialPressure := preload("res://scripts/sim/social_pressure.gd")
const SensitivePrivacyMask := preload("res://scripts/sim/sensitive_privacy_mask.gd")
const PsycheExt := preload("res://scripts/sim/psyche_ext.gd")
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
## Locally-authorized, opt-in non-graphic notice, NEVER an RPC/public snapshot.
signal private_sensitive_event_notice(text: String)

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
var trait_ids: Array = [] # legacy/public list for compatibility
var trait_profile: Variant = [] # Array[String] for old characters or weighted Dictionary for sliders
var needs
var mood
var mental
## Individuální citlivosti (hluk, tlačenice, radost, práh těšení) a jejich návyky.
var sensory = SensoryProfile.new()
## Independent vigilance/interpretation; never routed through FCCS.
var vigilance = Vigilance.new()
## Reakce na skutečné či domnělé odmítnutí: soukromý stav, nikoli hratelná SH akce.
var rejection = RejectionResponse.new()
## 19 simultaneous event-driven feelings + private person-directed emotions.
var emotions = EmotionalState.new()
## Stable self-belief (0..1), privately sourced from CharacterData.mind; NOT an emotion meter.
var self_defectiveness_belief := 0.0
## Rozšíření psychiky (neuro profil a další osy, scripts/sim/psyche_ext.gd). Soukromé, vlastní RNG.
var psy = PsycheExt.new()
## Stabilní interní uid postavy (z CharacterData; klíč sociální paměti, nikdy jméno). Soukromé.
var char_uid := ""
## Profil rysů bez osobnostních akcentů (akcenty se přidávají jako váhy acc_* podle režimu obsahu).
var _base_trait_profile: Variant = []
## Private sexuality and consent. Never part of replicated net_detail.
var intimacy = IntimacyState.new()
var _intimacy_resolved := false
var _privacy_mask: Node3D = null
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
## Kolikrát postava výtku spolkla (statistika pro testy a reporty).
var swallowed_complaints := 0
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
	trait_profile = p_traits
	_base_trait_profile = p_traits
	body_color = p_color
	world = p_world
	rng.seed = p_seed
	_seed = p_seed
	needs = Needs.new(rng)
	mood = Mood.new()
	mental = MentalState.new(rng, grammar)
	emotions = EmotionalState.new()
	intimacy = IntimacyState.new()
	_intimacy_resolved = false
	mental.trait_vuln = Traits.sum_param(trait_profile, "vulnerability")
	mental.trait_dep = Traits.sum_param(trait_profile, "dep_vuln")
	mental.sensitivity = mental.baseline_sensitivity()
	ledger = RelLedger.new()
	Traits.apply_decay(trait_profile, needs)
	sensory.setup(trait_profile, {}, p_seed)
	vigilance.configure({}, true)
	rejection.configure({}, true)
	psy = PsycheExt.new()
	psy.configure({}, {}, p_seed, false)
	name = node_name_for(p_name)


## Predispozice k duševním potížím: {"anxiety": 0.6}. Neznámé diagnózy ignoruje.
func set_conditions(conds: Dictionary, initialize_sensitivity: bool = true) -> void:
	mental.conditions = {}
	for id in conds:
		if MentalState.CONDITIONS.has(String(id)) and (typeof(conds[id]) == TYPE_FLOAT or typeof(conds[id]) == TYPE_INT):
			mental.conditions[String(id)] = clampf(float(conds[id]), 0.0, 1.0)
	# Spawn initializes adaptation; live editor changes preserve learned state.
	if initialize_sensitivity:
		mental.sensitivity = mental.baseline_sensitivity(mental_cfg())
	sensory.setup(trait_profile, mental.conditions, _seed)


## Soukromá část CharacterData (jen server/offline): predispozice a vzorce z `mind`.
func apply_character_private(cd: Dictionary, initialize_sensitivity: bool = true) -> void:
	var pers = cd.get("personality", {})
	if typeof(pers) == TYPE_DICTIONARY:
		var levels = pers.get("trait_levels", {})
		if typeof(levels) == TYPE_DICTIONARY and not levels.is_empty():
			trait_profile = levels.duplicate()
			# Keep readable legacy HUD labels; simulation uses the exact levels.
			trait_ids = []
			for id in levels:
				if float(levels[id]) >= 0.5:
					trait_ids.append(String(id))
			trait_ids.sort()
		else:
			# Clearing explicit sliders restores the legacy profile, not stale weights.
			trait_ids = (pers.get("traits", []) as Array).duplicate()
			trait_profile = trait_ids.duplicate()
		mental.trait_vuln = Traits.sum_param(trait_profile, "vulnerability")
		mental.trait_dep = Traits.sum_param(trait_profile, "dep_vuln")
		for k in needs.decay_mult:
			needs.decay_mult[k] = 1.0
		Traits.apply_decay(trait_profile, needs)
	var m = cd.get("mind", {})
	if typeof(m) != TYPE_DICTIONARY:
		return
	self_defectiveness_belief = clampf(float(m.get("self_defectiveness", 0.0)), 0.0, 1.0)
	var p = m.get("predispositions", {})
	set_conditions(p if typeof(p) == TYPE_DICTIONARY else {}, initialize_sensitivity)
	set_patterns({"morning_worse": bool(m.get("morning_worse", false))})
	# 1. osa psychiky (běh 20): individualita a explicitní osobnost jako háčky MentalState – pro všechny tři
	# režimy obsahu, MentalState si vybere podle aktuálního nastavení (přepnutí za běhu funguje hned).
	mental.set_psyche(PsycheModel.hooks_by_mode(cd))
	var dispositions: Dictionary = PsycheModel.compute(cd).get("D", {})
	vigilance.configure(dispositions, initialize_sensitivity)
	rejection.configure(dispositions, initialize_sensitivity)
	emotions.configure(dispositions)
	# CharacterData's sexual attraction is independent from romantic attraction.
	# Neither gender identity nor asexuality is inferred from anatomy or libido.
	var identity: Dictionary = cd.get("identity", {})
	var body: Dictionary = cd.get("body", {})
	intimacy.configure({"age": body.get("age", 30),
		"asexual": identity.get("asexual", false),
		"aromantic": identity.get("aromantic", false),
		"sexual_attraction": identity.get("sexual_attracted_to", []),
		"romantic_attraction": identity.get("attracted_to", []),
		"libido": identity.get("libido", 0.5),
		"drive_dysregulation": identity.get("drive_dysregulation", 0.0)})
	sensory.configure(dispositions)
	char_uid = String(cd.get("uid", "")) if typeof(cd.get("uid", "")) == TYPE_STRING else ""
	# Živá úprava v editoru (initialize_sensitivity = false) zachová naučený stav rozšíření psychiky.
	_base_trait_profile = trait_profile
	psy.configure(m, dispositions, _seed, not initialize_sensitivity)
	sensory.channel_gain = psy.neuro.channel_gains(psy.k())
	_apply_accents()


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
	for c in Traits.cravings(trait_profile):
		last_tag_time[c[0]] = _clock.total_minutes - rng.randf_range(0.0, float(c[1]) * 42.0)
	mood.evaluate(needs, trait_profile, _extra_moodlets())
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
	if not psy.mood.is_empty():
		suppress["energy"] = float(suppress["energy"]) * psy.mood.energy_mult(psy.k())
	if not psy.voice.loops.is_empty():
		suppress["energy"] = float(suppress["energy"]) * psy.voice.energy_drain_mult()
	if psy.eating.food_anxiety > 0.0:
		suppress["energy"] = float(suppress["energy"]) * psy.eating.energy_mult()
	needs.tick(dm, suppress)
	mood.tick(dm)
	sensory.tick(dm)
	_check_cravings()
	_mental_tick(dm)
	_psyche_tick(dm)
	ledger.decay(dm, Traits.mult_param(trait_profile, "grudge_tau"), Traits.mult_param(trait_profile, "guilt_tau"))
	_heal_relationships(dm)
	mood.evaluate(needs, trait_profile, _extra_moodlets())
	# Interpret current context; emotion values never automatically change stress.
	emotions.tick(dm, {"social": needs.values["social"], "stress": mental.stress,
		"burden": mental.dep.burden, "threat": mental.threat,
		"regulation": mental.regulation(float(needs.values["energy"]), float(needs.values["hunger"])),
		"support": mental.support, "sleeping": _is_sleeping(),
		"social_drive": Traits.weight(trait_profile, "spolecensky")})
	intimacy.tick(dm, {"safety": emotions.level("safety") / 100.0,
		"stress": mental.stress, "energy": needs.values["energy"], "now": now()})
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
	return sensory.joy_capacity(mental.dep.hedonic, mental.stress) * mental.dep.joy_severity_mult()


## Příjemný moodlet: síla podle toho, kolik radosti postava právě unese (ne každého potěší stejně).
func add_joy_moodlet(id: String, label: String, emo: String, strength: float, duration: float) -> void:
	var k := joy_capacity() if strength > 0.0 else 1.0
	if strength > 0.0 and strength * k < 1.0:
		return  # tak slabé, že to postava ani nevnímá
	var had_moodlet: bool = mood.has_moodlet(id)
	var delivered: float = strength * k
	mood.add_moodlet(id, label, emo, delivered, duration)
	# A new positive event can raise real arousal; refreshing the same moodlet
	# does not farm excitement. Calm contentment need not mean high arousal.
	if mental != null and not had_moodlet and delivered > 0.0 and emo in ["stastny", "energicky", "soustredeny"]:
		var gain := 2.5 if emo == "energicky" else (1.5 if emo == "stastny" else 0.8)
		mental.on_positive_stimulus(delivered * gain)


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
	if psy != null and not psy.is_neutral() and _clock != null:
		out.append_array(psy.neuro.mood_entries(now(), psy.k()))
		out.append_array(psy.mood.mood_entries(psy.k(), mental.stress))
	if psy != null and not psy.voice.loops.is_empty():
		out.append_array(psy.voice.mood_entries(psy.k()))
	if psy != null and not psy.accents.is_empty():
		out.append_array(psy.accents.mood_entries(float(needs.values["social"])))
	if psy != null and not psy.ocd.is_empty() and _clock != null:
		out.append_array(psy.ocd.mood_entries(psy.k(), now()))
	if psy != null and psy.eating.active():
		out.append_array(psy.eating.mood_entries())
	if psy != null and not psy.subs.is_empty() and _clock != null:
		out.append_array(psy.subs.mood_entries(now(), psy.sub_withdrawal, psy.sub_withdrawal_id, _subs_k()))
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
	if mental.panic_active and not was_panic:
		emotions.impulse("panic_start")
	elif was_panic and not mental.panic_active:
		emotions.impulse("panic_end")
	vigilance.tick(dm, _is_sleeping(), mental.support > 0.2)
	rejection.tick(dm, _is_sleeping(), mental.support, mental.stress,
		mental.regulation(float(needs.values["energy"]), float(needs.values["hunger"])), _allows_rejection_risk())
	# Tlačenice: kolik lidí je těsně kolem (sociální úzkost, samotáři).
	_crowd_timer -= dm
	# Spící tlačenici nevnímá (běh 23, matice 8 postav: spaní na zemi vedle ostatních přidávalo úzkostné postavě
	# přes noc desítky bodů stresu „z davu“). Rušení ve spánku řeší hluk (HouseholdDynamics), ne dav.
	var crowd_check := _crowd_timer <= 0.0 and world != null
	if crowd_check:
		_crowd_timer = CROWD_INTERVAL
	if crowd_check and not _is_sleeping():
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
			on_sensory_exposure("crowd", maxf(near - 1.0, 0.0))
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
		var stigma_p := clampf(0.08 + Traits.sum_param(o.trait_profile, "stigma") - rel / 150.0 + o.mental.stress / 300.0, 0.02, 0.8)
		var help_p := clampf(0.35 + rel / 100.0 - Traits.sum_param(o.trait_profile, "stigma"), 0.0, 0.9)
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
			remember_social(o, "humiliation", 0.6, "self", interpret_intent(0.3))
			inner_trigger("failure", o, 0.35)
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
	mental.receive_support(rel, Traits.mult_param(trait_profile, "support_accept"), now())
	add_joy_moodlet("pomoc_" + String(helper.name), "Někdo při mně stál", "spokojeny", 8.0, 600.0)
	ledger.record_trust(helper.sim_name, "support", 9.0)
	remember_social(helper, "support", 0.8)
	inner_positive("warm", helper)
	emotions.impulse("helped", helper.sim_name)
	helper.emotions.impulse("comforted_other", sim_name)
	remember("%s mi pomohl%s při panické atace" % [helper.sim_name, Grammar.past(helper.grammar)])
	for pair in [[self, helper], [helper, self]]:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var c0: float = float(a.relationships.get(b.sim_name, 0.0))
		a.relationships[b.sim_name] = clampf(c0 + 4.0, -100.0, 100.0)
		a.note_relationship_change(b, c0, float(a.relationships[b.sim_name]))
		a._detail_dirty = true
	_learn_connection(helper)
	helper.say(ActionLibrary.random_line("support", helper.rng))


## Bude partner naslouchat, nebo odbyde? (pro svěření se)
func dismisses_confide(asker: Node3D) -> bool:
	var rel: float = float(relationships.get(asker.sim_name, 0.0))
	var p := clampf(0.12 + Traits.sum_param(trait_profile, "stigma") - rel / 120.0 + mental.stress / 250.0, 0.03, 0.85)
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
	if String(action.get("id", "")) == "compulsion" and not psy.ocd.is_empty():
		action = action.duplicate(true)
		action["label"] = psy.ocd.COMPULSION_LABEL.get(psy.ocd.theme, action["label"])
	# Hyperfokus / časová slepota / pracovní paměť natáhnou jen AUTONOMNÍ akci (hráčův příkaz se nemění).
	if not by_player and not psy.is_neutral():
		var dmul: float = psy.neuro.duration_mult(action, false, psy.k())
		if dmul > 1.0 + 1e-6:
			action = action.duplicate(true)
			action["duration"] = float(action.get("duration", 30.0)) * dmul
			action["psy_extended"] = true
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
			_routine_disrupted()
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
	# Obtížné zahájení (neuro profil): stejná zrušitelná bariéra jako u deprese, jen u povinností.
	if not psy.is_neutral():
		b = maxf(b, psy.neuro.initiation_barrier(cmd["action"], psy.k()))
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
	if target != null and is_instance_valid(target) and target.get("object_tag") != null:
		psy.memory.cue("", now(), String(target.object_tag))
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
	# Consent and capacity remain revocable for the ENTIRE encounter; expiry,
	# coercion, panic or either partner withdrawing ends it without completion.
	if current_action.get("id", "") == "adult_consensual_sex":
		var gs := get_node_or_null("/root/GameSettings")
		var enable: bool = gs != null and gs.allows_content("adult_intimacy")
		if social_partner == null or not is_instance_valid(social_partner) or not bool(
				AdultIntimacy.check(world, self, social_partner, now(), enable).get("ok", false)):
			_finish(true)
			return
	# Before hygiene actually becomes critical, an autonomous character can
	# interrupt a long interruptible task (e.g. cooking) and seek a shower.
	# Only interrupt when a shower is AVAILABLE, never while being controlled
	# by a player, in an involuntary action, or already restoring hygiene.
	# _finish(true) preserves object reservation and interruption semantics.
	if not by_player and social_partner == null and action_elapsed > 10.0 \
			and bool(current_action.get("interruptible", true)) \
			and not bool(current_action.get("involuntary", false)) \
			and not bool(current_action.get("system", false)) \
			# A negative hygiene effect (e.g. workout) worsens, not solves, dirtiness.
			and float(current_action.get("effects", {}).get("hygiene", 0.0)) <= 0.0 \
			and float(current_action.get("rate", {}).get("hygiene", 0.0)) <= 0.0 \
			and float(needs.values["hygiene"]) < Planner.HYGIENE_INTERRUPT_AT \
			and world != null:
		var care := Planner.urgent_hygiene_plan(self, world.get_smart_objects())
		if not care.is_empty():
			_finish(true)
			# Replan at the next clock tick, after normal object release.
			think_cooldown = 0.0
			return
	var dur: float = float(current_action.get("duration", 30.0))
	var eff: Dictionary = current_action.get("effects", {})
	for k in eff:
		var dv: float = float(eff[k]) * dm / dur
		if k == "fun" and dv > 0.0:
			dv *= mental.dep.fun_mult()  # anhedonie: totéž baví méně
		needs.add(k, dv)
	var rate: Dictionary = current_action.get("rate", {})
	var sq: float = mental.sleep_quality() if current_action.get("tags", []).has("sleep") else 1.0
	if sq != 1.0 and not psy.mood.is_empty():
		sq *= psy.mood.sleep_rate_mult(psy.k())  # zvýšená fáze: méně spánku stačí
	if sq != 1.0 and not psy.subs.is_empty():
		sq *= psy.subs.sleep_quality_mult(now(), _clock.get_hour())  # káva, Jiskra a hraní před spaním spánek zhorší
	if sq != 1.0 and (not psy.voice.loops.is_empty() or psy.voice.hopelessness > 0.0):
		sq *= psy.voice.sleep_quality_mult()  # přemítání a beznaděj zhoršují spánek
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
	# Roztěkanost: autonomní soustředěná činnost může „vyšumět“ (nikdy hráčův příkaz, nikdy rozhovor).
	if not by_player and social_partner == null and not psy.is_neutral():
		var lam: float = psy.neuro.drift_hazard(current_action, by_player, action_elapsed, psy.k())
		if lam > 0.0 and psy.rng.randf() < 1.0 - exp(-lam * dm):
			mood.add_moodlet("nd_odbihani", "Myšlenky mi utekly jinam", "nesvuj", -2.0, 60.0)
			_finish(true)
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
	if id == "adult_consensual_sex" and not interrupted and not _intimacy_resolved:
		var gs := get_node_or_null("/root/GameSettings")
		var enabled: bool = gs != null and gs.allows_content("adult_intimacy")
		var partner: Node3D = social_partner
		var result := AdultIntimacy.commit(world, self, partner, now(), enabled)
		if bool(result.get("ok", false)):
			_intimacy_resolved = true
			partner._intimacy_resolved = true
			# Sensitive sexual facts are never written to replicated memories.
		else:
			interrupted = true
	if id == "adult_consensual_sex" and interrupted:
		intimacy.revoke_consent(String(social_partner.name) if social_partner != null and is_instance_valid(social_partner) else "")
		if social_partner != null and is_instance_valid(social_partner):
			social_partner.intimacy.revoke_consent(String(name))
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
		# Řešení přemítání: deník je jedna z cest, odborná pomoc uleví i beznaději.
		if cop == "journal" and frac > 0.5:
			psy.voice.resolve("", 0.3)
		elif cop == "seek_help" and frac > 0.5:
			psy.voice.resolve("", 0.3)
			psy.voice.hopelessness *= 0.6
			inner_positive("hope", null)
		_detail_dirty = true
	if bool(current_action.get("involuntary", false)) and not interrupted:
		mental.end_panic()
	if bool(current_action.get("approach_only", false)) and target != null and is_instance_valid(target):
		target._helping_me = maxi(target._helping_me - 1, 0)
	if not interrupted and social_partner != null and is_instance_valid(social_partner) \
			and current_action.get("tags", []).has("social") and cop == "":
		var th: String = mental.on_social_completed(_social_positive, _social_arousal_start,
			social_partner.sim_name, social_partner.grammar, now(), mental_cfg())
		if psy.social_anxiety > 0.0:
			# Přehrávání rozhovoru: z dat (proběhl rozhovor s někým), ne náhodná výplň.
			_push_thought(psy.voice.trigger("worry", memory_key(social_partner), social_partner.sim_name,
				0.25 * psy.social_anxiety * (0.6 if _social_positive else 1.2), now(), psy.k()), "inner_worry")
		if th != "":
			_detail_dirty = true
		# Perceived rejection is independent of intrusive-thought PRESENTATION settings.
		# A good chat may still be misread; this is not evidence of actual rejection.
		if _social_positive and id == "chat" and rng.randf() < perceived_rejection_chance():
			_on_rejection_cue("perceived", social_partner, 0.7)
	if not interrupted and not bool(current_action.get("system", false)) and not bool(current_action.get("involuntary", false)):
		_experience_finished()
	if not interrupted:
		var ml: Array = current_action.get("moodlet", [])
		if ml.size() == 5:
			if float(ml[3]) > 0.0:
				emotions.impulse("activity_good", "", clampf(joy_capacity(), 0.0, 1.0))
			elif float(ml[3]) < 0.0:
				emotions.impulse("activity_bad")
			var scale := Traits.moodlet_multiplier(trait_profile, current_action.get("tags", []))
			if float(ml[3]) > 0.0:
				scale *= joy_capacity()  # liking: prožitá radost (anhedonie a stres ji tlumí, citlivost postavy)
			mood.add_moodlet(ml[0], ml[1], ml[2], float(ml[3]) * scale, float(ml[4]))
			# Do paměti jen silné zážitky (např. gurmánovo vaření).
			var mem = current_action.get("memory", null)
			if mem != null and float(ml[3]) * scale >= MEMORABLE_STRENGTH:
				remember(String(mem))
	_psyche_after_finish(id, interrupted, cop)
	if not psy.ocd.is_empty():
		_ocd_after_finish(id, interrupted)
	if psy.eating.active() and not interrupted and (current_action.get("tags", []) as Array).has("food"):
		var g: float = psy.eating.after_meal(now())
		if g < 0.0:
			mood.add_moodlet("ed_vycitky", "Výčitky po jídle", "smutny", g, 180.0)
			if psy.eating.body_image > 0.5 and world != null:
				for o in world.get_sims():
					if o != self and o.has_method("command") and float(o.relationships.get(sim_name, 0.0)) >= 25.0 \
							and o.global_position.distance_to(global_position) < 6.0 and not o._is_sleeping():
						o.mood.add_moodlet("ed_obava_" + String(name), "Bojím se o: " + first_name(), "uzkostny", -3.0, 240.0)
	if psy.eating.active() and not interrupted and (cop == "confide" and not _confide_dismissed or cop == "seek_help"):
		psy.eating.on_support(1.0 if cop == "seek_help" else 0.6)
	if id == "drink" or id == "cut_down" or String(current_action.get("substance", "")) != "":
		_substance_after_finish(id, interrupted)
	_leave_target()
	var partner := social_partner
	social_partner = null
	if partner != null and is_instance_valid(partner) and partner.social_partner == self:
		partner._finish(interrupted if id == "adult_consensual_sex" else false)
	last_action_id = id
	_intimacy_resolved = false
	current_action = {}
	target = null
	state = State.IDLE
	think_cooldown = rng.randf_range(1.0, 4.0)
	action_finished.emit(self, id, interrupted)


## Dokončená akce: prožitek vs. očekávání (učení wanting) a behaviorální aktivace.
func _experience_finished() -> void:
	var id: String = current_action.get("id", "")
	var tags: Array = current_action.get("tags", [])
	var prior := ActionLibrary.hedonic_prior(current_action) * Traits.moodlet_multiplier(trait_profile, tags)
	var res := {}
	if prior > 0.0:
		res = mental.dep.experience(id, prior)
	var eff := ActionLibrary.effort(current_action)
	var relief := 0.0
	if eff >= 0.1:
		relief = mental.dep.on_activity(id, eff, float(res.get("surprise", 0.0)), now())
	if float(res.get("surprise", 0.0)) > 3.0 and mental.dep.pessimism > 0.3:
		mood.add_moodlet("lepsi_nez_cekal", gendered("Bylo to lepší, než jsem čekal(a)"), "spokojeny", 5.0, 180.0)
		inner_positive("hope", null)
	if float(res.get("surprise", 0.0)) < -4.0:
		emotions.impulse("activity_bad", "", 0.5)
	last_experience = res.duplicate()
	last_experience["id"] = id
	last_experience["relief"] = relief


func _abort() -> void:
	if current_action.get("id", "") == "adult_consensual_sex" and target != null and is_instance_valid(target) and _is_sim(target):
		intimacy.revoke_consent(String(target.name))
		target.intimacy.revoke_consent(String(name))
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
	for c in Traits.cravings(trait_profile):
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
		if not (current_action.get("tags", []) as Array).has("social"):
			_routine_disrupted()
	by_player = false
	current_action = action
	target = partner
	social_partner = partner
	state = State.ACTING
	action_elapsed = 0.0
	action_counts["chat"] = int(action_counts.get("chat", 0)) + 1
	_social_arousal_start = mental.aversive_arousal()
	_social_positive = true
	_confide_dismissed = false
	_face((partner.global_position - global_position).normalized())
	action_started.emit(self, current_action)


func say(text: String) -> void:
	speech = gendered(text)
	speech_until = _clock.total_minutes + SPEECH_MINUTES


func _start_social(partner: Node3D) -> void:
	var social_id: String = String(current_action.get("id", ""))
	# Setkání je podnět: oživí (omezeně) vzpomínky na toho člověka u obou.
	psy.memory.cue(memory_key(partner), now())
	if partner.get("psy") != null:
		partner.psy.memory.cue(memory_key(self), now())
	_social_anxiety_before(partner)
	# Zvýšená fáze: rychlá, překotná řeč (jen replika, nic se nevynucuje).
	if not psy.mood.is_empty() and psy.mood.elevation() > 0.35 and psy.rng.randf() < psy.mood.elevation():
		say(psy.mood.LINES_UP[psy.rng.randi_range(0, psy.mood.LINES_UP.size() - 1)])
	# A sexual encounter is possible ONLY with two independent, current, freely
	# given offers. The check also binds adult age to server CharacterData.
	if social_id == "adult_consensual_sex":
		var gs := get_node_or_null("/root/GameSettings")
		var enabled: bool = gs != null and gs.allows_content("adult_intimacy")
		var ok: Dictionary = AdultIntimacy.check(world, self, partner, now(), enabled)
		if not bool(ok.get("ok", false)):
			_abort()
			return
		if not intimacy.extend_started_encounter(String(partner.name), now(), 45.0) or not partner.intimacy.extend_started_encounter(String(name), now(), 45.0):
			_abort()
			return
		var act: Dictionary = current_action.duplicate(true)
		act["label"] = "Soukromá chvíle"
		var other_act: Dictionary = act.duplicate(true)
		other_act["label"] = "Soukromá chvíle"
		partner.join_social(self, other_act)
		social_partner = partner
		_intimacy_resolved = false
		partner._intimacy_resolved = false
		current_action = act
		_begin_acting()
		return
	var pressure_kind: String = String(current_action.get("pressure_kind", ""))
	if SocialPressure.KINDS.has(pressure_kind):
		var act: Dictionary = current_action.duplicate(true)
		if not SocialPressure.apply(pressure_kind, self, partner, now()):
			_abort()
			return
		partner.remember_social(self, "pressure", clampf(float(SocialPressure.SEVERITY[pressure_kind]) / 15.0, 0.2, 1.0),
			"self", "intended")
		say(ActionLibrary.random_line(pressure_kind, rng))
		act["label"] = "V konfliktním rozhovoru s: " + partner.first_name()
		var other_act: Dictionary = act.duplicate(true)
		other_act["label"] = "Reaguje na konfliktní rozhovor s: " + first_name()
		other_act["effects"] = {}
		partner.join_social(self, other_act)
		_social_positive = false
		partner._social_positive = false
		conversation.emit(self, partner, {"success": false, "argued": false,
			"outcome": pressure_kind, "avg_mood": (mood.value + partner.mood.value) * 0.5,
			"complaint": "", "deescalated": false, "p": 0.0})
		current_action = act
		social_partner = partner
		_begin_acting()
		return
	var forced: String = current_action.get("forced_outcome", "")
	var act: Dictionary = current_action.duplicate(true)
	var partner_act: Dictionary
	_social_arousal_start = mental.aversive_arousal()
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
		var complaint := maybe_swallow(take_complaint(partner), partner)
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
		# A conversation which was not pleasant is not necessarily an argument:
		# awkward silence, a misunderstanding, or a real fight have different impact.
		var outcome := "chat" if success else "argue"
		if not success and rng.randf() < 0.36:
			outcome = "awkward" if rng.randf() < 0.5 else "misunderstanding"
		if success:
			act["label"] = "Povídá si s: " + partner.first_name()
			_social_outcome(partner, rng.randf_range(2.0, 6.0), "chat")
			if complaint != "":
				# A complaint can be heard and resolved without an argument.
				ledger.soften(partner.sim_name, COMPLAINT_SOFTEN)
				partner.say(ActionLibrary.random_line("complaint_ok", partner.rng))
			elif deesc:
				partner.say(ActionLibrary.random_line("deescalate", partner.rng))
		elif outcome == "argue":
			act["label"] = "Hádá se s: " + partner.first_name()
			act["effects"] = {"social": 8.0, "fun": -6.0}
			act["duration"] = 15.0
			if complaint == "":
				say(ActionLibrary.random_line("argue", rng))
			_social_outcome(partner, -rng.randf_range(5.0, 10.0), "argue")
		else:
			act["label"] = ("Rozhovor vyšuměl s: " if outcome == "awkward" else "Nedorozumění s: ") + partner.first_name()
			act["effects"] = {"social": 5.0, "fun": -1.0 if outcome == "awkward" else -3.0}
			act["duration"] = 12.0
			if complaint == "":
				say(ActionLibrary.random_line(outcome, rng))
			_social_outcome(partner, -0.3 if outcome == "awkward" else -1.4, outcome)
		partner_act = act.duplicate(true)
		partner_act["label"] = act["label"].split(":")[0] + ": " + first_name()
		partner.join_social(self, partner_act)
		_social_positive = success
		partner._social_positive = success
		if not success:
			partner.say(ActionLibrary.random_line(outcome, partner.rng))
		conversation.emit(self, partner, {"success": success, "argued": outcome == "argue",
			"outcome": outcome, "avg_mood": (mood.value + partner.mood.value) * 0.5,
			"complaint": complaint, "deescalated": deesc, "p": p})
	current_action = act
	social_partner = partner
	_begin_acting()


## Šance, že běžný rozhovor s `partner` dopadne dobře (0,08..0,92). complaint = téma stížnosti.
func talk_success_chance(partner: Node3D, complaint := "") -> float:
	var friendship: float = float(relationships.get(partner.sim_name, 0.0))
	var p := TALK_BASE
	p += Traits.chemistry(trait_profile) + Traits.chemistry(partner.trait_profile)
	# Nálada obou: v dobré náladě člověk víc snese, ve špatné vybuchne dřív (max ±MOOD_WEIGHT).
	p += clampf((mood.value + partner.mood.value) * 0.5 / 100.0, -1.0, 1.0) * MOOD_WEIGHT
	p += friendship / 300.0
	# Stres a vznětlivost zvyšují riziko hádky.
	p -= (maxf(mental.stress - TALK_STRESS_FREE, 0.0) + maxf(partner.mental.stress - TALK_STRESS_FREE, 0.0)) / TALK_STRESS_DIV
	p -= Traits.sum_param(trait_profile, "argue_bias") + Traits.sum_param(partner.trait_profile, "argue_bias")
	# Špatná nálada (naštvaný, unavený, napjatý) zvyšuje riziko konfliktu.
	for e in [mood.emotion, partner.mood.emotion]:
		p -= float(TALK_EMOTION_PENALTY.get(e, 0.0))
	if complaint != "":
		p -= COMPLAINT_PENALTY
	# Přímá a doslovná komunikace (neuro profil): obou stran, podle toho, jak blízcí si jsou.
	if not psy.is_neutral():
		p += psy.neuro.talk_bias(friendship, psy.k())
	var pp = partner.get("psy")
	if pp != null and not pp.is_neutral():
		p += pp.neuro.talk_bias(float(partner.relationships.get(sim_name, 0.0)), pp.k())
		p += pp.mood.talk_bias(float(partner.mental.stress), pp.k())
	if not psy.is_neutral():
		p += psy.mood.talk_bias(mental.stress, psy.k())
		p -= 0.1 * psy.subs.irritability(psy.sub_withdrawal, psy.sub_withdrawal_id)
	# Sociální paměť obou: dobré zkušenosti spolu trochu pomáhají, křivdy trochu brzdí (±0,04 každý).
	p += psy.memory.talk_bias(memory_key(partner))
	if pp != null:
		p += pp.memory.talk_bias(memory_key(self))
	return clampf(p, 0.08, 0.92)


## Šance, že `listener` utne začínající hádku smířlivou odpovědí (podle jeho nálady).
static func deescalation_chance(listener: Node3D) -> float:
	return DEESCALATE_MAX * clampf((float(listener.mood.value) - DEESCALATE_FROM) / DEESCALATE_SPAN, 0.0, 1.0)


## Ve stresu nebo v depresi postava výtku někdy spolkne (nevyjde z toho hádka), ale není to
## zadarmo: vrací se v myšlenkách (ruminace) a krátce ji to drží v napětí.
func maybe_swallow(complaint: String, partner: Node3D) -> String:
	if complaint == "" or mental == null:
		return complaint
	var av: float = mental.avoidance(mental_cfg())
	if not psy.is_neutral():
		av *= psy.neuro.swallow_mult(psy.k())
	if av <= 0.0 or rng.randf() >= av * 0.6:
		return complaint
	swallowed_complaints += 1
	mental.dep.on_rumination(0.3)
	mood.add_moodlet("spolknuta_" + partner.name, gendered("Radši jsem mlčel(a)"), "napjaty", -3.0, 180.0)
	return ""


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
	var cap := Traits.get_param(trait_profile, "argue_stress_cap", ARGUE_STRESS_CAP)
	var f := clampf((cap - mental.stress) / ARGUE_STRESS_RAMP, ARGUE_STRESS_MIN, 1.0)
	return ARGUE_STRESS * Traits.mult_param(trait_profile, "stress_gain") * f


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
		ledger.record_trust(partner.sim_name, "dismissed", -9.0)
		remember_social(partner, "trust_breach", 0.6, "self", interpret_intent(0.5))
		inner_trigger("grievance", partner, 0.35)
		remember("Svěřil(a) jsem se a %s to odbyl%s" % [partner.sim_name, Grammar.past(partner.grammar)])
		_social_positive = false
		_on_rejection_cue("dismissed", partner)
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
		ledger.record_trust(partner.sim_name, "support", 8.0)
		remember_social(partner, "support", 0.5)
		_share_memory_with(partner)
		psy.voice.resolve("", 0.25)
		inner_positive("warm", partner)
		emotions.impulse("confided", partner.sim_name)
		partner.emotions.impulse("comforted_other", sim_name, 0.7)
		_learn_connection(partner)
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
	# Sociální paměť oběti: dobré zkušenosti s omlouvajícím se odpuštění trochu usnadní, křivdy ztíží (±0,08).
	var mem_forgive: float = 0.08 * partner.psy.memory.bias(memory_key(self)) if partner.get("psy") != null else 0.0
	var ev: Dictionary = partner.ledger.evaluate_apology(sim_name, t, rel_p,
		Traits.sum_param(partner.trait_profile, "forgiveness") + mem_forgive, partner.mental.stress, partner.rng.randf())
	var outcome: String = ev["outcome"]
	if outcome in ["accepted", "partial", "rejected"]:
		emotions.impulse("apology_" + outcome, partner.sim_name)
		if outcome == "accepted":
			partner.emotions.impulse("apology_accepted", sim_name)
	last_apology = ev.duplicate()
	last_apology["target"] = partner.sim_name
	partner.ledger.receive_apology(sim_name, outcome, t)
	ledger.apology_given(partner.sim_name, outcome, t)
	match outcome:
		"accepted":
			partner.remember_social(self, "apology", 0.6)
			# Řešení: omluva uvolní přemítání o tom člověku u obou.
			psy.voice.resolve(memory_key(partner), 0.5)
			partner.psy.voice.resolve(memory_key(self), 0.5)
			inner_positive("relief", partner)
		"partial":
			partner.remember_social(self, "apology", 0.3)
			psy.voice.resolve(memory_key(partner), 0.25)
		"rejected":
			remember_social(partner, "rejection", 0.5, "self", "none")
			inner_trigger("failure", partner, 0.4)
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
			mental.threat = clampf(mental.threat + vigilance.observe("rejection"), 0.0, 1.0)
			_on_rejection_cue("real", partner)
			if Traits.mult_param(trait_profile, "pride") < 0.8:
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
		mental.threat = clampf(mental.threat + vigilance.observe("argument", 0.75), 0.0, 1.0)
		partner.mental.threat = clampf(partner.mental.threat + partner.vigilance.observe("argument", 0.75), 0.0, 1.0)
	elif kind == "insult":
		mental.on_stressor("insult", 3.0 * Traits.mult_param(trait_profile, "stress_gain"), cfg)
		partner.mental.on_stressor("insulted", 16.0 * Traits.mult_param(partner.trait_profile, "stress_gain"), cfg)
		partner.mental.threat = clampf(partner.mental.threat + partner.vigilance.observe("insulted"), 0.0, 1.0)
		partner._on_rejection_cue("real", self)
	else:
		vigilance.observe("safe_social")
		partner.vigilance.observe("safe_social")
	if kind in ["argue", "insult"]:
		_witness_conflict(partner, cfg, kind)
	elif positive:
		_check_jealousy(partner, cfg)
	# Křivdy a vina: hádka zraní oba, urážka hlavně oběť (útočník cítí vinu, pokud se zrovna „neulevil“).
	if kind == "argue":
		ledger.on_hurt_by(partner.sim_name, 8.0, now)
		partner.ledger.on_hurt_by(sim_name, 8.0, now)
		ledger.on_hurt_other(partner.sim_name, 5.0)
		partner.ledger.on_hurt_other(sim_name, 5.0)
	elif kind == "insult":
		partner.ledger.on_hurt_by(sim_name, 25.0, now)
		var vented := 1.0 if mood.emotion == "nastvany" else Traits.weight(trait_profile, "brucoun")
		ledger.on_hurt_other(partner.sim_name, lerpf(20.0, 6.0, vented))
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
			a.ledger.record_trust(b.sim_name, "warm", 1.4)
			a._learn_connection(b)
			a.add_joy_moodlet("rozhovor_" + b.name, "Příjemný rozhovor", "stastny", 10.0, 150.0)
		elif kind == "awkward":
			a.ledger.record_trust(b.sim_name, "awkward", -0.2)
			a.mood.add_moodlet("trapne_ticho_" + b.name, "Rozhovor vyšuměl", "nesvuj", -2.0, 70.0)
		elif kind == "misunderstanding":
			a.ledger.record_trust(b.sim_name, "misunderstanding", -1.3)
			a.mood.add_moodlet("nedorozumeni_" + b.name, "Nerozuměli jsme si", "nesvuj", -4.0, 120.0)
		elif kind == "insult":
			if a == self:
				# Ten, kdo uráží: bručoun nebo naštvaný si uleví, ostatní mají výčitky.
				var relief := 1.0 if mood.emotion == "nastvany" else Traits.weight(trait_profile, "brucoun")
				if relief > 0.0:
					a.mood.add_moodlet("ulevil_" + b.name, "Ulevil(a) si".replace("(a)", Grammar.past(grammar)), "energicky", 5.0 * relief, 90.0)
				if relief < 1.0:
					a.mood.add_moodlet("vycitky_" + b.name, "Výčitky svědomí", "smutny", -8.0 * (1.0 - relief), 240.0)
				a.remember("Urazil(a) – %s" % b.sim_name)
			else:
				a.mood.add_moodlet("urazka_" + b.name, "Urážka od: " + b.first_name(), "nastvany", -18.0, 360.0)
				a.remember("%s mě urazil%s" % [b.sim_name, Grammar.past(b.grammar)])
		else:
			a.mood.add_moodlet("hadka_" + b.name, "Nepříjemná hádka", "nastvany", -14.0, 200.0)
			a.remember("Pohádal(a) se – %s" % b.sim_name)
		# Apply the outcome once to each participant; their existing moodlets and
		# anxiety are not overwritten. Mild awkwardness is not a full argument.
		var emotional_event := kind
		if kind == "insult":
			emotional_event = "insulted_other" if a == self else "insulted"
		a.emotions.impulse(emotional_event, b.sim_name)
		# Sociální paměť: fakt (druh události) + výklad úmyslu u záporných.
		match kind:
			"chat":
				a.remember_social(b, "pleasant_talk", 0.15)
			"argue":
				a.remember_social(b, "grievance", 0.4, "self", a.interpret_intent(0.5))
				a.inner_trigger("grievance", b, 0.3)
			"awkward":
				a.remember_social(b, "misunderstanding", 0.15, "self", "unclear")
			"misunderstanding":
				a.remember_social(b, "misunderstanding", 0.3, "self", a.interpret_intent(0.7))
			"insult":
				if a != self:
					a.remember_social(b, "insult", 0.8, "self", "intended")
					a.inner_trigger("grievance", b, 0.5)
		# Social comparison is distinct from jealousy over losing a relationship.
		# Only a noticeably happier conversation partner while the observer is
		# already distressed may evoke a *small*, person-directed envy response.
		# It never creates a grievance or overrides ordinary positive contact.
		if positive and a.mood.value < -25.0 and a.emotions.level("sadness") > 35.0:
			var joy_gap: float = b.emotions.level("joy") - a.emotions.level("joy")
			if joy_gap > 25.0 and b.emotions.level("joy") > 55.0:
				a.emotions.impulse("envy", b.sim_name, clampf(joy_gap / 90.0, 0.2, 0.7))
		a.note_relationship_change(b, cur, nv)


# ---------------------------------------------------------------- rozšíření psychiky (psyche_ext)

## Násobič chuti na akci z rozšíření psychiky (utility AI). Neutrální postava → přesně 1,0.
func psyche_action_weight(a: Dictionary) -> float:
	if psy == null or (psy.is_neutral() and psy.voice.loops.is_empty() and psy.voice.hopelessness <= 0.0 and not psy.eating.active()):
		return 1.0
	psy._mastery = mental.mastery
	psy._support = mental.support
	if psy.eating.food_anxiety > 0.0 and (a.get("tags", []) as Array).has("food"):
		return psy.action_weight(a, _clock.get_hour() if _clock != null else 12) \
			* psy.eating.food_weight(_others_near(4.0), float(needs.values["hunger"]))
	var sid := "alcohol" if String(a.get("id", "")) == "drink" else String(a.get("substance", ""))
	if sid != "" and not psy.subs.is_empty():
		var kk := _subs_k()
		if sid == "alcohol":
			return psy.action_weight(a, _clock.get_hour() if _clock != null else 12) * (1.0 + 3.0 * psy.subs.craving("alcohol") * kk)
		return psy.action_weight(a, _clock.get_hour() if _clock != null else 12) * psy.subs.use_weight(sid, now(), kk)
	return psy.action_weight(a, _clock.get_hour() if _clock != null else 12)


## Násobič výběru partnera pro sociální akci (maskování, později paměť a osobnostní akcenty).
func psyche_target_weight(other: Node3D, a: Dictionary) -> float:
	if psy == null or other == null:
		return 1.0
	return psy.target_weight(float(relationships.get(other.sim_name, 0.0)), a, memory_key(other))


## Klíč sociální paměti pro druhou postavu: stabilní uid z CharacterData (záložně jméno s předponou).
static func memory_key(other: Node3D) -> String:
	if other == null:
		return ""
	var u = other.get("char_uid")
	if typeof(u) == TYPE_STRING and String(u) != "":
		return String(u)
	return "n:" + String(other.get("sim_name"))


## Zapíše do sociální paměti událost od `other` (fakt + výklad). Nikdy nic neodesílá po síti.
func remember_social(other: Node3D, kind: String, severity: float, source := "self", interp := "none",
		place := "", whom: Node3D = null) -> void:
	if psy == null or other == null or _clock == null:
		return
	psy.memory.record(memory_key(other), String(other.sim_name), kind, severity, now(), source, interp, place,
		memory_key(whom) if whom != null else "")


## Výklad záporné události: jak jednoznačně postava čte úmysl (vigilance a citlivost na hrozbu).
func interpret_intent(ambiguity: float) -> String:
	if vigilance == null:
		return "unclear"
	var a: float = vigilance.appraisal("unclear_reply", ambiguity) + psy.accents.appraisal_shift()
	if a >= 0.55:
		return "intended"
	if a <= 0.3:
		return "accidental"
	return "unclear"


## Svěření: posluchač se dozví jen to, co mu postava sama řekne (nejsilnější křivdu na někoho třetího).
func _share_memory_with(listener: Node3D) -> void:
	if psy == null or listener == null or listener.get("psy") == null:
		return
	var tr: Dictionary = psy.memory.strongest_negative(memory_key(listener))
	if tr.is_empty() or float(tr["strength"]) < 0.15:
		return
	var who := String(tr["who"])
	listener.psy.memory.record(who, String(psy.memory.names.get(who, "?")), String(tr["kind"]),
		float(tr["severity"]) * 0.7, now(), "told", String(tr["interp"]), "", memory_key(self))


func _sim_by_name(n: String) -> Node3D:
	if world == null:
		return null
	for o in world.get_sims():
		if o != self and String(o.get("sim_name")) == n:
			return o
	return null


## Hodinová obnova popisků vztahu s hysterezí (soukromý HUD) – deterministicky, nezávisle na HUD.
func _update_memory_views() -> void:
	if world == null:
		return
	var vals := {}
	for o in world.get_sims():
		if o != self and relationships.has(o.sim_name):
			vals[memory_key(o)] = float(relationships[o.sim_name])
	psy.memory.update_views(vals)


## Smyslová zátěž (hluk z domácnosti, tlačenice): jen pro přetížení v neuro profilu.
func on_sensory_exposure(channel_name: String, amount: float) -> void:
	if psy == null or psy.is_neutral():
		return
	psy.neuro.on_sensory(channel_name, amount, psy.k())


## Krok rozšíření: režim obsahu (přepnutí za běhu), přetížení, sociální baterka, tiky.
func _psyche_tick(dm: float) -> void:
	var m := MentalState.cfg_mode(mental_cfg())
	if m != psy.mode:
		psy.set_mode(m)
		sensory.channel_gain = psy.neuro.channel_gains(psy.k())
		_apply_accents()
	# Sociální paměť vyhasíná u každého (hodinově); popisky vztahů s hysterezí jednou za herní hodinu.
	var hour_before := int((now() - dm) / 60.0)
	psy.memory.tick(dm)
	if int(now() / 60.0) != hour_before:
		_update_memory_views()
	mental.dep.chronic_floor = psy.mood.chronic_floor(psy.k())
	_inner_tick(dm)
	_eating_tick(dm)
	if psy.is_neutral():
		return
	if not psy.mood.is_empty():
		_mood_cycle_tick(dm)
	if not psy.ocd.is_empty():
		_ocd_tick(dm)
	if not psy.subs.is_empty():
		_substance_tick(dm)
	var tags: Array = current_action.get("tags", []) if state == State.ACTING else []
	var res: Dictionary = psy.neuro.tick(dm, {"sleeping": _is_sleeping(), "social": social_partner != null,
		"quiet": tags.has("quiet") or tags.has("rest"), "stress": mental.stress}, psy.k(), psy.rng)
	var add := float(res.get("stress", 0.0))
	if add > 0.0:
		_psyche_stress("overload", add)
	if bool(res.get("tic", false)):
		_on_tic()


## Vnitřní hlas: zapíše myšlenku do soukromého proudu (stejná cesta jako rušivé myšlenky, respektuje
## nastavení „rušivé myšlenky“). Beznaděj sem NIKDY nejde (ta je jen v offline soukromém popisu).
func _push_thought(text: String, kind: String, other_grammar: String = "m") -> void:
	if text == "" or mental == null:
		return
	var cfg := mental_cfg()
	if float(cfg.get("thought_rate", 1.0)) <= 0.0:
		return
	var t := Grammar.form(text, grammar).replace("{ng}", Grammar.past(other_grammar))
	if not mental.thoughts.is_empty() and String(mental.thoughts[-1]["text"]) == t:
		return
	mental.thoughts.append({"t": now(), "text": t, "kind": kind})
	while mental.thoughts.size() > mental.MAX_THOUGHTS:
		mental.thoughts.pop_front()
	_detail_dirty = true


## Událost → smyčka myšlenek (vyhodnocení z dat: kdo, co, jak silně).
func inner_trigger(topic: String, other: Node3D, amount: float) -> void:
	if psy == null or _clock == null:
		return
	var nm := String(other.sim_name) if other != null else ""
	var txt: String = psy.voice.trigger(topic, memory_key(other) if other != null else "", nm,
		amount * psy.accents.rumination_mult(topic), now(), psy.k(), self_defectiveness_belief)
	_push_thought(txt, "inner_" + topic, String(other.grammar) if other != null else "m")


## Dobrá zkušenost → naděje / vděk / úleva (taky z dat, ne náhodná výplň).
func inner_positive(kind: String, other: Node3D) -> void:
	if psy == null or _clock == null:
		return
	var nm := String(other.sim_name) if other != null else ""
	var txt: String = psy.voice.positive(kind, memory_key(other) if other != null else "", nm, now(), psy.k())
	_push_thought(txt, "inner_" + kind, String(other.grammar) if other != null else "m")


## Brána autonomních akcí rozšíření (např. „vyhledat pomoc“): bez důvodu je AI nevolí, hráč může vždy.
func psyche_gate(kind: String) -> float:
	if psy == null:
		return 0.0
	match kind:
		"help":
			return maxf(maxf(psy.voice.help_need(), clampf(psy.subs.max_dependence() - 0.5, 0.0, 1.0) * _subs_k()),
				psy.eating.help_need())
		"ocd_ritual":
			return psy.ocd.gate("ritual") * psy.k()
		"ocd_resist":
			return psy.ocd.gate("resist") * psy.k()
		"cut_down":
			return clampf(psy.subs.max_dependence() - 0.35, 0.0, 1.0) * _subs_k()
	if kind.begins_with("substance:"):
		return psy.subs.gate(kind.substr(10)) * _subs_k()
	return 0.0


func _inner_tick(dm: float) -> void:
	var kk: float = psy.k()
	var tags: Array = current_action.get("tags", []) if state == State.ACTING else []
	var distraction := 0.0
	if state == State.ACTING:
		if tags.has("fun") or tags.has("exercise") or tags.has("social") or tags.has("reading") or tags.has("cooking"):
			distraction = 0.8
		elif not tags.has("quiet") and not tags.has("rest") and not tags.has("sleep"):
			distraction = 0.3
	var night: bool = _clock.is_night() if _clock != null else false
	var sleeping := _is_sleeping()
	var v = psy.voice
	# Starost vzniká ze stavu (vysoký stres, vnímaná hrozba), jednou za herní hodinu, ne náhodně.
	if kk > 0.0 and int(now() / 60.0) != int((now() - dm) / 60.0) and not sleeping:
		var worry := maxf(mental.stress - 60.0, 0.0) / 80.0 + maxf(mental.threat - 0.35, 0.0) * 0.6
		if worry > 0.05:
			_push_thought(v.trigger("worry", "", "", worry * v.worry_k, now(), kk, 0.0), "inner_worry")
	var was_hopeless: float = v.hopelessness
	v.tick(dm, {"idle": state == State.IDLE, "quiet": tags.has("quiet") or tags.has("rest"),
		"night_awake": night and not sleeping, "sleeping": sleeping, "distraction": distraction,
		"stress": mental.stress, "burden": mental.dep.burden, "support": mental.support,
		"rejection": float(rejection.distress), "self_belief": self_defectiveness_belief,
		"allow_hopeless": _allows_rejection_risk()}, kk)
	if not v.loops.is_empty():
		mental.dep.on_rumination(v.rumination_feed() * dm / 60.0)
	# Krizová pomoc vlastníkovi: jen offline lokální HUD, nikdy po síti a nikdy jiným postavám.
	if v.hopelessness >= v.HOPELESS_SHOW and not v.crisis_shown:
		v.crisis_shown = true
		_detail_dirty = true
		if world != null and is_instance_valid(world) and world.get("net") != null and not world.net.is_networked() \
				and world.get("hud") != null and world.hud.has_method("show_notice"):
			world.hud.show_notice("Postava prožívá beznaděj. Pomáhá blízký člověk nebo odborná pomoc – "
				+ "Linka první psychické pomoci 116 123 (nonstop, zdarma), findahelpline.com.")
	if was_hopeless < v.HOPELESS_SHOW and v.hopelessness >= v.HOPELESS_SHOW:
		remember("Bylo mi hodně těžko")


## Potíže s jídlem a tělem: vzniká jen z dat a jen při opt-in citlivém obsahu (sh_ed) + plných tématech.
func _eating_tick(dm: float) -> void:
	var allow := _allows_rejection_risk()
	if not allow and not psy.eating.active():
		return
	psy.eating.tick(dm, {"allow": allow, "self_belief": self_defectiveness_belief,
		"perfectionism": psy.accents.a("perfectionism"), "envy": emotions.level("envy"),
		"rejection": float(rejection.distress), "stress": mental.stress, "support": mental.support})


func _others_near(dist: float) -> int:
	var n := 0
	if world == null:
		return 0
	for o in world.get_sims():
		if o != self and o.has_method("command") and not o._is_sleeping() and o.global_position.distance_to(global_position) < dist:
			n += 1
	return n


## Návykové látky a činnosti: k = režim obsahu × povolená témata závislostí.
func _subs_k() -> float:
	return psy.k() if content_allowed("addiction") else 0.0


func _substance_tick(dm: float) -> void:
	var kk := _subs_k()
	var others := 0
	if world != null:
		for o in world.get_sims():
			if o != self and o.state == State.ACTING and String(o.current_action.get("substance", "")) != "" \
					and o.global_position.distance_to(global_position) < 6.0:
				others += 1
	var res: Dictionary = psy.subs.tick(dm, now(), {"stress": mental.stress, "sleeping": _is_sleeping(),
		"hour": _clock.get_hour() if _clock != null else 12, "others_using": others, "support": mental.support}, kk)
	_psyche_stress("withdrawal", float(res.get("stress", 0.0)))
	psy.sub_withdrawal = float(res.get("withdrawal", 0.0))
	psy.sub_withdrawal_id = String(res.get("withdrawal_id", ""))
	if float(res.get("crash", 0.0)) > 0.0:
		mood.add_moodlet("sub_dojezd", "Dojezd – prázdno a únava", "unaveny", -float(res["crash"]), 240.0)
		needs.add("energy", -float(res["crash"]))


## Užití látky / behaviorální epizoda (konec akce): prožitek s tolerancí, sledování návyku, obava blízkých.
func _substance_after_finish(id: String, interrupted: bool) -> void:
	var kk := _subs_k()
	var sid := String(current_action.get("substance", ""))
	if id == "drink":
		sid = "alcohol"
	if id == "cut_down" and not interrupted:
		psy.subs.cut_until = now() + 3.0 * 1440.0
		mental.mastery = clampf(mental.mastery + 0.01, 0.0, 1.0)
		remember("Rozhodl(a) jsem se to omezit")
		inner_positive("hope", null)
		return
	if sid == "" or interrupted or kk <= 0.0:
		return
	var res: Dictionary = psy.subs.on_use(sid, now(), kk)
	_psyche_stress("substance_relief", float(res.get("stress", 0.0)))
	var liking := float(res.get("liking", 0.0))
	if liking >= 1.0:
		mood.add_moodlet("sub_" + sid, "Na chvíli úleva", "spokojeny", liking, 90.0)
	# Blízcí, kteří to vidí opakovaně, mají obavu (žádné odsuzování, žádná akce navíc).
	var concern := float(psy.subs.DEFS[sid]["concern"])
	if concern > 0.0 and world != null and (psy.subs.uses_today(sid, now()) >= 2 or psy.subs.dependence(sid) > 0.4):
		for o in world.get_sims():
			if o == self or not o.has_method("command") or o._is_sleeping() or o.global_position.distance_to(global_position) > 8.0:
				continue
			if float(o.relationships.get(sim_name, 0.0)) >= 25.0:
				o.mood.add_moodlet("sub_obava_" + String(name), "Bojím se o: " + first_name(), "uzkostny", -4.0 * concern, 240.0)


## OCD smyčka: spouštěče z dat (dokončená akce, večer), nevyřešená obsese stojí stres.
func _ocd_tick(dm: float) -> void:
	var kk: float = psy.k()
	var o = psy.ocd
	var tags: Array = current_action.get("tags", []) if state == State.ACTING else []
	var busy := 0.8 if (tags.has("fun") or tags.has("social") or tags.has("exercise") or tags.has("reading")) else 0.0
	var add: float = o.tick(dm, {"sleeping": _is_sleeping(), "distraction": busy, "stress": mental.stress,
		"threat": mental.threat}, kk)
	if add > 0.0:
		_psyche_stress("ocd", add)
	if _clock != null and not _is_sleeping():
		var th: String = o.evening(_clock.get_day(), _clock.get_hour(), kk, psy.rng)
		_push_thought(th, "inner_ocd")


## Po dokončené akci: OCD spouštěč podle tématu, rituál (úleva + posílení) a odolání (napětí + oslabení).
func _ocd_after_finish(id: String, interrupted: bool) -> void:
	var kk: float = psy.k()
	var o = psy.ocd
	if id == "compulsion" and not interrupted:
		_psyche_stress("ocd_ritual", o.on_ritual(now(), kk))
		if o.rituals_today(now()) >= 4 and world != null:
			for x in world.get_sims():
				if x != self and x.has_method("command") and x.global_position.distance_to(global_position) < 5.0 and not x._is_sleeping():
					mood.add_moodlet("ocd_stud", "Stydím se, že to dělám znovu", "nesvuj", -4.0 * kk, 120.0)
					break
		return
	if id == "resist_urge":
		if not interrupted:
			_psyche_stress("ocd_resist", o.on_resist(kk))
			mental.mastery = clampf(mental.mastery + 0.01 * kk, 0.0, 1.0)
			mood.add_moodlet("ocd_odolal", gendered("Odolal(a) jsem nutkání"), "spokojeny", 4.0 * kk, 180.0)
			inner_positive("hope", null)
		return
	if interrupted:
		return
	var amt: float = o.trigger_for_action(id, current_action.get("tags", []))
	if amt > 0.0:
		_push_thought(o.trigger(amt, kk, psy.rng), "inner_ocd")


## Sociální úzkost: napětí PŘED setkáním s méně blízkým člověkem (expozice: když to dopadne dobře,
## existující učení zvládnutí snižuje citlivost); po rozhovoru krátké přehrávání.
func _social_anxiety_before(partner: Node3D) -> void:
	var sev: float = psy.social_anxiety * psy.k()
	if sev <= 0.0 or partner == null:
		return
	var closeness := clampf(float(relationships.get(partner.sim_name, 0.0)) / 60.0, 0.0, 1.0)
	mental.arousal = clampf(mental.arousal + 22.0 * sev * (1.0 - closeness), 0.0, 100.0)
	mental.threat = clampf(mental.threat + 0.15 * sev * (1.0 - closeness), 0.0, 1.0)


## Osobnostní akcenty: váhy acc_* do profilu rysů (existující parametry chemie, zášti, pýchy …) a háčky
## do emocí, důvěry a náročnosti sociálních akcí. Bez akcentů zůstává profil přesně původní.
func _apply_accents() -> void:
	var acc: Dictionary = psy.accents.profile_weights()
	if acc.is_empty():
		if typeof(trait_profile) == typeof(_base_trait_profile) and trait_profile == _base_trait_profile:
			emotions.amplitude = 1.0
			ledger.trust_gain_mult = 1.0
			mental.accent_social_cost = 0.0
			return
		trait_profile = _base_trait_profile
	else:
		var prof := {}
		if typeof(_base_trait_profile) == TYPE_DICTIONARY:
			prof = (_base_trait_profile as Dictionary).duplicate()
		else:
			for t in _base_trait_profile:
				prof[String(t)] = 1.0
		for key in acc:
			prof[key] = acc[key]
		trait_profile = prof
	mental.trait_vuln = Traits.sum_param(trait_profile, "vulnerability")
	mental.trait_dep = Traits.sum_param(trait_profile, "dep_vuln")
	for kk in needs.decay_mult:
		needs.decay_mult[kk] = 1.0
	Traits.apply_decay(trait_profile, needs)
	emotions.amplitude = psy.accents.emotion_amplitude()
	ledger.trust_gain_mult = psy.accents.trust_gain_mult()
	mental.accent_social_cost = psy.accents.social_cost()


## Průběh nálady: epizody, spánkový dluh, vazba depresivní fáze na existující depresivní zátěž.
func _mood_cycle_tick(dm: float) -> void:
	var kk: float = psy.k()
	var was: String = psy.mood.phase
	psy.mood.tick(dm, {"sleeping": _is_sleeping(), "night": _clock.is_night() if _clock != null else false,
		"stress": mental.stress, "support": mental.support, "push": psy.subs.elevation_push()}, kk, psy.rng)
	var d: float = psy.mood.depressive()
	if d > 0.0 and kk > 0.0:
		# Depresivní fáze tlačí zátěž k (nebo přes) práh epizody – stávající deprese pak nese stažení i zotavení.
		var tgt := 0.45 + 0.4 * d
		if mental.dep.burden < tgt:
			mental.dep.burden = minf(mental.dep.burden + (tgt - mental.dep.burden) * (1.0 - exp(-dm / 720.0)), mental.dep._cap(mental_cfg()))
	var e: float = psy.mood.elevation()
	if e > 0.0:
		mental.dep.burden = maxf(mental.dep.burden - 0.00004 * e * dm, 0.0)
	if was != psy.mood.phase:
		_detail_dirty = true
		if psy.mood.phase in ["hypomanic", "manic"]:
			remember("Mám v sobě nějak moc energie")


## Stres z rozšíření psychiky (s měkkým stropem MentalState a zápisem zdroje). Záporné = úleva.
func _psyche_stress(kind: String, amount: float) -> void:
	if amount == 0.0 or not is_finite(amount):
		return
	var before: float = mental.stress
	mental.stress = clampf(mental.stress + amount * (mental.stress_gain_factor() if amount > 0.0 else 1.0), 0.0, 100.0)
	if mental.stress > before:
		mental.stress_sources[kind] = float(mental.stress_sources.get(kind, 0.0)) + mental.stress - before


## Tik: neškodný a mimovolný. Postava ho nijak „nepoužívá“; před lidmi ji může krátce zahanbit.
func _on_tic() -> void:
	if world == null:
		return
	for o in world.get_sims():
		if o != self and o.has_method("command") and not o._is_sleeping() \
				and o.global_position.distance_to(global_position) < 4.0:
			mood.add_moodlet("nd_tik", "Tik zrovna před ostatními", "nesvuj", -3.0 * psy.k(), 90.0)
			return


## Narušený plán (obsazeno, vyrušení) – víc vadí tomu, kdo silně potřebuje předvídatelnost.
func _routine_disrupted() -> void:
	if psy == null or psy.is_neutral():
		return
	var r: float = psy.neuro.routine_need()
	if r <= 0.0:
		return
	_psyche_stress("routine", 3.0 * psy.k() * r)
	if r > 0.4:
		mood.add_moodlet("nd_rutina", "Narušený plán mě rozhodil", "napjaty", -4.0 * r * psy.k(), 90.0)


## Po dokončení / přerušení akce: sociální baterka a maskování, zájem, pracovní paměť, čas.
func _psyche_after_finish(_id: String, interrupted: bool, cop: String) -> void:
	if psy == null or psy.is_neutral():
		return
	var kk: float = psy.k()
	if kk <= 0.0:
		return
	var tags: Array = current_action.get("tags", [])
	var n = psy.neuro
	if not interrupted and social_partner != null and is_instance_valid(social_partner) and tags.has("social"):
		var res: Dictionary = n.on_social_finished(float(relationships.get(social_partner.sim_name, 0.0)), kk)
		if float(res["energy"]) < 0.0:
			needs.add("energy", float(res["energy"]))
		_psyche_stress("masking", float(res["stress"]))
	if not interrupted and n.is_interest(current_action):
		_psyche_stress("interest", n.on_interest_finished(now(), kk))
	if not interrupted and cop == "journal" and n.a("working_memory") > 0.0:
		# Silná stránka vnějších pomůcek: sepsat si věci uleví přetížené pracovní paměti víc.
		_psyche_stress("journal", -3.0 * kk * n.a("working_memory"))
	if not interrupted and tags.has("cooking") and n.a("working_memory") > 0.0 \
			and psy.rng.randf() < 0.15 * kk * n.a("working_memory"):
		mood.add_moodlet("nd_zapomnel", gendered("Zase jsem na něco zapomněl(a)"), "nesvuj", -4.0 * kk, 120.0)
	if bool(current_action.get("psy_extended", false)) and float(needs.values[needs.lowest()]) < 30.0:
		mood.add_moodlet("nd_cas", gendered("Zase jsem se zapomněl(a) v čase"), "nesvuj", -3.0 * kk, 120.0)


## Soukromé slovní řádky pro vlastníka (offline HUD). Žádná čísla ani diagnózy.
func psyche_private_lines() -> PackedStringArray:
	if psy == null:
		return PackedStringArray()
	var out: PackedStringArray = psy.neuro.private_lines(psy.k())
	out.append_array(psy.mood.private_lines(psy.k()))
	var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
	out.append_array(psy.voice.private_lines(psy.k(), gs.CRISIS_LINES if gs != null else []))
	out.append_array(psy.accents.private_lines())
	out.append_array(psy.ocd.private_lines(psy.k()))
	if psy.eating.active():
		out.append_array(psy.eating.private_lines(gs.CRISIS_LINES if gs != null else []))
	if _clock != null:
		out.append_array(psy.subs.private_lines(now(), _subs_k()))
	return out


## Obnova z uložené hry (GameSave). Nevalidní data se ignorují (validace proběhla předem).
func restore_psyche(d: Variant) -> void:
	if psy.from_dict(d):
		sensory.channel_gain = psy.neuro.channel_gains(psy.k())


## Chance of a perceived rejection after an objectively good conversation.
## Uses threat interpretation rather than the emotional reactivity slider; no
## forced misinterpretation, deterministic under the character RNG seed.
func perceived_rejection_chance() -> float:
	var appraisal := vigilance.appraisal("unclear_reply", 0.7)
	var base := clampf((appraisal - 0.34) * 0.30 + maxf(mental.aversive_arousal() - 50.0, 0.0) / 900.0, 0.0, 0.22)
	return clampf(base + psy.accents.perceived_rejection_add(), 0.0, 0.3)


## Risk theme is opt-in and full mental-health presentation only.
## Never include risk flags in public snapshot, multiplayer net_detail or AI action lists.
func _allows_rejection_risk() -> bool:
	if not is_inside_tree():
		return false
	var gs = get_node_or_null("/root/GameSettings")
	return gs != null and gs.mental_health_mode() == "full" and gs.allows_content("sh_ed")


## Separate appraisal (expectation) from emotional impact (rejection_reactivity).
## kind: perceived (an ambiguous social cue), dismissed (not heard), real (direct rejection).
## No injury, no scripted diagnosis and no forced player action can originate here.
func _on_rejection_cue(kind: String, other: Node3D, ambiguity := 0.0) -> Dictionary:
	if not content_allowed("mental_health") or other == null or mental == null:
		return {}
	var rel := float(relationships.get(other.sim_name, 0.0))
	var bond: Dictionary = ledger.attachment_to(other.sim_name, rel)
	var importance: float = float(bond["impact"])
	var appraisal := vigilance.appraisal("unclear_reply" if kind == "perceived" else "rejection", ambiguity)
	if kind == "perceived":
		mental.threat = clampf(mental.threat + vigilance.observe("unclear_reply", 0.5, ambiguity), 0.0, 1.0)
	var regulation: float = mental.regulation(float(needs.values["energy"]), float(needs.values["hunger"]))
	var response := rejection.on_cue(kind, importance, appraisal, mental.support, regulation)
	var rm: float = psy.accents.rejection_mult()
	var gain: float = float(response.get("stress", 0.0)) * mental.stress_gain_factor() * rm
	mental.stress = clampf(mental.stress + gain, 0.0, 100.0)
	mental.arousal = clampf(mental.arousal + float(response.get("arousal", 0.0)), 0.0, 100.0)
	if gain > 0.0:
		mental.stress_sources["rejection"] = float(mental.stress_sources.get("rejection", 0.0)) + gain
	# Perceived rejection describes an interpretation, not what the other intended.
	emotions.impulse("rejection_perceived" if kind == "perceived" else (
		"dismissed" if kind == "dismissed" else "rejection_real"), other.sim_name,
		(0.35 + clampf(float(response.get("distress_added", 0.0)) * 3.0, 0.0, 1.0)) * rm)
	# Grandiozita: odmítnutí se mění spíš ve vztek než ve smutek (jen posun emocí, žádná akce).
	if psy.accents.a("grandiosity") > 0.0:
		emotions.shift("anger", 10.0 * psy.accents.a("grandiosity"), other.sim_name)
	var added := float(response.get("distress_added", 0.0))
	if added > 0.01:
		var label := "Obavy z odmítnutí" if kind == "perceived" else "Zasáhlo ji odmítnutí"
		# Gender-neutral Czech caption for both protagonist and NPC; avoid labelling a guess as fact.
		if kind != "perceived":
			label = "Bolestivé odmítnutí"
		mood.add_moodlet("pocit_odmitnuti_" + other.sim_name, label, "smutny",
			-maxf(1.0, added * 25.0), 180.0)
		_detail_dirty = true
	rejection.update_concern(mental.stress, regulation, mental.support, _allows_rejection_risk())
	return response


## Privately usable by the owning player's editor / future safety-aware support presentation.
## No numbers, methods or instructions concerning self-harm are exposed.
func private_rejection_status() -> Dictionary:
	var status: Dictionary = rejection.private_status(_allows_rejection_risk())
	# Severe ongoing emotional strain merits care in its own right; this is
	# neither a SH probability nor a diagnosis. Visible only on offline HUD.
	if content_allowed("mental_health") and mental != null and 			mental.dep.burden >= 0.85 and mental.stress >= 70.0:
		status["support_needed"] = true
		status["state"] = "výrazná psychická zátěž"
	return status


## Writer/editor API: the bond is directional and stored in the existing private ledger.
## It does not alter the public liking score and creates no guaranteed rejection outcome.
## Learn how strongly a specific real person matters; affection, trust and
## dependency remain distinct. Multiple safe bonds reduce overconcentration.
func _learn_connection(other: Node3D) -> void:
	if ledger == null or other == null:
		return
	var reliable_alternatives := 0
	for who in relationships:
		if who != other.sim_name and float(relationships[who]) >= 25.0 and ledger.trust_in(String(who)) > 55.0:
			reliable_alternatives += 1
	ledger.learn_attachment(other.sim_name,
		float(relationships.get(other.sim_name, 0.0)),
		Traits.weight(trait_profile, "spolecensky"),
		clampf(float(rejection.reactivity) * psy.accents.attachment_mult(), 0.0, 1.0), reliable_alternatives)


func set_attachment_to(who: String, importance: float, dependency: float) -> bool:
	if ledger == null or not ledger.set_attachment(who, importance, dependency):
		return false
	_detail_dirty = true
	return true


## Explicit private API for owner-only/offline relationship display.
func private_attachment_labels() -> Dictionary:
	var out := {}
	for n in relationships:
		var note: String = String(ledger.attachment_label(String(n), float(relationships[n])))
		var other: Node3D = _sim_by_name(String(n))
		if other != null:
			var view: String = psy.memory.current_view(memory_key(other))
			if view != "":
				note += " · " + view
			var lines: PackedStringArray = psy.memory.describe(memory_key(other), Callable(self, "gendered"), 1)
			if not lines.is_empty():
				note += " · pamatuje si: " + lines[0]
		var trusted: float = ledger.trust_in(String(n))
		if trusted >= 75.0:
			note += " · důvěra"
		elif trusted <= 25.0:
			note += " · nedůvěra"
		out[n] = note
	return out


## Presentation-only hook for a completed, strictly offscreen, non-playable event.
## Does NOT perform harm and is never an AI/player action or generated by a risk threshold.
## Full adult-sensitive opt-in, local offline world + active HUD required: no network leak.
func present_implied_sensitive_incident(kind: String = "self_harm") -> bool:
	if kind != "self_harm" or not _allows_rejection_risk():
		return false
	if world == null or not is_instance_valid(world) or world.get("net") == null:
		return false
	if world.net.is_networked() or world.get("hud") == null or visual == null:
		return false
	if _privacy_mask != null and is_instance_valid(_privacy_mask):
		return false
	_privacy_mask = SensitivePrivacyMask.new()
	_privacy_mask.name = "SensitiveEventOccluder"
	add_child(_privacy_mask)
	if not _privacy_mask.begin(visual):
		_privacy_mask.queue_free()
		_privacy_mask = null
		return false
	_privacy_mask.completed.connect(_after_sensitive_incident)
	return true


func _after_sensitive_incident() -> void:
	if _privacy_mask != null and is_instance_valid(_privacy_mask):
		_privacy_mask.queue_free()
		_privacy_mask = null
	var gs = get_node_or_null("/root/GameSettings")
	if gs == null or gs.mental_health_mode() != "full" or not gs.allows_content("sh_ed"):
		return
	var note := "Došlo k epizodě sebepoškozování. Postava může potřebovat podporu."
	# HUD is local/offline ONLY. No network RPC, no status or event replicated.
	if world != null and is_instance_valid(world) and world.get("hud") != null:
		world.hud.show_notice(note)
	private_sensitive_event_notice.emit(note)


## Kdo stojí poblíž hádky, toho to taky rozhodí (úzkostné víc).
func _witness_conflict(partner: Node3D, cfg: Dictionary, kind := "argue") -> void:
	if world == null:
		return
	for o in world.get_sims():
		if o == self or o == partner or not o.has_method("command") or o._is_sleeping():
			continue
		if o.global_position.distance_to(global_position) < WITNESS_DIST * 0.7:
			o.mental.on_stressor("witness_conflict", 3.0, cfg)
			# Svědek ví jen to, co viděl: hádku obou, nebo kdo koho urazil.
			if kind == "insult":
				o.remember_social(self, "conflict_seen", 0.5, "witnessed", "none", "", partner)
			else:
				o.remember_social(self, "conflict_seen", 0.3, "witnessed", "none", "", partner)
				o.remember_social(partner, "conflict_seen", 0.3, "witnessed", "none", "", self)


## Žárliví nesou těžce, když se jejich blízký (vztah ≥ 40) baví s někým jiným.
func _check_jealousy(partner: Node3D, cfg: Dictionary) -> void:
	if world == null:
		return
	for o in world.get_sims():
		if o == self or o == partner or not o.has_method("command"):
			continue
		var jealousy := Traits.flag_strength(o.trait_profile, "jealous")
		if jealousy <= 0.0:
			continue
		if o._is_sleeping() or o.global_position.distance_to(global_position) > WITNESS_DIST:
			continue
		for pair in [[self, partner], [partner, self]]:
			var friend: Node3D = pair[0]
			var rival: Node3D = pair[1]
			if float(o.relationships.get(friend.sim_name, 0.0)) >= 40.0 and not o.mood.has_moodlet("zarli_" + String(rival.name)):
				o.mental.on_stressor("jealousy", 6.0 * jealousy, cfg)
				o.emotions.impulse("jealousy", friend.sim_name, jealousy)
				o.mood.add_moodlet("zarli_" + String(rival.name), "Žárlí na: " + rival.first_name(), "nastvany", -10.0 * jealousy, 240.0)
				o.relationships[rival.sim_name] = clampf(float(o.relationships.get(rival.sim_name, 0.0)) - 2.0 * jealousy, -100.0, 100.0)
				o.ledger.grudges[rival.sim_name] = clampf(o.ledger.grudge(rival.sim_name) + 3.0 * jealousy, 0.0, 100.0)
				o._detail_dirty = true
				if o.speech == "" and o.rng.randf() < 0.4 * jealousy:
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
	net_label = "Soukromá chvíle" if current_action.get("id", "") == "adult_consensual_sex" else display_action()
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
		net_action = "private_moment|-1" if current_action["id"] == "adult_consensual_sex" else "%s|%d" % [current_action["id"], _object_index(target)]
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


## Emotional modulation is bounded: desires change, never lose agency.
func emotional_action_weight(action_id: String, tags: Array) -> float:
	return emotions.action_weight(action_id, tags)


func emotional_target_weight(who: String, action_id: String) -> float:
	if action_id not in ["chat", "confide"]:
		return 1.0
	var felt_safe := emotions.towards(who, "safety")
	var apprehension := emotions.towards(who, "fear") + emotions.towards(who, "anger")
	var bias := (felt_safe * 0.0011 - apprehension * 0.00055)
	# A deeply held self-belief modestly increases hesitation when approaching others,
	# but never creates a diagnosis, negative self-talk or a mandatory action.
	bias -= 0.04 * self_defectiveness_belief
	return clampf(1.0 + bias, 0.85, 1.12)


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
	# Not part of replicated _build_detail(): offline owner-only support hint.
	# An opt-in concern is never a SH action, graphic event or prediction.
	if world != null and is_instance_valid(world) and world.net != null and not world.net.is_networked():
		d["care"] = private_rejection_status()
		d["psyche_lines"] = psyche_private_lines()
		d["emotion_levels"] = emotions.levels.duplicate(true)
		d["crying"] = emotions.crying
		d["emotion_toward"] = emotions.top_people()
		if content_allowed("adult_intimacy"):
			d["sexual_arousal"] = intimacy.sexual_arousal
			d["sexual_preoccupation"] = intimacy.sexual_preoccupation
			d["libido"] = intimacy.libido_baseline
	return d


# ---------------------------------------------------------------- vizuál

func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(dir.x, dir.z)


func _update_visual() -> void:
	if visual == null:
		return
	visual.apply(current_posture(), mood.value, mood.emotion, sim_name, display_action(), speech, emotions.crying)
