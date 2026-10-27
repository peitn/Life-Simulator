extends SceneTree
# Read-only roof source/saved-scene/physics acceptance. --inject-drift mutates memory only.
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("PASS " if ok else "FAIL ") + label)
func collect(node: Node) -> Dictionary:
	var result := {}
	for m in node.find_children("*","MeshInstance3D",true,false):
		result[String(m.name)] = m
	return result
func transform_to(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n != null:
		if not n is Node3D: return Transform3D.IDENTITY
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var glb := "res://assets/city/roof_gable_2m.glb"
	var scn := "res://scenes/city/roof_gable_2m.scn"
	check(FileAccess.file_exists(glb),"GLB exists")
	check(ResourceLoader.exists(scn),"saved scene exists")
	if failed>0: quit(1); return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(glb,state)
	check(err==OK,"GLB import")
	if err!=OK: quit(1); return
	var src := doc.generate_scene(state)
	var pack := load(scn) as PackedScene
	check(src is Node3D and pack!=null,"source and PackedScene")
	if not src is Node3D or pack==null:
		if src!=null: src.free()
		quit(1)
		return
	var roof := pack.instantiate() as Node3D
	check(roof!=null and roof.transform.is_equal_approx(Transform3D.IDENTITY),"root pivot identity")
	if roof==null: src.free(); quit(1); return
	root.add_child(roof)
	var a := collect(src)
	var b := collect(roof)
	check(a.size()==2 and b.size()==2,"two slope meshes in source and scene")
	var expected := {"roof_left_slope":[0.0,1.0],"roof_right_slope":[1.0,2.0]}
	var tris := 0
	for name in expected.keys():
		check(a.has(name) and b.has(name),"mesh exists "+name)
		if not a.has(name) or not b.has(name): continue
		var sm: MeshInstance3D = a[name]
		var tm: MeshInstance3D = b[name]
		check(transform_to(sm,src).is_equal_approx(transform_to(tm,roof)),"mesh hierarchy transform "+name)
		check(sm.mesh.get_surface_count()==1 and tm.mesh.get_surface_count()==1,"one surface "+name)
		if sm.mesh.get_surface_count()!=1 or tm.mesh.get_surface_count()!=1: continue
		var sa := sm.mesh.surface_get_arrays(0)
		var ta := tm.mesh.surface_get_arrays(0)
		for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
			check(sa[field]==ta[field],"source/saved array "+str(field)+" "+name)
		var normals: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
		check(not normals.is_empty() and absf(normals[0].length()-1)<.001,"unit normal "+name)
		var uv: PackedVector2Array = sa[Mesh.ARRAY_TEX_UV]
		check(uv.size()==sa[Mesh.ARRAY_VERTEX].size(),"UV count "+name)
		var indices: PackedInt32Array = sa[Mesh.ARRAY_INDEX]
		tris += indices.size()/3 if not indices.is_empty() else sa[Mesh.ARRAY_VERTEX].size()/3
		var material := sm.mesh.surface_get_material(0) as BaseMaterial3D
		check(material!=null and absf(material.roughness-.83)<.001,"PBR roughness "+name)
	check(tris==24,"24 triangles")
	var body := roof.get_node_or_null("Collision") as StaticBody3D
	check(body!=null and body.collision_layer==1 and body.collision_mask==1,"static collision layer/mask 1")
	if body==null:
		src.free()
		roof.free()
		quit(1)
		return
	check(body.get_child_count()==2,"two independent convex colliders")
	for name in expected.keys():
		var col := body.get_node_or_null(name+"_collider") as CollisionShape3D
		check(col!=null and not col.disabled,"collider enabled "+name)
		if col==null: continue
		check(col.shape is ConvexPolygonShape3D,"convex hull "+name)
		if not col.shape is ConvexPolygonShape3D: continue
		var points := (col.shape as ConvexPolygonShape3D).points
		check(points.size()==8,"eight hull corners "+name)
		# Compare all convex corners with the actual imported mesh, not just its AABB.
		var original: MeshInstance3D = a[name]
		var vertices: PackedVector3Array = original.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var mesh_to_root := transform_to(original,src)
		var all_corners_match := true
		for vertex in vertices:
			var expected_point := mesh_to_root * vertex
			var found := false
			for point in points:
				if point.distance_to(expected_point)<.0002:
					found=true
					break
			if not found:
				all_corners_match=false
				break
		check(all_corners_match,"collider matches all imported roof vertices "+name)
		var lo := Vector3(INF,INF,INF)
		var hi := Vector3(-INF,-INF,-INF)
		for p in points:
			lo=lo.min(p)
			hi=hi.max(p)
		check(absf(lo.x-expected[name][0])<.001 and absf(hi.x-expected[name][1])<.001,"slope x bounds "+name)
		check(absf(lo.z+2)<.001 and absf(hi.z)<.001,"slope z bounds "+name)
		check(absf(lo.y)<.001 and absf(hi.y-.72)<.001,"slope height bounds "+name)
	if "--inject-drift" in OS.get_cmdline_user_args():
		var left := body.get_node_or_null("roof_left_slope_collider") as CollisionShape3D
		if left!=null: left.disabled=true
	await physics_frame
	await physics_frame
	var space := roof.get_world_3d().direct_space_state
	for x in [.5,1.5]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x,1.5,-1),Vector3(x,-.5,-1),1)
		var hit: Dictionary = space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-.42)<.015,"top slope ray x="+str(x))
	for x in [.5,1.5]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x,-.5,-1),Vector3(x,1.5,-1),1)
		var hit: Dictionary = space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-.3)<.015,"underside slope ray x="+str(x))
	for p in [Vector3(-.2,1.5,-1),Vector3(2.2,1.5,-1),Vector3(.5,1.5,.2),Vector3(1.5,1.5,-2.2)]:
		var ray := PhysicsRayQueryParameters3D.create(p,p+Vector3(0,-2,0),1)
		check(space.intersect_ray(ray).is_empty(),"outside roof footprint "+str(p))
	src.free()
	roof.free()
	print("ROOF_RESULT=",passed," passed ",failed," failed")
	quit(0 if failed==0 else 1)