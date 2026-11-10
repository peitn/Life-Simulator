extends SceneTree
const Main=preload("res://main.gd")
const Assets=preload("res://scripts/assets/asset_library.gd")
const Actions=preload("res://scripts/sim/action_library.gd")
const Fixture=preload("res://scripts/city/m2_fixture.gd")
var world:Node
var clock:Node
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func acting(actor:Node) -> void:
	for i in 20:
		clock.advance(.25)
		if actor.state==actor.State.ACTING:break
	check(actor.state==actor.State.ACTING,"real agent reached fixture")
func run() -> void:
	clock=root.get_node("GameClock");clock.running=false;Assets.enabled=false
	world=Main.new();world.net_config={"mode":"offline","hud":false,"camera":false,"visuals":false,"audio":false,"autoload":false,"autosave":false};root.add_child(world);await process_frame
	for sim in world.sims:sim.command({"id":"cancel"},null);sim.think_cooldown=100000
	var a:Node3D=world.sims[0];var b:Node3D=world.sims[1];var c:Node3D=world.sims[2]
	for kind in ["stove","shower","bookshelf","treadmill","tv"]:
		var d:Dictionary=Fixture.catalog().entries[kind];var action:Dictionary=Actions.get_action(d.action)
		for yaw in [0.0,PI*.5,PI,PI*1.5]:
			var f=load("res://scenes/city/m2_"+kind+".tscn").instantiate();world.add_child(f);f.position=Vector3(25,0,10);f.rotation.y=yaw;world.smart_objects.append(f)
			for sim in world.sims:
				sim.needs.values={"hunger":70.0,"energy":70.0,"hygiene":70.0,"fun":70.0,"social":70.0,"comfort":70.0}
				sim.think_cooldown=100000
			a.global_position=f.get_node("Points/Use0").global_position+f.global_basis*Vector3(0,0,.5)
			check(a.command(action,f),kind+" command accepted");acting(a)
			check(f.users.has(a) and a.target==f and a.current_action.id==d.action,kind+" production reservation/action")
			if kind=="treadmill":check(a.global_position.distance_to(f.get_pose_position(a))<.001,"workout actor stands on measured belt top")
			elif kind=="tv":check(a.global_position.distance_to(f.get_pose_position(a))<.001 and a.current_posture()=="sit","watcher sits on assembly bench")
			else:check(a.global_position.distance_to(f.get_use_position(a))<.31,kind+" standing access")
			if kind=="tv":
				b.global_position=f.get_node("Points/Use1").global_position+f.global_basis*Vector3(0,0,.5)
				check(b.command(action,f),"second watcher accepted");acting(b)
				var stable:Vector3=b.global_position
				a.command({"id":"cancel"},null)
				check(b.global_position==stable and f.get_pose_position(b)==stable,"watcher seat survives other cancellation")
				a.global_position=f.get_node("Points/Use0").global_position+f.global_basis*Vector3(0,0,.5)
				a.command(action,f);acting(a)
			c.command(action,f)
			check(not f.users.has(c) and c.target==null,kind+" occupied arrival rejected");c.think_cooldown=100000
			var use:Vector3=f.get_use_position(a)
			a.command({"id":"cancel"},null);a.think_cooldown=100000
			check(not f.users.has(a) and not a.is_connected("action_started",Callable(f,"_on_action_started")),kind+" cancellation releases callback and slot")
			if kind=="treadmill":check(a.global_position.distance_to(use)<.001 and f._on_platform.is_empty(),"cancelled runner returns to floor approach")
			b.command({"id":"cancel"},null);b.think_cooldown=100000
			a.global_position=use+f.global_basis*Vector3(0,0,.5);a.command(action,f);acting(a)
			# Production completion, including effects and action counts, no _finish shortcut.
			var need:String="hunger" if kind=="stove" else ("hygiene" if kind=="shower" else "fun")
			a.needs.values[need]=10.0
			for i in 300:
				clock.advance(.25)
				if a.state==a.State.IDLE:break
			check(a.state==a.State.IDLE and a.target==null and f.users.is_empty(),kind+" normal completion releases fixture")
			check(a.needs.values[need]>15.0,kind+" actual production need effect")
			if kind=="treadmill":check(a.global_position.distance_to(use)<.001,"finished runner returns to approach")
			a.think_cooldown=100000;a.global_position=use;a.command(action,f);acting(a)
			a.leave_world();check(f.users.is_empty(),kind+" leave_world cleanup")
			# Explicitly rejoin clock signals after the production disconnect for the next case.
			clock.time_advanced.connect(a.sim_tick);clock.day_changed.connect(a._on_day_changed)
			a.think_cooldown=100000;world.smart_objects.erase(f);f.free()
	world.queue_free();await process_frame;await process_frame;Assets.enabled=true;Assets.clear_cache();clock.running=false
	print("M2_FIXTURE_AGENTS ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
