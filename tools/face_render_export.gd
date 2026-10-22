extends RefCounted
## Postavy pro vizuální kontrolu obličeje v Blenderu (běh 18, C3+ B; běh 21 C3++ mimika a detaily).
## Zapíše JSON ve formátu Blender knihovny tools/blender/face_render.py (docs/asset-pipeline.md, „Blender render“):
## pro každou postavu váhy blend shapes těla a obličeje z AppearanceResolveru (stejné jako ve hře) a barvy kůže,
## rtů, duhovky, limbu, řas, zubů, dásně, jazyka a oblečení (hex bez #). Vlasy se vynechávají (hair_variant ""),
## aby byly vidět oči, čelo a spánky.
##
## Sada snaps() (pevná, deterministická): výchozí, 4 náhodné (seed 1–4), extrém +1 / −1 všech morfů obličeje,
## asymetrie, „velké oči a plné rty“, „malé oči a tenké rty“, tuk 0,9, svaly 0,9.
## Sada expression_rows() (běh 21): mimika (FaceMorphs.expression_weights – stejné váhy jako SimVisual) a krajní
## hodnoty detailů (řasy, zuby).

const CharacterData := preload("res://scripts/character/character_data.gd")
const CharacterRandomizer := preload("res://scripts/character/character_randomizer.gd")
const AppearanceResolver := preload("res://scripts/character/appearance_resolver.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const FaceMorphs := preload("res://scripts/character/face_morphs.gd")


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


## Mimika a detaily (běh 21): [název, snapshot, výraz pro FaceMorphs.expression_weights].
static func expression_rows() -> Array:
	var base := _with(func(_d): pass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var c = CharacterData.create()
	c.set_from_dict(CharacterRandomizer.generate(rng))
	var rnd: Dictionary = c.public_snapshot()
	var details_max := _with(func(d):
		for k in Schema.FACE_DETAILS:
			d["face"][k] = 1.0)
	var details_min := _with(func(d):
		for k in Schema.FACE_DETAILS:
			d["face"][k] = 0.0)
	return [
		["neutralni", base, {}],
		["usmev", base, {"ex_smile": 1.0, "ex_jaw_open": 0.25}],
		["mrknuti_L_obocí", base, {"ex_blink_l": 1.0, "ex_brow_up": 0.8}],
		["pul_mrknuti", base, {"ex_blink_l": 0.5, "ex_blink_r": 0.5}],
		["usta_otevrena", base, {"ex_jaw_open": 1.0, "ex_pupil": 1.0}],
		["zamraceni", rnd, {"ex_frown": 1.0, "ex_pupil": -1.0}],
		["detaily_max_usmev", details_max, {"ex_smile": 0.8, "ex_jaw_open": 0.45}],
		["detaily_min_usmev", details_min, {"ex_smile": 0.8, "ex_jaw_open": 0.45}],
	]


static func _row(name: String, snap: Dictionary, ex: Dictionary) -> Dictionary:
	var r: Dictionary = AppearanceResolver.resolve(snap)
	var face: Dictionary = (r["face"] as Dictionary).duplicate()
	if not ex.is_empty():
		face.merge(FaceMorphs.expression_weights(ex), true)
	var row := {
		"name": name,
		"body": r["body"],
		"face": face,
		"hair_variant": "",
	}
	for k in ["skin", "lips", "iris", "hair", "top", "bottom", "teeth", "gum", "tongue", "lash", "limbus"]:
		if r.has(k) and typeof(r[k]) == TYPE_COLOR:
			row[k] = _hex(r[k])
	return row


static func _store(name: String, rows: Array, names: Array) -> Dictionary:
	var path := "res://previews/%s.json" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	return {"count": rows.size(), "names": names, "md5": FileAccess.get_md5(path)}


## Zapíše res://previews/<name>.json a vrátí {"count", "names", "md5"}.
static func write(name := "c3b_faces") -> Dictionary:
	var rows: Array = []
	var names: Array = []
	for pair in snaps():
		rows.append(_row(pair[0], pair[1], {}))
		names.append(pair[0])
	return _store(name, rows, names)


## Mimika a detaily (běh 21) → res://previews/<name>.json.
static func write_expressions(name := "c3pp_expr") -> Dictionary:
	var rows: Array = []
	var names: Array = []
	for t in expression_rows():
		rows.append(_row(t[0], t[1], t[2]))
		names.append(t[0])
	return _store(name, rows, names)
