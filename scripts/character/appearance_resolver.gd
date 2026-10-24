extends RefCounted
## AppearanceResolver – čistá deterministická funkce: veřejný vzhledový snapshot → parametry
## vykreslení (barvy, měřítka, varianty sítí, vrstvy kůže). Žádná náhoda, žádný hash jména: stejný snapshot
## dá na serveru i všech klientech bit po bitu stejný výsledek (výstup je kvantovaný).
##
## Kůže (od C4) = fyzikálně inspirovaný model SkinModel (melanin / hemoglobin / karoten, Beer–Lambert) –
## jedna spojitá funkce bez kotev a předvoleb; detaily kůže (pihy, znaménka, akné, vitiligo, stárnutí,
## jizvy, tetování, make-up, obočí, strniště) = SkinLayers. Vlasy a oči: spojité modely pigmentu.
## Tvar těla (od C2) = váhy blend shapes jedné neutrální sítě + měřítka kostí (BodyMorphs), obličej (od C3)
## = váhy blend shapes procedurální hlavy (FaceMorphs) – vše jen z EXPLICITNÍCH atributů skupin `body`,
## `face`, `skin`, `hair`, `makeup`, nikdy z identity, rodu ani jména.

const Schema := preload("res://scripts/character/character_schema.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const FaceMorphs := preload("res://scripts/character/face_morphs.gd")
const SkinModel := preload("res://scripts/character/skin_model.gd")
const SkinLayers := preload("res://scripts/character/skin_layers.gd")

const IRIS_ANCHORS := [
	[0.0, Color(0.42, 0.58, 0.74)], [0.2, Color(0.45, 0.56, 0.6)], [0.4, Color(0.42, 0.53, 0.33)],
	[0.6, Color(0.5, 0.4, 0.2)], [0.8, Color(0.33, 0.2, 0.1)], [1.0, Color(0.13, 0.08, 0.05)],
]
## Výška referenčního modelu character.glb (m).
const MODEL_HEIGHT := BodyMorphs.MODEL_HEIGHT


static func _q(x: float) -> float:
	return roundf(x * 1000.0) / 1000.0


static func _qc(c: Color) -> Color:
	return Color(_q(clampf(c.r, 0.0, 1.0)), _q(clampf(c.g, 0.0, 1.0)), _q(clampf(c.b, 0.0, 1.0)), 1.0)


static func _anchor(anchors: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	for i in range(1, anchors.size()):
		if t <= float(anchors[i][0]):
			var a: Array = anchors[i - 1]
			var b: Array = anchors[i]
			var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
			# Interpolace v lineárním prostoru (fyzikálně věrnější míchání pigmentů).
			return (a[1] as Color).srgb_to_linear().lerp((b[1] as Color).srgb_to_linear(), u).linear_to_srgb()
	return anchors[-1][1]


static func _g(snap: Dictionary, group: String, key: String, fallback):
	var g = snap.get(group, {})
	if typeof(g) != TYPE_DICTIONARY:
		return fallback
	var v = g.get(key, fallback)
	var num := typeof(fallback) == TYPE_FLOAT or typeof(fallback) == TYPE_INT
	if num and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
		if is_nan(float(v)) or is_inf(float(v)):
			return fallback
		return float(v) if typeof(fallback) == TYPE_FLOAT else int(v)
	return v if typeof(v) == typeof(fallback) else fallback


## Albedo kůže (sRGB, kvantované) ze SkinModel – stejná rovnice jako skin.gdshader bez lokálních jevů.
static func skin_color(tone: float, undertone: float, redness: float) -> Color:
	return _qc(SkinModel.albedo(tone, undertone, redness))


## Koncentrace chromoforů pro shader (kvantované na 1/10000 → stejné na všech peerech).
static func skin_chromophores(tone: float, undertone: float, redness: float) -> Vector3:
	var c := SkinModel.chromophores(tone, undertone, redness)
	return Vector3(roundf(c.x * 10000.0) / 10000.0, roundf(c.y * 10000.0) / 10000.0, roundf(c.z * 10000.0) / 10000.0)


static func hair_color(melanin: float, red: float, grey: float) -> Color:
	var m := clampf(melanin, 0.0, 1.0)
	var base := Color(0.9, 0.82, 0.62).srgb_to_linear().lerp(Color(0.04, 0.035, 0.03).srgb_to_linear(), pow(m, 0.7)).linear_to_srgb()
	var ginger := Color(0.62, 0.25, 0.1).lerp(Color(0.28, 0.1, 0.05), m)
	base = base.lerp(ginger, clampf(red, 0.0, 1.0) * (1.0 - 0.5 * m))
	base = base.lerp(Color(0.8, 0.8, 0.79), clampf(grey, 0.0, 1.0))
	return _qc(base)


## Rty: kůže s víc prokrvenou sliznicí (tmavší a červenější, u tmavé kůže hlavně tmavší), rtěnka překryje
## podle intenzity. Žádná „barva rtů podle rasy“ – jen tentýž spojitý model jako kůže.
static func lip_color(skin: Color, lipstick: float, lip_hex: String) -> Color:
	var c := skin.srgb_to_linear() * Color(0.78, 0.52, 0.52)
	var out := c.linear_to_srgb()
	var ls := clampf(lipstick, 0.0, 1.0)
	if ls > 0.0 and lip_hex.length() == 7 and lip_hex.substr(1).is_valid_hex_number(false):
		out = out.lerp(Color.html(lip_hex), ls * 0.85)
	return _qc(out)


static func iris_color(iris: float) -> Color:
	return _qc(_anchor(IRIS_ANCHORS, iris))


## Detaily obličeje (C3++, běh 21) – barvy částí hlavy z explicitních atributů:
##  - zuby: odstín skloviny 0 (bílá) … 1 (zažloutlá), nic se neodvozuje z věku ani identity (to dělá jen generátor),
##  - dáseň a jazyk: růžová sliznice; u tmavší kůže dáseň spojitě pigmentovanější (fyziologická pigmentace dásní –
##    stejná spojitá funkce melaninu jako kůže, žádná předvolba),
##  - řasy: tmavší než obočí, se šedinami; řasenka je ztmaví do černa,
##  - limbus: tmavý okraj duhovky.
static func teeth_color(shade: float) -> Color:
	return _qc(Color(0.95, 0.94, 0.90).lerp(Color(0.86, 0.78, 0.58), clampf(shade, 0.0, 1.0)))


static func gum_color(tone: float) -> Color:
	return _qc(Color(0.78, 0.42, 0.44).lerp(Color(0.42, 0.24, 0.22), 0.6 * pow(clampf(tone, 0.0, 1.0), 1.5)))


static func tongue_color(tone: float) -> Color:
	return _qc(Color(0.74, 0.38, 0.40).lerp(Color(0.52, 0.28, 0.28), 0.25 * clampf(tone, 0.0, 1.0)))


static func lash_color(brow: Color, grey: float, mascara: float) -> Color:
	var c := brow.srgb_to_linear().lerp(Color(0.012, 0.010, 0.009), 0.45).linear_to_srgb()
	c = c.lerp(Color(0.72, 0.72, 0.70), clampf(grey, 0.0, 1.0) * 0.4)
	return _qc(c.lerp(Color(0.02, 0.02, 0.025), clampf(mascara, 0.0, 1.0)))


## Hlavní výstup pro SimVisual.
static func resolve(snap: Dictionary) -> Dictionary:
	var body = snap.get("body", {})
	if typeof(body) != TYPE_DICTIONARY:
		body = {}
	var sc := BodyMorphs.scales(body)
	var body_w := BodyMorphs.weights(body)
	var face = snap.get("face", {})
	if typeof(face) != TYPE_DICTIONARY:
		face = {}
	var frame := clampf(float(_g(snap, "body", "frame", 0.5)), 0.0, 1.0)
	var fat := clampf(float(_g(snap, "body", "body_fat", 0.3)), 0.0, 1.0)
	var muscle := clampf(float(_g(snap, "body", "muscle", 0.35)), 0.0, 1.0)
	var age := clampi(int(_g(snap, "body", "age", 30)), 18, 95)
	var style := String(_g(snap, "hair", "style", "kratke"))
	var hc := hair_color(float(_g(snap, "hair", "melanin", 0.6)), float(_g(snap, "hair", "red", 0.15)),
		float(_g(snap, "hair", "grey", 0.0)))
	if bool(_g(snap, "hair", "dyed", false)):
		var dc := String(_g(snap, "hair", "dye_color", ""))
		if dc.length() == 7 and dc.substr(1).is_valid_hex_number(false):
			hc = _qc(Color.html(dc).lerp(Color(0.8, 0.8, 0.79), clampf(float(_g(snap, "hair", "grey", 0.0)), 0.0, 1.0) * 0.3))
	var outfit: Dictionary = {}
	var cl = snap.get("clothing", {})
	var outfit_cat := "bezne"
	if typeof(cl) == TYPE_DICTIONARY:
		var requested := String(cl.get("active", "bezne"))
		if Schema.OUTFIT_CATEGORIES.has(requested) and typeof(cl.get(requested)) == TYPE_DICTIONARY:
			outfit_cat = requested
		outfit = cl.get(outfit_cat, {})
	var top := _color_or(outfit.get("top_color", ""), Color(0.36, 0.42, 0.48))
	var bottom := _color_or(outfit.get("bottom_color", ""), Color(0.18, 0.23, 0.29))
	# Šířka jen pro náhradu z primitiv (model z Blenderu má tvar z blend shapes).
	var w := 0.9 + 0.16 * frame + 0.14 * fat + 0.06 * muscle
	var tone := float(_g(snap, "skin", "tone", 0.45))
	var under := float(_g(snap, "skin", "undertone", 0.0))
	var red := float(_g(snap, "skin", "redness", 0.3))
	var skin := skin_color(tone, under, red)
	var hair_look := resolve_hair_look(snap)
	return {
		"skin": skin,
		"chrom": skin_chromophores(tone, under, red),
		"skin_layers": SkinLayers.resolve(snap),
		"hair": hc,
		"iris": iris_color(float(_g(snap, "eyes", "iris", 0.6))),
		"top": top,
		"bottom": bottom,
		"outfit_category": outfit_cat,
		"outfit_top": String(outfit.get("top", "tricko")),
		"outfit_bottom": String(outfit.get("bottom", "dziny")),
		"outfit_shoes": String(outfit.get("shoes", "tenisky")),
		"height_scale": sc["height_scale"],
		"head_scale": sc["head_scale"],
		"leg_scale": sc["leg_scale"],
		"lift": sc["lift"],
		"width_scale": _q(w),
		"body": body_w,
		"face": FaceMorphs.weights(face, body_w.merged(BodyMorphs.head_links(body)), _grp(snap, "makeup")),
		"teeth": teeth_color(float(_g(snap, "face", "teeth_shade", 0.25))),
		"gum": gum_color(tone),
		"tongue": tongue_color(tone),
		"lash": lash_color(hair_look["brow"], float(hair_look["brow_grey"]), float(_g(snap, "makeup", "mascara", 0.0))),
		"limbus": _qc(iris_color(float(_g(snap, "eyes", "iris", 0.6))).darkened(0.55)),
		"lips": lip_color(skin, float(_g(snap, "makeup", "lipstick", 0.0)),
			String(_g(snap, "makeup", "lip_color", "#9e3a42"))),
		"hair_variant": "" if style == "holy" else ("hair_long" if Schema.LONG_HAIR.has(style) else "hair_short"),
		"hair_look": hair_look,
		"age": age,
	}


## Vlasy, obočí a vousy pro karty (C4b, HairRig + hair.gdshader). Barvy jsou sRGB a BEZ šedin – šediny kreslí
## shader po jednotlivých vlasech (sůl a pepř), ne plošným zesvětlením. Barvení se týká jen vlasů na hlavě
## (odrůstající šediny barva z velké části překryje); obočí a vousy mají přirozený pigment. Styly se ověřují
## proti schématu (neznámý → výchozí), takže podvržený snapshot nevybere neexistující síť.
static func resolve_hair_look(snap: Dictionary) -> Dictionary:
	var style := String(_g(snap, "hair", "style", "kratke"))
	if not Schema.HAIR_STYLES.has(style):
		style = "kratke"
	var brows := String(_g(snap, "hair", "brows", "prirozene"))
	if not Schema.BROW_STYLES.has(brows):
		brows = "prirozene"
	var facial := String(_g(snap, "hair", "facial", "zadne"))
	if not Schema.FACIAL_HAIR.has(facial):
		facial = "zadne"
	var grey := _f01(_g(snap, "hair", "grey", 0.0), 0.0)
	var natural := hair_color(float(_g(snap, "hair", "melanin", 0.6)), float(_g(snap, "hair", "red", 0.15)), 0.0)
	var scalp := natural
	var scalp_grey := grey
	if bool(_g(snap, "hair", "dyed", false)):
		var dc := String(_g(snap, "hair", "dye_color", ""))
		if dc.length() == 7 and dc.begins_with("#") and dc.substr(1).is_valid_hex_number(false):
			scalp = _qc(Color.html(dc))
			scalp_grey = grey * 0.3
	return {
		"style": style, "brow_style": brows, "beard_style": facial,
		"natural": scalp, "grey": _q(scalp_grey),
		"hairline": _q(_f01(_g(snap, "hair", "hairline", 0.0), 0.0)),
		"brow": natural, "brow_grey": _q(grey * 0.6),
		"brow_density": _q(_f01(_g(snap, "hair", "brow_density", 0.6), 0.6)),
		"facial": natural, "facial_grey": _q(grey * 0.85),
		"facial_density": _q(_f01(_g(snap, "hair", "facial_density", 0.6), 0.6)),
	}


## Číslo v ⟨0; 1⟩ z libovolné hodnoty (NaN, ±∞, text → výchozí). Snapshot je validovaný, tohle je pojistka.
static func _f01(v, fallback: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return fallback
	var x := float(v)
	if is_nan(x) or is_inf(x):
		return fallback
	return clampf(x, 0.0, 1.0)


static func _grp(snap: Dictionary, group: String) -> Dictionary:
	var g = snap.get(group, {})
	return g if typeof(g) == TYPE_DICTIONARY else {}


static func _color_or(v, fallback: Color) -> Color:
	if typeof(v) == TYPE_STRING and String(v).length() == 7 and String(v).substr(1).is_valid_hex_number(false):
		return _qc(Color.html(v))
	return fallback
