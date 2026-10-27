extends RefCounted
# Read-only verification of the persistent M1 gable assembly manifest.
static func audit(inject_bad_visual: bool = false, inject_bad_run: bool = false) -> Dictionary:
	var checks := 0
	var failures: Array[String] = []
	var path := "res://docs/city/gable_infill_manifest.json"
	checks += 1
	if not FileAccess.file_exists(path):
		failures.append("manifest missing")
		return {"checks": checks, "failures": failures, "ok": false}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	checks += 1
	if not (parsed is Dictionary):
		failures.append("manifest invalid JSON object")
		return {"checks": checks, "failures": failures, "ok": false}
	var d: Dictionary = parsed
	var tests = d.get("tests", {})
	checks += 1
	if not (tests is Dictionary):
		failures.append("tests is not an object")
		return {"checks": checks, "failures": failures, "ok": false}
	var visual = tests.get("assembly_visual", null)
	if inject_bad_visual:
		visual = "\n## unstructured checkpoint text"
	checks += 1
	if not (visual is Dictionary):
		failures.append("assembly_visual must be structured metadata, not pasted Markdown")
		return {"checks": checks, "failures": failures, "ok": false}
	checks += 1
	if visual.get("render_count", 0) != 2 or visual.get("render_exit", -1) != 0 or visual.get("timed_out", true):
		failures.append("render completion metadata mismatch")
	checks += 1
	if visual.get("gable_checks", -1) != 92 or visual.get("roof_checks", -1) != 54:
		failures.append("recorded acceptance counts mismatch")
	if inject_bad_run:
		visual = visual.duplicate()
		visual["run_id"] = "wrong-run"
	checks += 1
	if d.get("assembly_visual_run", "") != "city-1792996214-204204" or visual.get("run_id", "") != d.get("assembly_visual_run", ""):
		failures.append("visual run ID mismatch")
	var images = d.get("assembly_previews", [])
	checks += 1
	if not (images is Array) or images.size() != 2:
		failures.append("expected exactly two assembly previews")
	else:
		for item in images:
			checks += 1
			if not FileAccess.file_exists("res://" + str(item)):
				failures.append("missing preview " + str(item))
	for key in ["assembly_scene", "assembly_validator", "glb", "source", "saved_scene"]:
		checks += 1
		if not FileAccess.file_exists("res://" + str(d.get(key, ""))):
			failures.append("missing dependency " + key)
	checks += 1
	if not str(tests.get("assembly", "")).contains("92/92"):
		failures.append("assembly regression record missing")
	return {"checks": checks, "failures": failures, "ok": failures.is_empty()}
