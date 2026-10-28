extends SceneTree
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const G=preload("res://tools/automation_lock.gd")
var failures=0
func check(ok,label):
    print("PASS " if ok else "FAIL ",label)
    if not ok: failures+=1
func distance_triangle(p:Vector3,a:Vector3,b:Vector3,c:Vector3)->float:
    var ab=b-a
    var ac=c-a
    var normal=ab.cross(ac)
    if normal.length_squared()>1e-16:
        var q=p-normal*((p-a).dot(normal)/normal.length_squared())
        var d00=ab.dot(ab)
        var d01=ab.dot(ac)
        var d11=ac.dot(ac)
        var v=q-a
        var denom=d00*d11-d01*d01
        if absf(denom)>1e-16:
            var u=(d11*v.dot(ab)-d01*v.dot(ac))/denom
            var w=(d00*v.dot(ac)-d01*v.dot(ab))/denom
            if u>=0 and w>=0 and u+w<=1:
                return p.distance_to(q)
    var best=INF
    for edge in [[a,b],[b,c],[c,a]]:
        var d=edge[1]-edge[0]
        var t=clampf((p-edge[0]).dot(d)/d.length_squared(),0,1) if d.length_squared()>1e-16 else 0.0
        best=minf(best,p.distance_to(edge[0]+d*t))
    return best
func _init():call_deferred("run")
func run():
    root.get_node("GameSettings").persist=false
    check(is_equal_approx(distance_triangle(Vector3(.25,.25,2),Vector3.ZERO,Vector3.RIGHT,Vector3.UP),2.0),"triangle interior analytic")
    check(is_equal_approx(distance_triangle(Vector3(2,0,0),Vector3.ZERO,Vector3.RIGHT,Vector3.UP),1.0),"triangle exterior analytic")
    check(is_equal_approx(distance_triangle(Vector3(0,2,0),Vector3.ZERO,Vector3.RIGHT,Vector3.RIGHT),2.0),"degenerate edge analytic")
    check(is_equal_approx(distance_triangle(Vector3(0,2,0),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),2.0),"collapsed triangle analytic")
    var p=Preview.new()
    root.add_child(p)
    var d=CD.create().to_dict()
    d.clothing.bezne.top="kawaii_kocici_mikina"
    p.show_draft(d)
    var v=p.visual
    var sk=v._skeleton()
    for a in v.find_children("*","AnimationPlayer",true,false): a.stop()
    var meshes={}
    for m in v._c5_nodes: meshes[String(m.name).trim_prefix("C5_top_")]=m
    check(meshes.has("shell") and meshes.has("sleeve_-1") and meshes.has("sleeve_1"),"required meshes")
    if failures:quit(1);return
    var shell=meshes.shell
    var indices=shell.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
    for angle in [0.0,-PI/2]:
        sk.reset_bone_poses()
        for name in ["forearm_l","forearm_r"]:
            var bone=sk.find_bone(name)
            check(bone>=0,"bone "+name)
            if bone<0:quit(1);return
            sk.set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT,angle))
        sk.force_update_all_bone_transforms()
        if angle==0:
            var worst=0.0
            for j in shell.skin.get_bind_count():
                var name=String(shell.skin.get_bind_name(j))
                var bi=sk.find_bone(name) if name!="" else shell.skin.get_bind_bone(j)
                var xf=sk.get_bone_global_pose(bi)*shell.skin.get_bind_pose(j)
                worst=maxf(worst,xf.origin.length())
                for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
                    worst=maxf(worst,(xf.basis*axis-axis).length())
            print("REST_BIND_IDENTITY_MAX_ERROR=",worst)
            check(worst<.0001,"actual stored binds already inverse rest")
        var sv=_skinned(v,shell)
        for side in ["sleeve_-1","sleeve_1"]:
            var m=meshes[side]
            var original=m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
            var posed=_skinned(v,m)
            var ymax=-INF
            for point in original:ymax=maxf(ymax,point.y)
            var gaps=[]
            for j in original.size():
                if original[j].y<ymax-.001:continue
                var best=INF
                for k in range(0,indices.size(),3):
                    best=minf(best,distance_triangle(posed[j],sv[indices[k]],sv[indices[k+1]],sv[indices[k+2]]))
                gaps.append(best)
            gaps.sort()
            check(gaps.size()==14,"authored upper rim count "+side)
            # True skinned point-to-triangle proximity, not just nearest vertices.
            # These bounds describe the corrected upper-ring surface in actual
            # idle and 90-degree elbow-bend poses. They reject the old 21mm
            # median rest gap without claiming a watertight seam.
            var median_limit:float=.003
            var max_limit:float=.004
            check(gaps[gaps.size()/2]<median_limit,"corrected triangle median seam "+side+" pose "+str(angle))
            check(gaps.back()<max_limit,"corrected triangle worst seam "+side+" pose "+str(angle))
            print("METRIC angle=",angle," side=",side," min=",gaps.front()," median=",gaps[gaps.size()/2]," max=",gaps.back())
        if DisplayServer.get_name()!="headless":
            var args=OS.get_cmdline_user_args()
            if args.size()!=1 or not G.owns(args[0]):quit(2);return
            p.viewport.size=Vector2i(480,480)
            p.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
            p.camera.size=1.1
            p.camera.position=Vector3(0,1.2,4)
            p.camera.look_at(Vector3(0,1.2,0))
            for i in 8:await process_frame
            await RenderingServer.frame_post_draw
            var path="res://previews/"+args[0]+"-sleeve-"+("rest" if angle==0 else "bent")+".jpg"
            if not G.owns(args[0]) or FileAccess.file_exists(path):quit(2);return
            check(p.viewport.get_texture().get_image().save_jpg(path,.85)==OK,"capture "+path)
    p.queue_free()
    await process_frame
    print("TRIANGLE_DIAGNOSTIC failures=",failures)
    quit(0 if failures==0 else 1)

func _skinned(v: Node3D, mi: MeshInstance3D) -> PackedVector3Array:
    var m: ArrayMesh = mi.mesh
    var arr := m.surface_get_arrays(0)
    var verts: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
    var bl := m.surface_get_blend_shape_arrays(0)
    for i in m.get_blend_shape_count():
        var wv: float = mi.get_blend_shape_value(i)
        if wv == 0.0:
            continue
        var tv: PackedVector3Array = bl[i][Mesh.ARRAY_VERTEX]
        var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
        for j in verts.size():
            verts[j] += (tv[j] - base[j]) * wv
    var skel: Skeleton3D = v._skeleton()
    var skin: Skin = mi.skin
    # Indexy kostí ve vrcholech po importu GLB odkazují na BIND (kloub skinu), ne přímo na kost kostry.
    var xf_of := {}
    for j in skin.get_bind_count():
        var bname := String(skin.get_bind_name(j))
        var bi := skel.find_bone(bname) if bname != "" else skin.get_bind_bone(j)
        xf_of[j] = skel.get_bone_global_pose(bi) * skin.get_bind_pose(j)
    var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
    var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
    var per := bones.size() / verts.size()
    var model_xf := Transform3D(Basis.from_scale(v._model.scale), v._model.position)
    var out := PackedVector3Array()
    out.resize(verts.size())
    for j in verts.size():
        var acc := Vector3.ZERO
        for k in per:
            var wk := wts[j * per + k]
            if wk <= 0.0:
                continue
            var b := bones[j * per + k]
            acc += ((xf_of[b] as Transform3D) * verts[j]) * wk
        out[j] = model_xf * acc
    return out
