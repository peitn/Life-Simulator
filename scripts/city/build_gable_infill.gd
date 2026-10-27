extends RefCounted
# Deterministic city M1 gable infill packer. Caller must own the v3 city lease.
static func own_descendants(scene_root: Node, node: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		own_descendants(scene_root, child)

static func build(run_id: String) -> Dictionary:
	var G = load("res://tools/automation_lock.gd")
	var source := "res://assets/city/gable_infill_2m.glb"
	var target := "res://scenes/city/gable_infill_2m.scn"
	if not G.owns(run_id):
		return {"ok":false,"reason":"city lease not owned"}
	var previous := FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""
	if not FileAccess.file_exists(source):
		return {"ok":false,"reason":"GLB missing"}
	if FileAccess.get_sha256(source) != "9fc3a6ceefebc9a54831e0aab50dd47dc3b6c4d950da5df867c3afc701fcf0fe":
		return {"ok":false,"reason":"source changed"}
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(source,state) != OK:
		return {"ok":false,"reason":"GLB import failed"}
	var model := doc.generate_scene(state)
	if not model is Node3D:
		if model != null: model.free()
		return {"ok":false,"reason":"invalid GLB root"}
	var root := Node3D.new()
	root.name = "GableInfill2m"
	root.add_child(model)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.size() != 1:
		root.free()
		return {"ok":false,"reason":"expected one gable prism"}
	for mesh_node in meshes:
		var m := mesh_node as MeshInstance3D
		if m.mesh == null or m.mesh.get_surface_count() != 1:
			root.free()
			return {"ok":false,"reason":"unexpected imported mesh hierarchy"}
		var to_model := Transform3D.IDENTITY
		var node: Node = m
		while node != model and node != null:
			if not node is Node3D:
				root.free()
				return {"ok":false,"reason":"nonspatial imported ancestor"}
			to_model = (node as Node3D).transform * to_model
			node = node.get_parent()
		if node != model:
			root.free()
			return {"ok":false,"reason":"mesh not under imported root"}
		var raw := m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var points := PackedVector3Array()
		for vertex in raw:
			var p: Vector3 = model.transform * to_model * vertex
			var exists := false
			for q in points:
				if p.distance_to(q) < 0.0001:
					exists = true
					break
			if not exists:
				points.append(p)
		if points.size() != 6:
			root.free()
			return {"ok":false,"reason":"expected 6 convex prism corners"}
		var col := CollisionShape3D.new()
		col.name = String(m.name) + "_collider"
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		col.shape = hull
		body.add_child(col)
	own_descendants(root,root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok":false,"reason":"pack failed"}
	var current := FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""
	if not G.owns(run_id) or current != previous:
		root.free()
		return {"ok":false,"reason":"lease lost or target changed"}
	var err := ResourceSaver.save(packed,target)
	root.free()
	if err != OK:
		return {"ok":false,"reason":"save failed","error":err}
	return {"ok":true,"sha256":FileAccess.get_sha256(target)}