extends "res://tests/test_base.gd"
## B4b regression groundwork: hinge interpolation only, no production edits.
const Door = preload("res://scripts/world/lot_door.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	section("B4b hinge interpolation")
	var holder := Node3D.new()
	add_child(holder)
	var door := Door.new()
	holder.add_child(door)
	door.set_process(false)
	check(not door.someone_near(), "no world means closed")
	door.want_open = true
	door.step(0.1)
	check(is_equal_approx(door.angle, 26.0), "opening uses bounded angular speed")
	door.step(0.0)
	check(is_equal_approx(door.angle, 26.0), "zero delta preserves partial opening")
	door.step(100.0)
	check(is_equal_approx(door.angle, Door.OPEN_DEG), "opening clamps at target")
	door.step(1.0)
	check(is_equal_approx(door.angle, Door.OPEN_DEG), "already open hinge remains clamped")
	door.want_open = false
	door.step(0.1)
	check(is_equal_approx(door.angle, 74.0), "closing uses bounded angular speed")
	door.step(-2.0)
	check(is_equal_approx(door.angle, 74.0), "negative delta cannot reverse hinge")
	door.step(100.0)
	check(is_zero_approx(door.angle), "closing clamps to zero")
	check(is_zero_approx(door.rotation_degrees.y), "visible hinge rotation follows angle")
	finish("test_b4_door_hinge")
