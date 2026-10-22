extends RefCounted
## Export vlasů z karet (C4b) pro vizuální kontrolu v Blenderu.
## Pro každou postavu postaví SimVisual (stejná cesta jako ve hře), přečte z něj SKUTEČNÉ váhy blend shapes
## hlavy, očí, těla i vlasů a geometrii karet deformuje na CPU (režim NORMALIZED: p = base + Σ w·(target − base)),
## v klidové póze – stejně jako Blender, který importuje character.glb a nastaví shape keys.
## Výstup: res://previews/hair_export/<name>.json – {"rows": [...]} se základním vzhledem (váhy, barvy) a díly
## vlasů jako base64 binárních polí (float32 pozice ×3, float32 UV ×2, float32 CUSTOM0 ×4, int32 indexy).
## Blender skript (docs/asset-pipeline.md) z CUSTOM0 a UV složí průhlednost pramenů podobně jako hair.gdshader.

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")


## Řádky kontrolního archu: různé účesy, barvy, šediny, ústup linie, vousy, obočí a tvary hlavy.
static func rows() -> Array:
	return [
		{"label": "kratke", "hair": {"style": "kratke", "melanin": 0.75, "red": 0.1, "brows": "prirozene"}},
		{"label": "dlouhe_vlnite", "skin": {"tone": 0.2}, "hair": {"style": "dlouhe_vlnite", "melanin": 0.35, "red": 0.6, "brows": "tenke"}},
		{"label": "afro", "skin": {"tone": 0.85, "undertone": 0.3}, "hair": {"style": "afro", "melanin": 0.95, "red": 0.05, "brows": "huste"}},
		{"label": "copanky", "skin": {"tone": 0.75}, "hair": {"style": "copanky", "melanin": 0.9, "red": 0.1, "brows": "oblouk"}},
		{"label": "drdol_sediny", "body": {"age": 64}, "hair": {"style": "drdol", "melanin": 0.6, "red": 0.15, "grey": 0.75, "brows": "rovne"}},
		{"label": "undercut_plnovous", "skin": {"tone": 0.55}, "face": {"jaw_width": 0.6, "head_width": 0.5},
			"hair": {"style": "undercut", "melanin": 0.8, "red": 0.2, "facial": "plnovous", "facial_density": 0.85, "brows": "huste"}},
		{"label": "ustup_sediny_bradka", "body": {"age": 58, "neck_length": -0.8},
			"hair": {"style": "strih_nakratko", "melanin": 0.55, "grey": 0.85, "hairline": 0.7, "facial": "bradka", "brows": "srostle"}},
		{"label": "dredy_knir", "skin": {"tone": 0.65}, "face": {"head_height": 0.6},
			"hair": {"style": "dredy", "melanin": 0.85, "red": 0.1, "facial": "knir", "brows": "prirozene"}},
	]


static func _snap(row: Dictionary) -> Dictionary:
	var s := {"identity": {"first_name": "Test", "grammar": "n"}}
	for g in ["skin", "hair", "body", "face"]:
		if row.has(g):
			s[g] = (row[g] as Dictionary).duplicate()
	return s


static func _hex(c: Color) -> String:
	return c.to_html(false)


static func _pack(m: ArrayMesh, mi: MeshInstance3D) -> Dictionary:
	var a: Array = m.surface_get_arrays(0)
	var pos: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var bl: Array = m.surface_get_blend_shape_arrays(0)
	var base: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for k in m.get_blend_shape_count():
		var w := mi.get_blend_shape_value(k)
		if absf(w) < 1e-6:
			continue
		var tv: PackedVector3Array = (bl[k] as Array)[Mesh.ARRAY_VERTEX]
		for i in pos.size():
			pos[i] += (tv[i] - base[i]) * w
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var fp := PackedFloat32Array()
	fp.resize(pos.size() * 3)
	for i in pos.size():
		fp[i * 3] = pos[i].x
		fp[i * 3 + 1] = pos[i].y
		fp[i * 3 + 2] = pos[i].z
	var fu := PackedFloat32Array()
	fu.resize(uv.size() * 2)
	for i in uv.size():
		fu[i * 2] = uv[i].x
		fu[i * 2 + 1] = uv[i].y
	return {"n": pos.size(), "m": idx.size(),
		"pos": Marshalls.raw_to_base64(fp.to_byte_array()), "uv": Marshalls.raw_to_base64(fu.to_byte_array()),
		"c0": Marshalls.raw_to_base64(c0.to_byte_array()), "idx": Marshalls.raw_to_base64(idx.to_byte_array())}


## Vytvoří export; parent = uzel ve stromu (SimVisual potřebuje _ready). Vrací souhrn.
static func make(parent: Node, name: String) -> Dictionary:
	var out_rows := []
	var tris := 0
	for row in rows():
		var v := SimVisual.new()
		v.apply_look(_snap(row))
		parent.add_child(v)
		var lp: Dictionary = v.look_params
		var keys := {}
		for mi in v._model.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			if m == null or not mi.visible:
				continue
			for k in m.get_blend_shape_count():
				var nm := String(m.get_blend_shape_name(k))
				var w: float = mi.get_blend_shape_value(k)
				if String(mi.name).begins_with("hair_cards_"):
					continue
				if absf(w) > 1e-6:
					keys[nm] = w
		var parts := []
		for part in SimVisual.HAIR_PARTS:
			var mi: MeshInstance3D = v.hair_part(part)
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var pk := _pack(mi.mesh as ArrayMesh, mi)
			pk["part"] = part
			var mat := v.hair_material(part)
			pk["color"] = mat.get_shader_parameter("hair_color")
			pk["grey"] = mat.get_shader_parameter("grey")
			pk["hairline"] = mat.get_shader_parameter("hairline")
			pk["density"] = mat.get_shader_parameter("density")
			pk["fine"] = mat.get_shader_parameter("fine")
			var cv: Vector3 = pk["color"]
			pk["color"] = [cv.x, cv.y, cv.z]
			tris += int(pk["m"]) / 3
			parts.append(pk)
		out_rows.append({"label": row["label"], "keys": keys, "skin": _hex(lp["skin"]), "lips": _hex(lp["lips"]),
			"iris": _hex(lp["iris"]), "top": _hex(lp["top"]), "bottom": _hex(lp["bottom"]),
			"brow_hex": _hex((lp["hair_look"] as Dictionary)["brow"]), "parts": parts})
		v.free()
	DirAccess.make_dir_recursive_absolute("res://previews/hair_export")
	var txt := JSON.stringify({"rows": out_rows})
	var f := FileAccess.open("res://previews/hair_export/%s.json" % name, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	return {"rows": out_rows.size(), "tris": tris, "chars": txt.length(), "md5": txt.md5_text()}
