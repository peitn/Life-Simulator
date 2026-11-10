extends Node
## Isolated H3 experiment. In-memory source patch only; NEVER use this coroutine
## variant in production: _built becomes true before async completion.
## Compare separate --headless processes with '-- baseline' and '-- staged'.
const SOURCE := "res://scripts/sim/sim_visual.gd"
const SOURCE_SHA := "2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3"
var _last_tick: int = 0
var _max_gap_ms: float = 0.0
var _frames: int = 0

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_tick != 0:
		_max_gap_ms = maxf(_max_gap_ms, float(now - _last_tick) / 1000.0)
	_last_tick = now
	_frames += 1

func _patch(src: String, start: String, ending: String, before: String, after: String) -> String:
	var a := src.find(start)
	var b := src.find(ending, a + start.length()) if a >= 0 else -1
	if a < 0 or b <= a:
		push_error("H3 yield probe missing section: " + start)
		return ""
	var section := src.substr(a, b - a)
	if section.count(before) != 1:
		push_error("H3 yield probe missing/ambiguous anchor in " + start + ": " + before.strip_edges())
		return ""
	return src.substr(0, a) + section.replace(before, after) + src.substr(b)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if not args.is_empty() else "baseline"
	if mode not in ["baseline", "staged"] or FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 yield probe invalid mode or production source hash changed")
		get_tree().quit(2)
		return
	var src := FileAccess.get_file_as_string(SOURCE)
	# A completion marker is necessary because Node._ready does not await coroutines.
	src = _patch(src, "func _build() -> void:", "func _build_primitives()", "\t_place_overhead()\n", "\t_place_overhead()\n\tset_meta(\"h3_probe_complete\", true)\n")
	if src.is_empty():
		get_tree().quit(2)
		return
	if mode == "staged":
		var edits: Array = [
			["func _ready() -> void:", "func anatomy_view()", "\t_build()\n", "\tawait _build()\n"],
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
	var err := script.reload()
	if err != OK:
		push_error("H3 yield probe in-memory compile error " + str(err))
		get_tree().quit(2)
		return
	var visual := Node3D.new()
	visual.set_script(script)
	await get_tree().process_frame
	await get_tree().process_frame
	var start := Time.get_ticks_usec()
	add_child(visual)
	var deadline := start + 35000000
	while not visual.has_meta("h3_probe_complete") and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	var done := visual.has_meta("h3_probe_complete")
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var model := visual.get_node_or_null("Body/Model")
	var meshes := visual.find_children("*", "MeshInstance3D", true, false).size()
	var labels := visual.find_children("*", "Label3D", true, false).size()
	var skeletons := model.find_children("*", "Skeleton3D", true, false).size() if model != null else 0
	var passed := done and model != null and meshes > 0 and labels > 0 and skeletons > 0
	await get_tree().process_frame
	var result := {"mode": mode, "done": done, "elapsed_ms": elapsed_ms,
		"max_process_gap_ms": _max_gap_ms, "frames": _frames,
		"mesh_count": meshes, "model_present": model != null,
		"label_count": labels, "skeleton_count": skeletons}
	print("H3_YIELD_RESULT ", JSON.stringify(result))
	visual.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)