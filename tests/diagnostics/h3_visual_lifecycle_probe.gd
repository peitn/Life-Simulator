extends "res://tests/diagnostics/h3_visual_yield_probe.gd"
## Test-only guarded lifecycle over a dynamically compiled SimVisual; never production.
var failures: Array[String] = []
var cancelled_signals := 0

func check(ok: bool, label: String) -> void:
	print("H3_LIFECYCLE ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _on_cancelled_ready() -> void:
	cancelled_signals += 1

func _run() -> void:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 lifecycle source hash mismatch")
		get_tree().quit(2)
		return
	var src := FileAccess.get_file_as_string(SOURCE)
	src = src.replace("extends Node3D\n", "extends Node3D\nsignal h3_probe_ready\nvar _h3_state := \"new\"\nvar _h3_epoch := 0\nvar _h3_pending_look: Dictionary = {}\nvar _h3_pending_valid := false\n")
	src = _patch(src, "func apply_look(snap: Dictionary) -> void:", "func _ready() -> void:", "\t# Restore old clothes before wardrobe/morph changes, then hide newly resolved\n", "\tif _h3_state == \"building\":\n\t\t_h3_pending_look = snap.duplicate(true)\n\t\t_h3_pending_valid = true\n\t\treturn\n\t# Restore old clothes before wardrobe/morph changes, then hide newly resolved\n")
	if src.is_empty():
		get_tree().quit(2)
		return
	src = _patch(src, "func _ready() -> void:", "func anatomy_view()", "\t_build()\n", "\t_h3_state = \"building\"\n\t_h3_epoch += 1\n\tvar epoch: int = _h3_epoch\n\tawait _build()\n\tif not is_inside_tree() or epoch != _h3_epoch:\n\t\treturn\n\t_h3_state = \"ready\"\n\tif _h3_pending_valid:\n\t\tvar pending: Dictionary = _h3_pending_look.duplicate(true)\n\t\t_h3_pending_valid = false\n\t\tapply_look(pending)\n\th3_probe_ready.emit()\n")
	if src.is_empty():
		get_tree().quit(2)
		return
	src = src.replace("func _ready() -> void:\n", "func _exit_tree() -> void:\n\t_h3_epoch += 1\n\t_h3_state = \"cancelled\"\n\t_h3_pending_valid = false\n\nfunc _ready() -> void:\n")
	src = _patch(src, "func _build() -> void:", "func _build_primitives()", "\t_place_overhead()\n", "\t_place_overhead()\n\tset_meta(\"h3_probe_complete\", true)\n")
	var edits: Array = [
		["func _build() -> void:", "func _build_primitives()", "\t\t_build_model()\n", "\t\tawait _build_model()\n"],
		["func _build_model() -> void:", "func _build_action_props()", "\t_build_hair_parts()\n", "\t_build_hair_parts()\n\tawait get_tree().process_frame\n"],
		["func _build_model() -> void:", "func _build_action_props()", "\t_build_foot_details()\n", "\t_build_foot_details()\n\tawait get_tree().process_frame\n"],
		["func _build_model() -> void:", "func _build_action_props()", "\t_apply_model_variant()\n", "\tawait _apply_model_variant()\n"],
		["func _apply_model_variant() -> void:", "func _apply_outfit(lp: Dictionary) -> void:", "\t_apply_outfit(lp)\n", "\tawait get_tree().process_frame\n\t_apply_outfit(lp)\n"]
	]
	for edit in edits:
		src = _patch(src, edit[0], edit[1], edit[2], edit[3])
		if src.is_empty():
			get_tree().quit(2)
			return
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		push_error("H3 in-memory lifecycle compilation failed")
		get_tree().quit(2)
		return
	var visual := Node3D.new()
	visual.set_script(script)
	add_child(visual)
	check(String(visual.get("_h3_state")) == "building", "building before first yield")
	var first := {"hair": {"melanin": 0.2}}
	var latest := {"hair": {"melanin": 0.9}}
	visual.call("apply_look", first)
	await get_tree().process_frame
	check(String(visual.get("_h3_state")) == "building", "still building at mid-stage look")
	visual.call("apply_look", latest)
	check(bool(visual.get("_h3_pending_valid")), "looks deferred")
	check((visual.get("look_params") as Dictionary).is_empty(), "no partial look")
	var deadline := Time.get_ticks_msec() + 40000
	while String(visual.get("_h3_state")) != "ready" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ready := String(visual.get("_h3_state")) == "ready"
	check(ready, "ready within deadline")
	if ready:
		var resolver = load("res://scripts/character/appearance_resolver.gd")
		check((visual.get("look_params") as Dictionary).get("hair") == resolver.resolve(latest).get("hair"), "latest look wins")
		check(not bool(visual.get("_h3_pending_valid")), "pending cleared")
		check(visual.has_meta("h3_probe_complete"), "completion marker")
		var model := visual.get_node_or_null("Body/Model")
		check(model != null, "model exists")
		check(visual.find_children("*", "MeshInstance3D", true, false).size() == 35, "35 meshes")
		check(visual.find_children("*", "Label3D", true, false).size() == 1, "one label")
		check(model != null and model.find_children("*", "Skeleton3D", true, false).size() == 1, "one skeleton")
		visual.call("apply_look", first)
		check((visual.get("look_params") as Dictionary).get("hair") == resolver.resolve(first).get("hair"), "post-ready look immediate")
	visual.queue_free()
	await get_tree().process_frame
	var cancelled := Node3D.new()
	cancelled.set_script(script)
	cancelled.connect("h3_probe_ready", Callable(self, "_on_cancelled_ready"))
	add_child(cancelled)
	check(String(cancelled.get("_h3_state")) == "building", "second build begins")
	var weak: WeakRef = weakref(cancelled)
	cancelled.queue_free()
	for i in range(6):
		await get_tree().process_frame
	check(weak.get_ref() == null, "cancelled node freed")
	check(cancelled_signals == 0, "no ready signal after cancellation")
	var mid := Node3D.new()
	mid.set_script(script)
	mid.connect("h3_probe_ready", Callable(self, "_on_cancelled_ready"))
	add_child(mid)
	for i in range(2):
		await get_tree().process_frame
	check(String(mid.get("_h3_state")) == "building", "mid-stage build not ready")
	var mid_weak: WeakRef = weakref(mid)
	mid.queue_free()
	for i in range(6):
		await get_tree().process_frame
	check(mid_weak.get_ref() == null, "mid-stage cancelled node freed")
	check(cancelled_signals == 0, "no ready signal after mid-stage cancellation")
	print("H3_LIFECYCLE_RESULT ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "cancelled_ready_signals": cancelled_signals}))
	get_tree().quit(0 if failures.is_empty() else 1)
