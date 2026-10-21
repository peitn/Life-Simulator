extends RefCounted
## HeadBuilder (C3) – procedurální hlava postavy s obličejovými morfy.
##
## Proč procedurálně (a ne sochou z Blenderu): každý obličejový morf je funkce parametrů schématu
## (character_schema.gd FACE_MORPHS), takže blend shapes jsou reprodukovatelné, laditelné v kódu
## a vždy odpovídají datům postavy. Topologie je pevná, polohy vrcholů = recept(vrchol) vyhodnocený pro
## parametry; morf = poloha(+1) − poloha(0) (a zvlášť −1, když morf není lineární).
## Kontrolu (hodnoty blend shapes, průniky kůže–oko při kombinacích extrémů, symetrie, determinismus,
## rozpočet) dělá tests/test_head.gd; šev hlava–tělo tests/test_neck_seam.gd. Vizuální kontrola: tools/raster_preview.gd
## (tools/neck_sheet.gd pro krk), Blender render v běhu 10b.
##
## Geometrie (osy Godotu: Y nahoru, +Z dopředu):
##  - lebka a obličej: mřížka „kostka → koule“ (hustší uprostřed obličeje), poloměr podél paprsku z C =
##    superelipsoid s profilem šířky (čelist, brada) ∪ krk (hladké maximum) + reliéf (nos, obočí, lícní
##    kosti, tváře, brada, filtrum…),
##  - oči: blok mřížky nahrazený soustřednými prstenci (okolí oka → víčko → okraj víčka → spojivka) a kapsou,
##    která obepíná oční kouli – víčka jsou skutečná geometrie, kůže se nikdy nedotkne oka (push_out),
##  - ústa: stejný princip (hranice rtů, plnost, linie úst, vnitřek a dutina),
##  - uši: disk (laterální a mediální strana) s lemem, protilemem, mušlí a lalůčkem,
##  - oční koule: sféra s duhovkou, zornicí a mírně vyklenutou rohovkou.
## Ochrana proti průnikům: kůže ≥ R + EYE_CLEAR od středu oka (měkké maximum), orbitální prstenec se hýbe
## s okem, krk se škáluje vodorovně (vrcholy nekloužou po povrchu). Kombinace morfů ověřuje test vzorkováním.

const FaceMorphs := preload("res://scripts/character/face_morphs.gd")

const FACE_KEYS := ["head_width", "head_height", "forehead_slope", "brow_ridge", "brow_height", "eye_size", "eye_tilt",
	"eye_distance", "eye_depth", "eyelid_hood", "nose_length", "nose_width", "nose_bridge", "nose_tip",
	"nose_tip_angle", "cheekbones", "cheeks_fullness", "jaw_width", "jaw_angle", "chin_length", "chin_width",
	"chin_cleft", "mouth_width", "lip_upper", "lip_lower", "philtrum", "ear_size", "ear_angle", "neck_width"]
const ASYM_KEYS := ["asym_eyes", "asym_mouth", "asym_jaw"]
## Klíče řízené tělem (BodyMorphs: fat_hi, muscle_hi) – jen kladný směr.
const BODY_KEYS := ["b_fat", "b_muscle"]

const NX := 24
const NY := 26
const NZ := 14
const KY := 1.35
## Osa krku (vizuální kontrola běh 10): nahoře pod hlavou je za středem hlavy (krk vpředu zkracoval úhel
## brada–krk a chyběla spodní plocha čelisti), dole u těla na ose těla – krk se mírně naklání dopředu
## a „rukáv“ krku hlavy navazuje na krk těla bez schodu vzadu.
const NECK_ZC := -0.012
const NECK_ZC_Y0 := 1.49
const NECK_ZC_Y1 := 1.57
## Krk není válec. Běh 11 (render s tělem): krk byl úzký a působil dlouze – poloosy teď ~5,4 cm do stran
## a ~5,1 cm do hloubky (dospělý krk ~11 × 10–11 cm); dole ho stejně přebírá profil okraje krku těla (SEAM_*).
const NECK_R := 0.053
const NECK_KX := 1.02
const NECK_KZ := 0.97
## Dolní víčko rukávu krku (rovina, ve které končí paprsky mířící dolů).
const NECK_CAP_Y := 1.49
## C3+ (běh 11) – šev hlava–tělo: vrcholy mřížky do výšky SEAM_BAND nad smyčkou se plynule (seam_weight podle
## polohy v ZÁKLADU a výšky smyčky v daném směru – vzadu je okraj těla výš než vpředu) posunou na radiální
## profil smyčky okraje krku těla + SEAM_EPS; pod smyčkou je přilnutí úplné. Víčko krku se zanoří do trupu
## (CAP_Y, CAP_SHRINK). Smyčku, normály, váhy kostí a výchylky morfů těla dodá CharacterAssembly.cut_body_neck().
const SEAM_BAND := 0.065
## Plné přilnutí ještě SEAM_HOLD nad smyčkou, pak plynulý přechod do vlastního tvaru krku do SEAM_BAND.
## (Běh 12: zkoušené plné přilnutí všech ploch přes výšku okraje dělalo nepravidelnou horní hranu pásu – při
## velkém tuku z toho byl na krku viditelný prstenec – a na krytí okraje nemělo vliv; to vyřešila volba úhlopříček.)
const SEAM_HOLD := 0.02
## Dosah morfů těla na krku hlavy (body_weight).
const SEAM_BODY_BAND := 0.08
## Pás, ve kterém se normály krku hlavy plynule stáčejí k normálám okraje těla.
const SEAM_NRM_BAND := 0.012
const SEAM_Y_TOP := 1.60
const SEAM_EPS := 0.0004
const CAP_Y := 1.476
const CAP_SHRINK := 0.80
const EYE_CLEAR := 0.0028
## Výška nosu ve spodině (subnasale) jako podíl výšky špičky (běh 11: 0,20 → 0,15).
const SUB_K := 0.15
const RELAX_ITERS := 4
const RELAX_L := 0.5
const LIN_TOL := 0.00025
## Korekční tvar se uloží, jen když opraví víc než 0,3 mm.
const CX_MIN := 0.0003
## Mezitvar (in-between v ±0,5) se uloží, když se morf uprostřed odchyluje od lineární interpolace o víc než 0,5 mm.
const INB_MIN := 0.0005
const EAR_K := 6
const EAR_M := 16
const EYE_RINGS_DEG := [9.0, 10.0, 21.0, 27.0, 31.0, 36.0, 50.0, 70.0, 90.0, 110.0, 135.0, 160.0]
const EYE_SEG := 18
const RX_FRONT := [[0.04, 1.0], [0.0, 0.955], [-0.03, 0.91], [-0.06, 0.84], [-0.085, 0.71], [-0.105, 0.50], [-0.125, 0.30]]
const RX_BACK := [[0.03, 1.0], [-0.02, 0.97], [-0.06, 0.86], [-0.10, 0.74]]

## Materiály (název → barva, drsnost). Kůže sdílí materiál s tělem (barvu nastavuje SimVisual).
const MATERIALS := {
	"skin": {"name": "skin_body", "color": [0.78, 0.58, 0.47], "rough": 0.55, "metal": 0.0},
	"lips": {"name": "skin_lips", "color": [0.66, 0.40, 0.38], "rough": 0.42, "metal": 0.0},
	"mouth": {"name": "mouth_inner", "color": [0.24, 0.07, 0.07], "rough": 0.6, "metal": 0.0},
	"eye_socket": {"name": "eye_socket", "color": [0.55, 0.30, 0.30], "rough": 0.35, "metal": 0.0},
	"sclera": {"name": "eye_sclera", "color": [0.92, 0.90, 0.86], "rough": 0.12, "metal": 0.0},
	"iris": {"name": "eye_iris", "color": [0.30, 0.42, 0.55], "rough": 0.18, "metal": 0.0},
	"pupil": {"name": "eye_pupil", "color": [0.02, 0.02, 0.02], "rough": 0.08, "metal": 0.0},
}

static var _wx: PackedFloat64Array = PackedFloat64Array()
static var _wy: PackedFloat64Array = PackedFloat64Array()
static var _wz: PackedFloat64Array = PackedFloat64Array()
## Aktivní šev během build_data() (positions() ho aplikuje jako poslední krok) – jen při importu.
static var _conform: Dictionary = {}
## Směry paprsků spodní stěny mřížky (bottom_dir) – nezávislé na parametrech, počítají se jednou.
static var _bottom_dirs: Dictionary = {}


# ======================================================================================
## Kontrolu (hodnoty blend shapes, průniky kůže–oko při kombinacích extrémů, symetrie, determinismus,
# ======================================================================================
static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _g2(dx: float, dy: float, sx: float, sy: float) -> float:
	return exp(-0.5 * ((dx / sx) * (dx / sx) + (dy / sy) * (dy / sy)))


static func _g3(dx: float, dy: float, dz: float, sx: float, sy: float, sz: float) -> float:
	return exp(-0.5 * ((dx / sx) * (dx / sx) + (dy / sy) * (dy / sy) + (dz / sz) * (dz / sz)))


static func _smax(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return b + (a - b) * h + k * h * (1.0 - h)


static func _profile(table: Array, y: float) -> float:
	if y >= float(table[0][0]):
		return float(table[0][1])
	for i in range(1, table.size()):
		if y >= float(table[i][0]):
			var y0 := float(table[i - 1][0])
			var v0 := float(table[i - 1][1])
			var y1 := float(table[i][0])
			var v1 := float(table[i][1])
			var t := (y0 - y) / (y0 - y1)
			t = t * t * (3.0 - 2.0 * t)
			return v0 + (v1 - v0) * t
	return float(table[-1][1])


## Hustota vrcholů ρ(c) = 1 + amp·exp(−((c−c0)/σ)²) → tabulka t → c (numerická inverze, 2048 kroků).
static func _warp_table(c0: float, amp: float, sig: float, count: int) -> PackedFloat64Array:
	var n := 2048
	var cs := PackedFloat64Array()
	cs.resize(n + 1)
	for i in n + 1:
		cs[i] = -1.0 + 2.0 * float(i) / float(n)
	var cum := PackedFloat64Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		var cm := 0.5 * (cs[i] + cs[i + 1])
		cum[i + 1] = cum[i] + (1.0 + amp * exp(-pow((cm - c0) / sig, 2.0))) * (2.0 / float(n))
	var tot := cum[n]
	var out := PackedFloat64Array()
	out.resize(count + 1)
	for k in count + 1:
		var target := float(k) / float(count) * tot
		var lo := 0
		var hi := n
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if cum[mid] <= target:
				lo = mid
			else:
				hi = mid
		var f := (target - cum[lo]) / maxf(cum[hi] - cum[lo], 1e-12)
		out[k] = tan((cs[lo] + f * (cs[hi] - cs[lo])) * PI / 4.0)
	return out


static func _ensure_tables() -> void:
	if _wx.is_empty():
		_wx = _warp_table(0.0, 1.2, 0.45, NX)
		_wy = _warp_table(-0.3, 1.5, 0.55, NY)
		_wz = _warp_table(0.0, 0.0, 1.0, NZ)


## Spodní stěna mřížky (j = 0) – běh 11: paprsky ze středu hlavy pokryly rukáv krku jen jednou řadou ploch
## (zbytek spodní stěny padl na víčko), takže krk byl hrubý, pruhovaný a šev neměl geometrii. Čtvercové
## prstence spodní stěny R = max(|i − NX/2| − (NX − NZ)/2, |k − NZ/2|) se proto rozloží po výšce rukávu:
## R = NZ/2 okraj (původní paprsek), R = 2..NZ/2 − 1 rovnoměrné řady rukávu, R = 1 těsně nad víčkem,
## R = 0 víčko. Topologie se nemění, jen směry paprsků (spočítané z výchozí hlavy – nezávislé na morfech).
static func bottom_ring(i: int, k: int) -> int:
	return maxi(absi(i - NX / 2) - (NX - NZ) / 2, absi(k - NZ / 2))


static func _interp_table(tab: PackedFloat64Array, x: float) -> float:
	var i0 := clampi(int(floor(x)), 0, tab.size() - 2)
	return lerpf(tab[i0], tab[i0 + 1], x - float(i0))


static func bottom_dir(i: int, k: int) -> Vector3:
	var key := Vector2i(i, k)
	if _bottom_dirs.has(key):
		return _bottom_dirs[key]
	_ensure_tables()
	var half := NZ / 2
	var off := (NX - NZ) / 2
	var r := bottom_ring(i, k)
	var u: Vector3
	if r >= half:
		u = lattice_dir(i, 0, k)
	else:
		var a := float(i - NX / 2) / float(r + off)
		var b := 0.0 if r == 0 else float(k - half) / float(r)
		var cx := _interp_table(_wx, float(NX / 2) + a * float(NX / 2))
		var cz := _interp_table(_wz, float(half) + b * float(half))
		var th := atan2(cx, cz)
		var d0 := derive({})
		var c: Vector3 = d0["C"]
		var yb := float(surface(_dir_to(cx, -KY, cz), d0).y)
		var y_t := NECK_CAP_Y - 0.02
		var re := neck_ellipse_r(th)
		if r == 0:
			re *= 0.5
		else:
			y_t = lerpf(NECK_CAP_Y + 0.0005, yb, float(r - 1) / float(half - 1))
		u = _dir_to(sin(th) * re, y_t - float(c.y), neck_zc(y_t) + cos(th) * re - float(c.z))
	_bottom_dirs[key] = u
	return u


static func lattice_dir(i: int, j: int, k: int) -> Vector3:
	_ensure_tables()
	var cx := _wx[i]
	var cy := _wy[j] * KY
	var cz := _wz[k]
	var l := sqrt(cx * cx + cy * cy + cz * cz)
	return Vector3(cx / l, cy / l, cz / l)


# ======================================================================================
# Parametry → odvozené veličiny
# ======================================================================================
static func derive(p: Dictionary) -> Dictionary:
	var v := func(k: String) -> float: return float(p.get(k, 0.0))
	var d := {}
	d["C"] = Vector3(0.0, 1.668, 0.0)
	d["rx"] = 0.0745 * (1.0 + 0.07 * v.call("head_width"))
	d["ry_top"] = 0.112 * (1.0 + 0.05 * v.call("head_height"))
	d["rz_front"] = 0.094
	d["rz_back"] = 0.103 * (1.0 + 0.03 * v.call("head_height"))
	d["forehead"] = v.call("forehead_slope")
	d["brow"] = v.call("brow_ridge")
	d["brow_h"] = v.call("brow_height")
	d["jaw_w"] = v.call("jaw_width")
	d["jaw_a"] = v.call("jaw_angle")
	d["chin_l"] = v.call("chin_length")
	d["chin_w"] = v.call("chin_width")
	d["cleft"] = v.call("chin_cleft")
	d["cheekb"] = v.call("cheekbones")
	d["cheekf"] = v.call("cheeks_fullness") + 0.8 * v.call("b_fat")
	d["fat"] = v.call("b_fat")
	d["muscle"] = v.call("b_muscle")
	d["neck_r"] = NECK_R
	# Běh 11: tuk a svaly krk rozšiřovaly až o 40 % („balón“ pod čelistí) – reálně obvod krku roste
	# s tukem/svaly řádově o 10–20 %; spodek krku navíc řídí morfy těla přes šev.
	d["neck_s"] = 0.12 * v.call("neck_width") + 0.12 * v.call("b_fat") + 0.09 * v.call("b_muscle")
	d["asym_jaw"] = v.call("asym_jaw")
	d["nose_len"] = v.call("nose_length")
	d["nose_w"] = v.call("nose_width")
	d["nose_br"] = v.call("nose_bridge")
	d["nose_tip"] = v.call("nose_tip")
	d["nose_ang"] = v.call("nose_tip_angle")
	d["nose_dev"] = 0.0025 * v.call("asym_mouth")
	d["philtrum"] = v.call("philtrum")
	for s in [1, -1]:
		var e := {}
		var asy: float = v.call("asym_eyes") * (1.0 if s > 0 else -1.0)
		e["E"] = Vector3(float(s) * (0.0318 + 0.0050 * v.call("eye_distance")), 1.6685 + 0.0012 * asy, 0.0708 - 0.0045 * v.call("eye_depth"))
		e["E0"] = Vector3(float(s) * 0.0318, 1.6685, 0.0708)
		e["R"] = 0.0119 * (1.0 + 0.03 * v.call("eye_size"))
		e["W"] = 0.0142 * (1.0 + 0.13 * v.call("eye_size")) * (1.0 - 0.03 * asy)
		e["hu"] = 0.0053 * (1.0 + 0.28 * v.call("eye_size")) * (1.0 - 0.05 * asy)
		e["hl"] = 0.0043 * (1.0 + 0.22 * v.call("eye_size"))
		e["tilt"] = deg_to_rad(4.0 + 9.0 * v.call("eye_tilt"))
		e["hood"] = 0.4 + 0.55 * v.call("eyelid_hood")
		e["brow_h"] = v.call("brow_height")
		d["eye%d" % s] = e
	d["Mw"] = 0.0245 * (1.0 + 0.10 * v.call("mouth_width"))
	d["My"] = 1.6035
	d["lipU"] = 0.0038 * (1.0 + 0.45 * v.call("lip_upper"))
	d["lipL"] = 0.0046 * (1.0 + 0.40 * v.call("lip_lower"))
	d["lipUh"] = 0.0078 * (1.0 + 0.25 * v.call("lip_upper"))
	d["lipLh"] = 0.0094 * (1.0 + 0.22 * v.call("lip_lower"))
	d["mouth_asym"] = 0.0015 * v.call("asym_mouth")
	d["ear_s"] = 1.0 + 0.14 * v.call("ear_size")
	d["ear_a"] = deg_to_rad(17.0 + 14.0 * v.call("ear_angle"))
	return d


# ======================================================================================
# Povrch hlavy
# ======================================================================================
static func _base_t(u: Vector3, d: Dictionary) -> float:
	var ux := float(u.x)
	var uy := float(u.y)
	var uz := float(u.z)
	var y := uy * 0.105
	var front := _smooth(-0.35, 0.55, uz)
	var jaw := 1.0 + 0.07 * float(d["jaw_w"]) + 0.04 * float(d["muscle"]) + 0.04 * float(d["fat"])
	var chin := 1.0 + 0.20 * float(d["chin_w"])
	var rf := _profile(RX_FRONT, y)
	var low := _smooth(-0.02, -0.07, y)
	rf *= 1.0 + low * (jaw - 1.0) * (1.0 - _smooth(0.55, 0.9, uz)) + _smooth(-0.08, -0.11, y) * (chin - 1.0)
	var bp := _profile(RX_BACK, y)
	var rx_eff := float(d["rx"]) * (bp + (rf - bp) * front)
	rx_eff *= 1.0 + 0.012 * float(d["asym_jaw"]) * (1.0 if ux > 0.0 else -1.0) * low
	rx_eff *= 1.0 + 0.035 * exp(-pow((uy - 0.35) / 0.3, 2.0)) * (1.0 - front * 0.5)
	var ry: float
	if uy > 0.0:
		ry = float(d["ry_top"])
	else:
		var a := 0.066
		var b := 0.119 * (1.0 + 0.06 * float(d["chin_l"]))   # běh 10: delší dolní třetina obličeje (ústa–brada ~4,3 cm)
		ry = a + (b - a) * _smooth(-0.45, 0.75, uz)
	var rz := float(d["rz_front"]) if uz > 0.0 else float(d["rz_back"])
	# Dolní přední část hranatější (spodní plocha čelisti pod bradou – podbradek, úhel brada–krk).
	var pw := 2.0 + 0.45 * _smooth(0.0, 0.6, uy) + 1.1 * _smooth(-0.35, -0.8, uy) * _smooth(-0.3, 0.4, uz)
	var q := pow(absf(ux / rx_eff), pw) + pow(absf(uy / ry), pw) + pow(absf(uz / rz), pw)
	return pow(q, -1.0 / pw)


## Osa krku v dané výšce (z): 0 u těla (NECK_ZC_Y0), NECK_ZC pod hlavou (NECK_ZC_Y1).
static func neck_zc(y: float) -> float:
	return NECK_ZC * _smooth(NECK_ZC_Y0, NECK_ZC_Y1, y)


static func _neck_t(u: Vector3, d: Dictionary) -> float:
	var ux := float(u.x)
	var uy := float(u.y)
	var uz := float(u.z)
	if uy > -0.05:
		return 0.0
	var c: Vector3 = d["C"]
	var r := float(d["neck_r"])
	# Paprsek z C proti eliptickému válci krku (poloosy r·NECK_KX do stran, r·NECK_KZ do hloubky, osa z = NECK_ZC).
	var rx := r * NECK_KX
	var rz := r * NECK_KZ
	var t_cyl := 1e3
	var yh := float(c.y) - 0.1
	for _it in 12:   # pevný bod (osa krku podle výšky); konverguje rychle, mez jen pro jistotu
		var dz := float(c.z) - neck_zc(yh)
		var a := ux * ux / (rx * rx) + uz * uz / (rz * rz)
		var b := 2.0 * uz * dz / (rz * rz)
		var cc := dz * dz / (rz * rz) - 1.0
		if a <= 1e-9:
			break
		var disc := b * b - 4.0 * a * cc
		if disc <= 0.0:
			break
		t_cyl = (-b + sqrt(disc)) / (2.0 * a)
		var y_new := float(c.y) + uy * t_cyl
		if absf(y_new - yh) < 1e-6:
			break
		yh = y_new
	var t_cap := (float(c.y) - NECK_CAP_Y) / (-uy)
	return minf(t_cyl, t_cap)


static func _nose(x: float, y: float, d: Dictionary) -> float:
	var ln := float(d["nose_len"])
	x = x - float(d["nose_dev"]) * _smooth(0.015, -0.03, y)
	var top := 0.017
	var tip_y := -0.0305 - 0.0045 * ln
	var sub_y := tip_y - 0.0105 - 0.0012 * ln + 0.0035 * float(d["nose_ang"])
	var br := 1.0 + 0.45 * float(d["nose_br"])
	var tipw := 1.0 + 0.32 * float(d["nose_tip"])
	var tip_h := (0.0205 + 0.002 * ln) * (1.0 + 0.06 * float(d["nose_br"])) + 0.0018 * float(d["nose_tip"])
	var h: float
	if y > top:
		h = 0.0
	elif y > tip_y + 0.006:
		var t := (top - y) / (top - (tip_y + 0.006))
		h = (0.0016 + (tip_h * 0.84 - 0.0016) * pow(t, 1.15)) * (br if t < 0.85 else 1.0 + (br - 1.0) * (1.0 - t) / 0.15)
		h = maxf(h, 0.0)
	elif y > tip_y:
		var t := (tip_y + 0.006 - y) / 0.006
		h = tip_h * (0.84 + 0.16 * sin(t * PI / 2.0))
	elif y > sub_y:
		var t := (tip_y - y) / (tip_y - sub_y)
		h = tip_h * (1.0 - (1.0 - SUB_K) * pow(t, 0.75)) + 0.0030 * float(d["nose_ang"]) * t
	else:
		# Běh 11 (render C3 v Blenderu, nálezy 5 a 6): „ocas“ pod spodinou nosu byl nespojitý – nepočítal
		# s úhlem špičky (u nose_tip_angle ±1 schod 3 mm = světlá skvrna / tmavý pás pod nosem) a byl široký
		# (20 % výšky špičky, σ 4 mm), takže ret pod nosem se svažoval dopředu dolů. Teď spojitý v sub_y,
		# nižší (SUB_K) a ostřejší (σ 3,2 mm) – filtrum je strmější a přechod nos–ret čitelný.
		var t := (sub_y - y) / 0.0032
		h = (tip_h * SUB_K + 0.0030 * float(d["nose_ang"])) * exp(-t * t)
	var w: float
	if y > tip_y:
		var t := clampf((top - y) / (top - tip_y), 0.0, 1.0)
		w = 0.0050 + 0.0035 * t
		w *= 1.0 + (tipw - 1.0) * _smooth(0.6, 1.0, t)
	else:
		w = 0.0085 * tipw
	w *= 1.0 + 0.10 * float(d["nose_w"])
	var hh := h * exp(-0.5 * (x / w) * (x / w))
	var aw := 0.0150 * (1.0 + 0.16 * float(d["nose_w"]))
	var ay := tip_y - 0.0048
	hh += (0.0068 + 0.0008 * float(d["nose_tip"])) * _g2(absf(x) - aw * 0.78, y - ay, 0.0050, 0.0050)
	return hh


static func _relief(px: float, py: float, pz: float, d: Dictionary) -> float:
	var x := px
	var y := py
	var z := pz
	var ax := absf(x)
	var fr := _smooth(0.02, 0.07, z)
	var c: Vector3 = d["C"]
	var r := 0.0
	var fh := float(d["forehead"])
	r -= (0.012 if fh > 0.0 else 0.005) * fh * _smooth(0.025, 0.10, y) * fr
	var yb := 0.030 + 0.0045 * float(d["brow_h"])
	r += (0.0042 + 0.0040 * float(d["brow"])) * _g2(ax - 0.030, y - yb, 0.020, 0.0075) * fr
	r -= 0.0028 * _g2(x, y - 0.016, 0.009, 0.007) * fr
	for s in [1, -1]:
		var e: Vector3 = d["eye%d" % s]["E"]
		r -= 0.0040 * _g2(x - float(e.x), y - (float(e.y) - float(c.y)), 0.016, 0.012) * fr
	r -= 0.0035 * _g2(ax - 0.068, y - 0.035, 0.012, 0.02) * _smooth(-0.01, 0.04, z)
	r += (0.0042 + 0.0050 * float(d["cheekb"])) * _g3(ax - 0.050, y + 0.010, z - 0.050, 0.012, 0.010, 0.022)
	r += (0.0024 + 0.0050 * float(d["cheekf"])) * _g3(ax - 0.044, y + 0.040, z - 0.055, 0.014, 0.016, 0.03)
	r += (0.0025 + 0.0035 * float(d["jaw_a"]) + 0.0015 * float(d["muscle"])) * _g3(ax - 0.050, y + 0.070, z + 0.002, 0.010, 0.010, 0.016)
	var my := float(d["My"]) - float(c.y)
	r += 0.0055 * _g2(x, (y - my) * 0.9, 0.022, 0.020) * fr
	r -= 0.0010 * _g2(ax - 0.020 - (y - my) * -0.25, y - (my + 0.012), 0.004, 0.012) * fr
	var cy := -0.106 - 0.008 * float(d["chin_l"])
	r += (0.0062 + 0.002 * float(d["chin_l"])) * _g2(x / (1.0 + 0.40 * float(d["chin_w"])), y - cy, 0.013, 0.010) * fr
	r -= 0.0022 * _g2(x, y - (my - 0.020), 0.012, 0.0045) * fr
	var cl := maxf(0.0, float(d["cleft"]))
	r -= 0.0016 * cl * _g2(x, y - (cy + 0.002), 0.0028, 0.006) * fr
	r += _nose(x, y, d) * fr
	var phy := my + 0.0145
	var pf := 1.0 + 0.9 * float(d["philtrum"])
	r += 0.0014 * pf * _g2(ax - 0.0045, y - phy, 0.0018, 0.005) * fr
	r -= 0.0010 * pf * _g2(x, y - phy, 0.0022, 0.005) * fr
	r += 0.0045 * maxf(0.0, float(d["fat"])) * _g3(x, y + 0.112, z - 0.04, 0.03, 0.012, 0.03)
	return r


## Bod povrchu hlavy ve směru u (jednotkový vektor od středu C).
static func surface(u: Vector3, d: Dictionary) -> Vector3:
	var tb := _base_t(u, d)
	var tn := _neck_t(u, d)
	var t := _smax(tb, tn, 0.009) if tn > 0.0 else tb
	var c: Vector3 = d["C"]
	t += _relief(float(u.x) * t, float(u.y) * t, float(u.z) * t, d)
	var px := float(c.x) + float(u.x) * t
	var py := float(c.y) + float(u.y) * t
	var pz := float(c.z) + float(u.z) * t
	var ns := float(d["neck_s"])
	if ns != 0.0:
		# Běh 10 (vizuální kontrola): krk se rozšiřuje po celé délce až k tělu, ne jen pod hlavou – dřív
		# vznikal u velkého tuku „balón“ pod čelistí. Vpředu (podbradek) slabší než do stran a dozadu.
		var w := _smooth(1.598, 1.556, py) * (1.0 - 0.6 * _smooth(0.025, 0.055, pz))
		var k := 1.0 + ns * w
		var zc := neck_zc(py)
		px *= k
		pz = zc + (pz - zc) * k
	return push_out(Vector3(px, py, pz), d)


## Ochrana proti průnikům: kůže nikdy není blíž středu oka než R + EYE_CLEAR (měkké maximum, bez zlomu).
static func push_out(p: Vector3, d: Dictionary) -> Vector3:
	var px := float(p.x)
	var py := float(p.y)
	var pz := float(p.z)
	for s in [1, -1]:
		var e: Dictionary = d["eye%d" % s]
		var ec: Vector3 = e["E"]
		var dx := px - float(ec.x)
		var dy := py - float(ec.y)
		var dz := pz - float(ec.z)
		var dist := sqrt(dx * dx + dy * dy + dz * dz)
		var rmin := float(e["R"]) + EYE_CLEAR
		if dist < rmin + 0.003 and dist > 1e-9:
			var k := _smax(dist, rmin, 0.003) / dist
			px = float(ec.x) + dx * k
			py = float(ec.y) + dy * k
			pz = float(ec.z) + dz * k
	return Vector3(px, py, pz)


static func _dir_to(x: float, y: float, z: float) -> Vector3:
	var l := sqrt(x * x + y * y + z * z)
	return Vector3(x / l, y / l, z / l)


## Bod přední části povrchu se zadanými světovými x, y (pevný bod iterace podél paprsků z C).
static func surface_xy(x: float, y: float, d: Dictionary, z0 := 0.085) -> Vector3:
	var c: Vector3 = d["C"]
	var z := z0
	var p := Vector3.ZERO
	for _i in 5:
		p = surface(_dir_to(x - float(c.x), y - float(c.y), z), d)
		z = float(p.z) - float(c.z)
	return p


static func surface_at(q: Vector3, d: Dictionary) -> Vector3:
	var c: Vector3 = d["C"]
	return surface(_dir_to(float(q.x) - float(c.x), float(q.y) - float(c.y), float(q.z) - float(c.z)), d)


# ======================================================================================
# Oči
# ======================================================================================
static func _almond(e: Dictionary, a: float, b: float, f: float, cs := 0.0007) -> Vector2:
	var w := float(e["W"]) * f
	var hu := float(e["hu"]) * f
	var hl := float(e["hl"]) * f
	a = clampf(a, -1.0, 1.0)
	var up := hu * pow(1.0 - a * a, 0.85) * (1.0 - 0.18 * a)
	var lo := -hl * pow(1.0 - a * a, 0.9) * (1.0 + 0.22 * a)
	var yb := lo + (up - lo) * (b + 1.0) * 0.5
	var x := a * w
	if absf(a) > 0.999:
		x = a * (w + cs * (1.0 - b * b))
		yb = cs * b
	var tilt := float(e["tilt"])
	return Vector2(x * cos(tilt), yb + x * sin(tilt))


static func _sph(e: Dictionary, x: float, y: float, rho: float, k: float, side: int) -> Vector3:
	var ec: Vector3 = e["E"]
	var ph := x / rho * k
	var th := y / rho * k
	var cx := sin(ph) * cos(th)
	var cy := sin(th)
	var cz := cos(ph) * cos(th)
	return Vector3(float(ec.x) + float(side) * cx * rho, float(ec.y) + cy * rho, float(ec.z) + cz * rho)


static func _eye_ring_pos(d: Dictionary, s: int, ring: int, a: float, b: float, gi: int, gj: int) -> Vector3:
	var e: Dictionary = d["eye%d" % s]
	var ec: Vector3 = e["E"]
	var r := float(e["R"])
	var am := a * float(s)
	match ring:
		1:
			var xy := _almond(e, am, b, 1.0, 0.0035)
			var hood := float(e["hood"])
			var up := maxf(0.0, b)
			var fy := 1.9 if xy.y > 0.0 else 1.6
			var e0: Vector3 = e["E0"]
			var cc: Vector3 = d["C"]
			var gx := float(e0.x) + float(s) * float(xy.x) * 1.32
			var gy := float(e0.y) + float(xy.y) * fy + 0.0030 * float(e["brow_h"]) * up
			var g := surface(lattice_dir(gi, gj, NZ), d)
			gx = gx + (float(g.x) - gx) * 0.35
			gy = gy + (float(g.y) - gy) * 0.35
			var p := surface_xy(gx, gy, d, float(e0.z) + 0.012 - float(cc.z))
			return Vector3(float(p.x) + 0.85 * (float(ec.x) - float(e0.x)),
				float(p.y) + 0.85 * (float(ec.y) - float(e0.y)) - 0.0030 * hood * up,
				float(p.z) + 0.85 * (float(ec.z) - float(e0.z)) + 0.0016 * hood * up)
		2:
			var xy := _almond(e, am, b, 1.18, 0.0022)
			var up := maxf(0.0, b)
			return _sph(e, float(xy.x), float(xy.y) - 0.0007 * float(e["hood"]) * up, r + 0.0034, 1.0, s)
		3:
			var xy := _almond(e, am, b, 1.0)
			return _sph(e, float(xy.x), float(xy.y), r + 0.0018, 1.0, s)
		4:
			var xy := _almond(e, am, b, 0.985)
			return _sph(e, float(xy.x), float(xy.y), r + 0.0012, 1.0, s)
		5:
			var xy := _almond(e, am, b, 1.0)
			return _sph(e, float(xy.x), float(xy.y), r + 0.0012, 1.55, s)
	return ec


static func _eye_cap_pos(d: Dictionary, s: int, a: float, b: float) -> Vector3:
	var e: Dictionary = d["eye%d" % s]
	var ec: Vector3 = e["E"]
	var r := float(e["R"]) + 0.0012
	var m := maxf(absf(a), absf(b))
	if m < 1e-9:
		return Vector3(float(ec.x), float(ec.y), float(ec.z) - r)
	var p := _eye_ring_pos(d, s, 5, a / m, b / m, 0, 0)
	var dv := _dir_to(float(p.x) - float(ec.x), float(p.y) - float(ec.y), float(p.z) - float(ec.z))
	var dot := clampf(-float(dv.z), -1.0, 1.0)
	var om := acos(dot)
	var vx: float
	var vy: float
	var vz: float
	if om < 1e-6:
		vx = float(dv.x)
		vy = float(dv.y)
		vz = float(dv.z)
	else:
		var w0 := sin((1.0 - m) * om) / sin(om)
		var w1 := sin(m * om) / sin(om)
		var n := _dir_to(float(dv.x) * w1, float(dv.y) * w1, -w0 + float(dv.z) * w1)
		vx = float(n.x)
		vy = float(n.y)
		vz = float(n.z)
	return Vector3(float(ec.x) + vx * r, float(ec.y) + vy * r, float(ec.z) + vz * r)


# ======================================================================================
# Ústa
# ======================================================================================
static func _lip_curves(d: Dictionary, a: float) -> Vector2:
	var aa := clampf(absf(a), 0.0, 1.0)
	var bow := 1.0 - 0.16 * exp(-pow(a / 0.11, 2.0)) + 0.07 * exp(-pow((aa - 0.26) / 0.12, 2.0))
	var up := float(d["lipUh"]) * pow(1.0 - pow(aa, 2.2), 0.55) * bow
	var lo := -float(d["lipLh"]) * pow(1.0 - aa * aa, 0.6)
	return Vector2(up, lo)


static func _mouth_ring_pos(d: Dictionary, ring: int, a: float, b: float, gi: int, gj: int) -> Vector3:
	var mw := float(d["Mw"])
	var my := float(d["My"]) + float(d["mouth_asym"]) * a
	var side := absf(a) > 0.999
	var ul := _lip_curves(d, a)
	var upper := b > 0.0
	var fz := sqrt(1.0 - pow(minf(absf(a), 1.0), 2.0))
	match ring:
		1:
			var x := a * mw * 1.04
			var y := float(ul.x) if upper else float(ul.y)
			if side:
				y = 0.0012 * b
				x = a * mw
				var ps := surface_xy(x, my + y, d, 0.09)
				return Vector3(ps.x, ps.y, float(ps.z) - 0.0015)
			var g := surface(lattice_dir(gi, gj, NZ), d)
			var p := surface_xy(x + (float(g.x) - x) * 0.12, (my + y) + (float(g.y) - (my + y)) * 0.12, d, 0.09)
			return Vector3(p.x, p.y, float(p.z) + 0.0004 * fz)
		2:
			var x := a * mw * 0.97
			var y := float(ul.x) * 0.45 if upper else float(ul.y) * 0.62
			if side:
				y = 0.0006 * b
			var p := surface_xy(x, my + y, d, 0.09)
			var full := float(d["lipU"]) if upper else float(d["lipL"])
			return Vector3(p.x, p.y, float(p.z) + full * fz)
		3:
			var x := a * mw * 0.93
			var y := 0.00025 * (1.0 if upper else -1.0)
			if side:
				y = 0.00025 * b
			var p := surface_xy(x, my + y, d, 0.09)
			var full := (float(d["lipU"]) + float(d["lipL"])) * 0.5
			return Vector3(p.x, p.y, float(p.z) + full * 0.55 * fz - 0.0006)
		4:
			var x := a * mw * 0.86
			var y := 0.0022 * (1.0 if upper else -1.0)
			if side:
				y = 0.0022 * b
			var p := surface_xy(x, my + y, d, 0.09)
			return Vector3(p.x, p.y, float(p.z) - 0.0045)
	return Vector3.ZERO


static func _mouth_cap_pos(d: Dictionary, a: float, b: float) -> Vector3:
	var p := surface_xy(a * float(d["Mw"]) * 0.7, float(d["My"]) + b * 0.006, d, 0.09)
	return Vector3(p.x, p.y, float(p.z) - 0.016 + 0.004 * (a * a))


# ======================================================================================
# Uši a oční koule
# ======================================================================================
static func _ear_local(side: int, k: int, m: int) -> Vector3:
	var rr := float(k) / float(EAR_K)
	var ph := 2.0 * PI * float(m) / float(EAR_M)
	var ny := sin(ph)
	var nz := cos(ph)
	var hy := 0.0310
	var hz := 0.0180 * (1.0 + 0.18 * ny)
	var y := ny * rr * hy
	var z := nz * rr * hz - 0.002 * (1.0 - ny) * rr
	var edge := sqrt(maxf(0.0, 1.0 - rr * rr))
	var lobe := _smooth(-0.45, -0.85, ny)
	var x: float
	if side > 0:
		var helix := 0.0040 * exp(-pow((rr - 0.84) / 0.10, 2.0)) * (1.0 - lobe)
		var anti := 0.0022 * exp(-pow((rr - 0.52) / 0.10, 2.0)) * (1.0 - lobe) * (1.0 - _smooth(0.2, 0.8, nz))
		var concha := -0.0016 * exp(-(pow((y + 0.003) / 0.009, 2.0) + pow((z - 0.002) / 0.007, 2.0)))
		x = (0.0022 + helix + anti + concha + 0.0026 * lobe) * sqrt(edge)
	else:
		x = -0.0026 * sqrt(edge)
	return Vector3(x, y, z)


static func _ear_pos(d: Dictionary, s: int, side: int, k: int, m: int) -> Vector3:
	var l := _ear_local(side, k, m)
	var sc := float(d["ear_s"])
	var lx := float(l.x) * sc
	var ly := float(l.y) * sc
	var lz := float(l.z) * sc
	var tb := deg_to_rad(14.0)
	var ly2 := ly * cos(tb) - lz * sin(tb)
	var lz2 := ly * sin(tb) + lz * cos(tb)
	ly = ly2
	lz = lz2
	var piv_z := 0.016 * sc
	var ang := float(d["ear_a"])
	var dz := lz - piv_z
	var rx := lx * cos(ang) - dz * sin(ang)
	var rz := lx * sin(ang) + dz * cos(ang) + piv_z
	var a := surface_at(Vector3(float(s) * 0.2, 1.655, -0.006), d)
	var ax := float(a.x) - float(s) * 0.003
	return Vector3(ax + float(s) * rx, float(a.y) + ly, float(a.z) - 0.004 + rz)


static func _eyeball_pos(d: Dictionary, s: int, kind: String, i: int, j: int) -> Vector3:
	var e: Dictionary = d["eye%d" % s]
	var ec: Vector3 = e["E"]
	var r := float(e["R"])
	var th := 0.0
	if kind == "back":
		th = PI
	elif kind == "ring":
		th = deg_to_rad(float(EYE_RINGS_DEG[i]))
	var ph := 2.0 * PI * float(j) / float(EYE_SEG)
	var rr := r
	if th < deg_to_rad(33.0):
		rr = r * (1.0 + 0.055 * pow(maxf(0.0, cos(minf(th, deg_to_rad(32.0)) / deg_to_rad(32.0) * PI / 2.0)), 2.0))
	return Vector3(float(ec.x) + sin(th) * cos(ph) * rr, float(ec.y) + sin(th) * sin(ph) * rr, float(ec.z) + cos(th) * rr)


# ======================================================================================
# Topologie (pevná, nezávislá na parametrech)
# ======================================================================================
class Topo:
	var recipes: Array = []          # recept každého vrcholu (Array)
	var index := {}                  # klíč (String) -> index vrcholu
	var faces: Array = []            # [část, materiál, PackedInt32Array] – CCW zvenku
	var blocks := {}
	var relax_idx := PackedInt32Array()
	var relax_nb: Array = []         # Array[PackedInt32Array]
	var relax_mouth := PackedByteArray()  # 1 = vrchol mřížky u úst (tečné vyhlazení + návrat na povrch)

	func v(rec: Array) -> int:
		var key := ",".join(PackedStringArray(rec.map(func(x): return str(x))))
		if index.has(key):
			return index[key]
		index[key] = recipes.size()
		recipes.append(rec)
		return recipes.size() - 1

	func add(part: String, mat: String, idx: Array) -> void:
		faces.append([part, mat, PackedInt32Array(idx)])


static func _span(vals: Array, lo: float, hi: float) -> Vector2i:
	var a := 0
	for k in vals.size():
		if float(vals[k]) <= lo:
			a = k
	var b := vals.size() - 1
	for k in range(vals.size() - 1, -1, -1):
		if float(vals[k]) >= hi:
			b = k
	return Vector2i(a, b - a)


static func _perimeter(i0: int, j0: int, bw: int, bh: int) -> Array:
	var out: Array = []
	for i in bw:
		out.append([i0 + i, j0])
	for j in bh:
		out.append([i0 + bw, j0 + j])
	for i in range(bw, 0, -1):
		out.append([i0 + i, j0 + bh])
	for j in range(bh, 0, -1):
		out.append([i0, j0 + j])
	var res: Array = []
	for q in out:
		res.append([q[0], q[1], float(q[0] - i0) / float(bw) * 2.0 - 1.0, float(q[1] - j0) / float(bh) * 2.0 - 1.0])
	return res


static func build_topology() -> Topo:
	var t := Topo.new()
	var d0 := derive({})
	var xs: Array = []
	var ys: Array = []
	for i in NX + 1:
		xs.append(float(surface(lattice_dir(i, NY / 2, NZ), d0).x))
	for j in NY + 1:
		ys.append(float(surface(lattice_dir(NX / 2, j, NZ), d0).y))
	var e: Vector3 = d0["eye1"]["E"]
	var sx := _span(xs, float(e.x) - 0.021, float(e.x) + 0.021)
	var sy := _span(ys, float(e.y) - 0.013, float(e.y) + 0.016)
	t.blocks["eye1"] = [sx.x, sy.x, sx.y, sy.y]
	t.blocks["eye-1"] = [NX - sx.x - sx.y, sy.x, sx.y, sy.y]
	var mx := _span(xs, -0.034, 0.034)
	var my := _span(ys, float(d0["My"]) - 0.015, float(d0["My"]) + 0.012)
	t.blocks["mouth"] = [mx.x, my.x, mx.y, my.y]
	# stěny kostky: [pevná osa, znaménko, osa a, osa b] s a × b = vnější normála
	var cube_faces := [[0, 1, 1, 2], [0, -1, 2, 1], [1, 1, 2, 0], [1, -1, 0, 2], [2, 1, 0, 1], [2, -1, 1, 0]]
	var nn := [NX, NY, NZ]
	for cf in cube_faces:
		var ax: int = cf[0]
		var sg: int = cf[1]
		var aa: int = cf[2]
		var bb: int = cf[3]
		var fixed: int = nn[ax] if sg > 0 else 0
		for ia in nn[aa]:
			for ib in nn[bb]:
				if ax == 2 and sg > 0 and _in_block(t.blocks, ia, ib):
					continue
				var q: Array = []
				for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var c := [0, 0, 0]
					c[ax] = fixed
					c[aa] = ia + dd[0]
					c[bb] = ib + dd[1]
					q.append(t.v(["g", c[0], c[1], c[2]]))
				t.add("head", "skin", q)
	for s in [1, -1]:
		var bl: Array = t.blocks["eye%d" % s]
		var per := _perimeter(bl[0], bl[1], bl[2], bl[3])
		var rings: Array = []
		var r0: Array = []
		for p in per:
			r0.append(t.v(["g", p[0], p[1], NZ]))
		rings.append(r0)
		for r in range(1, 6):
			var rr: Array = []
			for p in per:
				rr.append(t.v(["er", s, r, p[2], p[3], p[0], p[1]]))
			rings.append(rr)
		_annulus(t, rings, ["skin", "skin", "skin", "skin", "eye_socket"])
		_cap(t, rings[-1], per, bl, "ec", s, "eye_socket")
	var mb: Array = t.blocks["mouth"]
	var mper := _perimeter(mb[0], mb[1], mb[2], mb[3])
	var mrings: Array = []
	var m0: Array = []
	for p in mper:
		m0.append(t.v(["g", p[0], p[1], NZ]))
	mrings.append(m0)
	for r in range(1, 5):
		var rr: Array = []
		for p in mper:
			rr.append(t.v(["mr", r, p[2], p[3], p[0], p[1]]))
		mrings.append(rr)
	_annulus(t, mrings, ["skin", "lips", "lips", "mouth"])
	_cap(t, mrings[-1], mper, mb, "mc", 0, "mouth")
	_relax_setup(t)
	for s in [1, -1]:
		_ear(t, s)
	for s in [1, -1]:
		_eyeball(t, s)
	return t


static func _in_block(blocks: Dictionary, i: int, j: int) -> bool:
	for k in blocks:
		var b: Array = blocks[k]
		if i >= b[0] and i < b[0] + b[2] and j >= b[1] and j < b[1] + b[3]:
			return true
	return false


static func _annulus(t: Topo, rings: Array, mats: Array) -> void:
	var m_count: int = (rings[0] as Array).size()
	for r in rings.size() - 1:
		var o: Array = rings[r]
		var inn: Array = rings[r + 1]
		for m in m_count:
			var n := (m + 1) % m_count
			t.add("head", mats[r], [o[m], o[n], inn[n], inn[m]])


static func _cap(t: Topo, ring: Array, per: Array, bl: Array, kind: String, s: int, mat: String) -> void:
	var i0: int = bl[0]
	var j0: int = bl[1]
	var bw: int = bl[2]
	var bh: int = bl[3]
	var pmap := {}
	for k in per.size():
		pmap[Vector2i(int(per[k][0]) - i0, int(per[k][1]) - j0)] = ring[k]
	for ci in bw:
		for cj in bh:
			var q: Array = []
			for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var key := Vector2i(ci + dd[0], cj + dd[1])
				if pmap.has(key):
					q.append(pmap[key])
				else:
					var a := float(key.x) / float(bw) * 2.0 - 1.0
					var b := float(key.y) / float(bh) * 2.0 - 1.0
					q.append(t.v([kind, s, a, b]) if kind == "ec" else t.v([kind, a, b]))
			t.add("head", mat, q)


static func _relax_setup(t: Topo) -> void:
	var nb := {}
	for f in t.faces:
		var idx: PackedInt32Array = f[2]
		for k in idx.size():
			var a := idx[k]
			var b := idx[(k + 1) % idx.size()]
			if not nb.has(a):
				nb[a] = {}
			if not nb.has(b):
				nb[b] = {}
			nb[a][b] = true
			nb[b][a] = true
	var sel: Array = []
	var mouth := {}
	for i in t.recipes.size():
		var rec: Array = t.recipes[i]
		if rec[0] == "er" and int(rec[2]) == 1:
			sel.append(i)
		elif rec[0] == "g" and int(rec[3]) == NZ:
			var in_eye := false
			var in_mouth := false
			for k in t.blocks:
				var b: Array = t.blocks[k]
				if int(rec[1]) >= b[0] - 1 and int(rec[1]) <= b[0] + b[2] + 1 and int(rec[2]) >= b[1] - 1 and int(rec[2]) <= b[1] + b[3] + 1:
					if String(k) == "mouth":
						in_mouth = true
					else:
						in_eye = true
			if in_eye or in_mouth:
				sel.append(i)
				if in_mouth and not in_eye:
					mouth[i] = true
	sel.sort()
	t.relax_idx = PackedInt32Array(sel)
	t.relax_mouth = PackedByteArray()
	t.relax_mouth.resize(sel.size())
	for r in sel.size():
		t.relax_mouth[r] = 1 if mouth.has(sel[r]) else 0
	t.relax_nb = []
	for i in sel:
		var l: Array = (nb[i] as Dictionary).keys()
		l.sort()
		t.relax_nb.append(PackedInt32Array(l))


static func _ear(t: Topo, s: int) -> void:
	for side in [1, -1]:
		var fl: Array = []
		for m in EAR_M:
			fl.append([_ear_node(t, s, side, 0, 0), _ear_node(t, s, side, 1, m + 1), _ear_node(t, s, side, 1, m)])
		for k in range(1, EAR_K):
			for m in EAR_M:
				fl.append([_ear_node(t, s, side, k, m), _ear_node(t, s, side, k, m + 1),
					_ear_node(t, s, side, k + 1, m + 1), _ear_node(t, s, side, k + 1, m)])
		var flip: bool = (int(side) < 0) != (s < 0)
		for f in fl:
			var ff: Array = f.duplicate()
			if flip:
				ff.reverse()
			t.add("head", "skin", ff)


static func _ear_node(t: Topo, s: int, side: int, k: int, m: int) -> int:
	m = m % EAR_M
	if k == 0:
		return t.v(["ear", s, side, 0, 0])
	if k == EAR_K:
		return t.v(["ear", s, 1, EAR_K, m])
	return t.v(["ear", s, side, k, m])


static func _eyeball(t: Topo, s: int) -> void:
	var nr := EYE_RINGS_DEG.size()
	var f := t.v(["eb", s, "front", 0, 0])
	var bk := t.v(["eb", s, "back", 0, 0])
	for j in EYE_SEG:
		t.add("eyes", "pupil", [f, t.v(["eb", s, "ring", 0, j % EYE_SEG]), t.v(["eb", s, "ring", 0, (j + 1) % EYE_SEG])])
	for i in nr - 1:
		var m := "iris" if float(EYE_RINGS_DEG[i + 1]) <= 27.0 else "sclera"
		for j in EYE_SEG:
			t.add("eyes", m, [t.v(["eb", s, "ring", i, j % EYE_SEG]), t.v(["eb", s, "ring", i + 1, j % EYE_SEG]),
				t.v(["eb", s, "ring", i + 1, (j + 1) % EYE_SEG]), t.v(["eb", s, "ring", i, (j + 1) % EYE_SEG])])
	for j in EYE_SEG:
		t.add("eyes", "sclera", [bk, t.v(["eb", s, "ring", nr - 1, (j + 1) % EYE_SEG]), t.v(["eb", s, "ring", nr - 1, j % EYE_SEG])])


# ======================================================================================
# Polohy, morfy, váhy
# ======================================================================================
static func vertex_pos(rec: Array, d: Dictionary) -> Vector3:
	match String(rec[0]):
		"g":
			if int(rec[2]) == 0:
				return surface(bottom_dir(rec[1], rec[3]), d)
			return surface(lattice_dir(rec[1], rec[2], rec[3]), d)
		"er":
			return _eye_ring_pos(d, rec[1], rec[2], rec[3], rec[4], rec[5], rec[6])
		"ec":
			return _eye_cap_pos(d, rec[1], rec[2], rec[3])
		"mr":
			return _mouth_ring_pos(d, rec[1], rec[2], rec[3], rec[4], rec[5])
		"mc":
			return _mouth_cap_pos(d, rec[1], rec[2])
		"ear":
			return _ear_pos(d, rec[1], rec[2], rec[3], rec[4])
		"eb":
			return _eyeball_pos(d, rec[1], rec[2], rec[3], rec[4])
	return Vector3.ZERO


static func positions(t: Topo, params: Dictionary) -> PackedVector3Array:
	var d := derive(params)
	var p := PackedVector3Array()
	p.resize(t.recipes.size())
	for i in t.recipes.size():
		p[i] = vertex_pos(t.recipes[i], d)
	var n_rel := t.relax_idx.size()
	var newp := PackedVector3Array()
	newp.resize(n_rel)
	var c: Vector3 = d["C"]
	# Běh 11 (nález 5): u ÚST je vyhlazení jen TEČNÉ (bez složky ve směru od středu hlavy) a vrcholy mřížky
	# se pak vrátí na povrch – plné laplaceovské vyhlazení táhlo vrchol nad horním rtem ke spodině nosu
	# (u velkého nosu o 5 mm dopředu), filtrum se svažovalo a tvořilo tmavý pás nad rtem.
	# U OČÍ zůstává plné vyhlazení bez návratu na povrch: vnější prstenec víček sleduje hloubku a vzdálenost
	# oka (0,85 × posun středu) a sousední řada mřížky ho musí následovat, jinak se pruh pod okem přeloží
	# (běh 12: eye_depth +1 se zúžením eye_distance −1 → 6 obrácených ploch v test_head).
	var has_kind := t.relax_mouth.size() == n_rel
	for _it in RELAX_ITERS:
		for r in n_rel:
			var nbs: PackedInt32Array = t.relax_nb[r]
			var acc := Vector3.ZERO
			for j in nbs:
				acc += p[j]
			var cur := p[t.relax_idx[r]]
			var delta := RELAX_L * (acc / float(nbs.size()) - cur)
			if has_kind and t.relax_mouth[r] == 1:
				var rad := (cur - c).normalized()
				delta -= rad * delta.dot(rad)
			newp[r] = cur + delta
		for r in n_rel:
			p[t.relax_idx[r]] = newp[r]
	for r in n_rel:
		var vi := t.relax_idx[r]
		if t.recipes[vi][0] == "g":
			if has_kind and t.relax_mouth[r] == 1:
				p[vi] = surface(_dir_to(float(p[vi].x) - float(c.x), float(p[vi].y) - float(c.y), float(p[vi].z) - float(c.z)), d)
			else:
				p[vi] = push_out(p[vi], d)  # vyhlazená řada u oka nesmí vniknout do oční koule
		else:
			p[vi] = push_out(p[vi], d)
	if not _conform.is_empty():
		p = _apply_seam(p)
	return p


## Morfy: {"targets": {klíč: PackedVector3Array výchylek}, "spec": {pole: [lineární] | [kladný, záporný]}}.
static func morph_targets(t: Topo, p0: PackedVector3Array) -> Dictionary:
	var out := {}
	var spec := {}
	for k in FACE_KEYS + ASYM_KEYS:
		var pp := positions(t, {k: 1.0})
		var pn := positions(t, {k: -1.0})
		var dp := PackedVector3Array()
		var dn := PackedVector3Array()
		dp.resize(p0.size())
		dn.resize(p0.size())
		var err := 0.0
		var mp := 0.0
		var mn := 0.0
		for i in p0.size():
			dp[i] = pp[i] - p0[i]
			dn[i] = pn[i] - p0[i]
			var sm := dp[i] + dn[i]
			err = maxf(err, maxf(absf(sm.x), maxf(absf(sm.y), absf(sm.z))))
			mp = maxf(mp, maxf(absf(dp[i].x), maxf(absf(dp[i].y), absf(dp[i].z))))
			mn = maxf(mn, maxf(absf(dn[i].x), maxf(absf(dn[i].y), absf(dn[i].z))))
		if err < LIN_TOL:
			out[k] = dp
			spec[k] = [k]
		else:
			spec[k] = [k + "_pos", k + "_neg"]
			if mp > 1e-5:
				out[k + "_pos"] = dp
			if mn > 1e-5:
				out[k + "_neg"] = dn
	for k in BODY_KEYS:
		var pp := positions(t, {k: 1.0})
		var dp := PackedVector3Array()
		dp.resize(p0.size())
		for i in p0.size():
			dp[i] = pp[i] - p0[i]
		out[k] = dp
		spec[k] = [k]
	# Mezitvary: morf, jehož tvar v polovině není polovinou plného tvaru (délka nosu mění profil nelineárně),
	# dostane navíc tvar δ = P(±0,5) − P0 − ½·d(±1) s „trojúhelníkovou“ vahou 1 − |2|v| − 1| (FaceMorphs) –
	# Godot nemá nativní in-between blend shapes, tohle je jejich přesná náhrada v bodech 0, ½ a 1.
	# Když mezitvar potřebuje jedna strana, dostane ho i druhá (je-li ta strana samostatný tvar) – jinak by
	# drobná změna jinde v hlavě (běh 12: vyhlazení u úst) mohla jednu stranu shodit pod práh a profil by
	# se na ní lámal jinak než na druhé.
	var inb: Array = []
	for k in FACE_KEYS + ASYM_KEYS:
		var cand := {}
		var need := false
		for sg in [1, -1]:
			var p1 := positions(t, {k: float(sg)})
			var ph := positions(t, {k: 0.5 * float(sg)})
			var dm := PackedVector3Array()
			dm.resize(p0.size())
			var mx := 0.0
			for i in p0.size():
				dm[i] = ph[i] - p0[i] - (p1[i] - p0[i]) * 0.5
				mx = maxf(mx, dm[i].length())
			cand[sg] = [dm, mx]
			need = need or mx > INB_MIN
		if not need:
			continue
		for sg in [1, -1]:
			if float(cand[sg][1]) > INB_MIN or (out.has(k + "_pos") and out.has(k + "_neg")):
				var nm := FaceMorphs.inbetween_name(k, sg)
				out[nm] = cand[sg][0]
				inb.append(nm)
	spec["_inbetweens"] = inb
	# Korekční (kombinační) tvary: dvojice morfů, které se navzájem ovlivňují (délka nosu × hřbet mění
	# profil nosu součinem, ne součtem). Pro každý kvadrant znamének δ = P(a,b) − P(a) − P(b) + P0;
	# váha = součin vah obou morfů (FaceMorphs.weights). Bez nich by lineární míchání blend shapes
	# ve hře ujelo od přesného tvaru o ~4 mm (měřeno v tests/test_head.gd).
	var cx: Array = []
	for pair in FaceMorphs.CORRECTIVE_PAIRS:
		for sa in [1, -1]:
			for sb in [1, -1]:
				var pab := positions(t, {pair[0]: float(sa), pair[1]: float(sb)})
				var pa := positions(t, {pair[0]: float(sa)})
				var pb := positions(t, {pair[1]: float(sb)})
				var dc := PackedVector3Array()
				dc.resize(p0.size())
				var mx := 0.0
				for i in p0.size():
					dc[i] = pab[i] - pa[i] - pb[i] + p0[i]
					mx = maxf(mx, dc[i].length())
				if mx > CX_MIN:
					var nm := FaceMorphs.corrective_name(pair[0], sa, pair[1], sb)
					out[nm] = dc
					cx.append(nm)
	spec["_correctives"] = cx
	return {"targets": out, "spec": spec}


## Váha kosti „neck“ (zbytek „head“) – jen krk pod čelistí.
static func neck_weight(rec: Array, p: Vector3) -> float:
	if rec[0] != "g":
		return 0.0
	return _smooth(1.585, 1.525, p.y) * (1.0 - _smooth(0.045, 0.075, p.z))


# ======================================================================================
# Stavba sítí pro Godot
# ======================================================================================
## Hladké normály (plošně vážené) pro danou část; f = [a,b,c] nebo [a,b,c,d] CCW zvenku.
## wpos = poloha, podle které se počítají VÁHY vyhlazení (vždy základ – audit Gemini běh 10b: váhy z polohy cíle
## by se mezi cíli lišily a stínování by při míchání blend shapes „skákalo“). Prázdné = pos.
static func _normals(pos: PackedVector3Array, faces: Array, wpos := PackedVector3Array()) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(pos.size())
	for f in faces:
		var idx: PackedInt32Array = f[2]
		var fn: Vector3
		if idx.size() == 4:
			fn = (pos[idx[2]] - pos[idx[0]]).cross(pos[idx[3]] - pos[idx[1]])
		else:
			fn = (pos[idx[1]] - pos[idx[0]]).cross(pos[idx[2]] - pos[idx[0]])
		for v in idx:
			n[v] += fn
	for i in n.size():
		var l := n[i].length()
		n[i] = n[i] / l if l > 1e-12 else Vector3.UP
	return _smooth_jaw_normals(pos, faces, n, wpos if wpos.size() == pos.size() else pos)


## Vizuální kontrola (běh 10): podél linie čelist–krk se paprsky z C sbíhají a vznikají úzké plochy, jejichž
## normály se prudce mění – ve stínování „zubaté“ světlé skvrny. Normály (ne polohy) se tam dvakrát vyhladí
## průměrem se sousedy (1-ring). Oblast: pod ústy / mimo koutky, nad krkem těla, mimo oči a uši.
## Stejný operátor běží pro základ i každý cíl blend shape, takže morfy zůstávají konzistentní.
static func _smooth_jaw_normals(pos: PackedVector3Array, faces: Array, n: PackedVector3Array, wpos: PackedVector3Array) -> PackedVector3Array:
	var nb: Array = []
	nb.resize(pos.size())
	for f in faces:
		var idx: PackedInt32Array = f[2]
		for a in idx.size():
			var va := idx[a]
			var vb := idx[(a + 1) % idx.size()]
			if nb[va] == null:
				nb[va] = PackedInt32Array()
			if nb[vb] == null:
				nb[vb] = PackedInt32Array()
			(nb[va] as PackedInt32Array).append(vb)
			(nb[vb] as PackedInt32Array).append(va)
	var w := PackedFloat32Array()
	w.resize(pos.size())
	for i in pos.size():
		var q := wpos[i]
		var ax := absf(q.x)
		var band := _smooth(1.49, 1.51, q.y) * (1.0 - _smooth(1.605, 1.62, q.y))
		var away_mouth := maxf(_smooth(1.588, 1.578, q.y), _smooth(0.032, 0.040, ax))
		var not_ear := 1.0 - _smooth(0.066, 0.072, ax) * _smooth(1.6, 1.615, q.y)
		w[i] = band * away_mouth * not_ear
	var cur := n.duplicate()
	# Krk je analytický eliptický válec: normála = gradient elipsy (platí i po škálování krku morfy –
	# směr gradientu se škálováním nemění). Odstraní svislé pruhy ve stínování z nepravidelných plošek krku.
	for i in pos.size():
		var q := pos[i]
		var qb := wpos[i]
		var wn := _smooth(1.556, 1.536, qb.y) * _smooth(1.4905, 1.4935, qb.y)

		if wn <= 0.0:
			continue
		var g := Vector3(q.x / (NECK_KX * NECK_KX), 0.0, (q.z - neck_zc(q.y)) / (NECK_KZ * NECK_KZ))
		if g.length_squared() < 1e-12:
			continue
		g = g.normalized()
		if g.dot(cur[i]) < 0.0:
			continue
		cur[i] = cur[i].lerp(g, wn).normalized()
	for _it in 2:
		var nxt := cur.duplicate()
		for i in pos.size():
			if w[i] <= 0.0 or nb[i] == null:
				continue
			var acc := Vector3.ZERO
			for j in (nb[i] as PackedInt32Array):
				acc += cur[j]
			var avg := (cur[i] + acc / float((nb[i] as PackedInt32Array).size())) * 0.5
			var m := cur[i].lerp(avg, w[i])
			var l := m.length()
			nxt[i] = m / l if l > 1e-12 else cur[i]
		cur = nxt
	return cur


## Celá data hlavy: topologie, základ, morfy. conform = okraj krku těla od CharacterAssembly.cut_body_neck()
## ({} = samostatná hlava bez švu – testy obličeje). Se švem přibudou blend shapes se jmény klíčů těla
## (spec["_body_keys"]) a data["seam"] pro váhy kostí a normály. Výpočet trvá desítky sekund (import).
static func build_data(conform: Dictionary = {}) -> Dictionary:
	var t := build_topology()
	_conform = {}
	var seam := {}
	if not conform.is_empty():
		seam = _seam_setup(t, positions(t, {}), conform)
		_conform = seam
	var p0 := positions(t, {})
	var m := morph_targets(t, p0)
	_conform = {}
	var targets: Dictionary = m["targets"]
	var spec: Dictionary = m["spec"]
	if not seam.is_empty():
		var bt := _seam_body_targets(seam, p0.size())
		for k in bt:
			targets[k] = bt[k]
		var bk: Array = bt.keys()
		bk.sort()
		spec["_body_keys"] = bk
	return {"topo": t, "base": p0, "targets": targets, "spec": spec, "seam": seam}


# ======================================================================================
# C3+ (běh 11) – šev hlava–tělo
# ======================================================================================
## Váha přilnutí podle výšky vrcholu v ZÁKLADU vůči výšce smyčky v jeho směru: 1 na smyčce a pod ní,
## (a ještě SEAM_HOLD nad ní), 0 od SEAM_BAND nad ní. Váha z polohy v základu (ne z polohy cíle) drží morfy lineární: výchylka
## obličejového morfu v pásu = (1 − w) × vlastní výchylka.
static func seam_weight(y: float, y_loop: float) -> float:
	return _smooth(y_loop + SEAM_BAND, y_loop + SEAM_HOLD, y)


## Váha morfů TĚLA na krku hlavy (tuk, svaly, stavba…): 1 do SEAM_HOLD nad smyčkou, pak pomalu k nule do
## SEAM_BODY_BAND – jen na trubici krku (vrcholy blízko poloměru okraje), ne na spodku čelisti a brady.
## Běh 12 (render svalnaté postavy): s váhou švu w (6,5 cm) se okraj krku rozšířil se svaly/tukem těla,
## ale horní krk ne → světlý „límec“. Silný krk má být silný celý.
static func body_weight(q: Vector3, y_loop: float, r_loop: float, cen: Vector2) -> float:
	var r := Vector2(float(q.x) - cen.x, float(q.z) - cen.y).length()
	var tube := _smooth(1.25 * r_loop, 1.08 * r_loop, r)
	return _smooth(y_loop + SEAM_BODY_BAND, y_loop + SEAM_HOLD, float(q.y)) * tube


## Poloměr eliptického krku hlavy u těla ve směru θ = atan2(x, z) (bez morfů).
static func neck_ellipse_r(theta: float) -> float:
	var sx := sin(theta) / (NECK_R * NECK_KX)
	var cz := cos(theta) / (NECK_R * NECK_KZ)
	return 1.0 / sqrt(sx * sx + cz * cz)


## Průsečík vodorovného paprsku ze středu smyčky ve směru θ s polygonem smyčky (rovina xz).
## Vrací [vzdálenost, index a, index b, f] – bod = lerp(loop[a], loop[b], f). Smyčka je uzavřená a seřazená podle úhlu.
static func loop_hit(loop: Array, center: Vector2, theta: float) -> Array:
	var dir := Vector2(sin(theta), cos(theta))
	var n := loop.size()
	for a in n:
		var b := (a + 1) % n
		var pa := Vector2(float(loop[a].x), float(loop[a].z)) - center
		var e := Vector2(float(loop[b].x), float(loop[b].z)) - center - pa
		var den := e.x * dir.y - dir.x * e.y
		if absf(den) < 1e-12:
			continue
		var s := (e.x * pa.y - pa.x * e.y) / den
		var f := (dir.x * pa.y - pa.x * dir.y) / den
		if s > 0.0 and f >= -1e-6 and f <= 1.0 + 1e-6:
			return [s, a, b, clampf(f, 0.0, 1.0)]
	return [0.0, 0, 0, 0.0]


## Připraví šev z poloh základu BEZ švu: pro každý vrchol mřížky v pásu váhu, cílový bod na smyčce
## (boční stěna: profil smyčky + SEAM_EPS ve výšce vrcholu; víčko: zmenšený profil v CAP_Y uvnitř trupu)
## a hranu smyčky (a, b, f) pro interpolaci morfů těla, vah kostí a normál.
static func _seam_setup(t: Topo, raw: PackedVector3Array, conform: Dictionary) -> Dictionary:
	var loop: Array = conform.get("loop", [])
	if loop.size() < 6:
		return {}
	var cen := Vector2.ZERO
	for q in loop:
		cen += Vector2(float(q.x), float(q.z))
	cen /= float(loop.size())
	var idx := PackedInt32Array()
	var ws := PackedFloat32Array()
	var tg := PackedVector3Array()
	var ha := PackedInt32Array()
	var hb := PackedInt32Array()
	var hf := PackedFloat32Array()
	var cri := PackedInt32Array()
	var crw := PackedFloat32Array()
	var hdy := PackedFloat32Array()
	var hwb := PackedFloat32Array()
	var n_loop := loop.size()
	var caps := 0
	# 1) výška smyčky ve směru každého vrcholu mřížky v dosahu švu
	var hits := {}
	for i in t.recipes.size():
		if t.recipes[i][0] != "g":
			continue
		var q := raw[i]
		if q.y > SEAM_Y_TOP:
			continue
		var th := atan2(float(q.x) - cen.x, float(q.z) - cen.y)
		var hit := loop_hit(loop, cen, th)
		if float(hit[0]) <= 0.0:
			return {}
		hits[i] = [th, hit, lerpf(float(loop[hit[1]].y), float(loop[hit[2]].y), float(hit[3]))]
	for i in t.recipes.size():
		if not hits.has(i):
			continue
		var q := raw[i]
		var th := float(hits[i][0])
		var hit: Array = hits[i][1]
		var rl := float(hit[0])
		var yl := float(hits[i][2])
		var w := seam_weight(q.y, yl)
		var wb := body_weight(q, yl, rl, cen)
		if w <= 0.0 and wb <= 0.0:
			continue
		var rel := Vector2(float(q.x), float(q.z) - neck_zc(q.y))
		var re := neck_ellipse_r(atan2(rel.x, rel.y))
		var tp := Vector3.ZERO
		var is_cap := q.y < NECK_CAP_Y + 0.0002 and rel.length() < 0.985 * re
		if is_cap:
			var rho := rel.length() / re
			tp = Vector3(cen.x + sin(th) * rl * CAP_SHRINK * rho, CAP_Y, cen.y + cos(th) * rl * CAP_SHRINK * rho)
			w = 1.0
			caps += 1
		var cw := cr_weights(float(hit[3]))
		var ci := PackedInt32Array([(int(hit[1]) - 1 + n_loop) % n_loop, int(hit[1]), int(hit[2]), (int(hit[2]) + 1) % n_loop])
		if not is_cap:
			# Boční stěna: bod na hladké křivce (Catmull-Rom) PROCHÁZEJÍCÍ vrcholy smyčky, ne na polygonu –
			# tětivy mezi vrcholy hlavy pak neřežou rohy polygonu těla (dřív hlava zapadla až o 2,7 mm pod okraj
			# těla u rohů smyčky). Křivka je lineární kombinací vrcholů smyčky → morfy těla zůstanou přesné.
			var cp := Vector2.ZERO
			for m in 4:
				cp += Vector2(float(loop[ci[m]].x), float(loop[ci[m]].z)) * cw[m]
			var rd := cp - cen
			var rr := rd.length()
			if rr > 1e-6:
				cp += rd / rr * SEAM_EPS
			tp = Vector3(cp.x, q.y, cp.y)
		idx.append(i)
		ws.append(w)
		tg.append(tp)
		ha.append(int(hit[1]))
		hb.append(int(hit[2]))
		hf.append(float(hit[3]))
		cri.append_array(ci)
		crw.append_array(cw)
		hdy.append(float(q.y) - yl)
		hwb.append(maxf(w, wb))
	return {"idx": idx, "w": ws, "target": tg, "a": ha, "b": hb, "f": hf, "cr_i": cri, "cr_w": crw, "dy": hdy, "wb": hwb, "center": cen, "caps": caps,
		"loop": loop, "loop_n": conform.get("normals", []), "bones": conform.get("bones", []),
		"weights": conform.get("weights", []), "deltas": conform.get("deltas", {}), "dnormals": conform.get("dnormals", {})}


## Váhy uniformního Catmull-Rom splajnu pro parametr t ∈ [0, 1] mezi body 1 a 2 (body 0..3). Součet 1.
static func cr_weights(t: float) -> PackedFloat32Array:
	var t2 := t * t
	var t3 := t2 * t
	return PackedFloat32Array([0.5 * (-t3 + 2.0 * t2 - t), 0.5 * (3.0 * t3 - 5.0 * t2 + 2.0),
		0.5 * (-3.0 * t3 + 4.0 * t2 + t), 0.5 * (t3 - t2)])


## Poslední krok positions(): p = lerp(p, cíl na smyčce, w). Cíl nezávisí na parametrech obličeje.
static func _apply_seam(p: PackedVector3Array) -> PackedVector3Array:
	var idx: PackedInt32Array = _conform["idx"]
	var ws: PackedFloat32Array = _conform["w"]
	var tg: PackedVector3Array = _conform["target"]
	for k in idx.size():
		p[idx[k]] = p[idx[k]].lerp(tg[k], ws[k])
	return p


## Blend shapes hlavy se jmény klíčů těla: výchylka = max(w, body_weight) × výchylka smyčky interpolovaná
## stejnými váhami Catmull-Rom jako poloha – okraj krku hlavy sleduje tuk, svaly, ramena… přesně jako okraj
## těla a nad ním se vliv pomalu vytrácí po celé trubici krku (SimVisual nastaví váhu z lp["body"]).
static func _seam_body_targets(seam: Dictionary, n: int) -> Dictionary:
	var out := {}
	var deltas: Dictionary = seam["deltas"]
	var keys: Array = deltas.keys()
	keys.sort()
	var idx: PackedInt32Array = seam["idx"]
	var ws: PackedFloat32Array = seam["w"]
	var ha: PackedInt32Array = seam["a"]
	var hb: PackedInt32Array = seam["b"]
	var hf: PackedFloat32Array = seam["f"]
	var cri: PackedInt32Array = seam.get("cr_i", PackedInt32Array())
	var crw: PackedFloat32Array = seam.get("cr_w", PackedFloat32Array())
	var has_cr := cri.size() == idx.size() * 4 and crw.size() == cri.size()
	var wbs: PackedFloat32Array = seam.get("wb", ws)
	if wbs.size() != idx.size():
		wbs = ws
	for key in keys:
		var dl: Array = deltas[key]
		var arr := PackedVector3Array()
		arr.resize(n)
		var mx := 0.0
		for k in idx.size():
			var dv := Vector3.ZERO
			if has_cr:
				# stejné váhy křivky jako pro polohu (víčko: posun víčka je jen přibližný, je uvnitř trupu)
				for m in 4:
					dv += (dl[cri[k * 4 + m]] as Vector3) * crw[k * 4 + m]
			else:
				dv = (dl[ha[k]] as Vector3).lerp(dl[hb[k]] as Vector3, hf[k])
			dv *= wbs[k]
			arr[idx[k]] = dv
			mx = maxf(mx, dv.length())
		if mx > 1e-5:
			out[String(key)] = arr
	return out


## Váhy kostí vrcholu v pásu švu: (1 − w) × vlastní (head/neck) + w × interpolace vah smyčky těla.
## Indexy = indexy bindů sdíleného Skinu těla (u hlavy, krku a hrudníku shodné s indexy kostí).
## Vrací max. 4 dvojice [kost, váha] seřazené sestupně, součet 1.
static func seam_skin(seam: Dictionary, k: int, head_bone: int, neck_bone: int, wn: float) -> Array:
	var w := float((seam["w"] as PackedFloat32Array)[k])
	var lb: Array = seam.get("bones", [])
	var lw: Array = seam.get("weights", [])
	if lb.is_empty() or lw.size() != lb.size():
		w = 0.0
	var acc := {}
	acc[head_bone] = (1.0 - wn) * (1.0 - w)
	acc[neck_bone] = float(acc.get(neck_bone, 0.0)) + wn * (1.0 - w)
	if w > 0.0:
		var f := float((seam["f"] as PackedFloat32Array)[k])
		var ends := [[int((seam["a"] as PackedInt32Array)[k]), 1.0 - f], [int((seam["b"] as PackedInt32Array)[k]), f]]
		for e in ends:
			var bb: PackedInt32Array = lb[e[0]]
			var bw: PackedFloat32Array = lw[e[0]]
			for j in mini(bb.size(), bw.size()):
				if bw[j] > 0.0:
					acc[bb[j]] = float(acc.get(bb[j], 0.0)) + w * float(e[1]) * bw[j]
	var l: Array = []
	for b in acc:
		if float(acc[b]) > 1e-6:
			l.append([int(b), float(acc[b])])
	l.sort_custom(func(x, y): return x[1] > y[1] or (x[1] == y[1] and x[0] < y[0]))
	l = l.slice(0, 4)
	if l.is_empty():
		return [[neck_bone, 1.0]]  # poškozená data těla (samé nulové váhy) – vrchol nesmí zůstat bez kosti (audit Gemini)
	var tot := 0.0
	for e in l:
		tot += float(e[1])
	for e in l:
		e[1] = float(e[1]) / tot
	return l


## Normály v pásu švu: od SEAM_NRM_BAND nad smyčkou plynule k normále těla na smyčce (základ, nebo cíl klíče těla),
## aby se stínování krku hlavy a těla na švu nelámalo.
static func _seam_normals(seam: Dictionary, n: PackedVector3Array, key: String) -> PackedVector3Array:
	if seam.is_empty():
		return n
	var ln: Array = seam.get("loop_n", [])
	if ln.size() != (seam["loop"] as Array).size():
		return n
	var dn: Dictionary = seam.get("dnormals", {})
	var src: Array = dn[key] if key != "" and dn.has(key) else ln
	var idx: PackedInt32Array = seam["idx"]
	var ws: PackedFloat32Array = seam["w"]
	var ha: PackedInt32Array = seam["a"]
	var hb: PackedInt32Array = seam["b"]
	var hf: PackedFloat32Array = seam["f"]
	var hdy: PackedFloat32Array = seam.get("dy", PackedFloat32Array())
	for k in idx.size():
		# Jen těsně u okraje (do SEAM_NRM_BAND nad smyčkou): s plným přilnutím 2 cm nad okraj (SEAM_HOLD) by
		# normály celého spodku krku převzaly sklon trapézu z okraje těla a krk by měl světlý „límec“ (běh 12, render).
		var s := _smooth(SEAM_NRM_BAND, 0.0, hdy[k]) if hdy.size() == idx.size() else _smooth(0.55, 1.0, ws[k])
		if s <= 0.0:
			continue
		var nl: Vector3 = (src[ha[k]] as Vector3).lerp(src[hb[k]] as Vector3, hf[k])
		if nl.length_squared() < 1e-12:
			continue  # protilehlé/nulové normály smyčky – ponechat vlastní normálu (audit Gemini)
		var nn: Vector3 = n[idx[k]].lerp(nl.normalized(), s)
		if nn.length_squared() > 1e-12:
			n[idx[k]] = nn.normalized()
	return n


## Čtyřúhelník v pásu švu rozdělit druhou úhlopříčkou (1–3 místo 0–2)? Ano, když je její střed dál od osy
## krku: rukáv krku je šikmá mřížka a úhlopříčka 0–2 tam místy vede vodorovně ve výšce okraje mezi vrcholy
## 30° od sebe – tětiva se prověsí pod okraj těla. Konvexnější dělení drží povrch venku.
static func _seam_alt_diagonal(seam: Dictionary, seam_k: Dictionary, q: PackedInt32Array, p0: PackedVector3Array) -> bool:
	if seam.is_empty() or q.size() != 4:
		return false
	for vi in q:
		if not seam_k.has(vi):
			return false
	var c: Vector2 = seam["center"]
	var m02 := (p0[q[0]] + p0[q[2]]) * 0.5
	var m13 := (p0[q[1]] + p0[q[3]]) * 0.5
	return Vector2(m13.x, m13.z).distance_to(c) > Vector2(m02.x, m02.z).distance_to(c) + 1e-6


## MeshInstance3D pro každou část × materiál (název uzlu „<skupina>__<část>__<materiál>“) s blend shapes
## (BLEND_SHAPE_MODE_NORMALIZED, absolutní cíle) a vahami kostí head/neck (indexy bindů = indexy kostí).
## Vrací {"instances": Array[MeshInstance3D], "stats": {...}}.
static func build_instances(data: Dictionary, head_bone: int, neck_bone: int) -> Dictionary:
	var t: Topo = data["topo"]
	var p0: PackedVector3Array = data["base"]
	var targets: Dictionary = data["targets"]
	var seam: Dictionary = data.get("seam", {})
	var seam_k := {}
	if not seam.is_empty():
		var sidx: PackedInt32Array = seam["idx"]
		for k in sidx.size():
			seam_k[sidx[k]] = k
	var instances: Array = []
	var tris := 0
	var verts := 0
	var key_count := {}
	for part in ["head", "eyes"]:
		var pf: Array = []
		for f in t.faces:
			if f[0] == part:
				pf.append(f)
		var used := {}
		for f in pf:
			for vi in (f[2] as PackedInt32Array):
				used[vi] = true
		# klíče, které tuto část opravdu mění
		var keys: Array = []
		for k in targets:
			var dd: PackedVector3Array = targets[k]
			var mx := 0.0
			for vi in used:
				mx = maxf(mx, dd[vi].length())
			if mx > 1e-5:
				keys.append(k)
		key_count[part] = keys.size()
		var n0 := _seam_normals(seam, _normals(p0, pf), "")
		var tgt_pos: Array = []
		var tgt_nrm: Array = []
		for k in keys:
			var tp := PackedVector3Array()
			tp.resize(p0.size())
			var dd: PackedVector3Array = targets[k]
			for i in p0.size():
				tp[i] = p0[i] + dd[i]
			tgt_pos.append(tp)
			tgt_nrm.append(_seam_normals(seam, _normals(tp, pf, p0), String(k)))
		var by_mat := {}
		for f in pf:
			if not by_mat.has(f[1]):
				by_mat[f[1]] = []
			by_mat[f[1]].append(f)
		for mat in by_mat:
			var remap := {}
			var idx := PackedInt32Array()
			for f in by_mat[mat]:
				var q: PackedInt32Array = f[2]
				var l: Array = []
				for vi in q:
					if not remap.has(vi):
						remap[vi] = remap.size()
					l.append(remap[vi])
				# CCW zvenku → CW pro Godot
				if l.size() == 4 and _seam_alt_diagonal(seam, seam_k, q, p0):
					idx.append_array(PackedInt32Array([l[1], l[3], l[2], l[1], l[0], l[3]]))
				elif l.size() == 4:
					idx.append_array(PackedInt32Array([l[0], l[2], l[1], l[0], l[3], l[2]]))
				else:
					idx.append_array(PackedInt32Array([l[0], l[2], l[1]]))
			var inv := PackedInt32Array()
			inv.resize(remap.size())
			for vi in remap:
				inv[remap[vi]] = vi
			var sv := PackedVector3Array()
			var sn := PackedVector3Array()
			var sb := PackedInt32Array()
			var sw := PackedFloat32Array()
			sv.resize(inv.size())
			sn.resize(inv.size())
			sb.resize(inv.size() * 4)
			sw.resize(inv.size() * 4)
			for i in inv.size():
				var gi := inv[i]
				sv[i] = p0[gi]
				sn[i] = n0[gi]
				var wn := neck_weight(t.recipes[gi], p0[gi])
				var bw: Array = [[head_bone, 1.0 - wn], [neck_bone, wn]]
				if seam_k.has(gi):
					bw = seam_skin(seam, seam_k[gi], head_bone, neck_bone, wn)
				for j in 4:
					sb[i * 4 + j] = int(bw[j][0]) if j < bw.size() else 0
					sw[i * 4 + j] = float(bw[j][1]) if j < bw.size() else 0.0
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = sv
			arrays[Mesh.ARRAY_NORMAL] = sn
			arrays[Mesh.ARRAY_INDEX] = idx
			arrays[Mesh.ARRAY_BONES] = sb
			arrays[Mesh.ARRAY_WEIGHTS] = sw
			var blend: Array = []
			for ki in keys.size():
				var tp: PackedVector3Array = tgt_pos[ki]
				var tn: PackedVector3Array = tgt_nrm[ki]
				var bv := PackedVector3Array()
				var bn := PackedVector3Array()
				bv.resize(inv.size())
				bn.resize(inv.size())
				for i in inv.size():
					bv[i] = tp[inv[i]]
					bn[i] = tn[inv[i]]
				var ba := []
				ba.resize(Mesh.ARRAY_MAX)
				ba[Mesh.ARRAY_VERTEX] = bv
				ba[Mesh.ARRAY_NORMAL] = bn
				blend.append(ba)
			var am := ArrayMesh.new()
			if not keys.is_empty():
				am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
				for k in keys:
					am.add_blend_shape(StringName(k))
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
			var md: Dictionary = MATERIALS[mat]
			var smat := StandardMaterial3D.new()
			smat.resource_name = String(md["name"])
			smat.albedo_color = Color(md["color"][0], md["color"][1], md["color"][2])
			smat.roughness = float(md["rough"])
			smat.metallic = float(md["metal"])
			am.surface_set_material(0, smat)
			var nm := "%s__%s__%s" % [part if part == "head" else "eyes", "face" if part == "head" else "eyeballs", md["name"]]
			am.resource_name = nm
			var mi := MeshInstance3D.new()
			mi.name = nm
			mi.mesh = am
			instances.append(mi)
			tris += idx.size() / 3
			verts += inv.size()
	return {"instances": instances, "stats": {"tris": tris, "verts": verts, "keys": key_count,
		"morphs": targets.size(), "topo_verts": t.recipes.size(), "faces": t.faces.size()}}
