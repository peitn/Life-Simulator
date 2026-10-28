extends SceneTree
const G = preload("res://tools/automation_lock.gd")

func own(root_node: Node,node: Node) -> void:
	for child in node.get_children():
		child.owner=root_node
		own(root_node,child)

func model(asset: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file("res://assets/city/"+asset+".glb",state)!=OK: return null
	return doc.generate_scene(state)

func box(parent: Node,name_: String,size_: Vector3,center: Vector3,animated:=false) -> CollisionObject3D:
	var body: CollisionObject3D = AnimatableBody3D.new() if animated else StaticBody3D.new()
	body.name=name_; body.collision_layer=1; body.collision_mask=3
	if animated: body.sync_to_physics=false
	parent.add_child(body)
	var col := CollisionShape3D.new(); col.name="LeafCollider" if animated else "SolidCollider"
	var shape := BoxShape3D.new(); shape.size=size_; col.shape=shape; col.position=center
	body.add_child(col)
	return body

func save_module(node: Node3D,name_: String,run_id: String) -> void:
	own(node,node)
	var packed := PackedScene.new(); assert(packed.pack(node)==OK)
	assert(G.owns(run_id))
	assert(ResourceSaver.save(packed,"res://scenes/city/"+name_+".tscn")==OK)
	node.free()
	print("M1_SAVED ",name_)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]): quit(2); return
	var run_id: String=args[0]
	for item in [["foundation_2m",Vector3(2,.5,2),Vector3(1,-.25,-1)],["roof_flat_2m",Vector3(2,.15,2),Vector3(1,.075,-1)]]:
		var node := Node3D.new(); node.name=item[0]
		var imported=model(item[0]); assert(imported!=null); node.add_child(imported)
		box(node,"Collision",item[1],item[2])
		for point in [["FrontLeft",Vector3.ZERO],["FrontRight",Vector3(2,0,0)],["RearLeft",Vector3(0,0,-2)],["RearRight",Vector3(2,0,-2)]]:
			var marker := Marker3D.new(); marker.name=point[0]; marker.position=point[1]; node.add_child(marker)
		save_module(node,item[0],run_id)
	var door := Node3D.new(); door.name="DoorHinged1m"
	door.set_script(load("res://scripts/city/m1_door.gd"))
	var frame=load("res://scenes/city/wall_doorway_2m.scn").instantiate()
	# Flatten the reused frame before repacking ownership; retaining its scene
	# path while re-owning its children creates duplicate instance overrides.
	frame.scene_file_path=""; frame.name="Frame"; door.add_child(frame)
	var hinge := Node3D.new(); hinge.name="Hinge"; hinge.position=Vector3(.53,.02,0); door.add_child(hinge)
	var body=box(hinge,"LeafBody",Vector3(.96,2.06,.045),Vector3(.48,1.03,0),true)
	var leaf=model("door_leaf_1m"); assert(leaf!=null); body.add_child(leaf)
	for point in [["InteractFront",Vector3(1,1,.65)],["InteractBack",Vector3(1,1,-.65)]]:
		var marker := Marker3D.new(); marker.name=point[0]; marker.position=point[1]; door.add_child(marker)
	save_module(door,"door_hinged_1m",run_id)
	quit()
