# Read-only source-vs-saved-scene geometry regression for the M1 corner.
# -- --inject-drift mutates an in-memory instance only; expected exit 1.
extends SceneTree
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("PASS " if ok else "FAIL ") + label)

func gather(node: Node) -> Dictionary:
	var found := {}
	for m in node.find_children("*", "MeshInstance3D", true, false):
		found[String(m.name)] = m
	return found

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var source_path := "res://assets/city/wall_corner_2m.glb"
	var scene_path := "res://scenes/city/wall_corner_2m.scn"
	check(FileAccess.file_exists(source_path), "authored GLB exists")
	check(ResourceLoader.exists(scene_path), "saved PackedScene exists")
	if failed > 0:
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var imported := doc.append_from_file(source_path, state)
	check(imported == OK, "GLB import succeeds")
	if imported != OK:
		quit(1)
		return
	var raw := doc.generate_scene(state)
	var packed := load(scene_path) as PackedScene
	check(raw is Node3D and packed != null, "both resources instantiate")
	if not raw is Node3D or packed == null:
		if raw != null:
			raw.free()
		quit(1)
		return
	var saved := packed.instantiate()
	check(saved is Node3D and saved.transform.is_equal_approx(Transform3D.IDENTITY), "saved root identity")
	var src := gather(raw)
	var dst := gather(saved)
	check(src.size() == 3 and dst.size() == 3, "three meshes in source and saved scene")
	if "--inject-drift" in OS.get_cmdline_user_args() and dst.has("corner_core"):
		dst["corner_core"].mesh = BoxMesh.new()
	var names := src.keys()
	names.sort()
	var triangles := 0
	for name in names:
		check(dst.has(name), "matching mesh " + name)
		if not dst.has(name):
			continue
		var a: MeshInstance3D = src[name]
		var b: MeshInstance3D = dst[name]
		check(a.transform.is_equal_approx(b.transform), "mesh transform " + name)
		check(a.mesh.get_surface_count() == b.mesh.get_surface_count(), "surface count " + name)
		if a.mesh.get_surface_count() != b.mesh.get_surface_count():
			continue
		for si in a.mesh.get_surface_count():
			var x := a.mesh.surface_get_arrays(si)
			var y := b.mesh.surface_get_arrays(si)
			for field in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
				check(x[field] == y[field], "exact imported geometry field " + str(field) + " " + name)
			var mx := a.mesh.surface_get_material(si) as BaseMaterial3D
			var my := b.mesh.surface_get_material(si) as BaseMaterial3D
			check(mx != null and my != null, "PBR material " + name)
			if mx != null and my != null:
				check(mx.albedo_color.is_equal_approx(my.albedo_color) and is_equal_approx(mx.roughness, my.roughness), "matching PBR parameters " + name)
			check(a.mesh.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES, "triangle primitive " + name)
			var indices = x[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array and not indices.is_empty():
				triangles += indices.size() / 3
			else:
				triangles += x[Mesh.ARRAY_VERTEX].size() / 3
	check(triangles == 492, "source triangle budget contract 492")
	print("CORNER_SOURCE_SCENE_RESULT=", passed, " passed ", failed, " failed")
	raw.free()
	saved.free()
	quit(0 if failed == 0 else 1)