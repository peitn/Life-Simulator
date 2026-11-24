extends "res://tests/test_base.gd"
const Main = preload("res://main.gd")
const MAN = {"age":35,"aromantic":false,"attracted_to":["zeny"],"group":"muzi"}
const WOMAN = {"age":30,"aromantic":false,"attracted_to":["muzi"],"group":"zeny"}
var world: Node
var clock: Node
var save_dir: String
func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 200.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-romance-disk-clock-" + str(OS.get_process_id())
	world = Node3D.new()
	world.set_script(Main)
	world.name = "RomanceDiskWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":save_dir,"clock":clock}
	add_child(world)
	_run.call_deferred()
func _run() -> void:
	section("Romance disk snapshot, GameClock and rewind semantics")
	var a = String(world.sims[0].sim_name)
	var b = String(world.sims[1].sim_name)
	var r = world.dynamics.romance
	check(r.resolve_ask(a,b,MAN,WOMAN,1.0,0.0,200.0) == "yes", "dating setup")
	check(r.partner_of(a) == b and r.status(a,b) == "dating", "partner before save")
	var snapshot = JSON.stringify(r.to_dict())
	var saved = world.save_game("manual")
	check(bool(saved.get("ok",false)) and FileAccess.file_exists(save_dir+"/manual.lss"), "physical save",str(saved))
	check(not r.breakup(a,b,300.0).is_empty() and r.status(a,b) == "ex", "later breakup")
	check(r.ask_block(a,b,301.0) == "not_now", "later breakup cooldown")
	clock.total_minutes = 100.0
	check(r.ask_block(a,b,100.0) == "" and r.status(a,b) == "ex", "rewind skips cooldown but retains ex status")
	var loaded = world.load_game("manual")
	r = world.dynamics.romance
	check(bool(loaded.get("ok",false)) and is_equal_approx(clock.total_minutes,200.0), "disk load restores clock",str(loaded))
	check(r.status(a,b) == "dating" and r.partner_of(a) == b, "disk load restores relationship")
	check(JSON.stringify(r.to_dict()) == snapshot, "serialized romance state roundtrip")
	clock.total_minutes = 100.0
	check(r.ask_block(a,b,100.0) == "already", "restored branch remains dating at rewind")
	world.free()
	clock.running = false
	finish("test_romance_disk_clock")