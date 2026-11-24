extends "res://tests/test_base.gd"
## C-LOD krok 5 (běh main-claude-1794943543-facial, 17. 11. 2026): obočí a vousy ve stupni detailu 1.
## 1) Geometrie LOD1 pro všechny styly obočí (HairBuilder.BROWS) a vousů (BEARDS): úspora, kompaktnost, platné
##    indexy, konečné hodnoty, skin (váhy se součtem 1), klíče = stejná jména ve stejném pořadí, styl bez
##    geometrie (zadne, strniste) = žádný LOD1, statistiky v build_stats.
## 2) Hustota (oprava proti fallbacku 17. 11. odpoledne): shader obličejových chlupů skrývá karty s c0.x > density.
##    LOD1 přeškáluje c0.x ponechaných karet / podíl → viditelné karty LOD1 při hustotě d jsou PŘESNĚ karty
##    plné sítě s c0.x < podíl·d (obočí, bez obrysu), u vousů navíc nejvýš obrysové segmenty. Poměr viditelných
##    karet LOD1/LOD0 je tak stejný pro řídké i husté obočí (bez přeškálování by u d = 0,3 byl 1,0).
## 3) Krytí zepředu: nezávislý CPU rasterizér (jen viditelné karty podle hustoty), LOD1 / LOD0 při d 0,3/0,6/1,0;
##    3b) vzhled v dálce: celkové ztmavení obličeje chlupy v CPU renderu (obočí + vousy), LOD1 / LOD0 0,85–1,15.
## 4) Přenos morfů: nejsilnější klíč hýbe LOD1 stejně (max. výchylka v mezích).
## 5) Determinismus po clear_cache (bitově) a souběh ve WorkerThreadPool = sekvenční výsledek.
## 6) SimVisual: stupeň 0 plné sítě, 1 = LOD1 obočí i vousů s aktuálními vahami a nezměněným materiálem (hustota),
##    2 = skryté, návrat; změna stylu ve stupni 1; výkon přepnutí; cached_facial_lod1 nestaví (neblokuje);
##    asynchronní stavba ve stupni 1.

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const HB := preload("res://scripts/assets/hair_builder.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

const R := 200
const DENS := [0.3, 0.6, 1.0]
## minimální krytí zepředu LOD1/LOD0 podle hustoty (měřeno 17. 11.: obočí 0,73–0,97, vousy 0,67–0,98)
const MIN_COVER := {0.3: 0.6, 0.6: 0.7, 1.0: 0.75}
## nejvyšší poměr trojúhelníků LOD1/plná síť (měřeno: obočí 0,40–0,48; vousy 0,59–0,76)
const MAX_RATIO := {"brows": 0.55, "beard": 0.8}

var results := {}


func _init() -> void:
	watchdog_seconds = 500.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	HairRig.clear_cache()
	_test_geometry()
	_test_density()
	_test_coverage()
	_test_far_darkening()
	_test_morphs()
	_test_determinism()
	_test_threads()
	await _test_visual()
	await _test_nonblocking_async()
	print("FACIAL_LOD1_RESULTS ", JSON.stringify(results))
	finish("test_facial_lod1")


func _styles(part: String) -> Array:
	return HB.BROWS.keys() if part == "brows" else HB.BEARDS.keys()


func _has_geo(part: String, style: String) -> bool:
	return HairRig.mesh_for(part, style) != null


func _keep(part: String) -> float:
	var k := float(HairRig.FACIAL_LOD1_KEEP.get(part, -1.0))
	return k if k > 0.0 else HairRig.lod1_keep(0.5)


# ------------------------------------------------------------------ 1) geometrie

func _test_geometry() -> void:
	section("Geometrie LOD1 obočí a vousů")
	for part in ["brows", "beard"]:
		for style in _styles(part):
			var full := HairRig.mesh_for(part, style)
			var lm := HairRig.facial_lod1_mesh(part, style)
			var cr: Dictionary = HairRig.cached_facial_lod1(part, style)
			if full == null:
				check(lm == null and bool(cr["ready"]), "%s:%s bez geometrie → žádný LOD1 (v cache jako null)" % [part, style])
				continue
			if full.surface_get_array_index_len(0) / 3 < HairRig.FACIAL_LOD1_MIN_TRIS:
				var sst: Dictionary = HairRig.build_stats.get(part + HairRig.FACIAL_LOD1_SUFFIX + style, {})
				check(lm == null and bool(cr["ready"]) and String(sst.get("skip", "")) == "small",
					"%s:%s malá síť (%d tr. < %d) → bez LOD1, důvod v build_stats, stupeň 1 = plná síť" % [part, style,
					full.surface_get_array_index_len(0) / 3, HairRig.FACIAL_LOD1_MIN_TRIS])
				continue
			if not check(lm != null, "%s:%s má LOD1" % [part, style]):
				continue
			var fa := full.surface_get_arrays(0)
			var la := lm.surface_get_arrays(0)
			var ft: int = (fa[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var lt: int = (la[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var ratio := float(lt) / float(ft)
			results["%s:%s" % [part, style]] = {"full": ft, "lod1": lt, "ratio": snappedf(ratio, 0.001)}
			check(ratio <= float(MAX_RATIO[part]), "%s:%s úspora %d → %d tr. (%.0f %%, limit %.0f %%)" % [part, style, ft, lt,
				ratio * 100.0, float(MAX_RATIO[part]) * 100.0])
			var st: Dictionary = HairRig.build_stats.get(part + HairRig.FACIAL_LOD1_SUFFIX + style, {})
			check(int(st.get("tris", -1)) == lt and int(st.get("full_tris", -1)) == ft and String(st.get("skip", "")) == "",
				"%s:%s statistika v build_stats odpovídá síti" % [part, style], str(st))
			var pos: PackedVector3Array = la[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = la[Mesh.ARRAY_INDEX]
			var used := PackedByteArray()
			used.resize(pos.size())
			var idx_ok := true
			for i in idx:
				if i < 0 or i >= pos.size():
					idx_ok = false
					break
				used[i] = 1
			var all_used := true
			for u in used:
				if u == 0:
					all_used = false
					break
			var finite := true
			for p in pos:
				if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
					finite = false
					break
			var c0: PackedFloat32Array = la[Mesh.ARRAY_CUSTOM0]
			var c0_ok := c0.size() == pos.size() * 4
			if c0_ok:
				for k in pos.size():
					if not (c0[k * 4] >= 0.0 and c0[k * 4] < 1.0):
						c0_ok = false
						break
			check(idx_ok and all_used and finite and c0_ok, "%s:%s platné indexy, kompaktní, konečné hodnoty, c0.x v [0, 1)" % [part, style])
			# skin
			var b: PackedInt32Array = la[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = la[Mesh.ARRAY_WEIGHTS]
			var skin_ok := b.size() > 0 and b.size() == w.size() and b.size() % pos.size() == 0
			if skin_ok:
				var stride := b.size() / pos.size()
				for k in pos.size():
					var sw := 0.0
					for j in stride:
						sw += w[k * stride + j]
					if absf(sw - 1.0) > 1e-3:
						skin_ok = false
						break
			check(skin_ok, "%s:%s skin – kosti a váhy (součet 1)" % [part, style])
			# klíče
			var same_keys := lm.get_blend_shape_count() == full.get_blend_shape_count() and lm.get_blend_shape_count() > 0
			if same_keys:
				for k in full.get_blend_shape_count():
					if lm.get_blend_shape_name(k) != full.get_blend_shape_name(k):
						same_keys = false
						break
			check(same_keys and lm.surface_get_format(0) == full.surface_get_format(0) and lm.get_blend_shape_mode() == full.get_blend_shape_mode(),
				"%s:%s klíče (%d) stejná jména/pořadí, stejný formát a režim" % [part, style, lm.get_blend_shape_count()])


# ------------------------------------------------------------------ 2) hustota

## Počet trojúhelníků karet, které shader při hustotě d ukáže (fine = 0: skrytá karta má c0.x > d).
func _visible_tris(a: Array, d: float) -> int:
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var n := 0
	for t in range(0, idx.size(), 3):
		if c0[idx[t] * 4] <= d:
			n += 1
	return n


func _test_density() -> void:
	section("Hustota: viditelné karty LOD1 = vnořená podmnožina LOD0 s konstantním poměrem")
	for part in ["brows", "beard"]:
		var keep := _keep(part)
		for style in _styles(part):
			var lm := HairRig.facial_lod1_mesh(part, style)
			if lm == null:
				continue
			var fa := HairRig.mesh_for(part, style).surface_get_arrays(0)
			var la := lm.surface_get_arrays(0)
			var st: Dictionary = HairRig.build_stats.get(part + HairRig.FACIAL_LOD1_SUFFIX + style, {})
			var outline := int(st.get("outline_tris", 0))
			if part == "brows":
				check(outline == 0, "%s:%s bez obrysových segmentů (obočí netvoří siluetu)" % [part, style])
			var ok := true
			var detail := ""
			var ratios := []
			for d in [0.15, 0.3, 0.45, 0.6, 0.8, 1.0]:
				var vl := _visible_tris(la, d)
				var expect := _visible_tris(fa, keep * d)
				var vf := _visible_tris(fa, d)
				# tolerance 4 tr. = jedna karta na hraně zaokrouhlení dělení
				if vl < expect - 4 or vl > expect + outline + 4:
					ok = false
					detail += "d%.2f: %d vs %d..%d " % [d, vl, expect, expect + outline]
				# poměr dává smysl jen bez obrysových segmentů (ty mají původní c0.x a přibývají s hustotou nad podílem);
				# náhoda karet je rovnoměrná → odchylka od podílu v mezích 3σ binomického rozdělení pro počet viditelných karet
				if vf > 0 and outline == 0:
					var cards := float(vf) / float(_tris_per_card(fa))
					ratios.append([float(vl) / float(vf), 3.0 * sqrt(keep * (1.0 - keep) / maxf(cards, 1.0)) + 0.02, d])
			check(ok, "%s:%s viditelné karty LOD1 při každé hustotě = karty plné sítě s c0.x < %.3f·d (+ nejvýš %d obrysových)" % [part, style, keep, outline], detail)
			if not ratios.is_empty():
				var rok := true
				var txt := ""
				for rr in ratios:
					txt += " d%.2f %.2f±%.2f" % [rr[2], rr[0], rr[1]]
					if absf(float(rr[0]) - keep) > float(rr[1]):
						rok = false
				check(rok, "%s:%s poměr viditelných karet LOD1/LOD0 = podíl %.2f při každé hustotě (3σ podle počtu karet):%s" % [part, style, keep, txt])
	# kontrola, že test opravdu rozliší chybu fallbacku: bez přeškálování by poměr u nízké hustoty byl ~1
	var pack := HairRig.build_pack("brows", "huste")
	var raw := HairRig.lod1_pack(pack, {"facial": false, "outline": false, "keep": 0.5})
	var fixed := HairRig.lod1_pack(pack, {"facial": true, "outline": false, "keep": 0.5})
	var fa2: Array = pack["arrays"]
	var vf2 := float(_visible_tris(fa2, 0.3))
	var r_raw := float(_visible_tris(raw["arrays"], 0.3)) / vf2
	var r_fix := float(_visible_tris(fixed["arrays"], 0.3)) / vf2
	results["huste_d03_ratio"] = {"bez_preskalovani": snappedf(r_raw, 0.01), "s_preskalovanim": snappedf(r_fix, 0.01)}
	check(r_raw > 0.9 and absf(r_fix - 0.5) < 0.15,
		"kontrola citlivosti: bez přeškálování by řídké obočí v dálce mělo %.2f karet LOD0 (× rozšíření = hustší), s ním %.2f" % [r_raw, r_fix])
	check(raw["tris"] == fixed["tris"], "přeškálování nemění geometrii (jen c0.x)")


# ------------------------------------------------------------------ 3) krytí

func _cover(a: Array, dens: float, box: Rect2) -> int:
	var img := PackedByteArray()
	img.resize(R * R)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		if c0[idx[t] * 4] > dens:
			continue
		var P := []
		for k in 3:
			var p := pos[idx[t + k]]
			P.append(Vector2((p.x - box.position.x) / box.size.x * R, (p.y - box.position.y) / box.size.y * R))
		var mn: Vector2 = (P[0] as Vector2).min(P[1]).min(P[2])
		var mx: Vector2 = (P[0] as Vector2).max(P[1]).max(P[2])
		for y in range(maxi(0, int(mn.y)), mini(R - 1, int(mx.y) + 1)):
			for x in range(maxi(0, int(mn.x)), mini(R - 1, int(mx.x) + 1)):
				if Geometry2D.point_is_inside_triangle(Vector2(x + 0.5, y + 0.5), P[0], P[1], P[2]):
					img[y * R + x] = 1
	var c := 0
	for v in img:
		c += v
	return c


func _test_coverage() -> void:
	section("Krytí zepředu (CPU rasterizér, jen viditelné karty)")
	for part in ["brows", "beard"]:
		for style in _styles(part):
			var lm := HairRig.facial_lod1_mesh(part, style)
			if lm == null:
				continue
			var fa := HairRig.mesh_for(part, style).surface_get_arrays(0)
			var la := lm.surface_get_arrays(0)
			var pos: PackedVector3Array = fa[Mesh.ARRAY_VERTEX]
			var bb := AABB(pos[0], Vector3.ZERO)
			for p in pos:
				bb = bb.expand(p)
			var box := Rect2(bb.position.x - 0.005, bb.position.y - 0.005, bb.size.x + 0.01, bb.size.y + 0.01)
			var line := ""
			var ok := true
			var cov := {}
			for d in DENS:
				var cf := _cover(fa, d, box)
				var cl := _cover(la, d, box)
				var r := float(cl) / maxf(1.0, float(cf))
				cov[str(d)] = snappedf(r, 0.01)
				line += " d%.1f %.2f" % [d, r]
				if r < float(MIN_COVER[d]) or r > 1.3:
					ok = false
			(results["%s:%s" % [part, style]] as Dictionary)["cover"] = cov
			check(ok, "%s:%s krytí LOD1/LOD0:%s (meze 0,6/0,7/0,75; ≤ 1,3)" % [part, style, line])


# ------------------------------------------------------------------ 3b) vzhled v dálce

const RP := preload("res://tools/raster_preview.gd")
const RTOOL := preload("res://tools/render_facial_lod1_cpu.gd")

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _darkening(img: Image, base: Image) -> float:
	var s := 0.0
	for y in img.get_height():
		for x in img.get_width():
			s += _lum(base.get_pixel(x, y)) - _lum(img.get_pixel(x, y))
	return s


## Ve stupni 1 je postava 5,5–20 % výšky obrazu → obličej ~10–30 px a karta (3–5 mm) pod pixel: vnímá se jen,
## jak moc chlupy obličej ztmaví. Součet ztmavení (CPU rasterizér, hlava bez vlasů jako základ) LOD1/LOD0 musí být
## 0,85–1,15 zepředu i ¾ pro kombinace obočí + vousů a hustoty 0,3/0,6/1,0 (kandidát s rozšířením 1/√podíl měl 0,64–0,89).
func _test_far_darkening() -> void:
	section("Vzhled v dálce: ztmavení obličeje LOD1 / LOD0")
	var tool = RTOOL.new()
	var base := RP.deformed_parts({}, "__bez_vlasu__", false)
	var vals := {}
	for row in RTOOL.ROWS:
		var dens := float(row[2])
		var ok := true
		var txt := ""
		for v in RTOOL.VIEWS:
			var b0 := RP.render(base, 200, v.x, v.y, RTOOL.CENTER, RTOOL.EXTENT)
			var dk := []
			for li in 2:
				var mb: ArrayMesh = HairRig.mesh_for("brows", row[0]) if li == 0 else HairRig.facial_lod1_mesh("brows", row[0])
				var md: ArrayMesh = HairRig.mesh_for("beard", row[1]) if li == 0 else tool._lod_or_full("beard", row[1])
				var parts := base.duplicate()
				parts.append(tool._part(mb, dens, RTOOL.BROW_COL, "brows"))
				parts.append(tool._part(md, dens, RTOOL.BEARD_COL, "beard"))
				dk.append(_darkening(RP.render(parts, 200, v.x, v.y, RTOOL.CENTER, RTOOL.EXTENT), b0))
			var r := float(dk[1]) / maxf(1e-6, float(dk[0]))
			txt += " yaw%d %.2f" % [int(v.x), r]
			vals["%s+%s:%d" % [row[0], row[1], int(v.x)]] = snappedf(r, 0.01)
			if r < 0.85 or r > 1.15:
				ok = false
		check(ok, "%s + %s, hustota %.1f: ztmavení LOD1/LOD0%s (meze 0,85–1,15)" % [row[0], row[1], dens, txt])
	results["far_darkening"] = vals
	tool.free()


# ------------------------------------------------------------------ 4) morfy
	
func _test_morphs() -> void:
	section("Přenos morfů do LOD1")
	for pair in [["brows", "srostle"], ["beard", "plnovous"], ["beard", "bradka"]]:
		var full := HairRig.mesh_for(pair[0], pair[1])
		var lm := HairRig.facial_lod1_mesh(pair[0], pair[1])
		if not check(full != null and lm != null, "%s:%s sítě existují" % pair):
			continue
		var fb := full.surface_get_blend_shape_arrays(0)
		var lb := lm.surface_get_blend_shape_arrays(0)
		var fp: PackedVector3Array = full.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lp: PackedVector3Array = lm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var best := -1
		var best_d := 0.0
		for k in fb.size():
			var tv: PackedVector3Array = (fb[k] as Array)[Mesh.ARRAY_VERTEX]
			var md := 0.0
			for i in fp.size():
				md = maxf(md, (tv[i] - fp[i]).length())
			if md > best_d:
				best_d = md
				best = k
		var ltv: PackedVector3Array = (lb[best] as Array)[Mesh.ARRAY_VERTEX]
		var ld := 0.0
		for i in lp.size():
			ld = maxf(ld, (ltv[i] - lp[i]).length())
		check(best_d > 0.001 and ld > 0.6 * best_d and ld < 1.6 * best_d,
			"%s:%s nejsilnější klíč %s: max. výchylka plná %.1f mm, LOD1 %.1f mm" % [pair[0], pair[1],
			full.get_blend_shape_name(best), best_d * 1000.0, ld * 1000.0])


# ------------------------------------------------------------------ 5) determinismus a vlákna

func _sig(lm: ArrayMesh) -> String:
	if lm == null:
		return "null"
	var a := lm.surface_get_arrays(0)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	h.update((a[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).to_byte_array())
	h.update((a[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	for ba in lm.surface_get_blend_shape_arrays(0):
		h.update(((ba as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	return h.finish().hex_encode()


func _pack_sig(lp: Dictionary) -> String:
	if not lp.has("arrays"):
		return "skip"
	var a: Array = lp["arrays"]
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	h.update((a[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).to_byte_array())
	h.update((a[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	return h.finish().hex_encode()


func _test_determinism() -> void:
	section("Determinismus po clear_cache")
	var before := {}
	for pair in [["brows", "prirozene"], ["brows", "tenke"], ["beard", "bradka"], ["beard", "licousy"]]:
		before[pair[0] + ":" + pair[1]] = _sig(HairRig.facial_lod1_mesh(pair[0], pair[1]))
	HairRig.clear_cache()
	var same := true
	for k in before:
		var p: PackedStringArray = (k as String).split(":")
		if _sig(HairRig.facial_lod1_mesh(p[0], p[1])) != before[k]:
			same = false
	check(same, "LOD1 obočí a vousů bitově stejný po clear_cache (4 styly)")


var _thr_out := {}
var _thr_mx := Mutex.new()
const _THR := [["brows", "huste"], ["brows", "oblouk"], ["beard", "plnovous"], ["beard", "kozi_bradka"]]


func _thr_job(i: int) -> void:
	var pk := HairRig.build_pack(_THR[i][0], _THR[i][1])
	var s := _pack_sig(pk.get("lod1", {}))
	_thr_mx.lock()
	_thr_out[i] = s
	_thr_mx.unlock()


func _test_threads() -> void:
	section("Souběh ve WorkerThreadPool = sekvenční výsledek")
	var seq := {}
	for i in _THR.size():
		seq[i] = _pack_sig(HairRig.build_pack(_THR[i][0], _THR[i][1]).get("lod1", {}))
	_thr_out = {}
	var gid := WorkerThreadPool.add_group_task(_thr_job, _THR.size())
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var same := _thr_out.size() == _THR.size()
	for i in _THR.size():
		if _thr_out.get(i, "") != seq[i] or seq[i] == "skip":
			same = false
	check(same, "4 stavby LOD1 obočí/vousů ve vláknech bitově = sekvenčně")


# ------------------------------------------------------------------ 6) SimVisual

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
	section("SimVisual – obočí a vousy ve stupni 1")
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	var look := {"hair": {"style": "kratke", "brows": "huste", "facial": "plnovous", "brow_density": 0.3, "facial_density": 0.8},
		"face": {"jaw_width": 0.7, "brow_height": 0.5}, "body": {"body_fat": 0.4}}
	v.apply_look(look)
	await get_tree().process_frame
	var br: MeshInstance3D = v.hair_part("brows")
	var bd: MeshInstance3D = v.hair_part("beard")
	if not check(v._model != null and br != null and bd != null, "postava s modelem, obočím a vousy z karet"):
		v.queue_free()
		return
	var fb := HairRig.mesh_for("brows", "huste")
	var fd := HairRig.mesh_for("beard", "plnovous")
	var lb: ArrayMesh = HairRig.cached_facial_lod1("brows", "huste")["mesh"]
	var ld: ArrayMesh = HairRig.cached_facial_lod1("beard", "plnovous")["mesh"]
	check(lb != null and ld != null, "LOD1 obou částí je v cache spolu s plnou sítí")
	check(v.lod_tier() == 0 and br.mesh == fb and bd.mesh == fd and br.visible and bd.visible, "stupeň 0: plné sítě obočí i vousů")
	var mat_b: ShaderMaterial = v.hair_material("brows")
	var dens_b = mat_b.get_shader_parameter("density") if mat_b != null else null
	v.lod_override = 1
	await get_tree().process_frame
	check(v.lod_tier() == 1 and br.mesh == lb and bd.mesh == ld and br.visible and bd.visible, "stupeň 1: LOD1 obočí i vousů vidět")
	var wb := _weights_ok(v, br)
	var wd := _weights_ok(v, bd)
	check((wb[0] as Array).is_empty() and (wd[0] as Array).is_empty() and int(wd[1]) > 0,
		"stupeň 1: váhy klíčů LOD1 = CharacterData (obočí %d, vousy %d nenulových)" % [int(wb[1]), int(wd[1])], str(wb[0]) + str(wd[0]))
	check(mat_b != null and v.hair_material("brows") == mat_b and is_equal_approx(float(mat_b.get_shader_parameter("density")), float(dens_b))
		and absf(float(dens_b) - 0.3) < 0.01, "materiál obočí zůstává (hustota 0,3 – LOD1 ji respektuje přes přeškálované c0.x)")
	check(br.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and bd.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"stupeň 1: obočí a vousy bez stínu (beze změny proti kroku 1)")
	v.lod_override = 2
	await get_tree().process_frame
	check(not br.visible and not bd.visible and br.mesh == lb, "stupeň 2: skryté, síť se při 1 → 2 nemění")
	v.lod_override = 1
	await get_tree().process_frame
	check(br.visible and bd.visible and br.mesh == lb and bd.mesh == ld, "2 → 1: zpět LOD1")
	# změna stylu a tvaru přímo ve stupni 1
	look["hair"] = {"style": "kratke", "brows": "oblouk", "facial": "kozi_bradka"}
	look["face"] = {"jaw_width": -0.4}
	v.apply_look(look)
	await get_tree().process_frame
	var lb2: ArrayMesh = HairRig.cached_facial_lod1("brows", "oblouk")["mesh"]
	var ld2: ArrayMesh = HairRig.cached_facial_lod1("beard", "kozi_bradka")["mesh"]
	wd = _weights_ok(v, bd)
	check(lb2 != null and ld2 != null and br.mesh == lb2 and bd.mesh == ld2 and (wd[0] as Array).is_empty(),
		"změna stylu i tvaru ve stupni 1: LOD1 nového obočí a kozí bradky s novými vahami", str(wd[0]))
	# knír je malá síť bez LOD1 → ve stupni 1 plná síť (a viditelná)
	look["hair"] = {"style": "kratke", "brows": "oblouk", "facial": "knir"}
	v.apply_look(look)
	await get_tree().process_frame
	wd = _weights_ok(v, bd)
	check(HairRig.cached_facial_lod1("beard", "knir")["mesh"] == null and bd.mesh == HairRig.mesh_for("beard", "knir") and bd.visible
		and (wd[0] as Array).is_empty(), "knír (bez LOD1) ve stupni 1: plná síť s aktuálními vahami", str(wd[0]))
	look["hair"] = {"style": "kratke", "brows": "oblouk", "facial": "zadne"}
	v.apply_look(look)
	await get_tree().process_frame
	check(not bd.visible and br.visible, "bez vousů ve stupni 1: vousy skryté, obočí zůstává")
	look["hair"] = {"style": "kratke", "brows": "oblouk", "facial": "bradka"}
	v.apply_look(look)
	await get_tree().process_frame
	v.lod_override = 0
	await get_tree().process_frame
	wd = _weights_ok(v, bd)
	check(br.mesh == HairRig.mesh_for("brows", "oblouk") and bd.mesh == HairRig.mesh_for("beard", "bradka") and bd.visible
		and (wd[0] as Array).is_empty(), "1 → 0: plné sítě s aktuálními vahami", str(wd[0]))
	var t0 := Time.get_ticks_usec()
	for i in 50:
		v.set_lod_tier(1)
		v.set_lod_tier(0)
	var sw := float(Time.get_ticks_usec() - t0) / 100.0
	results["switch_us"] = snappedf(sw, 1.0)
	check(sw < 2500.0, "přepnutí 0 ↔ 1 (skalp + obočí + vousy) %.0f µs (limit 2,5 ms)" % sw)
	v.queue_free()
	await get_tree().process_frame


func _test_nonblocking_async() -> void:
	section("cached_facial_lod1 nestaví; asynchronní stavba ve stupni 1")
	HairRig.clear_cache()
	var t0 := Time.get_ticks_usec()
	var r: Dictionary = HairRig.cached_facial_lod1("brows", "srostle")
	var us := Time.get_ticks_usec() - t0
	check(not bool(r["ready"]) and r["mesh"] == null and not HairRig.cached_facial_lod1("brows", "srostle")["ready"] and us < 2000,
		"cached_facial_lod1 před stavbou: ready=false, nic nepostaví (%d µs)" % us)
	check(bool(HairRig.cached_facial_lod1("scalp", "kratke")["ready"]) and HairRig.cached_facial_lod1("scalp", "kratke")["mesh"] == null,
		"jiná část než obočí/vousy: žádný obličejový LOD1")
	HairRig.async_build = true
	var v = SimVisual.new()
	v.lod_override = 1
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "kratke", "brows": "srostle", "facial": "licousy"}})
	await get_tree().process_frame
	var br: MeshInstance3D = v.hair_part("brows")
	var bd: MeshInstance3D = v.hair_part("beard")
	if br == null or bd == null:
		check(false, "uzly obočí a vousů existují")
	else:
		var done := await wait_until(_async_done.bind(br, bd), 40.0)
		check(done and br.mesh != null and bd.mesh != null, "po asynchronní stavbě ve stupni 1: LOD1 obočí i licousů vidět")
	HairRig.wait_for_builds()
	HairRig.async_build = false
	v.queue_free()
	await get_tree().process_frame


func _async_done(br: MeshInstance3D, bd: MeshInstance3D) -> bool:
	var rb: Dictionary = HairRig.cached_facial_lod1("brows", "srostle")
	var rd: Dictionary = HairRig.cached_facial_lod1("beard", "licousy")
	return bool(rb["ready"]) and bool(rd["ready"]) and br.visible and bd.visible and br.mesh == rb["mesh"] and bd.mesh == rd["mesh"]


## Trojúhelníků na kartu (všechny karty části mají stejný počet bodů pramene → stejný počet trojúhelníků).
func _tris_per_card(a: Array) -> int:
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var ids := {}
	for t in range(0, idx.size(), 3):
		ids[c0[idx[t] * 4]] = true
	return maxi(1, (idx.size() / 3) / maxi(1, ids.size()))
