extends "res://tests/test_base.gd"
## Verify that narrow Web-like layouts expose the 3D scene for real touch
## rather than keeping the entire right sidebar over the hit targets.
const Main := preload("res://main.gd")
const Picker := preload("res://scripts/ui/world_interaction_picker.gd")

func _ready() -> void:
    watchdog_seconds=40.0
    _run.call_deferred()

func _run() -> void:
    get_window().size=Vector2i(390,720)
    var world=Main.new()
    world.net_config={"mode":"offline","hud":true,"camera":true,
        "visuals":false,"audio":false,"autoload":false,"autosave":false}
    add_child(world)
    await get_tree().process_frame
    var hud=world.hud
    hud._force_compact_preview=true
    hud._fit_controls_panel()
    await get_tree().process_frame
    section("390px touch-screen starts with usable unobscured 3D")
    check(hud._compact_panel_mode,"narrow browser layout detected")
    check(not hud._needs_panel.visible,"right panel does not consume full world input")
    check(hud._mobile_panel_toggle.visible and hud._mobile_panel_toggle.get_global_rect().end.x <= 390,
        "reachable menu toggle remains on-screen")
    hud._mobile_panel_toggle.emit_signal("pressed")
    check(hud._needs_panel.visible,"tap can open all existing HUD functions")
    hud._mobile_panel_toggle.emit_signal("pressed")
    check(not hud._needs_panel.visible,"tap can re-expose scene")
    var cam: Camera3D=world.camera_rig.camera
    var fridge=world.smart_objects[0]
    var screen:Vector2=cam.unproject_position(fridge.to_global(Vector3(0,1,0)))
    check(screen.x > 0 and screen.x < 390 and screen.y > 52 and screen.y < 720,
        "fridge is on visible touch screen")
    var pick:Dictionary=Picker.pick(cam,world.smart_objects,world.sims,screen)
    check(pick.get("kind","")=="object" and pick.get("index",-1)==0,
        "ray selects real fridge through 3D viewport")
    var event=InputEventScreenTouch.new()
    event.index=0
    event.pressed=true
    event.position=screen
    get_viewport().push_input(event,true)
    await get_tree().process_frame
    check(hud._world_popup.visible and hud._world_action_refs.size()>0,
        "real viewport touch opens contextual menu")
    check(world._last_touch_ms>0,"native touch is registered for emulated mouse dedup")
    hud._world_popup.hide()
    get_window().size=Vector2i(1200,800)
    hud._force_compact_preview=false
    hud._fit_controls_panel()
    await get_tree().process_frame
    check(hud._needs_panel.visible and not hud._mobile_panel_toggle.visible,
        "desktop-size resize restores existing full controls")
    world.queue_free()
    await get_tree().process_frame
    finish("web_touch_compact_controls")
