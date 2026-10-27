extends Control
## Transactional offline and authenticated owner-only native ENet editor.
## Private reads, correlated Apply and canonical private readback are owner-only;
## only validated public appearance changes are broadcast to other players.
const Session := preload("res://scripts/character/character_edit_session.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const SliderEditor := preload("res://scripts/ui/personality_slider_editor.gd")
const AppearanceEditor := preload("res://scripts/ui/appearance_slider_editor.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")
const Wardrobe := preload("res://scripts/assets/subculture_wardrobe.gd")
const Schema := preload("res://scripts/character/character_schema.gd")

var main: Node
var _session := Session.new()
var _target := ""
var _revision := -1
var _status: Label
var _preview: Label
var _visual_preview: VBoxContainer
var _sliders: VBoxContainer
var _appearance: VBoxContainer
var _sexuality_section: VBoxContainer
var _sexuality_controls: Dictionary = {}
var _style: OptionButton
var _slot: OptionButton
var _item_buttons: Dictionary = {}
var _undo_button: Button
var _redo_button: Button
var _network_read := false
var _host_session := false
var _read_token := ""
var _read_net: Node
var _body_scroll: ScrollContainer
var _title: Label
var _help: Label
var _apply_button: Button
var _apply_token := ""
var _apply_deadline_ms := 0
var _await_readback := false
var _canonical_revision := -1
var _reopen_required := false

func _ready() -> void:
    name = "CharacterEditorPanel"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var shade := ColorRect.new()
    shade.color = Color(0.04, 0.05, 0.08, 0.9)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(shade)
    var panel := PanelContainer.new()
    panel.anchor_left = 0.03
    panel.anchor_top = 0.05
    panel.anchor_right = 0.97
    panel.anchor_bottom = 0.95
    add_child(panel)
    var layout := VBoxContainer.new()
    panel.add_child(layout)
    var title := Label.new()
    _title = title
    title.text = "Úprava postavy — pouze offline"
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    title.add_theme_font_size_override("font_size", 22)
    layout.add_child(title)
    var help := Label.new()
    _help = help
    help.text = "Změny zůstávají v návrhu až do Použít. Jméno/rod a síťové úpravy jsou uzamčené; soukromou sexualitu lze nastavit offline."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(help)
    var body_scroll := ScrollContainer.new()
    _body_scroll = body_scroll
    body_scroll.name = "EditorBody"
    body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(body_scroll)
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_scroll.add_child(body)
    _visual_preview = Preview.new()
    body.add_child(_visual_preview)
    _appearance = AppearanceEditor.new()
    _appearance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _appearance.appearance_changed.connect(_on_appearance_changed)
    body.add_child(_appearance)
    body.add_child(HSeparator.new())
    var row := VBoxContainer.new()
    body.add_child(row)
    var label := Label.new()
    label.text = "Styl oblečení:"
    row.add_child(label)
    var choices := HBoxContainer.new()
    row.add_child(choices)
    _style = OptionButton.new()
    _style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _style.add_item("Vyber styl…", -1)
    for key in Wardrobe.names():
        _style.add_item(String(Wardrobe.STYLES[key]["label"]))
        _style.set_item_metadata(_style.item_count - 1, String(key))
    _style.item_selected.connect(_on_style_selected)
    choices.add_child(_style)
    _slot = OptionButton.new()
    for slot in ["bezne", "pracovni", "spolecenske", "spani", "sport"]:
        _slot.add_item(slot)
    choices.add_child(_slot)
    _slot.item_selected.connect(_on_slot_selected)
    var garment_row := VBoxContainer.new()
    garment_row.name = "GarmentSelectors"
    row.add_child(garment_row)
    for entry in [["top", "Vrchní díl", Schema.TOPS], ["bottom", "Spodní díl", Schema.BOTTOMS], ["shoes", "Obuv", Schema.SHOES]]:
        var line := HBoxContainer.new()
        garment_row.add_child(line)
        var caption := Label.new()
        caption.text = String(entry[1]) + ":"
        caption.custom_minimum_size.x = 96
        line.add_child(caption)
        var picker := OptionButton.new()
        picker.name = "Garment_" + String(entry[0])
        picker.fit_to_longest_item = false
        picker.clip_text = true
        picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var catalog: Dictionary = entry[2]
        for id in catalog:
            picker.add_item(String(catalog[id]))
            picker.set_item_metadata(picker.item_count - 1, String(id))
        picker.item_selected.connect(_on_item_selected.bind(String(entry[0])))
        line.add_child(picker)
        _item_buttons[String(entry[0])] = picker
    _sliders = SliderEditor.new()
    _sliders.custom_minimum_size = Vector2(0, 420)
    _sliders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sliders.character_changed.connect(_on_slider_changed)
    body.add_child(_sliders)
    _sexuality_section = VBoxContainer.new()
    _sexuality_section.name = "PrivateSexuality"
    body.add_child(HSeparator.new())
    body.add_child(_sexuality_section)
    var stitle := Label.new()
    stitle.text = "Sexualita a přitažlivost (soukromé údaje)"
    stitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stitle.add_theme_font_size_override("font_size", 17)
    _sexuality_section.add_child(stitle)
    var sub := Label.new()
    sub.text = "Asexualita není nulové libido. Vysoké libido samo o sobě není porucha. Intimní akce vždy vyžaduje souhlas obou dospělých."
    sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sexuality_section.add_child(sub)
    for entry in [["asexual", "Asexuální přitažlivost"], ["aromantic", "Aromantická přitažlivost"]]:
        var cb := CheckBox.new()
        cb.name = "Sexual_" + String(entry[0])
        cb.text = String(entry[1])
        cb.toggled.connect(_on_sexual_bool.bind(String(entry[0])))
        _sexuality_section.add_child(cb)
        _sexuality_controls[String(entry[0])] = cb
    var cap := Label.new()
    cap.text = "Sexuální přitažlivost k (nevybráno = neurčeno):"
    cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sexuality_section.add_child(cap)
    for group in Schema.ATTRACTION.keys():
        var opt := CheckBox.new()
        opt.name = "SexualAttraction_" + String(group)
        opt.text = String(Schema.ATTRACTION[group])
        opt.toggled.connect(_on_sexual_target.bind(String(group)))
        _sexuality_section.add_child(opt)
        _sexuality_controls["target_" + String(group)] = opt
    # Quick spectrum for binary-identified characters. Existing separate
    # attraction checkboxes remain the canonical private representation.
    var orientation_caption := Label.new()
    orientation_caption.text = "Sexuální orientace: hetero — bi — homo (rychlá volba)"
    orientation_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sexuality_section.add_child(orientation_caption)
    var orientation_slider := HSlider.new()
    orientation_slider.name = "SexualOrientationSpectrum"
    orientation_slider.min_value = 0.0
    orientation_slider.max_value = 1.0
    orientation_slider.step = 0.5
    orientation_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    orientation_slider.custom_minimum_size.x = 140
    orientation_slider.value_changed.connect(_on_orientation_spectrum)
    _sexuality_section.add_child(orientation_slider)
    var orientation_value := Label.new()
    orientation_value.name = "SexualOrientationLabel"
    orientation_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sexuality_section.add_child(orientation_value)
    _sexuality_controls["orientation_spectrum"] = orientation_slider
    _sexuality_controls["orientation_label"] = orientation_value
    for entry in [["libido", "Libido (nízké až vysoké)"],
            ["drive_dysregulation", "Nutkavé zaujetí (není diagnóza)"]]:
        var line := HBoxContainer.new()
        _sexuality_section.add_child(line)
        var caption := Label.new()
        caption.text = String(entry[1])
        caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        caption.custom_minimum_size.x = 132
        line.add_child(caption)
        var slider := HSlider.new()
        slider.name = "Sexual_" + String(entry[0])
        slider.min_value = 0.0
        slider.max_value = 1.0
        slider.step = 0.01
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slider.custom_minimum_size.x = 90
        slider.value_changed.connect(_on_sexual_value.bind(String(entry[0])))
        line.add_child(slider)
        var value_label := Label.new()
        value_label.custom_minimum_size.x = 42
        line.add_child(value_label)
        _sexuality_controls[String(entry[0])] = slider
        _sexuality_controls[String(entry[0]) + "_label"] = value_label
    _preview = Label.new()
    _preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(_preview)
    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(_status)
    var buttons := HBoxContainer.new()
    layout.add_child(buttons)
    _undo_button = Button.new()
    _undo_button.text = "Zpět"
    _undo_button.pressed.connect(_on_undo)
    buttons.add_child(_undo_button)
    _redo_button = Button.new()
    _redo_button.text = "Znovu"
    _redo_button.pressed.connect(_on_redo)
    buttons.add_child(_redo_button)
    var apply_button := Button.new()
    _apply_button = apply_button
    apply_button.name = "Apply"
    apply_button.text = "Použít"
    apply_button.pressed.connect(_on_apply)
    buttons.add_child(apply_button)
    var cancel_button := Button.new()
    cancel_button.name = "Cancel"
    cancel_button.text = "Zrušit"
    cancel_button.pressed.connect(_on_cancel)
    buttons.add_child(cancel_button)

func open_character(sim_node: String) -> bool:
    if main == null or not is_inside_tree() or _session.is_open():
        return false
    var read: Dictionary = main.read_character_edit(sim_node)
    if not read.get("ok", false):
        return false
    var source := CharacterData.new()
    source.set_from_dict(read["data"])
    if not _session.begin(source):
        return false
    _target = sim_node
    _revision = int(read["revision"])
    _host_session = main.net != null and main.net.mode == main.net.Mode.HOST
    if _host_session:
        _title.text = "Úprava vlastní postavy — hostitel"
        _help.text = "Pouze tvoje vlastní postava. Změny ověřuje server a sdílí jen veřejný vzhled; identita a soukromá sexualita jsou zamčené."
    _refresh()
    return true

## Explicitly staged entry: transport still authenticates the owner on the server.
func open_network_character(sim_node: String) -> bool:
    if main == null or not is_inside_tree() or _session.is_open() or _network_read:
        return false
    var net = main.net
    if net == null or not net.character_edit_read_ui_enabled or net.mode != net.Mode.CLIENT or sim_node.is_empty() or sim_node != net.my_sim:
        return false
    _network_read = true
    _read_net = net
    _target = sim_node
    _read_token = Crypto.new().generate_random_bytes(16).hex_encode()
    _body_scroll.hide()
    _undo_button.disabled = true
    _redo_button.disabled = true
    _apply_button.disabled = true
    _title.text = "Úprava vlastní postavy — multiplayer"
    _help.text = "Server ověřuje vlastníka a každou změnu. Návrh lze kdykoli zrušit; soukromé údaje se nezveřejňují."
    _status.text = "Čekám na autorizované načtení…"
    net.character_edit_snapshot_correlated.connect(_on_network_snapshot)
    if net.has_signal("character_edit_apply_correlated"):
        net.character_edit_apply_correlated.connect(_on_network_apply_result)
    net.character_edit_snapshot_timed_out.connect(_on_network_timeout)
    net.disconnected.connect(_on_network_disconnected)
    if not net.request_character_edit_snapshot(_read_token):
        _stop_network_read()
        return false
    return true

func _on_network_snapshot(token: String, sim_node: String, data: Dictionary, revision: int) -> void:
    if is_queued_for_deletion() or _read_token.is_empty() or token != _read_token or sim_node != _target:
        return
    if not is_instance_valid(_read_net) or _read_net.mode != _read_net.Mode.CLIENT or _read_net.my_sim != _target:
        _on_cancel()
        return
    _read_token = ""
    if _await_readback and revision != _canonical_revision:
        _await_readback = false
        _body_scroll.show()
        _status.text = "Server vrátil neočekávanou verzi postavy. Návrh zůstal zachovaný."
        _reopen_required = true
        _refresh()
        return
    var was_apply := _await_readback
    _await_readback = false
    _reopen_required = false
    var source := CharacterData.new()
    source.set_from_dict(data)
    if was_apply:
        _session.cancel()
    if revision < 0 or not _session.begin(source):
        _status.text = "Návrh nelze načíst. Zavři panel a zkus to znovu."
        return
    _revision = revision
    _body_scroll.show()
    _status.text = "Změny potvrzeny serverem a načteny." if was_apply else "Soukromý návrh načten. Uprav jej a potvrď tlačítkem Použít."
    _refresh()

func _on_network_timeout(token: String) -> void:
    if _read_token.is_empty() or token != _read_token:
        return
    _read_token = ""
    if _await_readback and _session.is_open():
        _await_readback = false
        _body_scroll.show()
        _status.text = "Potvrzení přišlo, ale nové načtení vypršelo. Návrh zůstal zachovaný; znovu otevři editor pro aktuální verzi."
        _reopen_required = true
        _apply_button.disabled = true
    else:
        _status.text = "Načtení vypršelo. Zavři panel a zkus to znovu."

func _process(_delta: float) -> void:
    if _network_read:
        if not is_instance_valid(_read_net) or _read_net.mode != _read_net.Mode.CLIENT or _read_net.my_sim != _target:
            _on_cancel()
            return
        if not _apply_token.is_empty() and Time.get_ticks_msec() >= _apply_deadline_ms:
            _apply_token = ""
            _apply_deadline_ms = 0
            _body_scroll.show()
            _status.text = "Server nepotvrdil úpravu včas. Návrh zůstal zachovaný; otevři editor znovu pro bezpečné ověření verze."
            _reopen_required = true
            _apply_button.disabled = true

func _on_network_disconnected(_reason: String) -> void:
    _on_cancel()

func _stop_network_read() -> void:
    if is_instance_valid(_read_net):
        if not _read_token.is_empty():
            _read_net.cancel_character_edit_snapshot(_read_token)
        if _read_net.has_signal("character_edit_apply_correlated") and _read_net.character_edit_apply_correlated.is_connected(_on_network_apply_result):
            _read_net.character_edit_apply_correlated.disconnect(_on_network_apply_result)
        if _read_net.character_edit_snapshot_correlated.is_connected(_on_network_snapshot):
            _read_net.character_edit_snapshot_correlated.disconnect(_on_network_snapshot)
        if _read_net.character_edit_snapshot_timed_out.is_connected(_on_network_timeout):
            _read_net.character_edit_snapshot_timed_out.disconnect(_on_network_timeout)
        if _read_net.disconnected.is_connected(_on_network_disconnected):
            _read_net.disconnected.disconnect(_on_network_disconnected)
    _read_token = ""
    _apply_token = ""
    _read_net = null

func _network_can_apply() -> bool:
    return _network_read and is_instance_valid(_read_net) and _read_net.has_signal("character_edit_apply_correlated") and _read_net.character_edit_apply_rpc_enabled and _read_net.mode == _read_net.Mode.CLIENT and _read_net.my_sim == _target and not _reopen_required and _session.is_open()

func _refresh() -> void:
    if not _session.is_open():
        return
    var data: Dictionary = _session.draft()
    var cd := CharacterData.new()
    cd.set_from_dict(data)
    _sliders.load_character(cd)
    _appearance.load_data(data)
    var sexual: Dictionary = data.get("identity", {})
    for key in ["asexual", "aromantic"]:
        (_sexuality_controls[key] as CheckBox).set_pressed_no_signal(bool(sexual.get(key, false)))
    var targets: Array = sexual.get("sexual_attracted_to", [])
    for group in Schema.ATTRACTION.keys():
        (_sexuality_controls["target_" + String(group)] as CheckBox).set_pressed_no_signal(targets.has(group))
    for key in ["libido", "drive_dysregulation"]:
        var value: float = float(sexual.get(key, 0.5 if key == "libido" else 0.0))
        (_sexuality_controls[key] as HSlider).set_value_no_signal(value)
        (_sexuality_controls[key + "_label"] as Label).text = "%.0f%%" % (value * 100.0)
    # The binary hetero/homo shortcut has no meaningful same/opposite
    # classification for nonbinary/unknown identity. Manual targets still work.
    var own_gender := String(sexual.get("gender_identity", "neuvedeno"))
    var supported := own_gender in ["muz", "zena"]
    var same := "muzi" if own_gender == "muz" else "zeny"
    var opposite := "zeny" if own_gender == "muz" else "muzi"
    var only_same := targets.has(same)
    var only_other := targets.has(opposite)
    var spectrum := 0.5
    if only_same != only_other:
        spectrum = 1.0 if only_same else 0.0
    (_sexuality_controls["orientation_spectrum"] as HSlider).set_value_no_signal(spectrum)
    (_sexuality_controls["orientation_label"] as Label).text = (
        "Heterosexuální přitažlivost" if spectrum == 0.0 else
        "Homosexuální přitažlivost" if spectrum == 1.0 else
        "Bisexuální / smíšená přitažlivost" if only_same and only_other else
        "Neurčeno — použij jednotlivé volby"
    ) if supported else "Pro nebinární nebo neurčenou identitu použij volby přitažlivosti výše."
    for key in _sexuality_controls:
        if _sexuality_controls[key] is BaseButton:
            (_sexuality_controls[key] as BaseButton).disabled = _network_read or _host_session
        elif _sexuality_controls[key] is HSlider:
            (_sexuality_controls[key] as HSlider).editable = not (_network_read or _host_session)
    (_sexuality_controls["orientation_spectrum"] as HSlider).editable = (
        not (_network_read or _host_session) and supported)
    var active := String(data.get("clothing", {}).get("active", "bezne"))
    var look: Dictionary = data.get("clothing", {}).get(active, {})
    for i in range(_slot.item_count):
        if _slot.get_item_text(i) == active:
            _slot.select(i)
            break
    for field in _item_buttons:
        var picker: OptionButton = _item_buttons[field]
        for i in range(picker.item_count):
            if String(picker.get_item_metadata(i)) == String(look.get(field, "")):
                picker.select(i)
                break
    _visual_preview.show_draft(data)
    _preview.text = "Návrh: %s %s · %s · %s / %s / %s" % [
        data.get("identity", {}).get("first_name", ""),
        data.get("identity", {}).get("last_name", ""),
        active, look.get("top", ""), look.get("bottom", ""), look.get("shoes", "")]
    _undo_button.disabled = not _session.can_undo()
    _redo_button.disabled = not _session.can_redo()
    _apply_button.disabled = (_network_read and (not _network_can_apply() or not _apply_token.is_empty() or _await_readback))

func _on_appearance_changed(group: String, key: String, value: Variant) -> void:
    if not _session.is_open() or (_network_read and (not _network_can_apply() or not _apply_token.is_empty() or _await_readback)):
        return
    if group not in AppearanceEditor.GROUP_ORDER or not Schema.fields(group).has(key):
        return
    var spec: Array = Schema.fields(group)[key]
    if (spec[0] == "f" and (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT)) or (spec[0] == "e" and (typeof(value) != TYPE_STRING or not spec[1].has(value))):
        return
    var draft: Dictionary = _session.draft()
    draft[group][key] = value
    _session.replace_draft(draft, "Appearance "+group+"."+key, group+":"+key)
    _visual_preview.show_draft(draft)
    _undo_button.disabled = not _session.can_undo()
    _redo_button.disabled = not _session.can_redo()


func _on_slider_changed(group: String, _key: String, _value: float) -> void:
    if not _session.is_open():
        return
    var draft: Dictionary = _session.draft()
    var section := "personality" if group in ["trait_levels", "hexaco"] else "mind"
    var source: Dictionary = _sliders.character.get(section)
    if group == "mind_belief" and _key == "self_defectiveness":
        draft["mind"][_key] = float(source.get(_key, 0.0))
    elif group == "mind_enum" and Schema.fields("mind").has(_key):
        draft["mind"][_key] = source.get(_key, Schema.default_value(Schema.fields("mind")[_key]))
    else:
        draft[section][group] = source.get(group, {}).duplicate(true)
    _session.replace_draft(draft, "Slider " + group, group + ":" + _key)
    _undo_button.disabled = not _session.can_undo()
    _redo_button.disabled = not _session.can_redo()

func _on_sexual_bool(on: bool, field: String) -> void:
    if _network_read or not _session.is_open() or field not in ["asexual", "aromantic"]:
        return
    var draft: Dictionary = _session.draft()
    draft["identity"][field] = on
    _session.replace_draft(draft, "Private sexuality " + field, "sex:" + field)
    _refresh()


func _on_sexual_value(value: float, field: String) -> void:
    if _network_read or not _session.is_open() or field not in ["libido", "drive_dysregulation"] or not is_finite(value):
        return
    var draft: Dictionary = _session.draft()
    draft["identity"][field] = clampf(value, 0.0, 1.0)
    _session.replace_draft(draft, "Private sexuality " + field, "sex:" + field)
    _refresh()


## Slider chooses the three common binary spectrum presets, but does not
## overwrite independent nonbinary attraction or romantic/asexual identity.
func _on_orientation_spectrum(value: float) -> void:
    if _network_read or _host_session or not _session.is_open() or not is_finite(value):
        return
    var draft: Dictionary = _session.draft()
    var gender := String(draft["identity"].get("gender_identity", "neuvedeno"))
    if gender not in ["muz", "zena"]:
        return
    var same := "muzi" if gender == "muz" else "zeny"
    var opposite := "zeny" if gender == "muz" else "muzi"
    var selected: Array = (draft["identity"].get("sexual_attracted_to", []) as Array).duplicate()
    selected.erase("muzi")
    selected.erase("zeny")
    if value <= 0.25:
        selected.append(opposite)
    elif value >= 0.75:
        selected.append(same)
    else:
        selected.append(same)
        selected.append(opposite)
    var ordered := []
    for group in Schema.ATTRACTION.keys():
        if selected.has(group):
            ordered.append(group)
    draft["identity"]["sexual_attracted_to"] = ordered
    _session.replace_draft(draft, "Sexual orientation spectrum", "sex:attraction")
    _refresh()


func _on_sexual_target(on: bool, group: String) -> void:
    if _network_read or not _session.is_open() or not Schema.ATTRACTION.has(group):
        return
    var draft: Dictionary = _session.draft()
    var selected: Array = (draft["identity"].get("sexual_attracted_to", []) as Array).duplicate()
    if on and not selected.has(group):
        selected.append(group)
    elif not on:
        selected.erase(group)
    # Deterministic schema order makes Apply/Undo and save replays stable.
    var ordered := []
    for known in Schema.ATTRACTION.keys():
        if selected.has(known):
            ordered.append(known)
    draft["identity"]["sexual_attracted_to"] = ordered
    _session.replace_draft(draft, "Private sexuality attraction", "sex:attraction")
    _refresh()


func _on_slot_selected(index: int) -> void:
    if not _session.is_open() or index < 0 or index >= _slot.item_count:
        return
    var slot := _slot.get_item_text(index)
    if not Schema.OUTFIT_CATEGORIES.has(slot):
        return
    var draft: Dictionary = _session.draft()
    draft["clothing"]["active"] = slot
    _session.replace_draft(draft, "Outfit category " + slot)
    _refresh()

func _on_item_selected(index: int, field: String) -> void:
    if not _session.is_open() or not _item_buttons.has(field) or _slot.selected < 0:
        return
    var picker: OptionButton = _item_buttons[field]
    if index < 0 or index >= picker.item_count:
        return
    var catalog: Dictionary = Schema.TOPS if field == "top" else (Schema.BOTTOMS if field == "bottom" else Schema.SHOES)
    var metadata: Variant = picker.get_item_metadata(index)
    if typeof(metadata) != TYPE_STRING or not catalog.has(metadata):
        return
    var slot := _slot.get_item_text(_slot.selected)
    if not Schema.OUTFIT_CATEGORIES.has(slot):
        return
    var draft: Dictionary = _session.draft()
    var outfit: Dictionary = draft["clothing"][slot]
    if field == "bottom" and metadata == "zadne" and outfit.get("top") != "saty":
        _status.text = "Bez spodního dílu lze zvolit pouze šaty."
        _refresh()
        return
    outfit[field] = String(metadata)
    if field == "top" and metadata != "saty" and outfit.get("bottom") == "zadne":
        outfit["bottom"] = "kalhoty"
    draft["clothing"]["active"] = slot
    _session.replace_draft(draft, "Garment " + slot + "/" + field)
    _status.text = "Kus oblečení je zatím pouze v návrhu."
    _refresh()

func _on_style_selected(index: int) -> void:
    if not _session.is_open() or index <= 0 or index >= _style.item_count or _slot.selected < 0:
        return
    var metadata: Variant = _style.get_item_metadata(index)
    if typeof(metadata) != TYPE_STRING or not Wardrobe.STYLES.has(String(metadata)):
        return
    var style := String(metadata)
    var slot := _slot.get_item_text(_slot.selected)
    var updated := Wardrobe.apply_to_character(_session.draft(), style, slot)
    _session.replace_draft(updated, "Wardrobe " + style)
    _status.text = "Styl je zatím pouze v návrhu."
    _refresh()

func _on_undo() -> void:
    _session.undo()
    _refresh()

func _on_redo() -> void:
    _session.redo()
    _refresh()

func _on_network_apply_result(token: String, sim_node: String, accepted: bool, revision: int, _changed: bool, reason: String) -> void:
    if is_queued_for_deletion() or token.is_empty() or token != _apply_token or sim_node != _target:
        return
    _apply_token = ""
    _apply_deadline_ms = 0
    if not accepted:
        _body_scroll.show()
        if reason == "conflict" or reason == "unauthorized":
            _reopen_required = true
        _status.text = "Server změny odmítl: " + reason + ". Návrh zůstal zachovaný."
        _refresh()
        return
    if revision < _revision:
        _body_scroll.show()
        _status.text = "Server vrátil starou revizi, obnov editor."
        _reopen_required = true
        _apply_button.disabled = true
        return
    _await_readback = true
    _canonical_revision = revision
    _read_token = Crypto.new().generate_random_bytes(16).hex_encode()
    _status.text = "Server změnu přijal. Ověřuji kanonická data…"
    if not _read_net.request_character_edit_snapshot(_read_token):
        _read_token = ""
        _await_readback = false
        _status.text = "Potvrzeno, ale znovunačtení nelze spustit. Zavři editor a načti jej znovu."
        _reopen_required = true
        _apply_button.disabled = true


func _on_network_apply() -> void:
    if not _network_can_apply() or not _apply_token.is_empty() or _await_readback:
        return
    if not _session.is_dirty():
        _status.text = "Žádné změny k použití."
        return
    var token := Crypto.new().generate_random_bytes(16).hex_encode()
    if not _read_net.request_character_edit_apply(_revision, _session.draft(), token):
        _status.text = "Úpravu nelze odeslat. Návrh zůstal zachovaný."
        return
    _apply_token = token
    _apply_deadline_ms = Time.get_ticks_msec() + 9000
    _body_scroll.hide()
    _apply_button.disabled = true
    _status.text = "Čekám na potvrzení změn od serveru…"


func _on_apply() -> void:
    if _network_read:
        _on_network_apply()
        return
    if not _session.is_open() or main == null:
        return
    # Fresh authority/revision/strict-validation checks occur in Main.
    var result: Dictionary = main.apply_character_edit(_target, _session.draft(), _revision)
    if not result.get("ok", false):
        _status.text = "Nelze použít: " + String(result.get("reason", "unknown"))
        return
    _session.cancel()
    var current: Dictionary = main.read_character_edit(_target)
    if not current.get("ok", false):
        _status.text = "Uloženo, ale znovunačtení selhalo."
        queue_free()
        return
    var cd := CharacterData.new()
    cd.set_from_dict(current["data"])
    _session.begin(cd)
    _revision = int(current["revision"])
    _status.text = "Změny použity."
    _refresh()

func _on_cancel() -> void:
    _stop_network_read()
    _session.cancel()
    queue_free()

func _exit_tree() -> void:
    _stop_network_read()
    _session.cancel()