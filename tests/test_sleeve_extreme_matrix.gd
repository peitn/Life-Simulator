extends SceneTree
## Character sleeve matrix: real world-space skinning for both arms, edited
## body morph extremes and all 11 authored long-sleeve Blender C5 styles. No screenshots implied.
const Preview := preload("res://scripts/ui/character_preview.gd")
const CD := preload("res://scripts/character/character_data.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
    print("PASS " if ok else "FAIL ",label)
func _init() -> void:
    call_deferred("run")
func run() -> void:
    var preview := Preview.new()
    root.add_child(preview)
    var cases := [
        {"id":"default","body":{},"face":{},"skin":0.45},
        {"id":"lean_min","body":{"frame":0.0,"muscle":0.0,"body_fat":0.0,"shoulders":0.0,"chest":0.0,"bust":0.0,"waist":0.0,"hips":0.0,"leg_length":0.0,"head_size":-1.0,"neck_length":-1.0},"face":{"head_width":-1.0,"cheekbones":-1.0,"nose_length":-1.0},"skin":0.0},
        {"id":"full_max","body":{"frame":1.0,"muscle":1.0,"body_fat":1.0,"shoulders":1.0,"chest":1.0,"bust":1.0,"waist":1.0,"hips":1.0,"leg_length":1.0,"head_size":1.0,"neck_length":1.0},"face":{"head_width":1.0,"cheekbones":1.0,"nose_length":1.0},"skin":1.0},
        {"id":"broad_mixed","body":{"frame":1.0,"muscle":0.0,"body_fat":1.0,"shoulders":0.0,"chest":1.0,"bust":0.0,"waist":1.0,"hips":0.0,"leg_length":0.0,"head_size":1.0,"neck_length":-1.0},"face":{"head_width":-1.0,"cheekbones":1.0,"nose_length":1.0},"skin":0.88},
        {"id":"muscular_mixed","body":{"frame":0.0,"muscle":1.0,"body_fat":0.0,"shoulders":1.0,"chest":0.0,"bust":1.0,"waist":0.0,"hips":1.0,"leg_length":1.0,"head_size":-1.0,"neck_length":1.0},"face":{"head_width":1.0,"cheekbones":-1.0,"nose_length":-1.0},"skin":0.14}
    ]
    var tested := 0
    var worst_max := 0.0
    var worst_median := 0.0
    for case in cases:
        var d: Dictionary = CD.create().to_dict()
        d["identity"]["first_name"] = "Nora"
        d["personality"]["traits"] = ["optimista"]
        for section in ["body","face"]:
            for field in case[section]:
                d[section][field] = case[section][field]
        d["skin"]["tone"] = case["skin"]
        for style in ["mikina","kawaii_kocici_mikina","svetr","rolak","sako","kosile","emo_mikina","kawaii_svetr","harajuku_bunda","grunge_kosile","visualkei_sako"]:
            d["clothing"]["bezne"]["top"] = style
            var parsed: Dictionary = Validator.validate(d, {"mode":"strict","mental_health":"full"})
            check(parsed.get("ok", false), str(case.id)+"/"+style+" strict-valid adult appearance")
            if not parsed.get("ok", false):
                continue
            preview.show_draft(parsed["data"])
            var v: Node3D = preview.visual
            var sk: Skeleton3D = v._skeleton()
            var meshes := {}
            for m in v._c5_nodes:
                if String(m.name) in ["C5_top_shell", "C5_top_sleeve_-1", "C5_top_sleeve_1"]:
                    meshes[String(m.name)] = m
            check(meshes.size()==3, str(case.id)+"/"+style+" canonical C5 meshes present")
            if meshes.size()!=3:
                continue
            var shell: MeshInstance3D = meshes["C5_top_shell"]
            var indices: PackedInt32Array = shell.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
            for pose in [
                {"name":"idle","elbow":0.0,"raise":0.0},
                {"name":"elbow90","elbow":-PI/2.0,"raise":0.0},
                {"name":"raise60","elbow":0.0,"raise":PI/3.0},
                {"name":"raise60_elbow90","elbow":-PI/2.0,"raise":PI/3.0}
            ]:
                sk.reset_bone_poses()
                for arm in ["l","r"]:
                    sk.set_bone_pose_rotation(sk.find_bone("upper_arm_"+arm),
                        Quaternion(Vector3.FORWARD, float(pose["raise"]) * (1.0 if arm=="l" else -1.0)))
                    sk.set_bone_pose_rotation(sk.find_bone("forearm_"+arm),
                        Quaternion(Vector3.RIGHT,float(pose["elbow"])))
                sk.force_update_all_bone_transforms()
                var shell_vertices: PackedVector3Array = _skinned(v,shell)
                for side in ["-1","1"]:
                    var sleeve: MeshInstance3D = meshes["C5_top_sleeve_"+side]
                    var ref: PackedVector3Array = sleeve.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
                    var posed: PackedVector3Array = _skinned(v,sleeve)
                    var upper_y := -INF
                    for point in ref:
                        upper_y = maxf(upper_y,point.y)
                    var distances := []
                    for vi in ref.size():
                        if ref[vi].y < upper_y - .001:
                            continue
                        var nearest := INF
                        for j in range(0,indices.size(),3):
                            nearest = minf(nearest,distance_triangle(posed[vi],
                                shell_vertices[indices[j]],shell_vertices[indices[j+1]],shell_vertices[indices[j+2]]))
                        distances.append(nearest)
                    distances.sort()
                    check(distances.size()==14, str(case.id)+"/"+style+"/"+side+" rim count")
                    if distances.size()!=14:
                        continue
                    var median: float = distances[distances.size()/2]
                    var maximum: float = distances.back()
                    worst_max = maxf(worst_max,maximum)
                    worst_median = maxf(worst_median,median)
                    print("EXTREME_SEAM profile=",case.id," style=",style," side=",side,
                        " pose=",pose["name"]," median_mm=",snappedf(median*1000,.01)," max_mm=",snappedf(maximum*1000,.01))
                    # Some extreme anatomies remain visibly imperfect, yet must
                    # not reintroduce a detached 45+ mm cuff or wrong-arm bind.
                    var raised: bool = float(pose["raise"]) > 0.0
                    check(median < (.035 if raised else .019) and maximum < (.052 if raised else .029),
                        str(case.id)+"/"+style+"/"+side+"/"+str(pose["name"])+" pose bounded gap")
                    tested += 1
    # Repeated loading must not mutate any public authored mesh.
    for name in ["mikina","kawaii_kocici_mikina","svetr","rolak","sako","kosile","emo_mikina","kawaii_svetr","harajuku_bunda","grunge_kosile","visualkei_sako"]:
        for entry in Wardrobe.parts("top",name):
            if not String(entry["name"]).begins_with("sleeve_"):
                continue
            var mesh: ArrayMesh = entry["mesh"]
            var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
            var blends: Array = mesh.surface_get_blend_shape_arrays(0)
            var new_arrays: Array = mesh.surface_get_arrays(0)
            Wardrobe._fit_legacy_sleeve(new_arrays,blends)
            check(new_arrays[Mesh.ARRAY_VERTEX]==vertices, name+"/"+str(entry["name"])+" migration not double applied")
    preview.queue_free()
    await process_frame
    print("SLEEVE_EXTREME_MATRIX tested=",tested," worst_median_mm=",worst_median*1000.0,
        " worst_max_mm=",worst_max*1000.0," pass=",passed," fail=",failed)
    quit(0 if failed==0 and tested==440 else 1)

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