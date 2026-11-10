extends "res://tests/test_base.gd"
## Neural Czech TTS acceptance: real ONNX/Piper audio, different speaker timbres,
## cache, worker jobs, editor playback and preserved opt-in GameSettings.

const Neural := preload("res://scripts/audio/neural_voice.gd")
const AudioMgr := preload("res://scripts/audio/audio_manager.gd")
const VoiceEditor := preload("res://scripts/ui/voice_editor.gd")
const Settings := preload("res://scripts/core/game_settings.gd")

func _ready() -> void:
	watchdog_seconds = 140.0
	_run.call_deferred()


func _run() -> void:
	section("Opt-in, local backend and safety")
	check(Settings.DEFAULTS["character_voices"] == "wordless", "neural mode does not silently change game default")
	check(Settings.VOICE_MODES.has("tts_neural"), "GameSettings lists separate neural option")
	check(Neural.speaker_for_character("char-a") == Neural.speaker_for_character("char-a"), "speaker ID is stable")
	check(Neural.speaker_for_character("char-a") in Neural.SPEAKERS, "only explicitly whitelisted Czech voices")
	check(not Neural.supported("nonexistent"), "unsupported speaker rejected")
	var gs := Settings.new()
	gs.persist = false
	check(gs.set_value("character_voices", "tts_neural", false), "neural mode validated")
	check(gs.character_voice_mode() == "tts_neural", "neural preference round-trip")
	gs.free()
	var backend := Neural.supported("kasandra") and Neural.supported("jirka")
	if not backend:
		section("Piper backend not present: graceful unsupported path")
		check(Neural.render("Ahoj", {}, "klidne", "nope") == null, "missing model yields null, not procedural fallback")
		finish("test_neural_tts")
		return
	section("Real Czech Piper ONNX inference and byte-distinct voices")
	var line := "Ahoj, jak se máš?"
	var a := Neural.render(line, {"tempo": 0.0}, "klidne", "kasandra")
	var b := Neural.render(line, {"tempo": 0.0}, "klidne", "jirka")
	check(a != null and b != null, "two local model inference runs yield AudioStreamWAV")
	if a == null or b == null:
		finish("test_neural_tts")
		return
	check(a.mix_rate >= 16000 and b.mix_rate >= 16000, "human speech audio sample rate")
	check(a.data.size() > 15000 and b.data.size() > 15000, "nonempty real PCM from each model")
	check(a.data != b.data, "Kasandra and Jirka differ in actual audio samples")
	var again := Neural.render(line, {"tempo": 0.0}, "klidne", "kasandra")
	check(again != null and again.data == a.data, "deterministic, reusable cached WAV")
	var slow := Neural.render(line, {"tempo": -1.0}, "klidne", "kasandra")
	var fast := Neural.render(line, {"tempo": 1.0}, "klidne", "kasandra")
	check(slow != null and fast != null and slow.get_length() > fast.get_length() * 1.15,
		"tempo slider changes neural length, not just formant bandwidth")
	section("AudioManager renders neural TTS via WorkerThreadPool")
	var out: Array = []
	var task := WorkerThreadPool.add_task(AudioMgr._render_tts_job.bind(line, {"tempo": 0.0}, "klidne", "jirka", out),
		false, "neural test")
	WorkerThreadPool.wait_for_task_completion(task)
	check(out.size() == 1 and out[0] is AudioStreamWAV, "AudioManager worker generated playable neural stream")
	if out.size() == 1:
		check((out[0] as AudioStreamWAV).data == b.data, "game 3D speech job uses genuine Piper PCM")
	section("Character editor preview")
	var ed := VoiceEditor.new()
	add_child(ed)
	ed.load_data({"voice": {"tempo": 0.0, "pitch": 0.0, "roughness": 0.2}})
	check(ed.get_node_or_null("VoiceNeuralPreviewRow/VoiceNeural_kasandra") != null,
		"Kasandra neural preview exists")
	check(ed.get_node_or_null("VoiceNeuralPreviewRow/VoiceNeural_jirka") != null,
		"Jirka neural preview exists")
	ed.play_neural_sentence("kasandra")
	var done: bool = await wait_until(func() -> bool: return ed.neural_sentence_plays > 0, 35.0)
	check(done and ed.neural_sentence_renders > 0, "editor background inference plays a new neural sample")
	ed.queue_free()
	await get_tree().process_frame
	finish("test_neural_tts")
