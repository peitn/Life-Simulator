extends "res://tests/test_base.gd"
## Běh 9 – schéma v2 a nálezy review ChatGPT (zprávy 48 a 49):
##  - kontrakt repaired() (nikdy {}), fatální vstupy, 128bit uid (server přiděluje vlastní),
##  - hranaté závorky v textech (escapování až při vykreslení),
##  - multikulturní korpus jmen (validní projdou, zalgo/bidi/neviditelné ne),
##  - jizvy/tetování: veřejný snapshot jen parametry vykreslení a jen neskryté položky; striktní allowlist,
##  - migrace v1 → v2 (asymetrie, důlek), head_size a přesnost temene na celé mřížce,
##  - validace tabulky posunů kostí z manifestu, náhled české gramatiky.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")


func _ready() -> void:
	_test_repaired_contract()
	_test_uid()
	_test_brackets()
	_test_unicode_corpus()
	_test_scars_privacy()
	_test_migration_v1()
	_test_crown_grid()
	_test_bone_table()
	_test_grammar_preview()
	finish("test_character_v2")


func _valid_base() -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = ["hravy"]
	return d


func _test_repaired_contract() -> void:
	section("Kontrakt repaired(): nikdy prázdný výsledek")
	var big := {}
	for i in 100:
		big["k%d" % i] = i
	var newer := _valid_base()
	newer["v"] = Schema.VERSION + 5
	var cases := {"není slovník": "x", "null": null, "65+ klíčů": big, "novější verze": newer, "pole": [1, 2]}
	for nm in cases:
		var r := Validator.validate(cases[nm], {"mode": "repair"})
		var rep := Validator.repaired(cases[nm])
		var ok_strict := Validator.validate(rep)
		check(bool(r["fatal"]) and not bool(r["ok"]) and not rep.is_empty() and bool(ok_strict["ok"]),
			"%s → fatal, ale data jsou bezpečná výchozí postava (platná i striktně)" % nm, str(ok_strict["errors"]))
	var pub := Validator.repaired("x", {"public_only": true})
	check(not pub.has("uid") and not pub.has("mind") and bool(Validator.validate(pub, {"public_only": true})["ok"]),
		"fatální vstup ve veřejném režimu → platný veřejný snapshot bez soukromých polí")
	check(not bool(Validator.validate(_valid_base())["fatal"]), "platná data nejsou fatální")


func _test_uid() -> void:
	section("uid: 128 bit, server přiděluje vlastní")
	var a := CharacterData.new_uid()
	var b := CharacterData.new_uid()
	check(a.length() == 32 and a.is_valid_hex_number(false) and a != b, "new_uid = 32 hex znaků (128 bit), pokaždé jiné")
	var d := _valid_base()
	d["uid"] = "0123456789abcdef"
	check(bool(Validator.validate(d)["ok"]), "starší 64bit uid (16 hex) se dál přijme")
	d["uid"] = "0123456789abcdef0123"
	check(not bool(Validator.validate(d)["ok"]), "uid jiné délky se odmítne")
	# Přepsání uid serverem ověřuje funkčně tests/test_character_net (vstup s vlastní postavou).


func _test_brackets() -> void:
	section("Hranaté závorky v textech")
	var d := _valid_base()
	d["story"]["backstory"] = "Říkali mi [Ježek], protože jsem pořád pichlal. [b]tučně[/b]"
	d["identity"]["nickname"] = "[Ježek]"
	var r := Validator.validate(d)
	check(bool(r["ok"]) and String(r["data"]["story"]["backstory"]).find("[Ježek]") >= 0, "příběh a přezdívka smí obsahovat [ ] (data se nemění)")
	var safe := Validator.display_safe("[b]tučně[/b]")
	check(safe == "[lb]b]tučně[lb]/b]", "display_safe escapuje BBCode pro RichTextLabel (%s)" % safe)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = safe
	check(rtl.get_parsed_text() == "[b]tučně[/b]", "RichTextLabel zobrazí závorky doslova, žádné formátování")
	rtl.free()
	d["identity"]["first_name"] = "[Alex]"
	check(not bool(Validator.validate(d)["ok"]), "ve jménu závorky dál zakázané (jména jsou jen písmena a pár znaků)")


func _test_unicode_corpus() -> void:
	section("Multikulturní korpus jmen")
	var good := [
		"پریا", "عائشہ", "مُحَمَّد", "یوسف", "יִצְחָק", "שָׁלוֹם", "प्रिया", "क्षितिज", "অর্ক", "தமிழ்செல்வி", "సాయి",
		"ಕಾವ್ಯ", "അനു", "ਗੁਰਪ੍ਰੀਤ", "ગીતા", "สมชาย", "ณัฐพงศ์", "ສົມພອນ", "Nguyễn Thị Ánh", "Nguyê\u0303n",
		"ნინო", "Արամ", "አበበ", "김민준", "さくら", "ユウキ", "健太", "王小明", "Ελένη", "Наталья", "Çağrı", "Þórður",
		"Adébáyọ̀", "Kawaiʻi", "Ó Súilleabháin", "Siobhán", "Zoë-Ann", "D'Angelo", "Jiří", "Ağaoğlu", "Ngũgĩ", "Wołodźko",
	]
	var rejected: Array = []
	for n in good:
		if Validator.name_problem(n, 1, 24) != "":
			rejected.append("%s (%s)" % [n, Validator.name_problem(n, 1, 24)])
	check(rejected.is_empty(), "%d skutečných jmen z různých písem projde" % good.size(), "; ".join(rejected))
	var bad := {
		"zalgo (4 značky)": "Já\u0302\u0303\u0304na", "arabské zalgo": "مَُِّْ",
		"bidi override": "Ali\u202Ebaba", "RLM": "\u200Fسارا", "ZWJ": "Jan\u200Da", "ZWNJ v latince": "Ja\u200Cna",
		"značka na začátku": "िप्रिया", "emoji": "Ana\U01F600", "číslice": "Ana7", "podtržítko": "Ana_B",
		"matematické symboly": "Ana∑", "variační selektor": "Ana\uFE0F",
	}
	var passed: Array = []
	for k in bad:
		if Validator.name_problem(bad[k], 1, 24) == "":
			passed.append(k)
	check(passed.is_empty(), "%d záškodnických jmen odmítnuto" % bad.size(), str(passed))
	var cleaned := Validator.clean_name("پریا\u202E\u200B", 24)
	check(cleaned == "پریا", "oprava (import) zachová perské písmo a odstraní skryté znaky")


func _test_scars_privacy() -> void:
	section("Jizvy a tetování: soukromí ve veřejném snapshotu")
	var d := _valid_base()
	d["skin"]["scars"] = [{"zone": "oblicej", "size": 0.3}, {"zone": "leva_paze", "size": 0.5, "hidden": true}]
	d["skin"]["tattoos"] = [{"zone": "prava_paze", "design": "kvetina", "color": "#1d1f24"},
		{"zone": "zada", "design": "text", "color": "#2b3550", "hidden": true}]
	var r := Validator.validate(d)
	check(bool(r["ok"]), "vlastník smí položky skrýt (hidden)", str(r["errors"]))
	var cd = CharacterData.new()
	cd.set_from_dict(r["data"])
	var pub: Dictionary = cd.public_snapshot()
	var sc: Array = pub["skin"]["scars"]
	var ta: Array = pub["skin"]["tattoos"]
	check(sc.size() == 1 and String(sc[0]["zone"]) == "oblicej" and ta.size() == 1 and String(ta[0]["design"]) == "kvetina",
		"skryté jizvy a tetování ostatním nejdou")
	check((sc[0] as Dictionary).keys().size() == 2 and (ta[0] as Dictionary).keys().size() == 3, "veřejně jen parametry vykreslení (žádná metadata)")
	check((cd.skin["scars"] as Array).size() == 2, "vlastník má dál všechny položky")
	var d2 := pub.duplicate(true)
	d2["skin"]["scars"] = [{"zone": "krk", "size": 0.2, "hidden": false}]
	check(not bool(Validator.validate(d2, {"public_only": true})["ok"]), "klíč hidden ve veřejném snapshotu = chyba (server ho nepošle)")
	var d3 := _valid_base()
	d3["skin"]["scars"] = [{"zone": "krk", "size": 0.2, "hidden": "ano"}]
	check(not bool(Validator.validate(d3)["ok"]), "hidden musí být ano/ne")
	# Allowlist i z poškozených dat editoru (set_path_value bez validace).
	var ed = CharacterData.create()
	ed.set_from_dict(r["data"])
	ed.set_path_value("body.height_cm", 999.0)
	ed.set_path_value("face.secret", 1)
	ed.set_path_value("identity.attracted_to", ["zeny"])
	ed.set_path_value("identity.first_name", "Ali\u202E")
	var p2: Dictionary = ed.public_snapshot()
	var v2 := Validator.validate(p2, {"public_only": true})
	check(bool(v2["ok"]) and float(p2["body"]["height_cm"]) == 205.0 and not (p2["face"] as Dictionary).has("secret")
		and not (p2["identity"] as Dictionary).has("attracted_to"), "veřejný snapshot z poškozených dat je kanonický a jen z allowlistu", str(v2["errors"]))
	check(String(p2["identity"]["first_name"]).find("\u202E") < 0, "bidi znak ze jména se do snapshotu nedostane")


func _test_migration_v1() -> void:
	section("Migrace v1 → v2")
	var v1 := _valid_base()
	v1["v"] = 1
	v1["uid"] = "0123456789abcdef"
	for k in Schema.FACE_ASYMMETRY:
		v1["face"].erase(k)
	v1["face"]["asymmetry"] = 0.5
	v1["face"]["chin_cleft"] = -0.4
	var r := Codec.from_dict(v1)
	var f: Dictionary = r["data"].get("face", {})
	check(bool(r["ok"]) and int(r["from_version"]) == 1 and int(r["data"]["v"]) == Schema.VERSION, "v1 se zmigruje na v%d" % Schema.VERSION, str(r["errors"]))
	check(not f.has("asymmetry") and is_equal_approx(float(f["asym_eyes"]), 0.3) and is_equal_approx(float(f["asym_mouth"]), -0.225)
		and is_equal_approx(float(f["asym_jaw"]), 0.2), "jedna asymetrie → tři osy (0,3 / −0,225 / 0,2)")
	check(float(f["chin_cleft"]) == 0.0, "záporný důlek (v1 bez účinku) → 0")
	check(String(r["data"]["uid"]) == "0123456789abcdef", "uid se migrací nemění")
	var code := Codec.encode_code(v1)
	var srv := Codec.decode_code(code, {"mode": "strict"})
	check(bool(srv["ok"]), "server přijme kód postavy z v1 (migrace před striktní validací)", str(srv["errors"]))
	var rnd := Randomizer.generate(RandomNumberGenerator.new())
	var rs := Validator.validate(rnd)
	check(bool(rs["ok"]) and rnd["face"].has("asym_eyes") and rnd["body"].has("head_size"), "generátor tvoří v2 (osy asymetrie, velikost hlavy)", str(rs["errors"]))


func _test_crown_grid() -> void:
	section("Temeno = height_cm na celé mřížce (výška × nohy × hlava)")
	var worst := 0.0
	var n := 0
	var h := 145.0
	while h <= 205.0:
		var l := 0.0
		while l <= 1.0001:
			for hs in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				var sc := BodyMorphs.scales({"height_cm": h, "leg_length": l, "head_size": hs})
				worst = maxf(worst, absf(BodyMorphs.crown_height(sc) - h / 100.0))
				n += 1
			l += 0.05
		h += 1.0
	check(worst < 0.00001, "%d kombinací: nejhorší chyba temene %.4f mm (< 0,01 mm)" % [n, worst * 1000.0])
	var a := BodyMorphs.scales({"height_cm": 172.0, "head_size": 1.0})
	var b := BodyMorphs.scales({"height_cm": 172.0, "head_size": -1.0})
	var ha := float(a["height_scale"]) * float(a["head_scale"])
	var hb := float(b["height_scale"]) * float(b["head_scale"])
	check(absf(ha / hb - 1.06 / 0.94) < 0.01, "head_size mění velikost hlavy ±6 %% nezávisle na výšce (poměr %.3f)" % (ha / hb))
	var s1 := BodyMorphs.scales({"height_cm": 172.0, "head_size": 0.0})
	var s2 := BodyMorphs.scales(JSON.parse_string(JSON.stringify({"height_cm": 172.0, "head_size": 0.0})))
	check(s1 == s2, "měřítka po JSON bit po bitu stejná (determinismus)")


func _test_bone_table() -> void:
	section("Tabulka posunů kostí z manifestu se validuje")
	var w := {"frame": 1.0}
	var table := {"frame": {"upper_arm_l": [0.01, 0.0, 0.0], "neznama_kost": [0.01, 0, 0], "thigh_l": [NAN, 0, 0],
		"thigh_r": [5.0, 0, 0], "upper_arm_r": ["x", 0, 0], "neck": [0.0, 0.002, 0.0]}}
	var off := BodyMorphs.bone_offsets(w, table)
	check(off.size() == 2 and off.has("upper_arm_l") and off.has("neck"), "neznámá kost, NaN, obří posun a text se ignorují (%s)" % str(off.keys()))


func _test_grammar_preview() -> void:
	section("Náhled české gramatiky (editor)")
	var m := Grammar.preview("m", "Alex")
	var f := Grammar.preview("f", "Alex")
	var nn := Grammar.preview("n", "Alex")
	var pl := Grammar.preview("pl", "Alex")
	check(m[0] == "Alex se vrátil domů unavený." and f[0] == "Alex se vrátila domů unavená.", "on/ona: %s | %s" % [m[0], f[0]])
	check(nn[0] == "Alex se vrátilo domů unavené." and pl[0] == "Alex se vrátili domů unavení.", "ono/oni (opt-in): %s | %s" % [nn[0], pl[0]])
	check(nn[1] == "Alex je moje blízká osoba." and m[1] == "Alex je můj kamarád.", "vztahové slovo bez rodové nálepky u ono/oni")
	check(String(Schema.GROUPS["identity"]["fields"]["grammar"][0]) == "e" and Schema.GRAMMAR.has("n") and Schema.GRAMMAR.has("pl")
		and not Schema.GROUPS["identity"]["fields"].has("gender_from_grammar"),
		"rod je samostatná volba gramatiky (nezávislá na identitě)")
