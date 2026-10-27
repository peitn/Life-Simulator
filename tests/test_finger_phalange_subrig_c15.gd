extends "res://tests/test_base.gd"
## C15 true 2x14-bone Godot Skeleton3D: real Blender bone coordinates,
## parented to ACTUAL animated game hand BoneAttachment3D, render-only demo.
const Visual=preload("res://scripts/sim/sim_visual.gd")
const Subrig=preload("res://scripts/assets/finger_phalange_subrig_c15.gd")
const Preview=preload("res://scripts/ui/character_preview.gd")

func _ready()->void:
    watchdog_seconds=75
    _run.call_deferred()

func _run()->void:
    var v=Visual.new()
    add_child(v)
    await get_tree().process_frame
    section("Lazy subrig only when requested")
    check(v.uses_model() and not v.finger_skeletal_view(),
        "normal game character remains original with no extra hand bones")
    check(v.get("_finger_skeletal_anchors").is_empty(),
        "28 new finger bones allocated only on demand")
    var sk:Skeleton3D=v.get_node("Body/Model/Skeleton3D")
    check(sk.get_bone_count()==17,"original production skeleton exactly 17 bones")
    var before:Array=v._hand_detail_nodes.map(func(mi):return mi.visible)
    check(v.set_finger_skeletal_view(true),"opt-in real skeletal hand mode available")
    var anchors:Dictionary=v.get("_finger_skeletal_anchors")
    check(anchors.size()==2,"two hands have separate active skeletal subrigs")
    check(not v._hand_detail_nodes[0].visible and
        not v._hand_detail_nodes[1].visible,
        "legacy GPU finger and nail meshes hide during skeleton diagnostic")
    for frame in 3: await get_tree().process_frame
    for side in ["l","r"]:
        var anchor:BoneAttachment3D=anchors[side]
        var rig:Skeleton3D=anchor.get_node("PhalangeRig")
        var root_idx:int=rig.find_bone("finger_2_1_"+side)
        var child_idx:int=rig.find_bone("finger_2_2_"+side)
        check(rig.get_bone_global_pose(root_idx).origin.distance_to(rig.get_bone_global_rest(root_idx).origin)<.0001,
            "C15 neutral root pose matches actual bone rest "+side)
        check(rig.get_bone_global_pose(child_idx).origin.distance_to(rig.get_bone_global_pose(root_idx).origin)>.01,
            "C15 relaxed child segment stays separate from root "+side)
        var driver:BoneAttachment3D=rig.get_node("Drive_finger_2_1_"+side)
        check(driver.global_position.distance_to(rig.to_global(rig.get_bone_global_pose(root_idx).origin))<.005,
            "C15 visible segment follows actual joint location "+side)
        check(anchor.get_parent()==sk and anchor.bone_name=="hand_"+side,
            "hand subrig attached to ACTUAL gameplay animation bone "+side)
        check(anchor.visible and rig.get_bone_count()==14,
            "each hand owns fourteen separate internally articulated bones "+side)
        check(rig.get_child_count()==14,
            "every phalanx has its own animated BoneAttachment3D "+side)
        check(not rig.get_meta("gameplay_collision_enabled",true),
            "these are skeleton render poses, not imaginary real collision physics")
        check(rig.get_bone_parent(rig.find_bone("finger_2_2_"+side))==
            rig.find_bone("finger_2_1_"+side),
            "true articulated anatomical finger parent hierarchy "+side)
        check(rig.get_bone_parent(rig.find_bone("finger_2_3_"+side))==
            rig.find_bone("finger_2_2_"+side),
            "three real individual phalanx levels link into one hierarchy "+side)
        var nail_independent:bool=true
        for bone in rig.get_children():
            if not bone is BoneAttachment3D or bone.get_child_count()!=1:
                nail_independent=false
                continue
            var mesh=bone.get_child(0)
            if not mesh is MeshInstance3D or mesh.mesh==null:
                nail_independent=false
        check(nail_independent,"fourteen separately attachable 3D bone surfaces "+side)
    section("Real independent skeletal rotations and parent motion")
    var l:BoneAttachment3D=anchors["l"]
    var left:Skeleton3D=l.get_node("PhalangeRig")
    var r:BoneAttachment3D=anchors["r"]
    var right:Skeleton3D=r.get_node("PhalangeRig")
    var index:int=left.find_bone("finger_2_1_l")
    var middle:int=left.find_bone("finger_2_2_l")
    var other:int=left.find_bone("finger_3_1_l")
    var right_index:int=right.find_bone("finger_2_1_r")
    var initial_left:Transform3D=left.get_bone_global_pose(middle)
    var initial_right:Transform3D=right.get_bone_global_pose(right_index)
    var other_before:Quaternion=left.get_bone_pose_rotation(other)
    check(v.set_finger_joint_bend("l",1,"proximal",.8),
        "same real character public visual API drives skeletal base phalanx")
    check(not left.get_bone_global_pose(middle).is_equal_approx(initial_left),
        "middle segment moves in transformed coordinates when parent bone rotates")
    check(left.get_bone_pose_rotation(other).is_equal_approx(other_before),
        "other finger retains its prior skeletal angle despite index rotation")
    check(right.get_bone_global_pose(right_index).is_equal_approx(initial_right),
        "right hand skeleton unaffected by left index bend")
    check(v.set_finger_joint_bend("l",1,"distal",.25),
        "a second independently oriented actual skeletal segment responds")
    check(not left.get_bone_pose_rotation(middle).is_equal_approx(Quaternion.IDENTITY),
        "distal actual phalanx bone rotates separately, not just a GPU morph")
    section("C15 combined-to-independent transition synchronizes real bones")
    check(v.set_finger_curl("l",1,.8),"combined curl prepares both skeletal segments")
    check(not left.get_bone_pose_rotation(middle).is_equal_approx(Quaternion.IDENTITY),
        "combined curl bends distal skeletal phalanx")
    check(v.set_finger_joint_bend("l",1,"proximal",.3),
        "switch from combined curl to independent proximal control")
    check(left.get_bone_pose_rotation(middle).is_equal_approx(Quaternion.IDENTITY),
        "switch to independent control clears stale distal skeleton pose")
    check(left.get_bone_pose_rotation(index).is_equal_approx(Quaternion(Vector3.RIGHT,.74*.3)),
        "new proximal angle matches the GPU joint value")
    check(v.set_finger_joint_bend("l",1,"distal",.4),
        "independent distal change accepted after transition")
    check(left.get_bone_pose_rotation(index).is_equal_approx(Quaternion(Vector3.RIGHT,.74*.3)) and
        left.get_bone_pose_rotation(middle).is_equal_approx(Quaternion(Vector3.RIGHT,.66*.4)),
        "independent distal update preserves proximal angle")
    check(right.get_bone_global_pose(right_index).is_equal_approx(initial_right),
        "combined-to-joint transition does not mutate opposite hand")
    check(v.set_finger_curl("l",1,0.0) and
        left.get_bone_pose_rotation(index).is_equal_approx(Quaternion.IDENTITY) and
        left.get_bone_pose_rotation(middle).is_equal_approx(Quaternion.IDENTITY),
        "return to open hand resets both skeletal angles")
    var original_hand:Transform3D=l.global_transform
    var left_forearm:int=sk.find_bone("forearm_l")
    sk.set_bone_pose_rotation(left_forearm,Quaternion(Vector3.RIGHT,-.45))
    sk.force_update_all_bone_transforms()
    await get_tree().process_frame
    check(not l.global_transform.is_equal_approx(original_hand),
        "complete 14-joint hand skeleton follows live actor elbow/hand animation")
    sk.reset_bone_poses()
    sk.force_update_all_bone_transforms()
    section("Pose validation and accurate restore")
    check(not Subrig.bend(l,5,"proximal",.5) and
        not Subrig.bend(l,0,"unsupported",.5) and
        not Subrig.bend(l,0,"distal",NAN) and
        not Subrig.bend(l,0,"proximal",1.1),
        "nonfinite/invalid physical-looking visual pose rejected safely")
    var node_count:int=sk.get_child_count()
    check(v.set_finger_skeletal_view(false),"skeletal overlay can turn off")
    check(not l.visible and not r.visible and not v.finger_skeletal_view(),
        "entire real 28-bone overlay is hidden without destroying original actor")
    check(v._hand_detail_nodes[0].visible==bool(before[0]) and
        v._hand_detail_nodes[1].visible==bool(before[1]),
        "existing skin and nail geometry visibility restored exactly")
    check(v.set_finger_skeletal_view(true) and sk.get_child_count()==node_count,
        "reopening skeletal mode reuses existing rigs without duplicates")
    v.set_finger_skeletal_view(false)
    section("Game editor UI and isolation")
    var preview:=Preview.new()
    add_child(preview)
    await get_tree().process_frame
    check(preview.has_node("IndividualFingerControls/ActualFingerSkeletonButton"),
        "player can toggle skeletal finger mode from real editor")
    preview._toggle_real_finger_skeleton()
    check(preview.visual.finger_skeletal_view(),"preview button activates real 28-bone rig")
    var prig:Skeleton3D=preview.visual.get("_finger_skeletal_anchors")["l"].get_node("PhalangeRig")
    var a:int=prig.find_bone("finger_1_1_l")
    preview._on_finger_joint_changed(.72,"l",0,"proximal")
    check(not prig.get_bone_pose_rotation(a).is_equal_approx(Quaternion.IDENTITY),
        "preview advanced slider directly rotates a real articulated bone")
    check(preview.viewport.world_3d!=get_viewport().world_3d,
        "3D editor preview skeleton is in an independent world")
    preview._toggle_real_finger_skeleton()
    check(not preview.visual.finger_skeletal_view(),"preview returns to normal skin and nails")
    check(not preview.public_snapshot().has("mind") and
        not preview.public_snapshot().has("uid"),
        "finger diagnostics never leak private state or user IDs")
    preview.queue_free()
    check(not v.has_method("simulate_finger_collision"),
        "no false live phalange physics claims")
    finish("test_finger_phalange_subrig_c15")