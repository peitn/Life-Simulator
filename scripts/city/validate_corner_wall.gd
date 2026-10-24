extends SceneTree
var passed=0
var failed=0
func check(ok,label):
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func meshes(n,out):
	if n is MeshInstance3D:out.append(n)
	for c in n.get_children():meshes(c,out)
func _init():call_deferred("run")
func run():
	var start=Time.get_ticks_usec()
	var path="res://scenes/city/wall_corner_2m.scn"
	check(ResourceLoader.exists(path),"saved corner exists")
	if not ResourceLoader.exists(path):quit(1);return
	var packed=load(path)
	var corner=packed.instantiate()
	check(corner is Node3D and corner.transform==Transform3D.IDENTITY,"left floor corner pivot identity")
	root.add_child(corner)
	var parts=[]
	meshes(corner,parts)
	check(parts.size()==3,"three authored mesh parts")
	var tri=0
	var bounds=AABB()
	var first=true
	for part in parts:
		var b=part.global_transform*part.get_aabb()
		bounds=b if first else bounds.merge(b)
		first=false
		for surface in part.mesh.get_surface_count():
			var a=part.mesh.surface_get_arrays(surface)
			var vertices=a[Mesh.ARRAY_VERTEX]
			var indices=a[Mesh.ARRAY_INDEX]
			var normals=a[Mesh.ARRAY_NORMAL]
			var uv=a[Mesh.ARRAY_TEX_UV]
			tri+=indices.size()/3 if indices!=null and indices.size()>0 else vertices.size()/3
			check(normals.size()==vertices.size() and uv.size()==vertices.size(),"UV and normals present "+str(part.name))
			var norm_ok=true
			for n in normals:
				if abs(n.length()-1)>.001:norm_ok=false
			check(norm_ok,"unit normals "+str(part.name))
	check(tri==492,"492 imported triangles")
	check(bounds.position.distance_to(Vector3(-.124,0,-2))<.004,"Godot axis conversion and minimum bounds")
	check(bounds.end.distance_to(Vector3(2,2.8,.124))<.004,"height leg lengths and outer trim bounds")
	var body=corner.get_node("Collision")
	check(body is StaticBody3D and body.collision_layer==1 and body.collision_mask==1,"environment collision layer")
	check(body.get_child_count()==2,"two collision boxes")
	var specs=[[Vector3(.95,1.4,0),Vector3(2.1,2.8,.2)],[Vector3(0,1.4,-1.05),Vector3(.2,2.8,1.9)]]
	for i in 2:
		var c=body.get_child(i)
		check(c.position.distance_to(specs[i][0])<.0001 and c.shape.size.distance_to(specs[i][1])<.0001,"exact collider position/size "+str(i))
	var ca=body.get_child(0)
	var cb=body.get_child(1)
	check(abs((ca.position.z-ca.shape.size.z/2)-(cb.position.z+cb.shape.size.z/2))<.0001,"boxes meet at Z=-0.1 without gap or volume overlap")
	for c in body.get_children():
		check(c is CollisionShape3D and c.shape is BoxShape3D and not c.disabled,"enabled box collider")
	var solid=load("res://scenes/city/wall_solid_2m.scn")
	var a=solid.instantiate()
	a.position=Vector3(2,0,0)
	root.add_child(a)
	var b=solid.instantiate()
	b.position=Vector3(0,0,-2);b.rotation.y=PI/2
	root.add_child(b)
	check(a.transform.origin==Vector3(2,0,0),"X socket grid alignment")
	check(b.transform.origin==Vector3(0,0,-2),"negative Z socket grid alignment")
	await physics_frame
	await physics_frame
	var space=corner.get_world_3d().direct_space_state
	for x in [.0,1.0,1.999,2.0,2.001,3.0]:
		var q=PhysicsRayQueryParameters3D.create(Vector3(x,1,-.5),Vector3(x,1,.5),1)
		check(not space.intersect_ray(q).is_empty(),"X arm and snap collision "+str(x))
	for z in [-1.0,-1.999,-2.0,-2.001,-3.0]:
		var q=PhysicsRayQueryParameters3D.create(Vector3(-.5,1,z),Vector3(.5,1,z),1)
		check(not space.intersect_ray(q).is_empty(),"Z arm and snap collision "+str(z))
	var clear=PhysicsRayQueryParameters3D.create(Vector3(.5,.5,-.5),Vector3(1.5,.5,-1.5),1)
	check(space.intersect_ray(clear).is_empty(),"interior floor space clear")
	var shape=SphereShape3D.new()
	shape.radius=.35
	var query=PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform.origin=Vector3(.6,1,-.6);query.collision_mask=1
	check(space.intersect_shape(query).is_empty(),"70cm diameter interior clearance")
	var diagonal=PhysicsRayQueryParameters3D.create(Vector3(.6,1,-.6),Vector3(-.6,1,.6),1)
	check(not space.intersect_ray(diagonal).is_empty(),"diagonal ray blocked at inner corner")
	query.transform.origin=Vector3(1,1,-1)
	query.motion=Vector3(-2,0,2)
	var cast=space.cast_motion(query)
	check(cast.size()==2 and cast[0]>0 and cast[0]<.5,"moving 70cm sphere blocked by corner")
	print("CORNER_TEST_MS=",float(Time.get_ticks_usec()-start)/1000)
	corner.free();a.free();b.free()
	print("CORNER_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)
