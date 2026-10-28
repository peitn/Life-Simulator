extends Node3D
const Furniture=preload("res://scripts/city/m2_furniture.gd")
var camera:Camera3D
func _ready() -> void:
	var specs=[["sofa",Vector3(-2.5,0,1.5),0.0],["bed_single",Vector3(-2.5,0,-2),0.0],["bed_double",Vector3(2,0,-2),PI*.5],["fridge",Vector3(2.5,0,1.5),0.0]]
	var floor:=MeshInstance3D.new();var slab:=BoxMesh.new();slab.size=Vector3(10,.1,8);floor.mesh=slab
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.65,.63,.57);floor.material_override=mat
	add_child(floor);floor.position=Vector3(0,-.06,0)
	for spec in specs:
		var object_=load("res://scenes/city/m2_"+spec[0]+".tscn").instantiate();add_child(object_);object_.position=spec[1];object_.rotation.y=spec[2]
		for marker in object_.get_node("Points").get_children():
			if marker.name.begins_with("Pose") or marker.name=="Lie":continue
			var sphere:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.07;mesh.height=.14;sphere.mesh=mesh
			var material:=StandardMaterial3D.new();material.albedo_color=Color(.05,.65,.25) if marker.name.begins_with("Use") else Color(.05,.35,.95)
			sphere.material_override=material;marker.add_child(sphere);sphere.position.y=.02
		var label:=Label3D.new();label.text=object_.display_name+" | "+str(object_.capacity)+(" místa" if object_.capacity==2 else " místo")
		label.font_size=40;label.pixel_size=.005;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.position=object_.position+Vector3(0,1.95 if spec[0]=="fridge" else 1.1,0);add_child(label)
	var env:=WorldEnvironment.new();var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.14,.18,.22)
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.7;env.environment=e;add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.6;add_child(light)
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=13
	camera.position=Vector3(10,9,13);camera.look_at(Vector3(0,.5,0),Vector3.UP)
	var layer:=CanvasLayer.new();add_child(layer);var caption:=Label.new()
	caption.text="Life Simulator — nábytek M2\nZelená: přístup | Modrá: skutečný povrch sedáku / lůžka"
	caption.position=Vector2(18,16);caption.add_theme_font_size_override("font_size",18);layer.add_child(caption)
