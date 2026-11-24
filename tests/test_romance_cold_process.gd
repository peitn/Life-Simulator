extends "res://tests/test_base.gd"
const Main = preload("res://main.gd")
const ROOT = "user://test-romance-cold-process-v1"
const MAN = {"age":35,"aromantic":false,"attracted_to":["zeny"],"group":"muzi"}
const WOMAN = {"age":30,"aromantic":false,"attracted_to":["muzi"],"group":"zeny"}
var world: Node
var clock: Node
func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 200.0
	world = Node3D.new()
	world.set_script(Main)
	world.name = "RomanceColdWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":ROOT+"/"+_slot(),"clock":clock}
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
	var expected_hash := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sha256="):
			expected_hash = arg.trim_prefix("--sha256=")
	section("Romance independent disk process "+("reader" if reader else "writer"))
	check(slot.length() >= 12 and slot.is_valid_identifier(), "unique safe slot")
	if slot.length() < 12 or not slot.is_valid_identifier():
		world.free()
		finish("test_romance_cold_process")
		return
	var path := ROOT+"/"+slot+"/manual.lss"
	var a := String(world.sims[0].sim_name)
	var b := String(world.sims[1].sim_name)
	var r = world.dynamics.romance
	if not reader:
		check(not FileAccess.file_exists(path), "writer rejects stale save")
		if FileAccess.file_exists(path):
			world.free()
			finish("test_romance_cold_process")
			return
		check(r.resolve_ask(a,b,MAN,WOMAN,1.0,0.0,200.0)=="yes", "dating created")
		check(r.partner_of(a)==b and is_equal_approx(r.contact_weight(a,b,"chat",200.0),1.3), "nondefault relationship before save")
		check(not r.breakup(a,b,300.0).is_empty(), "breakup before disk save")
		clock.total_minutes = 310.0
		check(r.ask_block(a,b,310.0)=="not_now" and is_equal_approx(r.contact_weight(a,b,"chat",310.0),0.6), "nontrivial cooldown before save")
		var saved: Dictionary = world.save_game("manual")
		check(bool(saved.get("ok",false)), "writer saved",str(saved))
		check(FileAccess.file_exists(path), "physical save exists")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size()>128 and FileAccess.get_open_error()==OK, "save bytes readable")
		print("ROMANCE_SAVE_SHA256=",FileAccess.get_sha256(path))
	else:
		check(FileAccess.file_exists(path), "reader sees saved file")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size()>128 and FileAccess.get_open_error()==OK, "reader sees nonempty bytes")
		check(expected_hash.length()==64 and FileAccess.get_sha256(path)==expected_hash, "reader verifies exact writer payload SHA256")
		if expected_hash.length()!=64 or FileAccess.get_sha256(path)!=expected_hash:
			world.free()
			finish("test_romance_cold_process")
			return
		clock.total_minutes = 777.0
		var loaded: Dictionary = world.load_game("manual")
		r = world.dynamics.romance
		check(bool(loaded.get("ok",false)), "reader loads disk",str(loaded))
		check(is_equal_approx(clock.total_minutes,310.0), "clock restored")
		check(r.partner_of(a)=="" and r.status(a,b)=="ex", "saved breakup restored")
		check(r.ask_block(a,b,310.0)=="not_now" and is_equal_approx(r.contact_weight(a,b,"chat",310.0),0.6), "saved cooldown and contact penalty restored")
		check(r.ask_block(a,b,301.0)=="not_now", "cooldown active")
		check(is_equal_approx(r.contact_weight(a,b,"chat",301.0),0.6), "ex contact penalty active")
		clock.total_minutes = 100.0
		check(r.ask_block(a,b,100.0)=="" and is_equal_approx(r.contact_weight(a,b,"chat",100.0),1.0), "rewind ignores future breakup effects")
		clock.total_minutes = 10379.0
		check(r.ask_block(a,b,10379.0)=="not_now", "saved breakup cooldown before exact expiry")
		clock.total_minutes = 10380.0
		check(r.ask_block(a,b,10380.0)=="", "saved breakup cooldown expires at exact 7-day boundary")
		check(is_equal_approx(r.contact_weight(a,b,"chat",10380.0),0.6), "ex contact penalty remains after cooldown expiry")
		clock.total_minutes = 10381.0
		check(r.ask_block(a,b,10381.0)=="", "cooldown stays expired after catch-up")
	world.free()
	clock.running = false
	finish("test_romance_cold_process")