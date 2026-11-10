extends RefCounted
const Fixture=preload("res://scripts/city/m2_fixture.gd")
static func vec(a:Array) -> Vector3:return Vector3(a[0],a[1],a[2])
static func material(id:String,tint:Color=Color.WHITE) -> StandardMaterial3D:
	var c:Array=Fixture.catalog().materials[id]
	var m:=StandardMaterial3D.new();m.resource_name=id
	m.albedo_color=Color(c[0],c[1],c[2],c[3])*tint;m.roughness=.65
	if id=="steel":m.metallic=.8;m.roughness=.25
	if id=="ceramic" or id=="enamel":m.roughness=.24
	if id=="glass":m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.roughness=.08;m.cull_mode=BaseMaterial3D.CULL_DISABLED
	if id=="screen":m.emission_enabled=true;m.emission=Color(.06,.16,.2);m.emission_energy_multiplier=.4
	return m
static func mesh_part(p:Dictionary) -> MeshInstance3D:
	var m:=MeshInstance3D.new();m.name=p.name;m.position=vec(p.position)
	var size:Vector3=vec(p.size)
	if p.shape=="cylinder":
		var cylinder:=CylinderMesh.new();cylinder.top_radius=size.x*.5;cylinder.bottom_radius=size.x*.5
		cylinder.height=size.y;cylinder.radial_segments=16;cylinder.rings=1;m.mesh=cylinder;m.scale.z=size.z/size.x
	else:
		var box:=BoxMesh.new();box.size=size;m.mesh=box
	m.material_override=material(p.material) if Fixture.catalog().materials.has(p.material) else null;return m
static func own(root:Node,node:Node) -> void:
	for child in node.get_children():child.owner=root;own(root,child)
static func build(kind:String) -> Node3D:
	var d:Dictionary=Fixture.catalog().entries[kind]
	var object_:=Node3D.new();object_.set_script(Fixture);object_.furniture_kind=kind;object_.name="M2_"+kind
	var model:=Node3D.new();model.name="Model";object_.add_child(model)
	for p in d.parts:model.add_child(mesh_part(p))
	var body:=StaticBody3D.new();body.name="Collision";body.collision_layer=1;body.collision_mask=3;object_.add_child(body)
	for part in d.colliders:
		var c:=CollisionShape3D.new();c.name=part.name;c.position=vec(part.position)
		var s:=BoxShape3D.new();s.size=vec(part.size);c.shape=s;body.add_child(c)
	var points:=Node3D.new();points.name="Points";object_.add_child(points)
	for slot in object_.capacity:
		for label in ["Use","Pose"]:
			var marker:=Marker3D.new();marker.name=label+str(slot)
			marker.position=object_.use_offsets[slot] if label=="Use" or object_.pose_offsets.is_empty() else object_.pose_offsets[slot]
			points.add_child(marker)
	own(object_,object_);return object_
static func bounds(node:Node3D) -> AABB:
	var first:=true;var result:=AABB()
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var t:Transform3D=mesh.transform;var parent=mesh.get_parent()
		while parent!=node and parent!=null:t=parent.transform*t;parent=parent.get_parent()
		var a:AABB=t*mesh.mesh.get_aabb()
		result=a if first else result.merge(a);first=false
	return result
