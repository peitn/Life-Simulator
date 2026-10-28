extends RefCounted
## CzechTTS – self-contained Czech text-to-speech (formant synthesis + rule-based prosody).
##
## No network, no external engine, no recorded samples. Text → CzechG2P (phonemes, syllables,
## stress units, phrase types) → timed segment plan + F0 contour → source–filter synthesis.
## Inputs are ONLY the text and the public voice parameters (CharacterData.voice: pitch,
## timbre, tempo, roughness) plus a style. Nothing is derived from gender, identity, name or
## body. Same input → bit-identical output on every peer (own hash + own RNG).
##
## Prosody (standard Czech):
##   - fixed stress on the first syllable of each stress unit (monosyllabic prepositions
##     carry the stress of the next word, enclitics are unstressed);
##   - F0 declination across the utterance;
##   - statement: final fall; yes/no question: low last stressed syllable, then a rise to the
##     end; wh-question (kdo, co, kde, …): high start, falling end; exclamation: wider range,
##     stronger accents; comma: slight rise + short pause; period: longer pause; ellipsis:
##     trailing low with fade;
##   - long vowels ~1.7× short; phrase-final lengthening; tempo from voice.tempo × style.

const G2P := preload("res://scripts/audio/czech_g2p.gd")

const SR := 22050
const MAX_DURATION := 16.0
const MAX_CHARS := 200
const BASE_F0 := 160.0
const PITCH_OCTAVES := 1.05
const TRACT_OCTAVES := 0.16
const TEMPO_OCTAVES := 0.6
const F0_STEP := 0.005
const COEF_BLOCK := 16
const NOISE_GAIN := 9.0
## Output level per consonant relative to a vowel (calibrated with tests/test_tts.gd
## segment RMS: sonorants ≈ −5…−7 dB, sibilants ≈ −10 dB, f/h weaker).
const OUT_GAIN := {"m": 0.24, "n": 0.24, "ň": 0.26, "ŋ": 0.24, "l": 0.34, "r": 0.5, "j": 0.42,
	"ř": 0.45, "ř̊": 0.6, "h": 0.22, "f": 0.45, "v": 0.3, "z": 0.32, "ž": 0.3,
	"dz": 0.55, "dž": 0.5, "b": 0.6, "d": 0.7, "ď": 0.7, "g": 0.7}

## Style modifiers for speech. f0_st: mean shift (semitones); range: intonation range scale;
## accent: stress accent size (st); rate: speaking rate; energy; breath; tilt (+ brighter);
## f1: larynx tension; pause: pause scale; voiced (0 = whisper); end: extra final fall (st).
const STYLES := {
	"klidne":   {"f0_st": 0.0,  "range": 1.0,  "accent": 1.6, "rate": 1.0,  "energy": 0.82, "breath": 0.06, "tilt": 0.0,   "f1": 1.0,  "pause": 1.0,  "voiced": 1.0, "end": 0.0},
	"vesele":   {"f0_st": 2.0,  "range": 1.45, "accent": 2.4, "rate": 1.08, "energy": 0.92, "breath": 0.05, "tilt": 0.15,  "f1": 1.03, "pause": 0.85, "voiced": 1.0, "end": 0.0},
	"nastvane": {"f0_st": 3.0,  "range": 1.3,  "accent": 3.0, "rate": 1.12, "energy": 1.0,  "breath": 0.03, "tilt": 0.38,  "f1": 1.10, "pause": 0.6,  "voiced": 1.0, "end": -1.5},
	"smutne":   {"f0_st": -1.5, "range": 0.55, "accent": 0.8, "rate": 0.82, "energy": 0.58, "breath": 0.20, "tilt": -0.28, "f1": 0.96, "pause": 1.4,  "voiced": 1.0, "end": -0.5},
	"unavene":  {"f0_st": -2.0, "range": 0.45, "accent": 0.6, "rate": 0.78, "energy": 0.55, "breath": 0.24, "tilt": -0.32, "f1": 0.97, "pause": 1.5,  "voiced": 1.0, "end": -0.8},
	"septem":   {"f0_st": 0.0,  "range": 0.0,  "accent": 0.0, "rate": 0.95, "energy": 0.46, "breath": 1.0,  "tilt": 0.05,  "f1": 1.0,  "pause": 1.1,  "voiced": 0.0, "end": 0.0},
}

## Formant targets (F1..F4, Hz) for an average tract (timbre 0).
const VOWEL_F := {
	"a": [730.0, 1250.0, 2550.0, 3500.0], "á": [760.0, 1250.0, 2550.0, 3500.0],
	"e": [530.0, 1800.0, 2500.0, 3550.0], "é": [560.0, 1850.0, 2550.0, 3550.0],
	"i": [320.0, 2150.0, 2900.0, 3650.0], "í": [280.0, 2300.0, 3000.0, 3750.0],
	"o": [500.0, 900.0, 2450.0, 3400.0],  "ó": [480.0, 850.0, 2450.0, 3400.0],
	"u": [340.0, 760.0, 2350.0, 3350.0],  "ú": [310.0, 680.0, 2300.0, 3350.0],
}
const DIPH := {"ou": ["o", "u"], "au": ["a", "u"], "eu": ["e", "u"]}
## Consonant acoustics. k: kind (N nasal, L lateral, R trill, RF trill-fricative, J glide,
## F fricative, P plosive, A affricate, H glottal); f: formants; v: voicing 0..1;
## nf/nbw: noise centre/bandwidth; na: noise amplitude; d: duration (s); loc: F2 locus for
## transitions into the following vowel.
const CONS := {
	"m": {"k": "N", "f": [260.0, 1000.0, 2300.0, 3300.0], "v": 1.0, "d": 0.065, "loc": 900.0},
	"n": {"k": "N", "f": [260.0, 1450.0, 2500.0, 3400.0], "v": 1.0, "d": 0.060, "loc": 1700.0},
	"ň": {"k": "N", "f": [260.0, 2050.0, 2800.0, 3500.0], "v": 1.0, "d": 0.068, "loc": 2200.0},
	"ŋ": {"k": "N", "f": [270.0, 1900.0, 2300.0, 3300.0], "v": 1.0, "d": 0.055, "loc": 1900.0},
	"l": {"k": "L", "f": [360.0, 1150.0, 2650.0, 3500.0], "v": 1.0, "d": 0.055, "loc": 1200.0},
	"r": {"k": "R", "f": [470.0, 1300.0, 1800.0, 3300.0], "v": 1.0, "d": 0.050, "loc": 1350.0},
	"j": {"k": "J", "f": [280.0, 2250.0, 3000.0, 3700.0], "v": 1.0, "d": 0.050, "loc": 2250.0},
	"ř": {"k": "RF", "f": [420.0, 1700.0, 2400.0, 3400.0], "v": 0.75, "nf": 3800.0, "nbw": 2200.0, "na": 0.45, "d": 0.075, "loc": 1800.0},
	"ř̊": {"k": "RF", "f": [420.0, 1700.0, 2400.0, 3400.0], "v": 0.0, "nf": 4000.0, "nbw": 2400.0, "na": 0.55, "d": 0.075, "loc": 1800.0},
	"s": {"k": "F", "f": [300.0, 1600.0, 2600.0, 3500.0], "v": 0.0, "nf": 5600.0, "nbw": 1800.0, "na": 0.75, "d": 0.090, "loc": 1750.0},
	"z": {"k": "F", "f": [280.0, 1600.0, 2600.0, 3500.0], "v": 0.45, "nf": 5400.0, "nbw": 1800.0, "na": 0.45, "d": 0.075, "loc": 1750.0},
	"š": {"k": "F", "f": [300.0, 1900.0, 2500.0, 3400.0], "v": 0.0, "nf": 2900.0, "nbw": 1500.0, "na": 0.85, "d": 0.090, "loc": 2000.0},
	"ž": {"k": "F", "f": [280.0, 1900.0, 2500.0, 3400.0], "v": 0.45, "nf": 2800.0, "nbw": 1500.0, "na": 0.5, "d": 0.075, "loc": 2000.0},
	"f": {"k": "F", "f": [300.0, 1100.0, 2400.0, 3400.0], "v": 0.0, "nf": 4200.0, "nbw": 5200.0, "na": 0.32, "d": 0.085, "loc": 900.0},
	"v": {"k": "F", "f": [300.0, 1100.0, 2400.0, 3400.0], "v": 0.8, "nf": 3800.0, "nbw": 4800.0, "na": 0.12, "d": 0.055, "loc": 900.0},
	"x": {"k": "F", "f": [400.0, 1500.0, 2400.0, 3400.0], "v": 0.0, "nf": 1500.0, "nbw": 1500.0, "na": 0.6, "d": 0.085, "loc": 1600.0},
	"h": {"k": "H", "f": [500.0, 1500.0, 2500.0, 3500.0], "v": 0.35, "nf": 1600.0, "nbw": 3000.0, "na": 0.5, "d": 0.060, "loc": 1500.0},
	"p": {"k": "P", "f": [300.0, 900.0, 2300.0, 3300.0], "v": 0.0, "nf": 900.0, "nbw": 1800.0, "na": 0.2, "d": 0.060, "loc": 850.0},
	"b": {"k": "P", "f": [250.0, 900.0, 2300.0, 3300.0], "v": 1.0, "nf": 900.0, "nbw": 1800.0, "na": 0.15, "d": 0.052, "loc": 850.0},
	"t": {"k": "P", "f": [300.0, 1700.0, 2600.0, 3500.0], "v": 0.0, "nf": 3900.0, "nbw": 2500.0, "na": 0.75, "d": 0.060, "loc": 1800.0},
	"d": {"k": "P", "f": [250.0, 1700.0, 2600.0, 3500.0], "v": 1.0, "nf": 3700.0, "nbw": 2500.0, "na": 0.5, "d": 0.052, "loc": 1800.0},
	"ť": {"k": "P", "f": [300.0, 2200.0, 2900.0, 3600.0], "v": 0.0, "nf": 3200.0, "nbw": 2000.0, "na": 0.75, "d": 0.062, "loc": 2250.0},
	"ď": {"k": "P", "f": [250.0, 2200.0, 2900.0, 3600.0], "v": 1.0, "nf": 3100.0, "nbw": 2000.0, "na": 0.5, "d": 0.055, "loc": 2250.0},
	"k": {"k": "P", "f": [300.0, 1900.0, 2300.0, 3300.0], "v": 0.0, "nf": 2100.0, "nbw": 1300.0, "na": 0.7, "d": 0.062, "loc": 1950.0},
	"g": {"k": "P", "f": [250.0, 1900.0, 2300.0, 3300.0], "v": 1.0, "nf": 2000.0, "nbw": 1300.0, "na": 0.5, "d": 0.055, "loc": 1950.0},
	"c": {"k": "A", "f": [300.0, 1700.0, 2600.0, 3500.0], "v": 0.0, "nf": 5400.0, "nbw": 2000.0, "na": 0.75, "d": 0.095, "loc": 1800.0},
	"dz": {"k": "A", "f": [260.0, 1700.0, 2600.0, 3500.0], "v": 0.5, "nf": 5200.0, "nbw": 2000.0, "na": 0.45, "d": 0.085, "loc": 1800.0},
	"č": {"k": "A", "f": [300.0, 2000.0, 2600.0, 3500.0], "v": 0.0, "nf": 3000.0, "nbw": 1600.0, "na": 0.85, "d": 0.095, "loc": 2050.0},
	"dž": {"k": "A", "f": [260.0, 2000.0, 2600.0, 3500.0], "v": 0.5, "nf": 2900.0, "nbw": 1600.0, "na": 0.5, "d": 0.085, "loc": 2050.0},
}
const SHORT_VOWEL := 0.072
const LONG_FACTOR := 1.72
const DIPH_DUR := 0.150
const FORMANT_GAIN := [1.0, 0.62, 0.30, 0.16]
const FORMANT_BW := [80.0, 100.0, 140.0, 210.0]
const PAUSES := {"continue": 0.16, "statement": 0.36, "question": 0.38, "wh": 0.38, "exclaim": 0.34, "trail": 0.5}


## Stable FNV-1a hash over Unicode code points (independent of Godot's String.hash()).
static func text_hash(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = ((h ^ s.unicode_at(i)) * 16777619) & 0xffffffff
	return h & 0x7fffffff


static func style_or_default(style: Variant) -> String:
	if typeof(style) == TYPE_STRING and STYLES.has(style):
		return String(style)
	return "klidne"


static func _num(v: Dictionary, key: String, def: float, lo: float, hi: float) -> float:
	var x: Variant = v.get(key, def)
	if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
		return def
	var f := float(x)
	if not is_finite(f):
		return def
	return roundf(clampf(f, lo, hi) * 1000.0) / 1000.0


## Public voice parameters only (same mapping as VoiceSynth.params()).
static func voice_params(voice: Variant) -> Dictionary:
	var v: Dictionary = voice if voice is Dictionary else {}
	var pitch := _num(v, "pitch", 0.0, -1.0, 1.0)
	var timbre := _num(v, "timbre", 0.0, -1.0, 1.0)
	var tempo := _num(v, "tempo", 0.0, -1.0, 1.0)
	var rough := _num(v, "roughness", 0.2, 0.0, 1.0)
	return {"f0": BASE_F0 * pow(2.0, pitch * PITCH_OCTAVES), "tract": pow(2.0, timbre * TRACT_OCTAVES),
		"bright": 0.5 + 0.5 * timbre, "tempo": pow(2.0, tempo * TEMPO_OCTAVES), "rough": rough}


## Sanitised, length-capped text that the synthesiser actually speaks.
static func clean_text(text: Variant) -> String:
	var s: String = text if typeof(text) == TYPE_STRING else ""
	if s.length() > MAX_CHARS:
		s = s.substr(0, MAX_CHARS)
	return s


## Timed plan: segments, syllables, F0 contour and phrase info. Public for tests.
##   segments: [{ph, kind, t, d, syl, voiced, stress}]
##   syllables: [{t0, t1, nt0, nt1 (nucleus), stress, long, phrase, unit}]
##   f0: PackedFloat32Array (Hz every F0_STEP s), phrases: [{kind, t0, t1}]
static func plan(text: Variant, voice: Variant = {}, style: Variant = "klidne") -> Dictionary:
	var st := style_or_default(style)
	var mods: Dictionary = STYLES[st]
	var vp := voice_params(voice)
	var src := clean_text(text)
	var phrases: Array = G2P.prosody(src)
	var speed: float = float(vp["tempo"]) * float(mods["rate"])
	var segs: Array = []
	var sylls: Array = []
	var ph_info: Array = []
	var t := 0.06
	for pi in phrases.size():
		var phr: Dictionary = phrases[pi]
		var kind: String = phr["kind"]
		var p_t0 := t
		var ps: Array = phr["syllables"]
		for si in ps.size():
			var sy: Dictionary = ps[si]
			var last := si == ps.size() - 1
			var syl_t0 := t
			var nuc_t0 := t
			var nuc_t1 := t
			var phs: Array = sy["ph"]
			var nuc: int = int(sy["nucleus"])
			for k in phs.size():
				var p: String = phs[k]
				var d := _dur(p, k == nuc, bool(sy["stress"])) / speed
				if k == nuc:
					if last:
						d *= 1.45 if kind != "trail" else 1.9
					elif si == ps.size() - 2:
						d *= 1.12
					nuc_t0 = t
					nuc_t1 = t + d
				segs.append({"ph": p, "t": t, "d": d, "syl": sylls.size(), "nucleus": k == nuc,
					"stress": bool(sy["stress"]), "phrase": pi})
				t += d
			if nuc < 0:
				nuc_t0 = syl_t0
				nuc_t1 = t
			sylls.append({"t0": syl_t0, "t1": t, "nt0": nuc_t0, "nt1": nuc_t1, "stress": bool(sy["stress"]),
				"long": bool(sy["long"]), "phrase": pi, "unit": int(sy["unit"]), "last": last})
			if t > MAX_DURATION - 0.4:
				break
		ph_info.append({"kind": kind, "t0": p_t0, "t1": t})
		if t > MAX_DURATION - 0.4:
			break
		if pi < phrases.size() - 1:
			t += float(PAUSES.get(kind, 0.3)) * float(mods["pause"])
	var dur := minf(t + 0.14, MAX_DURATION)
	var f0 := _f0_track(sylls, ph_info, dur, vp, mods)
	return {"segments": segs, "syllables": sylls, "phrases": ph_info, "f0": f0, "duration": dur,
		"style": st, "text": src, "phonemes": G2P.phonemes(src)}


static func _dur(p: String, is_nucleus: bool, stressed: bool) -> float:
	if G2P.DIPHTHONGS.has(p):
		return DIPH_DUR * (1.06 if stressed else 1.0)
	if G2P.VOWELS.has(p):
		var d := SHORT_VOWEL * (LONG_FACTOR if G2P.LONG_VOWELS.has(p) else 1.0)
		return d * (1.06 if stressed else 1.0)
	var c: Dictionary = CONS.get(p, {"d": 0.06})
	var d: float = c["d"]
	if is_nucleus:
		# Syllabic r / l / m (krk, vlk, sedm) are lengthened into a vowel-like nucleus.
		d = maxf(d, 0.085) * 1.15
	return d


## F0 contour in Hz sampled every F0_STEP seconds. Points are built in semitones relative to
## the speaker's base, then linearly interpolated and smoothed.
static func _f0_track(sylls: Array, phr: Array, dur: float, vp: Dictionary, mods: Dictionary) -> PackedFloat32Array:
	var base := float(vp["f0"]) * pow(2.0, float(mods["f0_st"]) / 12.0)
	var rng_scale: float = mods["range"]
	var accent: float = mods["accent"]
	var pts: Array = []  # [t, semitones]
	var total := maxf(dur, 0.1)
	for pi in phr.size():
		var info: Dictionary = phr[pi]
		var kind: String = info["kind"]
		var r := rng_scale * (1.5 if kind == "exclaim" else 1.0)
		var acc := accent * (1.6 if kind == "exclaim" else 1.0)
		var lift := 1.5 if kind == "exclaim" else 0.0
		# Syllables of this phrase.
		var ps: Array = []
		for s in sylls:
			if int(s["phrase"]) == pi:
				ps.append(s)
		if ps.is_empty():
			continue
		var last_stress := -1
		for k in ps.size():
			if bool(ps[k]["stress"]):
				last_stress = k
		if last_stress < 0:
			last_stress = 0
		for k in ps.size():
			var s: Dictionary = ps[k]
			var mid := (float(s["nt0"]) + float(s["nt1"])) * 0.5
			# Utterance declination (≈ 3 st over the whole utterance) + phrase reset.
			var decl := 1.6 * r - 3.2 * r * (mid / total)
			var p_rel := (mid - float(info["t0"])) / maxf(float(info["t1"]) - float(info["t0"]), 0.05)
			decl += 0.8 * r * (0.5 - p_rel)
			var v := decl + lift
			var is_final_region := k >= last_stress
			if bool(s["stress"]) and not (is_final_region and (kind == "question")):
				v += acc * (1.25 if k == 0 and kind == "wh" else 1.0)
			if kind == "wh" and k == 0:
				v += 1.6 * r
			if is_final_region:
				var span := maxf(float(ps.size() - 1 - last_stress), 1.0)
				var q := float(k - last_stress) / span if ps.size() - 1 > last_stress else 0.0
				match kind:
					"statement", "wh", "exclaim":
						if k == ps.size() - 1:
							v -= (2.2 + 1.4 * r) + float(mods["end"]) * -1.0 + (1.0 if kind == "wh" else 0.0)
						else:
							v -= q * 1.5 * r
					"question":
						# Low last stressed syllable, then a rise to the end.
						v += -1.2 * r + q * 0.0
					"continue":
						if k == ps.size() - 1:
							v += 1.6 * r
					"trail":
						v -= (2.5 + 2.0 * r) * maxf(q, 0.5)
			pts.append([float(s["nt0"]), v - (0.25 if bool(s["stress"]) else 0.0)])
			pts.append([mid, v])
			if k == ps.size() - 1:
				var end_v := v
				match kind:
					"question":
						end_v = v + 4.5 + 3.5 * r
					"statement", "wh", "exclaim":
						end_v = v - 1.2 * r - 0.8
					"continue":
						end_v = v + 1.4 * r
					"trail":
						end_v = v - 2.0 * r - 1.0
				pts.append([float(s["nt1"]), end_v])
			else:
				pts.append([float(s["nt1"]), v - 0.3 * r])
	var n := int(ceil(dur / F0_STEP)) + 1
	var out := PackedFloat32Array()
	out.resize(n)
	if pts.is_empty():
		out.fill(base)
		return out
	var j := 0
	var smooth := float(pts[0][1])
	for i in n:
		var tt := float(i) * F0_STEP
		while j < pts.size() - 1 and float(pts[j + 1][0]) <= tt:
			j += 1
		var v: float
		if tt <= float(pts[0][0]):
			v = float(pts[0][1])
		elif j >= pts.size() - 1:
			v = float(pts[pts.size() - 1][1])
		else:
			var a: Array = pts[j]
			var b: Array = pts[j + 1]
			var w := clampf((tt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4), 0.0, 1.0)
			v = lerpf(float(a[1]), float(b[1]), w)
		smooth += (v - smooth) * 0.35
		# Bounded excursion around the speaker's own base: lively but never squeaky/unnatural.
		out[i] = base * pow(2.0, clampf(smooth, -10.0, 8.0) / 12.0)
	return out


## Convenience for tests: F0 contour (Hz) with the voiced-nucleus mask.
static func f0_contour(text: Variant, voice: Variant = {}, style: Variant = "klidne") -> Dictionary:
	var pl := plan(text, voice, style)
	return {"f0": pl["f0"], "step": F0_STEP, "syllables": pl["syllables"], "phrases": pl["phrases"]}


## Render speech to mono float samples.
static func render(text: Variant, voice: Variant = {}, style: Variant = "klidne", sr: int = SR) -> PackedFloat32Array:
	var pl := plan(text, voice, style)
	return render_plan(pl, voice, sr)


static func render_plan(pl: Dictionary, voice: Variant, sr: int = SR) -> PackedFloat32Array:
	var st: String = pl["style"]
	var mods: Dictionary = STYLES[st]
	var vp := voice_params(voice)
	sr = clampi(sr, 8000, 48000)
	var dur: float = pl["duration"]
	var segs: Array = pl["segments"]
	var f0tr: PackedFloat32Array = pl["f0"]
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	if segs.is_empty():
		return buf
	var rng := RandomNumberGenerator.new()
	rng.seed = text_hash(String(pl["text"]) + "|" + st) ^ 0x2545F491
	var inv := 1.0 / float(sr)
	var nyq := 0.45 * float(sr)
	var tract: float = vp["tract"]
	var rough: float = vp["rough"]
	var voiced_style: float = mods["voiced"]
	var breath: float = clampf(float(mods["breath"]) + 0.10 * rough, 0.0, 1.0)
	var energy: float = mods["energy"]
	var f1_mul: float = mods["f1"]
	var bright := clampf(float(vp["bright"]) + float(mods["tilt"]), 0.0, 1.2)
	var tilt_a := 1.0 - exp(-TAU * (700.0 + 2600.0 * bright) * inv)
	var tp := 0.42
	var tn := clampf(0.18 - 0.07 * float(mods["tilt"]), 0.08, 0.24)
	var jitter := 0.004 + 0.028 * rough
	var shimmer := 0.03 + 0.16 * rough
	var subharm := clampf((rough - 0.35) / 0.65, 0.0, 1.0) * 0.55
	var bw_mul := 1.0 + 0.8 * breath
	var bw1: float = FORMANT_BW[0] * bw_mul
	var bw2: float = FORMANT_BW[1] * bw_mul
	var bw3: float = FORMANT_BW[2] * bw_mul
	var bw4: float = FORMANT_BW[3] * bw_mul
	var g2: float = FORMANT_GAIN[1]
	var g3: float = FORMANT_GAIN[2]
	var g4: float = FORMANT_GAIN[3]
	# Synthesis state.
	var phase := 0.0
	var period_mul := 1.0
	var amp_mul := 1.0
	var period_index := 0
	var prev_u := 0.0
	var tilt_y := 0.0
	var c1 := 500.0 * tract
	var c2 := 1500.0 * tract
	var c3 := 2500.0 * tract
	var c4 := 3500.0 * tract
	var y11 := 0.0
	var y12 := 0.0
	var y21 := 0.0
	var y22 := 0.0
	var y31 := 0.0
	var y32 := 0.0
	var y41 := 0.0
	var y42 := 0.0
	var a11 := 0.0
	var a12 := 0.0
	var b1 := 0.0
	var a21 := 0.0
	var a22 := 0.0
	var b2 := 0.0
	var a31 := 0.0
	var a32 := 0.0
	var b3 := 0.0
	var a41 := 0.0
	var a42 := 0.0
	var b4 := 0.0
	var nz1 := 0.0
	var nz2 := 0.0
	var nw1 := 0.0
	var nw2 := 0.0
	var na1 := 0.0
	var na2 := 0.0
	var nb0 := 0.0
	var ncur := 3000.0
	var nbw_cur := 2000.0
	var dc_x := 0.0
	var dc_y := 0.0
	var coart := 1.0 - exp(-inv / 0.013)
	var env_rate := 1.0 - exp(-inv / 0.005)
	var nenv_rate := 1.0 - exp(-inv / 0.004)
	var venv := 0.0
	var nenv := 0.0
	var oenv := 1.0
	# Current segment scalars.
	var si := -1
	var s_t := 0.0
	var s_end := -1.0
	var kind := ""
	var t1 := 500.0
	var t2 := 1500.0
	var t3 := 2500.0
	var t4 := 3500.0
	var e1 := 500.0
	var e2 := 1500.0
	var tgt_v := 0.0
	var tgt_n := 0.0
	var tgt_o := 0.0
	var nf := 3000.0
	var nbw := 2000.0
	var seg_d := 0.1
	var trill := false
	var diph := false
	var fade := 1.0
	var sr_f := float(sr)
	var last_seg: int = segs.size() - 1
	var trail_t0 := 1e9
	for info in pl["phrases"]:
		if String(info["kind"]) == "trail":
			trail_t0 = minf(trail_t0, float(info["t1"]) - 0.35)
	for i in n:
		var tt := float(i) * inv
		# Advance to the segment covering tt (silence in pauses).
		while si < last_seg and tt >= s_end:
			var nxt: Dictionary = segs[si + 1]
			if tt < float(nxt["t"]):
				break
			si += 1
			var s: Dictionary = segs[si]
			s_t = s["t"]
			seg_d = s["d"]
			s_end = s_t + seg_d
			var p: String = s["ph"]
			diph = false
			trill = false
			tgt_n = 0.0
			tgt_o = float(OUT_GAIN.get(p, 1.0))
			if bool(s["nucleus"]) and not VOWEL_F.has(p) and not DIPH.has(p):
				tgt_o = maxf(tgt_o, 0.6)
			if VOWEL_F.has(p) or DIPH.has(p):
				kind = "V"
				var q: Array
				var q2: Array
				if DIPH.has(p):
					diph = true
					q = VOWEL_F[DIPH[p][0]]
					q2 = VOWEL_F[DIPH[p][1]]
				else:
					q = VOWEL_F[p]
					q2 = q
				t1 = minf(float(q[0]) * tract * f1_mul, nyq)
				t2 = minf(float(q[1]) * tract, nyq)
				t3 = minf(float(q[2]) * tract, nyq)
				t4 = minf(float(q[3]) * tract, nyq)
				e1 = minf(float(q2[0]) * tract * f1_mul, nyq)
				e2 = minf(float(q2[1]) * tract, nyq)
				tgt_v = 1.0 if bool(s["stress"]) else 0.82
			else:
				var c: Dictionary = CONS.get(p, CONS["t"])
				kind = String(c["k"])
				var q: Array = c["f"]
				t1 = minf(float(q[0]) * tract, nyq)
				t2 = minf(float(q[1]) * tract, nyq)
				t3 = minf(float(q[2]) * tract, nyq)
				t4 = minf(float(q[3]) * tract, nyq)
				e1 = t1
				e2 = t2
				tgt_v = float(c["v"])
				nf = minf(float(c.get("nf", 3000.0)) * (0.92 + 0.16 * tract), nyq)
				nbw = float(c.get("nbw", 2000.0))
				tgt_n = float(c.get("na", 0.0))
				match kind:
					"N":
						tgt_v = 0.55
					"L":
						tgt_v = 0.72
					"J":
						tgt_v = 0.7
					"R", "RF":
						trill = true
						tgt_v = 0.75 * float(c["v"]) if kind == "RF" else 0.78
					"H":
						tgt_v = 0.3
				if bool(s["nucleus"]):
					tgt_v = maxf(tgt_v, 0.8)
				# Plosive release: pull formants towards the locus of the next vowel onset.
				if kind == "P" or kind == "A":
					c2 = lerpf(c2, float(c["loc"]) * tract, 0.6)
			if absf(nf - ncur) > 1.0 or absf(nbw - nbw_cur) > 1.0:
				ncur = nf
				nbw_cur = nbw
				var cr := exp(-PI * nbw_cur * inv)
				na1 = 2.0 * cr * cos(TAU * ncur * inv)
				na2 = cr * cr
				nb0 = (1.0 - cr * cr) * 0.5
		var in_seg := si >= 0 and tt >= s_t and tt < s_end
		var lt := tt - s_t
		var v_amp := 0.0
		var n_amp := 0.0
		if in_seg:
			match kind:
				"P":
					# Closure (voice bar for voiced plosives) then a short burst; no aspiration.
					var burst_t := seg_d - 0.013
					if lt < burst_t:
						v_amp = 0.10 * tgt_v
						n_amp = 0.0
					else:
						v_amp = 0.15 * tgt_v
						n_amp = tgt_n * 1.6 * (1.0 - (lt - burst_t) / 0.013)
				"A":
					var clos := seg_d * 0.35
					if lt < clos:
						v_amp = 0.08 * tgt_v
						n_amp = 0.0 if lt < clos - 0.006 else tgt_n * 1.4
					else:
						v_amp = 0.35 * tgt_v
						n_amp = tgt_n
				"F", "H":
					v_amp = tgt_v * (0.55 if kind == "F" else 1.0)
					n_amp = tgt_n
				_:
					v_amp = tgt_v
					n_amp = tgt_n
			if trill:
				# Tongue-tip trill: 1 tap (short r) or 2-3 cycles (ř, syllabic r) at ~28 Hz.
				var cyc := 28.0
				var am := 0.25 + 0.75 * absf(cos(PI * cyc * lt))
				if kind == "R" and seg_d < 0.065:
					am = 1.0 - 0.75 * exp(-pow((lt - seg_d * 0.5) / 0.009, 2.0))
				v_amp *= am
				n_amp *= 0.4 + 0.6 * am
		venv += (v_amp - venv) * env_rate
		nenv += (n_amp - nenv) * nenv_rate
		oenv += ((tgt_o if in_seg else oenv) - oenv) * env_rate
		if diph and in_seg:
			var w := smoothstep(0.25, 0.85, lt / maxf(seg_d, 0.01))
			c1 += (lerpf(t1, e1, w) - c1) * coart * 1.5
			c2 += (lerpf(t2, e2, w) - c2) * coart * 1.5
		else:
			c1 += (t1 - c1) * coart
			c2 += (t2 - c2) * coart
		c3 += (t3 - c3) * coart
		c4 += (t4 - c4) * coart
		if i % COEF_BLOCK == 0:
			var bwn := 1.0 if kind != "N" else 1.7
			var r := exp(-PI * bw1 * bwn * inv)
			a11 = 2.0 * r * cos(TAU * c1 * inv)
			a12 = r * r
			b1 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw2 * bwn * inv)
			a21 = 2.0 * r * cos(TAU * c2 * inv)
			a22 = r * r
			b2 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw3 * bwn * inv)
			a31 = 2.0 * r * cos(TAU * c3 * inv)
			a32 = r * r
			b3 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw4 * inv)
			a41 = 2.0 * r * cos(TAU * c4 * inv)
			a42 = r * r
			b4 = (1.0 - r * r) * 0.5
		# F0 from the precomputed contour (linear interpolation).
		var fi := tt / F0_STEP
		var i0 := mini(int(fi), f0tr.size() - 1)
		var i1 := mini(i0 + 1, f0tr.size() - 1)
		var f0 := lerpf(f0tr[i0], f0tr[i1], fi - float(i0))
		phase += f0 * inv * period_mul
		if phase >= 1.0:
			phase -= floorf(phase)
			period_index += 1
			period_mul = 1.0 + (rng.randf() * 2.0 - 1.0) * jitter
			amp_mul = 1.0 + (rng.randf() * 2.0 - 1.0) * shimmer
			if subharm > 0.0 and period_index % 2 == 1:
				amp_mul *= 1.0 - subharm
		var u := 0.0
		if phase < tp:
			u = 0.5 * (1.0 - cos(PI * phase / tp))
		elif phase < tp + tn:
			u = cos(0.5 * PI * (phase - tp) / tn)
		var glott := (u - prev_u) * sr_f / maxf(f0, 40.0) * 0.12
		prev_u = u
		var noise := rng.randf() * 2.0 - 1.0
		var asp := breath + (0.55 if kind == "H" and in_seg else 0.0)
		var src := voiced_style * glott * amp_mul * venv + noise * asp * (0.35 + 0.65 * u) * 0.9 * maxf(venv, 0.25 if kind == "H" else 0.0) \
			+ noise * rough * 0.04 * venv * voiced_style
		if voiced_style < 0.5:
			# Whisper: aspiration noise through the tract, amplitude follows the voicing envelope.
			src = noise * venv * 0.8
		tilt_y += tilt_a * (src - tilt_y)
		var source := tilt_y
		var f1o := b1 * source + a11 * y11 - a12 * y12
		y12 = y11
		y11 = f1o
		var f2o := b2 * source + a21 * y21 - a22 * y22
		y22 = y21
		y21 = f2o
		var f3o := b3 * source + a31 * y31 - a32 * y32
		y32 = y31
		y31 = f3o
		var f4o := b4 * source + a41 * y41 - a42 * y42
		y42 = y41
		y41 = f4o
		var vowel := f1o + f2o * g2 + f3o * g3 + f4o * g4
		if kind == "N":
			vowel *= 0.7
		var fric := 0.0
		if nenv > 0.0005:
			var nsrc := noise
			if kind == "RF" or (kind == "F" and tgt_v > 0.0):
				nsrc *= 0.55 + 0.45 * u
			# Two cascaded resonators = band-limited (4th order) frication noise.
			var ny := nb0 * nsrc + na1 * nz1 - na2 * nz2
			nz2 = nz1
			nz1 = ny
			var nw := nb0 * ny + na1 * nw1 - na2 * nw2
			nw2 = nw1
			nw1 = nw
			fric = nw * nenv * NOISE_GAIN * sqrt(maxf(nbw_cur, 200.0) / 2000.0)
		var x := (vowel * 6.0 + fric) * energy * oenv
		if tt > trail_t0:
			x *= clampf(1.0 - (tt - trail_t0) / 0.6, 0.25, 1.0)
		dc_y = x - dc_x + 0.995 * dc_y
		dc_x = x
		buf[i] = dc_y
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	if peak > 1e-6:
		var g := 0.82 * energy / peak
		var k := 1.0 / tanh(1.15)
		for i in n:
			buf[i] = tanh(buf[i] * g * 1.15) * k
	# Never clip: tanh normalisation keeps |x| ≤ 0.82 * energy * (1/tanh(1.15)) scaled; clamp anyway.
	for i in n:
		buf[i] = clampf(buf[i], -0.98, 0.98)
	return buf
