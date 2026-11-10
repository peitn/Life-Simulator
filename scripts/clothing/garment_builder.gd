extends RefCounted
## Tailors authored, rigged C5 templates; keeps ten body morphs and skin bindings.
const Wardrobe=preload("res://scripts/assets/clothing_wardrobe.gd")
const Design=preload("res://scripts/clothing/garment_design.gd")
const FABRIC_SHADER=preload("res://shaders/garment_design.gdshader")
static var _meshes:Dictionary={}
static var _midriff_mesh:ArrayMesh
const CACHE_LIMIT:=64

static func clear_cache()->void:
	_meshes.clear()
	_midriff_mesh=null
static func core_piece(name:String)->bool:
	return name=="shell" or name=="waistband" or name=="dress_lower" or name.begins_with("sleeve_") or name.contains("pleated") or name.contains("cropped_pants") or name.begins_with("boot_shaft_")

static func parts(lp:Dictionary)->Array:
	var result:Array=[]
	var incoming:Variant=lp.get("garment_designs",{})
	var designs:Dictionary=incoming if incoming is Dictionary else {}
	var originals:Array=Wardrobe.active_parts(lp)
	var bottom_design:Dictionary=Design.validate(designs.get("bottom",{}))
	if bottom_design.ok and float(bottom_design.data.length)<.999 and lp.get("outfit_top","")!="saty" and lp.get("outfit_bottom","") not in Wardrobe.LEG_OUTFITS:
		originals.append_array(Wardrobe.parts("legs","skin"))
	if designs.is_empty():return originals
	for entry in originals:
		var kind:String="top" if entry.category=="dress" else entry.category
		var checked:Dictionary=Design.validate(designs.get(kind,{}))
		if not checked.ok or checked.data.kind!=kind or checked.data.base!=lp.get("outfit_"+kind,""):
			result.append(entry)
			continue
		var recipe:Dictionary=checked.data
		if not recipe.details and not core_piece(entry.name):continue
		var customized:Dictionary=entry.duplicate()
		customized["mesh"]=_tailored_mesh(entry,recipe)
		customized["design"]=recipe
		result.append(customized)
	return result

static func material(entry:Dictionary,lp:Dictionary)->Material:
	if not entry.has("design"):return Wardrobe.material_instance(entry,lp)
	var d:Dictionary=entry.design
	var piece:String=entry.name
	# Logos, eyes, buttons and trim retain their original distinct materials.
	if not core_piece(piece) and piece not in ["hood","cat_hood","kangaroo_pocket","cat_pocket"]:
		return Wardrobe.material_instance(entry,lp)
	var mat:=ShaderMaterial.new()
	mat.shader=FABRIC_SHADER
	mat.set_shader_parameter("main_color",Color.html(d.color))
	mat.set_shader_parameter("accent_color",Color.html(d.accent))
	mat.set_shader_parameter("pattern",Design.PATTERNS.keys().find(d.pattern))
	mat.set_shader_parameter("pattern_scale",float(d.pattern_scale))
	mat.set_shader_parameter("roughness",float(d.roughness))
	var fabric:String=d.fabric
	if fabric=="original":fabric=String(entry.material).trim_prefix("cloth_").trim_prefix("shoe_").trim_suffix("_c5")
	var color_map:Texture2D=Wardrobe._tex(fabric,"A")
	var normal_map:Texture2D=Wardrobe._tex(fabric,"N")
	mat.set_shader_parameter("has_albedo",color_map!=null)
	mat.set_shader_parameter("has_normal",normal_map!=null)
	if color_map!=null:mat.set_shader_parameter("fabric_albedo",color_map)
	if normal_map!=null:mat.set_shader_parameter("fabric_normal",normal_map)
	return mat

static func _tailored_mesh(entry:Dictionary,d:Dictionary)->ArrayMesh:
	var source:ArrayMesh=entry.mesh
	if d.kind=="top" and d.base=="saty" and entry.name=="waistband":
		return _dress_bridge(source,d)
	if d.kind=="shoes" or (is_zero_approx(float(d.ease)) and is_equal_approx(float(d.length),1.0) and is_equal_approx(float(d.sleeve_length),1.0) and is_zero_approx(float(d.cuff_flare))):return source
	var key:String=str(source.get_instance_id())+"/"+JSON.stringify([d.ease,d.length,d.sleeve_length,d.cuff_flare])
	if _meshes.has(key):return _meshes[key]
	var mesh:=ArrayMesh.new()
	mesh.blend_shape_mode=source.blend_shape_mode
	for i in source.get_blend_shape_count():mesh.add_blend_shape(source.get_blend_shape_name(i))
	for surface in source.get_surface_count():
		var arrays:Array=source.surface_get_arrays(surface).duplicate(true)
		var blends:Array=source.surface_get_blend_shape_arrays(surface).duplicate(true)
		var originals:Array=source.surface_get_arrays(surface)
		var pinned:=PackedInt32Array()
		if String(entry.name).begins_with("sleeve_"):
			var points:PackedVector3Array=originals[Mesh.ARRAY_VERTEX]
			var top:float=-INF
			for point in points:top=maxf(top,point.y)
			for i in points.size():
				if points[i].y>=top-.001:pinned.append(i)
		_transform(arrays,String(entry.name),d,PackedInt32Array(),pinned)
		if (String(entry.name).begins_with("sleeve_") and float(d.sleeve_length)<.999) or (d.kind=="bottom" and absf(float(d.length)-1.0)>.001):
			_retarget_weights(arrays,originals)
		for target in blends:_transform(target,String(entry.name),d,arrays[Mesh.ARRAY_INDEX],pinned)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,blends)
		mesh.surface_set_material(surface,source.surface_get_material(surface))
	if _meshes.size()>=CACHE_LIMIT:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=mesh
	return mesh

static func _transform(arrays:Array,piece:String,d:Dictionary,indices:PackedInt32Array=PackedInt32Array(),pinned:PackedInt32Array=PackedInt32Array())->void:
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var sleeve:bool=piece.begins_with("sleeve_")
	var ymin:float=INF
	for point in points:ymin=minf(ymin,point.y)
	var ymax:float=-INF
	if sleeve:
		for point in points:ymax=maxf(ymax,point.y)
	for i in points.size():
		if i in pinned:continue
		var point:Vector3=points[i]
		var radial:=Vector3(normals[i].x,0,normals[i].z)
		if radial.length_squared()>.00001:radial=radial.normalized()
		var ease:float=float(d.ease)*.018
		if sleeve:
			# Preserve the stitched upper rim and its corresponding morph target.
			var down:float=maxf(0.0,ymax-point.y)
			point.y=ymax-down*float(d.sleeve_length)
			ease*=smoothstep(.0,.07,down)
			ease+=float(d.cuff_flare)*.012*smoothstep(.10,.24,down)
		else:
			var anchor:float=1.14 if d.kind=="top" else .98
			var ratio:float=float(d.length)
			if d.kind=="bottom" and ymin<anchor:ratio=minf(ratio,(anchor-.025)/(anchor-ymin))
			if point.y<anchor:point.y=anchor+(point.y-anchor)*ratio
			# Collar, shoulders and waist remain seated on the original rig.
			ease*=1.0-smoothstep(1.06,1.18,point.y) if d.kind=="top" else 1.0-smoothstep(.88,1.0,point.y)
		point+=radial*ease
		points[i]=point
	arrays[Mesh.ARRAY_VERTEX]=points
	var topology:PackedInt32Array=indices if not indices.is_empty() else arrays[Mesh.ARRAY_INDEX]
	Wardrobe._rebuild_vertex_normals(arrays,topology)
	if arrays[Mesh.ARRAY_TANGENT]!=null or arrays[Mesh.ARRAY_TEX_UV]!=null:
		var changed:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var tangents:=PackedFloat32Array()
		for n in changed:
			var axis:Vector3=Vector3.RIGHT-n*n.x
			if axis.length_squared()<.00001:axis=Vector3.FORWARD-n*n.z
			axis=axis.normalized()
			tangents.append_array(PackedFloat32Array([axis.x,axis.y,axis.z,1.0]))
		arrays[Mesh.ARRAY_TANGENT]=tangents

static func _retarget_weights(arrays:Array,source:Array)->void:
	var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var refs:PackedVector3Array=source[Mesh.ARRAY_VERTEX]
	var sb:PackedInt32Array=source[Mesh.ARRAY_BONES]
	var sw:PackedFloat32Array=source[Mesh.ARRAY_WEIGHTS]
	var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	for i in positions.size():
		if i<refs.size() and positions[i].distance_squared_to(refs[i])<1e-12:continue
		var near:Array=[]
		for j in refs.size():
			if absf(positions[i].x)>.025 and positions[i].x*refs[j].x<0.0:continue
			near.append([positions[i].distance_squared_to(refs[j]),j])
		near.sort_custom(func(a,b):return a[0]<b[0])
		var gathered:Dictionary={}
		for item in near.slice(0,4):
			var factor:float=1.0/maxf(float(item[0]),.000001)
			for k in 4:
				var id:int=sb[item[1]*4+k]
				gathered[id]=float(gathered.get(id,0.0))+sw[item[1]*4+k]*factor
		var ids:Array=gathered.keys()
		ids.sort_custom(func(a,b):return gathered[a]>gathered[b])
		var total:=0.0
		for k in mini(4,ids.size()):total+=gathered[ids[k]]
		for k in 4:
			bones[i*4+k]=ids[k] if k<ids.size() else 0
			weights[i*4+k]=float(gathered[ids[k]])/total if k<ids.size() else 0.0
	arrays[Mesh.ARRAY_BONES]=bones
	arrays[Mesh.ARRAY_WEIGHTS]=weights

## The legacy dress had an open annulus between a narrow bodice and wide skirt.
## Build a continuous flared waist band from both real template boundaries,
## including their ten body morphs, rather than leaving that visible void.
static func _dress_bridge(source:ArrayMesh,d:Dictionary)->ArrayMesh:
	var key:String="dress-waist/"+JSON.stringify([d.ease,d.length])
	if _meshes.has(key):return _meshes[key]
	var bodice:Mesh
	var skirt:Mesh
	for e in Wardrobe.parts("top","saty"):
		if e.name=="shell":bodice=e.mesh
	for e in Wardrobe.parts("dress","saty"):
		if e.name=="dress_lower":skirt=e.mesh
	if bodice==null or skirt==null:return source
	var a:Array=bodice.surface_get_arrays(0)
	var b:Array=skirt.surface_get_arrays(0)
	var av:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var bv:PackedVector3Array=b[Mesh.ARRAY_VERTEX]
	var upper:Array=[]
	var lower:Array=[]
	for i in av.size():
		if av[i].y<1.06 and absf(av[i].x)<.23:upper.append(i)
	for i in bv.size():
		if bv[i].y>1.0:lower.append(i)
	if upper.size()<8 or lower.size()<8:return source
	var arrays:Array=_waist_arrays(av,bv,upper,lower,true)
	_retarget_weights(arrays,source.surface_get_arrays(0))
	_transform(arrays,"waistband",d)
	var targets:Array=[]
	var ab:Array=bodice.surface_get_blend_shape_arrays(0)
	var bb:Array=skirt.surface_get_blend_shape_arrays(0)
	for i in source.get_blend_shape_count():
		var target:Array=_waist_arrays(ab[i][Mesh.ARRAY_VERTEX],bb[i][Mesh.ARRAY_VERTEX],upper,lower,false)
		_transform(target,"waistband",d,arrays[Mesh.ARRAY_INDEX])
		targets.append(target)
	var mesh:=ArrayMesh.new()
	mesh.blend_shape_mode=source.blend_shape_mode
	for i in source.get_blend_shape_count():mesh.add_blend_shape(source.get_blend_shape_name(i))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,targets)
	if _meshes.size()>=CACHE_LIMIT:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=mesh
	return mesh

static func _waist_arrays(upper_points:PackedVector3Array,lower_points:PackedVector3Array,upper:Array,lower:Array,base:bool)->Array:
	var arrays:Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	var positions:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	var indices:=PackedInt32Array()
	for ring in 2:
		var points:PackedVector3Array=upper_points if ring==0 else lower_points
		var selection:Array=upper if ring==0 else lower
		var low:=Vector3(INF,INF,INF)
		var high:Vector3=-low
		var mean_y:=0.0
		for index in selection:
			low=low.min(points[index])
			high=high.max(points[index])
			mean_y+=points[index].y/selection.size()
		var center:Vector3=(low+high)*.5
		var rx:float=(high.x-low.x)*.5+.002
		var rz:float=(high.z-low.z)*.5+.002
		for k in 32:
			var angle:float=TAU*float(k)/32.0
			var point:=Vector3(center.x+rx*cos(angle),mean_y+(.022 if ring==0 else -.012),center.z+rz*sin(angle))
			positions.append(point)
			normals.append(Vector3(cos(angle),1.0,sin(angle)).normalized())
			uv.append(Vector2(point.x*7.0+.5,point.y*7.0))
			bones.append_array(PackedInt32Array([0,0,0,0]))
			weights.append_array(PackedFloat32Array([1,0,0,0]))
	for k in 32:
		var next:int=(k+1)%32
		indices.append_array(PackedInt32Array([k,next,k+32,next,next+32,k+32]))
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_NORMAL]=normals
	if base:
		arrays[Mesh.ARRAY_TEX_UV]=uv
		arrays[Mesh.ARRAY_BONES]=bones
		arrays[Mesh.ARRAY_WEIGHTS]=weights
		arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

static func needs_midriff(lp:Dictionary)->bool:
	var designs:Variant=lp.get("garment_designs",{})
	if not designs is Dictionary:return false
	var checked:Dictionary=Design.validate(designs.get("top",{}))
	return checked.ok and checked.data.base!="saty" and float(checked.data.length)<.999

## A cropped shirt must reveal actual torso skin, not the empty background.
## Keep only lower torso triangles; the full anatomy's chest details remain hidden.
static func midriff_mesh(source:Mesh)->ArrayMesh:
	if _midriff_mesh!=null:return _midriff_mesh
	if source==null or source.get_surface_count()!=1:return null
	var arrays:Array=source.surface_get_arrays(0)
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var source_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var indices:=PackedInt32Array()
	for i in range(0,source_indices.size(),3):
		if points[source_indices[i]].y>1.16 or points[source_indices[i+1]].y>1.16 or points[source_indices[i+2]].y>1.16:continue
		indices.append_array(PackedInt32Array([source_indices[i],source_indices[i+1],source_indices[i+2]]))
	if indices.is_empty():return null
	arrays[Mesh.ARRAY_INDEX]=indices
	# Rest height drives a per-garment fragment mask, keeping the skin only
	# below the actual cropped hem while preserving body morphs and animation.
	var rest:=PackedFloat32Array()
	rest.resize(points.size()*4)
	for i in points.size():
		rest[i*4]=points[i].x
		rest[i*4+1]=points[i].y
		rest[i*4+2]=points[i].z
		rest[i*4+3]=1.0
	arrays[Mesh.ARRAY_CUSTOM0]=rest
	for slot in [Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:arrays[slot]=null
	var result:=ArrayMesh.new()
	result.blend_shape_mode=source.blend_shape_mode
	for i in source.get_blend_shape_count():result.add_blend_shape(source.get_blend_shape_name(i))
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,source.surface_get_blend_shape_arrays(0),{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	if result.get_surface_count()!=1:return null
	_midriff_mesh=result
	return result
