extends "res://tests/test_base.gd"
## End-to-end offline HUD editor: UI events -> draft -> authority.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Wardrobe := preload("res://scripts/assets/subculture_wardrobe.gd")

func _ready() -> void:
    run.call_deferred()

func run() -> void:
    get_node("/root/GameClock").running = false
    var settings = get_node("/root/GameSettings")
    settings.persist = false
    settings.reset()
    Assets.enabled = false
    var world = Main.new()
    world.net_config = {"mode":"offline","hud":true,"camera":false,"visuals":false,"audio":false}
    add_child(world)
    await get_tree().process_frame
    var sim = world.get_selected_sim()
    check(sim != null, "offline selected character exists")
    if sim == null:
        finish("test_character_editor_ui")
        return
    var key := String(sim.name)
    var original: Dictionary = world.read_character_edit(key)["data"].duplicate(true)
    var hud = world.hud
    check(hud != null, "real HUD exists")
    var button: Button = hud.get("_edit_button")
    check(button != null and button.text == "Upravit postavu", "visible editor entry in HUD")
    button.pressed.emit()
    var editor = hud.get("_character_editor")
    check(editor != null and is_instance_valid(editor) and editor.is_inside_tree(), "HUD opens editor control")
    if editor == null or not is_instance_valid(editor):
        finish("test_character_editor_ui")
        return
    var session = editor.get("_session")
    check(session.is_open(), "isolated edit session opened")
    var preview = editor.get("_visual_preview")
    check(preview != null and preview.visual != sim.visual, "draft uses a separate visual instance")
    check(preview.viewport.world_3d != world.get_viewport().world_3d, "preview has an isolated 3D world")
    check(not preview.public_snapshot().has("mind") and not preview.public_snapshot().has("story") and not preview.public_snapshot().has("uid"), "preview stores only public appearance snapshot")
    check(preview.viewport.size == Vector2i(360, 280), "preview render budget stays bounded")
    var live_rotation: Vector3 = sim.visual.rotation
    preview.call("_turn", PI / 4)
    check(not is_zero_approx(preview.visual.rotation.y) and sim.visual.rotation == live_rotation, "turntable rotates only preview")
    preview.call("_turn", 0.0)
    check(is_zero_approx(preview.visual.rotation.y), "front button restores orientation")
    var slider_panel = editor.get("_sliders")
    var sliders = slider_panel.find_children("*","HSlider",true,false)
    check(sliders.size()>0, "actual personality sliders rendered in UI tree")
    check(slider_panel.custom_minimum_size.x <= 1.0, "slider panel has no fixed desktop width")
    if sliders.size()>0:
        var slider: HSlider = sliders[0]
        check(slider.custom_minimum_size.x <= 140.0, "slider uses narrow viewport-friendly minimum")
        var before := slider.value
        var after := 0.81 if before < 0.6 else 0.21
        slider.value = after
        check(session.is_dirty(), "UI slider creates draft change")
        check(session.draft()["personality"]["hexaco"] == original["personality"]["hexaco"], "trait slider preserves other personality groups")
        check(world.read_character_edit(key)["data"] == original, "slider does not mutate live character")
        check(session.can_undo(), "slider change supports undo")
        editor.call("_on_undo")
        check(not session.is_dirty(), "undo restores original draft")
        editor.call("_on_redo")
        check(session.is_dirty(), "redo restores edited draft")
    var garments: Dictionary = editor.get("_item_buttons")
    check(garments.size() == 3, "individual garment selectors exist")
    var category: OptionButton = editor.get("_slot")
    var top_picker: OptionButton = garments.get("top")
    var bottom_picker: OptionButton = garments.get("bottom")
    var shoes_picker: OptionButton = garments.get("shoes")
    check(top_picker != null and bottom_picker != null and shoes_picker != null, "top/bottom/shoes picker controls exist")
    if top_picker != null and bottom_picker != null and shoes_picker != null:
        var before_items: Dictionary = session.draft()
        var sport_idx := -1
        for i in range(category.item_count):
            if category.get_item_text(i) == "sport":
                sport_idx = i
        check(sport_idx >= 0, "sport category is available")
        if sport_idx >= 0:
            category.select(sport_idx)
            category.item_selected.emit(sport_idx)
            check(session.draft()["clothing"]["active"] == "sport", "category switch updates draft active outfit")
            var top_idx := -1
            for i in range(top_picker.item_count):
                if top_picker.get_item_metadata(i) == "emo_mikina":
                    top_idx = i
            check(top_idx >= 0, "emo top is available as independent garment")
            if top_idx >= 0:
                top_picker.select(top_idx)
                top_picker.item_selected.emit(top_idx)
                check(session.draft()["clothing"]["sport"]["top"] == "emo_mikina", "individual top edits selected category")
                check(preview.visual.look_params["outfit_top"] == "emo_mikina", "garment change refreshes isolated preview")
                check(world.read_character_edit(key)["data"] == original, "garment change does not mutate live authority")
            var shoe_idx := -1
            for i in range(shoes_picker.item_count):
                if shoes_picker.get_item_metadata(i) == "goth_platformy":
                    shoe_idx = i
            if shoe_idx >= 0:
                shoes_picker.select(shoe_idx)
                shoes_picker.item_selected.emit(shoe_idx)
            check(session.draft()["clothing"]["sport"]["shoes"] == "goth_platformy", "individual shoes edit selected category")
            var no_bottom_idx := -1
            for i in range(bottom_picker.item_count):
                if bottom_picker.get_item_metadata(i) == "zadne":
                    no_bottom_idx = i
            var valid_draft: Dictionary = session.draft()
            if no_bottom_idx >= 0:
                bottom_picker.select(no_bottom_idx)
                bottom_picker.item_selected.emit(no_bottom_idx)
            check(session.draft() == valid_draft, "invalid no-bottom-without-dress selection rejected")
            editor.call("_on_item_selected", top_picker.item_count + 50, "top")
            check(session.draft() == valid_draft, "out-of-range item selection cannot alter draft")
            editor.call("_on_undo")
            check(session.draft()["clothing"]["sport"]["shoes"] != "goth_platformy", "Undo reverses individual shoe edit")
            editor.call("_on_redo")
            check(session.draft()["clothing"]["sport"]["shoes"] == "goth_platformy", "Redo restores individual shoe edit")
            editor.call("_on_undo")
            editor.call("_on_undo")
            editor.call("_on_undo")
            check(session.draft() == before_items, "Undo restores all original categories and garments")
    var styles: OptionButton = editor.get("_style")
    var idx := -1
    for i in range(1, styles.item_count):
        if str(styles.get_item_metadata(i)) == "kawaii_kocka":
            idx = i
            break
    check(idx>0, "cat hoodie style available")
    var unchanged_draft: Dictionary = session.draft()
    editor.call("_on_style_selected", styles.item_count + 50)
    check(session.draft() == unchanged_draft, "invalid wardrobe index cannot alter draft")
    if idx>0:
        styles.select(idx)
        styles.item_selected.emit(idx)
        check(session.draft()["clothing"]["bezne"]["top"]=="kawaii_kocici_mikina", "wardrobe UI writes draft")
        check(world.read_character_edit(key)["data"]==original, "wardrobe does not mutate live character")
        check(preview.visual.look_params["outfit_top"] == "kawaii_kocici_mikina", "cat hoodie reaches draft 3D visual")
        check(sim.visual.look_params["outfit_top"] != "kawaii_kocici_mikina", "live visual remains unchanged before Apply")
        editor.call("_on_undo")
        check(preview.public_snapshot()["clothing"] == original["clothing"], "undo refreshes preview clothing")
        editor.call("_on_redo")
        check(preview.visual.look_params["outfit_top"] == "kawaii_kocici_mikina", "redo refreshes preview clothing")
    var cancel: Button = editor.get_node("PanelContainer/VBoxContainer/HBoxContainer/Cancel") if editor.has_node("PanelContainer/VBoxContainer/HBoxContainer/Cancel") else null
    if cancel != null:
        cancel.pressed.emit()
    else:
        editor.call("_on_cancel")
    await get_tree().process_frame
    check(world.read_character_edit(key)["data"]==original, "Cancel discards all draft edits")
    check(not is_instance_valid(preview), "Cancel frees preview world and visual")
    button.pressed.emit()
    editor = hud.get("_character_editor")
    check(editor != null and is_instance_valid(editor), "editor can reopen after cancel")
    if editor != null and is_instance_valid(editor):
        session = editor.get("_session")
        styles = editor.get("_style")
        idx = -1
        for i in range(1, styles.item_count):
            if str(styles.get_item_metadata(i)) == "kawaii_kocka":
                idx = i
                break
        if idx>0:
            styles.select(idx)
            styles.item_selected.emit(idx)
        editor.call("_on_apply")
        var applied: Dictionary = world.read_character_edit(key)
        check(applied["revision"]==1, "Apply increments authoritative revision")
        check(applied["data"]["clothing"]["bezne"]["top"]=="kawaii_kocici_mikina", "Apply reaches live authority")
        check(sim.visual.look_params["outfit_top"]=="kawaii_kocici_mikina", "Apply refreshes visual appearance")
        check(not session.is_dirty(), "successful Apply resets draft baseline")
        check(editor.get("_visual_preview").visual.look_params == sim.visual.look_params, "applied live appearance matches preview")
        var applied_snapshot: Dictionary = world.read_character_edit(key).duplicate(true)
        # An editor opened offline must not bypass the authoritative mode check
        # if the session switches to multiplayer before Apply.
        var emo_idx := -1
        for i in range(1, styles.item_count):
            if str(styles.get_item_metadata(i)) == "emo":
                emo_idx = i
                break
        if emo_idx>0:
            styles.select(emo_idx)
            styles.item_selected.emit(emo_idx)
        check(session.is_dirty(), "new wardrobe draft exists before network switch")
        world.net.mode = world.net.Mode.HOST
        editor.call("_on_apply")
        world.net.mode = world.net.Mode.OFFLINE
        check(world.read_character_edit(key) == applied_snapshot, "network mode switch blocks stale offline editor Apply")
        check(session.is_dirty(), "rejected network Apply preserves editable draft")
        editor.call("_on_cancel")
        await get_tree().process_frame
    world.net.mode=world.net.Mode.HOST
    check(not world.read_character_edit(key)["ok"], "network private edit denied")
    hud.call("_on_edit_character")
    check(not is_instance_valid(hud.get("_character_editor")), "network HUD refuses editor")
    world.net.mode=world.net.Mode.OFFLINE
    world.queue_free()
    await get_tree().process_frame
    Assets.enabled = true
    finish("test_character_editor_ui")