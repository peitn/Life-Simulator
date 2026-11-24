extends "res://tests/test_base.gd"
## C-LOD krok 2 (běh main-claude-1794554507, 13. 11. 2026): proxy účesu pro dav.
## 1) Geometrie pro VŠECHNY účesy HairBuilder.STYLES: rozpočet trojúhelníků, konečné hodnoty, platné indexy,
##    orientace ven, jednotkové normály, skin (kosti + váhy se součtem 1), jména klíčů ⊂ hlava ∪ tělo,
##    holá hlava = žádná proxy, statistiky a čas stavby.
## 2) Silueta: nezávislý CPU rasterizér (ortho 4 mm; zepředu, z boku, shora), maska (hlava ∪ tělo ∪ vlasy)
##    – IoU proxy vs. karty musí být ≥ IoU helmy z GLB (dosavadní stupeň 2) v KAŽDÉM pohledu a ≥ 0,65.
## 3) Přenos morfů: nejsilnější klíč hlavy na kartách hýbe i proxy (srovnatelná výchylka).
## 4) Determinismus: po clear_cache vznikne bitově stejná proxy (síť je na všech peerech stejná).
## 5) SimVisual: stupeň 2 = proxy (helma i karty skryté), stupeň 0/1 = karty; materiál = helma postavy;
##    váhy klíčů proxy = váhy z CharacterData; změna účesu v davu; plešatá postava; asynchronní stavba
##    (během čekání helma, pak proxy); výkon přepnutí.

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const HB := preload("res://scripts/assets/hair_builder.gd")
const AL := preload("res://scripts/assets/asset_library.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

const RES := 0.004
const W := 180
const H := 220
const VIEWS := [0, 1, 3]
const VIEW_NAMES := ["zepředu", "z boku", "", "shora"]
const TRI_BUDGET := 1500

var results := {}


func _init() -> void:
	watchdog_seconds = 420.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	_test_geometry()
	_test_silhouette()
	_test_morphs()
	_test_determinism()
	await _test_visual()
	await _test_async()
	finish("test_hair_proxy")


# ------------------------------------------------------------------ 1) geometrie

func _test_geometry() -> void:
	section("Geometrie proxy pro všechny účesy")
	var src := HairRig.source()
	if not check(not src.is_empty(), "zdroj character.glb dostupný"):
		return
	var names := {}
	for k in src["head"]["keys"]:
		names[k] = true
	for k in src["body"]["keys"]:
		names[k] = true
	for style in HB.STYLES.keys():
		var t0 := Time.get_ticks_usec()
		var pm := HairRig.proxy_mesh(style)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if (HB.STYLES[style] as Dictionary).is_empty():
			check(pm == null and bool(HairRig.cached_proxy(style)["ready"]), "%s: holá hlava → žádná proxy (v cache jako null)" % style)
			continue
		if not check(pm != null, "%s: proxy existuje" % style):
			continue
		var a := pm.surface_get_arrays(0)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var bones = a[Mesh.ARRAY_BONES]
		var wts = a[Mesh.ARRAY_WEIGHTS]
		var tris := idx.size() / 3
		var finite := true
		for p in pos:
			finite = finite and is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
		var idx_ok := idx.size() % 3 == 0
		for i in idx:
			idx_ok = idx_ok and i >= 0 and i < pos.size()
		# Konvence Godotu (jako síť hlavy z GLB): přední strana po směru hodinových ručiček → (b−a)×(c−a) míří
		# dovnitř a proti vrcholovým normálám (ty míří ven).
		# Hladké normály se na strmých stěnách (vlasy ~40 cm vedle buňky schované pod kůží) mohou s plochou rozcházet –
		# to je vlastnost hladkého stínování na ostré hraně, ne obrácená plocha: proto ≥ 98 % zvlášť.
		var out_ok := 0
		var nrm_ok := 0
		for t in range(0, idx.size(), 3):
			var pa := pos[idx[t]]
			var pb := pos[idx[t + 1]]
			var pc := pos[idx[t + 2]]
			var fn := (pb - pa).cross(pc - pa)
			var vn := nrm[idx[t]] + nrm[idx[t + 1]] + nrm[idx[t + 2]]
			if fn.dot((pa + pb + pc) / 3.0 - HB.C) <= 1e-12:
				out_ok += 1
			if fn.dot(vn) <= 0.0 and vn.dot((pa + pb + pc) / 3.0 - HB.C) >= 0.0:
				nrm_ok += 1
		check(nrm_ok >= int(ceil(0.98 * tris)), "%s: vrcholové normály souhlasí s plochou u %d/%d tr. (≥ 98 %%)" % [style, nrm_ok, tris])
		var unit := true
		for nn in nrm:
			unit = unit and absf(nn.length() - 1.0) < 1e-3
		# Gemini audit 13. 11. (bod 4): žádné degenerované trojúhelníky (plocha < 1 mm²) – tangenty/normály bez NaN
		var min_area := INF
		for t in range(0, idx.size(), 3):
			min_area = minf(min_area, 0.5 * (pos[idx[t + 1]] - pos[idx[t]]).cross(pos[idx[t + 2]] - pos[idx[t]]).length())
		check(min_area > 1e-6, "%s: nejmenší trojúhelník %.2f mm² (> 1 mm²)" % [style, min_area * 1e6])
		var skin_ok := bones != null and wts != null and (bones as PackedInt32Array).size() > 0
		if skin_ok:
			var stride: int = (wts as PackedFloat32Array).size() / pos.size()
			for vi in pos.size():
				var s := 0.0
				for j in stride:
					s += (wts as PackedFloat32Array)[vi * stride + j]
				skin_ok = skin_ok and absf(s - 1.0) < 0.01
		var keys_ok := pm.get_blend_shape_count() > 0
		for i in pm.get_blend_shape_count():
			keys_ok = keys_ok and names.has(String(pm.get_blend_shape_name(i)))
		var st: Dictionary = HairRig.build_stats.get(HairRig.PROXY_PREFIX + style, {})
		check(tris <= TRI_BUDGET and tris == int(st.get("tris", -1)), "%s: %d trojúhelníků (rozpočet %d)" % [style, tris, TRI_BUDGET])
		check(finite and idx_ok, "%s: konečné vrcholy, platné indexy" % style)
		check(out_ok == tris, "%s: přední strana ven v konvenci Godotu – všechny trojúhelníky (%d/%d)" % [style, out_ok, tris])
		check(unit and nrm.size() == pos.size(), "%s: jednotkové normály" % style)
		check(skin_ok, "%s: skin – kosti a váhy se součtem 1" % style)
		check(keys_ok, "%s: %d klíčů, všechna jména z hlavy/těla" % [style, pm.get_blend_shape_count()])
		check(pm.resource_name == "hair_proxy", "%s: resource_name hair_proxy" % style)
		# Proxy se staví jednou za hru a účes ve stejné úloze WorkerThreadPool jako karty skalpu (hra nečeká; do té
		# doby helma). Náklad = _arrays_from (vazba na kůži + přenos klíčů, GDScript). Měřeno 13. 11.: 150–300 ms
		# (i při souběžné regresi), tj. 3–17 % stavby karet – u krátkých účesů je podíl vyšší, proto absolutní mez.
		var pms := float(st.get("ms", 999.0))
		check(pms < 400.0, "%s: proxy %.1f ms navíc ke kartám = %.1f %% stavby %.0f ms (limit 400 ms)" % [style, pms, 100.0 * pms / maxf(ms, 1.0), ms])


# ------------------------------------------------------------------ 2) silueta

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


func _test_silhouette() -> void:
	section("Silueta proxy vs. karty (a dosavadní helma)")
	var src := HairRig.source()
	var ctx := HairRig.context()
	var base := {}
	for view in VIEWS:
		var m := PackedByteArray()
		m.resize(W * H)
		_raster(m, src["head"]["pos"], src["head"]["idx"], view)
		_raster(m, src["body"]["pos"], src["body"]["idx"], view)
		base[view] = m
	var model := AL.instantiate("character")
	var helm := {}
	for gname in ["hair_short", "hair_long"]:
		var vv := PackedVector3Array()
		var ii := PackedInt32Array()
		for mi in AL.parts_in_group(model, gname):
			var arr := (mi as MeshInstance3D).mesh.surface_get_arrays(0)
			var off := vv.size()
			vv.append_array(arr[Mesh.ARRAY_VERTEX])
			for x in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
				ii.append(x + off)
		helm[gname] = [vv, ii]
	model.free()
	if not check(not (helm["hair_short"][0] as PackedVector3Array).is_empty(), "helma z GLB k porovnání"):
		return
	var t0 := Time.get_ticks_usec()
	var sum_p := 0.0
	var sum_h := 0.0
	var n := 0
	for style in HB.STYLES.keys():
		if (HB.STYLES[style] as Dictionary).is_empty():
			continue
		var g := HairRig.geometry("scalp", style)
		var pm := HairRig.proxy_mesh(style)
		var pa := pm.surface_get_arrays(0)
		var hv := "hair_long" if Schema.LONG_HAIR.has(style) else "hair_short"
		var row := {}
		var worse := []
		var low := []
		for view in VIEWS:
			var mc: PackedByteArray = (base[view] as PackedByteArray).duplicate()
			_raster(mc, g["pos"], g["idx"], view)
			var mp: PackedByteArray = (base[view] as PackedByteArray).duplicate()
			_raster(mp, pa[Mesh.ARRAY_VERTEX], pa[Mesh.ARRAY_INDEX], view)
			var mh: PackedByteArray = (base[view] as PackedByteArray).duplicate()
			_raster(mh, helm[hv][0], helm[hv][1], view)
			var ip := _iou(mc, mp)
			var ih := _iou(mc, mh)
			row[VIEW_NAMES[view]] = [snappedf(ip, 0.001), snappedf(ih, 0.001)]
			sum_p += ip
			sum_h += ih
			n += 1
			if ip < ih:
				worse.append(VIEW_NAMES[view])
			if ip < 0.65:
				low.append(VIEW_NAMES[view])
		results[style] = row
		check(worse.is_empty(), "%s: proxy ≥ helma ve všech pohledech %s" % [style, str(row)], str(worse))
		check(low.is_empty(), "%s: IoU proxy ≥ 0,65" % style, str(low))
	var mp_ := sum_p / maxf(n, 1)
	var mh_ := sum_h / maxf(n, 1)
	check(mp_ >= 0.88 and mp_ > mh_ + 0.1, "průměrné IoU proxy %.3f vs. helma %.3f (proxy ≥ 0,88, o > 0,1 lepší)" % [mp_, mh_])
	print("SILHOUETTE_MS ", (Time.get_ticks_usec() - t0) / 1000)


# ------------------------------------------------------------------ 3) morfy

func _test_morphs() -> void:
	section("Přenos morfů na proxy")
	for style in ["kratke", "dlouhe_rovne", "afro"]:
		var cards := HairRig.mesh_for("scalp", style)
		var pm := HairRig.proxy_mesh(style)
		var best := ""
		var best_d := 0.0
		var ca := cards.surface_get_arrays(0)
		var cp: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
		var cb := cards.surface_get_blend_shape_arrays(0)
		for i in cards.get_blend_shape_count():
			var nm := String(cards.get_blend_shape_name(i))
			if nm.begins_with("ex_"):
				continue
			var tv: PackedVector3Array = (cb[i] as Array)[Mesh.ARRAY_VERTEX]
			var d := 0.0
			for j in cp.size():
				d = maxf(d, (tv[j] - cp[j]).length())
			if d > best_d:
				best_d = d
				best = nm
		var pi := -1
		for i in pm.get_blend_shape_count():
			if String(pm.get_blend_shape_name(i)) == best:
				pi = i
		var pd := 0.0
		if pi >= 0:
			var pp: PackedVector3Array = pm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var tv: PackedVector3Array = (pm.surface_get_blend_shape_arrays(0)[pi] as Array)[Mesh.ARRAY_VERTEX]
			for j in pp.size():
				pd = maxf(pd, (tv[j] - pp[j]).length())
		check(pi >= 0 and best_d > 0.001 and pd > best_d * 0.3 and pd < best_d * 3.0,
			"%s: nejsilnější klíč karet „%s“ (%.1f mm) hýbe i proxy (%.1f mm)" % [style, best, best_d * 1000.0, pd * 1000.0])


# ------------------------------------------------------------------ 4) determinismus

func _test_determinism() -> void:
	section("Determinismus")
	var a := HairRig.proxy_mesh("dlouhe_vlnite")
	var arr_a := a.surface_get_arrays(0)
	var bl_a := a.surface_get_blend_shape_arrays(0)
	var names_a := []
	for i in a.get_blend_shape_count():
		names_a.append(String(a.get_blend_shape_name(i)))
	HairRig.clear_cache()
	check(not bool(HairRig.cached_proxy("dlouhe_vlnite")["ready"]), "clear_cache vymaže i proxy")
	var b := HairRig.proxy_mesh("dlouhe_vlnite")
	var arr_b := b.surface_get_arrays(0)
	var names_b := []
	for i in b.get_blend_shape_count():
		names_b.append(String(b.get_blend_shape_name(i)))
	var same: bool = arr_a[Mesh.ARRAY_VERTEX] == arr_b[Mesh.ARRAY_VERTEX] and arr_a[Mesh.ARRAY_INDEX] == arr_b[Mesh.ARRAY_INDEX] \
		and arr_a[Mesh.ARRAY_NORMAL] == arr_b[Mesh.ARRAY_NORMAL] and arr_a[Mesh.ARRAY_BONES] == arr_b[Mesh.ARRAY_BONES] \
		and arr_a[Mesh.ARRAY_WEIGHTS] == arr_b[Mesh.ARRAY_WEIGHTS] and names_a == names_b
	var bl_b := b.surface_get_blend_shape_arrays(0)
	for i in mini(bl_a.size(), bl_b.size()):
		same = same and (bl_a[i] as Array)[Mesh.ARRAY_VERTEX] == (bl_b[i] as Array)[Mesh.ARRAY_VERTEX]
	check(same and a != b, "nová stavba po clear_cache je bitově stejná (vrcholy, indexy, normály, skin, klíče)")
	check(HairRig.proxy_mesh("dlouhe_vlnite") == b, "opakovaná žádost vrací sdílenou síť z cache")


# ------------------------------------------------------------------ 5) SimVisual

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


func _test_visual() -> void:
	section("SimVisual – stupeň 2 = proxy")
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "dlouhe_rovne"}, "body": {"body_fat": 0.6, "muscle": 0.4}})
	await get_tree().process_frame
	if not check(v._model != null and v.hair_proxy() != null, "postava s modelem a uzlem proxy"):
		v.queue_free()
		return
	var px: MeshInstance3D = v.hair_proxy()
	check(px.get_parent() == v.hair_part("scalp").get_parent() and px.skin == v.hair_part("scalp").skin,
		"proxy je pod stejnou kostrou se stejným Skin jako karty")
	check(px.mesh == HairRig.cached_proxy("dlouhe_rovne")["mesh"], "síť proxy = sdílená síť účesu z cache")
	check(px.material_override != null and px.material_override == v._mats.get("hair_main", px.material_override),
		"materiál proxy = materiál helmy postavy (kalibrovaná barva)")
	check(v.lod_tier() == 0 and not px.visible and v.hair_part("scalp").visible and not _helm(v), "stupeň 0: karty, proxy i helma skryté")
	v.lod_override = 2
	await get_tree().process_frame
	check(v.lod_tier() == 2 and px.visible and not v.hair_part("scalp").visible and not _helm(v),
		"stupeň 2: proxy vidět, karty i helma skryté")
	check(not v.hair_waiting(), "stupeň 2 s proxy se nehlásí jako čekání")
	var cmp := 0
	var nz := 0
	var bad := []
	for i in px.mesh.get_blend_shape_count():
		var nm := String(px.mesh.get_blend_shape_name(i))
		var e := _expected_weight(v, nm)
		cmp += 1
		if absf(e) > 1e-4:
			nz += 1
		if absf(px.get_blend_shape_value(i) - e) > 1e-5:
			bad.append(nm)
	check(bad.is_empty() and nz > 0, "váhy klíčů proxy = CharacterData (%d klíčů, %d nenulových)" % [cmp, nz], str(bad))
	# změna účesu v davu
	v.apply_look({"hair": {"style": "afro"}, "body": {"body_fat": 0.6, "muscle": 0.4}})
	await get_tree().process_frame
	check(px.mesh == HairRig.cached_proxy("afro")["mesh"] and px.visible and not _helm(v), "změna účesu v davu: proxy afra")
	# plešatá postava v davu
	v.apply_look({"hair": {"style": "holy"}})
	await get_tree().process_frame
	check(px.mesh == null and not px.visible and not _helm(v) and not v.hair_part("scalp").visible,
		"plešatá postava v davu: žádná proxy, helma ani karty")
	v.apply_look({"hair": {"style": "culik"}})
	await get_tree().process_frame
	check(px.visible and px.mesh == HairRig.cached_proxy("culik")["mesh"], "z plešaté zpět na culík: proxy")
	# zpět blízko
	v.lod_override = 0
	await get_tree().process_frame
	check(not px.visible and v.hair_part("scalp").visible and not _helm(v), "stupeň 0: zpět karty, proxy skrytá")
	# výkon přepnutí
	var t0 := Time.get_ticks_usec()
	for i in 50:
		v.set_lod_tier(2)
		v.set_lod_tier(0)
	var sw := float(Time.get_ticks_usec() - t0) / 100.0
	check(sw < 1500.0, "přepnutí stupně s proxy %.0f µs (limit 1,5 ms)" % sw)
	v.queue_free()
	await get_tree().process_frame


func _test_async() -> void:
	section("Asynchronní stavba: helma → proxy")
	HairRig.clear_cache()
	HairRig.async_build = true
	var v = SimVisual.new()
	v.lod_override = 2
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"hair": {"style": "kudrnate"}})
	await get_tree().process_frame
	var px: MeshInstance3D = v.hair_proxy()
	if px == null:
		check(false, "proxy uzel existuje")
	else:
		var waiting_ok := not px.visible and _helm(v)
		check(waiting_ok, "během stavby ve vlákně: helma vidět, proxy ne")
		var done := await wait_until(func(): return bool(HairRig.cached_proxy("kudrnate")["ready"]) and px.visible, 30.0)
		check(done and not _helm(v) and px.mesh == HairRig.cached_proxy("kudrnate")["mesh"], "po dokončení: proxy vidět, helma skrytá")
	HairRig.wait_for_builds()
	HairRig.async_build = false
	v.queue_free()
	await get_tree().process_frame
