extends "res://tests/test_base.gd"
## Deterministic, private 19-axis emotions with real 8-person household, and
## H4 exact continuation/legacy-save contracts. Never creates SH actions.
const Emotions := preload("res://scripts/sim/emotional_state.gd")
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const Actions := preload("res://scripts/sim/action_library.gd")
var gs: Node
var clock: Node

func _ready() -> void:
	watchdog_seconds = 65.0
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	gs.set_value("mental_health", "full", false)
	gs.set_value("sh_ed_topics", false, false)
	clock = get_node("/root/GameClock")
	clock.running = false
	_run.call_deferred()


func _run() -> void:
	section("19 simultaneous axes, opposite emotions and person-specific history")
	var e := Emotions.new()
	check(e.levels.size() == 19 and e.levels.has("uncertainty") and e.levels.has("compassion")
		and not e.levels.has("defectiveness"), "only 19 transient emotions; inner belief is not an emotion meter")
	check(e.level("safety") > 0.0 and e.level("sadness") == 0.0,
		"neutral defaults are distinct from symptoms")
	section("Crying expression with hysteresis, distinct from private character belief")
	check(not e.crying, "neutral agent is not crying")
	e.shift("sadness", 80.0)
	check(e.crying, "crying starts when sadness crosses the high threshold")
	e.shift("sadness", -15.0)
	check(e.crying, "crying does not flicker in the hysteresis zone")
	e.shift("sadness", -30.0)
	check(not e.crying, "crying stops only below the lower threshold")
	e.shift("sadness", 80.0)
	e.shift("joy", 65.0)
	check(e.level("sadness") >= 80.0 and e.level("joy") >= 65.0,
		"joy and sadness coexist; they do not cancel or overwrite each other")
	e.impulse("argue", "Iris_North")
	check(e.level("anger") > 0.0 and e.towards("Iris_North", "anger") > 0.0,
		"conflict adds several emotions directed at one actual person")
	check(e.towards("Ash_Solace", "anger") == 0.0,
		"feelings about a person are not assigned indiscriminately to others")
	e.impulse("rejection_perceived", "Iris_North")
	check(e.towards("Iris_North", "uncertainty") > e.towards("Iris_North", "sadness") * 0.5,
		"ambiguity stimulates uncertainty without claiming real rejection")
	e.impulse("confided", "Iris_North")
	check(e.towards("Iris_North", "safety") > 0.0 and e.level("hope") > 0.0,
		"being heard can increase felt safety and hope without clearing sadness")
	check(e.top_emotions(3).size() == 3 and e.top_people(6).size() >= 1,
		"deterministic top emotions and per-person display summaries")
	var snapshot: Dictionary = e.to_dict()
	var clone := Emotions.new()
	check(Emotions.validate_snapshot(snapshot) and clone.from_dict(snapshot),
		"valid typed snapshot restores")
	check(clone.to_dict() == snapshot,
		"save/load is bit-exact for all current and person-directed emotions")
	var old_snapshot: Dictionary = snapshot.duplicate(true)
	old_snapshot.erase("crying")
	var migrated := Emotions.new()
	check(Emotions.validate_snapshot(old_snapshot) and migrated.from_dict(old_snapshot)
		and migrated.levels.size() == 19,
		"legacy nineteen-axis snapshots without crying remain compatible")
	old_snapshot["levels"]["defectiveness"] = 24.0
	check(Emotions.validate_snapshot(old_snapshot) and migrated.from_dict(old_snapshot)
		and not migrated.levels.has("defectiveness"),
		"temporary twenty-axis snapshots load but do not restore the erroneous meter")
	var before := clone.to_dict()
	var malformed := snapshot.duplicate(true)
	malformed["levels"]["fear"] = NAN
	check(not Emotions.validate_snapshot(malformed) and not clone.from_dict(malformed)
		and clone.to_dict() == before,
		"NaN is refused without partially mutating a valid emotional state")
	malformed = snapshot.duplicate(true)
	malformed["crying"] = 1
	check(not Emotions.validate_snapshot(malformed),
		"saved crying state must be a boolean")
	malformed = snapshot.duplicate(true)
	malformed["levels"]["fear"] = 101.0
	check(not Emotions.validate_snapshot(malformed),
		"out-of-range axes cannot poison saved psychological state")
	malformed = snapshot.duplicate(true)
	malformed["directed"]["../../../secrets"] = {"anger": 12.0}
	check(not Emotions.validate_snapshot(malformed),
		"only safe stable NPC references are persisted")
	var old := Emotions.new()
	check(old.level("safety") == 35.0 and old.directed.is_empty(),
		"old saves without this new field get neutral default state")
	var baseline := e.level("fear")
	e.tick(0.0, {})
	check(e.level("fear") == baseline, "zero minutes does not modify the model")
	e.tick(100.0, {"social": 22.0, "burden": 0.75, "threat": 0.8,
		"stress": 75.0, "regulation": 0.3, "social_drive": 0.9})
	check(e.level("sadness") > 0.0 and e.level("fear") > 0.0
		and e.level("loneliness") > 0.0 and e.level("emotional_numbness") > 0.0,
		"context gently informs feelings but is not itself a diagnosis")
	check(e.level("joy") > 0.0, "positive feeling can remain during distress")
	var slow := Emotions.new()
	slow.shift("anger", 60.0)
	slow.shift("sadness", 60.0)
	slow.tick(120.0)
	check(slow.level("anger") < slow.level("sadness"),
		"anger normally decays faster than grief")
	var strong := Emotions.new()
	strong.shift("fear", 1000.0)
	strong.shift("guilt", -1000.0)
	strong.shift("unknown", 30.0)
	strong.impulse("does_not_exist")
	check(strong.level("fear") == 100.0 and strong.level("guilt") == 0.0
		and strong.level("unknown") == 0.0,
		"all levels bounded and unknown impulses ignored")
	for tag in [["social"], ["rest"], ["fun"], ["sleep"], []]:
		var w: float = e.action_weight("confide", tag)
		check(w >= 0.84 and w <= 1.16,
			"planner modifier is bounded for %s" % str(tag))
	check(Actions.get_action("self_harm").is_empty() and Actions.get_action("suicide").is_empty(),
		"neither distress nor emotions add an automated SH action")

	section("Real 8-character household, context, social events and strict privacy")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/data/extreme_profiles_fictional8.json"))
	Main.household_override = raw
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	var w := Node3D.new()
	w.name = "EmotionIntegrationWorld"
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false,
		"visuals": false, "autoload": false, "autosave": false, "clock": clock}
	add_child(w)
	var raven = w.find_sim("Raven_Vale")
	var iris = w.find_sim("Iris_North")
	var sable = w.find_sim("Sable_Wraith")
	check(w.sims.size() == 8 and raven != null and iris != null and sable != null,
		"real eight fictional non-Czech adult NPCs spawned")
	check(raven.emotions.levels.size() == 19
		and raven.emotions.dispositions.has("rejection_reactivity"),
		"current agents receive their own private emotional module and personality modifiers")
	var initial_joy: float = raven.emotions.level("joy")
	raven._social_outcome(iris, 4.5, "chat")
	check(raven.emotions.level("joy") > initial_joy
		and raven.emotions.towards(iris.sim_name, "joy") > 0.0,
		"real conversation changes the corresponding feelings towards Iris")
	raven.emotions.shift("sadness", 67.0)
	raven.mood.value = -60.0
	iris.emotions.shift("joy", 90.0)
	raven.emotions.shift("joy", -100.0)
	raven._social_outcome(iris, 4.0, "chat")
	check(raven.emotions.towards(iris.sim_name, "envy") > 0.0
		and raven.emotions.towards(iris.sim_name, "jealousy") == 0.0,
		"social comparison can elicit mild envy without confusing it with jealousy")
	raven._social_outcome(sable, -2.0, "misunderstanding")
	check(raven.emotions.towards(sable.sim_name, "uncertainty") > 0.0
		and raven.emotions.towards(sable.sim_name, "anger") == 0.0,
		"a real misunderstanding raises uncertainty rather than forced anger")
	raven._on_rejection_cue("perceived", iris, 0.7)
	check(raven.emotions.level("fear") > 0.0,
		"perceived rejection adds fear without asserting that Iris rejected her")
	raven.emotions.shift("joy", 40.0)
	raven.emotions.shift("sadness", 40.0)
	check(raven.emotions.level("joy") > 20.0 and raven.emotions.level("sadness") > 20.0,
		"mixed emotions survive an event in an actual living NPC")
	check(not raven._build_detail().has("emotion_levels")
		and not raven.net_detail.has("emotion_levels")
		and not raven._build_detail().has("emotion_toward"),
		"raw emotions and targeted information never enter replicated net_detail")
	check(raven.hud_info().has("emotion_levels")
		and typeof(raven.hud_info().get("emotion_toward")) == TYPE_ARRAY,
		"offline selected-character HUD can inspect personal emotion details")
	check(raven.emotional_target_weight(iris.sim_name, "chat") > 0.0
		and raven.emotional_action_weight("confide", ["social"]) > 0.0,
		"bounded emotional factors feed the actual AI without forced action")

	var saved: Dictionary = SaveGame.capture(w)
	check(bool(saved.get("ok", false)) and SaveGame.validate_data(saved["data"], w).get("ok", false),
		"new emotional state is inside strict H4 offline save schema")
	var current_saved = saved["data"].duplicate(true)
	var corrupt = saved["data"].duplicate(true)
	corrupt["sims"][0]["state"]["emotions"]["levels"]["anger"] = NAN
	check(SaveGame.validate_data(corrupt, w).get("reason", "") == "bad_emotions",
		"corrupted emotional saves are rejected before household state is destroyed")
	var applied: Dictionary = SaveGame.apply(w, saved["data"])
	check(bool(applied.get("ok", false))
		and SaveGame.capture(w)["data"] == current_saved,
		"real whole-household load restores emotional state exactly")
	var legacy: Dictionary = current_saved.duplicate(true)
	for item in legacy["sims"]:
		item["state"].erase("emotions")
	check(bool(SaveGame.validate_data(legacy, w).get("ok", false)),
		"pre-emotions version-one save is still accepted")
	check(bool(SaveGame.apply(w, legacy).get("ok", false)),
		"legacy household can really be restored")
	var restored_raven = w.find_sim("Raven_Vale")
	check(restored_raven.emotions.level("sadness") == 0.0
		and restored_raven.emotions.level("safety") == 35.0,
		"legacy household starts with neutral emotional defaults")

	var any_joy := false
	var any_strain := false
	for day in 3:
		for step in 720:
			clock.advance(2.0)
			if step % 60 == 0:
				for sim in w.sims:
					any_joy = any_joy or sim.emotions.level("joy") > 10.0
					any_strain = any_strain or sim.emotions.level("frustration") > 6.0
	var after = SaveGame.capture(w)
	check(bool(after["ok"]) and bool(SaveGame.validate_data(after["data"], w)["ok"]),
		"three-day autonomous simulation remains finite and saveable")
	check(any_joy and any_strain, "real home life generates both positive and negative emotions")
	var no_bad_values := true
	for sim in w.sims:
		for key in Emotions.KEYS:
			var val: float = sim.emotions.level(key)
			no_bad_values = no_bad_values and is_finite(val) and val >= 0.0 and val <= 100.0
	check(no_bad_values, "all 8×19 values stay bounded over 3 days")
	check(not after["data"]["sims"].is_empty() and
		not w.find_sim("Raven_Vale")._build_detail().has("emotion_levels"),
		"new state remains server/offline-only even after prolonged interaction")
	w.free()
	Main.household_override = []
	clock.running = false
	gs.reset()
	finish("test_emotional_state")


