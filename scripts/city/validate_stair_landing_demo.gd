extends SceneTree
var passed=0
var failed=0
func check(ok,label):
	if ok: passed+=1
	else: failed+=1;print("FAIL ",label)
func _init(): call_deferred("run")
func run():
	var scene=load("res://scenes/city/stair_landing_demo.tscn")
	if not scene is PackedScene: check(false,"scene load");quit(1);return
	var demo=scene.instantiate();root.add_child(demo)
	var stairs=demo.get_node_or_null("Stairs")
	var bottom=demo.get_node_or_null("BottomLanding")
	var top=demo.get_node_or_null("TopLanding")
	if stairs==null or bottom==null or top==null: check(false,"module nodes");demo.free();quit(1);return
	check(demo.get_child_count()==3,"three saved modules")
	check(stairs.position.is_equal_approx(Vector3.ZERO),"stair origin")
	check(bottom.position.is_equal_approx(Vector3(0,0,2)),"lower placement")
	check(top.position.is_equal_approx(Vector3(0,3,-4.5)),"upper placement")
	check(stairs.get_node("Bottom").global_position.is_equal_approx(Vector3.ZERO),"lower socket")
	check(stairs.get_node("Top").global_position.is_equal_approx(top.position),"upper socket")
	var body=stairs.get_node("SolidSteps")
	check(body is StaticBody3D and body.collision_layer==1,"stair collision")
	if "--disable-step7" in OS.get_cmdline_user_args():
		var shape=body.get_node_or_null("Step07")
		if shape!=null: shape.disabled=true
	await physics_frame
	await physics_frame
	var space=root.world_3d.direct_space_state
	for i in range(15):
		var z=-(float(i)+0.5)*0.3
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.5,4,z),Vector3(.5,-.5,z),1))
		check(not hit.is_empty() and hit.collider==body,"tread body %02d"%i)
		check(not hit.is_empty() and abs(hit.position.y-(i+1)*.2)<.001,"tread height %02d"%i)
	for sample in [[0.05,0.0],[-4.55,3.0]]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.5,4,sample[0]),Vector3(.5,-.5,sample[0]),1))
		check(not hit.is_empty() and abs(hit.position.y-sample[1])<.001,"landing %s"%str(sample[0]))
	for x in [-.05,1.05]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,4,-2.1),Vector3(x,-.5,-2.1),1))
		check(hit.is_empty(),"lateral clear %s"%str(x))
	print("STAIR_DEMO ",passed,"/",passed+failed," failed=",failed)
	demo.free()
	quit(0 if failed==0 else 1)
