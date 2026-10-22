extends "res://tests/test_base.gd"
## Test tvorby postavy – běh C1 (datový model):
##   schéma a výchozí hodnoty, round-trip (slovník / JSON / sdílecí kód / soubor / Resource),
##   migrace v0 → v1 (stejný vzhled jako dřív), striktní validace + fuzz nevalidních dat,
##   filtr jmen (řídicí/bidi/neviditelné znaky, zalgo, písma světa), limity kodeku (zip bomba, CRC),
##   determinismus vzhledu (síťové kódování), veřejný × soukromý snapshot, náhodný generátor
##   (meze, rozložení, nezávislost na identitě, zámky), undo/redo, česká gramatika rodu,
##   nastavení obsahu, výkon a integrace do světa (domácnost z CharacterData, žádný hash jména).

const Schema := preload("res://scripts/character/character_schema.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const History := preload("res://scripts/character/character_history.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const Main := preload("res://main.gd")

## Původní vzhled v0 (SimVisual před C1) pro test věrnosti migrace.
const OLD_SKIN := [Color(0.93, 0.78, 0.68), Color(0.87, 0.69, 0.58), Color(0.78, 0.58, 0.47),
	Color(0.62, 0.43, 0.32), Color(0.45, 0.3, 0.22), Color(0.33, 0.22, 0.16)]
const OLD_HAIR := [Color(0.08, 0.06, 0.05), Color(0.2, 0.13, 0.08), Color(0.36, 0.24, 0.14),
	Color(0.62, 0.5, 0.32), Color(0.42, 0.2, 0.1), Color(0.55, 0.53, 0.5)]

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	watchdog_seconds = 120.0
	rng.seed = 20261015
	get_node("/root/GameClock").running = false
	var gs := get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	_test_schema()
	_test_roundtrip()
	_test_migration()
	_test_names()
	_test_fuzz()
	_test_codec_limits()
	_test_determinism()
	_test_privacy()
	_test_randomizer()
	_test_history()
	_test_grammar()
	_test_content()
	_test_performance()
	await _test_world()
	finish("test_character")


func _valid_char(seed := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return Validator.validate(Randomizer.generate(r))["data"]


# ---------------------------------------------------------------- schéma

func _test_schema() -> void:
	section("Schéma a výchozí hodnoty")
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = "0123456789abcdef"
	var r := Validator.validate(d)
	check(not r["ok"] and str(r["errors"]).find("first_name") >= 0, "výchozí data bez jména neprojdou (jméno je povinné)", str(r["errors"]))
	check(not r["ok"] and str(r["errors"]).find("traits") >= 0, "bez rysu neprojde (aspoň 1 rys)")
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = ["hravy"]
	r = Validator.validate(d)
	check(r["ok"], "výchozí data se jménem jsou platná", str(r["errors"]))
	check(int(r["data"]["body"]["age"]) >= 18 and int(Schema.GROUPS["body"]["fields"]["age"][1]) == 18, "postavy jsou dospělé (věk ≥ 18 ve schématu)")
	var cd = CharacterData.create()
	check(cd.uid.length() == 32 and cd.version == Schema.VERSION, "CharacterData.create: uid a verze")
	check(Schema.fields("face").size() == Schema.FACE_MORPHS.size() + Schema.FACE_ASYMMETRY.size() and Schema.FACE_MORPHS.size() >= 25,
		"obličej má %d morfů + %d osy asymetrie" % [Schema.FACE_MORPHS.size(), Schema.FACE_ASYMMETRY.size()])
	var all_tops := true
	for cat in Randomizer.OUTFIT_POOLS:
		for t in Randomizer.OUTFIT_POOLS[cat]["top"]:
			all_tops = all_tops and Schema.TOPS.has(t)
	check(all_tops, "katalogy generátoru jsou podmnožinou schématu")
	# Kódy schématu nejsou etnické předvolby ani „rasa“.
	var bad_words := ["rasa", "race", "etni", "ethnic", "black", "white", "asian", "african", "europ", "cikan", "romsk"]
	var found := ""
	for g in Schema.GROUPS:
		for k in Schema.fields(g):
			var spec: Array = Schema.fields(g)[k]
			var keys: Array = [k]
			if spec[0] == "e" or spec[0] == "set":
				keys += (spec[1] as Dictionary).keys()
			for key in keys:
				for token in String(key).to_lower().split("_"):
					for w in bad_words:
						if token.begins_with(w):
							found += "%s.%s " % [g, key]
	check(found == "", "žádná volba „rasa“ ani etnické předvolby ve schématu", found)


# ---------------------------------------------------------------- round-trip

func _test_roundtrip() -> void:
	section("Round-trip serializace")
	var ok_json := true
	var ok_code := true
	var ok_res := true
	var max_len := 0
	for i in 60:
		var d := _valid_char(100 + i)
		var j := Codec.from_json(Codec.to_json(d))
		ok_json = ok_json and bool(j["ok"]) and j["data"] == d
		var code := Codec.encode_code(d)
		max_len = maxi(max_len, code.length())
		var c := Codec.decode_code(code)
		ok_code = ok_code and bool(c["ok"]) and c["data"] == d
		var cd = CharacterData.new()
		cd.set_from_dict(d)
		ok_res = ok_res and cd.to_dict() == d and cd.clone().to_dict() == d
	check(ok_json, "60 postav: JSON → validace → stejná data")
	check(ok_code, "60 postav: sdílecí kód → stejná data")
	check(ok_res, "CharacterData (Resource) to_dict/set_from_dict/clone beze ztráty")
	check(max_len < 2500, "sdílecí kód je krátký (max %d znaků)" % max_len)
	var d0 := _valid_char(7)
	check(Codec.save_file(d0, "test_c1.json") == OK, "uložení šablony do souboru")
	var lf := Codec.load_file(Codec.DIR + "test_c1.json")
	check(bool(lf["ok"]) and lf["data"] == d0, "načtení šablony ze souboru = stejná data", str(lf["errors"]))
	check(Codec.save_file(d0, "../../etc/x.json") != OK or not FileAccess.file_exists("user://../etc/x.json"),
		"uložení nejde mimo složku šablon (jméno souboru se ořízne)")
	check(Codec.save_file(d0, "a/b?.json") == ERR_INVALID_PARAMETER, "neplatné jméno souboru odmítnuto")
	DirAccess.remove_absolute(Codec.DIR + "test_c1.json")
	DirAccess.remove_absolute(Codec.DIR + "x.json")
	# .tres – Resource se dá uložit nativně.
	var cd = CharacterData.new()
	cd.set_from_dict(d0)
	check(ResourceSaver.save(cd, "user://test_c1.tres") == OK, "CharacterData jde uložit jako .tres")
	var back = ResourceLoader.load("user://test_c1.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(back != null and back.to_dict() == d0, "a načíst zpět beze ztráty")
	DirAccess.remove_absolute("user://test_c1.tres")


# ---------------------------------------------------------------- migrace

func _test_migration() -> void:
	section("Migrace v0 → v1")
	var LSX = load("res://scripts/assets/lsx_decoder.gd")
	var old := {"name": "Jana Nováková", "female": true, "traits": ["spolecensky", "gurman", "zarlivy"],
		"color": Color(0.85, 0.3, 0.35), "conditions": {"depression": 0.5}, "patterns": {"morning_worse": true}}
	var r := Codec.from_dict(old)
	check(r["ok"] and int(r["from_version"]) == 0, "v0 se zmigruje a projde validací", str(r["errors"]))
	var d: Dictionary = r["data"]
	check(d["identity"]["first_name"] == "Jana" and d["identity"]["last_name"] == "Nováková" and d["identity"]["grammar"] == "f",
		"jméno a rod převzaté z v0")
	check(d["mind"]["predispositions"].get("depression", 0.0) == 0.5 and d["mind"]["morning_worse"], "predispozice a vzorce převzaté")
	check(d["personality"]["traits"] == ["spolecensky", "gurman", "zarlivy"], "rysy převzaté")
	check(Codec.from_dict(old)["data"] == d, "migrace je deterministická (stejné uid i vzhled)")
	# Věrnost vzhledu: migrovaná postava vypadá jako před migrací (dřív hash jména).
	var max_diff := 0.0
	for nm in ["Jana Nováková", "Petr Dvořák", "Eliška Malá", "Karel Novák", "Marie Svobodová", "Tomáš Černý", "Ann Lee"]:
		var h: int = LSX.crc32(nm.to_utf8_buffer())
		var m: Dictionary = Codec.from_dict({"name": nm, "female": false, "traits": ["optimista"], "color": [0.3, 0.4, 0.5]})["data"]
		var res := Resolver.resolve(m)
		var os: Color = OLD_SKIN[h % 6]
		var oh: Color = OLD_HAIR[(h >> 3) % 6]
		var sc: Color = res["skin"]
		var hc: Color = res["hair"]
		max_diff = maxf(max_diff, maxf(maxf(absf(sc.r - os.r), absf(sc.g - os.g)), absf(sc.b - os.b)))
		max_diff = maxf(max_diff, maxf(maxf(absf(hc.r - oh.r), absf(hc.g - oh.g)), absf(hc.b - oh.b)))
	check(max_diff < 0.06, "po migraci kůže a vlasy odpovídají starému vzhledu (max odchylka %.3f)" % max_diff)
	var p_old: Dictionary = Codec.from_dict({"name": "Petr Dvořák", "female": false, "traits": ["lenoch"], "color": Color(0.25, 0.45, 0.75)})["data"]
	var res_p := Resolver.resolve(p_old)
	check(res_p["hair_variant"] == "hair_short" and float(res_p["body"]["bust"]) < 0.0, "stará mužská varianta: krátké vlasy, plošší hrudník z explicitního bust")
	var tc: Color = res_p["top"]
	check(absf(tc.r - 0.25) < 0.005 and absf(tc.g - 0.45) < 0.005 and absf(tc.b - 0.75) < 0.005, "barva oblečení zůstane", str(tc))
	# Po migraci se jméno na vzhled nepoužívá: přejmenování nic nezmění.
	var renamed: Dictionary = p_old.duplicate(true)
	renamed["identity"]["first_name"] = "Zdeněk"
	check(Resolver.resolve(renamed) == res_p, "po migraci změna jména vzhled nemění")
	check(not Codec.from_dict({"v": 99, "identity": {}})["ok"], "novější verze se odmítne")
	check(not Codec.from_dict({"v": 0})["ok"] and not Codec.from_dict({"foo": 1})["ok"], "neplatná verze / chybějící verze se odmítne")
	check(not Codec.from_dict({"v": NAN})["ok"], "verze NaN se odmítne")
	var bad_v0 := Codec.from_dict({"name": "Ja\u202Ena", "female": "ano", "traits": "x", "color": "zelená", "conditions": [1]})
	check(bad_v0["ok"] and Validator.validate(bad_v0["data"])["ok"], "poškozená v0 se opraví na platnou postavu", str(bad_v0["errors"]))


# ---------------------------------------------------------------- jména

func _name_ok(s: String) -> bool:
	return Validator.name_problem(s, 1, 24) == ""


func _test_names() -> void:
	section("Filtr jmen (server)")
	for good in ["Jana", "Zoë", "O'Brien", "Anne-Marie", "Nguyễn", "Ngo\u0302", "李", "محمد", "Søren", "Łukasz",
			"J. R.", "Đức", "Ὀδυσσεύς", "Ñandú"]:
		check(_name_ok(good), "povoleno: %s" % good, Validator.name_problem(good, 1, 24))
	var bad := {"bidi přepínač": "Jana\u202Eavon", "bidi izolace": "\u2066Jana", "neviditelná mezera": "Ja\u200Bna",
		"BOM": "\uFEFFJana", "řídicí znak": "Ja\nna", "tabulátor": "Ja\tna", "zalgo": "Ja\u0301\u0302\u0303\u0304na",
		"kombinující na začátku": "\u0301Jana", "číslice": "Jana2", "BBCode": "[b]Jana", "HTML": "<i>Jana", "prázdné": "",
		"jen mezery": "   ", "mezera na začátku": " Jana", "dvojitá mezera": "Jana  Nová", "příliš dlouhé": "A".repeat(25),
		"emoji": "Jana\U01F600", "soukromá zóna": "Jana\uE000", "měkký spojovník": "Ja\u00ADna", "tag znaky": "Jana\U0E0041",
		"hangul filler": "\u3164", "jen interpunkce": "-'."}
	for label in bad:
		check(not _name_ok(bad[label]), "odmítnuto: %s" % label)
	check(Validator.clean_name("Ja\u202Ena  [x]\u200B", 24) == "Jana x", "oprava jména (import) odstraní skryté znaky",
		Validator.clean_name("Ja\u202Ena  [x]\u200B", 24))
	check(Validator.text_problem("Řádek 1\nŘádek 2", 600, true) == "", "příběh smí mít víc řádků")
	check(Validator.text_problem("Ahoj\u2067", 600, true) != "" and Validator.text_problem("x".repeat(601), 600, true) != "",
		"příběh: bidi i nadměrná délka odmítnuty")
	var d := _valid_char(3)
	d["identity"]["first_name"] = "Ja\u202Ena"
	var strict := Validator.validate(d)
	var rep := Validator.validate(d, {"mode": "repair"})
	check(not strict["ok"] and rep["ok"] and rep["data"]["identity"]["first_name"] == "Jana",
		"server jméno s bidi odmítne, import ho opraví")


# ---------------------------------------------------------------- fuzz

## Mutace, které data VŽDY znehodnotí (server je musí odmítnout).
func _mutate(d: Dictionary, kind: int, r: RandomNumberGenerator) -> String:
	var g: String = ["body", "skin", "hair", "eyes", "voice", "makeup"][r.randi_range(0, 5)]
	var keys: Array = []
	for k in Schema.fields(g):
		if Schema.fields(g)[k][0] == "f":
			keys.append(k)
	var k: String = keys[r.randi_range(0, keys.size() - 1)]
	match kind:
		0:
			d[g][k] = Schema.fields(g)[k][2] + r.randf_range(0.01, 1000.0)
			return "nad maximem %s.%s" % [g, k]
		1:
			d[g][k] = Schema.fields(g)[k][1] - r.randf_range(0.01, 1000.0)
			return "pod minimem %s.%s" % [g, k]
		2:
			d[g][k] = NAN
			return "NaN"
		3:
			d[g][k] = INF
			return "Inf"
		4:
			d[g][k] = "0.5"
			return "číslo jako text"
		5:
			d["body"]["age"] = r.randi_range(0, 17)
			return "nezletilá postava"
		6:
			d["hair"]["style"] = "neexistuje_%d" % r.randi()
			return "neznámý účes"
		7:
			d["identity"]["grammar"] = ["x", "M", "", 1, null][r.randi_range(0, 4)]
			return "neplatný rod"
		8:
			d["personality"]["traits"] = ["optimista", "brucoun"]
			return "rysy v konfliktu"
		9:
			d["personality"]["traits"] = ["optimista", "aktivni", "pedant", "gurman"]
			return "rysy přes rozpočet"
		10:
			d["personality"]["traits"] = []
			return "žádný rys"
		11:
			d["skin"]["tattoos"] = []
			for i in 9:
				d["skin"]["tattoos"].append({"zone": "krk", "design": "text", "color": "#000000"})
			return "příliš mnoho tetování"
		12:
			d["clothing"]["bezne"]["top_color"] = "red"
			return "barva není #rrggbb"
		13:
			d["hacker"] = {"x": 1}
			return "neznámá skupina"
		14:
			d["body"]["wings"] = 1.0
			return "neznámé pole"
		15:
			d["identity"]["attracted_to"] = ["muzi", "muzi"]
			return "duplicitní položka množiny"
		16:
			d["mind"]["predispositions"] = {"sebeposkozovani": 1.0}
			return "nepovolená predispozice"
		17:
			d["identity"]["first_name"] = "A".repeat(10000)
			return "obří jméno"
		18:
			d["story"]["backstory"] = "x".repeat(5000)
			return "obří příběh"
		19:
			d["uid"] = "../../etc"
			return "neplatné uid"
		20:
			d["skin"] = [1, 2, 3]
			return "skupina není slovník"
		21:
			d["clothing"]["bezne"]["top"] = "brneni"
			return "neznámý kus oblečení"
		22:
			d["identity"]["gender_custom"] = "něco"
			d["identity"]["gender_identity"] = "muz"
			return "vlastní popis bez volby Jiné"
		23:
			var big := []
			for i in 5000:
				big.append(i)
			d["personality"]["aspirations"] = big
			return "obří seznam"
		24:
			d["v"] = Schema.VERSION + 1
			return "jiná verze"
		25:
			d["clothing"]["bezne"]["bottom"] = "zadne"
			d["clothing"]["bezne"]["top"] = "tricko"
			return "bez spodního dílu bez šatů"
	return "?"


func _test_fuzz() -> void:
	section("Fuzz validátoru (nevalidní data)")
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var accepted := PackedStringArray()
	var repair_bad := PackedStringArray()
	var not_idem := 0
	var total := 0
	for i in 650:
		var d := _valid_char(1000 + (i % 40))
		var kind := i % 26
		var what := _mutate(d, kind, r)
		total += 1
		var s := Validator.validate(d)
		if bool(s["ok"]):
			accepted.append(what)
		var rp := Validator.validate(d, {"mode": "repair"})
		var again := Validator.validate(rp["data"])
		if not bool(again["ok"]) and kind != 24:
			repair_bad.append("%s: %s" % [what, str(again["errors"])])
		if Validator.validate(rp["data"], {"mode": "repair"})["data"] != rp["data"]:
			not_idem += 1
	check(accepted.is_empty(), "server odmítl všech %d nevalidních vstupů (26 druhů)" % total, ", ".join(accepted.slice(0, 5)))
	check(repair_bad.is_empty(), "opravný režim vždy vrátí platnou postavu", "; ".join(repair_bad.slice(0, 3)))
	check(not_idem == 0, "oprava je idempotentní", str(not_idem))
	# Náhodné typy na místě celé postavy / skupin – nesmí spadnout.
	var weird: Array = [null, 1, "x", [], {}, {"v": 1}, {"v": 1, "identity": "x"}, {"v": 1, "body": {"age": []}},
		{"v": 1, "clothing": {"bezne": 5}}, {"v": 1, "skin": {"scars": [{"zone": "krk"}]}}, PackedByteArray([1, 2])]
	var crashed := false
	for w in weird:
		var res := Validator.validate(w)
		crashed = crashed or bool(res["ok"]) or typeof(res["data"]) != TYPE_DICTIONARY
	check(not crashed, "podivné typy vstupu: odmítnuty bez pádu")


# ---------------------------------------------------------------- kodek

func _test_codec_limits() -> void:
	section("Kodek: limity a poškozená data")
	var d := _valid_char(5)
	var code := Codec.encode_code(d)
	check(code.begins_with("LSC1.") and code.length() <= Schema.MAX_CODE_LEN, "formát kódu LSC1")
	var flip := code.substr(0, 20) + ("A" if code[20] != "A" else "B") + code.substr(21)
	check(not Codec.decode_code(flip)["ok"], "změna jednoho znaku → odmítnuto (CRC / komprese)")
	var bad_crc := code.substr(0, code.length() - 8) + "00000000"
	check(not Codec.decode_code(bad_crc)["ok"], "špatný kontrolní součet → odmítnuto")
	check(not Codec.decode_code("LSC1." + "A".repeat(Schema.MAX_CODE_LEN))["ok"], "příliš dlouhý kód → odmítnuto")
	check(not Codec.decode_code("XYZ.abc.00000000")["ok"] and not Codec.decode_code(42)["ok"], "cizí formát / jiný typ → odmítnuto")
	check(not Codec.decode_code("LSC1.@@@@.00000000")["ok"], "neplatné znaky base64 → odmítnuto")
	# Zip bomba: malý kód, který by se rozbalil na megabajty.
	var huge := ("{\"v\":1,\"x\":\"" + "a".repeat(200000) + "\"}").to_utf8_buffer()
	var z := huge.compress(FileAccess.COMPRESSION_DEFLATE)
	var bomb := "LSC1." + Marshalls.raw_to_base64(z).replace("+", "-").replace("/", "_").replace("=", "") + ".%08x" % load("res://scripts/assets/lsx_decoder.gd").crc32(huge)
	var t0 := Time.get_ticks_msec()
	var br := Codec.decode_code(bomb)
	check(bomb.length() < Schema.MAX_CODE_LEN and not br["ok"], "zip bomba (200 kB z %d znaků) → odmítnuto" % bomb.length(), str(br["errors"]))
	check(Time.get_ticks_msec() - t0 < 200, "odmítnutí bomby je rychlé")
	var arr := "[1,2,3]".to_utf8_buffer()
	var arr_code := "LSC1." + Marshalls.raw_to_base64(arr.compress(FileAccess.COMPRESSION_DEFLATE)).replace("+", "-").replace("/", "_").replace("=", "") + ".%08x" % load("res://scripts/assets/lsx_decoder.gd").crc32(arr)
	check(not Codec.decode_code(arr_code)["ok"], "JSON, který není objekt → odmítnuto")
	check(not Codec.from_json("{\"v\":1, ")["ok"], "poškozený JSON → odmítnuto")
	# Audit Gemini: hluboké vnoření (do limitu 32 kB) nesmí shodit server.
	var deep := ("[".repeat(16000) + "]".repeat(16000)).to_utf8_buffer()
	var deep_code := "LSC1." + Marshalls.raw_to_base64(deep.compress(FileAccess.COMPRESSION_DEFLATE)).replace("+", "-").replace("/", "_").replace("=", "") + ".%08x" % load("res://scripts/assets/lsx_decoder.gd").crc32(deep)
	check(not Codec.decode_code(deep_code)["ok"], "16 000 úrovní vnoření → odmítnuto bez pádu")
	var nested := {"v": Schema.VERSION, "identity": {"first_name": {"a": {"b": {"c": [[[[1]]]]}}}}}
	check(not Codec.from_dict(nested, {"mode": "strict"})["ok"], "vnořená data v poli jména → odmítnuto")
	# Kód zalomený v chatu (mezery, nové řádky) se načte.
	var wrapped := code.substr(0, 40) + " \n " + code.substr(40, 60) + "\r\n\t" + code.substr(100)
	check(Codec.decode_code(wrapped)["ok"], "kód s mezerami / zalomením řádků se načte")


# ---------------------------------------------------------------- determinismus

func _test_determinism() -> void:
	section("Determinismus vzhledu napříč peery")
	var same := true
	var net_same := true
	var json_same := true
	for i in 40:
		var d := _valid_char(300 + i)
		var cd = CharacterData.new()
		cd.set_from_dict(d)
		var snap: Dictionary = cd.public_snapshot()
		var a := Resolver.resolve(snap)
		same = same and Resolver.resolve(snap) == a
		# Síťové kódování (var_to_bytes) jako u MultiplayerSpawneru.
		var over_net = bytes_to_var(var_to_bytes(snap))
		var pv := Validator.repaired(over_net, {"public_only": true})
		net_same = net_same and Resolver.resolve(pv) == a
		var via_json = JSON.parse_string(JSON.stringify(snap))
		json_same = json_same and Resolver.resolve(Validator.repaired(via_json, {"public_only": true})) == a
	check(same, "stejný snapshot → stejný výsledek")
	check(net_same, "snapshot po síťovém kódování a validaci na klientu → bit po bitu stejný vzhled")
	check(json_same, "snapshot přes JSON → stejný vzhled")
	var tones := {}
	for t in 101:
		tones[Resolver.skin_color(t / 100.0, 0.0, 0.3).to_html()] = true
	check(tones.size() > 80, "odstín kůže je spojitý (%d různých ze 101 kroků)" % tones.size())
	var lum0 := Resolver.skin_color(0.0, 0.0, 0.3).get_luminance()
	var lum1 := Resolver.skin_color(1.0, 0.0, 0.3).get_luminance()
	var mono := true
	var prev := 2.0
	for t in 21:
		var l := Resolver.skin_color(t / 20.0, 0.0, 0.3).get_luminance()
		mono = mono and l <= prev + 0.001
		prev = l
	check(lum0 > 0.75 and lum1 < 0.2 and mono, "škála od velmi světlé po velmi tmavou, monotónně (%.2f → %.2f)" % [lum0, lum1])
	var warm := Resolver.skin_color(0.5, 1.0, 0.3)
	var cool := Resolver.skin_color(0.5, -1.0, 0.3)
	check(warm.g / warm.r > cool.g / cool.r and cool.b / cool.r > warm.b / warm.r, "podtón: teplý víc do žluta, chladný do růžova")
	check(Resolver.hair_color(1.0, 0.0, 1.0).is_equal_approx(Resolver.hair_color(0.0, 0.0, 1.0)), "úplně šedé vlasy nezávisí na pigmentu")


# ---------------------------------------------------------------- soukromí

func _test_privacy() -> void:
	section("Veřejný snapshot × soukromá data")
	var d := _valid_char(11)
	d["identity"]["gender_identity"] = "nebinarni"
	d["identity"]["attracted_to"] = ["zeny"]
	d["personality"]["aspirations"] = ["kariera"]
	d["story"]["backstory"] = "Tajemství"
	d["mind"]["predispositions"] = {"anxiety": 0.4}
	d["mind"]["traumas"] = ["sikana"]
	var cd = CharacterData.new()
	cd.set_from_dict(Validator.validate(d)["data"])
	var pub: Dictionary = cd.public_snapshot()
	var s := JSON.stringify(pub)
	var leaks := PackedStringArray()
	for needle in ["gender_identity", "nebinarni", "attracted_to", "aromantic", "asexual", "aspirations", "kariera",
			"backstory", "Tajemství", "predispositions", "anxiety", "sikana", "traumas", "uid", "morning_worse", "story", "mind"]:
		if s.find(needle) >= 0:
			leaks.append(needle)
	check(leaks.is_empty(), "veřejný snapshot neobsahuje identitu, orientaci, aspirace, příběh, predispozice ani uid", ", ".join(leaks))
	check(pub["identity"].has("first_name") and pub["identity"].has("grammar") and pub.has("body") and pub.has("clothing")
		and pub["personality"].has("traits"), "veřejný snapshot má jméno, rod (oslovení), vzhled, oblečení a rysy")
	check(Validator.validate(pub, {"public_only": true})["ok"], "veřejný snapshot projde validací pro veřejná data")
	var inj := pub.duplicate(true)
	inj["identity"]["attracted_to"] = ["muzi"]
	check(not Validator.validate(inj, {"public_only": true})["ok"], "soukromé pole podstrčené do veřejného snapshotu → chyba")
	var rp := Validator.repaired(inj, {"public_only": true})
	check(not rp["identity"].has("attracted_to") and not rp.has("mind"), "klient soukromé pole ze snapshotu zahodí")
	var priv: Dictionary = cd.private_part()
	check(priv["identity"]["gender_identity"] == "nebinarni" and priv["mind"]["predispositions"].has("anxiety")
		and not priv.has("body"), "soukromá část obsahuje citlivé údaje a nic veřejného")
	check(cd.conditions() == {"anxiety": 0.4}, "predispozice pro MentalState")


# ---------------------------------------------------------------- generátor

func _test_randomizer() -> void:
	section("Náhodná postava: meze, rozložení, nezávislost, zámky")
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var n := 600
	var invalid := 0
	var heights_f: Array = []
	var heights_m: Array = []
	var long_f := 0
	var long_m := 0
	var nf := 0
	var nm := 0
	var tone_bins := [0, 0, 0, 0, 0]
	var mind_n := 0
	var ages: Array = []
	var grey_old := 0.0
	var grey_young := 0.0
	var n_old := 0
	var n_young := 0
	var grammar_seen := {}
	var dyed := 0
	var styles := {}
	for i in n:
		var d := Randomizer.generate(r)
		var v := Validator.validate(d)
		if not bool(v["ok"]):
			invalid += 1
			if invalid < 3:
				print("    neplatná: ", v["errors"])
		var g: String = d["identity"]["grammar"]
		grammar_seen[g] = true
		var long_hair: bool = Schema.LONG_HAIR.has(d["hair"]["style"])
		styles[d["hair"]["style"]] = true
		if g == "f":
			nf += 1
			heights_f.append(float(d["body"]["height_cm"]))
			long_f += int(long_hair)
		elif g == "m":
			nm += 1
			heights_m.append(float(d["body"]["height_cm"]))
			long_m += int(long_hair)
		tone_bins[mini(int(float(d["skin"]["tone"]) * 5.0), 4)] += 1
		if not d["mind"]["predispositions"].is_empty() or not d["mind"]["traumas"].is_empty():
			mind_n += 1
		ages.append(int(d["body"]["age"]))
		if int(d["body"]["age"]) >= 65:
			grey_old += float(d["hair"]["grey"])
			n_old += 1
		elif int(d["body"]["age"]) <= 30:
			grey_young += float(d["hair"]["grey"])
			n_young += 1
		dyed += int(d["hair"]["dyed"])
	check(invalid == 0, "%d náhodných postav: všechny platné (striktně)" % n, str(invalid))
	var all_h: Array = heights_f + heights_m
	var mean := 0.0
	for h in all_h:
		mean += h
	mean /= all_h.size()
	var sd := 0.0
	for h in all_h:
		sd += (h - mean) * (h - mean)
	sd = sqrt(sd / all_h.size())
	check(mean > 165.0 and mean < 177.0 and sd > 6.0 and sd < 13.0, "výška: realistický průměr a rozptyl (%.1f ± %.1f cm)" % [mean, sd])
	var mf := 0.0
	var mm := 0.0
	for h in heights_f:
		mf += h
	for h in heights_m:
		mm += h
	mf /= maxi(heights_f.size(), 1)
	mm /= maxi(heights_m.size(), 1)
	check(absf(mf - mm) < 3.0, "výška nezávisí na rodu („ona“ %.1f vs „on“ %.1f cm)" % [mf, mm])
	var pf := float(long_f) / maxi(nf, 1)
	var pm := float(long_m) / maxi(nm, 1)
	check(absf(pf - pm) < 0.12, "účes nezávisí na rodu (dlouhé: %.0f %% vs %.0f %%)" % [pf * 100.0, pm * 100.0])
	var min_bin: int = tone_bins.min()
	check(min_bin > n * 0.13, "odstín kůže rovnoměrně přes celé spektrum (pětiny: %s)" % str(tone_bins))
	check(mind_n == 0, "bez výslovné volby se duševní predispozice ani traumata nelosují")
	var mind_on := 0
	for i in 300:
		var d2 := Randomizer.generate(r, {}, [], {"include_mind": true})
		if not d2["mind"]["predispositions"].is_empty():
			mind_on += 1
	check(mind_on > 15 and mind_on < 90, "s volbou jen u menšiny postav (%d z 300)" % mind_on)
	check(ages.min() >= 18 and ages.max() <= 95, "věk 18–95 (%d–%d)" % [ages.min(), ages.max()])
	check(grey_old / maxi(n_old, 1) > grey_young / maxi(n_young, 1) + 0.3, "šediny přibývají s věkem")
	check(grammar_seen.size() == 4, "generují se všechny rody (on/ona/ono/oni)", str(grammar_seen.keys()))
	check(styles.size() >= 14, "používá se celý katalog účesů (%d)" % styles.size())
	check(dyed > n * 0.04 and dyed < n * 0.2, "barvené vlasy menšina (%d)" % dyed)
	# Determinismus generátoru.
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 77
	r2.seed = 77
	var g1 := Randomizer.generate(r1, {"uid": "0123456789abcdef"})
	var g2 := Randomizer.generate(r2, {"uid": "0123456789abcdef"})
	check(g1 == g2, "stejné semínko → stejná postava")
	# Zámky.
	var base := _valid_char(55)
	var locked_ok := true
	var changed := 0
	for i in 30:
		var d3 := Randomizer.generate(r, base, ["body", "skin.tone", "hair.style", "identity.first_name", "identity.last_name"])
		locked_ok = locked_ok and d3["body"] == base["body"] and d3["skin"]["tone"] == base["skin"]["tone"] \
			and d3["hair"]["style"] == base["hair"]["style"] and d3["identity"]["first_name"] == base["identity"]["first_name"]
		if d3["face"] != base["face"]:
			changed += 1
		locked_ok = locked_ok and Validator.validate(d3)["ok"]
	check(locked_ok, "zamčené hodnoty (tělo, odstín, účes, jméno) zůstanou a výsledek je platný")
	check(changed == 30, "nezamčené se mění")
	var gl_ok := true
	for i in 40:
		var b2 := base.duplicate(true)
		b2["identity"]["grammar"] = "f"
		var d4 := Randomizer.generate(r, b2, ["identity.grammar"])
		gl_ok = gl_ok and d4["identity"]["grammar"] == "f" and (Randomizer.NAMES_F.has(d4["identity"]["first_name"]))
	check(gl_ok, "zamčený rod „ona“ → jméno a příjmení odpovídají rodu")


# ---------------------------------------------------------------- undo/redo

func _test_history() -> void:
	section("Undo/redo")
	var h = History.new()
	var a := _valid_char(1)
	h.reset(a)
	check(not h.can_undo() and not h.can_redo(), "prázdná historie")
	var b := a.duplicate(true)
	b["body"]["height_cm"] = 190.0
	h.push(b, "Výška", "", 0)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var c: Dictionary = Validator.validate(Randomizer.generate(r, b, ["body"]))["data"]
	h.push(c, "Náhodná postava", "", 1000)
	check(h.undo_label() == "Náhodná postava", "poslední krok = náhodná postava")
	check(h.undo() == b, "undo vrátí stav před náhodou (zámky zachovány)")
	check(h.undo() == a, "druhé undo vrátí původní stav")
	check(h.undo() == a and not h.can_undo(), "undo na začátku nic nerozbije")
	check(h.redo() == b and h.redo() == c and not h.can_redo(), "redo projde zpět dopředu")
	h.undo()
	var e := b.duplicate(true)
	e["skin"]["tone"] = 0.9
	h.push(e, "Odstín", "", 2000)
	check(not h.can_redo(), "nová změna po undo zahodí redo větev")
	# Tažení posuvníku = jeden krok.
	var h2 = History.new()
	h2.reset(a)
	for i in 30:
		var s := a.duplicate(true)
		s["body"]["height_cm"] = 150.0 + i
		h2.push(s, "Výška", "body.height_cm", 5000 + i * 30)
	check(h2.undo() == a and not h2.can_undo(), "30 kroků tažení posuvníku = jeden krok zpět")
	var h3 = History.new()
	h3.reset(a)
	for i in 150:
		var s := a.duplicate(true)
		s["body"]["height_cm"] = 150.0 + i * 0.1
		h3.push(s, "x", "", i * 1000)
	var steps := 0
	while h3.can_undo():
		h3.undo()
		steps += 1
	check(steps == History.MAX_STEPS, "historie má strop %d kroků" % History.MAX_STEPS)


# ---------------------------------------------------------------- gramatika

func _test_grammar() -> void:
	section("Česká gramatika rodu")
	check(Grammar.form("Uvařil(a) večeři, je unaven{y}", "m") == "Uvařil večeři, je unavený", "on")
	check(Grammar.form("Uvařil(a) večeři, je unaven{y}", "f") == "Uvařila večeři, je unavená", "ona")
	check(Grammar.form("Uvařil(a) večeři, je unaven{y}", "n") == "Uvařilo večeři, je unavené", "ono")
	check(Grammar.form("Uvařil(a) večeři, je unaven{y}", "pl") == "Uvařili večeři, je unavení", "oni")
	check(Grammar.norm("zzz") == "m" and Grammar.norm(5) == "m", "neplatný rod → výchozí")
	check(SimAgent.relationship_label(30.0, "m") == "kamarád" and SimAgent.relationship_label(30.0, "f") == "kamarádka"
		and SimAgent.relationship_label(30.0, "pl") == "kamarádská duše" and SimAgent.relationship_label(90.0, "n") == "nejbližší osoba",
		"vztahová slova podle rodu druhé postavy (neutrální opisy)")
	check(SimAgent.relationship_label(30.0, true) == "kamarádka", "zpětná kompatibilita (bool)")
	check(Grammar.my("m") == "můj" and Grammar.my("pl") == "moje", "přivlastňovací tvar k podstatnému jménu")


# ---------------------------------------------------------------- nastavení obsahu

func _test_content() -> void:
	section("Nastavení obsahu a citlivé volby")
	var d := _valid_char(21)
	d["mind"]["predispositions"] = {"depression": 0.5}
	d["mind"]["traumas"] = ["domaci_nasili"]
	var full := Validator.validate(d, {"mental_health": "full"})
	check(full["ok"] and full["data"]["mind"]["traumas"] == ["domaci_nasili"], "plně: predispozice a traumata se přijmou")
	var off := Validator.validate(d, {"mental_health": "off"})
	check(off["ok"] and off["data"]["mind"]["predispositions"].is_empty() and off["data"]["mind"]["traumas"].is_empty()
		and not (off["warnings"] as PackedStringArray).is_empty(),
		"vypnuto: citlivé údaje se nepřijmou (varování, ne chyba – postava může do hry)")
	var muted := Validator.validate(d, {"mental_health": "muted"})
	check(muted["ok"] and not muted["data"]["mind"]["predispositions"].is_empty(), "ztlumeno: data zůstanou, simulace je tlumí")
	var sh := false
	for k in Schema.PREDISPOSITIONS.keys() + Schema.TRAUMAS.keys():
		for w in ["sebepo", "self", "harm", "sui", "anorex", "bulim", "ppp", "jidl"]:
			sh = sh or String(k).find(w) >= 0
	check(not sh, "sebepoškozování ani PPP se v tvorbě postavy nenabízejí (ani jako predispozice)")
	var neutral := true
	for k in Schema.PREDISPOSITIONS:
		var e: String = Schema.PREDISPOSITIONS[k]["effects"]
		for w in ["žen", "muž", "slab", "bonus", "trest"]:
			neutral = neutral and e.to_lower().find(w) < 0
	check(neutral, "popisy predispozic jsou neutrální (žádná vazba na identitu, žádný bonus/trest)")


# ---------------------------------------------------------------- výkon

func _test_performance() -> void:
	section("Výkon (odezva posuvníku)")
	var holder := Node3D.new()
	add_child(holder)
	var v := Node3D.new()
	v.set_script(SimVisual)
	holder.add_child(v)
	var d := _valid_char(31)
	var cd = CharacterData.new()
	# Zahřátí: první aplikace postaví sítě vlasů/obočí/vousů pro účes (C4b, ~1 s na účes, pak sdílená cache).
	# Posuvník měří odezvu při stejném účesu; první sestavení účesu měří test_hair (a C6 ho přesune mimo snímek).
	cd.set_from_dict(Validator.validate(d)["data"])
	v.apply_look(cd.public_snapshot())
	var t0 := Time.get_ticks_usec()
	for i in 200:
		d["body"]["height_cm"] = 150.0 + (i % 50)
		d["skin"]["tone"] = float(i % 100) / 100.0
		var r := Validator.validate(d)
		cd.set_from_dict(r["data"])
		v.apply_look(cd.public_snapshot())
	var per := float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0
	check(per < 4.0, "změna posuvníku: validace + snapshot + aplikace vzhledu %.2f ms (< 4 ms)" % per)
	var t1 := Time.get_ticks_usec()
	var code := ""
	for i in 50:
		code = Codec.encode_code(d)
		Codec.decode_code(code)
	check(float(Time.get_ticks_usec() - t1) / 50.0 / 1000.0 < 10.0, "kódování + dekódování sdílecího kódu < 10 ms")
	holder.queue_free()


# ---------------------------------------------------------------- svět

func _test_world() -> void:
	section("Integrace: domácnost z CharacterData")
	var chars: Array = Main.household_characters()
	check(chars.size() == 3, "domácnost: 3 platné postavy")
	var world := Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(world)
	await get_tree().process_frame
	var sims: Array = world.get_sims()
	check(sims.size() == 3, "ve světě 3 postavy")
	var by := {}
	for s in sims:
		by[s.first_name()] = s
	var jana = by.get("Jana")
	var petr = by.get("Petr")
	var eli = by.get("Eliška")
	check(jana != null and petr != null and eli != null, "jména z CharacterData")
	if jana == null or petr == null or eli == null:
		world.queue_free()
		return
	check(jana.grammar == "f" and petr.grammar == "m" and jana.female and not petr.female, "rod z CharacterData")
	check(not jana.look.is_empty() and not jana.look.has("mind") and not jana.look.has("story"), "postava nese jen veřejný snapshot")
	check(jana.mental.conditions.has("depression") and eli.mental.conditions.has("anxiety") and petr.mental.conditions.is_empty(),
		"soukromé predispozice nastavené na autoritě")
	check(jana.mental.dep.morning_pattern and not eli.mental.dep.morning_pattern, "individuální vzorec z CharacterData")
	var hs: Array = []
	for s in [jana, petr, eli]:
		hs.append(float(s.visual.look_params.get("height_scale", 0.0)))
	check(hs[1] > hs[0] and hs[0] > hs[2], "výška postav podle dat (Petr 181 > Jana 167 > Eliška 163)", str(hs))
	check(eli.visual.look_params["hair_variant"] == "hair_long" and petr.visual.look_params["hair_variant"] == "hair_short",
		"účesy podle dat (copánky → dlouhá síť)")
	check(not eli.visual.skin_color.is_equal_approx(jana.visual.skin_color), "různé odstíny kůže podle dat")
	var before: Color = petr.visual.skin_color
	petr.sim_name = "Úplně Jiný Člověk"
	petr._update_visual()
	check(petr.visual.skin_color == before, "přejmenování postavy vzhled nezmění")
	check(petr.gendered("Pohádal(a) se") == "Pohádal se" and jana.gendered("Pohádal(a) se") == "Pohádala se", "slovesa podle rodu postavy")
	jana.grammar = "pl"
	check(jana.gendered("Pohádal(a) se") == "Pohádali se", "rod „oni“ → množné tvary")
	jana.grammar = "f"
	# Vlastní postava offline přes kód.
	var r := RandomNumberGenerator.new()
	r.seed = 8
	var mine: Dictionary = Validator.validate(Randomizer.generate(r))["data"]
	var own = world.spawn_character(mine, Main.ARRIVAL_POS, 1, "Ja_test")
	check(own != null and world.get_sims().size() == 4 and own.sim_name == "%s %s" % [mine["identity"]["first_name"], mine["identity"]["last_name"]],
		"vlastní postava přidána do světa")
	own.leave_world()
	world.unregister_sim(own)
	own.queue_free()
	await get_tree().process_frame
	check(world.get_sims().size() == 3, "odchod postavy ze světa (uvolnění, odregistrace)")
	world.queue_free()
	await get_tree().process_frame
