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
	save_dir = "user://test-coldwar-disk-clock-" + str(OS.get_process_id())
	world = Node3D.new()
	world.set_script(Main)
	world.name = "ColdWarDiskWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":save_dir,"clock":clock}
	add_child(world)
	_run.call_deferred()
func _run() -> void:
	section("ColdWar real disk snapshot and GameClock fork")
	var a = String(world.sims[0].sim_name)
	var b = String(world.sims[1].sim_name)
	clock.total_minutes = 200.0
	world.dynamics.cold_war.note(a,b,"argue",200.0)
	world.dynamics.cold_war.note(a,b,"argue",201.0)
	check(world.dynamics.cold_war.stage(a,b) == 1, "initial stage established")
	var snapshot = world.dynamics.cold_war.to_dict()
	var saved = world.save_game("manual")
	check(bool(saved.get("ok",false)) and FileAccess.file_exists(save_dir+"/manual.lss"), "actual save written",str(saved))
	var outcome = world.dynamics.cold_war.resolve_clear_air(a,b,1.0,0.0,210.0)
	check(outcome == "breakthrough" and world.dynamics.cold_war.stage(a,b)==0, "live timeline diverges")
	clock.total_minutes = 100.0
	var loaded = world.load_game("manual")
	check(bool(loaded.get("ok",false)) and is_equal_approx(clock.total_minutes,200.0), "disk load restores GameClock",str(loaded))
	check(world.dynamics.cold_war.stage(a,b)==1, "disk load restores stage")
	check(world.dynamics.cold_war.clear_air_block(a,b,210.0)=="", "future branch cooldown not inherited")
	check(JSON.stringify(world.dynamics.cold_war.to_dict())==JSON.stringify(snapshot), "cold war snapshot roundtrip")
	clock.total_minutes = 100.0
	check(world.dynamics.cold_war.recent_argues(a,b,clock.total_minutes)==0, "rewind ignores future arguments")
	clock.total_minutes = 211.0
	check(world.dynamics.cold_war.recent_argues(a,b,clock.total_minutes)==2, "catch-up restores argument window")
	world.free()
	clock.running=false
	finish("test_cold_war_disk_clock")