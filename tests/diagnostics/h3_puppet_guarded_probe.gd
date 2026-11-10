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
	var puppet_source := FileAccess.get_file_as_string("res://scripts/sim/sim_puppet.gd")
	if FileAccess.get_sha256("res://scripts/sim/sim_puppet.gd") != "725d228d40a97711ad6757b71cc45dbfbd3add64862696682a92d875316d6554":
		push_error("H3 puppet production hash changed")
		get_tree().quit(2)
		return
	var puppet_preload := "const SimVisual := preload(\"res://scripts/sim/sim_visual.gd\")"
	if puppet_source.count(puppet_preload) != 1 or puppet_source.count("visual = SimVisual.new()") != 1 or puppet_source.count("if visual != null:\n\t\tvisual.apply(") != 1:
		push_error("H3 puppet patch anchors missing/ambiguous")
		get_tree().quit(2)
		return
	puppet_source = puppet_source.replace(puppet_preload, "var H3VisualScript: Script")
	puppet_source = puppet_source.replace("visual = SimVisual.new()", "visual = H3VisualScript.new()")
	puppet_source = puppet_source.replace("if visual != null:\n\t\tvisual.apply(", "if visual != null and visual.get(\"_h3_state\") == \"ready\":\n\t\tvisual.apply(")
	var puppet_script := GDScript.new()
	puppet_script.source_code = puppet_source
	if puppet_script.reload() != OK:
		push_error("H3 in-memory puppet compilation failed")
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
	# Real SimPuppet public look path with test-only guarded SimVisual injection.
	var validator = load("res://scripts/character/character_validator.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var randomizer = load("res://scripts/character/character_randomizer.gd")
	var public_initial: Dictionary = validator.repaired(randomizer.generate(rng), {"public_only": true})
	check(bool(validator.validate(public_initial, {"mode":"strict", "public_only":true}).get("ok",false)), "fixture public snapshot valid")
	var public_updated: Dictionary = public_initial.duplicate(true)
	public_updated["body"]["height_cm"] = 181.0
	check(bool(validator.validate(public_updated, {"mode":"strict", "public_only":true}).get("ok",false)), "updated public snapshot valid")
	var puppet := Node3D.new()
	puppet.set_script(puppet_script)
	puppet.set("H3VisualScript", script)
	puppet.call("setup_from_data", {"name":"Fixture","grammar":"f","look":public_initial}, null)
	add_child(puppet)
	var pv: Node3D = puppet.get("visual")
	check(pv != null and String(pv.get("_h3_state")) == "building", "puppet visual begins building")
	check(not bool(puppet.get("has_private")) and (puppet.get("net_detail") as Dictionary).is_empty(), "puppet has no private state")
	var invalid_private: Dictionary = public_updated.duplicate(true)
	invalid_private["uid"] = "0123456789abcdef0123456789abcdef"
	puppet.call("apply_public_look", invalid_private)
	check((puppet.get("look") as Dictionary) == public_initial, "private UID update rejected")
	puppet.call("apply_public_look", public_updated)
	check((puppet.get("look") as Dictionary) == public_updated, "valid public update accepted")
	check(bool(pv.get("_h3_pending_valid")), "public update deferred during build")
	var puppet_deadline: int = Time.get_ticks_msec() + 35000
	while String(pv.get("_h3_state")) != "ready" and Time.get_ticks_msec() < puppet_deadline:
		await get_tree().process_frame
	var puppet_ready: bool = String(pv.get("_h3_state")) == "ready"
	check(puppet_ready, "puppet guarded visual ready within deadline")
	if puppet_ready:
		var resolver = load("res://scripts/character/appearance_resolver.gd")
		check((pv.get("look_params") as Dictionary) == resolver.resolve(public_updated), "puppet last public appearance applied after ready")
		check(not bool(pv.get("_h3_pending_valid")), "puppet pending look cleared")
		check(not bool(puppet.get("has_private")), "puppet still has no private state")
	puppet.queue_free()
	await get_tree().process_frame
	var cancelled_puppet := Node3D.new()
	cancelled_puppet.set_script(puppet_script)
	cancelled_puppet.set("H3VisualScript", script)
	cancelled_puppet.call("setup_from_data", {"name":"Fixture","look":public_initial}, null)
	add_child(cancelled_puppet)
	var cancel_visual: Node3D = cancelled_puppet.get("visual")
	var cancel_weak: WeakRef = weakref(cancel_visual)
	cancelled_puppet.queue_free()
	for i in range(6):
		await get_tree().process_frame
	check(cancel_weak.get_ref() == null, "puppet removal cancels unfinished visual")
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
