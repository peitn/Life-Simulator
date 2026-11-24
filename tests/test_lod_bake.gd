extends "res://tests/test_base.gd"
## C-LOD krok 6 (18. 11. 2026): zapečení blend shapes ve stupni 2 (LodBake + SimVisual).
## 1) Syntetická síť: polohy = base + Σ w·(cíl − base) (nezávislý hustý výpočet), normály/tečny jednotkové,
##    UV/kosti/váhy/CUSTOM0/indexy beze změny, 0 blend shapes, nulové a neplatné váhy, řídké delty.
## 2) Skutečná hlava náhodné postavy: přesnost proti hustému vzorci, LOD indexy, formát, materiál, čas.
## 3) SimVisual: zapečení až po klidu ve stupni 2, od kroku 7 i ruce (póza ruku rozpeče), jediné pečení (žádné opakování), návrat do
##    stupně 0 vrátí stejné sítě a přesně stejné váhy, apply_look/výraz ve stupni 2 zapečení zruší a obnoví
##    s novými vahami, zastaralá úloha se zahodí, uvolnění uzlu s běžící úlohou, vypnutí.

const LodBake := preload("res://scripts/assets/lod_bake.gd")
const CL := preload("res://scripts/assets/character_lod.gd")
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
	_test_synthetic()
	await _test_visual()
	await _test_free_during_job()
	await _test_disabled()
	finish("test_lod_bake")


# ------------------------------------------------------------------ pomocné

func _look(seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cd = CharacterData.create()
	cd.set_from_dict(Randomizer.generate(rng))
	return cd.public_snapshot()


func _place_cam(d: float) -> void:
	cam.look_at_from_position(Vector3(0, 1.0, d), Vector3(0, 1.0, 0))


## Nezávislý hustý výpočet polohy (bez řídkých delt LodBake).
func _dense(m: ArrayMesh, w: PackedFloat32Array) -> PackedVector3Array:
	var base: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var out := base.duplicate()
	var bl: Array = m.surface_get_blend_shape_arrays(0)
	for k in w.size():
		if w[k] == 0.0:
			continue
		var tgt: PackedVector3Array = bl[k][Mesh.ARRAY_VERTEX]
		for i in base.size():
			out[i] += (tgt[i] - base[i]) * w[k]
	return out


func _max_err(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var e := 0.0
	for i in a.size():
		e = maxf(e, a[i].distance_to(b[i]))
	return e


func _weights(mi: MeshInstance3D) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for i in mi.get_blend_shape_count():
		w.append(mi.get_blend_shape_value(i))
	return w


func _head(v) -> MeshInstance3D:
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "head__face__skin_body":
			return mi
	return null


## Viditelné instance s blend shapes (od C-LOD kroku 7 včetně rukou).
func _shaped_visible(v) -> Array:
	var out: Array = []
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh is ArrayMesh and v.lod_source_mesh(mi).get_blend_shape_count() > 0:
			out.append(mi)
	return out


func _new_visual(look: Dictionary) -> Node3D:
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(look)
	await wait_until(func(): return not v.hair_waiting() and not v.wardrobe_waiting(), 30.0)
	return v


# ------------------------------------------------------------------ 1) syntetická síť

func _test_synthetic() -> void:
	section("LodBake – syntetická síť")
	var base := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	var nrm := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var tan := PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, -1])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var bones := PackedInt32Array([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
	var bw := PackedFloat32Array([0.7, 0.3, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0.5, 0.5, 0, 0])
	var c0 := PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = base
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = bw
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_INDEX] = idx
	# klíč A hýbe jen vrcholem 2 (+z a naklání normálu), klíč B posouvá vše o +x
	var a := base.duplicate()
	a[2] = Vector3(1, 1, 0.5)
	var an := nrm.duplicate()
	an[2] = Vector3(0.6, 0, 0.8)
	var b := base.duplicate()
	for i in b.size():
		b[i] += Vector3(0.2, 0, 0)
	var blend_a := []
	blend_a.resize(Mesh.ARRAY_MAX)
	blend_a[Mesh.ARRAY_VERTEX] = a
	blend_a[Mesh.ARRAY_NORMAL] = an
	blend_a[Mesh.ARRAY_TANGENT] = tan
	var blend_b := []
	blend_b.resize(Mesh.ARRAY_MAX)
	blend_b[Mesh.ARRAY_VERTEX] = b
	blend_b[Mesh.ARRAY_NORMAL] = nrm
	blend_b[Mesh.ARRAY_TANGENT] = tan
	var m := ArrayMesh.new()
	m.add_blend_shape("a")
	m.add_blend_shape("b")
	m.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [blend_a, blend_b], {}, fmt)
	var mat := StandardMaterial3D.new()
	m.surface_set_material(0, mat)
	m.surface_set_name(0, "syn")
	var src := LodBake.build_source(LodBake.raw_of(m))
	var shapes: Array = src["surfaces"][0]["shapes"]
	check((shapes[0][0] as PackedInt32Array) == PackedInt32Array([2]) and (shapes[1][0] as PackedInt32Array).size() == 4,
		"řídké delty: klíč A jen vrchol 2, klíč B všechny 4")
	var w := PackedFloat32Array([0.5, -0.3])
	var out := LodBake.bake(src, w)
	if not check(out != null and out.get_surface_count() == 1, "zapečená síť vznikla"):
		return
	var oa := out.surface_get_arrays(0)
	var exp := _dense(m, w)
	check(_max_err(oa[Mesh.ARRAY_VERTEX], exp) < 1e-5, "polohy = base + Σ w·(cíl − base), i záporná váha (chyba %.7f)" % _max_err(oa[Mesh.ARRAY_VERTEX], exp))
	var n2: Vector3 = (oa[Mesh.ARRAY_NORMAL] as PackedVector3Array)[2]
	var en := (Vector3(0, 0, 1) + (Vector3(0.6, 0, 0.8) - Vector3(0, 0, 1)) * 0.5).normalized()
	check(n2.distance_to(en) < 2e-3 and absf(n2.length() - 1.0) < 2e-3, "normála smíchaná a normalizovaná (%s vs %s)" % [n2, en])
	var unit := true
	for v3 in (oa[Mesh.ARRAY_NORMAL] as PackedVector3Array):
		unit = unit and absf(v3.length() - 1.0) < 2e-3
	check(unit, "všechny normály jednotkové")
	var ot: PackedFloat32Array = oa[Mesh.ARRAY_TANGENT]
	check(ot.size() == 16 and ot[15] == -1.0 and ot[3] == 1.0, "znaménko bitangenty (w) tečen zachováno")
	check(oa[Mesh.ARRAY_TEX_UV] == uv and oa[Mesh.ARRAY_BONES] == bones and oa[Mesh.ARRAY_INDEX] == idx,
		"UV, kosti a indexy beze změny")
	var ow: PackedFloat32Array = oa[Mesh.ARRAY_WEIGHTS]
	var wok := ow.size() == bw.size()
	for i in mini(ow.size(), bw.size()):
		wok = wok and absf(ow[i] - bw[i]) < 1e-3
	check(wok, "váhy kostí beze změny")
	var oc: PackedFloat32Array = oa[Mesh.ARRAY_CUSTOM0]
	check(oc == c0, "CUSTOM0 (klidové polohy pro shader kůže) beze změny")
	check(out.get_blend_shape_count() == 0, "zapečená síť nemá blend shapes")
	check(out.surface_get_material(0) == mat and out.surface_get_name(0) == "syn", "materiál a jméno plochy zachované")
	check((out.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "formát nese CUSTOM0")
	var z := LodBake.bake(src, PackedFloat32Array([0.0, 0.0]))
	check(_max_err(z.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], base) < 1e-6, "nulové váhy = základní tvar")
	var bad := LodBake.bake(src, PackedFloat32Array([NAN, INF]))
	check(bad != null and _max_err(bad.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], base) < 1e-6, "NaN/INF váhy se neaplikují (žádné NaN v síti)")
	var short := LodBake.bake(src, PackedFloat32Array([1.0]))
	var e1 := base.duplicate()
	e1[2] = Vector3(1, 1, 0.5)
	check(_max_err(short.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], e1) < 1e-6, "kratší pole vah: chybějící klíče = 0")
	check(LodBake.build_source({}).is_empty() and LodBake.bake({}, w) == null and LodBake.raw_of(null).is_empty(),
		"prázdný vstup → nic, bez pádu")
	var plain := ArrayMesh.new()
	plain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	check(LodBake.bake_now(plain, PackedFloat32Array()) == null, "síť bez blend shapes se nepeče")
	# cache zapečených sítí: stejná síť + stejné váhy = stejný objekt, jiné váhy = nic
	LodBake.store_baked(m, w, out)
	check(LodBake.baked_cached(m, w) == out and LodBake.baked_cached(m, PackedFloat32Array([0.5, -0.2])) == null,
		"cache zapečených sítí podle přesných vah")
	# mrtvé záznamy se průběžně pročistí (Gemini 18. 11.)
	for i in 64:
		LodBake.store_baked(m, PackedFloat32Array([float(i), 0.0]), LodBake.bake(src, PackedFloat32Array([0.0, 0.0])))
	check(LodBake.cache_sizes().y <= 33, "cache zapečených sítí se pročišťuje od uvolněných sítí (%d záznamů po 64 dočasných)" % LodBake.cache_sizes().y)


# ------------------------------------------------------------------ 2) + 3) skutečná postava

## Zapečená hlava proti referenci: (1) síť = hustý výpočet z vah, se kterými se pekla; (2) tvarové váhy
## (vše kromě mimiky ex_* – mrkání reference běží) = váhy referenční postavy. Vrací max. odchylku (m) nebo INF.
func _baked_vs_ref(v, head: MeshInstance3D, hm: ArrayMesh, rhead: MeshInstance3D) -> float:
	if not v._lb_entries.has(head) or head.mesh != v._lb_entries[head][1]:
		return INF
	var used: PackedFloat32Array = v._lb_entries[head][2]
	var e := _max_err(head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _dense(hm, used))
	var rw := _weights(rhead)
	var mixed := used.duplicate()
	for i in mini(rw.size(), used.size()):
		if not String(hm.get_blend_shape_name(i)).begins_with("ex_"):
			mixed[i] = rw[i]
	return maxf(e, _max_err(_dense(hm, used), _dense(hm, mixed)))


func _test_visual() -> void:
	section("Skutečná hlava – přesnost")
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	_place_cam(3.0)
	var look_a := _look(7)
	var v = await _new_visual(look_a)
	await wait_seconds(0.3)
	if not check(v._model != null and v.lod_tier() == 0, "postava s modelem ve stupni 0"):
		return
	var head := _head(v)
	if not check(head != null, "síť hlavy nalezena"):
		return
	var hm := head.mesh as ArrayMesh
	var hw := _weights(head)
	var active := 0
	for x in hw:
		if absf(x) > 1e-5:
			active += 1
	check(active >= 10, "náhodná postava má na hlavě aktivních %d klíčů" % active)
	LodBake.clear_cache()
	var t0 := Time.get_ticks_usec()
	var baked := LodBake.bake_now(hm, hw)
	var cold_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var baked2 := LodBake.bake_now(hm, hw)
	var warm_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not check(baked != null and baked2 != null, "hlava zapečená"):
		return
	var err := _max_err(baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _dense(hm, hw))
	check(_max_err(baked2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]) < 1e-7, "opakované pečení dá totéž (zdroj se pečením nemění)")
	check(err < 1e-4, "hlava: polohy proti hustému vzorci, chyba %.7f m (< 0,1 mm, komprese atributů)" % err)
	check(CL.lod_triangle_counts(baked) == CL.lod_triangle_counts(hm) and CL.lod_triangle_counts(hm).size() > 0,
		"hlava: stejné LOD indexy (%s)" % str(CL.lod_triangle_counts(hm)))
	check(baked.surface_get_format(0) & ~Mesh.ARRAY_FORMAT_BLEND_SHAPE_MASK == hm.surface_get_format(0) & ~Mesh.ARRAY_FORMAT_BLEND_SHAPE_MASK,
		"hlava: formát plochy stejný (%x vs %x)" % [baked.surface_get_format(0), hm.surface_get_format(0)])
	check(baked.surface_get_material(0) == hm.surface_get_material(0), "hlava: materiál stejný")
	check(LodBake.rs_lods(baked, 0) == LodBake.rs_lods(hm, 0) and not LodBake.rs_lods(hm, 0).is_empty(), "hlava: obsah LOD indexů bit po bitu stejný (dekódování z RenderingServeru)")
	var c0a = hm.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	var c0b = baked.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	check(c0a == c0b, "hlava: CUSTOM0 beze změny")
	check(warm_ms < 120.0, "hlava: pečení s hotovými deltami %.1f ms (studené %.1f ms)" % [warm_ms, cold_ms])
	print("[perf] head bake cold %.1f ms, warm %.1f ms, active %d" % [cold_ms, warm_ms, active])

	section("SimVisual – zapečení ve stupni 2")
	var before := {}
	var meshes := {}
	var mats := {}
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		var ov: Array = []
		for s in mi.get_surface_override_material_count():
			ov.append(mi.get_surface_override_material(s))
		mats[mi] = [mi.material_override, ov, mi.skin, mi.skeleton]
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh and mi.mesh.get_blend_shape_count() > 0:
			before[mi] = _weights(mi)
			meshes[mi] = mi.mesh
	_place_cam(80.0)
	await wait_seconds(0.3)
	check(v.lod_tier() == 2 and v.lod_baked_count() == 0, "stupeň 2: hned po přechodu ještě nezapečeno (klid %.1f s)" % v.LOD_BAKE_DELAY)
	var ok := await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	check(ok, "po klidu zapečeno (%d instancí, úloha %.1f ms)" % [v.lod_baked_count(), LodBake.last_job_ms])
	var shaped := _shaped_visible(v)
	var all_static := true
	var left := 0
	for mi in shaped:
		if mi.mesh.get_blend_shape_count() != 0:
			all_static = false
			left += 1
	check(all_static and shaped.size() == v.lod_baked_count(), "všechny viditelné sítě s klíči (i ruce) zapečené: %d/%d" % [shaped.size() - left, shaped.size()])
	var hands_ok := true
	for mi in v._hand_detail_nodes:
		hands_ok = hands_ok and v._lb_entries.has(mi) and (mi as MeshInstance3D).mesh == v._lb_entries[mi][1]
	check(hands_ok, "ruce zapečené také (C-LOD krok 7)")
	check(v.set_hand_pose("fist") and v.hand_pose_name() == "fist", "póza ruky ve stupni 2 funguje")
	check(v.lod_source_mesh(head) == hm and head.mesh != hm, "lod_source_mesh vrací původní síť hlavy")
	var mats_ok := true
	for mi in mats:
		if not is_instance_valid(mi):
			continue
		var ov: Array = []
		for s in mi.get_surface_override_material_count():
			ov.append(mi.get_surface_override_material(s))
		if [mi.material_override, ov, mi.skin, mi.skeleton] != mats[mi]:
			mats_ok = false
	check(mats_ok, "zapečení zachová materiály instancí (override i plošné), Skin a kostru")
	var herr := _max_err(head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _dense(hm, before[head]))
	check(herr < 1e-4, "zapečená hlava ve hře = tvar postavy (chyba %.7f m)" % herr)
	# cena na hlavním vlákně při teplé cache (sběr instancí a vah, spuštění úlohy)
	v._lod_touch()
	var ts := Time.get_ticks_usec()
	v._lod_bake_start()
	var start_ms := (Time.get_ticks_usec() - ts) / 1000.0
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	ts = Time.get_ticks_usec()
	v._lod_touch()
	var unbake_ms := (Time.get_ticks_usec() - ts) / 1000.0
	check(start_ms < 8.0 and unbake_ms < 8.0, "hlavní vlákno: start pečení %.2f ms, zrušení %.2f ms (< 8 ms)" % [start_ms, unbake_ms])
	print("[perf] start %.2f ms, unbake %.2f ms, job %.1f ms" % [start_ms, unbake_ms, LodBake.last_job_ms])
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	v.lod_bakes = 1
	var bakes := int(v.lod_bakes)
	await wait_seconds(2.0)
	check(int(v.lod_bakes) == bakes and bakes == 1, "klid 2 s: žádné opakované pečení (%d)" % int(v.lod_bakes))
	# zpět blízko → původní sítě i váhy
	_place_cam(3.0)
	await wait_seconds(0.4)
	var same := true
	var detail := ""
	for mi in before:
		if not is_instance_valid(mi):
			continue
		if mi.mesh != meshes[mi] or _weights(mi) != before[mi]:
			# ruce: póza fist změnila váhy prstů záměrně
			if v._hand_detail_nodes.has(mi):
				continue
			same = false
			detail = String(mi.name)
	check(v.lod_tier() == 0 and v.lod_baked_count() == 0 and same, "stupeň 0: stejné sítě a přesně stejné váhy " + detail)
	var exn: int = v.update_expression(0.016)
	check(exn >= 0, "mimika ve stupni 0 zase běží")

	section("SimVisual – změny ve stupni 2")
	_place_cam(80.0)
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	var bakes0 := int(v.lod_bakes)
	var old_baked := head.mesh
	var look_b := _look(1234)
	v.apply_look(look_b)
	check(v.lod_baked_count() == 0 and head.mesh == hm, "apply_look ve stupni 2 hned vrátí původní síti (nové váhy)")
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending() and not v.hair_waiting(), 20.0)
	check(int(v.lod_bakes) > bakes0 and head.mesh != old_baked and head.mesh != hm, "nový vzhled se zapekl znovu")
	# referenční postava se stejným vzhledem ve stupni 0
	var ref = await _new_visual(look_b)
	ref.lod_override = 0
	await wait_seconds(0.3)
	var rerr := _baked_vs_ref(v, head, hm, _head(ref))
	check(rerr < 1e-4, "zapečený nový vzhled = referenční postava ve stupni 0 (chyba %.7f m)" % rerr)
	# výraz ve stupni 2 (cutscéna)
	var errs_before := _failed
	var n: int = v.set_expression({"ex_smile": 0.8})
	var si: int = head.find_blend_shape_by_name("ex_smile")
	check(v.lod_baked_count() == 0 and n >= 0 and (si < 0 or head.get_blend_shape_value(si) > 0.0),
		"set_expression ve stupni 2: zapečení zrušeno, výraz zapsán do původní sítě")
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending(), 15.0)
	check(v.lod_baked_count() > 0 and errs_before == _failed, "po výrazu se znovu zapeklo")
	# zastaralá úloha: spustit pečení a hned změnit vzhled
	v._lod_touch()
	v._lb_wait = 0.0
	var started := await wait_until(func(): return v._lb_task >= 0, 5.0)
	v.apply_look(look_a)
	await wait_until(func(): return v.lod_baked_count() > 0 and not v.lod_bake_pending() and not v.hair_waiting(), 20.0)
	var ref_a = await _new_visual(look_a)
	ref_a.lod_override = 0
	await wait_seconds(0.3)
	var aerr := _baked_vs_ref(v, head, hm, _head(ref_a))
	check(started and aerr < 1e-4, "zastaralá úloha zahozena: zapečený tvar odpovídá poslednímu vzhledu (chyba %.7f m)" % aerr)
	# sdílení: druhá postava se stejným vzhledem ve stupni 2 použije zapečené sítě z cache
	var hits := LodBake.cache_hits
	ref_a.lod_override = 2
	await wait_until(func(): return ref_a.lod_baked_count() > 0 and not ref_a.lod_bake_pending(), 15.0)
	check(LodBake.cache_hits > hits, "stejný vzhled = sdílené zapečené sítě (%d zásahů cache)" % (LodBake.cache_hits - hits))
	var same_w: bool = ref_a._lb_entries.has(_head(ref_a)) and v._lb_entries.has(head) and ref_a._lb_entries[_head(ref_a)][2] == v._lb_entries[head][2]
	check(not same_w or _head(ref_a).mesh == head.mesh, "stejné váhy hlavy → tentýž objekt sítě (váhy shodné: %s)" % same_w)
	for x in [v, ref, ref_a]:
		x.queue_free()
	await get_tree().process_frame


func _test_free_during_job() -> void:
	section("Uvolnění s běžící úlohou")
	var v = await _new_visual(_look(99))
	v.lod_override = 2
	await wait_seconds(0.05)
	LodBake.clear_cache()   # studené delty – úloha běží déle
	v._lod_touch()
	v._lb_wait = 0.0
	var started := await wait_until(func(): return v._lb_task >= 0, 5.0)
	v.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(started and not is_instance_valid(v), "uzel uvolněn během pečení bez pádu")


func _test_disabled() -> void:
	section("Vypnuto")
	LodBake.enabled = false
	var v = await _new_visual(_look(5))
	v.lod_override = 2
	await wait_seconds(1.0)
	check(v.lod_tier() == 2 and v.lod_baked_count() == 0, "LodBake.enabled = false: nic se nepeče")
	LodBake.enabled = true
	await wait_until(func(): return v.lod_baked_count() > 0, 10.0)
	check(v.lod_baked_count() > 0, "po zapnutí se zapeče")
	v.queue_free()
	await get_tree().process_frame
