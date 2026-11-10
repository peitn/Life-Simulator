extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
var run_id:String
var tag:String
func _init() -> void:call_deferred("run")
func capture(view:SubViewport,name_:String) -> void:
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	var path:String="res://docs/city/m2-final-"+run_id+"-"+tag+"-"+name_+".jpg"
	assert(G.owns(run_id) and not FileAccess.file_exists(path));assert(view.get_texture().get_image().save_jpg(path,.9)==OK);print("CAPTURE ",path)
func viewport(size_:Vector2i) -> SubViewport:
	var v:=SubViewport.new();v.size=size_;v.world_3d=World3D.new();v.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(v);return v
func gallery(view:SubViewport,variants:bool) -> Node3D:
	var scene:=Node3D.new();view.add_child(scene)
	var keys:Array=["window_wide","window_double","window_arch","door_panelled","door_glazed","door_metal"] if variants else B.Fixture.catalog().entries.keys()+["sofa","bed_single","bed_double","fridge"]
	var columns:int=3 if variants else 5
	for index in keys.size():
		var kind:String=keys[index];var node=load("res://scenes/city/m2_"+kind+".tscn").instantiate();scene.add_child(node)
		node.position=Vector3((index%columns)*4.5,0,(index/columns)*5.0)
		var caption:=Label3D.new();caption.text=kind;caption.font_size=48;caption.pixel_size=.006;caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED;caption.position=node.position+Vector3(0,2.7 if variants else 2.3,0);scene.add_child(caption)
	var ground:=MeshInstance3D.new();var slab:=BoxMesh.new();slab.size=Vector3(26,.1,20);ground.mesh=slab;ground.position=Vector3(9,-.12,5);var ground_mat:=B.material("enamel");ground_mat.albedo_color=Color(.28,.33,.38);ground_mat.roughness=1;ground.material_override=ground_mat;scene.add_child(ground)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.11,.15,.19);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;scene.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.light_energy=1.5;scene.add_child(light)
	return scene
func run() -> void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or not G.owns(args[0]) or DisplayServer.get_name()=="headless":quit(2);return
	run_id=args[0];tag=args[1]
	for size_ in [Vector2i(1280,900),Vector2i(390,900)]:
		var view:=viewport(size_);var editor=load("res://scenes/city/furniture_editor.tscn").instantiate();view.add_child(editor)
		editor.replace(editor.Doc.preset("dining_chair"));editor.selected=0;editor.edit_part("material","wood_oak")
		await capture(view,"editor-"+str(size_.x));view.free()
	for variants in [false,true]:
		var view:=viewport(Vector2i(1600,1000));var scene:=gallery(view,variants);var camera:=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
		var target:=Vector3(5,1,2.5) if variants else Vector3(9,.5,5);camera.size=16 if variants else 28
		for spec in [["front",Vector3(10,12,20)],["rear",Vector3(-10,12,-20)],["top",Vector3(0,25,.1)]]:
			camera.position=target+spec[1];camera.look_at(target,Vector3.UP)
			await capture(view,("variants-" if variants else "furniture-")+spec[0])
		view.free()
	var view:=viewport(Vector2i(1280,900));var catalogue=load("res://scenes/city/m2_catalog_showcase.tscn").instantiate();view.add_child(catalogue)
	for kind in ["stove","tv","treadmill","shower"]:
		catalogue.select(catalogue.keys.find(kind));catalogue.use_next();catalogue.advance_minutes(3)
		if kind=="tv":catalogue.use_next();catalogue.advance_minutes(3)
		await capture(view,"catalogue-"+kind)
	view.free();quit()
