extends Node3D
## Main-house automatic hinged door. Uses the existing real M1 door:
## AnimatableBody3D leaf + collision, 0..90° sweep and anti-clipping checks.
## Local visual/world mechanism only; not an authenticated multiplayer RPC.
@export var trigger_distance := 1.9
@export var close_distance := 2.65
var _door: Node3D
var _near := false
var _elapsed := 0.0

func _ready() -> void:
	_door = get_node_or_null("HingedDoor")
	if _door == null or not _door.has_method("request_open"):
		push_error("AutoDoor requires M1 HingedDoor child")
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	var sims_root := get_parent().get_node_or_null("Sims")
	if sims_root == null or _door == null:
		return
	var center: Vector3 = _door.to_global(Vector3(1.0, 0, 0))
	var nearest := INF
	for actor in sims_root.get_children():
		if actor is Node3D:
			nearest = minf(nearest, (actor as Node3D).global_position.distance_to(center))
	var want_open := nearest < (close_distance if _near else trigger_distance)
	if want_open == _near:
		return
	_near = want_open
	_door.request_open(want_open)

func is_open() -> bool:
	return _door != null and _door.has_method("is_open") and _door.is_open()

func door_node() -> Node3D:
	return _door
