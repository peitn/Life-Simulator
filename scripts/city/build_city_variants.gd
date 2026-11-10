extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
func imported(path:String) -> Node3D:
	var document:=GLTFDocument.new();var state:=GLTFState.new();assert(document.append_from_file(path,state)==OK)
	return document.generate_scene(state)
func _init() -> void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://docs/city/variants_manifest.json"))
	for kind in manifest.models:
		var d:Dictionary=manifest.models[kind];var path:String="res://"+d.glb;assert(FileAccess.get_sha256(path)==d.sha256)
		var node:Node3D
		if d.category=="window":
			node=Node3D.new();node.name=kind;var model:=imported(path);model.name="Model";node.add_child(model)
			var body:=StaticBody3D.new();body.name="Collision";body.collision_layer=1;body.collision_mask=3;node.add_child(body)
			for collider in d.colliders:
				var shape:=CollisionShape3D.new();shape.name=collider.name;var convex:=ConvexPolygonShape3D.new();var points:=PackedVector3Array()
				for point in collider.points:points.append(B.vec(point))
				convex.points=points;shape.shape=convex;body.add_child(shape)
			for item in [["Left",Vector3.ZERO],["Right",Vector3(2,0,0)]]:
				var marker:=Marker3D.new();marker.name=item[0];marker.position=item[1];node.add_child(marker)
		else:
			node=load("res://scenes/city/door_hinged_1m.tscn").instantiate();node.scene_file_path="";node.name=kind
			var body:Node3D=node.get_node("Hinge/LeafBody")
			for child in body.get_children():
				if not child is CollisionShape3D:body.remove_child(child);child.free()
			var model:=imported(path);model.name="Model";body.add_child(model)
		B.own(node,node);var packed:=PackedScene.new();assert(packed.pack(node)==OK)
		assert(G.owns(args[0]));assert(ResourceSaver.save(packed,"res://scenes/city/m2_"+kind+".tscn")==OK)
		node.free();print("VARIANT_BUILT ",kind)
	quit()
