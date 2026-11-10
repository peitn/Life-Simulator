extends "res://tests/test_base.gd"
## Regression: shower outfit rendering, held book alignment, and visible
## dirty dishes tied to legitimate cooking completion (30 October 2026).
const Main := preload("res://main.gd")

func _ready() -> void:
	watchdog_seconds = 70.0
	_run.call_deferred()


func _run() -> void:
	var world := Main.new()
	add_child(world)
	await get_tree().process_frame
	var visual = world.sims[0].visual
	section("Shower hides clothes without modifying canonical wardrobe")
	check(visual != null and visual.uses_model(), "real skinned visual exists")
	# Main uses the game asset path (async C5 wardrobe since 7 Nov 2026): the first frame shows the
	# GLB placeholder clothes; wait for the authored garments instead of assuming a synchronous build.
	var dressed: bool = await wait_until(func(): return not visual.wardrobe_waiting(), 60.0)
	check(dressed, "authored wardrobe ready (async game path)")
	var garments: Array = []
	for item in visual._model.find_children("*", "MeshInstance3D", true, false):
		if item.name.begins_with("C5_"):
			garments.append(item)
	check(garments.size() >= 3, "top/bottom/shoes have actual C5 garment meshes")
	var originally_visible := 0
	for item in garments:
		if item.visible:
			originally_visible += 1
	var old_sig: String = visual._c5_signature
	visual.apply("stand", 0.0, "spokojeny", "Test", "Sprchuje se", "", false, "shower")
	var during := 0
	for item in garments:
		if item.visible:
			during += 1
	check(during == 0, "shirt, pants, shoes are hidden for shower")
	check(visual._c5_signature == old_sig, "wardrobe identity is unchanged while showering")
	visual.apply("stand", 0.0, "spokojeny", "Test", "Stojí", "", false, "")
	var restored := 0
	for item in garments:
		if item.visible:
			restored += 1
	check(restored == originally_visible, "original outfit visibility restored after shower")
	section("Open book sits between the two hands at reading pose")
	visual.apply("stand", 0.0, "spokojeny", "Test", "Čte", "", false, "read")
	visual._anim.play("read")
	visual._anim.seek(0.8, true)
	var sk = visual._skeleton()
	sk.force_update_all_bone_transforms()
	var left: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("hand_l")).origin)
	var right: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("hand_r")).origin)
	var center: Vector3 = (left + right) * 0.5
	var book: Vector3 = visual._read_book.global_position
	check(visual._read_book.visible, "open book appears only during read")
	check(visual._read_book.get_parent().bone_name == "chest", "book no longer inherits right-wrist rotation")
	check(book.distance_to(center) < 0.16, "book is close to midpoint of both animated palms",
		"book %s, hands midpoint %s" % [book, center])
	check(absf(book.x - center.x) < 0.06, "book centered between left and right palms")
	visual.apply("stand", 0.0, "spokojeny", "Test", "Přestala číst", "", false, "")
	check(not visual._read_book.visible, "book is removed from view at action end")
	section("Dirty plates appear only after a qualified cooking event")
	var dishes := world.get_node_or_null("DirtyDishes") as Node3D
	check(dishes != null, "world includes dish meshes at the actual kitchen countertop")
	if dishes != null:
		check(not dishes.visible, "clean counter at start")
		check(dishes.get_child_count() >= 6, "three dirty plates and accompanying cutlery/cup")
		var chef = world.sims[0]
		var now := float(world.clock.total_minutes)
		world.dynamics._prev_acting[chef.sim_name] = "cook"
		world.dynamics._cooked[chef.sim_name] = 1.0
		world.dynamics.tick(world.sims, world.clock.get_hour(), now)
		world._on_time_advanced(0.0)
		check(not dishes.visible, "cancelled cooking too short does not create dishes")
		world.dynamics._prev_acting[chef.sim_name] = "cook"
		world.dynamics._cooked[chef.sim_name] = 25.0
		world.dynamics.tick(world.sims, world.clock.get_hour(), now)
		world._on_time_advanced(0.0)
		check(dishes.visible and world.dynamics.has_dirty_dishes(now),
			"qualified completed cooking creates physical dirty plates")
		world.dynamics._dirty_dishes_until = now - 1.0
		world._on_time_advanced(0.0)
		check(not dishes.visible, "dirty plates disappear after cleanup/expiry")
	world.queue_free()
	await get_tree().process_frame
	finish("test_action_visual_consistency")
