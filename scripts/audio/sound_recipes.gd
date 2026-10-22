extends RefCounted
## Procedurální ambience (ptáci, cvrčci, vítr), zvuky objektů (sprcha, TV, sporák,
## běžecký pás) a UI zvuky. Inspirováno šablonami „nature“ z Audio Engine.

const Synth := preload("res://scripts/audio/synth.gd")

const AMBIENCE := ["amb_birds", "amb_dawn", "amb_crickets", "amb_wind", "amb_fridge", "amb_traffic", "amb_neighbors"]
const OBJECT_LOOPS := ["sfx_shower", "sfx_tv", "sfx_stove", "sfx_treadmill"]
const UI := ["ui_click", "ui_chime", "ui_conflict"]
## Vrstvy nad hudbou (smyčky řízené za běhu hlasitostí).
const LAYERS := ["layer_tension"]
## Hlasy hádky (nesrozumitelné formanty, ne slova) a jednorázové zvuky domácnosti.
const VOICES := ["vox_argue_a", "vox_argue_b", "vox_argue_rough_a", "vox_argue_rough_b"]
const HITS := ["hit_door_slam"]


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
		"amb_fridge":
			return _fridge(12.0, sr)
		"amb_traffic":
			return _traffic(30.0, sr)
		"amb_neighbors":
			return _neighbors(40.0, sr)
		"layer_tension":
			return _tension(32.0, sr)
		"vox_argue_a":
			return _argue_voice(sr, 101, 0.0)
		"vox_argue_b":
			return _argue_voice(sr, 202, 0.0)
		"vox_argue_rough_a":
			return _argue_voice(sr, 303, 0.7)
		"vox_argue_rough_b":
			return _argue_voice(sr, 404, 0.7)
		"hit_door_slam":
			return _door_slam(sr)
	push_error("Neznámý zvuk: " + id)
	return null


static func is_loop(id: String) -> bool:
	return not (id.begins_with("ui_") or id.begins_with("vox_") or id.begins_with("hit_"))


static func all_ids() -> Array:
	return AMBIENCE + OBJECT_LOOPS + UI + LAYERS + VOICES + HITS


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


# ---------------------------------------------------------------- byt a město (běh „zvuk“)

## Lednice: brum kompresoru (síťová frekvence a harmonické, celé periody ve smyčce),
## slabé „pískání“ motoru a občasné cvaknutí plechu. Tichá, ale stále přítomná – byt není ticho.
static func _fridge(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 31)
	var rng: RandomNumberGenerator = s.rng
	var n: int = s.length
	var f: float = s.loop_freq(50.0)
	var w: float = s.loop_freq(1130.0)
	var bf: float = s.loop_freq(0.25)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		var beat := 1.0 + 0.12 * sin(TAU * bf * t)
		lp += 0.02 * (rng.randf_range(-1.0, 1.0) - lp)
		buf[i] = (0.5 * sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t) + 0.12 * sin(TAU * 3.0 * f * t)) * beat * 0.4 \
				+ 0.015 * sin(TAU * w * t) + lp * 0.5
	s.mix(buf, 0, -0.15, 1.0)
	s.mix(buf, s.sec(0.013), 0.25, 0.7)
	for k in 3:
		var t0 := rng.randf() * sec
		var cl := PackedFloat32Array()
		cl.resize(int(0.05 * sr))
		for i in cl.size():
			cl[i] = rng.randf_range(-1.0, 1.0) * exp(-float(i) / sr * 120.0) * 0.6
		s.mix(cl, s.sec(t0), rng.randf_range(-0.3, 0.3), 0.5)
	s.reverb(0.12, 0.7, 0.5)
	s.fix_seam()
	s.normalize(0.4)
	return s


## Vzdálený provoz: hnědý šum ulice + projíždějící auta (filtr a hlasitost se otevřou
## a zavřou, panorama přejede), jedno vzdálené zatroubení. Přes okno, tedy tlumené.
static func _traffic(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 47)
	var rng: RandomNumberGenerator = s.rng
	var n: int = s.length
	# podklad – periodická modulace => bezešvá smyčka
	for ch in 2:
		var y := 0.0
		var y2 := 0.0
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			var t := float(i) / n
			var lvl := 0.7 + 0.3 * sin(TAU * 2.0 * t + float(ch))
			y += 0.04 * (rng.randf_range(-1.0, 1.0) - y)
			y2 += 0.04 * (y - y2)
			b[i] = y2 * lvl * 3.0
		s.mix(b, 0, -0.7 if ch == 0 else 0.7, 0.6)
	# auta
	for c in 6:
		var dur := rng.randf_range(4.0, 7.5)
		var t0 := rng.randf() * sec
		var m := int(dur * sr)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var y := 0.0
		var y2 := 0.0
		var car := PackedFloat32Array()
		car.resize(m)
		var eng := rng.randf_range(55.0, 95.0)
		for i in m:
			var x := float(i) / m
			var bell := exp(-pow((x - 0.5) / 0.2, 2.0))
			var cut := 220.0 + 900.0 * bell
			var a := 1.0 - exp(-TAU * cut / sr)
			y += a * (rng.randf_range(-1.0, 1.0) - y)
			y2 += a * (y - y2)
			var doppler := 1.0 + 0.06 * (0.5 - x) * dir
			car[i] = (y2 * 2.2 + 0.25 * sin(TAU * eng * doppler * float(i) / sr)) * bell
		# panorama: rozdělíme na kousky (jednoduchý pohyb zleva doprava)
		var parts := 8
		for p in parts:
			var a0 := int(float(p) / parts * m)
			var a1 := int(float(p + 1) / parts * m)
			var piece := car.slice(a0, a1)
			var pan := dir * (-0.8 + 1.6 * (float(p) + 0.5) / parts)
			s.mix(piece, s.sec(t0) + a0, pan, rng.randf_range(0.5, 0.9))
	# vzdálené zatroubení (dva krátké tóny)
	var th := rng.randf() * sec
	for k in 2:
		var hb := PackedFloat32Array()
		var hn := int(0.28 * sr)
		hb.resize(hn)
		var lp := 0.0
		for i in hn:
			var t := float(i) / sr
			var sq := 1.0 if fmod(t * 392.0, 1.0) < 0.5 else -1.0
			sq += 0.6 * (1.0 if fmod(t * 330.0, 1.0) < 0.5 else -1.0)
			lp += 0.08 * (sq - lp)
			hb[i] = lp * minf(1.0, t / 0.02) * minf(1.0, (0.28 - t) / 0.05) * 0.25
		s.mix(hb, s.sec(th + k * 0.38), 0.55, 0.35)
	s.reverb(0.35, 0.82, 0.5)
	s.filter(1600.0)
	s.fix_seam()
	s.normalize(0.5)
	return s


## Sousedé za zdí: útržky tlumeného hovoru, chvíli basy z jejich hudby, bouchnutí.
## Všechno přes zeď (dvakrát low-pass ~520 Hz) – nesrozumitelné, ale lidské.
static func _neighbors(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 59)
	var rng: RandomNumberGenerator = s.rng
	# hovor: dva hlasy, střídají se
	var t := rng.randf_range(1.0, 3.0)
	var who := 0
	while t < sec - 4.0:
		var d := rng.randf_range(1.5, 3.8)
		var f0 := 118.0 if who == 0 else 205.0
		var inten := rng.randf_range(0.15, 0.55)
		var v: PackedFloat32Array = s.voice(f0, d, inten, 0.15)
		s.mix(v, s.sec(t), -0.35 if who == 0 else -0.1, 0.55)
		t += d + rng.randf_range(0.2, 2.5)
		who = 1 - who
		if rng.randf() < 0.25:
			t += rng.randf_range(3.0, 6.0)
	# basa z jejich hudby (100 BPM, 8 s)
	var mt := rng.randf_range(0.0, sec)
	for k in 13:
		s.drum("kick", mt + k * 0.6, 0.8, 0.4)
		if k % 2 == 1:
			s.note("bass", 33.0, mt + k * 0.6, 0.5, 0.6, 0.4, 0.8)
	# bouchnutí (dveře / skříň)
	var bt := rng.randf_range(0.0, sec)
	var thump := PackedFloat32Array()
	thump.resize(int(0.4 * sr))
	for i in thump.size():
		var tt := float(i) / sr
		thump[i] = sin(TAU * (60.0 + 40.0 * exp(-tt * 30.0)) * tt) * exp(-tt * 14.0) * 0.9
	s.mix(thump, s.sec(bt), 0.2, 0.9)
	s.filter(520.0)
	s.filter(520.0)
	s.reverb(0.18, 0.75, 0.6)
	s.fix_seam()
	s.normalize(0.45)
	return s


## Vrstva napětí (hraje nad hudbou podle stavu domácnosti): netónový podzvuk, kovové
## neharmonické alikvoty, které pomalu tepou proti sobě, tlumený puls 60/min a skoro
## neslyšitelný vysoký tón. Netónová, aby seděla k jakékoli skladbě.
static func _tension(sec: float, sr: int) -> Object:
	var s = Synth.new(sec, sr, true, 71)
	var rng: RandomNumberGenerator = s.rng
	var n: int = s.length
	for ch in 2:
		var y := 0.0
		var y2 := 0.0
		var b := PackedFloat32Array()
		b.resize(n)
		var sw: float = s.loop_freq(1.0 / 16.0)
		for i in n:
			var tt := float(i) / sr
			var swell := 0.6 + 0.4 * sin(TAU * sw * tt + float(ch) * 0.8)
			y += 0.012 * (rng.randf_range(-1.0, 1.0) - y)
			y2 += 0.012 * (y - y2)
			b[i] = y2 * 9.0 * swell
		s.mix(b, 0, -0.6 if ch == 0 else 0.6, 0.8)
	var metal := [187.0, 263.7, 401.3, 579.0, 811.0]
	for k in metal.size():
		var f: float = s.loop_freq(float(metal[k]))
		var trem: float = s.loop_freq(rng.randf_range(0.07, 0.19))
		var b := PackedFloat32Array()
		b.resize(n)
		var ph0 := rng.randf() * TAU
		for i in n:
			var tt := float(i) / sr
			var a := 0.5 + 0.5 * sin(TAU * trem * tt + ph0)
			b[i] = sin(TAU * f * tt) * a * a * (0.09 / (1.0 + k * 0.6))
		s.mix(b, 0, rng.randf_range(-0.7, 0.7), 1.0)
	# puls 60/min (32 úderů ve 32 s – bezešvé), dvojitý tlumený úder
	for k in int(sec):
		for hit in [[0.0, 1.0], [0.19, 0.55]]:
			var hb := PackedFloat32Array()
			hb.resize(int(0.3 * sr))
			for i in hb.size():
				var tt := float(i) / sr
				hb[i] = sin(TAU * (42.0 + 25.0 * exp(-tt * 28.0)) * tt) * exp(-tt * 16.0) * float(hit[1]) * 0.5
			s.mix(hb, s.sec(float(k) + float(hit[0])), 0.0, 1.0)
	# vysoký tón (tinnitus) – velmi slabě
	var ht: float = s.loop_freq(6300.0)
	var tb := PackedFloat32Array()
	tb.resize(n)
	for i in n:
		tb[i] = sin(TAU * ht * float(i) / sr) * 0.006
	s.mix(tb, 0, 0.3, 1.0)
	s.reverb(0.3, 0.86, 0.45)
	s.fix_seam()
	s.normalize(0.6)
	return s


## Hlas v hádce: ~4 s křiku (formanty, ne slova), mono. Tlumení přes stěnu a vzdálenost
## řeší přehrávač za běhu; výška hlasu se dolaďuje pitch_scale podle voice.pitch postavy.
static func _argue_voice(sr: int, seed: int, rough: float) -> Object:
	var s = Synth.new(4.6, sr, false, seed)
	var v: PackedFloat32Array = s.voice(175.0, 3.9, 0.85, rough)
	s.mix(v, s.sec(0.05), 0.0, 1.0)
	s.reverb(0.1, 0.7, 0.5)
	s.normalize(0.7)
	return s


## Bouchnutí dveří: dřevěné tělo (pokles výšky), cvaknutí zámku, rezonance zárubně a místnosti.
static func _door_slam(sr: int) -> Object:
	var s = Synth.new(1.8, sr, false, 83)
	var rng: RandomNumberGenerator = s.rng
	var n := int(0.9 * sr)
	var b := PackedFloat32Array()
	b.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		var body := sin(TAU * (70.0 + 90.0 * exp(-t * 35.0)) * t) * exp(-t * 9.0)
		var wood := sin(TAU * 182.0 * t) * exp(-t * 22.0) * 0.5 + sin(TAU * 311.0 * t) * exp(-t * 30.0) * 0.3
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		var crack := lp * exp(-t * 60.0) * 1.2
		var latch := 0.0
		if t > 0.045 and t < 0.07:
			latch = rng.randf_range(-1.0, 1.0) * exp(-(t - 0.045) * 200.0) * 0.6
		b[i] = (body + wood + crack + latch) * 0.8
	s.mix(b, s.sec(0.01), 0.0, 1.0)
	s.reverb(0.28, 0.78, 0.45)
	s.normalize(0.85)
	return s
