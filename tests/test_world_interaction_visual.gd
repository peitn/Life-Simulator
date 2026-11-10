extends "res://tests/test_base.gd"
## Real production world regression: furniture support, authority-backed 3D picking,
## visible action props / clips, safe table routing and lying/sitting pivots.
const Main := preload("res://main.gd")
const Picker := preload("res://scripts/ui/world_interaction_picker.gd")
const Detour := preload("res://scripts/world/dining_detour.gd")
var world: Node3D

func _ready() -> void:
    watchdog_seconds = 70.0
    world = Main.new()
    world.net_config = {"mode":"offline", "hud":true, "camera":true,
        "visuals":false, "audio":false, "autosave":false, "autoload":false}
    add_child(world)
    _run.call_deferred()

func _run() -> void:
    await get_tree().process_frame
    section("Furniture mesh support and pose targets")
    var chair_legs := 0
    var duvet_meshes := 0
    for ch in world.get_children():
        if ch is MeshInstance3D and ch.mesh is BoxMesh:
            var d: Vector3 = ch.mesh.size
            if is_equal_approx(d.x, 0.055) and is_equal_approx(d.y, 0.435):
                chair_legs += 1
    check(chair_legs == 8, "two dining chairs have four real legs each", str(chair_legs))
    for o in world.get_smart_objects():
        if String(o.object_tag) == "bed":
            for ch in o.get_children():
                if ch is MeshInstance3D and ch.name == "DuvetCover" and ch.mesh is ArrayMesh and ch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 221 and o.get_node_or_null("DuvetRaised") != null:
                    duvet_meshes += 1
    check(duvet_meshes == 2, "both imported beds have visible separately placed quilts")
    var sofa = world.get_smart_objects()[3]
    check(sofa.pose_offsets[0].z >= 0.3, "sofa seated characters placed forward of rear cushion")

    section("Click to access 3D-world actions")
    var camera: Camera3D = world.camera_rig.camera
    check(camera != null and camera.is_current(), "real runtime 3D camera")
    for i in world.get_smart_objects().size():
        var obj = world.get_smart_objects()[i]
        var box: Array = Picker.BOXES.get(String(obj.object_tag), [])
        var screen: Vector2 = camera.unproject_position(obj.to_global(box[0]))
        var result: Dictionary = Picker.pick(camera, world.get_smart_objects(), [], screen)
        check(result.get("kind", "") == "object" and int(result.get("index", -1)) == i, "object projection picks " + String(obj.object_tag) + str(i))
    check(Picker.pick(camera, world.get_smart_objects(), [], Vector2(-1,-1)).is_empty(), "off-screen tap denied")
    var fridge = world.get_smart_objects()[0]
    var pt := camera.unproject_position(fridge.global_position + Vector3.UP * 1.1)
    world._pick_world_click(pt)
    check(world.hud._world_popup.visible and not world.hud._world_action_refs.is_empty(), "world click opens actual validated popup")
    check(int(world.hud._world_action_refs[0].get("target_index", -1)) == 0, "menu targets selected real fridge")
    var book = world.get_smart_objects()[4]
    world.hud.open_world_object_actions(4, Vector2i(350,330))
    check(world.hud._world_action_refs.size() == 1 and world.hud._world_action_refs[0].get("action_id") == "read",
        "clicking bookshelf exposes reading command")
    world.hud._world_popup.hide()

    section("Authoritative visual action clips and real hand props")
    var visual = world.sims[0].visual
    check(visual != null and visual.uses_model(), "original real skinned 3D character present")
    visual.apply("stand", 0.0, "spokojeny", "Test", "Čte", "", false, "read")
    check(visual.current_anim() == "read", "reading performs a dedicated bone animation")
    check(visual._read_book != null and visual._read_book.visible, "open book visible while reading (chest-mounted between both hands)")
    visual.apply("stand", 0.0, "spokojeny", "Test", "Píše", "", false, "text_friend")
    check(visual.current_anim() == "text" and visual._held_phone != null and visual._held_phone.visible,
        "phone and writing pose appear during message")
    check(not visual._read_book.visible, "book disappears outside reading")
    visual.apply("stand", 0.0, "spokojeny", "Test", "Vaří", "", false, "cook")
    check(visual.current_anim() == "cook" and not visual._held_phone.visible, "cooking uses hand movement without phone")
    visual.apply("lie", 0.0, "spokojeny", "Test", "Spí", "", false, "sleep")
    check(visual.current_anim() == "lie" and visual._body_pivot.position.y > 0.7
        and visual._body_pivot.position.z > 0.88, "lying body/head raised and shifted away from pillow")

    section("Table avoids straight-line mesh clipping")
    var routes := [[Vector3(-1,0,-1.4), Vector3(-5,0,-1.4)],
        [Vector3(-5,0,-1.4), Vector3(-1,0,-1.4)],
        [Vector3(-1,0,-0.8), Vector3(-5,0,-2.1)]]
    for pair in routes:
        var pos: Vector3 = pair[0]
        var goal: Vector3 = pair[1]
        var safe := true
        for i in 150:
            if pos.distance_to(goal) <= 0.30:
                break
            var next: Vector3 = Detour.waypoint(pos, goal)
            var delta: Vector3 = next - pos
            pos += delta.normalized() * minf(delta.length(), 0.3) if delta.length() > 0.001 else Vector3.ZERO
            if Detour.TABLE.grow(0.08).has_point(Vector2(pos.x, pos.z)):
                safe = false
        check(pos.distance_to(goal) <= 0.30 and safe, "actor routes around table without occupying its footprint")
    world.queue_free()
    await get_tree().process_frame
    finish("world_interaction_visual")