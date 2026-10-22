extends "res://tests/test_base.gd"
## C3++ (běh 21) – detaily obličeje a mimika: řasy, zuby, dáseň, jazyk, dutina úst, limbus a zornice, výrazy
## (mrkání, úsměv, zamračení, zvednuté obočí, otevřená čelist), schéma v6 + migrace, FaceMorphs (detaily, výrazy),
## GLB a SimVisual (mrkání, řeč, výraz podle emoce, výkon). Morfy se ověřují proti přesnému tvaru
## HeadBuilder.positions() – stejný recept, ze kterého vznikly blend shapes.

const HB := preload("res://scripts/assets/head_builder.gd")
const FM := preload("res://scripts/character/face_morphs.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

var topo
var p0: PackedVector3Array
var tg := {}
var kinds := {}


func _init() -> void:
	watchdog_seconds = 300.0


func _ready() -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	topo = HB.build_topology()
	p0 = HB.positions(topo, {})
	for i in topo.recipes.size():
		var k := String(topo.recipes[i][0])
		if not kinds.has(k):
			kinds[k] = PackedInt32Array()
		var a: PackedInt32Array = kinds[k]
		a.append(i)
		kinds[k] = a
	# cíle jen pro nové klíče (stejný výpočet jako HeadBuilder.morph_targets)
	for k in HB.DETAIL_KEYS + HB.EXPR_KEYS:
		tg[k + "_pos"] = _delta(HB.positions(topo, {k: 1.0}))
		tg[k + "_neg"] = _delta(HB.positions(topo, {k: -1.0}))
	for k in ["ex_blink_l", "ex_blink_r"]:
		var half := _delta(HB.positions(topo, {k: 0.5}))
		var mid := PackedVector3Array()
		mid.resize(p0.size())
		for i in p0.size():
			mid[i] = half[i] - tg[k + "_pos"][i] * 0.5
		tg[FM.inbetween_name(k, 1)] = mid
	print("příprava: %d ms" % (Time.get_ticks_msec() - t0))
	_test_schema_v6()
	_test_weights()
	_test_lashes()
	_test_blink()
	_test_teeth()
	_test_expressions()
	await _test_glb_visual()
	finish("test_face_detail")


# ------------------------------------------------------------------------------------------ pomocníci

func _delta(p: PackedVector3Array) -> PackedVector3Array:
	var d := PackedVector3Array()
	d.resize(p.size())
	for i in p.size():
		d[i] = p[i] - p0[i]
	return d


## Lineární míchání (to, co dělá hra) z vah FaceMorphs pro nové klíče.
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


func _idx(kind: String) -> PackedInt32Array:
	return kinds.get(kind, PackedInt32Array())


## Nejmenší vůle vrcholů (kůže kolem oka a řasy) od povrchu oční koule (středy a poloměry z derive).
func _eye_clear(p: PackedVector3Array, prm: Dictionary) -> float:
	var d := HB.derive(prm)
	var worst := 1e9
	for s in [1, -1]:
		var e: Dictionary = d["eye%d" % s]
		var c: Vector3 = e["E"]
		var r := float(e["R"]) * 1.06
		for i in topo.recipes.size():
			var rec: Array = topo.recipes[i]
			var ok: bool = (rec[0] == "er" and int(rec[1]) == s and int(rec[2]) <= 3) or (rec[0] == "lash" and int(rec[1]) == s)
			if ok:
				worst = minf(worst, p[i].distance_to(c) - r)
	return worst


## Svislá štěrbina oka s (max přes a: horní − dolní okraj víčka, prstenec 3).
func _slit(p: PackedVector3Array, s: int) -> float:
	var up := {}
	var lo := {}
	for i in _idx("er"):
		var r: Array = topo.recipes[i]
		if int(r[1]) == s and int(r[2]) == 3 and absf(float(r[3])) < 0.999:
			var a := snappedf(float(r[3]), 0.001)
			if float(r[4]) > 0.99:
				up[a] = p[i].y
			elif float(r[4]) < -0.99:
				lo[a] = p[i].y
	var mx := -1e9
	for a in up:
		if lo.has(a):
			mx = maxf(mx, float(up[a]) - float(lo[a]))
	return mx


## Přeložené plochy; spojivkový vak (materiál eye_socket – za víčky a okem, nikdy vidět) se při zavřeném oku
## záměrně složí, proto se nepočítá.
func _flipped(p: PackedVector3Array, part := "") -> int:
	var n := 0
	for f in topo.faces:
		if part != "" and f[0] != part:
			continue
		if f[1] == "eye_socket":
			continue
		var idx: PackedInt32Array = f[2]
		var a := (p0[idx[1]] - p0[idx[0]]).cross(p0[idx[2]] - p0[idx[0]])
		var b := (p[idx[1]] - p[idx[0]]).cross(p[idx[2]] - p[idx[0]])
		if a.length() > 1e-12 and b.length() > 1e-12 and a.dot(b) < 0.0:
			n += 1
	return n


## Nejmenší odstup zubů za vnitřkem rtů: pro zub a rtové vrcholy (prstence 3–4) s |Δx| < 3 mm a |Δy| < 4 mm.
func _teeth_behind_lips(p: PackedVector3Array) -> float:
	var lips: Array = []
	for i in _idx("mr"):
		if int(topo.recipes[i][1]) >= 3:
			lips.append(i)
	var worst := 1e9
	for i in _idx("th"):
		for j in lips:
			if absf(p[i].x - p[j].x) < 0.003 and absf(p[i].y - p[j].y) < 0.004:
				worst = minf(worst, p[j].z - p[i].z)
	return worst


func _tooth_vertex(arch: int, side: int, i: int, lvl: int, m: int) -> int:
	return topo.index.get("th,%d,%d,%d,%d,%d" % [arch, side, i, lvl, m], -1)


# ------------------------------------------------------------------------------------------ testy

func _test_schema_v6() -> void:
	section("Schéma v6 a migrace")
	var fs := Schema.fields("face")
	var miss: Array = []
	for k in Schema.FACE_DETAILS:
		if not fs.has(k):
			miss.append(k)
	check(Schema.VERSION == 6 and miss.is_empty(), "schéma v6: detaily obličeje ve skupině face", str(miss))
	check(Schema.GROUPS["makeup"]["fields"].has("mascara") and Schema.is_public("face", "teeth_gap") and Schema.is_public("makeup", "mascara"),
		"řasenka v make-upu, detaily jsou veřejné (vidí je všichni)")
	var v5 := Schema.defaults()
	v5["v"] = 5
	v5["uid"] = "0123456789abcdef0123456789abcdef"
	v5["identity"]["first_name"] = "Mira"
	v5["personality"]["traits"] = ["hravy"]
	for k in Schema.FACE_DETAILS:
		v5["face"].erase(k)
	v5["makeup"].erase("mascara")
	v5["face"]["nose_width"] = 0.4
	var r := Codec.from_dict(v5)
	check(bool(r["ok"]) and int(r["from_version"]) == 5 and int(r["data"]["v"]) == 6, "v5 se zmigruje na v6", str(r["errors"]))
	if bool(r["ok"]):
		var f: Dictionary = r["data"]["face"]
		check(is_equal_approx(float(f["lash_length"]), 0.5) and float(f["teeth_gap"]) == 0.0 and float(r["data"]["makeup"]["mascara"]) == 0.0
			and is_equal_approx(float(f["nose_width"]), 0.4), "migrace doplní výchozí detaily a nemění ostatní pole")
		check(Resolver.resolve(r["data"])["face"] == Resolver.resolve(v5)["face"], "migrovaná postava vypadá stejně (váhy obličeje beze změny)")
	var bad := Schema.defaults()
	bad["v"] = Schema.VERSION
	bad["uid"] = "0123456789abcdef0123456789abcdef"
	bad["identity"]["first_name"] = "Mira"
	bad["personality"]["traits"] = ["hravy"]
	bad["face"]["teeth_gap"] = 1.7
	bad["face"]["lash_curl"] = NAN
	var rs := Validator.validate(bad, {"mode": "strict"})
	check(not bool(rs["ok"]), "server odmítne detaily mimo rozsah (mezera 1,7, NaN)")
	var rr := Validator.validate(bad, {"mode": "repair"})
	check(bool(rr["ok"]) and float(rr["data"]["face"]["teeth_gap"]) <= 1.0, "opravný režim detaily ořízne do rozsahu")
	# generátor: v mezích, rozumné rozložení
	var rng := RandomNumberGenerator.new()
	rng.seed = 2121
	var gap := 0
	var crook := 0
	var out := 0
	var ll := 0.0
	for i in 200:
		var c := Randomizer.generate(rng)
		var f: Dictionary = c["face"]
		for k in Schema.FACE_DETAILS:
			var sp: Array = Schema.FACE_DETAILS[k][1]
			if float(f[k]) < float(sp[1]) or float(f[k]) > float(sp[2]):
				out += 1
		gap += 1 if float(f["teeth_gap"]) > 0.0 else 0
		crook += 1 if float(f["teeth_crooked"]) > 0.0 else 0
		ll += float(f["lash_length"])
	check(out == 0 and gap >= 3 and gap <= 30 and crook >= 20 and crook <= 75 and absf(ll / 200.0 - 0.5) < 0.05,
		"generátor: detaily v mezích, mezera %d/200, nerovné %d/200, průměr délky řas %.2f" % [gap, crook, ll / 200.0])


func _test_weights() -> void:
	section("FaceMorphs: detaily a mimika")
	var w0 := FM.weights({})
	var nz: Array = []
	for k in HB.DETAIL_KEYS:
		if float(w0[k]) != 0.0:
			nz.append(k)
	check(nz.is_empty(), "výchozí detaily = váhy 0 (vzhled beze změny)", str(nz))
	var w := FM.weights({"lash_length": 0.8, "teeth_gap": 0.5, "lash_density": 0.1})
	check(is_equal_approx(float(w["lash_length_pos"]), 0.6) and is_equal_approx(float(w["teeth_gap_pos"]), 0.5)
		and is_equal_approx(float(w["lash_density_neg"]), 0.8), "mapování: řasy (v − 0,5)·2, zuby 0..1")
	var wm := FM.weights({}, {}, {"mascara": 1.0})
	check(float(wm["lash_length_pos"]) > 0.3 and float(wm["lash_density_pos"]) > 0.4, "řasenka řasy prodlouží a zhustí")
	var wbad := FM.weights({"teeth_gap": -3.0, "lash_curl": "x"}, {}, {"mascara": NAN})
	check(float(wbad["teeth_gap_pos"]) == 0.0 and float(wbad["lash_curl"]) == 0.0 and float(wbad["lash_length"]) == 0.0, "neplatné hodnoty → výchozí")
	var ex := FM.expression_weights({"ex_blink_l": 0.5, "ex_smile": 3.0, "ex_frown": -1.0, "ex_pupil": -0.4, "ex_jaw_open": NAN})
	check(float(ex["ex_blink_l_pos"]) == 0.5 and float(ex[FM.inbetween_name("ex_blink_l", 1)]) == 1.0 and float(ex["ex_smile_pos"]) == 1.0
		and float(ex["ex_frown_pos"]) == 0.0 and float(ex["ex_pupil"]) == -0.4 and float(ex["ex_jaw_open_pos"]) == 0.0,
		"výrazy: ořez 0..1 (zornice −1..1), mezitvar mrkání, NaN → 0")
	var a := {"identity": {"first_name": "Jana", "grammar": "f"}, "face": {"teeth_gap": 0.4}}
	var b := {"identity": {"first_name": "Petr", "grammar": "m"}, "face": {"teeth_gap": 0.4}}
	check(Resolver.resolve(a)["face"] == Resolver.resolve(b)["face"] and Resolver.resolve(a)["teeth"] == Resolver.resolve(b)["teeth"], "jméno ani rod detaily nemění")
	var lt := Resolver.resolve({"skin": {"tone": 0.1}})
	var dk := Resolver.resolve({"skin": {"tone": 0.95}})
	check((lt["gum"] as Color).get_luminance() > (dk["gum"] as Color).get_luminance(), "dáseň: spojitá pigmentace podle melaninu kůže (bez předvoleb)")
	var t0 := Resolver.resolve({"face": {"teeth_shade": 0.0}})
	var t1 := Resolver.resolve({"face": {"teeth_shade": 1.0}})
	check((t0["teeth"] as Color).b > (t1["teeth"] as Color).b + 0.15, "odstín zubů 0 → bílé, 1 → zažloutlé")


func _test_lashes() -> void:
	section("Řasy")
	var li := _idx("lash")
	check(li.size() == 2 * (HB.LASH_UP + HB.LASH_LO) * (2 * HB.LASH_ST + 1), "řasy: %d karet na oko (%d vrcholů)" % [HB.LASH_UP + HB.LASH_LO, li.size()])
	# kořeny na okraji víčka i při morfech, mrkání a úsměvu (přesný tvar)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var worst_root := 0.0
	var worst_clear := 1e9
	var cases: Array = [{}, {"ex_blink_l": 1.0, "ex_blink_r": 0.5}, {"ex_smile": 1.0}, {"ex_frown": 1.0}]
	for s in 10:
		var f := {}
		for k in ["eye_size", "eye_depth", "eye_distance", "eyelid_hood", "eye_tilt", "brow_ridge", "brow_height", "asym_eyes", "lash_length", "lash_curl", "lash_density"]:
			f[k] = 1.0 if rng.randf() < 0.5 else -1.0
		cases.append(f)
	for prm in cases:
		var p := HB.positions(topo, prm)
		var d := HB.derive(prm)
		for i in li:
			var r: Array = topo.recipes[i]
			if int(r[4]) != 0:
				continue
			var a := lerpf(-0.90, 0.93, (float(r[3]) + 0.5) / float(HB.LASH_UP)) if int(r[2]) == 1 else lerpf(-0.62, 0.90, (float(r[3]) + 0.5) / float(HB.LASH_LO))
			var m := HB._eye_ring_pos(d, int(r[1]), 3, a * float(r[1]), 1.0 if int(r[2]) == 1 else -1.0, 0, 0)
			worst_root = maxf(worst_root, p[i].distance_to(m) - HB.LASH_W_UP * 0.8)
		worst_clear = minf(worst_clear, _eye_clear(p, prm))
	check(worst_root < 0.00005, "kořeny řas leží na okraji víčka (%d kombinací vč. mrkání, nejhůř %.3f mm)" % [cases.size(), worst_root * 1000.0])
	check(worst_clear > 0.0, "řasy ani víčka nepronikají okem (nejmenší vůle %.2f mm)" % (worst_clear * 1000.0))
	# délka: +1 delší než −1, hustota −1 část karet zkrátí
	var lens := {}
	for v in [-1.0, 0.0, 1.0]:
		var p := HB.positions(topo, {"lash_length": v})
		var tot := 0.0
		var n := 0
		var short := 0
		var pd := HB.positions(topo, {"lash_density": -1.0})
		for i in li:
			var r: Array = topo.recipes[i]
			if int(r[4]) == HB.LASH_ST and int(r[2]) == 1:
				var root: int = int(topo.index.get("lash,%d,1,%d,0,-1" % [int(r[1]), int(r[3])], -1))
				tot += p[i].distance_to(p[root])
				n += 1
				if pd[i].distance_to(pd[root]) < 0.75 * p0[i].distance_to(p0[root]):
					short += 1
		lens[v] = tot / float(n)
		if v == 0.0:
			check(short > n / 4 and short < n, "řidší řasy: zkrátí se %d z %d karet (ne všechny stejně)" % [short, n])
	check(float(lens[1.0]) > float(lens[0.0]) * 1.2 and float(lens[-1.0]) < float(lens[0.0]) * 0.8 and float(lens[0.0]) > 0.006 and float(lens[0.0]) < 0.0095,
		"délka horních řas: výchozí %.1f mm, krátké %.1f, dlouhé %.1f" % [float(lens[0.0]) * 1000.0, float(lens[-1.0]) * 1000.0, float(lens[1.0]) * 1000.0])
	var pc := HB.positions(topo, {"lash_curl": 1.0})
	var up_tip := 0.0
	var n2 := 0
	for i in li:
		var r: Array = topo.recipes[i]
		if int(r[4]) == HB.LASH_ST and int(r[2]) == 1:
			up_tip += pc[i].y - p0[i].y
			n2 += 1
	check(up_tip / float(n2) > 0.0005, "natočení řas zvedne špičky horních řas (%.2f mm)" % (up_tip / float(n2) * 1000.0))


func _test_blink() -> void:
	section("Mrkání")
	var s0 := _slit(p0, 1)
	var pc := HB.positions(topo, {"ex_blink_l": 1.0})
	check(s0 > 0.008 and _slit(pc, 1) < 0.0006, "mrknutí zavře levé oko (štěrbina %.1f → %.2f mm)" % [s0 * 1000.0, _slit(pc, 1) * 1000.0])
	var other := 0.0
	for i in topo.recipes.size():
		if p0[i].x < -0.005:
			other = maxf(other, pc[i].distance_to(p0[i]))
	check(other < 1e-6, "pravé oko zůstane otevřené (posun %.4f mm)" % (other * 1000.0))
	var worst := 0.0
	var worst_lash := 0.0
	var worst_clear := 1e9
	for v in [0.25, 0.5, 0.75, 1.0]:
		var w := FM.expression_weights({"ex_blink_l": v, "ex_blink_r": v})
		var pb := _blend(w)
		var pe := HB.positions(topo, {"ex_blink_l": v, "ex_blink_r": v})
		for i in topo.recipes.size():
			var rk: Array = topo.recipes[i]
			if rk[0] == "lash":
				worst_lash = maxf(worst_lash, pb[i].distance_to(pe[i]))
			elif rk[0] == "ec" or (rk[0] == "er" and int(rk[2]) >= 4):
				continue   # spojivkový vak za víčky (skrytý okem i víčky) – při zavření se jen složí
			else:
				worst = maxf(worst, pb[i].distance_to(pe[i]))
		worst_clear = minf(worst_clear, _eye_clear(pb, {}))
	# Víčko jde po kouli (mezitvar v ½ drží tětivu pod 0,4 mm); špičky řas se otáčejí po větším oblouku – odchylka
	# je jen vizuální (řasy jsou tenké karty před okem), průnik hlídá test vůle níže.
	check(worst < 0.0004, "mrkání v blend shapes (s mezitvarem) ≈ přesný tvar víček (nejhůř %.2f mm)" % (worst * 1000.0))
	check(worst_lash < 0.003, "špičky řas během mrknutí ≤ 3 mm od přesného tvaru (%.2f mm)" % (worst_lash * 1000.0))
	check(worst_clear > 0.0002, "víčko jde po povrchu oka – během mrknutí bez průniku (vůle %.2f mm)" % (worst_clear * 1000.0))
	# mrkání na extrémních očích (lineární součet blend shapes)
	# cíle očních morfů jako HeadBuilder.morph_targets, bez korekčního tvaru eye_distance × eye_depth (součet je tu horší než ve hře)
	var ftg := tg.duplicate()
	for k in ["eye_size", "eye_depth", "eye_distance", "eyelid_hood", "eye_tilt", "asym_eyes"]:
		ftg[k + "_pos"] = _delta(HB.positions(topo, {k: 1.0}))
		ftg[k + "_neg"] = _delta(HB.positions(topo, {k: -1.0}))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var wc := 1e9
	for s in 8:
		var face := {}
		for k in ["eye_size", "eye_depth", "eye_distance", "eyelid_hood", "eye_tilt", "asym_eyes"]:
			face[k] = 1.0 if rng.randf() < 0.5 else -1.0
		var w := {}
		for k in face:
			w[k + "_pos"] = maxf(0.0, float(face[k]))
			w[k + "_neg"] = maxf(0.0, -float(face[k]))
		w.merge(FM.expression_weights({"ex_blink_l": 0.5 + 0.5 * float(s % 2), "ex_blink_r": 0.5}), true)
		var p := p0.duplicate()
		for k in ftg:
			var wk := float(w.get(k, 0.0))
			if wk != 0.0:
				var dd: PackedVector3Array = ftg[k]
				for i in p.size():
					p[i] += dd[i] * wk
		wc = minf(wc, _eye_clear(p, face))
	check(wc > 0.0, "mrkání × extrémní oči (8 kombinací): bez průniku (vůle %.2f mm)" % (wc * 1000.0))


func _test_teeth() -> void:
	section("Zuby, dáseň, jazyk, dutina úst")
	var ti := _idx("th")
	check(ti.size() == 2 * 2 * 5 * (4 * HB.TOOTH_RING + 2), "2 oblouky × 10 zubů (%d vrcholů)" % ti.size())
	check(_teeth_behind_lips(p0) > 0.001, "zuby leží za vnitřkem rtů (odstup %.2f mm)" % (_teeth_behind_lips(p0) * 1000.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var worst := 1e9
	for s in 12:
		var f := {}
		for k in ["lip_upper", "lip_lower", "mouth_width", "philtrum", "jaw_width", "chin_length", "nose_length", "asym_mouth", "teeth_crooked", "teeth_gap"]:
			f[k] = 1.0 if rng.randf() < 0.5 else -1.0
		worst = minf(worst, _teeth_behind_lips(HB.positions(topo, f)))
	check(worst > 0.0005, "zuby za rty i při extrémech úst a nerovných zubech (12 kombinací, nejmenší %.2f mm)" % (worst * 1000.0))
	# zuby uvnitř hlavy: každý vrchol zubu, dásně a jazyka je pod povrchem hlavy (paprsek ze středu C)
	var d0 := HB.derive({})
	var c: Vector3 = d0["C"]
	var outside := 0
	for kind in ["th", "gm", "tg"]:
		for i in _idx(kind):
			var q := p0[i]
			var sp := HB.surface((q - c).normalized(), d0)
			if (q - c).length() > (sp - c).length() + 0.0005:
				outside += 1
	check(outside == 0, "zuby, dáseň a jazyk jsou uvnitř hlavy (%d vrcholů venku)" % outside)
	# mezera mezi horními jedničkami
	var gaps := {}
	for g in [0.0, 1.0]:
		var p := HB.positions(topo, {"teeth_gap": g})
		var mn := 1e9
		for i in ti:
			var r: Array = topo.recipes[i]
			if int(r[1]) == 1 and int(r[3]) == 0 and int(r[4]) == 2:
				mn = minf(mn, absf(p[i].x))
		gaps[g] = 2.0 * mn
	check(float(gaps[1.0]) - float(gaps[0.0]) > 0.0012 and float(gaps[1.0]) - float(gaps[0.0]) < 0.0018,
		"mezera mezi jedničkami +%.2f mm (diastema, bez karikatury)" % ((float(gaps[1.0]) - float(gaps[0.0])) * 1000.0))
	var pc := HB.positions(topo, {"teeth_crooked": 1.0})
	var moved := {}
	var mx := 0.0
	for i in ti:
		var dd := pc[i].distance_to(p0[i])
		if dd > 1e-5:
			var r: Array = topo.recipes[i]
			moved["%d:%d:%d" % [int(r[1]), int(r[2]), int(r[3])]] = true
			mx = maxf(mx, dd)
	check(moved.size() == 4 and mx < 0.0016, "nerovné zuby: vybočí %d zuby, nejvíc o %.2f mm" % [moved.size(), mx * 1000.0])
	# dutina: přední zuby (jedničky až trojky) leží před stěnou dutiny – vidět je zuby, ne „tmavou stěnu přes ně“
	var cz := float(d0["Tz"]) - HB.CAVITY_BACK
	var behind := 0
	for i in ti:
		var r: Array = topo.recipes[i]
		if int(r[3]) <= 2:
			var q := p0[i]
			var e := pow(q.x / HB.CAVITY_R.x, 2.0) + pow((q.y - float(d0["My"])) / HB.CAVITY_R.y, 2.0) + pow(minf(q.z - cz, 0.0) / HB.CAVITY_R.z, 2.0)
			if e > 1.0:
				behind += 1
	check(behind == 0, "přední zuby jsou uvnitř dutiny úst (%d vrcholů mimo)" % behind)


func _test_expressions() -> void:
	section("Mimika: úsměv, zamračení, obočí, čelist, zornice")
	var lower_edge := _tooth_vertex(-1, 1, 0, 5, 0)
	var upper_edge := _tooth_vertex(1, 1, 0, 5, 0)
	var pj := HB.positions(topo, {"ex_jaw_open": 1.0})
	var drop := p0[lower_edge].y - pj[lower_edge].y
	check(drop > 0.012 and drop < 0.022 and pj[upper_edge].distance_to(p0[upper_edge]) < 1e-7,
		"otevřená čelist: dolní řezáky o %.1f mm níž, horní zuby na místě" % (drop * 1000.0))
	var neck := 0.0
	for i in _idx("g"):
		if p0[i].y < 1.52:
			neck = maxf(neck, pj[i].distance_to(p0[i]))
	check(neck < 0.0001, "krk u švu s tělem se při otevření úst nehne (%.3f mm)" % (neck * 1000.0))
	var flips := {}
	for prm in [{"ex_jaw_open": 1.0}, {"ex_smile": 1.0}, {"ex_frown": 1.0}, {"ex_brow_up": 1.0},
			{"ex_smile": 1.0, "ex_jaw_open": 0.6, "ex_brow_up": 0.5}, {"ex_frown": 1.0, "ex_blink_l": 1.0, "ex_blink_r": 1.0}]:
		flips[str(prm)] = _flipped(HB.positions(topo, prm), "head")
	var bad := 0
	for k in flips:
		bad = maxi(bad, int(flips[k]))
	check(bad <= 2, "výrazy a jejich kombinace bez přeložených ploch (nejhůř %d)" % bad, str(flips))
	# úsměv: koutky nahoru a do stran, štěrbina se uprostřed pootevře
	var ps := HB.positions(topo, {"ex_smile": 1.0})
	var corner := -1
	for i in _idx("mr"):
		var r: Array = topo.recipes[i]
		if int(r[1]) == 1 and (corner < 0 or p0[i].x > p0[corner].x):
			corner = i
	check(corner >= 0 and ps[corner].y - p0[corner].y > 0.002 and ps[corner].x - p0[corner].x > 0.001,
		"úsměv: koutek nahoru o %.1f mm a do strany o %.1f mm" % [(ps[corner].y - p0[corner].y) * 1000.0, (ps[corner].x - p0[corner].x) * 1000.0] if corner >= 0 else "úsměv: koutek")
	var pf := HB.positions(topo, {"ex_frown": 1.0})
	var pb := HB.positions(topo, {"ex_brow_up": 1.0})
	var brow_f := 0.0
	var brow_b := 0.0
	for i in _idx("g"):
		var q := p0[i]
		if absf(q.x - 0.02) < 0.006 and absf(q.y - 1.69) < 0.004 and q.z > 0.05:
			brow_f = minf(brow_f, pf[i].y - q.y)
			brow_b = maxf(brow_b, pb[i].y - q.y)
	check(brow_f < -0.0015 and brow_b > 0.0025, "zamračení stáhne obočí dolů (%.1f mm), zvednuté obočí nahoru (%.1f mm)" % [brow_f * 1000.0, brow_b * 1000.0])
	var far := 0.0
	for prm in [{"ex_smile": 1.0}, {"ex_frown": 1.0}, {"ex_brow_up": 1.0}]:
		var p := HB.positions(topo, prm)
		for i in _idx("g"):
			if p0[i].z < -0.04:
				far = maxf(far, p[i].distance_to(p0[i]))
	check(far < 1e-6, "mimika nehýbe zadní částí hlavy (%.4f mm)" % (far * 1000.0))
	# zornice
	var pp := HB.positions(topo, {"ex_pupil": 1.0})
	var pn := HB.positions(topo, {"ex_pupil": -1.0})
	var front := -1
	var ring0 := -1
	for i in _idx("eb"):
		var r: Array = topo.recipes[i]
		if int(r[1]) == 1 and r[2] == "front":
			front = i
		if int(r[1]) == 1 and r[2] == "ring" and int(r[3]) == 0 and int(r[4]) == 0:
			ring0 = i
	var dp := pp[ring0].distance_to(pp[front])
	var dn := pn[ring0].distance_to(pn[front])
	check(dp > dn * 1.5 and dn > 0.001, "zornice: poloměr %.2f mm (stažená) … %.2f mm (rozšířená)" % [dn * 1000.0, dp * 1000.0])
	# lineárnost výrazů v blend shapes (bez mrkání – to má mezitvar)
	var wl := 0.0
	for k in ["ex_smile", "ex_frown", "ex_brow_up", "ex_jaw_open"]:
		var w := FM.expression_weights({k: 0.5})
		var a := _blend(w)
		var e := HB.positions(topo, {k: 0.5})
		for i in a.size():
			wl = maxf(wl, a[i].distance_to(e[i]))
	check(wl < 0.0006, "výrazy na 50 %% v blend shapes ≈ přesný tvar (nejhůř %.2f mm)" % (wl * 1000.0))


func _test_glb_visual() -> void:
	section("GLB a SimVisual")
	AssetLibrary.clear_cache()
	var root := AssetLibrary.instantiate("character")
	check(root != null, "character.glb se načte")
	if root == null:
		return
	var names := {}
	var lash_mi: MeshInstance3D = null
	var ex_keys := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		names[String(mi.name)] = true
		if String(mi.name).contains("__lashes__"):
			lash_mi = mi
		var m: Mesh = mi.mesh
		for i in m.get_blend_shape_count():
			if String(m.get_blend_shape_name(i)).begins_with("ex_"):
				ex_keys[String(m.get_blend_shape_name(i))] = true
	var want := ["head__lashes__eye_lash", "head__mouth__teeth_enamel", "head__mouth__mouth_gum", "head__mouth__mouth_tongue", "eyes__eyeballs__eye_limbus"]
	var missing: Array = []
	for n in want:
		if not names.has(n):
			missing.append(n)
	check(missing.is_empty(), "GLB obsahuje řasy, zuby, dáseň, jazyk a limbus", str(missing))
	var mat: BaseMaterial3D = lash_mi.mesh.surface_get_material(0) if lash_mi != null else null
	check(mat != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "řasy jsou oboustranné (glTF doubleSided)")
	check(ex_keys.has("ex_blink_l_pos") and ex_keys.has("ex_jaw_open_pos") and ex_keys.has("ex_smile_pos") and ex_keys.has(FM.inbetween_name("ex_blink_l", 1)),
		"blend shapes mimiky v GLB (%d)" % ex_keys.size(), str(ex_keys.keys()))
	root.free()
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look({"face": {"lash_length": 0.8, "teeth_shade": 0.6}, "skin": {"tone": 0.7}, "makeup": {"mascara": 0.5}})
	v.expressions_enabled = false
	var n := v.set_expression({"ex_smile": 1.0, "ex_jaw_open": 0.4})
	var ok_vals := true
	var cnt := 0
	for slot in v._expression_slots():
		var mi: MeshInstance3D = slot[0]
		var want_v := float(FM.expression_weights({"ex_smile": 1.0, "ex_jaw_open": 0.4}).get(slot[2], 0.0))
		cnt += 1
		if not is_equal_approx(mi.get_blend_shape_value(slot[1]), want_v):
			ok_vals = false
	check(cnt > 10 and n > 0 and ok_vals, "set_expression: %d slotů mimiky má hodnoty z FaceMorphs" % cnt)
	var brow_keys := 0
	var br = v.hair_part("brows")
	if br != null and br.mesh != null:
		for i in (br.mesh as Mesh).get_blend_shape_count():
			if String(br.mesh.get_blend_shape_name(i)).begins_with("ex_"):
				brow_keys += 1
	check(br == null or brow_keys >= 2, "obočí z karet převzalo mimiku přenosem (%d klíčů)" % brow_keys)
	# mrkání: simulace 120 s po 50 ms
	v.set_expression({"ex_smile": 0.0, "ex_jaw_open": 0.0})
	v._emotion = ""
	var blinks := 0
	var was := false
	var maxv := 0.0
	var t0 := Time.get_ticks_usec()
	for step in 2400:
		v.update_expression(0.05)
		var b := float(v._ex.get("ex_blink_l", 0.0))
		maxv = maxf(maxv, b)
		if b > 0.5 and not was:
			blinks += 1
		was = b > 0.5
	var us := float(Time.get_ticks_usec() - t0) / 2400.0
	check(blinks >= 18 and blinks <= 70 and maxv > 0.9, "mrkání: %d× za 2 min (reálně ~15–30/min v klidu je horní hranice; tady 2–6 s)" % blinks)
	check(us < 300.0, "krok mimiky %.0f µs (limit 300 µs)" % us)
	# řeč: čelist se hýbe jen během repliky
	v.apply("stand", 20.0, "stastny", "Test", "mluví", "Hele, to je teda den.")
	var jaw_max := 0.0
	for step in 40:
		v.update_expression(0.05)
		jaw_max = maxf(jaw_max, float(v._ex.get("ex_jaw_open", 0.0)))
	for step in 120:
		v.update_expression(0.05)
	check(jaw_max > 0.15 and float(v._ex.get("ex_jaw_open", 1.0)) < 0.02, "řeč: čelist se hýbe (max %.2f) a po replice zavře" % jaw_max)
	check(float(v._ex.get("ex_smile", 0.0)) > 0.4 and float(v._ex.get("ex_smile", 0.0)) <= 0.6, "šťastná emoce: jemný úsměv %.2f (≤ 0,6)" % float(v._ex.get("ex_smile", 0.0)))
	var top := 0.0
	for e in SimVisual.EMOTION_FACE:
		for x in (SimVisual.EMOTION_FACE[e] as Array).slice(0, 4):
			top = maxf(top, float(x))
	check(top <= 0.6, "žádná emoce nevede ke grimase (cíle ≤ %.2f)" % top)
	var lp: Dictionary = v.look_params
	var lp0 := Resolver.resolve({"face": {"lash_length": 0.8, "teeth_shade": 0.6}, "skin": {"tone": 0.7}})
	var brow: Color = (lp["hair_look"] as Dictionary)["brow"]
	check(lp.has("teeth") and lp.has("gum") and (lp["lash"] as Color).get_luminance() < (lp0["lash"] as Color).get_luminance()
		and (lp0["lash"] as Color).get_luminance() < brow.get_luminance(),
		"barvy zubů, dásně a řas z dat (řasy tmavší než obočí, řasenka je ztmaví)")
	v.queue_free()
