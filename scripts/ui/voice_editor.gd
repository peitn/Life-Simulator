extends VBoxContainer
## Editor hlasu postavy: výška, barva, tempo a chraplavost (CharacterData.voice) s živou
## ukázkou ve skutečném syntezátoru hry (VoiceSynth). Hlas je samostatná osa – nezávisí na
## těle, pohlaví, genderové identitě, rodu ani jménu a editor nic z toho nenastavuje.
## Hodnoty zůstávají v návrhu volajícího (CharacterEditSession) až do Použít / Vytvořit.
## Ukázka je čistě lokální kosmetika – nic neposílá po síti a nic nemění v simulaci.

const Schema := preload("res://scripts/character/character_schema.gd")
const VoiceSynth := preload("res://scripts/audio/voice_synth.gd")

signal voice_changed(key: String, value: float)

const FIELDS := ["pitch", "timbre", "tempo", "roughness"]
const LABELS := {
	"pitch": "Výška hlasu",
	"timbre": "Barva hlasu",
	"tempo": "Tempo řeči",
	"roughness": "Chraplavost",
}
## Slovní popis pro čtečky a pro ty, kdo nechtějí číst čísla (dolní / střed / horní).
const WORDS := {
	"pitch": ["hluboký", "střední", "vysoký"],
	"timbre": ["tmavá, sytá", "neutrální", "jasná, ostrá"],
	"tempo": ["pomalé, rozvážné", "běžné", "rychlé"],
	"roughness": ["čistý", "lehce zastřený", "chraplavý"],
}
const PREVIEW_SECONDS := 2.2
## Kolik ukázek si editor pamatuje (kvantizovaný klíč → stream); malá LRU cache.
const CACHE_MAX := 12

var auto_preview := true
var _controls: Dictionary = {}
var _value_labels: Dictionary = {}
var _style: OptionButton
var _play: Button
var _another: Button
var _auto: CheckBox
var _player: AudioStreamPlayer
var _summary: Label
var _voice: Dictionary = {}
var _variant := 0
var _loading := false
var _cache: Dictionary = {}
var _cache_order: Array = []
var _editable := true
var _pending := false
## Syntéza ukázky běží ve WorkerThreadPool (review Gemini: ~90 ms na hlavním vlákně = cuknutí UI).
var _job := -1
var _job_out: Array = []
var _job_t0 := 0
var _want_play := false
## Statistika pro testy a výkon (poslední doba syntézy v ms).
var last_render_ms := 0.0
var renders := 0
var plays := 0


func _ready() -> void:
	name = "VoiceEditor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Hlas"
	title.add_theme_font_size_override("font_size", 17)
	add_child(title)
	var help := Label.new()
	help.text = "Hlas je samostatná volba: nezávisí na těle, pohlaví, identitě ani rodu. Ukázka zní stejně jako postava ve hře."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var fields: Dictionary = Schema.fields("voice")
	for key in FIELDS:
		if not fields.has(key):
			continue
		_make_slider(String(key), fields[key])
	_summary = Label.new()
	_summary.name = "VoiceSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	_style = OptionButton.new()
	_style.name = "VoiceStyle"
	_style.tooltip_text = "Jak postava v ukázce mluví"
	for id in VoiceSynth.STYLES:
		_style.add_item(String(VoiceSynth.STYLES[id]))
		_style.set_item_metadata(_style.item_count - 1, String(id))
	row.add_child(_style)
	_play = Button.new()
	_play.name = "VoicePlay"
	_play.text = "▶ Přehrát ukázku"
	_play.pressed.connect(play_preview)
	row.add_child(_play)
	_another = Button.new()
	_another.name = "VoiceAnother"
	_another.text = "Jiná věta"
	_another.pressed.connect(_on_another)
	row.add_child(_another)
	_auto = CheckBox.new()
	_auto.name = "VoiceAutoPreview"
	_auto.text = "Přehrát po změně"
	_auto.button_pressed = auto_preview
	_auto.toggled.connect(func(on: bool) -> void: auto_preview = on)
	row.add_child(_auto)
	_style.item_selected.connect(func(_i: int) -> void: play_preview())
	_player = AudioStreamPlayer.new()
	_player.name = "VoicePreviewPlayer"
	# Sběrnice UI existuje, když běží AudioManager; jinak zůstane Master.
	if AudioServer.get_bus_index("UI") >= 0:
		_player.bus = "UI"
	add_child(_player)
	_update_summary()


func _make_slider(key: String, spec: Array) -> void:
	var line := VBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(line)
	var head := HBoxContainer.new()
	line.add_child(head)
	var caption := Label.new()
	caption.text = String(LABELS.get(key, key))
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(caption)
	var value := Label.new()
	value.custom_minimum_size.x = 120
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(value)
	var slider := HSlider.new()
	slider.name = "VoiceSlider_" + key
	slider.min_value = float(spec[1])
	slider.max_value = float(spec[2])
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(80, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = String(LABELS.get(key, key))
	line.add_child(slider)
	slider.value_changed.connect(_on_slider.bind(key))
	slider.drag_started.connect(func() -> void: slider.set_meta("dragging", true))
	slider.drag_ended.connect(_on_drag_ended.bind(key))
	_controls[key] = slider
	_value_labels[key] = value


## Načte hlas z návrhu postavy (dictionary CharacterData). Nevyvolá voice_changed.
func load_data(data: Dictionary) -> void:
	var v: Variant = data.get("voice", {})
	_voice = VoiceSynth.normalized(v)
	_loading = true
	for key in _controls:
		var slider: HSlider = _controls[key]
		slider.set_value_no_signal(clampf(float(_voice.get(key, 0.0)), slider.min_value, slider.max_value))
		_update_value_label(String(key))
	_loading = false
	_update_summary()


## Zamknutí (např. čeká se na potvrzení serveru) – ukázku lze přehrát dál.
func set_editable(on: bool) -> void:
	_editable = on
	for key in _controls:
		(_controls[key] as HSlider).editable = on


func _describe(key: String, value: float) -> String:
	var words: Array = WORDS.get(key, ["", "", ""])
	var lo := -1.0
	var hi := 1.0
	if key == "roughness":
		lo = 0.0
	var t := (value - lo) / (hi - lo)
	if t < 0.34:
		return String(words[0])
	if t > 0.66:
		return String(words[2])
	return String(words[1])


func _update_value_label(key: String) -> void:
	var slider: HSlider = _controls.get(key)
	var label: Label = _value_labels.get(key)
	if slider == null or label == null:
		return
	label.text = "%s (%+.2f)" % [_describe(key, slider.value), slider.value] if key != "roughness" else "%s (%.2f)" % [_describe(key, slider.value), slider.value]


func _update_summary() -> void:
	if _summary == null:
		return
	var p := VoiceSynth.params(_voice)
	_summary.text = "Základní tón ≈ %d Hz · %.1f slabik/s · %s" % [roundi(float(p["f0"])), float(p["rate"]),
		_describe("roughness", float(_voice.get("roughness", 0.2)))]


func _on_slider(value: float, key: String) -> void:
	if _loading or not _editable or not is_finite(value):
		return
	_voice[key] = value
	_update_value_label(key)
	_update_summary()
	voice_changed.emit(key, value)
	# Klávesnice/gamepad nemají „konec tažení“: ukázka se přehraje po krátké pauze.
	if auto_preview and not (_controls[key] as HSlider).has_meta("dragging"):
		_schedule_preview()


func _on_drag_ended(changed: bool, key: String) -> void:
	var s: HSlider = _controls.get(key)
	if s != null and s.has_meta("dragging"):
		s.remove_meta("dragging")
	if changed and auto_preview:
		play_preview()


func _schedule_preview() -> void:
	if _pending or not is_inside_tree():
		return
	_pending = true
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		_pending = false
		if is_inside_tree():
			play_preview())


func _on_another() -> void:
	_variant = (_variant + 1) % 64
	play_preview()


func current_style() -> String:
	if _style == null or _style.selected < 0:
		return "klidne"
	return VoiceSynth.style_or_default(_style.get_item_metadata(_style.selected))


func current_voice() -> Dictionary:
	return _voice.duplicate()


## Stream ukázky pro aktuální hlas (z cache nebo nově syntetizovaný) – SYNCHRONNĚ.
## Pro API a testy; tlačítko Přehrát používá asynchronní play_preview().
func preview_stream() -> AudioStreamWAV:
	var style := current_style()
	var key := VoiceSynth.cache_key(_voice, style, _variant, PREVIEW_SECONDS)
	if _cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var buf := VoiceSynth.render(VoiceSynth.quantized(_voice), style, _variant, PREVIEW_SECONDS)
	var stream := VoiceSynth.to_stream(buf)
	last_render_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	renders += 1
	_cache[key] = stream
	_cache_order.append(key)
	while _cache_order.size() > CACHE_MAX:
		_cache.erase(_cache_order.pop_front())
	return stream


## Přehraje ukázku: z cache hned, jinak syntéza na pozadí a přehrání po dokončení. Během
## syntézy se další požadavek jen poznamená (posuvník tažený sem a tam nezahltí vlákna).
func play_preview() -> void:
	if _player == null:
		return
	var key := VoiceSynth.cache_key(_voice, current_style(), _variant, PREVIEW_SECONDS)
	if _cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		_start_player(_cache[key])
		return
	_want_play = true
	if _job < 0:
		_start_job()


func is_rendering() -> bool:
	return _job >= 0


func _start_job() -> void:
	_job_out = []
	_job_t0 = Time.get_ticks_usec()
	var key := VoiceSynth.cache_key(_voice, current_style(), _variant, PREVIEW_SECONDS)
	_job = WorkerThreadPool.add_task(_render_job.bind(VoiceSynth.quantized(_voice), current_style(), _variant, key, _job_out), false, "voice preview")


## Běží ve vlákně: čistá statická syntéza + zakódování do vlastního pole, žádný přístup ke scéně.
static func _render_job(voice: Dictionary, style: String, variant: int, key: String, out: Array) -> void:
	out.append([key, VoiceSynth.to_stream(VoiceSynth.render(voice, style, variant, PREVIEW_SECONDS))])


func _process(_delta: float) -> void:
	if _job < 0 or not WorkerThreadPool.is_task_completed(_job):
		return
	WorkerThreadPool.wait_for_task_completion(_job)
	_job = -1
	if not _job_out.is_empty():
		var done: Array = _job_out[0]
		last_render_ms = float(Time.get_ticks_usec() - _job_t0) / 1000.0
		renders += 1
		_cache[String(done[0])] = done[1]
		_cache_order.erase(String(done[0]))
		_cache_order.append(String(done[0]))
		while _cache_order.size() > CACHE_MAX:
			_cache.erase(_cache_order.pop_front())
	if not _want_play:
		return
	# Mezitím se mohl hlas/styl změnit: přehraj aktuální, případně dopočítej.
	var key := VoiceSynth.cache_key(_voice, current_style(), _variant, PREVIEW_SECONDS)
	if _cache.has(key):
		_want_play = false
		_start_player(_cache[key])
	else:
		_start_job()


func _start_player(stream: AudioStreamWAV) -> void:
	_player.stream = stream
	if _player.is_inside_tree():
		_player.play()
	plays += 1


func _exit_tree() -> void:
	# Úloha trvá desítky ms; počkat je bezpečnější než nechat vlákno psát do uvolněného pole.
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1


func slider(key: String) -> HSlider:
	return _controls.get(key)


func style_button() -> OptionButton:
	return _style


func cache_size() -> int:
	return _cache.size()
