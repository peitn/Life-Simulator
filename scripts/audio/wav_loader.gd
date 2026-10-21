extends RefCounted
## Načte 16bit PCM WAV za běhu (bez importu editoru) a nastaví smyčku.
## Díky tomu hra funguje i headless a s WAVy vyrobenými nástrojem tools/build_audio.gd.

static var _cache := {}


static func load_wav(path: String, loop: bool) -> AudioStreamWAV:
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		push_warning("Neplatný WAV: " + path)
		return null
	var channels := 1
	var rate := 22050
	var bits := 16
	var data := PackedByteArray()
	var pos := 12
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt ":
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data":
			data = bytes.slice(body, mini(body + size, bytes.size()))
		pos = body + size + (size % 2)
	if bits != 16 or data.is_empty():
		push_warning("Nepodporovaný WAV (jen 16bit PCM): " + path)
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = channels == 2
	s.mix_rate = rate
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size() / (2 * channels)
	_cache[key] = s
	return s
