extends RefCounted
# Reproducible M1 floor tile scene packer; caller owns city protocol-v3 lease.
static func own_descendants(root: Node, node: Node) -> void:
	for child in node.get_children():
		child.owner = root
		own_descendants(root,child)

static func build(run_id: String) -> Dictionary:
	var G = load("res://tools/automation_lock.gd")
	var source = "res://assets/city/floor_tile_2m.glb"
	var target = "res://scenes/city/floor_tile_2m.scn"
	if not G.owns(run_id):
		return {"ok":false,"reason":"city lease not owned"}
	var prior = FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""
	if not FileAccess.file_exists(source):
		return {"ok":false,"reason":"GLB missing"}
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	if doc.append_from_file(source,state) != OK:
		return {"ok":false,"reason":"GLB import failed"}
	var model = doc.generate_scene(state)
	if not model is Node3D:
		if model != null: model.free()
		return {"ok":false,"reason":"invalid GLB root"}
	var root = Node3D.new()
	root.name = "FloorTile2m"
	root.add_child(model)
	var body = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var shape = CollisionShape3D.new()
	shape.name = "FloorCollider"
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2,.2,2)
	shape.position = Vector3(1,-.1,-1)
	body.add_child(shape)
	own_descendants(root,root)
	var packed = PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok":false,"reason":"pack failed"}
	var now = FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""
	if not G.owns(run_id) or now != prior:
		root.free()
		return {"ok":false,"reason":"lease lost or target changed"}
	var result = ResourceSaver.save(packed,target)
	root.free()
	if result != OK:
		return {"ok":false,"reason":"save failed","error":result}
	return {"ok":true,"sha256":FileAccess.get_sha256(target)}
