extends "res://tests/test_base.gd"
## C-LOD krok 3 (běh main-claude-1794597706, 13. 11. 2026): karty vlasů pro stupeň detailu 1.
## 1) Geometrie LOD1 pro VŠECHNY účesy HairBuilder.STYLES: úspora, kompaktnost (každý vrchol použitý), platné
##    indexy, konečné hodnoty, skin (kosti + váhy se součtem 1), klíče = stejná jména ve stejném pořadí jako
##    plné karty, stejný formát, holá hlava = žádný LOD1, statistiky, čas stavby.
## 2) Kompenzace šířky: ponechaná karta je přesně lod1_widen(lod1_keep(vrstva))× širší kolem STEJNÉ osy pramene,
##    v klidu i v cíli nejsilnějšího klíče.
## 3) Silueta a krytí: nezávislý CPU rasterizér (ortho 4 mm; zepředu, z boku, shora) – IoU LOD1 vs. plné karty
##    s hlavou a tělem a zvlášť jen vlasy (krytí).
## 4) Přenos morfů: nejsilnější klíč plných karet hýbe i LOD1 (stejná výchylka – stejná vazba).
## 5) Determinismus: po clear_cache bitově stejný LOD1.
## 6) SimVisual: stupeň 0 plné karty, 1 = LOD1, 2 = proxy; váhy klíčů po výměně sítě = CharacterData;
##    změna účesu ve stupni 1, plešatá postava, výkon přepnutí; asynchronní stavba (helma → LOD1).

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const HB := preload("res://scripts/assets/hair_builder.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const AL := preload("res://scripts/assets/asset_library.gd")

const RES := 0.004
const W := 180
const H := 220
const VIEWS := [0, 1, 3]
const VIEW_NAMES := ["zepředu", "z boku", "", "shora"]
## Úspora: LOD1 smí mít nejvýš tolik trojúhelníků plných karet (s ochranou obrysu měřeno 13. 11.: 0,32–0,72;
## culík má většinu karet na obrysu). Účes bez LOD1 musí mít důvod ve statistice (úspora < 20 %).
const MAX_RATIO := 0.75
const BUILD_MS := 400.0

var results := {}


func _init() -> void:
	watchdog_seconds = 600.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	_test_geometry()
	_test_widening()
	_test_silhouette()
	_test_morphs()
	_test_determinism()
	await _test_visual()
	await _test_async()
	print("LOD1_RESULTS ", JSON.stringify(results))
	finish("test_hair_lod1")


# ------------------------------------------------------------------ 1) geometrie

func _test_geometry() -> void:
	section("Geometrie LOD1 pro všechny účesy")
	var tot_f := 0
	var tot_l := 0
	for style in HB.STYLES.keys():
		var full := HairRig.mesh_for("scalp", style)
		var lm := HairRig.lod1_mesh(style)
		if (HB.STYLES[style] as Dictionary).is_empty():
			check(full == null and lm == null and bool(HairRig.cached_lod1(style)["ready"]),
				"%s: holá hlava → žádný LOD1 (v cache jako null)" % style)
			continue
		var st0: Dictionary = HairRig.build_stats.get(HairRig.LOD1_PREFIX + style, {})
		if lm == null:
			# bez LOD1 jen s doloženým důvodem a nikdy u účesu z karet (tam je úspora vždy)
			check(full != null and String(st0.get("skip", "")) == "min_saving" and int(st0.get("cards_total", 0)) == 0
				and bool(HairRig.cached_lod1(style)["ready"]),
				"%s: bez LOD1 – úspora jen %d → %d tr. (< 20 %%, trubice nad mezí chyby), stupeň 1 = plné karty" % [style,
				int(st0.get("full_tris", 0)), int(st0.get("tris", 0))])
			results[style] = {"full": int(st0.get("full_tris", 0)), "lod1": null, "skip": st0.get("skip", "")}
			tot_f += int(st0.get("full_tris", 0))
			tot_l += int(st0.get("full_tris", 0))
			continue
		if not check(full != null, "%s: plné karty i LOD1 existují" % style):
			continue
		var fa := full.surface_get_arrays(0)
		var a := lm.surface_get_arrays(0)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var n := pos.size()
		var tris := idx.size() / 3
		var ftris := (fa[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tot_f += ftris
		tot_l += tris
		var ratio := float(tris) / maxf(ftris, 1)
		var st: Dictionary = HairRig.build_stats.get(HairRig.LOD1_PREFIX + style, {})
		results[style] = {"full": ftris, "lod1": tris, "ratio": snappedf(ratio, 0.001), "verts": n,
			"full_verts": (fa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "ms": st.get("ms", -1)}
		check(ratio <= MAX_RATIO and tris == int(st.get("tris", -1)) and n == int(st.get("verts", -1)),
			"%s: %d → %d tr. (%.0f %%, mez %.0f %%), %d → %d vrcholů" % [style, ftris, tris, 100.0 * ratio, 100.0 * MAX_RATIO,
			(fa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), n])
		var finite := true
		for p in pos:
			finite = finite and is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
		var used := PackedByteArray()
		used.resize(n)
		var idx_ok := idx.size() % 3 == 0 and tris > 0
		for i in idx:
			if i < 0 or i >= n:
				idx_ok = false
			else:
				used[i] = 1
		var unused := 0
		for u in used:
			if u == 0:
				unused += 1
		check(finite and idx_ok, "%s: konečné vrcholy, platné indexy" % style)
		check(unused == 0, "%s: kompaktní – každý z %d vrcholů je použitý (nepoužitých %d)" % [style, n, unused])
		var arr_ok: bool = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == n and (a[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == n \
			and (a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == n * 4 and (a[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size() == n * 4
		check(arr_ok, "%s: normály, tangenty, UV a CUSTOM0 pro všechny vrcholy" % style)
		var bones = a[Mesh.ARRAY_BONES]
		var wts = a[Mesh.ARRAY_WEIGHTS]
		var fb = fa[Mesh.ARRAY_BONES]
		var skin_ok := bones != null and wts != null and (bones as PackedInt32Array).size() > 0
		if skin_ok:
			var stride: int = (wts as PackedFloat32Array).size() / n
			var fstride: int = (fb as PackedInt32Array).size() / (fa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			skin_ok = stride == fstride and (bones as PackedInt32Array).size() == n * stride
			for vi in n:
				var s := 0.0
				for j in stride:
					s += (wts as PackedFloat32Array)[vi * stride + j]
				skin_ok = skin_ok and absf(s - 1.0) < 0.01
		check(skin_ok, "%s: skin – stejný počet vlivů jako plné karty, váhy se součtem 1" % style)
		var names_ok := lm.get_blend_shape_count() == full.get_blend_shape_count() and lm.get_blend_shape_count() > 0
		if names_ok:
			for i in lm.get_blend_shape_count():
				names_ok = names_ok and lm.get_blend_shape_name(i) == full.get_blend_shape_name(i)
		check(names_ok, "%s: %d klíčů – stejná jména ve stejném pořadí jako plné karty" % [style, lm.get_blend_shape_count()])
		check(lm.surface_get_format(0) == full.surface_get_format(0) and lm.blend_shape_mode == full.blend_shape_mode,
			"%s: stejný formát plochy a režim klíčů" % style)
		check(lm.resource_name == "hair_cards_lod1", "%s: resource_name hair_cards_lod1" % style)
		# Stavba LOD1 jde ve stejné úloze WorkerThreadPool jako karty (hra nečeká); je to jen výběr indexů,
		# kompakce a meshoptimizer – nesmí stavbu karet výrazně prodloužit.
		check(float(st.get("ms", 999.0)) < BUILD_MS, "%s: LOD1 %.1f ms navíc ke stavbě karet (limit %.0f ms)" % [style, float(st.get("ms", 999.0)), BUILD_MS])
	var tr := float(tot_l) / maxf(tot_f, 1)
	check(tr <= 0.6, "všechny účesy dohromady (účes bez LOD1 = plné karty) %d → %d tr. (%.1f %%, mez 60 %%)" % [tot_f, tot_l, 100.0 * tr])


# ------------------------------------------------------------------ 2) rozšíření karet

## Klíč páru vrcholů karty: (náhoda pramene, vrstva, v) – jednoznačné v rámci účesu (náhoda je float z RNG).
func _pairs(a: Array, verts: PackedVector3Array) -> Dictionary:
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var out := {}
	for i in uv.size() - 1:
		if int(roundf(c0[i * 4 + 3] * 8.0)) != HB.KIND_CARD:
			continue
		if uv[i].x < 0.5 and uv[i + 1].x > 0.5 and absf(uv[i + 1].y - uv[i].y) < 1e-6:
			var k := "%.7f|%.4f|%.6f" % [c0[i * 4], c0[i * 4 + 2], uv[i].y]
			out[k] = [verts[i], verts[i + 1], c0[i * 4 + 2], c0[i * 4]]
	return out


func _test_widening() -> void:
	section("Kompenzace šířky ponechaných karet")
	for style in ["kratke", "dlouhe_vlnite", "culik"]:
		var full := HairRig.mesh_for("scalp", style)
		var lm := HairRig.lod1_mesh(style)
		var fa := full.surface_get_arrays(0)
		var la := lm.surface_get_arrays(0)
		var fp := _pairs(fa, fa[Mesh.ARRAY_VERTEX])
		var lp := _pairs(la, la[Mesh.ARRAY_VERTEX])
		var matched := 0
		var widened := 0
		var outline_only := 0
		var max_ratio_err := 0.0
		var max_mid := 0.0
		for k in lp:
			if not fp.has(k):
				continue
			var f: Array = fp[k]
			var l: Array = lp[k]
			var w0 := (f[1] as Vector3).distance_to(f[0])
			if w0 < 1e-5:
				continue
			matched += 1
			var expect := _expected_widen(l)
			if expect > 1.0:
				widened += 1
			else:
				outline_only += 1
			var w1 := (l[1] as Vector3).distance_to(l[0])
			max_ratio_err = maxf(max_ratio_err, absf(w1 / w0 - expect))
			max_mid = maxf(max_mid, (((l[0] as Vector3) + (l[1] as Vector3)) * 0.5).distance_to(((f[0] as Vector3) + (f[1] as Vector3)) * 0.5))
		check(matched > 50 and matched == lp.size(), "%s: %d párů karet LOD1 dohledáno v plných kartách (všechny)" % [style, matched], "%d/%d" % [matched, lp.size()])
		check(max_ratio_err < 1e-3 and widened > 0 and outline_only > 0,
			"%s: šířka = 1/√podíl u náhodně ponechaných karet (%d párů), obrysové segmenty beze změny (%d párů), max odchylka %.5f" % [style, widened, outline_only, max_ratio_err])
		check(max_mid < 1e-6, "%s: osa pramene beze změny (max posun středu %.3f µm)" % [style, max_mid * 1e6])
		# totéž v cíli nejsilnějšího klíče (rozšíření musí být i v blend shapes, jinak by se karty při tvaru hlavy zúžily)
		var best := _strongest_key(full)
		var fi := _key_index(full, best)
		var li := _key_index(lm, best)
		if not check(fi >= 0 and li >= 0, "%s: klíč %s v obou sítích" % [style, best]):
			continue
		var fpt := _pairs(fa, (full.surface_get_blend_shape_arrays(0)[fi] as Array)[Mesh.ARRAY_VERTEX])
		var lpt := _pairs(la, (lm.surface_get_blend_shape_arrays(0)[li] as Array)[Mesh.ARRAY_VERTEX])
		var err := 0.0
		var mid := 0.0
		for k in lpt:
			if not fpt.has(k):
				continue
			var f: Array = fpt[k]
			var l: Array = lpt[k]
			var w0 := (f[1] as Vector3).distance_to(f[0])
			if w0 < 1e-5:
				continue
			err = maxf(err, absf((l[1] as Vector3).distance_to(l[0]) / w0 - _expected_widen(l)))
			mid = maxf(mid, (((l[0] as Vector3) + (l[1] as Vector3)) * 0.5).distance_to(((f[0] as Vector3) + (f[1] as Vector3)) * 0.5))
		check(err < 1e-3 and mid < 1e-6, "%s: rozšíření i v cíli klíče %s (odchylka %.5f, střed %.3f µm)" % [style, best, err, mid * 1e6])


## Očekávané rozšíření páru: náhodně ponechaná karta 1/√podíl, obrysový segment vypuštěné karty 1.
func _expected_widen(l: Array) -> float:
	var keep := HairRig.lod1_keep(float(l[2]))
	return HairRig.lod1_widen(keep) if float(l[3]) < keep else 1.0


func _strongest_key(m: ArrayMesh) -> String:
	var ca := m.surface_get_arrays(0)
	var cp: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
	var cb := m.surface_get_blend_shape_arrays(0)
	var best := ""
	var best_d := 0.0
	for i in m.get_blend_shape_count():
		var nm := String(m.get_blend_shape_name(i))
		if nm.begins_with("ex_"):
			continue
		var tv: PackedVector3Array = (cb[i] as Array)[Mesh.ARRAY_VERTEX]
		var d := 0.0
		for j in cp.size():
			d = maxf(d, (tv[j] - cp[j]).length())
		if d > best_d:
			best_d = d
			best = nm
	return best


func _key_index(m: ArrayMesh, nm: String) -> int:
	for i in m.get_blend_shape_count():
		if String(m.get_blend_shape_name(i)) == nm:
			return i
	return -1


# ------------------------------------------------------------------ 3) silueta a krytí

func _uv(p: Vector3, view: int) -> Vector2:
	match view:
		0:
			return Vector2(p.x, p.y)
		1:
			return Vector2(p.z, p.y)
	return Vector2(p.x, p.z)


func _raster(m: PackedByteArray, v: PackedVector3Array, idx: PackedInt32Array, view: int) -> void:
	var o := Vector2(-0.36, 1.10 if view != 3 else -0.36)
	for t in range(0, idx.size(), 3):
		var A := (_uv(v[idx[t]], view) - o) / RES
		var B := (_uv(v[idx[t + 1]], view) - o) / RES
		var C := (_uv(v[idx[t + 2]], view) - o) / RES
		for pt in [A, B, C]:
			var px := int(floor(pt.x))
			var py := int(floor(pt.y))
			if px >= 0 and px < W and py >= 0 and py < H:
				m[py * W + px] = 1
		var x0 := maxi(int(floor(minf(A.x, minf(B.x, C.x)))), 0)
		var x1 := mini(int(ceil(maxf(A.x, maxf(B.x, C.x)))), W - 1)
		var y0 := maxi(int(floor(minf(A.y, minf(B.y, C.y)))), 0)
		var y1 := mini(int(ceil(maxf(A.y, maxf(B.y, C.y)))), H - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var P := Vector2(x + 0.5, y + 0.5)
				var w0 := (B - A).cross(P - A)
				var w1 := (C - B).cross(P - B)
				var w2 := (A - C).cross(P - C)
				if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
					m[y * W + x] = 1


func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var i := 0
	var u := 0
	for k in a.size():
		if a[k] or b[k]:
			u += 1
		if a[k] and b[k]:
			i += 1
	return float(i) / maxf(u, 1)


func _count(a: PackedByteArray) -> int:
	var c := 0
	for x in a:
		c += x
	return c


func _test_silhouette() -> void:
	section("Silueta a krytí LOD1 vs. plné karty")
	var src := HairRig.source()
	var base := {}
	for view in VIEWS:
		var m := PackedByteArray()
		m.resize(W * H)
		_raster(m, src["head"]["pos"], src["head"]["idx"], view)
		_raster(m, src["body"]["pos"], src["body"]["idx"], view)
		base[view] = m
	var t0 := Time.get_ticks_usec()
	var sum_s := 0.0
	var sum_c := 0.0
	var nn := 0
	for style in HB.STYLES.keys():
		if (HB.STYLES[style] as Dictionary).is_empty():
			continue
		if HairRig.lod1_mesh(style) == null:
			continue
		var fa := HairRig.mesh_for("scalp", style).surface_get_arrays(0)
		var la := HairRig.lod1_mesh(style).surface_get_arrays(0)
		var row := {}
		var low := []
		for view in VIEWS:
			var empty := PackedByteArray()
			empty.resize(W * H)
			var hf: PackedByteArray = empty.duplicate()
			_raster(hf, fa[Mesh.ARRAY_VERTEX], fa[Mesh.ARRAY_INDEX], view)
			var hl: PackedByteArray = empty.duplicate()
			_raster(hl, la[Mesh.ARRAY_VERTEX], la[Mesh.ARRAY_INDEX], view)
			var sf: PackedByteArray = (base[view] as PackedByteArray).duplicate()
			var sl: PackedByteArray = (base[view] as PackedByteArray).duplicate()
			for k in sf.size():
				sf[k] = sf[k] | hf[k]
				sl[k] = sl[k] | hl[k]
			var s_iou := _iou(sf, sl)
			var c_iou := _iou(hf, hl)
			var area := float(_count(hl)) / maxf(_count(hf), 1)
			row[VIEW_NAMES[view]] = [snappedf(s_iou, 0.001), snappedf(c_iou, 0.001), snappedf(area, 0.001)]
			sum_s += s_iou
			sum_c += c_iou
			nn += 1
			# silueta s hlavou a tělem ≥ 0,95; samotné vlasy (krytí) ≥ 0,85 a plocha 85–110 % plné
			if s_iou < 0.95 or c_iou < 0.85 or area < 0.85 or area > 1.10:
				low.append(VIEW_NAMES[view])
		(results.get(style, {}) as Dictionary)["silhouette"] = row
		check(low.is_empty(), "%s: silueta ≥ 0,95, krytí vlasů ≥ 0,85, plocha 85–110 %% %s" % [style, str(row)], str(low))
	check(sum_s / maxf(nn, 1) >= 0.97 and sum_c / maxf(nn, 1) >= 0.9,
		"průměr: silueta %.3f (≥ 0,97), krytí vlasů %.3f (≥ 0,90)" % [sum_s / maxf(nn, 1), sum_c / maxf(nn, 1)])
	print("SILHOUETTE_MS ", (Time.get_ticks_usec() - t0) / 1000)


# ------------------------------------------------------------------ 4) morfy

func _test_morphs() -> void:
	section("Přenos morfů na LOD1")
	for style in ["kratke", "dlouhe_rovne", "afro", "cornrows"]:
		var full := HairRig.mesh_for("scalp", style)
		var lm := HairRig.lod1_mesh(style)
		var best := _strongest_key(full)
		var fd := _max_disp(full, _key_index(full, best))
		var ld := _max_disp(lm, _key_index(lm, best))
		check(fd > 0.001 and ld > fd * 0.5 and ld <= fd * HairRig.LOD1_WIDEN_MAX + 1e-6,
			"%s: nejsilnější klíč „%s“ %.2f mm na plných kartách, %.2f mm na LOD1" % [style, best, fd * 1000.0, ld * 1000.0])


func _max_disp(m: ArrayMesh, ki: int) -> float:
	if ki < 0:
		return 0.0
	var p: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tv: PackedVector3Array = (m.surface_get_blend_shape_arrays(0)[ki] as Array)[Mesh.ARRAY_VERTEX]
	var d := 0.0
	for j in p.size():
		d = maxf(d, (tv[j] - p[j]).length())
	return d


# ------------------------------------------------------------------ 5) determinismus

func _snapshot(m: ArrayMesh) -> Array:
	var a := m.surface_get_arrays(0)
	var out := [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_INDEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_TANGENT], a[Mesh.ARRAY_TEX_UV],
		a[Mesh.ARRAY_CUSTOM0], a[Mesh.ARRAY_BONES], a[Mesh.ARRAY_WEIGHTS]]
	for i in m.get_blend_shape_count():
		out.append(String(m.get_blend_shape_name(i)))
		out.append((m.surface_get_blend_shape_arrays(0)[i] as Array)[Mesh.ARRAY_VERTEX])
	return out


func _test_determinism() -> void:
	section("Determinismus")
	for style in ["dlouhe_vlnite", "afro"]:
		var a := HairRig.lod1_mesh(style)
		var sa := _snapshot(a)
		HairRig.clear_cache()
		check(not bool(HairRig.cached_lod1(style)["ready"]), "%s: clear_cache vymaže i LOD1" % style)
		var b := HairRig.lod1_mesh(style)
		check(a != b and sa == _snapshot(b), "%s: nová stavba po clear_cache je bitově stejná (všechna pole, klíče)" % style)
		check(HairRig.lod1_mesh(style) == b, "%s: opakovaná žádost vrací sdílenou síť z cache" % style)


# ------------------------------------------------------------------ 6) SimVisual

func _helm(v) -> bool:
	for g in ["hair_short", "hair_long"]:
		for mi in AL.parts_in_group(v._model, g):
			if mi.visible:
				return true
	return false


func _expected_weight(v, nm: String) -> float:
	var lp: Dictionary = v.look_params
	var w: Dictionary = lp.get("face", {})
	var wb: Dictionary = lp.get("body", {})
	return clampf(float(w.get(nm, wb.get(nm, v._expr_w.get(nm, 0.0)))), -1.0, 1.0)


func _weights_ok(v, mi: MeshInstance3D) -> Array:
	var bad := []
	var nz := 0
	for i in mi.mesh.get_blend_shape_count():
		var nm := String(mi.mesh.get_blend_shape_name(i))
		var e := _expected_weight(v, nm)
		if absf(e) > 1e-4:
			nz += 1
		if absf(mi.get_blend_shape_value(i) - e) > 1e-5:
			bad.append(nm)
	return [bad, nz]


func _test_visual() -> void:
	section("SimVisual – stupeň 1 = LOD1 karet")
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	var look := {"hair": {"style": "dlouhe_vlnite"}, "body": {"body_fat": 0.7, "muscle": 0.3},
		"face": {"jaw_width": 0.8, "head_width": 0.6}}
	v.apply_look(look)
	await get_tree().process_frame
	if not check(v._model != null and v.hair_part("scalp") != null, "postava s modelem a kartami"):
		v.queue_free()
		return
	var sc: MeshInstance3D = v.hair_part("scalp")
	var full := HairRig.mesh_for("scalp", "dlouhe_vlnite")
	var lod1: ArrayMesh = HairRig.cached_lod1("dlouhe_vlnite")["mesh"]
	check(v.lod_tier() == 0 and sc.mesh == full and sc.visible, "stupeň 0: plné karty")
	v.lod_override = 1
	await get_tree().process_frame
	check(v.lod_tier() == 1 and sc.mesh == lod1 and v.scalp_lod_mesh() == lod1 and sc.visible and not _helm(v)
		and not v.hair_proxy().visible, "stupeň 1: LOD1 karet vidět, helma i proxy skryté")
	var wr := _weights_ok(v, sc)
	check((wr[0] as Array).is_empty() and int(wr[1]) > 0, "stupeň 1: váhy klíčů LOD1 = CharacterData (%d nenulových)" % int(wr[1]), str(wr[0]))
	v.lod_override = 2
	await get_tree().process_frame
	check(v.lod_tier() == 2 and not sc.visible and v.hair_proxy().visible, "stupeň 2: proxy, karty skryté")
	v.lod_override = 1
	await get_tree().process_frame
	check(sc.mesh == lod1 and sc.visible and not v.hair_proxy().visible, "2 → 1: zpět LOD1")
	# změna tvaru a účesu přímo ve stupni 1
	look["face"] = {"jaw_width": -0.5, "head_width": -0.4}
	look["hair"] = {"style": "kratke"}
	v.apply_look(look)
	await get_tree().process_frame
	var lod1k: ArrayMesh = HairRig.cached_lod1("kratke")["mesh"]
	wr = _weights_ok(v, sc)
	check(sc.mesh == lod1k and sc.visible and (wr[0] as Array).is_empty(), "změna účesu i tvaru ve stupni 1: LOD1 krátkých vlasů s novými vahami", str(wr[0]))
	v.apply_look({"hair": {"style": "holy"}})
	await get_tree().process_frame
	check(not sc.visible and not _helm(v), "plešatá postava ve stupni 1: žádné karty ani helma")
	v.apply_look(look)
	await get_tree().process_frame
	v.lod_override = 0
	await get_tree().process_frame
	wr = _weights_ok(v, sc)
	check(sc.mesh == HairRig.mesh_for("scalp", "kratke") and sc.visible and (wr[0] as Array).is_empty(),
		"1 → 0: plné karty s aktuálními vahami", str(wr[0]))
	# výkon přepnutí (výměna sítě + zápis vah tvaru)
	var t0 := Time.get_ticks_usec()
	for i in 50:
		v.set_lod_tier(1)
		v.set_lod_tier(0)
	var sw := float(Time.get_ticks_usec() - t0) / 100.0
	results["switch_us"] = snappedf(sw, 1.0)
	check(sw < 2000.0, "přepnutí 0 ↔ 1 s výměnou sítě %.0f µs (limit 2 ms)" % sw)
	v.queue_free()
	await get_tree().process_frame


func _test_async() -> void:
	section("Asynchronní stavba ve stupni 1: helma → LOD1")
	HairRig.clear_cache()
	HairRig.async_build = true
	var v = SimVisual.new()
	v.lod_override = 1
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "culik"}})
	await get_tree().process_frame
	var sc: MeshInstance3D = v.hair_part("scalp")
	if sc == null:
		check(false, "uzel skalpu existuje")
	else:
		check(not sc.visible and _helm(v), "během stavby ve vlákně: helma vidět, karty ne")
		var done := await wait_until(func(): return bool(HairRig.cached_lod1("culik")["ready"]) and sc.visible, 30.0)
		check(done and not _helm(v) and sc.mesh == HairRig.cached_lod1("culik")["mesh"] and sc.mesh != null,
			"po dokončení: LOD1 culíku vidět, helma skrytá")
	HairRig.wait_for_builds()
	HairRig.async_build = false
	v.queue_free()
	await get_tree().process_frame
