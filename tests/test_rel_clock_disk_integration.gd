extends "res://tests/test_base.gd"
const Main = preload("res://main.gd")
var world: Node
var clock: Node
var save_dir: String
func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-rel-disk-clock-" + str(OS.get_process_id())
	world = Node3D.new()
	world.set_script(Main)
	world.name = "RelClockWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":save_dir,"clock":clock}
	add_child(world)
	_run.call_deferred()
func _run() -> void:
	section("Real disk save and GameClock rewind relationship timing")
	var actor = world.sims[0]
	var other: String = world.sims[1].sim_name
	clock.total_minutes = 200.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	actor.ledger.on_hurt_by(other, 40.0, 180.0)
	actor.ledger.receive_apology(other, "partial", 200.0)
	var stored = world.save_game("manual")
	check(stored.get("ok",false) and FileAccess.file_exists(save_dir + "/manual.lss"), "real save file written", str(stored))
	actor.ledger.receive_apology(other, "full", 210.0)
	clock.total_minutes = 100.0
	var loaded = world.load_game("manual")
	check(loaded.get("ok",false) and is_equal_approx(clock.total_minutes,200.0), "real load restores clock",str(loaded))
	actor = world.sims[0]
	check(is_equal_approx(actor.ledger.sincerity(other,210.0),0.7), "saved apology history restored")
	clock.total_minutes = 100.0
	check(is_equal_approx(actor.ledger.sincerity(other,clock.total_minutes),1.0), "rewound GameClock ignores future apology")
	check(actor.ledger.evaluate_apology(other,clock.total_minutes,0.0,0.0,0.0,0.5).outcome != "spam", "future apology not spam at rewound clock")
	check(actor.ledger.evaluate_apology(other,clock.total_minutes,0.0,0.0,0.0,0.5).reason != "příliš brzy", "future hurt not too soon at rewound clock")
	clock.total_minutes = 210.0
	check(is_equal_approx(actor.ledger.sincerity(other,clock.total_minutes),0.7), "apology time boundary recovers")
	check(actor.ledger.evaluate_apology(other,clock.total_minutes,0.0,0.0,0.0,0.5).outcome == "spam", "cooldown recovers after clock catches up")
	world.free()
	clock.running = false
	finish("test_rel_clock_disk_integration")
