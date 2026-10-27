extends "res://tests/test_base.gd"
## Uninterrupted simulation against save/load continuation, including mid-action state.
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
var world: Node
var clock: Node
var save_dir: String

func _run() -> void:
	section("Uninterrupted 20 game minutes vs save/reload + 20 minutes")
	var w = world
	clock.advance(37.0)
	var snapshot = SaveGame.capture(w)
	check(snapshot.get("ok", false), "capture after a live 37-minute scenario")
	var ongoing := 0
	for s in w.sims:
		if s.state != s.State.IDLE:
			ongoing += 1
	check(ongoing >= 0, "save while autonomous simulation has chosen real plans", str(ongoing))
	var checkpoint = w.save_game("manual")
	check(checkpoint.get("ok", false), "checkpoint actual binary file written", str(checkpoint))
	clock.advance(20.0)
	var future_a: Dictionary = SaveGame.capture(w)
	check(future_a.get("ok", false), "uninterrupted future world captured")
	var loaded: Dictionary = w.load_game("manual")
	check(loaded.get("ok", false), "mid-simulation checkpoint restored", str(loaded))
	clock.advance(20.0)
	var future_b: Dictionary = SaveGame.capture(w)
	check(future_b.get("ok", false), "resumed future world captured")
	check(future_a["data"]["clock"] == future_b["data"]["clock"],
		"same game time and speed after save/reload continuation")
	check(future_a["data"]["dynamics"] == future_b["data"]["dynamics"],
		"household friction, life events, and counters deterministic across reload")
	var equal_agents := 0
	var bad: Array = []
	for i in future_a["data"]["sims"].size():
		var a: Dictionary = future_a["data"]["sims"][i]["state"]
		var b: Dictionary = future_b["data"]["sims"][i]["state"]
		if a == b:
			equal_agents += 1
		else:
			var mismatched: Array = []
			for k in a:
				if not b.has(k) or a[k] != b[k]:
					mismatched.append(k)
			bad.append({"agent": i, "fields": mismatched})
	check(equal_agents == future_a["data"]["sims"].size(),
		"agent futures identical across RNG, action timers, psyche and memory", str(bad))
	check(future_a["data"] == future_b["data"],
		"complete snapshot stays bit-compatible across uninterrupted and resumed runs")

	section("Autosave on game-day boundary, without requiring a real-time 5m delay")
	var manager = w._save_manager
	var existing: Dictionary = manager.load_slot("autosave")
	var present: bool = existing.get("ok", false)
	clock.total_minutes = 1439.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	clock.advance(2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var auto: Dictionary = manager.load_slot("autosave")
	check(auto.get("ok", false) and int(auto["data"]["clock"]["total_minutes"]) == 1441,
		"crossing midnight triggers autosave after all simulated day callbacks", str(auto.get("reason", "")))
	check(not present or int(auto["data"]["clock"]["total_minutes"]) > 0,
		"autosave is available independent of a manual save")
	w.free()
	clock.running = false
	finish("test_save_continuation")


func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	save_dir = "user://test-lifesim-continuation-" + str(OS.get_process_id())
	world = Node3D.new()
	world.name = "ContinuationWorld"
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "camera": false,
		"visuals": false, "hud": false, "autoload": false, "autosave": true,
		"save_directory": save_dir, "clock": clock}
	add_child(world)
	_run.call_deferred()
