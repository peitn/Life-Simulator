extends SceneTree
const Grid = preload("res://scripts/world/lot_grid.gd")
const Finder = preload("res://scripts/world/lot_pathfinder.gd")
var checks := 0
var failures := 0
func verify(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("B3_WALL_FAIL " + name)
func _initialize() -> void:
	var lot = Grid.new()
	lot.setup(Vector2.ZERO, Vector2(1.25, 1.25))
	var before = Finder.find_path(lot, Vector2i(0, 1), Vector2i(1, 1))
	verify(before.size() == 2, "adjacent open cells")
	var built: Dictionary = lot.build_wall(1, 1, 1, 3, 0.0)
	verify(bool(built.get("ok", false)), "real wall accepted")
	if bool(built.get("ok", false)):
		var after = Finder.find_path(lot, Vector2i(0, 1), Vector2i(1, 1))
		verify(after.size() == 4, "real wall forces detour")
		verify(after.front() == Vector2i(0, 1) and after.back() == Vector2i(1, 1), "detour endpoints")
		var valid_steps := true
		for k in range(1, after.size()):
			var a: Vector2i = after[k - 1]
			var b: Vector2i = after[k]
			var delta: Vector2i = b - a
			if absi(delta.x) + absi(delta.y) != 1:
				valid_steps = false
				break
			var edge_blocked := false
			if delta.x != 0:
				edge_blocked = lot._vedge[a.y * (lot.gw + 1) + maxi(a.x, b.x)] != 0
			else:
				edge_blocked = lot._hedge[maxi(a.y, b.y) * lot.gw + a.x] != 0
			if edge_blocked or not lot._walkable(b.y * lot.gw + b.x):
				valid_steps = false
				break
		verify(valid_steps and after.size() > 1, "every detour edge adjacent, unblocked and walkable")
		var reverse = Finder.find_path(lot, Vector2i(1, 1), Vector2i(0, 1))
		verify(reverse.size() == after.size(), "reverse wall detour same length")
		var reverse_valid: bool = reverse.size() > 1 and reverse.front() == Vector2i(1, 1) and reverse.back() == Vector2i(0, 1)
		for k in range(1, reverse.size()):
			var a: Vector2i = reverse[k - 1]
			var b: Vector2i = reverse[k]
			var d: Vector2i = b - a
			if absi(d.x) + absi(d.y) != 1 or not lot._walkable(b.y * lot.gw + b.x):
				reverse_valid = false
				break
			if (d.x != 0 and lot._vedge[a.y * (lot.gw + 1) + maxi(a.x, b.x)] != 0) or (d.y != 0 and lot._hedge[maxi(a.y, b.y) * lot.gw + a.x] != 0):
				reverse_valid = false
				break
		verify(reverse_valid, "reverse route endpoints and every edge valid")
		var removed: Dictionary = lot.remove_wall(int(built["wid"]), 1.0)
		verify(bool(removed.get("ok", false)), "real wall removed")
		verify(Finder.find_path(lot, Vector2i(0, 1), Vector2i(1, 1)).size() == 2, "direct path restored")
	print("B3_BUILT_WALL ", checks - failures, "/", checks, " PASS" if failures == 0 else " FAIL")
	quit(0 if failures == 0 else 1)