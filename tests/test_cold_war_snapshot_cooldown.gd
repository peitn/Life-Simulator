extends RefCounted
const ColdWar = preload("res://scripts/sim/cold_war.gd")

func run() -> Dictionary:
	var failures: Array = []
	var w = ColdWar.new()
	w.note("A", "B", "argue", 200.0)
	w.note("A", "B", "argue", 201.0)
	var snapshot := w.to_dict()
	var outcome := w.resolve_clear_air("A", "B", 1.0, 0.0, 210.0)
	if outcome != "breakthrough":
		failures.append("deterministic breakthrough did not occur")
	if w.stage("A", "B") != 0:
		failures.append("live branch did not clear stage")
	var restored = ColdWar.new()
	restored.from_dict(snapshot)
	if restored.stage("A", "B") != 1:
		failures.append("snapshot stage not restored")
	if restored.clear_air_block("A", "B", 210.0) != "":
		failures.append("snapshot inherited future clear-air cooldown")
	if restored.recent_argues("A", "B", 100.0) != 0:
		failures.append("future arguments counted at rewind")
	if restored.recent_argues("A", "B", 211.0) != 2:
		failures.append("arguments missing after catch-up")
	return {"passed":6-failures.size(),"total":6,"failures":failures}
