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
    # H3: private psyche and continuous traits must survive the creator-to-household path.
    # Body proportions and gender/grammar remain independent of each other.
    var isolated: Dictionary = creator._session.draft()
    isolated["body"]["bust"] = 0.13
    isolated["personality"]["trait_levels"] = {"uzkostlivy": 0.73}
    isolated["mind"]["predispositions"] = {"anxiety": 0.65}
    isolated["mind"]["morning_worse"] = true
    check(creator._session.replace_draft(isolated, "H3 independent axes"),
        "creator accepts independent body, continuous trait and private psyche draft")
    creator._refresh()
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
    check(is_equal_approx(float(stored["data"]["body"]["bust"]), 0.13),
        "body proportion survives creation independently of grammar and identity")
    check(is_equal_approx(float(stored["data"]["personality"]["trait_levels"]["uzkostlivy"]), 0.73),
        "authoritative CharacterData retains continuous trait weight")
    check(is_equal_approx(float(stored["data"]["mind"]["predispositions"]["anxiety"]), 0.65)
        and bool(stored["data"]["mind"]["morning_worse"]),
        "private psyche predisposition and pattern survive authoritative creation")
    check(selected.grammar == "f" and selected.trait_profile is Dictionary
        and is_equal_approx(float(selected.trait_profile.get("uzkostlivy", -1.0)), 0.73),
        "live SimAgent uses independent grammar and continuous personality")
    var public_personality: Dictionary = selected.look.get("personality", {})
    check(not selected.look.has("mind") and not selected.look.has("uid")
        and public_personality.has("traits") and not public_personality.has("trait_levels")
        and not public_personality.has("hexaco") and not public_personality.has("aspirations"),
        "public legacy trait labels retained; private continuous traits, psyche and UID excluded")
    check(selected.look.get("mind", {}).is_empty() and not selected.look.has("uid"),
        "spawn distributes no private mind/UID")
    check(not is_instance_valid(creator), "committed creator UI is freed")
    var duplicate: Dictionary = stored["data"].duplicate(true)
    check(not world.create_offline_character(duplicate).get("ok", false),
        "second character with same display name cannot collide in relationship keys")
    check(world.sims.size() == before_count + 1, "rejected duplicate leaves roster untouched")

    section("Second creator and private resident isolation")
    hud._create_button.pressed.emit()
    var second_creator = hud._character_creator
    check(second_creator != null and is_instance_valid(second_creator) and second_creator.is_inside_tree(),
        "creator reopens for a second independent resident")
    if second_creator == null or not is_instance_valid(second_creator):
        finish("test_full_playable_slice")
        return
    var second_draft: Dictionary = second_creator._session.draft()
    second_draft["identity"]["first_name"] = "Mira"
    second_draft["identity"]["last_name"] = "Druhá"
    second_draft["body"]["bust"] = 0.61
    second_draft["personality"]["trait_levels"] = {"uzkostlivy": 0.21}
    second_draft["mind"]["predispositions"] = {"anxiety": 0.18}
    second_draft["mind"]["morning_worse"] = false
    check(second_creator._session.replace_draft(second_draft, "H3 second resident"),
        "second resident draft is independently validated")
    second_creator._on_create()
    await get_tree().process_frame
    check(world.sims.size() == before_count + 2, "second creator adds exactly one additional resident")
    var second_sim = world.get_selected_sim()
    check(second_sim != null and second_sim.sim_name == "Mira Druhá",
        "second creation selects a distinct resident")
    if second_sim == null:
        finish("test_full_playable_slice")
        return
    var second_node_name: String = String(second_sim.name)
    var second_private: Dictionary = world.read_character_edit(second_node_name)
    var first_private: Dictionary = world.read_character_edit(node_name)
    check(second_private.get("ok", false) and first_private.get("ok", false)
        and second_private["data"]["uid"] != first_private["data"]["uid"],
        "two residents have separate authoritative identities")
    check(is_equal_approx(float(second_private["data"]["mind"]["predispositions"]["anxiety"]), 0.18)
        and is_equal_approx(float(first_private["data"]["mind"]["predispositions"]["anxiety"]), 0.65)
        and is_equal_approx(float(second_private["data"]["personality"]["trait_levels"]["uzkostlivy"]), 0.21)
        and is_equal_approx(float(first_private["data"]["personality"]["trait_levels"]["uzkostlivy"]), 0.73),
        "second resident cannot inherit first resident's private psyche or continuous traits")
    check(not second_sim.look.has("mind") and not second_sim.look.has("uid")
        and not second_sim.look.get("personality", {}).has("trait_levels"),
        "second resident public look excludes both residents' private data")
    second_private["data"]["mind"]["predispositions"]["anxiety"] = 0.99
    second_private["data"]["body"]["bust"] = 0.99
    second_private["data"]["personality"]["trait_levels"]["uzkostlivy"] = 0.99
    check(is_equal_approx(float(world.read_character_edit(second_node_name)["data"]["mind"]["predispositions"]["anxiety"]), 0.18)
        and is_equal_approx(float(world.read_character_edit(node_name)["data"]["mind"]["predispositions"]["anxiety"]), 0.65)
        and is_equal_approx(float(world.read_character_edit(second_node_name)["data"]["body"]["bust"]), 0.61)
        and is_equal_approx(float(world.read_character_edit(second_node_name)["data"]["personality"]["trait_levels"]["uzkostlivy"]), 0.21),
        "mutating nested readback data cannot alias either authoritative private record")
    first_private["data"]["mind"]["predispositions"]["anxiety"] = 0.42
    check(is_equal_approx(float(world.read_character_edit(node_name)["data"]["mind"]["predispositions"]["anxiety"]), 0.65)
        and is_equal_approx(float(world.read_character_edit(second_node_name)["data"]["mind"]["predispositions"]["anxiety"]), 0.18),
        "reverse readback mutation cannot affect either resident")
    var original_index: int = world.sims.find(selected)
    check(original_index >= 0, "first resident still belongs to the household")
    if original_index < 0:
        finish("test_full_playable_slice")
        return
    world.selected = original_index
    check(world.get_selected_sim() == selected, "original player selection restored after second creation")


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
    check(world.sims.size() == before_count + 2, "load restores both custom residents")
    check(String(world.get_selected_sim().name) == node_name, "load preserves selected player character")
    var reloaded_private: Dictionary = world.read_character_edit(node_name)
    check(reloaded_private.get("ok", false)
        and is_equal_approx(float(reloaded_private["data"]["personality"]["trait_levels"].get("uzkostlivy", -1.0)), 0.73)
        and is_equal_approx(float(reloaded_private["data"]["mind"]["predispositions"].get("anxiety", -1.0)), 0.65),
        "disk reload preserves private psyche and continuous trait values")
    var second_reloaded: Dictionary = world.read_character_edit(second_node_name)
    check(second_reloaded.get("ok", false)
        and is_equal_approx(float(second_reloaded["data"]["mind"]["predispositions"].get("anxiety", -1.0)), 0.18)
        and is_equal_approx(float(second_reloaded["data"]["personality"]["trait_levels"].get("uzkostlivy", -1.0)), 0.21)
        and is_equal_approx(float(reloaded_private["data"]["mind"]["predispositions"].get("anxiety", -1.0)), 0.65),
        "disk reload preserves separate private mind and trait values for both residents")
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
    var restarted_private: Dictionary = world.read_character_edit(node_name)
    check(restarted_private.get("ok", false)
        and bool(restarted_private["data"]["mind"]["morning_worse"])
        and is_equal_approx(float(restarted_private["data"]["body"]["bust"]), 0.13)
        and is_equal_approx(float(restarted_private["data"]["personality"]["trait_levels"].get("uzkostlivy", -1.0)), 0.73),
        "cold-start autosave resume preserves independent body, trait and psyche axes")
    check(not world.get_selected_sim().look.has("mind")
        and not world.get_selected_sim().look.has("uid"),
        "cold-start public appearance remains private-data-free")
    var second_restarted: Dictionary = world.read_character_edit(second_node_name)
    check(second_restarted.get("ok", false)
        and is_equal_approx(float(second_restarted["data"]["mind"]["predispositions"].get("anxiety", -1.0)), 0.18)
        and is_equal_approx(float(second_restarted["data"]["personality"]["trait_levels"].get("uzkostlivy", -1.0)), 0.21)
        and is_equal_approx(float(restarted_private["data"]["mind"]["predispositions"].get("anxiety", -1.0)), 0.65),
        "cold-start autosave keeps the two residents' private state independent")
    var restart: Dictionary = SaveGame.capture(world)
    check(world.sims.size() == before_count + 2, "new game instance auto-restores both custom residents")
    check(restart.get("ok", false) and restart.get("data") == expected.get("data"),
        "cold start autoload restores exactly the persisted simulation")
    check(String(world.get_selected_sim().name) == node_name,
        "real-world restart preserves playable selected character")
    world.queue_free()
    await get_tree().process_frame
    Assets.enabled = true
    clock.running = false
    finish("test_full_playable_slice")