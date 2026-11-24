extends "res://tests/test_base.gd"
const Main = preload("res://main.gd")
const ROOT = "user://test-coldwar-cold-process-v1"
var world: Node
var clock: Node
func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	var slot := _slot()
	world = Node3D.new()
	world.set_script(Main)
	world.name = "ColdWarColdWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":ROOT+"/"+slot,"clock":clock}
	add_child(world)
	_run.call_deferred()
func _slot() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			return arg.trim_prefix("--slot=")
	return ""
func _run() -> void:
	var slot := _slot()
	var reader := "--reader" in OS.get_cmdline_user_args()
	section("ColdWar independent process "+("reader" if reader else "writer"))
	check(slot.length() >= 12 and slot.is_valid_identifier(), "unique slot required")
	if slot.length() < 12 or not slot.is_valid_identifier():
		world.free()
		finish("test_cold_war_cold_process")
		return
	var path := ROOT+"/"+slot+"/manual.lss"
	var a := String(world.sims[0].sim_name)
	var b := String(world.sims[1].sim_name)
	if not reader:
		check(not FileAccess.file_exists(path), "writer refuses stale slot")
		if FileAccess.file_exists(path):
			world.free()
			finish("test_cold_war_cold_process")
			return
		clock.total_minutes = 200.0
		world.dynamics.cold_war.note(a,b,"argue",200.0)
		world.dynamics.cold_war.note(a,b,"argue",201.0)
		check(world.dynamics.cold_war.stage(a,b)==1, "stage before save")
		var saved: Dictionary = world.save_game("manual")
		check(saved.get("ok",false), "writer saved",str(saved))
		check(FileAccess.file_exists(path), "physical save exists")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size()>128 and FileAccess.get_open_error()==OK,"nonempty readable save")
	else:
		check(FileAccess.file_exists(path), "reader sees physical file")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size()>128 and FileAccess.get_open_error()==OK,"reader reads save")
		clock.total_minutes = 777.0
		var loaded: Dictionary = world.load_game("manual")
		check(loaded.get("ok",false), "reader loads disk",str(loaded))
		check(is_equal_approx(clock.total_minutes,200.0), "reader restores GameClock")
		check(world.dynamics.cold_war.stage(a,b)==1, "reader restores stage")
		check(world.dynamics.cold_war.recent_argues(a,b,100.0)==0, "future argues ignored at rewind")
		check(world.dynamics.cold_war.recent_argues(a,b,211.0)==2, "argues restored at catchup")
		check(world.dynamics.cold_war.clear_air_block(a,b,210.0)=="", "no future cooldown inherited")
	world.free()
	clock.running = false
	finish("test_cold_war_cold_process")