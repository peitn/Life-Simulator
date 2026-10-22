extends RefCounted
## SkinLayers (C4) – čistá deterministická funkce: veřejný snapshot → parametry vrstev kůže pro skin.gdshader
## (pihy, znaménka, akné, vitiligo, stárnutí, jizvy, tetování, make-up, obočí, strniště a vousy).
##
## Souřadnice: klidová (rest) poloha vrcholu v prostoru modelu character.glb (Y nahoru, +Z dopředu,
## +X = levá strana postavy – kosti *_l mají x > 0). AssetLibrary ji při načtení uloží do atributu CUSTOM0
## každé sítě kůže, takže masky „jedou“ s vrcholy při animaci i při obličejových/tělesných morfech
## (jizva nad obočím zůstane nad obočím, i když hráč obočí posune).
##
## Rozmístění pih, znamének, jizev a tetování v rámci zóny určuje `skin.detail_seed` – explicitní atribut
## postavy (editor: „jiné rozmístění“), nikdy jméno. Výstup je kvantovaný (bit po bitu stejný na všech peerech).
##
## Obsah: tetování a jizvy nesou jen parametry vykreslení (zóna, vzor, barva, velikost) – žádný příběh.
## Skryté položky (hidden) do veřejného snapshotu vůbec nepřijdou (validátor public_only), takže je tu
## ostatní hráči ani nemají jak vykreslit.

const Schema := preload("res://scripts/character/character_schema.gd")
const SkinModel := preload("res://scripts/character/skin_model.gd")
const SHADER_PATH := "res://shaders/skin.gdshader"

const MAX_SCARS := 6
const MAX_TATTOOS := 8

## Orientační body obličeje v klidové poloze = HeadBuilder.derive({}) (ověřuje tests/test_skin.gd).
const EYE := Vector3(0.0318, 1.6685, 0.0708)         # střed levého oka (pravé = zrcadlo)
## Běh 18 (C3+ B): štěrbina je nesouměrná (k nosu 16,5 mm, do spánku 13,7 mm od zornice) – shader kreslí make-up
## souměrně, takže půlšířka = průměr obou stran v čelním průmětu (tests/test_skin.gd hlídá shodu s HeadBuilderem).
const EYE_SHAPE := Vector4(0.0151, 0.0058, 0.0046, 0.0698)   # půlšířka, výška horního/dolního víčka, sklon (rad)
const MOUTH := Vector3(0.0, 1.6035, 0.0255)          # (x, y, půlšířka úst)
const HEAD_C := Vector3(0.0, 1.668, 0.0)

## Id vzorů tetování v shaderu.
const DESIGN_ID := {"text": 0, "kvetina": 1, "geometricky": 2, "zvire": 3, "abstraktni": 4, "symbol": 5, "ornament": 6, "portret": 7}
## Obočí: [tloušťka m, oblouk m, vnitřní okraj |x| m, srostlé 0/1]
const BROW_SHAPES := {
	"prirozene": [0.0042, 0.0035, 0.0125, 0.0], "huste": [0.0058, 0.0030, 0.0115, 0.0],
	"tenke": [0.0022, 0.0045, 0.0135, 0.0], "rovne": [0.0042, 0.0008, 0.0125, 0.0],
	"oblouk": [0.0038, 0.0065, 0.0125, 0.0], "srostle": [0.0048, 0.0030, 0.0110, 1.0],
}
## Vousy: [knír, brada, tváře a čelist, licousy] a délka (0 = strniště … 1 = plnovous; geometrie vousů v C4b).
const FACIAL := {
	"zadne": [Vector4(0, 0, 0, 0), 0.0], "strniste": [Vector4(1, 1, 1, 1), 0.0],
	"knir": [Vector4(1, 0, 0, 0), 0.7], "bradka": [Vector4(0, 1, 0, 0), 0.6],
	"kozi_bradka": [Vector4(1, 1, 0, 0), 0.6], "plnovous": [Vector4(1, 1, 1, 1), 1.0],
	"licousy": [Vector4(0, 0, 1, 1), 0.8],
}

## Zóny těla. Končetina = řetěz bodů (kosti) s poloměrem; plocha = seznam míst [střed, normála, „nahoru“].
const LIMBS := {
	"leva_paze": {"chain": [Vector3(0.19, 1.42, 0.0), Vector3(0.25, 1.16, -0.01), Vector3(0.29, 0.93, 0.0)], "r": [0.045, 0.033], "t": [0.2, 0.95]},
	"prava_paze": {"chain": [Vector3(-0.19, 1.42, 0.0), Vector3(-0.25, 1.16, -0.01), Vector3(-0.29, 0.93, 0.0)], "r": [0.045, 0.033], "t": [0.2, 0.95]},
	"leva_ruka": {"chain": [Vector3(0.29, 0.93, 0.0), Vector3(0.33, 0.80, 0.0)], "r": [0.022], "t": [0.25, 0.6]},
	"prava_ruka": {"chain": [Vector3(-0.29, 0.93, 0.0), Vector3(-0.33, 0.80, 0.0)], "r": [0.022], "t": [0.25, 0.6]},
	"leva_noha": {"chain": [Vector3(0.09, 0.93, 0.0), Vector3(0.10, 0.50, 0.01), Vector3(0.10, 0.12, -0.02)], "r": [0.065, 0.045], "t": [0.15, 0.9]},
	"prava_noha": {"chain": [Vector3(-0.09, 0.93, 0.0), Vector3(-0.10, 0.50, 0.01), Vector3(-0.10, 0.12, -0.02)], "r": [0.065, 0.045], "t": [0.15, 0.9]},
}
## Body na povrchu VÝCHOZÍ (klidové) sítě – zkalibrováno nejbližším bodem povrchu character.glb (běh 10,
## tests/test_skin.gd ověřuje vzdálenost od povrchu); normála = průměr normály plochy a původního směru.
const SPOTS := {
	"oblicej": [
		[Vector3(0.0213, 1.7337, 0.0802), Vector3(0.19, 0.34, 0.92), Vector3.UP],      # čelo
		[Vector3(0.0349, 1.7001, 0.0857), Vector3(0.32, 0.08, 0.94), Vector3.UP],      # obočí
		[Vector3(-0.0455, 1.6341, 0.0667), Vector3(-0.64, -0.1, 0.76), Vector3.UP],    # tvář
		[Vector3(0.0091, 1.5760, 0.0874), Vector3(0.21, -0.03, 0.98), Vector3.UP],     # brada (běh 18: projekce brady +8 mm)
		[Vector3(0.0658, 1.6900, 0.0399), Vector3(0.93, 0.02, 0.36), Vector3.UP],      # spánek
		[Vector3(-0.0468, 1.5951, 0.0308), Vector3(-0.88, -0.37, 0.29), Vector3.UP],   # čelist
	],
	"krk": [  # běh 13: báze krku zvednutá (vzadu C7 ~1,545 m) – body přeměřené paprskem na skutečném krku
		[Vector3(0.0, 1.5350, 0.0487), Vector3(0.0, 0.09, 1.0), Vector3.UP],        # hrdlo
		[Vector3(0.0560, 1.5400, -0.0060), Vector3(1.0, 0.01, -0.04), Vector3.UP],   # bok krku
		[Vector3(-0.0560, 1.5400, -0.0060), Vector3(-1.0, 0.01, -0.04), Vector3.UP],
		[Vector3(0.0, 1.5650, -0.0502), Vector3(0.0, -0.004, -1.0), Vector3.UP],     # zátylek nad C7
	],
	"hrudnik": [[Vector3(0.0642, 1.3290, 0.0770), Vector3(0.16, 0.06, 0.99), Vector3.UP], [Vector3(-0.0642, 1.3290, 0.0769), Vector3(-0.16, 0.06, 0.99), Vector3.UP],
		[Vector3(0.0, 1.3585, 0.0863), Vector3(-0.03, 0.1, 0.99), Vector3.UP]],
	"bricho": [[Vector3(0.0, 1.0809, 0.0688), Vector3(0.06, -0.01, 1.0), Vector3.UP], [Vector3(0.0547, 1.0160, 0.0614), Vector3(0.37, 0.05, 0.93), Vector3.UP]],
	"zada": [[Vector3(0.0, 1.3308, -0.0813), Vector3(-0.04, -0.01, -1.0), Vector3.UP], [Vector3(0.0647, 1.3053, -0.0671), Vector3(0.31, -0.08, -0.95), Vector3.UP],
		[Vector3(0.0, 1.0491, -0.0693), Vector3(-0.06, 0.01, -1.0), Vector3.UP]],
}


static func _q(x: float) -> float:
	return roundf(x * 10000.0) / 10000.0


static func _qv(v: Vector3) -> Vector3:
	return Vector3(_q(v.x), _q(v.y), _q(v.z))


static func _num(g: Dictionary, k: String, d: float, lo := 0.0, hi := 1.0) -> float:
	var v = g.get(k, d)
	if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or is_nan(float(v)) or is_inf(float(v)):
		return d
	return clampf(float(v), lo, hi)


static func _grp(snap: Dictionary, g: String) -> Dictionary:
	var v = snap.get(g, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _hex_lin(s, fallback: Color) -> Color:
	if typeof(s) == TYPE_STRING and String(s).length() == 7 and String(s).begins_with("#") and String(s).substr(1).is_valid_hex_number(false):
		return Color.html(s).srgb_to_linear()
	return fallback


## Deterministický generátor (PCG32 v RandomNumberGenerator je na všech platformách stejný).
static func _rng(seed_v: int, kind: int, idx: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = (seed_v * 1000003 + kind * 7919 + idx * 104729 + 17) & 0x7FFFFFFFFFFFFFFF
	r.state = r.seed ^ 0x5DEECE66D
	return r


## Umístění v zóně: {"c", "n", "u", "r"} (r = poloměr končetiny, 0 = plocha).
static func place(zone: String, rng: RandomNumberGenerator) -> Dictionary:
	if LIMBS.has(zone):
		var lb: Dictionary = LIMBS[zone]
		var chain: Array = lb["chain"]
		var tr: Array = lb["t"]
		var t := rng.randf_range(float(tr[0]), float(tr[1]))
		var segs := chain.size() - 1
		var fs := t * float(segs)
		var si := mini(int(fs), segs - 1)
		var ft := fs - float(si)
		var a: Vector3 = chain[si]
		var b: Vector3 = chain[si + 1]
		var axis := (a - b).normalized()          # „nahoru“ podél končetiny (k trupu)
		var p := a.lerp(b, ft)
		var radius := float((lb["r"] as Array)[mini(si, (lb["r"] as Array).size() - 1)])
		# Směr ven z končetiny: preferovaně dopředu a do strany (viditelná strana předloktí/stehna).
		var side := signf(chain[0].x) if absf(chain[0].x) > 0.001 else 1.0
		var front := (Vector3(0, 0, 1) - axis * axis.z).normalized()
		var outward := axis.cross(front).normalized() * side
		if outward.dot(Vector3(side, 0, 0)) < 0.0:
			outward = -outward
		var ang := rng.randf_range(-1.1, 1.1)
		var pref := (front * 0.75 + outward * 0.66).normalized()
		var n := pref.rotated(axis, ang).normalized()
		return {"c": p + n * radius, "n": n, "u": axis, "r": radius}
	var spots: Array = SPOTS.get(zone, SPOTS["krk"])
	var s: Array = spots[rng.randi_range(0, spots.size() - 1)]
	var n: Vector3 = (s[1] as Vector3).normalized()
	var up: Vector3 = s[2]
	var u := (up - n * up.dot(n)).normalized()
	var jitter := 0.006 if zone == "oblicej" else 0.02
	var off := u * rng.randf_range(-jitter, jitter) + n.cross(u) * rng.randf_range(-jitter, jitter)
	return {"c": (s[0] as Vector3) + off, "n": n, "u": u, "r": 0.0}


static func resolve(snap: Dictionary) -> Dictionary:
	var skin := _grp(snap, "skin")
	var hair := _grp(snap, "hair")
	var body := _grp(snap, "body")
	var mk := _grp(snap, "makeup")
	var seed_v := int(_num(skin, "detail_seed", 0.0, 0.0, 65535.0))
	var age := _num(body, "age", 30.0, 18.0, 95.0)
	var weather := _num(skin, "weathering", 0.0)
	var wrinkles := clampf(smoothstep(27.0, 78.0, age) * (0.75 + 0.5 * weather) + 0.2 * weather, 0.0, 1.0)
	var spots := clampf(smoothstep(42.0, 82.0, age) * (0.45 + 0.55 * weather) + 0.15 * weather, 0.0, 1.0)
	var out := {
		"seed": _q(float(seed_v) / 65535.0 * 97.0),
		"freckles": _q(_num(skin, "freckles", 0.0)),
		"moles": _q(_num(skin, "moles", 0.15)),
		"acne": _q(_num(skin, "acne", 0.0)),
		"vitiligo": _q(_num(skin, "vitiligo", 0.0)),
		"wrinkles": _q(wrinkles),
		"age_spots": _q(spots),
		"pores": _q(0.6 + 0.4 * weather),
	}
	# Make-up
	out["eyeliner"] = _q(_num(mk, "eyeliner", 0.0))
	out["eyeshadow"] = _q(_num(mk, "eyeshadow", 0.0))
	var es := _hex_lin(mk.get("eyeshadow_color", "#6b5a7a"), Color(0.15, 0.1, 0.19))
	out["eyeshadow_color"] = _qv(Vector3(es.r, es.g, es.b))
	out["blush"] = _q(_num(mk, "blush", 0.0))
	# Obočí a vousy mají přirozenou barvu (barvení se týká vlasů na hlavě).
	var Res = load("res://scripts/character/appearance_resolver.gd")
	var grey := _num(hair, "grey", 0.0)
	var nat: Color = Res.hair_color(_num(hair, "melanin", 0.6), _num(hair, "red", 0.15), grey * 0.85).srgb_to_linear()
	var brow_c: Color = Res.hair_color(_num(hair, "melanin", 0.6), _num(hair, "red", 0.15), grey * 0.6).srgb_to_linear()
	out["facial_color"] = _qv(Vector3(nat.r, nat.g, nat.b))
	out["brow_color"] = _qv(Vector3(brow_c.r, brow_c.g, brow_c.b))
	var bs := String(hair.get("brows", "prirozene")) if typeof(hair.get("brows")) == TYPE_STRING else "prirozene"
	var bsh: Array = BROW_SHAPES.get(bs, BROW_SHAPES["prirozene"])
	out["brow_shape"] = Vector4(bsh[0], bsh[1], bsh[2], bsh[3])
	out["brow_density"] = _q(_num(hair, "brow_density", 0.6))
	var fstyle := String(hair.get("facial", "zadne")) if typeof(hair.get("facial")) == TYPE_STRING else "zadne"
	var fc: Array = FACIAL.get(fstyle, FACIAL["zadne"])
	out["facial_mask"] = fc[0]
	out["facial_length"] = _q(float(fc[1]))
	out["facial_density"] = _q(_num(hair, "facial_density", 0.6) if fstyle != "zadne" else 0.0)
	# Jizvy
	var s0 := PackedVector4Array()
	var s1 := PackedVector4Array()
	var s2 := PackedVector4Array()
	var scars = skin.get("scars", [])
	if typeof(scars) == TYPE_ARRAY:
		for i in mini((scars as Array).size(), 64):
			if s0.size() >= MAX_SCARS:
				break
			var sc = scars[i]
			if typeof(sc) != TYPE_DICTIONARY or bool(sc.get("hidden", false)) or not Schema.BODY_ZONES.has(sc.get("zone")):
				continue
			var size := _num(sc, "size", 0.3)
			var rng := _rng(seed_v, 1, i)
			var pl := place(String(sc["zone"]), rng)
			var n: Vector3 = pl["n"]
			var u: Vector3 = pl["u"]
			var dir := u.rotated(n, rng.randf_range(-1.2, 1.2)).normalized()
			var face := String(sc["zone"]) == "oblicej"
			var half_len := lerpf(0.004, 0.022, size) if face else lerpf(0.008, 0.045, size)
			var half_w := lerpf(0.0007, 0.0022, size)
			var sutures := 1.0 if (size > 0.45 and rng.randf() < 0.5) else 0.0
			var c: Vector3 = pl["c"]
			s0.append(Vector4(_q(c.x), _q(c.y), _q(c.z), _q(half_len)))
			s1.append(Vector4(_q(dir.x), _q(dir.y), _q(dir.z), _q(half_w)))
			s2.append(Vector4(_q(n.x), _q(n.y), _q(n.z), sutures))
	out["scar_count"] = s0.size()
	out["scar0"] = _pad(s0, MAX_SCARS)
	out["scar1"] = _pad(s1, MAX_SCARS)
	out["scar2"] = _pad(s2, MAX_SCARS)
	# Tetování
	var t0 := PackedVector4Array()
	var t1 := PackedVector4Array()
	var t2 := PackedVector4Array()
	var t3 := PackedVector4Array()
	var depth_a := PackedFloat32Array()
	var tats = skin.get("tattoos", [])
	if typeof(tats) == TYPE_ARRAY:
		for i in mini((tats as Array).size(), 64):
			if t0.size() >= MAX_TATTOOS:
				break
			var tt = tats[i]
			if typeof(tt) != TYPE_DICTIONARY or bool(tt.get("hidden", false)) or not Schema.BODY_ZONES.has(tt.get("zone")) \
					or not DESIGN_ID.has(tt.get("design")):
				continue
			var zone := String(tt["zone"])
			var rng := _rng(seed_v, 2, i)
			var pl := place(zone, rng)
			var r := float(pl["r"])
			var hu: float
			var hv: float
			if r > 0.0:
				hu = clampf(r * rng.randf_range(0.9, 1.5), 0.016, 0.06)
				hv = minf(hu * 0.85, r * 0.85)
			elif zone == "oblicej":
				hu = rng.randf_range(0.004, 0.008)
				hv = hu
			elif zone == "krk":
				hu = rng.randf_range(0.012, 0.02)
				hv = hu
			else:
				hu = rng.randf_range(0.03, 0.06)
				hv = hu * rng.randf_range(0.8, 1.0)
			var ink := _hex_lin(tt.get("color", "#1d1f24"), Color(0.012, 0.013, 0.017))
			var c: Vector3 = pl["c"]
			var n: Vector3 = pl["n"]
			var u: Vector3 = pl["u"]
			t0.append(Vector4(_q(c.x), _q(c.y), _q(c.z), _q(hu)))
			t1.append(Vector4(_q(u.x), _q(u.y), _q(u.z), float(DESIGN_ID[tt["design"]])))
			t2.append(Vector4(_q(n.x), _q(n.y), _q(n.z), _q(rng.randf())))
			t3.append(Vector4(_q(ink.r), _q(ink.g), _q(ink.b), _q(hv)))
			# Hloubková tolerance projekce: u končetiny pod poloměrem (vzor neprosákne na druhou stranu), jinak 0,8–2 cm.
			depth_a.append(_q(r * 0.8 if r > 0.0 else (0.008 if zone == "oblicej" else 0.02)))
	out["tattoo_count"] = t0.size()
	out["tattoo0"] = _pad(t0, MAX_TATTOOS)
	out["tattoo1"] = _pad(t1, MAX_TATTOOS)
	out["tattoo2"] = _pad(t2, MAX_TATTOOS)
	out["tattoo3"] = _pad(t3, MAX_TATTOOS)
	while depth_a.size() < MAX_TATTOOS:
		depth_a.append(0.0)
	out["tattoo_depth"] = depth_a
	return out


static func _pad(a: PackedVector4Array, n: int) -> PackedVector4Array:
	var o := a.duplicate()
	while o.size() < n:
		o.append(Vector4.ZERO)
	return o


# ---------------------------------------------------------------- materiál

static var _shader: Shader = null


## Sdílený shader kůže (null, když chybí – volající nechá StandardMaterial3D).
static func shader() -> Shader:
	if _shader == null and ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH) as Shader
	return _shader


## Nový materiál kůže pro jednu postavu (konstanty modelu a orientační body hlavy už nastavené).
static func make_material() -> ShaderMaterial:
	var sh := shader()
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	var k := SkinModel.shader_constants()
	for key in k:
		m.set_shader_parameter(key, k[key])
	m.set_shader_parameter("eye", EYE)
	m.set_shader_parameter("eye_shape", EYE_SHAPE)
	m.set_shader_parameter("mouth", MOUTH)
	return m


## Nastaví parametry postavy z výstupu AppearanceResolveru (klíče "chrom" a "skin_layers").
## Vrací počet nastavených parametrů (testy, výkon).
static func apply(mat: ShaderMaterial, lp: Dictionary) -> int:
	if mat == null:
		return 0
	var n := 0
	if lp.has("chrom"):
		mat.set_shader_parameter("chrom", lp["chrom"])
		n += 1
	var layers: Dictionary = lp.get("skin_layers", {})
	for key in layers:
		mat.set_shader_parameter(key, layers[key])
		n += 1
	return n
