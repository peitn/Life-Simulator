extends "res://tests/test_base.gd"
const Store := preload("res://scripts/save/server_world_store.gd")
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var d := {"sims":[{"node":"A"},{"node":"B"}],"server":{"v":1,"own":["A"],"held":[],"host_sim":""}}
	check(bool(Store.validate_server_section(d).get("ok",false)), "valid")
	for change in [{"v":2},{"own":["A","A"]},{"own":["Ghost"]},{"host_sim":"B"},{"extra":true},{"held":[{"hash":"z".repeat(64),"sim":"A","name":"Alice","own":true,"remaining":20.0}]},{"held":[{"hash":"a".repeat(64),"sim":"A","name":"Alice","own":false,"remaining":20.0}]},{"held":[{"hash":"a".repeat(64),"sim":"A","name":"Alice","own":true,"remaining":-1.0}]}]:
		var x: Dictionary=d.duplicate(true)
		for key in change:
			x["server"][key]=change[key]
		check(not bool(Store.validate_server_section(x).get("ok",false)), "reject "+JSON.stringify(change).substr(0,40))
	section("Type and hash boundary rejection reasons")
	var bad: Array = [
		[{"v": 1.0}, "unsupported_server_version"],
		[{"own": "A"}, "bad_own"],
		[{"held": {}}, "bad_held"],
		[{"host_sim": 7}, "bad_host_sim"],
		[{"held": [{"hash": "a".repeat(63), "sim": "A", "name": "Alice", "own": true, "remaining": 1.0}]}, "bad_held_hash"],
		[{"held": [{"hash": "a".repeat(65), "sim": "A", "name": "Alice", "own": true, "remaining": 1.0}]}, "bad_held_hash"],
		[{"held": [{"hash": "A".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": 1.0}]}, "bad_held_hash"],
		[{"held": [{"hash": "a".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": "1"}]}, "bad_held_remaining"],
		[{"held": [{"hash": "a".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": 0.0}]}, "bad_held_remaining"],
		[{"held": [{"hash": "a".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": 86401.0}]}, "bad_held_remaining"]
	]
	for i in bad.size():
		var x: Dictionary = d.duplicate(true)
		for key in bad[i][0]:
			x["server"][key] = bad[i][0][key]
		var result: Dictionary = Store.validate_server_section(x)
		check(not bool(result.get("ok", false)) and String(result.get("reason", "")) == String(bad[i][1]), "boundary %d: %s" % [i, bad[i][1]], JSON.stringify(result))

	section("Missing and null mandatory server keys")
	for key in ["v", "own", "held", "host_sim"]:
		var absent: Dictionary = d.duplicate(true)
		absent["server"].erase(key)
		var expected: String = {"v":"unsupported_server_version","own":"bad_own","held":"bad_held","host_sim":"bad_host_sim"}[key]
		var missing_result: Dictionary = Store.validate_server_section(absent)
		check(not bool(missing_result.get("ok", false)) and String(missing_result.get("reason", "")) == expected, "missing "+key, JSON.stringify(missing_result))
		var null_case: Dictionary = d.duplicate(true)
		null_case["server"][key] = null
		var null_result: Dictionary = Store.validate_server_section(null_case)
		check(not bool(null_result.get("ok", false)) and String(null_result.get("reason", "")) == expected, "null "+key, JSON.stringify(null_result))
	section("Combined invalid inputs and deterministic rejection order")
	var combined: Array = [
		[{"v": 2, "own": "A"}, "unsupported_server_version"],
		[{"own": ["A", "A"], "held": {}}, "bad_own"],
		[{"held": [{"hash": "z".repeat(64), "sim": "Ghost", "name": "Alice", "own": true, "remaining": -1.0}]}, "bad_held_hash"],
		[{"host_sim": "Ghost", "held": [{"hash": "a".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": -1.0}]}, "bad_held_remaining"]
	]
	for pair in combined:
		var sample: Dictionary = d.duplicate(true)
		for key in pair[0]:
			sample["server"][key] = pair[0][key]
		var verdict: Dictionary = Store.validate_server_section(sample)
		check(not bool(verdict.get("ok", false)) and String(verdict.get("reason", "")) == String(pair[1]), "combined rejection "+String(pair[1]), JSON.stringify(verdict))
	section("Duplicate reconnect records")
	var h1: Dictionary = {"hash": "a".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": 30.0}
	var hash_case: Dictionary = d.duplicate(true)
	hash_case["server"]["held"] = [h1, {"hash": "a".repeat(64), "sim": "B", "name": "Bob", "own": false, "remaining": 30.0}]
	var hash_verdict: Dictionary = Store.validate_server_section(hash_case)
	check(not bool(hash_verdict.get("ok", false)) and String(hash_verdict.get("reason", "")) == "bad_held_hash", "duplicate token hash", JSON.stringify(hash_verdict))
	var sim_case: Dictionary = d.duplicate(true)
	sim_case["server"]["held"] = [h1, {"hash": "b".repeat(64), "sim": "A", "name": "Alice", "own": true, "remaining": 30.0}]
	var sim_verdict: Dictionary = Store.validate_server_section(sim_case)
	check(not bool(sim_verdict.get("ok", false)) and String(sim_verdict.get("reason", "")) == "bad_held_sim", "duplicate reconnect sim", JSON.stringify(sim_verdict))
	finish("H4b metadata")