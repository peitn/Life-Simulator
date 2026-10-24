extends SceneTree
var expected_hashes={}
func _init():
	var G=load("res://tools/automation_lock.gd")
	var id=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	if not G.owns(id):
		print("OWNERSHIP_LOST")
		quit(1)
		return
	var args=OS.get_cmdline_user_args()
	if args.size()==3:
		expected_hashes={"res://scenes/city/wall_solid_2m.scn":args[1],"res://scenes/city/wall_snap_demo.scn":args[2]}
	for path in ["res://scenes/city/wall_solid_2m.scn","res://scenes/city/wall_snap_demo.scn"]:
		if not unchanged(path):
			print("OUTPUT_EXISTS ",path)
			quit(1)
			return
	# Resolve required dependencies before either output can be replaced.
	var door_path="res://scenes/city/wall_doorway_2m.scn"
	if not ResourceLoader.exists(door_path):
		print("INVALID_DOORWAY_DEPENDENCY")
		quit(1)
		return
	var door_scene=load(door_path)
	if not door_scene is PackedScene or not door_scene.can_instantiate():
		print("INVALID_DOORWAY_DEPENDENCY")
		quit(1)
		return
	var doc=GLTFDocument.new()
	var state=GLTFState.new()
	if doc.append_from_buffer(FileAccess.get_file_as_bytes("res://assets/city/wall_solid_2m.glb"),"res://assets/city/",state)!=OK:
		quit(1)
		return
	var model=doc.generate_scene(state)
	if not model is Node3D:
		if model!=null: model.free()
		quit(1)
		return
	var body=StaticBody3D.new()
	model.add_child(body)
	var collider=CollisionShape3D.new()
	collider.shape=BoxShape3D.new()
	collider.shape.size=Vector3(2,2.8,.2)
	collider.position=Vector3(1,1.4,0)
	body.add_child(collider)
	assign_owners(model,model)
	var packed=PackedScene.new()
	if packed.pack(model)!=OK or not G.owns(id) or not unchanged("res://scenes/city/wall_solid_2m.scn"):
		model.free()
		quit(1)
		return
	var door=door_scene.instantiate()
	if not door is Node3D:
		if door!=null: door.free()
		model.free()
		print("INVALID_DOORWAY_ROOT")
		quit(1)
		return
	if ResourceSaver.save(packed,"res://scenes/city/wall_solid_2m.scn")!=OK:
		door.free()
		model.free()
		quit(1)
		return
	var demo=Node3D.new()
	demo.name="WallSnapDemo"
	demo.add_child(model)
	model.name="SolidLeft"
	demo.add_child(door)
	door.position.x=2
	var right=packed.instantiate()
	demo.add_child(right)
	right.name="SolidRight"
	right.position.x=4
	var materials={}
	for mesh in demo.find_children("*","MeshInstance3D",true,false):
		for si in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(si)
			if mat==null: continue
			var key=mat.resource_name
			if not materials.has(key): materials[key]=mat
			mesh.set_surface_override_material(si,materials[key])
	print("SHARED_MATERIAL_NAMES=",materials.keys())
	assign_owners(demo,demo)
	var demo_packed=PackedScene.new()
	if demo_packed.pack(demo)!=OK or not G.owns(id) or not unchanged("res://scenes/city/wall_snap_demo.scn"):
		demo.free()
		quit(1)
		return
	var result=ResourceSaver.save(demo_packed,"res://scenes/city/wall_snap_demo.scn")
	demo.free()
	print("SAVE_DEMO=",result)
	print(G.heartbeat(id))
	quit(0 if result==OK else 1)
func unchanged(path):
	if expected_hashes.has(path):
		return FileAccess.file_exists(path) and FileAccess.get_sha256(path)==expected_hashes[path]
	return not FileAccess.file_exists(path)
func assign_owners(node,owner_root):
	# Flatten loaded instances before owning descendants; otherwise packing saves
	# the instance plus separately-owned copies of its children.
	node.scene_file_path=""
	for child in node.get_children():
		child.owner=owner_root
		assign_owners(child,owner_root)
