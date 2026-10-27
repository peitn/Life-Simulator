extends SceneTree
## Actual hand-detail geometry + material + morph + pose tests.
## The mesh contains ten digits and ten nail plates, but uses two legacy
## hand bones and is not a new independently articulated phalange system.
const Preview := preload("res://scripts/ui/character_preview.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const G := preload("res://tools/automation_lock.gd")
var checks := 0
var failures := 0

func check(ok: bool, what: String) -> void:
    checks += 1
    if not ok:
        failures += 1
    print(("PASS " if ok else "FAIL ") + what)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var preview := Preview.new()
    root.add_child(preview)
    var v: Node3D=preview.visual
    check(v.uses_model(),"Blender character model exists")
    var nodes: Array=v._hand_detail_nodes
    check(nodes.size()==2,"runtime creates authentic skinned digit and nail meshes")
    if nodes.size()!=2:
        preview.queue_free()
        await process_frame
        quit(2)
        return
    var sk: Skeleton3D=v._skeleton()
    var expected: Dictionary={"Anatomy_fingers_skin":510,"Anatomy_fingers_nails":90}
    for m in nodes:
        var name:String=String(m.name)
        check(expected.has(name),"expected skin/nail mesh "+name)
        var mesh: Mesh=m.mesh
        check(mesh!=null and mesh.get_surface_count()==1,name+" actual skinned mesh")
        var arr: Array=mesh.surface_get_arrays(0)
        var verts:PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
        var normals:PackedVector3Array=arr[Mesh.ARRAY_NORMAL]
        var bones:PackedInt32Array=arr[Mesh.ARRAY_BONES]
        var weights:PackedFloat32Array=arr[Mesh.ARRAY_WEIGHTS]
        var indices:PackedInt32Array=arr[Mesh.ARRAY_INDEX]
        check(verts.size()==expected.get(name,0),name+" exact ten digits/nails geometry")
        check(normals.size()==verts.size() and bones.size()==verts.size()*4
            and weights.size()==bones.size() and indices.size()%3==0,
            name+" correct GPU skin arrays")
        check(mesh.get_blend_shape_count()==20,name+" retains ten body morphs and ten independent finger curl targets")
        check(m.skin==v._skin_copy and m.skeleton==NodePath(".."),
            name+" shares actor-specific deformable Skin and skeleton")
        var left:=0
        var right:=0
        var bad_bone:=0
        var degenerate:=0
        var max_err:=0.0
        for vi in verts.size():
            if verts[vi].x>0:
                left+=1
            else:
                right+=1
            var bind_id: int=bones[vi*4]
            if bind_id != (7 if verts[vi].x>0 else 13):
                bad_bone+=1
            var w:float=0.0
            for k in 4:
                w+=weights[vi*4+k]
            max_err=maxf(max_err,absf(1.0-w))
        for i in range(0,indices.size(),3):
            var a:int=indices[i]
            var b:int=indices[i+1]
            var c:int=indices[i+2]
            if (verts[b]-verts[a]).cross(verts[c]-verts[a]).length_squared()<0.00000000000001:
                degenerate+=1
        check(left==right and left>0,name+" five details on both hands")
        check(bad_bone==0 and max_err<0.00001,name+" 100% correct hand bone with exact normalized weights")
        check(degenerate==0,name+" no collapsed face triangles")
        var flipped:=0
        for i in range(0,indices.size(),3):
            var ia:int=indices[i]
            var ib:int=indices[i+1]
            var ic:int=indices[i+2]
            var fn:Vector3=(verts[ib]-verts[ia]).cross(verts[ic]-verts[ia]).normalized()
            var vn:Vector3=(normals[ia]+normals[ib]+normals[ic]).normalized()
            if fn.dot(vn)<0.05:
                flipped+=1
        check(flipped==0,name+" winding matches outward surface normals")
        check(m.get_blend_shape_value(0)==0.0,name+" default face deformation is zero")
        for target in mesh.surface_get_blend_shape_arrays(0):
            check((target[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==verts.size(),
                name+" all morph target vertex counts match")
    var base: Dictionary=CharacterData.create().to_dict()
    base["identity"]["first_name"]="Nora"
    base["personality"]["traits"]=["optimista"]
    var default_skin:Color=v._hand_skin_material.albedo_color
    base["skin"]["tone"]=0.95
    base["body"]["shoulders"]=1.0
    base["body"]["body_fat"]=1.0
    check(Validator.validate(base,{"mode":"strict"}).get("ok",false),
        "extreme adult appearance remains schema valid")
    preview.show_draft(base)
    check(v._hand_skin_material.albedo_color!=default_skin,
        "finger geometry follows continuous skin chromophores")
    check(v._hand_nail_material.albedo_color!=v._hand_skin_material.albedo_color,
        "real nail plates have independent surface shade")
    check(v._hand_detail_nodes[0].get_blend_shape_value(5)!=0.0,
        "hand fingers deform with body frame/shoulder morph targets")
    var skin_nodes_before: Array=v._hand_detail_nodes.duplicate()
    base["skin"]["tone"]=0.05
    preview.show_draft(base)
    check(v._hand_detail_nodes==skin_nodes_before,
        "multiple skin color changes reuse identical topology and rig")
    check(v._hand_skin_material.albedo_color!=default_skin,
        "melanin range changes hand coloration, not identity")

    # Real skeleton bone pose movements, independently left and right.
    var left_id:int=sk.find_bone("hand_l")
    var right_id:int=sk.find_bone("hand_r")
    check(left_id>=0 and right_id>=0,"independent hand bone targets present")
    var old_l:Transform3D=sk.get_bone_global_pose(left_id)
    var old_r:Transform3D=sk.get_bone_global_pose(right_id)
    sk.set_bone_pose_rotation(sk.find_bone("forearm_l"),Quaternion(Vector3.RIGHT,-PI/2))
    sk.force_update_all_bone_transforms()
    check(not sk.get_bone_global_pose(left_id).is_equal_approx(old_l),
        "left fingers follow articulated elbow motion")
    check(sk.get_bone_global_pose(right_id).is_equal_approx(old_r),
        "right hand unaffected by left forearm movement")
    sk.reset_bone_poses()
    sk.force_update_all_bone_transforms()
    if DisplayServer.get_name()!="headless":
        var args:=OS.get_cmdline_user_args()
        var run_id:String=String(args[0]) if args.size()==1 else ""
        check(G.owns(run_id),"capture only under actual owning project lease")
        if not G.owns(run_id):
            preview.queue_free()
            quit(3)
            return
        base["body"]["shoulders"]=0.5
        base["body"]["body_fat"]=0.3
        base["skin"]["tone"]=0.45
        base["clothing"]["bezne"]["top"]="kawaii_kocici_mikina"
        preview.show_draft(base)
        preview.viewport.size=Vector2i(720,540)
        preview.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        preview.camera.size=.58
        preview.camera.position=Vector3(0,0.89,3)
        preview.camera.look_at(Vector3(0,.89,0))
        for state in ["rest","elbow"]:
            sk.reset_bone_poses()
            for bname in ["forearm_l","forearm_r"]:
                sk.set_bone_pose_rotation(sk.find_bone(bname),Quaternion(Vector3.RIGHT,0.0 if state=="rest" else -PI/2.0))
            sk.force_update_all_bone_transforms()
            for i in 8: await process_frame
            await RenderingServer.frame_post_draw
            if not G.owns(run_id):
                quit(4)
                return
            var path:String="res://previews/"+run_id+"-hand-"+state+".jpg"
            check(preview.viewport.get_texture().get_image().save_jpg(path,.9)==OK,
                "real Godot framebuffer captured for "+state)
    preview.queue_free()
    await process_frame
    print("HAND_GEOMETRY_RESULT checks=",checks," failures=",failures)
    quit(0 if failures==0 else 1)