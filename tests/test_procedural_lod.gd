extends "res://tests/test_base.gd"
## C-LOD krok 7 (18. 11. 2026 večer): procedurální díly postavy (prsty + nehty, chodidla, trup) v davu.
## 1) LodBake v režimu RELATIVE = vzorec skinovacího shaderu Godotu (skeleton.glsl), ověřeno analyticky
##    i proti nezávislé implementaci; NORMALIZED s absolutními cíli dává stejné polohy jako RELATIVE s deltami.
## 2) HandDetailBuilder (ruce, chodidla, trup): NORMALIZED s absolutními cíli – tělesné morfy nemění normály
##    (dřív RELATIVE: oktaedrická „nulová“ delta normály = (0,0,−1) → odklon 50–78° na GPU), ohyb prstu
##    mění jen svůj prst, morph_delta odpovídá posunu.
## 3) Geometrické LOD procedurálních sítí: úrovně ubývají, hranice (kořen prstu, okraj chodidla) zachovaná,
##    vrcholy i blend shapes beze změny, síť sdílená mezi postavami.
## 4) Skutečná bosá postava bez trika ve stupni 2: zapečení VČETNĚ rukou, chodidel a trupu ve vlákně = vzorec GPU
##    s uloženými vahami; finger_joint_values čte zapečený stav bez rozpečení; póza ve stupni 2 rozpeče,
##    zapíše a znovu zapeče; viditelnost (sprcha) naplánuje pečení nově viditelných dílů; návrat do stupně 0
##    vrátí původní sítě s přesnými vahami.

const LodBake := preload("res://scripts/assets/lod_bake.gd")
const CL := preload("res://scripts/assets/character_lod.gd")
const Hand := preload("res://scripts/assets/hand_detail_builder.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")

var cam: Camera3D


func _init() -> void:
	watchdog_seconds = 300.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	_place_cam(3.0)
	_test_relative_bake()
	var v = await _new_visual(_look(7, "bosy", "zadne"))
	if check(v._model != null and v._hand_detail_nodes.size() == 2 and v._foot_detail_nodes.size() == 2,
			"postava s procedurálními prsty a chodidly"):
		_test_builders(v)
		_test_geometry_lod(v)
		await _test_tier2(v)
	await _test_shower_refresh()
	finish("test_procedural_lod")


# ------------------------------------------------------------------ pomocné

func _look(seed_v: int, shoes: String, top: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cd = CharacterData.create()
	cd.set_from_dict(Randomizer.generate(rng))
	cd.clothing["bezne"]["shoes"] = shoes
	cd.clothing["bezne"]["top"] = top
	return cd.public_snapshot()


func _place_cam(d: float) -> void:
	cam.look_at_from_position(Vector3(0, 1.0, d), Vector3(0, 1.0, 0))


func _new_visual(look: Dictionary) -> Node3D:
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(look)
	await wait_until(func(): return not v.hair_waiting() and not v.wardrobe_waiting(), 30.0)
	await wait_seconds(0.2)
	return v


func _weights(mi: MeshInstance3D) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for i in mi.get_blend_shape_count():
		w.append(mi.get_blend_shape_value(i))
	return w


## Nezávislá reprodukce skinovacího shaderu Godotu (servers/rendering/renderer_rd/shaders/skeleton.glsl)
## z dat přečtených ze sítě: [polohy, normály].
func _gpu(m: ArrayMesh, w: PackedFloat32Array) -> Array:
	var a := m.surface_get_arrays(0)
	var pos: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var nrm: PackedVector3Array = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	var bl := m.surface_get_blend_shape_arrays(0)
	var normalized := m.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var total := 0.0
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
		total += w[k]
	for i in pos.size():
		if normalized:
			pos[i] *= 1.0 - total
			nrm[i] *= 1.0 - total
		pos[i] += bv[i]
		nrm[i] = (nrm[i] + bn[i]).normalized()
	return [pos, nrm]


func _max_err(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var e := 0.0
	for i in a.size():
		e = maxf(e, a[i].distance_to(b[i]))
	return e


func _max_angle(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var e := 0.0
	for i in a.size():
		e = maxf(e, rad_to_deg(a[i].angle_to(b[i])))
	return e


func _procedural(v) -> Array:
	var out: Array = []
	out.append_array(v._hand_detail_nodes)
	out.append_array(v._foot_detail_nodes)
	out.append_array(v._torso_detail_nodes.values())
	return out


func _baked(v, mi: MeshInstance3D) -> bool:
	return v._lb_entries.has(mi) and mi.mesh == v._lb_entries[mi][1]


# ------------------------------------------------------------------ 1) LodBake RELATIVE

func _syn_mesh(relative: bool) -> ArrayMesh:
	var base := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	var nrm := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = base
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	# klíč A: vrchol 2 o +0,5 z; klíč B: vše o +0,2 x
	var da := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 0.5), Vector3.ZERO])
	var db := PackedVector3Array([Vector3(0.2, 0, 0), Vector3(0.2, 0, 0), Vector3(0.2, 0, 0), Vector3(0.2, 0, 0)])
	var shapes: Array = []
	for d in [da, db]:
		var s := []
		s.resize(Mesh.ARRAY_MAX)
		var p := PackedVector3Array()
		for i in 4:
			p.append(d[i] if relative else base[i] + d[i])
		s[Mesh.ARRAY_VERTEX] = p
		# NORMALIZED: cílová normála = základní; RELATIVE: „žádná změna“ nejde zakódovat – uloží se (0,0,1)
		s[Mesh.ARRAY_NORMAL] = nrm.duplicate()
		shapes.append(s)
	var m := ArrayMesh.new()
	m.add_blend_shape("a")
	m.add_blend_shape("b")
	m.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE if relative else Mesh.BLEND_SHAPE_MODE_NORMALIZED
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, shapes, {}, 0)
	return m


func _test_relative_bake() -> void:
	section("LodBake – režim RELATIVE = shader Godotu")
	var w := PackedFloat32Array([0.5, -0.3])
	var rel := _syn_mesh(true)
	var nor := _syn_mesh(false)
	var raw := LodBake.raw_of(rel)
	check(bool(raw.get("relative", false)) and not bool(LodBake.raw_of(nor).get("relative", true)), "raw_of zaznamená režim sítě")
	var br := LodBake.bake(LodBake.build_source(raw), w)
	var bnz := LodBake.bake(LodBake.build_source(LodBake.raw_of(nor)), w)
	if not check(br != null and bnz != null, "obě sítě zapečené"):
		return
	var expect := PackedVector3Array([Vector3(-0.06, 0, 0), Vector3(0.94, 0, 0), Vector3(0.94, 1, 0.25), Vector3(-0.06, 1, 0)])
	var pr: PackedVector3Array = br.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = bnz.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(_max_err(pr, expect) < 1e-5, "RELATIVE: v = base + Σ w·delta (analyticky, chyba %.7f)" % _max_err(pr, expect))
	check(_max_err(pn, expect) < 1e-5, "NORMALIZED s absolutními cíli: tytéž polohy (chyba %.7f)" % _max_err(pn, expect))
	var g := _gpu(rel, w)
	check(_max_err(pr, g[0]) < 1e-5, "RELATIVE: polohy = nezávislá reprodukce shaderu")
	var nr: PackedVector3Array = br.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check(_max_angle(nr, g[1]) < 0.5, "RELATIVE: normály = shader (n + Σ w·n_cíl, odchylka %.3f°)" % _max_angle(nr, g[1]))
	var nn: PackedVector3Array = bnz.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check(_max_angle(nn, PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])) < 0.5,
		"NORMALIZED: cílová normála = základní → normály beze změny")
	# staré chování (base + w·(cíl − base) nad delta cíli) by vrchol 2 stáhlo jinam – ověřit, že ho nereprodukujeme
	var wrong := Vector3(1, 1, 0) + (Vector3(0, 0, 0.5) - Vector3(1, 1, 0)) * 0.5 + (Vector3(0.2, 0, 0) - Vector3(1, 1, 0)) * -0.3
	check(pr[2].distance_to(wrong) > 0.1, "RELATIVE se nepočítá jako NORMALIZED (dřívější chyba kroku 6)")


# ------------------------------------------------------------------ 2) builder

func _test_builders(v) -> void:
	section("Procedurální sítě – absolutní cíle, normály tělesných morfů")
	check(v.set_hand_pose("open"), "otevřená ruka (ohyby prstů 0)")
	var parts := _procedural(v)
	check(parts.size() >= 4, "%d procedurálních instancí (trup: %s)" % [parts.size(), str(v.torso_details_available())])
	for mi in parts:
		var m := mi.mesh as ArrayMesh
		var label := String(mi.name)
		check(m.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, label + ": BLEND_SHAPE_MODE_NORMALIZED")
		var base_n: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var bl := m.surface_get_blend_shape_arrays(0)
		var worst := 0.0
		for k in mini(10, bl.size()):
			worst = maxf(worst, _max_angle(bl[k][Mesh.ARRAY_NORMAL], base_n))
		check(worst < 0.5, label + ": cílové normály tělesných morfů = základní (max %.3f°)" % worst)
		var w := _weights(mi)
		var active := 0
		for k in mini(10, w.size()):
			if absf(w[k]) > 0.0001:
				active += 1
		var g := _gpu(m, w)
		var tilt := _max_angle(g[1], base_n)
		check(active > 0 and tilt < 0.5, label + ": GPU normály s %d aktivními tělesnými morfy beze změny (max %.3f°)" % [active, tilt])
		var dok := true
		var rest: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in [0, mini(9, bl.size() - 1)]:
			var tv: PackedVector3Array = bl[k][Mesh.ARRAY_VERTEX]
			for i in range(0, rest.size(), maxi(1, rest.size() / 12)):
				dok = dok and Hand.morph_delta(m, k, i).distance_to(tv[i] - rest[i]) < 1e-6
		check(dok, label + ": morph_delta = cíl − klid")
	# ohyb prstu mění jen svůj prst (absolutní cíle: ostatní vrcholy = klid)
	var skin: MeshInstance3D = v._hand_detail_nodes[0]
	var sm := skin.mesh as ArrayMesh
	var spill := 0
	var moved := 0
	var rest_s: PackedVector3Array = sm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bls := sm.surface_get_blend_shape_arrays(0)
	var n := rest_s.size()
	var chunk := n / Hand.DIGIT_COUNT
	for digit in Hand.DIGIT_COUNT:
		var k := skin.find_blend_shape_by_name(Hand.curl_key(digit))
		var tv: PackedVector3Array = bls[k][Mesh.ARRAY_VERTEX]
		for i in n:
			var d := (tv[i] - rest_s[i]).length()
			if i / chunk == digit:
				moved += int(d > 1e-5)
			elif d > 1e-7:
				spill += 1
	check(chunk == Hand.SKIN_PER_DIGIT and moved > 10 * 20 and spill == 0,
		"ohyb prstu hýbe jen svým prstem (%d posunutých vrcholů, únik %d)" % [moved, spill])


# ------------------------------------------------------------------ 3) geometrické LOD

func _test_geometry_lod(v) -> void:
	section("Geometrické LOD procedurálních sítí")
	for mi in [v._hand_detail_nodes[0], v._foot_detail_nodes[0]]:
		var m := mi.mesh as ArrayMesh
		var label := String(mi.name)
		var counts := CL.lod_triangle_counts(m)
		var full := m.surface_get_array_index_len(0) / 3
		var dec := counts.size() > 0 and counts[0] < full
		for i in range(1, counts.size()):
			dec = dec and counts[i] < counts[i - 1]
		check(dec, label + ": LOD %d → %s trojúhelníků" % [full, str(counts)])
		var arrays := m.surface_get_arrays(0)
		var ids := CL._weld_ids(arrays[Mesh.ARRAY_VERTEX])
		var border := CL._border_edges(arrays[Mesh.ARRAY_INDEX], ids)
		var same := true
		for e in LodBake.rs_lods(m, 0).keys():
			same = same and CL._same_border(border, LodBake.rs_lods(m, 0)[e], ids)
		check(same and border.size() > 0, label + ": každá úroveň má stejnou hranici (%d hraničních hran)" % border.size())
	var nails: MeshInstance3D = v._hand_detail_nodes[1]
	check(CL.lod_count(nails.mesh) == 0, "nehty (80 tr.) bez LOD – pod prahem %d" % CL.MIN_TRIS)
	var hm := v._hand_detail_nodes[0].mesh as ArrayMesh
	check(hm.get_blend_shape_count() == 40 and hm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 10 * Hand.SKIN_PER_DIGIT,
		"LOD síť prstů: 40 klíčů, %d vrcholů (sdílené – morfy a pózy beze změny)" % (10 * Hand.SKIN_PER_DIGIT))


# ------------------------------------------------------------------ 4) stupeň 2

func _test_tier2(v) -> void:
	section("Stupeň 2 – zapečení procedurálních dílů")
	check(v.set_finger_joint_bend("l", 1, "proximal", 0.37) and v.set_finger_curl("r", 4, 0.6), "vlastní póza prstů")
	var fv_before: Dictionary = v.finger_joint_values("l", 1)
	var parts: Array = []
	for mi in _procedural(v):
		if mi.is_visible_in_tree():
			parts.append(mi)
	var src := {}
	var wts := {}
	for mi in parts:
		src[mi] = mi.mesh
		wts[mi] = _weights(mi)
	check(parts.size() >= 4, "viditelné procedurální díly: %s" % str(parts.map(func(x): return String(x.name))))
	_place_cam(80.0)
	var ok := await wait_until(func(): return v.lod_tier() == 2 and v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	check(ok, "stupeň 2: zapečeno (%d instancí, úloha %.1f ms)" % [v.lod_baked_count(), LodBake.last_job_ms])
	var all_baked := true
	var worst := 0.0
	var worst_n := 0.0
	for mi in parts:
		if not _baked(v, mi):
			all_baked = false
			continue
		var g := _gpu(src[mi], wts[mi])
		var a: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		worst = maxf(worst, _max_err(a[Mesh.ARRAY_VERTEX], g[0]))
		worst_n = maxf(worst_n, _max_angle(a[Mesh.ARRAY_NORMAL], g[1]))
	check(all_baked, "zapečené jsou i ruce, nehty, chodidla a trup")
	check(worst < 2e-5 and worst_n < 1.0, "zapečené díly = vzorec GPU (poloha %.7f m, normála %.3f°)" % [worst, worst_n])
	var hand: MeshInstance3D = v._hand_detail_nodes[0]
	check(LodBake.rs_lods(hand.mesh, 0) == LodBake.rs_lods(src[hand], 0) and not LodBake.rs_lods(hand.mesh, 0).is_empty(),
		"zapečené prsty nesou stejné LOD indexy")
	var baked_n: int = v.lod_baked_count()
	check(v.finger_joint_values("l", 1) == fv_before and v.lod_baked_count() == baked_n,
		"finger_joint_values čte zapečený stav bez rozpečení (%s)" % str(fv_before))
	check(v.lod_blend_value(hand, &"no_such_key") == null and v.lod_blend_value(hand, Hand.joint_key(6, "proximal")) == fv_before.get("proximal"),
		"lod_blend_value: neznámý klíč = null, známý = uložená váha")
	# póza ve stupni 2
	var bakes0 := int(v.lod_bakes)
	var others0: int = v.lod_baked_count() - int(_baked(v, hand)) - int(_baked(v, v._hand_detail_nodes[1]))
	check(v.set_hand_pose("fist"), "set_hand_pose ve stupni 2")
	check(v.lod_baked_count() == others0 and others0 > 5, "póza rozpekla jen ruce – zbylých %d dílů zůstává zapečených" % others0)
	check(not _baked(v, hand) and hand.mesh == src[hand], "póza rozpekla ruku – původní síť s blend shapes")
	var ci := hand.find_blend_shape_by_name(Hand.curl_key(0))
	check(ci >= 0 and is_equal_approx(hand.get_blend_shape_value(ci), 1.0), "póza fist zapsaná do vah")
	ok = await wait_until(func(): return _baked(v, hand) and not v.lod_bake_pending(), 15.0)
	check(ok and int(v.lod_bakes) > bakes0, "po klidu znovu zapečeno")
	var fw: PackedFloat32Array = v._lb_entries[hand][2] if _baked(v, hand) else PackedFloat32Array()
	var g2 := _gpu(src[hand], fw)
	var e2 := _max_err((hand.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], g2[0])
	check(e2 < 2e-5 and fw.size() > ci and absf(fw[ci] - 1.0) < 1e-6, "zapečená pěst = GPU s vahami pózy (chyba %.7f m)" % e2)
	check(v.set_finger_joint_bend("l", 0, "distal", 0.4) and not _baked(v, hand), "set_finger_joint_bend rozpeče a zapíše")
	await wait_until(func(): return _baked(v, hand) and not v.lod_bake_pending(), 15.0)
	# kostra prstů (ruce skryté) a zpět → ruce znovu zapečené
	var sk_ok: bool = v.set_finger_skeletal_view(true)
	check(sk_ok and not hand.visible, "kostra článků prstů ve stupni 2 (sítě rukou skryté)")
	check(v.set_finger_skeletal_view(false) and hand.visible, "kostra vypnutá, ruce zase vidět")
	ok = await wait_until(func(): return _baked(v, hand) and not v.lod_bake_pending(), 15.0)
	check(ok, "ruce po návratu z kostry zapečené")
	var final_w := {}
	for mi in parts:
		final_w[mi] = v._lb_entries[mi][2] if _baked(v, mi) else _weights(mi)
	# návrat
	_place_cam(3.0)
	await wait_seconds(0.4)
	var same := true
	var bad := ""
	for mi in parts:
		if mi.mesh != src[mi] or _weights(mi) != final_w[mi]:
			same = false
			bad = String(mi.name)
	check(v.lod_tier() == 0 and v.lod_baked_count() == 0 and same, "stupeň 0: původní sítě a přesné váhy %s" % bad)
	check(v.finger_joint_values("l", 0).get("distal") != null and is_equal_approx(float(v.finger_joint_values("l", 0)["distal"]), 0.4),
		"póza nastavená ve stupni 2 platí i blízko")
	var t0 := Time.get_ticks_usec()
	var hb := LodBake.bake_now(src[hand], final_w[hand])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(hb != null and ms < 40.0, "pečení prstů (teplá cache delt) %.2f ms" % ms)
	print("[perf] finger bake warm %.2f ms" % ms)
	v.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ 5) sprcha ve stupni 2

func _test_shower_refresh() -> void:
	section("Viditelnost ve stupni 2 (sprcha)")
	var v = await _new_visual(_look(11, "tenisky", "tricko"))
	var foot: MeshInstance3D = v._foot_detail_nodes[0] if v._foot_detail_nodes.size() > 0 else null
	if not check(foot != null and not foot.is_visible_in_tree(), "obutá postava: chodidla skrytá"):
		v.queue_free()
		return
	v.lod_override = 2
	var ok := await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	check(ok and not _baked(v, foot), "stupeň 2 zapečen, skrytá chodidla ne")
	var n0: int = v.lod_baked_count()
	v._update_shower_garments(true)
	check(foot.is_visible_in_tree() and v.lod_bake_pending() and v.lod_baked_count() == n0,
		"sprcha: chodidla vidět, pečení naplánované bez rozpečení ostatních (%d)" % v.lod_baked_count())
	ok = await wait_until(func(): return _baked(v, foot) and not v.lod_bake_pending(), 15.0)
	var g := _gpu(v._lb_entries[foot][0], v._lb_entries[foot][2]) if ok else []
	check(ok and _max_err((foot.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], g[0]) < 2e-5,
		"chodidla ve sprše dopečena = GPU")
	v._update_shower_garments(false)
	check(not foot.is_visible_in_tree(), "po sprše chodidla zase skrytá")
	v.lod_override = 0
	await wait_seconds(0.4)
	check(v.lod_baked_count() == 0 and foot.mesh == v.lod_source_mesh(foot) and foot.mesh.get_blend_shape_count() == 10,
		"stupeň 0: chodidla s původní sítí")
	v.queue_free()
	await get_tree().process_frame
