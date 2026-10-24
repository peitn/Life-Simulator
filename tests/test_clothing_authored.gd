extends "res://tests/test_base.gd"
## C5 authored Blender garments -> LSX -> Godot runtime, materials, morphs and bind mapping.

const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const LSX := preload("res://scripts/assets/lsx_decoder.gd")
const Library := preload("res://scripts/assets/asset_library.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Visual := preload("res://scripts/sim/sim_visual.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


func _ready() -> void:
	section("C5 authored source/texture library")
	check(Wardrobe.is_available(), "runtime LSX assets available, no Blender GLB import dependency")
	var st := Wardrobe.stats()
	check(st["top"]["styles"] == 20 and st["top"]["meshes"] == 118, "20 tops, including cat hoodie")
	check(st["bottom"]["styles"] == 16 and st["bottom"]["meshes"] == 22, "16 bottoms, including subculture variants")
	check(st["shoes"]["styles"] == 15 and st["shoes"]["meshes"] == 29, "15 shoes including modeled boot shafts")
	check(st["dress"]["meshes"] == 2 and st["legs"]["meshes"] == 1, "dress lower, waistband and exposed leg surface")
	var hood := Wardrobe.parts("top", "mikina")
	var jeans := Wardrobe.parts("bottom", "dziny")
	var skirt := Wardrobe.parts("bottom", "sukne")
	var dress := Wardrobe.parts("dress", "saty")
	var boots := Wardrobe.parts("shoes", "kozacky")
	check(hood.size() >= 7 and skirt.size() == 2 and dress.size() == 2 and boots.size() == 3,
		"hoodie, skirt, dress and boots contain actual authored accessory geometry")
	var total := 0
	var correct := true
	var normals := true
	for collection in [hood, jeans, skirt, dress, boots]:
		for info in collection:
			total += 1
			var mesh: ArrayMesh = info["mesh"]
			var arrays: Array = mesh.surface_get_arrays(0)
			var count := mesh.surface_get_array_len(0)
			correct = correct and mesh.get_blend_shape_count() == 10 and count > 0
			correct = correct and (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() == count * 4
			correct = correct and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == count
			correct = correct and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == count * 4
			for b in (arrays[Mesh.ARRAY_BONES] as PackedInt32Array):
				if b < 0 or b >= 17:
					correct = false
			var mat := Wardrobe.material_instance(info, {"top": Color(0.25,0.33,0.45), "bottom": Color(0.14,0.2,0.25)})
			if not String(info["material"]).begins_with("skin_"):
				normals = normals and mat.albedo_texture != null and mat.normal_texture != null and mat.normal_enabled
	check(total >= 15 and correct, "geometry has 10 morphs, valid bone binds and UV/tangent arrays", str(total))
	check(normals, "PBR materials use Blender-authored albedo and normal PNGs")
	section("Critical: remap LSX order to original character Skin bind order")
	var base := Library.instantiate("character")
	var sk := base.get_node("Skeleton3D") as Skeleton3D
	var old_skin: Skin = null
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			old_skin = (mi as MeshInstance3D).skin
			break
	var dec := LSX.decode(FileAccess.get_file_as_string("res://assets/src/clothing_c5/top.lsx"))
	var bone_names := []
	for item in dec["head"]["bones"]:
		bone_names.append(String(item["name"]))
	var mapping_correct := old_skin != null and bone_names.size() == 17
	if old_skin != null:
		for i in bone_names.size():
			var mapped: int = int(Wardrobe.C5_TO_CHARACTER_BIND[i])
			mapping_correct = mapping_correct and sk.get_bone_name(old_skin.get_bind_bone(mapped)) == bone_names[i]
	check(mapping_correct, "C5 vertex bind indices match the avatar's original Skin (leg vs arm)")
	var jj: Array = (jeans[0]["mesh"] as ArrayMesh).surface_get_arrays(0)
	var vv: PackedVector3Array = jj[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = jj[Mesh.ARRAY_BONES]
	var calf_ok := true
	var samples := 0
	for i in vv.size():
		if vv[i].y < 0.36:
			samples += 1
			for k in 4:
				var idx := bb[i * 4 + k]
				var wt: float = float((jj[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)[i * 4 + k])
				if wt > 0.01 and idx in [5, 6, 7, 11, 12, 13]:
					calf_ok = false
	check(samples > 25 and calf_ok, "calves bind to leg bones, never arm bones", str(samples))
	base.free()
	section("Public outfit selection and in-game morphs")
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Test"
	d["personality"]["traits"] = ["hravy"]
	d["clothing"]["active"] = "sport"
	d["clothing"]["sport"]["top"] = "mikina"
	d["clothing"]["sport"]["bottom"] = "teplaky"
	d["clothing"]["sport"]["shoes"] = "kozacky"
	var validated: Dictionary = Validator.validate(d)
	check(validated["ok"], "active sport outfit is server-valid", str(validated["errors"]))
	var lp: Dictionary = Resolver.resolve(validated["data"])
	var visual := Visual.new()
	visual._model = Library.instantiate("character")
	visual._apply_c5_wardrobe(lp)
	var contains_hood := false
	for mi in visual._c5_nodes:
		contains_hood = contains_hood or String(mi.name) == "C5_top_hood"
	check(contains_hood and visual._c5_nodes.size() >= 10, "runtime displays hood, sleeves and boots")
	var shape_data := {"body": {"frame": 0.84, "body_fat": 0.85, "height_cm": 185.0}}
	var weighted := Resolver.resolve(shape_data)
	var applied: int = visual.apply_body_shape(weighted)
	var changed := false
	for mi in visual._c5_nodes:
		var m: Mesh = mi.mesh
		var idx: int = mi.find_blend_shape_by_name(StringName("fat_hi"))
		if idx >= 0 and mi.get_blend_shape_value(idx) > 0.1:
			changed = true
	check(applied >= 40 and changed, "C5 garments receive body morph weights with the original skeleton")
	var formal := d.duplicate(true)
	formal["clothing"]["active"] = "spolecenske"
	formal["clothing"]["spolecenske"]["top"] = "saty"
	formal["clothing"]["spolecenske"]["bottom"] = "zadne"
	formal["clothing"]["spolecenske"]["shoes"] = "lodicky"
	visual._apply_c5_wardrobe(Resolver.resolve(formal))
	var names := []
	for mi in visual._c5_nodes:
		names.append(String(mi.name))
	check(names.has("C5_dress_dress_lower") and names.has("C5_legs_skin_surface") and not names.has("C5_bottom_shell"),
		"changing to dress hides pants and adds dress + exposed legs")
	visual._model.free()
	visual._model = null
	visual.free()
	finish("test_clothing_authored")
