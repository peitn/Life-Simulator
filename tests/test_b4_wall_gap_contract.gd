extends RefCounted
## B4 contract probe: a one-cell gap between two collinear wall segments
## is permitted by the existing validator. This is NOT a door placement API.
const V = preload("res://scripts/world/build_wall_validation.gd")
static func run() -> Dictionary:
	var left = {"x0":0,"z0":2,"x1":2,"z1":2}
	var right = {"x0":3,"z0":2,"x1":5,"z1":2}
	var bridge = {"x0":2,"z0":2,"x1":3,"z1":2}
	var tests = [
		["gap_allowed", [left,right], ""],
		["gap_filled", [left,bridge,right], ""],
		["overlap_rejected", [left,{"x0":1,"z0":2,"x1":3,"z1":2},right], "overlap"],
		["gap_reverse_order", [right,left], ""],
		["gap_not_crossing", [left,right,{"x0":2,"z0":1,"x1":2,"z1":3}], ""]
	]
	var failed: Array = []
	for t in tests:
		var got: String = V.validate(t[1], 6, 5)
		if got != t[2]:
			failed.append({"case":t[0],"expected":t[2],"got":got})
	return {"total":tests.size(),"failed":failed}
