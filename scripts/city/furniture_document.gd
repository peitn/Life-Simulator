extends RefCounted
## Data-only furniture drafts. Custom designs are decorative; M2 interactions
## remain on the validated catalogue scenes with measured access points.
const B=preload("res://scripts/city/m2_fixture_builder.gd")
const Surfaces=preload("res://scripts/city/m2_surfaces.gd")
const DIRECTORY="user://furniture_editor/"
const MAX_PARTS=64
static func finite_vector(a:Variant,low:float,high:float) -> bool:
	if not a is Array or a.size()!=3:return false
	for v in a:
		if not (v is float or v is int) or not is_finite(float(v)) or v<low or v>high:return false
	return true
static func validate(d:Variant) -> String:
	if not d is Dictionary:return "Návrh musí být objekt JSON."
	for k in d:
		if k not in ["version","name","parts"]:return "Neznámé pole návrhu."
	var version=d.get("version",0)
	if not (version is int or version is float):return "Neplatná verze."
	if version!=1 or not d.get("name") is String or d.name.length()>80:return "Neplatná verze nebo jméno."
	if not d.get("parts") is Array or d.parts.size()>MAX_PARTS:return "Nejvýše 64 dílů."
	var materials:Array=B.Fixture.catalog().materials.keys()+Surfaces.ids()
	for p in d.parts:
		if not p is Dictionary:return "Neplatný díl."
		for k in p:
			if k not in ["name","shape","size","position","rotation","material","tint","collide"]:return "Neznámé pole dílu."
		if not p.get("name") is String or p.name.length()>80 or p.get("shape","") not in ["box","cylinder"]:return "Neplatné jméno nebo tvar."
		if not finite_vector(p.get("size"),.001,8) or not finite_vector(p.get("position"),-10,10) or not finite_vector(p.get("rotation",[0,0,0]),-180,180):return "Rozměry, pozice nebo otočení jsou mimo rozsah."
		if p.get("material","") not in materials or not finite_vector(p.get("tint",[1,1,1]),0,1) or not p.get("collide",true) is bool:return "Neplatný materiál, barva nebo kolize."
	return ""
static func preset(kind:String) -> Dictionary:
	var data:Dictionary=B.Fixture.catalog().entries[kind]
	var d={"version":1,"name":data.label,"parts":data.parts.duplicate(true)}
	for i in d.parts.size():
		var p:Dictionary=d.parts[i];p.name+=" "+str(i+1);p.rotation=[0,0,0];p.tint=[1,1,1]
		p.collide=false
		for c in data.colliders:
			if B.vec(c.position).distance_to(B.vec(p.position))<.0001 and B.vec(c.size).distance_to(B.vec(p.size))<.0001:p.collide=true
	return d
static func build(d:Dictionary) -> Node3D:
	if not validate(d).is_empty():return null
	var root:=Node3D.new();root.name="CustomFurniture";root.set_meta("furniture_draft",d.duplicate(true))
	var parts:=Node3D.new();parts.name="Parts";root.add_child(parts)
	for i in d.parts.size():
		var p:Dictionary=d.parts[i];var pivot:=Node3D.new();pivot.name="Part"+str(i);pivot.position=B.vec(p.position);pivot.rotation_degrees=B.vec(p.get("rotation",[0,0,0]));parts.add_child(pivot)
		var mesh:=B.mesh_part(p);mesh.position=Vector3.ZERO;pivot.add_child(mesh)
		var mat:StandardMaterial3D=B.material(p.material) if B.Fixture.catalog().materials.has(p.material) else Surfaces.make(p.material)
		if not B.Fixture.catalog().materials.has(p.material):
			# glTF has no triplanar extension. Bake meter UVs into the mesh in both
			# preview and export so mapped materials retain scale in Blender.
			mesh.mesh=metric_uv(mesh,p.shape);mesh.scale=Vector3.ONE;mat.uv1_triplanar=false
		var c:Array=p.get("tint",[1,1,1]);mat.albedo_color*=Color(c[0],c[1],c[2]);mesh.material_override=mat
		if p.get("collide",true):
			var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=3;pivot.add_child(body)
			var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=B.vec(p.size);shape.shape=box;body.add_child(shape)
	B.own(root,root);return root
static func path_for(name_:String,suffix:String="json") -> String:
	var slug:=name_.strip_edges().to_lower().replace(" ","_")
	var safe:=""
	for c in slug:
		if c in "abcdefghijklmnopqrstuvwxyz0123456789_-":safe+=c
	if safe.is_empty():safe="nabytek"
	return DIRECTORY+safe.left(48)+"."+suffix
static func allowed(path:String,suffix:String="json") -> bool:
	return path==path.simplify_path() and path.get_base_dir()==DIRECTORY.trim_suffix("/") and path.ends_with("."+suffix) and not path.get_file().begins_with(".")
static func save(d:Dictionary,path:String) -> Error:
	if not allowed(path) or not validate(d).is_empty():return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var text:=JSON.stringify(d,"\t");var tmp:=path+".tmp"
	var f:=FileAccess.open(tmp,FileAccess.WRITE)
	if f==null:return FileAccess.get_open_error()
	f.store_string(text);f.flush();var err:=f.get_error();f.close()
	if err!=OK:return err
	if FileAccess.file_exists(path):
		err=DirAccess.copy_absolute(path,path+".bak.tmp")
		if err!=OK:return err
		err=DirAccess.rename_absolute(path+".bak.tmp",path+".bak")
		if err!=OK:return err
	return DirAccess.rename_absolute(tmp,path)
static func read(path:String) -> Dictionary:
	if not allowed(path):return {"error":"Nepovolená cesta."}
	for candidate in [path,path+".bak"]:
		var file:=FileAccess.open(candidate,FileAccess.READ)
		if file==null:continue
		if file.get_length()>262144:file.close();continue
		var parser:=JSON.new();var parse_error:=parser.parse(file.get_as_text());file.close()
		if parse_error!=OK:continue
		var d=parser.data
		if validate(d).is_empty():return {"data":d,"recovered":candidate!=path}
	return {"error":"Návrh ani jeho záloha nejsou platné."}
static func export_file(d:Dictionary,path:String) -> Error:
	var extension:=path.get_extension()
	if extension not in ["tscn","glb"] or not allowed(path,extension) or not validate(d).is_empty() or d.parts.is_empty():return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var root:=build(d);var temp:String=path.get_basename()+".tmp."+extension;var error:Error
	if extension=="tscn":
		var packed:=PackedScene.new();error=packed.pack(root)
		if error==OK:error=ResourceSaver.save(packed,temp)
	else:
		var gltf:=GLTFDocument.new();var state:=GLTFState.new();error=gltf.append_from_scene(root.get_node("Parts"),state)
		if error==OK:error=gltf.write_to_filesystem(state,temp)
	root.free()
	if error!=OK:return error
	return DirAccess.rename_absolute(temp,path)

static func metric_uv(instance:MeshInstance3D,shape:String) -> ArrayMesh:
	var arrays=instance.mesh.surface_get_arrays(0).duplicate(true)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var old_uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var uvs:=PackedVector2Array();uvs.resize(vertices.size())
	var size:Vector3=instance.mesh.get_aabb().size*instance.scale
	var a:float=size.x*.5;var b:float=size.z*.5
	var circumference:float=PI*(3*(a+b)-sqrt((3*a+b)*(a+3*b)))
	for i in vertices.size():
		vertices[i]*=instance.scale;normals[i]=(normals[i]/instance.scale).normalized()
		var n:Vector3=normals[i].abs();var v:Vector3=vertices[i]
		if shape=="cylinder" and n.y<.9:uvs[i]=Vector2(old_uvs[i].x*circumference,v.y)
		elif n.y>=n.x and n.y>=n.z:uvs[i]=Vector2(v.x,-v.z)
		elif n.x>=n.z:uvs[i]=Vector2(-v.z,v.y)
		else:uvs[i]=Vector2(v.x,v.y)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TANGENT]=null
	var baked:=ArrayMesh.new();baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var tool:=SurfaceTool.new();tool.create_from(baked,0);tool.generate_tangents();return tool.commit()
