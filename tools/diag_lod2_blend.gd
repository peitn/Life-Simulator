extends Node3D
## Diagnostika (C-LOD krok 6): kolik blend shapes je aktivních u náhodných postav ve stupni 2 (dav).

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


func _ready() -> void:
	HairRig.async_build = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1, 80), Vector3(0, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var d: Dictionary = Randomizer.generate(rng)
	var cd = CharacterData.create()
	cd.set_from_dict(d)
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(cd.public_snapshot())
	for i in 60:
		await get_tree().process_frame
	print("tier ", v.lod_tier(), " hair ", d["hair"].get("style"))
	var tot_active := 0
	var tot_vw := 0
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		if m == null or m.get_blend_shape_count() == 0:
			continue
		var act := 0
		for i in m.get_blend_shape_count():
			if absf(mi.get_blend_shape_value(i)) > 0.0001:
				act += 1
		var verts := 0
		for s in m.get_surface_count():
			verts += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if mi.is_visible_in_tree():
			tot_active += act
			tot_vw += act * verts
			print("%s shapes=%d active=%d verts=%d" % [mi.name, m.get_blend_shape_count(), act, verts])
	print("TOTAL visible active=%d active*verts=%d" % [tot_active, tot_vw])
	get_tree().quit()
