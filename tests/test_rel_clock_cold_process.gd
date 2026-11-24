extends "res://tests/test_base.gd"
const Main = preload("res://main.gd")
const SAVE_DIR = "user://test-rel-clock-cold-process-v1"
var world: Node
var clock: Node
func _ready() -> void:
	watchdog_seconds = 75.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var slot := _run_slot()
	world = Node3D.new()
	world.set_script(Main)
	world.name = "RelColdWorld"
	world.net_config = {"mode":"offline","audio":false,"camera":false,"visuals":false,"hud":false,"autoload":false,"autosave":false,"save_directory":SAVE_DIR + "/" + slot,"clock":clock}
	add_child(world)
	_run.call_deferred()
func _run() -> void:
	var reader := "--reader" in OS.get_cmdline_user_args()
	section("Cold process relationship disk save: " + ("reader" if reader else "writer"))
	var slot := _run_slot()
	check(slot.length() >= 12 and slot.is_valid_identifier(), "unique slot argument required")
	if slot.length() < 12 or not slot.is_valid_identifier():
		world.free()
		finish("test_rel_clock_cold_process")
		return
	var path := SAVE_DIR + "/" + slot + "/manual.lss"
	if "--truncate" in OS.get_cmdline_user_args():
		if reader:
			_truncate_reader(slot)
		else:
			_truncate_writer(slot)
		world.free()
		clock.running = false
		finish("test_rel_clock_cold_process")
		return
	if "--corrupt" in OS.get_cmdline_user_args():
		if not reader:
			check(not FileAccess.file_exists(path), "corrupt writer rejects stale slot")
			if not FileAccess.file_exists(path):
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR + "/" + slot))
				var f=FileAccess.open(path,FileAccess.WRITE)
				if f:
					f.store_buffer(PackedByteArray([76,83,83,0,1,2,3]))
					f.close()
			check(FileAccess.file_exists(path), "corrupt payload physically written")
		else:
			check(FileAccess.file_exists(path), "corrupt payload persisted into second process")
			var before=clock.total_minutes
			var result: Dictionary=world.load_game("manual")
			check(not result.get("ok",false), "corrupt save rejected",str(result))
			check(is_equal_approx(clock.total_minutes,before), "failed load preserves GameClock")
		world.free()
		clock.running=false
		finish("test_rel_clock_cold_process")
		return
	if not reader:
		check(not FileAccess.file_exists(path), "writer rejects stale slot")
		if FileAccess.file_exists(path):
			world.free()
			finish("test_rel_clock_cold_process")
			return
		var actor = world.sims[0]
		var other: String = world.sims[1].sim_name
		clock.total_minutes = 200.0
		actor.ledger.on_hurt_by(other, 40.0, 180.0)
		actor.ledger.receive_apology(other, "partial", 200.0)
		var result: Dictionary = world.save_game("manual")
		check(result.get("ok", false), "writer saves successfully", str(result))
		check(FileAccess.file_exists(path), "physical save file exists")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() > 128, "nonempty binary payload", str(bytes.size()))
		check(FileAccess.get_open_error() == OK, "disk payload readable")
	else:
		check(FileAccess.file_exists(path), "writer save persisted across processes")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() > 128, "cold reader sees physical payload")
		check(FileAccess.get_open_error() == OK, "cold reader disk read succeeds")
		var result: Dictionary = world.load_game("manual")
		check(result.get("ok", false), "cold process loads save", str(result))
		check(is_equal_approx(clock.total_minutes, 200.0), "cold process restores clock")
		var actor = world.sims[0]
		var other: String = world.sims[1].sim_name
		check(is_equal_approx(actor.ledger.sincerity(other, 210.0), 0.7), "cold process restores apology timestamp")
		clock.total_minutes = 100.0
		check(is_equal_approx(actor.ledger.sincerity(other, clock.total_minutes), 1.0), "rewind ignores future apology")
		clock.total_minutes = 210.0
		check(actor.ledger.evaluate_apology(other, clock.total_minutes, 0.0, 0.0, 0.0, 0.5).outcome == "spam", "cooldown resumes after catch-up")
	world.free()
	clock.running = false
	finish("test_rel_clock_cold_process")
func _run_slot() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			return arg.trim_prefix("--slot=")
	return ""


# --- Truncated VALID save (fresh-process recovery contract) -------------------------------
# Writer: two real saves of "manual" (the first becomes manual.lss.bak), one "autosave" with no
# backup; then both primaries are cut to half of their real length and a fingerprint sidecar
# (size + SHA-256 of the truncated bytes) is written. Reader (separate OS process): proves it
# reads exactly those bytes, then asserts the specific failure reason, an untouched world on
# failure, and recovery from the backup with the OLDER clock/ledger state.
func _sha_hex(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


func _household_print() -> String:
	var parts: PackedStringArray = []
	for s in world.sims:
		parts.append(String(s.sim_name) + "=" + JSON.stringify(s.ledger.to_dict(), "", true))
	return _sha_hex("|".join(parts).to_utf8_buffer())


func _truncate_file(path: String) -> Dictionary:
	var full := FileAccess.get_file_as_bytes(path)
	var cut := full.slice(0, full.size() / 2)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_buffer(cut)
	f.close()
	return {"full": full.size(), "size": cut.size(), "sha": _sha_hex(cut)}


func _truncate_writer(slot: String) -> void:
	var dir := SAVE_DIR + "/" + slot
	check(not FileAccess.file_exists(dir + "/manual.lss") and not FileAccess.file_exists(dir + "/autosave.lss"),
		"truncate writer rejects stale slot")
	if FileAccess.file_exists(dir + "/manual.lss") or FileAccess.file_exists(dir + "/autosave.lss"):
		return
	var actor = world.sims[0]
	var other: String = world.sims[1].sim_name
	clock.total_minutes = 150.0
	actor.ledger.on_hurt_by(other, 40.0, 140.0)
	actor.ledger.receive_apology(other, "partial", 150.0)
	check(world.save_game("manual").get("ok", false), "first valid manual save (becomes backup)")
	var bak_print := _household_print()
	clock.total_minutes = 200.0
	actor.ledger.receive_apology(other, "partial", 200.0)
	check(world.save_game("manual").get("ok", false), "second valid manual save (primary)")
	check(world.save_game("autosave").get("ok", false), "valid autosave without backup")
	check(FileAccess.file_exists(dir + "/manual.lss.bak"), "valid previous primary archived as .bak")
	check(not FileAccess.file_exists(dir + "/autosave.lss.bak"), "autosave has no backup")
	var m := _truncate_file(dir + "/manual.lss")
	var a := _truncate_file(dir + "/autosave.lss")
	check(not m.is_empty() and m["size"] > 32 and m["size"] < m["full"], "manual primary truncated to half", str(m))
	check(not a.is_empty() and a["size"] > 32 and a["size"] < a["full"], "autosave truncated to half", str(a))
	var side := FileAccess.open(dir + "/fingerprint.json", FileAccess.WRITE)
	if side:
		side.store_string(JSON.stringify({"manual": m, "autosave": a, "bak_print": bak_print}))
		side.close()
	check(FileAccess.file_exists(dir + "/fingerprint.json"), "fingerprint sidecar written")


func _truncate_reader(slot: String) -> void:
	var dir := SAVE_DIR + "/" + slot
	var side = JSON.parse_string(FileAccess.get_file_as_string(dir + "/fingerprint.json"))
	check(typeof(side) == TYPE_DICTIONARY, "fingerprint sidecar readable in fresh process")
	if typeof(side) != TYPE_DICTIONARY:
		return
	for name in ["manual", "autosave"]:
		var bytes := FileAccess.get_file_as_bytes(dir + "/" + name + ".lss")
		check(bytes.size() == int(side[name]["size"]) and _sha_hex(bytes) == String(side[name]["sha"]),
			"reader sees exactly the truncated %s bytes" % name)
	# Failure path: no backup -> specific reason, world untouched.
	clock.total_minutes = 777.0
	var before := _household_print()
	var r: Dictionary = world.load_game("autosave")
	check(not r.get("ok", false), "truncated autosave rejected", str(r))
	check(String(r.get("reason", "")) == "format", "truncation reported as 'format'", str(r))
	check(String(r.get("backup_reason", "")) == "missing", "no backup to fall back to", str(r))
	check(is_equal_approx(clock.total_minutes, 777.0), "failed load keeps GameClock")
	check(_household_print() == before, "failed load keeps household relationships bit-identical")
	# Payload bit flip (envelope still parses) -> checksum, never silently accepted.
	var good := FileAccess.get_file_as_bytes(dir + "/manual.lss.bak")
	var flipped := good.duplicate()
	flipped[flipped.size() / 2] = flipped[flipped.size() / 2] ^ 0x5A
	var fw := FileAccess.open(dir + "/autosave.lss", FileAccess.WRITE)
	if fw:
		fw.store_buffer(flipped)
		fw.close()
	var rf: Dictionary = world.load_game("autosave")
	check(String(rf.get("reason", "")) == "checksum", "payload bit flip reported as 'checksum'", str(rf))
	check(is_equal_approx(clock.total_minutes, 777.0) and _household_print() == before,
		"checksum failure keeps clock and household")
	# Recovery path: truncated primary, valid backup -> older state, source=backup.
	var rm: Dictionary = world.load_game("manual")
	check(rm.get("ok", false), "truncated manual recovers", str(rm))
	check(String(rm.get("source", "")) == "backup", "recovery comes from .bak", str(rm))
	check(is_equal_approx(clock.total_minutes, 150.0), "backup restores OLDER clock (150)", str(clock.total_minutes))
	check(_household_print() == String(side.get("bak_print", "")), "relationships equal the state at the FIRST save exactly")
	check(_household_print() != before, "household actually replaced by backup state")
	check(FileAccess.get_file_as_bytes(dir + "/manual.lss").size() == int(side["manual"]["size"]),
		"load never rewrites the damaged primary")
