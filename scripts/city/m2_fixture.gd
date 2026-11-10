extends "res://scripts/city/m2_furniture.gd"
## Additional M2 fixtures use the same inherited occupancy authority.
const CATALOG_PATH="res://assets/city/m2_fixture_catalog.json"
static var _catalog:Dictionary={}
var _on_platform:Dictionary={}
static func catalog() -> Dictionary:
	if _catalog.is_empty():_catalog=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return _catalog
func _configure() -> void:
	var entries:Dictionary=catalog().get("entries",{})
	if not entries.has(furniture_kind):super._configure();return
	var d:Dictionary=entries[furniture_kind]
	object_tag=d.tag;display_name=d.label;capacity=d.use.size()
	use_offsets=[];pose_offsets=[]
	for p in d.use:use_offsets.append(Vector3(p[0],p[1],p[2]))
	for p in d.pose:pose_offsets.append(Vector3(p[0],p[1],p[2]))
func _on_action_started(sim:Node3D,action:Dictionary) -> void:
	super._on_action_started(sim,action)
	if sim.get("target")!=self or not users.has(sim):return
	if furniture_kind=="tv":sim.global_rotation.y=global_rotation.y+PI
	elif furniture_kind=="treadmill" and action.get("id","")=="workout":
		# SimAgent's standing actions do not otherwise move onto raised platforms.
		sim.global_position=get_pose_position(sim);sim.global_rotation.y=global_rotation.y+PI
		_on_platform[sim.get_instance_id()]=true
func release(sim) -> void:
	if is_instance_valid(sim) and _on_platform.has(sim.get_instance_id()):
		if is_inside_tree() and sim.is_inside_tree():sim.global_position=get_use_position(sim)
		_on_platform.erase(sim.get_instance_id())
	super.release(sim)
func _prune() -> void:
	super._prune()
	var ids:Array=[]
	for user in users:ids.append(user.get_instance_id())
	for id in _on_platform.keys():
		if id not in ids:_on_platform.erase(id)
func placement_bounds() -> AABB:
	var result:=AABB();var first:=true
	for c in get_node("Collision").get_children():
		var a:=AABB(c.position-c.shape.size*.5,c.shape.size)
		result=a if first else result.merge(a);first=false
	return result
