extends "res://scripts/city/validate_stair_physics_walk.gd"
## City-only independent lateral-clearance regression of the existing stair walker.
## The production/controller source and authored geometry are never modified.
func run() -> void:
	var packed = load("res://scenes/city/stair_landing_demo.tscn")
	if not packed is PackedScene:
		check(false, "saved demo exists")
		quit(1)
		return
	var demo: Node3D = packed.instantiate()
	root.add_child(demo)
	var offsets := [0.23, 0.50, 0.77]
	var walkers: Array = []
	for x in offsets:
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
		walker.position = Vector3(x, .82, .8)
		walkers.append(walker)
	var wait_frames := 0
	while true:
		wait_frames += 1
		if wait_frames > 920:
			print("FAIL global physics watchdog")
			failed += 1
			break
		var done := true
		for walker in walkers:
			if not walker.finished:
				done = false
		if done:
			break
		await physics_frame
	for i in range(walkers.size()):
		var walker: CharacterBody3D = walkers[i]
		var x: float = offsets[i]
		var label := "x=" + str(x)
		check(walker.ticks > 300 and walker.ticks < 900, label + " bounded physics")
		check(walker.reached_top, label + " reached upper landing")
		check(walker.phase == 1 and walker.position.z > .8, label + " returned")
		check(abs(walker.position.y - .8) < .025 and walker.is_on_floor(), label + " grounded at end")
		check(walker.lifts > 0 and walker.lifts <= 18, label + " bounded lifts")
		check(walker.floor_ticks > walker.ticks * .8, label + " >80pct grounded")
		check(walker.max_y < 3.83, label + " no excessive vertical escape")
		check(walker.max_tick_distance < .26, label + " bounded tick displacement")
		check(abs(walker.position.x - x) < .005, label + " lateral alignment")
		print("STAIR_LATERAL_SAMPLE x=", x, " ticks=", walker.ticks, " lifts=", walker.lifts, " floor_ticks=", walker.floor_ticks, " top=", walker.reached_top, " final=", walker.position)
	print("STAIR_LATERAL ", passed, "/", passed + failed, " failed=", failed)
	demo.free()
	quit(0 if failed == 0 else 1)
