extends RefCounted
## CzechTTS – self-contained Czech text-to-speech (formant synthesis + rule-based prosody).
##
## No network, no external engine, no recorded samples. Text → CzechG2P (phonemes, syllables,
## stress units, phrase types) → timed segment plan + F0 contour → source–filter synthesis.
## Inputs are ONLY the text and the public voice parameters (CharacterData.voice: pitch,
## timbre, tempo, roughness) plus a style. Nothing is derived from gender, identity, name or
## body. Same input → bit-identical output on every peer (own hash + own seeded RNG).
##
## Prosody (standard Czech):
##   - fixed stress on the first syllable of each stress unit (monosyllabic prepositions
##     carry the stress of the next word, enclitics are unstressed);
##   - F0 declination across the utterance;
##   - statement: final fall; yes/no question: low last stressed syllable, then a rise to the
##     end; wh-question (kdo, co, kde, …): high start, falling end; exclamation: wider range,
##     stronger accents; comma: slight rise + short pause; period: longer pause; ellipsis:
##     trailing low with fade;
##   - micro-prosody: smooth (cosine + zero-phase smoothed) contour, slow deterministic drift,
##     intrinsic vowel pitch, F0 perturbation after voiceless / voiced obstruents;
##   - long vowels ~1.7× short; phrase-final lengthening and softening; tempo from
##     voice.tempo × style.
##
## Synthesis (v2, "natural voice" rework, Oct 2026):
##   - glottal source: KLGLOTT88 flow-derivative pulse with a style-dependent open quotient,
##     band-limited closure (polyBLEP), extra spectral tilt, Gaussian jitter/shimmer that stays
##     small (≈0.5 % / 3 %) unless roughness is high, and pulsed aspiration noise mixed in
##     (more at phrase onsets/offsets and in breathy styles);
##   - vocal tract: Klatt cascade of five unity-gain resonators (realistic bandwidths) so the
##     relative formant amplitudes follow from the formant frequencies; nasal antiformant and
##     murmur low-pass for m/n/ň/ŋ; tract length scaled from timbre within ±12 %;
##   - all control parameters (formants, bandwidths, voicing, aspiration, frication, nasality)
##     are tracks at control rate, built from per-segment targets and smoothed with a
##     zero-phase critically damped filter → 30–70 ms formant transitions, undershoot in short
##     syllables, F2 loci per place of articulation, no amplitude steps;
##   - consonants: place-shaped frication (s, š, f/v, x, h), plosive closure (voice bar for
##     b/d/ď/g) + place-shaped burst + short aspiration, r as 1–2 taps, ř trill + friction;
##   - output: DC block, gentle low-pass, very light deterministic early reflections, light
##     compression, peak normalisation (≈ −3 dBFS for the loudest style), short fades.

const G2P := preload("res://scripts/audio/czech_g2p.gd")

const SR := 22050
const MAX_DURATION := 16.0
const MAX_CHARS := 200
const BASE_F0 := 160.0
const PITCH_OCTAVES := 1.05
const TRACT_OCTAVES := 0.16
const TEMPO_OCTAVES := 0.6
const F0_STEP := 0.005
## Control-rate frame (samples); formant coefficients are recomputed once per frame.
const CTRL := 16
## Absolute F0 limits (Hz): lively but never squeaky or growly.
const F0_MIN := 50.0
const F0_MAX := 420.0

## Style modifiers for speech. f0_st: mean shift (semitones); range: intonation range scale;
## accent: stress accent size (st); rate: speaking rate; energy; breath: aspiration level;
## tilt: source brightness (+ brighter); oq: glottal open quotient (lower = more pressed);
## f1: larynx tension; pause: pause scale; voiced (0 = whisper); end: extra final fall (st).
const STYLES := {
	"klidne":   {"f0_st": 0.0,  "range": 1.0,  "accent": 1.6, "rate": 1.0,  "energy": 0.82, "breath": 0.13, "tilt": 0.0,   "oq": 0.62, "f1": 1.0,  "pause": 1.0,  "voiced": 1.0, "end": 0.0},
	"vesele":   {"f0_st": 2.0,  "range": 1.45, "accent": 2.4, "rate": 1.08, "energy": 0.92, "breath": 0.11, "tilt": 0.22,  "oq": 0.56, "f1": 1.03, "pause": 0.85, "voiced": 1.0, "end": 0.0},
	"nastvane": {"f0_st": 2.0,  "range": 1.2,  "accent": 2.8, "rate": 1.1,  "energy": 1.0,  "breath": 0.07, "tilt": 0.36,  "oq": 0.5,  "f1": 1.08, "pause": 0.6,  "voiced": 1.0, "end": -1.5},
	"smutne":   {"f0_st": -1.5, "range": 0.55, "accent": 0.8, "rate": 0.82, "energy": 0.62, "breath": 0.26, "tilt": -0.5,  "oq": 0.72, "f1": 0.96, "pause": 1.4,  "voiced": 1.0, "end": -0.5},
	"unavene":  {"f0_st": -2.0, "range": 0.45, "accent": 0.6, "rate": 0.78, "energy": 0.6,  "breath": 0.30, "tilt": -0.52, "oq": 0.74, "f1": 0.97, "pause": 1.5,  "voiced": 1.0, "end": -0.8},
	"septem":   {"f0_st": 0.0,  "range": 0.0,  "accent": 0.0, "rate": 0.95, "energy": 0.5,  "breath": 1.0,  "tilt": 0.05,  "oq": 0.6,  "f1": 1.0,  "pause": 1.1,  "voiced": 0.0, "end": 0.0},
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
## Intrinsic vowel pitch (semitones): close vowels slightly higher, open vowels lower.
const VOWEL_F0 := {"i": 0.35, "í": 0.35, "u": 0.3, "ú": 0.3, "a": -0.25, "á": -0.25}
## Neutral tract (reduction target for short unstressed vowels).
const NEUTRAL_F := [500.0, 1500.0, 2500.0, 3500.0]
## Consonant acoustics. k: kind (N nasal, L lateral, R trill, RF trill-fricative, J glide,
## F fricative, P plosive, A affricate, H glottal); f: formants (F2 = locus for the CV
## transition); v: voicing 0..1; nf/nbw: frication (or burst) noise centre/bandwidth;
## na: noise amplitude; d: duration (s); nz: nasal antiformant (Hz).
const CONS := {
	"m": {"k": "N", "f": [260.0, 1000.0, 2300.0, 3300.0], "v": 1.0, "d": 0.065, "nz": 1000.0},
	"n": {"k": "N", "f": [260.0, 1550.0, 2550.0, 3400.0], "v": 1.0, "d": 0.060, "nz": 1750.0},
	"ň": {"k": "N", "f": [260.0, 2100.0, 2800.0, 3500.0], "v": 1.0, "d": 0.068, "nz": 2350.0},
	"ŋ": {"k": "N", "f": [270.0, 1900.0, 2300.0, 3300.0], "v": 1.0, "d": 0.055, "nz": 2900.0},
	"l": {"k": "L", "f": [360.0, 1250.0, 2550.0, 3500.0], "v": 1.0, "d": 0.055},
	"r": {"k": "R", "f": [460.0, 1350.0, 2100.0, 3300.0], "v": 1.0, "d": 0.050},
	"j": {"k": "J", "f": [280.0, 2200.0, 2950.0, 3700.0], "v": 1.0, "d": 0.052},
	"ř": {"k": "RF", "f": [420.0, 1700.0, 2400.0, 3400.0], "v": 0.75, "nf": 3600.0, "nbw": 2000.0, "na": 0.40, "d": 0.078},
	"ř̊": {"k": "RF", "f": [420.0, 1700.0, 2400.0, 3400.0], "v": 0.0, "nf": 3800.0, "nbw": 2200.0, "na": 0.50, "d": 0.078},
	"s": {"k": "F", "f": [300.0, 1700.0, 2600.0, 3500.0], "v": 0.0, "nf": 5600.0, "nbw": 2600.0, "na": 0.62, "d": 0.090},
	"z": {"k": "F", "f": [280.0, 1700.0, 2600.0, 3500.0], "v": 0.6, "nf": 5400.0, "nbw": 2600.0, "na": 0.36, "d": 0.075},
	"š": {"k": "F", "f": [300.0, 1900.0, 2500.0, 3400.0], "v": 0.0, "nf": 3100.0, "nbw": 1900.0, "na": 0.62, "d": 0.090},
	"ž": {"k": "F", "f": [280.0, 1900.0, 2500.0, 3400.0], "v": 0.6, "nf": 3000.0, "nbw": 1900.0, "na": 0.36, "d": 0.075},
	"f": {"k": "F", "f": [300.0, 1100.0, 2400.0, 3400.0], "v": 0.0, "nf": 4000.0, "nbw": 6000.0, "na": 0.22, "d": 0.085},
	"v": {"k": "F", "f": [300.0, 1100.0, 2400.0, 3400.0], "v": 0.8, "nf": 3800.0, "nbw": 6000.0, "na": 0.08, "d": 0.055},
	"x": {"k": "F", "f": [400.0, 1500.0, 2400.0, 3400.0], "v": 0.0, "nf": 1900.0, "nbw": 1800.0, "na": 0.40, "d": 0.085},
	"h": {"k": "H", "f": [500.0, 1500.0, 2500.0, 3500.0], "v": 0.35, "d": 0.060},
	"p": {"k": "P", "f": [300.0, 900.0, 2300.0, 3300.0], "v": 0.0, "nf": 1200.0, "nbw": 3000.0, "na": 0.30, "d": 0.060},
	"b": {"k": "P", "f": [250.0, 900.0, 2300.0, 3300.0], "v": 1.0, "nf": 1200.0, "nbw": 3000.0, "na": 0.20, "d": 0.052},
	"t": {"k": "P", "f": [300.0, 1750.0, 2650.0, 3500.0], "v": 0.0, "nf": 4200.0, "nbw": 2600.0, "na": 0.55, "d": 0.060},
	"d": {"k": "P", "f": [250.0, 1750.0, 2650.0, 3500.0], "v": 1.0, "nf": 4000.0, "nbw": 2600.0, "na": 0.38, "d": 0.052},
	"ť": {"k": "P", "f": [300.0, 2200.0, 2900.0, 3600.0], "v": 0.0, "nf": 3300.0, "nbw": 2000.0, "na": 0.55, "d": 0.062},
	"ď": {"k": "P", "f": [250.0, 2200.0, 2900.0, 3600.0], "v": 1.0, "nf": 3200.0, "nbw": 2000.0, "na": 0.38, "d": 0.055},
	"k": {"k": "P", "f": [300.0, 1900.0, 2300.0, 3300.0], "v": 0.0, "nf": 2200.0, "nbw": 1200.0, "na": 0.55, "d": 0.062},
	"g": {"k": "P", "f": [250.0, 1900.0, 2300.0, 3300.0], "v": 1.0, "nf": 2100.0, "nbw": 1200.0, "na": 0.38, "d": 0.055},
	"c": {"k": "A", "f": [300.0, 1750.0, 2600.0, 3500.0], "v": 0.0, "nf": 5400.0, "nbw": 2600.0, "na": 0.6, "d": 0.095},
	"dz": {"k": "A", "f": [260.0, 1750.0, 2600.0, 3500.0], "v": 0.5, "nf": 5200.0, "nbw": 2600.0, "na": 0.36, "d": 0.085},
	"č": {"k": "A", "f": [300.0, 2000.0, 2600.0, 3500.0], "v": 0.0, "nf": 3100.0, "nbw": 1900.0, "na": 0.6, "d": 0.095},
	"dž": {"k": "A", "f": [260.0, 2000.0, 2600.0, 3500.0], "v": 0.5, "nf": 3000.0, "nbw": 1900.0, "na": 0.36, "d": 0.085},
}
const SHORT_VOWEL := 0.085
const LONG_FACTOR := 1.72
const DIPH_DUR := 0.165
## Cascade bandwidths (Hz) for F1..F5 (F5 is a fixed higher pole).
const FORMANT_BW := [70.0, 95.0, 150.0, 220.0, 300.0]
const F5 := 4500.0
## Sixth fixed pole (Hz, bandwidth) – keeps natural "air" above 4.5 kHz instead of a dull cliff.
const F6 := 5600.0
const B6 := 500.0
const PAUSES := {"continue": 0.2, "statement": 0.42, "question": 0.42, "wh": 0.42, "exclaim": 0.38, "trail": 0.55}
## Smoothing time constants (s) of the control tracks (zero-phase, two passes each way).
const TAU_FORMANT := 0.009
const TAU_AMP := 0.0035
const TAU_NOISE := 0.0022
const TAU_SLOW := 0.006
## Early reflections (s, gain): a small furnished room, very light.
const REFLECTIONS := [[0.0071, 0.10], [0.0113, 0.08], [0.0167, 0.065], [0.0239, 0.05], [0.0331, 0.035], [0.0457, 0.022]]


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
			if t > MAX_DURATION - 0.6:
				break
		ph_info.append({"kind": kind, "t0": p_t0, "t1": t})
		if t > MAX_DURATION - 0.6:
			break
		if pi < phrases.size() - 1:
			t += float(PAUSES.get(kind, 0.3)) * float(mods["pause"])
	var dur := minf(t + 0.2, MAX_DURATION)
	var f0 := _f0_track(sylls, ph_info, segs, dur, vp, mods, text_hash(src + "|f0|" + st))
	return {"segments": segs, "syllables": sylls, "phrases": ph_info, "f0": f0, "duration": dur,
		"style": st, "text": src, "phonemes": G2P.phonemes(src)}


static func _dur(p: String, is_nucleus: bool, stressed: bool) -> float:
	if G2P.DIPHTHONGS.has(p):
		return DIPH_DUR * (1.06 if stressed else 1.0)
	if G2P.VOWELS.has(p):
		var d := SHORT_VOWEL * (LONG_FACTOR if G2P.LONG_VOWELS.has(p) else 1.0)
		return d * (1.06 if stressed else 0.96)
	var c: Dictionary = CONS.get(p, {"d": 0.06})
	var d: float = c["d"]
	if is_nucleus:
		# Syllabic r / l / m (krk, vlk, sedm) are lengthened into a vowel-like nucleus.
		d = maxf(d, 0.085) * 1.15
	return d


## Zero-phase smoothing in place: two forward + two backward one-pole passes (a critically
## damped, symmetric S-shaped step response of total width ≈ 4–5 τ).
static func _smooth(a: PackedFloat32Array, tau_frames: float) -> void:
	var n := a.size()
	if n < 2 or tau_frames <= 0.01:
		return
	var k := 1.0 - exp(-1.0 / tau_frames)
	for _pass in 2:
		var y := a[0]
		for i in n:
			y += (a[i] - y) * k
			a[i] = y
		y = a[n - 1]
		for i in range(n - 1, -1, -1):
			y += (a[i] - y) * k
			a[i] = y


## F0 contour in Hz sampled every F0_STEP seconds. Target points are built in semitones
## relative to the speaker's base (sentence type, stress, declination), joined with cosine
## interpolation, smoothed zero-phase, then micro-prosody is added (deterministic drift,
## intrinsic vowel pitch, consonant perturbation) – no flat plateaus, no corners, no jumps.
static func _f0_track(sylls: Array, phr: Array, segs: Array, dur: float, vp: Dictionary, mods: Dictionary, seed: int) -> PackedFloat32Array:
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
						v += -1.2 * r
					"continue":
						if k == ps.size() - 1:
							v += 1.6 * r
					"trail":
						v -= (2.5 + 2.0 * r) * maxf(q, 0.5)
			# Accent peak slightly after the nucleus onset (natural late peak alignment).
			pts.append([float(s["nt0"]), v - (0.45 if bool(s["stress"]) else 0.1)])
			var final_q: bool = k == ps.size() - 1 and kind == "question"
			# A final yes/no rise starts early and spans the whole last syllable (incl. coda):
			# ≈ 50–80 st/s like natural speech, never a sudden jump.
			pts.append([lerpf(float(s["nt0"]), float(s["nt1"]), 0.25 if final_q else 0.55), v])
			if final_q:
				pts.append([minf(float(s["t1"]), float(s["nt1"])) + 0.025, v + 4.5 + 3.5 * r])
			elif k == ps.size() - 1:
				var end_v := v
				match kind:
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
	# 1) Cosine interpolation between target points (no corners).
	var semi := PackedFloat32Array()
	semi.resize(n)
	var j := 0
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
			v = lerpf(float(a[1]), float(b[1]), 0.5 - 0.5 * cos(PI * w))
		semi[i] = v
	# 2) Zero-phase smoothing (≈ 15 ms): rounded turns, no lag of the sentence-final rise.
	_smooth(semi, 0.015 / F0_STEP)
	# Bounded excursion (−10…+8 st around the speaker's base, and inside the absolute Hz
	# limits): when the contour would exceed it, the whole upper / lower side is compressed
	# linearly – the shape survives and nothing saturates into a flat plateau.
	var head_hi := minf(8.0, 12.0 * log(F0_MAX / base) / log(2.0) - 3.5)
	var head_lo := maxf(-10.0, 12.0 * log(F0_MIN / base) / log(2.0) + 3.5)
	var mx := 0.0
	var mn := 0.0
	for i in n:
		mx = maxf(mx, semi[i])
		mn = minf(mn, semi[i])
	var sc_hi := clampf(head_hi / mx, 0.2, 1.0) if mx > head_hi and mx > 0.01 else 1.0
	var sc_lo := clampf(head_lo / mn, 0.2, 1.0) if mn < head_lo and mn < -0.01 else 1.0
	if sc_hi < 1.0 or sc_lo < 1.0:
		for i in n:
			semi[i] *= sc_hi if semi[i] > 0.0 else sc_lo
	# 3) Micro-prosody. Deterministic drift (value noise), added after the range limiting.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5DEECE66
	# Two components: slow (≈ 120 ms knots, ±0.45 st) and faster flutter (≈ 55 ms, ±0.18 st).
	var lively := 0.55 + 0.45 * minf(rng_scale, 1.4)
	for comp in [[0.12, 0.45], [0.055, 0.18]]:
		var knot: float = comp[0]
		var amp: float = float(comp[1]) * lively
		var nk := int(dur / knot) + 3
		var knots := PackedFloat32Array()
		knots.resize(nk)
		for k in nk:
			knots[k] = rng.randf_range(-1.0, 1.0) * amp
		for i in n:
			var x := float(i) * F0_STEP / knot
			var k0 := mini(int(x), nk - 2)
			var w := x - float(k0)
			semi[i] += lerpf(knots[k0], knots[k0 + 1], w * w * (3.0 - 2.0 * w))
	# Intrinsic vowel pitch and consonant perturbation at vowel onsets.
	var prev := ""
	for s in segs:
		var p: String = s["ph"]
		if G2P.VOWELS.has(p) or bool(s["nucleus"]):
			var t0: float = s["t"]
			var t1: float = t0 + float(s["d"])
			var intr: float = float(VOWEL_F0.get(p, 0.0)) * clampf(rng_scale, 0.0, 1.0)
			var pert := 0.0
			if CONS.has(prev):
				var c: Dictionary = CONS[prev]
				var obstruent: bool = String(c["k"]) in ["P", "A", "F", "RF"]
				if obstruent:
					pert = 0.7 if float(c["v"]) < 0.5 else -0.45
				elif String(c["k"]) == "N":
					pert = -0.2
			var i0 := maxi(int(t0 / F0_STEP), 0)
			var i1 := mini(int(t1 / F0_STEP) + 1, n)
			for i in range(i0, i1):
				var lt := float(i) * F0_STEP - t0
				var e := smoothstep(0.0, 0.012, lt) * smoothstep(0.0, 0.012, t1 - float(i) * F0_STEP)
				semi[i] += intr * e + pert * exp(-lt / 0.035) * smoothstep(0.0, 0.006, lt + 0.003)
		prev = p
	for i in n:
		out[i] = _soft_hz(base * pow(2.0, semi[i] / 12.0))
	return out


## Absolute F0 limits with a 3-semitone soft knee (no clipped plateau at F0_MIN / F0_MAX).
static func _soft_hz(f: float) -> float:
	var x := 12.0 * log(maxf(f, 1.0)) / log(2.0)
	var hi := 12.0 * log(F0_MAX) / log(2.0)
	var lo := 12.0 * log(F0_MIN) / log(2.0)
	if x > hi - 3.0:
		x = hi - 3.0 + 3.0 * tanh((x - hi + 3.0) / 3.0)
	elif x < lo + 3.0:
		x = lo + 3.0 - 3.0 * tanh((lo + 3.0 - x) / 3.0)
	return pow(2.0, x / 12.0)


## Convenience for tests: F0 contour (Hz) with the voiced-nucleus mask.
static func f0_contour(text: Variant, voice: Variant = {}, style: Variant = "klidne") -> Dictionary:
	var pl := plan(text, voice, style)
	return {"f0": pl["f0"], "step": F0_STEP, "syllables": pl["syllables"], "phrases": pl["phrases"]}


## Render speech to mono float samples.
static func render(text: Variant, voice: Variant = {}, style: Variant = "klidne", sr: int = SR) -> PackedFloat32Array:
	var pl := plan(text, voice, style)
	return render_plan(pl, voice, sr)


## Formant targets of a vowel (or diphthong part) for this tract.
static func _vowel_targets(p: String, tract: float, f1_mul: float) -> Array:
	var q: Array = VOWEL_F.get(p, NEUTRAL_F)
	return [float(q[0]) * tract * f1_mul, float(q[1]) * tract, float(q[2]) * tract, float(q[3]) * tract]


static func _is_vowel(p: String) -> bool:
	return VOWEL_F.has(p) or DIPH.has(p)


## First vowel formants after segment i (for h, velar bursts); falls back to the previous one.
static func _context_vowel(segs: Array, i: int) -> String:
	for k in range(i + 1, mini(i + 4, segs.size())):
		var p: String = segs[k]["ph"]
		if _is_vowel(p):
			return String(DIPH[p][0]) if DIPH.has(p) else p
	for k in range(i - 1, maxi(i - 4, -1), -1):
		var p: String = segs[k]["ph"]
		if _is_vowel(p):
			return String(DIPH[p][1]) if DIPH.has(p) else p
	return "e"


## Control tracks (one value per CTRL samples). Each segment writes raw targets; then the
## tracks are smoothed zero-phase so every transition is a smooth S-curve.
static func _tracks(pl: Dictionary, vp: Dictionary, mods: Dictionary, sr: int, nfr: int) -> Dictionary:
	var segs: Array = pl["segments"]
	var sylls: Array = pl["syllables"]
	var phrases: Array = pl["phrases"]
	var tract: float = vp["tract"]
	var f1_mul: float = mods["f1"]
	var breath: float = clampf(float(mods["breath"]) + 0.08 * float(vp["rough"]), 0.0, 1.0)
	var fr_dt := float(CTRL) / float(sr)
	var nyq := 0.44 * float(sr)
	var names := ["f1", "f2", "f3", "f4", "bm", "av", "ah", "af", "fn", "fb", "nm", "nz", "lp"]
	var tr := {}
	for nm in names:
		var a := PackedFloat32Array()
		a.resize(nfr)
		a.fill(0.0)
		tr[nm] = a
	var f1: PackedFloat32Array = tr["f1"]
	var f2: PackedFloat32Array = tr["f2"]
	var f3: PackedFloat32Array = tr["f3"]
	var f4: PackedFloat32Array = tr["f4"]
	var bm: PackedFloat32Array = tr["bm"]
	var av: PackedFloat32Array = tr["av"]
	var ah: PackedFloat32Array = tr["ah"]
	var af: PackedFloat32Array = tr["af"]
	var fn: PackedFloat32Array = tr["fn"]
	var fb: PackedFloat32Array = tr["fb"]
	var nmx: PackedFloat32Array = tr["nm"]
	var nz: PackedFloat32Array = tr["nz"]
	var lp: PackedFloat32Array = tr["lp"]
	bm.fill(1.0)
	fn.fill(3000.0)
	fb.fill(2000.0)
	nz.fill(1500.0)
	if segs.is_empty():
		return tr
	# Neutral formants everywhere first; pauses later take the next segment's targets.
	var first_f := [500.0 * tract, 1500.0 * tract, 2500.0 * tract, 3500.0 * tract]
	var filled := PackedByteArray()
	filled.resize(nfr)
	filled.fill(0)
	var prev_p := ""
	for si in segs.size():
		var s: Dictionary = segs[si]
		var p: String = s["ph"]
		var t0: float = s["t"]
		var d: float = s["d"]
		var t1 := t0 + d
		var syl: Dictionary = sylls[int(s["syl"])] if int(s["syl"]) < sylls.size() else {}
		var phr: Dictionary = phrases[int(s["phrase"])] if int(s["phrase"]) < phrases.size() else {"kind": "statement", "t0": t0, "t1": t1}
		var pkind: String = phr["kind"]
		var p_t0: float = phr["t0"]
		var p_t1: float = phr["t1"]
		var stressed: bool = s["stress"]
		var last_syl: bool = bool(syl.get("last", false))
		var next_p: String = segs[si + 1]["ph"] if si + 1 < segs.size() and int(segs[si + 1]["phrase"]) == int(s["phrase"]) else ""
		var k0 := clampi(int(t0 / fr_dt), 0, nfr - 1)
		var k1 := clampi(int(t1 / fr_dt), k0 + 1, nfr)
		var vowel := _is_vowel(p)
		var c: Dictionary = {} if vowel else CONS.get(p, CONS["t"])
		var kind: String = "V" if vowel else String(c["k"])
		# Formant targets (start → end for diphthongs).
		var fa: Array
		var fe: Array
		if vowel:
			if DIPH.has(p):
				fa = _vowel_targets(DIPH[p][0], tract, f1_mul)
				fe = _vowel_targets(DIPH[p][1], tract, f1_mul)
			else:
				fa = _vowel_targets(p, tract, f1_mul)
				fe = fa
			# Short unstressed vowels undershoot slightly towards a neutral tract.
			if not stressed and not G2P.LONG_VOWELS.has(p) and not DIPH.has(p):
				for q in 4:
					fa[q] = lerpf(float(fa[q]), float(NEUTRAL_F[q]) * tract, 0.08)
				fe = fa
		elif kind == "H":
			fa = _vowel_targets(_context_vowel(segs, si), tract, 1.0)
			fe = fa
		else:
			var q: Array = c["f"]
			fa = [float(q[0]) * tract, float(q[1]) * tract, float(q[2]) * tract, float(q[3]) * tract]
			fe = fa
		# Syllable / phrase level gain: stressed louder, declination, phrase-final softening.
		var g := 1.12 if stressed else 0.94
		var p_rel := clampf((t0 - p_t0) / maxf(p_t1 - p_t0, 0.05), 0.0, 1.0)
		g *= 1.0 - 0.16 * p_rel
		var nt0: float = syl.get("nt0", t0)
		var nt1: float = syl.get("nt1", t1)
		var final_fall := pkind != "question"
		var prev_voiceless_stop := false
		if CONS.has(prev_p) and int(segs[si - 1]["phrase"]) == int(s["phrase"]):
			var pc: Dictionary = CONS[prev_p]
			prev_voiceless_stop = (String(pc["k"]) == "P" or String(pc["k"]) == "A") and float(pc["v"]) < 0.5
		var phrase_initial := t0 - p_t0 < 0.002
		for k in range(k0, k1):
			var tt := (float(k) + 0.5) * fr_dt
			var lt := tt - t0
			var w := clampf(lt / maxf(d, 0.001), 0.0, 1.0)
			var wd := smoothstep(0.2, 0.85, w) if DIPH.has(p) else 0.0
			f1[k] = lerpf(float(fa[0]), float(fe[0]), wd)
			f2[k] = lerpf(float(fa[1]), float(fe[1]), wd)
			f3[k] = lerpf(float(fa[2]), float(fe[2]), wd)
			f4[k] = lerpf(float(fa[3]), float(fe[3]), wd)
			filled[k] = 1
			var a_v := 0.0
			var a_h := 0.0
			var a_f := 0.0
			var gg := g
			# Final syllable of a phrase: decaying, slightly breathier offset.
			if last_syl and tt >= nt0:
				var wf := clampf((tt - nt0) / maxf(nt1 - nt0, 0.02), 0.0, 1.0)
				gg *= 1.0 - (0.5 if final_fall else 0.22) * pow(wf, 1.6) * (1.3 if pkind == "trail" else 1.0)
				a_h += 0.10 * wf
			match kind:
				"V":
					a_v = 1.0
					# Soft, slightly breathy vowel onset at a phrase start.
					if phrase_initial:
						var on := smoothstep(0.0, 0.035, lt)
						a_v *= 0.35 + 0.65 * on
						a_h += 0.22 * (1.0 - on)
					# Short aspiration + delayed voicing after a voiceless stop (Czech: short VOT).
					if prev_voiceless_stop and lt < 0.014:
						a_h += 0.55 * (1.0 - lt / 0.014)
						a_v *= smoothstep(0.004, 0.014, lt)
				"N":
					a_v = 0.62
					nmx[k] = 1.0
					nz[k] = minf(float(c["nz"]) * tract, nyq)
					lp[k] = 0.35
					bm[k] = 1.5
				"L":
					a_v = 0.7
					bm[k] = 1.2
				"J":
					a_v = 0.78
				"R":
					a_v = 0.74
					if bool(s["nucleus"]) or d >= 0.07:
						# 2 taps for a syllabic or long r.
						a_v *= 1.0 - 0.62 * pow(absf(sin(PI * lt / maxf(d * 0.5, 0.01))), 6.0) * smoothstep(0.0, 0.01, lt)
					else:
						a_v *= 1.0 - 0.65 * exp(-pow((lt - d * 0.5) / 0.0085, 2.0))
					bm[k] = 1.3
				"RF":
					# ř: trill (≈ 26 Hz, 2 cycles) + friction that peaks in the trill openings.
					var am := 0.5 + 0.5 * cos(TAU * 26.0 * lt)
					a_v = (0.55 * float(c["v"])) * (0.35 + 0.65 * am)
					a_f = float(c["na"]) * (0.45 + 0.55 * (1.0 - am)) * smoothstep(0.0, 0.015, lt) * smoothstep(0.0, 0.015, d - lt)
					fn[k] = minf(float(c["nf"]) * (0.94 + 0.12 * tract), nyq)
					fb[k] = c["nbw"]
					bm[k] = 1.25
				"F":
					a_v = 0.5 * float(c["v"])
					var env := smoothstep(0.0, 0.025, lt) * smoothstep(0.0, 0.022, d - lt)
					a_f = float(c["na"]) * (0.3 + 0.7 * env)
					fn[k] = minf(float(c["nf"]) * (0.94 + 0.12 * tract), nyq)
					fb[k] = c["nbw"]
				"H":
					# Breathy-voiced glottal fricative: aspiration through the vowel-context tract.
					a_v = 0.24
					a_h = 0.42
					bm[k] = 1.4
				"P", "A":
					var closure := d - 0.011 if kind == "P" else d * 0.4
					var voiced := float(c["v"])
					var nf_val := float(c["nf"])
					if kind == "P" and (p == "k" or p == "g"):
						# Velar burst follows the next vowel (front vowels → higher).
						var cv := _vowel_targets(_context_vowel(segs, si), tract, 1.0)
						nf_val = clampf(float(cv[1]) * 1.05, 1500.0, 3200.0)
					fn[k] = minf(nf_val * (0.94 + 0.12 * tract), nyq)
					fb[k] = c["nbw"]
					if lt < closure:
						# Closure: silence, or a low voice bar for voiced stops (fading in the closure).
						a_v = 0.3 * voiced * (1.0 - 0.35 * lt / maxf(closure, 0.01))
						lp[k] = voiced
					elif kind == "P":
						var bt := lt - closure
						a_f = float(c["na"]) * 1.6 * exp(-bt / 0.0035) * smoothstep(0.0, 0.0012, bt)
						a_h = (0.25 if voiced < 0.5 else 0.06) * smoothstep(0.0, 0.003, bt)
						a_v = 0.25 * voiced
					else:
						var ft := lt - closure
						a_f = float(c["na"]) * (1.25 * exp(-ft / 0.01) + 0.8) * smoothstep(0.0, 0.0015, ft) * smoothstep(0.0, 0.015, d - lt)
						a_v = 0.35 * voiced
			if bool(s["nucleus"]) and not vowel:
				a_v = maxf(a_v, 0.82)
			# Aspiration always rides on voicing a little (natural breathiness).
			av[k] = a_v * gg
			ah[k] = (a_h + breath * a_v) * gg
			af[k] = a_f * minf(gg, 1.0)
		prev_p = p
	# Pauses and margins: hold the next segment's formants (or the last one), silent.
	var next_f := PackedFloat32Array([first_f[0], first_f[1], first_f[2], first_f[3]])
	for k in range(nfr - 1, -1, -1):
		if filled[k] == 1:
			next_f = PackedFloat32Array([f1[k], f2[k], f3[k], f4[k]])
		else:
			f1[k] = next_f[0]
			f2[k] = next_f[1]
			f3[k] = next_f[2]
			f4[k] = next_f[3]
	var fps := float(sr) / float(CTRL)
	for nm in ["f1", "f2", "f3", "f4"]:
		_smooth(tr[nm], TAU_FORMANT * fps)
	for nm in ["bm", "nm", "nz", "lp", "ah"]:
		_smooth(tr[nm], TAU_SLOW * fps)
	_smooth(av, TAU_AMP * fps)
	for nm in ["af", "fn", "fb"]:
		_smooth(tr[nm], TAU_NOISE * fps)
	for k in nfr:
		f1[k] = clampf(f1[k], 150.0, nyq)
		f2[k] = clampf(f2[k], f1[k] + 150.0, nyq)
		f3[k] = clampf(f3[k], f2[k] + 200.0, nyq)
		f4[k] = clampf(f4[k], f3[k] + 250.0, nyq)
		fn[k] = clampf(fn[k], 400.0, nyq)
	return tr


static func _gauss(rng: RandomNumberGenerator) -> float:
	# Sum of three uniforms: cheap, bounded, ≈ Gaussian (σ = 1).
	return (rng.randf() + rng.randf() + rng.randf() - 1.5) * 2.0


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
	if segs.is_empty() or n < CTRL * 4:
		return buf
	var nfr := n / CTRL + 2
	var tr := _tracks(pl, vp, mods, sr, nfr)
	var tf1: PackedFloat32Array = tr["f1"]
	var tf2: PackedFloat32Array = tr["f2"]
	var tf3: PackedFloat32Array = tr["f3"]
	var tf4: PackedFloat32Array = tr["f4"]
	var tbm: PackedFloat32Array = tr["bm"]
	var tav: PackedFloat32Array = tr["av"]
	var tah: PackedFloat32Array = tr["ah"]
	var taf: PackedFloat32Array = tr["af"]
	var tfn: PackedFloat32Array = tr["fn"]
	var tfb: PackedFloat32Array = tr["fb"]
	var tnm: PackedFloat32Array = tr["nm"]
	var tnz: PackedFloat32Array = tr["nz"]
	var tlp: PackedFloat32Array = tr["lp"]
	var rng := RandomNumberGenerator.new()
	rng.seed = text_hash(String(pl["text"]) + "|" + st) ^ 0x2545F491
	var inv := 1.0 / float(sr)
	var sr_f := float(sr)
	var nyq := 0.44 * sr_f
	var tract: float = vp["tract"]
	var rough: float = vp["rough"]
	var voiced_style: float = mods["voiced"]
	var oq: float = clampf(float(mods["oq"]) - 0.06 * (rough - 0.2), 0.38, 0.8)
	var bright := clampf(float(vp["bright"]) + float(mods["tilt"]), -0.2, 1.2)
	# Extra source tilt (one-pole low-pass, Klatt "TL"): darker voices roll off earlier.
	var tilt_a := 1.0 - exp(-TAU * (1900.0 + 2400.0 * maxf(bright, 0.0)) * inv)
	# Jitter / shimmer (σ): small and natural, larger only for rough voices.
	var jit_sd := 0.0038 + 0.016 * rough * rough
	var shim_sd := 0.025 + 0.075 * rough * rough
	# Mild creak (alternating periods) only for very rough voices – never a growl.
	var creak := clampf((rough - 0.6) / 0.4, 0.0, 1.0) * 0.18
	var bw_mul := 1.0 + 0.6 * clampf(float(mods["breath"]), 0.0, 0.5)
	var f5 := minf(F5 * tract, nyq * 0.95)
	var step_h := 6.75 / oq
	# Synthesis state.
	var phase := 0.0
	var period_mul := 1.0
	var amp_mul := 1.0
	var period_index := 0
	var prev_src := 0.0
	var pend_corr := 0.0
	var tilt_y := 0.0
	var asp_x1 := 0.0
	var wh_lp := 0.0
	# Cascade resonator states and coefficients (Klatt: y = A x + B y1 + C y2).
	var r1a := 0.0
	var r1b := 0.0
	var r1c := 0.0
	var r2a := 0.0
	var r2b := 0.0
	var r2c := 0.0
	var r3a := 0.0
	var r3b := 0.0
	var r3c := 0.0
	var r4a := 0.0
	var r4b := 0.0
	var r4c := 0.0
	var r5a := 0.0
	var r5b := 0.0
	var r5c := 0.0
	var y11 := 0.0
	var y12 := 0.0
	var y21 := 0.0
	var y22 := 0.0
	var y31 := 0.0
	var y32 := 0.0
	var y41 := 0.0
	var y42 := 0.0
	var y51 := 0.0
	var y52 := 0.0
	# Nasal antiresonator (FIR zero pair) and murmur low-pass.
	var za := 1.0
	var zb := 0.0
	var zc := 0.0
	var zx1 := 0.0
	var zx2 := 0.0
	var lp_a := 1.0 - exp(-TAU * 600.0 * inv)
	var lp1 := 0.0
	var lp2 := 0.0
	# Frication branch: two cascaded band-pass resonators.
	var na1 := 0.0
	var na2 := 0.0
	var nb0 := 0.0
	var nz1 := 0.0
	var nz2 := 0.0
	var nw1 := 0.0
	var nw2 := 0.0
	var fgain := 1.0
	var r5 := exp(-PI * FORMANT_BW[4] * inv)
	r5b = 2.0 * r5 * cos(TAU * f5 * inv)
	r5c = -r5 * r5
	r5a = 1.0 - r5b - r5c
	var f6 := minf(F6 * tract, nyq * 0.97)
	var r6 := exp(-PI * B6 * inv)
	var r6b := 2.0 * r6 * cos(TAU * f6 * inv)
	var r6c := -r6 * r6
	var r6a := 1.0 - r6b - r6c
	var y61 := 0.0
	var y62 := 0.0
	var bw1b: float = FORMANT_BW[0] * bw_mul
	var bw2b: float = FORMANT_BW[1] * bw_mul
	var bw3b: float = FORMANT_BW[2] * bw_mul
	var bw4b: float = FORMANT_BW[3]
	var av0 := 0.0
	var av1 := 0.0
	var ah0 := 0.0
	var ah1 := 0.0
	var af0 := 0.0
	var af1 := 0.0
	var nm0 := 0.0
	var lpm0 := 0.0
	var fr := 0
	var u := 0.0
	var dc_x := 0.0
	var dc_y := 0.0
	for i in n:
		var sub := i % CTRL
		if sub == 0:
			fr = mini(i / CTRL, nfr - 2)
			av0 = tav[fr]
			av1 = tav[fr + 1]
			ah0 = tah[fr]
			ah1 = tah[fr + 1]
			af0 = taf[fr]
			af1 = taf[fr + 1]
			nm0 = tnm[fr]
			lpm0 = tlp[fr]
			var bmul: float = tbm[fr]
			# Wider F1 for high voices (sparse harmonics would otherwise whistle).
			var f0_here := f0tr[mini(int(float(i) * inv / F0_STEP), f0tr.size() - 1)]
			var b1 := bw1b * bmul + 0.12 * f0_here
			var r := exp(-PI * b1 * inv)
			r1b = 2.0 * r * cos(TAU * tf1[fr] * inv)
			r1c = -r * r
			r1a = 1.0 - r1b - r1c
			r = exp(-PI * bw2b * bmul * inv)
			r2b = 2.0 * r * cos(TAU * tf2[fr] * inv)
			r2c = -r * r
			r2a = 1.0 - r2b - r2c
			r = exp(-PI * bw3b * bmul * inv)
			r3b = 2.0 * r * cos(TAU * tf3[fr] * inv)
			r3c = -r * r
			r3a = 1.0 - r3b - r3c
			r = exp(-PI * bw4b * inv)
			r4b = 2.0 * r * cos(TAU * tf4[fr] * inv)
			r4c = -r * r
			r4a = 1.0 - r4b - r4c
			if nm0 > 0.001:
				# Antiresonator = inverse of a resonator at the nasal zero.
				r = exp(-PI * 160.0 * inv)
				var rb := 2.0 * r * cos(TAU * tnz[fr] * inv)
				var rc := -r * r
				var ra := 1.0 - rb - rc
				za = 1.0 / ra
				zb = -rb / ra
				zc = -rc / ra
			if af0 > 0.0005 or af1 > 0.0005:
				var cr := exp(-PI * tfb[fr] * inv)
				na1 = 2.0 * cr * cos(TAU * tfn[fr] * inv)
				na2 = cr * cr
				nb0 = (1.0 - cr * cr) * 0.5
				fgain = sqrt(maxf(tfb[fr], 300.0) / 2000.0)
		var fw := float(sub) / float(CTRL)
		var a_v := lerpf(av0, av1, fw)
		var a_h := lerpf(ah0, ah1, fw)
		var a_f := lerpf(af0, af1, fw)
		# --- glottal source: KLGLOTT88 flow derivative with polyBLEP closure -----------------
		var tt := float(i) * inv
		var fi := tt / F0_STEP
		var i0 := mini(int(fi), f0tr.size() - 1)
		var i1 := mini(i0 + 1, f0tr.size() - 1)
		var f0 := lerpf(f0tr[i0], f0tr[i1], fi - float(i0))
		var dphi := f0 * inv * period_mul
		var ph_prev := phase
		phase += dphi
		var corr_now := 0.0
		var g_amp := amp_mul * a_v * voiced_style
		if ph_prev < oq and phase >= oq:
			var dfrac := clampf((phase - oq) / maxf(dphi, 1e-6), 0.0, 1.0)
			var hh := step_h * g_amp
			pend_corr += hh * dfrac * dfrac * 0.5
			corr_now = -hh * (1.0 - dfrac) * (1.0 - dfrac) * 0.5
		if phase >= 1.0:
			phase -= floorf(phase)
			period_index += 1
			period_mul = 1.0 + _gauss(rng) * jit_sd
			amp_mul = 1.0 + _gauss(rng) * shim_sd
			if creak > 0.0 and period_index % 2 == 1:
				amp_mul *= 1.0 - creak
		var g := 0.0
		u = 0.0
		if phase < oq:
			var tau := phase / oq
			g = 6.75 * (2.0 * tau - 3.0 * tau * tau) / oq
			u = 6.75 * tau * tau * (1.0 - tau)
		var cur := g * g_amp + corr_now
		var src_v := prev_src + pend_corr
		prev_src = cur
		pend_corr = 0.0
		# Extra tilt on the voiced source.
		tilt_y += tilt_a * (src_v - tilt_y)
		# Aspiration: high-passed noise, pulsed by the glottal flow while voicing.
		var nz_w := rng.randf() * 2.0 - 1.0
		var asp_n := nz_w - 0.15 * asp_x1
		asp_x1 = nz_w
		var pulse := lerpf(1.0, 0.35 + 0.9 * u, clampf(a_v * voiced_style * 1.2, 0.0, 1.0))
		var src: float
		if voiced_style < 0.5:
			# Whisper: aspiration noise only (darkened a little, not hissy), amplitude follows
			# voicing + aspiration.
			wh_lp += 0.35 * (asp_n - wh_lp)
			src = (0.35 * asp_n + 1.3 * wh_lp) * (a_v * 0.55 + a_h * 0.6)
		else:
			src = tilt_y * 0.16 + asp_n * a_h * pulse * 1.25
		# --- vocal tract: cascade F1..F5 --------------------------------------------------
		var y := r1a * src + r1b * y11 + r1c * y12
		y12 = y11
		y11 = y
		var y2 := r2a * y + r2b * y21 + r2c * y22
		y22 = y21
		y21 = y2
		var y3 := r3a * y2 + r3b * y31 + r3c * y32
		y32 = y31
		y31 = y3
		var y4 := r4a * y3 + r4b * y41 + r4c * y42
		y42 = y41
		y41 = y4
		var y5 := r5a * y4 + r5b * y51 + r5c * y52
		y52 = y51
		y51 = y5
		var y6 := r6a * y5 + r6b * y61 + r6c * y62
		y62 = y61
		y61 = y6
		var out := y6
		if nm0 > 0.001:
			var anti := za * y6 + zb * zx1 + zc * zx2
			zx2 = zx1
			zx1 = y6
			out = lerpf(y6, anti, nm0)
		else:
			zx2 = zx1
			zx1 = y6
		lp1 += lp_a * (out - lp1)
		lp2 += lp_a * (lp1 - lp2)
		if lpm0 > 0.001:
			out = lerpf(out, lp2, lpm0)
		# --- frication branch -------------------------------------------------------------
		var fric := 0.0
		if a_f > 0.0005:
			var nsrc := rng.randf() * 2.0 - 1.0
			# Voiced fricatives: noise pulsed by the glottal flow.
			nsrc *= lerpf(1.0, 0.45 + 0.8 * u, clampf(a_v * 1.6, 0.0, 1.0))
			var ny := nb0 * nsrc + na1 * nz1 - na2 * nz2
			nz2 = nz1
			nz1 = ny
			var nw := nb0 * ny + na1 * nw1 - na2 * nw2
			nw2 = nw1
			nw1 = nw
			fric = nw * a_f * fgain * 7.0
		var x := out + fric
		dc_y = x - dc_x + 0.996 * dc_y
		dc_x = x
		buf[i] = dc_y
	_post(buf, sr, mods)
	return buf


## Output polish: gentle low-pass, light early reflections, light compression, peak
## normalisation and short fades. Deterministic, in place.
static func _post(buf: PackedFloat32Array, sr: int, mods: Dictionary) -> void:
	var n := buf.size()
	var inv := 1.0 / float(sr)
	# 2nd-order Butterworth low-pass (bilinear) at ≈ 7 kHz (or 0.42·sr).
	var fc := minf(7000.0, 0.42 * float(sr))
	var k := tan(PI * fc * inv)
	var norm := 1.0 / (1.0 + sqrt(2.0) * k + k * k)
	var b0 := k * k * norm
	var b1 := 2.0 * b0
	var a1 := 2.0 * (k * k - 1.0) * norm
	var a2 := (1.0 - sqrt(2.0) * k + k * k) * norm
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var x := buf[i]
		var y := b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] = y
	# Early reflections (damped, read from the dry signal).
	var dry := buf.duplicate()
	var damp := 1.0 - exp(-TAU * 3500.0 * inv)
	var wet := PackedFloat32Array()
	wet.resize(n)
	wet.fill(0.0)
	for r in REFLECTIONS:
		var dly := int(float(r[0]) * float(sr))
		var gr: float = r[1]
		for i in range(dly, n):
			wet[i] += dry[i - dly] * gr
	var ly := 0.0
	for i in n:
		ly += damp * (wet[i] - ly)
		buf[i] = dry[i] + ly
	# Peak → 1, then light compression (2:1 above −10 dB, 3 ms attack / 70 ms release).
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	if peak < 1e-7:
		buf.fill(0.0)
		return
	var att := 1.0 - exp(-inv / 0.003)
	var rel := 1.0 - exp(-inv / 0.07)
	var env := 0.0
	var thr := 0.316
	var gpk := 1.0 / peak
	for i in n:
		var x := buf[i] * gpk
		var ax := absf(x)
		env += (ax - env) * (att if ax > env else rel)
		var gr := 1.0
		if env > thr:
			gr = sqrt(thr / env)
		buf[i] = x * gr
	peak = 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	# Target peak: ≈ −3 dBFS for the loudest style, softer styles a little lower.
	var target := 0.708 * (0.55 + 0.45 * float(mods["energy"]))
	var g := target / maxf(peak, 1e-7)
	var fade := int(0.012 * float(sr))
	for i in n:
		var e := 1.0
		if i < fade:
			e = float(i) / float(fade)
		elif i >= n - fade:
			e = float(n - 1 - i) / float(fade)
		buf[i] = clampf(buf[i] * g * e, -0.98, 0.98)
