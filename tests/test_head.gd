extends "res://tests/test_base.gd"
## C3 – obličej: procedurální hlava (HeadBuilder) s blend shapes, FaceMorphs (data → váhy), napojení
## do GLB a SimVisual. Ověřuje: každé pole schématu má morf s viditelným účinkem, váhy = data,
## lineární míchání blend shapes ve hře se drží přesného tvaru, kombinace extrémů nevedou k průnikům
## (kůže × oční koule, rty, převrácené plochy), symetrie bez asymetrie a asymetrie jen přes své osy,
## determinismus napříč peery, rozpočet a výkon.

const HB := preload("res://scripts/assets/head_builder.gd")
const FM := preload("res://scripts/character/face_morphs.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

var data: Dictionary
var topo
var p0: PackedVector3Array
var tg: Dictionary
var eye_front := {}
var eye_back := {}
var skin_idx := PackedInt32Array()


func _init() -> void:
	watchdog_seconds = 400.0


func _ready() -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	data = HB.build_data()
	topo = data["topo"]
	p0 = data["base"]
	tg = data["targets"]
	print("HeadBuilder.build_data: %d ms" % (Time.get_ticks_msec() - t0))
	for i in topo.recipes.size():
		var r: Array = topo.recipes[i]
		if r[0] == "eb" and r[2] == "front":
			eye_front[int(r[1])] = i
		elif r[0] == "eb" and r[2] == "back":
			eye_back[int(r[1])] = i
		elif r[0] == "g" or r[0] == "ec" or (r[0] == "er" and int(r[2]) <= 3):
			skin_idx.append(i)
	_test_schema_coverage()
	_test_face_morphs()
	_test_determinism_symmetry()
	_test_blend_accuracy()
	_test_intersections()
	await _test_glb_and_visual()
	_test_network_determinism()
	finish("test_head")


# ------------------------------------------------------------------------------------------ pomocníci

func _blend(w: Dictionary) -> PackedVector3Array:
	var p := p0.duplicate()
	for k in tg:
		var wk := float(w.get(k, 0.0))
		if wk == 0.0:
			continue
		var dd: PackedVector3Array = tg[k]
		for i in p.size():
			p[i] += dd[i] * wk
	return p


## Přesný tvar pro stejné hodnoty, jaké dostanou blend shapes (kvantované váhy, tuk/svaly z těla).
func _exact(w: Dictionary) -> PackedVector3Array:
	var prm := {}
	for k in FM.morph_fields():
		prm[k] = float(w[k])
	prm["b_fat"] = float(w["b_fat"])
	prm["b_muscle"] = float(w["b_muscle"])
	return HB.positions(topo, prm)


func _err(a: PackedVector3Array, b: PackedVector3Array) -> Vector2:
	var mx := 0.0
	var sm := 0.0
	for i in a.size():
		var e := a[i].distance_to(b[i])
		mx = maxf(mx, e)
		sm += e
	return Vector2(mx, sm / float(a.size()))


func _random_face(rng: RandomNumberGenerator, extreme: bool) -> Dictionary:
	var f := {}
	for k in FM.morph_fields():
		if extreme:
			f[k] = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.75, 1.0)
		else:
			f[k] = clampf(rng.randfn(0.0, 0.35), -1.0, 1.0)
	f["chin_cleft"] = absf(float(f["chin_cleft"]))
	return f


## Nejmenší vzdálenost kůže od povrchu oční koule (střed = mezi předním a zadním pólem, poloměr k zadnímu).
func _eye_clearance(p: PackedVector3Array) -> float:
	var worst := 1e9
	for s in [1, -1]:
		var c: Vector3 = (p[eye_front[s]] + p[eye_back[s]]) * 0.5
		var rr := p[eye_back[s]].distance_to(c)
		for i in skin_idx:
			worst = minf(worst, p[i].distance_to(c) - rr)
	return worst


## Nejmenší mezera mezi horní a dolní linií úst (prstenec 3) – záporná = rty se překříží.
func _lip_gap(p: PackedVector3Array) -> float:
	var up := {}
	var lo := {}
	for i in topo.recipes.size():
		var r: Array = topo.recipes[i]
		if r[0] == "mr" and int(r[1]) == 3 and absf(float(r[2])) < 0.999:
			var a := snappedf(float(r[2]), 0.001)
			if float(r[3]) > 0.0:
				up[a] = p[i].y
			elif float(r[3]) < 0.0:
				lo[a] = p[i].y
	var gap := 1e9
	for a in up:
		if lo.has(a):
			gap = minf(gap, float(up[a]) - float(lo[a]))
	return gap


## Plochy, jejichž normála se po morfu otočila o víc než 90° (přeložení geometrie).
func _flipped(p: PackedVector3Array) -> int:
	var n := 0
	for f in topo.faces:
		var idx: PackedInt32Array = f[2]
		var a := (p0[idx[1]] - p0[idx[0]]).cross(p0[idx[2]] - p0[idx[0]])
		var b := (p[idx[1]] - p[idx[0]]).cross(p[idx[2]] - p[idx[0]])
		if a.length() > 1e-12 and b.length() > 1e-12 and a.dot(b) < 0.0:
			n += 1
	return n


# ------------------------------------------------------------------------------------------ testy

func _test_schema_coverage() -> void:
	section("Schéma ↔ blend shapes hlavy")
	var spec: Dictionary = data["spec"]
	var missing: Array = []
	var weak: Array = []
	var shapes := 0
	for k in FM.morph_fields():
		if not spec.has(k):
			missing.append(k)
			continue
		var mx := 0.0
		for nm in spec[k]:
			if tg.has(nm):
				shapes += 1
				for d in (tg[nm] as PackedVector3Array):
					mx = maxf(mx, d.length())
		if mx < 0.0005:
			weak.append("%s %.2f mm" % [k, mx * 1000.0])
	check(missing.is_empty(), "každé pole obličeje (%d) má morf" % FM.morph_fields().size(), str(missing))
	check(weak.is_empty(), "každý morf má viditelný účinek (≥ 0,5 mm)", str(weak))
	for k in FM.BODY_LINKS:
		check(tg.has(k), "tělo ovlivňuje obličej: %s" % k)
	var inb: Array = spec.get("_inbetweens", [])
	check(inb.has(FM.inbetween_name("nose_length", 1)) and inb.has(FM.inbetween_name("nose_length", -1)), "mezitvary pro nelineární délku nosu (%s)" % str(inb))
	var wm := FM.weights({"nose_length": -0.5, "eye_size": 0.25})
	check(float(wm[FM.inbetween_name("nose_length", -1)]) == 1.0 and float(wm[FM.inbetween_name("nose_length", 1)]) == 0.0
		and float(wm[FM.inbetween_name("eye_size", 1)]) == 0.5, "váha mezitvaru: 1 v polovině, 0 na koncích a u druhého znaménka")
	var cx: Array = spec.get("_correctives", [])
	check(cx.size() >= 4, "korekční tvary pro dvojice s interakcí (%d)" % cx.size())
	check(tg.size() <= 72, "počet blend shapes hlavy v rozumných mezích (%d)" % tg.size())
	var nonlin := 0
	for k in FM.morph_fields():
		if spec.has(k) and (spec[k] as Array).size() == 2:
			nonlin += 1
	print("    (lineárních %d, nelineárních %d, tvarů %d)" % [FM.morph_fields().size() - nonlin, nonlin, shapes])
	# Topologie: indexy v rozsahu, plochy 3/4 vrcholy.
	var bad := 0
	for f in topo.faces:
		var idx: PackedInt32Array = f[2]
		if idx.size() < 3 or idx.size() > 4:
			bad += 1
		for v in idx:
			if v < 0 or v >= p0.size():
				bad += 1
	check(bad == 0, "topologie: indexy v rozsahu, plochy 3–4 vrcholy (%d ploch, %d vrcholů)" % [topo.faces.size(), p0.size()])


func _test_face_morphs() -> void:
	section("FaceMorphs: data → váhy")
	var w0 := FM.weights({})
	var nz: Array = []
	for k in w0:
		if float(w0[k]) != 0.0:
			nz.append(k)
	check(nz.is_empty(), "výchozí obličej = všechny váhy 0", str(nz))
	var w := FM.weights({"eye_size": 0.4, "nose_length": -0.7, "nose_bridge": 0.5, "asym_eyes": -0.3})
	check(is_equal_approx(float(w["eye_size"]), 0.4) and is_equal_approx(float(w["eye_size_pos"]), 0.4) and float(w["eye_size_neg"]) == 0.0,
		"kladná hodnota → <pole> a <pole>_pos")
	check(is_equal_approx(float(w["nose_length_neg"]), 0.7) and float(w["nose_length_pos"]) == 0.0, "záporná hodnota → <pole>_neg")
	check(is_equal_approx(float(w[FM.corrective_name("nose_length", -1, "nose_bridge", 1)]), 0.35)
		and float(w[FM.corrective_name("nose_length", 1, "nose_bridge", 1)]) == 0.0, "korekční tvar = součin vah ve správném kvadrantu")
	var wb := FM.weights({"eye_size": NAN, "jaw_width": 7.0, "chin_cleft": -0.8, "mouth_width": "x", "lip_upper": INF})
	check(float(wb["eye_size"]) == 0.0 and float(wb["jaw_width"]) == 1.0 and float(wb["chin_cleft"]) == 0.0
		and float(wb["mouth_width"]) == 0.0 and float(wb["lip_upper"]) == 0.0, "NaN/INF/text → výchozí, mimo rozsah → ořez, důlek ≥ 0")
	var wq := FM.weights({"eye_size": 0.123456})
	check(float(wq["eye_size"]) == 0.123, "váhy kvantované na 1/1000")
	var bw := BodyMorphs.weights({"body_fat": 0.9, "muscle": 0.8})
	var wf := FM.weights({}, bw)
	check(float(wf["b_fat"]) > 0.5 and float(wf["b_muscle"]) > 0.3, "tuk a svaly těla se promítnou do obličeje (%.3f, %.3f)" % [wf["b_fat"], wf["b_muscle"]])
	var wthin := FM.weights({}, BodyMorphs.weights({"body_fat": 0.0}))
	check(float(wthin["b_fat"]) == 0.0, "hubnutí obličej nedeformuje (jen nárůst)")
	# Obličej závisí jen na skupinách face a body – ne na jménu, rodu ani identitě.
	var a := {"identity": {"first_name": "Jana", "grammar": "f"}, "face": {"nose_width": 0.4}, "body": {"body_fat": 0.5}}
	var b := {"identity": {"first_name": "Petr", "grammar": "m"}, "face": {"nose_width": 0.4}, "body": {"body_fat": 0.5}}
	check(Resolver.resolve(a)["face"] == Resolver.resolve(b)["face"], "jméno ani rod obličej nemění")


func _test_determinism_symmetry() -> void:
	section("Determinismus a symetrie")
	var t2 = HB.build_topology()
	check(t2.recipes.size() == topo.recipes.size() and t2.faces.size() == topo.faces.size(), "topologie je pevná (stejný počet vrcholů a ploch)")
	var q := HB.positions(t2, {})
	var same := true
	for i in q.size():
		if q[i] != p0[i]:
			same = false
			break
	check(same, "opakovaný výpočet = bit po bitu stejné polohy")
	check(_mirror_error(p0) < 0.00005, "výchozí hlava je souměrná (%.4f mm)" % (_mirror_error(p0) * 1000.0))
	var sym_bad: Array = []
	for k in ["nose_width", "jaw_width", "eye_size", "ear_angle", "cheekbones", "lip_lower"]:
		var e := _mirror_error(HB.positions(topo, {k: 1.0}))
		if e > 0.00005:
			sym_bad.append("%s %.3f mm" % [k, e * 1000.0])
	check(sym_bad.is_empty(), "souměrné morfy zůstávají souměrné", str(sym_bad))
	var asym_ok: Array = []
	for k in Schema.FACE_ASYMMETRY:
		var e := _mirror_error(HB.positions(topo, {k: 1.0}))
		if e > 0.0005:
			asym_ok.append(k)
	check(asym_ok.size() == Schema.FACE_ASYMMETRY.size(), "každá osa asymetrie souměrnost opravdu poruší (%s)" % str(asym_ok))


## Největší vzdálenost vrcholu od nejbližšího zrcadlového (x → −x) vrcholu; prostorová mřížka 0,5 mm.
func _mirror_error(p: PackedVector3Array) -> float:
	var cell := 0.0005
	var grid := {}
	for i in p.size():
		var key := Vector3i(floori(p[i].x / cell), floori(p[i].y / cell), floori(p[i].z / cell))
		var arr: PackedInt32Array = grid.get(key, PackedInt32Array())
		arr.append(i)
		grid[key] = arr   # PackedInt32Array je hodnotový typ – nutno zapsat zpět
	var worst := 0.0
	for i in p.size():
		var m := Vector3(-p[i].x, p[i].y, p[i].z)
		var c := Vector3i(floori(m.x / cell), floori(m.y / cell), floori(m.z / cell))
		var best := 1e9
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var key := c + Vector3i(dx, dy, dz)
					if grid.has(key):
						for j in (grid[key] as PackedInt32Array):
							best = minf(best, p[j].distance_to(m))
		worst = maxf(worst, best)
	return worst


func _test_blend_accuracy() -> void:
	section("Blend shapes ve hře × přesný tvar")
	# Jedno pole na 60 %: lineární interpolace tvaru mezi 0 a ±1.
	var single_worst := 0.0
	var single_key := ""
	for k in FM.morph_fields():
		for v in [0.6, -0.6]:
			if k == "chin_cleft" and v < 0.0:
				continue
			var w := FM.weights({k: v})
			var e := _err(_blend(w), _exact(w))
			if e.x > single_worst:
				single_worst = e.x
				single_key = "%s=%s" % [k, v]
	check(single_worst < 0.0008, "jedno pole na ±60 %%: odchylka ≤ 0,8 mm (nejhorší %.2f mm, %s)" % [single_worst * 1000.0, single_key])
	# Korekční tvary: dvojice s interakcí.
	var wpair := FM.weights({"nose_length": 1.0, "nose_bridge": 1.0})
	var with_cx := _err(_blend(wpair), _exact(wpair)).x
	var wno := wpair.duplicate()
	for k in wno:
		if String(k).begins_with("cx_"):
			wno[k] = 0.0
	var without_cx := _err(_blend(wno), _exact(wpair)).x
	check(with_cx < 0.0003 and without_cx > 0.002, "korekční tvar: dlouhý nos + vysoký hřbet %.2f mm (bez korekce %.2f mm)" % [with_cx * 1000.0, without_cx * 1000.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	for mode in ["typické", "extrémní"]:
		var mx := 0.0
		var mean := 0.0
		for s in 8:
			var bw := {"fat_hi": rng.randf() * 0.6, "muscle_hi": rng.randf() * 0.6}
			var w := FM.weights(_random_face(rng, mode == "extrémní"), bw)
			var e := _err(_blend(w), _exact(w))
			mx = maxf(mx, e.x)
			mean = maxf(mean, e.y)
		if mode == "typické":
			check(mx < 0.003 and mean < 0.0001, "typické obličeje (σ 0,35): max %.2f mm, průměr %.3f mm" % [mx * 1000.0, mean * 1000.0])
		else:
			check(mx < 0.005 and mean < 0.0003, "extrémní kombinace (|v| ≥ 0,75 u všech 32 polí): max %.2f mm, průměr %.3f mm" % [mx * 1000.0, mean * 1000.0])


func _test_intersections() -> void:
	section("Průniky při kombinacích extrémů (to, co vykreslí hra)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var worst_eye := 1e9
	var worst_lip := 1e9
	var worst_flip := 0
	var samples := 0
	# Rohy podprostoru „oči a víčka“ (nejrizikovější) + náhodné extrémy všech polí.
	var eye_keys := ["eye_size", "eye_depth", "eye_distance", "eyelid_hood", "eye_tilt", "brow_ridge", "brow_height", "asym_eyes"]
	for corner in 24:
		var f := {}
		for k in eye_keys:
			f[k] = 1.0 if rng.randf() < 0.5 else -1.0
		var w := FM.weights(f, {"fat_hi": rng.randf()})
		var p := _blend(w)
		worst_eye = minf(worst_eye, _eye_clearance(p))
		worst_flip = maxi(worst_flip, _flipped(p))
		samples += 1
	for s in 24:
		var w := FM.weights(_random_face(rng, true), {"fat_hi": rng.randf(), "muscle_hi": rng.randf()})
		var p := _blend(w)
		worst_eye = minf(worst_eye, _eye_clearance(p))
		worst_lip = minf(worst_lip, _lip_gap(p))
		worst_flip = maxi(worst_flip, _flipped(p))
		samples += 1
	check(worst_eye > 0.0003, "kůže a víčka nikdy neproniknou okem (%d kombinací, nejmenší vůle %.2f mm)" % [samples, worst_eye * 1000.0])
	check(worst_lip > -0.00005, "horní a dolní ret se nepřekříží (nejmenší mezera %.3f mm)" % (worst_lip * 1000.0))
	check(worst_flip <= 2, "žádné přeložené plochy (nejhůř %d z %d)" % [worst_flip, topo.faces.size()])
	check(_eye_clearance(p0) > 0.0005, "výchozí hlava: vůle kůže–oko %.2f mm" % (_eye_clearance(p0) * 1000.0))


func _test_glb_and_visual() -> void:
	section("GLB a SimVisual")
	AssetLibrary.clear_cache()
	var meta := AssetLibrary.manifest_meta("character")
	check(meta.has("face_spec") and typeof(meta["face_spec"]) == TYPE_DICTIONARY, "manifest nese specifikaci obličejových morfů")
	check(int(meta.get("neck_cut_tris", 0)) > 0 and int(meta.get("seam_loop_verts", 0)) >= 8,
		"krk těla odříznutý nad smyčkou švu (%s trojúhelníků, smyčka %s vrcholů)" % [str(meta.get("neck_cut_tris", 0)), str(meta.get("seam_loop_verts", 0))])
	var body_keys: Array = (meta.get("face_spec", {}) as Dictionary).get("_body_keys", [])
	var root := AssetLibrary.instantiate("character")
	check(root != null, "character.glb se načte")
	if root == null:
		return
	var heads := AssetLibrary.parts_in_group(root, "head")
	var eyes := AssetLibrary.parts_in_group(root, "eyes")
	check(heads.size() >= 3 and eyes.size() == 3, "hlava (%d materiálů) a oči (duhovka, zornice, bělmo)" % heads.size())
	var names := {}
	var tris := 0
	for mi in heads + eyes:
		var m: ArrayMesh = mi.mesh
		tris += m.surface_get_array_index_len(0) / 3
		for i in m.get_blend_shape_count():
			names[String(m.get_blend_shape_name(i))] = true
	var unknown: Array = []
	for nm in names:
		if not tg.has(nm) and not body_keys.has(nm):
			unknown.append(nm)
	check(unknown.is_empty() and names.size() >= 50, "blend shapes v GLB = morfy HeadBuilderu (%d)" % names.size(), str(unknown.slice(0, 5)))
	check(tris <= 9000, "rozpočet hlavy a očí %d trojúhelníků (≤ 9 000)" % tris)
	var hair_keys := 0
	for mi in AssetLibrary.parts_in_group(root, "hair_long"):
		hair_keys += (mi.mesh as ArrayMesh).get_blend_shape_count()
	check(hair_keys > 0, "vlasy převzaly morfy lebky (%d)" % hair_keys)
	root.free()
	# SimVisual: hodnoty blend shapes = data.
	var snap := {"face": {"eye_size": 0.5, "nose_length": -0.6, "nose_bridge": 0.4, "jaw_width": 0.8, "asym_jaw": -0.4,
		"head_width": 0.7}, "body": {"body_fat": 0.8}}
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(snap)
	# Hlava nese i klíče těla (pás švu krku, běh 11) – jejich váha je z lp["body"].
	var w: Dictionary = (v.look_params["face"] as Dictionary).merged(v.look_params["body"])
	var wrong: Array = []
	var seen := 0
	for mi in AssetLibrary.parts_in_group(v._model, "head") + AssetLibrary.parts_in_group(v._model, "hair_long"):
		var m: Mesh = mi.mesh
		for i in m.get_blend_shape_count():
			var nm := String(m.get_blend_shape_name(i))
			seen += 1
			if not is_equal_approx(mi.get_blend_shape_value(i), float(w.get(nm, 0.0))):
				wrong.append(nm)
	check(seen > 50 and wrong.is_empty(), "SimVisual: všech %d hodnot blend shapes hlavy a vlasů = data" % seen, str(wrong.slice(0, 5)))
	var hw := float(w["head_width_pos"])
	check(is_equal_approx(hw, 0.7) and float(w[FM.corrective_name("nose_length", -1, "nose_bridge", 1)]) > 0.0, "nelineární a korekční váhy dorazily (%.3f)" % hw)
	var t0 := Time.get_ticks_usec()
	for i in 20:
		v.apply_face_shape(v.look_params)
	var ms := float(Time.get_ticks_usec() - t0) / 20000.0
	check(ms < 2.0, "aplikace obličeje za %.3f ms (limit 2 ms)" % ms)
	v.queue_free()


func _test_network_determinism() -> void:
	section("Determinismus obličeje napříč peery")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var diff := 0
	for s in 20:
		var d := Schema.defaults()
		d["v"] = Schema.VERSION
		d["uid"] = load("res://scripts/character/character_data.gd").new_uid()
		d["identity"]["first_name"] = "Alex"
		d["personality"]["traits"] = ["hravy"]
		d["face"] = _random_face(rng, false)
		var r := Validator.validate(d)
		if not bool(r["ok"]):
			diff += 1
			continue
		var server: Dictionary = Resolver.resolve(r["data"])
		# Klient: veřejný snapshot přes síťový kód (JSON) a opravnou validaci.
		var cd = load("res://scripts/character/character_data.gd").new()
		cd.set_from_dict(r["data"])
		var pub: Dictionary = cd.public_snapshot()
		var wire = JSON.parse_string(JSON.stringify(pub))
		var client: Dictionary = Resolver.resolve(Validator.repaired(wire, {"public_only": true}))
		if server["face"] != client["face"]:
			diff += 1
	check(diff == 0, "20 obličejů: server i klient mají bit po bitu stejné váhy")
	var hh: Array = []
	for c in load("res://main.gd").household_characters():
		hh.append(Resolver.resolve(c)["face"])
	check(hh.size() == 3 and hh[0] != hh[1] and hh[1] != hh[2] and hh[0] != hh[2], "členové domácnosti mají různé obličeje")
