extends Node
## Diagnostika (C-LOD krok 7, 18. 11. 2026): procedurální díly (prsty, chodidla, trup) a jejich blend shapes.
## Reprodukuje vzorec GPU (servers/rendering/renderer_rd/shaders/skeleton.glsl):
##   NORMALIZED: v = (1−Σw)·base + Σ w·cíl,  n = normalize((1−Σw)·n + Σ w·dekód(n_cíl))
##   RELATIVE:   v = base + Σ w·cíl,          n = normalize(n + Σ w·dekód(n_cíl))   (dekód = jednotkový vektor)
## a měří (1) odchylku normál od základní normály u tělesných morfů, (2) chybu zapečení LodBake proti GPU.

const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const LodBake := preload("res://scripts/assets/lod_bake.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")


static func gpu(m: ArrayMesh, w: PackedFloat32Array) -> Array:
	var a := m.surface_get_arrays(0)
	var pos: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var nrm: PackedVector3Array = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	var bl := m.surface_get_blend_shape_arrays(0)
	var norm := m.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var tot := 0.0
	var bv := PackedVector3Array()
	bv.resize(pos.size())
	var bn := PackedVector3Array()
	bn.resize(pos.size())
	for k in mini(w.size(), bl.size()):
		if absf(w[k]) <= 0.0001:
			continue
		var tv: PackedVector3Array = bl[k][Mesh.ARRAY_VERTEX]
		var tn: PackedVector3Array = bl[k][Mesh.ARRAY_NORMAL]
		for i in pos.size():
			bv[i] += tv[i] * w[k]
			bn[i] += tn[i].normalized() * w[k]
		tot += w[k]
	for i in pos.size():
		if norm:
			pos[i] *= 1.0 - tot
			nrm[i] *= 1.0 - tot
		pos[i] += bv[i]
		nrm[i] = (nrm[i] + bn[i]).normalized()
	return [pos, nrm]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cd = CharacterData.create()
	cd.set_from_dict(Randomizer.generate(rng))
	var look: Dictionary = cd.public_snapshot()
	look["outfit_shoes"] = "bosy"
	look["outfit_top"] = "zadne"
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(look)
	for i in 600:
		await get_tree().process_frame
		if not v.hair_waiting() and not v.wardrobe_waiting():
			break
	var nodes: Array = []
	nodes.append_array(v._hand_detail_nodes)
	nodes.append_array(v._foot_detail_nodes)
	nodes.append_array(v._torso_detail_nodes.values())
	for mi in nodes:
		var m := mi.mesh as ArrayMesh
		var w := PackedFloat32Array()
		for i in mi.get_blend_shape_count():
			w.append(mi.get_blend_shape_value(i))
		var base: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var g := gpu(m, w)
		var maxang := 0.0
		var mean := 0.0
		for i in base.size():
			var ang := rad_to_deg(base[i].angle_to(g[1][i]))
			maxang = maxf(maxang, ang)
			mean += ang
		mean /= maxf(1.0, base.size())
		var baked := LodBake.bake_now(m, w)
		var perr := 0.0
		if baked != null:
			var bp: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in bp.size():
				perr = maxf(perr, bp[i].distance_to(g[0][i]))
		var tris := m.surface_get_array_index_len(0) / 3
		print("%s vis=%s mode=%d keys=%d verts=%d tris=%d | normal tilt vs base: mean %.2f° max %.2f° | LodBake pos err vs GPU %.4f m"
			% [mi.name, mi.visible, m.blend_shape_mode, m.get_blend_shape_count(), base.size(), tris, mean, maxang, perr])
	var bw := PackedFloat32Array()
	for i in mini(10, (v._hand_detail_nodes[0] as MeshInstance3D).get_blend_shape_count()):
		bw.append((v._hand_detail_nodes[0] as MeshInstance3D).get_blend_shape_value(i))
	print("body morph weights: ", bw)
	get_tree().quit(0)
