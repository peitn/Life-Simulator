extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
func _init() -> void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	var run_id:String=args[0];var entries:Dictionary={}
	DirAccess.make_dir_recursive_absolute("res://assets/city/fixtures")
	for kind in B.Fixture.catalog().entries:
		var node:=B.build(kind);var packed:=PackedScene.new();assert(packed.pack(node)==OK)
		var scene_path:String="res://scenes/city/m2_"+kind+".tscn"
		assert(G.owns(run_id));assert(ResourceSaver.save(packed,scene_path)==OK)
		var gltf:=GLTFDocument.new();var state:=GLTFState.new()
		assert(gltf.append_from_scene(node.get_node("Model"),state)==OK)
		var path:String="res://assets/city/fixtures/"+kind+".glb"
		assert(G.owns(run_id));assert(gltf.write_to_filesystem(state,path)==OK)
		var a:=B.bounds(node);var tri:=0
		for m in node.find_children("*","MeshInstance3D",true,false):
			for i in m.mesh.get_surface_count():
				var arrays=m.mesh.surface_get_arrays(i);var indices=arrays[Mesh.ARRAY_INDEX]
				tri+=indices.size()/3 if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()/3
		assert(tri<3000)
		entries[kind]={"scene":scene_path,"glb":path,"sha256":FileAccess.get_sha256(path),"triangles":tri,"min":[a.position.x,a.position.y,a.position.z],"max":[a.end.x,a.end.y,a.end.z],"capacity":node.capacity,"tag":node.object_tag,"action":B.Fixture.catalog().entries[kind].action}
		node.free();print("FIXTURE_BUILT ",kind," tris=",tri)
	assert(G.owns(run_id))
	var file=FileAccess.open("res://docs/city/m2_fixtures_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"run_id":run_id,"entries":entries},"\t"));file.close()
	quit()
