extends "res://tests/test_base.gd"
## Actual offline household save/load, autosave, corrupted slot, backup and boot integration.

const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

var clock: Node
var world: Node
var test_path := ""

func _new_world(load_on_start: bool = false, automatic: bool = false, hud: bool = false) -> void:
	world = Node3D.new()
	world.set_script(Main)
	world.name = "SaveTestWorld"
	world.net_config = {"mode": "offline", "audio": false, "hud": hud, "camera": false,
		"visuals": false, "save_directory": test_path, "autoload": load_on_start,
		"autosave": automatic, "clock": clock}
	add_child(world)


func _remove_world() -> void:
	if world != null and is_instance_valid(world):
		world.free()
		world = null


func _ready() -> void:
	watchdog_seconds = 90.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	test_path = "user://test-lifesim-save-" + str(OS.get_process_id())
	_run.call_deferred()


func _run() -> void:
	section("Offline authority: real complete household snapshot")
	_new_world(false, true, true)
	check(world.hud._save_button.name == "SaveGame" and
		world.hud._load_auto_button.name == "LoadAutosave" and
		world.hud._load_manual_button.name == "LoadManual",
		"live offline HUD contains manual Save, Load autosave and Load manual buttons")
	var first = world.sims[0]
	var partner_name: String = world.sims[1].sim_name
	first.mental.on_positive_stimulus(50.0)
	first.mental.thoughts.append({"t": 122.0, "text": "Vzpomínka", "kind": "future"})
	first.mental.panic_count = 3
	first.mental.panic_cooldown = 17.0
	first.mental._thought_cd = 8.0
	first.mental.dep.pessimism = 0.23
	first.needs.values["energy"] = 41.25
	first.relationships[partner_name] = 57.0
	first.ledger.grudges[partner_name] = 19.0
	first.ledger.set_attachment(partner_name, 0.77, 0.35)
	first.vigilance.alertness = 0.78
	first.rejection.distress = 0.42
	first.sensory.noise_habit = 0.36
	first.memories.append({"t": 567.0, "text": "Důležitá vzpomínka"})
	first.action_counts["cook"] = 7
	first.last_talk[partner_name] = 344.0
	first.speech = "Už brzy."
	first.speech_until = 10000.0
	first.position = Vector3(-2.5, 0, 0.9)
	first.rotation.y = 1.15
	world.selected = 1
	clock.total_minutes = 1449.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	clock.set_speed(2)
	world.dynamics._acc = 3.25
	world.dynamics._last_friction["A>B>dishes"] = 1340.0
	# Explicit persisted object reservation with matching in-flight WALKING plan.
	var obj = world.smart_objects[0]
	check(obj.reserve(first), "smart object can be reserved by real agent")
	first.current_action = {"id": "relax", "label": "Odpočívá", "duration": 60.0,
		"tags": [], "effects": {}, "suppress": {}}
	first.target = obj
	first.state = first.State.WALKING
	first.target_point = obj.get_use_position(first)
	first.walk_elapsed = 9.0
	first.player_queue = [{"action": {"id": "wait", "duration": 2.0, "tags": []},
		"target": world.sims[1]}]
	var original: Dictionary = SaveGame.capture(world)
	check(original.get("ok", false), "full authoritative household captured")
	check(original.get("data", {}).get("sims", []).size() == 3, "all three characters captured")
	check(original.get("data", {}).get("objects", [])[0]["users"] == [String(first.name)],
		"object reservation stored by stable character node name")
	var expected_state: int = first.rng.state
	var expected_time: float = clock.total_minutes
	var expected_arousal: float = first.mental.positive_arousal
	var save1: Dictionary = world.save_game("manual")
	check(save1.get("ok", false) and FileAccess.file_exists(test_path + "/manual.lss"),
		"manual save persisted as a real file", str(save1))
	world.hud._on_edit_character()
	var unsaved_draft = world.hud._character_editor
	check(unsaved_draft != null and is_instance_valid(unsaved_draft),
		"offline editor draft can be open before user loads game")
	first.needs.values["energy"] = 8.0
	first.relationships[partner_name] = -99.0
	clock.total_minutes = 5123.0
	var restore: Dictionary = world.load_game("manual")
	check(restore.get("ok", false) and clock.total_minutes == expected_time,
		"manual load restores clock and simulation day")
	check(world.hud._character_editor == null and unsaved_draft.is_queued_for_deletion(),
		"loading a household safely discards stale uncommitted character editor draft")
	first = world.sims[0]
	check(absf(first.needs.values["energy"] - 41.25) < 0.0001 and
		first.relationships[partner_name] == 57.0 and
		first.ledger.grudges[partner_name] == 19.0,
		"needs, relationships and grudges restored")
	check(absf(first.mental.positive_arousal - expected_arousal) < 0.0001 and
		first.mental.panic_count == 3 and first.mental.thoughts.size() >= 1 and
		first.mental.panic_cooldown == 17.0,
		"arousal, panic timeline, intrusive thoughts and cooldown survive loading")
	check(first.vigilance.alertness == 0.78 and first.rejection.distress == 0.42 and
		first.sensory.noise_habit == 0.36,
		"vigilance, rejection and sensory habituation restored")
	check(first.rng.state == expected_state and world.selected == 1 and
		clock.speed_index == 2,
		"random generator, selected character and speed restored")
	check(first.state == first.State.WALKING and first.target == world.smart_objects[0] and
		world.smart_objects[0].users.has(first) and
		first.player_queue[0]["target"] == world.sims[1],
		"in-flight walk, reserved furniture and queued command targets resolved")
	check(world.dynamics._acc == 3.25 and
		world.dynamics._last_friction["A>B>dishes"] == 1340.0,
		"household dynamics timers and relationship friction restored")
	check(world._character_records.has(String(first.name)) and
		world._character_records[String(first.name)].to_dict() ==
			original["data"]["sims"][0]["character"],
		"full private CharacterData retained server-side after restoring")

	section("Autosave, rollback safety and fallback backup")
	first.mental.stress = 31.0
	world._save_elapsed = world.AUTOSAVE_REAL_SECONDS + 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(FileAccess.file_exists(test_path + "/autosave.lss"),
		"five-minute real-time autosave fires from real main._process")
	var stored_auto: Dictionary = world._save_manager.load_slot("autosave")
	check(stored_auto.get("ok", false) and
		absf(float(stored_auto["data"]["sims"][0]["state"]["mental"]["stress"]) - 31.0) < 0.001,
		"automatic save contains the current private mental state")
	first = world.sims[0]
	first.mental.stress = 43.0
	check(world.save_game("autosave").get("ok", false),
		"second autosave atomically replaces active primary")
	check(FileAccess.file_exists(test_path + "/autosave.lss.bak"),
		"valid previous save retained as fallback backup")
	var primary = FileAccess.open(test_path + "/autosave.lss", FileAccess.WRITE)
	primary.store_string("deliberately corrupted save")
	primary.close()
	var recovered: Dictionary = world._save_manager.load_slot("autosave")
	check(recovered.get("ok", false) and recovered.get("source") == "backup" and
		absf(float(recovered["data"]["sims"][0]["state"]["mental"]["stress"]) - 31.0) < 0.001,
		"corrupt primary cannot erase the last valid autosave backup")
	check(world.load_game("autosave").get("ok", false) and
		world.sims[0].mental.stress == 31.0,
		"backup fallback actually restores playable world")
	var before_invalid: float = world.sims[0].needs.values["energy"]
	var invalid: Dictionary = SaveGame.capture(world)["data"]
	invalid["clock"]["total_minutes"] = -100.0
	check(not SaveGame.apply(world, invalid).get("ok", false) and
		world.sims[0].needs.values["energy"] == before_invalid,
		"invalid saved clock rejected before any world mutation")
	var malformed: Dictionary = SaveGame.capture(world)["data"]
	malformed["sims"][0]["state"]["needs"]["values"]["energy"] = -80.0
	check(not SaveGame.apply(world, malformed).get("ok", false) and
		world.sims[0].needs.values["energy"] == before_invalid,
		"invalid needs rejected before destructive roster rebuild")
	var badref: Dictionary = SaveGame.capture(world)["data"]
	badref["sims"][0]["state"]["target"] = {"sim": "Nonexistent123"}
	check(not SaveGame.apply(world, badref).get("ok", false),
		"unresolved character reference rejected before destructive roster rebuild")
	var oldversion: Dictionary = SaveGame.capture(world)["data"]
	oldversion["version"] = 99
	check(not SaveGame.apply(world, oldversion).get("ok", false),
		"future incompatible save schema is rejected without data loss")

	section("Malformed movement destination rejected before household replacement")
	var intact: Dictionary = SaveGame.capture(world)["data"]
	var original_instance: int = world.sims[0].get_instance_id()
	for value in ["not a vector", Vector3(NAN, 0, 0), Vector3(0, INF, 0), Vector3(0, 0, -INF), Vector3(10001, 0, 0)]:
		var bad_destination: Dictionary = intact.duplicate(true)
		bad_destination["sims"][0]["state"]["target_point"] = value
		check(not SaveGame.validate_data(bad_destination).get("ok", false),
			"malformed destination rejected by preflight: " + str(value))
		check(not SaveGame.apply(world, bad_destination).get("ok", false) and
			world.sims[0].get_instance_id() == original_instance and
			SaveGame.capture(world)["data"] == intact,
			"invalid destination leaves entire household and instances intact")

	var legacy: Dictionary = intact.duplicate(true)
	legacy["sims"][0]["state"].erase("target_point")
	check(SaveGame.validate_data(legacy).get("ok", false), "v1 missing destination keeps position fallback")

	section("Cold boot restores autosave without explicit player interaction")
	# Fresh valid autosave primary, preserving earlier validated backup.
	check(world.save_game("autosave").get("ok", false), "recovered game can be saved again")
	check(FileAccess.file_exists(test_path + "/autosave.lss.invalid"),
		"corrupt primary is quarantined rather than silently deleted")
	check(world._save_manager.load_slot("autosave").get("source", "") == "primary" and
		world._save_manager._read_file(test_path + "/autosave.lss.bak").get("ok", false),
		"valid primary is restored without discarding the previous valid backup")
	var boot_time: float = clock.total_minutes
	_remove_world()
	clock.total_minutes = 480.0
	clock._last_day = 0
	clock._last_hour = 8
	_new_world(true, false, false)
	check(world.sims.size() == 3 and clock.total_minutes == boot_time,
		"next game launch automatically restores the household")
	check(world.sims[0].mental.stress == 31.0 and
		world.sims[0].mental.positive_arousal > 0.0,
		"next launch restores psychological state including pleasant arousal")
	check(world.sims[0].target == world.smart_objects[0] and
		world.smart_objects[0].users.has(world.sims[0]),
		"new game process restores furniture reservation and in-progress action")
	check(not world.net.is_networked() and world._character_records.size() == 3,
		"only offline authority reconstructs private household")

	section("Authority and slot safety")
	world.net.mode = 1 # listen server simulation: unsupported save in v1
	check(not world.save_game("manual").get("ok", false) and
		not world.load_game("manual").get("ok", false),
		"host/multiplayer save operations cannot expose server-owned private minds")
	world.net.mode = 0
	check(not world._save_manager.save_slot("../escape", original["data"]).get("ok", false),
		"invalid slot path traversal is rejected")
	_remove_world()
	clock.running = false
	finish("test_save_game")
