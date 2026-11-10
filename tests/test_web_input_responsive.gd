extends "res://tests/test_base.gd"
## UI-only regression for live browser canvas sizes. No household mutation.
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const HUD := preload("res://scripts/ui/hud.gd")

func _ready() -> void:
    watchdog_seconds = 35.0
    _run.call_deferred()

func _inside(r: Rect2, size: Vector2i) -> bool:
    return r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= float(size.x) + 0.5 and r.end.y <= float(size.y) + 0.5

func _run() -> void:
    var old_size: Vector2i = get_window().size
    var settings := SettingsMenu.new()
    add_child(settings)
    await get_tree().process_frame
    settings._warning.visible = true
    var acknowledge := settings._warning.find_child("ContinueButton", true, false) as Button
    var warning_scroll := settings._warning.find_child("WarningScroll", true, false) as ScrollContainer
    section("First-run warning touch visibility and scroll")
    check(acknowledge != null and warning_scroll != null, "real warning button and scroll exist")
    if acknowledge == null or warning_scroll == null:
        finish("web_input_responsive")
        return
    for size in [Vector2i(320, 568), Vector2i(390, 720), Vector2i(900, 600), Vector2i(1600, 900)]:
        get_window().size = size
        await get_tree().process_frame
        await get_tree().process_frame
        check(_inside(settings._warning.get_global_rect(), size), "warning panel inside " + str(size))
        check(_inside(acknowledge.get_global_rect(), size), "confirm hit area inside " + str(size))
        check(warning_scroll.size.y >= 70.0, "warning body remains scrollable " + str(size))
    settings._warning.visible = false
    settings._menu.visible = true
    section("Settings menu responsive")
    for size in [Vector2i(320, 568), Vector2i(390, 720), Vector2i(900, 600)]:
        get_window().size = size
        await get_tree().process_frame
        await get_tree().process_frame
        check(_inside(settings._menu.get_global_rect(), size), "settings panel inside " + str(size))
    var hud := HUD.new()
    add_child(hud)
    await get_tree().process_frame
    section("HUD commands and touch targets")
    for size in [Vector2i(320, 568), Vector2i(390, 720), Vector2i(900, 600)]:
        get_window().size = size
        await get_tree().process_frame
        await get_tree().process_frame
        var panel := hud.get_node("NeedsAndCommandsPanel") as Control
        check(_inside(panel.get_global_rect(), size), "HUD panel inside " + str(size))
        check(_inside(hud._create_button.get_global_rect(), size), "create character button inside " + str(size))
    hud.queue_free()
    settings.queue_free()
    get_window().size = old_size
    await get_tree().process_frame
    finish("web_input_responsive")
