extends RefCounted
## VoiceSynth – hlas postavy jako procedurální formantová syntéza (nesrozumitelná „řeč“).
##
## Jediný vstup je skupina CharacterData.voice (pitch / timbre / tempo / roughness). Hlas
## se NIKDY neodvozuje z pohlaví, genderové identity, rodu, těla, věku ani jména – rozsah
## výšky pokrývá hluboké i vysoké hlasy pro kohokoli. Stejná data + styl + varianta dají na
## všech peerech bitově shodný zvuk (vlastní RNG, žádný globální stav).
##
## Model (zjednodušený zdroj–filtr):
##   - hlasivkový zdroj: Rosenbergův puls (otevírací / zavírací fáze) s derivací (vyzařování
##     rty), jitter (kolísání periody), shimmer (kolísání amplitudy), u chraplavého hlasu
##     zdvojení periody (subharmonie) a šum;
##   - dechový šum (aspirace) modulovaný otevřením hlasivek; šepot = jen šum;
##   - spektrální náklon (jednopólový filtr) podle barvy hlasu a stylu;
##   - 4 paralelní formantové rezonátory (české samohlásky a e i o u), délka hlasového
##     traktu škáluje formanty (timbre: tmavý = delší trakt = nižší formanty);
##   - souhlásky: šumové frikativy (s, š, ch), ploziva (záblesk), nosovky (znělé, tlumené);
##   - prozodie: deklinace věty, přízvuky, prodloužení konce fráze, styl (klidně, vesele,
##     naštvaně, smutně, šeptem).
## Výstup je mono PackedFloat32Array; to_stream() udělá 16bit AudioStreamWAV.

const SR := 22050
## Czech text-to-speech (rule-based G2P + formant synthesis + prosody), see czech_tts.gd.
const CzechTTS := preload("res://scripts/audio/czech_tts.gd")
## Speech styles available to TTS: the five wordless styles plus "unavene" (tired).
const TTS_STYLES := ["klidne", "vesele", "nastvane", "smutne", "unavene", "septem"]
## Public displayed emotion (Mood.emotion / net_emotion) → speaking style. Never private state.
const EMOTION_STYLE := {"nastvany": "nastvane", "smutny": "smutne", "unaveny": "unavene", "stastny": "vesele"}
## Výchozí (neutrální) základní frekvence – uprostřed lidského rozsahu, bez vazby na rod.
const BASE_F0 := 160.0
## pitch −1..1 → ±1,05 oktávy (≈ 77–331 Hz): od basu po vysoký hlas.
const PITCH_OCTAVES := 1.05
## timbre −1..1 → délka traktu: formanty ×2^(±0,16) (≈ ±11,7 %).
const TRACT_OCTAVES := 0.16
## tempo −1..1 → slabiky za sekundu ×2^(±0,6).
const TEMPO_OCTAVES := 0.6
const BASE_RATE := 5.0
const MAX_DURATION := 6.0
const STYLES := {
	"klidne": "Klidně",
	"vesele": "Vesele",
	"nastvane": "Naštvaně",
	"smutne": "Smutně",
	"septem": "Šeptem",
}
## Modifikátory stylu: f0 (půltóny), rozsah intonace (půltóny), rychlost, energie, dech,
## náklon (+ jasnější), F1 posun (napětí hrtanu), pauzy, konec fráze (+ stoupá / − klesá),
## znělost (0 = šepot).
const STYLE_MODS := {
	"klidne":   {"f0_st": 0.0,  "range": 2.6, "rate": 1.0,  "energy": 0.80, "breath": 0.07, "tilt": 0.0,   "f1": 1.0,  "pause": 1.0,  "end": -1.2, "voiced": 1.0},
	"vesele":   {"f0_st": 2.0,  "range": 5.0, "rate": 1.12, "energy": 0.92, "breath": 0.05, "tilt": 0.15,  "f1": 1.03, "pause": 0.85, "end": 2.0,  "voiced": 1.0},
	"nastvane": {"f0_st": 3.0,  "range": 4.2, "rate": 1.18, "energy": 1.0,  "breath": 0.03, "tilt": 0.35,  "f1": 1.10, "pause": 0.6,  "end": -2.5, "voiced": 1.0},
	"smutne":   {"f0_st": -1.5, "range": 1.4, "rate": 0.78, "energy": 0.55, "breath": 0.20, "tilt": -0.28, "f1": 0.96, "pause": 1.5,  "end": -2.2, "voiced": 1.0},
	"septem":   {"f0_st": 0.0,  "range": 0.0, "rate": 0.95, "energy": 0.45, "breath": 1.0,  "tilt": 0.05,  "f1": 1.0,  "pause": 1.1,  "end": 0.0,  "voiced": 0.0},
}
## České samohlásky (F1, F2, F3, F4) pro „průměrný“ trakt (timbre 0).
const VOWELS := [
	[730.0, 1250.0, 2550.0, 3500.0],  # a
	[530.0, 1800.0, 2500.0, 3550.0],  # e
	[300.0, 2250.0, 2950.0, 3700.0],  # i
	[500.0, 900.0, 2450.0, 3400.0],   # o
	[330.0, 700.0, 2350.0, 3350.0],   # u
]
const FORMANT_GAIN := [1.0, 0.62, 0.30, 0.16]
const FORMANT_BW := [85.0, 105.0, 150.0, 220.0]
## Souhlásky před samohláskou: 0 žádná, 1 s, 2 š, 3 ch, 4 plozivum, 5 nosovka.
const CONS_NONE := 0
const CONS_NOISE_FREQ := [0.0, 5200.0, 2900.0, 1600.0, 2200.0, 0.0]
const COEF_BLOCK := 32


## Bezpečné převzetí čísla z (potenciálně nedůvěryhodného) slovníku: jen konečné int/float,
## oříznuté na rozsah a zaokrouhlené na 0,001; cokoli jiného (text, NaN, ∞, null) → výchozí.
static func _num(v: Dictionary, key: String, def: float, lo: float, hi: float) -> float:
	var x: Variant = v.get(key, def)
	if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
		return def
	var f := float(x)
	if not is_finite(f):
		return def
	# Stejná kanonická přesnost jako CharacterValidator (QUANT 1000): návrh v editoru i veřejný
	# snapshot ve hře (zaokrouhlený validátorem) pak dají přesně stejný zvuk.
	return roundf(clampf(f, lo, hi) * 1000.0) / 1000.0


## Normalizované hodnoty hlasu (stejné meze jako character_schema.gd → voice).
static func normalized(voice: Variant) -> Dictionary:
	var v: Dictionary = voice if voice is Dictionary else {}
	return {
		"pitch": _num(v, "pitch", 0.0, -1.0, 1.0),
		"timbre": _num(v, "timbre", 0.0, -1.0, 1.0),
		"tempo": _num(v, "tempo", 0.0, -1.0, 1.0),
		"roughness": _num(v, "roughness", 0.2, 0.0, 1.0),
	}


## Fyzikální parametry hlasu z CharacterData.voice. Nic jiného než voice nevstupuje.
static func params(voice: Variant) -> Dictionary:
	var n := normalized(voice)
	return {
		"f0": BASE_F0 * pow(2.0, n["pitch"] * PITCH_OCTAVES),
		"tract": pow(2.0, n["timbre"] * TRACT_OCTAVES),
		"bright": 0.5 + 0.5 * n["timbre"],
		"rate": BASE_RATE * pow(2.0, n["tempo"] * TEMPO_OCTAVES),
		"rough": n["roughness"],
	}


static func style_or_default(style: Variant) -> String:
	if typeof(style) == TYPE_STRING and STYLE_MODS.has(style):
		return String(style)
	return "klidne"


static func _seed(variant: int, style: String) -> int:
	var idx: int = STYLE_MODS.keys().find(style)
	# Knuthovo multiplikativní míchání – deterministické, nezávislé na hash() platformy.
	return int((absi(variant) % 1000003) * 2654435761 + (idx + 1) * 40503 + 12345) & 0x7fffffff


## Plán slabik (veřejný kvůli testům): pole [start_s, délka_s, samohláska, souhláska,
## přízvuk (bool), index fráze, poslední ve frázi (bool)] a počet frází.
static func plan(voice: Variant, style: Variant = "klidne", variant: int = 0, dur: float = 2.2) -> Dictionary:
	var st := style_or_default(style)
	var mods: Dictionary = STYLE_MODS[st]
	var p := params(voice)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(variant, st)
	dur = clampf(dur if is_finite(dur) else 2.2, 0.3, MAX_DURATION)
	var rate: float = float(p["rate"]) * float(mods["rate"])
	var syl_len := 1.0 / rate
	var out: Array = []
	var t := rng.randf_range(0.03, 0.12)
	var phrase := 0
	var tail := 0.12
	while t < dur - tail - syl_len * 0.6:
		var count := rng.randi_range(2, 6)
		for s in count:
			var last := s == count - 1
			var d := syl_len * rng.randf_range(0.72, 1.25) * (1.3 if last else 1.0)
			if t + d > dur - tail:
				last = true
				d = maxf(dur - tail - t, syl_len * 0.5)
			var cons := CONS_NONE if rng.randf() < 0.3 else rng.randi_range(1, 5)
			out.append([t, d, rng.randi() % VOWELS.size(), cons, s == 0 or rng.randf() < 0.22, phrase, last])
			t += d
			if last:
				break
		var last_entry: Array = out[out.size() - 1]
		last_entry[6] = true
		phrase += 1
		t += rng.randf_range(0.16, 0.42) * float(mods["pause"])
	return {"syllables": out, "phrases": phrase, "duration": dur, "style": st}


## Vyrenderuje hlas. voice = CharacterData.voice, style z STYLES, variant = jiná „věta“.
static func render(voice: Variant, style: Variant = "klidne", variant: int = 0, dur: float = 2.2, sr: int = SR) -> PackedFloat32Array:
	var st := style_or_default(style)
	var mods: Dictionary = STYLE_MODS[st]
	var p := params(voice)
	var pl := plan(voice, st, variant, dur)
	var syl: Array = pl["syllables"]
	dur = float(pl["duration"])
	sr = clampi(sr, 8000, 48000)
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	if syl.is_empty():
		return buf
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(variant, st) ^ 0x3C6EF372
	var inv := 1.0 / float(sr)
	var nyq := 0.45 * float(sr)
	var rough: float = p["rough"]
	var voiced: float = mods["voiced"]
	var breath: float = clampf(float(mods["breath"]) + 0.10 * rough, 0.0, 1.0)
	var tract: float = p["tract"]
	var f1_mul: float = mods["f1"]
	var base_f0: float = float(p["f0"]) * pow(2.0, float(mods["f0_st"]) / 12.0)
	var range_st: float = mods["range"]
	var end_st: float = mods["end"]
	var energy: float = mods["energy"]
	# Náklon: jasnější hlas a napjatý styl propouští víc výšek.
	var bright := clampf(float(p["bright"]) + float(mods["tilt"]), 0.0, 1.2)
	var tilt_cut := 700.0 + 2600.0 * bright
	var tilt_a := 1.0 - exp(-TAU * tilt_cut * inv)
	# Rosenbergův puls: Tp (otevírání), Tn (zavírání) – napjatý hlas zavírá rychleji.
	var tp := 0.42
	var tn := clampf(0.18 - 0.07 * float(mods["tilt"]), 0.08, 0.24)
	var jitter := 0.004 + 0.028 * rough
	var shimmer := 0.03 + 0.16 * rough
	var subharm := clampf((rough - 0.35) / 0.65, 0.0, 1.0) * 0.55
	var phrase_bounds := {}
	for s in syl:
		var ph := int(s[5])
		var a: float = s[0]
		var b: float = float(s[0]) + float(s[1])
		if phrase_bounds.has(ph):
			phrase_bounds[ph] = [minf(phrase_bounds[ph][0], a), maxf(phrase_bounds[ph][1], b)]
		else:
			phrase_bounds[ph] = [a, b]
	# Stav syntézy (formanty rozepsané do skalárů – netypová pole jsou v GDScriptu pomalá).
	var phase := 0.0
	var period_mul := 1.0
	var amp_mul := 1.0
	var period_index := 0
	var prev_u := 0.0
	var tilt_y := 0.0
	var drift := 0.0
	var c1 := 500.0
	var c2 := 1500.0
	var c3 := 2500.0
	var c4 := 3500.0
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
	var g2: float = FORMANT_GAIN[1]
	var g3: float = FORMANT_GAIN[2]
	var g4: float = FORMANT_GAIN[3]
	var bw1: float = float(FORMANT_BW[0]) * (1.0 + 0.8 * breath)
	var bw2: float = float(FORMANT_BW[1]) * (1.0 + 0.8 * breath)
	var bw3: float = float(FORMANT_BW[2]) * (1.0 + 0.8 * breath)
	var bw4: float = float(FORMANT_BW[3]) * (1.0 + 0.8 * breath)
	var cz1 := 0.0
	var cz2 := 0.0
	var ca1 := 0.0
	var ca2 := 0.0
	var cb0 := 0.0
	var cons_freq := -1.0
	var env_s := 0.0
	var si := 0
	var dc_x := 0.0
	var dc_y := 0.0
	var coart := 1.0 - exp(-inv / 0.028)
	var env_rate := 1.0 - exp(-inv / 0.006)
	var accent_env := 0.0
	var sr_f := float(sr)
	# Slabika se mění jen na hranicích – její vlastnosti se čtou jednou, ne každý vzorek.
	var s_start := 0.0
	var s_len := 0.0
	var s_end := -1.0
	var cons_kind := 0
	var cons_len := 0.0
	var accented := false
	var last_in_phrase := false
	var t1 := 500.0
	var t2 := 1500.0
	var t3 := 2500.0
	var t4 := 3500.0
	var t1_nasal := 260.0 * tract
	var p_start := 0.0
	var p_len := 1.0
	var loaded := -1
	for i in n:
		var tt := float(i) * inv
		while si < syl.size() - 1 and tt >= s_end and loaded == si:
			si += 1
		if loaded != si:
			loaded = si
			var s: Array = syl[si]
			s_start = s[0]
			s_len = s[1]
			s_end = s_start + s_len
			cons_kind = s[3]
			cons_len = minf(0.065, s_len * 0.38) if cons_kind != CONS_NONE else 0.0
			accented = bool(s[4])
			last_in_phrase = bool(s[6])
			var vw: Array = VOWELS[int(s[2])]
			t1 = minf(float(vw[0]) * tract * f1_mul, nyq)
			t2 = minf(float(vw[1]) * tract, nyq)
			t3 = minf(float(vw[2]) * tract, nyq)
			t4 = minf(float(vw[3]) * tract, nyq)
			var pb: Array = phrase_bounds.get(int(s[5]), [0.0, 1.0])
			p_start = pb[0]
			p_len = maxf(float(pb[1]) - p_start, 0.05)
			# Šumový filtr souhlásky (s / š / ch / plozivum) – jednou na slabiku.
			if cons_kind != CONS_NONE and cons_kind != 5:
				var want_cf: float = minf(float(CONS_NOISE_FREQ[cons_kind]) * (0.9 + 0.2 * tract), nyq)
				if absf(want_cf - cons_freq) > 1.0:
					cons_freq = want_cf
					var cr := exp(-PI * (900.0 if cons_kind != 4 else 2600.0) * inv)
					ca1 = 2.0 * cr * cos(TAU * cons_freq * inv)
					ca2 = cr * cr
					cb0 = (1.0 - cr * cr) * 0.5
		var lt := tt - s_start
		var in_syl := lt >= 0.0 and lt <= s_len
		# Obálka slabiky: souhláska → samohláska → doznění.
		var vowel_amp := 0.0
		var cons_amp := 0.0
		var nasal := false
		if in_syl:
			var vt := lt - cons_len
			if vt < 0.0:
				if cons_kind == 5:
					nasal = true
				elif cons_kind == 4:
					# Plozivum: závěr (ticho) a krátký záblesk před samohláskou.
					cons_amp = 1.0 if vt > -0.012 else 0.0
				else:
					cons_amp = smoothstep(0.0, 0.02, lt) * 0.9
			else:
				var vlen := s_len - cons_len
				vowel_amp = smoothstep(0.0, 0.016, vt) * (1.0 - smoothstep(vlen - 0.045, vlen, vt))
				if not accented:
					vowel_amp *= 0.74
		var target_env := maxf(vowel_amp, 0.55 if nasal else 0.0)
		env_s += (target_env - env_s) * env_rate
		accent_env += ((1.0 if accented and in_syl else 0.0) - accent_env) * coart
		# Formanty se k cíli blíží plynule (koartikulace).
		c1 += ((t1_nasal if nasal else t1) - c1) * coart
		c2 += (t2 - c2) * coart
		c3 += (t3 - c3) * coart
		c4 += (t4 - c4) * coart
		# Prozodie: deklinace fráze, přízvuk, konec fráze, pomalý drift.
		var pos := clampf((tt - p_start) / p_len, 0.0, 1.0)
		var st_off := range_st * (0.5 - pos) * 0.6 + range_st * 0.55 * accent_env
		if last_in_phrase and in_syl:
			st_off += end_st * smoothstep(0.2, 1.0, lt / maxf(s_len, 0.01))
		drift += (rng.randf() - 0.5) * 0.02
		drift *= 0.9995
		var f0 := base_f0 * pow(2.0, (st_off + drift) / 12.0)
		# Koeficienty rezonátorů po blocích (cos/exp jsou drahé).
		if i % COEF_BLOCK == 0:
			var r := exp(-PI * bw1 * (1.6 if nasal else 1.0) * inv)
			a11 = 2.0 * r * cos(TAU * c1 * inv)
			a12 = r * r
			b1 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw2 * inv)
			a21 = 2.0 * r * cos(TAU * c2 * inv)
			a22 = r * r
			b2 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw3 * inv)
			a31 = 2.0 * r * cos(TAU * c3 * inv)
			a32 = r * r
			b3 = (1.0 - r * r) * 0.5
			r = exp(-PI * bw4 * inv)
			a41 = 2.0 * r * cos(TAU * c4 * inv)
			a42 = r * r
			b4 = (1.0 - r * r) * 0.5
		# Hlasivkový zdroj (Rosenbergův puls) s jitterem, shimmerem a subharmonií.
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
		var src := voiced * glott * amp_mul + noise * breath * (0.35 + 0.65 * u) * 0.9 + noise * rough * 0.05 * voiced
		tilt_y += tilt_a * (src - tilt_y)
		var source := tilt_y * env_s
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
		if nasal:
			vowel *= 0.55
		var cons_out := 0.0
		if cons_amp > 0.0:
			var cy := cb0 * noise + ca1 * cz1 - ca2 * cz2
			cz2 = cz1
			cz1 = cy
			cons_out = cy * cons_amp * (2.2 if cons_kind == 4 else 1.4)
		var x := (vowel * 6.0 + cons_out) * energy
		# DC blok.
		dc_y = x - dc_x + 0.995 * dc_y
		dc_x = x
		buf[i] = dc_y
	# Normalizace na energii stylu (ne na pevnou špičku – šepot zůstane tišší).
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	if peak > 1e-6:
		var g := 0.82 * energy / peak
		for i in n:
			buf[i] = tanh(buf[i] * g * 1.15) / tanh(1.15)
	return buf


## Hlas přímo z celé postavy – čte se VÝHRADNĚ skupina voice (test nezávislosti).
static func render_for_character(data: Dictionary, style: Variant = "klidne", variant: int = 0, dur: float = 2.2) -> PackedFloat32Array:
	return render(data.get("voice", {}), style, variant, dur)


## Klíč cache: kvantizace 0,02 (posuvník s krokem 0,01 nemusí přepočítávat každý pixel).
static func cache_key(voice: Variant, style: Variant, variant: int, dur: float) -> String:
	var n := normalized(voice)
	return "%d|%d|%d|%d|%s|%d|%d" % [roundi(n["pitch"] * 50.0), roundi(n["timbre"] * 50.0),
		roundi(n["tempo"] * 50.0), roundi(n["roughness"] * 50.0), style_or_default(style),
		variant, roundi(dur * 100.0)]


## Kvantizovaný hlas (shodný s cache_key) – aby cache vracela přesně to, co klíč popisuje.
static func quantized(voice: Variant) -> Dictionary:
	var n := normalized(voice)
	for k in n:
		n[k] = roundf(float(n[k]) * 50.0) / 50.0
	return n


static func to_stream(buf: PackedFloat32Array, sr: int = SR) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var v := clampi(int(roundf(clampf(buf[i], -1.0, 1.0) * 32767.0)), -32768, 32767)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sr
	s.stereo = false
	s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	s.data = data
	return s


# ------------------------------------------------------------------ řeč z textu (TTS)

## Czech text-to-speech: speaks `text` (≤ 200 characters are used) in the given public voice and
## style. Deterministic (same input → identical bytes), offline, never crashes on odd input.
static func speak(text: Variant, voice: Variant = {}, style: Variant = "klidne", sr: int = CzechTTS.SR) -> AudioStreamWAV:
	var rate := clampi(sr, 8000, 48000)
	return to_stream(CzechTTS.render(text, voice, tts_style_or_default(style), rate), rate)


static func speak_buffer(text: Variant, voice: Variant = {}, style: Variant = "klidne", sr: int = CzechTTS.SR) -> PackedFloat32Array:
	return CzechTTS.render(text, voice, tts_style_or_default(style), clampi(sr, 8000, 48000))


static func tts_style_or_default(style: Variant) -> String:
	return CzechTTS.style_or_default(style)


## Phoneme sequence with "|" word boundaries and punctuation tokens (for tests and tools).
static func tts_phonemes(text: Variant) -> Array:
	return CzechTTS.G2P.phonemes(text)


## Readable phonetic transcription, e.g. "led" → "let", "obchod" → "opxot".
static func tts_transcription(text: Variant) -> String:
	return CzechTTS.G2P.transcribe(text)


## Timed plan (segments, syllables with stress, phrases, F0 track every CzechTTS.F0_STEP s).
static func tts_plan(text: Variant, voice: Variant = {}, style: Variant = "klidne") -> Dictionary:
	return CzechTTS.plan(text, voice, tts_style_or_default(style))


static func tts_f0_contour(text: Variant, voice: Variant = {}, style: Variant = "klidne") -> Dictionary:
	return CzechTTS.f0_contour(text, voice, tts_style_or_default(style))


## Cache key: quantised voice (0.02 like cache_key) + style + hash of the spoken text + rate.
static func tts_cache_key(text: Variant, voice: Variant, style: Variant, sr: int = CzechTTS.SR) -> String:
	var n := quantized(voice)
	var clean := CzechTTS.G2P.normalize(CzechTTS.clean_text(text))
	return "tts|%d|%d|%d|%d|%s|%d|%d|%d" % [roundi(n["pitch"] * 50.0), roundi(n["timbre"] * 50.0),
		roundi(n["tempo"] * 50.0), roundi(n["roughness"] * 50.0), tts_style_or_default(style),
		CzechTTS.text_hash(clean), clean.length(), clampi(sr, 8000, 48000)]


static func tts_style_for_emotion(emotion: Variant) -> String:
	return String(EMOTION_STYLE.get(String(emotion) if typeof(emotion) == TYPE_STRING else "", "klidne"))

