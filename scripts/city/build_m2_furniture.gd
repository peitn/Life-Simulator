extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const Furniture=preload("res://scripts/city/m2_furniture.gd")
const Assets=preload("res://scripts/assets/asset_library.gd")
var run_id:String

func own(root_:Node,node:Node) -> void:
	for child in node.get_children():child.owner=root_;own(root_,child)

func relative_transform(node:Node3D,ancestor:Node3D) -> Transform3D:
	var result:=node.transform;var p:=node.get_parent()
	while p!=ancestor and p!=null:result=p.transform*result;p=p.get_parent()
	return result

func source_metrics(model:Node3D) -> Dictionary:
	var low:=Vector3(INF,INF,INF);var high:=-low;var triangles:=0
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var t:=relative_transform(mesh,model);var a:AABB=t*mesh.mesh.get_aabb()
		low=low.min(a.position);high=high.max(a.end)
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface);var inds=arrays[Mesh.ARRAY_INDEX]
			triangles+=inds.size()/3 if inds!=null and not inds.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()/3
	return {"low":low,"high":high,"triangles":triangles}

func surface_height(model:Node3D,where:Vector3,ray_top:float) -> float:
	var highest:=-INF
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var t:=relative_transform(mesh,model)
		for surface in mesh.mesh.get_surface_count():
			var a=mesh.mesh.surface_get_arrays(surface);var verts=a[Mesh.ARRAY_VERTEX];var inds=a[Mesh.ARRAY_INDEX]
			for i in range(0,inds.size(),3):
				var hit=Geometry3D.ray_intersects_triangle(Vector3(where.x,ray_top,where.z),Vector3.DOWN,t*verts[inds[i]],t*verts[inds[i+1]],t*verts[inds[i+2]])
				if hit!=null:highest=maxf(highest,hit.y)
	return highest

func marker(parent:Node,name_:String,where:Vector3) -> void:
	var point:=Marker3D.new();point.name=name_;point.position=where;parent.add_child(point)

func _init() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	run_id=args[0]
	Assets.enabled=true
	var entries:Dictionary={}
	for kind in Furniture.DEFINITIONS:
		var node:=Node3D.new();node.set_script(Furniture);node.furniture_kind=kind;node.name="M2_"+kind
		var model:=Assets.instantiate(kind);assert(model!=null)
		model.scene_file_path="";model.name="Model";node.add_child(model)
		var metrics:=source_metrics(model)
		var body:=StaticBody3D.new();body.name="Collision";body.collision_layer=1;body.collision_mask=3;node.add_child(body)
		var shape:=CollisionShape3D.new();shape.name="BodyShape";shape.shape=BoxShape3D.new()
		shape.shape.size=metrics.high-metrics.low;shape.position=(metrics.high+metrics.low)*.5;body.add_child(shape)
		var points:=Node3D.new();points.name="Points";node.add_child(points)
		if kind=="sofa":marker(points,"Lie",Furniture.SOFA_LIE_POSE)
		var surfaces:Array=[]
		for i in node.capacity:
			marker(points,"Use%d"%i,node.use_offsets[i])
			var pose:Vector3=node.pose_offsets[i] if not node.pose_offsets.is_empty() else node.use_offsets[i]
			marker(points,"Pose%d"%i,pose)
			if not node.pose_offsets.is_empty():
				var y:=surface_height(model,pose,metrics.high.y+.25);assert(is_finite(y))
				marker(points,"Surface%d"%i,Vector3(pose.x,y,pose.z));surfaces.append(y)
		own(node,node)
		var packed:=PackedScene.new();assert(packed.pack(node)==OK)
		var target:String="res://scenes/city/m2_"+kind+".tscn"
		assert(G.owns(run_id));assert(ResourceSaver.save(packed,target)==OK)
		entries[kind]={"scene":target.trim_prefix("res://"),"source":"assets/models/"+kind+".glb","source_sha256":FileAccess.get_sha256("res://assets/models/"+kind+".glb"),"scene_sha256":FileAccess.get_sha256(target),"bounds_min":[metrics.low.x,metrics.low.y,metrics.low.z],"bounds_max":[metrics.high.x,metrics.high.y,metrics.high.z],"triangles":metrics.triangles,"capacity":node.capacity,"surface_heights_m":surfaces,"pose_convention":"floor-level actor origin; posture animation sets pelvis height","collision":"conservative single body box; walking/navmesh integration under M6"}
		print("M2_BUILT ",kind," ",JSON.stringify(entries[kind]))
		node.free()
	Assets.clear_cache()
	assert(G.owns(run_id))
	var f=FileAccess.open("res://docs/city/m2_furniture_manifest.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":"1.0","run_id":run_id,"entries":entries},"  "));f.close()
	quit()
