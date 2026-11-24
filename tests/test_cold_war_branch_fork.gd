extends RefCounted
## Save-snapshot branch isolation, NOT a policy for rewinding a live ColdWar instance.
const ColdWar = preload("res://scripts/sim/cold_war.gd")
func run() -> Dictionary:
	var failures: Array = []
	var checks := 0
	var original = ColdWar.new()
	original.note("A", "B", "argue", 100.0)
	var frozen: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
	original.note("A", "B", "argue", 200.0)
	original.note("A", "B", "argue", 201.0)
	checks += 1
	if original.stage("A", "B") != 2: failures.append("original branch must reach cold war")
	var fork = ColdWar.new()
	fork.from_dict(frozen)
	checks += 1
	if fork.stage("A", "B") != 0: failures.append("fork inherited later stage")
	checks += 1
	if fork.recent_argues("A", "B", 201.0) != 1: failures.append("fork inherited later arguments")
	checks += 1
	if fork.to_dict()["pairs"]["A|B"]["stamps"] != [100.0]: failures.append("fork timestamp mismatch")
	fork.note("A", "B", "chat", 150.0)
	checks += 1
	if original.stage("A", "B") != 2 or original.recent_argues("A", "B", 201.0) != 3: failures.append("fork mutated original")
	checks += 1
	if frozen["pairs"]["A|B"]["stamps"] != [100.0]: failures.append("snapshot mutated")
	var replay = ColdWar.new()
	replay.from_dict(frozen)
	checks += 1
	if replay.recent_argues("A", "B", 201.0) != 1: failures.append("replay mismatch")
	checks += 1
	if replay.stage("A", "B") != 0: failures.append("replay stage mismatch")
	return {"passed": checks - failures.size(), "total": checks, "failures": failures, "scope": "JSON snapshot fork only; live rewind policy open"}