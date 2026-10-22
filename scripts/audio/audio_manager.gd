extends Node
## AudioManager (autoload „AudioManager“)
## - sběrnice Music / Ambience / SFX / UI (+ efekty: dozvuk interiéru, kompresor,
##   „tlumená“ hudba při pauze)
## - hudební režisér: skladba podle denní doby, při špatné náladě vybrané postavy
##   melancholie (s hysterezí), plynulé prolínání
## - ambience ve vrstvách: ranní ptačí koncert, ptáci přes den, cvrčci v noci, vítr
## - 3D zvuky objektů (sporák, sprcha, TV, běžecký pás) přes AudioStreamPlayer3D
## - UI zvuky (změna rychlosti, nové přátelství, hádka)
## - psychický stav (PsycheFX → set_psyche_level): při úzkosti se hudba tlumí low-passem
##   a ozývá se tlukot srdce (generovaný za běhu, bez souboru)
## - dospělý tón (běh „zvuk“): ambience bytu (lednice, provoz za oknem, sousedé za zdí),
##   vrstva NAPĚTÍ nad hudbou (stres vybrané postavy + hádka v doslechu, hudba se ztlumí),
##   HÁDKY slyšet: zvýšené hlasy u postav (formantové, nesrozumitelné; výška podle
##   voice.pitch z CharacterData), tlumené vzdáleností jako přes zeď, občas bouchnutí dveří.
##   Vše je jen kosmetika na tomto peeru – žádný vliv na simulaci ani síť.

const WavLoader := preload("res://scripts/audio/wav_loader.gd")
const MUSIC_DIR := "res://audio/music/"
const SFX_DIR := "res://audio/sfx/"
const CROSSFADE := 3.0
const MIN_TRACK_TIME := 12.0
const SILENT_DB := -60.0
const AMBIENCE_IDS := ["amb_dawn", "amb_birds", "amb_crickets", "amb_wind", "amb_fridge", "amb_traffic", "amb_neighbors"]
const MUSIC_BUS_DB := -5.0
## Ztlumení hudby při plném napětí (dB) – napětí hudbu „vytlačí“, nepřekřičí ji.
const TENSION_DUCK_DB := -6.0
## Poločas doznívání napětí po hádce (reálné sekundy).
const CONFLICT_HALF_LIFE := 14.0
## Hádka dál než tohle (m) od vybrané postavy napětí nezvedá.
const CONFLICT_HEAR_DIST := 16.0
const VOICE_COOLDOWN := 5.0
const MAX_VOICES := 3
const SLAM_CHANCE := 0.3

var main: Node = null
var current_track := ""
var melancholy := false
var stats := {"track_changes": 0, "object_starts": 0, "object_stops": 0, "ui": 0, "voices": 0, "slams": 0}
## Úroveň napětí 0..1 (vyhlazená) a její složky – čte test a HUD/debug.
var tension := 0.0
var conflict_env := 0.0
var speed_index := 1

var _clock
var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _track_time := 0.0
var _decide := 0.0
var _amb := {}
var _amb_level := {}
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _obj_sounds := {}   # SmartObject -> {"player": AudioStreamPlayer3D, "count": int}
var _sim_sound := {}    # Sim -> SmartObject, který právě ozvučuje
var _last_ui_time := -10.0
var _music_lowpass_idx := -1
var _psyche_lp_idx := -1
var psyche_level := 0.0
var _heart: AudioStreamPlayer
var _heart_phase := 0.0
var _heart_bpm := 70.0
var _heart_beats := 0
var _tension_player: AudioStreamPlayer
var _voice_last := {}      # Sim -> čas posledního hlasu (s)
var _voices: Array = []    # aktivní AudioStreamPlayer3D hlasů
var _voice_alt := 0
var _last_voice_time := -10.0
var _now := 0.0            # reálný čas AudioManageru (s), krokovatelný v testech
var _arng := RandomNumberGenerator.new()
var _music_bus := -1
var _music_db_set := 1000.0


func _ready() -> void:
	_clock = get_node("/root/GameClock")
	_setup_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_music.append(p)
	for id in AMBIENCE_IDS:
		var s := WavLoader.load_wav(SFX_DIR + id + ".wav", true)
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = s
		p.volume_db = SILENT_DB
		add_child(p)
		if s != null:
			p.play(randf() * 5.0)
		_amb[id] = p
		_amb_level[id] = 0.0
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_ui_pool.append(u)
	_clock.speed_changed.connect(_on_speed_changed)
	_heart = AudioStreamPlayer.new()
	_heart.bus = "SFX"
	_heart.stream = make_heartbeat()
	_heart.volume_db = SILENT_DB
	add_child(_heart)
	_arng.seed = 0x5A17
	_tension_player = AudioStreamPlayer.new()
	_tension_player.bus = "Music"
	_tension_player.stream = WavLoader.load_wav(SFX_DIR + "layer_tension.wav", true)
	_tension_player.volume_db = SILENT_DB
	add_child(_tension_player)
	if _tension_player.stream != null:
		_tension_player.play()


func _setup_buses() -> void:
	var defs := {"Music": MUSIC_BUS_DB, "Ambience": -9.0, "SFX": -3.0, "UI": -6.0}
	for bus_name in defs:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, defs[bus_name])
	# Dozvuk interiéru pro zvuky objektů
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.35
		rv.damping = 0.6
		rv.wet = 0.12
		rv.dry = 1.0
		AudioServer.add_bus_effect(sfx, rv)
	# Tlumení hudby při pauze
	var mus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mus) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		AudioServer.add_bus_effect(mus, lp)
		_music_lowpass_idx = 0
		AudioServer.set_bus_effect_enabled(mus, 0, false)
		# Druhý filtr: „zúžený“ zvuk při úzkosti (řídí set_psyche_level).
		var plp := AudioEffectLowPassFilter.new()
		plp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mus, plp)
		_psyche_lp_idx = 1
	# Jemná komprese celku
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -12.0
		comp.ratio = 3.0
		comp.attack_us = 20.0
		comp.release_ms = 250.0
		AudioServer.add_bus_effect(master, comp)


## Napojí AudioManager na hlavní scénu a postavy (další se registrují při spawnu).
func attach(p_main: Node) -> void:
	main = p_main
	for sim in main.get_sims():
		register_sim(sim)


func register_sim(sim: Node) -> void:
	if not sim.has_signal("action_started") or sim.action_started.is_connected(_on_action_started):
		return
	sim.action_started.connect(_on_action_started)
	sim.action_finished.connect(_on_action_finished)
	if sim.has_signal("social_event"):
		sim.social_event.connect(_on_social_event)


# ---------------------------------------------------------------- hudba

func choose_track() -> String:
	var sim = main.get_selected_sim() if main != null else null
	if sim != null:
		# Hystereze – melancholie začne pod −20, skončí až nad −5.
		var mv: float = sim.get_mood_value()
		var emo: String = sim.get_emotion()
		if melancholy and mv > -5.0 and emo != "smutny":
			melancholy = false
		elif not melancholy and (mv < -20.0 or emo == "smutny"):
			melancholy = true
	if melancholy:
		return "melancholie"
	var h: int = _clock.get_hour()
	if h >= 5 and h < 10:
		return "rano"
	if h >= 10 and h < 17:
		return "den"
	if h >= 17 and h < 22:
		return "vecer"
	return "noc"


func play_music(id: String) -> void:
	var stream := WavLoader.load_wav(MUSIC_DIR + id + ".wav", true)
	if stream == null:
		push_warning("Chybí hudba: " + id + " (spusť tools/build_audio.gd)")
		return
	var old := _music[_active]
	_active = 1 - _active
	var nw := _music[_active]
	nw.stream = stream
	nw.volume_db = SILENT_DB
	nw.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nw, "volume_db", 0.0, CROSSFADE).set_trans(Tween.TRANS_SINE)
	if old.playing:
		tw.tween_property(old, "volume_db", SILENT_DB, CROSSFADE).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(old.stop)
	current_track = id
	_track_time = 0.0
	stats["track_changes"] += 1


## Úroveň úzkosti 0..1 a tep (úderů/min) – volá PsycheFX každý snímek.
func set_psyche_level(level: float, bpm: float) -> void:
	psyche_level = clampf(level, 0.0, 1.0)
	_heart_bpm = clampf(bpm, 40.0, 180.0)
	var mus := AudioServer.get_bus_index("Music")
	if _psyche_lp_idx >= 0 and mus >= 0:
		var lp := AudioServer.get_bus_effect(mus, _psyche_lp_idx) as AudioEffectLowPassFilter
		if lp != null:
			lp.cutoff_hz = lerpf(20000.0, 650.0, pow(psyche_level, 0.7))


## Krátký „lub-dub“ (22 050 Hz, 16 bit) – nízké tlumené údery s poklesem výšky.
static func make_heartbeat() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for hit in [[0.0, 1.0], [0.17, 0.6]]:
			var dt: float = t - float(hit[0])
			if dt >= 0.0:
				var f := 38.0 + 30.0 * exp(-dt * 30.0)
				v += float(hit[1]) * sin(TAU * f * dt) * exp(-dt * 18.0) * (1.0 - exp(-dt * 400.0))
		data.encode_s16(i * 2, int(clampf(v * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _update_heart(delta: float) -> void:
	if psyche_level < 0.05:
		_heart_phase = 0.0
		return
	_heart_phase += delta * _heart_bpm / 60.0
	if _heart_phase >= 1.0:
		_heart_phase = fmod(_heart_phase, 1.0)
		_heart.volume_db = linear_to_db(clampf(psyche_level * 0.9, 0.001, 1.0))
		_heart.play()
		_heart_beats += 1


func heartbeats() -> int:
	return _heart_beats


func _process(delta: float) -> void:
	_now += delta
	_update_heart(delta)
	_update_tension(delta)
	_track_time += delta
	_decide -= delta
	if _decide <= 0.0:
		_decide = 1.0
		var t := choose_track()
		if t != current_track and (current_track == "" or _track_time > MIN_TRACK_TIME):
			play_music(t)
	_update_ambience(delta)


# ---------------------------------------------------------------- ambience

## Váhy vrstev ambience podle hodiny (0–24, plynulé).
func ambience_weights(hours: float) -> Dictionary:
	var dawn := exp(-pow((hours - 6.3) / 1.3, 2.0))
	var day := smoothstep(6.5, 8.5, hours) * (1.0 - smoothstep(18.5, 20.5, hours))
	var night := 1.0 - smoothstep(4.5, 6.5, hours) + smoothstep(19.5, 21.5, hours)
	var n := clampf(night, 0.0, 1.0)
	# Večer u sousedů (18–24 h) a pak ještě pozdě v noci slaběji.
	var evening := smoothstep(17.5, 19.5, hours) * (1.0 - smoothstep(23.5, 24.0, hours)) \
			+ 0.35 * (1.0 - smoothstep(0.5, 2.0, hours))
	# Provoz: ranní a odpolední špička, v noci skoro nic.
	var rush := 0.5 * exp(-pow((hours - 7.8) / 1.4, 2.0)) + 0.4 * exp(-pow((hours - 17.0) / 1.8, 2.0))
	return {
		# Ptáci už nejsou koberec přes celý den – jen krátké ranní okno a zbytky přes den.
		"amb_dawn": dawn * 0.45,
		"amb_birds": day * 0.22,
		"amb_crickets": n * 0.45,
		"amb_wind": 0.18 + 0.2 * n,
		# Byt nikdy není úplně ticho.
		"amb_fridge": 0.3 + 0.12 * n,
		"amb_traffic": clampf(0.12 + 0.35 * day + rush, 0.0, 0.85) * (1.0 - 0.6 * n),
		"amb_neighbors": clampf(evening, 0.0, 1.0) * 0.4,
	}


func _update_ambience(delta: float) -> void:
	var w := ambience_weights(_clock.day_fraction() * 24.0)
	for id in _amb:
		var target: float = w.get(id, 0.0)
		_amb_level[id] = move_toward(_amb_level[id], target, delta * 0.25)
		var p: AudioStreamPlayer = _amb[id]
		p.volume_db = linear_to_db(maxf(_amb_level[id], 0.001))


# ---------------------------------------------------------------- objekty

func _on_action_started(sim: Node3D, action: Dictionary) -> void:
	var snd: String = action.get("sound", "")
	var obj = sim.target
	if snd == "" or obj == null or not is_instance_valid(obj) or not obj.has_method("reserve"):
		return
	_sim_sound[sim] = obj
	if _obj_sounds.has(obj):
		_obj_sounds[obj]["count"] += 1
		return
	var stream := WavLoader.load_wav(SFX_DIR + snd + ".wav", true)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = 3.0
	p.max_distance = 30.0
	p.position = Vector3(0, 1.0, 0)
	p.volume_db = -30.0
	obj.add_child(p)
	p.play(randf() * 2.0)
	create_tween().tween_property(p, "volume_db", 0.0, 0.4)
	_obj_sounds[obj] = {"player": p, "count": 1}
	stats["object_starts"] += 1


func _on_action_finished(sim: Node3D, _id: String, _interrupted: bool) -> void:
	if not _sim_sound.has(sim):
		return
	var obj = _sim_sound[sim]
	_sim_sound.erase(sim)
	if not _obj_sounds.has(obj):
		return
	_obj_sounds[obj]["count"] -= 1
	if _obj_sounds[obj]["count"] > 0:
		return
	var p: AudioStreamPlayer3D = _obj_sounds[obj]["player"]
	_obj_sounds.erase(obj)
	stats["object_stops"] += 1
	if is_inside_tree() and p.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -40.0, 0.5)
		tw.tween_callback(p.queue_free)
	else:
		p.queue_free()


func active_object_sounds() -> int:
	return _obj_sounds.size()


# ---------------------------------------------------------------- UI

func play_ui(id: String, volume_db := 0.0) -> void:
	var s := WavLoader.load_wav(SFX_DIR + id + ".wav", false)
	if s == null:
		return
	var p := _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.play()
	stats["ui"] += 1


func _on_speed_changed(index: int) -> void:
	speed_index = index
	play_ui("ui_click")
	var mus := AudioServer.get_bus_index("Music")
	if _music_lowpass_idx >= 0:
		AudioServer.set_bus_effect_enabled(mus, _music_lowpass_idx, index == 0)


func _on_social_event(sim: Node3D, positive: bool, milestone: bool) -> void:
	if not positive:
		_on_conflict(sim)
	# Jen pro vybraného Sima a ne příliš často (při zrychleném čase by to rušilo).
	if main == null or sim != main.get_selected_sim():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_ui_time < 2.0:
		return
	if positive and milestone:
		play_ui("ui_chime")
		_last_ui_time = now
	elif not positive:
		play_ui("ui_conflict", -4.0)
		_last_ui_time = now


# ---------------------------------------------------------------- hádky a napětí

## Hádka/urážka: hlas postavy (zvýšený, nesrozumitelný) jako 3D zvuk u ní, napětí podle
## vzdálenosti od vybrané postavy, občas bouchnutí dveří. Volá se pro každého účastníka.
func _on_conflict(sim: Node3D) -> void:
	if sim == null or not is_instance_valid(sim) or not sim.is_inside_tree():
		return
	var sel = main.get_selected_sim() if main != null else null
	var hear := 1.0
	if sel != null and is_instance_valid(sel) and sel != sim and sel is Node3D:
		var d: float = (sel as Node3D).global_position.distance_to(sim.global_position)
		hear = clampf(1.0 - d / CONFLICT_HEAR_DIST, 0.0, 1.0)
	conflict_env = maxf(conflict_env, hear)
	# Při rychlém čase hlasy vynecháme (byla by to kakofonie), napětí zůstává.
	if speed_index >= 3:
		return
	if _now - float(_voice_last.get(sim, -100.0)) < VOICE_COOLDOWN:
		return
	if active_voices() >= MAX_VOICES:
		return
	var voice := voice_params(sim)
	var rough := float(voice.get("roughness", 0.2)) > 0.45
	var id := "vox_argue_%s%s" % ["rough_" if rough else "", "a" if _voice_alt % 2 == 0 else "b"]
	_voice_alt += 1
	var stream := WavLoader.load_wav(SFX_DIR + id + ".wav", false)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = 4.0
	p.max_distance = 40.0
	# „Přes zeď“: s rostoucí vzdáleností se hlas zakulatí a ztratí srozumitelnost.
	p.attenuation_filter_cutoff_hz = 1800.0
	p.attenuation_filter_db = -16.0
	p.pitch_scale = voice_pitch_scale(voice)
	p.position = Vector3(0, 1.6, 0)
	p.volume_db = -2.0
	sim.add_child(p)
	# Druhý účastník skočí do řeči až chvíli po prvním.
	var delay := 0.0
	if _now - _last_voice_time < 1.0:
		delay = _arng.randf_range(0.35, 0.9)
	_last_voice_time = _now
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_play_if_alive.bind(p))
	else:
		p.play()
	p.finished.connect(p.queue_free)
	_voices.append(p)
	# odpojené postavy (odchod hráče) ze slovníku cooldownů vyhodíme
	if _voice_last.size() > 32:
		for k in _voice_last.keys():
			if not is_instance_valid(k):
				_voice_last.erase(k)
	_voice_last[sim] = _now
	stats["voices"] += 1
	if _arng.randf() < SLAM_CHANCE and is_inside_tree():
		var where := sim.global_position
		var parent := sim.get_parent()
		get_tree().create_timer(_arng.randf_range(3.5, 6.0)).timeout.connect(_play_slam.bind(parent, where))


func _play_if_alive(p) -> void:
	if is_instance_valid(p) and p.is_inside_tree():
		p.play()


func _play_slam(parent, where: Vector3) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var s := WavLoader.load_wav(SFX_DIR + "hit_door_slam.wav", false)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 5.0
	p.max_distance = 45.0
	p.attenuation_filter_cutoff_hz = 2500.0
	p.attenuation_filter_db = -12.0
	parent.add_child(p)
	p.global_position = where + Vector3(_arng.randf_range(-2.0, 2.0), 1.0, _arng.randf_range(-2.0, 2.0))
	p.pitch_scale = _arng.randf_range(0.9, 1.08)
	p.play()
	p.finished.connect(p.queue_free)
	stats["slams"] += 1


## Hlasové parametry postavy z veřejného snapshotu (CharacterData.voice), s výchozími hodnotami.
static func voice_params(sim: Object) -> Dictionary:
	var out := {"pitch": 0.0, "timbre": 0.0, "roughness": 0.2}
	var look = sim.get("look") if sim != null else null
	if look is Dictionary and look.get("voice") is Dictionary:
		var v: Dictionary = look["voice"]
		for k in out:
			if v.has(k) and (v[k] is float or v[k] is int):
				out[k] = float(v[k])
	return out


## Výška hlasu: voice.pitch −1..1 → ±~5 půltónů (pitch_scale 0,76…1,32). Žádná vazba na rod.
static func voice_pitch_scale(voice: Dictionary) -> float:
	return pow(2.0, clampf(float(voice.get("pitch", 0.0)), -1.0, 1.0) * 0.4)


## Napětí 0..1: stres vybrané postavy (od 45, plně kolem 90), hádka v doslechu, úzkost.
func tension_target() -> float:
	var stress_t := 0.0
	var sel = main.get_selected_sim() if main != null else null
	if sel != null and is_instance_valid(sel):
		var m = sel.get("mental")
		if m != null:
			var st = m.get("stress")
			if st is float or st is int:
				stress_t = smoothstep(45.0, 90.0, float(st)) * 0.6
	return clampf(maxf(maxf(stress_t, conflict_env), psyche_level * 0.5), 0.0, 1.0)


func _update_tension(delta: float) -> void:
	conflict_env *= pow(0.5, delta / CONFLICT_HALF_LIFE)
	if conflict_env < 0.002:
		conflict_env = 0.0
	var target := tension_target()
	# nástup rychlejší než odeznění
	var rate := 0.6 if target > tension else 0.12
	tension = move_toward(tension, target, delta * rate)
	if _tension_player != null:
		_tension_player.volume_db = linear_to_db(maxf(tension * 0.85, 0.001))
	# index sběrnice a hlasitost jen při změně (review Gemini: ne každý snímek)
	if _music_bus < 0 or _music_bus >= AudioServer.bus_count or AudioServer.get_bus_name(_music_bus) != "Music":
		_music_bus = AudioServer.get_bus_index("Music")
		_music_db_set = 1000.0
	var db := MUSIC_BUS_DB + TENSION_DUCK_DB * tension
	if _music_bus >= 0 and absf(db - _music_db_set) > 0.05:
		AudioServer.set_bus_volume_db(_music_bus, db)
		_music_db_set = db


## Pro testy: posune vnitřní čas a napětí bez čekání na snímky.
func step_for_test(delta: float) -> void:
	_now += delta
	_update_tension(delta)


func active_voices() -> int:
	_voices = _voices.filter(func(v): return is_instance_valid(v))
	return _voices.size()
