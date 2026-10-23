extends "res://tests/test_base.gd"
## C4c (běh 22) – mikrodetail kůže a typ pleti: schéma v7 + migrace v6 → v7, validace na serveru (fuzz), SkinLayers.micro
## (zóny mazu a suchosti podle typu, věk, kvantování, determinismus), nezávislost na tónu kůže, rodu a jménu, náhodný
## generátor (rozložení typů, předvolby, zámky), veřejný snapshot, shader (parametry, kompilace, shoda vzorce drsnosti
## s CPU zrcadlem níže, LOD) a výkon.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const SkinLayers := preload("res://scripts/character/skin_layers.gd")

const MICRO_KEYS := ["oil_t", "oil_c", "dry_t", "dry_c", "pore_size", "micro", "vellus", "vellus_color"]
## Řádek shaderu, který CPU zrcadlo _rough() kopíruje (test hlídá, že se shader nezměnil bez zrcadla).
const SHADER_ROUGH_LINE := "rough += 0.22 * (dry - 0.125) - 0.38 * (oil - 0.04);"


func _ready() -> void:
	await get_tree().process_frame
	_test_schema()
	_test_migration()
	_test_validation()
	_test_zones()
	_test_independence()
	_test_randomizer()
	_test_snapshot()
	_test_shader()
	_test_perf()
	finish("test_skin_micro")


func _base() -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = "0123456789abcdef0123456789abcdef"
	d["identity"]["first_name"] = "Mira"
	d["personality"]["traits"] = ["hravy"]
	return d


func _layers(skin: Dictionary, age := 30) -> Dictionary:
	var d := _base()
	d["body"]["age"] = age
	d["skin"].merge(skin, true)
	return SkinLayers.resolve(d)


## CPU zrcadlo zónové drsnosti ze skin.gdshader (jen část C4c; základ 0,52). zone: "t" | "c" | "body".
func _rough(l: Dictionary, zone: String) -> float:
	var oil: float
	var dry: float
	match zone:
		"t":
			oil = float(l["oil_t"])
			dry = float(l["dry_t"])
		"c":
			oil = float(l["oil_c"])
			dry = float(l["dry_c"])
		_:
			oil = float(l["oil_c"]) * 0.5
			dry = float(l["dry_c"])
	return 0.52 + 0.22 * (dry - 0.125) - 0.38 * (oil - 0.04)


## Totéž s ořezem jako ve shaderu (ROUGHNESS = clamp(rough, 0.22, 0.88)).
func _rough_c(l: Dictionary, zone: String) -> float:
	return clampf(_rough(l, zone), 0.22, 0.88)


func _test_schema() -> void:
	section("Schéma v7")
	var f: Dictionary = Schema.GROUPS["skin"]["fields"]
	check(Schema.VERSION >= 7 and f.has("type") and f.has("oiliness") and f.has("dryness"), "schéma v7: skin.type, oiliness, dryness")
	check(String(Schema.default_value(f["type"])) == "normal" and is_equal_approx(float(Schema.default_value(f["oiliness"])), 0.35)
		and is_equal_approx(float(Schema.default_value(f["dryness"])), 0.25), "výchozí = normální pleť (maz 0,35, suchost 0,25)")
	check(Schema.is_public("skin", "type") and Schema.is_public("skin", "oiliness") and Schema.is_public("skin", "dryness"),
		"typ pleti je veřejný vzhled (vidí ho ostatní)")
	var ok := true
	for t in Schema.SKIN_TYPES:
		var pr: Array = Schema.SKIN_TYPE_PRESETS.get(t, [])
		ok = ok and pr.size() == 2 and float(pr[0]) >= 0.0 and float(pr[0]) <= 1.0 and float(pr[1]) >= 0.0 and float(pr[1]) <= 1.0
		ok = ok and SkinLayers.SKIN_TYPE_ZONES.has(t)
	check(ok and Schema.SKIN_TYPES.size() == 4, "4 typy pleti, každý má předvolbu v mezích a zónové násobky")


func _test_migration() -> void:
	section("Migrace v6 → v7")
	var v6 := _base()
	v6["v"] = 6
	for k in ["type", "oiliness", "dryness"]:
		v6["skin"].erase(k)
	v6["skin"]["tone"] = 0.8
	v6["skin"]["freckles"] = 0.3
	var r := Codec.from_dict(v6)
	check(bool(r["ok"]) and int(r["from_version"]) == 6 and int(r["data"]["v"]) == Schema.VERSION, "v6 se zmigruje na v7", str(r.get("errors", "")))
	if bool(r["ok"]):
		var s: Dictionary = r["data"]["skin"]
		check(String(s["type"]) == "normal" and is_equal_approx(float(s["oiliness"]), 0.35) and is_equal_approx(float(s["dryness"]), 0.25)
			and is_equal_approx(float(s["tone"]), 0.8) and is_equal_approx(float(s["freckles"]), 0.3), "migrace doplní výchozí typ a nemění ostatní pole")
		check(Resolver.resolve(r["data"])["chrom"] == Resolver.resolve(v6)["chrom"], "migrace nemění barvu kůže")
	var v6b := _base()
	v6b["v"] = 6
	v6b["skin"]["type"] = "oily"
	v6b["skin"]["oiliness"] = 0.9
	var r2 := Codec.from_dict(v6b)
	check(bool(r2["ok"]) and String(r2["data"]["skin"]["type"]) == "oily" and is_equal_approx(float(r2["data"]["skin"]["oiliness"]), 0.9),
		"migrace nepřepíše existující hodnoty")
	var v1 := {"v": 1, "identity": {"first_name": "Ota"}, "skin": {"tone": 0.3}}
	var r3 := Codec.from_dict(v1)
	check(bool(r3["ok"]) and int(r3["data"]["v"]) == Schema.VERSION and String(r3["data"]["skin"].get("type", "")) == "normal",
		"řetěz migrací v1 → v7 projde")
	var d := _base()
	d["skin"]["type"] = "combination"
	d["skin"]["oiliness"] = 0.61
	d["skin"]["dryness"] = 0.44
	var code := Codec.encode_code(d)
	var back := Codec.decode_code(code)
	check(bool(back["ok"]) and String(back["data"]["skin"]["type"]) == "combination" and is_equal_approx(float(back["data"]["skin"]["oiliness"]), 0.61),
		"sdílecí kód přenese typ pleti", str(back.get("errors", "")))
	var j := Codec.from_json(Codec.to_json(d))
	check(bool(j["ok"]) and is_equal_approx(float(j["data"]["skin"]["dryness"]), 0.44), "JSON round trip")


func _test_validation() -> void:
	section("Validace (server) – fuzz")
	var good := _base()
	good["skin"]["type"] = "dry"
	check(bool(Validator.validate(good, {"mode": "strict"})["ok"]), "platná suchá pleť projde přísnou validací")
	var bad_vals := [
		["type", "greasy"], ["type", 3], ["type", ""], ["type", "oily\u202e"], ["type", null],
		["oiliness", 1.5], ["oiliness", -0.1], ["oiliness", NAN], ["oiliness", INF], ["oiliness", "0.5"],
		["dryness", 2.0], ["dryness", NAN], ["dryness", []], ["dryness", {}],
	]
	var rejected := 0
	var repaired_ok := 0
	for bv in bad_vals:
		var d := _base()
		d["skin"][bv[0]] = bv[1]
		if not bool(Validator.validate(d, {"mode": "strict"})["ok"]):
			rejected += 1
		var rr := Validator.validate(d, {"mode": "repair"})
		if bool(rr["ok"]):
			var s: Dictionary = rr["data"]["skin"]
			if Schema.SKIN_TYPES.has(s["type"]) and float(s["oiliness"]) >= 0.0 and float(s["oiliness"]) <= 1.0 \
					and float(s["dryness"]) >= 0.0 and float(s["dryness"]) <= 1.0:
				repaired_ok += 1
	check(rejected == bad_vals.size(), "server odmítne všechny neplatné hodnoty (%d/%d)" % [rejected, bad_vals.size()])
	check(repaired_ok == bad_vals.size(), "opravný režim vrátí platná data (%d/%d)" % [repaired_ok, bad_vals.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crash_free := true
	for i in 300:
		var d := _base()
		var junk = [rng.randf_range(-5, 5), rng.randi(), "x".repeat(rng.randi_range(0, 40)), NAN, null, [1], {"a": 1}, true][rng.randi_range(0, 7)]
		d["skin"][["type", "oiliness", "dryness"][i % 3]] = junk
		var res := Validator.validate(d, {"mode": "repair"})
		crash_free = crash_free and res.has("ok")
		var l := SkinLayers.resolve(d)   # i bez validace nesmí resolver spadnout ani vrátit hodnoty mimo meze
		for k in ["oil_t", "oil_c", "dry_t", "dry_c", "micro"]:
			crash_free = crash_free and float(l[k]) >= 0.0 and float(l[k]) <= 1.0
	check(crash_free, "300 náhodně poškozených vstupů: validátor i resolver bez pádu a v mezích")


func _test_zones() -> void:
	section("Zóny mazu a suchosti podle typu")
	var n := _layers({"type": "normal", "oiliness": 0.35, "dryness": 0.25})
	var o := _layers({"type": "oily", "oiliness": 0.75, "dryness": 0.12})
	var c := _layers({"type": "combination", "oiliness": 0.6, "dryness": 0.4})
	var dr := _layers({"type": "dry", "oiliness": 0.15, "dryness": 0.65})
	check(is_equal_approx(float(n["oil_t"]), 0.21), "výchozí normální pleť: maz T-zóny 0,21 (drsnost blízko C4a)")
	check(_rough(o, "t") < _rough(n, "t") and _rough(n, "t") < _rough(dr, "t"), "T-zóna: mastná lesklejší než normální, suchá nejmatnější (%.3f / %.3f / %.3f)" % [_rough(o, "t"), _rough(n, "t"), _rough(dr, "t")])
	check(_rough(c, "t") < _rough(c, "c") - 0.1, "smíšená: lesklá T-zóna, matnější tváře (%.3f vs %.3f)" % [_rough(c, "t"), _rough(c, "c")])
	check(float(c["dry_c"]) > float(c["dry_t"]) and float(c["oil_t"]) > float(c["oil_c"]) * 2.0, "smíšená: suchost na tvářích, maz v T-zóně")
	check(float(dr["dry_c"]) > float(n["dry_c"]) and float(dr["oil_t"]) < float(n["oil_t"]), "suchá: víc suchosti všude, méně mazu")
	check(_rough(o, "c") < _rough(n, "c"), "mastná: lesklé i tváře")
	var lo := _layers({"type": "normal", "oiliness": 0.1})
	var hi := _layers({"type": "normal", "oiliness": 0.9})
	check(float(hi["oil_t"]) > float(lo["oil_t"]) and float(hi["pore_size"]) > float(lo["pore_size"]), "víc mazu → lesk a větší póry")
	var young := _layers({"type": "oily", "oiliness": 0.75}, 22)
	var old := _layers({"type": "oily", "oiliness": 0.75}, 82)
	check(float(old["oil_t"]) < float(young["oil_t"]) and float(old["dry_c"]) > float(young["dry_c"]) and float(old["micro"]) > float(young["micro"]),
		"věk: maz ubývá, suchost a mikroreliéf přibývá")
	var all_ok := true
	var quant := true
	for t in Schema.SKIN_TYPES:
		for ov in [0.0, 0.5, 1.0]:
			for dv in [0.0, 0.5, 1.0]:
				for age in [18, 50, 95]:
					var l := _layers({"type": t, "oiliness": ov, "dryness": dv, "weathering": 1.0}, age)
					for k in ["oil_t", "oil_c", "dry_t", "dry_c", "micro"]:
						all_ok = all_ok and float(l[k]) >= 0.0 and float(l[k]) <= 1.0
						quant = quant and is_equal_approx(float(l[k]) * 10000.0, roundf(float(l[k]) * 10000.0))
					all_ok = all_ok and float(l["pore_size"]) >= 1.0 and float(l["pore_size"]) <= 1.7
					for z in ["t", "c", "body"]:
						var r := _rough(l, z)
						all_ok = all_ok and r > 0.1 and r < 0.95
	check(all_ok, "108 kombinací typu × mazu × suchosti × věku: hodnoty v mezích, drsnost před ořezem 0,1–0,95")
	check(quant, "výstupy jsou kvantované (stejné bity na všech peerech)")


func _test_independence() -> void:
	section("Nezávislost na tónu kůže, rodu a jménu; determinismus")
	var a := _base()
	a["skin"]["type"] = "combination"
	a["skin"]["tone"] = 0.03
	a["skin"]["undertone"] = -0.8
	var b := a.duplicate(true)
	b["skin"]["tone"] = 0.97
	b["skin"]["undertone"] = 0.9
	b["skin"]["redness"] = 0.8
	b["identity"]["first_name"] = "Petr"
	b["identity"]["grammar"] = "f"
	b["identity"]["gender_identity"] = "nebinarni"
	var la := SkinLayers.resolve(a)
	var lb := SkinLayers.resolve(b)
	var same := true
	for k in MICRO_KEYS:
		same = same and var_to_str(la[k]) == var_to_str(lb[k])
	check(same, "mikrodetail (maz, suchost, póry, chloupky) nezávisí na tónu kůže, jménu, rodu ani identitě")
	var h := a.duplicate(true)
	h["hair"]["melanin"] = 0.05
	var lh := SkinLayers.resolve(h)
	check((lh["vellus_color"] as Vector3).length() > (la["vellus_color"] as Vector3).length(), "barva chloupků se řídí přirozenou barvou vlasů")
	var dyed := a.duplicate(true)
	dyed["hair"]["dyed"] = true
	dyed["hair"]["dye_color"] = "#ff00ff"
	check(var_to_str(SkinLayers.resolve(dyed)["vellus_color"]) == var_to_str(la["vellus_color"]), "barvení vlasů chloupky na kůži nemění")
	var c1 := CharacterData.create()
	c1.set_from_dict(a)
	var c2 := CharacterData.create()
	var dec := Codec.decode_code(Codec.encode_code(c1.to_dict()))
	c2.set_from_dict(dec["data"])
	check(var_to_str(SkinLayers.resolve(c1.public_snapshot())) == var_to_str(SkinLayers.resolve(c2.public_snapshot())),
		"determinismus: stejný vstup přes sdílecí kód → bit po bitu stejné parametry")


func _test_randomizer() -> void:
	section("Náhodný generátor")
	var rng := RandomNumberGenerator.new()
	var cnt := {}
	var by_gram := {"m": {}, "f": {}}
	var by_tone := {"light": {}, "dark": {}}
	var oil_by := {}
	var out := 0
	var n := 600
	for i in n:
		rng.seed = 5000 + i
		var d := Randomizer.generate(rng)
		var s: Dictionary = d["skin"]
		var t := String(s["type"])
		cnt[t] = int(cnt.get(t, 0)) + 1
		oil_by[t] = float(oil_by.get(t, 0.0)) + float(s["oiliness"])
		var g := String(d["identity"]["grammar"])
		if by_gram.has(g):
			by_gram[g][t] = int(by_gram[g].get(t, 0)) + 1
		var tk := "light" if float(s["tone"]) < 0.5 else "dark"
		by_tone[tk][t] = int(by_tone[tk].get(t, 0)) + 1
		if not Schema.SKIN_TYPES.has(t) or float(s["oiliness"]) < 0.0 or float(s["oiliness"]) > 1.0 or float(s["dryness"]) < 0.0 or float(s["dryness"]) > 1.0:
			out += 1
	check(out == 0, "generátor: typ a síly vždy v mezích")
	var dist_ok := true
	for t in Schema.SKIN_TYPES:
		var p := float(cnt.get(t, 0)) / float(n)
		dist_ok = dist_ok and p > 0.08 and p < 0.5
	check(dist_ok, "rozumné rozložení typů %s" % str(cnt))
	var mo := func(t): return float(oil_by.get(t, 0.0)) / maxf(1.0, float(cnt.get(t, 0)))
	check(mo.call("oily") > mo.call("combination") and mo.call("combination") > mo.call("normal") and mo.call("normal") > mo.call("dry"),
		"průměrný maz podle typu: mastná > smíšená > normální > suchá")
	var worst := 0.0
	for pair in [[by_gram["m"], by_gram["f"]], [by_tone["light"], by_tone["dark"]]]:
		var sa := 0
		var sb := 0
		for t in Schema.SKIN_TYPES:
			sa += int(pair[0].get(t, 0))
			sb += int(pair[1].get(t, 0))
		for t in Schema.SKIN_TYPES:
			worst = maxf(worst, absf(float(pair[0].get(t, 0)) / maxf(1, sa) - float(pair[1].get(t, 0)) / maxf(1, sb)))
	check(worst < 0.12, "typ pleti nezávisí na rodu ani tónu kůže (největší rozdíl podílů %.2f)" % worst)
	var base := Randomizer.generate(rng)
	base["skin"]["type"] = "dry"
	base["skin"]["oiliness"] = 0.05
	var locked := true
	for i in 30:
		rng.seed = 900 + i
		var d := Randomizer.generate(rng, base, ["skin.type", "skin.oiliness"])
		locked = locked and String(d["skin"]["type"]) == "dry" and is_equal_approx(float(d["skin"]["oiliness"]), 0.05)
	check(locked, "zámek typu pleti a mazu při náhodné postavě drží")
	rng.seed = 42
	var x := Randomizer.generate(rng)
	rng.seed = 42
	var y := Randomizer.generate(rng)
	x.erase("uid")
	y.erase("uid")
	check(var_to_str(x) == var_to_str(y), "stejný seed → stejná postava (včetně typu pleti)")


func _test_snapshot() -> void:
	section("Veřejný snapshot a síť")
	var d := _base()
	d["skin"]["type"] = "oily"
	d["skin"]["oiliness"] = 0.8
	var c := CharacterData.create()
	c.set_from_dict(d)
	var snap: Dictionary = c.public_snapshot()
	check(String(snap["skin"].get("type", "")) == "oily" and is_equal_approx(float(snap["skin"].get("oiliness", -1.0)), 0.8),
		"typ pleti je ve veřejném snapshotu")
	check(not snap.has("mind") and not snap.has("story"), "snapshot dál bez soukromých skupin")
	var lp := Resolver.resolve(snap)
	var layers: Dictionary = lp["skin_layers"]
	var miss: Array = []
	for k in MICRO_KEYS:
		if not layers.has(k):
			miss.append(k)
	check(miss.is_empty(), "AppearanceResolver předá mikrodetail do vrstev kůže", str(miss))


func _test_shader() -> void:
	section("Shader kůže (C4c)")
	var sh := SkinLayers.shader()
	if not check(sh != null, "shader kůže existuje"):
		return
	var names := {}
	for u in sh.get_shader_uniform_list():
		names[String(u["name"])] = true
	var miss: Array = []
	for k in MICRO_KEYS + ["micro_bump", "pores"]:
		if not names.has(k):
			miss.append(k)
	check(names.size() >= 48 and miss.is_empty(), "shader se zkompiloval a má parametry mikrodetailu (%d)" % names.size(), str(miss))
	var code := sh.code
	check(code.find(SHADER_ROUGH_LINE) >= 0, "vzorec zónové drsnosti v shaderu = CPU zrcadlo v testu")
	check(code.find("fwidth(p)") >= 0 and code.find("lod_p") >= 0 and code.find("near") >= 0, "póry mají LOD (velikost pixelu a vzdálenost)")
	check(code.find("dFdx(h)") >= 0 and code.find("NORMAL = normalize(") >= 0, "póry a linie mění normálu (bump), ne barvu")
	check(code.find("CLEARCOAT") >= 0 and code.find("RIM") >= 0, "maz jako clearcoat, chloupky jako rim")
	# mikrodetail nesmí záviset na melaninu: ve výpočtu h ani drsnosti se chromofory nepoužívají
	var start := code.find("// --- C4c (běh 22)")
	var end := code.find("ALBEDO = alb;")
	var block := code.substr(start, end - start)
	check(start > 0 and block.find("mel") < 0 and block.find("chrom") < 0, "zóny, póry a lesk nepoužívají melanin (fungují na všech tónech)")
	var m := SkinLayers.make_material()
	var lp := Resolver.resolve(_layers_snap("oily"))
	var nset := SkinLayers.apply(m, lp)
	check(nset > 30 and is_equal_approx(float(m.get_shader_parameter("oil_t")), float(lp["skin_layers"]["oil_t"])), "materiál dostane parametry mikrodetailu (%d)" % nset)
	var broken := Shader.new()
	broken.code = code.replace("RIM_TINT = 0.6;", "RIM_TINT = nonexistent_x;")
	check(broken.get_shader_uniform_list().is_empty(), "kontrola kompilace funguje (poškozený shader se nezkompiluje)")


func _layers_snap(t: String) -> Dictionary:
	var d := _base()
	d["skin"]["type"] = t
	var c := CharacterData.create()
	c.set_from_dict(d)
	return c.public_snapshot()


func _test_perf() -> void:
	section("Výkon")
	var snap := _layers_snap("combination")
	var t0 := Time.get_ticks_usec()
	for i in 200:
		SkinLayers.micro(snap["skin"], 40.0, 0.2, 0.3, Color(0.3, 0.2, 0.1))
	var us := float(Time.get_ticks_usec() - t0) / 200.0
	check(us < 150.0, "SkinLayers.micro %.1f µs (limit 150)" % us)
	var m := SkinLayers.make_material()
	var lp := Resolver.resolve(snap)
	t0 = Time.get_ticks_usec()
	for i in 50:
		SkinLayers.apply(m, lp)
	us = float(Time.get_ticks_usec() - t0) / 50.0
	check(us < 2000.0, "nastavení všech parametrů kůže %.0f µs (limit 2 ms)" % us)
	# statický rozpočet fragmentu: počet volání šumu v bloku C4c
	var code := SkinLayers.shader().code
	var start := code.find("// --- C4c (běh 22)")
	var block := code.substr(start, code.find("ALBEDO = alb;") - start)
	var calls := block.count("vnoise(") + block.count("cell_spots(")
	check(calls <= 5, "C4c přidává nejvýš 5 volání šumu na fragment (%d), všechna za LOD" % calls)
