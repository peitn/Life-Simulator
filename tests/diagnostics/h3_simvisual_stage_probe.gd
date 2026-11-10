extends Node
## Diagnostic-only: copy SimVisual source IN MEMORY, instrument known stage boundaries,
## instantiate twice to compare cold vs warm caches. No production source mutation.
## This is NOT H3 three-process acceptance, privacy, or performance regression gate.
const SOURCE = "res://scripts/sim/sim_visual.gd"
const SOURCE_SHA = "2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 stage probe source changed; review anchors and update expected hash")
		get_tree().quit(2)
		return
	var src: String = FileAccess.get_file_as_string(SOURCE)
	var script: GDScript = GDScript.new()
	var stages: Array = [["func _build_model() -> void:\n","func _build_model() -> void:\n\tvar __h3_t0: int = Time.get_ticks_usec()\n\tprint(\"H3_STAGE model_enter 0\")\n"],["\t\tmi.material_override = _mats[mname]\n","\t\tmi.material_override = _mats[mname]\n\tprint(\"H3_STAGE materials \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_build_hair_parts()\n","\t_build_hair_parts()\n\tprint(\"H3_STAGE hair \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_build_hand_details()\n","\t_build_hand_details()\n\tprint(\"H3_STAGE hands \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_build_foot_details()\n","\t_build_foot_details()\n\tprint(\"H3_STAGE feet \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_anim.add_animation_library(\"\", clips)\n","\t_anim.add_animation_library(\"\", clips)\n\tprint(\"H3_STAGE animations \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_apply_model_variant()\n","\t_apply_model_variant()\n\tprint(\"H3_STAGE variant \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_apply_colors()\n","\t_apply_colors()\n\tprint(\"H3_STAGE colors \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\tset_hand_pose(\"relaxed\")\n","\tset_hand_pose(\"relaxed\")\n\tprint(\"H3_STAGE pose \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_anim.play(\"idle\")\n","\t_anim.play(\"idle\")\n\tprint(\"H3_STAGE play \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["\t_build_action_props()\n","\t_build_action_props()\n\tprint(\"H3_STAGE props \", (Time.get_ticks_usec()-__h3_t0)/1000.0)\n"],["func _apply_model_variant() -> void:\n","func _apply_model_variant() -> void:\n\tvar __h3_v0: int = Time.get_ticks_usec()\n\tprint(\"H3_VARIANT enter 0\")\n"],["\tvar lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})\n","\tvar lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})\n\tprint(\"H3_VARIANT resolve \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"],["\t\tmi.visible = bool(show.get(grp, true))\n","\t\tmi.visible = bool(show.get(grp, true))\n\tprint(\"H3_VARIANT hair_requests_and_visibility \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"],["\t_apply_outfit(lp)\n","\t_apply_outfit(lp)\n\tprint(\"H3_VARIANT outfit \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"],["\tapply_body_shape(lp)\n","\tapply_body_shape(lp)\n\tprint(\"H3_VARIANT body \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"],["\tapply_face_shape(lp)\n","\tapply_face_shape(lp)\n\tprint(\"H3_VARIANT face \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"],["\t_refresh_torso_visibility(lp)\n","\t_refresh_torso_visibility(lp)\n\tprint(\"H3_VARIANT torso_visibility \", (Time.get_ticks_usec()-__h3_v0)/1000.0)\n"]]
	var sections: Array = [
		{"start": "func _build_model() -> void:", "end": "func _build_action_props()", "items": stages.slice(0, 11)},
		{"start": "func _apply_model_variant() -> void:", "end": "func _apply_outfit(lp: Dictionary) -> void:", "items": stages.slice(11)}
	]
	for block in sections:
		var a: int = src.find(block["start"])
		var b: int = src.find(block["end"], a)
		if a < 0 or b <= a:
			push_error("H3 stage probe missing function bounds")
			get_tree().quit(2)
			return
		var body: String = src.substr(a, b - a)
		for pair in block["items"]:
			var anchor: String = pair[0]
			if body.count(anchor) != 1:
				push_error("H3 stage probe ambiguous scoped anchor: " + anchor.strip_edges())
				get_tree().quit(2)
				return
			body = body.replace(anchor, pair[1])
		src = src.substr(0, a) + body + src.substr(b)
	script.source_code = src
	var err: Error = script.reload()
	if err != OK:
		push_error("H3 stage probe in-memory compilation failed: " + str(err))
		get_tree().quit(2)
		return
	for i in range(2):
		var visual := Node3D.new()
		visual.set_script(script)
		var start: int = Time.get_ticks_usec()
		get_tree().root.add_child(visual)
		await get_tree().process_frame
		print("H3_VISUAL_TOTAL ", i, " ", (Time.get_ticks_usec() - start) / 1000.0)
		visual.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
