extends "res://tests/test_base.gd"
## Thirty simulated days with real on-disk checkpoints and full reload of seven Sims.
## Isolated test slots, never user://saves/ from a player's actual game.
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const CHUNK_DAYS := 5
const TOTAL_DAYS := 30

var clock: Node
var world: Node3D
var gs: Node
var base_dir: String
var counters: Dictionary = {}
var low_samples: Dictionary = {}
var severe_samples: Dictionary = {}
var stress_hi_samples: Dictionary = {}
var samples := 0
var loaded_count := 0
var saved_bytes := 0
var last_snap: Dictionary = {}

func _ready() -> void:
	watchdog_seconds = 105.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	base_dir = "user://test-lifesim-soak-" + str(OS.get_process_id())
	_run.call_deferred()


func _new_world() -> Node3D:
	var w := Node3D.new()
	w.name = "SaveSoakWorld"
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false,
		"camera": false, "visuals": false, "autoload": false, "autosave": false,
		"save_directory": base_dir, "clock": clock}
	add_child(w)
	return w


func _check_bounds() -> bool:
	for s in world.sims:
		if not is_instance_valid(s) or not s.has_method("command"):
			return false
		for v in s.needs.values.values():
			if not is_finite(float(v)) or float(v) < -0.0001 or float(v) > 100.0001:
				return false
		for v in [s.mental.stress, s.mental.arousal, s.mental.positive_arousal]:
			if not is_finite(float(v)) or float(v) < -0.0001 or float(v) > 100.0001:
				return false
		if not is_finite(s.mental.dep.burden) or s.mental.dep.burden < 0.0 or s.mental.dep.burden > 1.0:
			return false
	return true


func _count_hourly() -> void:
	samples += 1
	for s in world.sims:
		var key: String = String(s.name)
		if s.needs.average() < 20.0:
			low_samples[key] = int(low_samples.get(key, 0)) + 1
		if s.mental.dep.burden >= 0.95:
			severe_samples[key] = int(severe_samples.get(key, 0)) + 1
		if s.mental.stress > 85.0:
			stress_hi_samples[key] = int(stress_hi_samples.get(key, 0)) + 1


func _run() -> void:
	section("Actual seven-Sim 30-day life, disk save and cold-resume every five days")
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/household_stress7.json"))
	if typeof(raw) != TYPE_ARRAY or raw.size() != 7:
		check(false, "seven character stress fixture exists and parses")
		finish("test_household_resume")
		return
	Main.household_override = raw
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	world = _new_world()
	check(world.sims.size() == 7 and not world.net.is_networked(),
		"real single-player Godot simulation spawned seven different NPCs")
	var initial_minutes: float = clock.total_minutes
	var all_valid := true
	var all_exact := true
	var all_written := true
	var all_live := true
	for chunk in TOTAL_DAYS / CHUNK_DAYS:
		var elapsed := Time.get_ticks_msec()
		for step in CHUNK_DAYS * 720:
			clock.advance(2.0)
			if step % 30 == 0:
				_count_hourly()
				if not _check_bounds():
					all_valid = false
		var captured: Dictionary = SaveGame.capture(world)
		if not captured.get("ok", false):
			check(false, "save capture after chunk " + str(chunk+1), str(captured))
			all_written = false
			break
		last_snap = captured["data"]
		var writing: Dictionary = world.save_game("manual")
		if not writing.get("ok", false):
			check(false, "save file after chunk " + str(chunk+1), str(writing))
			all_written = false
			break
		saved_bytes += int(writing.get("bytes", 0))
		var old_clock: float = clock.total_minutes
		world.free()
		world = null
		clock.running = false
		world = _new_world()
		var loaded: Dictionary = world.load_game("manual")
		if not loaded.get("ok", false):
			check(false, "cold reload after chunk " + str(chunk+1), str(loaded))
			all_live = false
			break
		loaded_count += 1
		var after: Dictionary = SaveGame.capture(world)
		if not after.get("ok", false) or after["data"] != last_snap:
			all_exact = false
		if clock.total_minutes != old_clock or world.sims.size() != 7:
			all_live = false
		print("SOAK_CHUNK %d/%d: day %d, %.1fs simulation, save %d bytes, full snapshot %s, arguments %d, mood %s" % [
			chunk + 1, TOTAL_DAYS / CHUNK_DAYS, clock.get_day(),
			(Time.get_ticks_msec()-elapsed)/1000.0, writing.get("bytes", 0),
			"exact" if after.get("ok",false) and after["data"] == last_snap else "MISMATCH",
			int(world.dynamics.stats["talks"]),
			String(world.sims[0].mood.emotion)])
	check(all_written and all_live and loaded_count == TOTAL_DAYS / CHUNK_DAYS,
		"all six 5-day checkpoint files saved and entire household cold-restored")
	check(all_exact, "six consecutive complete seven-NPC snapshots remain exactly equal after cold resume")
	check(all_valid and samples > 0, "all simulated hourly samples remain numerically bounded without NaN or Inf")
	check(clock.total_minutes == initial_minutes + TOTAL_DAYS * 1440.0,
		"30 full simulated days advanced without resetting GameClock")
	var highest_low := 0.0
	var highest_severe := 0.0
	var highest_stress := 0.0
	for n in low_samples:
		highest_low = maxf(highest_low, float(low_samples[n]) / maxf(float(samples),1.0))
	for n in severe_samples:
		highest_severe = maxf(highest_severe, float(severe_samples[n]) / maxf(float(samples),1.0))
	for n in stress_hi_samples:
		highest_stress = maxf(highest_stress, float(stress_hi_samples[n]) / maxf(float(samples),1.0))
	print("SOAK_SUMMARY days=%d samples=%d saves=%d total_bytes=%d talks=%d arguments=%d high_low=%.2f high_dep=%.2f high_stress=%.2f" % [
		TOTAL_DAYS, samples, loaded_count, saved_bytes,
		int(world.dynamics.stats["talks"]), int(world.dynamics.stats["argues"]),
		highest_low, highest_severe, highest_stress])
	check(highest_low < 0.1,
		"no household member remains on chronically collapsed average needs",
		"worst fraction %.3f" % highest_low)
	check(highest_severe < 0.25,
		"severe depression does not stick at the absolute maximum of 0.95+",
		"worst fraction %.3f" % highest_severe)
	check(int(world.dynamics.stats["talks"]) > 10 and
		int(world.dynamics.stats["events"]["good"] + world.dynamics.stats["events"]["bad"]) > 10,
		"AI conversations and random events continue after repeated disk loading")
	check(world.save_game("manual").get("ok", false) and
		FileAccess.file_exists(base_dir + "/manual.lss.bak"),
		"final save remains recoverable through the previous-good backup")

	section("Control: uninterrupted 30-day baseline versus six genuine disk reloads")
	var resumed_end: Dictionary = SaveGame.capture(world)["data"]
	world.free()
	world = null
	clock.total_minutes = initial_minutes
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	clock.running = false
	world = _new_world()
	for step in TOTAL_DAYS * 720:
		clock.advance(2.0)
	var uninterrupted: Dictionary = SaveGame.capture(world)["data"]
	var diffs := PackedStringArray()
	for k in resumed_end:
		if not uninterrupted.has(k) or uninterrupted[k] != resumed_end[k]:
			diffs.append(k)
	var bad_agents := PackedStringArray()
	for i in 7:
		if uninterrupted["sims"][i] != resumed_end["sims"][i]:
			var fields := PackedStringArray()
			var resumed_agent: Dictionary = resumed_end["sims"][i]["state"]
			var baseline_agent: Dictionary = uninterrupted["sims"][i]["state"]
			for key in resumed_agent:
				if not baseline_agent.has(key) or resumed_agent[key] != baseline_agent[key]:
					fields.append(String(key))
			bad_agents.append("%s:%s" % [resumed_end["sims"][i]["node"], ",".join(fields)])
	print("SOAK_CONTROL equal=%s differing_top=%s varying_agents=%s" % [
		str(uninterrupted == resumed_end), ",".join(diffs), ";".join(bad_agents)])
	check(uninterrupted == resumed_end,
		"30-day save/reload trajectory is identical to a separate never-saved 30-day control",
		"top_level=[" + ",".join(diffs) + "] agents=[" + ";".join(bad_agents) + "]")
	world.free()
	world = null
	Main.household_override = []
	clock.running = false
	finish("test_household_resume")
