extends SceneTree
## Genuine barefoot soles, separated ten toes/nails, shoe occlusion and
## shared morph/rig test. No independent toe-bone animation yet.
const Preview := preload("res://scripts/ui/character_preview.gd")
const CD := preload("res://scripts/character/character_data.gd")
const G := preload("res://tools/automation_lock.gd")
var checks:=0
var failures:=0
func check(cond:bool,label:String)->void:
    checks+=1
    if not cond:failures+=1
    print(("PASS " if cond else "FAIL ")+label)
func _init()->void:call_deferred("run")
func run()->void:
    var preview:=Preview.new()
    root.add_child(preview)
    var visual:Node3D=preview.visual
    var nodes:Array=visual._foot_detail_nodes
    check(nodes.size()==2,"two real anatomy meshes (feet + nails) created")
    if nodes.size()!=2:
        preview.queue_free()
        quit(2)
        return
    var details:Dictionary={}
    for mi in nodes:
        details[String(mi.name)]=mi
        var mesh:Mesh=mi.mesh
        check(mesh!=null and mesh.get_surface_count()==1,String(mi.name)+" valid surface")
        var arrays:Array=mesh.surface_get_arrays(0)
        var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
        var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
        var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
        check(verts.size()>80 and indices.size()%3==0 and indices.size()>100,
            String(mi.name)+" real triangles instead of featureless placeholder")
        check(mesh.get_blend_shape_count()==10,String(mi.name)+" 10 real authored body morphs")
        check(mi.skin==visual._skin_copy,String(mi.name)+" bound to real actor-specific Skin")
        check(not mi.visible,String(mi.name)+" is hidden in default closed shoes")
        var bad_bones:=0
        var max_weight_error:=0.0
        var left:=0
        var right:=0
        for i in verts.size():
            var side:int=10 if verts[i].x>0.0 else 16
            if verts[i].x>0.0:left+=1
            else:right+=1
            if bones[i*4]!=side:bad_bones+=1
            var total:=0.0
            for j in 4:total+=weights[i*4+j]
            max_weight_error=maxf(max_weight_error,absf(total-1.0))
        check(bad_bones==0 and max_weight_error<.00001,
            String(mi.name)+" never skinned to hand, arm or opposite foot")
        check(left==right and left>0,String(mi.name)+" both feet share a symmetric topology")
        var collapsed:=0
        for i in range(0,indices.size(),3):
            var a:int=indices[i];var b:int=indices[i+1];var c:int=indices[i+2]
            if a<0 or b<0 or c<0 or a>=verts.size() or b>=verts.size() or c>=verts.size():
                collapsed+=1
                continue
            if (verts[b]-verts[a]).cross(verts[c]-verts[a]).length_squared()<1e-14:
                collapsed+=1
        check(collapsed==0,String(mi.name)+" no collapsed or out-of-bounds faces")
        var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
        var winding_bad:=0
        for i in range(0,indices.size(),3):
            var ia:int=indices[i]
            var ib:int=indices[i+1]
            var ic:int=indices[i+2]
            var fn:Vector3=(verts[ib]-verts[ia]).cross(verts[ic]-verts[ia]).normalized()
            var vn:Vector3=(normals[ia]+normals[ib]+normals[ic]).normalized()
            if fn.dot(vn)<0.05:
                winding_bad+=1
        check(winding_bad==0,String(mi.name)+" all visible triangles face the correct direction")
    check(details.has("Anatomy_foot_skin") and details.has("Anatomy_foot_nails"),
        "skin and nail surfaces both present")
    var d:Dictionary=CD.create().to_dict()
    d["clothing"]["bezne"]["shoes"]="bosy"
    preview.show_draft(d)
    check(visual._foot_detail_nodes.all(func(mi):return mi.visible),
        "bare feet are visible when shoes = bosy")
    var base_skin_color:Color=visual._foot_skin_material.albedo_color
    d["skin"]["tone"]=0.93
    d["body"]["shoulders"]=1.0
    d["body"]["hips"]=1.0
    preview.show_draft(d)
    check(visual._foot_skin_material.albedo_color!=base_skin_color,
        "feet follow continuous skin pigmentation")
    check(visual._foot_nail_material.albedo_color!=visual._foot_skin_material.albedo_color,
        "toe nail plates have independent enamel shading")
    check(visual._foot_detail_nodes[0].get_blend_shape_value(9)!=0.0,
        "feet inherit actual authored hips morph")
    d["clothing"]["bezne"]["shoes"]="goth_platformy"
    preview.show_draft(d)
    check(visual._foot_detail_nodes.all(func(mi):return not mi.visible),
        "changing to platform shoes hides both feet and nails (no shoe clipping)")
    d["clothing"]["bezne"]["shoes"]="bosy"
    preview.show_draft(d)
    check(visual._foot_detail_nodes.all(func(mi):return mi.visible),
        "returning to barefoot reveals same mesh instances")
    var foot_before:Node=visual._foot_detail_nodes[0]
    d["skin"]["tone"]=0.15
    preview.show_draft(d)
    check(visual._foot_detail_nodes[0]==foot_before,
        "repeated appearance updates reuse cached topology, not extra meshes")
    var sk:Skeleton3D=visual._skeleton()
    var l:int=sk.find_bone("foot_l")
    var r:int=sk.find_bone("foot_r")
    check(l>=0 and r>=0,"both feet attached to independent rig bones")
    var before_l:Transform3D=sk.get_bone_global_pose(l)
    var before_r:Transform3D=sk.get_bone_global_pose(r)
    sk.set_bone_pose_rotation(sk.find_bone("shin_l"),Quaternion(Vector3.RIGHT,PI/3))
    sk.force_update_all_bone_transforms()
    check(not sk.get_bone_global_pose(l).is_equal_approx(before_l),
        "bare toes follow independent left shin animation")
    check(sk.get_bone_global_pose(r).is_equal_approx(before_r),
        "right foot remains unchanged on left shin animation")
    sk.reset_bone_poses()
    sk.force_update_all_bone_transforms()
    if DisplayServer.get_name()!="headless":
        var args:=OS.get_cmdline_user_args()
        var run_id:String=String(args[0]) if args.size()==1 else ""
        check(G.owns(run_id),"render output requires own cooperative lease")
        if not G.owns(run_id):
            quit(3)
            return
        d["body"]["shoulders"]=0.5
        d["body"]["hips"]=0.5
        d["skin"]["tone"]=0.4
        preview.show_draft(d)
        preview.viewport.size=Vector2i(720,540)
        preview.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        preview.camera.size=.46
        preview.camera.position=Vector3(0,.14,2.8)
        preview.camera.look_at(Vector3(0,.14,0))
        for state in ["bare","shod"]:
            d["clothing"]["bezne"]["shoes"]="bosy" if state=="bare" else "tenisky"
            preview.show_draft(d)
            preview.camera.size=.46
            preview.camera.position=Vector3(0,.14,2.8)
            preview.camera.look_at(Vector3(0,.14,0))
            for i in 8:await process_frame
            await RenderingServer.frame_post_draw
            var file:String="res://previews/"+run_id+"-feet-"+state+".jpg"
            check(preview.viewport.get_texture().get_image().save_jpg(file,.90)==OK,
                "captured real rendered "+state+" feet")
            if state=="bare":
                preview.camera.position=Vector3(.22,.55,1.1)
                preview.camera.look_at(Vector3(0,.04,.07))
                for i in 8:await process_frame
                await RenderingServer.frame_post_draw
                var overhead:String="res://previews/"+run_id+"-feet-oblique.jpg"
                check(preview.viewport.get_texture().get_image().save_jpg(overhead,.90)==OK,
                    "captured real 3/4 perspective of all ten toes")
    preview.queue_free()
    await process_frame
    print("BAREFOOT_DETAIL_RESULT checks=",checks," failures=",failures)
    quit(0 if failures==0 else 1)