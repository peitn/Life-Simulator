extends RefCounted
## Procedurální ambience (ptáci, cvrčci, vítr), zvuky objektů (sprcha, TV, sporák,
## běžecký pás) a UI zvuky. Inspirováno šablonami „nature“ z Audio Engine.

const Synth := preload("res://scripts/audio/synth.gd")

const AMBIENCE := ["amb_birds", "amb_dawn", "amb_crickets", "amb_wind"]
const OBJECT_LOOPS := ["sfx_shower", "sfx_tv", "sfx_stove", "sfx_treadmill"]
const UI := ["ui_click", "ui_chime", "ui_conflict"]


static func render(id: String, sr := 22050) -> Object:
	match id:
		"amb_birds":
			return _birds(20.0, 14, sr, 11)
		"amb_dawn":
			return _birds(20.0, 34, sr, 23)
		"amb_crickets":
			return _crickets(20.0, sr)
		"amb_wind":
			return _wind(24.0, sr)
		"sfx_shower":
			return _shower(4.0, sr)
		"sfx_tv":
			return _tv(6.0, sr)
		"sfx_stove":
			return _stove(4.0, sr)
		"sfx_treadmill":
			return _treadmill(3.2, sr)
		"ui_click":
			return _blip(sr)
		"ui_chime":
			return _chime(sr, [76, 83, 88], 0.11)
		"ui_conflict":
			return _chime(sr, [57, 56], 0.16)
	push_error("Neznámý zvuk: " + id)
	return null


static func is_loop(id: String) -> bool:
	return not id.begins_with("ui_")


# ---------------------------------------------------------------- ambience

## Ptáci: zpěvné fráze z frekvenčních „cvrlik“ glissand, náhodně v prostoru.
static func _birds(sec: float, phrases: int, sr: int, seed: int) -> Object:
	var s = Synth.new(sec, sr, true, seed)
	var rng: RandomNumberGenerator = s.rng
	for p in phrases:
		var t := rng.randf() * sec
		var base := rng.randf_range(2200.0, 4200.0)
		var pan := rng.randf_range(-0.9, 0.9)
		var gain := rng.randf_range(0.25, 0.7)
		var notes := rng.randi_range(3, 8)
		var style := rng.randi_range(0, 2)
		for k in notes:
			var dur := rng.randf_range(0.05, 0.16)
			var f0 := base * rng.randf_range(0.85, 1.2)
			var f1 := f0 * (rng.randf_range(1.15, 1.5) if style != 1 else rng.randf_range(0.6, 0.85))
			s.mix(_chirp(sr, f0, f1, dur, rng), s.sec(t), pan, gain)
			t += dur + rng.randf_range(0.03, 0.12)
	s.filter(1200.0, true)
	s.reverb(0.25, 0.75, 0.5)
	s.normalize(0.6)
	return s


static func _chirp(sr: int, f0: float, f1: float, dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var trill := rng.randf_range(0.0, 40.0)
	for i in n:
		var x := float(i) / n
		var f := lerpf(f0, f1, x * x) * (1.0 + 0.03 * sin(TAU * trill * x * dur))
		ph += TAU * f / sr
		buf[i] = sin(ph) * sin(PI * x) * 0.5
	return buf


## Cvrčci: vysoký tón 4–5 kHz amplitudově modulovaný pulzy v sériích.
static func _crickets(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 5)
	var rng: RandomNumberGenerator = s.rng
	for c in 5:
		var freq := rng.randf_range(3900.0, 4900.0)
		var pan := rng.randf_range(-0.85, 0.85)
		var gain := rng.randf_range(0.15, 0.4)
		var period := rng.randf_range(0.45, 0.9)
		var pulses := rng.randi_range(2, 4)
		var t := rng.randf() * period
		while t < sec:
			var n := int(pulses * 0.035 * sr)
			var buf := PackedFloat32Array()
			buf.resize(n)
			for i in n:
				var tt := float(i) / sr
				var pulse := maxf(0.0, sin(PI * fmod(tt, 0.035) / 0.035))
				buf[i] = sin(TAU * freq * tt) * pulse * pulse * 0.4
			s.mix(buf, s.sec(t), pan, gain)
			t += period * rng.randf_range(0.9, 1.1)
	s.reverb(0.3, 0.8, 0.4)
	s.normalize(0.5)
	return s


## Vítr: filtrovaný šum s pomalou modulací (poryvy), stereo nezávislé.
static func _wind(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 9)
	var rng: RandomNumberGenerator = s.rng
	var n: int = s.length
	for ch in 2:
		var y := 0.0
		var y2 := 0.0
		var buf := PackedFloat32Array()
		buf.resize(n)
		var ph := rng.randf() * TAU
		for i in n:
			var t := float(i) / n
			# periodické poryvy => bezešvá smyčka
			var gust := 0.55 + 0.3 * sin(TAU * 3.0 * t + ph) + 0.15 * sin(TAU * 7.0 * t + ph * 2.0)
			var cutoff := 250.0 + 500.0 * gust
			var a := 1.0 - exp(-TAU * cutoff / sr)
			y += a * (rng.randf_range(-1.0, 1.0) - y)
			y2 += a * (y - y2)
			buf[i] = y2 * gust
		s.mix(buf, 0, -0.8 if ch == 0 else 0.8, 1.0)
	s.normalize(0.55)
	return s


# ---------------------------------------------------------------- objekty (mono)

static func _shower(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, false, 3)
	var rng: RandomNumberGenerator = s.rng
	var buf := PackedFloat32Array()
	buf.resize(s.length)
	var lp := 0.0
	for i in s.length:
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (x - lp)
		var t: float = float(i) / s.length
		buf[i] = (x - lp * 0.7) * (0.8 + 0.2 * sin(TAU * 5.0 * t)) * 0.5
	s.mix(buf, 0)
	# kapky
	for k in 120:
		var d := PackedFloat32Array()
		var dn := int(0.02 * sr)
		d.resize(dn)
		var f := rng.randf_range(1500.0, 3500.0)
		for i in dn:
			d[i] = sin(TAU * f * i / sr * (1.0 + i / float(dn))) * exp(-i / float(dn) * 6.0) * 0.4
		s.mix(d, rng.randi_range(0, s.length - 1), 0.0, rng.randf_range(0.2, 0.6))
	s.normalize(0.7)
	return s


## Televize: zabarvený šum s „slabikovou“ modulací = vzdálené mluvené slovo.
static func _tv(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, false, 4)
	var rng: RandomNumberGenerator = s.rng
	var buf := PackedFloat32Array()
	buf.resize(s.length)
	var lp1 := 0.0
	var lp2 := 0.0
	var env := 0.0
	var target := 0.0
	var next_change := 0
	var formant := 700.0
	var ph := 0.0
	for i in s.length:
		if i >= next_change:
			target = rng.randf_range(0.2, 1.0) if rng.randf() > 0.18 else 0.0
			formant = rng.randf_range(400.0, 1400.0)
			next_change = i + int(rng.randf_range(0.07, 0.22) * sr)
		env += 0.004 * (target - env)
		var x := rng.randf_range(-1.0, 1.0)
		var a1 := 1.0 - exp(-TAU * formant * 2.0 / sr)
		lp1 += a1 * (x - lp1)
		lp2 += 0.03 * (lp1 - lp2)
		ph += TAU * (110.0 + 30.0 * env) / sr
		buf[i] = ((lp1 - lp2) * 0.8 + 0.25 * sin(ph) * env) * env
	s.mix(buf, 0)
	s.normalize(0.6)
	return s


static func _stove(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, false, 6)
	var rng: RandomNumberGenerator = s.rng
	var buf := PackedFloat32Array()
	buf.resize(s.length)
	var prev := 0.0
	for i in s.length:
		var x := rng.randf_range(-1.0, 1.0)
		var t: float = float(i) / s.length
		buf[i] = (x - prev) * 0.18 * (0.7 + 0.3 * sin(TAU * 2.0 * t))
		prev = x
	s.mix(buf, 0)
	# praskání tuku
	for k in 70:
		var dn := int(rng.randf_range(0.003, 0.012) * sr)
		var d := PackedFloat32Array()
		d.resize(dn)
		for i in dn:
			d[i] = rng.randf_range(-1.0, 1.0) * exp(-float(i) / dn * 5.0)
		s.mix(d, rng.randi_range(0, s.length - 1), 0.0, rng.randf_range(0.2, 0.7))
	s.normalize(0.6)
	return s


static func _treadmill(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, false, 8)
	var hum := PackedFloat32Array()
	hum.resize(s.length)
	for i in s.length:
		var t := float(i) / sr
		hum[i] = (sin(TAU * 100.0 * t) * 0.5 + sin(TAU * 200.0 * t) * 0.2) * 0.12
	s.mix(hum, 0)
	for k in 8:  # 8 kroků za 3,2 s = 150 kroků/min
		s.drum("kick", k * 0.4, 0.55 if k % 2 == 0 else 0.45)
		s.drum("brush", k * 0.4 + 0.01, 0.3)
	s.normalize(0.65)
	return s


# ---------------------------------------------------------------- UI

static func _blip(sr: int) -> Object:
	var s = Synth.new(0.08, sr, false, 1)
	var n: int = s.length
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var x := float(i) / n
		buf[i] = sin(TAU * (1800.0 - 600.0 * x) * i / sr) * (1.0 - x) * (1.0 - x) * 0.5
	s.mix(buf, 0)
	s.normalize(0.5)
	return s


static func _chime(sr: int, notes: Array, step: float) -> Object:
	var s = Synth.new(step * notes.size() + 1.6, sr, false, 2)
	for k in notes.size():
		s.note("bell", notes[k], k * step, 0.3, 0.7)
	s.normalize(0.55)
	return s
