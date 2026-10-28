extends SceneTree
const Materials = preload("res://scripts/city/m1_materials.gd")
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1; print("FAIL ",label)
func _init() -> void: call_deferred("run")

func mesh_check(node: Node3D,label: String,expected: AABB) -> void:
	var low:=Vector3(INF,INF,INF); var high:=Vector3(-INF,-INF,-INF)
	var triangles:=0
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
			check(verts.size()>0 and uv.size()==verts.size(),label+" UV coverage")
			check(normals.size()==verts.size() and tangents.size()==verts.size()*4,label+" normal/tangent coverage")
			var normal_ok:=true
			for normal in normals: normal_ok=normal_ok and normal.is_finite() and absf(normal.length()-1)<.002
			check(normal_ok,label+" unit normals")
			for point in verts:
				var p: Vector3=node.global_transform.affine_inverse()*mesh.global_transform*point
				low=low.min(p); high=high.max(p)
			var indices=arrays[Mesh.ARRAY_INDEX]
			triangles+=indices.size()/3 if indices!=null and indices.size()>0 else verts.size()/3
	check(low.is_equal_approx(expected.position) and high.is_equal_approx(expected.end),label+" imported bounds/pivot")
	check(triangles>0 and triangles<3000,label+" triangle budget")
	print("M1_GEOMETRY ",label," low=",low," high=",high," triangles=",triangles)

func actor(parent: Node,where: Vector3) -> CharacterBody3D:
	var body:=CharacterBody3D.new(); body.collision_layer=2; body.collision_mask=1
	var c:=CollisionShape3D.new(); c.name="Capsule"; var shape:=CapsuleShape3D.new(); shape.height=1.6; shape.radius=.18; c.shape=shape
	body.add_child(c); parent.add_child(body); body.position=where
	return body

func box(parent: Node,size_: Vector3,center: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new(); var c:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=size_; c.shape=shape
	body.add_child(c); parent.add_child(body); body.position=center; return body

func wait_door(door: Node) -> void:
	for i in range(90):
		await physics_frame
		if not door.moving: break
	check(not door.moving,"door bounded transition")

func run() -> void:
	var fixture:=Node3D.new(); root.add_child(fixture)
	var foundation=load("res://scenes/city/foundation_2m.tscn").instantiate(); fixture.add_child(foundation)
	mesh_check(foundation,"foundation",AABB(Vector3(0,-.5,-2),Vector3(2,.5,2)))
	check(foundation.get_node("RearRight").position==Vector3(2,0,-2),"foundation grid socket")
	var roof=load("res://scenes/city/roof_flat_2m.tscn").instantiate(); fixture.add_child(roof); roof.position=Vector3(4,0,0)
	mesh_check(roof,"flat roof",AABB(Vector3(0,0,-2),Vector3(2,.15,2)))
	await physics_frame; await physics_frame
	for x in [.1,1.0,1.9]:
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,1,-1),Vector3(x,-1,-1),1)
		var hit=root.world_3d.direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y)<.001,"foundation top support")
	var roof_hit=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(5,1,-1),Vector3(5,-1,-1),1))
	check(not roof_hit.is_empty() and absf(roof_hit.position.y-.15)<.001,"flat roof top collision")
	for kind in Materials.NAMES:
		var mat=Materials.make(kind)
		check(mat!=null and mat.normal_enabled and mat.texture_repeat,kind+" functional PBR material")
		check(mat!=null and mat.albedo_texture!=null and mat.normal_texture!=null and mat.roughness_texture!=null,kind+" three actual maps")
		for part in ["albedo","normal","roughness"]:
			var im:=Image.load_from_file("res://assets/city/materials/"+kind+"_"+part+".png")
			var seams:=true
			for i in range(128):
				seams=seams and im.get_pixel(i,0)==im.get_pixel(i,127) and im.get_pixel(0,i)==im.get_pixel(127,i)
			check(seams and im.get_size()==Vector2i(128,128),kind+" "+part+" periodic edge texels")
	check(Materials.make("invalid")==null,"unknown material rejected")
	check(Materials.apply(foundation,"brick"),"material variant applies to imported meshes")
	check(foundation.get_node("Collision/SolidCollider").shape.size==Vector3(2,.5,2),"material swap preserves collision dimensions")
	fixture.free(); await physics_frame
	fixture=Node3D.new(); root.add_child(fixture)
	box(fixture,Vector3(4,.2,4),Vector3(1,-.1,0))
	var door=load("res://scenes/city/door_hinged_1m.tscn").instantiate(); fixture.add_child(door)
	mesh_check(door.get_node("Hinge/LeafBody").get_child(1),"door leaf",AABB(Vector3(0,0,-.075),Vector3(.96,2.06,.15)))
	var capsule=actor(fixture,Vector3(1,.82,.6))
	await physics_frame; await physics_frame
	if "--disable-leaf" in OS.get_cmdline_user_args():
		door.leaf_shape.disabled=true
		await physics_frame; await physics_frame
	check(door.is_closed(),"door starts closed")
	check(capsule.test_move(capsule.global_transform,Vector3(0,0,-1.2)),"closed door blocks capsule")
	# Park the actor outside the entire swing, then open the real collider.
	capsule.position=Vector3(3,.82,1)
	check(door.request_open(true),"open command accepted")
	await wait_door(door)
	check(door.is_open() and not door.motion_blocked,"door opens to 90 degrees")
	capsule.position=Vector3(1,.82,.6)
	check(not capsule.test_move(capsule.global_transform,Vector3(0,0,-1.2)),"open door passes full capsule sweep")
	capsule.position=Vector3(1,.82,0)
	await physics_frame
	check(door.request_open(false),"close command accepted")
	await wait_door(door)
	check(door.motion_blocked and not door.is_closed(),"closing stops before doorway occupant")
	var q:=PhysicsShapeQueryParameters3D.new(); q.shape=capsule.get_node("Capsule").shape
	q.transform=capsule.global_transform; q.collision_mask=1
	var hits=root.world_3d.direct_space_state.intersect_shape(q)
	check(hits.is_empty(),"blocked leaf never penetrates standing capsule")
	capsule.position=Vector3(3,.82,1)
	await physics_frame; await physics_frame
	check(door.request_open(false),"close retry accepted after clearance")
	await wait_door(door)
	check(door.is_closed() and not door.motion_blocked,"door closes when occupant leaves")
	check(door.has_node("InteractFront") and door.has_node("InteractBack"),"two accessible interaction markers")
	var obstacle=box(fixture,Vector3(.10,1.8,.10),Vector3(1,.95,-.4))
	await physics_frame; await physics_frame
	door.request_open(true)
	await wait_door(door)
	check(door.motion_blocked and not door.is_open(),"opening stops at static swing obstacle")
	obstacle.queue_free(); await physics_frame; await physics_frame
	door.request_open(true)
	await wait_door(door)
	check(door.is_open() and not door.motion_blocked,"opening resumes after obstacle removal")
	fixture.queue_free()
	Materials._cache.clear()
	await process_frame; await process_frame
	print("M1_FINISH ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
