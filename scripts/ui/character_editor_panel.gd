extends Control
## Offline-only transactional character editor, opened from the HUD.
## This panel never sends private CharacterData over multiplayer RPC.
const Session := preload("res://scripts/character/character_edit_session.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const SliderEditor := preload("res://scripts/ui/personality_slider_editor.gd")
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
var _style: OptionButton
var _slot: OptionButton
var _item_buttons: Dictionary = {}
var _undo_button: Button
var _redo_button: Button

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
    title.text = "Úprava postavy — pouze offline"
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    title.add_theme_font_size_override("font_size", 22)
    layout.add_child(title)
    var help := Label.new()
    help.text = "Změny zůstávají v návrhu až do Použít. Identita a síťové úpravy jsou zatím uzamčené."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(help)
    var body_scroll := ScrollContainer.new()
    body_scroll.name = "EditorBody"
    body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(body_scroll)
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_scroll.add_child(body)
    _visual_preview = Preview.new()
    body.add_child(_visual_preview)
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
    _refresh()
    return true

func _refresh() -> void:
    if not _session.is_open():
        return
    var data: Dictionary = _session.draft()
    var cd := CharacterData.new()
    cd.set_from_dict(data)
    _sliders.load_character(cd)
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

func _on_slider_changed(group: String, _key: String, _value: float) -> void:
    if not _session.is_open():
        return
    var draft: Dictionary = _session.draft()
    var section := "personality" if group in ["trait_levels", "hexaco"] else "mind"
    var source: Dictionary = _sliders.character.get(section)
    draft[section][group] = source.get(group, {}).duplicate(true)
    _session.replace_draft(draft, "Slider " + group, group + ":" + _key)
    _undo_button.disabled = not _session.can_undo()
    _redo_button.disabled = not _session.can_redo()

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

func _on_apply() -> void:
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
    _session.cancel()
    queue_free()

func _exit_tree() -> void:
    _session.cancel()