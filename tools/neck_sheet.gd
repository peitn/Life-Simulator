extends RefCounted
## Kontaktní arch přechodu hlava–krk–tělo (C3+) pro vizuální kontrolu přes RasterPreview.
## Řádky: výchozí postava, max. tuk + svaly, hubená a široká ramena, extrém obličeje (všechna pole +1).
## Sloupce: zepředu, 35°, profil, zezadu, zespodu (pohled na podbradek).
## Výstup: JPG v base64 (res://previews/<name>.b64) – přenos k prohlídce mimo Godot.

const RasterPreview := preload("res://tools/raster_preview.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


static func snaps() -> Array:
	var out: Array = []
	var a = CharacterData.create()
	out.append(a.public_snapshot())
	var b = CharacterData.create()
	b.set_path_value("body.body_fat", 1.0)
	b.set_path_value("body.muscle", 1.0)
	b.set_path_value("body.frame", 1.0)
	out.append(b.public_snapshot())
	var c = CharacterData.create()
	c.set_path_value("body.body_fat", 0.0)
	c.set_path_value("body.muscle", 0.0)
	c.set_path_value("body.shoulders", 1.0)
	c.set_path_value("face.neck_width", -1.0)
	out.append(c.public_snapshot())
	var d = CharacterData.create()
	var face: Dictionary = d.to_dict().get("face", {})
	for k in face:
		if typeof(face[k]) == TYPE_FLOAT or typeof(face[k]) == TYPE_INT:
			d.set_path_value("face." + String(k), 1.0)
	out.append(d.public_snapshot())
	return out


static func make(name: String, tile := 240, center := Vector3(0.0, 1.54, 0.0), extent := 0.19, views: Array = [], rows: Array = []) -> Dictionary:
	if views.is_empty():
		views = [Vector2(0, 0), Vector2(35, 0), Vector2(90, 0), Vector2(180, 0), Vector2(20, -55)]
	var all := snaps()
	var sel: Array = all
	if not rows.is_empty():
		sel = []
		for r in rows:
			sel.append(all[r])
	var img: Image = RasterPreview.sheet(sel, views, tile, center, extent, true)
	var buf := img.save_jpg_to_buffer(0.88)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	var f := FileAccess.open("res://previews/%s.b64" % name, FileAccess.WRITE)
	f.store_string(Marshalls.raw_to_base64(buf))
	f.close()
	return {"bytes": buf.size(), "w": img.get_width(), "h": img.get_height()}
