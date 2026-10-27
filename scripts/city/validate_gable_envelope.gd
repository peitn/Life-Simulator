extends SceneTree
# Read-only gable infill boundary contract; no asset, collision or scene writes.
# The open roof demo has no gable infill yet. This tests its intended envelope.
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
	check(packed != null, "saved roof assembly available")
	if packed == null:
		quit(1)
		return
	var fixture := packed.instantiate() as Node3D
	check(fixture != null, "assembly has Node3D root")
	if fixture == null:
		quit(1)
		return
	root.add_child(fixture)
	var roofs: Array[Node3D] = []
	var ceilings: Array[Node3D] = []
	for i in range(2):
		var roof := fixture.get_node_or_null("Roof" + str(i)) as Node3D
		var ceiling := fixture.get_node_or_null("Ceiling" + str(i)) as Node3D
		check(roof != null and ceiling != null, "roof and ceiling present " + str(i))
		if roof == null or ceiling == null:
			fixture.free()
			quit(1)
			return
		roofs.append(roof)
		ceilings.append(ceiling)
	if "--inject-lift" in OS.get_cmdline_user_args():
		roofs[1].position.y += 0.1 # Memory-only deliberate failure.
	await physics_frame
	await physics_frame
	var space := fixture.get_world_3d().direct_space_state
	# Near outer front/back ends, avoid the shared z=-2 seam.
	for i in range(2):
		var z := -0.1 if i == 0 else -3.9
		var roof_body := roofs[i].get_node_or_null("Collision") as StaticBody3D
		var ceiling_body := ceilings[i].get_node_or_null("Collision") as StaticBody3D
		check(roof_body != null and roof_body.collision_layer == 1, "roof collision body layer 1 end=" + str(i))
		check(ceiling_body != null and ceiling_body.collision_layer == 1, "ceiling collision body layer 1 end=" + str(i))
		for x in [0.25, 0.5, 1.0, 1.5, 1.75]:
			var rise := 0.6 * minf(x, 2.0 - x)
			var roof_ray := PhysicsRayQueryParameters3D.create(Vector3(x, 3.01, z), Vector3(x, 3.85, z), 1)
			var roof_hit := space.intersect_ray(roof_ray)
			check(roof_body != null and not roof_hit.is_empty() and roof_hit.collider == roof_body and absf(roof_hit.position.y - (3.0 + rise)) < 0.003, "gable roof underside end=" + str(i) + " x=" + str(x))
			var ceiling_ray := PhysicsRayQueryParameters3D.create(Vector3(x, 3.01, z), Vector3(x, 2.9, z), 1)
			var ceiling_hit := space.intersect_ray(ceiling_ray)
			check(ceiling_body != null and not ceiling_hit.is_empty() and ceiling_hit.collider == ceiling_body and absf(ceiling_hit.position.y - 3.0) < 0.003, "gable base ceiling top end=" + str(i) + " x=" + str(x))
	fixture.free()
	print("GABLE_ENVELOPE_RESULT=", passed, " passed ", failed, " failed")
	quit(0 if failed == 0 else 1)