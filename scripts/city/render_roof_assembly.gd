extends SceneTree
const G=preload("res://tools/automation_lock.gd")
func _init():
	call_deferred("run")
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]) or DisplayServer.get_name()=="headless":
		quit(2);return
	var settings=root.get_node_or_null("GameSettings")
	if settings!=null: settings.persist=false
	var viewport=SubViewport.new()
	viewport.size=Vector2i(640,480)
	viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var demo=load("res://scenes/city/roof_assembly_demo.tscn").instantiate()
	viewport.add_child(demo)
	var camera=demo.get_node("Camera")
	camera.size=4.0
	for spec in [["front",Vector3(1,3.1,6),Vector3(1,2.6,0)],["rear",Vector3(1,3.1,-10),Vector3(1,2.6,-4)]]:
		camera.position=spec[1]
		camera.look_at(spec[2],Vector3.UP)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var img=viewport.get_texture().get_image()
		if not G.owns(args[0]):quit(2);return
		var path="res://docs/city/assembly-"+args[0]+"-"+spec[0]+".jpg"
		if FileAccess.file_exists(path):quit(3);return
		var err=img.save_jpg(path,.85)
		print("CAPTURE=",path," ERROR=",err," SIZE=",img.get_size())
		if err!=OK:quit(1);return
	demo.free()
	viewport.free()
	quit()
