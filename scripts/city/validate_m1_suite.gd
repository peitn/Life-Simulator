extends SceneTree
const G=preload("res://tools/automation_lock.gd")
var results:Array=[]
var failed:=0
var passed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func child(name_:String,extra:Array=[]) -> Dictionary:
	var args=["--headless","--path",ProjectSettings.globalize_path("res://"),"--fixed-fps","60","--quit-after","3600","--script","res://scripts/city/"+name_]
	if not extra.is_empty():args.append("--");args.append_array(extra)
	var o=[]
	var rc=OS.execute(OS.get_executable_path(),args,o,true)
	return {"script":name_,"args":extra,"exit":rc,"log":"".join(o)}
func _init() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	var run_id:String=args[0]
	var specs=[
		["validate_doorway.gd","CITY_TEST_RESULT="],["validate_solid_wall.gd","SOLID_TEST_RESULT="],
		["validate_corner_source.gd","CORNER_SOURCE_SCENE_RESULT="],["validate_corner_wall.gd","CORNER_RESULT="],
		["validate_window_wall.gd","WINDOW_RESULT="],["validate_floor_tile.gd","FLOOR_RESULT="],
		["validate_ceiling_tile.gd","CEILING_RESULT="],["validate_roof_gable.gd","ROOF_RESULT="],
		["validate_roof_assembly.gd","ASSEMBLY_RESULT="],["validate_gable_infill.gd","GABLE_INFILL_RESULT="],
		["validate_gable_envelope.gd","GABLE_ENVELOPE_RESULT="],["validate_gable_collision.gd","GABLE_COLLISION_RESULT "],
		["validate_gable_assembly.gd","GABLE_ASSEMBLY_RESULT="],["validate_staircase.gd","STAIRS "],
		["validate_stair_landing_demo.gd","STAIR_DEMO "],["validate_stair_capsule_traversal.gd","CAPSULE_TRAVERSAL "],
		["validate_stair_lateral_offsets.gd","STAIR_LATERAL "],["validate_stair_physics_walk.gd","PHYSICS_STAIR "],
		["validate_stair_repeated.gd","STAIR_REPEATED "],["validate_stair_clearance.gd","STAIR_CLEARANCE "],
		["validate_m1_finish.gd","M1_FINISH "],["validate_m1_showcase.gd","M1_SHOWCASE "]]
	for spec in specs:
		var result=child(spec[0]);results.append(result)
		var clean:bool=result.exit==0 and spec[1] in result.log and not "SCRIPT ERROR" in result.log and not "ERROR:" in result.log and not "FAIL " in result.log
		check(clean,spec[0])
		print("M1_SUITE_CASE ",spec[0]," clean=",clean)
		if not clean:print(result.log.right(2000))
	var manifest=load("res://scripts/city/validate_gable_manifest.gd")
	var audit:Dictionary=manifest.audit();results.append({"script":"validate_gable_manifest.gd","runner":"static audit","result":audit})
	check(audit.ok,"gable manifest static audit")
	check(not manifest.audit(true,false).ok,"malformed gable metadata rejected")
	check(not manifest.audit(false,true).ok,"wrong gable run rejected")
	var leaf=child("validate_m1_finish.gd",["--disable-leaf"]);results.append(leaf)
	check(leaf.exit==1 and "FAIL closed door blocks capsule" in leaf.log and not "SCRIPT ERROR" in leaf.log,"disabled leaf negative control detected")
	var wall=child("validate_stair_physics_walk.gd",["--block-path"]);results.append(wall)
	check(wall.exit==1 and "top=false" in wall.log and not "SCRIPT ERROR" in wall.log,"wall negative prevents stair completion")
	assert(G.owns(run_id))
	var f=FileAccess.open("res://docs/city/m1-final-regression-20261028.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"run_id":run_id,"passed":passed,"failed":failed,"results":results},"  "));f.close()
	print("M1_SUITE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
