extends Node
## Vizuální kontrola C-LOD krok 5 (17. 11. 2026) BEZ GPU: obočí a vousy – plná síť vs. LOD1.
## Softwarový rasterizér RasterPreview (z-buffer, Gouraud; tvar, hustota a silueta, ne PBR). Hlava z character.glb
## (výchozí vzhled, bez vlasů skalpu), obočí a vousy = skutečné sítě HairRig v klidové poloze. Karty se filtrují
## stejně jako v shaderu obličejových chlupů (viditelné jen c0.x ≤ hustota), takže je vidět i účinek přeškálování.
## Řádky = styly × hustota, sloupce = plná zepředu | LOD1 zepředu | plná ¾ | LOD1 ¾.
## Výstup: res://previews/facial-lod1/cpu_sheet.png (dlaždice 300 px) a cpu_sheet_small.jpg (150 px).
## Spuštění: godot --headless --path . res://tools/render_facial_lod1_cpu.tscn -- --lease=<main lease>

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const RasterPreview := preload("res://tools/raster_preview.gd")
const OUT := "res://previews/facial-lod1/"
## [obočí, vousy, hustota obočí i vousů]
const ROWS := [["huste", "plnovous", 0.6], ["tenke", "bradka", 0.3], ["srostle", "licousy", 1.0], ["oblouk", "knir", 0.6]]
const VIEWS := [Vector2(0, 0), Vector2(35, 0)]
const BROW_COL := Color(0.22, 0.15, 0.09)
const BEARD_COL := Color(0.30, 0.20, 0.12)
const CENTER := Vector3(0.0, 1.6, 0.0)
const EXTENT := 0.13


func _ready() -> void:
	var lease := ""
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
	var t0 := Time.get_ticks_msec()
	var base_parts := RasterPreview.deformed_parts({}, "__bez_vlasu__", false)
	var big := _sheet(base_parts, 300)
	big.save_png(OUT + "cpu_sheet.png")
	var small := _sheet(base_parts, 150)
	small.save_jpg(OUT + "cpu_sheet_small.jpg", 0.75)
	print("RENDER saved ", OUT, " ms ", Time.get_ticks_msec() - t0, " small_bytes ",
		FileAccess.get_file_as_bytes(OUT + "cpu_sheet_small.jpg").size())
	print("RENDER DONE")
	get_tree().quit(0)


func _lod_or_full(part: String, style: String) -> ArrayMesh:
	var m := HairRig.facial_lod1_mesh(part, style)
	return m if m != null else HairRig.mesh_for(part, style)


## Díl pro rasterizér: jen karty viditelné při dané hustotě (pravidlo shaderu pro fine = 0).
func _part(m: ArrayMesh, dens: float, col: Color, nm: String) -> Dictionary:
	if m == null:
		return {}
	var a := m.surface_get_arrays(0)
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var vis := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if c0[idx[t] * 4] <= dens:
			vis.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	return {"p": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "idx": vis, "col": col, "name": nm}


func _sheet(base_parts: Array, tile: int) -> Image:
	var img := Image.create(tile * VIEWS.size() * 2, tile * ROWS.size(), false, Image.FORMAT_RGB8)
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var dens := float(row[2])
		var sets := [
			[HairRig.mesh_for("brows", row[0]), HairRig.mesh_for("beard", row[1])],
			# bez LOD1 (malá síť, skip) ukazuje stupeň 1 plnou síť – stejně jako SimVisual
			[_lod_or_full("brows", row[0]), _lod_or_full("beard", row[1])],
		]
		for vi in VIEWS.size():
			for li in 2:
				var parts := base_parts.duplicate()
				var pb := _part(sets[li][0], dens, BROW_COL, "brows")
				var pd := _part(sets[li][1], dens, BEARD_COL, "beard")
				if not pb.is_empty():
					parts.append(pb)
				if not pd.is_empty():
					parts.append(pd)
				var v: Vector2 = VIEWS[vi]
				var t := RasterPreview.render(parts, tile, v.x, v.y, CENTER, EXTENT)
				img.blit_rect(t, Rect2i(0, 0, tile, tile), Vector2i((vi * 2 + li) * tile, r * tile))
	return img
