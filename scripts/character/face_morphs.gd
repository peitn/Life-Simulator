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
## takže se nic neaplikuje dvakrát. Tělo ovlivní obličej jen přes tuk (plnější tváře, podbradek, krk)
## a svaly (krk, úhel čelisti) – ne přes identitu, rod ani jméno.

const Schema := preload("res://scripts/character/character_schema.gd")

## Dvojice morfů s korekčními (kombinačními) tvary – vybrané měřením interakcí všech dvojic při ±1
## (běh 9): jen tyto přesahovaly ~2 mm. Ostatní dvojice se sčítají lineárně s chybou < 1,3 mm.
const CORRECTIVE_PAIRS := [["nose_length", "nose_bridge"], ["nose_length", "nose_tip"]]

## Klíče hlavy řízené tělem (BodyMorphs.weights) – jen nárůst; hubnutí obličej nemění (hlava je štíhlá v základu).
const BODY_LINKS := {"b_fat": "fat_hi", "b_muscle": "muscle_hi"}


static func _q(x: float) -> float:
	return roundf(x * 1000.0) / 1000.0


## Hodnota pole ořezaná do rozsahu schématu; chybějící / neplatná = výchozí.
static func value(face: Dictionary, field: String) -> float:
	var fs: Dictionary = Schema.fields("face")
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


## Váhy (název blend shape → float). body_w = výstup BodyMorphs.weights().
static func weights(face: Dictionary, body_w: Dictionary = {}) -> Dictionary:
	var w := {}
	for k in morph_fields():
		var v := _q(value(face, k))
		w[k] = v
		w[k + "_pos"] = maxf(0.0, v)
		w[k + "_neg"] = maxf(0.0, -v)
		# Mezitvar: 0 v nule i na maximu, 1 v polovině (přesný tvar v ±0,5 u nelineárních morfů).
		w[inbetween_name(k, 1)] = _q(1.0 - absf(2.0 * maxf(0.0, v) - 1.0)) if v > 0.0 else 0.0
		w[inbetween_name(k, -1)] = _q(1.0 - absf(2.0 * maxf(0.0, -v) - 1.0)) if v < 0.0 else 0.0
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
	return w


## Název korekčního tvaru pro dvojici a kvadrant znamének (např. cx_nose_length_p__nose_bridge_n).
static func corrective_name(a: String, sa: int, b: String, sb: int) -> String:
	return "cx_%s_%s__%s_%s" % [a, "p" if sa > 0 else "n", b, "p" if sb > 0 else "n"]


## Název mezitvaru pole pro znaménko (např. nose_length_neg_mid).
static func inbetween_name(field: String, sg: int) -> String:
	return "%s_%s_mid" % [field, "pos" if sg > 0 else "neg"]
