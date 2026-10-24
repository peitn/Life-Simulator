extends SceneTree
# Reproducible builder; requires the active city run ID.
func own(root, node):
	node.scene_file_path=""
	for c in node.get_children():
		c.owner=root
		own(root,c)
func _init():
	var args=OS.get_cmdline_user_args()
	var G=load("res://tools/automation_lock.gd")
	if args.is_empty() or not G.owns(args[0]):quit(1);return
	var output="res://scenes/city/wall_corner_2m.scn"
	var previous_hash=FileAccess.get_sha256(output) if FileAccess.file_exists(output) else ""
	var gltf=GLTFDocument.new()
	var state=GLTFState.new()
	if gltf.append_from_file("res://assets/city/wall_corner_2m.glb",state)!=OK:quit(1);return
	var model=gltf.generate_scene(state)
	if not model is Node3D:quit(1);return
	var node=Node3D.new()
	node.name="WallCorner2m"
	node.add_child(model)
	var body=StaticBody3D.new()
	body.name="Collision"
	body.collision_layer=1
	body.collision_mask=1
	node.add_child(body)
	for spec in [[Vector3(.95,1.4,0),Vector3(2.1,2.8,.2)],[Vector3(0,1.4,-1.05),Vector3(.2,2.8,1.9)]]:
		var c=CollisionShape3D.new()
		c.shape=BoxShape3D.new()
		c.shape.size=spec[1]
		c.position=spec[0]
		body.add_child(c)
	own(node,node)
	var pack=PackedScene.new()
	if pack.pack(node)!=OK:node.free();quit(1);return
	var current_hash=FileAccess.get_sha256(output) if FileAccess.file_exists(output) else ""
	if not G.owns(args[0]) or current_hash!=previous_hash:node.free();quit(1);return
	if ResourceSaver.save(pack,"res://scenes/city/wall_corner_2m.scn")!=OK:node.free();quit(1);return
	node.free()
	print("CORNER_BUILD_OK")
	quit()
