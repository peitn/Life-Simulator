extends "res://tests/test_base.gd"
## Stažení do sebe a vyhýbání střetu (review Groka #169, body 1–3).
##   - Depression.withdrawal(): podle stupně epizody méně chuti na společnost a náročné povinnosti,
##     víc na samotu; joy_severity_mult(): těžká epizoda tlumí radost i z oblíbených věcí.
##   - MentalState.avoidance(): vysoký stres + stažení → postava se radši vyhne člověku, na kterého
##     má pifku, a výtku občas spolkne (to ale vrací ruminaci). Nic se nezakazuje.

const Main := preload("res://main.gd")
const Depression := preload("res://scripts/sim/depression.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

const CFG_FULL := {"conditions": true, "episodes": true, "thought_rate": 1.0}
const CFG_OFF := {"conditions": false, "episodes": false, "thought_rate": 0.0}

var world: Node3D
var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 120.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	world = Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(world)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_withdrawal_levels()
	_test_avoidance_levels()
	_test_planner()
	_test_swallow()
	_test_compound_distress()
	finish("test_withdrawal_avoidance")


func _episode(sev: int, burden: float) -> Depression:
	var d := Depression.new()
	d.burden = burden
	d.episode_active = sev > 0
	d.severity = sev
	return d


func _test_withdrawal_levels() -> void:
	section("Stažení podle stupně epizody")
	var w: Array = []
	for s in 4:
		w.append(_episode(s, [0.1, 0.62, 0.74, 0.9][s]).withdrawal())
	check(float(w[0]) < 0.01, "bez epizody skoro žádné stažení", str(w))
	check(float(w[0]) < float(w[1]) and float(w[1]) < float(w[2]) and float(w[2]) < float(w[3]), "mírná < středně těžká < těžká", str(w))
	check(float(w[3]) <= 0.35, "stažení má strop (nic se nezakazuje)", str(w[3]))
	check(is_equal_approx(_episode(0, 0.1).joy_severity_mult(), 1.0) and _episode(3, 0.9).joy_severity_mult() < _episode(2, 0.74).joy_severity_mult(),
		"těžká epizoda tlumí radost víc než středně těžká")


func _test_avoidance_levels() -> void:
	section("Sklon vyhnout se střetu")
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var ms := MentalState.new(r, true)
	ms.stress = 20.0
	check(ms.avoidance(CFG_FULL) == 0.0, "v klidu se nikdo nevyhýbá")
	ms.stress = 95.0
	var a_st := ms.avoidance(CFG_FULL)
	check(a_st > 0.3, "vysoký stres → vyhýbání", "%.2f" % a_st)
	ms.dep.burden = 0.9
	ms.dep.episode_active = true
	ms.dep.severity = 3
	var a_dep := ms.avoidance(CFG_FULL)
	check(a_dep > a_st and a_dep <= 0.7, "těžká epizoda přidá stažení, se stropem", "%.2f" % a_dep)
	check(is_equal_approx(ms.avoidance(CFG_OFF), a_st), "vypnutá témata: jen stres, bez depresivní složky")


func _sim(n: String):
	return world.find_sim(SimAgent.node_name_for(n))


func _reset(s) -> void:
	s.player_queue.clear()
	s.command({"id": "cancel"}, null)
	s.mental.dep.burden = 0.0
	s.mental.dep.episode_active = false
	s.mental.dep.severity = 0
	s.mental.dep.vigour = 1.0
	s.mental.dep.hedonic = 1.0
	s.mental.dep.pessimism = 0.0
	s.mental.stress = 10.0
	s.mental.arousal = 5.0
	s.pending_complaints.clear()
	s.ledger.grudges.clear()
	for k in s.needs.values:
		s.needs.values[k] = 60.0


func _test_planner() -> void:
	section("Plánovač: stažení a vyhýbání")
	var jana = _sim("Jana Nováková")
	var petr = _sim("Petr Dvořák")
	check(jana != null and petr != null, "postavy ve světě")
	if jana == null or petr == null:
		return
	_reset(jana)
	var chat: Dictionary = ActionLibrary.get_action("chat")
	var hide: Dictionary = ActionLibrary.get_action("hide")
	check(not chat.is_empty(), "akce rozhovoru existuje")
	var chat0: float = Planner.score_action(jana, chat, 14)
	jana.mental.dep.burden = 0.9
	jana.mental.dep.hedonic = 1.0
	jana.mental.dep.vigour = 1.0
	jana.mental.dep.pessimism = 0.0
	jana.mental.dep.episode_active = true
	jana.mental.dep.severity = 3
	var chat3: float = Planner.score_action(jana, chat, 14)
	check(chat3 < chat0 * 0.8 and chat3 > 0.0, "těžká epizoda: rozhovor láká méně, ale ne nula",
		"%.2f → %.2f" % [chat0, chat3])
	if not hide.is_empty():
		var w: float = jana.mental.dep.withdrawal()
		check(w > 0.25, "v těžké epizodě je stažení znatelné", "%.2f" % w)
	# Vyhýbání konkrétnímu člověku: pifka + čerstvá výtka, ve stresu.
	_reset(jana)
	check(is_equal_approx(Planner.avoidance_weight(jana, petr, chat), 1.0), "v klidu žádné vyhýbání")
	jana.mental.stress = 95.0
	check(is_equal_approx(Planner.avoidance_weight(jana, petr, chat), 1.0), "ve stresu bez pifky se nikomu nevyhýbá")
	jana.ledger.on_hurt_by(petr.sim_name, 30.0, clock.total_minutes)
	jana.pending_complaints[petr.sim_name] = {"topic": "dishes", "t": float(clock.total_minutes)}
	var aw: float = Planner.avoidance_weight(jana, petr, chat)
	check(aw < 0.8 and aw >= 0.3, "ve stresu se vyhne tomu, na koho má pifku (ale ne úplně)", "%.2f" % aw)
	var apol: Dictionary = ActionLibrary.get_action("apologize")
	if not apol.is_empty():
		check(is_equal_approx(Planner.avoidance_weight(jana, petr, apol), 1.0), "omluvy se vyhýbání netýká")
	_reset(jana)


func _test_swallow() -> void:
	section("Spolknutá výtka")
	var jana = _sim("Jana Nováková")
	var petr = _sim("Petr Dvořák")
	if jana == null or petr == null:
		return
	_reset(jana)
	var kept := 0
	for i in 50:
		if jana.maybe_swallow("dishes", petr) != "":
			kept += 1
	check(kept == 50 and jana.swallowed_complaints == 0, "v klidu výtku nespolkne", str(kept))
	jana.mental.stress = 95.0
	jana.mental.dep.burden = 0.9
	jana.mental.dep.episode_active = true
	jana.mental.dep.severity = 3
	var rum0: float = jana.mental.dep.rumination
	var swallowed := 0
	for i in 200:
		if jana.maybe_swallow("dishes", petr) == "":
			swallowed += 1
	check(swallowed > 40 and swallowed < 160, "ve stresu a depresi výtku často spolkne, ne vždy", str(swallowed))
	check(jana.swallowed_complaints == swallowed, "počítadlo spolknutých výtek")
	check(jana.mental.dep.rumination > rum0, "spolknutá výtka se vrací v myšlenkách (není zadarmo)")
	check(jana.mood.has_moodlet("spolknuta_" + petr.name), "nálada: Radši jsem mlčel(a)")
	check(jana.maybe_swallow("", petr) == "", "bez výtky nic")
	_reset(jana)


func _test_compound_distress() -> void:
	section("Kombinace vnitřní nedostatečnosti, stažení, úzkosti a vyhledání pomoci")
	var jana = _sim("Jana Nováková")
	var petr = _sim("Petr Dvořák")
	if jana == null or petr == null:
		check(false, "two actual household NPCs must exist")
		return
	_reset(jana)
	var chat: Dictionary = ActionLibrary.get_action("chat")
	var confide: Dictionary = ActionLibrary.get_action("confide")
	var help: Dictionary = ActionLibrary.get_action("seek_help")
	var ordinary: float = Planner.score_action(jana, chat, 14)
	jana.self_defectiveness_belief = 1.0
	jana.mental.stress = 95.0
	jana.mental.threat = 0.85
	jana.mental.dep.burden = 0.92
	jana.mental.dep.episode_active = true
	jana.mental.dep.severity = 3
	jana.mental.arousal = 90.0
	jana.ledger.on_hurt_by(petr.sim_name, 30.0, clock.total_minutes)
	jana.pending_complaints[petr.sim_name] = {"topic": "dishes", "t": float(clock.total_minutes)}
	var strained: float = Planner.score_action(jana, chat, 14)
	var confide_score: float = Planner.score_action(jana, confide, 14)
	var target: float = Planner.avoidance_weight(jana, petr, confide) * jana.emotional_target_weight(petr.sim_name, "confide")
	print("COMPOUND_SOCIAL ",JSON.stringify({"baseline_chat":ordinary,"strained_chat":strained,"confide":confide_score,"target_weight":target}))
	check(ordinary > 0.0 and strained > 0.0 and strained < ordinary,
		"withdrawal and social anxiety lower social initiative without forbidding conversation")
	check(confide_score > 0.0 and target > 0.0 and confide_score * target > 0.01,
		"helpful disclosure remains numerically available under compounded difficulties")
	check(jana.self_defectiveness_belief == 1.0 and jana.emotions.levels.size() == 19,
		"inner conviction remains private stable data, not a twentieth emotion")
	for _i in 6:
		jana.inner_trigger("failure", null, 0.9)
	var help_gate: float = jana.psyche_gate("help")
	var help_score: float = Planner.score_action(jana, help, 14)
	print("COMPOUND_HELP ",JSON.stringify({"gate":help_gate,"score":help_score}))
	check(help_gate > 0.0 and help_score > 0.0, "rumination enables a voluntary professional-help option")
	check(ActionLibrary.get_action("self_harm").is_empty() and ActionLibrary.get_action("suicide").is_empty(),
		"no automatic dangerous action is created by high distress")
	_reset(jana)