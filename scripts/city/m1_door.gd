extends Node3D
## Isolated M1 door; main-game interaction/network authority is integrated in M7.
signal state_changed(open: bool)
signal blocked
const SWEEP_RADIUS := 1.0
var moving := false
var motion_blocked := false
var _target_angle := 0.0
@onready var hinge: Node3D = $Hinge
@onready var leaf_body: AnimatableBody3D = $Hinge/LeafBody
@onready var leaf_shape: CollisionShape3D = $Hinge/LeafBody/LeafCollider

func is_open() -> bool:
	return absf(hinge.rotation.y - PI*.5) < .001

func is_closed() -> bool:
	return absf(hinge.rotation.y) < .001

func request_open(value: bool) -> bool:
	if not is_inside_tree(): return false
	_target_angle = PI*.5 if value else 0.0
	motion_blocked = false
	moving = not is_equal_approx(hinge.rotation.y, _target_angle)
	return true

func _excluded() -> Array[RID]:
	var result: Array[RID] = [leaf_body.get_rid()]
	# This fitted leaf is authored to clear its own frame. Exclude only that
	# frame from conservative rotation margins, never unrelated world objects.
	for node in $Frame.find_children("*", "CollisionObject3D", true, false):
		result.append(node.get_rid())
	return result

func _clear_rotation(from: float, to: float) -> bool:
	var count := maxi(1, ceili(absf(to-from)/deg_to_rad(2)))
	for i in range(count):
		var a := lerpf(from,to,float(i)/count)
		var b := lerpf(from,to,float(i+1)/count)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = leaf_shape.shape
		var rotated := Transform3D(Basis(Vector3.UP,(a+b)*.5),hinge.position)
		query.transform = global_transform * rotated * leaf_body.transform * leaf_shape.transform
		# The inflated midpoint box encloses the angular sweep in this interval.
		# One meter bounds every collider corner's distance to the hinge axis.
		query.margin = .001 + SWEEP_RADIUS*absf(b-a)*.5
		query.collision_mask = 3
		query.exclude = _excluded()
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			return false
	return true

func _physics_process(delta: float) -> void:
	if not moving: return
	var next := move_toward(hinge.rotation.y,_target_angle,PI*.5*delta/.45)
	if not _clear_rotation(hinge.rotation.y,next):
		moving = false
		motion_blocked = true
		_target_angle = hinge.rotation.y
		blocked.emit()
		return
	hinge.rotation.y = next
	if is_equal_approx(next,_target_angle):
		moving = false
		state_changed.emit(is_open())
