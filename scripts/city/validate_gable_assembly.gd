extends SceneTree
# Read-only integration regression for the saved front/rear triangular gables.
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("PASS " if ok else "FAIL ") + label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load("res://scenes/city/roof_assembly_demo.tscn") as PackedScene
	check(packed != null, "saved roof demo loads")
	if packed == null:
		quit(1)
		return
	var fixture := packed.instantiate() as Node3D
	check(fixture != null, "demo root is spatial")
	if fixture == null:
		quit(1)
		return
	root.add_child(fixture)
	var gables: Array[Node3D] = []
	var roofs: Array[Node3D] = []
	var ceilings: Array[Node3D] = []
	for name in ["GableFront", "GableRear"]:
		var node := fixture.get_node_or_null(name) as Node3D
		check(node != null, name + " exists")
		if node == null:
			fixture.free()
			quit(1)
			return
		gables.append(node)
	for i in range(2):
		var roof := fixture.get_node_or_null("Roof" + str(i)) as Node3D
		var ceiling := fixture.get_node_or_null("Ceiling" + str(i)) as Node3D
		check(roof != null and ceiling != null, "roof and ceiling " + str(i))
		if roof == null or ceiling == null:
			fixture.free()
			quit(1)
			return
		roofs.append(roof)
		ceilings.append(ceiling)
	if "--inject-shift" in OS.get_cmdline_user_args():
		gables[1].position.z -= 0.1
	var bodies: Array[StaticBody3D] = []
	for i in range(2):
		var gable := gables[i]
		var expected_position := Vector3(0, 3, 0 if i == 0 else -3.88)
		check(gable.position.distance_to(expected_position) < 0.0001, "gable placement " + str(i))
		check(gable.basis.is_equal_approx(Basis.IDENTITY), "gable rotation " + str(i))
		var body := gable.get_node_or_null("Collision") as StaticBody3D
		check(body != null, "gable collision body " + str(i))
		if body == null:
			fixture.free()
			quit(1)
			return
		check(body.collision_layer == 1 and body.collision_mask == 1, "gable collision mask " + str(i))
		check(body.get_child_count() == 1, "single collider " + str(i))
		var shape_node := body.get_child(0) as CollisionShape3D
		check(shape_node != null and not shape_node.disabled, "enabled collision shape " + str(i))
		if shape_node == null:
			fixture.free()
			quit(1)
			return
		check(shape_node.shape is ConvexPolygonShape3D, "convex prism " + str(i))
		if not shape_node.shape is ConvexPolygonShape3D:
			fixture.free()
			quit(1)
			return
		check((shape_node.shape as ConvexPolygonShape3D).points.size() == 6, "six prism corners " + str(i))
		bodies.append(body)
		var gable_end_z := 0.0 if i == 0 else -0.12
		var roof_end_z := 0.0 if i == 0 else -2.0
		for x in [0.05, 0.25, 0.5, 1.0, 1.5, 1.75, 1.95]:
			var rise := 0.6 * minf(x, 2.0 - x)
			var top := gable.to_global(Vector3(x, rise, gable_end_z))
			var roof_underside := roofs[i].to_global(Vector3(x, rise, roof_end_z))
			check(top.distance_to(roof_underside) < 0.0001, "gable roof edge " + str(i) + "/" + str(x))
			var bottom := gable.to_global(Vector3(x, 0, gable_end_z))
			var ceiling_top := ceilings[i].to_global(Vector3(x, 0.2, roof_end_z))
			check(bottom.distance_to(ceiling_top) < 0.0001, "gable ceiling edge " + str(i) + "/" + str(x))
	await physics_frame
	await physics_frame
	var space := fixture.get_world_3d().direct_space_state
	for i in range(2):
		var exterior_z := 0.4 if i == 0 else -4.4
		var interior_z := -0.4 if i == 0 else -3.6
		var expected_hit_z := 0.0 if i == 0 else -4.0
		for x in [0.05, 0.25, 0.5, 1.0, 1.5, 1.75, 1.95]:
			var y := 3.0 + 0.3 * minf(x, 2.0 - x)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, y, exterior_z), Vector3(x, y, interior_z), 1)
			var hit := space.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider == bodies[i], "gable exterior ray " + str(i) + "/" + str(x))
			if not hit.is_empty():
				check(absf(hit.position.z - expected_hit_z) < 0.002, "gable face depth " + str(i) + "/" + str(x))
				var outward := Vector3.FORWARD if i == 1 else Vector3.BACK
				check(hit.normal.dot(outward) > 0.99, "gable outward normal " + str(i) + "/" + str(x))
	fixture.free()
	print("GABLE_ASSEMBLY_RESULT=", passed, " passed ", failed, " failed")
	quit(0 if failed == 0 else 1)