extends "res://tests/test_base.gd"
## Each case runs in its own process: --case=8bit / --case=8khz.
const Neural := preload("res://scripts/audio/neural_voice.gd")

func _ready() -> void:
	watchdog_seconds = 20.0
	_run.call_deferred()

func _run() -> void:
	var mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			mode = arg.trim_prefix("--case=")
	section("Piper invalid cache: " + mode)
	if not check(mode in ["8bit", "8khz"], "explicit case"):
		finish("test_neural_cache_formats")
		return
	if not check(Neural.supported("kasandra"), "local Piper model installed"):
		finish("test_neural_cache_formats")
		return
	var line := "Cache QA " + mode + " " + str(int(Time.get_unix_time_from_system())) + " " + str(OS.get_process_id())
	var path := ProjectSettings.globalize_path("user://piper_tts").path_join(Neural.key_for(line, {}, "klidne", "kasandra") + ".wav")
	if not check(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK, "cache directory ready"):
		finish("test_neural_cache_formats")
		return
	var fake := AudioStreamWAV.new()
	fake.format = AudioStreamWAV.FORMAT_8_BITS if mode == "8bit" else AudioStreamWAV.FORMAT_16_BITS
	fake.mix_rate = 22050 if mode == "8bit" else 8000
	fake.stereo = false
	var pcm := PackedByteArray()
	pcm.resize(8192)
	fake.data = pcm
	if not check(fake.save_to_wav(path) == OK, "invalid WAV written"):
		DirAccess.remove_absolute(path)
		finish("test_neural_cache_formats")
		return
	var planted := AudioStreamWAV.load_from_file(path)
	var invalid := planted != null and planted.data.size() >= 2000
	if invalid:
		if mode == "8bit":
			invalid = planted.format == AudioStreamWAV.FORMAT_8_BITS and planted.mix_rate == 22050
		else:
			invalid = planted.format == AudioStreamWAV.FORMAT_16_BITS and planted.mix_rate == 8000
	check(invalid, "loadable invalid WAV would pass old size-only check")
	if invalid:
		var result := Neural.render(line, {}, "klidne", "kasandra")
		check(result != null, "Piper regenerated invalid cache")
		if result != null:
			check(not result.stereo and result.format == AudioStreamWAV.FORMAT_16_BITS, "fresh mono 16-bit")
			check(result.mix_rate >= 16000 and result.data.size() >= 2000, "fresh rate and data valid")
		var persisted := AudioStreamWAV.load_from_file(path)
		check(persisted != null and not persisted.stereo and persisted.format == AudioStreamWAV.FORMAT_16_BITS and persisted.mix_rate >= 16000 and persisted.data.size() >= 2000, "disk cache replaced")
	check(DirAccess.remove_absolute(path) == OK, "cache fixture removed")
	finish("test_neural_cache_formats")
