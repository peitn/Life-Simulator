extends "res://tests/test_base.gd"
## Tail checks separated from 16-seed household matrix to avoid MCP 120-second kill.
## Same seed 14 days must lead to identical relationship/stress/statistics signatures.
const Main := preload("res://main.gd")
const DAYS := 14
var clock: Node

func _ready() -> void:
	watchdog_seconds = 85.0
	clock = get_node("/root/GameClock")
	clock.running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _one_run(seed: int, days: int) -> Dictionary:
	clock.total_minutes = 8.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "DeterministicHousehold"
	w.net_config = {"mode": "offline", "audio": false, "hud": false,
		"camera": false, "visuals": false, "autosave": false, "autoload": false}
	add_child(w)
	var n := 0
	for sim in w.sims:
		sim.rng.seed = seed * 7919 + n * 104729 + 13
		sim.think_cooldown = sim.rng.randf_range(0.0, 3.0)
		n += 1
	for m in days * 720:
		clock.advance(2.0)
	var sig := PackedStringArray()
	for a in w.sims:
		for b in w.sims:
			if a != b:
				sig.append("%.4f" % float(a.relationships.get(b.sim_name, 0.0)))
		sig.append("%.4f" % a.mental.stress)
	var stats: Dictionary = w.dynamics.stats.duplicate(true)
	sig.append(JSON.stringify(stats))
	var output := {"seed": seed, "days": days, "sig": ",".join(sig),
		"talks": int(stats["talks"]), "arguments": int(stats["argues"]),
		"characters": w.sims.size()}
	w.queue_free()
	await get_tree().process_frame
	return output


func _run() -> void:
	section("Original long household matrix: isolated final determinism checks")
	var a: Dictionary = await _one_run(3, DAYS)
	var b: Dictionary = await _one_run(3, DAYS)
	check(a["characters"] == 3 and b["characters"] == 3,
		"both scenarios have the original 3-person household")
	check(a["sig"] == b["sig"],
		"replay of identical seed over 14 days reproduces all relationships, stresses and household statistics")
	check(a["talks"] > 20 and b["talks"] == a["talks"] and
		b["arguments"] == a["arguments"],
		"the deterministic replay still contains actual relationships and conflicts")
	print("DETERMINISM_14D seed3 talks=%d arguments=%d sig_equal=%s" % [
		a["talks"], a["arguments"], str(a["sig"] == b["sig"])])
	var c: Dictionary = await _one_run(4, 2)
	var d: Dictionary = await _one_run(3, 2)
	check(c["sig"] != d["sig"],
		"different seed produces a different two-day social outcome")
	check(a["sig"] != c["sig"] and a["sig"] != d["sig"],
		"14-day path has advanced beyond either two-day scenario")
	print("DETERMINISM_SHORT seed4 talks=%d seed3 talks=%d different=%s" % [
		c["talks"], d["talks"], str(c["sig"] != d["sig"])])
	clock.running = false
	finish("test_household_determinism_split")
