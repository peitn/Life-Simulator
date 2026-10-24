# Read-only regression for solid wall and saved three-module assembly.
extends SceneTree
var passed=0
var failed=0
func check(ok,label):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func _init():
	call_deferred("run")
func run():
	var start=Time.get_ticks_usec()
	var doc=GLTFDocument.new()
	var state=GLTFState.new()
	check(doc.append_from_buffer(FileAccess.get_file_as_bytes("res://assets/city/wall_solid_2m.glb"),"res://assets/city/",state)==OK,"solid GLB imports")
	var model=doc.generate_scene(state)
	root.add_child(model)
	var meshes=model.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==3,"three mesh parts")
	var bounds=AABB()
	var first=true
	var triangles=0
	var uv_ok=true
	var normal_ok=true
	for n in meshes:
		var b=n.global_transform*n.mesh.get_aabb()
		bounds=b if first else bounds.merge(b)
		first=false
		for si in n.mesh.get_surface_count():
			var a=n.mesh.surface_get_arrays(si)
			triangles+=a[Mesh.ARRAY_INDEX].size()/3
			uv_ok=uv_ok and a[Mesh.ARRAY_TEX_UV].size()==a[Mesh.ARRAY_VERTEX].size()
			for uv in a[Mesh.ARRAY_TEX_UV]: uv_ok=uv_ok and uv.is_finite()
			for normal in a[Mesh.ARRAY_NORMAL]: normal_ok=normal_ok and normal.is_finite() and abs(normal.length()-1)<.01
	check(bounds.size.is_equal_approx(Vector3(2,2.8,.248)),"solid meter bounds Y-up")
	check(abs(bounds.position.x)<.0001 and abs(bounds.position.y)<.0001,"left-floor pivot")
	check(triangles==324,"324 triangles")
	check(uv_ok,"finite complete UVs")
	check(normal_ok,"unit finite normals")
	model.queue_free()
	await process_frame
	# Validate the separately saved catalogue asset, not only its demo copy.
	var standalone_resource=load("res://scenes/city/wall_solid_2m.scn")
	check(standalone_resource is PackedScene,"standalone PackedScene exists")
	if not standalone_resource is PackedScene:
		quit(1)
		return
	var standalone=standalone_resource.instantiate()
	root.add_child(standalone)
	check(standalone.transform.is_equal_approx(Transform3D.IDENTITY),"standalone root identity")
	var standalone_shapes=standalone.find_children("*","CollisionShape3D",true,false)
	check(standalone_shapes.size()==1,"standalone has one core collider")
	var core_ok=standalone_shapes.size()==1
	if core_ok:
		var shape=standalone_shapes[0]
		core_ok=shape.shape is BoxShape3D and not shape.disabled and shape.get_parent() is StaticBody3D
		if core_ok:
			core_ok=shape.shape.size.is_equal_approx(Vector3(2,2.8,.2)) and shape.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(1,1.4,0))) and shape.get_parent().collision_layer==1
	check(core_ok,"standalone collision dimensions placement and layer")
	await physics_frame
	await physics_frame
	var standalone_space=standalone.get_world_3d().direct_space_state
	for x in [.001,1.0,1.999]:
		var hit=standalone_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,1,1),1))
		check(not hit.is_empty(),"standalone solid ray "+str(x))
	for x in [-.01,2.01]:
		var hit=standalone_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,1,1),1))
		check(hit.is_empty(),"standalone outside ray "+str(x))
	standalone.queue_free()
	await process_frame
	await physics_frame
	var assembly=load("res://scenes/city/wall_snap_demo.scn").instantiate()
	root.add_child(assembly)
	check(assembly.get_child_count()==3,"three module assembly")
	check(flattened(assembly,assembly),"saved descendants have unified owners and no nested scene paths")
	check(assembly.get_child(0).position.is_equal_approx(Vector3.ZERO),"first wall snap")
	check(assembly.get_child(1).position.is_equal_approx(Vector3(2,0,0)),"doorway snap")
	check(assembly.get_child(2).position.is_equal_approx(Vector3(4,0,0)),"second wall snap")
	var shapes=assembly.find_children("*","CollisionShape3D",true,false)
	check(shapes.size()==5,"five collision boxes")
	for shape in shapes:
		check(not shape.disabled and shape.get_parent().collision_layer==1,"enabled environment collision")
	await physics_frame
	await physics_frame
	var space=assembly.get_world_3d().direct_space_state
	for x in [1.0,1.999,2.001,3.0,3.999,4.001,5.0]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,1,1)))
		check(hit.is_empty() if x==3.0 else not hit.is_empty(),"wall/seam/opening ray "+str(x))
	var sphere=SphereShape3D.new()
	sphere.radius=.35
	var query=PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform.origin=Vector3(3,1,0)
	check(space.intersect_shape(query).is_empty(),"doorway body clearance")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3,2.45,-1),Vector3(3,2.45,1))).is_empty(),"doorway lintel")
	var mats={}
	for n in assembly.find_children("*","MeshInstance3D",true,false):
		for si in n.mesh.get_surface_count():
			var mat=n.get_active_material(si)
			if mat!=null: mats[mat.get_instance_id()]=true
	check(mats.size()==2,"two shared material resources across assembly")
	print("IMPORT_AND_VALIDATION_MS=",float(Time.get_ticks_usec()-start)/1000)
	assembly.queue_free()
	await process_frame
	print("SOLID_TEST_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed==0 else 1)

func flattened(node,scene_root):
	for child in node.get_children():
		if child.owner!=scene_root or child.scene_file_path!="" or not flattened(child,scene_root):
			return false
	return true
