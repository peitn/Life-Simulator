extends Node3D
## Life-sim kamera: orbit kolem bodu, zoom kolečkem, posun WASD / šipkami.
## Pravé tlačítko myši = otáčení, prostřední = posun.

var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-38.0)
var distance := 18.0
var min_distance := 4.0
var max_distance := 45.0
var pan_speed := 12.0
var camera: Camera3D

var _target_distance := 18.0
var _rotating := false
var _panning := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = maxf(min_distance, _target_distance * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = minf(max_distance, _target_distance * 1.12)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			yaw -= mm.relative.x * 0.005
			pitch = clampf(pitch - mm.relative.y * 0.004, deg_to_rad(-85.0), deg_to_rad(-8.0))
		elif _panning:
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * 0.002 * distance)


func _pan(v: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	position += right * v.x - fwd * v.y
	position.x = clampf(position.x, -40.0, 40.0)
	position.z = clampf(position.z, -40.0, 40.0)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	# Když hráč píše do chatu, klávesy kamerou nehýbou.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		distance = lerpf(distance, _target_distance, clampf(delta * 8.0, 0.0, 1.0))
		_apply()
		return
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		yaw += delta * 1.5
	if Input.is_key_pressed(KEY_E):
		yaw -= delta * 1.5
	if v != Vector2.ZERO:
		_pan(Vector2(v.x, -v.y) * pan_speed * delta * (distance / 18.0))
	distance = lerpf(distance, _target_distance, clampf(delta * 8.0, 0.0, 1.0))
	_apply()


func _apply() -> void:
	if camera == null:
		return
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.transform = Transform3D(b, b * Vector3(0, 0, distance))


func focus_on(p: Vector3) -> void:
	position = Vector3(p.x, 0.0, p.z)
