extends Node
## Vizuální kontrola C-LOD krok 2 (13. 11. 2026): proxy účesu pro dav → res://previews/hair-proxy/.
## Pro čtyři objemné účesy vedle sebe: stupeň 0 (karty), stupeň 2 s proxy (nové) a stupeň 2 se společnou
## helmou z GLB (dosavadní stav; jen pro srovnání – proxy se v nástroji ručně vypne).
## front.jpg (¾ zepředu), back.jpg (zezadu), crowd.jpg (skutečná vzdálenost stupně 2, výřez zvětšený 4×).
## Spuštění: xvfb-run godot --rendering-driver opengl3 --path . res://tools/render_hair_proxy.tscn -- --lease=<main lease>
## Zapisuje jen s platným main lease (protokol v3).

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const OUT := "res://previews/hair-proxy/"
const STYLES := ["dlouhe_vlnite", "afro", "culik", "copanky"]
const TONES := [0.3, 0.8, 0.55, 0.65]
const HAIR := [Color(0.32, 0.2, 0.11), Color(0.07, 0.05, 0.04), Color(0.62, 0.45, 0.25), Color(0.1, 0.07, 0.05)]

var lease := ""
var vs: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lease="):
			lease = a.trim_prefix("--lease=")
	var G = load("res://tools/automation_lock.gd")
	if not lease.begins_with("main-") or not G.owns(lease):
		print("RENDER: chybí platný main lease")
		get_tree().quit(2)
		return
	HairRig.async_build = false
	DirAccess.make_dir_recursive_absolute(OUT)
	get_window().size = Vector2i(1800, 760)
	var root := Node3D.new()
	add_child(root)
	_env(root)
	for si in STYLES.size():
		for k in 3:
			var v = SimVisual.new()
			root.add_child(v)
			v.position = Vector3((si * 3 + k - 5.5) * 0.46 + si * 0.25 - 0.375, 0, 0)
			v.lod_override = 0 if k == 0 else 2
			vs.append(v)
	await get_tree().process_frame
	for i in vs.size():
		var si: int = i / 3
		vs[i].apply_look({"hair": {"style": STYLES[si], "beard_style": "zadne", "color": HAIR[si].to_html(false)},
			"skin": {"tone": TONES[si]}})
		vs[i].expressions_enabled = false
	await get_tree().process_frame
	for i in vs.size():
		if i % 3 == 2:
			# dosavadní stav: bez proxy → helma z GLB
			vs[i]._hair_proxy_ready = false
			vs[i]._apply_lod_visibility()
		var lab := Label3D.new()
		lab.text = "%s\n%s" % [STYLES[i / 3], ["karty (stupeň 0)", "PROXY (stupeň 2)", "helma (dříve)"][i % 3]]
		lab.font_size = 30
		lab.pixel_size = 0.0011
		lab.position = Vector3(vs[i].position.x, 2.02, 0.1)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(lab)
	var cam := Camera3D.new()
	cam.fov = 24.0
	root.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(-1.6, 1.62, 13.5), Vector3(0, 1.45, 0))
	await _shot("front.jpg")
	cam.look_at_from_position(Vector3(1.0, 1.62, -13.5), Vector3(0, 1.45, 0))
	await _shot("back.jpg")
	# skutečná vzdálenost davu: jen proxy vs. karty jednoho účesu, výřez zvětšený (nejbližší soused)
	for i in vs.size():
		vs[i].visible = (i / 3) == 0 and i % 3 < 2
	cam.fov = 50.0
	var x0: float = (vs[0].position.x + vs[1].position.x) * 0.5
	cam.look_at_from_position(Vector3(x0, 1.6, 30.0), Vector3(x0, 1.0, 0))
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c := img.get_size() / 2
	var crop := img.get_region(Rect2i(c.x - 110, c.y - 120, 220, 160))
	crop.resize(880, 640, Image.INTERPOLATE_NEAREST)
	crop.save_jpg(OUT + "crowd.jpg", 0.9)
	print("RENDER saved ", OUT + "crowd.jpg")
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
