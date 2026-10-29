extends "res://tests/test_base.gd"
## Czech text-to-speech (28 Oct 2026): rule-based G2P, stress, F0 contours (statement, yes/no
## and wh-questions), determinism, voice parameters, signal sanity, durations, odd input,
## threading/cache in AudioManager, the "Hlasy postav" setting, privacy and the editor preview.
## Naturalness rework (29 Oct 2026): no clicks at segment joins, breath noise present, F0 never
## flat inside vowels, bandwidth / spectral tilt sanity, segment levels, timing ranges.

const G2P := preload("res://scripts/audio/czech_g2p.gd")
const TTS := preload("res://scripts/audio/czech_tts.gd")
const VoiceSynth := preload("res://scripts/audio/voice_synth.gd")
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

class FakeSim extends Node3D:
	signal action_started(sim: Node3D, action: Dictionary)
	signal action_finished(sim: Node3D, action_id: String, interrupted: bool)
	signal speech_started(sim: Node3D, text: String)
	var look := {}
	var net_emotion := "spokojeny"
	var grammar := "m"
	var target = null
	func get_mood_value() -> float:
		return 0.0
	func get_emotion() -> String:
		return net_emotion

## Records every property read, to prove the speech path only touches public fields.
class SpySim extends FakeSim:
	var reads: Array = []
	func _get(property: StringName) -> Variant:
		reads.append(String(property))
		return null

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
	_test_g2p()
	_test_numbers_and_odd_input()
	_test_stress()
	_test_contours()
	_test_determinism_and_signal()
	_test_voice_params()
	_test_durations()
	_test_naturalness()
	await _test_audio_manager()
	await _test_editor_preview()
	finish("test_tts")


func _t(text: String) -> String:
	return G2P.transcribe(text)


func _test_g2p() -> void:
	section("G2P: known Czech words")
	var cases := {
		"dědeček": "ďedeček", "chleba": "xleba", "pět": "pjet", "město": "mňesto", "děti": "ďeťi",
		"kůň": "kúň", "řeka": "řeka", "obchod": "opxot", "led": "let", "tři": "tř̊i", "kde": "gde",
		"všechno": "fšexno", "shoda": "sxoda", "banka": "baŋka", "dny": "dni", "nic": "ňic",
		"tělo": "ťelo", "vědět": "vjeďet", "mýdlo": "mídlo", "dům": "dúm", "auto": "auto",
		"pouze": "pouze", "neumím": "neumím", "led byl": "led bil", "v lese": "vlese", "v pokoji": "fpokoji",
		"hrad": "hrat", "kniha": "kňiha", "džus": "džus", "Ř": "ř̊"}
	var bad: Array = []
	for w in cases:
		if _t(w) != String(cases[w]):
			bad.append("%s→%s (want %s)" % [w, _t(w), cases[w]])
	check(bad.is_empty(), "%d G2P cases incl. ch, ě, di/ti/ni, ů, ř, devoicing, assimilation, proclitics" % cases.size(), ", ".join(bad))
	var ph: Array = G2P.phonemes("led")
	check(ph == ["l", "e", "t"], "phoneme list for led = [l, e, t]", str(ph))
	check(G2P.phonemes("máš").has("á") and G2P.LONG_VOWELS.has("á"), "long vowels are separate phonemes")
	check(G2P.phonemes("dům").has("ú") and G2P.phonemes("auto")[0] == "au", "ů → ú and diphthong au")


func _test_numbers_and_odd_input() -> void:
	section("Numbers, symbols, emoji, odd Unicode, length cap")
	check(G2P.number_words(0) == "nula" and G2P.number_words(7) == "sedm" and G2P.number_words(15) == "patnáct",
		"0, 7, 15")
	check(G2P.number_words(21) == "dvacet jedna" and G2P.number_words(100) == "sto" and G2P.number_words(234) == "dvě stě třicet čtyři",
		"21, 100, 234", G2P.number_words(234))
	check(G2P.number_words(1000) == "tisíc" and G2P.number_words(2026) == "dva tisíce dvacet šest"
		and G2P.number_words(9999) == "devět tisíc devět set devadesát devět", "1000, 2026, 9999", G2P.number_words(2026))
	check(G2P.normalize("Mám 3 kočky!") == "mám tři kočky !", "digits are spelled in text", G2P.normalize("Mám 3 kočky!"))
	check(G2P.normalize("12345").split(" ").size() == 5, "numbers above 9999 are read digit by digit")
	var odd: Array = ["", "   ", "😀😀😀", "a\u202e\u0001b", "e\u030C", "#@$%^&*", "ÄÖÜ ß ñ", "...", "?!?!",
		"x".repeat(500), "1".repeat(300), "\t\n\r", "ﷺ𝔄𝔅", "Ahoj 👋 jak je?"]
	var safe := true
	for s in odd:
		var buf := TTS.render(s, {}, "klidne", 16000)
		var p := TTS.plan(s)
		safe = safe and buf.size() == int(float(p["duration"]) * 16000) and float(p["duration"]) <= TTS.MAX_DURATION
		for x in buf:
			if not is_finite(x):
				safe = false
				break
	check(safe, "%d odd inputs (empty, emoji, controls, NFD, 500 chars, 300 digits) render finite, bounded audio" % odd.size())
	check(G2P.normalize("e\u030Cšte") == "ěšte", "combining caron composes (NFD input)")
	check(G2P.normalize("😀 Ahoj") == "ahoj", "emoji are dropped")
	check(TTS.clean_text("x".repeat(500)).length() == TTS.MAX_CHARS, "text is capped at 200 characters")
	check(TTS.render(null).size() > 0 and TTS.render(42).size() > 0, "non-string input yields the silent minimum, no crash")


func _stressed(text: String) -> Array:
	var out: Array = []
	for ph in G2P.prosody(text):
		for sy in ph["syllables"]:
			out.append(("'" if sy["stress"] else "") + "".join(PackedStringArray(sy["ph"])))
	return out


func _test_stress() -> void:
	section("Fixed first-syllable stress per stress unit")
	check(_stressed("dědeček") == ["'ďe", "de", "ček"], "dědeček: first syllable", str(_stressed("dědeček")))
	check(_stressed("na stole") == ["'na", "sto", "le"], "a monosyllabic preposition takes the stress", str(_stressed("na stole")))
	check(_stressed("Dneska je hezky.") == ["'dnes", "ka", "je", "'hes", "ki"], "enclitic je is unstressed", str(_stressed("Dneska je hezky.")))
	check(_stressed("vlk") == ["'vlk"] and _stressed("krk") == ["'krk"], "syllabic l / r form a nucleus")
	var kinds: Array = []
	for ph in G2P.prosody("Ahoj, jak se máš? Půjdeš ven? To je skvělé! Nevím…"):
		kinds.append(ph["kind"])
	check(kinds == ["continue", "wh", "question", "exclaim", "trail"], "phrase types from punctuation and wh-words", str(kinds))


func _f0(pl: Dictionary, t: float) -> float:
	var f: PackedFloat32Array = pl["f0"]
	return f[clampi(int(t / TTS.F0_STEP), 0, f.size() - 1)]


## F0 at the end of the last nucleus and at the middle syllable's nucleus.
func _ends(text: String, voice := {}, style := "klidne") -> Dictionary:
	var pl := TTS.plan(text, voice, style)
	var sy: Array = pl["syllables"]
	var last: Dictionary = sy[sy.size() - 1]
	var mid: Dictionary = sy[sy.size() / 2]
	var lst: Dictionary = {}
	for s in sy:
		if s["stress"]:
			lst = s
	return {"end": _f0(pl, float(last["nt1"]) - 0.006), "mid": _f0(pl, (float(mid["nt0"]) + float(mid["nt1"])) * 0.5),
		"last_stress": _f0(pl, (float(lst["nt0"]) + float(lst["nt1"])) * 0.5), "start": _f0(pl, float(sy[0]["nt0"]) + 0.01)}


func _test_contours() -> void:
	section("Intonation: declination, statement fall, yes/no rise, wh fall, exclamation")
	var st := _ends("Dneska je hezky.")
	check(st["end"] < st["mid"] * 0.85, "statement: final F0 clearly below the middle", "%.0f vs %.0f Hz" % [st["end"], st["mid"]])
	var yn := _ends("Půjdeš se mnou ven?")
	check(yn["end"] > yn["mid"] * 1.15 and yn["end"] > yn["last_stress"] * 1.2, "yes/no question rises at the end",
		"end %.0f, mid %.0f, last stressed %.0f Hz" % [yn["end"], yn["mid"], yn["last_stress"]])
	var wh := _ends("Kdo to udělal?")
	check(wh["end"] < wh["mid"] and wh["start"] > wh["end"] * 1.3, "wh-question starts high and falls",
		"start %.0f, end %.0f Hz" % [wh["start"], wh["end"]])
	var plain := TTS.plan("To je skvělé.")
	var excl := TTS.plan("To je skvělé!")
	var r_plain: float = _range(plain["f0"])
	var r_excl: float = _range(excl["f0"])
	check(r_excl > r_plain * 1.2, "exclamation has a wider pitch range", "%.2f vs %.2f st" % [r_excl, r_plain])
	var long_pl := TTS.plan("Dneska ráno jsme šli do parku a potom domů na oběd.")
	var sy: Array = long_pl["syllables"]
	check(_f0(long_pl, float(sy[1]["nt0"])) > _f0(long_pl, float(sy[sy.size() - 3]["nt0"])), "F0 declines across the utterance")
	var cont := TTS.plan("Ahoj, jak se máš?")
	var ph0: Dictionary = cont["phrases"][0]
	var ph1: Dictionary = cont["phrases"][1]
	check(float(ph1["t0"]) - float(ph0["t1"]) > 0.1, "comma inserts a pause", "%.2f s" % (float(ph1["t0"]) - float(ph0["t1"])))
	var two := TTS.plan("Ahoj. Jak se máš.")
	check(float(two["phrases"][1]["t0"]) - float(two["phrases"][0]["t1"]) > float(ph1["t0"]) - float(ph0["t1"]),
		"period pause is longer than comma pause")
	var sad := _range(TTS.plan("Dneska je hezky.", {}, "smutne")["f0"])
	var happy := _range(TTS.plan("Dneska je hezky.", {}, "vesele")["f0"])
	check(happy > sad * 1.5, "style scales the intonation range (happy > sad)", "%.2f vs %.2f" % [happy, sad])
	var tired_mean := _mean(TTS.plan("Dneska je hezky.", {}, "unavene")["f0"])
	var calm_mean := _mean(TTS.plan("Dneska je hezky.", {}, "klidne")["f0"])
	check(tired_mean < calm_mean, "tired style lowers mean F0")


func _range(f: PackedFloat32Array) -> float:
	var lo := INF
	var hi := 0.0
	for x in f:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return 12.0 * log(hi / maxf(lo, 1.0)) / log(2.0)


func _mean(f: PackedFloat32Array) -> float:
	var s := 0.0
	for x in f:
		s += x
	return s / maxf(f.size(), 1)


func _rms(b: PackedFloat32Array) -> float:
	var s := 0.0
	for x in b:
		s += x * x
	return sqrt(s / maxf(b.size(), 1))


func _test_determinism_and_signal() -> void:
	section("Determinism, no clipping, not silent")
	var v := {"pitch": 0.2, "timbre": -0.3, "tempo": 0.1, "roughness": 0.4}
	var a := VoiceSynth.speak("Ahoj, jak se máš?", v, "vesele").data
	var b := VoiceSynth.speak("Ahoj, jak se máš?", v.duplicate(), "vesele").data
	check(a == b, "same text + voice + style → identical bytes")
	check(VoiceSynth.speak("Ahoj, jak se máš?", v, "smutne").data != a, "different style → different audio")
	var bad: Array = []
	for st in VoiceSynth.TTS_STYLES:
		for vv in [{}, {"pitch": -1.0, "timbre": -1.0, "tempo": -1.0, "roughness": 1.0}, {"pitch": 1.0, "timbre": 1.0, "tempo": 1.0, "roughness": 0.0}]:
			var buf := VoiceSynth.speak_buffer("To je skvělé! Kdo to udělal?", vv, st)
			var peak := 0.0
			for x in buf:
				peak = maxf(peak, absf(x))
			var r := _rms(buf)
			if peak >= 0.99 or r < 0.02:
				bad.append("%s %s peak=%.2f rms=%.3f" % [st, str(vv), peak, r])
	check(bad.is_empty(), "6 styles × 3 voices: peak < 0.99 (no clipping) and audible RMS", ", ".join(bad))
	var st := VoiceSynth.speak("Dobrý den.", {})
	check(st.format == AudioStreamWAV.FORMAT_16_BITS and not st.stereo and st.mix_rate == TTS.SR, "16-bit mono AudioStreamWAV")


## Median autocorrelation F0 of voiced frames.
func _measure_f0(b: PackedFloat32Array, sr: int) -> float:
	var frame := 1024
	var ests: Array = []
	var i := 0
	while i + frame < b.size():
		var e := 0.0
		for k in frame:
			e += b[i + k] * b[i + k]
		if e / frame > 0.004:
			var best := 0.0
			var bl := 0
			for lag in range(int(sr / 420.0), int(sr / 60.0)):
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
			if bl > 0 and best > 0.4:
				ests.append(float(sr) / bl)
		i += frame
	ests.sort()
	return ests[ests.size() / 2] if not ests.is_empty() else 0.0


func _brightness(b: PackedFloat32Array) -> float:
	var e := 0.0
	var d := 0.0
	for i in range(1, b.size()):
		e += b[i] * b[i]
		d += (b[i] - b[i - 1]) * (b[i] - b[i - 1])
	return d / maxf(e, 1e-9)


func _test_voice_params() -> void:
	section("Voice parameters change F0 and formants measurably; identity never read")
	var lo := _measure_f0(VoiceSynth.speak_buffer("Máma mele maso.", {"pitch": -1.0, "roughness": 0.0}, "klidne"), TTS.SR)
	var mid := _measure_f0(VoiceSynth.speak_buffer("Máma mele maso.", {"pitch": 0.0, "roughness": 0.0}, "klidne"), TTS.SR)
	var hi := _measure_f0(VoiceSynth.speak_buffer("Máma mele maso.", {"pitch": 1.0, "roughness": 0.0}, "klidne"), TTS.SR)
	check(lo < mid and mid < hi and lo < 110.0 and hi > 230.0, "pitch −1/0/+1 → measured F0 rises (≈77–331 Hz base)", "%.0f / %.0f / %.0f Hz" % [lo, mid, hi])
	var dark := _brightness(VoiceSynth.speak_buffer("Máma mele maso.", {"timbre": -1.0}, "klidne"))
	var bright := _brightness(VoiceSynth.speak_buffer("Máma mele maso.", {"timbre": 1.0}, "klidne"))
	check(bright > dark * 1.15, "timbre +1 is brighter (higher formants) than −1", "%.4f vs %.4f" % [bright, dark])
	check(TTS.voice_params({"pitch": 1.0})["tract"] == TTS.voice_params({"pitch": -1.0})["tract"], "pitch does not change the tract")
	var full := {"voice": {"pitch": 0.3}, "identity": {"gender_identity": "zena", "grammar": "f", "first_name": "Eva"}, "body": {"height_cm": 150.0}}
	var other := {"voice": {"pitch": 0.3}, "identity": {"gender_identity": "muz", "grammar": "m", "first_name": "Petr"}, "body": {"height_cm": 199.0}}
	check(VoiceSynth.speak("Ahoj.", full["voice"]).data == VoiceSynth.speak("Ahoj.", other["voice"]).data,
		"same voice group with different gender/grammar/name/body → identical speech")


func _test_durations() -> void:
	section("Durations: text length, tempo, long vowels, phrase-final lengthening")
	var short := float(TTS.plan("Ahoj.")["duration"])
	var long := float(TTS.plan("Ahoj, dneska je opravdu krásný den a já mám hroznou chuť jít ven.")["duration"])
	check(long > short * 3.0, "duration grows with text length", "%.2f vs %.2f s" % [long, short])
	var slow := float(TTS.plan("Dneska je hezky.", {"tempo": -1.0})["duration"])
	var fast := float(TTS.plan("Dneska je hezky.", {"tempo": 1.0})["duration"])
	check(slow > fast * 1.6, "tempo −1 is much slower than +1", "%.2f vs %.2f s" % [slow, fast])
	var pl := TTS.plan("pata páta")
	var segs: Array = pl["segments"]
	var a_short := 0.0
	var a_long := 0.0
	for sgm in segs:
		if sgm["ph"] == "a" and a_short == 0.0:
			a_short = float(sgm["d"])
		if sgm["ph"] == "á":
			a_long = float(sgm["d"])
	check(a_long > a_short * 1.5 and a_long < a_short * 2.0, "long vowel ≈ 1.6–1.8× the short one", "%.3f vs %.3f s" % [a_long, a_short])
	var mid_v := 0.0
	var fin_v := 0.0
	for sgm in TTS.plan("mama mama mama.")["segments"]:
		if sgm["ph"] == "a":
			if mid_v == 0.0:
				mid_v = float(sgm["d"])
			fin_v = float(sgm["d"])
	check(fin_v > mid_v * 1.3, "phrase-final lengthening", "%.3f vs %.3f s" % [fin_v, mid_v])
	var t0 := Time.get_ticks_usec()
	TTS.render("Ahoj, jak se máš? Dneska je hezky a zítra bude pršet.", {}, "klidne", 16000)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 400.0, "a typical bubble line synthesises in < 400 ms (runs in a worker thread in game)", "%.0f ms" % ms)


func _test_audio_manager() -> void:
	section("AudioManager: TTS of speech lines, worker thread, cache, limits, setting, privacy")
	var gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	check(gs.get_value("character_voices") == "wordless", "default voice mode is Beze slov until the reworked TTS voice is approved")
	check(not gs.set_value("character_voices", "robot", false) and gs.set_value("character_voices", "wordless", false), "setting validates its three values")
	gs.set_value("character_voices", "tts", false)
	var am = get_node("/root/AudioManager")
	var fm := FakeMain.new()
	add_child(fm)
	var old_main = am.main
	am.main = fm
	am.speed_index = 1
	var a := FakeSim.new()
	var far := FakeSim.new()
	a.look = {"voice": {"pitch": -0.4, "timbre": 0.2, "tempo": 0.0, "roughness": 0.3}}
	a.net_emotion = "stastny"
	far.look = {"voice": {"pitch": 0.5}}
	add_child(a)
	add_child(far)
	far.position = Vector3(40, 0, 0)
	fm.selected = a
	am.register_sim(a)
	am.register_sim(far)
	check(a.speech_started.is_connected(am._on_speech), "AudioManager listens to public speech lines")
	am.step_for_test(30.0)
	am._chat_cache.clear()
	am._chat_order.clear()
	var s0: Dictionary = am.stats.duplicate()
	a.speech_started.emit(a, "Ahoj, jak se máš?")
	check(am._chat_jobs.size() == 1 and bool(am._chat_jobs[0].get("tts", false)), "line is queued as an asynchronous TTS job")
	am.flush_chat_jobs_for_test()
	check(int(am.stats["tts_renders"]) == int(s0["tts_renders"]) + 1 and a.get_node_or_null("SpeechVoice") != null,
		"rendered in WorkerThreadPool and played as a 3D voice at the speaker")
	var p: AudioStreamPlayer3D = a.get_node_or_null("SpeechVoice")
	if p != null:
		var expect := VoiceSynth.speak("Ahoj, jak se máš?", VoiceSynth.quantized(a.look["voice"]), "vesele", am.CHAT_VOICE_SR).data
		check((p.stream as AudioStreamWAV).data == expect, "played audio = TTS of the public line, public voice, style from displayed emotion")
	a.speech_started.emit(a, "Ještě jedna věta.")
	check(am._chat_jobs.is_empty(), "per-character cooldown")
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	for pl in am._voices:
		if is_instance_valid(pl):
			pl.queue_free()
	await get_tree().process_frame
	var hits0: int = int(am.stats["chat_cache_hits"])
	a.speech_started.emit(a, "Ahoj, jak se máš?")
	check(int(am.stats["chat_cache_hits"]) == hits0 + 1 and am._chat_jobs.is_empty(), "repeated line comes from the LRU cache")
	check(am.chat_cache_size() <= am.CHAT_CACHE_MAX, "cache stays bounded")
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	far.speech_started.emit(far, "Haló!")
	check(far.get_node_or_null("SpeechVoice") == null and am._chat_jobs.is_empty(), "characters beyond hearing distance are not voiced")
	am.speed_index = 3
	a.speech_started.emit(a, "Rychle.")
	check(am._chat_jobs.is_empty(), "no TTS work at speed ≥ 3")
	am.speed_index = 1
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	a.speech_started.emit(a, "Tohle už nestihnu.")
	am.speed_index = 3
	var dropped0: int = int(am.stats["tts_dropped"])
	am.flush_chat_jobs_for_test()
	check(int(am.stats["tts_dropped"]) == dropped0 + 1, "a job queued before a speed-up is dropped, not played late")
	am.speed_index = 1
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	a.speech_started.emit(a, "Stará věta.")
	am.step_for_test(am.TTS_MAX_AGE + 0.5)
	dropped0 = int(am.stats["tts_dropped"])
	am.flush_chat_jobs_for_test()
	check(int(am.stats["tts_dropped"]) == dropped0 + 1, "a stale job (render backlog > 4 s) is dropped")
	for pl in am._voices:
		if is_instance_valid(pl):
			pl.queue_free()
	await get_tree().process_frame
	gs.set_value("character_voices", "off", false)
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	var req0: int = int(am.stats["tts_requests"])
	a.speech_started.emit(a, "Vypnuto.")
	am.flush_chat_jobs_for_test()
	check(int(am.stats["tts_requests"]) == req0 and a.get_node_or_null("SpeechVoice") == null, "setting Vypnuto → no TTS players")
	gs.set_value("character_voices", "wordless", false)
	a.speech_started.emit(a, "Beze slov.")
	check(am._chat_jobs.is_empty(), "Beze slov mode does not speak text")
	gs.set_value("character_voices", "tts", false)
	am.step_for_test(am.TTS_COOLDOWN + 0.5)
	# Privacy: only public fields of the speaker are read on the speech path.
	var spy := SpySim.new()
	add_child(spy)
	spy.look = {"voice": {"pitch": 0.1}}
	fm.selected = spy
	am._on_speech(spy, "Soukromí.")
	am.flush_chat_jobs_for_test()
	var private_reads: Array = spy.reads.filter(func(k: String) -> bool: return k in ["mind", "mental", "story", "emotions", "needs", "self_defectiveness_belief"])
	check(private_reads.is_empty(), "speech path never reads private fields (mind, mental, emotions, needs…)", str(private_reads))
	check(VoiceSynth.tts_style_for_emotion("nastvany") == "nastvane" and VoiceSynth.tts_style_for_emotion(null) == "klidne",
		"style comes only from the displayed emotion")
	for pl in am._voices:
		if is_instance_valid(pl):
			pl.queue_free()
	am.main = old_main
	for n in [a, far, spy, fm]:
		n.queue_free()
	await get_tree().process_frame
	gs.reset()


func _test_editor_preview() -> void:
	section("Character creator: Zkusit větu")
	get_node("/root/GameClock").running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	Assets.enabled = false
	var world := Main.new()
	world.net_config = {"mode": "offline", "hud": true, "camera": false, "visuals": false, "audio": false, "autosave": false, "autoload": false}
	add_child(world)
	await get_tree().process_frame
	world.hud._create_button.pressed.emit()
	var creator = world.hud._character_creator
	var ve = creator._voice if creator != null else null
	check(ve != null and ve.sentence_edit() != null and ve.sentence_text() == ve.SAMPLE_SENTENCE, "voice section has a sentence field with a default sample")
	if ve == null:
		world.queue_free()
		Assets.enabled = true
		return
	ve.auto_preview = false
	var s1: AudioStreamWAV = ve.sentence_stream()
	var expect := VoiceSynth.speak(ve.SAMPLE_SENTENCE, VoiceSynth.quantized(creator._session.draft()["voice"]), ve.current_style(), VoiceSynth.SR).data
	check(s1.data == expect, "preview speaks the sentence with the current draft voice")
	ve.slider("pitch").value = 0.8
	var s2: AudioStreamWAV = ve.sentence_stream()
	check(s2.data != s1.data, "changing the draft voice changes the spoken preview")
	ve.sentence_edit().text = ve.SAMPLE_QUESTION
	var t_ui := Time.get_ticks_usec()
	ve.play_sentence()
	var ui_ms := float(Time.get_ticks_usec() - t_ui) / 1000.0
	check(ve.is_rendering() and ui_ms < 25.0, "a new sentence renders off the main thread", "%.1f ms" % ui_ms)
	var played: bool = await wait_until(func() -> bool: return ve.sentence_plays > 0, 6.0)
	check(played and not ve.is_rendering(), "question variant plays after the worker finishes")
	creator._on_cancel()
	world.queue_free()
	await get_tree().process_frame
	Assets.enabled = true


# ------------------------------------------------------------------ naturalness (v2 synthesis)

const VOWELS := ["a", "e", "i", "o", "u", "á", "é", "í", "ó", "ú", "ou", "au", "eu"]
const STOPS := ["p", "b", "t", "d", "ť", "ď", "k", "g", "c", "č", "dz", "dž"]


## Clicks: per 1 ms frame the energy of the 2nd difference (a broadband transient detector);
## a click is a frame > 10 dB above the 90th percentile of its ±25 ms neighbourhood (so the
## regular glottal pulses of a low voice do not count). Legit plosive releases are excluded.
func _clicks(buf: PackedFloat32Array, sr: int, pl: Dictionary) -> Array:
	var h := sr / 1000
	var nfr := (buf.size() - 2) / h
	var e := PackedFloat32Array()
	var lv := PackedFloat32Array()
	e.resize(nfr)
	lv.resize(nfr)
	for f in nfr:
		var s2 := 0.0
		var s0 := 0.0
		for k in h:
			var i := f * h + k
			var d2 := buf[i + 2] - 2.0 * buf[i + 1] + buf[i]
			s2 += d2 * d2
			s0 += buf[i] * buf[i]
		e[f] = 10.0 * log(s2 / h + 1e-12) / log(10.0)
		lv[f] = 10.0 * log(s0 / h + 1e-12) / log(10.0)
	var excl := PackedByteArray()
	excl.resize(nfr)
	excl.fill(0)
	for sg in pl["segments"]:
		if String(sg["ph"]) in STOPS:
			var r := int((float(sg["t"]) + float(sg["d"]) - 0.013) * 1000.0)
			for f in range(maxi(r - 6, 0), mini(r + 20, nfr)):
				excl[f] = 1
	var hits: Array = []
	for f in nfr:
		if excl[f] == 1 or lv[f] < -50.0:
			continue
		var nb: Array = []
		for g in range(maxi(f - 25, 0), mini(f + 26, nfr)):
			if absi(g - f) > 2:
				nb.append(e[g])
		if nb.size() < 10:
			continue
		nb.sort()
		if e[f] > float(nb[int(nb.size() * 0.9)]) + 10.0:
			hits.append(f)
	return hits


## Harmonics-to-noise ratio (dB) of the middle of a vowel segment from the normalised
## autocorrelation at the period (searched ±12 % around the planned F0).
func _hnr(buf: PackedFloat32Array, sr: int, pl: Dictionary, seg: Dictionary) -> float:
	var mid := float(seg["t"]) + float(seg["d"]) * 0.5
	var w := int(0.03 * sr)
	var a := int(mid * sr) - w / 2
	var f0: float = _f0(pl, mid)
	var best := 0.0
	for lag in range(int(sr / (f0 * 1.12)), int(sr / (f0 * 0.88)) + 1):
		var c := 0.0
		var n0 := 0.0
		var n1 := 0.0
		for k in w:
			var x := buf[a + k]
			var y := buf[a + k + lag]
			c += x * y
			n0 += x * x
			n1 += y * y
		best = maxf(best, c / maxf(sqrt(n0 * n1), 1e-12))
	best = clampf(best, 1e-4, 0.99999)
	return 10.0 * log(best / (1.0 - best)) / log(10.0)


## RMS of a biquad-filtered copy (RBJ low-pass or band-pass) – band levels for tilt checks.
func _band_db(x: PackedFloat32Array, sr: int, f: float, q: float, bandpass: bool) -> float:
	var w0 := TAU * f / sr
	var al := sin(w0) / (2.0 * q)
	var cw := cos(w0)
	var b0: float
	var b1: float
	var b2: float
	if bandpass:
		b0 = al
		b1 = 0.0
		b2 = -al
	else:
		b0 = (1.0 - cw) * 0.5
		b1 = 1.0 - cw
		b2 = b0
	var a0 := 1.0 + al
	var a1 := -2.0 * cw
	var a2 := 1.0 - al
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var e := 0.0
	for v in x:
		var y := (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = v
		y2 = y1
		y1 = y
		e += y * y
	return 10.0 * log(e / maxf(x.size(), 1) + 1e-14) / log(10.0)


## Concatenated vowel-nucleus samples (central 70 %) of a rendered plan.
func _vowel_samples(buf: PackedFloat32Array, sr: int, pl: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for sg in pl["segments"]:
		if String(sg["ph"]) in VOWELS:
			var a := int((float(sg["t"]) + float(sg["d"]) * 0.15) * sr)
			var b := int((float(sg["t"]) + float(sg["d"]) * 0.85) * sr)
			out.append_array(buf.slice(a, b))
	return out


func _seg_rms_db(buf: PackedFloat32Array, sr: int, sg: Dictionary) -> float:
	var a := int((float(sg["t"]) + float(sg["d"]) * 0.2) * sr)
	var b := int((float(sg["t"]) + float(sg["d"]) * 0.8) * sr)
	var e := 0.0
	for i in range(a, b):
		e += buf[i] * buf[i]
	return 10.0 * log(e / maxf(b - a, 1) + 1e-14) / log(10.0)


func _test_naturalness() -> void:
	section("Naturalness: no clicks, breath noise, living F0, tilt, levels, timing")
	var sr := TTS.SR
	# --- clicks / discontinuities at segment joins, smooth utterance edges --------------
	var lines := ["Máma mele maso.", "ama ana aňa ala ara aja asa aša afa aha ava aza aža axa", "Řekni tři slova, prosím.",
		"Dobré ráno, dáš si kávu?", "Nevím, asi zítra."]
	var click_report: Array = []
	var edges_ok := true
	for ln in lines:
		for vv in [{}, {"pitch": -0.9, "timbre": -0.6, "roughness": 0.6}, {"pitch": 0.8, "timbre": 0.7, "tempo": 0.5}]:
			var pl := TTS.plan(ln, vv, "klidne")
			var buf := TTS.render_plan(pl, vv, sr)
			var hits := _clicks(buf, sr, pl)
			if not hits.is_empty():
				click_report.append("%s %s @%s ms" % [ln.substr(0, 12), str(vv), str(hits.slice(0, 4))])
			var head := 0.0
			for i in int(0.004 * sr):
				head = maxf(head, absf(buf[i]))
			edges_ok = edges_ok and buf[0] == 0.0 and absf(buf[buf.size() - 1]) < 1e-6 and head < 0.01
	check(click_report.is_empty(), "no clicks / discontinuities at segment joins (5 lines × 3 voices)", ", ".join(click_report))
	check(edges_ok, "utterance starts and ends silently (no onset/offset click)")
	# --- breath / aspiration noise: natural HNR, breathier sad style, whisper is noise -----
	var hnr := {}
	for st in ["klidne", "smutne", "nastvane", "septem"]:
		var pl := TTS.plan("Máma tam má málo.", {"roughness": 0.2}, st)
		var buf := TTS.render_plan(pl, {"roughness": 0.2}, sr)
		var vals: Array = []
		for sg in pl["segments"]:
			if String(sg["ph"]) == "á" and float(sg["d"]) > 0.1:
				vals.append(_hnr(buf, sr, pl, sg))
		vals.sort()
		hnr[st] = vals[vals.size() / 2] if not vals.is_empty() else 99.0
	check(float(hnr["klidne"]) > 10.0 and float(hnr["klidne"]) < 28.0, "calm voice: HNR in a natural range (breath noise present, not a pure buzz)",
		"%.1f dB" % hnr["klidne"])
	check(float(hnr["smutne"]) < float(hnr["klidne"]) - 1.0, "sad style is breathier (lower HNR) than calm", "%.1f vs %.1f dB" % [hnr["smutne"], hnr["klidne"]])
	check(float(hnr["septem"]) < 3.0, "whisper is aperiodic", "%.1f dB" % hnr["septem"])
	# Default roughness: jitter/shimmer stay small (natural), high roughness clearly rougher.
	var rough_lo := float(hnr["klidne"])
	var plr := TTS.plan("Máma tam má málo.", {"roughness": 1.0}, "klidne")
	var bufr := TTS.render_plan(plr, {"roughness": 1.0}, sr)
	var rvals: Array = []
	for sg in plr["segments"]:
		if String(sg["ph"]) == "á" and float(sg["d"]) > 0.1:
			rvals.append(_hnr(bufr, sr, plr, sg))
	rvals.sort()
	check(not rvals.is_empty() and float(rvals[rvals.size() / 2]) < rough_lo - 1.0, "roughness 1 lowers HNR (more jitter/shimmer/noise)",
		"%.1f vs %.1f dB" % [rvals[rvals.size() / 2] if not rvals.is_empty() else 0.0, rough_lo])
	# --- F0 lives: never perfectly flat inside a vowel, smooth, lively but bounded -------
	var longest := 0.0
	var max_step := 0.0
	var sd_ok := true
	var sds: Array = []
	for ln in ["Ahoj, jak se máš?", "Dneska je hezky.", "Půjdeš se mnou zítra ven?", "To je skvělé!", "Ty jsi dneska nějaký smutný."]:
		for vv in [{}, {"pitch": 0.9}, {"pitch": -0.9}]:
			var pl := TTS.plan(ln, vv, "vesele" if ln.ends_with("!") else "klidne")
			var f: PackedFloat32Array = pl["f0"]
			for sg in pl["segments"]:
				if not String(sg["ph"]) in VOWELS:
					continue
				var i0 := int((float(sg["t"]) + 0.01) / TTS.F0_STEP)
				var i1 := int((float(sg["t"]) + float(sg["d"]) - 0.01) / TTS.F0_STEP)
				var run := 0
				for i in range(i0 + 1, i1):
					var dst := absf(12.0 * log(f[i] / f[i - 1]) / log(2.0))
					max_step = maxf(max_step, dst)
					run = run + 1 if dst < 0.004 else 0
					longest = maxf(longest, run * TTS.F0_STEP)
			if vv.is_empty():
				var m := 0.0
				var cnt := 0
				for sy in pl["syllables"]:
					m += 12.0 * log(_f0(pl, (float(sy["nt0"]) + float(sy["nt1"])) * 0.5) / 160.0) / log(2.0)
					cnt += 1
				m /= maxf(cnt, 1)
				var v := 0.0
				for sy in pl["syllables"]:
					var d := 12.0 * log(_f0(pl, (float(sy["nt0"]) + float(sy["nt1"])) * 0.5) / 160.0) / log(2.0) - m
					v += d * d
				sds.append(sqrt(v / maxf(cnt, 1)))
	check(longest <= 0.05, "F0 is never perfectly flat inside a vowel for > 50 ms (micro-prosody, soft limits)", "longest flat run %.0f ms" % (longest * 1000.0))
	check(max_step < 0.5, "no abrupt F0 jumps inside vowels (< 0.5 st per 5 ms)", "max %.2f st" % max_step)
	for x in sds:
		sd_ok = sd_ok and float(x) > 0.8 and float(x) < 6.0
	check(sd_ok, "syllable F0 spread is speech-like (0.8–6 st SD per sentence)", str(sds))
	var hi_pl := TTS.plan("To je ale skvělé! Hurá!", {"pitch": 1.0}, "nastvane")
	var hi_max := 0.0
	for x in hi_pl["f0"]:
		hi_max = maxf(hi_max, x)
	check(hi_max <= TTS.F0_MAX and hi_max > 300.0, "highest voice + angry exclamation stays below the soft F0 ceiling (never shrieky)", "%.0f Hz" % hi_max)
	# --- bandwidths and spectral tilt ------------------------------------------------------
	var bw: Array = TTS.FORMANT_BW
	check(bw[0] >= 60.0 and bw[0] <= 90.0 and bw[1] >= 90.0 and bw[1] <= 120.0 and bw[2] >= 120.0 and bw[2] <= 180.0 and bw[3] >= 200.0,
		"formant bandwidths in natural ranges (F1 60–90, F2 90–120, F3 120–180, F4 ≥ 200 Hz)", str(bw))
	var tilt := {}
	for st in ["klidne", "smutne", "nastvane"]:
		var pl := TTS.plan("Dneska je hezky a máma má málo.", {}, st)
		var vs := _vowel_samples(TTS.render_plan(pl, {}, sr), sr, pl)
		tilt[st] = _band_db(vs, sr, 2828.0, 1.41, true) - _band_db(vs, sr, 1000.0, 0.707, false)
	check(float(tilt["klidne"]) > -32.0 and float(tilt["klidne"]) < -12.0, "calm vowels: 2–4 kHz band 12–32 dB below 0–1 kHz (warm, not muffled, not harsh)",
		"%.1f dB" % tilt["klidne"])
	check(float(tilt["nastvane"]) > float(tilt["smutne"]) + 2.0, "angry is brighter/tenser than sad", "%.1f vs %.1f dB" % [tilt["nastvane"], tilt["smutne"]])
	# --- segment levels relative to vowels ---------------------------------------------
	var plv := TTS.plan("ama ana ala ara asa aša afa aha ava", {}, "klidne")
	var bv := TTS.render_plan(plv, {}, sr)
	var vowel_db := 0.0
	var nv := 0
	var lev := {}
	for sg in plv["segments"]:
		var db := _seg_rms_db(bv, sr, sg)
		if String(sg["ph"]) == "a":
			vowel_db += db
			nv += 1
		else:
			lev[String(sg["ph"])] = db
	vowel_db /= maxf(nv, 1)
	var lv_bad: Array = []
	for ph in lev:
		var rel := float(lev[ph]) - vowel_db
		var lo := -13.0 if ph in ["m", "n", "l", "r", "v"] else -18.0
		var hi := -3.0 if ph in ["m", "n", "l", "r", "v"] else -5.0
		if rel < lo or rel > hi:
			lv_bad.append("%s %.1f dB" % [ph, rel])
	check(lv_bad.is_empty(), "consonant levels relative to vowels: sonorants −3…−13 dB, fricatives / h −5…−18 dB", ", ".join(lv_bad))
	# --- timing ranges -------------------------------------------------------------------
	var pt := TTS.plan("Pata, máma má kosu. Půjdeme ven.")
	var shorts: Array = []
	var cons: Array = []
	for sg in pt["segments"]:
		var ph := String(sg["ph"])
		var syl: Dictionary = pt["syllables"][int(sg["syl"])]
		if ph in ["a", "e", "i", "o", "u"] and not bool(syl["last"]):
			shorts.append(float(sg["d"]))
		elif not ph in VOWELS:
			cons.append(float(sg["d"]))
	var t_bad: Array = []
	for d in shorts:
		if d < 0.07 or d > 0.11:
			t_bad.append("V %.0f ms" % (d * 1000.0))
	for d in cons:
		if d < 0.045 or d > 0.1:
			t_bad.append("C %.0f ms" % (d * 1000.0))
	check(t_bad.is_empty(), "short vowels 70–110 ms, consonants 45–100 ms at default tempo", ", ".join(t_bad))
	var phs: Array = pt["phrases"]
	var comma := float(phs[1]["t0"]) - float(phs[0]["t1"])
	var period := float(phs[2]["t0"]) - float(phs[1]["t1"])
	check(comma >= 0.15 and comma <= 0.25 and period >= 0.35 and period <= 0.5, "pauses: comma 150–250 ms, period 350–500 ms",
		"%.0f / %.0f ms" % [comma * 1000.0, period * 1000.0])
	# --- loudness: ≈ −3 dBFS peak for the loudest style, no clipping ----------------------
	var ang := VoiceSynth.speak_buffer("To snad nemyslíš vážně!", {}, "nastvane")
	var pk := 0.0
	for x in ang:
		pk = maxf(pk, absf(x))
	check(pk > 0.6 and pk < 0.75, "angry style peaks near −3 dBFS (no clipping)", "%.2f" % pk)
	# --- determinism across rates and interleaving, and speed -----------------------------
	var v := {"pitch": -0.2, "timbre": 0.4, "tempo": -0.2, "roughness": 0.7}
	var d1 := VoiceSynth.speak("Ty jsi dneska nějaký smutný.", v, "smutne", 16000).data
	VoiceSynth.speak("Něco úplně jiného!", {"pitch": 0.9}, "vesele", 22050)
	var d2 := VoiceSynth.speak("Ty jsi dneska nějaký smutný.", v.duplicate(), "smutne", 16000).data
	check(d1 == d2, "identical bytes for identical input even after other renders (16 kHz)")
	var t0 := Time.get_ticks_usec()
	var long_buf := TTS.render("Dobré ráno, dáš si kávu? Já si dám čaj, protože káva mi nechutná.", {}, "klidne", 22050)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var secs := float(long_buf.size()) / 22050.0
	check(secs > 2.5 and ms < 1000.0, "a ~3 s sentence at 22.05 kHz synthesises well under 1 s", "%.1f s audio in %.0f ms" % [secs, ms])
