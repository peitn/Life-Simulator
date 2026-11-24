extends Node
## Diagnostika (C-LOD krok 7): LOD indexy procedurálních sítí a viditelnost dílů pro bosou postavu bez trika.

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const CL := preload("res://scripts/assets/character_lod.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cd = CharacterData.create()
	cd.set_from_dict(Randomizer.generate(rng))
	var look: Dictionary = cd.public_snapshot()
	var keys: Array = []
	for k in look.keys():
		if String(k).find("outfit") >= 0 or String(k).find("shoe") >= 0:
			keys.append("%s=%s" % [k, look[k]])
	print("outfit keys: ", keys)
	look["outfit_shoes"] = "bosy"
	look["outfit_top"] = "zadne"
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(look)
	for i in 900:
		await get_tree().process_frame
		if not v.hair_waiting() and not v.wardrobe_waiting():
			break
	print("look_params shoes=%s top=%s" % [v.look_params.get("outfit_shoes"), v.look_params.get("outfit_top")])
	print("torso nodes: ", v._torso_detail_nodes.keys(), " available=", v.torso_details_available())
	var nodes: Array = []
	nodes.append_array(v._hand_detail_nodes)
	nodes.append_array(v._foot_detail_nodes)
	nodes.append_array(v._torso_detail_nodes.values())
	for mi in nodes:
		var m: Mesh = mi.mesh
		print("%s vis=%s tris=%d lods=%s keys=%d mode=%d" % [mi.name, mi.is_visible_in_tree(), m.surface_get_array_index_len(0) / 3,
			str(CL.lod_triangle_counts(m)), m.get_blend_shape_count(), m.blend_shape_mode])
	print("CL generated=%d rejected=%d" % [CL.generated, CL.rejected_lods])
	get_tree().quit(0)
