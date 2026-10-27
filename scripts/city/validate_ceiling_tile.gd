extends SceneTree
# Read-only M1 ceiling source/scene and physics acceptance. --inject-drift is memory-only.
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("PASS " if ok else "FAIL ") + label)
func gather(node: Node) -> Dictionary:
	var d := {}
	for m in node.find_children("*","MeshInstance3D",true,false):
		d[String(m.name)] = m
	return d
func bounds_in_root(mesh_instance: MeshInstance3D, boundary: Node) -> AABB:
	# Import transforms can live on parent nodes; inspect all eight transformed AABB corners.
	var transform_to_root := Transform3D.IDENTITY
	var current: Node = mesh_instance
	while current != boundary and current != null:
		if not current is Node3D:
			return AABB()
		transform_to_root = (current as Node3D).transform * transform_to_root
		current = current.get_parent()
	if current != boundary:
		return AABB()
	var local := mesh_instance.mesh.get_aabb()
	var lo := Vector3(INF,INF,INF)
	var hi := Vector3(-INF,-INF,-INF)
	for x in [local.position.x,local.end.x]:
		for y in [local.position.y,local.end.y]:
			for z in [local.position.z,local.end.z]:
				var point := transform_to_root * Vector3(x,y,z)
				lo = lo.min(point)
				hi = hi.max(point)
	return AABB(lo,hi-lo)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var glb := "res://assets/city/ceiling_tile_2m.glb"
	var scn := "res://scenes/city/ceiling_tile_2m.scn"
	check(FileAccess.file_exists(glb),"ceiling GLB exists")
	check(ResourceLoader.exists(scn),"ceiling saved scene exists")
	if failed>0:
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var result := doc.append_from_file(glb,state)
	check(result==OK,"GLB import")
	if result!=OK:
		quit(1)
		return
	var src := doc.generate_scene(state)
	var packed := load(scn) as PackedScene
	check(src is Node3D and packed!=null,"source and PackedScene valid")
	if not src is Node3D or packed==null:
		if src!=null: src.free()
		quit(1)
		return
	var ceiling: Node3D = packed.instantiate() as Node3D
	root.add_child(ceiling)
	check(ceiling is Node3D and ceiling.transform.is_equal_approx(Transform3D.IDENTITY),"ceiling origin at underside corner")
	var a := gather(src)
	var b := gather(ceiling)
	if "--inject-geometry-drift" in OS.get_cmdline_user_args() and b.has("ceiling_plaster_finish"):
		(b["ceiling_plaster_finish"] as MeshInstance3D).position.x += .15 # memory-only negative test
	check(a.size()==2 and b.size()==2,"two source and saved meshes")
	var triangles := 0
	for name in a.keys():
		check(b.has(name),"saved mesh "+name)
		if not b.has(name): continue
		var am: MeshInstance3D = a[name]
		var bm: MeshInstance3D = b[name]
		check(am.transform.is_equal_approx(bm.transform),"mesh transform "+name)
		check(am.mesh.get_surface_count()==bm.mesh.get_surface_count(),"surface count "+name)
		if am.mesh.get_surface_count()!=bm.mesh.get_surface_count(): continue
		for si in am.mesh.get_surface_count():
			var aa := am.mesh.surface_get_arrays(si)
			var bb := bm.mesh.surface_get_arrays(si)
			for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
				check(aa[field]==bb[field],"source/saved array "+str(field)+" "+name)
			var indices: PackedInt32Array = aa[Mesh.ARRAY_INDEX]
			triangles += indices.size()/3 if not indices.is_empty() else aa[Mesh.ARRAY_VERTEX].size()/3
			var ma := am.mesh.surface_get_material(si) as BaseMaterial3D
			var mb := bm.mesh.surface_get_material(si) as BaseMaterial3D
			check(ma!=null and mb!=null,"PBR materials "+name)
			if ma!=null and mb!=null:
				check(ma.albedo_color.is_equal_approx(mb.albedo_color) and is_equal_approx(ma.roughness,mb.roughness),"material values "+name)
			check(am.mesh.surface_get_primitive_type(si)==Mesh.PRIMITIVE_TRIANGLES,"triangles primitive "+name)
	# Numeric bounds in Godot coordinates: independent of source/scene array equality.
	var expected := {
		"ceiling_concrete_slab": AABB(Vector3(0,.02,-2),Vector3(2,.18,2)),
		"ceiling_plaster_finish": AABB(Vector3(0,0,-2),Vector3(2,.02,2))
	}
	for origin in [{"root":src,"meshes":a,"label":"GLB"},{"root":ceiling,"meshes":b,"label":"saved scene"}]:
		var combined := AABB()
		var has_bounds := false
		for name in expected.keys():
			if not origin["meshes"].has(name):
				continue
			var bounds := bounds_in_root(origin["meshes"][name],origin["root"])
			var target: AABB = expected[name]
			check(bounds.position.distance_to(target.position)<.001,origin["label"]+" "+name+" min bounds")
			check(bounds.end.distance_to(target.end)<.001,origin["label"]+" "+name+" max bounds")
			combined = combined.merge(bounds) if has_bounds else bounds
			has_bounds = true
		if has_bounds:
			check(combined.position.distance_to(Vector3(0,0,-2))<.001,origin["label"]+" combined min bounds")
			check(combined.end.distance_to(Vector3(2,.2,0))<.001,origin["label"]+" combined max bounds")
	check(triangles==216,"216 triangles (<3000)")
	var body := ceiling.get_node_or_null("Collision") as StaticBody3D
	check(body!=null and body.collision_layer==1 and body.collision_mask==1,"static layer/mask1")
	if body==null:
		src.free()
		ceiling.free()
		quit(1)
		return
	check(body.get_child_count()==1,"single slab collider")
	var col := body.get_child(0) as CollisionShape3D
	check(col!=null and col.shape is BoxShape3D and not col.disabled,"enabled box shape")
	if col!=null and col.shape is BoxShape3D:
		check(col.position.distance_to(Vector3(1,.1,-1))<.0001,"collider center")
		check(col.shape.size.distance_to(Vector3(2,.2,2))<.0001,"collider dimensions")
	if "--inject-drift" in OS.get_cmdline_user_args() and col!=null:
		col.disabled=true
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = ceiling.get_world_3d().direct_space_state
	for x in [.1,1.0,1.9]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x,.5,-1),Vector3(x,-.5,-1),1)
		var hit: Dictionary = space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-.2)<.002,"ceiling top blocks downward ray x="+str(x))
	for pos in [Vector3(-.2,.5,-1),Vector3(2.2,.5,-1),Vector3(1,.5,.2),Vector3(1,.5,-2.2)]:
		var ray := PhysicsRayQueryParameters3D.create(pos,pos+Vector3(0,-1,0),1)
		check(space.intersect_ray(ray).is_empty(),"outside ceiling footprint "+str(pos))
	# Two tiles placed above the 2.8m wall, upward rays test underside and seam.
	var adjacent: Node3D = packed.instantiate()
	adjacent.position = Vector3(2,2.8,0)
	ceiling.position.y = 2.8
	root.add_child(adjacent)
	await physics_frame
	await physics_frame
	for x in [1.0,1.999,2.001,3.0]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x,2.5,-1),Vector3(x,3.2,-1),1)
		var hit: Dictionary = space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-2.8)<.002,"ceiling underside and snap seam "+str(x))
	adjacent.free()
	src.free()
	ceiling.free()
	print("CEILING_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)