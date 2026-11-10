extends "res://tests/diagnostics/h3_three_process.FAILING.gd"
## H3 experimental three-process fixture: unchanged inherited 17 gates.
## Replaces only client spawn function with in-memory guarded SimPuppet/SimVisual.
var _h3_guarded_scripts: Dictionary = {}
var _h3_injection_count := 0

func _world(mode: String, character_code: String = "") -> Node3D:
	var w: Node3D = super._world(mode, character_code)
	if mode == "server":
		return w
	if _h3_guarded_scripts.is_empty():
		var helper = load("res://tests/diagnostics/h3_guarded_script_builder.gd").new()
		_h3_guarded_scripts = helper.build_scripts()
		helper.free()
	if _h3_guarded_scripts.is_empty():
		push_error("H3 guarded script compilation failed; fixture must fail closed")
		get_tree().quit(2)
		return w
	var puppet_script: Script = _h3_guarded_scripts["puppet"]
	var visual_script: Script = _h3_guarded_scripts["visual"]
	var original: Callable = w.net.spawner.spawn_function
	w.net.spawner.spawn_function = func(data: Variant) -> Node:
		var node: Node = original.call(data)
		if not (node is Node3D) or not node.has_method("setup_from_data"):
			return node
		var existing: Script = node.get_script() as Script
		if existing == null or not existing.resource_path.ends_with("/sim_puppet.gd"):
			return node
		if typeof(data) != TYPE_DICTIONARY:
			push_error("H3 guarded spawn received invalid data")
			return node
		node.set_script(puppet_script)
		node.set("H3VisualScript", visual_script)
		node.call("setup_from_data", data, w)
		_h3_injection_count += 1
		_trace(mode, "guarded_puppet_injected", {"count": _h3_injection_count, "script_in_memory": true})
		return node
	_trace(mode, "guarded_spawn_hook_installed", {"script_in_memory": true})
	return w

func _spawn(role: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/diagnostics/h3_three_process_guarded.tscn", "--", "worker", _token, str(_port), role])
	if _prewarm_clients and role in ["owner", "observer"]:
		args.append("prewarm")
	if _extended_enet_timeout:
		args.append("enet-extended")
	return OS.create_process(OS.get_executable_path(), args)
