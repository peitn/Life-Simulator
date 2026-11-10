extends Node
## H3 diagnostic only. In-memory instrumentation; production source is never rewritten.
## Cold vs warm measurements are wall-clock brackets, not CPU-time or H3 acceptance.
const SOURCE = "res://scripts/sim/sim_visual.gd"
const SOURCE_SHA = "2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 hotspot probe source changed; refuse stale anchors")
		get_tree().quit(2)
		return
	var src: String = FileAccess.get_file_as_string(SOURCE)
	var sections: Array = [
		{
			"start": "func _apply_model_variant() -> void:",
			"end": "func _apply_outfit(lp: Dictionary) -> void:",
			"repls": [
				[
					"\t\t\tvar r := HairRig.request_mesh(part, styles[part], self)\n",
					"\t\t\tvar __h3_hair_t0: int = Time.get_ticks_usec()\n\t\t\tvar r := HairRig.request_mesh(part, styles[part], self)\n\t\t\tprint(\"H3_HOT hair_request \", part, \" \", (Time.get_ticks_usec() - __h3_hair_t0) / 1000.0, \" ready=\", r.get(\"ready\", false))\n"
				],
				[
					"\t_apply_outfit(lp)\n",
					"\tvar __h3_outfit_t0: int = Time.get_ticks_usec()\n\t_apply_outfit(lp)\n\tprint(\"H3_HOT outfit_total \", (Time.get_ticks_usec() - __h3_outfit_t0) / 1000.0)\n"
				]
			]
		},
		{
			"start": "func _apply_c5_wardrobe(lp: Dictionary) -> void:",
			"end": "func apply_body_shape(",
			"repls": [
				[
					"\t\tvar entries := GarmentBuilder.parts(lp)\n",
					"\t\tvar __h3_parts_t0: int = Time.get_ticks_usec()\n\t\tvar entries := GarmentBuilder.parts(lp)\n\t\tprint(\"H3_HOT garment_parts \", (Time.get_ticks_usec() - __h3_parts_t0) / 1000.0, \" entries=\", entries.size())\n"
				],
				[
					"\t\t\tskel.add_child(mi)\n",
					"\t\t\tvar __h3_attach_t0: int = Time.get_ticks_usec()\n\t\t\tskel.add_child(mi)\n\t\t\tprint(\"H3_HOT garment_attach \", mi.name, \" \", (Time.get_ticks_usec() - __h3_attach_t0) / 1000.0)\n"
				],
				[
					"\t\t\tmi.material_override = GarmentBuilder.material(entry, lp)\n",
					"\t\t\tvar __h3_mat_t0: int = Time.get_ticks_usec()\n\t\t\tmi.material_override = GarmentBuilder.material(entry, lp)\n\t\t\tprint(\"H3_HOT garment_material \", mi.name, \" \", (Time.get_ticks_usec() - __h3_mat_t0) / 1000.0)\n"
				]
			]
		}
	]
	for section in sections:
		var start: int = src.find(section["start"])
		var stop: int = src.find(section["end"], start + 1)
		if start < 0 or stop <= start:
			push_error("H3 hotspot probe missing function bounds: " + section["start"])
			get_tree().quit(2)
			return
		var body: String = src.substr(start, stop - start)
		for pair in section["repls"]:
			var anchor: String = pair[0]
			if body.count(anchor) != 1:
				push_error("H3 hotspot probe ambiguous scoped anchor: " + anchor.strip_edges())
				get_tree().quit(2)
				return
			body = body.replace(anchor, pair[1])
		src = src.substr(0, start) + body + src.substr(stop)
	var script: GDScript = GDScript.new()
	script.source_code = src
	var err: Error = script.reload()
	if err != OK:
		push_error("H3 hotspot probe in-memory compilation failed: " + str(err))
		get_tree().quit(2)
		return
	for i in range(2):
		var visual := Node3D.new()
		visual.set_script(script)
		var start: int = Time.get_ticks_usec()
		get_tree().root.add_child(visual)
		await get_tree().process_frame
		print("H3_HOT visual_total ", i, " ", (Time.get_ticks_usec() - start) / 1000.0)
		visual.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
