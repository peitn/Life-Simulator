extends "res://tests/test_base.gd"
## Zvuk: hudba v3 (původní skladby, „noc“ jako vzor tónu, nové ráno v jejím duchu),
## nové nástroje syntezátoru (konečné hodnoty, determinismus, bezešvé smyčky),
## vyrenderované soubory (špička, klipování, ticho, šev), ambience bytu podle času,
## hádky (hlas u postavy, výška z voice.pitch, cooldown, limit, rychlý čas) a vrstva napětí.

const Synth := preload("res://scripts/audio/synth.gd")
const MusicData := preload("res://scripts/audio/music_data.gd")
const Recipes := preload("res://scripts/audio/sound_recipes.gd")
const WavLoader := preload("res://scripts/audio/wav_loader.gd")

const INSTRUMENTS := ["epiano", "pad", "pad_dark", "bass", "pluck", "bell", "flute", "felt", "cello", "drone", "pluck_muted"]
const CHORD_STYLES := ["pad", "pad_dark", "epiano_comp"]
## Nástroje hudby v2, kterou uživatelka odmítla (22. 10. 2026) – skladby je nesmí používat;
## v syntezátoru zůstávají pro recepty zvuků.
const V2_INSTR := ["felt", "cello", "drone", "pluck_muted"]
## Ráno musí zůstat v duchu „noci“: bez veselých prvků.
const BRIGHT_INSTR := ["flute", "pluck"]
const BRIGHT_ARP := ["pop", "up"]

class FakeSim extends Node3D:
	signal action_started(sim: Node3D, action: Dictionary)
	signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
	signal social_event(sim: Node3D, positive: bool, milestone: bool)
	var look := {}
	var grammar := "m"
	var target = null
	var mental = null


func _init() -> void:
	watchdog_seconds = 150.0


func _ready() -> void:
	_test_song_data()
	_test_instruments()
	_test_files()
	_test_music_brightness()
	_test_ambience()
	await _test_conflicts()
	finish("test_audio_tone")


# ---------------------------------------------------------------- data

func _test_song_data() -> void:
	section("Hudba v3 – data skladeb (vzor tónu: noc)")
	check(MusicData.DESIGN_VERSION >= 3, "verze hudebního designu ≥ 3 (návrat k původní hudbě)")
	check(MusicData.TONE_REFERENCE == "noc", "vzorem tónu je „noc“")
	for id in ["rano", "den", "vecer", "noc", "melancholie"]:
		check(MusicData.SONGS.has(id), "skladba %s existuje (výběr podle času ji potřebuje)" % id)
	for id in MusicData.SONGS:
		var s: Dictionary = MusicData.SONGS[id]
		check(float(s["tempo"]) >= 50.0 and float(s["tempo"]) <= 120.0, "%s: tempo v rozumném rozsahu" % id, str(s["tempo"]))
		check(INSTRUMENTS.has(s["melody_instr"]), "%s: známý nástroj melodie" % id, s["melody_instr"])
		check(CHORD_STYLES.has(s["chord_instr"]), "%s: známý styl akordů" % id, s["chord_instr"])
		var arp_i: String = s.get("arp_instr", "")
		check(arp_i == "" or INSTRUMENTS.has(arp_i), "%s: známý nástroj doprovodu" % id, arp_i)
		check(not V2_INSTR.has(s["melody_instr"]) and not V2_INSTR.has(arp_i),
				"%s: bez nástrojů odmítnuté hudby v2" % id)
		check((s["chords"] as Array).size() == 8, "%s: 8 taktů akordů" % id)
		var ok_notes := true
		for ch in s["chords"]:
			ok_notes = ok_notes and (ch as Array).size() >= 3
			for nn in ch:
				ok_notes = ok_notes and int(nn) >= 28 and int(nn) <= 90
		var ok_mel := true
		for m in s["melody"]:
			ok_mel = ok_mel and int(m[0]) >= 28 and int(m[0]) <= 96 and float(m[1]) >= 0.0 \
					and float(m[1]) + float(m[2]) <= 32.0 + 0.001 and int(m[3]) > 0 and int(m[3]) <= 127
		check(ok_notes, "%s: akordy v rozsahu" % id)
		check(ok_mel, "%s: melodie v rozsahu a v délce 2. průchodu" % id)
	# Vzor tónu – „noc“ zůstává přesně původní (uživatelka: správný vibe)
	var noc: Dictionary = MusicData.SONGS["noc"]
	check(noc["melody_instr"] == "bell" and noc["chord_instr"] == "pad_dark" and noc["drums"] == ""
			and float(noc["tempo"]) == 66.0 and (noc["melody"] as Array).size() == 18,
			"noc: původní verze (zvonek, tmavý pad, bez bicích, 66 BPM)")
	# Ráno v duchu noci
	var r: Dictionary = MusicData.SONGS["rano"]
	check(float(r["tempo"]) <= float(noc["tempo"]) + 8.0, "ráno: pomalé jako noc (%.0f BPM)" % float(r["tempo"]))
	check(r["drums"] == "", "ráno: bez bicích")
	check(not BRIGHT_INSTR.has(r["melody_instr"]) and not BRIGHT_INSTR.has(r.get("arp_instr", "")),
			"ráno: bez flétny a drnkání")
	check(not BRIGHT_ARP.has(r["arp"]), "ráno: bez veselého arpeggia", r["arp"])
	check(r["melody_instr"] == noc["melody_instr"], "ráno: stejná barva melodie jako noc")
	check(float(r["reverb"]) >= 0.4, "ráno: hodně prostoru (dozvuk ≥ 0,4)")
	var minor_bars := 0
	for ch in r["chords"]:
		var root: int = ch[0]
		if ch.has(root + 3) or ch.has(root + 15):
			minor_bars += 1
	check(minor_bars >= 3, "ráno: aspoň 3 mollové akordy z 8 (%d)" % minor_bars)
	check((r["melody"] as Array).size() <= int(ceil((noc["melody"] as Array).size() * 1.2)),
			"ráno: řídká melodie jako noc (%d not)" % (r["melody"] as Array).size())
	var last: Array = r["chords"][7]
	check(not (last.has(int(last[0]) + 3) or last.has(int(last[0]) + 4)), "ráno: smyčka končí nevyřešeně (sus akord)")


# ---------------------------------------------------------------- syntéza

static func _finite_peak(buf: PackedFloat32Array) -> float:
	var pk := 0.0
	for v in buf:
		if is_nan(v) or is_inf(v):
			return -1.0
		pk = maxf(pk, absf(v))
	return pk


func _test_instruments() -> void:
	section("Syntéza – nové nástroje a efekty")
	var syn := Synth.new(1.0, 22050, true, 7)
	for instr in ["felt", "cello", "drone", "pluck_muted"]:
		var buf: PackedFloat32Array
		match instr:
			"felt":
				buf = syn.felt_piano(220.0, 0.5, 0.7)
			"cello":
				buf = syn.cello(110.0, 0.5, 0.7)
			"drone":
				buf = syn.drone(55.0, 0.5, 0.7)
			_:
				buf = syn.pluck(330.0, 0.3, 0.7, 0.08)
		var pk := _finite_peak(buf)
		check(pk > 0.001 and pk < 2.0, "%s: konečné hodnoty, slyšitelné, bez přebuzení" % instr, str(pk))
	var v1 := Synth.new(2.0, 22050, false, 11).voice(175.0, 1.5, 0.85, 0.0)
	var v2 := Synth.new(2.0, 22050, false, 11).voice(175.0, 1.5, 0.85, 0.0)
	var v3 := Synth.new(2.0, 22050, false, 11).voice(175.0, 1.5, 0.85, 0.7)
	var vp := _finite_peak(v1)
	check(vp > 0.5 and vp <= 0.7001, "hlas: konečný a normalizovaný na 0,7", str(vp))
	check(v1 == v2, "hlas: stejný seed = stejný výsledek (determinismus)")
	check(v1 != v3, "hlas: chraplavost mění zvuk")
	var calm := Synth.new(2.0, 22050, false, 3).voice(175.0, 1.5, 0.1, 0.0)
	check(_finite_peak(calm) > 0.5, "hlas: klidná řeč (sousedé) funguje")
	var a1 = Recipes.render("vox_argue_a")
	var a2 = Recipes.render("vox_argue_a")
	check(a1.to_stream(false).data == a2.to_stream(false).data, "recept vox_argue_a je deterministický")
	# loop_freq: celý počet period ve smyčce
	var lf := Synth.new(12.0, 22050, true, 1)
	var len_s := float(lf.length) / lf.sr
	for f in [50.0, 0.25, 1130.0, 6300.0]:
		var q: float = lf.loop_freq(f) * len_s
		check(absf(q - roundf(q)) < 1e-3 and absf(lf.loop_freq(f) - f) / f < 0.1,
				"loop_freq(%.2f) má celý počet period" % f, str(q))
	# fix_seam: náhodná procházka (šum s driftem) navazuje
	var rw := Synth.new(3.0, 22050, true, 5)
	var acc := 0.0
	for i in rw.length:
		acc += rw.rng.randf_range(-0.01, 0.01)
		rw.left[i] = acc
		rw.right[i] = -acc
	var before := absf((2.0 * rw.left[0] - rw.left[1]) - rw.left[rw.length - 1])
	rw.fix_seam()
	var after := absf((2.0 * rw.left[0] - rw.left[1]) - rw.left[rw.length - 1])
	var after_r := absf((2.0 * rw.right[0] - rw.right[1]) - rw.right[rw.length - 1])
	check(after < 1e-4 and after_r < 1e-4, "fix_seam: konec navazuje na začátek (obě strany)", "%.5f → %.6f" % [before, after])
	# wow: délka zachovaná, hodnoty konečné, smyčka bezešvá (modulace s celým počtem period)
	var ww := Synth.new(2.0, 22050, true, 9)
	ww.mix(ww.cello(110.0, 2.0, 0.8), 0)
	var n0: int = ww.length
	ww.wow(1.0, 0.4)
	check(ww.left.size() == n0 and _finite_peak(ww.left) > 0.0, "wow: délka i hodnoty v pořádku")
	# duck_range ztlumí střed úseku
	var dk := Synth.new(4.0, 22050, false, 1)
	dk.left.fill(1.0)
	dk.duck_range(1.0, 2.0, 0.85, 0.5)
	check(absf(dk.left[dk.sec(2.0)] - 0.15) < 0.01 and dk.left[dk.sec(0.5)] == 1.0, "duck_range: ticho uprostřed, mimo beze změny")


# ---------------------------------------------------------------- soubory

func _test_files() -> void:
	section("Vyrenderované soubory (tools/build_audio.gd)")
	var ids: Array = []
	for id in MusicData.SONGS:
		ids.append(["res://audio/music/%s.wav" % id, id, true])
	for id in Recipes.all_ids():
		ids.append(["res://audio/sfx/%s.wav" % id, id, Recipes.is_loop(id)])
	for e in ids:
		var path: String = e[0]
		var id: String = e[1]
		var loop: bool = e[2]
		var w := WavLoader.load_wav(path, loop)
		if not check(w != null, "%s: soubor existuje a načte se" % id):
			continue
		var d: PackedByteArray = w.data
		var ch := 2 if w.stereo else 1
		var n := d.size() / 2
		var pk := 0
		var clip := 0
		var ss := 0.0
		var step := 1 if n < 400000 else 3
		for i in range(0, n, step):
			var v := absi(d.decode_s16(i * 2))
			pk = maxi(pk, v)
			ss += float(v) * float(v)
			if v >= 32700:
				clip += 1
		var rms := sqrt(ss / float(n / step)) / 32767.0
		check(pk / 32767.0 <= 0.95 and clip == 0, "%s: bez přebuzení (špička %.2f)" % [id, pk / 32767.0])
		check(rms > 0.01, "%s: není ticho (RMS %.3f)" % [id, rms])
		check((w.loop_mode == AudioStreamWAV.LOOP_FORWARD) == loop, "%s: smyčka = %s" % [id, str(loop)])
		if loop and not id.begins_with("sfx_") and not id.begins_with("amb_birds") and not id.begins_with("amb_dawn") \
				and not id.begins_with("amb_crickets") and not id.begins_with("amb_wind"):
			var seam := 0.0
			for c in ch:
				var first := d.decode_s16(c * 2)
				var last := d.decode_s16((n - ch + c) * 2)
				seam = maxf(seam, absf(float(first - last)) / 32767.0)
			# Skok na švu porovnáváme s běžným rozdílem sousedních vzorků v souboru (99. percentil):
			# hudba s hi-hatem má přirozeně větší skoky než pad, pevná mez 0,035 byla na „den“ moc přísná.
			var diffs := PackedFloat32Array()
			for i in range(1, n / ch, 7):
				diffs.append(absf(float(d.decode_s16(i * ch * 2) - d.decode_s16((i - 1) * ch * 2))) / 32767.0)
			diffs.sort()
			var p99: float = diffs[int(diffs.size() * 0.99)] if diffs.size() > 0 else 0.0
			check(seam <= maxf(0.035, p99), "%s: bezešvá smyčka (skok %.4f, běžný p99 %.4f)" % [id, seam, p99])


func _zcr_per_s(path: String) -> float:
	var w := WavLoader.load_wav(path, true)
	if w == null:
		return -1.0
	var d: PackedByteArray = w.data
	var ch := 2 if w.stereo else 1
	var n := d.size() / (2 * ch)
	# Odhad z každé 4. dvojice sousedních vzorků (levý kanál) – rychlé a nestranné.
	var zc := 0
	var step := 2 * ch
	for i in range(0, n - 1, 4):
		var v0 := d.decode_s16(i * step)
		var v1 := d.decode_s16(i * step + step)
		if (v0 >= 0) != (v1 >= 0):
			zc += 4
	return float(zc) / (float(n) / float(w.mix_rate))


func _test_music_brightness() -> void:
	section("Hudba v3 – jas (průchody nulou za sekundu)")
	var zr := _zcr_per_s("res://audio/music/rano.wav")
	var zn := _zcr_per_s("res://audio/music/noc.wav")
	var zd := _zcr_per_s("res://audio/music/den.wav")
	check(zr > 0.0 and zn > 0.0 and zd > 0.0, "soubory hudby se načtou")
	check(zr >= zn * 0.95, "ráno je světlejší (nebo stejné) než noc (%.0f vs %.0f)" % [zr, zn])
	check(zr <= zn * 1.25, "ráno zůstává blízko noci, ne „sluníčko“ (%.0f ≤ 1,25 × %.0f)" % [zr, zn])
	check(zr < zd, "ráno je tmavší než den (%.0f < %.0f)" % [zr, zd])


# ---------------------------------------------------------------- ambience

func _test_ambience() -> void:
	section("Ambience bytu podle denní doby")
	var am = get_node_or_null("/root/AudioManager")
	if not check(am != null, "AudioManager běží (autoload)"):
		return
	var w13: Dictionary = am.ambience_weights(13.0)
	for id in am.AMBIENCE_IDS:
		check(w13.has(id), "váha pro %s existuje" % id)
	check(float(w13["amb_birds"]) <= 0.25, "přes den ptáci jen v pozadí (≤ 0,25)", str(w13["amb_birds"]))
	check(float(w13["amb_traffic"]) > float(w13["amb_birds"]), "přes den je slyšet spíš ulice než ptáci")
	var fridge_ok := true
	var max_birds := 0.0
	for h in 24:
		var w: Dictionary = am.ambience_weights(float(h) + 0.5)
		fridge_ok = fridge_ok and float(w["amb_fridge"]) > 0.0
		max_birds = maxf(max_birds, float(w["amb_birds"]) + float(w["amb_dawn"]))
		for k in w:
			fridge_ok = fridge_ok and float(w[k]) >= 0.0 and float(w[k]) <= 1.0
	check(fridge_ok, "lednice hraje celý den a všechny váhy jsou v 0..1")
	check(max_birds <= 0.5, "ptačí koncert nikdy nepřebije byt (max %.2f)" % max_birds)
	check(float(am.ambience_weights(21.0)["amb_neighbors"]) > float(am.ambience_weights(4.0)["amb_neighbors"]) + 0.2,
			"sousedé večer slyšet, ve 4 ráno ne")
	check(float(am.ambience_weights(2.0)["amb_traffic"]) < float(am.ambience_weights(8.0)["amb_traffic"]) * 0.5,
			"v noci skoro žádný provoz, ráno špička")


# ---------------------------------------------------------------- hádky a napětí

func _test_conflicts() -> void:
	section("Hádky slyšet a napětí")
	var am = get_node_or_null("/root/AudioManager")
	if am == null:
		return
	var a := FakeSim.new()
	a.look = {"voice": {"pitch": 0.5, "roughness": 0.8}}
	add_child(a)
	var b := FakeSim.new()
	b.grammar = "f"
	b.position = Vector3(3, 0, 0)
	add_child(b)
	am.register_sim(a)
	am.register_sim(b)
	am.speed_index = 1
	am.step_for_test(30.0)   # odstup od předchozích hlasů
	var v0: int = am.stats["voices"]
	a.social_event.emit(a, false, false)
	b.social_event.emit(b, false, false)
	check(am.stats["voices"] == v0 + 2, "hádka: oba účastníci mají hlas", str(am.stats["voices"] - v0))
	var pa: AudioStreamPlayer3D = null
	for c in a.get_children():
		if c is AudioStreamPlayer3D:
			pa = c
	var pb: AudioStreamPlayer3D = null
	for c in b.get_children():
		if c is AudioStreamPlayer3D:
			pb = c
	check(pa != null and pb != null, "hlas je 3D zvuk u postavy")
	if pa != null and pb != null:
		check(absf(pa.pitch_scale - pow(2.0, 0.2)) < 1e-4, "výška hlasu z voice.pitch (0,5 → %.3f)" % pa.pitch_scale)
		check(absf(pb.pitch_scale - 1.0) < 1e-4, "výchozí hlas bez posunu; rod výšku neurčuje")
		var rough_a := WavLoader.load_wav("res://audio/sfx/vox_argue_rough_a.wav", false)
		var rough_b := WavLoader.load_wav("res://audio/sfx/vox_argue_rough_b.wav", false)
		check(pa.stream == rough_a or pa.stream == rough_b, "chraplavý hlas (roughness 0,8) → chraplavá varianta")
		check(pb.stream != rough_a and pb.stream != rough_b, "běžný hlas → čistá varianta")
		check(pa.attenuation_filter_db < -6.0 and pa.max_distance >= 30.0, "hlas se vzdáleností tlumí „jako přes zeď“")
		check((pa.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "hlas se neopakuje do nekonečna")
	a.social_event.emit(a, false, false)
	check(am.stats["voices"] == v0 + 2, "cooldown: hádka hned znovu nepřidá další hlas")
	am.step_for_test(6.0)
	a.social_event.emit(a, true, false)
	check(am.stats["voices"] == v0 + 2, "příjemný hovor hlas hádky nespustí")
	check(am.active_voices() <= am.MAX_VOICES, "nejvýš %d hlasů najednou" % am.MAX_VOICES)
	am.speed_index = 3
	am.conflict_env = 0.0
	a.social_event.emit(a, false, false)
	check(am.stats["voices"] == v0 + 2 and am.conflict_env > 0.9, "rychlý čas: bez hlasů, napětí ale ano")
	am.speed_index = 1
	# Napětí: náběh, ztlumení hudby, odeznění
	am.conflict_env = 1.0
	for i in 30:
		am.step_for_test(0.1)
	var mus := AudioServer.get_bus_index("Music")
	check(am.tension > 0.5, "napětí po hádce naběhne (%.2f)" % am.tension)
	check(AudioServer.get_bus_volume_db(mus) <= am.MUSIC_BUS_DB - 2.5, "hudba se při napětí ztlumí (%.1f dB)" % AudioServer.get_bus_volume_db(mus))
	for i in 300:
		am.step_for_test(0.5)
	check(am.conflict_env < 0.01 and am.tension < 0.1, "napětí po ~2,5 min odezní (%.3f)" % am.tension)
	check(AudioServer.get_bus_volume_db(mus) > am.MUSIC_BUS_DB - 0.7, "hudba se vrátí na původní hlasitost")
	# Hádka daleko od vybrané postavy napětí nezvedne – bez vybrané postavy je doslech plný,
	# s ní se škáluje vzdáleností (ověřeno přímo výpočtem).
	check(am.CONFLICT_HEAR_DIST > 5.0, "doslech hádky je rozumný (%.0f m)" % am.CONFLICT_HEAR_DIST)
	# Hlasové parametry: neplatná data → výchozí
	var bad := FakeSim.new()
	bad.look = {"voice": "nesmysl"}
	var vp: Dictionary = am.voice_params(bad)
	check(float(vp["pitch"]) == 0.0 and float(vp["roughness"]) == 0.2, "neplatný voice → výchozí hodnoty")
	check(absf(am.voice_pitch_scale({"pitch": 5.0}) - pow(2.0, 0.4)) < 1e-5, "výška hlasu je oříznutá na rozsah")
	bad.free()
	# Bouchnutí dveří
	var s0: int = am.stats["slams"]
	am._play_slam(self, Vector3.ZERO)
	check(am.stats["slams"] == s0 + 1, "bouchnutí dveří se přehraje")
	var gone := Node3D.new()
	gone.free()
	am._play_slam(gone, Vector3.ZERO)
	am._play_slam(null, Vector3.ZERO)
	check(am.stats["slams"] == s0 + 1, "zrušený rodič bouchnutí nespadne ani nepřehraje")
	# Úklid: postavy pryč → hlasy zmizí
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(am.active_voices() == 0, "po odchodu postav nezůstanou viset hlasy")
