extends Node
## Vizuální kontrola C-LOD krok 4 (17. 11. 2026) BEZ GPU: trubice copánků, dredů a cornrows – plné vs. LOD1.
## Na serveru už není xvfb-run (GPU render tools/render_hair_lod1 skončí 127), proto softwarový rasterizér
## RasterPreview (z-buffer, Gouraud; tvar a silueta, ne PBR). Hlava + tělo z character.glb (výchozí vzhled),
## vlasy = skutečné sítě HairRig (plné karty skalpu / LOD1) v klidové poloze.
## Řádky = účesy, sloupce = plné ¾ zepředu | LOD1 ¾ zepředu | plné ¾ zezadu | LOD1 ¾ zezadu.
## Výstup: res://previews/hair-lod1-tubes/cpu_sheet.png (dlaždice 320 px) a cpu_sheet_small.jpg (140 px, přenos).
## Spuštění: godot --headless --path . res://tools/render_hair_tubes_cpu.tscn -- --lease=<main lease>

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const RasterPreview := preload("res://tools/raster_preview.gd")
const OUT := "res://previews/hair-lod1-tubes/"
const STYLES := ["copanky", "dredy", "cornrows"]
const VIEWS := [Vector2(30, 5), Vector2(150, 5)]
const HAIR_COL := Color(0.36, 0.23, 0.13)
const CENTER := Vector3(0.0, 1.42, 0.0)
const EXTENT := 0.42


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
	var base_parts := RasterPreview.deformed_parts({}, "__bez_vlasu__", true)
	var big := _sheet(base_parts, 320)
	big.save_png(OUT + "cpu_sheet.png")
	var small := _sheet(base_parts, 140)
	small.save_jpg(OUT + "cpu_sheet_small.jpg", 0.72)
	print("RENDER saved ", OUT, " ms ", Time.get_ticks_msec() - t0, " small_bytes ",
		FileAccess.get_file_as_bytes(OUT + "cpu_sheet_small.jpg").size())
	print("RENDER DONE")
	get_tree().quit(0)


func _hair_part(m: ArrayMesh) -> Dictionary:
	var a := m.surface_get_arrays(0)
	return {"p": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "idx": a[Mesh.ARRAY_INDEX], "col": HAIR_COL, "name": "hair"}


func _sheet(base_parts: Array, tile: int) -> Image:
	var img := Image.create(tile * VIEWS.size() * 2, tile * STYLES.size(), false, Image.FORMAT_RGB8)
	for r in STYLES.size():
		var meshes := [HairRig.mesh_for("scalp", STYLES[r]), HairRig.lod1_mesh(STYLES[r])]
		for vi in VIEWS.size():
			for li in 2:
				var parts := base_parts.duplicate()
				if meshes[li] != null:
					parts.append(_hair_part(meshes[li]))
				var v: Vector2 = VIEWS[vi]
				var t := RasterPreview.render(parts, tile, v.x, v.y, CENTER, EXTENT)
				img.blit_rect(t, Rect2i(0, 0, tile, tile), Vector2i((vi * 2 + li) * tile, r * tile))
	return img
