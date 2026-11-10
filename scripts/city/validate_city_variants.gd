extends SceneTree
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func ray(node:Node3D,a:Vector3,b:Vector3) -> Dictionary:return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(node.to_global(a),node.to_global(b),1))
func run() -> void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://docs/city/variants_manifest.json"))
	for kind in manifest.models:
		var d:Dictionary=manifest.models[kind];check(FileAccess.get_sha256("res://"+d.glb)==d.sha256,kind+" unchanged source hash")
		var node=load("res://scenes/city/m2_"+kind+".tscn").instantiate();root.add_child(node);node.position=Vector3(4,0,-3);node.rotation.y=PI*.5
		await physics_frame;await physics_frame
		var model:Node3D=node.get_node("Model") if d.category=="window" else node.get_node("Hinge/LeafBody/Model")
		var tris:=0;var ok:=true
		for m in model.find_children("*","MeshInstance3D",true,false):
			for surface in m.mesh.get_surface_count():
				var a=m.mesh.surface_get_arrays(surface);var vs=a[Mesh.ARRAY_VERTEX];var ns=a[Mesh.ARRAY_NORMAL];var uv=a[Mesh.ARRAY_TEX_UV];var ts=a[Mesh.ARRAY_TANGENT]
				tris+=a[Mesh.ARRAY_INDEX].size()/3
				ok=ok and ns.size()==vs.size() and uv.size()==vs.size() and ts.size()==vs.size()*4
				for i in vs.size():ok=ok and vs[i].is_finite() and ns[i].is_finite() and uv[i].is_finite() and absf(ns[i].length()-1)<.001
		check(ok and tris==int(d.triangles),kind+" imported topology normals UV tangents")
		if d.category=="window":
			check(node.get_node("Right").position==Vector3(2,0,0),kind+" compatible wall socket")
			check(node.get_node("Collision").get_child_count()==d.colliders.size(),kind+" exact compound collider count")
			check(not ray(node,Vector3(.05,1,-1),Vector3(.05,1,1)).is_empty(),kind+" wall side blocks ray")
			var opening:Array=d.opening;var x:float=(opening[0]+opening[2])*.5;var y:float=(opening[1]+opening[3])*.5
			check(not ray(node,Vector3(x,y,-1),Vector3(x,y,1)).is_empty(),kind+" closed glass remains physical")
			if kind=="window_arch":
				check(not ray(node,Vector3(.52,2.25,-1),Vector3(.52,2.25,1)).is_empty(),"arch shoulder wall remains solid")
		else:
			check(node.is_closed() and not ray(node,Vector3(1,1,-.5),Vector3(1,1,.5)).is_empty(),kind+" closed leaf blocks passage")
			check(node.request_open(true),kind+" existing door API")
			for tick in 60:await physics_frame
			check(node.is_open() and ray(node,Vector3(1,1,-.5),Vector3(1,1,.5)).is_empty(),kind+" open leaf clears passage")
			node.request_open(false)
			for tick in 60:await physics_frame
			check(node.is_closed(),kind+" closes again")
			var blocker:=StaticBody3D.new();blocker.collision_layer=1;var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(.14,1,.14);blocker.add_child(shape);root.add_child(blocker);blocker.global_position=node.to_global(Vector3(1.05,1,-.5))
			await physics_frame;await physics_frame;node.request_open(true)
			for tick in 60:await physics_frame
			check(node.motion_blocked and not node.is_open(),kind+" rotation refuses static obstacle")
			blocker.free()
		node.free()
	var surfaces=JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/surfaces_v2.json"))
	for id in surfaces:
		for map in surfaces[id].maps:
			var img:=Image.load_from_file("res://"+surfaces[id].maps[map]);var seamless:=img!=null and img.get_size()==Vector2i(256,256)
			if seamless:
				for i in 256:seamless=seamless and img.get_pixel(i,0)==img.get_pixel(i,255) and img.get_pixel(0,i)==img.get_pixel(255,i)
			check(seamless,id+" "+map+" repeating 256px map")
	print("CITY_VARIANTS ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
