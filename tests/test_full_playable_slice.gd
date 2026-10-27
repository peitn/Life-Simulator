extends "res://tests/test_base.gd"
## Actual offline first-playthrough: HUD creator -> authoritative spawn ->
## player command -> 20 minute continuation -> disk save/reload.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

var world: Node
var clock: Node

func _ready() -> void:
    watchdog_seconds = 85.0
    clock = get_node("/root/GameClock")
    clock.running = false
    clock.total_minutes = 480.0
    clock._last_day = clock.get_day()
    clock._last_hour = clock.get_hour()
    Assets.enabled = false
    world = Main.new()
    world.net_config = {"mode":"offline","hud":true,"camera":false,"visuals":false,
        "audio":false,"autoload":false,"autosave":true,
        "save_directory":"user://test-first-playthrough-"+str(OS.get_process_id())}
    add_child(world)
    _run.call_deferred()

func _run() -> void:
    await get_tree().process_frame
    section("Offline creation and cancellation")
    var hud = world.hud
    check(hud != null and hud._create_button != null, "visible new-character HUD entry")
    check(world.sims.size() == 3, "initial household has three characters")
    var right_scroll: ScrollContainer = hud.get_node_or_null("NeedsAndCommandsPanel/ControlsScroll")
    check(right_scroll != null, "game HUD has scrollable needs and commands")
    if right_scroll != null:
        var original_size: Vector2i = get_window().size
        get_window().size = Vector2i(390, 720)
        await get_tree().process_frame
        await get_tree().process_frame
        check(right_scroll.size.y > 100.0 and right_scroll.size.y <= 720.0,
            "narrow window keeps controls panel within viewport")
        right_scroll.scroll_vertical = 9999
        await get_tree().process_frame
        check(right_scroll.scroll_vertical > 0, "narrow window can scroll down to player commands")
        get_window().size = original_size
        await get_tree().process_frame
    hud._create_button.pressed.emit()
    var creator = hud._character_creator
    check(creator != null and is_instance_valid(creator) and creator.is_inside_tree(), "HUD opens creator")
    if creator == null or not is_instance_valid(creator):
        finish("test_full_playable_slice")
        return
    var draft: Dictionary = creator._session.draft()
    check(creator._visual_preview.public_snapshot().has("clothing"), "isolated creator preview available")
    check(not creator._visual_preview.public_snapshot().has("mind") and not creator._visual_preview.public_snapshot().has("uid"),
        "private mind and UID never enter preview")
    check(creator._visual_preview.viewport.world_3d != world.get_viewport().world_3d,
        "creator preview has separate 3D world")
    creator._on_name_changed("Zrušená", "first_name")
    check(creator._session.is_dirty() and world.sims.size() == 3, "draft does not spawn anything")
    creator._on_cancel()
    await get_tree().process_frame
    check(world.sims.size() == 3 and not is_instance_valid(creator), "cancel keeps household untouched")

    section("Reject invalid and remote creation")
    hud._create_button.pressed.emit()
    creator = hud._character_creator
    check(creator != null and is_instance_valid(creator), "creator can reopen after cancel")
    var initial: Dictionary = creator._session.draft()
    var underage: Dictionary = initial.duplicate(true)
    underage["body"]["age"] = 17
    check(not world.create_offline_character(underage).get("ok", false), "under-18 character blocked by authority")
    var invalid_name: Dictionary = initial.duplicate(true)
    invalid_name["identity"]["first_name"] = "a\\u202e"
    check(not world.create_offline_character(invalid_name).get("ok", false), "bidi control in name rejected")
    var before_count: int = world.sims.size()
    world.net.mode = world.net.Mode.HOST
    check(not world.create_offline_character(initial).get("ok", false), "network mode cannot create offline character")
    hud._on_create_character()
    check(hud._character_creator == creator, "network mode cannot open a second creator")
    world.net.mode = world.net.Mode.OFFLINE
    check(world.sims.size() == before_count, "rejected attempts cannot change the roster")

    section("Creator Apply commits a canonical playable character")
    creator._first.text = "Nora"
    creator._first.text_changed.emit("Nora")
    creator._last.text = "Nová"
    creator._last.text_changed.emit("Nová")
    for i in creator._grammar.item_count:
        if creator._grammar.get_item_metadata(i) == "f":
            creator._grammar.select(i)
            creator._grammar.item_selected.emit(i)
    for i in creator._gender.item_count:
        if creator._gender.get_item_metadata(i) == "nebinarni":
            creator._gender.select(i)
            creator._gender.item_selected.emit(i)
    creator._age.value = 29
    for i in creator._style.item_count:
        if creator._style.get_item_metadata(i) == "kawaii_kocka":
            creator._style.select(i)
            creator._style.item_selected.emit(i)
    var belief_slider: HSlider = creator._sliders.find_child("BeliefDefectiveness", true, false)
    check(belief_slider != null, "creator has a private inner-belief slider")
    if belief_slider != null:
        belief_slider.value = 0.77
        check(absf(float(creator._session.draft()["mind"]["self_defectiveness"]) - 0.77) < 0.001, "creator slider changes draft")
    var data: Dictionary = creator._session.draft()
    var before_uid: String = String(data["uid"])
    var public_draft: Dictionary = creator._visual_preview.public_snapshot()
    check(data["identity"]["grammar"] == "f" and data["identity"]["gender_identity"] == "nebinarni",
        "grammatical gender is independent from gender identity")
    check(data["identity"]["first_name"] == "Nora" and int(data["body"]["age"]) == 29,
        "editable identity and adult age saved only in draft")
    check(data["clothing"]["bezne"]["top"] == "kawaii_kocici_mikina",
        "creator applies wardrobe preset to draft and preview")
    check(creator._session.can_undo(), "creation edits support Undo")
    creator._on_undo()
    creator._on_redo()
    check(creator._session.draft() == data, "redo restores chosen creation data")
    creator._on_create()
    await get_tree().process_frame
    check(world.sims.size() == before_count + 1, "confirmed creator adds exactly one resident")
    var selected = world.get_selected_sim()
    check(selected != null and selected.sim_name == "Nora Nová", "new character is selected for playing")
    if selected == null:
        finish("test_full_playable_slice")
        return
    var node_name: String = String(selected.name)
    var stored: Dictionary = world.read_character_edit(node_name)
    check(stored.get("ok", false), "authoritative private CharacterData exists")
    check(stored["data"]["uid"] != before_uid and stored["data"]["uid"].length() == 32,
        "server generates its own 128-bit UID")
    check(stored["data"]["identity"]["gender_identity"] == "nebinarni"
        and stored["data"]["identity"]["grammar"] == "f", "identity axes survive authoritative spawn")
    check(absf(float(stored["data"]["mind"]["self_defectiveness"]) - 0.77) < 0.001 and absf(selected.self_defectiveness_belief - 0.77) < 0.001, "creator commits private inner belief into live agent")
    check(selected.look == public_draft, "spawned appearance exactly matches creator's preview")
    check(selected.look.get("mind", {}).is_empty() and not selected.look.has("uid"),
        "spawn distributes no private mind/UID")
    check(not is_instance_valid(creator), "committed creator UI is freed")
    var duplicate: Dictionary = stored["data"].duplicate(true)
    check(not world.create_offline_character(duplicate).get("ok", false),
        "second character with same display name cannot collide in relationship keys")
    check(world.sims.size() == before_count + 1, "rejected duplicate leaves roster untouched")

    section("Actual play command and save/load continuation")
    var tv := -1
    for i in world.smart_objects.size():
        if world.smart_objects[i].object_tag == "tv":
            tv = i
    check(tv >= 0, "real TV interaction point exists")
    if tv >= 0:
        var error: String = world.net.handle_command(1, node_name, "watch_tv", tv)
        check(error == "", "new character can receive real player TV command", error)
    clock.advance(20.0)
    var baseline: Dictionary = SaveGame.capture(world)
    check(baseline.get("ok", false), "save-game capture accepts custom character household")
    var written: Dictionary = world.save_game("manual")
    check(written.get("ok", false), "manual disk save succeeds after creation", str(written))
    clock.advance(20.0)
    var future: Dictionary = SaveGame.capture(world)
    var restore: Dictionary = world.load_game("manual")
    check(restore.get("ok", false), "saved custom household loads from disk", str(restore))
    check(world.sims.size() == before_count + 1, "load restores same resident count")
    check(String(world.get_selected_sim().name) == node_name, "load preserves selected player character")
    var restored: Dictionary = SaveGame.capture(world)
    check(restored.get("ok", false) and restored.get("data") == baseline.get("data"),
        "immediate post-load snapshot matches before-save simulation exactly")
    clock.advance(20.0)
    var resumed: Dictionary = SaveGame.capture(world)
    check(resumed.get("ok", false) and resumed.get("data") == future.get("data"),
        "uninterrupted and save/reload continuations identical")
    section("Actual application restart and automatic resume")
    var auto: Dictionary = world.save_game("autosave")
    check(auto.get("ok", false), "autosave persists user-created character")
    var expected: Dictionary = SaveGame.capture(world)
    var persisted_directory: String = world._save_manager.directory
    world.queue_free()
    await get_tree().process_frame
    world = Main.new()
    world.net_config = {"mode":"offline","hud":true,"camera":false,"visuals":false,
        "audio":false,"autoload":true,"autosave":true,"save_directory":persisted_directory}
    add_child(world)
    await get_tree().process_frame
    var restart: Dictionary = SaveGame.capture(world)
    check(world.sims.size() == before_count + 1, "new game instance auto-restores custom household")
    check(restart.get("ok", false) and restart.get("data") == expected.get("data"),
        "cold start autoload restores exactly the persisted simulation")
    check(String(world.get_selected_sim().name) == node_name,
        "real-world restart preserves playable selected character")
    world.queue_free()
    await get_tree().process_frame
    Assets.enabled = true
    clock.running = false
    finish("test_full_playable_slice")