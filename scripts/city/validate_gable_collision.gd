extends SceneTree
var passed=0
var failed=0
func check(ok:bool,label:String):
	if ok: passed+=1
	else: failed+=1
	print(("PASS " if ok else "FAIL ")+label)
func _init():
	call_deferred("run")
func run():
	var scene=load("res://scenes/city/gable_infill_2m.scn")
	check(scene is PackedScene,"saved scene")
	if not scene is PackedScene: quit(1);return
	var inst=scene.instantiate()
	root.add_child(inst)
	var body=inst.get_node("Collision")
	check(body is StaticBody3D and body.collision_layer==1 and body.collision_mask==1,"static layer mask")
	check(body.get_child_count()==1,"single collider")
	var col=body.get_child(0)
	check(col.shape is ConvexPolygonShape3D and col.shape.points.size()==6,"six convex corners")
	if "--disable-collision" in OS.get_cmdline_user_args(): col.disabled=true
	var expected=[Vector3(0,0,0),Vector3(2,0,0),Vector3(1,.6,0),Vector3(0,0,-.12),Vector3(2,0,-.12),Vector3(1,.6,-.12)]
	for p in expected:
		var found=false
		for q in col.shape.points:
			if p.distance_to(q)<.0001: found=true
		check(found,"corner "+str(p))
	await physics_frame
	await physics_frame
	var space=inst.get_world_3d().direct_space_state
	for x in [.25,.5,1.0,1.5,1.75]:
		var y=.3*min(x,2-x)
		for direction in [1,-1]:
			var a=Vector3(x,y,.5 if direction==1 else -.5)
			var b=Vector3(x,y,-.5 if direction==1 else .5)
			var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
			check(not hit.is_empty() and hit.collider==body,"inside face ray")
			if not hit.is_empty():
				check(abs(hit.position.z-(0.0 if direction==1 else -.12))<.001,"face depth")
		var outside=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,.6*min(x,2-x)+.05,.5),Vector3(x,.6*min(x,2-x)+.05,-.5),1))
		check(outside.is_empty(),"above pitched edge remains empty")
	inst.free()
	print("GABLE_COLLISION_RESULT ",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)
