extends "res://tests/test_base.gd"
## Two independent Godot OS processes share only a test-specific on-disk autosave.
## Run first with --phase=prepare, then with --phase=verify. No in-process Main restart.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const SAVE_DIR := "user://test-h3-cold-main-fallback-1793236448-36878"
const PEOPLE := [
    {"first": "Nora", "last": "Cold", "size": -0.6, "scale": 0.88, "anxiety": 0.65},
    {"first": "Mira", "last": "Cold", "size": 0.8, "scale": 1.16, "anxiety": 0.18}
]
var world: Node
var phase := ""

func _rig_ok(sim: Node, scale: float) -> bool:
    if sim == null or not is_instance_valid(sim) or sim.visual == null:
        return false
    var visual = sim.visual
    var skeleton: Skeleton3D = visual._skeleton()
    if skeleton == null or visual._hand_detail_nodes.size() < 2:
        return false
    for side in ["hand_l", "hand_r"]:
        var index: int = skeleton.find_bone(side)
        if index < 0 or not skeleton.get_bone_pose_scale(index).is_equal_approx(Vector3.ONE * scale):
            return false
    return true

func _ready() -> void:
    watchdog_seconds = 55.0
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--phase="):
            phase = arg.trim_prefix("--phase=")
    var clock = get_node("/root/GameClock")
    clock.running = false
    clock.total_minutes = 480.0
    clock._last_day = clock.get_day()
    clock._last_hour = clock.get_hour()
    Assets.enabled = true
    world = Main.new()
    world.net_config = {"mode": "offline", "hud": true, "camera": false,
        "visuals": false, "audio": false, "autoload": phase == "verify",
        "autosave": true, "save_directory": SAVE_DIR}
    add_child(world)
    _run.call_deferred()

func _run() -> void:
    await get_tree().process_frame
    section("H3 true cold-process autosave: " + phase)
    if not check(phase in ["prepare", "verify"], "explicit test phase required"):
        finish("test_h3_cold_process_reload")
        return
    if phase == "prepare":
        check(world.sims.size() == 3, "producer starts with default three residents")
        for person in PEOPLE:
            var hud = world.hud
            hud._create_button.pressed.emit()
            var creator = hud._character_creator
            if not check(creator != null and is_instance_valid(creator), "HUD opens a real creator"):
                finish("test_h3_cold_process_reload")
                return
            var draft: Dictionary = creator._session.draft()
            draft["identity"]["first_name"] = person["first"]
            draft["identity"]["last_name"] = person["last"]
            draft["body"]["hand_size"] = person["size"]
            draft["mind"]["predispositions"] = {"anxiety": person["anxiety"]}
            if not check(creator._session.replace_draft(draft, "H3 cross-process hand size"),
                "creator validates independent draft"):
                finish("test_h3_cold_process_reload")
                return
            creator._refresh()
            check(is_equal_approx(float(creator._visual_preview.visual.look_params["hand_scale"]), person["scale"]),
                "creator preview resolves expected authored hand scale")
            creator._on_create()
            await get_tree().process_frame
            var sim = world.get_selected_sim()
            check(sim != null and sim.sim_name == person["first"] + " " + person["last"],
                "HUD creator spawns requested resident")
            check(_rig_ok(sim, person["scale"]), "producer spawned real hand Skeleton3D and mesh")
        check(world.sims.size() == 5, "producer has both custom residents")
        var saved: Dictionary = world.save_game("autosave")
        if not check(saved.get("ok", false), "real autosave persisted", str(saved)):
            finish("test_h3_cold_process_reload")
            return
        var path: String = SAVE_DIR + "/autosave.lss"
        var digest: String = FileAccess.get_sha256(path)
        check(digest.length() == 64, "binary autosave has SHA-256 digest")
        var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
        check(dir_error == OK, "isolated test directory exists")
        var marker := FileAccess.open(SAVE_DIR + "/producer.json", FileAccess.WRITE)
        if not check(marker != null, "producer writes cross-process evidence"):
            finish("test_h3_cold_process_reload")
            return
        marker.store_string(JSON.stringify({"pid": OS.get_process_id(), "sha256": digest}))
        marker.close()
    else:
        var marker_path: String = SAVE_DIR + "/producer.json"
        if not check(FileAccess.file_exists(marker_path), "producer evidence exists from previous process"):
            finish("test_h3_cold_process_reload")
            return
        var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
        if not check(typeof(marker) == TYPE_DICTIONARY, "producer evidence parses"):
            finish("test_h3_cold_process_reload")
            return
        check(int(marker.get("pid", -1)) != OS.get_process_id(),
            "consumer has different OS PID from producer")
        check(String(marker.get("sha256", "")) == FileAccess.get_sha256(SAVE_DIR + "/autosave.lss"),
            "consumer reads exact producer autosave bytes")
        check(world.sims.size() == 5, "cold-process Main autoloads five residents")
        check(world._save_manager.directory == SAVE_DIR,
            "consumer Main uses the exact producer save directory")
        var on_disk: Dictionary = world._save_manager.load_slot("autosave")
        var live_snapshot: Dictionary = SaveGame.capture(world)
        check(on_disk.get("ok", false) and live_snapshot.get("ok", false)
            and on_disk.get("data") == live_snapshot.get("data"),
            "cold-process live household equals the complete saved world snapshot")
        for person in PEOPLE:
            var found: Node = null
            for sim in world.sims:
                if sim.sim_name == person["first"] + " " + person["last"]:
                    found = sim
            if not check(found != null, "cold-process roster includes " + person["first"]):
                continue
            check(_rig_ok(found, person["scale"]), "cold-process authored hand Skeleton3D rebuilt")
            check(is_equal_approx(float(found.look["body"]["hand_size"]), person["size"]),
                "cold-process public hand size matches producer")
            check(not found.look.has("mind") and not found.look.has("uid"),
                "public snapshot still excludes private identity and mind")
            var private_data: Dictionary = world.read_character_edit(String(found.name))
            check(private_data.get("ok", false)
                and is_equal_approx(float(private_data["data"]["mind"]["predispositions"]["anxiety"]), person["anxiety"]),
                "cold-process authoritative private psyche remains isolated")
        check(SaveGame.capture(world).get("ok", false), "cold-process household is saveable")
    world.queue_free()
    await get_tree().process_frame
    finish("test_h3_cold_process_reload")