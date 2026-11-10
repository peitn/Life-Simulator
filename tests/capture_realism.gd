extends SceneTree
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const G=preload("res://tools/automation_lock.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2 or not G.owns(args[0]):quit(2);return
	if args.size()>2 and args[2]=="low":
		var a=load("res://scripts/assets/asset_library.gd")
		a._cache["character_hq"]=a._get_scene("character")
	var p:=Preview.new()
	root.add_child(p)
	var d:Dictionary=CD.create().to_dict()
	d["body"]["height_cm"]=178.0
	d["hair"]["style"]="kratke"
	d["hair"]["facial_style"]="zadne"
	d["clothing"]["bezne"]["shoes"]="bosy"
	p.show_draft(d)
	p.visual._anim.stop()
	p.visual.set_hand_pose("open")
	p.viewport.size=Vector2i(640,800)
	p.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var path:String="res://previews/"+args[0]+"/"+args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	for shot in [["face",Vector3(0,1.66,0),.32,0.0],["quarter",Vector3(0,1.66,0),.32,.65],["profile",Vector3(0,1.66,0),.32,1.57],["body",Vector3(0,.9,0),2.0,.2],["hand",Vector3(.32,.83,0),.22,0.0],["feet",Vector3(0,.13,.04),.40,.35]]:
		p.visual.rotation.y=shot[3]
		var target:Vector3=shot[1].rotated(Vector3.UP,shot[3])
		p.camera.size=shot[2]
		p.camera.position=target+Vector3(0,.02,3)
		p.camera.look_at(target)
		for i in 12:await process_frame
		await RenderingServer.frame_post_draw
		if not G.owns(args[0]):quit(2);return
		var img:=p.viewport.get_texture().get_image()
		print("SHOT ",shot[0]," ",img.save_jpg(path+"/"+shot[0]+".jpg",.92))
	p.free()
	await process_frame
	quit()
