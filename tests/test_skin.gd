extends "res://tests/test_base.gd"
## Běh 10 – C4a kůže:
##  - SkinModel (Beer–Lambert: melanin / hemoglobin / karoten): spojitost, monotonie, celé spektrum, podtón,
##    prokrvení, robustnost, shoda s dřívějšími kotvami, shoda CPU barvy s chromofory pro shader,
##  - SkinLayers: determinismus (i po síťovém kódování), kvantizace, skryté položky, limity, umístění jizev
##    a tetování NA povrchu těla/hlavy, rozmístění jen z detail_seed (nikdy ze jména/identity), stárnutí,
##  - shader kůže se zkompiluje a má všechny parametry, materiál dostane konstanty modelu,
##  - AssetLibrary: klidové polohy v CUSTOM0, zachované blend shapes a kosti, jen u sítí kůže,
##  - SimVisual: vlastní ShaderMaterial na postavu, parametry = výstup resolveru, výkon,
##  - schéma v3: detail_seed, migrace v2 → v3, generátor, striktní validace,
##  - C3 review (Grok 74 / ChatGPT 78): mezitvary mají rodiče, váhy těla kvantované.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const SkinModel := preload("res://scripts/character/skin_model.gd")
const SkinLayers := preload("res://scripts/character/skin_layers.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")

## Dřívější kotvy odstínu (AppearanceResolver C1–C3) – SkinModel je nafitovaný tak, aby domácnost vypadala skoro stejně.
const OLD_ANCHORS := [
	[0.0, Color(0.98, 0.88, 0.81)], [0.2, Color(0.93, 0.77, 0.66)], [0.4, Color(0.82, 0.62, 0.48)],
	[0.6, Color(0.64, 0.44, 0.31)], [0.8, Color(0.43, 0.28, 0.19)], [1.0, Color(0.23, 0.15, 0.1)],
]


func _ready() -> void:
	watchdog_seconds = 120.0
	_test_model()
	_test_layers()
	_test_placement()
	_test_shader()
	_test_meshes()
	await _test_visual()
	_test_schema_v3()
	_test_c3_review()
	finish("test_skin")


func _valid_base() -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = ["hravy"]
	return d


func _snap(d: Dictionary) -> Dictionary:
	var cd = CharacterData.create()
	cd.set_from_dict(d)
	return cd.public_snapshot()


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


# ---------------------------------------------------------------- model

func _test_model() -> void:
	section("SkinModel: fyzikální model barvy kůže")
	var max_step := 0.0
	var prev := SkinModel.albedo(0.0, 0.0, 0.3)
	var mono := true
	var distinct := {}
	for i in range(1, 1001):
		var t := float(i) / 1000.0
		var c := SkinModel.albedo(t, 0.0, 0.3)
		max_step = maxf(max_step, maxf(absf(c.r - prev.r), maxf(absf(c.g - prev.g), absf(c.b - prev.b))))
		if _lum(c) > _lum(prev) + 1e-7:
			mono = false
		prev = c
		if i % 10 == 0:
			distinct[Resolver.skin_color(t, 0.0, 0.3).to_html(false)] = true
	check(max_step < 0.01, "odstín je spojitý (největší skok %.4f na krok 0,001)" % max_step)
	check(mono, "světlost monotónně klesá s melaninem")
	check(distinct.size() >= 95, "celé spektrum: %d různých barev ze 100 kroků" % distinct.size())
	var lo := _lum(SkinModel.albedo(0.0, 0.0, 0.3))
	var hi := _lum(SkinModel.albedo(1.0, 0.0, 0.3))
	check(lo > 0.55 and hi < 0.04, "od velmi světlé (%.3f) po velmi tmavou (%.3f) lineární světlost" % [lo, hi])
	var max_dev := 0.0
	for a in OLD_ANCHORS:
		var c := SkinModel.albedo(float(a[0]), 0.0, 0.3)
		var o: Color = a[1]
		max_dev = maxf(max_dev, maxf(absf(c.r - o.r), maxf(absf(c.g - o.g), absf(c.b - o.b))))
	check(max_dev < 0.09, "shoda s dřívějšími kotvami (max odchylka %.3f) – domácnost vypadá skoro stejně" % max_dev)
	var ok_hue := true
	var ok_red := true
	for t in [0.1, 0.4, 0.7, 0.95]:
		var warm := SkinModel.albedo(t, 1.0, 0.3).srgb_to_linear()
		var cool := SkinModel.albedo(t, -1.0, 0.3).srgb_to_linear()
		if not (warm.g / warm.b > cool.g / cool.b):
			ok_hue = false
		var pale := SkinModel.albedo(t, 0.0, 0.0).srgb_to_linear()
		var flush := SkinModel.albedo(t, 0.0, 1.0).srgb_to_linear()
		if not (flush.r / flush.g > pale.r / pale.g):
			ok_red = false
	check(ok_hue, "podtón: teplý víc do zlata (G/B), chladný do růžova – na celém spektru")
	check(ok_red, "prokrvení zvyšuje podíl červené na celém spektru")
	var robust := true
	for v in [NAN, INF, -INF, -5.0, 9.0]:
		var c := SkinModel.albedo(v, v, v)
		if is_nan(c.r) or is_nan(c.g) or is_nan(c.b) or c.r < 0.0 or c.r > 1.0:
			robust = false
	check(robust, "nesmyslné vstupy (NaN, ±∞, mimo rozsah) → platná barva")
	# CPU barva (náhrada, rty, testy) a chromofory pro shader popisují totéž.
	var worst := 0.0
	for i in 21:
		var t := float(i) / 20.0
		var u := -1.0 + 0.1 * i
		var cpu := Resolver.skin_color(t, u, 0.3)
		var gpu := SkinModel.reflectance_linear(Resolver.skin_chromophores(t, u, 0.3)).linear_to_srgb()
		worst = maxf(worst, maxf(absf(cpu.r - gpu.r), maxf(absf(cpu.g - gpu.g), absf(cpu.b - gpu.b))))
	check(worst < 0.003, "kvantované chromofory pro shader = barva na CPU (odchylka %.4f)" % worst)
	# Audit Gemini (běh 10): žádná kombinace nesmí dát „mrtvolný“ šedý či zelený odstín – na celé mřížce
	# melanin × podtón × prokrvení musí zůstat sytost i odstín v rozsahu lidské kůže.
	var min_s := 1.0
	var h_lo := 1.0
	var h_hi := -1.0
	for ti in 21:
		for ui in 11:
			for ri in 6:
				var col := SkinModel.albedo(float(ti) / 20.0, -1.0 + 0.2 * ui, float(ri) / 5.0)
				min_s = minf(min_s, col.s)
				var hh := col.h if col.h < 0.5 else col.h - 1.0
				h_lo = minf(h_lo, hh)
				h_hi = maxf(h_hi, hh)
	check(min_s > 0.15 and h_lo * 360.0 > -10.0 and h_hi * 360.0 < 50.0,
		"celá mřížka 1 386 kombinací: sytost ≥ %.2f, odstín %.0f°…%.0f° (žádné šedé/zelené tóny)" % [min_s, h_lo * 360.0, h_hi * 360.0])
	check(not Schema.GROUPS["skin"]["fields"].has("preset") and not Schema.GROUPS["skin"]["fields"].has("race"),
		"kůže nemá předvolby ani kategorii „rasa“ – jen koncentrace chromoforů")


# ---------------------------------------------------------------- vrstvy

func _rich() -> Dictionary:
	var d := _valid_base()
	d["skin"].merge({"freckles": 0.6, "moles": 0.4, "acne": 0.3, "vitiligo": 0.2, "weathering": 0.3, "detail_seed": 4242}, true)
	d["skin"]["scars"] = [{"zone": "oblicej", "size": 0.5}, {"zone": "leva_paze", "size": 0.3}, {"zone": "bricho", "size": 0.2, "hidden": true}]
	d["skin"]["tattoos"] = [{"zone": "prava_paze", "design": "kvetina", "color": "#2b3550"}, {"zone": "krk", "design": "text", "color": "#1d1f24"},
		{"zone": "zada", "design": "ornament", "color": "#5a1f1f", "hidden": true}]
	d["makeup"].merge({"eyeliner": 0.7, "eyeshadow": 0.4, "blush": 0.3}, true)
	d["hair"].merge({"facial": "strniste", "brows": "huste"}, true)
	d["body"]["age"] = 52
	return d


func _test_layers() -> void:
	section("SkinLayers: deterministické vrstvy kůže")
	var d := _rich()
	var r := Validator.validate(d, {})
	check(bool(r["ok"]), "postava s pihami, jizvami, tetováním a make-upem je platná", str(r.get("errors")))
	var snap := _snap(r["data"])
	var a := SkinLayers.resolve(snap)
	var b := SkinLayers.resolve(snap.duplicate(true))
	check(var_to_str(a) == var_to_str(b), "stejný snapshot → bit po bitu stejné vrstvy")
	var code := Codec.encode_code(r["data"])
	var back := Codec.decode_code(code, {})
	var c := SkinLayers.resolve(_snap(back["data"]))
	check(var_to_str(a) == var_to_str(c), "po sdílecím kódu (síť) stejné vrstvy na klientu")
	var j = JSON.parse_string(JSON.stringify(snap))
	check(var_to_str(SkinLayers.resolve(j)) == var_to_str(a), "po JSON (čísla jako float) stejné vrstvy")
	var quant := true
	for k in a:
		var v = a[k]
		if typeof(v) == TYPE_FLOAT and absf(v * 10000.0 - roundf(v * 10000.0)) > 1e-3:
			quant = false
		if typeof(v) == TYPE_PACKED_VECTOR4_ARRAY:
			for q in v:
				for x in [q.x, q.y, q.z]:
					if absf(x * 10000.0 - roundf(x * 10000.0)) > 1e-3:
						quant = false
	check(quant, "výstup kvantovaný na 1/10000")
	check(int(a["scar_count"]) == 2 and int(a["tattoo_count"]) == 2, "skryté jizvy/tetování se nevykreslí (%d jizvy, %d tetování)" % [a["scar_count"], a["tattoo_count"]])
	check((a["scar0"] as PackedVector4Array).size() == SkinLayers.MAX_SCARS and (a["tattoo0"] as PackedVector4Array).size() == SkinLayers.MAX_TATTOOS,
		"pole pro shader mají pevnou délku")
	# Identita, jméno ani rod vrstvy nemění.
	var d2: Dictionary = r["data"].duplicate(true)
	d2["identity"]["first_name"] = "Kim"
	d2["identity"]["grammar"] = "f" if d2["identity"]["grammar"] != "f" else "m"
	d2["identity"]["gender_identity"] = "nebinarni"
	check(var_to_str(SkinLayers.resolve(_snap(d2))) == var_to_str(a), "jméno, rod ani identita rozmístění ani vzhled kůže nemění")
	var d3: Dictionary = r["data"].duplicate(true)
	d3["skin"]["detail_seed"] = 4243
	var a3 := SkinLayers.resolve(_snap(d3))
	check((a3["scar0"] as PackedVector4Array)[0] != (a["scar0"] as PackedVector4Array)[0], "jiné detail_seed → jiné rozmístění (explicitní volba hráče)")
	# Stárnutí
	var prev := -1.0
	var mono := true
	for age in [18, 25, 35, 45, 55, 65, 75, 90]:
		var e := _valid_base()
		e["body"]["age"] = age
		var w := float(SkinLayers.resolve(_snap(e))["wrinkles"])
		if w < prev - 1e-6:
			mono = false
		prev = w
	var young := _valid_base()
	young["body"]["age"] = 18
	check(mono and float(SkinLayers.resolve(_snap(young))["wrinkles"]) < 0.01 and prev > 0.6, "vrásky přibývají s věkem (18 let ≈ 0, 90 let %.2f)" % prev)
	# Limity a nesmysly (opravný vstup do resolveru – poškozený snapshot nesmí shodit klienta).
	var bad := {"skin": {"scars": [{"zone": "mimo"}, "x", {"zone": "krk", "size": NAN}], "tattoos": [{"zone": "krk", "design": "lebka"}],
		"freckles": "hodně", "detail_seed": -50}, "hair": {"facial": 7, "brows": "neexistuje"}, "makeup": [], "body": {"age": INF}}
	var rb := SkinLayers.resolve(bad)
	var fin := true
	for k in rb:
		if typeof(rb[k]) == TYPE_FLOAT and not is_finite(float(rb[k])):
			fin = false
	check(int(rb["scar_count"]) == 1 and int(rb["tattoo_count"]) == 0 and fin, "poškozený snapshot: neplatné položky vynechány, žádné NaN")
	var many := _valid_base()
	for i in 20:
		many["skin"]["scars"].append({"zone": "krk", "size": 0.2})
	check(int(SkinLayers.resolve(many)["scar_count"]) == SkinLayers.MAX_SCARS, "víc jizev než limit shaderu → oříznuto na %d" % SkinLayers.MAX_SCARS)
	var fz := SkinLayers.resolve(_snap(_valid_base()))
	check(float(fz["facial_density"]) == 0.0 and fz["facial_mask"] == Vector4.ZERO, "bez vousů: žádné strniště (nezávisle na rodu)")


# ---------------------------------------------------------------- umístění na povrchu

func _tris_of(model: Node3D, groups: Array) -> Array:
	var out := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not groups.has(String(mi.name).get_slice("__", 0)):
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var p: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			out.append([p[idx[t]], p[idx[t + 1]], p[idx[t + 2]]])
	return out


static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## Trojúhelníky rozdělené do mřížky 4 cm (rychlé hledání nejbližšího bodu povrchu).
static func _grid(tris: Array) -> Dictionary:
	var g := {}
	for t in tris:
		var lo: Vector3 = (t[0] as Vector3).min(t[1]).min(t[2])
		var hi: Vector3 = (t[0] as Vector3).max(t[1]).max(t[2])
		for x in range(floori(lo.x / 0.04), floori(hi.x / 0.04) + 1):
			for y in range(floori(lo.y / 0.04), floori(hi.y / 0.04) + 1):
				for z in range(floori(lo.z / 0.04), floori(hi.z / 0.04) + 1):
					var k := Vector3i(x, y, z)
					if not g.has(k):
						g[k] = []
					g[k].append(t)
	return g


static func _dist(p: Vector3, grid: Dictionary) -> float:
	var best := 1e9
	var c := Vector3i(floori(p.x / 0.04), floori(p.y / 0.04), floori(p.z / 0.04))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for t in grid.get(c + Vector3i(dx, dy, dz), []):
					best = minf(best, p.distance_to(_closest_on_tri(p, t[0], t[1], t[2])))
	return best


func _test_placement() -> void:
	section("Jizvy a tetování leží na povrchu těla (klidová poloha modelu)")
	var model := AssetLibrary.instantiate("character")
	if not check(model != null, "model postavy se načte"):
		return
	var head_tris := _grid(_tris_of(model, ["head"]))
	var body_tris := _grid(_tris_of(model, ["body"]))
	# Krk je od C3+ (běh 11–12) z větší části síť hlavy (krk těla je odříznutý nad smyčkou švu) → obě sítě.
	var neck_tris := _grid(_tris_of(model, ["head", "body"]))
	model.free()
	var worst := {}
	for zone in Schema.BODY_ZONES:
		var tris: Dictionary = head_tris if zone == "oblicej" else (neck_tris if zone == "krk" else body_tris)
		var w := 0.0
		for s in 12:
			var rng := SkinLayers._rng(s * 977 + 3, 1, 0)
			var pl := SkinLayers.place(zone, rng)
			w = maxf(w, _dist(pl["c"], tris))
		worst[zone] = w
	var ok := true
	var detail := []
	for zone in worst:
		var lim := 0.006 if zone == "oblicej" else (0.016 if zone == "krk" else 0.02)
		if float(worst[zone]) > lim:
			ok = false
		detail.append("%s %.1f mm" % [zone, float(worst[zone]) * 1000.0])
	check(ok, "střed každé položky ≤ 6 mm od obličeje, ≤ 2 cm od těla", ", ".join(detail))
	print("    vzdálenosti od povrchu: " + ", ".join(detail))


# ---------------------------------------------------------------- shader

func _test_shader() -> void:
	section("Shader kůže")
	var sh := SkinLayers.shader()
	if not check(sh != null, "shader kůže existuje"):
		return
	var names := {}
	for u in sh.get_shader_uniform_list():
		names[u["name"]] = true
	check(names.size() >= 39, "shader se zkompiloval (%d parametrů)" % names.size())
	var missing := []
	for k in SkinLayers.resolve({}):
		if not names.has(k):
			missing.append(k)
	for k in SkinModel.shader_constants():
		if not names.has(k):
			missing.append(k)
	for k in ["chrom", "eye", "eye_shape", "mouth"]:
		if not names.has(k):
			missing.append(k)
	check(missing.is_empty(), "každý výstup SkinLayers/SkinModel má v shaderu parametr", str(missing))
	var m := SkinLayers.make_material()
	var kc := SkinModel.shader_constants()
	check(m != null and m.get_shader_parameter("k_mel") == kc["k_mel"] and m.get_shader_parameter("rd") == kc["rd"],
		"materiál dostane konstanty modelu ze SkinModel (jediný zdroj pravdy)")
	var code := sh.code
	check(code.find("CUSTOM0") >= 0 and code.find("SSS_STRENGTH") >= 0, "masky z klidových poloh (CUSTOM0), podpovrchový rozptyl")


# ---------------------------------------------------------------- sítě

## Názvy blend shapes sítě kůže hlavy podle manifestu (face_spec: pole → tvary, _inbetweens, _correctives, _body_keys).
func _head_shape_names() -> Dictionary:
	var spec: Dictionary = AssetLibrary.manifest_meta("character").get("face_spec", {})
	var names := {}
	for k in spec:
		for n in spec[k]:
			names[String(n)] = true
	return names


func _test_meshes() -> void:
	section("AssetLibrary: klidové polohy v CUSTOM0")
	var model := AssetLibrary.instantiate("character")
	if not check(model != null, "model postavy se načte"):
		return
	var skin_count := 0
	var ok_c0 := true
	var ok_bs := true
	var ok_w := true
	var others_clean := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var me := mi.mesh as ArrayMesh
		var fmt := me.surface_get_format(0)
		var has_c0 := (fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0
		if AssetLibrary.is_skin_mesh(mi):
			skin_count += 1
			var arr := me.surface_get_arrays(0)
			var p: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0] if arr[Mesh.ARRAY_CUSTOM0] != null else PackedFloat32Array()
			if not has_c0 or c0.size() != p.size() * 4:
				ok_c0 = false
			else:
				for i in range(0, p.size(), 7):
					if Vector3(c0[i * 4], c0[i * 4 + 1], c0[i * 4 + 2]).distance_to(p[i]) > 1e-4:
						ok_c0 = false
			# hlava: obličejové morfy + mezitvary + korekce + klíče těla na pásu švu (C3+) – počet z manifestu
			# (tvary bez účinku – např. chin_cleft_neg, důlek je jen kladný – se do sítě nedávají)
			var is_head := String(mi.name).begins_with("head")
			var expect := _head_shape_names() if is_head else {}
			var nbs := me.get_blend_shape_count()
			var count_ok := (nbs >= 60 and nbs <= expect.size()) if is_head else nbs == 10
			if not count_ok or me.blend_shape_mode != Mesh.BLEND_SHAPE_MODE_NORMALIZED:
				ok_bs = false
			for bi in me.get_blend_shape_count():
				if is_head and not expect.has(String(me.get_blend_shape_name(bi))):
					ok_bs = false
			if String(mi.name).begins_with("head") and (mi as MeshInstance3D).find_blend_shape_by_name(&"nose_length_pos_mid") < 0:
				ok_bs = false
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := w.size() / p.size()
			for v in range(0, p.size(), 5):
				var s := 0.0
				for j in per:
					s += w[v * per + j]
				if absf(s - 1.0) > 0.01:
					ok_w = false
			if mi.skin == null:
				ok_w = false
		elif has_c0:
			others_clean = false
	model.free()
	check(skin_count == 2, "2 sítě kůže (tělo, hlava)")
	check(ok_c0, "CUSTOM0 = klidová poloha každého vrcholu")
	check(ok_bs, "blend shapes zachované (jména, počet, režim NORMALIZED)")
	check(ok_w, "kosti a váhy zachované (součet 1, Skin)")
	check(others_clean, "ostatní sítě (oblečení, oči, vlasy) beze změny")


# ---------------------------------------------------------------- SimVisual

func _test_visual() -> void:
	section("SimVisual: materiál kůže postavy")
	var v1 := SimVisual.new()
	var v2 := SimVisual.new()
	add_child(v1)
	add_child(v2)
	await get_tree().process_frame
	var d := _rich()
	var snap := _snap(Validator.validate(d, {})["data"])
	v1.apply_look(snap)
	v2.apply_look(_snap(_valid_base()))
	var m1 = v1.skin_material()
	var m2 = v2.skin_material()
	check(m1 is ShaderMaterial and m2 is ShaderMaterial, "kůže postavy používá shader kůže")
	check(m1 != m2, "každá postava má vlastní materiál kůže")
	var lp := Resolver.resolve(snap)
	var L: Dictionary = lp["skin_layers"]
	var same := m1 != null
	if same:
		var sm: ShaderMaterial = m1
		for key in ["chrom", "freckles", "tattoo_count", "tattoo0", "scar1", "brow_shape", "facial_mask"]:
			var want = lp["chrom"] if key == "chrom" else L[key]
			if var_to_str(sm.get_shader_parameter(key)) != var_to_str(want):
				same = false
	check(same, "parametry shaderu = výstup AppearanceResolveru")
	check(m2 != null and int(m2.get_shader_parameter("tattoo_count")) == 0, "druhá postava bez tetování (materiály se neovlivňují)")
	var shared := true
	for mi in v1.find_children("*", "MeshInstance3D", true, false):
		if AssetLibrary.is_skin_mesh(mi) and mi.material_override != m1:
			shared = false
	check(shared, "hlava i tělo postavy sdílí jeden materiál kůže (stejné parametry, žádný šev v barvě)")
	var t0 := Time.get_ticks_usec()
	for i in 50:
		v1.apply_skin(lp)
	var per := float(Time.get_ticks_usec() - t0) / 50000.0
	check(per < 0.5, "aplikace vrstev kůže %.3f ms (< 0,5 ms)" % per)
	var t1 := Time.get_ticks_usec()
	for i in 20:
		SkinLayers.resolve(snap)
	var per_r := float(Time.get_ticks_usec() - t1) / 20000.0
	check(per_r < 1.0, "výpočet vrstev ze snapshotu %.3f ms (< 1 ms)" % per_r)
	v1.queue_free()
	v2.queue_free()


# ---------------------------------------------------------------- schéma v3

func _test_schema_v3() -> void:
	section("Schéma v3: skin.detail_seed")
	check(Schema.VERSION >= 3, "verze schématu ≥ 3 (v4 od běhu 13 přidala body.neck_length)")
	check(Schema.defaults()["skin"].has("detail_seed"), "výchozí data mají detail_seed")
	check(Schema.is_public("skin", "detail_seed"), "detail_seed je ve veřejném snapshotu (ostatní hráči vidí stejné rozmístění)")
	var v2 := _valid_base()
	v2["v"] = 2
	v2["skin"].erase("detail_seed")
	v2["uid"] = "0123456789abcdef0123456789abcdef"
	var m := Codec.from_dict(v2, {})
	var seed1 := int(m["data"]["skin"]["detail_seed"]) if bool(m["ok"]) else -1
	var m2 := Codec.from_dict(v2.duplicate(true), {})
	check(bool(m["ok"]) and int(m["from_version"]) == 2 and seed1 >= 0 and seed1 <= 65535, "v2 se zmigruje na v3 (detail_seed %d)" % seed1)
	check(bool(m2["ok"]) and int(m2["data"]["skin"]["detail_seed"]) == seed1, "migrace je deterministická (z uid, ne ze jména)")
	var v2b: Dictionary = v2.duplicate(true)
	v2b["identity"]["first_name"] = "Jiné"
	check(int(Codec.from_dict(v2b, {})["data"]["skin"]["detail_seed"]) == seed1, "jméno migraci rozmístění neovlivní")
	var v2c: Dictionary = v2.duplicate(true)
	v2c["skin"]["detail_seed"] = 77
	check(int(Codec.from_dict(v2c, {})["data"]["skin"]["detail_seed"]) == 77, "existující hodnota se migrací nepřepíše")
	var bad := _valid_base()
	bad["skin"]["detail_seed"] = 70000
	check(not bool(Validator.validate(bad, {})["ok"]), "server odmítne detail_seed mimo 0..65535")
	bad["skin"]["detail_seed"] = NAN
	check(not bool(Validator.validate(bad, {})["ok"]), "server odmítne detail_seed NaN")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seen := {}
	var all_ok := true
	for i in 300:
		var g := Randomizer.generate(rng)
		var s := int(g["skin"]["detail_seed"])
		seen[s] = true
		if s < 0 or s > 65535:
			all_ok = false
	check(all_ok and seen.size() > 290, "generátor: rozmístění v mezích a pokaždé jiné (%d různých z 300)" % seen.size())


# ---------------------------------------------------------------- C3 review

func _test_c3_review() -> void:
	section("C3 review (Grok 74 / ChatGPT 78)")
	var model := AssetLibrary.instantiate("character")
	if model == null:
		check(false, "model postavy se načte")
		return
	var me: ArrayMesh = AssetLibrary.parts_in_group(model, "head")[0].mesh
	var names := {}
	for i in me.get_blend_shape_count():
		names[String(me.get_blend_shape_name(i))] = true
	model.free()
	var orphan := []
	var one_sided := []
	for n in names:
		if String(n).ends_with("_pos_mid") or String(n).ends_with("_neg_mid"):
			var parent: String = String(n).trim_suffix("_mid")
			if not names.has(parent):
				orphan.append(n)
			var field: String = parent.trim_suffix("_pos").trim_suffix("_neg")
			if names.has(field + "_pos_mid") != names.has(field + "_neg_mid") and names.has(field + "_pos") and names.has(field + "_neg"):
				one_sided.append(field)
	check(orphan.is_empty(), "každý mezitvar má rodičovský tvar (žádná ztracená váha)", str(orphan))
	check(one_sided.is_empty(), "nelineární morfy s mezitvarem ho mají pro obě strany", str(one_sided))
	var quant := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		var b := {}
		for k in ["frame", "muscle", "body_fat", "shoulders", "chest", "bust", "waist", "hips"]:
			b[k] = rng.randf()
		var w := BodyMorphs.weights(b)
		for k in w:
			if absf(float(w[k]) * 1000.0 - roundf(float(w[k]) * 1000.0)) > 1e-4:
				quant = false
	check(quant, "váhy těla jsou kvantované (1/1000) ještě před vazbou na obličej a korekcemi")
	# Vizuální kontrola C3 (běh 10, rasterizované snímky skutečného GLB): chyběla spodní plocha čelisti a úhel
	# brada–krk, dolní třetina obličeje byla krátká, krk byl vpředu. Profil v ose obličeje to teď hlídá.
	var HB = load("res://scripts/assets/head_builder.gd")
	var d: Dictionary = HB.derive({})
	var prof := []
	for i in 120:
		var a := deg_to_rad(-20.0 - float(i) * 0.75)
		prof.append(HB.surface(Vector3(0.0, sin(a), cos(a)), d))
	var chin_bottom := 9.0
	var throat_z := 9.0
	var chin_front := 0.0
	for q in prof:
		if q.y < 1.585 and q.y > 1.565:
			chin_front = maxf(chin_front, q.z)
		if q.z > 0.06 and q.y > 1.54:   # spodek brady (ne přední strana krku)
			chin_bottom = minf(chin_bottom, q.y)
		if absf(q.y - 1.53) < 0.006:
			throat_z = minf(throat_z, q.z)
	var mouth_chin := float(d["My"]) - chin_bottom
	check(mouth_chin > 0.04 and mouth_chin < 0.05, "dolní třetina: ústa–spodek brady %.1f cm (4–5 cm)" % (mouth_chin * 100.0))
	check(chin_front - throat_z > 0.03, "spodní plocha čelisti: brada %.1f cm před krkem (úhel brada–krk)" % ((chin_front - throat_z) * 100.0))
	var back_top: Vector3 = HB.surface(Vector3(0.0, sin(deg_to_rad(-112.0)), cos(deg_to_rad(-112.0))), d)
	var back_bot: Vector3 = HB.surface(Vector3(0.0, sin(deg_to_rad(-106.0)), cos(deg_to_rad(-106.0))), d)
	check(absf(back_top.z - back_bot.z) < 0.012, "zátylek navazuje na krk těla bez schodu (%.1f mm)" % (absf(back_top.z - back_bot.z) * 1000.0))
