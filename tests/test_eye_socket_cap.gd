extends "res://tests/test_base.gd"
## Zadní víčko očnice „ec“ a prstenec 5 (spojivkový vak) – běh main-claude-1794424928.
## Ověřuje invariant, na kterém oprava stojí: v azimutálně délkojevné mapě kolem přední osy oka je azimut prstence 5
## i všech prstenců víčka (při pohledu podél osy oka) ostře monotónní pro jakýkoli obličej, prstence jsou vnořené
## (úhel od přední osy roste s hloubkou), víčko leží na kouli R + 1,2 mm (nikdy nepronikne okem) a je uzavřené
## (každá hrana kolem víčka má právě 2 plochy). Pak přímo: žádná plocha hlavy se při extrémních kombinacích
## nepřeloží (přesný tvar i lineární součet očních morfů), determinismus a souměrnost.
## Rychlý test (bez build_data / blend shapes, ~1 min); plný test blend shapes je test_head.

const HB := preload("res://scripts/assets/head_builder.gd")
const FM := preload("res://scripts/character/face_morphs.gd")

const EYE_KEYS := ["eye_size", "eye_depth", "eye_distance", "eyelid_hood", "eye_tilt", "brow_ridge", "brow_height", "asym_eyes"]

var topo
var p0: PackedVector3Array
## strana → [prstenec 5, prstenec EC_RINGS[0], …] jako pole indexů vrcholů v pořadí obvodu bloku
var rings := {}
var pole := {}


func _init() -> void:
	watchdog_seconds = 300.0


func _ready() -> void:
	await get_tree().process_frame
	topo = HB.build_topology()
	p0 = HB.positions(topo, {})
	_collect_rings()
	_test_topology()
	_test_sphere_and_invariant()
	_test_no_flips()
	_test_determinism_symmetry()
	finish("test_eye_socket_cap")


func _collect_rings() -> void:
	var er5 := {}
	var ec := {}
	for i in topo.recipes.size():
		var r: Array = topo.recipes[i]
		if r[0] == "er" and int(r[2]) == 5:
			er5["%d|%s|%s" % [int(r[1]), str(r[3]), str(r[4])]] = i
		elif r[0] == "ec":
			if float(r[2]) >= 1.0:
				pole[int(r[1])] = i
			else:
				ec["%d|%s|%s|%s" % [int(r[1]), str(r[2]), str(r[3]), str(r[4])]] = i
	for s in [1, -1]:
		var bl: Array = topo.blocks["eye%d" % s]
		var per: Array = HB._perimeter(bl[0], bl[1], bl[2], bl[3])
		var list: Array = []
		var r5 := PackedInt32Array()
		for p in per:
			r5.append(int(er5.get("%d|%s|%s" % [s, str(p[2]), str(p[3])], -1)))
		list.append(r5)
		for m in HB.EC_RINGS:
			var rr := PackedInt32Array()
			for p in per:
				rr.append(int(ec.get("%d|%s|%s|%s" % [s, str(float(m)), str(p[2]), str(p[3])], -1)))
			list.append(rr)
		rings[s] = list


func _test_topology() -> void:
	section("Topologie víčka")
	var ok_idx := true
	var n_ec := 0
	for s in [1, -1]:
		for rr in rings[s]:
			for v in (rr as PackedInt32Array):
				if v < 0:
					ok_idx = false
		ok_idx = ok_idx and pole.has(s)
	for r in topo.recipes:
		if r[0] == "ec":
			n_ec += 1
			if (r as Array).size() != 5:
				ok_idx = false
	var per_n: int = (rings[1][0] as PackedInt32Array).size()
	check(ok_idx and n_ec == 2 * (per_n * HB.EC_RINGS.size() + 1),
		"recepty [\"ec\", strana, m, a, b]: %d prstence × %d vrcholů + pól na oko (%d vrcholů)" % [HB.EC_RINGS.size(), per_n, n_ec])
	# Uzavřenost: každá hrana s vrcholem víčka má právě 2 plochy; vějíř u pólu má per_n trojúhelníků.
	# Hrany se počítají přes VŠECHNY plochy hlavy (hrana prstence 5 má druhou plochu v pásu prstenec 4 → 5).
	var r5set := {}
	for s in [1, -1]:
		for v in (rings[s][0] as PackedInt32Array):
			r5set[v] = true
	var edges := {}
	var pole_tris := 0
	var mats_ok := true
	for f in topo.faces:
		var idx: PackedInt32Array = f[2]
		var touches := false
		for v in idx:
			if topo.recipes[v][0] == "ec":
				touches = true
		if touches and String(f[1]) != "eye_socket":
			mats_ok = false
		if touches and idx.size() == 3 and (idx[2] == pole.get(1, -2) or idx[2] == pole.get(-1, -2)):
			pole_tris += 1
		for k in idx.size():
			var a := idx[k]
			var b := idx[(k + 1) % idx.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = int(edges.get(key, 0)) + 1
	var bad := 0
	var n_checked := 0
	for key in edges:
		var ka: int = key.x
		var kb: int = key.y
		if topo.recipes[ka][0] == "ec" or topo.recipes[kb][0] == "ec" or (r5set.has(ka) and r5set.has(kb)):
			n_checked += 1
			if int(edges[key]) != 2:
				bad += 1
	check(bad == 0 and n_checked > 0, "víčko je uzavřené: každá z %d hran víčka a prstence 5 má právě 2 plochy" % n_checked, "%d hran mimo" % bad)
	check(pole_tris == 2 * per_n and mats_ok, "vějíř k zadnímu pólu (%d trojúhelníků), vše materiál eye_socket" % pole_tris)
	# Gemini audit (běh main-claude-1794424928): konzistentní orientace vějíře a prstenců – každá hrana víčka je ve
	# svých 2 plochách projitá opačnými směry (jinak by vějíř měl obrácené normály oproti _annulus).
	var directed := {}
	for f in topo.faces:
		var idx: PackedInt32Array = f[2]
		for k in idx.size():
			var a := idx[k]
			var b := idx[(k + 1) % idx.size()]
			if topo.recipes[a][0] == "ec" or topo.recipes[b][0] == "ec" or (r5set.has(a) and r5set.has(b)):
				var dk := Vector2i(a, b)
				directed[dk] = int(directed.get(dk, 0)) + 1
	var same_dir := 0
	for dk in directed:
		if int(directed[dk]) > 1 or not directed.has(Vector2i(dk.y, dk.x)):
			same_dir += 1
	check(same_dir == 0, "orientace víčka konzistentní s okolím: každá hrana projitá v obou plochách opačně (%d orientovaných hran)" % directed.size(), "%d nesouhlasí" % same_dir)


## Azimut v místním rámci oka (x' = strana·x) a úhel od přední osy.
func _polar(q: Vector3, c: Vector3, s: int) -> Vector2:
	var dv := (q - c).normalized()
	return Vector2(atan2(dv.y, float(s) * dv.x), acos(clampf(dv.z, -1.0, 1.0)))


func _faces_sample(seed_v: int, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array = [{}]
	for c in n:
		var f := {}
		for k in EYE_KEYS:
			f[k] = 1.0 if rng.randf() < 0.5 else -1.0
		out.append(f)
	for c in n:
		var f := {}
		for k in FM.morph_fields():
			f[k] = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.75, 1.0)
		f["chin_cleft"] = absf(float(f["chin_cleft"]))
		if c % 4 == 0:
			f["ex_blink_l"] = rng.randf()
			f["ex_smile"] = rng.randf()
		out.append(f)
	return out


func _test_sphere_and_invariant() -> void:
	section("Invariant: koule, monotónní azimut, vnořené prstence")
	var worst_r := 0.0
	var mono_bad: Array = []
	var nest_bad := 0
	var min_step := 1e9
	var faces := _faces_sample(20261111, 16)
	for f in faces:
		var p := HB.positions(topo, f)
		var d := HB.derive(f)
		for s in [1, -1]:
			var e: Dictionary = d["eye%d" % s]
			var c: Vector3 = e["E"]
			var rad := float(e["R"]) + 0.0012
			var prev_pol := PackedFloat64Array()
			for ri in (rings[s] as Array).size():
				var rr: PackedInt32Array = rings[s][ri]
				var az := PackedFloat64Array()
				var pol := PackedFloat64Array()
				for v in rr:
					worst_r = maxf(worst_r, absf(p[v].distance_to(c) - rad))
					var pp := _polar(p[v], c, s)
					az.append(pp.x)
					pol.append(pp.y)
				var tot := 0.0
				var steps := PackedFloat64Array()
				for k in az.size():
					var da := wrapf(az[(k + 1) % az.size()] - az[k], -PI, PI)
					steps.append(da)
					tot += da
				var sg := signf(tot)
				var rev := 0
				for da in steps:
					if da * sg <= 0.0:
						rev += 1
					min_step = minf(min_step, absf(da))
				if rev > 0 or absf(absf(tot) - TAU) > 1e-6:
					mono_bad.append("strana %d prstenec %d: %d obrácených kroků %s" % [s, ri, rev, str(f).substr(0, 60)])
				if ri > 0:
					for k in pol.size():
						if pol[k] <= prev_pol[k]:
							nest_bad += 1
				prev_pol = pol
			var pc := _polar(p[pole[s]], c, s)
			worst_r = maxf(worst_r, absf(p[pole[s]].distance_to(c) - rad))
			if pc.y < PI - 1e-6:
				nest_bad += 1
	check(worst_r < 1e-6, "prstenec 5 i víčko leží na kouli R + 1,2 mm kolem oka (odchylka %.4f µm, %d obličejů)" % [worst_r * 1e6, faces.size()])
	check(mono_bad.is_empty(), "azimut prstence 5 a všech prstenců víčka je ostře monotónní (nejmenší krok %.3f°)" % rad_to_deg(min_step), str(mono_bad.slice(0, 3)))
	check(nest_bad == 0, "prstence jsou vnořené: úhel od přední osy roste k zadnímu pólu (pól = 180°)", "%d porušení" % nest_bad)


func _flip_count(p: PackedVector3Array) -> Vector2:
	var n := 0
	var mx := 0.0
	for f in topo.faces:
		var idx: PackedInt32Array = f[2]
		var a := (p0[idx[1]] - p0[idx[0]]).cross(p0[idx[2]] - p0[idx[0]])
		var b := (p[idx[1]] - p[idx[0]]).cross(p[idx[2]] - p[idx[0]])
		if a.length() > 1e-12 and b.length() > 1e-12 and a.dot(b) < 0.0:
			n += 1
			mx = maxf(mx, a.length() * 0.5)
	return Vector2(n, mx)


func _test_no_flips() -> void:
	section("Žádné přeložené plochy (celá hlava)")
	var tg := {}
	for k in EYE_KEYS:
		for sg in [1.0, -1.0]:
			var q := HB.positions(topo, {k: sg})
			for i in q.size():
				q[i] -= p0[i]
			tg["%s%s" % [k, sg]] = q
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var we := Vector2.ZERO
	var wl := Vector2.ZERO
	for c in 24:
		var f := {}
		for k in EYE_KEYS:
			f[k] = 1.0 if rng.randf() < 0.5 else -1.0
		rng.randf()
		var fe := _flip_count(HB.positions(topo, f))
		var pb := p0.duplicate()
		for k in EYE_KEYS:
			var dd: PackedVector3Array = tg["%s%s" % [k, f[k]]]
			for i in pb.size():
				pb[i] += dd[i]
		var fl := _flip_count(pb)
		we = Vector2(maxf(we.x, fe.x), maxf(we.y, fe.y))
		wl = Vector2(maxf(wl.x, fl.x), maxf(wl.y, fl.y))
	check(we.x == 0, "24 rohů očního podprostoru (přesný tvar): 0 přeložených ploch (nejhůř %d, %.2f mm²)" % [we.x, we.y * 1e6])
	check(wl.x == 0, "24 rohů jako lineární součet očních morfů: 0 přeložených ploch (nejhůř %d, %.2f mm²)" % [wl.x, wl.y * 1e6])
	var wr := Vector2.ZERO
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242
	for s in 24:
		var f := {}
		for k in FM.morph_fields():
			f[k] = (1.0 if rng2.randf() < 0.5 else -1.0) * rng2.randf_range(0.75, 1.0)
		f["chin_cleft"] = absf(float(f["chin_cleft"]))
		var fr := _flip_count(HB.positions(topo, f))
		wr = Vector2(maxf(wr.x, fr.x), maxf(wr.y, fr.y))
	check(wr.x == 0, "24 náhodných extrémů všech %d polí: 0 přeložených ploch (nejhůř %d, %.2f mm²)" % [FM.morph_fields().size(), wr.x, wr.y * 1e6])
	# Nejmenší plocha víčka ve výchozím tvaru – degenerované jehly by kazily normály.
	var amin := 1e9
	for f in topo.faces:
		if String(f[1]) == "eye_socket":
			var idx: PackedInt32Array = f[2]
			amin = minf(amin, (p0[idx[1]] - p0[idx[0]]).cross(p0[idx[2]] - p0[idx[0]]).length() * 0.5)
	check(amin > 1e-8, "žádný degenerovaný trojúhelník vaku a víčka (nejmenší %.3f mm²)" % (amin * 1e6))
	# Gemini audit: blend shapes se sčítají lineárně, takže při mezivahách jdou vrcholy koule po sečně (dovnitř).
	# Vůle víčka a vaku od povrchu oční koule (R) při polovičních i plných vahách očních morfů a jejich součtu.
	var worst_clear := 1e9
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 99
	for c in 16:
		var f := {}
		for k in EYE_KEYS:
			f[k] = (1.0 if rng3.randf() < 0.5 else -1.0)
		for wgt in [0.5, 1.0]:
			var pb := p0.duplicate()
			var fx := {}
			for k in EYE_KEYS:
				var dd: PackedVector3Array = tg["%s%s" % [k, f[k]]]
				for i in pb.size():
					pb[i] += dd[i] * wgt
				fx[k] = float(f[k]) * wgt
			# střed a poloměr oka z přesného tvaru (oční koule jsou ve hře samostatná síť s vlastními morfy)
			var d := HB.derive(fx)
			for s in [1, -1]:
				var e: Dictionary = d["eye%d" % s]
				var cc: Vector3 = e["E"]
				for ri in (rings[s] as Array).size():
					for v in (rings[s][ri] as PackedInt32Array):
						worst_clear = minf(worst_clear, pb[v].distance_to(cc) - float(e["R"]))
				worst_clear = minf(worst_clear, pb[pole[s]].distance_to(cc) - float(e["R"]))
	check(worst_clear > 0.0006, "vak a víčko drží vůli od oční koule i při mezivahách lineárního součtu (nejmenší %.2f mm)" % (worst_clear * 1000.0))


func _test_determinism_symmetry() -> void:
	section("Determinismus a souměrnost víčka")
	var q := HB.positions(HB.build_topology(), {})
	var same := q.size() == p0.size()
	if same:
		for i in q.size():
			if q[i] != p0[i]:
				same = false
				break
	check(same, "nová topologie i polohy bit po bitu stejné")
	var worst := 0.0
	var r1: Array = rings[1]
	var r2: Array = rings[-1]
	for ri in r1.size():
		var a: PackedInt32Array = r1[ri]
		var b: PackedInt32Array = r2[ri]
		for k in a.size():
			# obvod bloku pravého oka je zrcadlem levého: vrchol (a, b) levého ↔ (−a, b) pravého
			var m := Vector3(-p0[a[k]].x, p0[a[k]].y, p0[a[k]].z)
			var best := 1e9
			for v in b:
				best = minf(best, p0[v].distance_to(m))
			worst = maxf(worst, best)
	worst = maxf(worst, Vector3(-p0[pole[1]].x, p0[pole[1]].y, p0[pole[1]].z).distance_to(p0[pole[-1]]))
	check(worst < 1e-6, "výchozí víčko je zrcadlově souměrné (%.4f mm)" % (worst * 1000.0))
