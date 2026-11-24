extends Node
## Vizuální kontrola C-LOD krok 3 (13. 11. 2026): karty vlasů pro stupeň 1 → res://previews/hair-lod1/.
## Pro čtyři účesy vedle sebe stupeň 0 (plné karty) a stupeň 1 (LOD1 – proředěné karty, obrys, zjednodušená
## skořepina). close_front.jpg / close_back.jpg = zblízka (přísnější než hra – LOD1 se zblízka nikdy neukazuje),
## distance.jpg = skutečná vzdálenost uprostřed stupně 1 (podíl výšky obrazu ~0,12 při FOV 50°), výřez 3× zvětšený.
## Spuštění: xvfb-run godot --rendering-driver opengl3 --path . res://tools/render_hair_lod1.tscn -- --lease=<main lease>
## Zapisuje jen s platným main lease (protokol v3).
## C-LOD krok 4 (17. 11.): volitelně --styles=a,b,c,d (4 účesy) a --out=<podsložka previews/> – např. trubice:
## --styles=copanky,dredy,cornrows,kratke --out=hair-lod1-tubes

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
var OUT := "res://previews/hair-lod1/"
var STYLES := ["dlouhe_rovne", "kudrnate", "culik", "kratke"]
const TONES := [0.3, 0.75, 0.55, 0.45]
const HAIR := [Color(0.32, 0.2, 0.11), Color(0.08, 0.06, 0.05), Color(0.62, 0.45, 0.25), Color(0.18, 0.12, 0.08)]

var lease := ""
var vs: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lease="):
			lease = a.trim_prefix("--lease=")
		elif a.begins_with("--styles="):
			var st := a.trim_prefix("--styles=").split(",", false)
			if st.size() == 4:
				STYLES = Array(st)
		elif a.begins_with("--out=") and a.trim_prefix("--out=").is_valid_filename():
			OUT = "res://previews/" + a.trim_prefix("--out=") + "/"
	var G = load("res://tools/automation_lock.gd")
	if not lease.begins_with("main-") or not G.owns(lease):
		print("RENDER: chybí platný main lease")
		get_tree().quit(2)
		return
	HairRig.async_build = false
	DirAccess.make_dir_recursive_absolute(OUT)
	get_window().size = Vector2i(1600, 760)
	var root := Node3D.new()
	add_child(root)
	_env(root)
	for si in STYLES.size():
		for k in 2:
			var v = SimVisual.new()
			root.add_child(v)
			v.position = Vector3((si * 2 + k - 3.5) * 0.5 + (si - 1.5) * 0.3, 0, 0)
			v.lod_override = k
			vs.append(v)
	await get_tree().process_frame
	for i in vs.size():
		var si: int = i / 2
		vs[i].apply_look({"hair": {"style": STYLES[si], "beard_style": "zadne", "color": HAIR[si].to_html(false)},
			"skin": {"tone": TONES[si]}})
		vs[i].expressions_enabled = false
	await get_tree().process_frame
	for i in vs.size():
		var m: ArrayMesh = vs[i].scalp_lod_mesh()
		var tris: int = 0 if m == null else m.surface_get_array_index_len(0) / 3
		var lab := Label3D.new()
		lab.text = "%s\n%s\n%d tr." % [STYLES[i / 2], ["plné karty (st. 0)", "LOD1 (st. 1)"][i % 2], tris]
		lab.font_size = 28
		lab.pixel_size = 0.0011
		lab.position = Vector3(vs[i].position.x, 2.05, 0.1)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(lab)
		print("RENDER ", STYLES[i / 2], " tier ", vs[i].lod_tier(), " scalp tris ", tris)
	var cam := Camera3D.new()
	cam.fov = 24.0
	root.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(-1.2, 1.62, 12.5), Vector3(0, 1.45, 0))
	await _shot("close_front.jpg")
	cam.look_at_from_position(Vector3(1.0, 1.62, -12.5), Vector3(0, 1.45, 0))
	await _shot("close_back.jpg")
	# skutečná vzdálenost stupně 1 (podíl ~0,12): jen první dvojice (dlouhé rovné) a druhá (kudrnaté)
	for i in vs.size():
		vs[i].visible = i < 4
	cam.fov = 50.0
	var x0: float = (vs[0].position.x + vs[3].position.x) * 0.5
	cam.look_at_from_position(Vector3(x0, 1.5, 16.0), Vector3(x0, 1.2, 0))
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c := img.get_size() / 2
	var crop := img.get_region(Rect2i(c.x - 200, c.y - 150, 400, 220))
	crop.resize(1200, 660, Image.INTERPOLATE_NEAREST)
	crop.save_jpg(OUT + "distance.jpg", 0.9)
	print("RENDER saved ", OUT + "distance.jpg")
	print("RENDER DONE")
	get_tree().quit(0)


func _env(parent: Node) -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.6
	we.environment = e
	parent.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 25, 0)
	key.light_energy = 1.3
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.45
	parent.add_child(fill)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(OUT + name, 0.88)
	print("RENDER saved ", OUT + name, " ", img.get_size())
