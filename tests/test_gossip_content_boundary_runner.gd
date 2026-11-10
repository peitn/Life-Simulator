extends Node
const Boundary = preload("res://tests/test_gossip_content_boundary.gd")
func _ready() -> void:
	var result: Dictionary = Boundary.run()
	for key in result.get("results", {}).keys():
		print("GOSSIP_BOUNDARY ", key, "=", result["results"][key])
	var expected: Array = ["panic_disabled", "panic_enabled", "drinking_disabled", "drinking_enabled", "self_witness", "empty_witness"]
	var checks: Dictionary = result.get("results", {})
	var valid: bool = result.get("ok", false) == true and result.get("checks", 0) == expected.size() and checks.size() == expected.size()
	for key in expected:
		valid = valid and checks.get(key, false) == true
	print("GOSSIP_BOUNDARY_SUMMARY ", JSON.stringify(result))
	get_tree().quit(0 if valid else 1)
