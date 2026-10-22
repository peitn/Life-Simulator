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


# ------------------------------------------------------------------ temné nástroje (běh „zvuk“)

## Plstěné piano (felt): měkký úder, mírně neharmonické alikvoty, tlumené výšky,
## dva lehce rozladěné „struny“ (chorus) – intimní, unavený zvuk místo jasného e-piana.
func felt_piano(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 1.6) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var inv := 1.0 / sr
	var amp := vel * 0.17
	var dn := int(dur * sr)
	var bright := clampf(0.35 + vel * 0.4, 0.0, 1.0)
	var B := 0.0004   # neharmonicita struny
	var parts := 7
	var ws := PackedFloat32Array()
	var as_ := PackedFloat32Array()
	var ds := PackedFloat32Array()
	for k in range(1, parts + 1):
		var fk := freq * k * sqrt(1.0 + B * k * k)
		if fk > sr * 0.45:
			break
		ws.append(TAU * fk * inv)
		as_.append(pow(bright, float(k - 1)) / float(k))
		ds.append(1.1 + 0.9 * k)
	var det := 1.0021
	var lp := 0.0
	var a := 1.0 - exp(-TAU * (900.0 + 2600.0 * vel) * inv)
	for i in n:
		var t := i * inv
		var env := minf(1.0, t / 0.012)
		if i > dn:
			env *= exp(-(t - dur) * 6.0)
		var v := 0.0
		for k in ws.size():
			var e := exp(-t * ds[k])
			v += as_[k] * e * (sin(ws[k] * i) + 0.6 * sin(ws[k] * det * i))
		# „plst“ – krátký tlumený šum úderu
		if t < 0.03:
			v += rng.randf_range(-1.0, 1.0) * 0.08 * (1.0 - t / 0.03)
		lp += a * (v - lp)
		buf[i] = lp * env * amp
	return buf


## Smyčcové violoncello (zjednodušeně): pila se smyčcovým nástupem, opožděné vibrato,
## lehký šum smyčce, dvoupólový low-pass – vážný, „lidský“ hlas melodie.
func cello(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var n := int((dur + 0.6) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var inv := 1.0 / sr
	var tab := table("saw")
	var ts := float(TABLE_SIZE)
	var p := rng.randf() * ts
	var amp := vel * 0.16
	var dn := int(dur * sr)
	var cutoff := 900.0 + 1400.0 * vel
	var a := 1.0 - exp(-TAU * cutoff * inv)
	var y := 0.0
	var y2 := 0.0
	var nz := 0.0
	for i in n:
		var t := i * inv
		var vib := 1.0 + 0.0055 * sin(TAU * 5.0 * t) * smoothstep(0.25, 0.7, t)
		p += freq * vib * ts * inv
		if p >= ts:
			p -= ts
		var env := smoothstep(0.0, 0.22, t) * (0.85 + 0.15 * sin(TAU * 0.7 * t))
		if i > dn:
			env *= exp(-(t - dur) * 9.0)
		nz += 0.3 * (rng.randf_range(-1.0, 1.0) - nz)
		var v := tab[int(p) & TABLE_MASK] + 0.05 * nz
		y += a * (v - y)
		y2 += a * (y - y2)
		buf[i] = y2 * env * amp
	return buf


## Drone: nízký rozladěný shluk s pomalu dýchajícím filtrem – podlaha pro noc a napětí.
func drone(freq: float, dur: float, vel: float) -> PackedFloat32Array:
	var rel := 2.5
	var n := int((dur + rel) * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var inv := 1.0 / sr
	var tab := table("saw")
	var ts := float(TABLE_SIZE)
	var incs := [freq * 0.997, freq * 1.0031, freq * 0.5, freq * 1.4983]
	var gains := [1.0, 0.9, 0.7, 0.18]
	var ph := [rng.randf() * ts, rng.randf() * ts, rng.randf() * ts, rng.randf() * ts]
	var y := 0.0
	var y2 := 0.0
	var amp := vel * 0.09
	var dn := int(dur * sr)
	var lfo_rate := rng.randf_range(0.05, 0.11)
	for i in n:
		var t := i * inv
		var env := minf(1.0, t / 1.8)
		if i > dn:
			env *= exp(-(t - dur) * 1.6)
		var v := 0.0
		for k in 4:
			ph[k] += float(incs[k]) * ts * inv
			if ph[k] >= ts:
				ph[k] -= ts
			v += tab[int(ph[k]) & TABLE_MASK] * float(gains[k])
		var cut := 180.0 + 260.0 * (0.5 + 0.5 * sin(TAU * lfo_rate * t))
		var a := 1.0 - exp(-TAU * cut * inv)
		y += a * (v - y)
		y2 += a * (y - y2)
		buf[i] = y2 * env * amp
	return buf


## Formantový hlas – nesrozumitelná „řeč“ (slabiky z českých samohlásek a šumových
## souhlásek). intensity 0 = klidný hovor, 1 = křik (vyšší f0, víc energie, ostřejší F1).
## rough 0..1 = chraplavost (subharmonie + šum). Vrací mono buffer délky `dur`.
func voice(f0: float, dur: float, intensity: float, rough: float) -> PackedFloat32Array:
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	var inv := 1.0 / sr
	# Samohlásky (F1, F2, F3) – a, e, i, o, u
	var vowels := [[800.0, 1250.0, 2600.0], [520.0, 1800.0, 2550.0], [320.0, 2250.0, 3000.0],
			[520.0, 900.0, 2500.0], [350.0, 720.0, 2400.0]]
	var shout := clampf(intensity, 0.0, 1.0)
	# Plán slabik: [začátek, délka, samohláska, přízvuk, souhláska]
	var plan := []
	var t := rng.randf_range(0.0, 0.15)
	while t < dur - 0.2:
		var phrase := rng.randi_range(3, 9)
		for s in phrase:
			var d := rng.randf_range(0.09, 0.22) * (1.0 + 0.4 * shout * float(s == phrase - 1))
			plan.append([t, d, rng.randi() % vowels.size(), (rng.randf() < 0.3) or s == 0, rng.randi() % 4])
			t += d + rng.randf_range(0.015, 0.05)
			if t >= dur - 0.2:
				break
		t += rng.randf_range(0.18, 0.55) * (1.0 - 0.5 * shout)
	# Buzení: pila s náklonem spektra, jitter, shimmer; formanty jako 3 rezonátory.
	var phase := 0.0
	var f1 := 500.0
	var f2 := 1500.0
	var f3 := 2500.0
	var z := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
	var coef := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var tilt := 0.0
	var nz := 0.0
	var sub := 1.0
	var si := 0
	var base := f0 * (1.0 + 0.45 * shout)
	var bws := [90.0 + 60.0 * shout, 110.0, 160.0]
	var fgain := [1.0, 0.55 + 0.25 * shout, 0.25 + 0.2 * shout]
	for i in n:
		var tt := i * inv
		while si < plan.size() - 1 and tt > float(plan[si][0]) + float(plan[si][1]):
			si += 1
		var amp := 0.0
		var target: Array = vowels[2]
		var pitch := base
		var cons := false
		if plan.size() > 0:
			var syl: Array = plan[si]
			var st: float = syl[0]
			var sd: float = syl[1]
			var lt := tt - st
			if lt >= 0.0 and lt <= sd:
				amp = smoothstep(0.0, 0.018, lt) * (1.0 - smoothstep(sd - 0.04, sd, lt))
				amp *= 1.0 if bool(syl[3]) else 0.72
				target = vowels[int(syl[2])]
				# intonace: přízvuk nahoru, konec slabiky mírně dolů; křik = strmější
				pitch = base * (1.0 + (0.18 + 0.2 * shout) * float(bool(syl[3])) * (1.0 - lt / sd) - 0.06 * lt / sd)
				cons = lt < 0.035 and int(syl[4]) != 0
		# formanty plynule sledují cíl (~25 ms)
		var k := 1.0 - exp(-inv / 0.025)
		f1 += k * (float(target[0]) * (1.0 + 0.18 * shout) - f1)
		f2 += k * (float(target[1]) - f2)
		f3 += k * (float(target[2]) - f3)
		if i % 32 == 0:
			var fs := [f1, f2, f3]
			for r in 3:
				var w := TAU * float(fs[r]) * inv
				var rad := exp(-PI * float(bws[r]) * inv)
				coef[r][0] = 2.0 * rad * cos(w)
				coef[r][1] = -rad * rad
				coef[r][2] = (1.0 - rad * rad) * 0.5
		var jit := 1.0 + rng.randf_range(-0.012, 0.012) * (1.0 + 2.0 * rough)
		phase += pitch * jit * inv
		if phase >= 1.0:
			phase -= 1.0
			sub = -sub
		var src := 1.0 - 2.0 * phase
		if rough > 0.0:
			src += rough * 0.3 * sub
		tilt += (0.35 - 0.2 * shout) * (src - tilt)
		nz += 0.5 * (rng.randf_range(-1.0, 1.0) - nz)
		var exc := tilt * amp + nz * amp * (0.04 + 0.25 * rough * shout)
		if cons:
			exc = rng.randf_range(-1.0, 1.0) * 0.6
		var out := 0.0
		for r in 3:
			var y: float = coef[r][2] * exc + coef[r][0] * float(z[r][0]) + coef[r][1] * float(z[r][1])
			z[r][1] = z[r][0]
			z[r][0] = y
			out += y * float(fgain[r])
		buf[i] = out * (0.9 + 0.5 * shout)
	# normalizace bufferu na rozumnou špičku
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(buf[i]))
	var g := 0.7 / pk
	for i in n:
		buf[i] *= g
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
		"felt":
			buf = felt_piano(f, dur_s, vel)
		"cello":
			buf = cello(f, dur_s, vel)
		"drone":
			buf = drone(f, dur_s, vel)
		"pluck_muted":
			buf = pluck(f, minf(dur_s, 0.35), vel, 0.08)
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


## Frekvence zaokrouhlená tak, aby se do smyčky vešel celý počet period (bez švu).
func loop_freq(f: float) -> float:
	var len_s := float(length) / sr
	return maxf(1.0, roundf(f * len_s)) / len_s


## „Opotřebovaná páska“: kolísání rychlosti (wow + flutter) frakčním zpožděním.
## Modulace má celý počet period ve smyčce, takže smyčka zůstává bezešvá.
func wow(depth_ms := 0.8, rate := 0.45, flutter_ms := 0.08, flutter_rate := 6.5) -> void:
	var wr := loop_freq(rate)
	var fr := loop_freq(flutter_rate)
	var dmax := (depth_ms + flutter_ms) * 0.001 * sr
	var inv := 1.0 / sr
	for ch in (2 if stereo else 1):
		var src: PackedFloat32Array = (left if ch == 0 else right).duplicate()
		var off := 0.37 * float(ch)
		for i in length:
			var t := i * inv
			var d := dmax * 0.5 + depth_ms * 0.0005 * sr * sin(TAU * wr * t + off) \
					+ flutter_ms * 0.0005 * sr * sin(TAU * fr * t)
			var pos := float(i) - d
			var i0 := int(floor(pos))
			var fr_ := pos - float(i0)
			var a: float = src[posmod(i0, length)]
			var b: float = src[posmod(i0 + 1, length)]
			var v := a + (b - a) * fr_
			if ch == 0:
				left[i] = v
			else:
				right[i] = v


## Textura nahrávky: šum pásky (hiss), síťový brum (50 Hz + harmonické) a praskání desky.
## Úrovně jsou lineární amplitudy po normalizaci (typicky 0,002–0,01).
func texture(hiss := 0.0, hum := 0.0, crackle := 0.0) -> void:
	var inv := 1.0 / sr
	var hf := loop_freq(50.0)
	var hp_l := 0.0
	var hp_r := 0.0
	for i in length:
		var t := i * inv
		var v := 0.0
		if hum > 0.0:
			v += hum * (sin(TAU * hf * t) + 0.5 * sin(TAU * 2.0 * hf * t) + 0.25 * sin(TAU * 3.0 * hf * t))
		var nl := 0.0
		var nr := 0.0
		if hiss > 0.0:
			var xl := rng.randf_range(-1.0, 1.0)
			var xr := rng.randf_range(-1.0, 1.0)
			hp_l += 0.25 * (xl - hp_l)
			hp_r += 0.25 * (xr - hp_r)
			nl = (xl - hp_l) * hiss
			nr = (xr - hp_r) * hiss
		if crackle > 0.0 and rng.randf() < 0.0009:
			var c := rng.randf_range(-1.0, 1.0) * crackle * 12.0
			nl += c
			nr += c * rng.randf_range(0.3, 1.0)
		left[i] += v + nl
		if stereo:
			right[i] += v + nr


## Bezešvá smyčka i pro šum: pomalá lineární korekce (neslyšitelný posun DC), aby poslední
## vzorek navázal na první (předpověď z prvních dvou vzorků). Volat před normalize().
func fix_seam() -> void:
	if length < 3:
		return
	for ch in (2 if stereo else 1):
		var buf: PackedFloat32Array = left if ch == 0 else right
		var delta := (2.0 * buf[0] - buf[1]) - buf[length - 1]
		var inv := 1.0 / float(length - 1)
		for i in length:
			buf[i] += delta * float(i) * inv
		if ch == 0:
			left = buf
		else:
			right = buf


## Ztlumí úsek (ticho jako stav) – měkký fade, s ovinutím kolem konce.
func duck_range(start_s: float, dur_s: float, depth := 0.85, fade_s := 1.2) -> void:
	var a := sec(start_s)
	var n := sec(dur_s)
	var f := maxi(sec(fade_s), 1)
	for k in n:
		var w := minf(1.0, minf(float(k) / f, float(n - k) / f))
		var g := 1.0 - depth * w
		var j := posmod(a + k, length)
		left[j] *= g
		right[j] *= g


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
