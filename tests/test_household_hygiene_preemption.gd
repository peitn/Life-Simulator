extends "res://tests/test_base.gd"
## Regression: shower early enough to prevent the seed4 hygiene/cooking cliff.
## Uses real objects, a foreign-named fictional household and actual SimAgent
## planning/walking/acting. Does not relax the <10 critical acceptance.
const Main := preload("res://main.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const Actions := preload("res://scripts/sim/action_library.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
var clock
var gs

func _ready() -> void:
	watchdog_seconds = 40.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	section("Predictable shower planning before hygiene becomes critical")
	var fixture: Array = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/data/extreme_profiles_fictional8.json"))
	Main.household_override = fixture
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var w := Node3D.new()
	w.name = "HygieneUrgencyRegression"
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false,
		"camera": false, "visuals": false, "autoload": false,
		"autosave": false, "clock": clock}
	add_child(w)
	var raven = w.find_sim("Raven_Vale")
	var iris = w.find_sim("Iris_North")
	var shower
	var stove
	for obj in w.get_smart_objects():
		if obj.object_tag == "shower":
			shower = obj
		if obj.object_tag == "stove":
			stove = obj
	check(w.sims.size() == 8 and raven != null and iris != null
		and shower != null and stove != null,
		"real eight-adult scenario includes an actual shower and stove")
	raven.needs.values["hunger"] = 70.0
	raven.needs.values["energy"] = 70.0
	raven.needs.values["hygiene"] = Planner.HYGIENE_SHOWER_PRIORITY
	check(Planner.urgent_hygiene_plan(raven, w.get_smart_objects()).is_empty(),
		"at healthy hygiene threshold a shower is not compulsory")
	raven.needs.values["hygiene"] = 22.0
	var choice: Dictionary = Planner.urgent_hygiene_plan(raven, w.get_smart_objects())
	check(choice.get("action", {}).get("id", "") == "shower"
		and choice.get("target") == shower,
		"NPC proactively locates the free shower above critical hygiene")
	check(Planner.choose(raven, w.get_smart_objects(), w.get_sims(),
		raven.rng, 9).get("action", {}).get("id", "") == "shower",
		"real planner prioritizes shower over tempting unrelated tasks")
	raven.needs.values["hunger"] = 12.0
	check(Planner.urgent_hygiene_plan(raven, w.get_smart_objects()).is_empty(),
		"true critical hunger retains priority over hygiene")
	raven.needs.values["hunger"] = 70.0
	raven.needs.values["energy"] = 9.0
	check(Planner.urgent_hygiene_plan(raven, w.get_smart_objects()).is_empty(),
		"true critical exhaustion retains priority over hygiene")
	raven.needs.values["energy"] = 70.0
	check(shower.reserve(iris), "other NPC can reserve the actual bathroom")
	check(Planner.urgent_hygiene_plan(raven, w.get_smart_objects()).is_empty(),
		"occupied bathroom never produces an invalid urgent reservation")
	shower.release(iris)

	section("Cooking interrupted before hygiene drops below ten")
	raven.needs.values["hygiene"] = 21.0
	raven.current_action = Actions.get_action("cook").duplicate(true)
	raven.target = stove
	raven.state = SimAgent.State.ACTING
	raven.by_player = false
	raven.action_elapsed = 11.0
	check(stove.reserve(raven), "NPC actually reserves the kitchen while cooking")
	var interrupted := false
	var min_hygiene: float = float(raven.needs.values["hygiene"])
	for step in 40:
		raven.needs.tick(2.0)
		raven._act(2.0)
		min_hygiene = minf(min_hygiene, float(raven.needs.values["hygiene"]))
		if raven.state == SimAgent.State.IDLE:
			interrupted = true
			break
	check(interrupted and raven.last_action_id == "cook"
		and raven.action_elapsed < float(Actions.get_action("cook")["duration"]),
		"autonomous character stops cooking early rather than finishing neglectfully",
		"action_elapsed=%.1f hygiene=%.3f" %
		[raven.action_elapsed, raven.needs.values["hygiene"]])
	check(min_hygiene >= 10.0,
		"the original <10 acceptance boundary is never crossed before stopping",
		"min %.3f" % min_hygiene)
	check(not stove.users.has(raven), "interrupted cooking releases stove reservation")
	check(raven.think_cooldown == 0.0, "urgent replan is immediate on the next clock tick")
	raven._decide()
	check(raven.current_action.get("id", "") == "shower" and raven.target == shower,
		"AI picks shower after abandoning cooking, not another leisure action")
	check(shower.users.has(raven) and raven.state == SimAgent.State.WALKING,
		"AI reserves the bathroom and walks to it")
	var min_travel: float = float(raven.needs.values["hygiene"])
	var recovered := false
	for step in 35:
		raven.needs.tick(2.0)
		min_travel = minf(min_travel, float(raven.needs.values["hygiene"]))
		if raven.state == SimAgent.State.WALKING:
			raven._walk(2.0)
		elif raven.state == SimAgent.State.ACTING:
			raven._act(2.0)
		if float(raven.needs.values["hygiene"]) >= 40.0:
			recovered = true
			break
	check(min_travel >= 10.0 and recovered,
		"walk to bathroom and actual shower recover hygiene without a critical dip",
		"travel min=%.3f now=%.3f" % [min_travel, raven.needs.values["hygiene"]])
	if raven.state == SimAgent.State.ACTING:
		raven._finish(true)
	elif raven.state == SimAgent.State.WALKING:
		raven._abort()
	check(not shower.users.has(raven), "completed/aborted shower never leaks reservation")

	section("Consent and availability: never force user action or busy facility")
	raven.needs.values["hygiene"] = 18.0
	raven.by_player = true
	raven.current_action = Actions.get_action("cook").duplicate(true)
	raven.state = SimAgent.State.ACTING
	raven.action_elapsed = 12.0
	raven.target = stove
	check(stove.reserve(raven), "player-controlled cook reserves the kitchen")
	raven._act(2.0)
	check(raven.state == SimAgent.State.ACTING and raven.current_action["id"] == "cook",
		"player's requested cooking is NOT overridden by hygiene urgency")
	raven._finish(true)
	raven.by_player = false
	raven.needs.values["hygiene"] = 18.0
	raven.current_action = Actions.get_action("sleep").duplicate(true)
	raven.state = SimAgent.State.ACTING
	raven.action_elapsed = 12.0
	raven.target = null
	raven._act(2.0)
	check(raven.state == SimAgent.State.ACTING,
		"non-interruptible sleep is never forcibly stopped for a shower")
	raven._finish(true)
	raven.current_action = Actions.get_action("cook").duplicate(true)
	raven.state = SimAgent.State.ACTING
	raven.action_elapsed = 12.0
	raven.target = stove
	check(stove.reserve(raven) and shower.reserve(iris),
		"stove and shower occupancy can be tracked separately")
	raven._act(2.0)
	check(raven.state == SimAgent.State.ACTING,
		"no interrupted-work thrashing while the only bathroom is occupied")
	shower.release(iris)
	raven._act(2.0)
	check(raven.state == SimAgent.State.IDLE,
		"once bathroom becomes available, urgent care can resume")
	check(not stove.users.has(raven),
		"second interruption still releases kitchen cleanly")

	section("Actions that DECREASE hygiene cannot mask the preemption")
	var treadmill
	for obj in w.get_smart_objects():
		if obj.object_tag == "treadmill":
			treadmill = obj
	check(treadmill != null, "real exercise machine exists in the test household")
	raven.needs.values["hygiene"] = 18.0
	raven.current_action = Actions.get_action("workout").duplicate(true)
	raven.state = SimAgent.State.ACTING
	raven.action_elapsed = 12.0
	raven.target = treadmill
	raven.by_player = false
	check(treadmill.reserve(raven), "exercise actually reserves the machine")
	raven._act(2.0)
	check(raven.state == SimAgent.State.IDLE and raven.last_action_id == "workout",
		"workout's negative hygiene effect does not falsely count as cleaning")
	check(not treadmill.users.has(raven), "early exit frees the exercise machine")
	w.free()
	Main.household_override = []
	clock.running = false
	gs.reset()
	finish("test_household_hygiene_preemption")
