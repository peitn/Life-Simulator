extends RefCounted
## CharacterAssembly (C3, C3+) – sestavení modelu postavy při importu (tools/import_lsx.gd):
##  1) krk těla se nad smyčkou v y ≈ 1,499 ODŘÍZNE (cut_body_neck) – z okraje se vezme smyčka (polohy,
##     normály, váhy kostí a výchylky všech blend shapes těla),
##  2) procedurální hlava s obličejovými morfy (HeadBuilder) se postaví s PŘILNUTÍM ke smyčce: spodní pás krku
##     hlavy leží na okraji těla (+0,4 mm), víčko krku je schované v trupu, pás nese blend shapes se jmény
##     klíčů těla a váhy kostí smíchané s tělem → šev se neotevře při morfech ani animaci (C3+, běh 11;
##     dřív se krk těla jen zužoval pod rukávem hlavy a dvě sítě se protínaly v zubaté čáře),
##  3) vlasy (zatím sítě z v3, nové účesy přijdou v C4b) převezmou morfy hlavy PŘENOSEM (vážený průměr
##     výchylek nejbližších vrcholů lebky) – stejný nástroj poslouží v C5 pro oblečení.
## Všechno je deterministické a běží jen při importu; hra načítá hotové GLB.

const HeadBuilder := preload("res://scripts/assets/head_builder.gd")

## Řez krku těla: smažou se trojúhelníky, jejichž VŠECHNY vrcholy leží nad CUT_Y a blíž ose než CUT_R.
## Smyčka těla leží v y 1,4985–1,4993, řada pod ní v 1,487–1,490 → řez mezi nimi.
const CUT_Y := 1.4935
const CUT_R := 0.075
## Zvednutí báze krku těla (běh 11, render s tělem): okraj krku těla byl vzadu v ~1,49 m, ale u dospělého
## (výška modelu 1,78 m) leží obratel C7 kolem 0,86 H ≈ 1,53 m a trapéz stoupá ke krku – krk proto působil
## dlouze (hlavně zezadu a z boku). Pole posunu NAHORU: LIFT × směr (vpředu 15 %, do stran ~64 %, vzadu 100 %)
## × blízkost ose krku (LIFT_R0..R1) × výška (LIFT_Y0..Y1). Posun se počítá z polohy v ZÁKLADU a přičte se
## stejně k základu i ke všem cílům blend shapes (výchylky morfů zůstanou beze změny); normály se otočí
## o rozdíl normál spočítaných před a po posunu (mimo pole se nezmění vůbec nic).
const LIFT := 0.022
const LIFT_R0 := 0.07
const LIFT_R1 := 0.17
const LIFT_Y0 := 1.34
const LIFT_Y1 := 1.44
## Přenos morfů: k nejbližších zdrojových vrcholů, jen klíče s výchylkou nad prahem.
const TRANSFER_K := 4
const TRANSFER_MIN := 0.0001


## Připojí hlavu do scény z LSX (Node3D → Skeleton3D → MeshInstance3D…). Vrací meta pro manifest nebo {} při chybě.
static func attach_head(scene: Node3D, hair_groups: Array = ["hair_short", "hair_long"]) -> Dictionary:
	var skel := scene.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel == null:
		return {}
	var hb := skel.find_bone("head")
	var nb := skel.find_bone("neck")
	if hb < 0 or nb < 0:
		return {}
	var skin: Skin = null
	var body_mi: MeshInstance3D = null
	for mi in skel.get_children():
		if not (mi is MeshInstance3D):
			continue
		if skin == null and (mi as MeshInstance3D).skin != null:
			skin = (mi as MeshInstance3D).skin
		var nm := String(mi.name)
		if nm.get_slice("__", 0) == "body" and nm.get_slice("__", 2) == "skin_body":
			body_mi = mi
	if skin == null or body_mi == null:
		return {}
	var lifted := 0
	var body_dy := PackedFloat32Array()
	for mi in skel.get_children():
		if mi is MeshInstance3D and String(mi.name).get_slice("__", 0) == "body":
			var dy := lift_neck_base(mi)
			if mi == body_mi:
				body_dy = dy
			for v in dy:
				if v > 0.0:
					lifted += 1
	var cut := cut_body_neck(body_mi, body_dy)
	if cut.is_empty():
		return {}
	var data := HeadBuilder.build_data(cut["conform"])
	var seam: Dictionary = data["seam"]
	if seam.is_empty():
		return {}
	var built := HeadBuilder.build_instances(data, hb, nb)
	for mi in built["instances"]:
		skel.add_child(mi)
		mi.owner = scene
		mi.skin = skin
		mi.skeleton = NodePath("..")
	# Zdroj pro přenos: vrcholy lebky (mřížka nad úrovní uší).
	var t = data["topo"]
	var p0: PackedVector3Array = data["base"]
	var src_idx := PackedInt32Array()
	for i in t.recipes.size():
		if t.recipes[i][0] == "g" and p0[i].y > 1.60:
			src_idx.append(i)
	var transferred := {}
	for g in hair_groups:
		for mi in skel.get_children():
			if mi is MeshInstance3D and String(mi.name).get_slice("__", 0) == g:
				transferred[String(mi.name)] = transfer_morphs(mi, p0, data["targets"], src_idx)
	var st: Dictionary = built["stats"]
	return {"face_spec": data["spec"], "head": st, "hair_morphs": transferred, "neck_lifted_verts": lifted,
		"neck_cut_tris": cut["cut_tris"], "seam_loop_verts": (cut["conform"]["loop"] as Array).size(),
		"seam_head_verts": (seam["idx"] as PackedInt32Array).size(), "seam_cap_verts": seam["caps"]}


## Posun báze krku nahoru (viz LIFT) z polohy v základu. Bod → posun v metrech (≥ 0).
static func lift_amount(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).length()
	var g := HeadBuilder._smooth(LIFT_R1, LIFT_R0, r)
	var h := HeadBuilder._smooth(LIFT_Y0, LIFT_Y1, p.y)
	if g <= 0.0 or h <= 0.0:
		return 0.0
	var back := 0.5 * (1.0 - (p.z / r if r > 1e-6 else 0.0))
	return LIFT * (0.15 + 0.85 * pow(back, 0.8)) * g * h


## Plošně vážené normály vrcholů (jen pro rozdíl před/po posunu – metoda se ruší).
static func _area_normals(pos: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(pos.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		n[a] += fn
		n[b] += fn
		n[c] += fn
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 1e-20 else Vector3.ZERO
	return n


## Otočí normály n o rotaci, která převádí normály geometrie před posunem na normály po posunu.
static func _rotate_normals(n: PackedVector3Array, before: PackedVector3Array, after: PackedVector3Array, dy: PackedFloat32Array) -> PackedVector3Array:
	for i in n.size():
		if dy[i] <= 0.0 or before[i] == Vector3.ZERO or after[i] == Vector3.ZERO:
			continue
		if before[i].dot(after[i]) > 0.999999:
			continue
		n[i] = (Quaternion(before[i], after[i]) * n[i]).normalized()
	return n


## Zvedne bázi krku sítě těla (základ i všechny cíle blend shapes). Vrací posun každého vrcholu (pro řez).
static func lift_neck_base(mi: MeshInstance3D) -> PackedFloat32Array:
	var dy := PackedFloat32Array()
	var old := mi.mesh as ArrayMesh
	if old == null or old.get_surface_count() != 1:
		return dy
	var arrays: Array = old.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	dy.resize(verts.size())
	var any := false
	for i in verts.size():
		dy[i] = lift_amount(verts[i])
		any = any or dy[i] > 0.0
	if not any or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_NORMAL] == null:
		return dy
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := verts.duplicate()
	for i in moved.size():
		moved[i] = moved[i] + Vector3(0.0, dy[i], 0.0)
	arrays[Mesh.ARRAY_NORMAL] = _rotate_normals(arrays[Mesh.ARRAY_NORMAL], _area_normals(verts, idx), _area_normals(moved, idx), dy)
	arrays[Mesh.ARRAY_VERTEX] = moved
	var blend: Array = old.surface_get_blend_shape_arrays(0)
	for b in blend:
		var bv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
		var bm := bv.duplicate()
		for i in bm.size():
			bm[i] = bm[i] + Vector3(0.0, dy[i], 0.0)
		var bn = b[Mesh.ARRAY_NORMAL]
		if bn != null and (bn as PackedVector3Array).size() == bv.size():
			b[Mesh.ARRAY_NORMAL] = _rotate_normals(bn, _area_normals(bv, idx), _area_normals(bm, idx), dy)
		b[Mesh.ARRAY_VERTEX] = bm
	var am := ArrayMesh.new()
	am.blend_shape_mode = old.blend_shape_mode
	for i in old.get_blend_shape_count():
		am.add_blend_shape(old.get_blend_shape_name(i))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
	am.surface_set_material(0, old.surface_get_material(0))
	am.resource_name = old.resource_name
	mi.mesh = am
	return dy


## Odřízne krk těla nad smyčkou a vrátí {"conform": {...}, "cut_tris": n} nebo {} (síť neodpovídá).
## dy = posun báze krku (lift_neck_base) – řez se rozhoduje podle výšky PŘED posunem.
## conform: "loop" (polohy seřazené podle úhlu kolem těžiště), "normals", "bones"/"weights" (4 na vrchol,
## indexy bindů), "deltas" {klíč: výchylky smyčky}, "dnormals" {klíč: normály smyčky v cíli}.
static func cut_body_neck(mi: MeshInstance3D, dy := PackedFloat32Array()) -> Dictionary:
	var old := mi.mesh as ArrayMesh
	if old == null or old.get_surface_count() != 1:
		return {}
	var arrays: Array = old.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm_v = arrays[Mesh.ARRAY_NORMAL]
	var idx_v = arrays[Mesh.ARRAY_INDEX]
	var bones_v = arrays[Mesh.ARRAY_BONES]
	var wts_v = arrays[Mesh.ARRAY_WEIGHTS]
	if nrm_v == null or idx_v == null or bones_v == null or wts_v == null:
		return {}
	var nrm: PackedVector3Array = nrm_v
	var idx: PackedInt32Array = idx_v
	var bones: PackedInt32Array = bones_v
	var wts: PackedFloat32Array = wts_v
	if bones.size() != verts.size() * 4 or wts.size() != verts.size() * 4 or nrm.size() != verts.size():
		return {}
	var inside := PackedByteArray()
	inside.resize(verts.size())
	for i in verts.size():
		var p := verts[i]
		var y0 := p.y - (dy[i] if dy.size() == verts.size() else 0.0)
		inside[i] = 1 if y0 > CUT_Y and Vector2(p.x, p.z).length() < CUT_R else 0
	var keep := PackedInt32Array()
	var edge_kept := {}
	var edge_cut := {}
	var cut_tris := 0
	for tri in range(0, idx.size(), 3):
		var a := idx[tri]
		var b := idx[tri + 1]
		var c := idx[tri + 2]
		var cut_me := inside[a] == 1 and inside[b] == 1 and inside[c] == 1
		var dst: Dictionary = edge_cut if cut_me else edge_kept
		for e in [[a, b], [b, c], [c, a]]:
			dst[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))] = true
		if cut_me:
			cut_tris += 1
		else:
			keep.append_array(PackedInt32Array([a, b, c]))
	var loop_set := {}
	for e in edge_cut:
		if edge_kept.has(e):
			loop_set[e.x] = true
			loop_set[e.y] = true
	if cut_tris == 0 or loop_set.size() < 6:
		return {}
	var li: Array = loop_set.keys()
	var cen := Vector2.ZERO
	for i in li:
		cen += Vector2(verts[i].x, verts[i].z)
	cen /= float(li.size())
	li.sort_custom(func(x, y): return atan2(verts[x].x - cen.x, verts[x].z - cen.y) < atan2(verts[y].x - cen.x, verts[y].z - cen.y))
	var loop: Array = []
	var ln: Array = []
	var lb: Array = []
	var lw: Array = []
	for i in li:
		loop.append(verts[i])
		ln.append(nrm[i])
		lb.append(PackedInt32Array([bones[i * 4], bones[i * 4 + 1], bones[i * 4 + 2], bones[i * 4 + 3]]))
		lw.append(PackedFloat32Array([wts[i * 4], wts[i * 4 + 1], wts[i * 4 + 2], wts[i * 4 + 3]]))
	var blend: Array = old.surface_get_blend_shape_arrays(0)
	var deltas := {}
	var dnorm := {}
	for bi in old.get_blend_shape_count():
		var bv: PackedVector3Array = (blend[bi] as Array)[Mesh.ARRAY_VERTEX]
		var bn_v = (blend[bi] as Array)[Mesh.ARRAY_NORMAL]
		var has_bn: bool = bn_v != null and (bn_v as PackedVector3Array).size() == verts.size()
		var d: Array = []
		var dn: Array = []
		for i in li:
			d.append(bv[i] - verts[i])
			dn.append((bn_v as PackedVector3Array)[i] if has_bn else nrm[i])
		var key := String(old.get_blend_shape_name(bi))
		deltas[key] = d
		dnorm[key] = dn
	arrays[Mesh.ARRAY_INDEX] = keep
	var am := ArrayMesh.new()
	am.blend_shape_mode = old.blend_shape_mode
	for i in old.get_blend_shape_count():
		am.add_blend_shape(old.get_blend_shape_name(i))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
	am.surface_set_material(0, old.surface_get_material(0))
	am.resource_name = old.resource_name
	mi.mesh = am
	return {"conform": {"loop": loop, "normals": ln, "bones": lb, "weights": lw, "deltas": deltas, "dnormals": dnorm},
		"cut_tris": cut_tris}


## Přenese morfy z bodové množiny (src_pos + výchylky) na síť: každý vrchol = vážený průměr výchylek
## TRANSFER_K nejbližších zdrojových bodů (váha 1/(d² + ε)). Nahradí mesh novým s blend shapes
## (NORMALIZED, absolutní cíle, normály ze základu). Vrací počet přidaných blend shapes.
static func transfer_morphs(mi: MeshInstance3D, src_pos: PackedVector3Array, targets: Dictionary, src_idx: PackedInt32Array) -> int:
	var old := mi.mesh as ArrayMesh
	if old == null or old.get_surface_count() != 1 or old.get_blend_shape_count() > 0:
		return 0
	var arrays: Array = old.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# k nejbližších (hrubou silou – běží jen při importu)
	var nn_idx: Array = []
	var nn_w: Array = []
	for v in verts:
		var best_d := PackedFloat64Array()
		var best_i := PackedInt32Array()
		for si in src_idx:
			var d2 := float(v.distance_squared_to(src_pos[si]))
			if best_d.size() < TRANSFER_K:
				best_d.append(d2)
				best_i.append(si)
			else:
				var worst := 0
				for k in range(1, TRANSFER_K):
					if best_d[k] > best_d[worst]:
						worst = k
				if d2 < best_d[worst]:
					best_d[worst] = d2
					best_i[worst] = si
		var ws := PackedFloat64Array()
		var tot := 0.0
		for k in best_d.size():
			var w := 1.0 / (best_d[k] + 1e-6)
			ws.append(w)
			tot += w
		for k in ws.size():
			ws[k] /= tot
		nn_idx.append(best_i)
		nn_w.append(ws)
	var names: Array = []
	var blend: Array = []
	var keys: Array = targets.keys()
	keys.sort()
	for key in keys:
		var dd: PackedVector3Array = targets[key]
		var tv := PackedVector3Array()
		tv.resize(verts.size())
		var mx := 0.0
		for i in verts.size():
			var acc := Vector3.ZERO
			var bi: PackedInt32Array = nn_idx[i]
			var bw: PackedFloat64Array = nn_w[i]
			for k in bi.size():
				acc += dd[bi[k]] * float(bw[k])
			tv[i] = verts[i] + acc
			mx = maxf(mx, acc.length())
		if mx < TRANSFER_MIN:
			continue
		var ba := []
		ba.resize(Mesh.ARRAY_MAX)
		ba[Mesh.ARRAY_VERTEX] = tv
		ba[Mesh.ARRAY_NORMAL] = nrm
		names.append(key)
		blend.append(ba)
	if names.is_empty():
		return 0
	var am := ArrayMesh.new()
	am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for n in names:
		am.add_blend_shape(StringName(n))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
	am.surface_set_material(0, old.surface_get_material(0))
	am.resource_name = old.resource_name
	mi.mesh = am
	return names.size()
