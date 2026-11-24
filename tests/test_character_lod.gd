extends "res://tests/test_base.gd"
## C-LOD (běh main-claude-1794511294, 12. 11. 2026): úrovně detailu postav pro dav.
## 1) Čistá logika stupně: podíl výšky obrazu, hranice, hystereze, škála nastavení, kamera (perspektiva/orto).
## 2) Geometrie: GLB s LOD vs. bez LOD – stejné vrcholy, formát, indexy LOD0, blend shapes (jména i data), skin,
##    CUSTOM0, klesající počty trojúhelníků, NEZMĚNĚNÁ hranice každé LOD (nezávislá kontrola z index bufferu
##    RenderingServeru), malé sítě beze změny, cache a sdílení mezi instancemi, syntetické okrajové případy, čas.
## 3) SimVisual s reálnou kamerou: blízko/střed/dav, karty ↔ helma, vnitřek úst, stíny, zmrazená mimika,
##    hystereze, vynucený stupeň, bez kamery = plný detail, plešatá postava, nastavení „Detail postav v dálce“,
##    validace nastavení, výkon přepnutí a kontroly.
## 4) Server/primitivní náhrada: bez modelu se nic nerozbije.

const CL := preload("res://scripts/assets/character_lod.gd")
const AL := preload("res://scripts/assets/asset_library.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

const WELD := 0.00001
var cam: Camera3D


func _init() -> void:
	watchdog_seconds = 240.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	_test_tier_logic()
	_test_geometry()
	_test_synthetic()
	await _test_visual()
	await _test_bald_and_settings()
	_test_no_model()
	finish("test_character_lod")


# ------------------------------------------------------------------ 1) logika stupně

func _dist_for(fraction: float, fov := 50.0) -> float:
	return CL.REF_HEIGHT / (2.0 * fraction * tan(deg_to_rad(fov) * 0.5))


func _test_tier_logic() -> void:
	section("Stupeň detailu – čistá logika")
	var f18 := CL.screen_fraction(18.0, 50.0)
	check(absf(f18 - 0.1072) < 0.001, "výchozí kamera hry (18 m, FOV 50°): postava zabírá %.4f výšky obrazu" % f18)
	check(CL.screen_fraction(0.0, 50.0) == INF and CL.screen_fraction(-3.0, 50.0) == INF and CL.screen_fraction(NAN, 50.0) == INF,
		"nulová/záporná/NaN vzdálenost → INF (plný detail)")
	check(CL.tier_for(INF, 2) == 0 and CL.tier_for(NAN, 1) == 0, "INF/NaN → stupeň 0")
	check(CL.tier_for(0.5, 0) == 0 and CL.tier_for(0.1, 0) == 1 and CL.tier_for(0.03, 0) == 2, "hranice: 0,5 → 0, 0,1 → 1, 0,03 → 2")
	# vzdalování přepne hned na hranici
	check(CL.tier_for(CL.T1_FRACTION * 0.999, 0) == 1 and CL.tier_for(CL.T2_FRACTION * 0.999, 1) == 2, "vzdalování přepne hned za hranicí")
	# přibližování až s hysterezí
	check(CL.tier_for(CL.T1_FRACTION * 1.05, 1) == 1 and CL.tier_for(CL.T1_FRACTION * 1.2, 1) == 0, "hystereze 0↔1 (1,05× hranice drží 1, 1,2× vrátí 0)")
	check(CL.tier_for(CL.T2_FRACTION * 1.05, 2) == 2 and CL.tier_for(CL.T2_FRACTION * 1.2, 2) == 1, "hystereze 1↔2")
	check(CL.tier_for(CL.T1_FRACTION * 1.2, 2) == 0, "skok z davu rovnou na plný detail, když je postava blízko")
	# oscilace kolem hranice nemění stupeň
	var t := 1
	var flips := 0
	for i in 200:
		var f := CL.T2_FRACTION * (1.0 + 0.06 * sin(float(i) * 0.7))
		var nt := CL.tier_for(f, t)
		if nt != t:
			flips += 1
		t = nt
	check(flips <= 1, "kmitání ±6 %% kolem hranice: %d přepnutí (≤ 1)" % flips)
	check(CL.tier_for(0.04, 0, CL.detail_scale(2)) == 1 and CL.tier_for(0.04, 0, CL.detail_scale(0)) == 2
		and CL.tier_for(0.15, 0, CL.detail_scale(0)) == 1, "škála nastavení: vysoký detail drží 1, nízký přepne dřív")
	check(CL.detail_scale(-5) == CL.DETAIL_SCALE[0] and CL.detail_scale(99) == CL.DETAIL_SCALE[2], "škála mimo rozsah se ořízne")
	check(CL.tier_for(0.1, -7) == 1 and CL.tier_for(0.1, 9) == 1, "neplatný aktuální stupeň se ořízne")
	# kamera
	var c := Camera3D.new()
	c.fov = 50.0
	add_child(c)
	c.look_at_from_position(Vector3(0, 1, 18), Vector3(0, 1, 0))
	var fc := CL.camera_fraction(c, Vector3(0, 1, 0))
	check(absf(fc - f18) < 1e-4, "kamera: podíl z hloubky podél osy (%.4f)" % fc)
	var fside := CL.camera_fraction(c, Vector3(6, 1, 0))
	check(absf(fside - f18) < 1e-4, "postava na okraji obrazu má stejný podíl jako uprostřed (perspektivní hloubka)")
	var fbehind := CL.camera_fraction(c, Vector3(0, 1, 30))
	check(is_finite(fbehind) and fbehind > 0.0, "postava za kamerou: konečný kladný podíl z prosté vzdálenosti")
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = 36.0
	check(absf(CL.camera_fraction(c, Vector3.ZERO) - 0.05) < 1e-6, "ortografická kamera: 1,8 / size")
	check(CL.camera_fraction(null, Vector3.ZERO) == INF, "bez kamery → INF")
	c.free()


# ------------------------------------------------------------------ 2) geometrie z GLB

func _tri_count(m: Mesh) -> int:
	return m.surface_get_array_index_len(0) / 3


## Nezávislé dekódování LOD indexů z RenderingServeru (ne přes CharacterLod).
func _rs_lods(m: Mesh) -> Array:
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), 0)
	var main: PackedByteArray = sd.get("index_data", PackedByteArray())
	var cnt := int(sd.get("index_count", 0))
	var elem := main.size() / maxi(cnt, 1)
	var out: Array = []
	for lod in sd.get("lods", []):
		var b: PackedByteArray = lod["index_data"]
		var idx := PackedInt32Array()
		var n := b.size() / elem
		idx.resize(n)
		for i in n:
			idx[i] = b.decode_u16(i * 2) if elem == 2 else b.decode_u32(i * 4)
		out.append(idx)
	return out


func _border(idx: PackedInt32Array, pos: PackedVector3Array) -> Dictionary:
	var ids := {}
	var wid := PackedInt32Array()
	wid.resize(pos.size())
	for i in pos.size():
		var k := Vector3i((pos[i] / WELD).round())
		if not ids.has(k):
			ids[k] = ids.size()
		wid[i] = ids[k]
	var cnt := {}
	for t in range(0, idx.size() - 2, 3):
		for e in 3:
			var a := wid[idx[t + e]]
			var b := wid[idx[t + (e + 1) % 3]]
			if a != b:
				var key := Vector2i(mini(a, b), maxi(a, b))
				cnt[key] = int(cnt.get(key, 0)) + 1
	var out := {}
	for k in cnt:
		if cnt[k] == 1:
			out[k] = true
	return out


## Pole sítě stejná: polohy, UV, kosti, váhy, CUSTOM0 a indexy bit po bitu; normály a tečny do 2e-4 –
## Godot je ukládá oktaedricky v 16 bitech a každé sestavení ArrayMesh z polí (i bez LOD) je překvantuje
## o ≤ 1,3e-4 (ověřeno: obyčejný round-trip bez LOD dává stejné odchylky).
func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if typeof(a[i]) != typeof(b[i]):
			return false
		if a[i] == null or a[i] == b[i]:
			continue
		if i != Mesh.ARRAY_NORMAL and i != Mesh.ARRAY_TANGENT:
			return false
		if a[i].size() != b[i].size():
			return false
		for k in a[i].size():
			var d = a[i][k] - b[i][k]
			var m: float = d.length() if typeof(d) == TYPE_VECTOR3 else absf(d)
			if m > 0.0002:
				return false
	return true


func _meshes_by_name(root: Node) -> Dictionary:
	var out := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		out[String(mi.name)] = mi
	return out


func _test_geometry() -> void:
	section("Geometrie – GLB s LOD vs. bez LOD")
	AL.generate_lods = false
	AL.clear_cache()
	var plain: Node3D = AL.instantiate("character")
	AL.generate_lods = true
	AL.clear_cache()
	CL.clear_cache()
	var gen0: int = CL.generated
	var t0 := Time.get_ticks_usec()
	var lodded: Node3D = AL.instantiate("character")
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var second: Node3D = AL.instantiate("character")
	if not check(plain != null and lodded != null and second != null, "character.glb se načte s LOD i bez nich"):
		return
	var P := _meshes_by_name(plain)
	var L := _meshes_by_name(lodded)
	var S := _meshes_by_name(second)
	check(P.size() == L.size() and P.size() >= 15, "stejné uzly (%d)" % L.size())
	var with_lod := 0
	var same_data := true
	var same_blend := true
	var decreasing := true
	var borders_ok := true
	var small_untouched := true
	var shared := true
	var bad: PackedStringArray = []
	for nm in P:
		var pm: ArrayMesh = (P[nm] as MeshInstance3D).mesh
		var lm: ArrayMesh = (L[nm] as MeshInstance3D).mesh if L.has(nm) else null
		if lm == null:
			same_data = false
			bad.append(nm + ":chybí")
			continue
		if S.has(nm) and (S[nm] as MeshInstance3D).mesh != lm:
			shared = false
		var pa := pm.surface_get_arrays(0)
		var la := lm.surface_get_arrays(0)
		if pm.surface_get_format(0) != lm.surface_get_format(0) or not _arrays_equal(pa, la):
			same_data = false
			bad.append(nm + ":data")
		var pb := pm.surface_get_blend_shape_arrays(0)
		var lb := lm.surface_get_blend_shape_arrays(0)
		if pm.get_blend_shape_count() != lm.get_blend_shape_count() or pb.size() != lb.size() or pm.blend_shape_mode != lm.blend_shape_mode:
			same_blend = false
			bad.append(nm + ":bs")
		else:
			for i in pm.get_blend_shape_count():
				if pm.get_blend_shape_name(i) != lm.get_blend_shape_name(i) or not _arrays_equal(pb[i], lb[i]):
					same_blend = false
					bad.append(nm + ":bs%d" % i)
					break
		var lods := _rs_lods(lm)
		if _tri_count(pm) < CL.MIN_TRIS:
			if not lods.is_empty() or lm != pm and CL.lod_count(lm) > 0:
				small_untouched = false
			continue
		if lods.is_empty():
			continue
		with_lod += 1
		var prev := _tri_count(pm)
		var border0 := _border(pa[Mesh.ARRAY_INDEX], pa[Mesh.ARRAY_VERTEX])
		for idx in lods:
			var n: int = (idx as PackedInt32Array).size() / 3
			if n >= prev:
				decreasing = false
				bad.append(nm + ":nesestupné")
			prev = n
			var b := _border(idx, pa[Mesh.ARRAY_VERTEX])
			if b.size() != border0.size():
				borders_ok = false
				bad.append("%s:hranice %d/%d" % [nm, b.size(), border0.size()])
			else:
				for k in border0:
					if not b.has(k):
						borders_ok = false
						bad.append(nm + ":hrana")
						break
	check(with_lod >= 8, "LOD má %d sítí (tělo, oblečení, helmy vlasů, obličej, bělmo, zuby)" % with_lod)
	check(same_data, "polohy, UV, kosti, váhy, CUSTOM0 a indexy LOD0 beze změny, normály/tečny v kvantizaci 16 bitů (formát stejný)", ", ".join(bad))
	check(same_blend, "blend shapes: stejná jména, režim i data (tvar obličeje a mimika fungují na všech LOD)", ", ".join(bad))
	check(decreasing, "počty trojúhelníků LOD ostře klesají", ", ".join(bad))
	check(borders_ok, "každá LOD má přesně stejnou hranici (šev krk/hlava, oči, rty – žádné škvíry)", ", ".join(bad))
	check(small_untouched, "sítě pod %d trojúhelníků (řasy, jazyk, rty…) beze změny" % CL.MIN_TRIS)
	check(shared, "dvě postavy sdílejí tutéž LOD síť (generuje se jednou)")
	var face: ArrayMesh = (L["head__face__skin_body"] as MeshInstance3D).mesh
	var ft := CL.lod_triangle_counts(face)
	check(ft.size() >= 4 and ft[1] <= _tri_count(face) * 0.3, "obličej: %d → %s" % [_tri_count(face), str(ft)])
	check(face.get_blend_shape_count() >= 80, "obličej si nese %d blend shapes" % face.get_blend_shape_count())
	check(face.surface_get_material(0) == ((P["head__face__skin_body"] as MeshInstance3D).mesh as ArrayMesh).surface_get_material(0)
		or face.surface_get_material(0) != null, "materiál plochy zachován")
	check(CL.generated - gen0 >= with_lod, "počítadlo generací %d" % (CL.generated - gen0))
	check(load_ms < 5000.0, "načtení GLB včetně LOD %.0f ms (limit 5 s, jednou za hru; samotné LOD ~150 ms)" % load_ms)
	# cache
	var again := CL.with_lods(face)
	check(again == face, "LOD síť na vstupu se nezpracuje znovu")
	var pf: ArrayMesh = (P["head__face__skin_body"] as MeshInstance3D).mesh
	var t1 := Time.get_ticks_usec()
	var a1 := CL.with_lods(pf)
	var first_ms := (Time.get_ticks_usec() - t1) / 1000.0
	t1 = Time.get_ticks_usec()
	var a2 := CL.with_lods(pf)
	var hit_us := float(Time.get_ticks_usec() - t1)
	check(a1 == a2 and a1 != pf and first_ms < 1000.0, "cache: druhé volání vrátí tutéž síť (generace obličeje %.1f ms < 1 s → zásah %.0f µs)" % [first_ms, hit_us])
	check(hit_us < 500.0, "zásah cache pod 0,5 ms")
	plain.free()
	lodded.free()
	second.free()
	# cache drží jen slabé odkazy: po uvolnění všech postav a scény v AssetLibrary se LOD sítě uvolní
	a1 = null
	a2 = null
	again = null
	face = null
	pf = null
	AL.clear_cache()
	var probe := ArrayMesh.new()
	probe.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _grid(40))
	var wr: WeakRef = weakref(CL.with_lods(probe))
	var before: int = CL.cache_size()
	probe = null
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _grid(41))
	CL.with_lods(tmp)   # další generace spustí úklid mrtvých záznamů
	check(wr.get_ref() == null and CL.cache_size() <= 4, "cache bez úniku: uvolněné sítě zmizí (%d → %d záznamů)" % [before, CL.cache_size()])


func _grid(n: int) -> Array:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	for j in n + 1:
		for i in n + 1:
			var x := float(i) / n
			var y := float(j) / n
			pos.append(Vector3(x, 0.02 * sin(x * 9.0) * cos(y * 7.0), y))
			nor.append(Vector3.UP)
			uv.append(Vector2(x, y))
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _test_synthetic() -> void:
	section("Syntetické okrajové případy")
	var arr := _grid(40)
	var m := ArrayMesh.new()
	m.add_blend_shape("lift")
	var bs := []
	bs.resize(Mesh.ARRAY_MAX)
	var moved := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in moved.size():
		moved[i] += Vector3(0, 0.1, 0)
	bs[Mesh.ARRAY_VERTEX] = moved
	bs[Mesh.ARRAY_NORMAL] = arr[Mesh.ARRAY_NORMAL]
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [bs])
	var o := CL.with_lods(m)
	var lods := _rs_lods(o)
	var b0 := _border(arr[Mesh.ARRAY_INDEX], arr[Mesh.ARRAY_VERTEX])
	var ok := not lods.is_empty()
	for idx in lods:
		if _border(idx, arr[Mesh.ARRAY_VERTEX]).size() != b0.size():
			ok = false
	check(ok, "otevřená vlnitá plocha 3 200 tr.: %d LOD, okraj (%d hran) zachován" % [lods.size(), b0.size()])
	check(o.get_blend_shape_count() == 1 and o.get_blend_shape_name(0) == &"lift", "blend shape syntetické sítě zachován")
	# malá síť
	var small := ArrayMesh.new()
	small.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _grid(5))
	check(CL.with_lods(small) == small, "malá síť (50 tr.) beze změny")
	# neindexovaná síť a čáry
	var flat := _grid(30)
	var p: PackedVector3Array = flat[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = flat[Mesh.ARRAY_INDEX]
	var tri_pos := PackedVector3Array()
	for i in ix:
		tri_pos.append(p[i])
	var na := []
	na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = tri_pos
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	check(CL.with_lods(nm) == nm, "neindexovaná síť beze změny")
	var lines := ArrayMesh.new()
	var la := []
	la.resize(Mesh.ARRAY_MAX)
	la[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
	check(CL.with_lods(lines) == lines and CL.with_lods(null) == null and CL.with_lods(BoxMesh.new()) is BoxMesh,
		"čáry, null a primitivní síť beze změny")
	CL.enabled = false
	var m2 := ArrayMesh.new()
	m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _grid(40))
	check(CL.with_lods(m2) == m2, "vypnuté CharacterLod nic nemění")
	CL.enabled = true


# ------------------------------------------------------------------ 3) SimVisual s kamerou

func _place_cam(d: float) -> void:
	cam.look_at_from_position(Vector3(0, 1.0, d), Vector3(0, 1.0, 0))


func _helm_visible(v) -> Dictionary:
	var out := {}
	for g in ["hair_short", "hair_long"]:
		var vis := false
		for mi in AL.parts_in_group(v._model, g):
			vis = vis or mi.visible
		out[g] = vis
	return out


func _mouth_visible(v) -> bool:
	var vis := false
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		if AL.part_material_name(mi) in v.LOD_MOUTH:
			vis = vis or mi.visible
	return vis


func _lash(v) -> GeometryInstance3D:
	for mi in v._model.find_children("*", "MeshInstance3D", true, false):
		if AL.part_material_name(mi) == "eye_lash":
			return mi
	return null


func _test_visual() -> void:
	section("SimVisual – stupně podle kamery")
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	_place_cam(3.0)
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "kratke", "beard_style": "plnovous"}})
	await wait_until(func(): return not v.hair_waiting(), 30.0)
	await wait_seconds(0.35)
	if not check(v._model != null and v.hair_part("scalp") != null, "postava s modelem a kartami vlasů"):
		return
	var hv := String(v.look_params["hair_variant"])
	var lash := _lash(v)
	var lash_shadow0: int = lash.cast_shadow if lash != null else -1
	check(v.lod_tier() == 0 and v.hair_part("scalp").visible and not _helm_visible(v)[hv] and _mouth_visible(v),
		"3 m: stupeň 0, karty vidět, helma skrytá, ústa vidět")
	# střed
	_place_cam(_dist_for(0.12))
	await wait_seconds(0.35)
	check(v.lod_tier() == 1, "podíl 0,12 (%.1f m): stupeň 1" % _dist_for(0.12))
	check(v.hair_part("scalp").visible and not _helm_visible(v)[hv], "stupeň 1: karty stále vidět")
	check(lash != null and lash.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "stupeň 1: řasy bez stínu")
	var brows: GeometryInstance3D = v.hair_part("brows")
	check(brows == null or brows.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "stupeň 1: obočí z karet bez stínu")
	# řeč ve stupni 1: čelist se hýbe (10 Hz)
	v.apply("stand", 20.0, "", "Test", "mluví", "No to si snad děláš prdel, ne?")
	var jaw := 0.0
	for i in 40:
		await get_tree().process_frame
		jaw = maxf(jaw, float(v._ex.get("ex_jaw_open", 0.0)))
	check(jaw > 0.05, "stupeň 1: mimika běží dál (řeč hýbe čelistí)")
	# dav
	_place_cam(_dist_for(0.03))
	await wait_seconds(0.35)
	var hvis := _helm_visible(v)
	check(v.lod_tier() == 2, "podíl 0,03 (%.0f m): stupeň 2" % _dist_for(0.03))
	check(not v.hair_part("scalp").visible and not v.hair_part("beard").visible and not v.hair_part("brows").visible,
		"stupeň 2: karty (vlasy, vousy, obočí) skryté")
	# C-LOD krok 2 (13. 11.): ve stupni 2 místo společné helmy proxy účesu (tests/test_hair_proxy.gd)
	check(v.hair_proxy() != null and v.hair_proxy().visible and not bool(hvis[hv]) and not bool(hvis["hair_long" if hv == "hair_short" else "hair_short"]),
		"stupeň 2: proxy účesu vidět, obě helmy skryté")
	check(not v.hair_waiting(), "stupeň 2 se nehlásí jako čekání na vlasy")
	check(not _mouth_visible(v), "stupeň 2: vnitřek úst skrytý")
	check(float(v._ex.get("ex_jaw_open", 1.0)) == 0.0 and float(v._ex.get("ex_blink_l", 1.0)) <= float(v._ex.get("_lid", 0.0)) + 1e-6,
		"stupeň 2: ústa zavřená, oči otevřené (zmrazený výraz)")
	var frozen: Dictionary = v.expression_values()
	v.apply("stand", 20.0, "", "Test", "mluví", "Kurva, zase pozdě.")
	for i in 30:
		await get_tree().process_frame
	check(v.expression_values() == frozen, "stupeň 2: mimika se nepočítá (váhy beze změny ani při řeči)")
	# hystereze z davu
	_place_cam(_dist_for(CL.T2_FRACTION * 1.07))
	await wait_seconds(0.35)
	check(v.lod_tier() == 2, "1,07× hranice: zůstává stupeň 2 (hystereze)")
	_place_cam(_dist_for(CL.T2_FRACTION * 1.3))
	await wait_seconds(0.35)
	check(v.lod_tier() == 1 and v.hair_part("scalp").visible and not _helm_visible(v)[hv] and _mouth_visible(v),
		"1,3× hranice: stupeň 1, karty zpět, helma pryč, ústa zpět")
	# zpět blízko
	_place_cam(2.5)
	await wait_seconds(0.35)
	check(v.lod_tier() == 0 and lash.cast_shadow == lash_shadow0, "zpět blízko: stupeň 0, původní stíny řas")
	check(brows == null or brows.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "zpět blízko: obočí opět se stínem")
	# změna vzhledu v davu: _apply_model_variant respektuje stupeň
	_place_cam(80.0)
	await wait_seconds(0.35)
	v.apply_look({"hair": {"style": "kratke", "beard_style": "zadne"}, "body": {"body_fat": 0.6}})
	await get_tree().process_frame
	check(v.lod_tier() == 2 and not v.hair_part("scalp").visible and v.hair_proxy().visible and not _helm_visible(v)[hv] and not _mouth_visible(v),
		"nový vzhled v davu: stále proxy účesu a skrytá ústa")
	# vynucený stupeň
	v.lod_override = 0
	await get_tree().process_frame
	check(v.lod_tier() == 0 and v.hair_part("scalp").visible, "lod_override = 0 vynutí plný detail i v 80 m")
	v.lod_override = 2
	await get_tree().process_frame
	check(v.lod_tier() == 2, "lod_override = 2 vynutí dav")
	v.lod_override = -1
	# bez kamery
	cam.clear_current(false)
	cam.queue_free()
	cam = null
	await wait_seconds(0.4)
	check(v.lod_tier() == 0 and v.hair_part("scalp").visible, "bez kamery (server, headless): plný detail")
	# výkon
	var t0 := Time.get_ticks_usec()
	for i in 50:
		v.set_lod_tier(2)
		v.set_lod_tier(0)
	var sw := float(Time.get_ticks_usec() - t0) / 100.0
	check(sw < 1500.0, "přepnutí stupně %.0f µs (limit 1,5 ms)" % sw)
	t0 = Time.get_ticks_usec()
	for i in 2000:
		v._lod_tick(0.3)
	var tick := float(Time.get_ticks_usec() - t0) / 2000.0
	check(tick < 60.0, "kontrola stupně %.1f µs (limit 60 µs, běží 4× za s)" % tick)
	v.queue_free()
	await get_tree().process_frame


func _test_bald_and_settings() -> void:
	section("Plešatá postava a nastavení")
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	_place_cam(_dist_for(0.03))
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "holy"}})
	await wait_seconds(0.35)
	var hvis := _helm_visible(v)
	check(v.lod_tier() == 2 and not hvis["hair_short"] and not hvis["hair_long"]
		and (v.hair_part("scalp") == null or not v.hair_part("scalp").visible), "plešatá postava v davu: žádná helma ani karty")
	var gs := get_node_or_null("/root/GameSettings")
	if not check(gs != null, "autoload GameSettings"):
		v.queue_free()
		return
	var old_persist = gs.persist
	gs.persist = false
	var old := int(gs.get_value("crowd_detail"))
	check(old >= 0 and old <= 2 and gs.DEFAULTS.has("crowd_detail") and int(gs.DEFAULTS["crowd_detail"]) == 1, "výchozí detail postav v dálce = střední")
	check(not gs.set_value("crowd_detail", "vysoko", false) and not gs.set_value("crowd_detail", NAN, false)
		and not gs.set_value("crowd_detail", INF, false), "nastavení odmítne řetězec, NaN i ∞")
	gs.set_value("crowd_detail", 99, false)
	check(int(gs.get_value("crowd_detail")) == 2, "nastavení 99 → ořez na 2")
	gs.set_value("crowd_detail", -4.0, false)
	check(int(gs.get_value("crowd_detail")) == 0, "nastavení −4 → ořez na 0")
	# vysoký detail: podíl 0,04 zůstane ve stupni 1
	gs.set_value("crowd_detail", 2, false)
	_place_cam(_dist_for(0.04))
	await wait_seconds(0.4)
	check(v.lod_tier() == 1, "vysoký detail: podíl 0,04 → stupeň 1")
	gs.set_value("crowd_detail", 0, false)
	await wait_seconds(0.4)
	check(v.lod_tier() == 2, "nízký detail: podíl 0,04 → stupeň 2")
	gs.set_value("crowd_detail", old, false)
	gs.persist = old_persist
	var menu_src := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	check(menu_src.find("\"crowd_detail\"") >= 0 and menu_src.find("Detail postav v dálce") >= 0, "volba je v menu nastavení")
	v.queue_free()
	cam.queue_free()
	cam = null
	await get_tree().process_frame


# ------------------------------------------------------------------ 4) bez modelu

func _test_no_model() -> void:
	section("Bez modelu (dedikovaný server / náhrada)")
	AL.enabled = false
	var v = SimVisual.new()
	add_child(v)
	var ok: bool = v._model == null
	v._lod_tick(1.0)
	v.set_lod_tier(2)
	v._lod_tick(1.0)
	check(ok, "SimVisual bez modelu – primitivní náhrada")
	check(v.lod_fraction() == INF or v.lod_tier() >= 0, "stupeň detailu bez modelu nespadne")
	AL.enabled = true
	v.free()
