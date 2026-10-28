extends SceneTree
## Full authored C5 wardrobe integrity: inventory, skin, normals, UVs, morph
## and non-degenerate triangles. No visual watertightness certification.
const Schema := preload("res://scripts/character/character_schema.gd")
const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")

var checks := 0
var failures := []
var inspected := 0
var vertices_inspected := 0
var triangles_inspected := 0
var degenerates := 0
var worst_normal_error := 0.0
var worst_weight_error := 0.0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        print("FAIL "+label)

func _init() -> void:
    call_deferred("run")

func _valid_float(x: float) -> bool:
    return is_finite(x)

func run() -> void:
    var inventories := [
        ["top", Schema.TOPS, ["zadne"]],
        ["bottom", Schema.BOTTOMS, ["zadne"]],
        ["shoes", Schema.SHOES, ["bosy"]]
    ]
    for entry in inventories:
        var kind: String = entry[0]
        var names: Dictionary = entry[1]
        var exempt: Array = entry[2]
        for name in names:
            var pieces: Array = Wardrobe.parts(kind,name)
            check((pieces.is_empty() and name in exempt) or
                (not pieces.is_empty() and name not in exempt),
                "catalog material coverage "+kind+"/"+String(name))
            if name not in exempt:
                _inspect_parts(kind+"/"+String(name),pieces)
    for extra in [["dress","saty"],["legs","skin"]]:
        var pieces := Wardrobe.parts(extra[0],extra[1])
        check(not pieces.is_empty(),"extra layer "+String(extra[0])+"/"+String(extra[1]))
        _inspect_parts(String(extra[0])+"/"+String(extra[1]),pieces)
    # Every outfit is composable independently of any gender/body labels.
    var composition := 0
    for top in Schema.TOPS:
        for bottom in Schema.BOTTOMS:
            for shoes in Schema.SHOES:
                var lp := {"outfit_top":top,"outfit_bottom":bottom,"outfit_shoes":shoes}
                var parts: Array = Wardrobe.active_parts(lp)
                check(parts.is_empty() if top=="zadne" and bottom=="zadne" and shoes=="bosy" else not parts.is_empty(), "intentional nude or nonempty outfit "+top+"/"+bottom+"/"+shoes)
                composition += 1
    print("GARMENT_INTEGRITY inventory=",inspected," vertices=",vertices_inspected,
        " triangles=",triangles_inspected," degenerate=",degenerates,
        " largest_weight_error=",worst_weight_error,
        " largest_normal_error=",worst_normal_error,
        " outfit_combinations=",composition,
        " checks=",checks," failed=",failures.size())
    for issue in failures.slice(0,35):
        print("INTEGRITY_ISSUE ",issue)
    quit(0 if failures.is_empty() else 1)

func _inspect_parts(label: String, pieces: Array) -> void:
    for part in pieces:
        inspected += 1
        var part_name: String = label+"/"+String(part["name"])
        var mesh: Mesh = part.get("mesh")
        check(mesh != null and mesh.get_surface_count()==1,part_name+" has exactly one surface")
        if mesh == null or mesh.get_surface_count()!=1:
            continue
        var arr: Array = mesh.surface_get_arrays(0)
        var positions: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
        var texcoords: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
        var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
        var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
        var n := positions.size()
        check(n>=3 and normals.size()==n and texcoords.size()==n and
            indices.size()%3==0 and indices.size()>=3, part_name+" complete geometry")
        if n<3 or normals.size()!=n or indices.size()%3!=0 or indices.size()<3:
            continue
        vertices_inspected += n
        triangles_inspected += indices.size()/3
        var finite_geometry := true
        for i in n:
            var point: Vector3 = positions[i]
            var normal: Vector3 = normals[i]
            if not point.is_finite() or not normal.is_finite():
                finite_geometry=false
                break
            var l: float = normal.length()
            if l<0.01:
                finite_geometry=false
                break
            worst_normal_error=maxf(worst_normal_error,absf(l-1.0))
            if absf(point.x)>4 or absf(point.y)>4 or absf(point.z)>4:
                finite_geometry=false
                break
        check(finite_geometry,part_name+" finite normals & bounded vertices")
        var bone_ok: bool = (bones.size() == n * 4 and weights.size()==bones.size())
        var bad_weight := false
        if bone_ok:
            for i in n:
                var total := 0.0
                for j in 4:
                    var bone: int = bones[i*4+j]
                    var weight: float = weights[i*4+j]
                    if not is_finite(weight) or weight<0.0 or weight>1.001 or bone<0 or bone>16:
                        bad_weight=true
                        break
                    total += weight
                worst_weight_error=maxf(worst_weight_error,absf(total-1.0))
                if absf(total-1.0)>0.012:
                    bad_weight=true
                    break
        check(bone_ok and not bad_weight,part_name+" normalized 17-bone skin influences")
        var geometry_ok := true
        var triangle_degenerate := 0
        for tri in range(0, indices.size(),3):
            var a:int=indices[tri]
            var b:int=indices[tri+1]
            var c:int=indices[tri+2]
            if a<0 or b<0 or c<0 or a>=n or b>=n or c>=n:
                geometry_ok=false
                break
            var area_sq := (positions[b]-positions[a]).cross(positions[c]-positions[a]).length_squared()
            if area_sq<0.000000000001:
                triangle_degenerate+=1
        degenerates+=triangle_degenerate
        check(geometry_ok,part_name+" triangle indices stay in bounds")
        check(triangle_degenerate==0,part_name+" no collapsed rest triangles ("+str(triangle_degenerate)+")")
        check(mesh.get_blend_shape_count()==10,part_name+" ten authored body shape keys")
        var targets: Array=mesh.surface_get_blend_shape_arrays(0)
        check(targets.size()==10,part_name+" ten stored morph arrays")
        var morph_ok := true
        for target in targets:
            var mv: PackedVector3Array = target[Mesh.ARRAY_VERTEX]
            var mn: PackedVector3Array = target[Mesh.ARRAY_NORMAL]
            if mv.size()!=n or (mn.size()!=n and not mn.is_empty()):
                morph_ok=false
                break
            for v in mv:
                if not v.is_finite():
                    morph_ok=false
                    break
            if not morph_ok:
                break
        check(morph_ok,part_name+" finite compatible morph targets")
        if part.get("name")=="waist_chain":
            var again: Array=mesh.surface_get_arrays(0)
            var positions_before: PackedVector3Array=again[Mesh.ARRAY_VERTEX].duplicate()
            var copied_targets: Array=mesh.surface_get_blend_shape_arrays(0)
            Wardrobe._repair_legacy_waist_chain(again,copied_targets)
            check(again[Mesh.ARRAY_VERTEX]==positions_before,
                part_name+" correction is idempotent and prevents vertex drift")
