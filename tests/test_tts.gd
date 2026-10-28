extends "res://tests/test_base.gd"
## Czech text-to-speech (28 Oct 2026): rule-based G2P, stress, F0 contours (statement, yes/no
## and wh-questions), determinism, voice parameters, signal sanity, durations, odd input,
## threading/cache in AudioManager, the "Hlasy postav" setting, privacy and the editor preview.

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
	check(gs.get_value("character_voices") == "tts", "default voice mode is Řeč z textu")
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
