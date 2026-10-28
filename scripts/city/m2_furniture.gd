extends "res://scripts/world/smart_object.gd"
## Reuse SmartObject.users/reserve/release as the occupancy authority.
## The extra ID->slot map preserves physical seats when another user leaves.
const DEFINITIONS := {
	"sofa":{"tag":"sofa","label":"Sedačka","capacity":2,"use":[Vector3(-.5,0,.95),Vector3(.5,0,.95)],"pose":[Vector3(-.5,0,.1),Vector3(.5,0,.1)]},
	"bed_single":{"tag":"bed","label":"Jednolůžko","capacity":1,"use":[Vector3(-.75,0,.3)],"pose":[Vector3.ZERO]},
	"bed_double":{"tag":"bed","label":"Dvojlůžko","capacity":2,"use":[Vector3(-.55,0,1.6),Vector3(.55,0,1.6)],"pose":[Vector3(-.4,0,0),Vector3(.4,0,0)]},
	"fridge":{"tag":"fridge","label":"Lednice","capacity":1,"use":[Vector3(0,0,1)],"pose":[]}
}
@export_storage var furniture_kind:String="sofa":
	set(value):
		# Reconfiguring occupied furniture would invalidate live reservations.
		# Geometry is baked by the builder: live kind changes cannot swap it.
		if not users.is_empty() or (is_inside_tree() and value!=furniture_kind):return
		furniture_kind=value
		_configure()
var _slot_by_id:Dictionary={}
const SOFA_LIE_POSE := Vector3.ZERO

func _init() -> void:
	_configure()

func _configure() -> void:
	if not DEFINITIONS.has(furniture_kind):
		object_tag="";display_name="";capacity=0;use_offsets=[];pose_offsets=[]
		return
	var d:Dictionary=DEFINITIONS[furniture_kind]
	object_tag=d.tag;display_name=d.label;capacity=d.capacity
	use_offsets=d.use.duplicate();pose_offsets=d.pose.duplicate()

func _prune() -> void:
	var live_ids:Array=[]
	for user in users.duplicate():
		if is_instance_valid(user):live_ids.append(user.get_instance_id())
		else:super.release(user)
	for id in _slot_by_id.keys():
		if id not in live_ids:_slot_by_id.erase(id)

func is_available(sim) -> bool:
	if not is_instance_valid(sim) or not sim is Node3D:return false
	_prune()
	if furniture_kind=="sofa":
		for user in users:
			if user!=sim and _sofa_sleep(user):return false
	return capacity>0 and super.is_available(sim)

func _sofa_sleep(sim) -> bool:
	if not is_instance_valid(sim):return false
	var action=sim.get("current_action")
	return action is Dictionary and action.get("id","")=="sleep_sofa"

func reserve(sim) -> bool:
	if not is_instance_valid(sim) or not sim is Node3D:return false
	_prune()
	if capacity<=0 or use_offsets.size()!=capacity:return false
	if furniture_kind=="sofa":
		for user in users:
			if user!=sim and (_sofa_sleep(user) or _sofa_sleep(sim)):return false
	if not super.reserve(sim):return false
	var id:int=sim.get_instance_id()
	if not _slot_by_id.has(id):
		var selected:=-1
		for slot in range(capacity):
			if slot not in _slot_by_id.values():selected=slot;break
		if selected<0:
			super.release(sim)
			return false
		_slot_by_id[id]=selected
	if sim.has_signal("action_started"):
		var callback:=Callable(self,"_on_action_started")
		if not sim.is_connected("action_started",callback):sim.connect("action_started",callback)
	return true

func release(sim) -> void:
	if is_instance_valid(sim):
		_slot_by_id.erase(sim.get_instance_id())
		var callback:=Callable(self,"_on_action_started")
		if sim.has_signal("action_started") and sim.is_connected("action_started",callback):
			sim.disconnect("action_started",callback)
	super.release(sim)
	_prune()

func _slot(sim) -> int:
	if not is_instance_valid(sim):return 0
	return int(_slot_by_id.get(sim.get_instance_id(),0))

func get_use_position(sim) -> Vector3:
	if use_offsets.is_empty():return global_position
	return super.get_use_position(sim)

func get_pose_position(sim) -> Vector3:
	if furniture_kind=="sofa" and _sofa_sleep(sim):return to_global(SOFA_LIE_POSE)
	return super.get_pose_position(sim)

func _on_action_started(sim:Node3D,action:Dictionary) -> void:
	if sim.get("target")!=self or not users.has(sim):return
	# SimAgent faces an object's center before emitting action_started. A seated
	# person needs the sofa's actual front, not a diagonal toward its center.
	if furniture_kind=="sofa" and action.get("posture","")=="sit":
		sim.global_rotation.y=global_rotation.y
	elif furniture_kind=="sofa" and action.get("id","")=="sleep_sofa":
		sim.global_rotation.y=global_rotation.y+PI*.5

func _exit_tree() -> void:
	for user in users.duplicate():release(user)

func placement_bounds() -> AABB:
	var body:CollisionShape3D=get_node_or_null("Collision/BodyShape")
	if body==null:return AABB()
	return AABB(body.position-body.shape.size*.5,body.shape.size)
