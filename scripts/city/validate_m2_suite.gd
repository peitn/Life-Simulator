extends SceneTree
const G=preload("res://tools/automation_lock.gd")
var results:Array=[]
var passed:=0
var failed:=0
func _init() -> void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or not G.owns(args[0]) or args[1] not in ["core","ui","regression","negative"]:quit(2);return
	var run_id:String=args[0];var group:String=args[1]
	var groups={
		"core":[["scripts/city/validate_m2_furniture.gd",[],0,"M2_FURNITURE "],["scripts/city/validate_m2_agents.gd",[],0,"M2_AGENTS "],["scripts/city/validate_m2_lifecycle.gd",[],0,"M2_LIFECYCLE "],["scripts/city/validate_m2_fixtures.gd",[],0,"M2_FIXTURES "],["scripts/city/validate_m2_fixture_agents.gd",[],0,"M2_FIXTURE_AGENTS "]],
		"ui":[["scripts/city/validate_furniture_editor.gd",[run_id],0,"FURNITURE_EDITOR "],["scripts/city/validate_m2_catalogue.gd",[],0,"M2_CATALOGUE "],["scripts/city/validate_city_variants.gd",[],0,"CITY_VARIANTS "]],
		"regression":[["tests/test_assets.tscn",[],0,""],["tests/test_full_playable_slice.tscn",[],0,""]],
		"negative":[["scripts/city/validate_m2_furniture.gd",["--legacy-seat-order"],1,"FAIL "],["scripts/city/validate_m2_fixtures.gd",["--legacy-tv"],1,"FAIL TV second seat remains stable"],["scripts/city/validate_m2_fixtures.gd",["--disable-shower-side"],1,"FAIL shower glass blocks lateral passage"]]}
	for spec in groups[group]:
		assert(G.owns(run_id))
		var command=["40s",OS.get_executable_path(),"--headless","--path",ProjectSettings.globalize_path("res://")]
		if spec[0].ends_with(".gd"):command.append("--script")
		command.append("res://"+spec[0])
		if not spec[1].is_empty():command.append("--");command.append_array(spec[1])
		var output=[];var rc:=OS.execute("timeout",command,output,true);var log:String="".join(output)
		var clean:bool=rc==spec[2] and (spec[3].is_empty() or spec[3] in log) and not "SCRIPT ERROR" in log and not "Parse Error" in log
		if spec[2]==0:clean=clean and not "FAIL " in log
		if clean:passed+=1
		else:failed+=1
		results.append({"target":spec[0],"args":spec[1],"expected_exit":spec[2],"exit":rc,"accepted":clean,"log":log})
		print("M2_SUITE_CASE ",spec[0]," exit=",rc," accepted=",clean)
		print(log.right(800))
	assert(G.owns(run_id))
	var f=FileAccess.open("res://docs/city/m2-final-"+group+"-20261029.json",FileAccess.WRITE);f.store_string(JSON.stringify({"run_id":run_id,"group":group,"passed":passed,"failed":failed,"results":results},"\t"));f.close()
	print("M2_SUITE ",group," ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
