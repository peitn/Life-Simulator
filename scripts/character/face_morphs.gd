extends RefCounted
## FaceMorphs (C3) – čistá deterministická funkce: skupina `face` z CharacterData (+ tuk a svaly z těla)
## → váhy blend shapes procedurální hlavy (scripts/assets/head_builder.gd). Sdílí ji server i klienti
## přes AppearanceResolver; výstup je kvantovaný na 1/1000 → stejný na všech peerech.
##
## Pojmenování blend shapes (HeadBuilder.morph_targets):
##  - LINEÁRNÍ morf (výchylka pro −1 = přesně opačná výchylce pro +1): jeden klíč „<pole>“, váha = hodnota
##    (záporná váha = opačný směr),
##  - NELINEÁRNÍ morf (např. ústup čela ≠ zrcadlo vyklenutí): dva klíče „<pole>_pos“ a „<pole>_neg“,
##    váhy max(0, v) a max(0, −v).
##  - MEZITVAR „<pole>_pos_mid“ / „<pole>_neg_mid“ (jen kde je morf v polovině výrazně nelineární, dnes
##    délka nosu): váha 1 − |2|v| − 1| – Godot nemá nativní in-between tvary,
##  - KOREKČNÍ tvar „cx_<a>_<p|n>__<b>_<p|n>“ pro dvojice s interakcí: váha = součin vah obou polí.
## Výstup obsahuje oba tvary pro každé pole – síť má vždy jen jeden z nich (podle manifest meta face_spec),
## takže se nic neaplikuje dvakrát. Tělo ovlivní obličej jen přes tuk (plnější tváře, podbradek, krk),
## svaly (krk, úhel čelisti) a délku krku (posun celé hlavy nad krkem) – ne přes identitu, rod ani jméno.

const Schema := preload("res://scripts/character/character_schema.gd")

## Dvojice morfů s korekčními (kombinačními) tvary – vybrané měřením interakcí všech dvojic při ±1
## (běh 9): jen tyto přesahovaly ~2 mm. Ostatní dvojice se sčítají lineárně s chybou < 1,3 mm.
## Běh 18 (delší oční štěrbina, C3+ B): vzdálenost × hloubka očí 2,9 mm (široko posazené vystouplé oči – vnější
## prstenec víček se opírá o zakřivení spánku) → třetí dvojice; ostatní dvojice morfů očí, obočí a lící ≤ 2,0 mm.
const CORRECTIVE_PAIRS := [["nose_length", "nose_bridge"], ["nose_length", "nose_tip"], ["eye_distance", "eye_depth"]]

## Klíče hlavy řízené tělem (BodyMorphs.weights) – jen nárůst; hubnutí obličej nemění (hlava je štíhlá v základu).
const BODY_LINKS := {"b_fat": "fat_hi", "b_muscle": "muscle_hi"}
## Klíče hlavy řízené tělem v OBOU směrech (váha −1..1): délka krku (body.neck_length → BodyMorphs.head_links „neck_len“).
const BODY_SIGNED_LINKS := {"b_neck_len": "neck_len"}
## C3++ (běh 21): detaily obličeje ze skupiny face → klíče morfů HeadBuilderu (DETAIL_KEYS). "c" = pole 0..1 se
## středem 0,5 → −1..1 (lineární kolem výchozí hodnoty), "p" = pole 0..1 přímo (jen kladný směr).
const DETAIL_FIELDS := {"lash_length": "c", "lash_curl": "c", "lash_density": "c", "teeth_gap": "p", "teeth_crooked": "p"}
## Řasenka (makeup.mascara 0..1) řasy pro vykreslení prodlouží a zhustí (data postavy se nemění).
const MASCARA_LEN := 0.35
const MASCARA_DENS := 0.5
## Mimika (HeadBuilder.EXPR_KEYS) – jen prezentace klienta (SimVisual): není v CharacterData a nereplikuje se.
## Jednostranné klíče 0..1, zornice −1..1.
const EXPR_KEYS := ["ex_blink_l", "ex_blink_r", "ex_smile", "ex_frown", "ex_brow_up", "ex_jaw_open", "ex_pupil"]
const EXPR_SIGNED := ["ex_pupil"]


static func _q(x: float) -> float:
	return roundf(x * 1000.0) / 1000.0


## Hodnota pole ořezaná do rozsahu schématu; chybějící / neplatná = výchozí.
## fs = Schema.fields("face") – volající ve smyčce ho předá jednou (běh 13: skládání slovníku polí pro každé pole
## zvlášť stálo ~0,8 ms na postavu a shodilo odezvu posuvníku přes 4 ms).
static func value(face: Dictionary, field: String, fs: Dictionary = {}) -> float:
	if fs.is_empty():
		fs = Schema.fields("face")
	if not fs.has(field):
		return 0.0
	var spec: Array = fs[field]
	var v = face.get(field, spec[3])
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return float(spec[3])
	var f := float(v)
	if not is_finite(f):
		return float(spec[3])
	return clampf(f, float(spec[1]), float(spec[2]))


## Seznam polí, která se promítají do blend shapes (morfy + asymetrie).
static func morph_fields() -> Array:
	var out: Array = Schema.FACE_MORPHS.keys()
	out.append_array(Schema.FACE_ASYMMETRY.keys())
	return out


## Hodnoty detailů (DETAIL_FIELDS) jako váhy morfů: řasy −1..1 kolem výchozí 0,5, zuby 0..1; řasenka z make-upu.
static func detail_values(face: Dictionary, makeup: Dictionary = {}, fs: Dictionary = {}) -> Dictionary:
	if fs.is_empty():
		fs = Schema.fields("face")
	var out := {}
	for k in DETAIL_FIELDS:
		var v := value(face, k, fs)
		out[k] = (v - 0.5) * 2.0 if String(DETAIL_FIELDS[k]) == "c" else v
	var m = makeup.get("mascara", 0.0)
	var mf := clampf(float(m), 0.0, 1.0) if (typeof(m) == TYPE_FLOAT or typeof(m) == TYPE_INT) and is_finite(float(m)) else 0.0
	out["lash_length"] = float(out["lash_length"]) + MASCARA_LEN * mf
	out["lash_density"] = float(out["lash_density"]) + MASCARA_DENS * mf
	for k in out:
		out[k] = _q(clampf(float(out[k]), -1.0, 1.0))
	return out


## Zapíše váhy jednoho pole: <pole> (lineární), <pole>_pos/_neg a mezitvary (1 v polovině, 0 v nule i na maximu).
static func _put(w: Dictionary, k: String, v: float) -> void:
	w[k] = v
	w[k + "_pos"] = maxf(0.0, v)
	w[k + "_neg"] = maxf(0.0, -v)
	w[inbetween_name(k, 1)] = _q(1.0 - absf(2.0 * maxf(0.0, v) - 1.0)) if v > 0.0 else 0.0
	w[inbetween_name(k, -1)] = _q(1.0 - absf(2.0 * maxf(0.0, -v) - 1.0)) if v < 0.0 else 0.0


## Váhy (název blend shape → float). body_w = výstup BodyMorphs.weights(), makeup = skupina makeup (řasenka).
## Malá cache výsledků weights() (posuvník těla/kůže mění vzhled, ale obličej zůstává – přepočet ~250 vah se
## opakoval při každém pohybu). Klíč = hash vstupů, při zásahu se vstupy porovnají celé (kolize hashe nevadí);
## vrací se kopie, takže volající může výsledek měnit.
static var _memo: Dictionary = {}


static func weights(face: Dictionary, body_w: Dictionary = {}, makeup: Dictionary = {}) -> Dictionary:
	var key := [face.hash(), body_w.hash(), makeup.hash()].hash()
	var hit = _memo.get(key)
	if hit != null and hit[0] == face and hit[1] == body_w and hit[2] == makeup:
		return (hit[3] as Dictionary).duplicate()
	var w := _compute(face, body_w, makeup)
	if _memo.size() >= 64:
		_memo.clear()
	_memo[key] = [face.duplicate(true), body_w.duplicate(true), makeup.duplicate(true), w.duplicate()]
	return w


static func _compute(face: Dictionary, body_w: Dictionary, makeup: Dictionary) -> Dictionary:
	var w := {}
	var fs: Dictionary = Schema.fields("face")
	for k in morph_fields():
		_put(w, k, _q(value(face, k, fs)))
	var dv := detail_values(face, makeup, fs)
	for k in dv:
		_put(w, k, float(dv[k]))
	for pair in CORRECTIVE_PAIRS:
		var va: float = w[pair[0]]
		var vb: float = w[pair[1]]
		for sa in [1, -1]:
			for sb in [1, -1]:
				w[corrective_name(pair[0], sa, pair[1], sb)] = _q(maxf(0.0, sa * va) * maxf(0.0, sb * vb))
	for k in BODY_LINKS:
		var b = body_w.get(BODY_LINKS[k], 0.0)
		var bf := float(b) if (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT) and is_finite(float(b)) else 0.0
		w[k] = _q(clampf(bf, 0.0, 1.0))
	for k in BODY_SIGNED_LINKS:
		var b = body_w.get(BODY_SIGNED_LINKS[k], 0.0)
		var bf := float(b) if (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT) and is_finite(float(b)) else 0.0
		w[k] = _q(clampf(bf, -1.0, 1.0))
	return w


## Váhy mimiky (SimVisual): {ex_*: hodnota} → názvy blend shapes včetně _pos/_neg a mezitvarů (mrkání je v polovině
## výrazně nelineární – víčko jde po kouli, ne po tětivě). Neplatné hodnoty → 0, mimo rozsah → ořez, kvantováno.
static func expression_weights(ex: Dictionary) -> Dictionary:
	var w := {}
	for k in EXPR_KEYS:
		var raw = ex.get(k, 0.0)
		var f := float(raw) if (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT) and is_finite(float(raw)) else 0.0
		_put(w, k, _q(clampf(f, -1.0 if EXPR_SIGNED.has(k) else 0.0, 1.0)))
	return w


## Název korekčního tvaru pro dvojici a kvadrant znamének (např. cx_nose_length_p__nose_bridge_n).
static func corrective_name(a: String, sa: int, b: String, sb: int) -> String:
	return "cx_%s_%s__%s_%s" % [a, "p" if sa > 0 else "n", b, "p" if sb > 0 else "n"]


## Název mezitvaru pole pro znaménko (např. nose_length_neg_mid).
static func inbetween_name(field: String, sg: int) -> String:
	return "%s_%s_mid" % [field, "pos" if sg > 0 else "neg"]
