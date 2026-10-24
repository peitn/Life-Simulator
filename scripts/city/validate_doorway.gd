# Read-only asset regression test: never rebuild or overwrite authored scenes.
# Run with: godot --headless --path <project> --script res://scripts/city/validate_doorway.gd
extends SceneTree
var passed = 0
var failed = 0
func check(value, label):
	if value:
		passed += 1
		print("PASS ",label)
	else:
		failed += 1
		print("FAIL ",label)
func _init():
	call_deferred("run")
func own_children(n, model):
	for c in n.get_children():
		c.owner = model
		own_children(c,model)
func run():
	var start = Time.get_ticks_usec()
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var bytes = FileAccess.get_file_as_bytes("res://assets/city/wall_doorway_2m.glb")
	var err = doc.append_from_buffer(bytes,"res://assets/city/",state)
	check(err == OK,"GLB buffer imported")
	if err != OK:
		quit(1)
		return
	var model = doc.generate_scene(state)
	root.add_child(model)
	var meshes = model.find_children("*","MeshInstance3D",true,false)
	check(meshes.size() == 13,"all 13 authored mesh parts imported")
	var bounds = AABB()
	var first = true
	var triangles = 0
	var uv_ok = true
	var normals_ok = true
	for mesh_node in meshes:
		var b = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
		for surface in mesh_node.mesh.get_surface_count():
			var arrays = mesh_node.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size()/3
			uv_ok = uv_ok and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size()
			for normal in arrays[Mesh.ARRAY_NORMAL]:
				normals_ok = normals_ok and normal.is_finite() and abs(normal.length()-1.0)<0.01
	check(bounds.size.is_equal_approx(Vector3(2,2.8,.26)),"meter dimensions and Y-up conversion")
	check(abs(bounds.position.x)<0.0001 and abs(bounds.position.y)<0.0001,"pivot at left endpoint and floor")
	check(triangles == 1404,"triangle count matches manifest")
	check(uv_ok,"UVs retained by GLB import")
	check(normals_ok,"finite unit normals")
	var body = StaticBody3D.new()
	body.name = "WallCollision"
	model.add_child(body)
	for spec in [[[.25,1.4,0],[.5,2.8,.2]],[[1.75,1.4,0],[.5,2.8,.2]],[[1,2.45,0],[1,.7,.2]]]:
		var shape = BoxShape3D.new()
		shape.size = Vector3(spec[1][0],spec[1][1],spec[1][2])
		var node = CollisionShape3D.new()
		node.shape = shape
		node.position = Vector3(spec[0][0],spec[0][1],spec[0][2])
		body.add_child(node)
	own_children(model,model)
	var packed = PackedScene.new()
	check(packed.pack(model)==OK,"pack standalone scene")
	check(FileAccess.file_exists("res://scenes/city/wall_doorway_2m.scn"),"authored standalone scene exists")
	print("IMPORT_AND_PACK_MS=",float(Time.get_ticks_usec()-start)/1000)
	await physics_frame
	await physics_frame
	var space = model.get_world_3d().direct_space_state
	for x in [.25,1.0,1.75]:
		var query = PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,1,1))
		var hit = space.intersect_ray(query)
		check(hit.is_empty() if x == 1.0 else not hit.is_empty(),"doorway ray x="+str(x))
	var header = PhysicsRayQueryParameters3D.create(Vector3(1,2.45,-1),Vector3(1,2.45,1))
	check(not space.intersect_ray(header).is_empty(),"lintel blocks above opening")
	var sphere = SphereShape3D.new()
	sphere.radius = .35
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = Vector3(1,1,0)
	check(space.intersect_shape(query).is_empty(),"70cm diameter body fits opening")
	model.queue_free()
	await process_frame
	var scene_resource = load("res://scenes/city/wall_doorway_2m.scn")
	if scene_resource == null or not scene_resource is PackedScene:
		check(false,"authored scene is a PackedScene")
	else:
		var reloaded = scene_resource.instantiate()
		root.add_child(reloaded)
		check(reloaded.transform.is_equal_approx(Transform3D.IDENTITY),"saved root has identity placement")
		var shapes = reloaded.find_children("*","CollisionShape3D",true,false)
		check(shapes.size()==3,"saved scene retains collisions")
		var specs = [AABB(Vector3(0,0,-.1),Vector3(.5,2.8,.2)), AABB(Vector3(1.5,0,-.1),Vector3(.5,2.8,.2)), AABB(Vector3(.5,2.1,-.1),Vector3(1,.7,.2))]
		for shape_node in shapes:
			check(not shape_node.disabled,"saved collision enabled")
			var parent_body = shape_node.get_parent()
			check(parent_body is StaticBody3D and parent_body.collision_layer == 1 and parent_body.collision_mask == 1,"saved environment collision layer/mask")
			var matching = -1
			if shape_node.shape is BoxShape3D and shape_node.get_parent() is StaticBody3D:
				var size = shape_node.shape.size
				var actual = shape_node.global_transform * AABB(-size/2,size)
				for i in specs.size():
					if actual.position.is_equal_approx(specs[i].position) and actual.size.is_equal_approx(specs[i].size):
						matching = i
			check(matching >= 0,"saved collision matches unique authored box")
			if matching >= 0:
				specs.remove_at(matching)
		check(specs.is_empty(),"all expected collision boxes present")
		await physics_frame
		await physics_frame
		var saved_space = reloaded.get_world_3d().direct_space_state
		for x in [.25,1.0,1.75]:
			var ray = PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,1,1))
			var hit = saved_space.intersect_ray(ray)
			check(hit.is_empty() if x == 1.0 else not hit.is_empty(),"saved scene doorway ray x="+str(x))
		check(not saved_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,2.45,-1),Vector3(1,2.45,1))).is_empty(),"saved scene lintel blocks")
		check(saved_space.intersect_shape(query).is_empty(),"saved scene 70cm clearance")
		reloaded.queue_free()
		await process_frame
	print("CITY_TEST_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed==0 else 1)
