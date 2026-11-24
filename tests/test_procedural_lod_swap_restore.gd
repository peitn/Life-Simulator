extends RefCounted
## Isolated SimVisual LOD2 swap/restore test, not procedural mesh or worker bake coverage.
const Visual = preload("res://scripts/sim/sim_visual.gd")

static func _mesh(morphed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if morphed:
		mesh.add_blend_shape("ex_smile")
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var shapes := []
	if morphed:
		var b := []
		b.resize(Mesh.ARRAY_MAX)
		b[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0.1, 0), Vector3(1, 0.1, 0), Vector3(0, 1.1, 0)])
		b[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		shapes.append(b)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, shapes)
	return mesh

static func run() -> Dictionary:
	var v := Visual.new()
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	var source := _mesh(true)
	var baked := _mesh(false)
	mi.mesh = source
	mi.set_blend_shape_value(0, 0.37)
	mi.transform.origin = Vector3(0.3, 1.2, -0.2)
	model.add_child(mi)
	v.add_child(model)
	v._model = model
	var pose := mi.transform
	var failures: Array[String] = []
	var checks := 0
	checks += 1
	if not v.set_lod_tier(2):
		failures.append("tier2 transition")
	checks += 1
	if not v._lod_swap(mi, source, PackedFloat32Array([0.37]), baked):
		failures.append("swap rejected")
	checks += 1
	if mi.mesh != baked or mi.get_blend_shape_count() != 0:
		failures.append("baked mesh not active")
	checks += 1
	if v.lod_baked_count() != 1 or v.lod_source_mesh(mi) != source:
		failures.append("baked source tracking")
	checks += 1
	if not v.set_lod_tier(0):
		failures.append("tier0 transition")
	checks += 1
	if mi.mesh != source or absf(mi.get_blend_shape_value(0) - 0.37) > 0.00001:
		failures.append("original mesh/morph not restored")
	checks += 1
	if mi.transform != pose or v.lod_baked_count() != 0:
		failures.append("pose or bake bookkeeping")
	v.free()
	return {"ok": failures.is_empty(), "checks": checks, "failures": failures}
