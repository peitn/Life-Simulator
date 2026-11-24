extends RefCounted
const LotGrid = preload("res://scripts/world/lot_grid.gd")
const LotNav = preload("res://scripts/world/lot_nav.gd")
static func run() -> Dictionary:
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(10.0, 10.0))
	lot.rebuild()
	var a: Dictionary = lot.build_wall(20, 0, 20, 16, 0.0, "Test")
	var b: Dictionary = lot.build_wall(20, 20, 20, 40, 0.0, "Test")
	var failures: Array = []
	if not a.get("ok", false) or not b.get("ok", false):
		failures.append("initial_wall_build")
	var open_route: Dictionary = LotNav.plan(lot, Vector2(2.0, 4.5), Vector2(8.0, 4.5))
	if String(open_route.get("mode", "")) != "route":
		failures.append("opening_not_traversable")
	var bridge: Dictionary = lot.build_wall(20, 16, 20, 20, 0.0, "Test")
	if not bridge.get("ok", false):
		failures.append("bridge_build")
	var closed_route: Dictionary = LotNav.plan(lot, Vector2(2.0, 4.5), Vector2(8.0, 4.5))
	if String(closed_route.get("mode", "")) != "none":
		failures.append("closed_wall_traversable")
	return {"total": 4, "failed": failures}
