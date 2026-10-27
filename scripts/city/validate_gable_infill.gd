extends SceneTree
# Read-only M1 triangular gable prototype source/GLB validator; no saved scene yet.
var passed := 0
var failed := 0
func check(ok:bool, label:String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("PASS " if ok else "FAIL ") + label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("res://assets/city/gable_infill_2m.glb",state)
	check(err == OK,"GLB parses via GLTFDocument")
	if err != OK: quit(1); return
	var inst := doc.generate_scene(state)
	check(inst is Node3D,"generated root Node3D")
	if not inst is Node3D: quit(1); return
	root.add_child(inst)
	var nodes:Array[Node] = [inst]
	var parts:Array[MeshInstance3D] = []
	while not nodes.is_empty():
		var n:Node = nodes.pop_back()
		if n is MeshInstance3D: parts.append(n)
		for child in n.get_children(): nodes.append(child)
	check(parts.size()==1,"exactly one mesh")
	var lo := Vector3(INF,INF,INF)
	var hi := Vector3(-INF,-INF,-INF)
	var tris := 0
	for part in parts:
		var mesh := part.mesh
		check(mesh != null,"mesh resource")
		if mesh == null: continue
		check(mesh.get_surface_count()==1,"one surface")
		for si in range(mesh.get_surface_count()):
			check(mesh.surface_get_primitive_type(si)==Mesh.PRIMITIVE_TRIANGLES,"triangle primitive")
			var arrays := mesh.surface_get_arrays(si)
			var verts:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv:PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx:PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += int(idx.size()/3) if idx.size()>0 else int(verts.size()/3)
			check(verts.size()>0 and uv.size()==verts.size(),"UV present")
			check(normals.size()==verts.size(),"normals present")
			var unit := true
			for normal in normals:
				if absf(normal.length()-1)>0.001: unit=false
			check(unit,"unit normals")
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			check(mat != null,"PBR material")
			if mat != null:
				check(absf(mat.roughness-.85)<.01,"plaster roughness")
				check(mat.albedo_color.is_equal_approx(Color(.64,.60,.52,1).linear_to_srgb()),"plaster albedo (glTF sRGB)")
			for v in verts:
				var world := part.global_transform*v
				lo=lo.min(world)
				hi=hi.max(world)
	check(tris==8,"8 triangles")
	if "--inject-shift" in OS.get_cmdline_user_args():
		lo.x += .1
		hi.x += .1
	check(lo.distance_to(Vector3(0,0,-.12))<.001,"bounds min")
	check(hi.distance_to(Vector3(2,.6,0))<.001,"bounds max")
	check(FileAccess.get_sha256("res://assets/city/gable_infill_2m.glb")=="9fc3a6ceefebc9a54831e0aab50dd47dc3b6c4d950da5df867c3afc701fcf0fe","source GLB SHA")
	inst.free()
	print("GABLE_INFILL_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)