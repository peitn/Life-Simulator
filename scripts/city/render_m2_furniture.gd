extends SceneTree
const G=preload("res://tools/automation_lock.gd")
func _init() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]) or DisplayServer.get_name()=="headless":quit(2);return
	var run_id:String=args[0]
	var viewport:=SubViewport.new();viewport.size=Vector2i(1120,720);viewport.world_3d=World3D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var demo=load("res://scenes/city/m2_showcase.tscn").instantiate();viewport.add_child(demo)
	for spec in [["front",Vector3(10,9,13)],["rear",Vector3(-10,8,-12)],["top",Vector3(0,15,.1)]]:
		demo.camera.position=spec[1];demo.camera.look_at(Vector3(0,.5,0),Vector3.UP)
		for frame in 20:await process_frame
		await RenderingServer.frame_post_draw
		var path="res://docs/city/m2-v2-"+run_id+"-"+spec[0]+".jpg"
		if not G.owns(run_id) or FileAccess.file_exists(path):quit(2);return
		var error=viewport.get_texture().get_image().save_jpg(path,.86);print("M2_RENDER ",path," ERROR ",error)
		if error!=OK:quit(3);return
	demo.free();viewport.free();quit()
