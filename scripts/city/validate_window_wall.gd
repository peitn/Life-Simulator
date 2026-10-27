extends SceneTree
# Read-only M1 window GLB/saved-scene geometry, physics and snap regression.
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
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		found[String(mesh.name)] = mesh
	return found

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var glb_path := "res://assets/city/wall_window_2m.glb"
	var scene_path := "res://scenes/city/wall_window_2m.scn"
	check(FileAccess.file_exists(glb_path),"GLB exists")
	check(ResourceLoader.exists(scene_path),"saved scene exists")
	if failed > 0:
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var imported := doc.append_from_file(glb_path,state)
	check(imported == OK,"GLB import succeeds")
	if imported != OK:
		quit(1)
		return
	var raw := doc.generate_scene(state)
	var packed := load(scene_path) as PackedScene
	check(raw is Node3D and packed != null,"GLB and scene instantiate")
	if not raw is Node3D or packed == null:
		if raw != null: raw.free()
		quit(1)
		return
	var wall := packed.instantiate()
	root.add_child(wall)
	check(wall is Node3D and wall.transform.is_equal_approx(Transform3D.IDENTITY),"left-floor pivot")
	var src := gather(raw)
	var dst := gather(wall)
	check(src.size() == 14 and dst.size() == 14,"14 mesh parts in source and scene")
	var triangles := 0
	for name in src.keys():
		check(dst.has(name),"saved mesh "+name)
		if not dst.has(name): continue
		var a: MeshInstance3D = src[name]
		var b: MeshInstance3D = dst[name]
		check(a.transform.is_equal_approx(b.transform),"mesh transform "+name)
		check(a.mesh.get_surface_count() == b.mesh.get_surface_count(),"surface count "+name)
		if a.mesh.get_surface_count() != b.mesh.get_surface_count(): continue
		for si in a.mesh.get_surface_count():
			var arrays_a := a.mesh.surface_get_arrays(si)
			var arrays_b := b.mesh.surface_get_arrays(si)
			for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
				check(arrays_a[field] == arrays_b[field],"GLB vs saved array "+str(field)+" "+name)
			var idx: PackedInt32Array = arrays_a[Mesh.ARRAY_INDEX]
			triangles += idx.size()/3 if not idx.is_empty() else arrays_a[Mesh.ARRAY_VERTEX].size()/3
			var ma := a.mesh.surface_get_material(si) as BaseMaterial3D
			var mb := b.mesh.surface_get_material(si) as BaseMaterial3D
			check(ma != null and mb != null,"PBR material "+name)
			if ma != null and mb != null:
				check(ma.albedo_color.is_equal_approx(mb.albedo_color) and is_equal_approx(ma.roughness,mb.roughness),"material match "+name)
			check(a.mesh.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES,"triangle primitive "+name)
	check(triangles == 1512,"1512 imported triangles (<3000)")
	var body := wall.get_node_or_null("Collision") as StaticBody3D
	check(body != null and body.collision_layer == 1 and body.collision_mask == 1,"static environment body")
	if body == null:
		raw.free()
		wall.free()
		quit(1)
		return
	check(body.get_child_count() == 4,"four disjoint wall collider boxes")
	var specs := [
		[Vector3(.2,1.4,0),Vector3(.4,2.8,.2)],
		[Vector3(1.8,1.4,0),Vector3(.4,2.8,.2)],
		[Vector3(1,.45,0),Vector3(1.2,.9,.2)],
		[Vector3(1,2.45,0),Vector3(1.2,.7,.2)]
	]
	for i in specs.size():
		for j in range(i+1,specs.size()):
			var amin: Vector3 = specs[i][0] - specs[i][1] * .5
			var amax: Vector3 = specs[i][0] + specs[i][1] * .5
			var bmin: Vector3 = specs[j][0] - specs[j][1] * .5
			var bmax: Vector3 = specs[j][0] + specs[j][1] * .5
			var overlap := Vector3(minf(amax.x,bmax.x)-maxf(amin.x,bmin.x),minf(amax.y,bmax.y)-maxf(amin.y,bmin.y),minf(amax.z,bmax.z)-maxf(amin.z,bmin.z))
			check(overlap.x <= .00001 or overlap.y <= .00001 or overlap.z <= .00001,"colliders have no volumetric overlap "+str(i)+"/"+str(j))
	for i in mini(body.get_child_count(),specs.size()):
		var c := body.get_child(i) as CollisionShape3D
		check(c != null and c.shape is BoxShape3D and not c.disabled,"enabled box "+str(i))
		if c != null and c.shape is BoxShape3D:
			check(c.position.distance_to(specs[i][0]) < .0001 and c.shape.size.distance_to(specs[i][1]) < .0001,"exact box bounds "+str(i))
	if "--inject-drift" in OS.get_cmdline_user_args():
		var c := body.get_child(0) as CollisionShape3D
		c.disabled = true
	await physics_frame
	await physics_frame
	var space = wall.get_world_3d().direct_space_state
	for height in [.45,1.5,2.45]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(1,height,-.8),Vector3(1,height,.8),1)
		check(space.intersect_ray(query).is_empty() == (height == 1.5),"aperture clear only at window height "+str(height))
	for x in [.2,1.8]:
		var side_ray := PhysicsRayQueryParameters3D.create(Vector3(x,1.5,-.8),Vector3(x,1.5,.8),1)
		check(not space.intersect_ray(side_ray).is_empty(),"side wall blocks ray x="+str(x))
	var sphere := SphereShape3D.new()
	sphere.radius = .35
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.collision_mask = 1
	shape_query.transform.origin = Vector3(1,1.5,0)
	check(space.intersect_shape(shape_query).is_empty(),"70cm sphere fits window aperture")
	raw.free()
	wall.free()
	print("WINDOW_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed == 0 else 1)