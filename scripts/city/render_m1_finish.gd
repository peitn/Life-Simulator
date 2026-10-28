extends SceneTree
const G=preload("res://tools/automation_lock.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]) or DisplayServer.get_name()=="headless":quit(2);return
	var run_id:String=args[0]
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1120,720); viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var demo=load("res://scenes/city/m1_showcase.tscn").instantiate(); viewport.add_child(demo)
	for spec in [["front",Vector3(12,8,12)],["rear",Vector3(-7,7,-9)],["door_open",Vector3(6,4,8)]]:
		if spec[0]=="door_open":
			demo.door.request_open(true)
			for frame in 90:
				await physics_frame
				if not demo.door.moving:break
			if not demo.door.is_open():print("RENDER_DOOR_FAILED");quit(3);return
		demo.camera.position=spec[1]; demo.camera.look_at(Vector3(3,1,-1),Vector3.UP)
		demo.camera.size=13 if spec[0]!="door_open" else 9
		for frame in 10:await process_frame
		await RenderingServer.frame_post_draw
		var path="res://docs/city/m1-v2-"+run_id+"-"+spec[0]+".jpg"
		if not G.owns(run_id) or FileAccess.file_exists(path):quit(2);return
		var error=viewport.get_texture().get_image().save_jpg(path,.86)
		print("M1_RENDER ",path," ERROR ",error)
		if error!=OK:quit(4);return
	demo.free(); viewport.free(); MaterialsCleanup()
	quit()
func MaterialsCleanup() -> void:
	load("res://scripts/city/m1_materials.gd")._cache.clear()
