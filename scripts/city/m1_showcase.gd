extends Node3D
const Materials=preload("res://scripts/city/m1_materials.gd")
var door:Node3D
var camera:Camera3D

func piece(path:String,where:Vector3,kind:String="",angle:float=0) -> Node3D:
	var node=load("res://scenes/city/"+path).instantiate()
	add_child(node); node.position=where; node.rotation.y=angle
	if not kind.is_empty(): Materials.apply(node,kind)
	return node

func _ready() -> void:
	# 4x4m module compatibility assembly, deliberately open on two sides.
	# A final inhabited house/district and main build UI are later milestones.
	for x in [0,2]:
		for z in [0,-2]:
			piece("foundation_2m.tscn",Vector3(x,0,z),"concrete")
			piece("floor_tile_2m.scn",Vector3(x,0,z),"wood" if x==0 else "tile")
	door=piece("door_hinged_1m.tscn",Vector3.ZERO)
	Materials.apply(door.get_node("Frame"),"plaster")
	piece("wall_window_2m.scn",Vector3(2,0,0),"brick")
	piece("wall_solid_2m.scn",Vector3(0,0,-4),"plaster")
	piece("wall_corner_2m.scn",Vector3(4,0,-2),"brick",PI)
	piece("ceiling_tile_2m.scn",Vector3(0,2.8,0),"plaster")
	piece("ceiling_tile_2m.scn",Vector3(2,2.8,0),"plaster")
	piece("roof_gable_2m.scn",Vector3(0,3,0),"roof")
	piece("gable_infill_2m.scn",Vector3(0,3,0),"plaster")
	piece("roof_flat_2m.tscn",Vector3(2,3,0),"roof")
	# The separate stair/landing assembly preserves its full 3m rise/clearance.
	piece("stair_landing_demo.tscn",Vector3(6,0,0),"concrete")
	for i in Materials.NAMES.size():
		var swatch:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(.85,.12,.85)
		swatch.mesh=mesh; swatch.material_override=Materials.make(Materials.NAMES[i])
		add_child(swatch); swatch.position=Vector3(float(i),0,2)
		var label:=Label3D.new(); label.text=Materials.NAMES[i]; label.font_size=40; label.pixel_size=.005
		label.position=swatch.position+Vector3(0,.3,0); add_child(label)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR
	e.background_color=Color(.16,.20,.24); e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color.WHITE; e.ambient_light_energy=.7; env.environment=e; add_child(env)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); light.light_energy=1.8; add_child(light)
	camera=Camera3D.new(); add_child(camera); camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=13
	camera.position=Vector3(12,8,12); camera.look_at(Vector3(3,1,-1),Vector3.UP)
	var layer:=CanvasLayer.new(); add_child(layer)
	var caption:=Label.new(); caption.text="Life Simulator — M1 stavebni moduly\nE: otevrit / zavrit dvere | 6 materialu | skutecne kolize"
	caption.position=Vector2(18,16); caption.add_theme_font_size_override("font_size",18); layer.add_child(caption)

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_E:
		door.request_open(not door.is_open())
		get_viewport().set_input_as_handled()
