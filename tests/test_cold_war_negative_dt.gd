extends RefCounted
const ColdWar = preload("res://scripts/sim/cold_war.gd")
func run() -> Dictionary:
	var failures: Array = []
	var w = ColdWar.new()
	w.note("A", "B", "argue", 200.0)
	w.note("A", "B", "argue", 201.0)
	var before := JSON.stringify(w.to_dict())
	w.decay(-30.0, 100.0)
	if JSON.stringify(w.to_dict()) != before:
		failures.append("negative dt mutated state")
	if w.stage("A", "B") != 1:
		failures.append("negative dt changed stage")
	w.decay(0.0, 201.0)
	if not is_equal_approx(w.heat("A", "B"), 0.5):
		failures.append("zero dt changed heat")
	w.decay(10.0, 211.0)
	if not (w.heat("A", "B") < 0.5 and w.heat("A", "B") > 0.0):
		failures.append("positive dt did not cool")
	return {"passed": 4 - failures.size(), "total": 4, "failures": failures}
