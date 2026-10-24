extends RefCounted
## CharacterCodec – serializace CharacterData:
##   - kanonický JSON (seřazené klíče) pro soubory šablon (user://characters/*.json),
##   - krátký sdílecí kód  LSC1.<base64url(zlib(JSON))>.<crc32 hex>  (do chatu, na fórum, do hello v MP),
##   - migrace starších verzí (v0 = původní formát domácnosti: jméno + pohlaví + barva + hash jména;
##     v1 → v2: jedna „asymmetry“ → tři osy asymetrie obličeje, důlek v bradě 0..1; v2 → v3: skin.detail_seed;
##     v3 → v4: body.neck_length = 0; v4 → v5: personality.hexaco = {}, personality.psyche_seed z uid;
##     v5 → v6: detaily obličeje – řasy, zuby – a řasenka s výchozími hodnotami).
## Každý vstup z venku (soubor, kód, síť) projde: limity velikosti → CRC → JSON → migrace → validátor.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const LSX := preload("res://scripts/assets/lsx_decoder.gd")

const CODE_PREFIX := "LSC1."
const DIR := "user://characters/"
const MAX_FILE_BYTES := 65536

## Původní vzhled v0 (SimVisual před C1): 6 odstínů kůže a 6 barev vlasů vybraných hashem jména.
## Migrace je převede na explicitní atributy, aby postava po migraci vypadala stejně (hodnoty
## nalezené prohledáním modelu AppearanceResolveru: max. odchylka kanálu ≤ 0,05).
## Kůže: [melanin, podtón, prokrvení]; vlasy: [eumelanin, feomelanin, šedivění].
const LEGACY_SKIN := [[0.18, 0.0, 0.0], [0.3, -0.1, 0.0], [0.43, -0.2, 0.0], [0.61, 0.0, 0.0], [0.78, 0.0, 0.0], [0.91, 0.0, 0.0]]
const LEGACY_HAIR := [[1.0, 0.45, 0.0], [0.96, 0.65, 0.0], [0.78, 0.9, 0.0], [0.34, 0.4, 0.0], [0.76, 1.0, 0.0], [0.92, 0.25, 0.55]]


static func to_json(d: Dictionary) -> String:
	return JSON.stringify(d, "", true)


## Výsledek jako u validátoru + "from_version" a případně "notes" z migrace.
static func from_json(text: String, opts := {}) -> Dictionary:
	if text.to_utf8_buffer().size() > Schema.MAX_JSON_BYTES:
		return _fail("data postavy jsou příliš velká")
	var j := JSON.new()
	if j.parse(text) != OK:
		return _fail("poškozený JSON (řádek %d)" % j.get_error_line())
	return from_dict(j.data, opts)


static func from_dict(d, opts := {}) -> Dictionary:
	var m := migrate(d)
	if not bool(m["ok"]):
		return _fail(String(m["error"]))
	var o := opts.duplicate()
	if int(m["from_version"]) < Schema.VERSION and not o.has("mode"):
		o["mode"] = "repair"   # starší data se opravují, neodmítají
	var r := Validator.validate(m["data"], o)
	r["from_version"] = m["from_version"]
	return r


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([msg]), "warnings": PackedStringArray(), "data": {}, "from_version": -1}


# ---------------------------------------------------------------- sdílecí kód

static func encode_code(d: Dictionary) -> String:
	var raw := to_json(d).to_utf8_buffer()
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var b64 := Marshalls.raw_to_base64(z).replace("+", "-").replace("/", "_").replace("=", "")
	return "%s%s.%08x" % [CODE_PREFIX, b64, LSX.crc32(raw)]


static func decode_code(code, opts := {}) -> Dictionary:
	if typeof(code) != TYPE_STRING:
		return _fail("kód postavy není text")
	if String(code).length() > Schema.MAX_CODE_LEN * 2:
		return _fail("kód postavy je příliš dlouhý")
	# Bílé znaky kdekoli v kódu (zalomení řádku při kopírování z chatu) se ignorují.
	var s := ""
	for ch in String(code):
		if not (ch in " \t\r\n"):
			s += ch
	if s.length() > Schema.MAX_CODE_LEN:
		return _fail("kód postavy je příliš dlouhý")
	if not s.begins_with(CODE_PREFIX):
		return _fail("neznámý formát kódu postavy")
	var parts := s.substr(CODE_PREFIX.length()).split(".")
	if parts.size() != 2 or parts[1].length() != 8 or not parts[1].is_valid_hex_number(false):
		return _fail("poškozený kód postavy")
	var b64 := parts[0].replace("-", "+").replace("_", "/")
	for c in b64:
		if not (c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"):
			return _fail("poškozený kód postavy (znaky)")
	while b64.length() % 4 != 0:
		b64 += "="
	var z := Marshalls.base64_to_raw(b64)
	if z.is_empty():
		return _fail("poškozený kód postavy (base64)")
	var raw := z.decompress_dynamic(Schema.MAX_JSON_BYTES + 1, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return _fail("poškozený kód postavy (komprese)")
	if raw.size() > Schema.MAX_JSON_BYTES:
		return _fail("data postavy jsou příliš velká")
	if "%08x" % LSX.crc32(raw) != parts[1].to_lower():
		return _fail("kód postavy je poškozený (kontrolní součet nesedí)")
	return from_json(raw.get_string_from_utf8(), opts)


# ---------------------------------------------------------------- soubory šablon

static func save_file(d: Dictionary, file_name: String) -> int:
	var fname := file_name.get_file()
	if fname == "" or not fname.ends_with(".json") or fname.length() > 64 or not fname.get_basename().is_valid_filename():
		return ERR_INVALID_PARAMETER
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + fname, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "\t", true))
	f.close()
	return OK


static func load_file(path: String, opts := {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("soubor neexistuje")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("soubor nejde otevřít")
	if f.get_length() > MAX_FILE_BYTES:
		return _fail("soubor je příliš velký")
	var o := opts.duplicate()
	if not o.has("mode"):
		o["mode"] = "repair"   # vlastní/stažené soubory se opravují; server vždy striktně
	return from_json(f.get_as_text(), o)


# ---------------------------------------------------------------- migrace

## {"ok", "data", "from_version", "error"} – data ve verzi Schema.VERSION (ještě nevalidovaná).
static func migrate(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "error": "data postavy nejsou slovník", "from_version": -1, "data": {}}
	var ver = d.get("v", null)
	if ver == null:
		if d.has("name"):
			return {"ok": true, "data": _from_v0(d), "from_version": 0}
		return {"ok": false, "error": "chybí verze dat postavy", "from_version": -1, "data": {}}
	if (typeof(ver) != TYPE_INT and typeof(ver) != TYPE_FLOAT) or is_nan(float(ver)):
		return {"ok": false, "error": "neplatná verze dat postavy", "from_version": -1, "data": {}}
	var v := int(ver)
	if v > Schema.VERSION:
		return {"ok": false, "error": "postava je z novější verze hry (%d)" % v, "from_version": v, "data": {}}
	if v < 1:
		return {"ok": false, "error": "neplatná verze dat postavy", "from_version": v, "data": {}}
	var data: Dictionary = d
	if v == 1:
		data = _v1_to_v2(data)
	if v <= 2:
		data = _v2_to_v3(data)
	if v <= 3:
		data = _v3_to_v4(data)
	if v <= 4:
		data = _v4_to_v5(data)
	if v <= 5:
		data = _v5_to_v6(data)
	if v <= 6:
		data = _v6_to_v7(data)
	if v <= 7:
		data = _v7_to_v8(data)
	return {"ok": true, "data": data, "from_version": v}


## Poměr os při převodu jedné velikosti asymetrie (v1) na tři osy (v2); znaménka = deterministická
## „strana“, aby migrovaná postava nebyla dokonale souměrná, když ji hráč nesouměrnou chtěl.
const V1_ASYM_SPLIT := {"asym_eyes": 0.6, "asym_mouth": -0.45, "asym_jaw": 0.4}


static func _v1_to_v2(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 2
	var face = d.get("face", null)
	if typeof(face) == TYPE_DICTIONARY:
		var a = face.get("asymmetry", null)
		face.erase("asymmetry")
		if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and not is_nan(float(a)) and not is_inf(float(a)):
			var amt := clampf(float(a), 0.0, 1.0)
			for k in V1_ASYM_SPLIT:
				if not face.has(k):
					face[k] = Validator.quant(clampf(amt * float(V1_ASYM_SPLIT[k]), -1.0, 1.0))
		var cl = face.get("chin_cleft", null)
		if (typeof(cl) == TYPE_FLOAT or typeof(cl) == TYPE_INT) and float(cl) < 0.0:
			face["chin_cleft"] = 0.0   # v1 měl −1..1, ale záporná hodnota nic nedělala
	return d


## v2 → v3: přibylo skin.detail_seed. Jednorázově se odvodí z uid (náhodný identifikátor postavy, ne jméno),
## aby migrované postavy neměly všechny stejné rozmístění pih a znamének; dál je to obyčejný atribut.
static func _v2_to_v3(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 3
	var skin = d.get("skin", null)
	if typeof(skin) == TYPE_DICTIONARY and not skin.has("detail_seed"):
		var uid = d.get("uid", "")
		skin["detail_seed"] = int(LSX.crc32(String(uid).to_utf8_buffer()) & 0xFFFF) if typeof(uid) == TYPE_STRING and String(uid) != "" else 0
	return d


## v3 → v4: přibyla body.neck_length. Chybějící = 0 (nová, anatomicky upravená výchozí délka krku – rozhodnutí
## #110); existující hodnota se nepřepisuje (validátor ji ořeže do rozsahu) a žádné jiné pole se nemění.
static func _v3_to_v4(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 4
	var body = d.get("body", null)
	if typeof(body) == TYPE_DICTIONARY and not body.has("neck_length"):
		body["neck_length"] = 0.0
	return d


## v4 → v5 (běh 20): osobnost a individualita psychiky. hexaco {} = všechny osy z rysů (chování beze změny);
## psyche_seed jednou z náhodného uid (ne ze jména), dál obyčejný atribut. Existující hodnoty se nepřepisují.
static func _v4_to_v5(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 5
	var pers = d.get("personality", null)
	if typeof(pers) == TYPE_DICTIONARY:
		if not pers.has("hexaco"):
			pers["hexaco"] = {}
		if not pers.has("psyche_seed"):
			var uid = d.get("uid", "")
			pers["psyche_seed"] = int(LSX.crc32(("psyche:" + String(uid)).to_utf8_buffer()) & 0xFFFF) if typeof(uid) == TYPE_STRING and String(uid) != "" else 0
	return d


## v5 → v6 (běh 21): detaily obličeje (řasy, zuby) a řasenka. Chybějící pole = výchozí hodnota ze schématu
## (řasy 0,5 = dosavadní vzhled, rovné zuby bez mezery), existující hodnoty se nepřepisují.
static func _v5_to_v6(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 6
	var face = d.get("face", null)
	if typeof(face) == TYPE_DICTIONARY:
		for k in Schema.FACE_DETAILS:
			if not face.has(k):
				face[k] = Schema.default_value(Schema.FACE_DETAILS[k][1])
	var mk = d.get("makeup", null)
	if typeof(mk) == TYPE_DICTIONARY and not mk.has("mascara"):
		mk["mascara"] = 0.0
	return d


## v6 → v7 (běh 22): typ pleti. Chybějící pole = „normální“ pleť s výchozí mazovitostí a suchostí (shader pak dá
## T-zóně stejnou drsnost jako dřív); existující hodnoty se nepřepisují.
static func _v6_to_v7(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 7
	var skin = d.get("skin", null)
	if typeof(skin) == TYPE_DICTIONARY:
		for k in ["type", "oiliness", "dryness"]:
			if not skin.has(k):
				skin[k] = Schema.default_value(Schema.GROUPS["skin"]["fields"][k])
	return d


## v7 → v8: scalar trait intensities and explicit psyche dispositions.
## Empty trait_levels retains the legacy categorical profile until edited.
static func _v7_to_v8(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	d["v"] = 8
	var pers = d.get("personality", null)
	if typeof(pers) == TYPE_DICTIONARY and not pers.has("trait_levels"):
		pers["trait_levels"] = {}
	var mind = d.get("mind", null)
	if typeof(mind) == TYPE_DICTIONARY and not mind.has("dispositions"):
		mind["dispositions"] = {}
	return d


static func _col(v) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v
	if typeof(v) == TYPE_ARRAY and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if typeof(v) == TYPE_STRING and Validator.is_color(v):
		return Color.html(v)
	return Color(0.36, 0.42, 0.48)


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false).to_lower()


## v0: {"name", "female", "traits", "color", "conditions", "patterns"} – vzhled se dřív
## odvozoval z pohlaví a hashe jména. Migrace ho jednou provždy převede na explicitní atributy
## (stejný vzhled jako před migrací), dál už se jméno na vzhled nepoužívá.
static func _from_v0(old: Dictionary) -> Dictionary:
	var d := Schema.defaults()
	var name := String(old.get("name", "")) if typeof(old.get("name")) == TYPE_STRING else ""
	var parts := name.strip_edges().split(" ", false, 1)
	d["identity"]["first_name"] = parts[0] if parts.size() > 0 else ""
	d["identity"]["last_name"] = parts[1] if parts.size() > 1 else ""
	var fem: bool = typeof(old.get("female")) == TYPE_BOOL and bool(old["female"])
	d["identity"]["grammar"] = "f" if fem else "m"
	d["identity"]["gender_identity"] = "zena" if fem else "muz"
	if fem:
		d["body"].merge({"height_cm": 166.0, "bust": 0.55, "hips": 0.6, "shoulders": 0.4, "waist": 0.42, "frame": 0.42}, true)
		d["hair"]["style"] = "dlouhe_rovne"
	else:
		d["body"].merge({"height_cm": 178.0, "bust": 0.05, "hips": 0.45, "shoulders": 0.62, "waist": 0.5, "frame": 0.58}, true)
		d["hair"]["style"] = "kratke"
	var h := LSX.crc32(name.to_utf8_buffer())
	var sk: Array = LEGACY_SKIN[h % LEGACY_SKIN.size()]
	d["skin"]["tone"] = sk[0]
	d["skin"]["undertone"] = sk[1]
	d["skin"]["redness"] = sk[2]
	var hc: Array = LEGACY_HAIR[(h >> 3) % LEGACY_HAIR.size()]
	d["hair"]["melanin"] = hc[0]
	d["hair"]["red"] = hc[1]
	d["hair"]["grey"] = hc[2]
	var tr = old.get("traits", [])
	d["personality"]["traits"] = (tr as Array).duplicate() if typeof(tr) == TYPE_ARRAY else []
	var c := _col(old.get("color", null))
	d["clothing"]["bezne"]["top_color"] = _hex(c)
	d["clothing"]["bezne"]["bottom_color"] = _hex(c.darkened(0.6).lerp(Color(0.18, 0.2, 0.25), 0.5))
	var cond = old.get("conditions", {})
	d["mind"]["predispositions"] = (cond as Dictionary).duplicate() if typeof(cond) == TYPE_DICTIONARY else {}
	var pat = old.get("patterns", {})
	d["mind"]["morning_worse"] = bool((pat as Dictionary).get("morning_worse", false)) if typeof(pat) == TYPE_DICTIONARY else false
	d["v"] = Schema.VERSION
	d["uid"] = "%08x%08x" % [h, LSX.crc32(("uid:" + name).to_utf8_buffer())]
	return d
