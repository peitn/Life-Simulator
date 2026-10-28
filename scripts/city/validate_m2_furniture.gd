extends SceneTree
const Furniture=preload("res://scripts/city/m2_furniture.gd")
const Smart=preload("res://scripts/world/smart_object.gd")
class LegacySlots extends Furniture:
	func _slot(sim) -> int:return maxi(users.find(sim),0)
const EXPECTED={
	"sofa":{"tag":"sofa","capacity":2,"low":Vector3(-1.1,0,-.45),"high":Vector3(1.1,.825,.44),"triangles":2896,"sha":"bbcc3a6ed228e58dcd3ea2c35cc6b47ae562f77c3bfc2f24ef955ff6d8511d64"},
	"bed_single":{"tag":"bed","capacity":1,"low":Vector3(-.5,0,-1.05),"high":Vector3(.5,.895,1.05),"triangles":2472,"sha":"3c2b2f6e445b1279db6c391e50cb28701003834e56bb7d57664dad213038e90f"},
	"bed_double":{"tag":"bed","capacity":2,"low":Vector3(-.87,0,-1.07),"high":Vector3(.87,1.00129,1.05),"triangles":4200,"sha":"d1b54a340f97fd15e6d594ea8b5fd6c4cfc748d65127ac070953fe2843c605ac"},
	"fridge":{"tag":"fridge","capacity":1,"low":Vector3(-.34,0,-.35),"high":Vector3(.34,1.87,.356),"triangles":868,"sha":"89e075c41f1def3cb3942056f333b779dee169b2fc6477abc51488c5850b291f"}
}
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func transform_to(node:Node3D,parent:Node3D) -> Transform3D:
	var result:=node.transform;var p:=node.get_parent()
	while p!=parent and p!=null:result=p.transform*result;p=p.get_parent()
	return result
func run() -> void:
	var fixture:=Node3D.new();root.add_child(fixture)
	var index:=0
	for kind in EXPECTED:
		var e:Dictionary=EXPECTED[kind]
		var furniture=load("res://scenes/city/m2_"+kind+".tscn").instantiate()
		if "--legacy-seat-order" in OS.get_cmdline_user_args():
			furniture.set_script(LegacySlots);furniture.furniture_kind=kind
		fixture.add_child(furniture)
		furniture.position=Vector3(index*5,0,0);index+=1
		check(furniture is Smart and furniture.furniture_kind==kind,kind+" persisted adapter kind")
		check(furniture.object_tag==e.tag and furniture.capacity==e.capacity,kind+" production action tag/capacity")
		check(FileAccess.get_sha256("res://assets/models/"+kind+".glb")==e.sha,kind+" original source unchanged")
		var low:=Vector3(INF,INF,INF);var high:=-low;var triangles:=0
		var detailed:=StaticBody3D.new();detailed.collision_layer=8;detailed.collision_mask=0;furniture.add_child(detailed)
		for mesh in furniture.get_node("Model").find_children("*","MeshInstance3D",true,false):
			var t:=transform_to(mesh,furniture);var a:AABB=t*mesh.mesh.get_aabb();low=low.min(a.position);high=high.max(a.end)
			var c:=CollisionShape3D.new();c.shape=mesh.mesh.create_trimesh_shape();c.transform=t;detailed.add_child(c)
			for surface in mesh.mesh.get_surface_count():
				var arrays=mesh.mesh.surface_get_arrays(surface);triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
		check(low.distance_to(e.low)<.0001 and high.distance_to(e.high)<.0001,kind+" saved mesh bounds")
		check(triangles==e.triangles,kind+" measured reused triangle count")
		var bound:AABB=furniture.placement_bounds()
		check(bound.position.distance_to(low)<.0001 and bound.end.distance_to(high)<.0001,kind+" conservative collider matches source bounds")
		var capsule:=CharacterBody3D.new();capsule.collision_layer=4;capsule.collision_mask=1
		var cs:=CollisionShape3D.new();var cap:=CapsuleShape3D.new();cap.height=1.6;cap.radius=.18;cs.shape=cap;capsule.add_child(cs);fixture.add_child(capsule)
		await physics_frame;await physics_frame
		var actors:Array=[]
		for slot in furniture.capacity:
			var a:=Node3D.new();fixture.add_child(a);actors.append(a)
			check(furniture.reserve(a),kind+" free slot accepted")
			check(furniture.reserve(a) and furniture.users.size()==slot+1,kind+" idempotent reservation")
			var use_marker:Marker3D=furniture.get_node("Points/Use%d"%slot)
			var pose_marker:Marker3D=furniture.get_node("Points/Pose%d"%slot)
			check(furniture.get_use_position(a).distance_to(use_marker.global_position)<.0001,kind+" use marker matches production API")
			check(furniture.get_pose_position(a).distance_to(pose_marker.global_position)<.0001,kind+" pose marker matches production API")
			var direction:=Vector3.LEFT if kind=="bed_single" else Vector3.FORWARD*-1
			var start:=Transform3D(Basis.IDENTITY,use_marker.global_position+Vector3(0,.82,0)+direction*.5)
			check(not capsule.test_move(start,-direction*.5),kind+" capsule can approach use point")
			if not furniture.pose_offsets.is_empty():
				var surface:Marker3D=furniture.get_node("Points/Surface%d"%slot)
				var hit=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(surface.global_position+Vector3(0,2,0),surface.global_position-Vector3(0,1,0),8))
				check(not hit.is_empty() and absf(hit.position.y-surface.global_position.y)<.001,kind+" measured marker lies on actual source surface")
		var extra:=Node3D.new();fixture.add_child(extra)
		check(not furniture.reserve(extra) and not furniture.is_available(extra),kind+" occupied capacity rejected")
		check(not furniture.reserve(null),kind+" invalid reservation rejected")
		if actors.size()==2:
			var second_use:Vector3=furniture.get_use_position(actors[1]);var second_pose:Vector3=furniture.get_pose_position(actors[1])
			furniture.release(actors[0])
			check(furniture.get_use_position(actors[1])==second_use and furniture.get_pose_position(actors[1])==second_pose,kind+" remaining occupant keeps physical slot")
			check(furniture.reserve(extra) and furniture.get_use_position(extra)!=second_use,kind+" freed slot reused without overlap")
			furniture.release(extra)
		for a in actors:furniture.release(a);a.free()
		check(furniture.users.is_empty(),kind+" inherited occupancy completely released")
		furniture.furniture_kind="fridge" if kind!="fridge" else "sofa"
		check(furniture.furniture_kind==kind,kind+" live identity cannot diverge from saved geometry")
		check(furniture.reserve(extra),kind+" available again after release")
		furniture.furniture_kind="fridge" if kind!="fridge" else "sofa"
		check(furniture.furniture_kind==kind,kind+" occupied layout cannot be reconfigured")
		extra.free()
		var replacement:=Node3D.new();fixture.add_child(replacement)
		check(furniture.reserve(replacement) and furniture.users.size()==1,kind+" freed actor reclaimed by existing occupancy list")
		for yaw in [0,PI*.5,PI,PI*1.5]:
			fixture.position=Vector3(2,0,3);fixture.rotation.y=yaw
			check(furniture.get_use_position(replacement).distance_to(furniture.get_node("Points/Use0").global_position)<.0001,kind+" translated/rotated use point")
			check(furniture.get_pose_position(replacement).distance_to(furniture.get_node("Points/Pose0").global_position)<.0001,kind+" translated/rotated pose point")
			await physics_frame;await physics_frame
			var direction:=Vector3.LEFT if kind=="bed_single" else Vector3.BACK
			var facing:Vector3=furniture.global_basis*direction
			var start:=Transform3D(Basis.IDENTITY,furniture.get_use_position(replacement)+Vector3(0,.82,0)+facing*.5)
			check(not capsule.test_move(start,-facing*.5),kind+" rotated collider preserves usable approach")
		furniture.release(replacement);replacement.free()
		fixture.position=Vector3.ZERO;fixture.rotation=Vector3.ZERO
		detailed.free();capsule.free();furniture.free()
		print("M2_VALIDATED ",kind)
	fixture.free()
	var invalid:=Node3D.new();invalid.set_script(Furniture);invalid.furniture_kind="unknown";root.add_child(invalid)
	var rejected:=Node3D.new();root.add_child(rejected)
	check(not invalid.reserve(rejected) and not invalid.is_available(rejected),"unknown furniture kind fails closed")
	check(invalid.get_use_position(rejected)==invalid.global_position,"empty layout query avoids modulo zero")
	invalid.free();rejected.free()
	print("M2_FURNITURE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
