extends SceneTree
const B=preload("res://scripts/city/m2_fixture_builder.gd")
const Actions=preload("res://scripts/sim/action_library.gd")
class LegacySlots extends B.Fixture:
	func _slot(sim) -> int:return maxi(users.find(sim),0)
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func ray(a:Vector3,b:Vector3) -> Dictionary:return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
func run() -> void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://docs/city/m2_fixtures_manifest.json"))
	var rig:=Node3D.new();root.add_child(rig)
	for kind in B.Fixture.catalog().entries:
		var d:Dictionary=B.Fixture.catalog().entries[kind];var e:Dictionary=manifest.entries[kind]
		var node=load(e.scene).instantiate()
		if kind=="tv" and "--legacy-tv" in OS.get_cmdline_user_args():node.set_script(LegacySlots);node.furniture_kind="tv"
		rig.add_child(node)
		if kind=="shower" and "--disable-shower-side" in OS.get_cmdline_user_args():node.get_node("Collision").get_child(1).disabled=true
		check(node.furniture_kind==kind and node.object_tag==d.tag and node.capacity==d.use.size(),kind+" persisted identity")
		check(FileAccess.get_sha256(e.glb)==e.sha256,kind+" GLB hash")
		var a:=B.bounds(node)
		check(a.position.distance_to(B.vec(e.min))<.00001 and a.end.distance_to(B.vec(e.max))<.00001,kind+" measured bounds")
		check(node.get_node("Model").get_child_count()==d.parts.size(),kind+" complete geometry")
		check(node.get_node("Collision").get_child_count()==d.colliders.size(),kind+" conservative compound collision")
		check(node.get_node("Collision").collision_layer==1,kind+" world physics layer")
		var triangles:=0;var arrays_ok:=true
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			check(mesh.get_active_material(0)!=null,kind+" material")
			for surface in mesh.mesh.get_surface_count():
				var arr=mesh.mesh.surface_get_arrays(surface)
				var vertices=arr[Mesh.ARRAY_VERTEX];var normals=arr[Mesh.ARRAY_NORMAL];var uvs=arr[Mesh.ARRAY_TEX_UV];var tangents=arr[Mesh.ARRAY_TANGENT];var indices=arr[Mesh.ARRAY_INDEX]
				triangles+=indices.size()/3
				arrays_ok=arrays_ok and vertices.size()==normals.size() and vertices.size()==uvs.size() and tangents.size()==vertices.size()*4
				for i in vertices.size():arrays_ok=arrays_ok and vertices[i].is_finite() and absf(normals[i].length()-1)<.001 and uvs[i].is_finite()
		check(arrays_ok and triangles==int(e.triangles) and triangles<3000,kind+" finite normals UV tangents and triangle budget")
		var gltf:=GLTFDocument.new();var state:=GLTFState.new();check(gltf.append_from_file(e.glb,state)==OK,kind+" GLB independently imports")
		var imported=gltf.generate_scene(state)
		var imported_bounds:=B.bounds(imported)
		check(imported_bounds.position.distance_to(a.position)<.0001 and imported_bounds.end.distance_to(a.end)<.0001,kind+" GLB roundtrip dimensions")
		imported.free()
		var actors:Array=[]
		for slot in node.capacity:
			var actor:=Node3D.new();rig.add_child(actor);actors.append(actor)
			check(node.reserve(actor) and node.reserve(actor) and node.users.size()==slot+1,kind+" inherited idempotent reservation")
		var extra:=Node3D.new();rig.add_child(extra)
		check(not node.reserve(extra) and not node.is_available(extra),kind+" full or decorative object rejects occupancy")
		if not d.action.is_empty():check(Actions.get_action(d.action).object==d.tag,kind+" existing production action")
		if actors.size()==2:
			var stable:Vector3=node.get_pose_position(actors[1]);node.release(actors[0])
			check(node.get_pose_position(actors[1])==stable,"TV second seat remains stable")
			check(node.reserve(extra) and node.get_pose_position(extra)!=stable,"TV fills only vacant seat")
			node.release(extra)
		for actor in actors:node.release(actor);actor.free()
		extra.free()
		for yaw in [0.0,PI*.5,PI,PI*1.5]:
			rig.position=Vector3(11,0,-7);rig.rotation.y=yaw
			await physics_frame;await physics_frame
			var capsule:=CharacterBody3D.new();capsule.collision_layer=4;capsule.collision_mask=1
			var shape:=CollisionShape3D.new();shape.shape=CapsuleShape3D.new();shape.shape.radius=.18;shape.shape.height=1.6;capsule.add_child(shape);root.add_child(capsule)
			var rotation_actors:Array=[]
			for slot in node.capacity:
				var actor:=Node3D.new();rig.add_child(actor);node.reserve(actor);rotation_actors.append(actor)
				var point:Vector3=node.get_node("Points/Use%d"%slot).global_position
				check(point.distance_to(node.get_use_position(actor))<.0001,kind+" quarter-turn use point")
				var start:=Transform3D(Basis.IDENTITY,point+Vector3(0,.805,0)+rig.global_basis*Vector3(0,0,.65))
				check(not capsule.test_move(start,rig.global_basis*Vector3(0,0,-.65)),kind+" clear capsule approach")
			for actor in rotation_actors:node.release(actor);actor.free()
			if kind=="shower":
				check(not ray(rig.to_global(Vector3(-1,1,0)),rig.to_global(Vector3(0,1,0))).is_empty(),"shower glass blocks lateral passage")
				check(ray(rig.to_global(Vector3(0,1,1)),rig.to_global(Vector3(0,1,.1))).is_empty(),"shower front opening stays clear")
			if kind=="stove":check(not ray(rig.to_global(Vector3(0,.5,1)),rig.to_global(Vector3(0,.5,0))).is_empty(),"stove body blocks penetration")
			capsule.free()
		rig.transform=Transform3D.IDENTITY;node.free()
	rig.free()
	print("M2_FIXTURES ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
