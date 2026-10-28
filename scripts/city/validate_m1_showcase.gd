extends SceneTree
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func _init() -> void:call_deferred("run")
func key() -> void:
	var e:=InputEventKey.new();e.keycode=KEY_E;e.pressed=true
	Input.parse_input_event(e)
	var release:=InputEventKey.new();release.keycode=KEY_E;release.pressed=false
	Input.parse_input_event(release)
func run() -> void:
	var demo=load("res://scenes/city/m1_showcase.tscn").instantiate();root.add_child(demo)
	await process_frame;await physics_frame
	check(demo.door.is_closed(),"saved showcase starts closed")
	check(demo.camera.current,"saved showcase has current camera")
	for y in [2.85,2.95]:
		var query:=PhysicsPointQueryParameters3D.new();query.position=Vector3(3,y,-1);query.collision_mask=1
		check(not demo.get_world_3d().direct_space_state.intersect_point(query).is_empty(),"ceiling fills wall-to-roof seam")
	var side:=PhysicsPointQueryParameters3D.new();side.position=Vector3(3.95,1.4,-1);side.collision_mask=1
	check(demo.get_world_3d().direct_space_state.intersect_point(side).size()==1,"one collider at corner wall, no duplicated arm")
	key()
	for frame in 90:
		await physics_frame
		if demo.door.is_open():break
	check(demo.door.is_open(),"real E input event opens showcase door")
	key()
	for frame in 90:
		await physics_frame
		if demo.door.is_closed():break
	check(demo.door.is_closed(),"real E input event closes showcase door")
	demo.queue_free();await process_frame;await process_frame
	load("res://scripts/city/m1_materials.gd")._cache.clear()
	print("M1_SHOWCASE ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
