extends CanvasLayer
## HUD: čas a rychlost, panel vybrané postavy (potřeby, nálada, pocity, vztahy, paměť),
## nabídka příkazů pro ovládanou postavu, chat a seznam hráčů v multiplayeru.
## Data postavy bere z `hud_info()` – funguje stejně pro SimAgent (server/offline)
## i SimPuppet (klient).

const Needs := preload("res://scripts/sim/needs.gd")
const CharacterEditorPanel := preload("res://scripts/ui/character_editor_panel.gd")
const CharacterCreatorPanel := preload("res://scripts/ui/character_creator_panel.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const EmotionalState := preload("res://scripts/sim/emotional_state.gd")
const THOUGHT_SHOW_MINUTES := 240.0

const CHAT_LINES := 8
const NOTICE_TIME := 4.0

var main: Node
var _time_label: Label
var _speed_label: Label
var _name_label: Label
var _edit_button: Button
var _create_button: Button
var _anatomy_button: Button
const ANATOMY_DISPLAY := ["off","bones","muscles","cartilage","fat","all"]
const ANATOMY_LABELS := ["Vypnuto","Kostra","Svaly","Chrupavky","Tuk","Všechny vrstvy"]
var _character_creator: Control
var _save_button: Button
var _load_auto_button: Button
var _load_manual_button: Button
var _character_editor: Control
var _info_label: Label
var _bars := {}
var _moodlet_label: Label
var _rel_label: Label
var _mem_label: Label
var _mind_label: Label
var _stress_bar: ProgressBar
var _arousal_bar: ProgressBar
var _sexual_arousal_label: Label
var _intimacy_fade: ColorRect
var _emotion_button: Button
var _emotion_popup: PopupPanel
var _emotion_bars: Dictionary = {}
var _emotion_top: Label
var _emotion_people: Label
var _thought_box: VBoxContainer
var _thought_seen := ""
var _cmd_title: Label
var _cmd_list: ItemList
var _chat_panel: PanelContainer
var _chat_log: Label
var _chat_edit: LineEdit
var _roster_label: Label
var _notice_label: Label
var _refresh := 0.0
var _notice_left := 0.0
var _cmd_for := ""
var _cmd_refresh := 0.0


func _ready() -> void:
	# A genuine non-explicit fade covers the 3D world, not the cancelable HUD.
	# This is visible only to the selected offline player.
	_intimacy_fade = ColorRect.new()
	_intimacy_fade.name = "PrivateIntimacyFade"
	_intimacy_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intimacy_fade.color = Color(0, 0, 0, 0.96)
	_intimacy_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intimacy_fade.visible = false
	add_child(_intimacy_fade)
	var top := PanelContainer.new()
	top.position = Vector2(16, 16)
	add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 22)
	tv.add_child(_time_label)
	_speed_label = Label.new()
	tv.add_child(_speed_label)
	var help := Label.new()
	help.text = "Mezerník pauza · 1–4 rychlost · P nouzová pauza · Tab další postava · F zaměřit · WASD/QE kamera · Enter chat"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	tv.add_child(help)
	_roster_label = Label.new()
	_roster_label.add_theme_font_size_override("font_size", 13)
	tv.add_child(_roster_label)

	var panel := PanelContainer.new()
	panel.name = "NeedsAndCommandsPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -340
	panel.offset_right = -16
	panel.offset_top = 16
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -16
	add_child(panel)
	# The needs/action panel must remain usable in a portrait or small window.
	# Keep commands reachable by scrolling instead of clipping below the screen.
	var controls_scroll := ScrollContainer.new()
	controls_scroll.name = "ControlsScroll"
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(controls_scroll)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_scroll.add_child(v)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	v.add_child(_name_label)
	_edit_button = Button.new()
	_edit_button.name = "EditCharacter"
	_edit_button.text = "Upravit postavu"
	_edit_button.pressed.connect(_on_edit_character)
	v.add_child(_edit_button)
	_create_button = Button.new()
	_create_button.name = "CreateNewCharacter"
	_create_button.text = "Vytvořit vlastní postavu"
	_create_button.pressed.connect(_on_create_character)
	v.add_child(_create_button)
	# The very same animated SimVisual object used by the in-game character,
	# not a static gallery. Purely local visualization, never server commands.
	_anatomy_button = Button.new()
	_anatomy_button.name = "LiveCharacterAnatomy"
	_anatomy_button.text = "Anatomie: Vypnuto"
	_anatomy_button.tooltip_text = "Vizuální vrstvy z Blenderu. Animované s postavou; bez změny hry a fyziky."
	_anatomy_button.pressed.connect(_on_anatomy_view)
	v.add_child(_anatomy_button)
	var save_actions := HBoxContainer.new()
	v.add_child(save_actions)
	_save_button = Button.new()
	_save_button.name = "SaveGame"
	_save_button.text = "Uložit hru"
	_save_button.pressed.connect(_on_save_game)
	save_actions.add_child(_save_button)
	_load_auto_button = Button.new()
	_load_auto_button.name = "LoadAutosave"
	_load_auto_button.text = "Načíst auto"
	_load_auto_button.pressed.connect(_on_load_autosave)
	save_actions.add_child(_load_auto_button)
	_load_manual_button = Button.new()
	_load_manual_button.name = "LoadManual"
	_load_manual_button.text = "Načíst ručně"
	_load_manual_button.pressed.connect(_on_load_manual)
	save_actions.add_child(_load_manual_button)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info_label)
	for k in Needs.KEYS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = Needs.LABELS[k]
		l.custom_minimum_size = Vector2(100, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		v.add_child(row)
		_bars[k] = bar
	# Duševní stav (soukromý – jen vlastní postava)
	_mind_label = Label.new()
	_mind_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_mind_label)
	_stress_bar = _make_bar(v, "Stres")
	_arousal_bar = _make_bar(v, "Aktivace")
	_sexual_arousal_label = Label.new()
	_sexual_arousal_label.text = "Sexuální vzrušení: —"
	_sexual_arousal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sexual_arousal_label)
	_make_emotion_details(v)
	_moodlet_label = Label.new()
	_moodlet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_moodlet_label)
	_rel_label = Label.new()
	_rel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rel_label)
	_mem_label = Label.new()
	_mem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mem_label.add_theme_font_size_override("font_size", 12)
	v.add_child(_mem_label)
	_cmd_title = Label.new()
	_cmd_title.text = "Příkazy"
	v.add_child(_cmd_title)
	_cmd_list = ItemList.new()
	_cmd_list.custom_minimum_size = Vector2(300, 180)
	_cmd_list.item_activated.connect(_on_cmd_activated)
	_cmd_list.item_clicked.connect(func(idx: int, _pos: Vector2, _btn: int): _on_cmd_activated(idx))
	v.add_child(_cmd_list)

	# Chat (jen v multiplayeru)
	_chat_panel = PanelContainer.new()
	_chat_panel.anchor_top = 1.0
	_chat_panel.anchor_bottom = 1.0
	_chat_panel.offset_left = 16
	_chat_panel.offset_right = 476
	_chat_panel.offset_top = -230
	_chat_panel.offset_bottom = -16
	add_child(_chat_panel)
	var cv := VBoxContainer.new()
	_chat_panel.add_child(cv)
	_chat_log = Label.new()
	_chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_chat_log.add_theme_font_size_override("font_size", 13)
	cv.add_child(_chat_log)
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "Napiš zprávu a stiskni Enter…"
	_chat_edit.max_length = 200
	_chat_edit.text_submitted.connect(_on_chat_submitted)
	cv.add_child(_chat_edit)

	# Rušivé myšlenky – vlevo uprostřed, vždy označené jako myšlenka, ne fakt.
	_thought_box = VBoxContainer.new()
	_thought_box.anchor_top = 0.5
	_thought_box.anchor_bottom = 0.5
	_thought_box.offset_left = 24
	_thought_box.offset_right = 520
	_thought_box.offset_top = -120
	_thought_box.offset_bottom = 60
	_thought_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_thought_box)

	_notice_label = Label.new()
	_notice_label.anchor_left = 0.5
	_notice_label.anchor_right = 0.5
	_notice_label.offset_left = -300
	_notice_label.offset_right = 300
	_notice_label.offset_top = 24
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 18)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	add_child(_notice_label)

	if main != null and main.net != null:
		main.net.chat_received.connect(_on_chat)
		main.net.notice.connect(show_notice)
		main.net.disconnected.connect(show_notice)


func _on_anatomy_view() -> void:
	if main == null:
		return
	var sim = main.get_selected_sim()
	if sim == null:
		return
	var vis := sim.get("visual") as Node3D
	if vis == null or not vis.has_method("set_anatomy_view"):
		show_notice("Vybraná postava nemá anatomický náhled.")
		return
	var idx: int = ANATOMY_DISPLAY.find(String(vis.call("anatomy_view")))
	if idx < 0:
		idx = 0
	var next: String = ANATOMY_DISPLAY[(idx+1)%ANATOMY_DISPLAY.size()]
	if not bool(vis.call("set_anatomy_view",next)):
		show_notice("Anatomická data nebo kostra této postavy nejsou dostupné.")
		return
	_anatomy_button.text = "Anatomie: " + String(ANATOMY_LABELS[(idx+1)%ANATOMY_DISPLAY.size()])


func _on_create_character() -> void:
	if main == null or main.net == null or main.net.mode != main.net.Mode.OFFLINE:
		show_notice("Vytvoření postavy je zatím pouze offline.")
		return
	if (_character_creator != null and is_instance_valid(_character_creator)) or (_character_editor != null and is_instance_valid(_character_editor)):
		return
	var creator: Control = CharacterCreatorPanel.new()
	creator.main = main
	add_child(creator)
	_character_creator = creator


func _on_edit_character() -> void:
	if main == null or main.net == null:
		show_notice("Editor není dostupný.")
		return
	var is_client_owner: bool = main.net.mode == main.net.Mode.CLIENT and main.net.character_edit_read_ui_enabled
	var is_host_owner: bool = main.net.mode == main.net.Mode.HOST and main.net.character_edit_apply_rpc_enabled and main.get_selected_sim() != null and main.net.server_can_edit_character(1, String(main.get_selected_sim().name))
	if main.net.is_networked() and not (is_client_owner or is_host_owner):
		show_notice("Editor je zatím dostupný pouze offline.")
		return
	var sim = main.get_selected_sim()
	if sim == null or is_instance_valid(_character_editor):
		return
	var editor: Control = CharacterEditorPanel.new()
	editor.main = main
	add_child(editor)
	var opened: bool = editor.open_network_character(String(sim.name)) if main.net.mode == main.net.Mode.CLIENT else editor.open_character(String(sim.name))
	if not opened:
		editor.queue_free()
		show_notice("Úprava této postavy není povolena.")
	else:
		_character_editor = editor


func _on_save_game() -> void:
	var result: Dictionary = main.save_game("manual")
	show_notice("Hra uložena." if result.get("ok", false) else "Ukládání selhalo: " + String(result.get("reason", "")))


func _on_load_autosave() -> void:
	var result: Dictionary = main.load_game("autosave")
	show_notice("Automatické uložení načteno." if result.get("ok", false) else "Načítání selhalo: " + String(result.get("reason", "")))


func _on_load_manual() -> void:
	var result: Dictionary = main.load_game("manual")
	show_notice("Ruční uložení načteno." if result.get("ok", false) else "Načítání selhalo: " + String(result.get("reason", "")))


## The full 19-axis panel is optional and scrollable, not 19 permanently
## expanded bars competing with commands in the main HUD.
func _make_emotion_details(v: VBoxContainer) -> void:
	_emotion_button = Button.new()
	_emotion_button.name = "EmotionDetailsButton"
	_emotion_button.text = "Emoce – 19 ukazatelů ▸"
	_emotion_button.pressed.connect(_on_emotion_details)
	_emotion_button.visible = false
	v.add_child(_emotion_button)
	_emotion_popup = PopupPanel.new()
	_emotion_popup.name = "PrivateEmotionDetails"
	add_child(_emotion_popup)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(220.0, 300.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_emotion_popup.add_child(sc)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 220.0
	sc.add_child(box)
	var title := Label.new()
	title.text = "Aktuální emoce (0–100)"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	_emotion_top = Label.new()
	_emotion_top.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_emotion_top)
	for k in EmotionalState.KEYS:
		var emotion_bar := _make_bar(box, EmotionalState.label(k))
		emotion_bar.show_percentage = true
		emotion_bar.custom_minimum_size.x = 114.0
		var caption: Label = emotion_bar.get_parent().get_child(0)
		caption.custom_minimum_size.x = 96.0
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_emotion_bars[k] = emotion_bar
	_emotion_people = Label.new()
	_emotion_people.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_emotion_people)


## The popup remains inside smaller portrait viewports without 19 bars on HUD.
static func emotion_popup_size(viewport: Vector2) -> Vector2i:
	return Vector2i(maxi(1, mini(410, int(viewport.x) - 16)),
		maxi(1, mini(560, int(viewport.y) - 16)))


func _on_emotion_details() -> void:
	if main == null or main.net == null or main.net.is_networked() \
			or not _emotion_button.visible:
		return
	if _emotion_popup.visible:
		_emotion_popup.hide()
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_emotion_popup.popup_centered(emotion_popup_size(vp))


func _render_emotion_details(info: Dictionary) -> void:
	var data: Dictionary = info.get("emotion_levels", {})
	if data.is_empty():
		_emotion_top.text = ""
		return
	var ordered: Array = []
	for k in EmotionalState.KEYS:
		var value: float = clampf(float(data.get(k, 0.0)), 0.0, 100.0)
		(_emotion_bars[k] as ProgressBar).value = value
		ordered.append({"k": k, "v": value})
	ordered.sort_custom(func(a, b): return float(a["v"]) > float(b["v"]))
	var names := PackedStringArray()
	for x in ordered.slice(0, 3):
		names.append("%s %.0f" % [EmotionalState.label(String(x["k"])), float(x["v"])])
	_emotion_top.text = "Nejsilnější: " + ", ".join(names)
	var people := PackedStringArray()
	for record in info.get("emotion_toward", []):
		if typeof(record) != TYPE_DICTIONARY:
			continue
		people.append("%s: %s %.0f" % [
			String(record.get("who", "")).replace("_", " "),
			String(record.get("label", "")), float(record.get("value", 0.0))])
	_emotion_people.text = "Vůči lidem:\n" + (
		"\n".join(people) if not people.is_empty() else "bez výrazného aktuálního podnětu")


func _make_bar(parent: Control, title: String) -> ProgressBar:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(100, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	parent.add_child(row)
	return bar


## Texty myšlenek k zobrazení podle nastavení TOHOTO hráče. Vrací [[text, stáří_min]].
static func visible_thoughts(mind: Dictionary, now: float, settings: Node) -> Array:
	var out: Array = []
	if settings != null and (int(settings.get_value("intrusive_thoughts")) <= 0 or settings.mental_health_mode() == "off"):
		return out
	for th in mind.get("thoughts", []):
		if typeof(th) != TYPE_ARRAY or th.size() < 2:
			continue
		var age: float = now - float(th[0])
		if age < 0.0 or age > THOUGHT_SHOW_MINUTES:
			continue
		var txt := String(th[1])
		if settings != null:
			txt = settings.filter_profanity(txt)
		out.append([txt, age])
	return out


## Jak se myšlenka zobrazí: subjektivní interpretace, ne pravda o světě.
static func format_thought(text: String) -> String:
	return "„%s“\n   — myšlenka, ne fakt" % text


func _render_thoughts(mind: Dictionary) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	var items := visible_thoughts(mind, main.clock.total_minutes, gs)
	var sig := str(items.map(func(it): return it[0]))
	if sig == _thought_seen:
		# Jen doznívání (průhlednost podle stáří).
		for i in mini(items.size(), _thought_box.get_child_count()):
			_thought_box.get_child(i).modulate.a = clampf(1.0 - float(items[i][1]) / THOUGHT_SHOW_MINUTES, 0.25, 0.9)
		return
	_thought_seen = sig
	for c in _thought_box.get_children():
		c.queue_free()
	for it in items:
		var l := Label.new()
		l.text = format_thought(String(it[0]))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.78, 0.72, 0.95))
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1))
		l.add_theme_constant_override("outline_size", 6)
		l.modulate.a = clampf(1.0 - float(it[1]) / THOUGHT_SHOW_MINUTES, 0.25, 0.9)
		_thought_box.add_child(l)


func focus_chat() -> void:
	if _chat_panel.visible and not _chat_edit.has_focus():
		_chat_edit.grab_focus()


func show_notice(text: String) -> void:
	_notice_label.text = text
	_notice_left = NOTICE_TIME


func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() != "" and main != null:
		main.net.send_chat(text)
	_chat_edit.clear()
	_chat_edit.release_focus()


func _on_chat(_from: String, _text: String, _system: bool) -> void:
	_render_chat()


func _render_chat() -> void:
	var lines: PackedStringArray = []
	var entries: Array = main.net.chat_log
	for i in range(maxi(entries.size() - CHAT_LINES, 0), entries.size()):
		var e: Array = entries[i]
		if bool(e[2]):
			lines.append("• " + String(e[1]))
		else:
			lines.append("%s: %s" % [e[0], e[1]])
	_chat_log.text = "\n".join(lines)


# ---------------------------------------------------------------- příkazy

func _rebuild_commands(sim) -> void:
	_cmd_list.clear()
	if sim == null:
		_cmd_title.text = "Příkazy"
		return
	var node_name := String(sim.name)
	if not main.net.can_control(node_name):
		_cmd_title.text = "Příkazy (tuhle postavu neovládáš)"
		return
	_cmd_title.text = "Příkazy pro: " + sim.first_name()
	_add_cmd("✕ Zrušit, co dělá", ["cancel", ""])
	var gs := get_node_or_null("/root/GameSettings")
	# V multiplayeru o dostupnosti rozhoduje server; klient skrývá jen podle svého nastavení
	# (kdyby se lišilo, server příkaz odmítne s vysvětlením).
	var mind: Dictionary = sim.hud_info().get("mind", {})
	var hard := int(mind.get("aversive_arousal", mind.get("arousal", 0))) > 50
	# V depresi jsou náročnější akce „těžké“ – zůstávají dostupné, jen to hráč vidí.
	var heavy := int(mind.get("low", 0)) > 45
	var objs: Array = main.get_smart_objects()
	for i in objs.size():
		var o = objs[i]
		for a in ActionLibrary.ACTIONS:
			if a.get("object", "") == o.object_tag and _cmd_allowed(a, gs):
				_add_cmd("%s – %s%s" % [o.display_name, a["label"], heavy_hint(a, heavy)], [a["id"], i])
	var social_hint := "  (náročné – úzkost)" if hard else ""
	for other in main.get_sims():
		if other == sim:
			continue
		_add_cmd("Povídat si: " + other.sim_name + social_hint, ["chat", String(other.name)])
		_add_cmd("Svěřit se: " + other.sim_name, ["confide", String(other.name)])
		if _cmd_allowed(ActionLibrary.get_action("comfort_panic"), gs) and other.display_action() == "Panická ataka":
			_add_cmd("Jít uklidnit: " + other.sim_name, ["comfort_panic", String(other.name)])
		_add_cmd("Omluvit se: " + other.sim_name, ["apologize", String(other.name)])
		_add_cmd("Urazit: " + other.sim_name, ["insult", String(other.name)])
		for pressure_id in ["reproach", "guilt_trip", "blame_shift", "emotional_blackmail", "stonewalling"]:
			var pressure_action: Dictionary = ActionLibrary.get_action(pressure_id)
			if _cmd_allowed(pressure_action, gs):
				_add_cmd(String(pressure_action["label"]) + ": " + other.sim_name, [pressure_id, String(other.name)])
		if _cmd_allowed(ActionLibrary.get_action("intimacy_offer"), gs):
			_add_cmd("Projevit intimní zájem: " + other.sim_name, ["intimacy_offer", String(other.name)])
			_add_cmd("Odvolat souhlas: " + other.sim_name, ["intimacy_withdraw", String(other.name)])
			_add_cmd("Soukromá intimní chvíle: " + other.sim_name, ["adult_consensual_sex", String(other.name)])
	for a in ActionLibrary.ACTIONS:
		if a.get("object", "") == "" and _cmd_allowed(a, gs):
			_add_cmd(a["label"] + heavy_hint(a, heavy), [a["id"], ""])


## Nápověda u náročných akcí v depresi (bez čísel – jen „teď je to těžké“).
static func heavy_hint(a: Dictionary, heavy: bool) -> String:
	return "  (teď těžké se k tomu dokopat)" if heavy and ActionLibrary.effort(a) >= 0.5 else ""


static func _cmd_allowed(a: Dictionary, gs: Node) -> bool:
	if a.is_empty() or bool(a.get("involuntary", false)) or bool(a.get("system", false)):
		return false
	return gs == null or gs.allows_content(String(a.get("content", "")))


func _add_cmd(text: String, meta: Array) -> void:
	var idx := _cmd_list.add_item(text)
	_cmd_list.set_item_metadata(idx, meta)


func _on_cmd_activated(idx: int) -> void:
	var sim = main.get_selected_sim()
	if sim == null:
		return
	var meta: Array = _cmd_list.get_item_metadata(idx)
	main.net.request_command(String(sim.name), meta[0], meta[1])
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_ui("ui_click")


# ---------------------------------------------------------------- obnova

func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice_label.text = ""
	_refresh -= delta
	if _refresh > 0.0 or main == null:
		return
	_refresh = 0.2
	var clock = main.clock
	_time_label.text = "%s · %s" % [clock.time_string(), clock.phase_name()]
	_speed_label.text = "Rychlost: " + clock.SPEED_NAMES[clock.speed_index]
	_chat_panel.visible = main.net.is_networked()
	_edit_button.visible = not main.net.is_networked() or (main.net.character_edit_read_ui_enabled and main.net.mode == main.net.Mode.CLIENT and main.get_selected_sim() != null and String(main.get_selected_sim().name) == main.net.my_sim) or (main.net.mode == main.net.Mode.HOST and main.net.character_edit_apply_rpc_enabled and main.get_selected_sim() != null and main.net.server_can_edit_character(1, String(main.get_selected_sim().name)))
	_edit_button.disabled = main.get_selected_sim() == null
	for button in [_save_button, _load_auto_button, _load_manual_button]:
		button.visible = not main.net.is_networked()
		button.disabled = main.get_selected_sim() == null
	_render_roster()
	var sim = main.get_selected_sim()
	_anatomy_button.visible = false
	if sim != null:
		var anatomy_visual := sim.get("visual") as Node3D
		if anatomy_visual != null and anatomy_visual.has_method("anatomy_available") and 				bool(anatomy_visual.call("anatomy_available")):
			_anatomy_button.visible = true
			var view_idx: int = ANATOMY_DISPLAY.find(String(anatomy_visual.call("anatomy_view")))
			_anatomy_button.text = "Anatomie: " + String(ANATOMY_LABELS[maxi(0,view_idx)])
	_intimacy_fade.visible = not main.net.is_networked() and sim != null \
		and String(sim.current_action.get("id", "")) == "adult_consensual_sex" \
		and sim.state == sim.State.ACTING
	_cmd_refresh -= 0.2
	var key := String(sim.name) if sim != null else ""
	if key != _cmd_for or _cmd_refresh <= 0.0:
		_cmd_for = key
		_cmd_refresh = 3.0
		_rebuild_commands(sim)
	if sim == null:
		_name_label.text = "Čekám na postavy…"
		_emotion_button.visible = false
		_emotion_popup.hide()
		return
	var info: Dictionary = sim.hud_info()
	_name_label.text = String(info.get("name", ""))
	if main.net.is_networked() and key == main.net.my_sim:
		_name_label.text += " (ty)"
	var q := int(info.get("queue", 0))
	_info_label.text = "Povaha: %s\nNálada: %s (%+d)\nDělá: %s%s" % [
		Traits.labels(info.get("traits", [])), Mood.emotion_label(String(info.get("emotion", ""))),
		int(info.get("mood", 0.0)), String(info.get("action", "")),
		("\nVe frontě příkazů: %d" % q) if q > 0 else ""]
	# Soukromé údaje (potřeby, pocity, vztahy, vzpomínky) jen u vlastní postavy – i hostitel,
	# který má na serveru všechno, vidí v multiplayeru detail jen té své (férovost, intriky).
	var show_private: bool = bool(info.get("private", false)) and (not main.net.is_networked() or key == main.net.my_sim)
	for k in _bars:
		_bars[k].get_parent().visible = show_private
	_stress_bar.get_parent().visible = show_private
	_arousal_bar.get_parent().visible = show_private
	_sexual_arousal_label.visible = show_private and not main.net.is_networked() \
		and typeof(info.get("sexual_arousal")) in [TYPE_FLOAT, TYPE_INT]
	if _sexual_arousal_label.visible:
		_sexual_arousal_label.text = "Sexuální vzrušení: %.0f/100 · Libido: %.0f/100\nNutkavé myšlenky: %.0f/100 (není diagnóza)" % [
			float(info["sexual_arousal"]), float(info.get("libido", 0.5)) * 100.0,
			float(info.get("sexual_preoccupation", 0.0))]
	# The new raw emotional vector NEVER crosses the multiplayer detail RPC.
	# Even the host cannot inspect another player's emotion panel.
	_emotion_button.visible = show_private and not main.net.is_networked() \
		and typeof(info.get("emotion_levels")) == TYPE_DICTIONARY
	if not _emotion_button.visible:
		_emotion_popup.hide()
	if not show_private:
		_mind_label.text = ""
		_render_thoughts({})
		_moodlet_label.text = "Pocity: soukromé"
		_rel_label.text = "Vztahy: soukromé – vidí je jen hráč, který postavu ovládá"
		_mem_label.text = ""
		return
	var nv: Dictionary = info.get("needs", {})
	for k in _bars:
		var bar: ProgressBar = _bars[k]
		var val: float = float(nv.get(k, 0.0))
		bar.value = val
		bar.modulate = Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.35), val / 100.0)
	var mind: Dictionary = info.get("mind", {})
	var st := float(mind.get("stress", 0))
	var ar := float(mind.get("arousal", 0))
	_stress_bar.value = st
	_stress_bar.modulate = Color(0.35, 0.75, 0.45).lerp(Color(0.9, 0.3, 0.2), st / 100.0)
	_arousal_bar.value = ar
	_arousal_bar.modulate = Color(0.45, 0.6, 0.85).lerp(Color(0.62, 0.35, 0.85), ar / 100.0)
	var extra: PackedStringArray = []
	if String(mind.get("day", "")) != "":
		extra.append(String(mind["day"]))
	var conds: Array = mind.get("conditions", [])
	if not conds.is_empty():
		extra.append("predispozice: " + ", ".join(PackedStringArray(conds)))
	_mind_label.text = "Duševní stav: %s%s" % [String(mind.get("label", "—")),
		(" (" + "; ".join(extra) + ")") if not extra.is_empty() else ""]
	# Only offline SimAgent.hud_info supplies this non-replicated private care hint.
	var care: Dictionary = info.get("care", {})
	if bool(care.get("safety_concern", false)):
		_mind_label.text += "\nZvýšená zátěž – může potřebovat bezpečí a podporu."
	elif bool(care.get("support_needed", false)):
		_mind_label.text += "\nMůže potřebovat oporu."
	# Rozšíření psychiky: jen slova, jen offline vlastník (hud_info je nepřenáší po síti).
	for line in info.get("psyche_lines", PackedStringArray()):
		_mind_label.text += "\n" + String(line)
	_render_thoughts(mind)
	if _emotion_button.visible:
		_render_emotion_details(info)
	var ml: PackedStringArray = []
	for m in info.get("moodlets", []):
		ml.append("%s %+d" % [m[0], int(m[1])])
	_moodlet_label.text = "Pocity: " + (", ".join(ml) if not ml.is_empty() else "—")
	var rl: PackedStringArray = []
	var rel: Dictionary = info.get("rel", {})
	var grudge: Dictionary = info.get("grudge", {}) if typeof(info.get("grudge")) == TYPE_DICTIONARY else {}
	# Bond/dependency is a private per-person value; never put it into net_detail
	# or call a local server-only method on network SimPuppets.
	var attachments: Dictionary = {}
	if not main.net.is_networked() and sim.has_method("private_attachment_labels"):
		attachments = sim.private_attachment_labels()
	for n in rel:
		var bond_text := (" · " + String(attachments[n])) if attachments.has(n) else ""
		rl.append("%s %+d%s%s" % [String(n).split(" ")[0], int(rel[n]), " (křivda)" if grudge.has(n) else "", bond_text])
	_rel_label.text = "Vztahy: " + (", ".join(rl) if not rl.is_empty() else "—")
	var mem: PackedStringArray = []
	var mems: Array = info.get("mem", [])
	for i in range(mems.size() - 1, -1, -1):
		var tm := float(mems[i][0])
		mem.append("den %d %02d:%02d – %s" % [int(tm / 1440.0) + 1, int(fmod(tm, 1440.0) / 60.0), int(fmod(tm, 60.0)), mems[i][1]])
	_mem_label.text = "Vzpomínky:\n" + ("\n".join(mem) if not mem.is_empty() else "—")


func _render_roster() -> void:
	var net = main.net
	if not net.is_networked():
		_roster_label.text = ""
		return
	var lines: PackedStringArray = ["Režim: " + net.mode_name()]
	for pid in net.roster:
		var p: Dictionary = net.roster[pid]
		var sim_txt := String(p.get("sim", ""))
		var s = main.find_sim(sim_txt)
		lines.append("  %s → %s (hlas: %s)" % [p.get("name", "?"),
			s.sim_name if s != null else "divák", main.clock.SPEED_NAMES[clampi(int(p.get("vote", 1)), 0, 4)]])
	_roster_label.text = "\n".join(lines)