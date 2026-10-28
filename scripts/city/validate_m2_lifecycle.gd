extends SceneTree
class Actor extends Node3D:
	signal action_started(sim:Node3D,action:Dictionary)
	var current_action:Dictionary={"id":"relax","posture":"sit"}
	var target:Node3D
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func run() -> void:
	var fixture:=Node3D.new();root.add_child(fixture)
	var sofa=load("res://scenes/city/m2_sofa.tscn").instantiate();fixture.add_child(sofa);sofa.rotation.y=PI*.5
	var a:=Actor.new();fixture.add_child(a);a.target=sofa
	var callback:=Callable(sofa,"_on_action_started")
	check(sofa.reserve(a) and a.is_connected("action_started",callback),"action callback connected by reservation")
	sofa.release(a)
	check(not a.is_connected("action_started",callback),"formal release disconnects callback")
	sofa.reserve(a);a.action_started.emit(a,a.current_action)
	check(absf(angle_difference(a.global_rotation.y,sofa.global_rotation.y))<.001,"synchronous action signal sees current target and sets facing")
	sofa.queue_free();await process_frame;await process_frame
	check(a.get_signal_connection_list("action_started").is_empty(),"removing receiver disconnects living emitter")
	a.action_started.emit(a,a.current_action)
	check(is_instance_valid(a),"emitting after furniture removal is harmless")
	a.free()
	sofa=load("res://scenes/city/m2_sofa.tscn").instantiate();fixture.add_child(sofa)
	var dead:=Actor.new();fixture.add_child(dead);dead.target=sofa;sofa.reserve(dead);dead.free()
	check(sofa.get_use_position(dead).is_finite(),"freed actor query uses guarded fallback slot")
	var replacement:=Actor.new();fixture.add_child(replacement)
	check(sofa.reserve(replacement) and sofa.users.size()==1,"freed emitter reservation pruned without a stale callback")
	sofa.release(replacement);replacement.free();sofa.free()
	var rng:=RandomNumberGenerator.new();rng.seed=28102026
	for kind in ["sofa","bed_double"]:
		var object_=load("res://scenes/city/m2_"+kind+".tscn").instantiate();fixture.add_child(object_)
		var actors:Array=[]
		for i in 5:
			var actor:=Actor.new();fixture.add_child(actor);actor.target=object_;actors.append(actor)
		for step in 120:
			var positions:Dictionary={}
			for user in object_.users:positions[user.get_instance_id()]=object_.get_pose_position(user)
			var actor:Actor=actors[rng.randi_range(0,4)]
			if rng.randf()<.6:object_.reserve(actor)
			else:object_.release(actor)
			check(object_.users.size()<=object_.capacity,kind+" same-frame capacity never exceeded")
			var points:Array=[];var stable:=true;var distinct:=true
			for user in object_.users:
				var pos:Vector3=object_.get_pose_position(user)
				if positions.has(user.get_instance_id()):stable=stable and pos==positions[user.get_instance_id()]
				distinct=distinct and pos not in points;points.append(pos)
			check(stable and distinct,kind+" interleaved operations retain distinct stable slots")
		for actor in actors:object_.release(actor);actor.free()
		check(object_.users.is_empty() and object_._slot_by_id.is_empty(),kind+" stress leaves no occupancy metadata")
		object_.free()
	fixture.free()
	print("M2_LIFECYCLE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
