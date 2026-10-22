extends RefCounted
## HairBuilder (C4b) – procedurální vlasy, obočí a vousy jako KARTY (pásky s texturou pramenů), trubice
## (copánky, dredy, cornrows) a skořepiny (na ježka, strany undercutu, afro). Běží v Godotu nad skutečnou
## sítí kůže hlavy z character.glb (HairRig.source()), takže kořeny vždy leží na hlavě, kterou hra kreslí.
##
## Zásady:
##  - deterministické: pevný seed na účes (ne na postavu ani jméno) → stejná síť na všech peerech,
##  - účes je nezávislý na rodu, identitě i těle; ustupující vlasová linie, šedivění a hustota obočí/vousů
##    se NEřeší geometrií, ale atributy vrcholů (CUSTOM0) a uniformy shaderu (shaders/hair.gdshader), takže
##    jedna sdílená síť pokryje všechny postavy se stejným účesem,
##  - kolize: radiální mapa hlavy (azimut × elevace od středu C) a válcová mapa krku/trupu (tělo + tričko,
##    bez paží), dlouhé vlasy se opírají o ramena a padají po zádech nebo před rameny,
##  - obočí a vousy se promítají přesně na trojúhelníky kůže (prostorový hash), ne přes mapu.
##
## Výstup build(): {"pos", "nrm", "tan" (4/vrchol), "uv", "c0" (CUSTOM0 RGBA float: x = náhoda pramene
## nebo okraj skořepiny, y = pořadí ústupu vlasové linie, z = vrstva 0..1, w = druh/8), "idx", "stats"}.
## Druhy (w × 8): 0 karta, 1 skořepina, 2 copánek, 3 dred, 4 afro skořepina, 5 plná (drdol, gumička).
## Souřadnice: model (Y nahoru, +Z dopředu), výchozí postava 1,78 m – stejné jako hlava v GLB.

const C := Vector3(0.0, 1.69, -0.005)
## Vír na temeni (mírně vpravo a vzadu) – odtud vlasy přirozeně padají.
const WHORL := Vector3(0.012, 1.776, -0.055)
## Osa trupu pro válcovou mapu.
const TZ := 0.0
const KIND_CARD := 0
const KIND_SHELL := 1
const KIND_BRAID := 2
const KIND_LOC := 3
const KIND_AFRO := 4
const KIND_SOLID := 5

## Vlasová linie: minimální elevace kořene (stupně) podle |azimutu| (0 = vpředu, 180 = vzadu). Kalibrace na
## hlavě z GLB (běh 14): čelo y ≈ 1,742 (6 cm nad obočím), kotlety před uchem dolů k ~1,655, nad uchem
## těsně nad horním okrajem ucha (1,693), za uchem dolů, týl ~1,60.
const HAIRLINE := [[0.0, 31.0], [25.0, 30.5], [45.0, 26.0], [58.0, 16.0], [66.0, -2.0], [70.0, -22.0],
	[75.0, -24.0], [78.0, 4.0], [82.0, 9.0], [106.0, 9.0], [114.0, -15.0], [130.0, -35.0], [150.0, -48.0],
	[180.0, -55.0]]
## Ústup vlasové linie při hairline = 1 (stupně elevace navíc): spánky víc než střed čela, do stran slábne.
const RECEDE := [[0.0, 40.0], [38.0, 52.0], [58.0, 30.0], [75.0, 0.0], [180.0, 0.0]]
## Řídnutí temene: střed (azimut, elevace) a poloměr (stupně) při hairline = 1.
const CROWN_AZ := 180.0
const CROWN_EL := 62.0
const CROWN_R := 38.0
## Pořadí ústupu pro vlasy, které nikdy nezmizí (strany a týl).
const RANK_NEVER := 4.0

## Účesy. Klíče: flow (whorl | part | back | pull), part_x, len [min, max] (m), cut_y (vodorovný střih),
## bangs_y (ofina vpředu), lift (odklon od hlavy na začátku), stiff (0 = jen gravitace, 1 = drží směr),
## vol (objem: odsazení horní vrstvy), width (šířka karty), spacing (rozestup kořenů), layers, seg (délka
## segmentu), curl_r / curl_p (kadeř: poloměr a perioda šroubovice), wave_a / wave_p (vlna), shell
## (odsazení skořepin), shell_max_el (skořepina jen pod touto elevací), min_el (karty jen nad elevací),
## front_frac (podíl bočních pramenů, které padají před rameny), seed.
const STYLES := {
	"holy": {},
	"strih_nakratko": {"shell": [0.0010, 0.0026], "seed": 11},
	"kratke": {"flow": "part", "part_x": 0.03, "len": [0.035, 0.055], "lift": 0.32, "stiff": 0.9, "vol": 0.007,
		"width": 0.014, "spacing": 0.0125, "layers": 3, "seg": 0.011, "shell": [0.0010], "seed": 12},
	"kratke_kudrny": {"flow": "whorl", "len": [0.028, 0.04], "lift": 0.9, "stiff": 0.94, "vol": 0.012,
		"width": 0.010, "spacing": 0.0115, "layers": 3, "seg": 0.0045, "curl_r": 0.0035, "curl_p": 0.011,
		"shell": [0.0010, 0.0045], "seed": 13},
	"undercut": {"flow": "back", "len": [0.075, 0.10], "lift": 0.25, "stiff": 0.8, "vol": 0.010, "width": 0.015,
		"spacing": 0.0115, "layers": 3, "seg": 0.014, "min_el": 20.0, "shell": [0.0010, 0.0024],
		"shell_max_el": 26.0, "seed": 14},
	"stredni": {"flow": "part", "part_x": 0.022, "len": [0.24, 0.28], "cut_y": 1.47, "lift": 0.25, "stiff": 0.55,
		"vol": 0.009, "width": 0.018, "spacing": 0.0135, "layers": 3, "seg": 0.02, "front_frac": 0.4,
		"shell": [0.0010], "seed": 15},
	"mikado": {"flow": "part", "part_x": 0.0, "len": [0.2, 0.22], "cut_y": 1.585, "bangs_y": 1.705, "lift": 0.3,
		"stiff": 0.6, "vol": 0.01, "width": 0.018, "spacing": 0.0125, "layers": 3, "seg": 0.016,
		"front_frac": 0.6, "shell": [0.0010], "seed": 16},
	"dlouhe_rovne": {"flow": "part", "part_x": 0.0, "len": [0.5, 0.56], "cut_y": 1.25, "lift": 0.2, "stiff": 0.5,
		"vol": 0.008, "width": 0.02, "spacing": 0.0145, "layers": 3, "seg": 0.026, "front_frac": 0.35,
		"shell": [0.0010], "seed": 17},
	"dlouhe_vlnite": {"flow": "part", "part_x": -0.02, "len": [0.46, 0.52], "cut_y": 1.29, "lift": 0.25,
		"stiff": 0.5, "vol": 0.011, "width": 0.02, "spacing": 0.0145, "layers": 3, "seg": 0.022, "wave_a": 0.009,
		"wave_p": 0.075, "front_frac": 0.35, "shell": [0.0010], "seed": 18},
	"kudrnate": {"flow": "part", "part_x": 0.012, "len": [0.3, 0.36], "cut_y": 1.40, "lift": 0.5, "stiff": 0.6,
		"vol": 0.02, "width": 0.016, "spacing": 0.0165, "layers": 2, "seg": 0.009, "curl_r": 0.0075,
		"curl_p": 0.04, "front_frac": 0.45, "shell": [0.0010, 0.006], "seed": 19},
	"afro": {"afro": 0.06, "shells": 7, "shell": [0.0010], "seed": 20},
	"copanky": {"tube": KIND_BRAID, "tube_r": 0.0036, "spacing": 0.02, "cut_y": 1.22, "len": [0.62, 0.66],
		"stiff": 0.5, "lift": 0.15, "front_frac": 0.3, "seg": 0.03, "shell": [0.0010], "seed": 21},
	"cornrows": {"rows": 11, "tube_r": 0.0042, "shell": [0.0008], "seed": 22},
	"dredy": {"tube": KIND_LOC, "tube_r": 0.0058, "spacing": 0.023, "cut_y": 1.30, "len": [0.5, 0.55],
		"stiff": 0.5, "lift": 0.2, "front_frac": 0.3, "seg": 0.022, "shell": [0.0010], "seed": 23},
	"drdol": {"pull": Vector3(0.0, 1.752, -0.09), "bun_r": 0.033, "width": 0.016, "spacing": 0.0125,
		"layers": 2, "shell": [0.0010], "seed": 24},
	"culik": {"pull": Vector3(0.0, 1.668, -0.112), "tail_len": 0.3, "tail_cut": 1.37, "width": 0.016,
		"spacing": 0.0125, "layers": 2, "shell": [0.0010], "seed": 25},
}

## Obočí: [tloušťka (m), výška oblouku (m), vnitřní začátek |x| (m), srostlé] – stejné tvary jako shader kůže
## (SkinLayers.BROW_SHAPES), aby karty seděly na namalovaném podkladu; + počet karet na stranu.
const BROWS := {
	"prirozene": [0.0042, 0.0035, 0.0125, 0.0, 70], "huste": [0.0058, 0.0030, 0.0115, 0.0, 95],
	"tenke": [0.0022, 0.0045, 0.0135, 0.0, 40], "rovne": [0.0042, 0.0008, 0.0125, 0.0, 70],
	"oblouk": [0.0038, 0.0065, 0.0125, 0.0, 65], "srostle": [0.0048, 0.0030, 0.0110, 1.0, 85],
}
## Výchozí poloha oka a úst (SkinLayers EYE / MOUTH, klidová poloha).
const EYE := Vector3(0.0318, 1.6685, 0.0708)
const EYE_W := 0.0142
const MOUTH := Vector3(0.0, 1.6035, 0.0245)

## Vousy: zóny [knír, brada, tváře a čelist (+ pod bradou), licousy] (jako SkinLayers.FACIAL) a délka (m).
const BEARDS := {
	"zadne": [], "strniste": [],
	"knir": [[1, 0, 0, 0], 0.013], "bradka": [[0, 1, 0, 0], 0.02], "kozi_bradka": [[1, 1, 0, 0], 0.022],
	"plnovous": [[1, 1, 1, 1], 0.03], "licousy": [[0, 0, 1, 1], 0.02],
}

## Obličej, do kterého nesmí padat prameny (oči, nos, ústa): pramen, který by sem padl, se odsune na tvář
## na straně svého kořene (vlasy rámují obličej, nepadají přes oči). Ofina (bangs_y) končí nad FACE_Y1.
const FACE_X := 0.074  # osa pramene; okraj karty (± šířka/2) a vlna zůstanou mimo oči
const FACE_Y0 := 1.55
const FACE_Y1 := 1.715  # nad obočím (oko 1,6685, obočí ~1,69); ofina má vlastní mez bangs_y
const FACE_Z := 0.03
## Náklon gravitace přes ramena plně nad LEAN_Y1, pod LEAN_Y0 už žádný (ramena ~1,45–1,50 m).
const LEAN_Y0 := 1.38
const LEAN_Y1 := 1.50

## Rozpočty trojúhelníků (test_hair).
const BUDGET_SCALP := 26000
const BUDGET_BROWS := 1200
const BUDGET_BEARD := 9000


# ======================================================================================
# Pomocné funkce
# ======================================================================================
static func _table(t: Array, x: float) -> float:
	if x <= float(t[0][0]):
		return float(t[0][1])
	for i in range(1, t.size()):
		if x <= float(t[i][0]):
			var a: Array = t[i - 1]
			var b: Array = t[i]
			var k := (x - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), k)
	return float(t[t.size() - 1][1])


## Azimut (stupně, 0 vpředu, ±180 vzadu) a elevace (stupně) bodu vůči středu hlavy.
static func az_el(p: Vector3) -> Vector2:
	var q := p - C
	var h := Vector2(q.x, q.z).length()
	return Vector2(rad_to_deg(atan2(q.x, q.z)), rad_to_deg(atan2(q.y, h)))


static func hairline_el(az: float) -> float:
	return _table(HAIRLINE, absf(az))


## Úhlová vzdálenost dvou směrů daných azimutem a elevací (stupně).
static func _ang(az1: float, el1: float, az2: float, el2: float) -> float:
	var a := Vector3(cos(deg_to_rad(el1)) * sin(deg_to_rad(az1)), sin(deg_to_rad(el1)), cos(deg_to_rad(el1)) * cos(deg_to_rad(az1)))
	var b := Vector3(cos(deg_to_rad(el2)) * sin(deg_to_rad(az2)), sin(deg_to_rad(el2)), cos(deg_to_rad(el2)) * cos(deg_to_rad(az2)))
	return rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))


## Pořadí ústupu: nejmenší hodnota uniformy `hairline`, při které tento kořen zmizí (0 = hned, 4 = nikdy).
## Ustupují spánky a čelo (vlasová linie se zvedá) a řídne temeno; strany a týl zůstávají.
static func recession_rank(p: Vector3) -> float:
	var ae := az_el(p)
	var r := RANK_NEVER
	var rec := _table(RECEDE, absf(ae.x))
	if rec > 0.5:
		r = minf(r, maxf(ae.y - hairline_el(ae.x), 0.0) / rec)
	r = minf(r, _ang(ae.x, ae.y, CROWN_AZ, CROWN_EL) / CROWN_R)
	return clampf(r, 0.0, RANK_NEVER)


## Je bod uvnitř vlasové části hlavy? margin (stupně) > 0 zužuje.
static func in_scalp(p: Vector3, margin := 0.0) -> bool:
	var ae := az_el(p)
	return ae.y >= hairline_el(ae.x) + margin


static func _hash(i: int) -> float:
	var x := (i * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


# ======================================================================================
# Kolizní mapy
# ======================================================================================
const NA := 72
const NE := 36
const TA := 72
const TY0 := 0.90
const TY1 := 1.62
const TDY := 0.01


## Radiální mapa hlavy: max. vzdálenost vrcholu kůže od C v binu (azimut × elevace), prázdné biny doplněné.
static func head_map(hp: PackedVector3Array) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(NA * NE)
	m.fill(-1.0)
	for p in hp:
		var ae := az_el(p)
		var ai := clampi(int(floor((ae.x + 180.0) / 360.0 * NA)), 0, NA - 1)
		var ei := clampi(int(floor((ae.y + 90.0) / 180.0 * NE)), 0, NE - 1)
		m[ei * NA + ai] = maxf(m[ei * NA + ai], (p - C).length())
	return _fill(m, NA, NE, true)


## Válcová mapa trupu: max. vodorovná vzdálenost od osy (x = 0, z = TZ) v binu (úhel × výška); paže vynechané.
static func torso_map(pts: Array) -> PackedFloat32Array:
	var ny := int(round((TY1 - TY0) / TDY)) + 1
	var m := PackedFloat32Array()
	m.resize(TA * ny)
	m.fill(-1.0)
	for arr in pts:
		for p in (arr as PackedVector3Array):
			if p.y < TY0 - 0.01 or p.y > TY1 + 0.01:
				continue
			if absf(p.x) > 0.165 and p.y < 1.38:
				continue
			var a := atan2(p.x, p.z - TZ)
			var ai := clampi(int(floor((a + PI) / TAU * TA)), 0, TA - 1)
			var yi := clampi(int(round((p.y - TY0) / TDY)), 0, ny - 1)
			m[yi * TA + ai] = maxf(m[yi * TA + ai], Vector2(p.x, p.z - TZ).length())
	return _fill(m, TA, ny, false)


## Doplní prázdné biny (−1) průměrem sousedů (azimut je cyklický).
static func _fill(m: PackedFloat32Array, w: int, h: int, sphere: bool) -> PackedFloat32Array:
	for _it in 64:
		var empty := 0
		var out := m.duplicate()
		for y in h:
			for x in w:
				if m[y * w + x] >= 0.0:
					continue
				var s := 0.0
				var n := 0
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var yy: int = y + d[1]
					if yy < 0 or yy >= h:
						continue
					var xx: int = (x + d[0] + w) % w
					if m[yy * w + xx] >= 0.0:
						s += m[yy * w + xx]
						n += 1
				if n > 0:
					out[y * w + x] = s / n
				else:
					empty += 1
		m = out
		if empty == 0:
			break
	for i in m.size():
		if m[i] < 0.0:
			m[i] = 0.0
	return m


static func head_r(map: PackedFloat32Array, dir: Vector3) -> float:
	var h := Vector2(dir.x, dir.z).length()
	var az := rad_to_deg(atan2(dir.x, dir.z))
	var el := rad_to_deg(atan2(dir.y, h))
	var fx := (az + 180.0) / 360.0 * NA - 0.5
	var fy := clampf((el + 90.0) / 180.0 * NE - 0.5, 0.0, NE - 1.0)
	var x0 := int(floor(fx))
	var tx := fx - x0
	var y0 := int(floor(fy))
	var ty := fy - y0
	var y1 := mini(y0 + 1, NE - 1)
	var xa := (x0 + NA) % NA
	var xb := (x0 + 1 + NA) % NA
	var a := lerpf(map[y0 * NA + xa], map[y0 * NA + xb], tx)
	var b := lerpf(map[y1 * NA + xa], map[y1 * NA + xb], tx)
	return lerpf(a, b, ty)


static func torso_r(map: PackedFloat32Array, ang: float, y: float) -> float:
	var ny := map.size() / TA
	var fx := (ang + PI) / TAU * TA - 0.5
	var fy := clampf((y - TY0) / TDY, 0.0, ny - 1.0)
	var x0 := int(floor(fx))
	var tx := fx - x0
	var y0 := int(floor(fy))
	var ty := fy - y0
	var y1 := mini(y0 + 1, ny - 1)
	var xa := (x0 + TA) % TA
	var xb := (x0 + 1 + TA) % TA
	return lerpf(lerpf(map[y0 * TA + xa], map[y0 * TA + xb], tx), lerpf(map[y1 * TA + xa], map[y1 * TA + xb], tx), ty)


## Vytlačí bod z hlavy (radiálně od C) a z trupu (po gradientu válcové mapy – na ramenou nahoru, na zádech ven).
static func collide(ctx: Dictionary, p: Vector3, off: float) -> Vector3:
	var q := p - C
	var r := q.length()
	if r > 1e-6:
		var R := head_r(ctx["hmap"], q / r) + off
		if r < R:
			p = C + q / r * R
	if p.y < TY1 and p.y > TY0:
		var tm: PackedFloat32Array = ctx["tmap"]
		for _i in 4:
			var h := Vector2(p.x, p.z - TZ)
			var rh := h.length()
			if rh < 1e-5:
				break
			var ang := atan2(p.x, p.z - TZ)
			var R := torso_r(tm, ang, p.y) + off
			var f := rh - R
			if f >= 0.0:
				break
			var dr := (torso_r(tm, ang, p.y + 0.01) - torso_r(tm, ang, p.y - 0.01)) / 0.02
			var radial := Vector3(h.x / rh, 0.0, h.y / rh)
			var n := (radial - Vector3.UP * dr).normalized()
			var along := n.dot(radial)
			p += n * (-f) / maxf(along, 0.25) * 0.8 if along > 0.25 else n * (-f)
	return p


# ======================================================================================
# Přesná projekce na kůži (obočí, vousy)
# ======================================================================================
const PCELL := 0.012


static func _tri_hash(ctx: Dictionary) -> Dictionary:
	if ctx.has("thash"):
		return ctx["thash"]
	var hp: PackedVector3Array = ctx["hp"]
	var hi: PackedInt32Array = ctx["hi"]
	var hs := {}
	for t in range(0, hi.size(), 3):
		var a := hp[hi[t]]
		var b := hp[hi[t + 1]]
		var c := hp[hi[t + 2]]
		var lo := a.min(b).min(c)
		var up := a.max(b).max(c)
		for x in range(int(floor(lo.x / PCELL)), int(floor(up.x / PCELL)) + 1):
			for y in range(int(floor(lo.y / PCELL)), int(floor(up.y / PCELL)) + 1):
				for z in range(int(floor(lo.z / PCELL)), int(floor(up.z / PCELL)) + 1):
					var k := Vector3i(x, y, z)
					if not hs.has(k):
						hs[k] = PackedInt32Array()
					var arr: PackedInt32Array = hs[k]
					arr.append(t)
					hs[k] = arr
	ctx["thash"] = hs
	return hs


## Nejbližší bod na trojúhelníku (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
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
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## Nejbližší bod kůže a interpolovaná normála: {"p", "n", "d"} (d = vzdálenost) nebo {} mimo dosah.
static func project(ctx: Dictionary, p: Vector3) -> Dictionary:
	var hs := _tri_hash(ctx)
	var hp: PackedVector3Array = ctx["hp"]
	var hn: PackedVector3Array = ctx["hn"]
	var hi: PackedInt32Array = ctx["hi"]
	var k0 := Vector3i(int(floor(p.x / PCELL)), int(floor(p.y / PCELL)), int(floor(p.z / PCELL)))
	var best := 1e9
	var bp := Vector3.ZERO
	var bt := -1
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var arr = hs.get(k0 + Vector3i(dx, dy, dz))
				if arr == null:
					continue
				for t in (arr as PackedInt32Array):
					var q := _closest_tri(p, hp[hi[t]], hp[hi[t + 1]], hp[hi[t + 2]])
					var d := p.distance_squared_to(q)
					if d < best:
						best = d
						bp = q
						bt = t
	if bt < 0:
		return {}
	var a := hp[hi[bt]]
	var b := hp[hi[bt + 1]]
	var c := hp[hi[bt + 2]]
	var fn := (b - a).cross(c - a)
	var area := fn.length()
	var n := Vector3.ZERO
	if area > 1e-12:
		var wa := (b - bp).cross(c - bp).length() / area
		var wb := (c - bp).cross(a - bp).length() / area
		var wc := 1.0 - wa - wb
		n = (hn[hi[bt]] * wa + hn[hi[bt + 1]] * wb + hn[hi[bt + 2]] * wc).normalized()
	if n == Vector3.ZERO:
		n = (bp - C).normalized()
	return {"p": bp, "n": n, "d": sqrt(best)}


## Drží bod nad kůží: aspoň `off` nad nejbližším bodem ve směru normály.
static func keep_above(ctx: Dictionary, p: Vector3, off: float) -> Vector3:
	var pr := project(ctx, p)
	if pr.is_empty():
		return p
	var n: Vector3 = pr["n"]
	var h := (p - (pr["p"] as Vector3)).dot(n)
	if h < off:
		p += n * (off - h)
	return p


# ======================================================================================
# Vzorkování kořenů (Poissonův disk po trojúhelnících kůže)
# ======================================================================================
## mask: Callable(p: Vector3) -> bool. Vrací pole {"p", "n"} (deterministicky podle rng).
static func sample(ctx: Dictionary, spacing: float, rng: RandomNumberGenerator, mask: Callable, oversample := 7.0) -> Array:
	var hp: PackedVector3Array = ctx["hp"]
	var hn: PackedVector3Array = ctx["hn"]
	var hi: PackedInt32Array = ctx["hi"]
	var ear: PackedByteArray = ctx["ear"]
	var cum := PackedFloat64Array()
	var tris := PackedInt32Array()
	var tot := 0.0
	for t in range(0, hi.size(), 3):
		if ear[hi[t]] == 1 or ear[hi[t + 1]] == 1 or ear[hi[t + 2]] == 1:
			continue
		var a := hp[hi[t]]
		var b := hp[hi[t + 1]]
		var c := hp[hi[t + 2]]
		if not (mask.call(a) or mask.call(b) or mask.call(c)):
			continue
		tot += 0.5 * (b - a).cross(c - a).length()
		cum.append(tot)
		tris.append(t)
	var out: Array = []
	if tris.is_empty():
		return out
	var n_cand := int(tot / (spacing * spacing) * oversample)
	var grid := {}
	var s2 := spacing * spacing
	for _i in n_cand:
		var x := rng.randf() * tot
		var lo := 0
		var hi_i := cum.size() - 1
		while lo < hi_i:
			var mid := (lo + hi_i) >> 1
			if cum[mid] < x:
				lo = mid + 1
			else:
				hi_i = mid
		var t := tris[lo]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var p := hp[hi[t]] * (1.0 - u - v) + hp[hi[t + 1]] * u + hp[hi[t + 2]] * v
		if not mask.call(p):
			continue
		var k := Vector3i(int(floor(p.x / spacing)), int(floor(p.y / spacing)), int(floor(p.z / spacing)))
		var ok := true
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var cell = grid.get(k + Vector3i(dx, dy, dz))
					if cell == null:
						continue
					for q in (cell as Array):
						if p.distance_squared_to(q) < s2:
							ok = false
							break
					if not ok:
						break
				if not ok:
					break
			if not ok:
				break
		if not ok:
			continue
		if not grid.has(k):
			grid[k] = []
		(grid[k] as Array).append(p)
		var n := (hn[hi[t]] * (1.0 - u - v) + hn[hi[t + 1]] * u + hn[hi[t + 2]] * v).normalized()
		out.append({"p": p, "n": n})
	return out


# ======================================================================================
# Geometrie: karty, trubice, skořepiny
# ======================================================================================
## Rozestavěná geometrie (pole jako členy objektu: Packed*Array ve slovníku by se při append kopírovalo).
class Geo:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var stats := {"cards": 0, "tubes": 0, "shell_tris": 0}

	func to_dict() -> Dictionary:
		return {"pos": pos, "nrm": nrm, "tan": tan, "uv": uv, "c0": c0, "idx": idx, "stats": stats}


static func _vert(g: Geo, p: Vector3, n: Vector3, t: Vector3, uv: Vector2, c: Vector4) -> int:
	var i: int = g.pos.size()
	g.pos.append(p)
	g.nrm.append(n)
	g.tan.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
	g.uv.append(uv)
	g.c0.append_array(PackedFloat32Array([c.x, c.y, c.z, c.w]))
	return i


static func _tri(g: Geo, a: int, b: int, c: int) -> void:
	g.idx.append_array(PackedInt32Array([a, b, c]))


## Směr „ven“ pro orientaci karty: od středu hlavy, pod hlavou od osy trupu.
static func _out_dir(p: Vector3) -> Vector3:
	var hd := (p - C).normalized()
	var td := Vector3(p.x, 0.0, p.z - TZ)
	td = td.normalized() if td.length() > 1e-5 else Vector3.BACK
	var k := clampf((1.6 - p.y) / 0.08, 0.0, 1.0)
	var o := hd.lerp(td, k)
	return o.normalized() if o.length() > 1e-5 else Vector3.UP


## Páska podél polyline: šířky w[i]; UV x 0/1 přes šířku, y 0 kořen … 1 konec.
static func ribbon(g: Geo, pts: PackedVector3Array, widths: PackedFloat32Array, attr: Vector4) -> void:
	var n := pts.size()
	if n < 2:
		return
	var prev_w := Vector3.ZERO
	var base: int = g.pos.size()
	var total := 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
		acc.append(total)
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
		t = t.normalized() if t.length() > 1e-7 else Vector3.DOWN
		var o := _out_dir(pts[i])
		var w := t.cross(o)
		if w.length() < 1e-3:
			w = t.cross(Vector3.FORWARD)
		w = w.normalized()
		if prev_w != Vector3.ZERO and w.dot(prev_w) < 0.0:
			w = -w
		prev_w = w
		var nn := w.cross(t).normalized()
		if nn.dot(o) < 0.0:
			nn = -nn
		var v := acc[i] / maxf(total, 1e-6)
		_vert(g, pts[i] - w * widths[i] * 0.5, nn, t, Vector2(0.0, v), attr)
		_vert(g, pts[i] + w * widths[i] * 0.5, nn, t, Vector2(1.0, v), attr)
	for i in n - 1:
		var a := base + i * 2
		_tri(g, a, a + 2, a + 1)
		_tri(g, a + 1, a + 2, a + 3)
	g.stats["cards"] += 1


## Trubice podél polyline (paralelní přenos rámce): k stran, poloměry r[i]; UV x = obvod 0..1, y = délka v m.
static func tube(g: Geo, pts: PackedVector3Array, radii: PackedFloat32Array, k: int, attr: Vector4, cap := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var base: int = g.pos.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := t0.cross(ref).normalized()
	var s := 0.0
	var prev_t := t0
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
			var ax := prev_t.cross(t)
			if ax.length() > 1e-6:
				u = u.rotated(ax.normalized(), prev_t.angle_to(t))
			u = (u - t * u.dot(t)).normalized()
		prev_t = t
		var b := t.cross(u)
		for j in k + 1:
			var a := TAU * float(j) / k
			var d := u * cos(a) + b * sin(a)
			_vert(g, pts[i] + d * radii[i], d, t, Vector2(float(j) / k, s), attr)
	for i in n - 1:
		for j in k:
			var a := base + i * (k + 1) + j
			var c := a + k + 1
			_tri(g, a, c, a + 1)
			_tri(g, a + 1, c, c + 1)
	if cap:
		var tip := _vert(g, pts[n - 1] + prev_t * radii[n - 1] * 0.6, prev_t, prev_t, Vector2(0.5, s + radii[n - 1]), attr)
		var last := base + (n - 1) * (k + 1)
		for j in k:
			_tri(g, last + j, tip, last + j + 1)
	g.stats["tubes"] += 1


## Skořepina: trojúhelníky kůže, kterých se dotýká vlasová část, posunuté o off po normále.
## CUSTOM0.x = okraj (0,5 = vlasová linie, plynule), y = pořadí ústupu, z = vrstva, w = druh.
static func shell(g: Geo, ctx: Dictionary, off: float, layer: float, kind: int, max_el := 999.0, displace := 0.0, seed_i := 0) -> void:
	var hp: PackedVector3Array = ctx["hp"]
	var hn: PackedVector3Array = ctx["hn"]
	var hi: PackedInt32Array = ctx["hi"]
	var ear: PackedByteArray = ctx["ear"]
	var remap := {}
	var tris := 0
	for t in range(0, hi.size(), 3):
		var any := false
		var all_ear := true
		for j in 3:
			var p := hp[hi[t + j]]
			var ae := az_el(p)
			if ae.y > hairline_el(ae.x) - 4.0 and ae.y < max_el + 4.0:
				any = true
			if ear[hi[t + j]] == 0:
				all_ear = false
		if not any or all_ear:
			continue
		var ids: Array = []
		for j in 3:
			var vi := hi[t + j]
			if not remap.has(vi):
				var p := hp[vi]
				var ae := az_el(p)
				var edge := clampf(0.5 + (ae.y - hairline_el(ae.x)) / 8.0, 0.0, 1.0)
				if max_el < 900.0:
					edge = minf(edge, clampf(0.5 + (max_el - ae.y) / 6.0, 0.0, 1.0))
				if ear[vi] == 1:
					edge = 0.0
				var nrm := hn[vi]
				var o := off
				if displace > 0.0:
					o += displace * (0.55 + 0.45 * sin(p.x * 211.0 + seed_i) * sin(p.y * 173.0 + p.z * 97.0 + seed_i * 0.7))
				var tg := nrm.cross(Vector3.UP)
				tg = tg.normalized() if tg.length() > 1e-4 else Vector3.RIGHT
				var uv := Vector2(deg_to_rad(ae.x) * 0.1, deg_to_rad(ae.y) * 0.1)
				remap[vi] = _vert(g, p + nrm * o, nrm, tg, uv, Vector4(edge, recession_rank(p), layer, float(kind) / 8.0))
			ids.append(remap[vi])
		# stejné pořadí vrcholů jako síť hlavy (už v konvenci Godotu) → normála ven
		_tri(g, ids[0], ids[1], ids[2])
		tris += 1
	g.stats["shell_tris"] += tris


# ======================================================================================
# Prameny
# ======================================================================================
## Směr toku (tečný k hlavě) v kořeni podle účesu.
static func flow_dir(st: Dictionary, p: Vector3, n: Vector3) -> Vector3:
	var f := Vector3.ZERO
	match String(st.get("flow", "whorl")):
		"part":
			var px := float(st.get("part_x", 0.0))
			var side := 1.0 if p.x >= px else -1.0
			var ae := az_el(p)
			# u pěšinky na stranu, vzadu dolů (od víru), vpředu mírně dozadu
			f = Vector3(side, -0.15, -0.35)
			if absf(ae.x) > 100.0:
				f = (p - WHORL).normalized() + Vector3(0, -0.3, 0)
		"back":
			f = Vector3(0.0, -0.05, -1.0)
			if absf(p.x) > 0.055:
				f += Vector3(0.0, -0.6, 0.0)
		"pull":
			f = (st["pull"] as Vector3) - p
		_:
			f = (p - WHORL)
	f -= n * f.dot(n)
	if f.length() < 1e-5:
		f = Vector3.DOWN - n * n.y
	return f.normalized()


## Pramen z kořene: polyline. Pochod s tuhostí, gravitací (s náklonem dozadu nebo dopředu přes ramena),
## kolizí s hlavou a trupem, střihem (cut_y, ofina) a objemem (odsazení roste od kořene).
static func strand(ctx: Dictionary, st: Dictionary, root: Dictionary, length: float, off0: float, vol: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var p: Vector3 = root["p"]
	var n: Vector3 = root["n"]
	var lift := float(st.get("lift", 0.3))
	var stiff := float(st.get("stiff", 0.8))
	var seg := float(st.get("seg", 0.015))
	var cut_y := float(st.get("cut_y", -10.0))
	if st.has("bangs_y") and p.z > 0.035 and absf(p.x) < 0.05:
		cut_y = float(st["bangs_y"])
	var front := p.z > 0.0 and absf(p.x) > 0.035 and rng.randf() < float(st.get("front_frac", 0.0))
	var side := 1.0 if p.x >= float(st.get("part_x", 0.0)) else -1.0
	var face_top := minf(FACE_Y1, float(st.get("bangs_y", FACE_Y1)))
	# Náklon dopředu (přes ramena) nebo dozadu jen nad rameny; pod nimi visí pramen svisle a o hrudník/záda se
	# opírá kolizí (běh 17: dřív náklon platil po celé délce a dlouhé copánky a dredy trčely 15–20 cm před hrudník).
	var lean_z := 0.32 if front else -0.32
	var dir := (flow_dir(st, p, n) + n * lift).normalized()
	var pts := PackedVector3Array([p + n * off0])
	var steps := maxi(2, int(ceil(length / seg)))
	var step := length / steps
	var cur := pts[0]
	for i in steps:
		var t := float(i + 1) / steps
		var g := (1.0 - stiff) * (0.4 + 0.6 * t)
		# pod úrovní středu hlavy už pramen nedrží hybnost od kořene (jinak dlouhé vlasy odstávaly od zad jako pláštěnka)
		if cur.y < C.y - 0.03 and length > 0.15:
			g = maxf(g, 0.6)
		# jen boční prameny (nad rameny); vzadu uprostřed visí vlasy svisle a leží na zádech
		# (dopředu jen nad rameny, ne u obličeje – tam pramen visí svisle podél tváře)
		var lean := clampf((cur.y - LEAN_Y0) / (LEAN_Y1 - LEAN_Y0), 0.0, 1.0) * clampf((absf(cur.x) - (0.075 if front else 0.045)) / 0.05, 0.0, 1.0)
		var grav := (Vector3.DOWN + Vector3(0.0, 0.0, lean_z * lean)).normalized()
		dir = (dir * (1.0 - g) + grav * g).normalized()
		var off := off0 + vol * minf(t * 3.0, 1.0)
		var nxt := avoid_face(collide(ctx, cur + dir * step, off), side, face_top)
		var d := nxt - cur
		if d.length() < 1e-6:
			break
		# střih: vodorovná linie (s drobnou nepravidelností)
		var cy := cut_y + (rng.randf() - 0.5) * 0.006
		if nxt.y < cy and cur.y >= cy:
			var k := (cur.y - cy) / maxf(cur.y - nxt.y, 1e-6)
			nxt = cur.lerp(nxt, k)
			pts.append(nxt)
			break
		if nxt.y < cy:
			break
		dir = d.normalized()
		cur = nxt
		pts.append(cur)
	return pts


## Bod pramene v obličeji (před očima, nosem, ústy) odsune na tvář na straně kořene.
static func avoid_face(p: Vector3, side: float, top := FACE_Y1) -> Vector3:
	if p.z > FACE_Z and absf(p.x) < FACE_X and p.y > FACE_Y0 and p.y < top:
		p.x = side * FACE_X
	return p


## Kadeř (šroubovice) nebo vlna kolem středové čáry pramene.
static func _curl(pts: PackedVector3Array, r: float, period: float, wave_a: float, wave_p: float, phase: float) -> PackedVector3Array:
	if pts.size() < 3 or (r <= 0.0 and wave_a <= 0.0):
		return pts
	var out := PackedVector3Array()
	var s := 0.0
	var prev_w := Vector3.ZERO
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var o := _out_dir(pts[i])
		var w := t.cross(o)
		w = w.normalized() if w.length() > 1e-3 else t.cross(Vector3.FORWARD).normalized()
		if prev_w != Vector3.ZERO and w.dot(prev_w) < 0.0:
			w = -w
		prev_w = w
		var b := w.cross(t).normalized()
		var ramp := clampf(s / 0.015, 0.0, 1.0)
		var d := Vector3.ZERO
		if r > 0.0:
			var a := phase + TAU * s / period
			d += (w * cos(a) + b * sin(a)) * r * ramp
		if wave_a > 0.0:
			d += w * sin(phase + TAU * s / wave_p) * wave_a * ramp
		out.append(pts[i] + d)
	return out


static func _widths(n: int, w0: float, taper: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		w.append(w0 * (1.0 - taper * t))
	return w


# ======================================================================================
# Účesy
# ======================================================================================
static func build(ctx: Dictionary, style: String) -> Dictionary:
	var g := Geo.new()
	var st: Dictionary = STYLES.get(style, {})
	if st.is_empty():
		return g.to_dict()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * int(st.get("seed", 1)) + 17
	for off in st.get("shell", []):
		var layer := 0.0 if float(off) < 0.002 else 0.5
		shell(g, ctx, float(off), layer, KIND_SHELL, float(st.get("shell_max_el", 999.0)))
	if st.has("afro"):
		_afro(g, ctx, st)
	elif st.has("rows"):
		_cornrows(g, ctx, st, rng)
	elif st.has("tube"):
		_tubes(g, ctx, st, rng)
	elif st.has("pull"):
		_pulled(g, ctx, st, rng)
	elif st.has("len"):
		_cards(g, ctx, st, rng)
	return g.to_dict()


static func _cards(g: Geo, ctx: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var layers := int(st.get("layers", 3))
	var min_el := float(st.get("min_el", -999.0))
	var lens: Array = st["len"]
	for li in layers:
		var lt := float(li) / maxf(layers - 1, 1)
		var spacing := float(st["spacing"]) * lerpf(0.9, 1.15, lt)
		var mask := func(p: Vector3) -> bool:
			var ae := az_el(p)
			return ae.y >= hairline_el(ae.x) + 1.0 and ae.y >= min_el
		var roots := sample(ctx, spacing, rng, mask)
		var off0 := 0.0011 + float(st.get("vol", 0.008)) * 0.25 * lt
		var vol := float(st.get("vol", 0.008)) * lerpf(0.35, 1.0, lt)
		for r in roots:
			var L := rng.randf_range(float(lens[0]), float(lens[1]))
			# vpředu u čela a u spánků kratší (přirozený střih, neleze do očí)
			var ae := az_el(r["p"])
			if absf(ae.x) < 60.0 and ae.y < hairline_el(ae.x) + 12.0 and not st.has("cut_y"):
				L *= 0.75
			var pts := strand(ctx, st, r, L, off0, vol, rng)
			if pts.size() < 2:
				continue
			pts = _curl(pts, float(st.get("curl_r", 0.0)), float(st.get("curl_p", 1.0)), float(st.get("wave_a", 0.0)),
				float(st.get("wave_p", 1.0)), rng.randf() * TAU)
			var w := float(st["width"]) * lerpf(1.2, 0.85, lt) * rng.randf_range(0.85, 1.15)
			ribbon(g, pts, _widths(pts.size(), w, 0.45), Vector4(rng.randf(), recession_rank(r["p"]), lt, 0.0))


## Afro: soustředné skořepiny se zvlněním (objem až `afro` m) + krátké karty po obvodu pro roztřepený okraj.
static func _afro(g: Geo, ctx: Dictionary, st: Dictionary) -> void:
	var n := int(st.get("shells", 7))
	var R := float(st["afro"])
	for i in n:
		var t := float(i + 1) / n
		shell(g, ctx, 0.002 + R * pow(t, 1.15), t, KIND_AFRO, 999.0, 0.004 + 0.01 * t, i * 13)


## Trubice: copánky (box braids) nebo dredy z mřížky kořenů; nejdřív po hlavě, pak gravitace.
static func _tubes(g: Geo, ctx: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind := int(st["tube"])
	var r0 := float(st["tube_r"])
	var mask := func(p: Vector3) -> bool:
		var ae := az_el(p)
		return ae.y >= hairline_el(ae.x) + 3.0
	var roots := sample(ctx, float(st["spacing"]), rng, mask, 10.0)
	var lens: Array = st["len"]
	for r in roots:
		var L := rng.randf_range(float(lens[0]), float(lens[1]))
		var pts := strand(ctx, st, r, L, r0 * 0.8, r0 * 0.6, rng)
		if pts.size() < 2:
			continue
		var rad := PackedFloat32Array()
		for i in pts.size():
			var t := float(i) / maxf(pts.size() - 1, 1)
			var x := r0 * (1.0 - 0.25 * t)
			if kind == KIND_LOC:
				x *= 0.85 + 0.3 * _hash(int(t * 40.0) + int((r["p"] as Vector3).x * 1e5))
			rad.append(x)
		tube(g, pts, rad, 5 if kind == KIND_BRAID else 7, Vector4(rng.randf(), recession_rank(r["p"]), 1.0, float(kind) / 8.0))


## Cornrows: řady od vlasové linie vpředu po týl, trubice napůl zapuštěné do skořepiny.
static func _cornrows(g: Geo, ctx: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var rows := int(st["rows"])
	var r0 := float(st["tube_r"])
	for i in rows:
		var az := lerpf(-62.0, 62.0, float(i) / (rows - 1))
		var el := hairline_el(az) + 2.0
		var d := Vector3(cos(deg_to_rad(el)) * sin(deg_to_rad(az)), sin(deg_to_rad(el)), cos(deg_to_rad(el)) * cos(deg_to_rad(az)))
		var p := C + d * (head_r(ctx["hmap"], d) + r0 * 0.7)
		var pts := PackedVector3Array()
		# pochod dozadu po hlavě: rovina řady obsahuje osu y-z posunutou do strany (řady se vzadu sbíhají)
		var x0 := p.x
		for k in 60:
			var q := p - C
			var target_x := x0 * (1.0 - 0.55 * clampf(-q.z / 0.1, 0.0, 1.0))
			var tdir := Vector3((target_x - p.x) * 4.0, -0.05, -1.0)
			if q.z < -0.03:
				tdir = Vector3((target_x - p.x) * 4.0, -1.0, -0.6 * clampf(q.y / 0.05, 0.0, 1.0))
			# napůl zapuštěné do skořepiny, ale ne hlouběji než ~2 mm pod povrch
			var nxt := collide(ctx, p + tdir.normalized() * 0.008, r0 * 0.7)
			if not in_scalp(nxt, 2.0) and k > 3:
				break
			pts.append(nxt)
			p = nxt
		if pts.size() < 3:
			continue
		var rad := PackedFloat32Array()
		for j in pts.size():
			rad.append(r0)
		tube(g, pts, rad, 6, Vector4(rng.randf(), recession_rank(pts[0]), 1.0, float(KIND_BRAID) / 8.0), false)


## Stažené vlasy (drdol, culík): karty těsně u hlavy tažené k bodu `pull`, pak drdol nebo ohon.
static func _pulled(g: Geo, ctx: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var T: Vector3 = st["pull"]
	var layers := int(st.get("layers", 2))
	for li in layers:
		var lt := float(li) / maxf(layers - 1, 1)
		var mask := func(p: Vector3) -> bool:
			var ae := az_el(p)
			return ae.y >= hairline_el(ae.x) + 1.0
		var roots := sample(ctx, float(st["spacing"]) * lerpf(0.9, 1.1, lt), rng, mask)
		for r in roots:
			var p: Vector3 = r["p"]
			var pts := PackedVector3Array([p + (r["n"] as Vector3) * 0.001])
			var cur := pts[0]
			var off := 0.0011 + 0.0016 * lt
			for _k in 40:
				var d := T - cur
				if d.length() < 0.012:
					break
				var nxt := collide(ctx, cur + d.normalized() * minf(0.012, d.length()), off)
				if nxt.distance_to(cur) < 1e-5:
					break
				cur = nxt
				pts.append(cur)
			if pts.size() < 2:
				continue
			var w := float(st["width"]) * lerpf(1.15, 0.9, lt)
			ribbon(g, pts, _widths(pts.size(), w, 0.55), Vector4(rng.randf(), recession_rank(p), lt * 0.6, 0.0))
	var dirc := (T - C).normalized()
	if st.has("bun_r"):
		# drdol: plné jádro + karty omotané po šroubovici kolem něj
		var R := float(st["bun_r"])
		var bc := T + dirc * R * 0.8
		var core := PackedVector3Array()
		var crad := PackedFloat32Array()
		var ax := dirc
		for i in 9:
			var t := float(i) / 8.0
			core.append(bc - ax * R * 0.75 + ax * R * 1.5 * t)
			crad.append(R * 0.92 * sqrt(maxf(1.0 - pow(2.0 * t - 1.0, 2.0), 0.04)))
		tube(g, core, crad, 12, Vector4(0.5, RANK_NEVER, 0.3, float(KIND_SOLID) / 8.0), true)
		var u := ax.cross(Vector3.UP).normalized()
		var v := ax.cross(u).normalized()
		for c in 34:
			var ph := TAU * c / 34.0
			var pts := PackedVector3Array()
			for i in 15:
				var t := float(i) / 14.0
				var a := ph + t * 3.6
				var h := lerpf(-0.6, 0.6, fmod(t * 1.3 + c * 0.37, 1.0))
				var rr := R * sqrt(maxf(1.0 - h * h, 0.05)) + 0.0015
				pts.append(bc + ax * h * R * 0.75 + (u * cos(a) + v * sin(a)) * rr)
			ribbon(g, pts, _widths(pts.size(), float(st["width"]) * 1.1, 0.3), Vector4(rng.randf(), RANK_NEVER, 0.8, 0.0))
	if st.has("tail_len"):
		# gumička + ohon: prameny z bodu stažení, gravitace a kolize se zády
		var band := PackedVector3Array([T - dirc * 0.004, T + dirc * 0.008])
		tube(g, band, PackedFloat32Array([0.009, 0.009]), 10, Vector4(0.5, RANK_NEVER, 0.0, float(KIND_SOLID) / 8.0 + 0.0625), false)
		var tst := {"lift": 0.0, "stiff": 0.35, "seg": 0.02, "cut_y": float(st.get("tail_cut", 1.37))}
		var u2 := dirc.cross(Vector3.UP).normalized()
		var v2 := dirc.cross(u2).normalized()
		for c in 30:
			var a := TAU * c / 30.0
			var rr := 0.004 + 0.003 * rng.randf()
			var p0 := T + dirc * 0.012 + (u2 * cos(a) + v2 * sin(a)) * rr
			var root := {"p": p0, "n": (dirc + (u2 * cos(a) + v2 * sin(a)) * 0.6).normalized()}
			var tst2 := tst.duplicate()
			tst2["flow"] = "pull"
			tst2["pull"] = p0 + Vector3(0, -0.05, -0.04)
			var pts := strand(ctx, tst2, root, float(st["tail_len"]) * rng.randf_range(0.85, 1.0), 0.0, 0.0, rng)
			if pts.size() < 2:
				continue
			ribbon(g, pts, _widths(pts.size(), float(st["width"]) * 1.2, 0.6), Vector4(rng.randf(), RANK_NEVER, 0.5 + 0.5 * rng.randf(), 0.0))


# ======================================================================================
# Obočí a vousy
# ======================================================================================
## Obočí: krátké karty podél oblouku (tvar jako shader kůže), chloupky u kořene nosu nahoru, dál do strany
## a na konci mírně dolů; leží na kůži (přesná projekce, 0,5 mm nad povrchem).
static func build_brows(ctx: Dictionary, style: String) -> Dictionary:
	var g := Geo.new()
	if not BROWS.has(style):
		return g.to_dict()
	var sh: Array = BROWS[style]
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 + absi(style.hash()) % 1000
	var inner := 0.0 if float(sh[3]) > 0.5 else float(sh[2])
	var outer := EYE.x + EYE_W + 0.006
	var count := int(sh[4])
	for side in [-1.0, 1.0]:
		for c in count:
			var t := rng.randf()
			var ax := lerpf(inner, outer, t)
			var yc := EYE.y + 0.0125 + float(sh[1]) * sin(PI * t * 0.9) - 0.002 * t
			var th := float(sh[0]) * (1.1 - 0.55 * t)
			if float(sh[3]) > 0.5 and ax < float(sh[2]):
				th *= 0.45
			var y := yc + (rng.randf() - 0.5) * th
			# výchozí bod na hlavě radiálně od středu (běh 17: dřív pevné z = 0,11 m bylo mimo dosah projekce
			# u bočních částí obočí – zůstaly jen chloupky u kořene nosu)
			var dir0 := (Vector3(ax * side, y, C.z + 0.09) - C).normalized()
			var start := C + dir0 * head_r(ctx["hmap"], dir0)
			var pr := project(ctx, start)
			if pr.is_empty():
				continue
			var n: Vector3 = pr["n"]
			# směr chloupku: u kořene nosu nahoru, uprostřed do strany a nahoru, na konci do strany a dolů
			var ang := lerpf(80.0, -12.0, smoothstep(0.0, 1.0, t)) + rng.randf_range(-10.0, 10.0)
			var d2 := Vector3(cos(deg_to_rad(ang)) * side, sin(deg_to_rad(ang)), 0.0)
			var L := rng.randf_range(0.006, 0.0095) * (0.8 if t < 0.15 else 1.0)
			var pts := PackedVector3Array()
			var p: Vector3 = pr["p"] + n * 0.0005
			pts.append(p)
			for k in 2:
				var tang := (d2 - n * d2.dot(n)).normalized()
				p = keep_above(ctx, p + tang * L * 0.5, 0.0005 + 0.0007 * (k + 1))
				pts.append(p)
			var w := rng.randf_range(0.0022, 0.0032) * (1.25 if style == "huste" else 1.0)
			ribbon(g, pts, _widths(3, w, 0.5), Vector4(rng.randf(), RANK_NEVER, 0.5, 0.0))
	return g.to_dict()


static func _beard_zone(z: Array, p: Vector3) -> float:
	var ax := absf(p.x)
	var my := MOUTH.y
	var mw := MOUTH.z
	var best := 0.0
	if int(z[0]) == 1 and p.y > my + 0.005 and p.y < my + 0.018 and ax < mw + 0.006 - (p.y - my) * 0.3 and p.z > 0.055:
		best = 1.0
	if int(z[1]) == 1 and p.y > 1.546 and p.y < my - 0.007 and ax < 0.028 + (my - p.y) * 0.3 and p.z > 0.025:
		best = 2.0
	if int(z[2]) == 1:
		var jaw := p.y > 1.543 and p.y < 1.628 - maxf(ax - 0.02, 0.0) * 0.15 and ax > 0.02 and ax < 0.074 and p.z > -0.025
		if jaw and ax < mw + 0.004 and absf(p.y - my) < 0.012:
			jaw = false
		var neck := p.y > 1.512 and p.y <= 1.548 and p.z > 0.0 and ax < 0.06
		if jaw or neck:
			best = 3.0
	if int(z[3]) == 1 and ax > 0.062 and p.y > 1.615 and p.y < 1.672 and p.z > -0.015 and p.z < 0.035:
		best = 4.0
	return best


## Vousy: krátké karty v zónách stylu, rostou dolů (knír do stran), leží těsně u kůže a s délkou odstávají.
static func build_beard(ctx: Dictionary, style: String) -> Dictionary:
	var g := Geo.new()
	var b: Array = BEARDS.get(style, [])
	if b.is_empty():
		return g.to_dict()
	var zones: Array = b[0]
	var L0 := float(b[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 130363 + absi(style.hash()) % 1000
	var mask := func(p: Vector3) -> bool:
		return _beard_zone(zones, p) > 0.0
	var roots := sample(ctx, 0.0042, rng, mask, 8.0)
	for r in roots:
		var p: Vector3 = r["p"]
		var n: Vector3 = r["n"]
		var zone := _beard_zone(zones, p)
		var L := L0 * rng.randf_range(0.8, 1.15)
		var d := Vector3.DOWN
		if zone == 1.0:
			d = Vector3(signf(p.x) * 0.7, -1.0, 0.15)
			L = minf(L, 0.014)
		elif zone == 4.0:
			L *= 0.7
		elif zone == 3.0 and p.y < 1.55:
			d = Vector3(0, -0.3, 1.0)       # pod bradou dopředu-dolů k bradě
		var segs := 3 if L > 0.012 else 2
		var pts := PackedVector3Array([p + n * 0.0006])
		var cur := pts[0]
		for k in segs:
			var tt := float(k + 1) / segs
			var tang := (d - n * d.dot(n)).normalized()
			var lift := n * 0.35 * tt if L > 0.015 else n * 0.12
			cur = keep_above(ctx, cur + (tang + lift).normalized() * L / segs, 0.0006 + L * 0.28 * tt)
			n = (cur - C).normalized().lerp(n, 0.7).normalized()
			pts.append(cur)
		var w := rng.randf_range(0.0035, 0.005)
		ribbon(g, pts, _widths(pts.size(), w, 0.5), Vector4(rng.randf(), RANK_NEVER, 0.5, 0.0))
	return g.to_dict()


static func tri_count(g: Dictionary) -> int:
	return (g["idx"] as PackedInt32Array).size() / 3
