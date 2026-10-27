extends "res://tests/test_base.gd"
## In-game GPU double-joint finger bend integration, not real phalange physics.
const Visual=preload("res://scripts/sim/sim_visual.gd")
const Preview=preload("res://scripts/ui/character_preview.gd")
const Hand=preload("res://scripts/assets/hand_detail_builder.gd")

func _ready() -> void:
    watchdog_seconds=75
    _run.call_deferred()

func _run() -> void:
    var v=Visual.new()
    add_child(v)
    await get_tree().process_frame
    section("40 real skinned 3D blend shapes")
    check(v.uses_model(),"original Godot 17-bone character loads")
    check(v._hand_detail_nodes.size()==2,"original 10 fingers and 10 nails present")
    var skin:MeshInstance3D=v._hand_detail_nodes[0]
    var nails:MeshInstance3D=v._hand_detail_nodes[1]
    for part in [skin,nails]:
        check(part.mesh.get_blend_shape_count()==40,
            "10 body +10 combined finger+20 separate proximal/distal channels")
        check(part.skin.get_bind_count()==17,"original player animation Skin unchanged")
        check(part.mesh.get_surface_count()==1,"actual GPU skinned indexed geometry")
    check(Hand.joint_key(5,"proximal")==&"finger_joint_5_proximal",
        "stable left index proximal key")
    check(Hand.joint_key(5,"distal")==&"finger_joint_5_distal",
        "stable left index distal key")
    check(Hand.joint_key(11,"distal")==&"" and
        Hand.joint_key(0,"nonexistent")==&"","unknown or invalid shapes rejected")
    var a:int=skin.find_blend_shape_by_name(Hand.joint_key(5,"proximal"))
    var b:int=skin.find_blend_shape_by_name(Hand.joint_key(5,"distal"))
    check(a>=20 and b>=20 and a!=b,"separate indices are actual mesh blend shapes")
    var verts:PackedVector3Array=skin.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var shapes:Array=skin.mesh.surface_get_blend_shape_arrays(0)
    var pa:PackedVector3Array=shapes[a][Mesh.ARRAY_VERTEX]
    var pb:PackedVector3Array=shapes[b][Mesh.ARRAY_VERTEX]
    var changed:=0
    var unrelated:=0
    for i in pa.size():
        if (pa[i]-pb[i]).length_squared()>1e-8:changed+=1
        if i<5*Hand.SKIN_PER_DIGIT or i>=6*Hand.SKIN_PER_DIGIT:
            if pa[i].length_squared()>1e-14 or pb[i].length_squared()>1e-14:
                unrelated+=1
    check(changed>=15,"proximal and distal hinge regions truly differ in 3D")
    check(unrelated==0,"left index bends cannot modify any neighboring finger")
    check(verts.size()==510 and (shapes[a][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==510,
        "all 510 finger skin vertices have full proximal morph arrays")
    check(nails.mesh.surface_get_blend_shape_arrays(0).size()==40 and
        (nails.mesh.surface_get_blend_shape_arrays(0)[a][Mesh.ARRAY_VERTEX]
            as PackedVector3Array).size()==90,
        "all 90 fingernail vertices support both new joint bends")
    section("Two independent curl regions, live character")
    var right_before:Dictionary=v.finger_joint_values("r",0)
    check(v.set_finger_joint_bend("l",0,"proximal",.80),"proximal bend accepted")
    check(v.set_finger_joint_bend("l",0,"distal",.30),"distal bend accepted")
    var values:Dictionary=v.finger_joint_values("l",0)
    check(values.get("mode")=="joint" and
        is_equal_approx(float(values.get("proximal",0)),.80) and
        is_equal_approx(float(values.get("distal",0)),.30) and
        is_zero_approx(float(values.get("combined",-1))),
        "proximal=.8, distal=.3, no competing whole-finger deformation")
    check(is_equal_approx(nails.get_blend_shape_value(
        nails.find_blend_shape_by_name(Hand.joint_key(5,"proximal"))),.80),
        "fingernail follows actual proximal GPU animation")
    check(is_equal_approx(nails.get_blend_shape_value(
        nails.find_blend_shape_by_name(Hand.joint_key(5,"distal"))),.30),
        "fingernail follows actual distal GPU animation")
    check(v.finger_joint_values("r",0)==right_before,
        "right-hand counterpart unaffected")
    check(not v.set_finger_joint_bend("l",0,"middle",.5) and
        not v.set_finger_joint_bend("l",5,"proximal",.5) and
        not v.set_finger_joint_bend("X",0,"proximal",.5) and
        not v.set_finger_joint_bend("l",0,"proximal",NAN) and
        not v.set_finger_joint_bend("l",0,"proximal",1.5),
        "invalid side/digit/joint/finite/range fail closed")
    check(v.finger_joint_values("l",0)==values,
        "rejected joints did not mutate existing finger pose")
    check(v.set_finger_curl("l",0,.65),"existing whole-finger curl retained")
    var legacy:Dictionary=v.finger_joint_values("l",0)
    check(legacy.get("mode")=="legacy" and
        is_equal_approx(float(legacy.get("combined",0)),.65) and
        is_zero_approx(float(legacy.get("proximal",-1))) and
        is_zero_approx(float(legacy.get("distal",-1))),
        "whole-finger curl safely clears incompatible paired joint morphs")
    section("Isolated editor 3D controls")
    var preview:=Preview.new()
    add_child(preview)
    await get_tree().process_frame
    var singles:Dictionary=preview.get("_finger_sliders")
    var joints:Dictionary=preview.get("_finger_joint_sliders")
    check(singles.size()==10 and joints.size()==20,
        "10 legacy sliders +20 new independent UI controls exist")
    var details:VBoxContainer=preview.get_node_or_null(
        "IndividualFingerControls/IndividualFingerJointControls")
    check(details!=null and not details.visible,
        "advanced controls are initially folded to avoid UI overload")
    preview._toggle_finger_controls()
    preview._toggle_finger_joint_controls()
    check(details.visible,"nested advanced joint controls can be displayed")
    (joints["l_0_proximal"] as HSlider).value=.55
    (joints["l_0_distal"] as HSlider).value=.27
    var pv:Dictionary=preview.visual.finger_joint_values("l",0)
    check(is_equal_approx(float(pv.get("proximal",0)),.55) and
        is_equal_approx(float(pv.get("distal",0)),.27),
        "live 3D creator controls actually modify independent knuckle shapes")
    check(is_zero_approx((singles["l_0"] as HSlider).value),
        "joint selection resets conflicting combined UI")
    (singles["l_0"] as HSlider).value=.9
    check(is_zero_approx((joints["l_0_proximal"] as HSlider).value) and
        is_zero_approx((joints["l_0_distal"] as HSlider).value),
        "combined selection resets advanced UI")
    preview._set_hand_pose_preview(2)
    check(preview.visual.finger_joint_values("l",0).get("mode")=="legacy",
        "existing fist preset remains compatible")
    check(preview.viewport.world_3d!=get_viewport().world_3d,
        "preview world isolated from living game and multiplayer physics")
    check(not preview.public_snapshot().has("mind") and
        not preview.public_snapshot().has("uid"),
        "new sliders never expose private character fields")
    preview.queue_free()
    finish("test_independent_finger_joints_c14")
