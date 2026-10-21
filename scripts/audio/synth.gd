extends RefCounted
## Offline syntezátor Life Simulator – renderuje hudbu, ambience a zvuky do 16bit WAV.
## Všechny zápisy se „ovíjejí“ kolem konce bufferu (i dozvuk), takže smyčky
## navazují bez švu. Nástroje: FM e-piano, pad (wavetable + filtr), basa,
## Karplus-Strong kytara, zvonkohra, flétna, bicí; Freeverb-like reverb.

const TABLE_SIZE := 2048
const TABLE_MASK := TABLE_SIZE - 1

var sr: int
var length: int
var stereo := true
var left := PackedFloat32Array()
var right := PackedFloat32Array()
var rng := RandomNumberGenerator.new()

static var _tables := {}


func _init(seconds: float, sample_rate := 22050, p_stereo := true, seed := 1) -> void:
	sr = sample_rate
	length = maxi(int(seconds * sr), 1)
	stereo = p_stereo
	left.resize(length)
	left.fill(0.0)
	right.resize(length)
	right.fill(0.0)
	rng.seed = seed


static func midi_to_freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


static func table(kind: String) -> PackedFloat32Array:
	if _tables.has(kind):
		return _tables[kind]
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		var ph := TAU * float(i) / TABLE_SIZE
		var v := 0.0
		match kind:
			"saw":
				for k in range(1, 10):
					v += sin(ph * k) / k
				v *= 0.55
			"square":
				for k in [1, 3, 5, 7, 9]:
					v += sin(ph * k) / k
				v *= 0.8
			_:
				v = sin(ph)
		t[i] = v
	_tables[kind] = t
	return t


## Přimíchá mono buffer do stereo mixu (equal-power panorama), s ovinutím.
func mix(buf: PackedFloat32Array, start: int, pan := 0.0, gain := 1.0) -> void:
	var a := (clampf(pan, -1.0, 1.0) + 1.0) * PI / 4.0
	var gl := cos(a) * gain * 1.41421
	var gr := sin(a) * gain * 1.41421
	if not stereo:
		gl = gain
		gr = 0.0
	var j := posmod(start, length)
	for i in buf.size():
		var v := buf[i]
		left[j] += v * gl
		right[j] += v * gr
		j += 1
		if j >= length:
			j = 0


func sec(t: float) -> int:
	return int(t * sr)


# ------------------------------------------------------------------ nástroje

func epiano(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 0.9) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w := TAU * freq / sr
	var amp := vel * 0.2
	var dn := int(dur * sr)
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var env := minf(1.0, t / 0.004) * exp(-t * 1.5)
		if i > dn:
			env *= exp(-(t - dur) * 7.0)
		var ph := w * i
		var idx := 1.5 * exp(-t * 4.0) + 0.25
		var s := sin(ph + idx * sin(ph)) + 0.16 * sin(ph * 4.0) * exp(-t * 10.0)
		buf[i] = s * env * amp
	return buf


func pad(freq: float, dur: float, vel: float, cutoff := 1400.0) -> PackedFloat32Array:
	var rel := 1.4
	var n := int((dur + rel) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var tab := table("saw")
	var ts := float(TABLE_SIZE)
	var inc1 := freq * 1.004 * ts / sr
	var inc2 := freq * 0.996 * ts / sr
	var inc3 := freq * 0.5 * ts / sr
	var p1 := rng.randf() * ts
	var p2 := rng.randf() * ts
	var p3 := rng.randf() * ts
	var a := 1.0 - exp(-TAU * cutoff / sr)
	var y := 0.0
	var y2 := 0.0
	var amp := vel * 0.11
	var dn := int(dur * sr)
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var env := minf(1.0, t / 0.7)
		if i > dn:
			env *= exp(-(t - dur) * 3.2)
		var v := tab[int(p1) & TABLE_MASK] + tab[int(p2) & TABLE_MASK] + 0.5 * tab[int(p3) & TABLE_MASK]
		p1 += inc1
		p2 += inc2
		p3 += inc3
		if p1 >= ts:
			p1 -= ts
		if p2 >= ts:
			p2 -= ts
		if p3 >= ts:
			p3 -= ts
		y += a * (v - y)
		y2 += a * (y - y2)
		buf[i] = y2 * env * amp
	return buf


func bass(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 0.25) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w := TAU * freq / sr
	var amp := vel * 0.42
	var dn := int(dur * sr)
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var env := minf(1.0, t / 0.008) * (0.55 + 0.45 * exp(-t * 2.5))
		if i > dn:
			env *= exp(-(t - dur) * 18.0)
		var ph := w * i
		buf[i] = (sin(ph) + 0.28 * sin(2.0 * ph) * exp(-t * 3.0) + 0.08 * sin(3.0 * ph)) * env * amp
	return buf


## Karplus-Strong – drnkaná kytara.
func pluck(freq: float, dur: float, vel: float, bright := 0.5) -> PackedFloat32Array:
	var n := int((dur + 1.2) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var p := maxi(int(sr / freq), 2)
	var d := PackedFloat32Array()
	d.resize(p)
	var lp := 0.0
	for i in p:
		lp += (1.0 - bright * 0.6) * (rng.randf_range(-1.0, 1.0) - lp)
		d[i] = lp
	var idx := 0
	var amp := vel * 0.38
	var dn := int(dur * sr)
	var inv := 1.0 / sr
	var decay := 0.4985 + 0.0013 * clampf(1.0 - freq / 1500.0, 0.0, 1.0)
	for i in n:
		var nxt := idx + 1
		if nxt >= p:
			nxt = 0
		var out := d[idx]
		d[idx] = (out + d[nxt]) * decay
		idx = nxt
		var env := 1.0
		if i > dn:
			env = exp(-(i - dn) * inv * 9.0)
		buf[i] = out * amp * env
	return buf


func bell(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 2.5) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ratios := [1.0, 2.76, 5.4, 8.93]
	var amps := [1.0, 0.45, 0.22, 0.1]
	var decs := [0.9, 1.8, 3.2, 5.0]
	var amp := vel * 0.16
	var inv := 1.0 / sr
	for k in 4:
		var w: float = TAU * freq * ratios[k] / sr
		if freq * ratios[k] > sr * 0.45:
			continue
		var ak: float = amps[k]
		var dk: float = decs[k]
		for i in n:
			var t := i * inv
			buf[i] += sin(w * i) * ak * exp(-t * dk) * minf(1.0, t / 0.002) * amp
	return buf


func flute(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 0.2) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var amp := vel * 0.2
	var dn := int(dur * sr)
	var inv := 1.0 / sr
	var noise := 0.0
	for i in n:
		var t := i * inv
		var vib := 1.0 + 0.005 * sin(TAU * 5.2 * t) * minf(1.0, t / 0.35)
		ph += TAU * freq * vib * inv
		var env := minf(1.0, t / 0.07)
		if i > dn:
			env *= exp(-(t - dur) * 25.0)
		noise += 0.2 * (rng.randf_range(-1.0, 1.0) - noise)
		buf[i] = (sin(ph) + 0.12 * sin(2.0 * ph) + 0.05 * sin(3.0 * ph) + 0.06 * noise) * env * amp
	return buf


func kick(vel: float) -> PackedFloat32Array:
	var n := int(0.45 * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var f := 45.0 + 85.0 * exp(-t * 28.0)
		ph += TAU * f * inv
		buf[i] = sin(ph) * exp(-t * 7.0) * vel * 0.75
	return buf


func brush(vel: float) -> PackedFloat32Array:
	var n := int(0.3 * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.35 * (x - lp)
		buf[i] = (x - lp) * exp(-t * 14.0) * minf(1.0, t / 0.01) * vel * 0.3
	return buf


func hat(vel: float, open := false) -> PackedFloat32Array:
	var n := int((0.25 if open else 0.06) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prev := 0.0
	var inv := 1.0 / sr
	var dec := 12.0 if open else 60.0
	for i in n:
		var t := i * inv
		var x := rng.randf_range(-1.0, 1.0)
		buf[i] = (x - prev) * 0.5 * exp(-t * dec) * vel * 0.16
		prev = x
	return buf


func shaker(vel: float) -> PackedFloat32Array:
	var n := int(0.09 * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var inv := 1.0 / sr
	for i in n:
		var t := i * inv
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.5 * (x - lp)
		buf[i] = (x - lp) * sin(PI * minf(t / 0.09, 1.0)) * vel * 0.12
	return buf


## Vyrenderuje jednu notu daným nástrojem a přimíchá ji.
func note(instr: String, midi: float, start_s: float, dur_s: float, vel: float, pan := 0.0, gain := 1.0) -> void:
	var f := midi_to_freq(midi)
	var buf: PackedFloat32Array
	match instr:
		"epiano":
			buf = epiano(f, dur_s, vel)
		"pad":
			buf = pad(f, dur_s, vel)
		"pad_dark":
			buf = pad(f, dur_s, vel, 700.0)
		"bass":
			buf = bass(f, dur_s, vel)
		"pluck":
			buf = pluck(f, dur_s, vel)
		"bell":
			buf = bell(f, dur_s, vel)
		"flute":
			buf = flute(f, dur_s, vel)
		_:
			buf = epiano(f, dur_s, vel)
	mix(buf, sec(start_s), pan, gain)


func drum(kind: String, start_s: float, vel: float, pan := 0.0) -> void:
	var buf: PackedFloat32Array
	match kind:
		"kick":
			buf = kick(vel)
		"brush":
			buf = brush(vel)
		"hat":
			buf = hat(vel)
		"ohat":
			buf = hat(vel, true)
		_:
			buf = shaker(vel)
	mix(buf, sec(start_s), pan)


# ------------------------------------------------------------------ efekty

## Freeverb-like dozvuk (4 hřebenové + 2 všepropustné filtry na kanál), kruhově.
func reverb(wet: float, feedback := 0.8, damp := 0.3) -> void:
	var sc := float(sr) / 44100.0
	for ch in (2 if stereo else 1):
		var spread := 23 if ch == 1 else 0
		var src: PackedFloat32Array = left if ch == 0 else right
		var out := _reverb_channel(src, sc, spread, feedback, damp)
		for i in length:
			var v := src[i] * (1.0 - wet * 0.4) + out[i] * wet
			if ch == 0:
				left[i] = v
			else:
				right[i] = v


func _reverb_channel(src: PackedFloat32Array, sc: float, spread: int, fb: float, damp: float) -> PackedFloat32Array:
	var n0 := int((1116 + spread) * sc)
	var n1 := int((1188 + spread) * sc)
	var n2 := int((1277 + spread) * sc)
	var n3 := int((1356 + spread) * sc)
	var a0n := int((556 + spread) * sc)
	var a1n := int((441 + spread) * sc)
	var c0 := PackedFloat32Array()
	c0.resize(n0)
	c0.fill(0.0)
	var c1 := PackedFloat32Array()
	c1.resize(n1)
	c1.fill(0.0)
	var c2 := PackedFloat32Array()
	c2.resize(n2)
	c2.fill(0.0)
	var c3 := PackedFloat32Array()
	c3.resize(n3)
	c3.fill(0.0)
	var ap0 := PackedFloat32Array()
	ap0.resize(a0n)
	ap0.fill(0.0)
	var ap1 := PackedFloat32Array()
	ap1.resize(a1n)
	ap1.fill(0.0)
	var i0 := 0
	var i1 := 0
	var i2 := 0
	var i3 := 0
	var j0 := 0
	var j1 := 0
	var f0 := 0.0
	var f1 := 0.0
	var f2 := 0.0
	var f3 := 0.0
	var out := PackedFloat32Array()
	out.resize(length)
	# Zahřátí: projet konec smyčky, aby dozvuk z konce zazněl i na začátku.
	var warm := mini(length, int(3.0 * sr))
	var total := warm + length
	for k in total:
		var idx := (length - warm + k) % length
		var x := src[idx] * 0.12
		var y0 := c0[i0]
		f0 = y0 * (1.0 - damp) + f0 * damp
		c0[i0] = x + f0 * fb
		i0 += 1
		if i0 >= n0:
			i0 = 0
		var y1 := c1[i1]
		f1 = y1 * (1.0 - damp) + f1 * damp
		c1[i1] = x + f1 * fb
		i1 += 1
		if i1 >= n1:
			i1 = 0
		var y2 := c2[i2]
		f2 = y2 * (1.0 - damp) + f2 * damp
		c2[i2] = x + f2 * fb
		i2 += 1
		if i2 >= n2:
			i2 = 0
		var y3 := c3[i3]
		f3 = y3 * (1.0 - damp) + f3 * damp
		c3[i3] = x + f3 * fb
		i3 += 1
		if i3 >= n3:
			i3 = 0
		var y := y0 + y1 + y2 + y3
		var b0 := ap0[j0]
		ap0[j0] = y + b0 * 0.5
		y = b0 - y
		j0 += 1
		if j0 >= a0n:
			j0 = 0
		var b1 := ap1[j1]
		ap1[j1] = y + b1 * 0.5
		y = b1 - y
		j1 += 1
		if j1 >= a1n:
			j1 = 0
		if k >= warm:
			out[idx] = y
	return out


## Jednopólový filtr celé stopy (lowpass, nebo highpass = vstup − lowpass).
func filter(cutoff: float, highpass := false) -> void:
	var a := 1.0 - exp(-TAU * cutoff / sr)
	for ch in (2 if stereo else 1):
		var y := 0.0
		for i in length:
			var x: float = left[i] if ch == 0 else right[i]
			y += a * (x - y)
			var v := x - y if highpass else y
			if ch == 0:
				left[i] = v
			else:
				right[i] = v


# ------------------------------------------------------------------ export

func normalize(target_peak := 0.85) -> float:
	var peak := 0.0001
	for i in length:
		peak = maxf(peak, absf(left[i]))
		if stereo:
			peak = maxf(peak, absf(right[i]))
	var g := target_peak / peak
	for i in length:
		left[i] *= g
		right[i] *= g
	return peak


func to_stream(loop := true) -> AudioStreamWAV:
	var ch := 2 if stereo else 1
	var bytes := PackedByteArray()
	bytes.resize(length * ch * 2)
	for i in length:
		# jemný soft-clip
		var l := left[i]
		l = l / (1.0 + absf(l) * 0.15)
		bytes.encode_s16(i * ch * 2, int(clampf(l, -1.0, 1.0) * 32767.0))
		if stereo:
			var r := right[i]
			r = r / (1.0 + absf(r) * 0.15)
			bytes.encode_s16(i * 4 + 2, int(clampf(r, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = stereo
	s.mix_rate = sr
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = length
	return s


func save(path: String, loop := true) -> Error:
	return to_stream(loop).save_to_wav(path)
