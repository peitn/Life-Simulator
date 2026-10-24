extends "res://tests/test_base.gd"
const P := preload("res://scripts/assets/subculture_wardrobe.gd")
const W := preload("res://scripts/assets/clothing_wardrobe.gd")
const S := preload("res://scripts/character/character_schema.gd")
const V := preload("res://scripts/character/character_validator.gd")
const R := preload("res://scripts/character/appearance_resolver.gd")
const D := preload("res://scripts/character/character_data.gd")

func _ready() -> void:
	section("C5.1 subcultures: actual authored garments")
	check(P.STYLES.size() == 9, "eight subcultures and cat hoodie variant")
	var all_ok := true
	var geometry_ok := true
	var variants := {}
	for style in P.names():
		var data := S.defaults()
		data["v"] = S.VERSION
		data["uid"] = D.new_uid()
		data["identity"]["first_name"] = "Test"
		data["personality"]["traits"] = ["hravy"]
		data = P.apply_to_character(data, style)
		var valid := V.validate(data)
		all_ok = all_ok and valid["ok"]
		var lp := R.resolve(valid["data"])
		var pieces := W.active_parts(lp)
		var found := {"top":false,"bottom":false,"shoes":false}
		for item in pieces:
			if found.has(item["category"]):
				found[item["category"]] = true
			var mesh: ArrayMesh = item["mesh"]
			geometry_ok = geometry_ok and mesh.get_blend_shape_count() == 10
			geometry_ok = geometry_ok and mesh.surface_get_array_len(0) > 0
		geometry_ok = geometry_ok and found.values().all(func(x): return x)
		variants[style] = pieces.size()
	check(all_ok, "all nine presets pass public character validator")
	check(geometry_ok, "all subculture pieces are actual skinned ten-morph meshes")
	check(variants["punk"] > 12 and variants["goth"] > 12, "punk studs and goth lacing are authored geometry")
	check(variants["harajuku"] >= 8 and variants["kawaii"] >= 7, "harajuku/kawaii have their own bow and skirt geometry")
	check(W.parts("bottom", "punk_kostka").size() >= 2, "punk skirt has separately modeled belt")
	check(W.parts("top", "emo_mikina").size() == 3, "emo hoodie has skinned long sleeves")
	check(W.parts("shoes", "goth_platformy").size() == 3, "goth boots have two skinned shafts")
	var base := S.defaults()
	var old := base.duplicate(true)
	var result := P.apply_to_character(base, "emo", "sport")
	check(result["clothing"]["sport"]["top"] == "emo_mikina" and result["clothing"]["active"] == "sport",
		"preset can be applied to any existing outfit slot")
	check(base == old, "preset does not mutate input")
	check(P.apply_to_character(base, "unknown") == base, "unknown presets are ignored")
	var kitty := W.parts("top", "kawaii_kocici_mikina")
	var names: Array = []
	for piece in kitty:
		names.append(String(piece["name"]))
	check(kitty.size() >= 18 and names.has("cat_ear_-1") and names.has("cat_ear_1"),
		"cat hoodie has two 3D ears, real hood and sleeves")
	check(names.has("cat_face") and names.has("cat_nose") and names.has("cat_eye_1"),
		"cat face, eyes, whiskers and nose are authored geometry")
	check(P.outfit("kawaii_kocka")["top_color"] == "#f5a6d0",
		"cat hoodie pastel-pink outfit tint")
	finish("test_subculture_wardrobe")
