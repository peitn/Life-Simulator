extends SceneTree
const Main=preload("res://main.gd")
const Assets=preload("res://scripts/assets/asset_library.gd")
const Actions=preload("res://scripts/sim/action_library.gd")
var world:Node
var clock:Node
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func acting(actor:Node) -> void:
	for i in 16:
		clock.advance(.25)
		if actor.state==actor.State.ACTING:break
	check(actor.state==actor.State.ACTING,"real SimAgent walks and begins acting")
func run() -> void:
	clock=root.get_node("GameClock");clock.running=false
	Assets.enabled=false
	world=Main.new();world.net_config={"mode":"offline","hud":false,"camera":false,"visuals":false,"audio":false,"autoload":false,"autosave":false}
	root.add_child(world);await process_frame
	check(world.sims.size()==3,"real Main household loaded")
	for sim in world.sims:
		sim.command({"id":"cancel"},null);sim.think_cooldown=100000
	var a:Node3D=world.sims[0];var b:Node3D=world.sims[1];var c:Node3D=world.sims[2]
	var fixtures:Dictionary={};var i:=0
	for kind in ["bed_single","bed_double","fridge","sofa"]:
		var furniture=load("res://scenes/city/m2_"+kind+".tscn").instantiate();world.add_child(furniture)
		furniture.position=Vector3(20+i*5,0,0);furniture.rotation.y=PI*.5;i+=1
		world.smart_objects.append(furniture);fixtures[kind]=furniture
		if kind=="sofa":continue
		var action_id:String="snack" if kind=="fridge" else "sleep"
		var action:Dictionary=Actions.get_action(action_id)
		a.global_position=furniture.get_node("Points/Use0").global_position+Vector3(.6,0,0)
		check(a.command(action,furniture),kind+" production command accepted")
		check(furniture.users.has(a),kind+" inherited reservation used by SimAgent")
		acting(a)
		check(a.target==furniture and a.current_action.id==action_id,kind+" actual action targets adapter")
		if kind=="fridge":
			check(a.global_position.distance_to(furniture.get_use_position(a))<.31,"fridge actor remains at front access")
		else:
			check(a.global_position.distance_to(furniture.get_pose_position(a))<.001,kind+" sleep uses floor-level pose contract")
			check(a.current_posture()=="lie",kind+" production lying posture retained")
		a.command({"id":"cancel"},null)
		check(furniture.users.is_empty() and a.state==a.State.IDLE,kind+" production cancellation releases object")
		a.think_cooldown=100000
	var sofa:Node3D=fixtures.sofa
	var relax:Dictionary=Actions.get_action("relax")
	a.global_position=sofa.get_node("Points/Use0").global_position+Vector3(.6,0,0)
	b.global_position=sofa.get_node("Points/Use1").global_position+Vector3(.6,0,0)
	check(a.command(relax,sofa) and b.command(relax,sofa),"two real actors command separate sofa seats")
	check(sofa.users.size()==2,"same production occupancy list holds both actors")
	c.command(relax,sofa)
	check(c.target==null and c.state==c.State.IDLE and not sofa.users.has(c),"third real actor is rejected by occupied sofa")
	c.think_cooldown=100000
	acting(a);acting(b)
	check(a.current_posture()=="sit" and b.current_posture()=="sit","real seated posture for both actors")
	check(a.global_position.distance_to(sofa.get_node("Points/Pose0").global_position)<.001,"first actor at transformed seat0")
	check(b.global_position.distance_to(sofa.get_node("Points/Pose1").global_position)<.001,"second actor at transformed seat1")
	check(absf(angle_difference(a.global_rotation.y,sofa.global_rotation.y))<.001 and absf(angle_difference(b.global_rotation.y,sofa.global_rotation.y))<.001,"seated actors face sofa front after production action signal")
	var stable:Vector3=b.global_position
	a.command({"id":"cancel"},null)
	check(sofa.users.size()==1 and sofa.users[0]==b,"first actor cancellation preserves second reservation")
	check(sofa.get_pose_position(b).distance_to(stable)<.001,"second actor retains seat1 after first cancellation")
	c.global_position=sofa.get_node("Points/Use0").global_position+Vector3(.6,0,0)
	c.command(relax,sofa);acting(c)
	check(c.global_position.distance_to(sofa.get_node("Points/Pose0").global_position)<.001,"new actor fills freed physical seat0")
	check(b.global_position.distance_to(stable)<.001 and c.global_position.distance_to(b.global_position)>.99,"simultaneous seats remain distinct and stationary")
	c.leave_world()
	check(not sofa.users.has(c) and sofa.users.has(b),"real leave_world releases only departing actor")
	b.command({"id":"cancel"},null)
	check(sofa.users.is_empty(),"final cancellation releases all sofa occupancy")
	check(not b.is_connected("action_started",Callable(sofa,"_on_action_started")),"action hook disconnected on release")
	a.global_position=sofa.get_node("Points/Use0").global_position+Vector3(.6,0,0)
	check(a.command(Actions.get_action("sleep_sofa"),sofa),"real sofa sleep command accepted")
	acting(a)
	check(a.current_posture()=="lie" and a.global_position.distance_to(sofa.get_node("Points/Lie").global_position)<.001,"sofa sleeper uses central lying pose")
	check(absf(angle_difference(a.global_rotation.y,sofa.global_rotation.y+PI*.5))<.001,"sofa sleeper aligns along sofa width")
	b.command(relax,sofa)
	check(not sofa.users.has(b) and b.target==null,"whole-sofa sleeper rejects a seated arrival")
	c.command(Actions.get_action("sleep_sofa"),sofa)
	check(not sofa.users.has(c) and c.target==null,"whole-sofa sleeper rejects a second sleeper")
	check(not sofa.is_available(b),"production planner sees sleeping sofa as occupied")
	a.command({"id":"cancel"},null)
	check(sofa.users.is_empty() and sofa.is_available(b),"wake-up releases entire sofa")
	b.global_position=sofa.get_node("Points/Use0").global_position+Vector3(.6,0,0)
	b.command(relax,sofa);acting(b)
	# A sleeper must also be rejected while another actor is seated.
	a.command(Actions.get_action("sleep_sofa"),sofa)
	check(a.target==null and not sofa.users.has(a) and sofa.users.has(b),"sleeper cannot take sofa away from seated actor")
	b.leave_world()
	check(sofa.users.is_empty(),"departing seated actor leaves sofa completely available")
	world.queue_free();await process_frame;await process_frame
	Assets.enabled=true;Assets.clear_cache();clock.running=false
	print("M2_AGENTS ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
