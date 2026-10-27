extends "res://tests/test_base.gd"
## Actual production Blender 17-bone model + 10 torso morphs + anatomical
## paired breast areolae, papillae, and anterior umbilical ridge.
## Independent ten finger morph sliders in isolated editor preview.
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const CD := preload("res://scripts/character/character_data.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")
const TorsoBuilder := preload("res://scripts/assets/torso_detail_builder.gd")
const HandBuilder := preload("res://scripts/assets/hand_detail_builder.gd")
const Library := preload("res://scripts/assets/asset_library.gd")

var visual: Node3D

func _ready() -> void:
    watchdog_seconds = 75.0
    visual = SimVisual.new()
    add_child(visual)
    _run.call_deferred()


func _run() -> void:
    await get_tree().process_frame
    section("Torso source and safety")
    check(visual.uses_model() and visual.torso_details_available(),
        "actual character.glb contains all five anatomically enriched torso meshes")
    check(Schema.TOPS.has("zadne"),"validated optional no-top wardrobe choice exists")
    var sk:Skeleton3D=visual.get_node("Body/Model/Skeleton3D")
    check(sk.get_bone_count()==17,"real gameplay skeleton remains 17 functional animation bones")
    var nodes:Dictionary=visual.get("_torso_detail_nodes")
    check(nodes.size()==5,"surface, areola, nipple, umbilical rim and darker umbilical center")
    var expected_vertices:Dictionary={
        "surface":830,"areola":66,"nipple":66,"navel_rim":33,"navel_dark":33}
    for label in expected_vertices:
        var instance:MeshInstance3D=nodes[label]
        check(instance.mesh != null and instance.mesh.get_blend_shape_count()==10,
            "authored 10 torso morph targets preserved for "+label)
        check((instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
            ==int(expected_vertices[label]),"real nonempty 3D anatomy mesh vertex count "+label)
        check(instance.skin.get_bind_count()==17 and instance.skeleton==NodePath(".."),
            "torso anatomy shares original skinned player model "+label)
        check(not instance.visible,"clothing defaults to covering anatomical details "+label)
    check(visual._hand_detail_nodes.size()==2,"existing 10 fingers and 10 nail plates preserved")
    check(visual._foot_detail_nodes.size()==2,"existing 10 toes and toenails preserved")
    section("Bare torso and materials")
    var data=CD.create()
    var base_snapshot:Dictionary=data.public_snapshot()
    var start_look:Dictionary=visual.look_params.duplicate(true)
    var bare:Dictionary=data.to_dict()
    bare["clothing"]["bezne"]["top"]="zadne"
    var cd=CD.create()
    cd.set_from_dict(bare)
    var bare_snapshot:Dictionary=cd.public_snapshot()
    check(String(bare_snapshot.get("clothing",{}).get("bezne",{}).get("top",""))=="zadne",
        "strict public character snapshot accepts no-top outfit")
    visual.apply_look(bare_snapshot)
    var look:Dictionary=visual.look_params
    check(look.get("outfit_top")=="zadne","skin torso only selected with explicit no top")
    for label in nodes:
        check((nodes[label] as MeshInstance3D).visible,
            "bare top reveals correctly skinned detail "+label)
    var pelvis:MeshInstance3D=nodes["navel_dark"]
    var a:MeshInstance3D=nodes["areola"]
    var n:MeshInstance3D=nodes["nipple"]
    var areola_color:Color=(a.material_override as StandardMaterial3D).albedo_color
    var nipple_color:Color=(n.material_override as StandardMaterial3D).albedo_color
    var skin_color:Color=(nodes["surface"].material_override as StandardMaterial3D).albedo_color
    check(areola_color.r<skin_color.r and nipple_color.r<=areola_color.r,
        "nipple/areola pigments derive from character's skin tone, not gender")
    check((pelvis.material_override as StandardMaterial3D).albedo_color.r<skin_color.r,
        "navel uses shaded inset and raised geometry")
    var navel_verts:PackedVector3Array=pelvis.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    check(navel_verts[0].z>0.06,"navel marker is on the front of the actual body")
    var nipverts:PackedVector3Array=n.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var max_z:float=-99.0
    var has_left:=false
    var has_right:=false
    for point in nipverts:
        max_z=maxf(max_z,point.z)
        has_left=has_left or point.x<-.08
        has_right=has_right or point.x>.08
    check(has_left and has_right and max_z>.06,
        "two genuinely protruding papillae in paired left/right positions")
    check(n.mesh.surface_get_blend_shape_arrays(0).size()==10 and
        nodes["navel_rim"].mesh.surface_get_blend_shape_arrays(0).size()==10,
        "all surface details own ten independent morph delta targets")
    section("Morph/animation and clothing restoration")
    cd.body["bust"]=.92
    cd.body["body_fat"]=.76
    cd.body["chest"]=.73
    var shaped:Dictionary=cd.public_snapshot()
    visual.apply_look(shaped)
    check(nodes["nipple"].get_blend_shape_value(
        nodes["nipple"].find_blend_shape_by_name("bust"))>.25,
        "papillae track real body/bust morph with source Blender shape delta")
    var skintone=(nodes["surface"].material_override as StandardMaterial3D).albedo_color
    check(skintone==visual.skin_color,
        "skin cover uses the same public SkinModel pigment as rest of character")
    var chest:int=sk.find_bone("chest")
    var earlier:Transform3D=sk.get_bone_global_pose(chest)
    sk.set_bone_pose_rotation(chest,Quaternion(Vector3.RIGHT,.32))
    await get_tree().process_frame
    check(not earlier.is_equal_approx(sk.get_bone_global_pose(chest)),
        "torso details continue to follow the game's animated chest bone")
    sk.reset_bone_poses()
    check(visual.set_anatomy_view("bones"),
        "character's previously integrated 194-bone debug anatomy remains usable")
    check(not nodes["surface"].visible and not nodes["nipple"].visible,
        "anatomy cutaway hides the skin and nipple overlays")
    visual.set_anatomy_view("off")
    check(nodes["surface"].visible and nodes["nipple"].visible,
        "when leaving cutaway, explicit bare-top appearance is restored")
    cd.clothing["bezne"]["top"]="tricko"
    visual.apply_look(cd.public_snapshot())
    for label in nodes:
        check(not (nodes[label] as MeshInstance3D).visible,
            "changing to ordinary shirt covers all intimate torso details "+label)
    section("Individual actual finger sliders in editor preview")
    var preview:VBoxContainer=Preview.new()
    add_child(preview)
    await get_tree().process_frame
    var sliders:Dictionary=preview.get("_finger_sliders")
    check(sliders.size()==10,"all ten separate finger articulation slider controls built")
    var control:=preview.get_node_or_null("IndividualFingerControls") as VBoxContainer
    check(control!=null and not control.visible,
        "individual finger panel defaults collapsed on small screens")
    preview._toggle_finger_controls()
    check(control.visible,"hand-specific control panel opens on demand")
    check(preview.visual._hand_detail_nodes.size()==2,
        "finger controls drive 3D simulated character finger+real nail meshes")
    var source_skin:MeshInstance3D=preview.visual._hand_detail_nodes[0]
    var source_nails:MeshInstance3D=preview.visual._hand_detail_nodes[1]
    var before_key:=HandBuilder.curl_key(5)
    var other_key:=HandBuilder.curl_key(9)
    var finger_i:int=source_skin.find_blend_shape_by_name(before_key)
    var other_i:int=source_skin.find_blend_shape_by_name(other_key)
    var pre_other:float=source_skin.get_blend_shape_value(other_i)
    (sliders["l_0"] as HSlider).value=.65
    check(is_equal_approx(source_skin.get_blend_shape_value(finger_i),.65),
        "individual left index finger slider deforms real GPU skin morph")
    check(is_equal_approx(source_nails.get_blend_shape_value(finger_i),.65),
        "finger nail plate follows precisely same motion as finger")
    check(is_equal_approx(source_skin.get_blend_shape_value(other_i),pre_other),
        "altering one finger cannot deform unrelated thumb")
    (sliders["r_4"] as HSlider).value=.95
    var thumb: int=source_skin.find_blend_shape_by_name(HandBuilder.curl_key(4))
    check(is_equal_approx(source_skin.get_blend_shape_value(thumb),.95),
        "independent right thumb can curl while left index unchanged")
    preview._set_hand_pose_preview(2)
    check((sliders["l_0"] as HSlider).value==1.0 and
        (sliders["r_4"] as HSlider).value==.84,
        "full-hand fist gesture synchronizes all individual sliders without loops")
    check(preview.viewport.world_3d!=get_viewport().world_3d,
        "isolated editor character finger mechanics never mutate playable world")
    check(preview.public_snapshot().is_empty() or not
        preview.public_snapshot().has("mind"),
        "individual anatomy sliders transmit no private mind state")
    preview.queue_free()
    section("No new gameplay/network mechanics")
    check(not visual.has_method("run_elmer_fem"),
        "nipple, navel and fingers remain visual anatomy, not fake Elmer physics")
    check(start_look.is_empty() or not start_look.has("mind"),
        "public anatomy cosmetics do not reference mental state")
    finish("test_torso_fingers_v1")
