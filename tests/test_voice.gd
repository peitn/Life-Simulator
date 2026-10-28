extends "res://tests/test_base.gd"
## Hlas postavy (CharacterData.voice): syntéza VoiceSynth (fyzikální rozsahy, determinismus,
## odolnost vůči nevalidním datům, měřitelný vliv výšky / barvy / tempa / chraplavosti, šepot,
## nezávislost na identitě a těle, výkon), validace na serveru, náhodný generátor, editor
## hlasu v tvorbě i úpravě postavy (návrh, Zpět/Znovu, ukázka, Použít) a hlasy v rozhovoru
## (AudioManager: vlákno, cache, odstup, doslech, hádka/rychlý čas bez repliky).

const VoiceSynth := preload("res://scripts/audio/voice_synth.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

class FakeSim extends Node3D:
	signal action_started(sim: Node3D, action: Dictionary)
	signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
	signal social_event(sim: Node3D, positive: bool, milestone: bool)
	signal conversation(sim: Node3D, partner: Node3D, info: Dictionary)
	signal crying_changed(sim: Node3D, active: bool)
	var look := {}
	var grammar := "m"
	var target = null
	var mental = null

class FakeMain extends Node:
	var net = null
	var selected: Node3D
	func get_selected_sim():
		return selected
	func get_sims() -> Array:
		return []


func _init() -> void:
	watchdog_seconds = 150.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_params()
	_test_robustness()
	_test_determinism_and_sanity()
	_test_measurable_effects()
	_test_independence()
	_test_performance_and_cache()
	_test_validation_and_randomizer()
	await _test_creator_ui()
	await _test_live_editor_apply()
	await _test_chat_voices()
	finish("test_voice")


# ---------------------------------------------------------------- analýza signálu

static func _rms(b: PackedFloat32Array) -> float:
	var s := 0.0
	for x in b:
		s += x * x
	return sqrt(s / maxf(b.size(), 1))


## Normalizovaná autokorelace (periodicita) a odhad f0 v hlasitých rámcích (medián).
static func _periodicity(b: PackedFloat32Array, sr: int) -> Dictionary:
	var frame := 1024
	var ests: Array = []
	var peaks: Array = []
	var i := 0
	while i + frame < b.size():
		var e := 0.0
		for k in frame:
			e += b[i + k] * b[i + k]
		if e / frame > 0.004:
			var best := 0.0
			var bl := 0
			for lag in range(int(sr / 420.0), int(sr / 65.0)):
				var c := 0.0
				var n0 := 0.0
				var n1 := 0.0
				for k in range(0, frame - lag, 2):
					c += b[i + k] * b[i + k + lag]
					n0 += b[i + k] * b[i + k]
					n1 += b[i + k + lag] * b[i + k + lag]
				var r := c / maxf(sqrt(n0 * n1), 1e-9)
				if r > best:
					best = r
					bl = lag
			peaks.append(best)
			if bl > 0 and best > 0.3:
				ests.append(float(sr) / bl)
		i += frame
	ests.sort()
	peaks.sort()
	return {"f0": ests[ests.size() / 2] if not ests.is_empty() else 0.0,
		"periodicity": peaks[peaks.size() / 2] if not peaks.is_empty() else 0.0}


## Podíl energie první diference (měřítko „jasu“ / vysokých frekvencí).
static func _brightness(b: PackedFloat32Array) -> float:
	var e := 0.0
	var d := 0.0
	for i in range(1, b.size()):
		e += b[i] * b[i]
		var x := b[i] - b[i - 1]
		d += x * x
	return d / maxf(e, 1e-9)


# ---------------------------------------------------------------- testy syntézy

func _test_params() -> void:
	section("VoiceSynth – parametry z CharacterData.voice")
	var lo := VoiceSynth.params({"pitch": -1.0})
	var mid := VoiceSynth.params({})
	var hi := VoiceSynth.params({"pitch": 1.0})
	check(absf(float(mid["f0"]) - 160.0) < 0.01, "výchozí hlas = 160 Hz (střed rozsahu, bez vazby na rod)")
	check(float(lo["f0"]) < 80.0 and float(hi["f0"]) > 320.0, "rozsah výšky pokrývá bas i vysoký hlas", "%.1f–%.1f Hz" % [lo["f0"], hi["f0"]])
	var prev := 0.0
	var mono := true
	for k in 21:
		var f := float(VoiceSynth.params({"pitch": -1.0 + k * 0.1})["f0"])
		mono = mono and f > prev
		prev = f
	check(mono, "výška roste monotónně s posuvníkem")
	check(float(VoiceSynth.params({"timbre": -1.0})["tract"]) < 1.0 and float(VoiceSynth.params({"timbre": 1.0})["tract"]) > 1.0,
		"barva: tmavá = delší trakt (nižší formanty), jasná = kratší")
	check(float(VoiceSynth.params({"tempo": 1.0})["rate"]) > float(VoiceSynth.params({"tempo": -1.0})["rate"]) * 2.0,
		"tempo ±1 mění rychlost řeči víc než 2×")
	check(VoiceSynth.STYLES.size() == 5 and VoiceSynth.STYLE_MODS.size() == 5, "5 stylů řeči (klidně, vesele, naštvaně, smutně, šeptem)")


func _test_robustness() -> void:
	section("VoiceSynth – nevalidní vstupy (data od klienta nejsou důvěryhodná)")
	var garbage: Array = [null, "text", 42, [], {"pitch": NAN}, {"pitch": INF, "timbre": -INF},
		{"pitch": "1", "tempo": [1]}, {"pitch": 99.0, "roughness": -5.0}, {"roughness": NAN}]
	var all_ok := true
	for g in garbage:
		var n := VoiceSynth.normalized(g)
		for k in n:
			all_ok = all_ok and is_finite(float(n[k]))
		all_ok = all_ok and float(n["pitch"]) >= -1.0 and float(n["pitch"]) <= 1.0 and float(n["roughness"]) >= 0.0 and float(n["roughness"]) <= 1.0
	check(all_ok, "normalized(): NaN/∞/text/null/mimo rozsah → konečné hodnoty v rozsahu")
	check(VoiceSynth.normalized({"pitch": 99.0})["pitch"] == 1.0 and VoiceSynth.normalized({"pitch": NAN})["pitch"] == 0.0,
		"mimo rozsah se ořízne, NaN → výchozí")
	var b1 := VoiceSynth.render({"pitch": NAN, "tempo": "x"}, "neexistujici_styl", 3, NAN)
	var b2 := VoiceSynth.render({}, "klidne", 3, 2.2)
	check(b1 == b2, "nesmyslný vstup = výchozí hlas, neznámý styl = klidně, NaN délka = 2,2 s")
	var short := VoiceSynth.render({}, "klidne", 0, 0.01)
	var long := VoiceSynth.render({}, "klidne", 0, 999.0)
	check(short.size() == int(0.3 * VoiceSynth.SR) and long.size() == int(VoiceSynth.MAX_DURATION * VoiceSynth.SR),
		"délka ukázky je omezená (0,3–6 s) – žádná obří alokace", "%d / %d" % [short.size(), long.size()])
	check(VoiceSynth.style_or_default(7) == "klidne" and VoiceSynth.style_or_default("septem") == "septem", "styl se bere jen z povoleného seznamu")


func _test_determinism_and_sanity() -> void:
	section("VoiceSynth – determinismus a zdravý signál")
	var v := {"pitch": 0.3, "timbre": -0.2, "tempo": 0.1, "roughness": 0.4}
	var a := VoiceSynth.to_stream(VoiceSynth.render(v, "nastvane", 5, 1.5)).data
	var b := VoiceSynth.to_stream(VoiceSynth.render(v.duplicate(), "nastvane", 5, 1.5)).data
	check(a == b, "stejný hlas + styl + varianta → bitově shodný zvuk (stejný na všech peerech)")
	check(VoiceSynth.render(v, "nastvane", 6, 1.5) != VoiceSynth.render(v, "nastvane", 5, 1.5), "jiná varianta = jiná „věta“")
	var voices: Array = [{}, {"pitch": -1.0, "timbre": -1.0, "tempo": -1.0, "roughness": 1.0},
		{"pitch": 1.0, "timbre": 1.0, "tempo": 1.0, "roughness": 0.0}]
	var bad: Array = []
	for vv in voices:
		for st in VoiceSynth.STYLES:
			var buf := VoiceSynth.render(vv, st, 2, 1.6)
			var peak := 0.0
			var mean := 0.0
			var finite := true
			for x in buf:
				finite = finite and is_finite(x)
				peak = maxf(peak, absf(x))
				mean += x
			mean /= buf.size()
			var r := _rms(buf)
			if not finite or peak > 1.0 or r < 0.02 or absf(mean) > 0.01:
				bad.append("%s/%s peak=%.2f rms=%.3f dc=%.4f" % [str(vv), st, peak, r, mean])
	check(bad.is_empty(), "15 kombinací hlas×styl: konečné vzorky, špička ≤ 1, ne ticho, bez DC", ", ".join(bad))
	var st := VoiceSynth.to_stream(VoiceSynth.render({}, "klidne", 0, 1.0))
	check(st.format == AudioStreamWAV.FORMAT_16_BITS and not st.stereo and st.loop_mode == AudioStreamWAV.LOOP_DISABLED
		and st.data.size() == int(1.0 * VoiceSynth.SR) * 2, "AudioStreamWAV: 16 bit mono, bez smyčky, správná délka")
	var loud := _rms(VoiceSynth.render({}, "nastvane", 1, 2.0))
	var whisper := _rms(VoiceSynth.render({}, "septem", 1, 2.0))
	var sad := _rms(VoiceSynth.render({}, "smutne", 1, 2.0))
	check(whisper < sad and sad < loud, "šepot < smutně < naštvaně (hlasitost)", "%.3f / %.3f / %.3f" % [whisper, sad, loud])


func _test_measurable_effects() -> void:
	section("VoiceSynth – posuvníky mají slyšitelný (měřitelný) účinek")
	var est: Array = []
	for p in [-1.0, 0.0, 1.0]:
		var buf := VoiceSynth.render({"pitch": p, "roughness": 0.05}, "klidne", 1, 2.2)
		est.append(float(_periodicity(buf, VoiceSynth.SR)["f0"]))
	check(est[0] < est[1] and est[1] < est[2], "naměřená f0 roste s výškou", str(est))
	var ok_f0 := true
	for idx in 3:
		var target := float(VoiceSynth.params({"pitch": [-1.0, 0.0, 1.0][idx]})["f0"])
		ok_f0 = ok_f0 and absf(float(est[idx]) - target) / target < 0.15
	check(ok_f0, "naměřená f0 do 15 % od cíle (intonace kolem základního tónu)")
	var dark := _brightness(VoiceSynth.render({"timbre": -1.0}, "klidne", 2, 2.0))
	var bright := _brightness(VoiceSynth.render({"timbre": 1.0}, "klidne", 2, 2.0))
	check(bright > dark * 1.3, "jasná barva má víc vysokých frekvencí než tmavá", "%.4f vs %.4f" % [bright, dark])
	var slow := 0
	var fast := 0
	for variant in 4:
		slow += (VoiceSynth.plan({"tempo": -1.0}, "klidne", variant, 3.0)["syllables"] as Array).size()
		fast += (VoiceSynth.plan({"tempo": 1.0}, "klidne", variant, 3.0)["syllables"] as Array).size()
	check(float(fast) >= float(slow) * 1.5, "rychlé tempo = víc slabik za stejný čas", "%d vs %d" % [fast, slow])
	var clean := float(_periodicity(VoiceSynth.render({"roughness": 0.0}, "klidne", 3, 2.0), VoiceSynth.SR)["periodicity"])
	var rough := float(_periodicity(VoiceSynth.render({"roughness": 1.0}, "klidne", 3, 2.0), VoiceSynth.SR)["periodicity"])
	check(rough < clean, "chraplavý hlas je méně periodický (jitter, shimmer, subharmonie)", "%.3f vs %.3f" % [rough, clean])
	var whisper := float(_periodicity(VoiceSynth.render({}, "septem", 3, 2.0), VoiceSynth.SR)["periodicity"])
	check(whisper < 0.5 and whisper < clean, "šepot je neznělý (bez periodicity)", "%.3f" % whisper)
	var happy := float(_periodicity(VoiceSynth.render({}, "vesele", 3, 2.2), VoiceSynth.SR)["f0"])
	var sadf := float(_periodicity(VoiceSynth.render({}, "smutne", 3, 2.2), VoiceSynth.SR)["f0"])
	check(happy > sadf, "vesele zní výš než smutně", "%.0f vs %.0f Hz" % [happy, sadf])


func _test_independence() -> void:
	section("Hlas je nezávislý na identitě, těle a jménu")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var a := Randomizer.generate(rng)
	var b := Randomizer.generate(rng)
	b["voice"] = a["voice"].duplicate(true)
	b["identity"]["gender_identity"] = "zena" if a["identity"]["gender_identity"] != "zena" else "muz"
	b["identity"]["grammar"] = "f" if a["identity"]["grammar"] != "f" else "m"
	b["body"]["height_cm"] = 150.0 if float(a["body"]["height_cm"]) > 170.0 else 195.0
	b["body"]["age"] = 80 if int(a["body"]["age"]) < 60 else 20
	check(VoiceSynth.render_for_character(a, "klidne", 1, 1.0) == VoiceSynth.render_for_character(b, "klidne", 1, 1.0),
		"stejný hlas + jiná identita/rod/tělo/věk/jméno → identický zvuk")
	b["voice"]["pitch"] = clampf(float(a["voice"]["pitch"]) + 0.5, -1.0, 1.0) if float(a["voice"]["pitch"]) < 0.4 else float(a["voice"]["pitch"]) - 0.5
	check(VoiceSynth.render_for_character(a, "klidne", 1, 1.0) != VoiceSynth.render_for_character(b, "klidne", 1, 1.0),
		"jiný hlas → jiný zvuk")


func _test_performance_and_cache() -> void:
	section("Výkon a cache")
	var t0 := Time.get_ticks_usec()
	VoiceSynth.render({"pitch": 0.4}, "vesele", 9, 2.2)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 250.0, "ukázka 2,2 s se syntetizuje do 250 ms", "%.1f ms" % ms)
	t0 = Time.get_ticks_usec()
	VoiceSynth.render({"pitch": 0.4}, "klidne", 9, 1.3, 16000)
	var chat_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(chat_ms < 120.0, "replika v rozhovoru (1,3 s, 16 kHz) do 120 ms – a běží ve vlákně", "%.1f ms" % chat_ms)
	check(VoiceSynth.cache_key({"pitch": 0.301}, "klidne", 0, 2.2) == VoiceSynth.cache_key({"pitch": 0.299}, "klidne", 0, 2.2),
		"drobná změna posuvníku (< 0,01) použije cache")
	check(VoiceSynth.cache_key({"pitch": 0.30}, "klidne", 0, 2.2) != VoiceSynth.cache_key({"pitch": 0.36}, "klidne", 0, 2.2),
		"slyšitelná změna vytvoří nový klíč")
	var q := VoiceSynth.quantized({"pitch": 0.333, "roughness": 0.777})
	check(is_equal_approx(float(q["pitch"]), 0.34) and is_equal_approx(float(q["roughness"]), 0.78), "kvantizace na krok 0,02 odpovídá klíči")


func _test_validation_and_randomizer() -> void:
	section("Server validuje hlas; generátor má rozumné rozložení")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var base := Randomizer.generate(rng)
	check(Validator.validate(base, {"mode": "strict", "mental_health": "full"})["ok"], "náhodná postava projde přísnou validací")
	var rejected := 0
	var cases: Array = [["pitch", 1.5], ["pitch", NAN], ["timbre", -1.01], ["tempo", "rychle"], ["roughness", 1.2], ["roughness", -0.1], ["pitch", INF], ["pitch", null]]
	for c in cases:
		var d: Dictionary = base.duplicate(true)
		d["voice"][c[0]] = c[1]
		if not Validator.validate(d, {"mode": "strict", "mental_health": "full"})["ok"]:
			rejected += 1
	check(rejected == cases.size(), "strict validátor odmítne všech %d nevalidních hodnot hlasu" % cases.size(), "%d/%d" % [rejected, cases.size()])
	var extra: Dictionary = base.duplicate(true)
	extra["voice"]["formant_hack"] = 3.0
	var ex := Validator.validate(extra, {"mode": "strict", "mental_health": "full"})
	check(not ex["ok"] or not (ex["data"]["voice"] as Dictionary).has("formant_hack"), "neznámé pole hlasu se nepropustí")
	var rep := Validator.repaired((func() -> Dictionary:
		var d: Dictionary = base.duplicate(true)
		d["voice"]["pitch"] = 7.0
		return d).call())
	check(float(rep["voice"]["pitch"]) == 1.0, "import (repair) ořízne výšku do rozsahu")
	# Rozložení generátoru: v mezích, kolem středu, NEZÁVISLÉ na genderové identitě.
	var by_gender := {}
	var inside := true
	var all_pitch: Array = []
	for i in 400:
		var d := Randomizer.generate(rng)
		var v: Dictionary = d["voice"]
		for k in ["pitch", "timbre", "tempo"]:
			inside = inside and float(v[k]) >= -1.0 and float(v[k]) <= 1.0
		inside = inside and float(v["roughness"]) >= 0.0 and float(v["roughness"]) <= 1.0
		var g := String(d["identity"]["gender_identity"])
		if not by_gender.has(g):
			by_gender[g] = []
		by_gender[g].append(float(v["pitch"]))
		all_pitch.append(float(v["pitch"]))
	check(inside, "400 náhodných hlasů je v rozsazích schématu")
	var mean := 0.0
	for p in all_pitch:
		mean += p
	mean /= all_pitch.size()
	var spread := 0.0
	for p in all_pitch:
		spread += (p - mean) * (p - mean)
	spread = sqrt(spread / all_pitch.size())
	check(absf(mean) < 0.08 and spread > 0.25 and spread < 0.6, "výška: střed ≈ 0, rozumný rozptyl (ne chaos, ne klony)", "μ=%.3f σ=%.3f" % [mean, spread])
	var m_mean := 0.0
	var f_mean := 0.0
	for p in by_gender.get("muz", [0.0]):
		m_mean += p
	m_mean /= maxf(by_gender.get("muz", [0.0]).size(), 1)
	for p in by_gender.get("zena", [0.0]):
		f_mean += p
	f_mean /= maxf(by_gender.get("zena", [0.0]).size(), 1)
	check(absf(m_mean - f_mean) < 0.15, "generátor nesvazuje výšku hlasu s genderovou identitou", "muž %.3f / žena %.3f" % [m_mean, f_mean])
	check(Schema.is_public("voice", "pitch") and Schema.is_public("voice", "roughness"), "hlas je veřejná (vzhledová) část snapshotu")
	var cd := CharacterData.new()
	cd.set_from_dict(base)
	var snap := cd.public_snapshot()
	check(snap.has("voice") and snap["voice"] == VoiceSynth.normalized(base["voice"]),
		"veřejný snapshot nese hlas v kanonické přesnosti 0,001 (stejně jako VoiceSynth)")
	check(VoiceSynth.render(base["voice"], "klidne", 2, 1.0) == VoiceSynth.render(snap["voice"], "klidne", 2, 1.0),
		"vlastník (nezaokrouhlený návrh) i ostatní hráči (snapshot) slyší bitově stejný hlas")
	check(not snap.has("mind") and not snap.has("story"), "snapshot s hlasem nenese soukromé části")


# ---------------------------------------------------------------- UI

var world: Node

func _make_world() -> void:
	get_node("/root/GameClock").running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	Assets.enabled = false
	world = Main.new()
	world.net_config = {"mode": "offline", "hud": true, "camera": false, "visuals": false,
		"audio": false, "autosave": false, "autoload": false}
	add_child(world)
	await get_tree().process_frame


func _test_creator_ui() -> void:
	section("Tvorba postavy: editor hlasu (návrh → Zpět/Znovu → ukázka → Vytvořit)")
	await _make_world()
	var hud = world.hud
	hud._create_button.pressed.emit()
	var creator = hud._character_creator
	check(creator != null and is_instance_valid(creator), "tvorba postavy se otevře")
	if creator == null:
		return
	var ve = creator._voice
	check(ve != null and ve.is_inside_tree(), "sekce Hlas je součástí tvorby postavy")
	if ve == null:
		return
	ve.auto_preview = false
	var sliders: Array = ve.find_children("VoiceSlider_*", "HSlider", true, false)
	check(sliders.size() == 4, "4 posuvníky hlasu (výška, barva, tempo, chraplavost)")
	var narrow := true
	var focus := true
	for s in sliders:
		narrow = narrow and (s as HSlider).custom_minimum_size.x <= 140.0
		focus = focus and (s as HSlider).focus_mode == Control.FOCUS_ALL
	check(narrow and focus, "posuvníky se vejdou na úzkou obrazovku a jdou ovládat klávesnicí/gamepadem")
	check(ve.style_button().item_count == 5, "výběr stylu ukázky má 5 stylů")
	var session = creator._session
	var living: int = world.sims.size()
	ve.slider("pitch").value = -0.62
	check(is_equal_approx(float(session.draft()["voice"]["pitch"]), -0.62), "posuvník výšky mění návrh postavy")
	ve.slider("pitch").value = -0.64
	ve.slider("timbre").value = 0.45
	check(is_equal_approx(float(session.draft()["voice"]["timbre"]), 0.45) and is_equal_approx(float(session.draft()["voice"]["pitch"]), -0.64),
		"barva i výška v návrhu")
	creator._on_undo()
	check(is_equal_approx(float(session.draft()["voice"]["timbre"]), 0.0) and is_equal_approx(float(session.draft()["voice"]["pitch"]), -0.64),
		"Zpět vrátí poslední posuvník (rychlé tažení výšky = jeden krok)")
	check(is_equal_approx(ve.slider("timbre").value, 0.0), "Zpět aktualizuje i posuvník")
	creator._on_undo()
	check(is_equal_approx(float(session.draft()["voice"]["pitch"]), 0.0), "druhé Zpět vrátí celé tažení výšky")
	creator._on_redo()
	creator._on_redo()
	check(is_equal_approx(float(session.draft()["voice"]["timbre"]), 0.45), "Znovu obnoví změny")
	var st1: AudioStreamWAV = ve.preview_stream()
	var renders: int = ve.renders
	var st2: AudioStreamWAV = ve.preview_stream()
	check(st1 != null and st1 == st2 and ve.renders == renders, "ukázka se syntetizuje jednou a pak jde z cache")
	check(ve.last_render_ms < 250.0, "ukázka hlasu do 250 ms", "%.1f ms" % ve.last_render_ms)
	var expected := VoiceSynth.to_stream(VoiceSynth.render(VoiceSynth.quantized(session.draft()["voice"]), "klidne", 0, ve.PREVIEW_SECONDS)).data
	check(st1.data == expected, "ukázka = přesně hlas z návrhu (stejná syntéza jako ve hře)")
	ve.play_preview()
	check(ve.plays >= 1, "tlačítko Přehrát spustí ukázku (z cache okamžitě)")
	ve.style_button().select(1)
	var plays0: int = ve.plays
	var r0: int = ve.renders
	var t_ui := Time.get_ticks_usec()
	ve.play_preview()
	var ui_ms := float(Time.get_ticks_usec() - t_ui) / 1000.0
	check(ve.is_rendering() and ve.plays == plays0, "nová ukázka se syntetizuje na pozadí (UI nečeká)")
	check(ui_ms < 20.0, "kliknutí na Přehrát neblokuje hlavní vlákno", "%.1f ms" % ui_ms)
	var played: bool = await wait_until(func() -> bool: return ve.plays > plays0, 5.0)
	check(played and not ve.is_rendering() and ve.renders == r0 + 1, "po dokončení se ukázka přehraje a uloží do cache")
	ve.style_button().select(4)
	check(ve.current_style() == "septem" and ve.preview_stream() != st1, "jiný styl = jiná ukázka")
	ve.set_editable(false)
	ve.slider("tempo").value = 0.9
	check(is_equal_approx(float(session.draft()["voice"]["tempo"]), 0.0), "zamčený editor hlasu nemění návrh")
	ve.set_editable(true)
	check(world.sims.size() == living, "posuvníky hlasu nikoho nevytvoří ani nezmění živou postavu")
	var draft: Dictionary = session.draft()
	creator._first.text = "Hlasová"
	creator._on_name_changed("Hlasová", "first_name")
	var voice_before: Dictionary = session.draft()["voice"].duplicate()
	var preview_secs: float = ve.PREVIEW_SECONDS
	creator._on_create()
	await get_tree().process_frame
	check(world.sims.size() == living + 1, "Vytvořit a hrát přidá postavu")
	var spawned = world.get_selected_sim()
	check(spawned != null and spawned.look.get("voice", {}) == VoiceSynth.normalized(voice_before), "nová postava má ve veřejném vzhledu přesně zvolený hlas")
	if spawned != null:
		var in_game := VoiceSynth.render(VoiceSynth.quantized(spawned.look["voice"]), "klidne", 0, preview_secs)
		check(VoiceSynth.to_stream(in_game).data == expected, "ukázka v editoru = hlas postavy ve hře")
	check(draft["voice"]["timbre"] == voice_before["timbre"], "hlas se po cestě nezměnil")


func _test_live_editor_apply() -> void:
	section("Úprava postavy: hlas přes Použít (autorita validuje a commitne)")
	var hud = world.hud
	var target = world.get_selected_sim()
	var key := String(target.name)
	var before: Dictionary = world.read_character_edit(key)
	hud._edit_button.pressed.emit()
	var editor = hud._character_editor
	check(editor != null and is_instance_valid(editor), "editor postavy se otevře")
	if editor == null:
		return
	var ve = editor._voice
	check(ve != null, "editor postavy má sekci Hlas")
	if ve == null:
		return
	ve.auto_preview = false
	check(is_equal_approx(ve.slider("pitch").value, float(before["data"]["voice"]["pitch"])), "posuvník ukazuje uložený hlas")
	ve.slider("roughness").value = 0.83
	check(world.read_character_edit(key)["data"] == before["data"], "před Použít se živá postava nemění")
	editor._on_apply()
	var after: Dictionary = world.read_character_edit(key)
	check(int(after["revision"]) == int(before["revision"]) + 1 and is_equal_approx(float(after["data"]["voice"]["roughness"]), 0.83),
		"Použít uloží hlas jako novou revizi")
	check(is_equal_approx(float(target.look["voice"]["roughness"]), 0.83), "živá postava mluví novým hlasem (veřejný vzhled)")
	var others_same := true
	for g in ["identity", "body", "face", "personality", "mind"]:
		others_same = others_same and after["data"][g] == before["data"][g]
	check(others_same, "změna hlasu nesahá na identitu, tělo, obličej ani psychiku")
	editor._on_cancel()
	await get_tree().process_frame


func _test_chat_voices() -> void:
	section("Hlasy v běžném rozhovoru (AudioManager)")
	var am = get_node("/root/AudioManager")
	# Wordless conversation lines belong to the "Beze slov" voice mode (TTS is tested in test_tts).
	var gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.set_value("character_voices", "wordless", false)
	var fm := FakeMain.new()
	add_child(fm)
	var old_main = am.main
	am.main = fm
	am.speed_index = 1
	var a := FakeSim.new()
	var b := FakeSim.new()
	var far := FakeSim.new()
	a.look = {"voice": {"pitch": -0.7, "timbre": -0.4, "tempo": 0.0, "roughness": 0.6}}
	b.look = {"voice": {"pitch": 0.6, "timbre": 0.5, "tempo": 0.3, "roughness": 0.1}}
	far.look = {"voice": {"pitch": 0.0}}
	add_child(a)
	add_child(b)
	add_child(far)
	b.position = Vector3(1.5, 0, 0)
	far.position = Vector3(40, 0, 0)
	fm.selected = a
	for s in [a, b, far]:
		am.register_sim(s)
	check(a.conversation.is_connected(am._on_conversation), "AudioManager poslouchá rozhovory postav")
	check(a.crying_changed.is_connected(am._on_crying_changed), "Crying signal connected to local audio")
	am.step_for_test(30.0)
	var s0: Dictionary = am.stats.duplicate()
	a.conversation.emit(a, b, {"success": true, "argued": false, "avg_mood": 40.0})
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_renders"]) - int(s0["chat_renders"]) == 2, "obě postavy dostanou repliku (syntéza ve vlákně)")
	check(int(am.stats["chat_voices"]) - int(s0["chat_voices"]) == 2, "repliky se přehrají jako 3D zvuk u postav")
	var pa: AudioStreamPlayer3D = a.get_node_or_null("ChatVoice")
	var pb: AudioStreamPlayer3D = b.get_node_or_null("ChatVoice")
	check(pa != null and pb != null and pa.stream != pb.stream, "každá postava má vlastní hlas")
	if pa != null:
		var expect := VoiceSynth.to_stream(VoiceSynth.render(VoiceSynth.quantized(a.look["voice"]), "vesele", 0, am.CHAT_VOICE_SECONDS, am.CHAT_VOICE_SR)).data
		check((pa.stream as AudioStreamWAV).data == expect, "replika = hlas z veřejného snapshotu, styl vesele při dobré náladě")
		check(pa.max_distance >= 20.0 and pa.attenuation_filter_db < 0.0, "replika slábne se vzdáleností")
	var s1: Dictionary = am.stats.duplicate()
	a.conversation.emit(a, b, {"success": true, "argued": false, "avg_mood": 0.0})
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_voices"]) == int(s1["chat_voices"]), "odstup: hned další rozhovor nepřidá repliku")
	am.step_for_test(am.CHAT_VOICE_COOLDOWN + 1.0)
	a.conversation.emit(a, b, {"success": true, "argued": true, "avg_mood": -60.0})
	b.conversation.emit(b, a, {"success": false, "argued": false, "avg_mood": 0.0})
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_voices"]) == int(s1["chat_voices"]), "hádka ani nepovedený rozhovor nespustí běžnou repliku (hádka má vlastní hlasy)")
	am.speed_index = 3
	a.conversation.emit(a, b, {"success": true, "argued": false, "avg_mood": 0.0})
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_voices"]) == int(s1["chat_voices"]), "rychlý čas: bez replik")
	am.speed_index = 1
	var s2: Dictionary = am.stats.duplicate()
	far.conversation.emit(far, a, {"success": true, "argued": false, "avg_mood": 0.0})
	am.flush_chat_jobs_for_test()
	check(far.get_node_or_null("ChatVoice") == null, "postava mimo doslech vybrané postavy nemluví (šetří výkon)")
	check(int(am.stats["chat_voices"]) - int(s2["chat_voices"]) <= 1, "v doslechu mluví jen blízká postava")
	check(am.chat_style(40.0) == "vesele" and am.chat_style(-40.0) == "smutne" and am.chat_style(0.0) == "klidne" and am.chat_style(NAN) == "klidne",
		"styl repliky podle nálady rozhovoru (NaN → klidně)")
	check(am.chat_cache_size() <= am.CHAT_CACHE_MAX, "cache replik je omezená")
	# A previous dialog has filled the bounded three-voice pool.
	# Drain it before independently testing crying onset.
	for player in am._voices:
		if is_instance_valid(player):
			player.queue_free()
	await get_tree().process_frame
	check(am.active_voices() == 0, "previous conversation voices drained before cry test")
	section("Smutek a hlas: jednání na začátku pláče")
	am.step_for_test(40.0)
	var cried_before: int = int(am.stats["cry_voices"])
	a.crying_changed.emit(a, false)
	check(int(am.stats["cry_voices"]) == cried_before, "cry stop is silent")
	a.crying_changed.emit(a, true)
	am.flush_chat_jobs_for_test()
	check(int(am.stats["cry_voices"]) == cried_before + 1, "cry start produces a sad voice cue")
	check(am.chat_cache_size() <= am.CHAT_CACHE_MAX, "cry cue uses bounded voice synth cache")
	a.crying_changed.emit(a, true)
	check(int(am.stats["cry_voices"]) == cried_before + 1, "cry onset has a cooldown")
	am.step_for_test(am.CRY_VOICE_COOLDOWN + 1.0)
	am.speed_index = 3
	a.crying_changed.emit(a, true)
	check(int(am.stats["cry_voices"]) == cried_before + 1, "high speed suppresses emotional voice")
	am.speed_index = 1
	far.crying_changed.emit(far, true)
	check(int(am.stats["cry_voices"]) == cried_before + 1, "cry beyond hearing range is muted")
	am.main = world
	var saved_mode = world.net.mode
	world.net.mode = world.net.Mode.HOST
	a.crying_changed.emit(a, true)
	check(int(am.stats["cry_voices"]) == cried_before + 1, "network host does not expose private emotion via audio")
	world.net.mode = saved_mode
	am.main = fm
	section("Delayed crying voice jobs respect speed changes")
	for player in am._voices:
		if is_instance_valid(player):
			player.queue_free()
	await get_tree().process_frame
	am._chat_cache.clear()
	am._chat_order.clear()
	var voices_before: int = int(am.stats["chat_voices"])
	var cues_before: int = int(am.stats["cry_voices"])
	a.crying_changed.emit(a, true)
	check(am._chat_jobs.size() > 0 and bool(am._chat_jobs[-1].get("cry_cue", false)),
		"cry onset schedules an asynchronous marked job")
	am.speed_index = 3
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_voices"]) == voices_before and int(am.stats["cry_voices"]) == cues_before + 1,
		"voice job queued at normal speed is not played after speed-up")
	am.speed_index = 1
	am.step_for_test(am.CRY_VOICE_COOLDOWN + 1.0)
	am._chat_cache.clear()
	am._chat_order.clear()
	var stale_voices_before: int = int(am.stats["chat_voices"])
	a.crying_changed.emit(a, true)
	check(am._chat_jobs.size() > 0, "stale-cue test has an actual queued render")
	am.step_for_test(5.0)
	am.flush_chat_jobs_for_test()
	check(int(am.stats["chat_voices"]) == stale_voices_before,
		"cry voice delayed beyond four real seconds is dropped even at normal speed")



	am.main = old_main
	for s in [a, b, far]:
		s.queue_free()
	fm.queue_free()
	await get_tree().process_frame
