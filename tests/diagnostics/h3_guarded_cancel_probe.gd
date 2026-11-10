extends Node
## Test-only cancellation of guarded SimPuppet; not authoritative ENet despawn.
var failures: Array[String] = []
var ready_after_cancel := 0
func _ready() -> void:
	_run.call_deferred()
func _check(ok: bool, label: String) -> void:
	print("H3_CANCEL ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)
func _on_ready() -> void:
	ready_after_cancel += 1
func _run() -> void:
	var helper = load("res://tests/diagnostics/h3_guarded_script_builder.gd").new()
	var scripts: Dictionary = helper.build_scripts()
	helper.free()
	_check(not scripts.is_empty(), "exact-hash guarded scripts compiled")
	if scripts.is_empty():
		get_tree().quit(2)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var generated: Dictionary = load("res://scripts/character/character_randomizer.gd").generate(rng)
	var public_look: Dictionary = load("res://scripts/character/character_validator.gd").repaired(generated, {"public_only": true})
	for stage in [0, 1, 2]:
		var puppet := Node3D.new()
		puppet.set_script(scripts["puppet"])
		puppet.set("H3VisualScript", scripts["visual"])
		puppet.call("setup_from_data", {"name": "H3 Test Only", "look": public_look}, null)
		add_child(puppet)
		var visual: Node3D = puppet.get("visual")
		_check(visual != null and String(visual.get("_h3_state")) == "building", "stage %d starts building" % stage)
		if visual == null:
			puppet.queue_free()
			continue
		visual.connect("h3_probe_ready", Callable(self, "_on_ready"))
		var weak: WeakRef = weakref(visual)
		for j in range(stage):
			await get_tree().process_frame
		_check(is_instance_valid(visual) and String(visual.get("_h3_state")) == "building", "stage %d interrupted before ready" % stage)
		puppet.queue_free()
		for j in range(8):
			await get_tree().process_frame
		_check(weak.get_ref() == null, "stage %d visual freed" % stage)
		_check(ready_after_cancel == 0, "stage %d no late ready signal" % stage)
	print("H3_CANCEL_RESULT ", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "ready_after_cancel": ready_after_cancel}))
	get_tree().quit(0 if failures.is_empty() else 1)