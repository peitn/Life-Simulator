extends Node
## Vizuální kontrola C-LOD (12. 11. 2026): dva snímky do res://previews/crowd-lod/.
## 1) lod_levels.jpg – obličejová síť (s očima, rty, ústy, řasami) v LOD0 a ve třech LOD z CharacterLod vedle
##    sebe, se zvýrazněnými hranami; hledají se škvíry na švech a rozpad tvaru.
## 2) tiers.jpg – tatáž postava ve stupni 0 (karty vlasů, vousy) a ve stupni 2 (helma z GLB) zblízka, ať je
##    vidět, co se v davu vyměňuje.
## Spuštění: xvfb-run godot --rendering-driver opengl3 --path . res://tools/render_crowd_lod.tscn -- --lease=<main lease>
## Zapisuje jen s platným main lease (protokol v3).

const AL := preload("res://scripts/assets/asset_library.gd")
const CL := preload("res://scripts/assets/character_lod.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const OUT := "res://previews/crowd-lod/"

var lease := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lease="):
			lease = a.trim_prefix("--lease=")
	var G = load("res://tools/automation_lock.gd")
	if not lease.begins_with("main-") or not G.owns(lease):
		print("RENDER: chybí platný main lease")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	await _render_levels()
	await _render_tiers()
	print("RENDER DONE")
	get_tree().quit(0)


func _env(parent: Node, bg: Color) -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
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


## Síť z indexů jedné LOD (pro snímek), bez skinu a blend shapes.
func _level_mesh(src: ArrayMesh, idx: PackedInt32Array) -> ArrayMesh:
	var a := src.surface_get_arrays(0)
	var b := []
	b.resize(Mesh.ARRAY_MAX)
	b[Mesh.ARRAY_VERTEX] = a[Mesh.ARRAY_VERTEX]
	b[Mesh.ARRAY_NORMAL] = a[Mesh.ARRAY_NORMAL]
	b[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
	return m


func _edges_mesh(src: ArrayMesh, idx: PackedInt32Array) -> ArrayMesh:
	var p: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var seen := {}
	var lines := PackedVector3Array()
	for t in range(0, idx.size() - 2, 3):
		for e in 3:
			var i0 := idx[t + e]
			var i1 := idx[t + (e + 1) % 3]
			var k := Vector2i(mini(i0, i1), maxi(i0, i1))
			if seen.has(k):
				continue
			seen[k] = true
			lines.append(p[i0] + n[i0] * 0.0004)
			lines.append(p[i1] + n[i1] * 0.0004)
	var b := []
	b.resize(Mesh.ARRAY_MAX)
	b[Mesh.ARRAY_VERTEX] = lines
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, b)
	return m


func _lod_indices(m: ArrayMesh) -> Array:
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), 0)
	var main: PackedByteArray = sd["index_data"]
	var elem := main.size() / maxi(int(sd["index_count"]), 1)
	var out: Array = [m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]]
	for lod in sd.get("lods", []):
		var bytes: PackedByteArray = lod["index_data"]
		var idx := PackedInt32Array()
		idx.resize(bytes.size() / elem)
		for i in idx.size():
			idx[i] = bytes.decode_u16(i * 2) if elem == 2 else bytes.decode_u32(i * 4)
		out.append(idx)
	return out


func _render_levels() -> void:
	get_window().size = Vector2i(1800, 620)
	var root := Node3D.new()
	add_child(root)
	_env(root, Color(0.11, 0.115, 0.13))
	var model: Node3D = AL.instantiate("character")
	var face_mesh: ArrayMesh = null
	var others: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm == "head__face__skin_body":
			face_mesh = mi.mesh
		elif nm.begins_with("head__") or nm.begins_with("eyes__"):
			others.append(mi.mesh)
	var levels := _lod_indices(face_mesh)
	var show := [0, 1, 2, 3]
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.6, 0.5)
	skin.roughness = 0.6
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.1, 0.1, 0.12)
	var other_mat := StandardMaterial3D.new()
	other_mat.albedo_color = Color(0.85, 0.82, 0.8)
	for k in show.size():
		var li: int = show[k]
		if li >= levels.size():
			continue
		var holder := Node3D.new()
		holder.position = Vector3((k - 1.5) * 0.30, 0, 0)
		root.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = _level_mesh(face_mesh, levels[li])
		mi.material_override = skin
		holder.add_child(mi)
		var ed := MeshInstance3D.new()
		ed.mesh = _edges_mesh(face_mesh, levels[li])
		ed.material_override = line_mat
		holder.add_child(ed)
		for om in others:
			var o := MeshInstance3D.new()
			o.mesh = om
			o.material_override = other_mat
			holder.add_child(o)
		var lab := Label3D.new()
		lab.text = "LOD%d · %d tr." % [li, (levels[li] as PackedInt32Array).size() / 3] if li > 0 else "plná síť · %d tr." % ((levels[0] as PackedInt32Array).size() / 3)
		lab.font_size = 42
		lab.pixel_size = 0.0006
		lab.position = Vector3(0, 1.43, 0.12)
		lab.modulate = Color(0.95, 0.9, 0.8)
		holder.add_child(lab)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.42
	cam.position = Vector3(0, 1.6, 1.2)
	cam.rotation_degrees = Vector3(0, 0, 0)
	root.add_child(cam)
	cam.make_current()
	# mírně z boku, ať je vidět profil nosu a šev krku
	root.rotation_degrees = Vector3(0, 0, 0)
	for c in root.get_children():
		if c is Node3D and c != cam and not (c is DirectionalLight3D):
			(c as Node3D).rotate_y(deg_to_rad(28))
	await _shot("lod_levels.jpg")
	model.free()
	root.queue_free()
	await get_tree().process_frame


func _render_tiers() -> void:
	get_window().size = Vector2i(1200, 760)
	var root := Node3D.new()
	add_child(root)
	_env(root, Color(0.16, 0.17, 0.19))
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.look_at_from_position(Vector3(0, 1.55, 2.0), Vector3(0, 1.5, 0))
	root.add_child(cam)
	cam.make_current()
	var looks := [{"hair": {"style": "dlouhe_vlnite", "beard_style": "zadne"}, "skin": {"tone": 0.35}},
		{"hair": {"style": "kratke_kudrny", "beard_style": "plnovous"}, "skin": {"tone": 0.75}}]
	var vs: Array = []
	for i in 4:
		var v = SimVisual.new()
		root.add_child(v)
		v.position = Vector3(-0.66 + i * 0.44, 0, 0)
		v.lod_override = 0 if i % 2 == 0 else 2
		vs.append(v)
	await get_tree().process_frame
	for i in 4:
		vs[i].apply_look(looks[i / 2])
		vs[i].expressions_enabled = false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		var waiting := false
		for v in vs:
			waiting = waiting or v.hair_waiting()
		if not waiting:
			break
		await get_tree().process_frame
	for i in 4:
		var lab := Label3D.new()
		lab.text = "stupeň %d" % vs[i].lod_tier()
		lab.font_size = 40
		lab.pixel_size = 0.0012
		lab.position = Vector3(vs[i].position.x, 1.98, 0.1)
		root.add_child(lab)
	await _shot("tiers.jpg")
	root.queue_free()
