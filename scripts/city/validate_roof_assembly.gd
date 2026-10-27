extends SceneTree
# Read-only integration fixture. No authored scene or mesh is written.
var passed := 0
var failed := 0
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print(("PASS " if ok else "FAIL ")+label)
func _init():
	call_deferred("run")
func run():
	var fixture: Node3D
	var roofs: Array[Node3D] = []
	var ceilings: Array[Node3D] = []
	if "--saved-demo" in OS.get_cmdline_user_args():
		var packed=load("res://scenes/city/roof_assembly_demo.tscn") as PackedScene
		check(packed!=null,"saved demo loads")
		if packed==null:quit(1);return
		fixture=packed.instantiate()
		root.add_child(fixture)
		for i in 2:
			for spec in [["Roof",3.0],["Ceiling",2.8],["Wall",0.0]]:
				var node=fixture.get_node_or_null(spec[0]+str(i)) as Node3D
				check(node!=null,"saved module "+spec[0]+str(i))
				if node==null:fixture.free();quit(1);return
				check(node.position.is_equal_approx(Vector3(0,spec[1],-2*i)) and node.basis.is_equal_approx(Basis.IDENTITY),"saved placement "+spec[0]+str(i))
				if spec[0]=="Roof":roofs.append(node)
				if spec[0]=="Ceiling":ceilings.append(node)
	else:
		fixture = Node3D.new()
		root.add_child(fixture)
		for i in range(2):
			for spec in [["roof_gable_2m",3.0],["ceiling_tile_2m",2.8],["wall_solid_2m",0.0]]:
				var resource = load("res://scenes/city/"+spec[0]+".scn")
				check(resource is PackedScene,"dependency "+str(i)+" "+spec[0])
				if not resource is PackedScene:
					fixture.free(); quit(1); return
				var node = resource.instantiate()
				check(node is Node3D,"Node3D "+spec[0])
				if not node is Node3D:
					node.free(); fixture.free(); quit(1); return
				fixture.add_child(node)
				node.position = Vector3(0,spec[1],-2*i)
				if spec[0]=="roof_gable_2m": roofs.append(node)
				if spec[0]=="ceiling_tile_2m": ceilings.append(node)
	if "--inject-gap" in OS.get_cmdline_user_args():
		roofs[1].position.z -= .1
	if "--inject-height" in OS.get_cmdline_user_args():
		roofs[0].position.y += .1
	for x in [0.0,1.0,2.0]:
		var y := .6 if x==1.0 else 0.0
		check((roofs[0].to_global(Vector3(x,y,-2))-roofs[1].to_global(Vector3(x,y,0))).length()<.0001,"adjacent roof socket x="+str(x))
	for i in range(2):
		for x in [0.0,2.0]:
			for z in [0.0,-2.0]:
				check(roofs[i].to_global(Vector3(x,0,z)).distance_to(ceilings[i].to_global(Vector3(x,.2,z)))<.0001,"eave/ceiling contact "+str(i)+str(Vector2(x,z)))
	await physics_frame
	await physics_frame
	var space := fixture.get_world_3d().direct_space_state
	for z in [-1.0,-1.99,-2.0,-2.01,-3.0]:
		for x in [.25,.75,1.25,1.75]:
			var expected := 3.12+.6*minf(x,2-x)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,4,z),Vector3(x,3,z),1))
			check(not hit.is_empty() and absf(hit.position.y-expected)<.002,"roof seam ray "+str(Vector2(x,z)))
	for z in [-1.0,-1.99,-2.0,-2.01,-3.0]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,2,z),Vector3(1,3.2,z),1))
		check(not hit.is_empty() and absf(hit.position.y-2.8)<.002,"ceiling underside "+str(z))
	for z in [0.0,-2.0]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,2.7,z+.4),Vector3(1,2.7,z-.4),1))
		check(not hit.is_empty(),"wall below ceiling "+str(z))
	var sphere := SphereShape3D.new()
	sphere.radius=.35
	for z in [-.5,-1.5,-2.5,-3.5]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape=sphere
		q.collision_mask=1
		q.transform.origin=Vector3(1,2.4,z)
		check(space.intersect_shape(q).is_empty(),"head clearance "+str(z))
	fixture.free()
	print("ASSEMBLY_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)
