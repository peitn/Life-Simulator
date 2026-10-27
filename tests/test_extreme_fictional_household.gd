extends "res://tests/test_base.gd"
## Intentionally fictional extreme-psychological-profile household, NOT a diagnosis or
## replica of any actual user. Adult foreign-name fixture; non-graphic content only.
## Local isolated H4 checkpoints, no new self-harm or suicide actions.
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const DAYS := 14
const NPC_COUNT := 8
var duration_days := DAYS
const FIXTURE := "res://tests/data/extreme_profiles_fictional8.json"

var clock: Node
var settings: Node
var seed_info := {}
var bad_floats := 0
var save_dir := ""

func _ready() -> void:
	watchdog_seconds = 110.0
	clock = get_node("/root/GameClock")
	clock.running = false
	settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	settings.set_value("mental_health", "full", false)
	settings.set_value("sh_ed_topics", false, false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			duration_days = clampi(int(arg.trim_prefix("--days=")), 1, 45)
	save_dir = "user://test-extreme-fictional-" + str(OS.get_process_id())
	_run.call_deferred()


func _fixture() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _make_world(seed: int, scenario: String) -> Node3D:
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	clock.running = false
	Main.household_override = _fixture()
	var w := Node3D.new()
	w.name = "Extreme" + scenario + str(seed)
	w.set_script(Main)
	w._seed_offset = seed
	w.net_config = {"mode": "offline", "audio": false, "hud": false,
		"camera": false, "visuals": false, "autoload": false, "autosave": false,
		"clock": clock, "save_directory": save_dir + "/" + scenario + "-" + str(seed)}
	add_child(w)
	return w


func _prepare(w: Node3D, scenario: String) -> void:
	var first_stress := {"Raven": 74.0, "Sable": 94.0, "Dorian": 80.0,
		"Juno": 77.0, "Orion": 92.0, "Iris": 36.0, "Ash": 26.0, "Lucian": 86.0}
	var first_burden := {"Raven": 0.56, "Sable": 0.78, "Dorian": 0.86,
		"Juno": 0.34, "Orion": 0.43, "Iris": 0.06, "Ash": 0.02, "Lucian": 0.28}
	for sim in w.sims:
		var name: String = sim.first_name()
		sim.mental.stress = float(first_stress[name])
		sim.mental.dep.burden = float(first_burden[name])
		if name in ["Raven", "Sable", "Dorian", "Orion"]:
			sim.needs.values["energy"] = 31.0 if name != "Dorian" else 22.0
		if name in ["Raven", "Sable", "Juno", "Orion", "Lucian"]:
			sim.mental.threat = 0.57
		if name == "Raven":
			sim.mental.support = 0.06 if scenario == "low_support" else 0.88
	var raven = w.find_sim("Raven_Vale")
	var iris = w.find_sim("Iris_North")
	var ash = w.find_sim("Ash_Solace")
	if scenario == "high_support" and raven != null and iris != null and ash != null:
		raven.relationships[iris.sim_name] = 68.0
		iris.relationships[raven.sim_name] = 68.0
		raven.relationships[ash.sim_name] = 71.0
		ash.relationships[raven.sim_name] = 71.0
	# A single ambiguous social cue (NOT confirmed real-world rejection).
	# Its impact differs with support; no graphic self-harm outcomes.
	if raven != null:
		var event: Dictionary = raven.rejection.on_cue("perceived", 0.95, 0.90,
			raven.mental.support, 0.44)
		raven.mental.on_stressor("social", float(event["stress"]) * 3.0)


func _valid_numbers(w: Node3D) -> bool:
	for s in w.sims:
		for need in s.needs.values.values():
			if not is_finite(float(need)) or need < -0.00001 or need > 100.00001:
				return false
		for v in [s.mental.stress, s.mental.arousal, s.mental.positive_arousal]:
			if not is_finite(float(v)) or v < -0.00001 or v > 100.00001:
				return false
		for v in [s.mental.dep.burden, s.mental.threat, s.rejection.distress]:
			if not is_finite(float(v)) or v < -0.00001 or v > 1.00001:
				return false
		for v in s.relationships.values():
			if not is_finite(float(v)) or v < -100.0001 or v > 100.0001:
				return false
	return true


func _run_case(scenario: String, seed: int, checkpoint: bool = true) -> Dictionary:
	var started := Time.get_ticks_msec()
	var w := _make_world(seed, scenario)
	if w.sims.size() != NPC_COUNT:
		w.free()
		return {"ok": false, "error": "incorrect_agent_count"}
	_prepare(w, scenario)
	var initial = SaveGame.capture(w)
	var raven = w.find_sim("Raven_Vale")
	var configs: Dictionary = {
		"raven_rejection": raven.rejection.reactivity,
		"raven_social_decay": raven.needs.decay_mult["social"],
		"raven_energy_dim": float(w._character_records["Raven_Vale"].mind["dispositions"]["energy_baseline"]),
		"raven_support": raven.mental.support,
		"raven_alt_top": w._character_records["Raven_Vale"].clothing["bezne"]["top"]}
	var record: Dictionary = {}
	for sim in w.sims:
		record[String(sim.name)] = {"low": 0, "severe": 0, "high_stress": 0,
			"min_mood": 100.0, "max_mood": -100.0, "max_burden": 0.0,
			"max_arousal": 0.0, "max_rejection": 0.0, "min_energy": 100.0,
			"stress_sum": 0.0, "streak_high": 0, "longest_high": 0,
			"observations": 0}
	var valid := true
	var mismatch: PackedStringArray = []
	var saves := 0
	var saved_size := 0
	for day in duration_days:
		for tick in 720:
			clock.advance(2.0)
			if tick % 30 == 0:
				if not _valid_numbers(w):
					valid = false
					bad_floats += 1
				for sim in w.sims:
					var d: Dictionary = record[String(sim.name)]
					d["observations"] += 1
					d["stress_sum"] += sim.mental.stress
					d["min_mood"] = minf(d["min_mood"], sim.mood.value)
					d["max_mood"] = maxf(d["max_mood"], sim.mood.value)
					d["max_burden"] = maxf(d["max_burden"], sim.mental.dep.burden)
					d["max_arousal"] = maxf(d["max_arousal"], sim.mental.arousal)
					d["max_rejection"] = maxf(d["max_rejection"], sim.rejection.distress)
					d["min_energy"] = minf(d["min_energy"], sim.needs.values["energy"])
					if sim.needs.average() < 20.0:
						d["low"] += 1
					if sim.mental.dep.burden >= 0.95:
						d["severe"] += 1
					if sim.mental.stress > 85.0:
						d["high_stress"] += 1
						d["streak_high"] += 1
						d["longest_high"] = maxi(d["longest_high"], d["streak_high"])
					else:
						d["streak_high"] = 0
		if checkpoint and (day == 6 or (duration_days > DAYS and day > 6 and day % 7 == 6)):
			var before: Dictionary = SaveGame.capture(w)
			var save: Dictionary = w.save_game("manual")
			if not before.get("ok", false) or not save.get("ok", false):
				mismatch.append("save_failed:" + String(save.get("reason", "capture")))
			else:
				saves += 1
				saved_size = int(save.get("bytes", 0))
				w.free()
				w = _make_world(seed, scenario)
				var reload: Dictionary = w.load_game("manual")
				if not reload.get("ok", false):
					mismatch.append("load_failed:" + String(reload.get("reason", "unknown")))
				else:
					var after: Dictionary = SaveGame.capture(w)
					if not after.get("ok", false) or after["data"] != before["data"]:
						var diff := PackedStringArray()
						if after.get("ok", false):
							for field in before["data"]:
								if after["data"].get(field) != before["data"][field]:
									diff.append(String(field))
							for i in before["data"]["sims"].size():
								var before_sim: Dictionary = before["data"]["sims"][i]["state"]
								var after_sim: Dictionary = after["data"]["sims"][i]["state"]
								var fields := PackedStringArray()
								for field in before_sim:
									if before_sim[field] != after_sim.get(field):
										fields.append(String(field))
								if not fields.is_empty():
									print("RESTORE_DIFF sim=%s fields=%s" % [
										String(before["data"]["sims"][i]["node"]), ",".join(fields)])
									if fields.has("mental"):
										for mind_key in before_sim["mental"]:
											if before_sim["mental"][mind_key] != after_sim["mental"].get(mind_key):
												print("RESTORE_DIFF_MIND sim=%s key=%s before=%s after=%s" % [
													String(before["data"]["sims"][i]["node"]),
													String(mind_key),str(before_sim["mental"][mind_key]),
													str(after_sim["mental"].get(mind_key))])
						print("RESTORE_DIFF_TOP scenario=%s seed=%d fields=%s" % [scenario, seed, ",".join(diff)])
						mismatch.append("full_state_mismatch:" + ",".join(diff))
	var sums := PackedStringArray()
	for sim in w.sims:
		var d: Dictionary = record[String(sim.name)]
		sums.append("%s mood%+.0f stress%.0f dep%.2f panic%d arousal%.0f" % [
			sim.first_name(), sim.mood.value, sim.mental.stress,
			sim.mental.dep.burden, sim.mental.panic_count, sim.mental.arousal])
	var result := {"ok": valid and mismatch.is_empty(), "scenario": scenario,
		"seed": seed, "agent_count": w.sims.size(), "saves": saves,
		"save_bytes": saved_size, "mismatch": Array(mismatch),
		"elapsed": (Time.get_ticks_msec() - started) / 1000.0,
		"days": duration_days, "clock": clock.total_minutes, "metrics": record,
		"initial": initial.get("ok", false), "config": configs,
		"talks": int(w.dynamics.stats["talks"]),
		"argues": int(w.dynamics.stats["argues"]),
		"friction": w.dynamics.stats["friction"].duplicate(true),
		"final_state": SaveGame.capture(w)["data"], "remaining": sums}
	print("EXTREME_RUN scenario=%s seed=%d runtime=%.1fs talks=%d argues=%d (%.1f%%) saves=%d bytes=%d valid=%s" % [
		scenario,seed,result["elapsed"],result["talks"],result["argues"],
		100.0 * float(result["argues"])/maxf(1.0,float(result["talks"])),
		saves,saved_size,str(result["ok"])])
	for sim in w.sims:
		var m: Dictionary = record[String(sim.name)]
		print("EXTREME_PERSON %s | mood=%.0f range[%.0f..%.0f] avgStress=%.1f maxDep=%.3f highStressHours=%d severeHours=%d lowNeedHours=%d maxReject=%.2f" % [
			sim.sim_name,sim.mood.value,m["min_mood"],m["max_mood"],
			m["stress_sum"]/maxf(1.0,float(m["observations"])),m["max_burden"],
			m["high_stress"],m["severe"],m["low"],m["max_rejection"]])
	w.queue_free()
	await get_tree().process_frame
	return result


func _run() -> void:
	section("Eight adult fictional characters, all names non-Czech; explicit psychological dimensions")
	var raw: Array = _fixture()
	check(raw.size() == NPC_COUNT, "fixture has exactly eight adult characters")
	var names: PackedStringArray = []
	var all_valid := true
	for item in raw:
		names.append(item["identity"]["first_name"] + " " + item["identity"]["last_name"])
		if int(item["body"]["age"]) < 18:
			all_valid = false
		if (item["mind"]["dispositions"] as Dictionary).size() != 11:
			all_valid = false

	check(all_valid, "all fictional profiles are adults and expose all eleven psyche dimensions")
	check(names == PackedStringArray(["Raven Vale", "Sable Wraith", "Dorian Flint",
		"Juno Vex", "Orion Voss", "Iris North", "Ash Solace", "Lucian Rook"]),
		"all eight names are explicitly non-Czech English-language fictional names")
	Main.household_override = raw
	var normalized: Array = Main.household_characters()
	var strict_ok := true
	for item in normalized:
		strict_ok = strict_ok and bool(Validator.validate(item).get("ok", false))
	check(strict_ok, "eight profiles satisfy strict CharacterData schema and are spawnable")
	var raven: Dictionary = normalized[0]
	check(raven["identity"]["gender_identity"] == "zena"
		and raven["identity"]["grammar"] == "f"
		and raven["personality"]["aspirations"].has("tvorba")
		and raven["personality"]["aspirations"].has("pratele"),
		"Raven fictional profile is a woman with creative and friendship aspirations")
	check(raven["mind"]["dispositions"]["social_threat"] >= 0.9
		and raven["mind"]["dispositions"]["rejection_reactivity"] >= 0.9
		and raven["mind"]["dispositions"]["energy_baseline"] <= 0.3
		and raven["personality"]["trait_levels"]["spolecensky"] >= 0.8,
		"Raven models simultaneously high closeness need, rejection sensitivity and low energy")
	check(raven["clothing"]["bezne"]["top"] == "kawaii_kocici_mikina"
		and raven["clothing"]["bezne"]["bottom"] == "goth_sukne",
		"Raven uses authored alternative/kawaii-goth game wardrobe")
	var public_character = load("res://scripts/character/character_data.gd").new()
	public_character.set_from_dict(raven)
	check(not public_character.public_snapshot().has("mind")
		and not public_character.public_snapshot().has("story"),
		"private psychological dimensions cannot enter public multiplayer appearance snapshots")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var chosen_scenario := ""
	var chosen_seed := -1
	for arg in args:
		if arg.begins_with("--scenario="):
			chosen_scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--seed="):
			chosen_seed = int(arg.trim_prefix("--seed="))
	# Regression found by the high-pressure 8-NPC test: resolved panic can
	# retain a 26-minute last duration after a two-minute simulation step.
	var panic_restored = MentalState.new()
	var panic_saved: Dictionary = panic_restored.to_dict()
	panic_saved["panic_elapsed"] = 26.0
	panic_saved["panic_active"] = false
	panic_restored.from_dict(panic_saved)
	check(panic_restored.to_dict()["panic_elapsed"] == 26.0,
		"ended panic duration exceeding nominal 25-minute threshold round trips exactly")
	var runs := []
	for scenario in ["low_support", "high_support"]:
		if chosen_scenario != "" and scenario != chosen_scenario:
			continue
		for seed in [3, 7]:
			if chosen_seed >= 0 and seed != chosen_seed:
				continue
			var res: Dictionary = await _run_case(scenario, seed)
			runs.append(res)
			check(res.get("ok", false), "extreme scenario restores valid full state and has bounded physiology: " + scenario + " seed " + str(seed), str(res.get("mismatch", [])))
			var expected_saves: int = duration_days / 7 if duration_days > DAYS else 1
			check(int(res.get("agent_count", 0)) == NPC_COUNT and int(res.get("saves", 0)) == expected_saves,
				"eight fully configured NPCs survive true mid-scenario disk save/reload", scenario+str(seed))
			check(int(res.get("talks", 0)) > 8 and int(res.get("argues", 0)) >= 0,
				"social interactions continue throughout extreme stress", scenario+str(seed))
			var config: Dictionary = res.get("config", {})
			check(float(config.get("raven_rejection",0.0)) > 0.8
				and float(config.get("raven_social_decay",0.0)) > 1.0
				and float(config.get("raven_energy_dim",1.0)) <= 0.3,
				"fictional Raven trait and psyche settings are active in actual SimAgent runtime")
	if args.has("--control") and runs.size() == 1:
		var saved_case: Dictionary = runs[0]
		var never_saved: Dictionary = await _run_case(String(saved_case["scenario"]), int(saved_case["seed"]), false)
		check(never_saved.get("ok", false) and never_saved.get("saves", -1) == 0,
			"independent same-seed stress control runs without a save or reload")
		check(saved_case["final_state"] == never_saved.get("final_state", {}),
			"14-day eight-person household ending is exactly identical with and without 7-day disk reload")
		print("EXTREME_UNINTERRUPTED_CONTROL scenario=%s seed=%d exact=%s" % [
			saved_case["scenario"],saved_case["seed"],
			str(saved_case["final_state"] == never_saved.get("final_state", {}))])
	section("Support versus low-support conditions; comparison is descriptive, not clinical")
	if runs.size() == 4:
		for i in 2:
			var low: Dictionary = runs[i]["metrics"].get("Raven_Vale", {})
			var high: Dictionary = runs[i+2]["metrics"].get("Raven_Vale", {})
			print("RAVEN_COMPARE seed=%d low_avg_stress=%.2f high_avg_stress=%.2f low_peak_dep=%.3f high_peak_dep=%.3f low_high_stress_hours=%d high_high_stress_hours=%d" % [
				runs[i]["seed"],float(low["stress_sum"])/maxf(1.0,float(low["observations"])),
				float(high["stress_sum"])/maxf(1.0,float(high["observations"])),
				low["max_burden"],high["max_burden"],low["high_stress"],high["high_stress"]])
		check(true,"paired Raven condition summaries emitted without claiming medical prediction")
	check(bad_floats == 0, "no NaN, infinities or out-of-range needs / arousal / stress / emotional dimensions")
	Main.household_override = []
	settings.reset()
	clock.running = false
	finish("test_extreme_fictional_household")
