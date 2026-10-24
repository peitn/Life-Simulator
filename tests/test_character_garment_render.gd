extends SceneTree
## Manual graphical screenshot regression, run with xvfb-run (not --headless).
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const G := preload("res://tools/automation_lock.gd")

func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    var args := OS.get_cmdline_user_args()
    var index := args.find("--lease")
    var lease := String(args[index + 1]) if index >= 0 and index + 1 < args.size() else ""
    if not G.owns(lease):
        print("GARMENT_RENDER_BLOCKED: no lease")
        quit(2)
        return
    var clock = get_root().get_node("GameClock")
    clock.running = false
    var settings = get_root().get_node("GameSettings")
    settings.persist = false
    settings.reset()
    settings.set_value("warning_ack", true, false)
    Assets.enabled = true
    var world = Main.new()
    world.net_config = {"mode":"offline", "hud":true, "camera":false, "visuals":false, "audio":false}
    get_root().add_child(world)
    await process_frame
    await process_frame
    var hud = world.hud
    if hud == null:
        print("GARMENT_RENDER_FAIL: no HUD")
        quit(3)
        return
    hud.get("_edit_button").pressed.emit()
    await process_frame
    var editor = hud.get("_character_editor")
    if editor == null:
        print("GARMENT_RENDER_FAIL: no editor")
        quit(3)
        return
    var slot: OptionButton = editor.get("_slot")
    for i in range(slot.item_count):
        if slot.get_item_text(i) == "sport":
            slot.select(i)
            slot.item_selected.emit(i)
            break
    var tops: OptionButton = editor.get("_item_buttons")["top"]
    for i in range(tops.item_count):
        if tops.get_item_metadata(i) == "kawaii_kocici_mikina":
            tops.select(i)
            tops.item_selected.emit(i)
            break
    for size in [Vector2i(1280,900),Vector2i(360,800)]:
        DisplayServer.window_set_size(size)
        get_root().size = size
        await process_frame
        await process_frame
        await process_frame
        if not G.owns(lease):
            print("GARMENT_RENDER_BLOCKED: lost lease")
            quit(2)
            return
        var img := get_root().get_texture().get_image()
        var path := "res://previews/garment-editor-%dx%d.png" % [size.x,size.y]
        var err := img.save_png(path)
        print("GARMENT_RENDER size=",size," screenshot=",path," error=",err," image_size=",img.get_size())
        if err != OK:
            quit(4)
            return
    world.queue_free()
    await process_frame
    quit()