extends SceneTree
## Isolated city test controller, not main-game navigation.
var failed := 0
var passed := 0
class Walker extends CharacterBody3D:
	var ticks := 0
	var phase := 0
	var reached_top := false
	var finished := false
	var lifts := 0
	var max_y := 0.0
	var max_tick_distance := 0.0
	var floor_ticks := 0
	var ascent_min_dy := 0.0
	func _physics_process(delta: float) -> void:
		if finished: return
		ticks += 1
		var start := global_position
		var direction := -1.0 if phase == 0 else 1.0
		var horizontal := Vector3(0,0,direction*1.5*delta)
		var grounded := is_on_floor()
		# Probe a fixed maximum step height; never use tread coordinates.
		if grounded and test_move(global_transform,horizontal):
			var raised := global_transform
			raised.origin.y += .22
			if not test_move(global_transform,Vector3(0,.22,0)) and not test_move(raised,horizontal):
				var ahead := raised
				ahead.origin += horizontal.normalized()*.20
				var support := KinematicCollision3D.new()
				# For this centered 1.6m capsule, foot is origin.y - 0.8m.
				# Avoid repeat lift when prospective support is not 8cm above current foot.
				if test_move(ahead,Vector3(0,-.24,0),support) and support.get_normal().dot(Vector3.UP) > .7 and support.get_position().y > global_position.y - .8 + .08:
					# Prospective capsule center from whole-shape sweep, not contact point.
					var destination := raised
					destination.origin += horizontal.normalized()*.20
					var landing := KinematicCollision3D.new()
					if test_move(destination,Vector3(0,-.24,0),landing):
						var lift := clampf(.22 + landing.get_travel().y + .001,.001,.22)
						var target := global_transform
						target.origin.y += lift
						if not test_move(global_transform,Vector3(0,lift,0)) and not test_move(target,horizontal):
							move_and_collide(Vector3(0,lift,0))
							lifts += 1
		velocity.x = 0
		velocity.z = direction*1.5
		velocity.y = -0.1 if grounded else velocity.y-9.8*delta
		move_and_slide()
		apply_floor_snap()
		if is_on_floor(): floor_ticks += 1
		if phase == 0: ascent_min_dy = min(ascent_min_dy,global_position.y-start.y)
		max_y = max(max_y,global_position.y)
		max_tick_distance = max(max_tick_distance,start.distance_to(global_position))
		if phase == 0 and global_position.z < -5.2 and is_on_floor():
			reached_top = abs(global_position.y-3.8)<.025
			phase = 1
		elif phase == 1 and global_position.z > .8 and is_on_floor():
			finished = true
		if ticks >= 900: finished = true
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL ",label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var packed = load("res://scenes/city/stair_landing_demo.tscn")
	if not packed is PackedScene:
		check(false,"saved demo exists")
		quit(1)
		return
	var demo: Node3D = packed.instantiate()
	root.add_child(demo)
	var walker := Walker.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	walker.safe_margin = .001
	walker.floor_snap_length = .24
	walker.floor_stop_on_slope = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .18
	capsule.height = 1.6
	shape.shape = capsule
	walker.add_child(shape)
	demo.add_child(walker)
	walker.position = Vector3(.5,.82,.8)
	if "--block-path" in OS.get_cmdline_user_args():
		var wall := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1,3,.1)
		collision.shape = box
		wall.add_child(collision)
		demo.add_child(wall)
		wall.position = Vector3(.5,1.5,-.6)
	while not walker.finished:
		await physics_frame
	check(walker.ticks > 300 and walker.ticks < 900,"bounded actual physics ticks")
	check(walker.reached_top,"upper landing reached at 3m")
	check(walker.phase == 1 and walker.position.z > .8,"returned across lower landing")
	check(abs(walker.position.y-.8)<.025,"final grounded foot at zero")
	check(walker.is_on_floor(),"final floor contact")
	check(walker.lifts > 0,"explicit obstacle-driven step-up executed")
	check(walker.lifts <= 18,"no repeated lifts on 15-riser ascent")
	check(walker.max_y < 3.83,"no excessive vertical escape")
	check(walker.max_tick_distance < .26,"no teleport-sized per-tick motion")
	check(abs(walker.position.x-.5)<.005,"no lateral escape")
	check(walker.floor_ticks > walker.ticks*.8,"grounded for majority of traversal")
	print("PHYSICS_STAIR ",passed,"/",passed+failed," failed=",failed," ticks=",walker.ticks," lifts=",walker.lifts," floor_ticks=",walker.floor_ticks," max_tick_m=",walker.max_tick_distance," final=",walker.position," top=",walker.reached_top," ascent_min_dy=",walker.ascent_min_dy)
	demo.free()
	quit(0 if failed==0 else 1)

