extends SceneTree
const Assets=preload("res://scripts/assets/asset_library.gd")
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func press(node:Node,text:String) -> void:
	for button in node.find_children("*","Button",true,false):
		if button.text==text:button.pressed.emit();return
	check(false,"actual button exists "+text)
func _init() -> void:call_deferred("run")
func run() -> void:
	Assets.enabled=false
	var view=load("res://scenes/city/m2_catalog_showcase.tscn").instantiate();root.add_child(view);await process_frame
	check(view.keys.size()==21 and view.picker.item_count==21,"21 actual catalogue entries")
	for index in view.keys.size():
		view.select(index);var kind:String=view.keys[index]
		check(view.current!=null and view.picker.selected==index,kind+" selectable real scene")
		if not view.action_id.is_empty():
			check(not view.action_button.disabled,"interactive catalogue button enabled")
			press(view,"Použít dalším Simem");view.advance_minutes(3)
			check(view.current.users.size()==1 and view.world.sims[0].target==view.current and view.world.sims[0].state==view.world.sims[0].State.ACTING,kind+" real command button acts")
			press(view,"Zrušit akce");check(view.current.users.is_empty(),kind+" real cancel button")
		else:check(view.action_button.disabled and not view.world.smart_objects.has(view.current),kind+" no fictitious advertised action")
		check(view.door_button.disabled==(not view.current.has_method("request_open")),kind+" door controls state")
	view.select(view.keys.find("tv"));press(view,"Použít dalším Simem");view.advance_minutes(3)
	press(view,"Použít dalším Simem");view.advance_minutes(3)
	check(view.current.users.size()==2,"two viewers from actual catalogue button")
	var a:Node3D=view.world.sims[0];var b:Node3D=view.world.sims[1];var stable:Vector3=b.global_position
	a.command({"id":"cancel"},null)
	check(view.current.get_pose_position(b)==stable,"catalogue preserves remaining viewer seat")
	press(view,"Dokončit akce");check(view.current.users.is_empty(),"catalogue normal completion button")
	# A freed runner is pruned from both authoritative users and platform metadata.
	var f=load("res://scenes/city/m2_treadmill.tscn").instantiate();root.add_child(f)
	var actor:=Node3D.new();root.add_child(actor);check(f.reserve(actor),"lifecycle dummy reserves runner")
	f._on_platform[actor.get_instance_id()]=true;actor.free()
	var replacement:=Node3D.new();root.add_child(replacement)
	check(f.is_available(replacement) and f._on_platform.is_empty() and f.users.is_empty(),"freed platform user pruned before new reservation")
	replacement.position=Vector3(4,0,4);var position:Vector3=replacement.position
	check(f.reserve(replacement),"replacement runner accepted");f.release(replacement)
	check(replacement.position==position,"never-started runner release does not teleport")
	f.reserve(replacement);f._on_platform[replacement.get_instance_id()]=true;var exit_position:Vector3=f.get_use_position(replacement);f.free()
	check(replacement.global_position.distance_to(exit_position)<.001,"destroyed occupied platform restores surviving actor to floor")
	replacement.free();view.free();await process_frame;Assets.enabled=true;Assets.clear_cache()
	print("M2_CATALOGUE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
