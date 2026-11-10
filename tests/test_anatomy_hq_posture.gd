extends "res://tests/test_base.gd"
## Production realistic seated contact + pillow clearance + native quality LOD.
const Visual := preload("res://scripts/sim/sim_visual.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Builder := preload("res://scripts/world/world_builder.gd")

func _ready() -> void:
    watchdog_seconds = 65.0
    _run.call_deferred()

func _bone_world(visual: Node3D, bone_name: String) -> Vector3:
    var skel: Skeleton3D = visual._skeleton()
    var idx := skel.find_bone(bone_name)
    return skel.to_global(skel.get_bone_global_pose(idx).origin)

func _run() -> void:
    section("Native Blender high-detail LOD, lossless rig")
    check(Visual.preferred_character_model(false,false,true) == "character", "native uses rebuilt detail mesh with canonical wardrobe bind order")
    check(Visual.preferred_character_model(true,false,true) == "character", "web uses same canonical detailed anatomy")
    check(Visual.preferred_character_model(false,true,true) == "character", "dedicated/headless simulation remains lightweight")
    check(Visual.preferred_character_model(false,false,false) == "character", "missing HQ source safely falls back")
    var hq = Assets.instantiate("character_hq")
    check(hq != null, "real exported Blender HQ GLB loads through production AssetLibrary")
    if hq != null:
        var skeletons := hq.find_children("*","Skeleton3D",true,false)
        check(skeletons.size()==1 and skeletons[0].get_bone_count()==17, "existing 17-bone animation rig preserved")
        var face:MeshInstance3D=null
        var torso:MeshInstance3D=null
        for node in hq.find_children("*","MeshInstance3D",true,false):
            if String(node.name).contains("head__face__skin_body"):face=node
            if String(node.name).contains("body__body__skin_body"):torso=node
        check(face != null and face.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() >= 12000, "subdivided 12.4k-vertex head")
        check(face != null and face.mesh.get_blend_shape_count() == 86, "86 independent facial morph targets retained")
        check(torso != null and torso.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() >= 3800, "skin body subdivision retained")
        hq.free()
    section("Actual animated seated ankles contact floor")
    var visual=Visual.new()
    add_child(visual)
    await get_tree().process_frame
    visual.apply("sit",0.0,"spokojeny","test","Sezení")
    visual._anim.play("sit",0.0)
    visual._anim.seek(0.4,true)
    var before_y: float=minf(_bone_world(visual,"foot_l").y,_bone_world(visual,"foot_r").y)
    for i in 36:
        visual._seat_foot_contact(1.0/60.0)
    var after_y: float=minf(_bone_world(visual,"foot_l").y,_bone_world(visual,"foot_r").y)
    check(before_y > 0.14, "original floating seated ankle reproduced",str(before_y))
    check(absf(after_y - 0.08) <= 0.015, "seated foot corrected to ~8 cm above ground (bone inside sole)",str(after_y))
    var stable:float=visual._body_pivot.position.y
    visual.apply("sit",0.0,"spokojeny","test","relax")
    check(absf(visual._body_pivot.position.y-stable)<0.001, "repeated action HUD update preserves foot contact correction")
    visual.apply("lie",0.0,"spokojeny","test","sleep")
    visual._anim.play("lie",0)
    visual._anim.seek(0.4,true)
    var head:Vector3=_bone_world(visual,"head")
    var toes:Vector3=_bone_world(visual,"foot_l")
    check(head.z > -0.47 and head.z < -0.3, "sleeping face center clears the starter pillow edge",str(head))
    check(toes.z < 1.075 and toes.z > 0.91, "sleeping feet remain on full-length starter mattress",str(toes))
    check(absf(visual._body_pivot.position.y - 0.79)<0.001, "lying trunk stays above mattress")
    visual.apply("stand",0.0,"spokojeny","test","idle")
    check(visual._body_pivot.position.length()<0.001, "standing clears all posture offsets")
    visual.queue_free()
    section("TV interaction matches real front sofa cushion")
    var world3d=Node3D.new()
    add_child(world3d)
    var b=Builder.new(world3d)
    b.build()
    var tv=b.objects[2]
    var sofa=b.objects[3]
    check(tv.object_tag=="tv" and sofa.object_tag=="sofa", "known starter television and couch")
    var seat:Vector3=tv.to_global(tv.pose_offsets[0])
    var cushion:Vector3=sofa.to_global(sofa.pose_offsets[0])
    check(seat.distance_to(cushion)<0.08, "watch-TV seat anchor equals sofa cushion, not inside backrest",str(seat.distance_to(cushion)))
    var entry:Vector3=tv.to_global(tv.use_offsets[0])
    check((entry-seat).length()>0.5 and (entry-seat).length()<0.8, "TV approach from in front of seat")
    world3d.queue_free()
    await get_tree().process_frame
    finish("anatomy_hq_posture")
