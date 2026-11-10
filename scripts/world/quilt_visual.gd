extends RefCounted
## Lightweight draped quilts authored as a deterministic 12x16 patch.
## Material/color remains native Godot fabric; no dynamic CPU mesh swapping.
## Empty and occupied variants are cached as separate objects at world build.

static func _roof(u: float, v: float) -> float:
    var sx := pow(maxf(0.0, sin(PI * clampf(u,0.0,1.0))), 0.7)
    var sz := pow(maxf(0.0, sin(PI * clampf(v,0.0,1.0))), 0.7)
    var folds := 0.96 + 0.04 * sin(TAU * (2.7*v + 0.5*u))
    return 0.26 * sx * sz * folds


static func mesh(width: float, length: float, occupied: bool) -> ArrayMesh:
    const X := 12
    const Z := 16
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uv := PackedVector2Array()
    var index := PackedInt32Array()
    var f: float = 1.0 if occupied else 0.07
    for zi in Z + 1:
        var v := float(zi) / float(Z)
        for xi in X + 1:
            var u := float(xi) / float(X)
            var h := f * _roof(u,v)
            vertices.append(Vector3((u-0.5)*width,h,(v-0.5)*length))
            var eps := 0.005
            var dx := f * (_roof(u+eps,v)-_roof(u-eps,v))/(2.0*eps*width)
            var dz := f * (_roof(u,v+eps)-_roof(u,v-eps))/(2.0*eps*length)
            normals.append(Vector3(-dx,1.0,-dz).normalized())
            uv.append(Vector2(u,v))
    for zi in Z:
        for xi in X:
            var a := zi*(X+1)+xi
            var b := a+1
            var c := a+X+1
            var d := c+1
            index.append_array(PackedInt32Array([a,b,c,b,d,c]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    arrays[Mesh.ARRAY_NORMAL]=normals
    arrays[Mesh.ARRAY_TEX_UV]=uv
    arrays[Mesh.ARRAY_INDEX]=index
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return result


static func add_to_bed(bed: Node3D, width: float, length: float, material: StandardMaterial3D) -> void:
    material.cull_mode = BaseMaterial3D.CULL_BACK
    var flat := MeshInstance3D.new()
    flat.name = "DuvetCover"
    flat.mesh = mesh(width,length,false)
    flat.material_override = material
    flat.position = Vector3(0,0.64,0.40)
    bed.add_child(flat)
    var raised := MeshInstance3D.new()
    raised.name = "DuvetRaised"
    raised.mesh = mesh(width,length,true)
    raised.material_override = material
    raised.position = flat.position
    raised.visible = false
    bed.add_child(raised)
