extends SceneTree
const G=preload("res://tools/automation_lock.gd")
func _init()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	var lease:String=args[0]
	var dir:String="res://previews/"+lease+"/source_backup"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for name in ["character.glb","manifest.json"]:
		if not FileAccess.file_exists(dir+"/"+name):
			if DirAccess.copy_absolute("res://assets/models/"+name,dir+"/"+name)!=OK:quit(3);return
	print("REBUILD_BEGIN")
	var result:Dictionary=load("res://tools/import_lsx.gd").convert_composed("character")
	if not result.get("ok",false):print(result);quit(4);return
	if not G.owns(lease):quit(2);return
	var path:="res://assets/models/manifest.json"
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	result["realism_revision"]="2026-10-30-v3"
	manifest["character"]=result
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest,"  "))
	f.close()
	print("REBUILD_COMPLETE verts=",result.verts," tris=",result.tris," bytes=",result.glb_bytes)
	quit()
