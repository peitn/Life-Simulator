extends RefCounted
## CharacterValidator – ověření dat postavy proti schématu (character_schema.gd).
##
## Režimy:
##   "strict" – SERVER: každé chybné pole = chyba, data se odmítnou (nic se tiše „neopravuje“,
##              kromě doplnění chybějících polí výchozí hodnotou a odstranění citlivých údajů,
##              které server podle nastavení obsahu nepřijímá – to je varování, ne chyba).
##   "repair" – IMPORT / starší soubory / data ze serveru na klientu: hodnoty se ořežou do rozsahu,
##              neznámé položky zahodí, neplatné nahradí výchozí; výsledek je vždy platný.
##
## Volby (opts):
##   mode: "strict" | "repair"            (výchozí "strict")
##   public_only: bool                    – ověřuje veřejný snapshot (soukromá pole jsou chyba)
##   mental_health: "full"|"muted"|"off"  – nastavení obsahu; při "off" se predispozice a traumata
##                                          nepřijímají (odstraní se s varováním)
##
## Výsledek: {"ok": bool, "fatal": bool, "errors": PackedStringArray, "warnings": PackedStringArray, "data": Dictionary}
## `data` je kanonický slovník (čísla zaokrouhlená na 3 desetinná místa → deterministický vzhled). Kontrakt
## (review ChatGPT 48): `data` NIKDY není prázdný – když vstup nejde použít vůbec (není slovník, obří,
## neznámá novější verze), `fatal` = true a `data` jsou bezpečné výchozí hodnoty (ok = false).

const Schema := preload("res://scripts/character/character_schema.gd")
const Traits := preload("res://scripts/sim/traits.gd")

const QUANT := 1000.0
## Pojistka proti obřím vstupům (pole/slovníky delší než tohle se ani neprochází).
const MAX_COLLECTION := 64
## Nejvýš 3 navazující kombinující znaky (hebrejská niqqud + dageš, vietnamština v NFD, dévanágarí);
## „zalgo“ jich mívá desítky.
const MAX_COMBINING_RUN := 3
## Zástupné jméno pro opravená/fatální data – rodově neutrální (audit Gemini, běh 9; dřív „Bezejmenná“).
const FALLBACK_NAME := "Bez jména"


static func validate(d, opts := {}) -> Dictionary:
	var v := _V.new()
	v.strict = String(opts.get("mode", "strict")) != "repair"
	v.public_only = bool(opts.get("public_only", false))
	v.mh = String(opts.get("mental_health", "full"))
	v.run(d)
	return {"ok": v.errors.is_empty(), "fatal": v.fatal, "errors": v.errors, "warnings": v.warnings, "data": v.out}


## Pohodlná zkratka: platný CharacterData z libovolného (i poškozeného) slovníku. Fatální vstup
## (není slovník, příliš velký, novější verze) = výchozí postava; kdo potřebuje rozlišit, volá validate().
static func repaired(d, opts := {}) -> Dictionary:
	var o := opts.duplicate()
	o["mode"] = "repair"
	return validate(d, o)["data"]


static func quant(x: float) -> float:
	return roundf(x * QUANT) / QUANT


# ---------------------------------------------------------------- jména a texty

## Znaky, které nikdy nepatří do jména ani textu: řídicí, bidi přepínače, neviditelné, BOM, náhradní.
static func is_forbidden_char(c: int) -> bool:
	if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0):
		return true
	if (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F):
		return true
	if c == 0xFEFF or c == 0x00AD or c == 0x034F or c == 0x061C or c == 0x115F or c == 0x1160 or c == 0x3164:
		return true
	if (c >= 0xFE00 and c <= 0xFE0F) or (c >= 0xFFF0 and c <= 0xFFFF) or (c >= 0xE000 and c <= 0xF8FF):
		return true
	if c >= 0xE0000:  # tagy a variační selektory v astrálních rovinách
		return true
	return false


## Písmeno libovolného písma = Unicode XID_Start (Godot `is_valid_unicode_identifier`), bez „_“.
## Dřív tu byl ruční seznam bloků, který odmítal např. perská/urdská písmena (پ چ گ ی), bengálštinu,
## tamilštinu, gruzínštinu nebo etiopské písmo (review ChatGPT 48 – multikulturní korpus jmen).
static func is_letter(c: int) -> bool:
	if c == 0x5F or c < 0x41:
		return false
	return String.chr(c).is_valid_unicode_identifier()


## Kombinující/závislý znak (diakritika, samohlásková znaménka indických písem, arabské harakát, thajské
## tónové značky…) = XID_Continue, ale ne XID_Start; číslice a „_“ se nepočítají.
static func is_combining(c: int) -> bool:
	if c < 0x300 or is_letter(c):
		return false
	var s := String.chr(c)
	if s.is_valid_int():
		return false
	return ("a" + s).is_valid_unicode_identifier()


## Text bezpečný pro RichTextLabel s BBCode (hranaté závorky jsou v datech povolené – escapuje se
## až při vykreslení, review ChatGPT 48).
static func display_safe(s: String) -> String:
	return s.replace("[", "[lb]")


const NAME_PUNCT := [0x20, 0x2D, 0x27, 0x2019, 0x2E]  # mezera - ' ’ .


## Vrací "" když je jméno v pořádku, jinak popis chyby. (Bez oprav – na to je clean_name.)
static func name_problem(s: String, min_len: int, max_len: int) -> String:
	var n := s.length()
	if n < min_len:
		return "je prázdné" if n == 0 else "je příliš krátké"
	if n > max_len:
		return "je delší než %d znaků" % max_len
	if n > 0 and (s.begins_with(" ") or s.ends_with(" ") or s.find("  ") >= 0):
		return "má mezery navíc"
	var letters := 0
	var run := 0
	for i in n:
		var c := s.unicode_at(i)
		if is_forbidden_char(c):
			return "obsahuje skryté nebo řídicí znaky"
		if is_combining(c):
			run += 1
			if i == 0 or run > MAX_COMBINING_RUN:
				return "obsahuje nepovolené kombinující znaky"
			continue
		run = 0
		if is_letter(c):
			letters += 1
		elif not NAME_PUNCT.has(c):
			return "obsahuje nepovolený znak „%s“" % String.chr(c)
	if n > 0 and letters == 0:
		return "neobsahuje žádné písmeno"
	return ""


## Opraví jméno: zahodí zakázané znaky, slije mezery, ořízne délku.
static func clean_name(raw, max_len: int) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var s: String = raw
	if s.length() > max_len * 4:
		s = s.substr(0, max_len * 4)
	var out := ""
	var run := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if is_forbidden_char(c):
			continue
		if is_combining(c):
			run += 1
			if out == "" or run > MAX_COMBINING_RUN:
				continue
			out += String.chr(c)
			continue
		run = 0
		if is_letter(c) or NAME_PUNCT.has(c):
			if c == 0x20 and (out == "" or out.ends_with(" ")):
				continue
			out += String.chr(c)
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len).strip_edges()
	return out


static func text_problem(s: String, max_len: int, multiline: bool) -> String:
	if s.length() > max_len:
		return "je delší než %d znaků" % max_len
	var lines := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 0x0A and multiline:
			lines += 1
			if lines > 12:
				return "má příliš mnoho řádků"
			continue
		if is_forbidden_char(c):
			return "obsahuje skryté nebo řídicí znaky"
	return ""


static func clean_text(raw, max_len: int, multiline: bool) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var s: String = raw
	if s.length() > max_len * 4:
		s = s.substr(0, max_len * 4)
	var out := ""
	var lines := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 0x0A and multiline and lines < 12:
			lines += 1
			out += "\n"
			continue
		if is_forbidden_char(c):
			continue
		out += String.chr(c)
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len)
	return out


static func is_color(v) -> bool:
	if typeof(v) != TYPE_STRING or String(v).length() != 7 or not String(v).begins_with("#"):
		return false
	return String(v).substr(1).is_valid_hex_number(false)


static func _is_num(v) -> bool:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return false
	var f := float(v)
	return not is_nan(f) and not is_inf(f)


# ---------------------------------------------------------------- vlastní validace

class _V:
	var strict := true
	var public_only := false
	var mh := "full"
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var out := {}
	var fatal := false
	var CV: Script

	## V opravném režimu jsou chyby polí jen varování (hodnota se nahradí výchozí/ořízne);
	## `fatal` = data nejdou opravit vůbec (není slovník, neznámá verze).
	func err(path: String, msg: String, is_fatal := false) -> void:
		if is_fatal:
			fatal = true
		if not strict and not is_fatal:
			warn(path, msg + " (opraveno)")
			return
		if errors.size() < 40:
			errors.append("%s: %s" % [path, msg])

	func warn(path: String, msg: String) -> void:
		if warnings.size() < 40:
			warnings.append("%s: %s" % [path, msg])

	func run(d) -> void:
		CV = load("res://scripts/character/character_validator.gd")
		if typeof(d) != TYPE_DICTIONARY:
			err("postava", "data nejsou slovník", true)
			_fallback()
			return
		if d.size() > MAX_COLLECTION:
			err("postava", "příliš mnoho položek", true)
			_fallback()
			return
		# Verze
		var ver = d.get("v", null)
		if not CV._is_num(ver) or float(ver) != floor(float(ver)) or int(ver) != Schema.VERSION:
			if strict or not CV._is_num(ver) or int(ver) > Schema.VERSION:
				err("v", "nepodporovaná verze dat postavy (%s)" % str(ver), true)
				if CV._is_num(ver) and int(ver) > Schema.VERSION:
					_fallback()   # novější formát neumíme přečíst – nehádáme
					return
		out["v"] = Schema.VERSION
		# UID
		var uid = d.get("uid", "")
		if public_only:
			if d.has("uid"):
				_unknown("uid", "interní ID nepatří do veřejného snapshotu")
			out.erase("uid")
		elif typeof(uid) == TYPE_STRING and (String(uid).length() == 16 or String(uid).length() == 32) \
				and String(uid).is_valid_hex_number(false):   # 32 = 128 bit (v2), 16 = starší postavy
			out["uid"] = String(uid).to_lower()
		else:
			if strict:
				err("uid", "neplatné interní ID")
			out["uid"] = load("res://scripts/character/character_data.gd").new_uid()
		# Neznámé skupiny
		for k in d:
			if typeof(k) != TYPE_STRING:
				_unknown(str(k), "neznámá položka")
				continue
			if k == "v" or k == "uid" or k == "clothing" or Schema.GROUPS.has(k):
				continue
			_unknown(String(k), "neznámá skupina")
		for g in Schema.GROUPS:
			_group(g, d.get(g, null))
		_clothing(d.get("clothing", null))
		_cross_checks()

	## Bezpečné výchozí hodnoty pro fatální vstup (validní pro daný režim, aby repaired() nikdy nevrátil {}).
	func _fallback() -> void:
		var dd: Dictionary = Schema.defaults()
		out = {"v": Schema.VERSION}
		if not public_only:
			out["uid"] = load("res://scripts/character/character_data.gd").new_uid()
		for g in dd:
			if g == "clothing":
				out[g] = dd[g]
				continue
			var gd := {}
			for k in dd[g]:
				if _group_allowed_field(g, k):
					gd[k] = dd[g][k]
			if not gd.is_empty():
				out[g] = gd
		out["identity"]["first_name"] = FALLBACK_NAME
		out["personality"]["traits"] = ["optimista"]

	func _unknown(path: String, msg: String) -> void:
		if strict:
			err(path, msg)
		else:
			warn(path, msg + " (zahozeno)")

	func _group_allowed_field(g: String, k: String) -> bool:
		return not public_only or Schema.is_public(g, k) or (g == "skin" and (k == "scars" or k == "tattoos"))

	func _group(g: String, src) -> void:
		var fs: Dictionary = Schema.fields(g)
		var res := {}
		var has_public := false
		for k in fs:
			if _group_allowed_field(g, k):
				has_public = true
		if public_only and not has_public:
			if src != null:
				_unknown(g, "soukromá skupina ve veřejném snapshotu")
			return
		if src == null:
			src = {}
		if typeof(src) != TYPE_DICTIONARY:
			err(g, "není slovník")
			src = {}
		if (src as Dictionary).size() > MAX_COLLECTION:
			err(g, "příliš mnoho položek")
			src = {}
		for k in src:
			var ks := String(k) if typeof(k) == TYPE_STRING else ""
			if ks == "" or (not fs.has(ks) and not (g == "skin" and (ks == "scars" or ks == "tattoos"))):
				_unknown("%s.%s" % [g, str(k)], "neznámé pole")
			elif not _group_allowed_field(g, ks):
				_unknown("%s.%s" % [g, ks], "soukromé pole ve veřejném snapshotu")
		for k in fs:
			if not _group_allowed_field(g, k):
				continue
			var path := "%s.%s" % [g, k]
			if not src.has(k):
				# Chybějící pole = výchozí (kromě povinného křestního jména).
				res[k] = Schema.default_value(fs[k])
				if fs[k][0] == "name" and int(fs[k][1]) > 0:
					err(path, "chybí")
					if not strict:
						res[k] = FALLBACK_NAME
				continue
			res[k] = _field(path, fs[k], src[k])
		if g == "skin":
			res["scars"] = _scars(src.get("scars", []))
			res["tattoos"] = _tattoos(src.get("tattoos", []))
		out[g] = res

	func _field(path: String, spec: Array, val) -> Variant:
		var def = Schema.default_value(spec)
		match String(spec[0]):
			"f", "i":
				var lo := float(spec[1])
				var hi := float(spec[2])
				if not CV._is_num(val):
					err(path, "není číslo")
					return def
				var f := float(val)
				if spec[0] == "i" and f != floor(f):
					if strict:
						err(path, "není celé číslo")
					f = roundf(f)
				if f < lo or f > hi:
					if strict:
						err(path, "mimo rozsah %s–%s" % [str(spec[1]), str(spec[2])])
					f = clampf(f, lo, hi)
				return int(f) if spec[0] == "i" else CV.quant(f)
			"b":
				if typeof(val) != TYPE_BOOL:
					err(path, "není ano/ne")
					return def
				return val
			"e":
				if typeof(val) != TYPE_STRING or not (spec[1] as Dictionary).has(val):
					err(path, "nepovolená hodnota")
					return def
				return String(val)
			"set":
				return _subset(path, val, spec[1], int(spec[2]))
			"color":
				if not CV.is_color(val):
					err(path, "není barva #rrggbb")
					return def
				return String(val).to_lower()
			"name":
				if typeof(val) != TYPE_STRING:
					err(path, "není text")
					return def
				var p: String = CV.name_problem(val, int(spec[1]), int(spec[2]))
				if p == "":
					return String(val)
				if strict:
					err(path, p)
					return String(val)
				var c: String = CV.clean_name(val, int(spec[2]))
				if CV.name_problem(c, int(spec[1]), int(spec[2])) != "":
					c = FALLBACK_NAME if int(spec[1]) > 0 else ""
				warn(path, p + " (opraveno)")
				return c
			"text":
				if typeof(val) != TYPE_STRING:
					err(path, "není text")
					return def
				var ml := spec.size() > 2 and bool(spec[2])
				var tp: String = CV.text_problem(val, int(spec[1]), ml)
				if tp == "":
					return String(val).strip_edges()
				if strict:
					err(path, tp)
					return ""
				warn(path, tp + " (opraveno)")
				return CV.clean_text(val, int(spec[1]), ml)
			"traits":
				return _traits(path, val)
			"predisp":
				return _predisp(path, val)
			"axes":
				return _axes(path, val, spec[1], float(spec[2]), float(spec[3]))
		err(path, "neznámý typ pole")
		return def

	func _subset(path: String, val, catalog: Dictionary, max_n: int) -> Array:
		var res: Array = []
		if typeof(val) != TYPE_ARRAY:
			err(path, "není seznam")
			return res
		if (val as Array).size() > MAX_COLLECTION:
			err(path, "příliš dlouhý seznam")
			return res
		for x in val:
			if typeof(x) != TYPE_STRING or not catalog.has(x):
				if strict:
					err(path, "nepovolená položka „%s“" % str(x).substr(0, 24))
				continue
			if res.has(x):
				if strict:
					err(path, "opakovaná položka „%s“" % x)
				continue
			res.append(String(x))
		if res.size() > max_n:
			if strict:
				err(path, "nejvýš %d položek" % max_n)
			res = res.slice(0, max_n)
		return res

	func _traits(path: String, val) -> Array:
		var res: Array = []
		if typeof(val) != TYPE_ARRAY or (val as Array).size() > MAX_COLLECTION:
			err(path, "není seznam")
			val = []
		for x in val:
			if typeof(x) != TYPE_STRING or not Traits.DEFS.has(x) or not Schema.TRAIT_COST.has(x):
				if strict:
					err(path, "neznámý rys „%s“" % str(x).substr(0, 24))
				continue
			if res.has(x):
				if strict:
					err(path, "rys „%s“ dvakrát" % x)
				continue
			if Traits.conflicts_with(x, res):
				if strict:
					err(path, "rys „%s“ se vylučuje s jiným zvoleným" % Traits.label(x))
				continue
			if res.size() >= Schema.MAX_TRAITS:
				if strict:
					err(path, "nejvýš %d rysů" % Schema.MAX_TRAITS)
				break
			if Schema.trait_cost(res + [x]) > Schema.TRAIT_BUDGET:
				if strict:
					err(path, "rysy přesahují rozpočet %d bodů" % Schema.TRAIT_BUDGET)
				continue
			res.append(String(x))
		if res.size() < Schema.MIN_TRAITS:
			if strict:
				err(path, "aspoň %d rys" % Schema.MIN_TRAITS)
			res = ["optimista"] if res.is_empty() else res
		return res

	func _predisp(path: String, val) -> Dictionary:
		var res := {}
		if typeof(val) != TYPE_DICTIONARY or (val as Dictionary).size() > MAX_COLLECTION:
			err(path, "není slovník")
			return res
		for k in val:
			if typeof(k) != TYPE_STRING or not Schema.PREDISPOSITIONS.has(k):
				if strict:
					err(path, "neznámá predispozice „%s“" % str(k).substr(0, 24))
				continue
			var x = val[k]
			if not CV._is_num(x):
				err("%s.%s" % [path, k], "není číslo")
				continue
			var f := float(x)
			if f < 0.0 or f > 1.0:
				if strict:
					err("%s.%s" % [path, k], "mimo rozsah 0–1")
				f = clampf(f, 0.0, 1.0)
			if f > 0.0:
				res[String(k)] = CV.quant(f)
		return res

	## Slovník os {osa: číslo} (HEXACO): jen osy z katalogu, čísla v rozsahu (kvantovaná); chybějící osa = odvozená.
	func _axes(path: String, val, catalog: Dictionary, lo: float, hi: float) -> Dictionary:
		var res := {}
		if typeof(val) != TYPE_DICTIONARY or (val as Dictionary).size() > MAX_COLLECTION:
			err(path, "není slovník")
			return res
		for k in val:
			if typeof(k) != TYPE_STRING or not catalog.has(k):
				_unknown("%s.%s" % [path, str(k).substr(0, 24)], "neznámá osa")
				continue
			var x = val[k]
			if not CV._is_num(x):
				err("%s.%s" % [path, k], "není číslo")
				continue
			var f := float(x)
			if f < lo or f > hi:
				if strict:
					err("%s.%s" % [path, k], "mimo rozsah %s–%s" % [str(lo), str(hi)])
				f = clampf(f, lo, hi)
			res[String(k)] = CV.quant(f)
		return res

	## Přesně povinné klíče + volitelně "hidden" (bool; ve veřejném snapshotu nepřípustné – skryté položky
	## se do něj vůbec nedostanou).
	func _item_keys_ok(item: Dictionary, req: Array) -> bool:
		for k in req:
			if not item.has(k):
				return false
		for k in item:
			if req.has(k):
				continue
			if k == "hidden" and typeof(item[k]) == TYPE_BOOL and not public_only:
				continue
			return false
		return true

	func _scars(val) -> Array:
		var res: Array = []
		if typeof(val) != TYPE_ARRAY or (val as Array).size() > MAX_COLLECTION:
			err("skin.scars", "není seznam")
			return res
		for i in (val as Array).size():
			var s = val[i]
			var p := "skin.scars[%d]" % i
			if typeof(s) != TYPE_DICTIONARY or not _item_keys_ok(s, ["zone", "size"]) or not Schema.BODY_ZONES.has(s.get("zone")) \
					or not CV._is_num(s.get("size")):
				if strict:
					err(p, "neplatná jizva")
				continue
			var sz := float(s["size"])
			if sz < 0.0 or sz > 1.0:
				if strict:
					err(p, "velikost mimo 0–1")
				sz = clampf(sz, 0.0, 1.0)
			var item := {"zone": String(s["zone"]), "size": CV.quant(sz)}
			if bool(s.get("hidden", false)):
				item["hidden"] = true
			res.append(item)
		if res.size() > Schema.MAX_SCARS:
			if strict:
				err("skin.scars", "nejvýš %d jizev" % Schema.MAX_SCARS)
			res = res.slice(0, Schema.MAX_SCARS)
		return res

	func _tattoos(val) -> Array:
		var res: Array = []
		if typeof(val) != TYPE_ARRAY or (val as Array).size() > MAX_COLLECTION:
			err("skin.tattoos", "není seznam")
			return res
		for i in (val as Array).size():
			var t = val[i]
			var p := "skin.tattoos[%d]" % i
			if typeof(t) != TYPE_DICTIONARY or not _item_keys_ok(t, ["zone", "design", "color"]) or not Schema.BODY_ZONES.has(t.get("zone")) \
					or not Schema.TATTOO_DESIGNS.has(t.get("design")) or not CV.is_color(t.get("color")):
				if strict:
					err(p, "neplatné tetování")
				continue
			var item := {"zone": String(t["zone"]), "design": String(t["design"]), "color": String(t["color"]).to_lower()}
			if bool(t.get("hidden", false)):
				item["hidden"] = true
			res.append(item)
		if res.size() > Schema.MAX_TATTOOS:
			if strict:
				err("skin.tattoos", "nejvýš %d tetování" % Schema.MAX_TATTOOS)
			res = res.slice(0, Schema.MAX_TATTOOS)
		return res

	func _clothing(src) -> void:
		var defs: Dictionary = Schema.default_outfits()
		var res := {}
		if src == null:
			src = {}
		if typeof(src) != TYPE_DICTIONARY or (src as Dictionary).size() > MAX_COLLECTION:
			err("clothing", "není slovník")
			src = {}
		for k in src:
			if typeof(k) != TYPE_STRING or (not Schema.OUTFIT_CATEGORIES.has(k) and k != "active"):
				_unknown("clothing.%s" % str(k), "neznámá kategorie oblečení")
		for cat in Schema.OUTFIT_CATEGORIES:
			var o = src.get(cat, null)
			var d: Dictionary = defs[cat].duplicate()
			if o == null:
				res[cat] = d
				continue
			var p := "clothing.%s" % cat
			if typeof(o) != TYPE_DICTIONARY or o.size() > 8:
				err(p, "neplatný outfit")
				res[cat] = d
				continue
			for k in o:
				if typeof(k) != TYPE_STRING or not d.has(k):
					_unknown("%s.%s" % [p, str(k)], "neznámé pole")
			for pair in [["top", Schema.TOPS], ["bottom", Schema.BOTTOMS], ["shoes", Schema.SHOES]]:
				var key: String = pair[0]
				if o.has(key):
					if typeof(o[key]) == TYPE_STRING and (pair[1] as Dictionary).has(o[key]):
						d[key] = String(o[key])
					else:
						err("%s.%s" % [p, key], "nepovolený kus oblečení")
			for key in ["top_color", "bottom_color"]:
				if o.has(key):
					if CV.is_color(o[key]):
						d[key] = String(o[key]).to_lower()
					else:
						err("%s.%s" % [p, key], "není barva #rrggbb")
			if d["bottom"] == "zadne" and d["top"] != "saty":
				if strict:
					err(p + ".bottom", "bez spodního dílu jen se šaty")
				d["bottom"] = defs[cat]["bottom"] if defs[cat]["bottom"] != "zadne" else "kalhoty"
			res[cat] = d
		if src.has("active"):
			if typeof(src["active"]) == TYPE_STRING and Schema.OUTFIT_CATEGORIES.has(src["active"]):
				res["active"] = String(src["active"])
			else:
				err("clothing.active", "neplatná kategorie")
		out["clothing"] = res

	func _cross_checks() -> void:
		var idn: Dictionary = out.get("identity", {})
		if not public_only and idn.has("gender_identity") and String(idn.get("gender_custom", "")) != "" \
				and idn["gender_identity"] != "jine":
			if strict:
				err("identity.gender_custom", "vlastní popis jen u volby „Jiné“")
			idn["gender_custom"] = ""
		# Nastavení obsahu: vypnutá témata duševního zdraví → citlivé údaje se nepřijímají (ne chyba).
		if not public_only and out.has("mind") and mh == "off":
			# Vypnutá témata: celé soukromé „mind“ se nepřijímá – každé pole se vrátí na výchozí hodnotu
			# (i nové osy přidané později, bez výjimek). Varování jen, když něco opravdu zahazujeme.
			var m: Dictionary = out["mind"]
			var fs: Dictionary = Schema.fields("mind")
			var dropped := false
			for k in fs:
				var def = Schema.default_value(fs[k])
				if m.has(k) and m[k] != def:
					dropped = true
				m[k] = def.duplicate(true) if typeof(def) == TYPE_DICTIONARY or typeof(def) == TYPE_ARRAY else def
			if dropped:
				warn("mind", "témata duševního zdraví jsou vypnutá – predispozice a traumata se nepoužijí")
