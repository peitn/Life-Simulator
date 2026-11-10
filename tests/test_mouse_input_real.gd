extends "res://tests/test_base.gd"
## Real viewport-dispatched mouse and touch events, not method-only tests.
const Main := preload("res://main.gd")
const Picker := preload("res://scripts/ui/world_interaction_picker.gd")
var world: Node3D

func _ready() -> void:
    watchdog_seconds = 80.0
    _run.call_deferred()

func _mouse(position: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
    var e := InputEventMouseButton.new()
    e.position = position
    e.global_position = position
    e.button_index = button
    e.pressed = pressed
    get_viewport().push_input(e, true)

func _motion(position: Vector2, relative: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> void:
    var e := InputEventMouseMotion.new()
    e.position=position
    e.global_position=position
    e.relative=relative
    e.button_mask=mask
    get_viewport().push_input(e, true)

func _click(position: Vector2) -> void:
    _mouse(position,true)
    _mouse(position,false)

func _run() -> void:
    get_window().size=Vector2i(1200,800)
    world=Main.new()
    world.net_config={"mode":"offline","hud":true,"camera":true,"visuals":false,
        "audio":false,"autosave":false,"autoload":false}
    add_child(world)
    await get_tree().process_frame
    await get_tree().process_frame
    var cam:Camera3D=world.camera_rig.camera
    section("Actual viewport world clicks")
    check(cam!=null,"native camera exists")
    check(not world.settings_menu.is_open(),"world is not blocked by a modal")
    for i in world.smart_objects.size():
        var obj=world.smart_objects[i]
        var center:Vector3=Picker.BOXES[String(obj.object_tag)][0]
        var point:Vector2=cam.unproject_position(obj.to_global(center))
        var chosen:Dictionary=Picker.pick(cam,world.smart_objects,[],point)
        check(chosen.get("kind","")=="object" and int(chosen.get("index",-1))==i,
            "ray hits visible object "+String(obj.object_tag)+str(i))
    var fridge=world.smart_objects[0]
    var point:Vector2=cam.unproject_position(fridge.to_global(Vector3(0,1,0)))
    _click(point)
    await get_tree().process_frame
    check(world.hud._world_popup.visible,"real mouse down+up opens fridge menu")
    check(world.hud._world_action_refs.size()==2,"fridge menu offers authenticated commands")
    world.hud._world_popup.hide()

    section("Drag never accidentally executes click")
    var before:Vector3=world.camera_rig.position
    var start:=Vector2(600,650)
    _mouse(start,true)
    _motion(start+Vector2(66,0),Vector2(66,0))
    _mouse(start+Vector2(66,0),false)
    await get_tree().process_frame
    check(world.camera_rig.position.distance_to(before)>1.0,"left drag moves 3D camera")
    check(not world.hud._world_popup.visible,"left drag does not open action popup")

    section("Right-drag orbit and wheel zoom")
    var rotation_before:float=world.camera_rig.yaw
    _mouse(Vector2(600,650),true,MOUSE_BUTTON_RIGHT)
    _motion(Vector2(645,650),Vector2(45,0),MOUSE_BUTTON_MASK_RIGHT)
    _mouse(Vector2(645,650),false,MOUSE_BUTTON_RIGHT)
    check(absf(rotation_before-world.camera_rig.yaw)>0.12,"right mouse rotates orbit")
    var zoom_before:float=world.camera_rig._target_distance
    _mouse(Vector2(600,650),true,MOUSE_BUTTON_WHEEL_UP)
    check(world.camera_rig._target_distance < zoom_before,"wheel zooms towards furniture")

    section("UI receives clicks without world commands")
    var button:Button=world.hud._create_button
    var before_roster:int=world.sims.size()
    _click(button.get_global_rect().get_center())
    await get_tree().process_frame
    check(world.hud._character_creator!=null and is_instance_valid(world.hud._character_creator),
        "mouse click opens real creator HUD button")
    check(world.sims.size()==before_roster,"mouse UI click does not create unintended agent")
    check(not world.hud._world_popup.visible,"HUD click doesn't cause 3D object command")
    if world.hud._character_creator!=null:
        world.hud._character_creator.queue_free()
        world.hud._character_creator=null
    world.queue_free()
    await get_tree().process_frame
    finish("mouse_input_real")
