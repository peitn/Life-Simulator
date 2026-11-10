extends "res://tests/diagnostics/h3_visual_yield_probe.gd"
## Extracted exact source-hash-guarded patcher from h3_puppet_guarded_probe.
func build_scripts() -> Dictionary:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 lifecycle source hash mismatch")
		return {}
	var src := FileAccess.get_file_as_string(SOURCE)
	src = src.replace("extends Node3D\n", "extends Node3D\nsignal h3_probe_ready\nvar _h3_state := \"new\"\nvar _h3_epoch := 0\nvar _h3_pending_look: Dictionary = {}\nvar _h3_pending_valid := false\n")
	src = _patch(src, "func apply_look(snap: Dictionary) -> void:", "func _ready() -> void:", "\t# Restore old clothes before wardrobe/morph changes, then hide newly resolved\n", "\tif _h3_state == \"building\":\n\t\t_h3_pending_look = snap.duplicate(true)\n\t\t_h3_pending_valid = true\n\t\treturn\n\t# Restore old clothes before wardrobe/morph changes, then hide newly resolved\n")
	if src.is_empty():
		return {}
	src = _patch(src, "func _ready() -> void:", "func anatomy_view()", "\t_build()\n", "\t_h3_state = \"building\"\n\t_h3_epoch += 1\n\tvar epoch: int = _h3_epoch\n\tawait _build()\n\tif not is_inside_tree() or epoch != _h3_epoch:\n\t\treturn\n\t_h3_state = \"ready\"\n\tif _h3_pending_valid:\n\t\tvar pending: Dictionary = _h3_pending_look.duplicate(true)\n\t\t_h3_pending_valid = false\n\t\tapply_look(pending)\n\th3_probe_ready.emit()\n")
	if src.is_empty():
		return {}
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
			return {}
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		push_error("H3 in-memory lifecycle compilation failed")
		return {}
	var puppet_source := FileAccess.get_file_as_string("res://scripts/sim/sim_puppet.gd")
	if FileAccess.get_sha256("res://scripts/sim/sim_puppet.gd") != "725d228d40a97711ad6757b71cc45dbfbd3add64862696682a92d875316d6554":
		push_error("H3 puppet production hash changed")
		return {}
	var puppet_preload := "const SimVisual := preload(\"res://scripts/sim/sim_visual.gd\")"
	if puppet_source.count(puppet_preload) != 1 or puppet_source.count("visual = SimVisual.new()") != 1 or puppet_source.count("if visual != null:\n\t\tvisual.apply(") != 1:
		push_error("H3 puppet patch anchors missing/ambiguous")
		return {}
	puppet_source = puppet_source.replace(puppet_preload, "var H3VisualScript: Script")
	puppet_source = puppet_source.replace("visual = SimVisual.new()", "visual = H3VisualScript.new()")
	puppet_source = puppet_source.replace("if visual != null:\n\t\tvisual.apply(", "if visual != null and visual.get(\"_h3_state\") == \"ready\":\n\t\tvisual.apply(")
	var puppet_script := GDScript.new()
	puppet_script.source_code = puppet_source
	if puppet_script.reload() != OK:
		push_error("H3 in-memory puppet compilation failed")
		return {}
	return {"visual": script, "puppet": puppet_script}
