extends SceneTree
const Studio=preload("res://scripts/ui/clothing_studio.gd")
const G=preload("res://tools/automation_lock.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	var lease:String=args[0]
	var studio:=Studio.new()
	root.add_child(studio)
	await process_frame
	await process_frame
	studio._on_preset(2)
	studio._focus=true
	studio._refresh_preview()
	for size in [Vector2i(1280,900),Vector2i(360,800)]:
		DisplayServer.window_set_size(size)
		root.size=size
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		var apply:Rect2=studio._apply.get_global_rect()
		var close:Control=studio.find_child("CloseStudio",true,false)
		if apply.end.x>size.x+.5 or apply.end.y>size.y+.5 or close.get_global_rect().end.x>size.x+.5:
			print("FAIL footer outside viewport");quit(4);return
		print("LAYOUT ",size," studio=",studio.size," apply=",apply," close=",close.get_global_rect()," scroll=",studio._scroll.get_global_rect())
		if not G.owns(lease):quit(2);return
		var path:String="res://previews/"+lease+"/studio-"+str(size.x)+".jpg"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		print("CAPTURE ",path," rc=",root.get_texture().get_image().save_jpg(path,.9))
	# High-detail actual garment captures, independent of UI size.
	for preset in [1,2,3,4,5,6]:
		studio._on_preset(preset)
		if preset==1:
			studio.change("sleeve_length",.55)
			studio.change("ease",.5)
			studio.change("length",.7)
			studio.change("cuff_flare",.6)
		studio._focus=true
		studio._pose=1 if preset==1 else 0
		studio._refresh_preview()
		studio._preview.viewport.size=Vector2i(600,600)
		studio._preview.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		if not G.owns(lease):quit(2);return
		var path:String="res://previews/"+lease+"/garment-"+str(preset)+".jpg"
		print("GARMENT ",preset," rc=",studio._preview.viewport.get_texture().get_image().save_jpg(path,.9))
	studio.free()
	await process_frame
	quit()
