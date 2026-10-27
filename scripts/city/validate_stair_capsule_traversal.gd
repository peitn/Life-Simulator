extends SceneTree
var passed := 0
var failed := 0
var max_foot_error := 0.0
var blocked_horizontal := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var packed = load("res://scenes/city/stair_landing_demo.tscn")
	if not packed is PackedScene:
		check(false,"saved demo load")
		quit(1)
		return
	var demo: Node3D = packed.instantiate()
	root.add_child(demo)
	var steps = demo.get_node("Stairs/SolidSteps")
	if "--disable-step7" in OS.get_cmdline_user_args():
		steps.get_node("Step07").disabled = true
	var avatar := CharacterBody3D.new()
	avatar.name = "CityOnlyCapsuleProbe"
	avatar.collision_layer = 2
	avatar.collision_mask = 1
	avatar.safe_margin = .001
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .18
	capsule.height = 1.6
	collider.shape = capsule
	avatar.add_child(collider)
	demo.add_child(avatar)
	avatar.global_position = Vector3(.5,.8,.65)
	await physics_frame
	await physics_frame
	check(steps.collision_layer == 1,"stair physics layer")
	var bottom_contact = avatar.move_and_collide(Vector3(0,-.1,0))
	check(bottom_contact != null and bottom_contact.get_collider() != steps,"bottom landing capsule contact")
	check(abs(avatar.global_position.y-.8)<.015,"bottom landing foot height")
	for i in range(15):
		var foot_y = (i+1)*.2
		var z = -(i*.3+.1)
		var up = avatar.move_and_collide(Vector3(0,foot_y+.11-(avatar.global_position.y-.8),0))
		var forward = avatar.move_and_collide(Vector3(0,0,z-avatar.global_position.z))
		var down = avatar.move_and_collide(Vector3(0,-.2,0))
		if forward != null: blocked_horizontal += 1
		var error = abs(avatar.global_position.y-.8-foot_y)
		max_foot_error = max(max_foot_error,error)
		check(up == null,"ascent vertical clear %02d"%i)
		check(forward == null,"ascent horizontal unsnagged %02d"%i)
		check(down != null and down.get_collider() == steps,"ascent step contact %02d"%i)
		check(error<.015,"ascent foot height %02d"%i)
		check(abs(avatar.global_position.z-z)<.005,"ascent position %02d"%i)
	var onto_top = avatar.move_and_collide(Vector3(0,0,-5-avatar.global_position.z))
	check(onto_top == null,"upper landing seam crossing")
	var top_contact = avatar.move_and_collide(Vector3(0,-.08,0))
	check(top_contact != null and top_contact.get_collider() != steps,"upper landing capsule contact")
	check(abs(avatar.global_position.y-.8-3)<.015,"upper landing foot height")
	for i in range(14,-1,-1):
		var foot_y = (i+1)*.2
		var z = -(i*.3+.1)
		var forward = avatar.move_and_collide(Vector3(0,0,z-avatar.global_position.z))
		var down = avatar.move_and_collide(Vector3(0,foot_y-.07-(avatar.global_position.y-.8),0))
		if forward != null: blocked_horizontal += 1
		var error = abs(avatar.global_position.y-.8-foot_y)
		max_foot_error = max(max_foot_error,error)
		check(forward == null,"descent horizontal unsnagged %02d"%i)
		check(down != null and down.get_collider() == steps,"descent step contact %02d"%i)
		check(error<.015,"descent foot height %02d"%i)
		check(abs(avatar.global_position.z-z)<.005,"descent position %02d"%i)
	var onto_bottom = avatar.move_and_collide(Vector3(0,0,.65-avatar.global_position.z))
	var final_contact = avatar.move_and_collide(Vector3(0,-.27,0))
	check(onto_bottom == null,"lower landing seam crossing")
	check(final_contact != null and final_contact.get_collider() != steps,"lower landing final contact")
	check(abs(avatar.global_position.y-.8)<.015,"lower landing final foot height")
	check(blocked_horizontal==0,"no horizontal snags")
	print("CAPSULE_TRAVERSAL ",passed,"/",passed+failed," failed=",failed," max_foot_error_m=",max_foot_error," blocked_horizontal=",blocked_horizontal," scripted_step_clearance_m=.11 capsule_radius_m=.18 capsule_height_m=1.6")
	demo.free()
	quit(0 if failed==0 else 1)