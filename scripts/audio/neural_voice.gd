extends RefCounted
## CPU neural Czech TTS (Piper ONNX) for Godot native/headless builds.
## No network at synthesis time. Model selection is explicit and NEVER inferred
## from gender, anatomy, identity or the character's grammatical form.
## Web exports have no Python process; the caller must handle unavailable backend.

const CLI := "res://tools/audio/neural_tts.py"
const DEFAULT_MODELS := "/app/library/lifesim/neural_models"
const SPEAKERS := ["kasandra", "jirka"]
const MODEL_NAMES := {
	"kasandra": "cs_CZ-kasandra-medium.onnx",
	"jirka": "cs_CZ-jirka-medium.onnx",
}
const MIN_SAMPLES := 1000

static func model_dir() -> String:
	var custom := OS.get_environment("LIFESIM_PIPER_MODEL_DIR")
	return custom if custom != "" else DEFAULT_MODELS

static func supported(speaker: String = "kasandra") -> bool:
	if OS.has_feature("web") or not MODEL_NAMES.has(speaker):
		return false
	if not FileAccess.file_exists(ProjectSettings.globalize_path(CLI)):
		return false
	var model_path := model_dir().path_join(String(MODEL_NAMES[speaker]))
	return FileAccess.file_exists(model_path) and FileAccess.file_exists(model_path + ".json")

static func key_for(text: String, voice: Dictionary, style: String, speaker: String) -> String:
	# Cache includes normalized inputs, backend name and version so it cannot collide
	# with old procedural samples or other speaker models.
	var tempo := clampf(float(voice.get("tempo", 0.0)), -1.0, 1.0)
	return ("piper-v1|" + speaker + "|" + text.substr(0, 200) + "|" + style
		+ "|" + "%.3f" % tempo).sha256_text()

static func render(text: String, voice: Dictionary = {}, style: String = "klidne",
		speaker: String = "kasandra") -> AudioStreamWAV:
	if not supported(speaker) or text.strip_edges() == "":
		return null
	var cleaned := text.strip_edges().substr(0, 200)
	var cache_dir := ProjectSettings.globalize_path("user://piper_tts")
	if DirAccess.make_dir_recursive_absolute(cache_dir) != OK:
		return null
	var output := cache_dir.path_join(key_for(cleaned, voice, style, speaker) + ".wav")
	if FileAccess.file_exists(output):
		var cached := AudioStreamWAV.load_from_file(output)
		if cached != null and not cached.stereo and cached.format == AudioStreamWAV.FORMAT_16_BITS and cached.mix_rate >= 16000 and cached.data.size() >= MIN_SAMPLES * 2:
			return cached
	# Piper's length_scale changes rate but DOES NOT preserve the procedural
	# formant timbre, glottal roughness or resonance slider interpretations.
	var tempo := clampf(float(voice.get("tempo", 0.0)), -1.0, 1.0)
	var speed := pow(2.0, -0.50 * tempo)
	match style:
		"vesele", "nastvane":
			speed *= 0.93
		"smutne", "unavene":
			speed *= 1.14
	speed = clampf(speed, 0.75, 1.4)
	var noise := 0.70
	match style:
		"vesele":
			noise = 0.82
		"smutne", "unavene":
			noise = 0.54
		"nastvane":
			noise = 0.88
	# Each arg is separate (no shell injection); stdout may contain provider diagnostics.
	var argv := PackedStringArray([ProjectSettings.globalize_path(CLI),
		"--speaker", speaker, "--text", cleaned, "--output", output,
		"--length-scale", "%.4f" % speed, "--noise-scale", "%.4f" % noise])
	var lines: Array = []
	var rc := OS.execute("python3", argv, lines, true)
	if rc != 0:
		push_warning("Piper TTS failed (code %d): %s" % [rc, " ".join(PackedStringArray(lines)).substr(0, 160)])
		return null
	var result := AudioStreamWAV.load_from_file(output)
	if result == null or result.stereo or result.format != AudioStreamWAV.FORMAT_16_BITS or result.mix_rate < 16000 or result.data.size() < MIN_SAMPLES * 2:
		return null
	return result

static func speaker_for_character(character_id: String) -> String:
	# A stable opt-in preview default, not inferred from any personal characteristic.
	# Individual character speaker selection in the creator is an independent follow-up.
	var digest := character_id.sha256_text()
	return "kasandra" if int("0x" + digest.substr(0, 2)) % 2 == 0 else "jirka"
