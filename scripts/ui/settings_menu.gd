extends CanvasLayer
## Menu (Esc): nastavení obsahu, obsahové varování a krizová pomoc.
## Při prvním spuštění ukáže obsahové varování s odkazy na pomoc; hráč může citlivá témata
## rovnou ztlumit nebo vypnout. Hodnoty ukládá GameSettings (user://settings.cfg).

const GS_PATH := "/root/GameSettings"
const NeuralVoice := preload("res://scripts/audio/neural_voice.gd")
const VOICE_IDS := ["wordless", "tts", "tts_neural", "off"]

var _settings: Node
var _root: Control
var _warning: PanelContainer
var _menu: PanelContainer
var _mh: OptionButton
var _thoughts: OptionButton
var _fx: CheckBox
var _fx_strength: HSlider
var _addiction: CheckBox
var _profanity: CheckBox
var _voices: OptionButton
var _audio_enabled: CheckBox
var _sh_ed: CheckBox
var _adult_intimacy: CheckBox
var _syncing := false


func _ready() -> void:
	layer = 20
	_settings = get_node_or_null(GS_PATH)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_menu()
	_build_warning()
	_menu.visible = false
	_warning.visible = false
	_root.resized.connect(_layout_panels)
	_layout_panels()


func is_open() -> bool:
	return _menu.visible or _warning.visible


func toggle() -> void:
	if _warning.visible:
		return
	_menu.visible = not _menu.visible
	if _menu.visible:
		_sync_from_settings()


## Varování při prvním spuštění (dokud ho hráč nepotvrdí).
func show_first_run_warning() -> void:
	if _settings == null or bool(_settings.get_value("warning_ack")):
		return
	_warning.visible = true


# ---------------------------------------------------------------- stavba UI

func _panel(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.set_meta("preferred_width", width)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.96)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	return p


## Keep the actual hit areas inside the viewport on phones and after resizing.
## Content is scrollable, but warning confirmation buttons stay visible.
func _layout_panels() -> void:
	if _root == null:
		return
	var view := _root.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	for panel in [_menu, _warning]:
		if panel == null:
			continue
		var w := minf(float(panel.get_meta("preferred_width", 600.0)), maxf(1.0, view.x - 24.0))
		var h := minf(660.0, maxf(1.0, view.y - 24.0))
		panel.offset_left = -w * 0.5
		panel.offset_right = w * 0.5
		panel.offset_top = -h * 0.5
		panel.offset_bottom = h * 0.5


func _label(text: String, size := 14, color := Color(0.92, 0.92, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _crisis_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_child(_label("Potřebuješ si s někým promluvit?", 16, Color(1.0, 0.85, 0.55)))
	var lines: Array = _settings.CRISIS_LINES if _settings != null else []
	for c in lines:
		v.add_child(_label("• %s: %s (%s)" % [c[0], c[1], c[2]], 14))
	var b := Button.new()
	b.text = "Otevřít findahelpline.com"
	b.pressed.connect(func(): OS.shell_open(_settings.HELPLINE_URL if _settings != null else "https://findahelpline.com"))
	v.add_child(b)
	return v


func _build_warning() -> void:
	_warning = _panel(640)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_warning.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.name = "WarningScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 80.0
	v.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	content.add_child(_label("Upozornění k obsahu", 22, Color(1.0, 0.8, 0.45)))
	content.add_child(_label(_settings.CONTENT_WARNING if _settings != null else "", 14))
	content.add_child(_crisis_box())
	var actions := VBoxContainer.new()
	actions.name = "WarningActions"
	actions.add_theme_constant_override("separation", 5)
	v.add_child(actions)
	var ok := Button.new()
	ok.text = "Rozumím, pokračovat"
	ok.name = "ContinueButton"
	ok.pressed.connect(func(): _ack_warning(""))
	actions.add_child(ok)
	var mute := Button.new()
	mute.text = "Ztlumit citlivá témata"
	mute.pressed.connect(func(): _ack_warning("muted"))
	actions.add_child(mute)
	var cfg := Button.new()
	cfg.text = "Nastavení…"
	cfg.pressed.connect(func():
		_ack_warning("")
		_menu.visible = true
		_sync_from_settings())
	actions.add_child(cfg)
	for b in actions.get_children():
		b.custom_minimum_size.y = 42.0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ack_warning(mh_mode: String) -> void:
	if _settings != null:
		if mh_mode != "":
			_settings.set_value("mental_health", mh_mode, false)
			_settings.set_value("intrusive_thoughts", 1, false)
		_settings.set_value("warning_ack", true)
	_warning.visible = false


func _build_menu() -> void:
	_menu = _panel(600)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(_label("Nastavení obsahu", 22, Color(1.0, 0.8, 0.45)))
	v.add_child(_label("V multiplayeru o tom, co se ve světě děje (ataky, alkohol), rozhoduje nastavení serveru. "
		+ "Zobrazení myšlenek, zkreslení a cenzuru si řídí každý hráč sám.", 12, Color(0.75, 0.75, 0.75)))

	_mh = _option(v, "Duševní zdraví (úzkost, panické ataky…)", ["Plně", "Ztlumeně (bez atak, méně myšlenek)", "Vypnuto (jen běžný stres)"])
	_mh.item_selected.connect(func(i: int): _apply("mental_health", ["full", "muted", "off"][i]))
	_thoughts = _option(v, "Rušivé myšlenky v UI", ["Vypnuto", "Jemně", "Normálně", "Silně"])
	_thoughts.item_selected.connect(func(i: int): _apply("intrusive_thoughts", i))
	_fx = _check(v, "Zkreslení obrazu a zvuku při úzkosti (vinětace, tlumení, tlukot srdce)")
	_fx.toggled.connect(func(on: bool): _apply("distortion_fx", on))
	var row := VBoxContainer.new()
	row.add_child(_label("Síla zkreslení", 13))
	_fx_strength = HSlider.new()
	_fx_strength.min_value = 0.0
	_fx_strength.max_value = 1.0
	_fx_strength.step = 0.05
	_fx_strength.custom_minimum_size = Vector2(120, 28)
	_fx_strength.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fx_strength.value_changed.connect(func(val: float): _apply("distortion_strength", val))
	row.add_child(_fx_strength)
	v.add_child(row)
	_audio_enabled = _check(v, "Herní zvuk zapnutý (hudba, ruchy, hlasy)")
	_audio_enabled.name = "AudioEnabled"
	_audio_enabled.toggled.connect(func(on: bool): _apply("audio_enabled", on))
	_addiction = _check(v, "Závislosti (alkohol, později hazard)")
	_addiction.toggled.connect(func(on: bool): _apply("addiction", on))
	_voices = _option(v, "Hlasy postav", ["Beze slov", "Řeč z textu (syntetická)",
		"Přirozenější řeč – Piper (CPU)", "Vypnuto"])
	# Browser builds have no Python/ONNX engine. Hide an unusable choice by disabling it,
	# rather than silently returning to the old robotic formant synthesizer.
	_voices.set_item_disabled(2, not (NeuralVoice.supported("kasandra") and NeuralVoice.supported("jirka")))
	_voices.set_item_tooltip(2, "Vyžaduje lokální Python a české modely Piper; web zatím není podporován.")
	_voices.item_selected.connect(func(i: int): _apply("character_voices", VOICE_IDS[i]))
	_profanity = _check(v, "Sprostá mluva v dialozích (vypnuto = cenzura k***a)")
	_profanity.toggled.connect(func(on: bool): _apply("profanity", on))
	_sh_ed = _check(v, "Sebepoškozování a poruchy příjmu potravy (jen přes emoce a vztahy; zatím ve hře nejsou)")
	_sh_ed.toggled.connect(func(on: bool): _apply("sh_ed_topics", on))
	_adult_intimacy = _check(v, "Dobrovolná intimita dospělých (neexplicitní; výchozí vypnuto)")
	_adult_intimacy.toggled.connect(func(on: bool): _apply("adult_intimacy", on))
	v.add_child(HSeparator.new())
	v.add_child(_crisis_box())
	v.add_child(HSeparator.new())
	var row2 := VBoxContainer.new()
	row2.add_theme_constant_override("separation", 5)
	v.add_child(row2)
	var warn := Button.new()
	warn.text = "Znovu zobrazit upozornění"
	warn.pressed.connect(func():
		_menu.visible = false
		_warning.visible = true)
	row2.add_child(warn)
	var reset := Button.new()
	reset.text = "Výchozí"
	reset.pressed.connect(func():
		if _settings != null:
			var ack: bool = bool(_settings.get_value("warning_ack"))
			_settings.reset()
			_settings.set_value("warning_ack", ack)
		_sync_from_settings())
	row2.add_child(reset)
	var close := Button.new()
	close.text = "Zavřít (Esc)"
	close.pressed.connect(func(): _menu.visible = false)
	row2.add_child(close)


func _option(parent: Control, title: String, items: Array) -> OptionButton:
	parent.add_child(_label(title, 14))
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.clip_text = true
	o.fit_to_longest_item = false
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(o)
	return o


func _check(parent: Control, title: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = title
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(c)
	return c


func _apply(key: String, v: Variant) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_value(key, v)


func _sync_from_settings() -> void:
	if _settings == null:
		return
	_syncing = true
	_mh.select(maxi(["full", "muted", "off"].find(String(_settings.get_value("mental_health"))), 0))
	_thoughts.select(clampi(int(_settings.get_value("intrusive_thoughts")), 0, 3))
	_fx.button_pressed = bool(_settings.get_value("distortion_fx"))
	_fx_strength.value = float(_settings.get_value("distortion_strength"))
	_addiction.button_pressed = bool(_settings.get_value("addiction"))
	_audio_enabled.button_pressed = bool(_settings.get_value("audio_enabled"))
	_profanity.button_pressed = bool(_settings.get_value("profanity"))
	if _voices != null:
		_voices.select(maxi(VOICE_IDS.find(String(_settings.get_value("character_voices"))), 0))
	_sh_ed.button_pressed = bool(_settings.get_value("sh_ed_topics"))
	_adult_intimacy.button_pressed = bool(_settings.get_value("adult_intimacy"))
	_syncing = false


func _unhandled_input(event: InputEvent) -> void:
	# Když je menu otevřené, klávesy nejdou do hry (kromě Esc, který menu zavře).
	if is_open() and event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE:
		get_viewport().set_input_as_handled()