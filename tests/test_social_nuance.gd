extends "res://tests/test_base.gd"
## Real offline Life Simulator world: richer ordinary conversations, directed
## trust and repeated relationship history, learned (non-diagnostic) dependency.
## Sensitive topics: only private opt-in care flags; NEVER automated SH acts.
const Main := preload("res://main.gd")
const Ledger := preload("res://scripts/sim/rel_ledger.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const Actions := preload("res://scripts/sim/action_library.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
var clock: Node
var gs: Node
var world: Node3D
var observed := []

func _ready() -> void:
	watchdog_seconds = 55.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	gs.set_value("mental_health", "full", false)
	gs.set_value("sh_ed_topics", false, false)
	_run.call_deferred()


func _run() -> void:
	section("Private directed trust, persistent relationship patterns, and real dependency learning")
	var a := Ledger.new()
	check(a.trust_in("Ash") == 45.0 and a.attachment_to("Ash", 90.0)["dependency"] == 0.0,
		"fondness alone creates neither automatic trust nor dependency")
	for i in 9:
		a.record_trust("Ash", "warm", 4.0)
	check(a.trust_in("Ash") > 75.0 and a.trust_in("Other") == 45.0,
		"safe repetitions build specific-person trust while other contacts stay neutral")
	a.on_hurt_by("Ash", 25.0, 100.0)
	a.on_hurt_by("Ash", 25.0, 200.0)
	check(a.trust_in("Ash") < 70.0 and int(a.relational_history["Ash"]["hurt"]) == 2,
		"repeat harm erodes trust and is remembered beyond rolling text memories")
	a.receive_apology("Ash", "accepted", 300.0)
	check(int(a.relational_history["Ash"]["repair"]) == 1 and a.trust_in("Ash") < 75.0,
		"apologies can repair but not instantly erase repeated harm")
	check(Planner.confide_trust_weight(10.0) > 0.0 and
		Planner.confide_trust_weight(90.0) > Planner.confide_trust_weight(10.0),
		"high trust makes confiding more attractive, but even low trust is not a ban")
	var restored := Ledger.new()
	restored.from_dict(a.to_dict())
	check(restored.to_dict() == a.to_dict(),
		"entire compact relational history, attachment and trust serialize exactly")
	restored.from_dict({"grudges": {"Ash": 3.0}})
	check(restored.trust_in("Ash") == 45.0 and restored.relational_history.is_empty(),
		"old H4 saves without new fields remain compatible")

	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/extreme_profiles_fictional8.json"))
	Main.household_override = raw
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	world = Node3D.new()
	world.set_script(Main)
	world.name = "SocialNuanceTest"
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false,
		"visuals": false, "autoload": false, "autosave": false, "clock": clock}
	add_child(world)
	var raven = world.find_sim("Raven_Vale")
	var ash = world.find_sim("Ash_Solace")
	var lucian = world.find_sim("Lucian_Rook")
	check(world.sims.size() == 8 and raven != null and ash != null and lucian != null,
		"eight distinct fictional, non-Czech adult NPCs are truly spawned")
	check(raven.rejection.reactivity >= 0.9 and ash.rejection.reactivity < 0.4,
		"psychological predispositions from CharacterData are active in real agents")
	raven.relationships[ash.sim_name] = 90.0
	ash.relationships[raven.sim_name] = 90.0
	check(raven.ledger.attachment_to(ash.sim_name, 90.0)["dependency"] == 0.0,
		"real spawned NPC begins without artificially preseeded dependency")
	for i in 110:
		raven.ledger.record_trust(ash.sim_name, "warm", 1.0)
		raven._learn_connection(ash)
		ash.ledger.record_trust(raven.sim_name, "warm", 1.0)
		ash._learn_connection(raven)
	var dep_raven: float = float(raven.ledger.attachment_to(ash.sim_name, 90.0)["dependency"])
	var dep_ash: float = float(ash.ledger.attachment_to(raven.sim_name, 90.0)["dependency"])
	check(dep_raven > 0.25 and dep_raven > dep_ash + 0.2,
		"high social need + rejection sensitivity can gradually produce *directional* dependency",
		"Raven %.3f Ash %.3f" % [dep_raven, dep_ash])
	check(String(raven.private_attachment_labels().get(ash.sim_name, "")).contains("emoční závislost")
		and String(raven.private_attachment_labels().get(ash.sim_name, "")).contains("důvěra"),
		"private offline HUD labels developing dependency and earned trust without raw diagnostic numbers")
	check(raven.ledger.attachment_to(ash.sim_name, 90.0)["importance"] > 0.5 and
		raven.ledger.trust_in(ash.sim_name) > 60.0,
		"importance, dependency and trust coexist as distinct values")
	raven.ledger.decay(24.0 * 60.0 * 10.0)
	check(float(raven.ledger.attachment_to(ash.sim_name, 90.0)["dependency"]) < dep_raven,
		"dependency can subside instead of being a permanent locked state")
	var node_reload := Ledger.new()
	node_reload.from_dict(raven.ledger.to_dict())
	check(node_reload.to_dict() == raven.ledger.to_dict(),
		"actual NPC learned attachment and trust can be saved and perfectly recovered")

	section("Real household conversations have separate negative social outcomes")
	raven.conversation.connect(_on_conversation)
	raven.rng.seed = 34192
	raven.relationships[lucian.sim_name] = -30.0
	lucian.relationships[raven.sim_name] = -30.0
	raven.mood.value = -85.0
	lucian.mood.value = -85.0
	for i in 140:
		raven.mental.stress = 98.0
		lucian.mental.stress = 98.0
		raven.current_action = Actions.get_action("chat").duplicate(true)
		raven.target = lucian
		raven._start_social(lucian)
		raven._finish(false)
	var outcomes: Dictionary = world.dynamics.stats["outcomes"]
	var totals := 0
	for kind in outcomes:
		totals += int(outcomes[kind])
	check(totals == 140 and world.dynamics.stats["talks"] == 140,
		"one and only one social outcome is recorded per real conversation")
	check(int(outcomes.get("argue", 0)) > 0 and int(outcomes.get("awkward", 0)) > 0 and
		int(outcomes.get("misunderstanding", 0)) > 0,
		"real seeded agents experience fights, awkward silence and misunderstandings")
	check(int(world.dynamics.stats["argues"]) == int(outcomes["argue"]),
		"awkwardness and misunderstandings DO NOT count as arguments")
	check(int(outcomes["awkward"]) + int(outcomes["misunderstanding"]) > 0 and
		observed.size() == 140 and observed.all(func(e): return e.has("outcome") and e.has("argued")),
		"outcome labels and argued flag remain auditable per conversation")
	check(raven.ledger.relational_history.has(lucian.sim_name) and
		int(raven.ledger.relational_history[lucian.sim_name].get("misunderstanding", 0)) > 0,
		"mild negative experiences are preserved in compact persistent memory")

	section("SH is a private opt-in concern, not an autonomous gameplay action")
	raven.rejection.distress = 0.9
	raven.mental.stress = 95.0
	raven.mental.support = 0.01
	raven.rejection.update_concern(95.0, 0.1, 0.01, raven._allows_rejection_risk())
	check(not raven.private_rejection_status().has("safety_concern"),
		"sensitive concern is completely hidden without adult opt-in")
	gs.set_value("sh_ed_topics", true, false)
	raven.rejection.update_concern(95.0, 0.1, 0.01, raven._allows_rejection_risk())
	check(raven.private_rejection_status().get("safety_concern", false) == true,
		"non-graphic elevated support concern can appear when explicitly enabled")
	check(bool(raven.hud_info().get("care", {}).get("safety_concern", false)),
		"offline private HUD data includes contextual support hint when enabled")
	var cd = CharacterData.new()
	cd.set_from_dict(raw[0])
	check(not cd.public_snapshot().has("mind") and
		not raven._build_detail().has("safety_concern") and
		not raven._build_detail().has("trust"),
		"private risk, emotional dependency and trust are not publicly replicated")
	check(Actions.get_action("self_harm").is_empty() and
		Actions.get_action("suicide").is_empty(),
		"no automated or playable self-harm action, reward or method was introduced")
	gs.set_value("sh_ed_topics", false, false)
	raven.rejection.update_concern(95.0, 0.1, 0.01, raven._allows_rejection_risk())
	check(not raven.private_rejection_status().has("safety_concern"),
		"disabling sensitive content immediately removes private risk flag")
	raven.mental.dep.burden = 0.94
	raven.mental.stress = 91.0
	check(bool(raven.hud_info().get("care", {}).get("support_needed", false))
		and not raven.hud_info().get("care", {}).has("safety_concern"),
		"severe prolonged depression and stress can prompt support without conflating it with SH")
	world.free()
	Main.household_override = []
	clock.running = false
	gs.reset()
	finish("test_social_nuance")


func _on_conversation(_a, _b, info: Dictionary) -> void:
	observed.append(info.duplicate(true))
