extends SceneTree
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Design=preload("res://scripts/clothing/garment_design.gd")
const Builder=preload("res://scripts/clothing/garment_builder.gd")
const Wardrobe=preload("res://scripts/assets/clothing_wardrobe.gd")
const Resolver=preload("res://scripts/character/appearance_resolver.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	var p:=Preview.new()
	root.add_child(p)
	var source:Dictionary=CD.create().to_dict()
	var recipe:Dictionary=Design.create()
	recipe.sleeve_length=.45
	recipe.ease=1.0
	recipe.cuff_flare=1.0
	var lp:Dictionary=Resolver.resolve(Design.put_on_character(source,recipe))
	for custom in Builder.parts(lp):
		if not String(custom.name).begins_with("sleeve_"):continue
		var original:Mesh
		for entry in Wardrobe.parts("top","mikina"):
			if entry.name==custom.name:original=entry.mesh
		var points:PackedVector3Array=original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var changed:PackedVector3Array=custom.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shapes:Array=original.surface_get_blend_shape_arrays(0)
		var changed_shapes:Array=custom.mesh.surface_get_blend_shape_arrays(0)
		var top:float=-INF
		for point in points:top=maxf(top,point.y)
		var pins:=0
		var worst:=0.0
		for i in points.size():
			if points[i].y<top-.001:continue
			pins+=1
			worst=maxf(worst,points[i].distance_to(changed[i]))
			for k in shapes.size():worst=maxf(worst,shapes[k][Mesh.ARRAY_VERTEX][i].distance_to(changed_shapes[k][Mesh.ARRAY_VERTEX][i]))
		check(pins==14 and worst<.000001,"short/loose sleeve preserves exact shoulder stitch in base and all ten body morphs")
	var cases:Array=[["top","mikina"],["top","kawaii_kocici_mikina"],["top","saty"],["bottom","dziny"],["bottom","goth_sukne"],["shoes","goth_platformy"]]
	var poses:=0
	for pair in cases:
		for shape in [{"length":.6,"sleeve_length":.45,"ease":1.0,"cuff_flare":1.0},{"length":1.15,"sleeve_length":.75,"ease":.4,"cuff_flare":.4}]:
			var design:Dictionary=Design.create(pair[0],pair[1])
			design.merge(shape,true)
			for broad in [false,true]:
				var d:Dictionary=Design.put_on_character(source,design)
				d.body.merge({"frame":1.0 if broad else .1,"body_fat":.8 if broad else .1,"muscle":.8 if broad else .1,"shoulders":1.0 if broad else .1,"hips":1.0 if broad else .1},true)
				p.show_draft(d)
				var v:Node3D=p.visual
				if v._anim!=null:v._anim.stop()
				var sk:Skeleton3D=v._skeleton()
				if Builder.needs_midriff(v.look_params):
					check(v._garment_midriff!=null and v._garment_midriff.mesh.get_surface_count()==1 and v._garment_midriff.visible,"cropped garment has complete skinned body beneath")
				elif v._garment_midriff!=null:check(not v._garment_midriff.visible,"full-length clothes hide the optional midriff surface")
				for pose in 3:
					for side in ["l","r"]:
						sk.set_bone_pose_rotation(sk.find_bone("forearm_"+side),Quaternion(Vector3.RIGHT,-PI/2 if pose==1 else 0.0))
						sk.set_bone_pose_rotation(sk.find_bone("upper_arm_"+side),Quaternion(Vector3.FORWARD,(.6 if side=="l" else -.6) if pose==2 else 0.0))
					sk.force_update_all_bone_transforms()
					var healthy:=true
					var rendered_parts:Array=v._c5_nodes.duplicate()
					if v._garment_midriff!=null and v._garment_midriff.visible and v._garment_midriff.mesh.get_surface_count()==1:rendered_parts.append(v._garment_midriff)
					for mi in rendered_parts:
						var points:PackedVector3Array=posed(v,mi)
						var indices:PackedInt32Array=mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
						for i in range(0,indices.size(),3):
							var a:Vector3=points[indices[i]]
							var b:Vector3=points[indices[i+1]]
							var c:Vector3=points[indices[i+2]]
							if not a.is_finite() or (b-a).cross(c-a).length_squared()<1e-16:healthy=false
					check(healthy,"actual skinned custom outfit has finite noncollapsed faces: "+str(pair)+"/"+str(broad)+"/"+str(pose))
					poses+=1
	p.free()
	await process_frame
	print("CLOTHING_DEFORMATION_RESULT checks=",checks," failures=",failures," poses=",poses)
	quit(0 if failures==0 and poses==72 else 1)
func posed(v:Node3D,mi:MeshInstance3D)->PackedVector3Array:
	var arrays:Array=mi.mesh.surface_get_arrays(0)
	var base:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var points:PackedVector3Array=base.duplicate()
	var blends:Array=mi.mesh.surface_get_blend_shape_arrays(0)
	for k in blends.size():
		var w:float=mi.get_blend_shape_value(k)
		if is_zero_approx(w):continue
		var target:PackedVector3Array=blends[k][Mesh.ARRAY_VERTEX]
		for i in points.size():points[i]+=(target[i]-base[i])*w
	var sk:Skeleton3D=v._skeleton()
	var transforms:Array=[]
	for i in mi.skin.get_bind_count():
		var name:String=mi.skin.get_bind_name(i)
		var bone:int=sk.find_bone(name) if name!="" else mi.skin.get_bind_bone(i)
		transforms.append(sk.get_bone_global_pose(bone)*mi.skin.get_bind_pose(i))
	var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	for i in points.size():
		var out:=Vector3.ZERO
		for k in 4:out+=(transforms[bones[i*4+k]]*points[i])*weights[i*4+k]
		points[i]=out
	return points
