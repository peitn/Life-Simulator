extends RefCounted
## SkinModel (C4) – fyzikálně inspirovaný model barvy kůže. Jediný zdroj pravdy pro CPU (AppearanceResolver,
## testy, náhrada z primitiv) i GPU (skin.gdshader dostává tytéž konstanty jako uniformy).
##
## Kůže = dvě vrstvy chromoforů (Beer–Lambert): pokožka s melaninem a škára s hemoglobinem a karotenem.
##   R(λ) = s + Rd(λ) · exp(−(c_mel·k_mel(λ) + c_hb·k_hb(λ) + c_car·k_car(λ)))
## k_mel ∝ λ^−2,36 (absorpce melaninu klesá s vlnovou délkou), hemoglobin absorbuje hlavně zelenou a modrou,
## karoten modrou; s = neutrální odraz povrchu (rohová vrstva). Kanály R/G/B = 610/550/465 nm.
## Konstanty jsou nafitované nejmenšími čtverci na dřívější kotvy odstínu (max. odchylka ~0,08 sRGB), takže
## domácnost vypadá skoro stejně, ale celé spektrum je jedna spojitá funkce bez kotev a předvoleb:
##   tone (melanin 0..1) → c_mel = 0,078 + 3,055·tone^1,935
##   redness (prokrvení 0..1) → c_hb = 0,082 + 0,359·redness
##   undertone −1..1: teplý = víc karotenu a o něco méně hemoglobinu, chladný = víc hemoglobinu (růžovější).
## Žádná „rasa“ ani etnické kategorie – jen koncentrace chromoforů, stejné pro všechny.
## Lokální jevy v shaderu (pihy, stařecké skvrny, vitiligo, ruměnec, akné, jizvy) mění TYTÉŽ koncentrace,
## takže vypadají věrohodně na jakémkoli odstínu (např. vitiligo je výraznější na tmavší kůži, akné po sobě
## na tmavé kůži zanechává spíš tmavé skvrny – obojí vychází z modelu, ne z výjimek).

const RD := Vector3(1.0638, 0.9236, 0.7323)
const SURFACE := 0.0083
const MEL_EXP := 2.357
const LAMBDA := Vector3(610.0, 550.0, 465.0)
const K_HB := Vector3(0.06, 1.0, 0.55)
const K_CAR := Vector3(0.0, 0.12, 1.0)
const MEL_A0 := 0.0776
const MEL_A1 := 3.0553
const MEL_GAMMA := 1.9349
const HB_A0 := 0.0814
const HB_A1 := 0.3587
const CAR_WARM := 0.55
const HB_WARM := -0.06
const HB_COOL := 0.28


static func k_mel() -> Vector3:
	return Vector3(1.0, pow(LAMBDA.y / LAMBDA.x, -MEL_EXP), pow(LAMBDA.z / LAMBDA.x, -MEL_EXP))


## Koncentrace chromoforů z dat postavy: Vector3(melanin, hemoglobin, karoten).
static func chromophores(tone: float, undertone: float, redness: float) -> Vector3:
	# Nekonečna a NaN (poškozený snapshot) → výchozí hodnoty schématu; clampf by NaN propustil.
	var t := clampf(tone, 0.0, 1.0) if is_finite(tone) else 0.45
	var u := clampf(undertone, -1.0, 1.0) if is_finite(undertone) else 0.0
	var r := clampf(redness, 0.0, 1.0) if is_finite(redness) else 0.3
	var mel := MEL_A0 + MEL_A1 * pow(t, MEL_GAMMA)
	var hb := HB_A0 + HB_A1 * r + (HB_WARM * u if u > 0.0 else HB_COOL * -u)
	var car := CAR_WARM * maxf(u, 0.0)
	return Vector3(mel, maxf(hb, 0.0), car)


## Lineární odrazivost (albedo v lineárním RGB) pro dané koncentrace.
static func reflectance_linear(c: Vector3) -> Color:
	var km := k_mel()
	var e := Vector3(
		c.x * km.x + c.y * K_HB.x + c.z * K_CAR.x,
		c.x * km.y + c.y * K_HB.y + c.z * K_CAR.y,
		c.x * km.z + c.y * K_HB.z + c.z * K_CAR.z)
	return Color(
		clampf(SURFACE + RD.x * exp(-e.x), 0.0, 1.0),
		clampf(SURFACE + RD.y * exp(-e.y), 0.0, 1.0),
		clampf(SURFACE + RD.z * exp(-e.z), 0.0, 1.0))


## Albedo kůže v sRGB (nekvantované; kvantuje AppearanceResolver).
static func albedo(tone: float, undertone: float, redness: float) -> Color:
	return reflectance_linear(chromophores(tone, undertone, redness)).linear_to_srgb()


## Uniformy modelu pro skin.gdshader (shader počítá tutéž rovnici po pixelech s lokálními změnami).
static func shader_constants() -> Dictionary:
	var km := k_mel()
	return {"rd": RD, "surface_refl": SURFACE, "k_mel": km, "k_hb": K_HB, "k_car": K_CAR}
