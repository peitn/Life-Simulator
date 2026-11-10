extends "res://tests/test_base.gd"
## Regression: an untrusted or corrupted on-disk Piper cache entry must not
## bypass mono/16-bit/sample-rate validation or be used for 3D speech.
const Neural := preload("res://scripts/audio/neural_voice.gd")

func _ready() -> void:
	watchdog_seconds = 80.0
	_run.call_deferred()

func _run() -> void:
	section("Piper cache format integrity")
	check(Neural.supported("kasandra"), "real local Piper model is installed")
	if not Neural.supported("kasandra"):
		finish("test_neural_cache_integrity")
		return
	var line := "Kontrola integrity hlasové cache 2026-10-30."
	var path := ProjectSettings.globalize_path("user://piper_tts").path_join(
		Neural.key_for(line, {}, "klidne", "kasandra") + ".wav")
	check(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK, "cache directory exists")
	var fake := AudioStreamWAV.new()
	fake.format = AudioStreamWAV.FORMAT_16_BITS
	fake.mix_rate = 22050
	fake.stereo = true
	var bytes := PackedByteArray()
	bytes.resize(8192)
	fake.data = bytes
	check(fake.save_to_wav(path) == OK, "stereo cache fixture written")
	var planted := AudioStreamWAV.load_from_file(path)
	check(planted != null and planted.stereo and planted.data.size() >= 2000,
		"fixture is loadable and would pass the old size-only check")
	var result := Neural.render(line, {}, "klidne", "kasandra")
	check(result != null, "Piper regenerated the invalid cache entry")
	if result != null:
		check(not result.stereo and result.format == AudioStreamWAV.FORMAT_16_BITS,
			"regenerated PCM is mono 16-bit")
		check(result.mix_rate >= 16000 and result.data.size() > 8192,
			"regenerated speech has valid sample rate and nontrivial data")
	var persisted := AudioStreamWAV.load_from_file(path)
	check(persisted != null and not persisted.stereo,
		"invalid on-disk stereo entry was atomically replaced")
	check(DirAccess.remove_absolute(path) == OK, "test cache entry cleaned up")
	finish("test_neural_cache_integrity")
