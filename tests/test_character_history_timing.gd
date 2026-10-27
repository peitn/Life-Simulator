extends SceneTree
const History = preload("res://scripts/character/character_history.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)
func _init() -> void:
	var h = History.new()
	h.reset({"height": 0})
	h.push({"height": 1}, "Height", "height", 1000)
	h.push({"height": 2}, "Height", "height", 900)
	check(h.undo() == {"height": 1}, "backward timestamp starts a separate undo step")
	check(h.undo() == {"height": 0}, "earlier edit remains recoverable")
	h.reset({"height": 0})
	h.push({"height": 1}, "Height", "height", 1000)
	h.push({"height": 2}, "Height", "height", 1600)
	check(h.undo() == {"height": 0}, "600ms boundary still coalesces")
	check(not h.can_undo(), "coalesced drag is one step")
	check(h.redo() == {"height": 2}, "redo restores coalesced endpoint")
	h.push({"height": 3}, "Height", "height", 1601)
	check(h.undo() == {"height": 2}, "redo separates subsequent drag")
	h.push({"height": 4}, "Height", "height", 1602)
	check(not h.can_redo(), "new edit after undo invalidates redo branch")
	check(h.undo() == {"height": 2}, "new branch has its own undo baseline")
	h.reset({"height": 0})
	h.push({"height": 1}, "Height", "height", 1000)
	h.push({"height": 2}, "Height", "height", 1601)
	check(h.undo() == {"height": 1}, "601ms starts a separate undo step")
	check(h.undo() == {"height": 0}, "nonmerged first step preserved")
	h.reset({"height": 0, "width": 0})
	h.push({"height": 1, "width": 0}, "Height", "height", 1000)
	h.push({"height": 1, "width": 1}, "Width", "width", 1001)
	h.push({"height": 2, "width": 1}, "Height", "height", 1002)
	check(h.undo() == {"height": 1, "width": 1}, "interleaved property separates later height edit")
	check(h.undo() == {"height": 1, "width": 0}, "interleaved width edit remains recoverable")
	check(h.undo() == {"height": 0, "width": 0}, "interleaved first edit remains recoverable")
	print("test_character_history_timing: ", checks-failures, "/", checks)
	quit(1 if failures else 0)
