extends SceneTree
const Grid = preload("res://scripts/world/lot_grid.gd")
const Finder = preload("res://scripts/world/lot_pathfinder.gd")
var checks := 0
var fails := 0

func expect_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		fails += 1
		push_error("B3 FAIL: " + label)

func _initialize() -> void:
	var lot = Grid.new()
	lot.setup(Vector2.ZERO, Vector2(1.25, 1.25))
	var path: Array[Vector2i] = Finder.find_path(lot, Vector2i(0, 0), Vector2i(4, 4))
	expect_true(path.size() == 9, "open shortest Manhattan route")
	expect_true(path.front() == Vector2i(0, 0) and path.back() == Vector2i(4, 4), "endpoints")
	lot.add_static_rect(Rect2(Vector2(0.5, 0.0), Vector2(0.25, 1.0)))
	lot.rebuild()
	var detour: Array[Vector2i] = Finder.find_path(lot, Vector2i(0, 0), Vector2i(4, 0))
	expect_true(detour.size() == 13, "detour around partial static barrier")
	for cell in detour:
		expect_true(lot._walkable(cell.y * lot.gw + cell.x), "detour stays walkable")
	lot.add_static_rect(Rect2(Vector2(0.5, 1.0), Vector2(0.25, 0.25)))
	lot.rebuild()
	expect_true(Finder.find_path(lot, Vector2i(0, 0), Vector2i(4, 0)).is_empty(), "complete barrier unreachable")
	expect_true(Finder.find_path(lot, Vector2i(2, 0), Vector2i(4, 0)).is_empty(), "blocked start")
	expect_true(Finder.find_path(lot, Vector2i(-1, 0), Vector2i(4, 0)).is_empty(), "negative start")
	expect_true(Finder.find_path(lot, Vector2i(0, 0), Vector2i(5, 0)).is_empty(), "out of bounds goal")
	expect_true(Finder.find_path(lot, Vector2i(0, 0), Vector2i(0, 0)).size() == 1, "same cell")
	print("B3_PATH_REGRESSION ", checks - fails, "/", checks, " PASS" if fails == 0 else " FAIL")
	quit(0 if fails == 0 else 1)
