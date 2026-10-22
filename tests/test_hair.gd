extends "res://tests/test_base.gd"
## C4b – vlasy, obočí a vousy z karet (HairBuilder + HairRig + hair.gdshader) a jejich zapojení do SimVisual.
## Kontroluje: každý účes / obočí / vousy ze schématu má síť v rozpočtu (holá hlava a strniště žádnou), vlasy
## neprostupují hlavou, obličej zůstává volný, sestavení je deterministické, přenesené morfy (délka krku, šířka
## hlavy) vlasy opravdu posunou, kosti a váhy jsou platné, SimVisual kreslí karty místo „helmy“ z GLB s vlastním
## materiálem, vzhled vlasů nezávisí na rodu ani jménu, a runtime kontroly krku z review ChatGPT #117.

const HairBuilder := preload("res://scripts/assets/hair_builder.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Res := preload("res://scripts/character/appearance_resolver.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")

## Tolerance průniku do hlavy (m) a povolený podíl vrcholů pod ní.
const PEN_TOL := 0.002
const PEN_MAX := 0.003


func _ready() -> void:
	watchdog_seconds = 110.0
	_run.call_deferred()


func _run() -> void:
	if HairRig.context().is_empty():
		check(false, "kontext vlasů (kůže hlavy z character.glb) je k dispozici")
		finish("test_hair")
		return
	_test_styles()
	_test_drape()
	_test_determinism()
	_test_mesh()
	await _test_visual()
	await _test_async()
	finish("test_hair")


# ---------------------------------------------------------------- styly a geometrie

func _test_styles() -> void:
	section("Katalog: každý styl ze schématu má síť v rozpočtu")
	var ctx := HairRig.context()
	# Radiální mapa hlavy BEZ uší (mapa HairBuilderu bere max. poloměr v binu včetně boltců – u uší by vlasy
	# vycházely „pod povrchem“, i když leží na skalpu).
	var hp: PackedVector3Array = ctx["hp"]
	var ear: PackedByteArray = ctx["ear"]
	var no_ear := PackedVector3Array()
	for i in hp.size():
		if ear[i] == 0:
			no_ear.append(hp[i])
	var hmap: PackedFloat32Array = HairBuilder.head_map(no_ear)
	var missing := []
	for st in Schema.HAIR_STYLES:
		if not HairBuilder.STYLES.has(st):
			missing.append(st)
	check(missing.is_empty(), "všech %d účesů ze schématu má definici" % Schema.HAIR_STYLES.size(), str(missing))
	check(Schema.BROW_STYLES.keys().all(func(k): return HairBuilder.BROWS.has(k)), "všechna obočí ze schématu mají tvar")
	check(Schema.FACIAL_HAIR.keys().all(func(k): return HairBuilder.BEARDS.has(k)), "všechny vousy ze schématu mají definici")
	var over := []
	var worst_pen := 0.0
	var pen_styles := []
	var face_hits := []
	var tri_txt := PackedStringArray()
	for st in Schema.HAIR_STYLES:
		var g := HairRig.geometry("scalp", st)
		var tris := HairBuilder.tri_count(g)
		tri_txt.append("%s %d" % [st, tris])
		if st == "holy":
			check(tris == 0, "holá hlava = žádná geometrie")
			continue
		if tris == 0 or tris > HairBuilder.BUDGET_SCALP:
			over.append("%s %d" % [st, tris])
		var pos: PackedVector3Array = g["pos"]
		var pen := 0
		var face := 0
		for p in pos:
			var q := p - HairBuilder.C
			var r := q.length()
			if p.y > 1.45 and r > 1e-5:
				var R := HairBuilder.head_r(hmap, q / r)
				if r < R - PEN_TOL:
					pen += 1
			if absf(p.x) < 0.045 and p.y > 1.595 and p.y < 1.70 and p.z > 0.06:
				face += 1
		var frac := float(pen) / maxf(1.0, pos.size())
		worst_pen = maxf(worst_pen, frac)
		if frac > PEN_MAX:
			pen_styles.append("%s %.2f %%" % [st, frac * 100.0])
		if face > 0:
			face_hits.append("%s %d" % [st, face])
	print("    trojúhelníky: " + ", ".join(tri_txt))
	check(over.is_empty(), "každý účes má 1 … %d trojúhelníků" % HairBuilder.BUDGET_SCALP, str(over))
	check(pen_styles.is_empty(), "vlasy neprostupují hlavou (pod povrchem > 2 mm nejvýš %.1f %% vrcholů)" % (PEN_MAX * 100.0),
		"%s (nejhůř %.2f %%)" % [str(pen_styles), worst_pen * 100.0])
	check(face_hits.is_empty(), "oči, nos a ústa zůstávají volné (žádný vlas před obličejem)", str(face_hits))
	var bo := []
	for b in Schema.BROW_STYLES:
		var t := HairBuilder.tri_count(HairRig.geometry("brows", b))
		if t == 0 or t > HairBuilder.BUDGET_BROWS:
			bo.append("%s %d" % [b, t])
	check(bo.is_empty(), "každé obočí má 1 … %d trojúhelníků" % HairBuilder.BUDGET_BROWS, str(bo))
	var fo := []
	for f in Schema.FACIAL_HAIR:
		var t := HairBuilder.tri_count(HairRig.geometry("beard", f))
		var empty_ok: bool = f == "zadne" or f == "strniste"
		if (empty_ok and t != 0) or (not empty_ok and (t == 0 or t > HairBuilder.BUDGET_BEARD)):
			fo.append("%s %d" % [f, t])
	check(fo.is_empty(), "vousy: žádné/strniště bez karet (strniště kreslí kůže), ostatní 1 … %d" % HairBuilder.BUDGET_BEARD, str(fo))
	# obočí leží na kůži nad očima
	var gb := HairRig.geometry("brows", "prirozene")
	var ok_b := true
	for p in (gb["pos"] as PackedVector3Array):
		if p.y < HairBuilder.EYE.y or p.y > HairBuilder.EYE.y + 0.035 or absf(p.x) > 0.075:
			ok_b = false
			break
	check(ok_b, "obočí leží nad očima (ne na čele ani v očích)")
	# běh 17: boční části obočí chyběly (projekce mimo dosah) – zůstal jen chomáček u kořene nosu
	var brow_bad := []
	for b in HairBuilder.BROWS:
		var gb2 := HairRig.geometry("brows", b)
		var lo := 9.0
		var hi := -9.0
		for q in (gb2["pos"] as PackedVector3Array):
			lo = minf(lo, q.x)
			hi = maxf(hi, q.x)
		if int(gb2["stats"]["cards"]) < 2 * int(HairBuilder.BROWS[b][4]) or lo > -0.04 or hi < 0.04:
			brow_bad.append("%s %d karet, x %.3f…%.3f" % [b, int(gb2["stats"]["cards"]), lo, hi])
	check(brow_bad.is_empty(), "obočí: všechny karty postavené a sahají nad oči do stran (|x| ≥ 4 cm na obou stranách)", str(brow_bad))
	# ustupující vlasová linie: spánky a čelo mají nižší pořadí než týl
	var front := HairBuilder.recession_rank(HairBuilder.C + Vector3(0.0, 0.055, 0.085))
	var temple := HairBuilder.recession_rank(HairBuilder.C + Vector3(0.05, 0.06, 0.06))
	var nape := HairBuilder.recession_rank(HairBuilder.C + Vector3(0.0, -0.06, -0.09))
	check(temple < 1.0 and front < 1.0 and nape > 1.0,
		"ustupující linie: spánky a čelo ustoupí v rozsahu posuvníku, týl nikdy", "%.2f %.2f %.2f" % [temple, front, nape])


## Běh 17 (render v Blenderu): dlouhé copánky a dredy trčely vpředu 15–20 cm před hrudník a dlouhé vlasy
## odstávaly od zad (náklon gravitace platil po celé délce pramene a pramen si držel hybnost od kořene).
func _test_drape() -> void:
	section("Dlouhé vlasy leží na těle (hrudník, záda)")
	var ctx := HairRig.context()
	for st in ["copanky", "dredy", "dlouhe_rovne", "dlouhe_vlnite"]:
		var pos: PackedVector3Array = HairRig.geometry("scalp", st)["pos"]
		var front := PackedFloat32Array()
		var back := PackedFloat32Array()
		for q in pos:
			if q.y > 1.10 and q.y < 1.42 and absf(q.x) < 0.10:
				var R := HairBuilder.torso_r(ctx["tmap"], atan2(q.x, q.z - HairBuilder.TZ), q.y)
				var d := Vector2(q.x, q.z - HairBuilder.TZ).length() - R
				if q.z > 0.0:
					front.append(d)
				else:
					back.append(d)
		front.sort()
		back.sort()
		var fmax := front[front.size() - 1] if front.size() > 0 else 0.0
		check(fmax <= 0.09, "%s: vpředu nic dál než 9 cm od hrudníku" % st, "%.1f cm" % (fmax * 100.0))
		if back.size() > 10:
			var med := back[back.size() / 2]
			var p90 := back[int(back.size() * 0.9)]
			check(med <= 0.05 and p90 <= 0.09, "%s: vzadu vlasy leží na zádech (medián ≤ 5 cm, p90 ≤ 9 cm)" % st, "%.1f / %.1f cm" % [med * 100.0, p90 * 100.0])


## Review Gemini (běh 17): první sestavení účesu trvá 0,25–1 s – ve hře se proto staví ve WorkerThreadPool
## a postava mezitím ukazuje helmu z GLB.
func _test_async() -> void:
	section("Asynchronní stavba účesu (hra)")
	HairRig.clear_cache()
	HairRig.async_build = true
	var v := SimVisual.new()
	v.apply_look(_snap({"hair": {"style": "kudrnate", "facial": "zadne"}}))
	add_child(v)
	await get_tree().process_frame
	check(v.hair_waiting() and HairRig.is_pending("scalp", "kudrnate"),
		"nový účes se staví ve vlákně a postava zatím ukazuje helmu z GLB (hra se nezasekne)")
	var t0 := Time.get_ticks_msec()
	while HairRig.is_pending("scalp", "kudrnate") and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	await get_tree().process_frame
	var sc := v.hair_part("scalp")
	check(not v.hair_waiting() and sc.visible and sc.mesh != null and sc.mesh == HairRig.mesh_for("scalp", "kudrnate"),
		"po dostavění se helma vymění za karty", "%d ms" % (Time.get_ticks_msec() - t0))
	if sc.mesh != null:
		var sync_mesh := HairRig.build_mesh(HairRig.geometry("scalp", "kudrnate"), false)
		var a: PackedVector3Array = sc.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = sync_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(a == b and sc.mesh.get_blend_shape_count() == sync_mesh.get_blend_shape_count(),
			"síť z vlákna je stejná jako synchronní (determinismus mezi peery)")
		var ni := sc.find_blend_shape_by_name("b_neck_len")
		check(ni >= 0, "po výměně dostanou karty i váhy morfů (apply_face_shape)")
	# vlastník zrušený během stavby: nic nespadne, síť se dostaví do cache
	var gone := SimVisual.new()
	gone.apply_look(_snap({"hair": {"style": "mikado", "facial": "zadne"}}))
	add_child(gone)
	await get_tree().process_frame
	gone.free()
	t0 = Time.get_ticks_msec()
	while HairRig.is_pending("scalp", "mikado") and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	await get_tree().process_frame
	check(not HairRig.is_pending("scalp", "mikado") and HairRig.mesh_for("scalp", "mikado") != null,
		"postava zrušená během stavby nic nerozbije (síť je v cache pro další)")
	HairRig.async_build = false
	v.queue_free()
	await get_tree().process_frame


func _sig(g: Dictionary) -> String:
	var pos: PackedVector3Array = g["pos"]
	return "%d:%s" % [pos.size(), pos.to_byte_array().hex_encode().md5_text()]


func _test_determinism() -> void:
	section("Determinismus")
	var a := _sig(HairRig.geometry("scalp", "dlouhe_vlnite"))
	var b := _sig(HairRig.geometry("scalp", "dlouhe_vlnite"))
	HairRig.clear_cache()
	var c := _sig(HairRig.geometry("scalp", "dlouhe_vlnite"))
	check(a == b and b == c, "stejný účes → bit po bitu stejná síť (i po vymazání cache) – stejné na všech peerech")
	check(_sig(HairRig.geometry("beard", "plnovous")) == _sig(HairRig.geometry("beard", "plnovous")), "vousy deterministicky")
	check(_sig(HairRig.geometry("scalp", "kratke")) != _sig(HairRig.geometry("scalp", "kratke_kudrny")), "různé účesy = různé sítě")


func _test_mesh() -> void:
	section("Síť: přenesené morfy, kosti, atributy")
	var t0 := Time.get_ticks_msec()
	var m := HairRig.mesh_for("scalp", "kratke")
	var ms := Time.get_ticks_msec() - t0
	check(m != null and m.get_surface_count() == 1, "síť účesu se postaví", "%d ms" % ms)
	if m == null:
		return
	var names := []
	for i in m.get_blend_shape_count():
		names.append(String(m.get_blend_shape_name(i)))
	check(names.has("b_neck_len"), "vlasy převzaly délku krku (b_neck_len)", str(names))
	check(names.any(func(n): return String(n).begins_with("head_")), "vlasy převzaly tvar lebky (head_*)")
	check(m.get_blend_shape_count() <= 64, "počet klíčů v mezích (%d)" % m.get_blend_shape_count())
	var arr: Array = m.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bl: Array = m.surface_get_blend_shape_arrays(0)
	var top := 0
	for i in pos.size():
		if pos[i].y > pos[top].y:
			top = i
	var ni := names.find("b_neck_len")
	var dy := ((bl[ni] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[top].y - pos[top].y
	check(absf(dy - 0.015) < 0.002, "délka krku +1 zvedne temeno vlasů o ~15 mm (jako hlavu)", "%.1f mm" % (dy * 1000.0))
	var hw := -1
	for i in names.size():
		if String(names[i]).begins_with("head_width"):
			hw = i
			break
	if hw >= 0:
		var mx := 0.0
		var tv: PackedVector3Array = (bl[hw] as Array)[Mesh.ARRAY_VERTEX]
		for i in pos.size():
			mx = maxf(mx, absf(tv[i].x - pos[i].x))
		check(mx > 0.002, "šířka hlavy posune vlasy do stran", "%.1f mm" % (mx * 1000.0))
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride := bones.size() / maxi(pos.size(), 1)
	var bad := 0
	for vi in pos.size():
		var s := 0.0
		for j in stride:
			s += wts[vi * stride + j]
			if bones[vi * stride + j] < 0 or bones[vi * stride + j] >= 17:
				bad += 1
		if absf(s - 1.0) > 0.01:
			bad += 1
	check(bones.size() > 0 and bad == 0, "váhy kostí: součet 1 a indexy v rozsahu sdíleného Skin (17)", "%d chyb" % bad)
	check(arr[Mesh.ARRAY_CUSTOM0] != null and (arr[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size() == pos.size() * 4,
		"atributy pramenů (CUSTOM0: náhoda, pořadí ústupu, vrstva, druh)")
	check(HairRig.mesh_for("scalp", "holy") == null and HairRig.mesh_for("beard", "zadne") == null, "holá hlava / bez vousů = žádná síť")
	check(HairRig.mesh_for("scalp", "kratke") == m, "síť se sdílí (cache na účes)")
	var sh := HairRig.shader()
	var uni := []
	if sh != null:
		for u in sh.get_shader_uniform_list():
			uni.append(String(u["name"]))
	check(sh != null and ["hair_color", "grey", "hairline", "density", "fine"].all(func(x): return uni.has(x)),
		"shader vlasů se načte a má parametry", str(uni))


# ---------------------------------------------------------------- SimVisual

func _snap(extra: Dictionary) -> Dictionary:
	var s := {"identity": {"first_name": "Alex", "grammar": "f"}, "body": {"height_cm": 175.0},
		"hair": {"style": "dlouhe_vlnite", "melanin": 0.35, "red": 0.2, "grey": 0.3, "hairline": 0.0,
			"brows": "huste", "facial": "plnovous", "facial_density": 0.8}}
	for g in extra:
		if s.has(g) and typeof(extra[g]) == TYPE_DICTIONARY:
			(s[g] as Dictionary).merge(extra[g], true)
		else:
			s[g] = extra[g]
	return s


func _new_visual(snap: Dictionary) -> SimVisual:
	var v := SimVisual.new()
	v.apply_look(snap)
	add_child(v)
	await get_tree().process_frame
	return v


func _test_visual() -> void:
	section("SimVisual: karty místo helmy z GLB")
	var v := await _new_visual(_snap({}))
	check(v.uses_model() and v.hair_part("scalp") != null, "postava má části vlasů z karet")
	if v.hair_part("scalp") == null:
		v.queue_free()
		return
	var sc := v.hair_part("scalp")
	check(sc.visible and sc.mesh == HairRig.mesh_for("scalp", "dlouhe_vlnite"), "vlasy podle účesu ze snapshotu")
	var helm := 0
	for g in ["hair_short", "hair_long"]:
		for mi in AssetLibrary.parts_in_group(v._model, g):
			if mi.visible:
				helm += 1
	check(helm == 0, "„helma“ z GLB je skrytá")
	check(v.hair_part("brows").visible and v.hair_part("beard").visible, "obočí a plnovous jsou karty")
	check(sc.skin != null and sc.get_node_or_null(sc.skeleton) is Skeleton3D, "vlasy jsou napojené na kostru (Skin hlavy)")
	var mat := v.hair_material("scalp")
	var hl: Dictionary = v.look_params["hair_look"]
	var lin := (hl["natural"] as Color).srgb_to_linear()
	var hc: Vector3 = mat.get_shader_parameter("hair_color")
	check(hc.distance_to(Vector3(lin.r, lin.g, lin.b)) < 1e-4 and absf(float(mat.get_shader_parameter("grey")) - 0.3) < 1e-4,
		"materiál: přirozená barva bez šedin + šediny po vlasech (grey 0,3)")
	check(v.hair_material("brows") != mat and v.hair_material("scalp") != (await _new_visual(_snap({}))).hair_material("scalp"),
		"každá část i postava má vlastní materiál")
	section("Morfy obličeje a těla jdou i na vlasy")
	var v2 := await _new_visual(_snap({"body": {"neck_length": 1.0, "body_fat": 0.9}}))
	var sc2 := v2.hair_part("scalp")
	var ni := sc2.find_blend_shape_by_name("b_neck_len")
	check(ni >= 0 and absf(sc2.get_blend_shape_value(ni) - 1.0) < 1e-3, "délka krku +1 → b_neck_len 1 na vlasech")
	var vneg := await _new_visual(_snap({"body": {"neck_length": -1.0}}))
	var hn := -1.0
	for mi in AssetLibrary.parts_in_group(vneg._model, "head"):
		var k: int = mi.find_blend_shape_by_name("b_neck_len")
		if k >= 0:
			hn = mi.get_blend_shape_value(k)
	var sneg := vneg.hair_part("scalp")
	check(absf(hn + 1.0) < 1e-3 and absf(sneg.get_blend_shape_value(sneg.find_blend_shape_by_name("b_neck_len")) + 1.0) < 1e-3,
		"#117: záporná délka krku −1 dorazí v Godotu na hlavu i vlasy (ne ořez na 0)")
	section("Účes bez vlasů, bez vousů")
	var v3 := await _new_visual(_snap({"hair": {"style": "holy", "facial": "zadne"}}))
	check(not v3.hair_part("scalp").visible and not v3.hair_part("beard").visible and v3.hair_part("brows").visible,
		"holá hlava a bez vousů: jen obočí")
	v3.apply_look(_snap({"hair": {"style": "afro"}}))
	check(v3.hair_part("scalp").visible and v3.hair_part("scalp").mesh == HairRig.mesh_for("scalp", "afro"),
		"změna účesu za běhu přepne síť")
	section("Nezávislost a determinismus mezi peery (#117)")
	var a := Res.resolve(_snap({}))
	var b := Res.resolve(_snap({"identity": {"first_name": "Bohumil", "grammar": "m", "gender_identity": "muz"}}))
	check(str(a["hair_look"]) == str(b["hair_look"]), "jméno, rod ani identita vlasy nemění")
	var net: Dictionary = JSON.parse_string(JSON.stringify(_snap({"body": {"neck_length": -0.4}, "face": {"head_width": 0.6}})))
	var p1 := await _new_visual(_snap({"body": {"neck_length": -0.4}, "face": {"head_width": 0.6}}))
	var p2 := await _new_visual(net)
	var same := true
	for part in SimVisual.HAIR_PARTS:
		var m1 := p1.hair_part(part)
		var m2 := p2.hair_part(part)
		if m1.mesh != m2.mesh:
			same = false
			continue
		if m1.mesh == null:
			continue
		for i in m1.mesh.get_blend_shape_count():
			if m1.get_blend_shape_value(i) != m2.get_blend_shape_value(i):
				same = false
	check(same, "snapshot po síti (JSON) → stejná síť vlasů i stejné váhy morfů na obou peerech")
	var hk := Res.resolve_hair_look({"hair": {"style": "neexistuje", "brows": 7, "facial": "<b>"}})
	check(hk["style"] == "kratke" and hk["brow_style"] == "prirozene" and hk["beard_style"] == "zadne",
		"neznámé styly → výchozí (nevybere neexistující síť)")
	var bad := Res.resolve_hair_look({"hair": {"grey": NAN, "hairline": "x", "brow_density": INF, "melanin": NAN,
		"dyed": true, "dye_color": "x3366cc"}})
	var finite := true
	for k in ["grey", "hairline", "brow_density", "facial_density", "brow_grey", "facial_grey"]:
		var x := float(bad[k])
		finite = finite and not is_nan(x) and x >= 0.0 and x <= 1.0
	var nc: Color = bad["natural"]
	finite = finite and not (is_nan(nc.r) or is_nan(nc.g) or is_nan(nc.b))
	check(finite, "poškozené hodnoty vlasů (NaN, ∞, text, barva bez #) → konečné výchozí hodnoty", str(bad))
	var dy := Res.resolve_hair_look({"hair": {"dyed": true, "dye_color": "#3366cc", "grey": 0.8, "melanin": 0.9}})
	check((dy["natural"] as Color).b > 0.5 and float(dy["grey"]) < 0.3 and (dy["brow"] as Color).b < 0.2,
		"barvené vlasy: barva jen na hlavě, šediny z velké části překryté, obočí přirozené")
	for n in [v, v2, vneg, v3, p1, p2]:
		n.queue_free()
	await get_tree().process_frame
