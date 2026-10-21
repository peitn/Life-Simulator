extends RefCounted
## BodyMorphs – čistá deterministická funkce: skupina `body` z CharacterData → váhy blend shapes těla,
## měřítka (výška, délka nohou, hlava) a posuny kloubů. Sdílí ji server i klienti (AppearanceResolver),
## výstup je kvantovaný (váhy 1/1000, měřítko výšky 1e-4, hlava 1e-5), takže je na všech peerech bit po bitu stejný.
##
## Shape keys těla (tools/blender/char.py) představují výchozí hodnoty schématu (character_schema.gd):
##  - LINEÁRNÍ klíče (frame, shoulders, chest, bust, waist, hips): deformační pole je lineární, proto
##    jeden klíč pokryje obě strany – váha w = (v − výchozí) / (1 − výchozí), tj. 0 ve výchozí hodnotě,
##    1 na maximu a −výchozí/(1 − výchozí) na minimu (záporná váha = přesné „opačné“ těleso);
##  - PÁRY (svaly, tuk): úbytek a nárůst mají jiný tvar (hubnutí není zrcadlo obezity), proto
##    w_hi = max(0, (v − výchozí)/(1 − výchozí)), w_lo = max(0, (výchozí − v)/výchozí).
## Nic z toho nezávisí na identitě, rodu ani jméně – poprsí, boky i ramena jsou samostatné osy.
##
## Kosti: délka nohou = škálování stehenní kosti po délce (dědí lýtko i chodidlo), výška = uniformní
## měřítko modelu; hlava se s výškou mění jen s odmocninou (malí lidé nemají „malou hlavu“ úměrně,
## vysocí ne obří) – výška temene pak přesně odpovídá height_cm.

const Schema := preload("res://scripts/character/character_schema.gd")

const MORPHS := ["frame", "muscle_hi", "muscle_lo", "fat_hi", "fat_lo", "shoulders", "chest", "bust", "waist", "hips"]
## Pole schématu → lineární klíč.
const LINEAR := {"frame": "frame", "shoulders": "shoulders", "chest": "chest", "bust": "bust", "waist": "waist", "hips": "hips"}
## Pole schématu → [klíč úbytku, klíč nárůstu].
const PAIRS := {"muscle": ["muscle_lo", "muscle_hi"], "body_fat": ["fat_lo", "fat_hi"]}

## Geometrie referenčního modelu (tools/blender/char.py, meta v manifestu).
const MODEL_HEIGHT := 1.78       # m – temeno
const HEAD_PIVOT := 1.56         # m – kloub hlavy (kost head)
const LEG_LENGTH := 0.93         # m – kyčelní kloub → zem
const LEG_MIN := 0.92            # měřítko stehna při leg_length = 0
const LEG_MAX := 1.08            # … při leg_length = 1
## Velikost hlavy ∝ (měřítko výšky)^HEAD_EXP – výchozí UMĚLECKÁ heuristika (ne anatomický zákon, review
## ChatGPT 49); hráč ji posune vlastním posuvníkem body.head_size (±HEAD_SIZE_RANGE) nezávisle na výšce.
const HEAD_EXP := 0.5
const HEAD_SIZE_RANGE := 0.06
## Délka krku (běh 13): body.neck_length −1..1 posune hlavu nad krkem o ±NECK_LEN_RANGE (v souřadnicích modelu,
## blend shape hlavy b_neck_len; musí souhlasit s HeadBuilder.NECK_LEN_RANGE – hlídá test). Temeno se tím zvedne
## o stejnou vzdálenost × měřítko hlavy, proto ho scales() započítá a výška postavy dál přesně sedí na height_cm.
const NECK_LEN_RANGE := 0.015
## Kvantizace: měřítko výšky na 1e-4, hlava se pak dopočítá z KVANTOVANÉHO měřítka (1e-5), takže temeno
## sedí na height_cm s chybou v řádu mikrometrů (dřív se obojí kvantovalo zvlášť na 1e-3 – review ChatGPT 49 B).
const Q_SCALE := 10000.0
const Q_HEAD := 100000.0


static func _q(x: float) -> float:
	return roundf(x * 1000.0) / 1000.0


static func default_of(field: String) -> float:
	return float(Schema.fields("body")[field][3])


static func _val(body: Dictionary, field: String) -> float:
	var spec: Array = Schema.fields("body")[field]
	var v = body.get(field, spec[3])
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return float(spec[3])
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return float(spec[3])
	return clampf(f, float(spec[1]), float(spec[2]))


## Váhy všech morfů (jméno → float, kvantované). Chybějící/neplatná pole = výchozí hodnota.
static func weights(body: Dictionary) -> Dictionary:
	var w := {}
	for field in LINEAR:
		var d := default_of(field)
		w[LINEAR[field]] = _q((_val(body, field) - d) / (1.0 - d))
	for field in PAIRS:
		var d := default_of(field)
		var v := _val(body, field)
		w[PAIRS[field][0]] = _q(maxf(0.0, (d - v) / d))
		w[PAIRS[field][1]] = _q(maxf(0.0, (v - d) / (1.0 - d)))
	return w


## Váhy klíčů HLAVY řízených tělem, které nejsou tvary těla (běh 13: délka krku −1..1). Předávají se do
## FaceMorphs.weights spolu s weights() (AppearanceResolver); síť těla je nemá.
static func head_links(body: Dictionary) -> Dictionary:
	return {"neck_len": _q(_val(body, "neck_length"))}


## Posun hlavy nad krkem v souřadnicích modelu (m) – stejná kvantizace jako váha blend shape.
static func neck_offset(body: Dictionary) -> float:
	return NECK_LEN_RANGE * _q(_val(body, "neck_length"))


## Měřítko stehenní kosti po délce (1.0 = výchozí délka nohou).
static func leg_scale(body: Dictionary) -> float:
	return _q(lerpf(LEG_MIN, LEG_MAX, _val(body, "leg_length")))


## Uniformní měřítko modelu a měřítko kosti hlavy tak, aby temeno bylo přesně ve výšce height_cm:
##   H = s·B + k·s^HEAD_EXP·C,  B = kloub hlavy (+ prodloužení nohou), C = hlava nad kloubem (+ posun délky krku –
##   blend shape posouvá hlavu v prostoru kosti hlavy, takže se škáluje spolu s ní),
##   k = 1 + HEAD_SIZE_RANGE·head_size (vlastní velikost hlavy).
## Pro HEAD_EXP = 0,5 je to kvadratická rovnice v x = √s. Hlava se pak dopočítá z kvantovaného s.
static func scales(body: Dictionary) -> Dictionary:
	var h := _val(body, "height_cm") / 100.0
	var ls := leg_scale(body)
	var lift := _q((ls - 1.0) * LEG_LENGTH)   # zvednutí modelu (v jeho souřadnicích), aby chodidla zůstala na zemi
	var b := HEAD_PIVOT + lift
	var nk := neck_offset(body)
	var c := MODEL_HEIGHT - HEAD_PIVOT + nk
	var k := 1.0 + HEAD_SIZE_RANGE * _val(body, "head_size")
	# b > 0 a h ∈ ⟨1,45; 2,05⟩ (_val ořezává) → diskriminant je vždy kladný; maxf jen jako pojistka (review Gemini).
	var x := (-c * k + sqrt(maxf(0.0, c * c * k * k + 4.0 * b * h))) / (2.0 * maxf(b, 0.5))
	var s := roundf(x * x * Q_SCALE) / Q_SCALE
	# kost hlavy: absolutní velikost = s · head; z rovnice s kvantovaným s → temeno přesně v h.
	s = maxf(s, 0.1)   # pojistka (audit Gemini): _val ořezává výšku, takže s ≈ 0,8–1,2 – nula nenastane
	var head := roundf((h - s * b) / (s * c) * Q_HEAD) / Q_HEAD
	return {"height_scale": s, "head_scale": head, "leg_scale": ls, "lift": lift, "neck": nk}


## Výška temene (m) pro dané parametry – kontrola v testech.
static func crown_height(sc: Dictionary) -> float:
	var s := float(sc["height_scale"])
	return s * (HEAD_PIVOT + float(sc["lift"])) + s * float(sc["head_scale"]) * (MODEL_HEIGHT - HEAD_PIVOT + float(sc.get("neck", 0.0)))


## Kosti, které smí tabulka z manifestu posouvat, a největší povolený posun (m) – manifest je soubor
## na disku, nevěříme mu slepě (review ChatGPT 49 C).
const BONES := ["upper_arm_l", "upper_arm_r", "thigh_l", "thigh_r", "shoulder_l", "shoulder_r", "neck", "head", "spine", "chest"]
const MAX_BONE_OFFSET := 0.1


## Posuny hlav kostí (osy modelu) = Σ váha × posun při plné váze (tabulka morph_bones z manifestu).
static func bone_offsets(w: Dictionary, table: Dictionary) -> Dictionary:
	var out := {}
	for k in table:
		var wk := float(w.get(k, 0.0))
		if wk == 0.0 or typeof(table[k]) != TYPE_DICTIONARY:
			continue
		for bone in table[k]:
			var a = table[k][bone]
			if typeof(bone) != TYPE_STRING or not BONES.has(bone) or typeof(a) != TYPE_ARRAY or (a as Array).size() != 3:
				continue
			var ok := true
			for x in a:
				if (typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT) or not is_finite(float(x)) or absf(float(x)) > MAX_BONE_OFFSET:
					ok = false
			if ok:
				out[bone] = (out.get(bone, Vector3.ZERO) as Vector3) + Vector3(float(a[0]), float(a[1]), float(a[2])) * wk
	return out
