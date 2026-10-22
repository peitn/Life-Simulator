extends RefCounted
## Postavy pro vizuální kontrolu obličeje v Blenderu (běh 18, C3+ B). Zapíše JSON ve formátu Blender
## knihovny render_lib.py (docs/asset-pipeline.md, „Blender render“): pro každou postavu váhy blend shapes
## těla a obličeje z AppearanceResolveru (stejné jako ve hře) a barvy kůže, rtů, duhovky a oblečení (hex bez #).
## Vlasy se vynechávají (hair_variant ""), aby byly vidět oči, čelo a spánky.
##
## Sada (pevná, deterministická): výchozí, 4 náhodné (seed 1–4), extrém +1 / −1 všech morfů obličeje,
## asymetrie, „velké oči a plné rty“, „malé oči a tenké rty“, tuk 0,9, svaly 0,9.

const CharacterData := preload("res://scripts/character/character_data.gd")
const CharacterRandomizer := preload("res://scripts/character/character_randomizer.gd")
const AppearanceResolver := preload("res://scripts/character/appearance_resolver.gd")
const Schema := preload("res://scripts/character/character_schema.gd")


static func _hex(c: Color) -> String:
	return c.to_html(false)


static func _with(mod: Callable) -> Dictionary:
	var c = CharacterData.create()
	var d: Dictionary = c.to_dict()
	mod.call(d)
	c.set_from_dict(d)
	return c.public_snapshot()


static func snaps() -> Array:
	var out: Array = []
	out.append(["vychozi", _with(func(_d): pass)])
	for s in [1, 2, 3, 4]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var c = CharacterData.create()
		c.set_from_dict(CharacterRandomizer.generate(rng))
		out.append(["nahodna_%d" % s, c.public_snapshot()])
	out.append(["extrem_max", _with(func(d):
		for k in Schema.FACE_MORPHS:
			d["face"][k] = 1.0)])
	out.append(["extrem_min", _with(func(d):
		for k in Schema.FACE_MORPHS:
			d["face"][k] = -1.0)])
	out.append(["asymetrie", _with(func(d):
		for k in Schema.FACE_ASYMMETRY:
			d["face"][k] = 1.0)])
	out.append(["oci_rty_plus", _with(func(d):
		d["face"]["eye_size"] = 1.0
		d["face"]["lip_upper"] = 1.0
		d["face"]["lip_lower"] = 1.0
		d["face"]["mouth_width"] = 0.5)])
	out.append(["oci_rty_minus", _with(func(d):
		d["face"]["eye_size"] = -1.0
		d["face"]["lip_upper"] = -1.0
		d["face"]["lip_lower"] = -1.0
		d["face"]["eye_depth"] = 1.0)])
	out.append(["tuk", _with(func(d): d["body"]["body_fat"] = 0.9)])
	out.append(["svaly", _with(func(d):
		d["body"]["muscle"] = 0.9
		d["body"]["frame"] = 0.8)])
	return out


## Zapíše res://previews/<name>.json a vrátí {"count", "names", "md5"}.
static func write(name := "c3b_faces") -> Dictionary:
	var rows: Array = []
	var names: Array = []
	for pair in snaps():
		var r: Dictionary = AppearanceResolver.resolve(pair[1])
		rows.append({
			"name": pair[0],
			"body": r["body"],
			"face": r["face"],
			"skin": _hex(r["skin"]), "lips": _hex(r["lips"]), "iris": _hex(r["iris"]),
			"hair": _hex(r["hair"]), "top": _hex(r["top"]), "bottom": _hex(r["bottom"]),
			"hair_variant": "",
		})
		names.append(pair[0])
	var path := "res://previews/%s.json" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	return {"count": rows.size(), "names": names, "md5": FileAccess.get_md5(path)}
