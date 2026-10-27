extends "res://tests/test_base.gd"
## Dedicated non-clothing torso sculpt C13: check closed watertight skin mesh,
## actual 3D recessed navel, anatomically continuous tissue and body morphs.
## GPU-skin/animation testing uses REAL playable 17-bone character.glb.
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Torso := preload("res://scripts/assets/anatomical_torso_surface.gd")

func _ready() -> void:
    watchdog_seconds = 80.0
    _run.call_deferred()

func _run() -> void:
    var character := SimVisual.new()
    add_child(character)
    await get_tree().process_frame
    section("Zero bare-skin overhead until requested")
    check(character.uses_model(),"real authored 17-bone gameplay character exists")
    check(not character.torso_details_available(),"clothed NPC has no high-poly torso")
    var cd := CharacterData.create()
    cd.clothing["bezne"]["top"]="zadne"
    character.apply_look(cd.public_snapshot())
    check(character.torso_details_available(),"first topless selection builds actual new skin")
    var members:Dictionary=character.get("_torso_detail_nodes")
    var surface:MeshInstance3D=members["surface"]
    var shader:StandardMaterial3D=surface.material_override
    var shirt_mesh:Mesh=character.get_node("Body/Model/Skeleton3D").get_node("body__0").mesh         if character.get_node("Body/Model/Skeleton3D").has_node("body__0") else null
    check(surface.mesh!=shirt_mesh,"bare torso is no longer original garment mesh")
    check(surface.mesh.get_blend_shape_count()==10,
        "all original public body morphs apply to sculpted bare skin")
    var arrays:Array=surface.mesh.surface_get_arrays(0)
    var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
    var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
    var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
    var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
    check(verts.size()==2162 and indices.size()==12960,
        "actual closed 2162-vertex / 4320 indexed triangle skin topology")
    check(uvs.size()==verts.size() and weights.size()==verts.size()*4,
        "UV and 17-skin-compatible four influence data allocated for all vertices")
    var edges:Dictionary={}
    var degenerate:=0
    var side_wrong:=0
    for i in range(0,indices.size(),3):
        var a:int=indices[i]
        var b:int=indices[i+1]
        var c:int=indices[i+2]
        var n:Vector3=(verts[b]-verts[a]).cross(verts[c]-verts[a])
        if n.length_squared()<1e-16:degenerate+=1
        var avg:Vector3=(verts[a]+verts[b]+verts[c])/3.0
        if absf(avg.y-1.255)<.16 and (n*Vector3(avg.x,0,avg.z)).dot(Vector3.ONE)<0:
            # This can include navel relief surface, only samples enough to
            # guard global inverted skin orientation.
            side_wrong+=1
        for edge in [[a,b],[b,c],[c,a]]:
            var k:String=str(mini(edge[0],edge[1]))+":"+str(maxi(edge[0],edge[1]))
            edges[k]=int(edges.get(k,0))+1
    var nonmanifold:=0
    for key in edges:
        if int(edges[key])!=2:nonmanifold+=1
    check(degenerate==0 and nonmanifold==0,
        "all torso triangles nondegenerate and EVERY edge connects exactly 2 faces")
    check(verts.size()-edges.size()+indices.size()/3==2,
        "closed torso has genus-zero Euler characteristic (no shirt seams/gaps)")
    var influence_errors:=0
    var interpolated:=0
    for i in verts.size():
        var t:float=weights[i*4]+weights[i*4+1]+weights[i*4+2]+weights[i*4+3]
        if absf(t-1.0)>.0001 or bones[i*4]!=1 or bones[i*4+1]!=2:
            influence_errors+=1
        if weights[i*4]>.01 and weights[i*4+1]>.01:
            interpolated+=1
    check(influence_errors==0 and interpolated>100,
        "all skin vertices normalized to correct spine+chest bones with smooth bend seam")
    check(shader!=null and not shader.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,
        "new skin is an opaque colored body, not a semitransparent clothing overlay")
    section("Scultped navel in actual mesh topology")
    var source:PackedVector3Array=PackedVector3Array()
    for node in character.get_node("Body/Model").find_children("*","MeshInstance3D",true,false):
        var mi:MeshInstance3D=node
        if mi.mesh == null or mi.mesh.get_surface_count()==0:
            continue
        # Real source shirt is available as a retained hidden GLB part.
        if (mi.name.begins_with("body__") and mi.mesh.get_blend_shape_count()==10
                and mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==830):
            source=mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
            break
    check(source.size()==830,"source 10-morph garment landmark data available (not drawn bare)")
    if source.size()==830:
        var inside:float=Torso.anterior_z(source,0,Torso.NAVEL_Y)
        var outside:float=Torso.anterior_z(source,.03,Torso.NAVEL_Y)
        check(outside-inside>.0045 and inside>.05,
            "navel is a true >=4.5mm inward geometric indentation, not colored dot")
        var right:float=Torso.anterior_z(source,.03,Torso.NAVEL_Y)
        var left:float=Torso.anterior_z(source,-.03,Torso.NAVEL_Y)
        check(absf(left-right)<.0005,"umbilical pit geometrically symmetric in neutral mesh")
    section("Existing chest details on new sculpted body")
    check(members["nipple"].visible and members["navel_dark"].visible,
        "existing 3D papillae and navel visual layers sit on new bare torso")
    var nipple:MeshInstance3D=members["nipple"]
    check(nipple.mesh.get_blend_shape_count()==10,
        "raised nipples still follow all 10 original body shape targets")
    var ref_bust:float=nipple.get_blend_shape_value(
        nipple.find_blend_shape_by_name("bust"))
    cd.body["bust"]=.9
    cd.body["waist"]=.4
    character.apply_look(cd.public_snapshot())
    check(nipple.get_blend_shape_value(nipple.find_blend_shape_by_name("bust"))>ref_bust,
        "complex bust/waist edits correctly update skinned chest sculpt")
    var sample_idx: int=surface.find_blend_shape_by_name("bust")
    check(sample_idx>=0 and surface.get_blend_shape_value(sample_idx)>.20,
        "new sculpted torso participates in normal character morph system")
    var skel:Skeleton3D=character.get_node("Body/Model/Skeleton3D")
    var chest:int=skel.find_bone("chest")
    var before:Transform3D=skel.get_bone_global_pose(chest)
    skel.set_bone_pose_rotation(chest,Quaternion(Vector3.RIGHT,.30))
    await get_tree().process_frame
    check(not before.is_equal_approx(skel.get_bone_global_pose(chest)),
        "original character chest animation still drives actual torso skin")
    skel.reset_bone_poses()
    check(character.set_anatomy_view("muscles"),
        "existing original real in-world anatomy mode remains operational")
    check(not surface.visible,"anatomical cutaway hides outside skin")
    character.set_anatomy_view("off")
    check(surface.visible,"original bare torso visible after leaving anatomy view")
    cd.clothing["bezne"]["top"]="tricko"
    character.apply_look(cd.public_snapshot())
    check(not surface.visible,"regular shirt hides torso and details")
    check(surface.mesh.get_blend_shape_count()==10,
        "switching outfit doesn't destroy shared skinned geometry")
    finish("test_torso_surface_c13")