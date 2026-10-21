extends RefCounted
## Detail nosu a rtů pro vizuální kontrolu (běh 11, nálezy 5–6 z Blender renderu C3): výchozí obličej,
## extrém (všechna pole +1) a 3 náhodné obličeje (seed 1–3) × 4 pohledy. Výstup JPG v base64 v res://previews/.

const RasterPreview := preload("res://tools/raster_preview.gd")
const NeckSheet := preload("res://tools/neck_sheet.gd")
const CharacterRandomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


static func make(name: String, tile := 220) -> Dictionary:
	var all: Array = NeckSheet.snaps()
	var rows: Array = [all[0], all[3]]
	for s in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var c = CharacterData.create()
		c.set_from_dict(CharacterRandomizer.generate(rng))
		rows.append(c.public_snapshot())
	var views := [Vector2(0, 0), Vector2(35, 0), Vector2(70, 0), Vector2(25, -25)]
	var img: Image = RasterPreview.sheet(rows, views, tile, Vector3(0.0, 1.625, 0.03), 0.06, false)
	var buf := img.save_jpg_to_buffer(0.88)
	var f := FileAccess.open("res://previews/%s.b64" % name, FileAccess.WRITE)
	f.store_string(Marshalls.raw_to_base64(buf))
	f.close()
	return {"bytes": buf.size(), "w": img.get_width(), "h": img.get_height()}
