extends "res://tests/test_base.gd"
## Real authored meshes (not primitive fallback), editor integration and optional screenshots.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

func _ready() -> void:
    run.call_deferred()

func run() -> void:
    var settings = get_node("/root/GameSettings")
    settings.persist = false
    settings.reset()
    settings.set_value("warning_ack", true, false)
    Assets.enabled = true
    var world = Main.new()
    world.net_config = {"mode":"offline", "hud":true, "camera":false, "visuals":false, "audio":false}
    add_child(world)
    get_node("/root/GameClock").running = false
    await get_tree().process_frame
    world.set_process(false)
    var sim = world.get_selected_sim()
    var before: Dictionary = world.read_character_edit(String(sim.name)).duplicate(true)
    world.hud.get("_edit_button").pressed.emit()
    var editor = world.hud.get("_character_editor")
    var preview = editor.get("_visual_preview")
    check(preview.visual.uses_model(), "preview loads authored character mesh")
    check(preview.visual.get("_model") != sim.visual.get("_model"), "authored preview and live model are different instances")
    var styles: OptionButton = editor.get("_style")
    for i in range(1, styles.item_count):
        if str(styles.get_item_metadata(i)) == "kawaii_kocka":
            styles.select(i)
            styles.item_selected.emit(i)
            break
    check(preview.visual.look_params["outfit_top"] == "kawaii_kocici_mikina", "authored preview resolves pink cat hoodie")
    check(preview.visual.get("_c5_nodes").size() > 0, "authored C5 clothing geometry instantiated")
    check(preview.visual.get("_skin_copy") != sim.visual.get("_skin_copy"), "preview does not share mutable skin bind poses")
    check(preview.visual.skin_material() != sim.visual.skin_material(), "preview has independent skin material")
    check(world.read_character_edit(String(sim.name)) == before, "preview creation and clothing leave authority unchanged")
    var args := OS.get_cmdline_user_args()
    for dimensions in [Vector2i(1280, 900), Vector2i(360, 800)]:
        get_window().content_scale_size = Vector2i.ZERO
        get_window().size = dimensions
        for i in 6:
            await get_tree().process_frame
        var panel: Control = editor.find_children("*", "PanelContainer", true, false)[0]
        var apply_button: Button = editor.find_child("Apply", true, false)
        var rect: Rect2 = panel.get_global_rect()
        check(rect.end.x <= dimensions.x + 1 and rect.end.y <= dimensions.y + 1, "editor fits viewport %s" % dimensions)
        check(apply_button.get_global_rect().end.y <= dimensions.y, "Apply remains visible at %s" % dimensions)
        if "--capture" in args:
            var lease_index := args.find("--lease")
            var lease := args[lease_index + 1] if lease_index >= 0 and lease_index + 1 < args.size() else ""
            var G = load("res://tools/automation_lock.gd")
            if not check(G.owns(lease), "capture owns project lease"):
                finish("test_character_preview"); return
            await RenderingServer.frame_post_draw
            var image := get_viewport().get_texture().get_image()
            check(not image.is_empty(), "renderer returned a real framebuffer")
            var path := "res://previews/editor-preview-%dx%d.png" % [dimensions.x, dimensions.y]
            check(image.save_png(path) == OK, "screenshot saved " + path)
    editor.call("_on_cancel")
    await get_tree().process_frame
    check(not is_instance_valid(preview), "authored preview resources released with editor")
    check(world.read_character_edit(String(sim.name)) == before, "Cancel preserves original live character")
    world.queue_free()
    await get_tree().process_frame
    finish("test_character_preview")
