extends "res://tests/test_base.gd"
## Běh 13 – délka krku (body.neck_length) na úrovni dat: schéma v4, migrace v3 → v4 (chybějící = 0, nic jiného
## se nemění), round-trip JSON / sdílecí kód / soubor, striktní validace serveru (fuzz nevalidních hodnot), veřejný
## snapshot pro MP, determinismus vah, nezávislost na rodu a identitě, rozložení v generátoru, zámek pole.
## Geometrii (blend shape b_neck_len, šev při extrémech, ohnutí krku) ověřuje tests/test_neck_seam.gd.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const FaceMorphs := preload("res://scripts/character/face_morphs.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")


func _ready() -> void:
	_test_schema()
	_test_migration()
	_test_round_trip()
	_test_validation()
	_test_public_and_weights()
	_test_randomizer()
	finish("test_neck_length")


func _valid_base() -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = ["hravy"]
	return d


func _test_schema() -> void:
	section("Schéma v4+ (neck_length od v4)")
	var spec: Array = Schema.fields("body").get("neck_length", [])
	check(Schema.VERSION >= 4, "verze schématu ≥ 4 (%d)" % Schema.VERSION)
	check(spec == ["f", -1.0, 1.0, 0.0], "body.neck_length: float −1..1, výchozí 0 (%s)" % str(spec))
	check(Schema.is_public("body", "neck_length"), "délka krku je veřejná (vzhled se replikuje)")
	check(float(Schema.defaults()["body"]["neck_length"]) == 0.0, "výchozí postava má neck_length 0")


func _test_migration() -> void:
	section("Migrace v3 → v4")
	var v3 := _valid_base()
	v3["v"] = 3
	(v3["body"] as Dictionary).erase("neck_length")
	v3["body"].merge({"height_cm": 181.5, "head_size": 0.4, "leg_length": 0.62, "shoulders": 0.71}, true)
	var r := Codec.from_dict(v3.duplicate(true))
	var out: Dictionary = r["data"]
	check(bool(r["ok"]) and int(r["from_version"]) == 3 and int(out.get("v", 0)) == Schema.VERSION, "v3 se načte jako aktuální verze", str(r["errors"]))
	check(out.get("body", {}).get("neck_length", null) == 0.0, "chybějící neck_length = 0 (nová výchozí délka)")
	var same := true
	for k in v3["body"]:
		if out["body"][k] != v3["body"][k]:
			same = false
	check(same, "ostatní pole těla beze změny (výška, hlava, nohy, ramena)")
	var face_same: bool = out["face"] == v3["face"] and out["skin"]["detail_seed"] == v3["skin"]["detail_seed"]
	check(face_same, "obličej a kůže beze změny")
	# v3, která už pole má (např. ruční úprava) – hodnota se zachová.
	var v3b := _valid_base()
	v3b["v"] = 3
	v3b["body"]["neck_length"] = -0.35
	check(float(Codec.from_dict(v3b)["data"]["body"]["neck_length"]) == -0.35, "existující hodnota se migrací nepřepíše")
	# Řetěz v1 → v4 (staré sdílené postavy).
	var v1 := _valid_base()
	v1["v"] = 1
	v1["face"]["asymmetry"] = 0.5
	for k in Schema.FACE_ASYMMETRY:
		(v1["face"] as Dictionary).erase(k)
	(v1["skin"] as Dictionary).erase("detail_seed")
	(v1["body"] as Dictionary).erase("neck_length")
	var r1 := Codec.from_dict(v1)
	check(bool(r1["ok"]) and int(r1["data"]["v"]) == Schema.VERSION and r1["data"]["body"]["neck_length"] == 0.0 and r1["data"]["face"].has("asym_eyes"),
		"řetěz migrací v1 → aktuální", str(r1["errors"]))
	var mig := Codec.migrate(v3.duplicate(true))
	check(bool(mig["ok"]) and mig["data"]["body"]["neck_length"] == 0.0 and not v3["body"].has("neck_length"), "migrace nemění vstupní slovník (kopie)")
	var newer := _valid_base()
	newer["v"] = Schema.VERSION + 1
	check(not bool(Codec.from_dict(newer)["ok"]), "postava z novější verze (%d) se odmítne" % (Schema.VERSION + 1))


func _test_round_trip() -> void:
	section("Round-trip: JSON, sdílecí kód, soubor")
	var d := _valid_base()
	d["body"]["neck_length"] = 0.437
	var rj := Codec.from_json(Codec.to_json(d))
	check(bool(rj["ok"]) and float(rj["data"]["body"]["neck_length"]) == 0.437, "JSON zachová 0,437")
	var code := Codec.encode_code(d)
	var rc := Codec.decode_code(code, {"mode": "strict"})
	check(bool(rc["ok"]) and float(rc["data"]["body"]["neck_length"]) == 0.437, "sdílecí kód zachová 0,437 (striktně)", str(rc["errors"]))
	var c = CharacterData.create()
	c.set_from_dict(rc["data"])
	check(float(c.to_dict()["body"]["neck_length"]) == 0.437, "CharacterData.to_dict zachová hodnotu")
	var fn := "test_neck_length_tmp.json"
	var err := Codec.save_file(rc["data"], fn)
	var rf := Codec.load_file(Codec.DIR + fn, {"mode": "strict"})
	check(err == OK and bool(rf["ok"]) and float(rf["data"]["body"]["neck_length"]) == 0.437, "soubor šablony zachová hodnotu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Codec.DIR + fn))
	# Kvantizace na 1/1000 (stejná hodnota na všech peerech).
	d["body"]["neck_length"] = 0.123456
	var rq := Validator.validate(d)
	check(bool(rq["ok"]) and float(rq["data"]["body"]["neck_length"]) == 0.123, "hodnota se kvantuje na 1/1000 (%s)" % str(rq["data"]["body"]["neck_length"]))


func _test_validation() -> void:
	section("Validace (server striktně, import opravou) + fuzz")
	var bad_vals := [1.0001, -1.5, 7.0, NAN, INF, -INF, "dlouhý", null, [0.2], {"x": 1}, true]
	var rejected := 0
	var repaired_ok := 0
	for bv in bad_vals:
		var d := _valid_base()
		d["body"]["neck_length"] = bv
		var rs := Validator.validate(d)
		if not bool(rs["ok"]):
			rejected += 1
		var rr := Validator.validate(d, {"mode": "repair"})
		var nv = rr["data"]["body"].get("neck_length", null)
		if (typeof(nv) == TYPE_FLOAT or typeof(nv) == TYPE_INT) and float(nv) >= -1.0 and float(nv) <= 1.0:
			repaired_ok += 1
	check(rejected == bad_vals.size(), "server odmítne všech %d nevalidních hodnot (%d)" % [bad_vals.size(), rejected])
	check(repaired_ok == bad_vals.size(), "opravný režim vrátí vždy číslo v ⟨−1; 1⟩ (%d/%d)" % [repaired_ok, bad_vals.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var wrong := 0
	for n in 400:
		var d := _valid_base()
		var x := rng.randf_range(-3.0, 3.0)
		d["body"]["neck_length"] = x
		var ok := bool(Validator.validate(d)["ok"])
		if ok != (x >= -1.0 and x <= 1.0):
			wrong += 1
	check(wrong == 0, "fuzz 400 hodnot: platné právě v ⟨−1; 1⟩ (%d chyb)" % wrong)
	var extra := _valid_base()
	extra["body"]["neck_len"] = 0.5   # neznámé pole (překlep / pokus o vlastní klíč)
	check(not bool(Validator.validate(extra)["ok"]), "neznámé pole body.neck_len server odmítne")
	var d0 := _valid_base()
	(d0["body"] as Dictionary).erase("neck_length")
	var r0 := Validator.validate(d0, {"mode": "repair"})
	check(float(r0["data"]["body"]["neck_length"]) == 0.0, "chybějící pole doplní validátor výchozí hodnotou")


func _test_public_and_weights() -> void:
	section("Veřejný snapshot, váhy a determinismus")
	var c = CharacterData.create()
	c.set_path_value("body.neck_length", -0.8)
	var pub: Dictionary = c.public_snapshot()
	check(float(pub.get("body", {}).get("neck_length", 9.0)) == -0.8, "veřejný snapshot nese neck_length (replikuje se všem)")
	check(bool(Validator.validate(pub, {"public_only": true})["ok"]), "snapshot projde veřejnou validací")
	c.set_path_value("body.neck_length", 5.0)   # editor bez validace → snapshot je vždy kanonický
	check(float(c.public_snapshot()["body"]["neck_length"]) == 1.0, "poškozená hodnota v editoru → snapshot ořízne na 1")
	var lp := Resolver.resolve({"body": {"neck_length": 0.5}})
	check(float(lp["face"].get("b_neck_len", 9.0)) == 0.5, "AppearanceResolver: b_neck_len = 0,5")
	check(not (lp["body"] as Dictionary).has("neck_len"), "váhy SÍTĚ těla klíč krku nemají (není to tvar těla)")
	var lp2 := Resolver.resolve(JSON.parse_string(JSON.stringify({"body": {"neck_length": 0.5}})))
	check(lp2["face"]["b_neck_len"] == lp["face"]["b_neck_len"] and lp2["height_scale"] == lp["height_scale"] and lp2["head_scale"] == lp["head_scale"],
		"po přenosu sítí (JSON) stejné váhy i měřítka (determinismus)")
	var fw := FaceMorphs.weights({}, {"neck_len": NAN})
	var fw2 := FaceMorphs.weights({}, {"neck_len": -7.0})
	var fw3 := FaceMorphs.weights({}, {"neck_len": "x"})
	check(fw["b_neck_len"] == 0.0 and fw2["b_neck_len"] == -1.0 and fw3["b_neck_len"] == 0.0, "nesmysly → 0, mimo rozsah → ořez na −1")
	# Nezávislost: rod, identita ani jméno délku krku nemění.
	var a := Resolver.resolve({"identity": {"grammar": "f", "first_name": "Jana"}, "body": {"neck_length": 0.3}})
	var b := Resolver.resolve({"identity": {"grammar": "m", "first_name": "Karel"}, "body": {"neck_length": 0.3}})
	check(a["face"]["b_neck_len"] == b["face"]["b_neck_len"] and a["height_scale"] == b["height_scale"], "rod a jméno délku krku neovlivní")
	# Delší krk při stejné výšce = trochu menší měřítko těla (výška temene drží height_cm).
	var s_lo := BodyMorphs.scales({"neck_length": -1.0})
	var s_hi := BodyMorphs.scales({"neck_length": 1.0})
	check(float(s_hi["height_scale"]) < float(s_lo["height_scale"]) and absf(BodyMorphs.crown_height(s_hi) - BodyMorphs.crown_height(s_lo)) < 2e-4,
		"delší krk → menší měřítko těla, temeno ve stejné výšce (%.4f / %.4f)" % [float(s_lo["height_scale"]), float(s_hi["height_scale"])])


func _test_randomizer() -> void:
	section("Generátor: rozložení a zámek")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var vals := PackedFloat64Array()
	var by_g := {}
	var in_range := true
	for n in 600:
		var d := Randomizer.generate(rng)
		var v := float(d["body"]["neck_length"])
		in_range = in_range and v >= -0.8 and v <= 0.8 and bool(Validator.validate(d)["ok"])
		vals.append(v)
		var g := String(d["identity"]["grammar"])
		if not by_g.has(g):
			by_g[g] = []
		by_g[g].append(v)
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var sd := 0.0
	for v in vals:
		sd += (v - mean) * (v - mean)
	sd = sqrt(sd / vals.size())
	var tails := 0
	for v in vals:
		if absf(v) > 0.7:
			tails += 1
	check(in_range, "600 postav: neck_length v ⟨−0,8; 0,8⟩ a platné")
	check(absf(mean) < 0.04 and sd > 0.24 and sd < 0.34, "střed %.3f ≈ 0, rozptyl sd %.3f ≈ 0,3" % [mean, sd])
	check(tails < 30, "extrémy jsou vzácné (|v| > 0,7: %d z 600)" % tails)
	var worst := 0.0
	for g in by_g:
		var m := 0.0
		for v in by_g[g]:
			m += float(v)
		m /= float((by_g[g] as Array).size())
		if (by_g[g] as Array).size() >= 30:
			worst = maxf(worst, absf(m - mean))
	check(worst < 0.08, "délka krku nezávisí na gramatickém rodu (max. rozdíl průměrů %.3f)" % worst)
	var base := Randomizer.generate(rng)
	base["body"]["neck_length"] = 0.777
	var locked := Randomizer.generate(rng, base, ["body.neck_length"])
	check(float(locked["body"]["neck_length"]) == 0.777, "zamčená délka krku zůstane při náhodné postavě")
