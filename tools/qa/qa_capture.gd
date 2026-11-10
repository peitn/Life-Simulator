extends SceneTree
## QA 11/2026: vizuální průchod hrou. Spustí skutečnou scénu hry (offline, osmičlenná domácnost),
## počká na asynchronní vlasy a šatník a uloží snímky: celkový pohled, HUD, každá postava zblízka,
## každý animační klip ve dvou fázích, tvorba postavy, nastavení. Jen čte – nic neukládá do hry.
## Spuštění (vyžaduje zobrazovací server, např. Xvfb):
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s res://tools/qa/qa_capture.gd -- <výstupní adresář> [stage]
const Main := preload("res://main.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")

var out_dir := ""
var world: Node3D
var shots := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <output dir> [all|world|anims|ui]")
		quit(2)
		return
	out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred(args[1] if args.size() > 1 else "all")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("%02d_%s.png" % [shots, tag])
	shots += 1
	print("SHOT %s %d (%dx%d)" % [path, img.save_png(path), img.get_width(), img.get_height()])


func _cam(target: Vector3, dist: float, yaw_deg: float, pitch_deg: float) -> void:
	var rig = world.camera_rig
	rig.position = Vector3(target.x, target.y, target.z)
	rig.yaw = deg_to_rad(yaw_deg)
	rig.pitch = deg_to_rad(pitch_deg)
	rig.distance = dist
	rig._target_distance = dist
	rig._apply()


func _run(stage: String) -> void:
	root.size = Vector2i(1280, 720)
	world = Main.new()
	world.net_config = {"mode": "offline", "eight_member_household": true, "autosave": false,
		"autoload": false, "audio": true, "save_directory": "user://qa_capture_saves"}
	root.add_child(world)
	await _frames(5)
	print("QA sims=%d objects=%d" % [world.sims.size(), world.smart_objects.size()])
	await _shot("start_first_run_warning")
	# Upozornění jen skrýt (bez zápisu do nastavení hráče).
	if world.settings_menu != null and world.settings_menu._warning != null:
		world.settings_menu._warning.visible = false
	await _shot("start_default_camera")
	# Čekání na async vlasy a šatník (herní cesta).
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		var waiting := false
		for s in world.sims:
			if s.visual != null and (s.visual.hair_waiting() or s.visual.wardrobe_waiting()):
				waiting = true
		if not waiting:
			break
		await _frames(5)
	print("QA assets ready after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	world.clock.running = true
	await _frames(30)
	if stage in ["all", "world"]:
		var mid := Vector3.ZERO
		for s in world.sims:
			mid += s.global_position
			print("QA sim %s at %s rot %.2f" % [s.sim_name, str(s.global_position), s.rotation.y])
		mid /= float(maxi(1, world.sims.size()))
		mid.y = 0.0
		_cam(mid, 24.0, 35.0, -45.0)
		await _shot("overview")
		_cam(mid, 24.0, 215.0, -45.0)
		await _shot("overview_back")
		_cam(mid, 34.0, 0.0, -88.0)
		await _shot("overview_top")
		for i in world.sims.size():
			var s = world.sims[i]
			world.clock.running = false
			_cam(s.global_position + Vector3(0, 0.9, 0), 4.2, rad_to_deg(s.rotation.y), -28.0)
			await _shot("sim%d_front" % i)
			_cam(s.global_position + Vector3(0, 1.5, 0), 1.3, rad_to_deg(s.rotation.y) + 20.0, -12.0)
			await _shot("sim%d_face" % i)
		world.clock.running = true
		# Hodina hry při vyšší rychlosti: postavy něco dělají.
		for k in 4:
			world.clock.advance(15.0)
			await _frames(40)
		_cam(mid, 24.0, 35.0, -45.0)
		await _shot("overview_after_hour")
	if stage in ["all", "anims"]:
		world.clock.running = false
		var s0 = world.sims[0]
		var v = s0.visual
		s0.set_process(false)
		s0.set_physics_process(false)
		s0.global_position = Vector3(0, 0, 9.0)
		s0.rotation.y = 0.0
		if world.hud != null:
			world.hud.visible = false
		for clip in ["idle", "walk", "sit", "lie", "read", "cook", "text", "eat"]:
			var posture := "stand"
			var action := ""
			match clip:
				"sit": posture = "sit"
				"lie": posture = "lie"
				"read": action = "read"
				"cook": action = "cook"
				"text": action = "text_friend"
				"eat": action = "snack"
			v.apply(posture, 10.0, "spokojeny", "QA", clip, "", false, action)
			if v._anim != null:
				v._anim.play(clip, 0.0)
			for ph in [0.25, 0.75]:
				if v._anim != null:
					v._anim.seek(ph * v._anim.current_animation_length, true)
					v._anim.speed_scale = 0.0
				for ang in [0.0, 90.0]:
					_cam(s0.global_position + Vector3(0, 0.8, 0), 3.2, ang, -10.0)
					await _shot("anim_%s_%02d_yaw%d" % [clip, int(ph * 100), int(ang)])
		s0.set_process(true)
		s0.set_physics_process(true)
		if world.hud != null:
			world.hud.visible = true
	if stage in ["all", "ui"]:
		world.clock.running = false
		_cam(Vector3(0, 0, 0), 22.0, 35.0, -42.0)
		world.selected = 0
		await _shot("hud_selected")
		if world.settings_menu != null:
			world.settings_menu.toggle()
			await _shot("settings_menu")
			world.settings_menu.toggle()
		if world.hud != null and world.hud.has_method("_on_create_character"):
			world.hud._on_create_character()
			await _frames(20)
			await _shot("character_creator")
		root.size = Vector2i(420, 860)
		await _frames(10)
		await _shot("narrow_420")
	print("QA shots=%d" % shots)
	world.queue_free()
	await _frames(3)
	quit(0)
