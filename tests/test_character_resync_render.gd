extends SceneTree
## H2b: graphical client puppet capture after a real ENet public-look resync.
## Run under Xvfb, never --headless. Screenshots require the active main lease.
const Main = preload("res://main.gd")
const GameClockScript = preload("res://scripts/core/game_clock.gd")
const G = preload("res://tools/automation_lock.gd")
const Resolver = preload("res://scripts/character/appearance_resolver.gd")
var passed := 0
var failed := 0
var port := 0
var server: Node3D
var client: Node3D
var viewport: SubViewport

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	call_deferred("_run")

func _branch(parent: Node, name: String, cfg: Dictionary) -> Node3D:
	var holder := Node.new()
	holder.name = name
	parent.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	if cfg.get("mode", "") == "client":
		var clock := Node.new()
		clock.set_script(GameClockScript)
		clock.name = "Clock"
		holder.add_child(clock)
		cfg["clock"] = clock
	var world := Node3D.new()
	world.set_script(Main)
	world.name = "World"
	world.net_config = cfg
	holder.add_child(world)
	return world

func _wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--lease")
	var lease := String(args[idx + 1]) if idx >= 0 and idx + 1 < args.size() else ""
	if not G.owns(lease):
		print("RESYNC_RENDER_BLOCKED no lease")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("RESYNC_RENDER_FAIL headless cannot capture pixels")
		quit(3)
		return
	var settings = root.get_node("GameSettings")
	settings.persist = false
	settings.reset()
	settings.set_value("warning_ack", true, false)
	var clock = root.get_node("GameClock")
	clock.running = false
	randomize()
	port = 26700 + randi() % 400
	viewport = SubViewport.new()
	viewport.name = "ClientRenderViewport"
	viewport.size = Vector2i(1280, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.17, 0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	viewport.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.6
	viewport.add_child(sun)
	server = _branch(root, "ResyncServer", {"mode":"server", "port":port, "clock":clock,
		"audio":false, "hud":false, "camera":false, "visuals":false})
	client = _branch(viewport, "ResyncClient", {"mode":"client", "address":"127.0.0.1",
		"port":port, "name":"VisualProbe", "audio":false, "hud":false,
		"camera":false, "visuals":false})
	var connected := await _wait_for(func(): return client.net.my_sim != "", 8.0)
	check(connected, "real ENet client joined")
	if not connected:
		_finish()
		return
	var key: String = String(client.net.my_sim)
	var ready := await _wait_for(func(): return client.find_sim(key) != null, 6.0)
	check(ready, "real MultiplayerSpawner puppet exists")
	if not ready:
		_finish()
		return
	var puppet = client.find_sim(key)
	check(puppet.visual != null, "client puppet has live SimVisual")
	var before: float = float(puppet.look.get("body", {}).get("height_cm", 0.0))
	var new_height: float = 182.0 if before < 170.0 else 160.0
	check(before > 0.0 and absf(before - new_height) > 5.0, "distinct baseline and canonical target heights")
	var record = server._character_records.get(key)
	check(record != null, "server holds canonical CharacterData")
	if record == null:
		_finish()
		return
	record.body["height_cm"] = new_height
	server._character_revisions[key] = int(server._character_revisions[key]) + 1
	var revision: int = int(server._character_revisions[key])
	var token: String = String(puppet.get_meta("net_incarnation", ""))
	check(token.length() == 32, "spawn incarnation token present")
	server.net.character_edit_apply_rpc_enabled = true
	client.net.character_edit_apply_rpc_enabled = true
	client.net._request_public_look_resync(key, token)
	var synced := await _wait_for(func(): return int(client.net._public_look_revisions.get(key, 0)) == revision, 5.0)
	check(synced, "authenticated ENet resync reaches current revision")
	check(float(puppet.look.get("body", {}).get("height_cm", 0.0)) == new_height,
		"client puppet applies canonical height after resync")
	check(puppet.visual.look_params == Resolver.resolve(puppet.look),
		"live puppet SimVisual parameters equal resolved network appearance")
	check(not puppet.look.has("mind") and not puppet.look.has("story") and
		not puppet.look.get("personality", {}).has("trait_levels"),
		"resync carries public-only appearance")
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.fov = 43.0
	camera.global_position = puppet.global_position + Vector3(0, 1.55, 4.8)
	camera.look_at(puppet.global_position + Vector3(0, 1.25, 0), Vector3.UP)
	for size in [Vector2i(1280,900), Vector2i(360,800)]:
		if not G.owns(lease):
			print("RESYNC_RENDER_BLOCKED lease lost before screenshot")
			failed += 1
			break
		viewport.size = size
		DisplayServer.window_set_size(size)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var path := "res://previews/h2b-resync-client-%dx%d.png" % [size.x,size.y]
		var err := img.save_png(path)
		check(err == OK and img.get_width() == size.x and img.get_height() == size.y,
			"real client resync screenshot %dx%d" % [size.x,size.y])
		print("RESYNC_RENDER_CAPTURE ",path," size=",img.get_size()," error=",err)
	_finish()

func _finish() -> void:
	if client != null and is_instance_valid(client):
		client.net.shutdown()
	if server != null and is_instance_valid(server):
		server.net.shutdown()
	print("RESYNC_RENDER_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed == 0 else 1)
