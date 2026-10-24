extends SceneTree
# Run with -- <owned city run_id>. Writes only to a new run-specific fixture directory.
var passed=0
var failed=0
func check(ok,label):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func _init():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(1);return
	var id=args[0]
	var G=load("res://tools/automation_lock.gd")
	if not id.is_valid_filename() or not G.owns(id):
		quit(1);return
	var base="res://scripts/city/test-runs/"+id+"-preflight-v2/"
	if DirAccess.dir_exists_absolute(base):
		print("FIXTURES_ALREADY_EXIST");quit(1);return
	if not G.owns(id):quit(1);return
	DirAccess.make_dir_recursive_absolute(base)
	var source=FileAccess.get_file_as_string("res://scripts/city/build_solid_wall.gd")
	var protected_paths=["res://scenes/city/wall_solid_2m.scn","res://scenes/city/wall_snap_demo.scn","res://scenes/city/wall_doorway_2m.scn"]
	var hashes={}
	for p in protected_paths: hashes[p]=FileAccess.get_sha256(p)
	if not G.owns(id):quit(1);return
	var root_file=FileAccess.open(base+"non_spatial.tscn",FileAccess.WRITE)
	root_file.store_string('[gd_scene format=3]\n\n[node name="NonSpatial" type="Node"]\n')
	root_file.close()
	for fixture in ["missing","wrong_type","wrong_root","valid"]:
		var solid=base+fixture+"_solid.scn"
		var demo=base+fixture+"_demo.scn"
		var worker=source.replace(protected_paths[0],solid).replace(protected_paths[1],demo)
		if fixture=="missing":
			worker=worker.replace(protected_paths[2],base+"absent.scn")
		elif fixture=="wrong_type":
			worker=worker.replace(protected_paths[2],"res://scripts/city/validate_solid_wall.gd")
		elif fixture=="wrong_root":
			worker=worker.replace(protected_paths[2],base+"non_spatial.tscn")
		var script_path=base+fixture+".gd"
		if not G.owns(id):quit(1);return
		var file=FileAccess.open(script_path,FileAccess.WRITE)
		file.store_string(worker);file.close()
		var out=[]
		var status=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script",script_path,"--",id],out,true)
		print(fixture+" exit="+str(status))
		for line in out: print(line)
		if fixture=="valid":
			check(status==0,"valid dependency builds fixture")
			check(FileAccess.file_exists(solid) and FileAccess.file_exists(demo),"both fixture outputs exist")
			var scene=load(demo)
			check(scene is PackedScene,"fixture demo loads")
			if scene is PackedScene:
				var root=scene.instantiate()
				check(root.get_child_count()==3,"fixture demo has three modules")
				check(root.find_children("*","CollisionShape3D",true,false).size()==5,"fixture demo has five colliders")
				root.free()
		else:
			check(status==1,"bad dependency fails deliberately "+fixture)
			check(not FileAccess.file_exists(solid) and not FileAccess.file_exists(demo),"bad dependency writes no output "+fixture)
			check("\n".join(out).contains("INVALID_DOORWAY_ROOT" if fixture=="wrong_root" else "INVALID_DOORWAY_DEPENDENCY"),"bad dependency diagnostic "+fixture)
		for p in protected_paths:
			check(FileAccess.get_sha256(p)==hashes[p],"authored asset unchanged "+p+" "+fixture)
	print("BUILDER_PREFLIGHT_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed==0 else 1)
