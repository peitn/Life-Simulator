extends "res://tests/test_base.gd"
## C2 – tělo se shape keys: Catmull-Clark, LSX v4 (morfy, čtyřúhelníky), GLB blend shapes,
## mapování CharacterData → váhy/kosti/měřítka, aplikace v SimVisual (hodnoty blend shapes = data),
## klouby bez dvojího posunu, výška temene = height_cm, determinismus, výkon posuvníku.

const LSX := preload("res://scripts/assets/lsx_decoder.gd")
const Subdiv := preload("res://scripts/assets/subdiv.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const Schema := preload("res://scripts/character/character_schema.gd")


func _ready() -> void:
	watchdog_seconds = 120.0
	_test_subdiv()
	_test_lsx_v4()
	_test_glb()
	_test_mapping()
	_test_scales()
	_test_visual_apply()
	_test_skinning()
	_test_perf()
	finish("test_body_morphs")


# ---------------------------------------------------------------- Catmull-Clark

func _cube() -> Array:
	var v := PackedVector3Array()
	for z in [-1, 1]:
		for y in [-1, 1]:
			for x in [-1, 1]:
				v.append(Vector3(x, y, z))
	# Indexy: i = x + 2y + 4z (x,y,z ∈ {0,1}); plochy CCW zvenku.
	var q := PackedInt32Array([0, 2, 3, 1,  4, 5, 7, 6,  0, 1, 5, 4,  2, 6, 7, 3,  0, 4, 6, 2,  1, 3, 7, 5])
	return [v, q]


func _test_subdiv() -> void:
	section("Catmull-Clark (shoda s Blenderem/cc_matrix)")
	var c := _cube()
	var op := Subdiv.build(c[1], 8)
	check(not op.is_empty(), "uzavřená krychle se zjemní")
	if op.is_empty():
		return
	check(int(op["nv"]) == 26 and (op["quads"] as PackedInt32Array).size() == 96, "26 vrcholů a 24 ploch (%d)" % int(op["nv"]))
	var fine := Subdiv.apply_vec3(op, c[0])
	var corner: Vector3 = fine[7]
	check(corner.is_equal_approx(Vector3(5.0, 5.0, 5.0) / 9.0), "vrcholový bod rohu = 5/9 (%s)" % str(corner))
	var found_edge := false
	var found_face := false
	for p in fine:
		if p.is_equal_approx(Vector3(0.75, 0.75, 0.0)):
			found_edge = true
		if p.is_equal_approx(Vector3(1, 0, 0)):
			found_face = true
	check(found_edge and found_face, "hranový bod (3/4, 3/4, 0) a bod plochy (1, 0, 0)")
	# Linearita: zjemnění výchylky = rozdíl zjemnění (morf jemné sítě = zjemněný morf řídicí).
	var d := PackedVector3Array()
	var moved := PackedVector3Array()
	for i in 8:
		var dd := Vector3(sin(i), cos(i * 2.0), 0.1 * i)
		d.append(dd)
		moved.append(c[0][i] + dd)
	var a := Subdiv.apply_vec3(op, moved)
	var b := Subdiv.apply_vec3(op, d)
	var err := 0.0
	for i in fine.size():
		err = maxf(err, (a[i] - fine[i] - b[i]).length())
	check(err < 1e-5, "operátor je lineární (chyba %.7f)" % err)
	var nr := Subdiv.quad_normals(fine, op["quads"])
	var outward := 0
	for i in fine.size():
		if nr[i].dot(fine[i]) > 0.0:
			outward += 1
	check(outward == fine.size(), "normály krychle míří ven (%d/%d)" % [outward, fine.size()])
	# Váhy kostí se interpolují a zůstávají normalizované.
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	for i in 8:
		bones.append_array(PackedInt32Array([i % 3, (i + 1) % 3, 0, 0]))
		wts.append_array(PackedFloat32Array([0.7, 0.3, 0.0, 0.0]))
	var bw := Subdiv.apply_weights(op, bones, wts)
	var bad := 0
	for i in int(op["nv"]):
		var s := 0.0
		for k in 4:
			s += (bw["weights"] as PackedFloat32Array)[i * 4 + k]
		if absf(s - 1.0) > 1e-4:
			bad += 1
	check(bad == 0, "váhy kostí po zjemnění sčítají na 1")
	# Otevřená síť (chybí plocha) a neplatné indexy se odmítnou.
	var open_q: PackedInt32Array = (c[1] as PackedInt32Array).slice(0, 20)
	check(Subdiv.build(open_q, 8).is_empty(), "otevřená síť se odmítne")
	check(Subdiv.build(PackedInt32Array([0, 1, 2, 99]), 4).is_empty(), "index mimo rozsah se odmítne")


# ---------------------------------------------------------------- LSX v4

func _body_dec() -> Dictionary:
	return LSX.decode(FileAccess.get_file_as_string("res://assets/src/body.lsx"))


func _test_lsx_v4() -> void:
	section("LSX v4: řídicí síť těla, morfy, zjemnění, normály, poškozená data")
	var dec := _body_dec()
	check(not dec.is_empty() and int(dec["head"]["v"]) == 4, "body.lsx je LSX v4")
	if dec.is_empty():
		return
	var h: Dictionary = dec["head"]
	check(h["morphs"] == BodyMorphs.MORPHS, "pořadí morfů v souboru = BodyMorphs.MORPHS", str(h["morphs"]))
	var meta: Dictionary = h["meta"]
	var bd: Dictionary = meta.get("basis_defaults", {})
	var mism := []
	for f in bd:
		if absf(float(bd[f]) - BodyMorphs.default_of(f)) > 1e-6:
			mism.append(f)
	check(not bd.is_empty() and mism.is_empty(), "základní síť z Blenderu = výchozí hodnoty schématu", str(mism))
	var part: Dictionary = h["parts"][0]
	check(String(part.get("prim")) == "quad" and int(part["nv"]) == 868, "řídicí síť: 868 vrcholů, čtyřúhelníky")
	var q := LSX.decode_quad_part(part, dec["blob"], true, h["morphs"], 17)
	check(not q.is_empty(), "zjemnění proběhne")
	if q.is_empty():
		return
	check(int(q["fine_tris"]) == int(meta.get("fine_tris", -1)) and int(q["fine_tris"]) == 6928, "6 928 trojúhelníků po zjemnění (jako v Blenderu)")
	check((q["surfaces"] as Array).size() == 4, "4 povrchy podle materiálů (kůže, triko, kalhoty, boty)")
	# Velikost morfů na jemné síti odpovídá Blenderu (cíl ± rezidua nejmenších čtverců ± kvantizace).
	var stats: Dictionary = meta.get("key_stats", {})
	var resid: Dictionary = meta.get("key_resid", {})
	var bad := []
	for k in h["morphs"]:
		var d: PackedVector3Array = q["morphs"][k]
		var mx := 0.0
		for v in d:
			mx = maxf(mx, v.length())
		var target := float(stats.get(k, -1.0))
		if absf(mx - target) > float(resid.get(k, 0.0)) + 0.003:
			bad.append("%s %.4f/%.4f" % [k, mx, target])
	check(bad.is_empty(), "amplituda všech 10 morfů sedí s Blenderem", str(bad))
	# Lokálnost: poprsí hýbe jen hrudníkem vpředu, boky hlavně pánví.
	var base: PackedVector3Array = q["verts"]
	var bust: PackedVector3Array = q["morphs"]["bust"]
	var far := 0.0
	var near := 0.0
	for i in base.size():
		var l := bust[i].length()
		if base[i].y < 1.0 or base[i].y > 1.5:
			far = maxf(far, l)
		elif base[i].z > 0.05:
			near = maxf(near, l)
	check(near > 0.03 and far < 0.004, "morf poprsí je lokální (vpředu %.3f m, nohy/hlava %.4f m)" % [near, far])
	var bdir := Vector3.ZERO
	for i in base.size():
		bdir += bust[i]
	check(bdir.z > 0.0, "poprsí roste dopředu (+Z)")
	# Normály: jednotkové, ven z těla (radiálně od osy trupu) – základ i silný morf.
	for label in ["základ", "fat_hi"]:
		var verts := base
		if label == "fat_hi":
			verts = base.duplicate()
			var fd: PackedVector3Array = q["morphs"]["fat_hi"]
			for i in verts.size():
				verts[i] += fd[i]
		var surf: Array = q["surfaces"]
		var total := 0
		var out := 0
		var unit := true
		for s in surf:
			var arr: Array = s["arrays"] if label == "základ" else (s["blend"][BodyMorphs.MORPHS.find("fat_hi")])
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in vv.size():
				if absf(nn[i].length() - 1.0) > 1e-3:
					unit = false
				if vv[i].y > 1.0 and vv[i].y < 1.4 and absf(vv[i].x) < 0.12:   # trup
					total += 1
					if nn[i].dot(Vector3(vv[i].x, 0.0, vv[i].z)) > 0.0:
						out += 1
		check(unit and total > 100 and float(out) / float(total) > 0.97,
			"normály (%s): jednotkové a z trupu ven %d/%d" % [label, out, total])
	# Poškozená data: neplatné měřítko morfu, neznámý morf, materiál mimo rozsah, absurdní dělení.
	var evil_cases := {
		"záporné měřítko morfu": func(p): p["morphs"][0][1] = -0.1,
		"neznámé jméno morfu": func(p): p["morphs"][0][0] = "nesmysl",
		"délka morfu nesedí": func(p): p["morphs"][0][3] = 3,
		"příliš mnoho dělení": func(p): p["subdiv"] = 5,
		"chybí seznam materiálů": func(p): p["mats"] = [],
	}
	for lab in evil_cases:
		var p2: Dictionary = part.duplicate(true)
		(evil_cases[lab] as Callable).call(p2)
		check(LSX.decode_quad_part(p2, dec["blob"], true, h["morphs"], 17).is_empty(), "odmítne: %s" % lab)
	var blob2: PackedByteArray = (dec["blob"] as PackedByteArray).duplicate()
	var fm: Array = part["fmat"]
	blob2[int(fm[0])] = 9
	check(LSX.decode_quad_part(part, blob2, true, h["morphs"], 17).is_empty(), "odmítne: materiál plochy mimo rozsah")
	check(LSX.decode_quad_part(part, dec["blob"], true, h["morphs"], 5).is_empty(), "odmítne: index kosti mimo kostru")
	var many := []
	for i in 40:
		many.append("m%d" % i)
	var raw := JSON.stringify({"v": 4, "morphs": many, "parts": []}).to_utf8_buffer()
	var pk := PackedByteArray()
	pk.resize(4)
	pk.encode_u32(0, raw.size())
	pk.append_array(raw)
	check(LSX.decode(Marshalls.raw_to_base64(pk.compress(FileAccess.COMPRESSION_DEFLATE))).is_empty(), "odmítne: víc než 32 morfů")


# ---------------------------------------------------------------- GLB

func _test_glb() -> void:
	section("GLB: blend shapes po exportu a načtení")
	AssetLibrary.clear_cache()
	var root := AssetLibrary.instantiate("character")
	check(root != null, "character.glb se načte")
	if root == null:
		return
	var parts := AssetLibrary.parts_in_group(root, "body")
	check(parts.size() == 4, "4 části těla")
	var names_ok := true
	var mode_ok := true
	var size_ok := true
	var move := 0.0
	for mi in parts:
		var m: ArrayMesh = mi.mesh
		var nm := []
		for i in m.get_blend_shape_count():
			nm.append(String(m.get_blend_shape_name(i)))
		if nm != BodyMorphs.MORPHS:
			names_ok = false
		if m.blend_shape_mode != Mesh.BLEND_SHAPE_MODE_NORMALIZED:
			mode_ok = false
		var base: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bl: Array = m.surface_get_blend_shape_arrays(0)
		for b in bl:
			var tv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
			if tv.size() != base.size():
				size_ok = false
				continue
		var fat: PackedVector3Array = bl[BodyMorphs.MORPHS.find("fat_hi")][Mesh.ARRAY_VERTEX]
		for i in base.size():
			move = maxf(move, (fat[i] - base[i]).length())
	check(names_ok, "jména blend shapes = BodyMorphs.MORPHS ve stejném pořadí")
	check(mode_ok, "režim NORMALIZED (absolutní cíle, správný GLTF export)")
	check(size_ok, "cíle mají stejný počet vrcholů jako základ")
	check(move > 0.07 and move < 0.12, "cíle jsou absolutní a nesou tvar (fat_hi max %.3f m)" % move)
	var mb: Dictionary = AssetLibrary.manifest_meta("character").get("morph_bones", {})
	check(mb.has("shoulders") and mb["shoulders"].has("upper_arm_l"), "manifest nese posuny kloubů (morph_bones)")
	root.free()


# ---------------------------------------------------------------- mapování

func _test_mapping() -> void:
	section("BodyMorphs: data → váhy (meze, nezávislost, determinismus)")
	var w0 := BodyMorphs.weights({})
	var all_zero := true
	for k in BodyMorphs.MORPHS:
		if not w0.has(k) or float(w0[k]) != 0.0:
			all_zero = false
	check(all_zero and w0.size() == BodyMorphs.MORPHS.size(), "výchozí tělo = všechny váhy 0 (základní síť)")
	var w1 := BodyMorphs.weights({"muscle": 1.0, "body_fat": 0.0, "bust": 0.0, "hips": 1.0, "frame": 0.0})
	check(w1["muscle_hi"] == 1.0 and w1["muscle_lo"] == 0.0, "svaly 1 → muscle_hi 1")
	check(w1["fat_lo"] == 1.0 and w1["fat_hi"] == 0.0, "tuk 0 → fat_lo 1")
	check(w1["bust"] == -0.25 and w1["hips"] == 1.0 and w1["frame"] == -1.0, "lineární klíče: bust 0 → −0,25, boky 1 → 1, stavba 0 → −1")
	var w2 := BodyMorphs.weights({"muscle": 0.0, "body_fat": 1.0, "bust": 1.0})
	check(w2["muscle_lo"] == 1.0 and w2["fat_hi"] == 1.0 and w2["bust"] == 1.0, "opačné extrémy")
	var junk := BodyMorphs.weights({"muscle": "hodně", "body_fat": NAN, "bust": INF, "hips": 7.0, "waist": -3})
	check(junk["muscle_hi"] == 0.0 and junk["fat_hi"] == 0.0 and junk["bust"] == 0.0 and junk["hips"] == 1.0 and junk["waist"] == -1.0,
		"nesmysly → výchozí, mimo rozsah → ořez", str(junk))
	# Fuzz: náhodná těla → váhy vždy v ⟨−1, 1⟩ a kvantované.
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var ok := true
	for n in 500:
		var body := {}
		for f in Schema.fields("body"):
			var s: Array = Schema.fields("body")[f]
			body[f] = rng.randf_range(float(s[1]) - 0.2, float(s[2]) + 0.2)
		var w := BodyMorphs.weights(body)
		for k in w:
			var v := float(w[k])
			if v < -1.0 or v > 1.0 or absf(v * 1000.0 - roundf(v * 1000.0)) > 1e-6:
				ok = false
	check(ok, "fuzz 500 těl: váhy v ⟨−1, 1⟩ a kvantované na 1/1000")
	# Nezávislost na identitě/rodu/jméně a determinismus přes síť (JSON).
	var snap := {"body": {"bust": 0.7, "hips": 0.3, "muscle": 0.8, "height_cm": 158.0, "leg_length": 0.2}}
	var a := Resolver.resolve(snap)
	var snap2: Dictionary = snap.duplicate(true)
	snap2["identity"] = {"first_name": "Někdo Jiný", "grammar": "m", "gender_identity": "muz"}
	var b := Resolver.resolve(snap2)
	check(a["body"] == b["body"] and a["height_scale"] == b["height_scale"], "rod, identita ani jméno tvar těla nemění")
	var c := Resolver.resolve(JSON.parse_string(JSON.stringify(snap)))
	check(a["body"] == c["body"] and a["leg_scale"] == c["leg_scale"] and a["head_scale"] == c["head_scale"],
		"po přenosu sítí (JSON) bit po bitu stejné váhy a měřítka")


func _test_scales() -> void:
	section("Výška, nohy, hlava: temeno = height_cm")
	var worst := 0.0
	for h in [145.0, 158.0, 172.0, 186.0, 205.0]:
		for ll in [0.0, 0.5, 1.0]:
			var sc := BodyMorphs.scales({"height_cm": h, "leg_length": ll})
			worst = maxf(worst, absf(BodyMorphs.crown_height(sc) - h / 100.0))
	check(worst < 0.003, "výška temene sedí na všech kombinacích (max odchylka %.1f mm)" % (worst * 1000.0))
	var short := BodyMorphs.scales({"height_cm": 150.0})
	var tall := BodyMorphs.scales({"height_cm": 200.0})
	check(short["head_scale"] > 1.0 and tall["head_scale"] < 1.0, "hlava roste s výškou pomaleji než tělo (%.3f / %.3f)" % [short["head_scale"], tall["head_scale"]])
	check(float(short["height_scale"]) * float(short["head_scale"]) < float(tall["height_scale"]) * float(tall["head_scale"]),
		"vysoký člověk má přesto větší hlavu než malý (absolutně)")
	var l0 := BodyMorphs.scales({"leg_length": 0.0})
	var l1 := BodyMorphs.scales({"leg_length": 1.0})
	check(l0["leg_scale"] == BodyMorphs.LEG_MIN and l1["leg_scale"] == BodyMorphs.LEG_MAX, "délka nohou 0..1 → měřítko stehna 0,92..1,08")
	check(float(l0["lift"]) < 0.0 and float(l1["lift"]) > 0.0, "kratší nohy model spustí, delší zvednou (chodidla na zemi)")


# ---------------------------------------------------------------- SimVisual

func _make_visual() -> Node3D:
	var v := Node3D.new()
	v.set_script(SimVisual)
	v._build()          # bez stromu scény: model se postaví, animace neběží (čistá klidová póza)
	return v


func _test_visual_apply() -> void:
	section("SimVisual: hodnoty blend shapes a kosti = data")
	var v := _make_visual()
	check(v.uses_model(), "model z Blenderu")
	var snap := {"body": {"height_cm": 188.0, "leg_length": 0.9, "frame": 0.8, "muscle": 0.1, "body_fat": 0.85,
		"shoulders": 0.9, "chest": 0.3, "bust": 0.65, "waist": 0.7, "hips": 0.2}}
	v.apply_look(snap)
	var lp := Resolver.resolve(snap)
	var w: Dictionary = lp["body"]
	var bad := []
	var parts: Array = v._body_meshes()
	for mi in parts:
		for k in w:
			var idx: int = mi.find_blend_shape_by_name(StringName(k))
			if idx < 0 or absf(mi.get_blend_shape_value(idx) - float(w[k])) > 1e-6:
				bad.append("%s/%s" % [mi.name, k])
	check(parts.size() == 4 and bad.is_empty(), "všech 10 vah na všech 4 částech těla = data", str(bad))
	var skel: Skeleton3D = v._skeleton()
	var thigh := skel.find_bone("thigh_l")
	check(skel.get_bone_pose_scale(thigh).is_equal_approx(Vector3(1.0, float(lp["leg_scale"]), 1.0)), "stehno škálované podle délky nohou")
	var hb := skel.find_bone("head")
	check(skel.get_bone_pose_scale(hb).is_equal_approx(Vector3.ONE * float(lp["head_scale"])), "hlava škálovaná podle výšky")
	check(v._model.scale.is_equal_approx(Vector3.ONE * float(lp["height_scale"])), "model škálovaný podle výšky")
	var offs := BodyMorphs.bone_offsets(w, AssetLibrary.manifest_meta("character").get("morph_bones", {}))
	var ua := skel.find_bone("upper_arm_l")
	check(skel.get_bone_rest(ua).origin.is_equal_approx(v._rest0[ua] + offs["upper_arm_l"]) and offs["upper_arm_l"].x > 0.02,
		"kloub ramene posunutý o %.3f m (široká ramena + tuk)" % offs["upper_arm_l"].x)
	# Návrat na výchozí: všechny váhy 0, klouby v původní poloze.
	v.apply_look({})
	var zero := true
	for mi in parts:
		for i in (mi.mesh as ArrayMesh).get_blend_shape_count():
			if mi.get_blend_shape_value(i) != 0.0:
				zero = false
	check(zero and skel.get_bone_rest(ua).origin.is_equal_approx(v._rest0[ua]), "výchozí snapshot vrátí základní tělo i klouby")
	v.free()


## Lineární skinning na CPU (klidová póza + aktuální měřítka/klouby) včetně blend shapes – jako GPU.
func _skinned(v: Node3D, mi: MeshInstance3D) -> PackedVector3Array:
	var m: ArrayMesh = mi.mesh
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var bl := m.surface_get_blend_shape_arrays(0)
	for i in m.get_blend_shape_count():
		var wv: float = mi.get_blend_shape_value(i)
		if wv == 0.0:
			continue
		var tv: PackedVector3Array = bl[i][Mesh.ARRAY_VERTEX]
		var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] += (tv[j] - base[j]) * wv
	var skel: Skeleton3D = v._skeleton()
	var skin: Skin = mi.skin
	# Indexy kostí ve vrcholech po importu GLB odkazují na BIND (kloub skinu), ne přímo na kost kostry.
	var xf_of := {}
	for j in skin.get_bind_count():
		var bname := String(skin.get_bind_name(j))
		var bi := skel.find_bone(bname) if bname != "" else skin.get_bind_bone(j)
		xf_of[j] = skel.get_bone_global_pose(bi) * skin.get_bind_pose(j)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var model_xf := Transform3D(Basis.from_scale(v._model.scale), v._model.position)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for j in verts.size():
		var acc := Vector3.ZERO
		for k in per:
			var wk := wts[j * per + k]
			if wk <= 0.0:
				continue
			var b := bones[j * per + k]
			acc += ((xf_of[b] as Transform3D) * verts[j]) * wk
		out[j] = model_xf * acc
	return out


func _test_skinning() -> void:
	section("Skinning: výška temene, chodidla na zemi, klouby bez dvojího posunu")
	var v := _make_visual()
	var worst := 0.0
	var floor_worst := 0.0
	for h in [150.0, 175.0, 200.0]:
		for ll in [0.0, 1.0]:
			v.apply_look({"body": {"height_cm": h, "leg_length": ll}})
			var top := -INF
			for mi in AssetLibrary.parts_in_group(v._model, "head"):
				if String(mi.name).contains("eyes"):
					continue
				for p in _skinned(v, mi):
					top = maxf(top, p.y)
			var bottom := INF
			for mi in v._body_meshes():
				for p in _skinned(v, mi):
					bottom = minf(bottom, p.y)
			worst = maxf(worst, absf(top - h / 100.0))
			floor_worst = maxf(floor_worst, absf(bottom))
	check(worst < 0.012, "temeno ve výšce height_cm (max odchylka %.1f mm)" % (worst * 1000.0))
	check(floor_worst < 0.03, "chodidla u podlahy i s krátkýma/dlouhýma nohama (max %.1f mm)" % (floor_worst * 1000.0))
	# Široká ramena: paže se posune JEN jednou (shape key), ne podruhé kostí.
	v.apply_look({"body": {"shoulders": 1.0}})
	var dev := 0.0
	var moved := 0.0
	for mi in v._body_meshes():
		var m: ArrayMesh = mi.mesh
		var arr := m.surface_get_arrays(0)
		var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := BodyMorphs.MORPHS.find("shoulders")
		var tv: PackedVector3Array = m.surface_get_blend_shape_arrays(0)[idx][Mesh.ARRAY_VERTEX]
		var sk := _skinned(v, mi)
		var s: float = v._model.scale.x
		for j in base.size():
			if base[j].y < 1.0 or absf(base[j].x) < 0.2:      # jen paže
				continue
			var expect: Vector3 = v._model.position + tv[j] * s
			dev = maxf(dev, (sk[j] - expect).length())
			moved = maxf(moved, (tv[j] - base[j]).length())
	check(moved > 0.02 and dev < 0.002, "paže posunutá morfem o %.1f cm, skinning nepřidal nic navíc (odchylka %.2f mm)" % [moved * 100.0, dev * 1000.0])
	v.free()


# ---------------------------------------------------------------- výkon

func _test_perf() -> void:
	section("Výkon: aplikace posuvníku")
	var v := _make_visual()
	var t0 := Time.get_ticks_usec()
	var n := 200
	for i in n:
		var x := float(i) / float(n)
		v.apply_look({"body": {"body_fat": x, "muscle": 1.0 - x, "bust": x, "height_cm": 150.0 + 50.0 * x, "leg_length": x}})
	var per := float(Time.get_ticks_usec() - t0) / float(n) / 1000.0
	check(per < 4.0, "změna těla včetně kloubů a barev za %.3f ms (limit 4 ms, cíl < 1 snímek)" % per)
	var t1 := Time.get_ticks_usec()
	for i in n:
		v.apply_body_shape(Resolver.resolve({"body": {"waist": float(i) / float(n)}}))
	var per2 := float(Time.get_ticks_usec() - t1) / float(n) / 1000.0
	check(per2 < 2.0, "samotný posuvník tvaru těla %.3f ms" % per2)
	v.free()
