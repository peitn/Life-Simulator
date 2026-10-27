extends Control
## Offline new-character transaction: editing/Cancel never touches the live
## household. Only Main validates and creates the actual authoritative agent.
const CharacterData := preload("res://scripts/character/character_data.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Session := preload("res://scripts/character/character_edit_session.gd")
const Wardrobe := preload("res://scripts/assets/subculture_wardrobe.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")
const SliderEditor := preload("res://scripts/ui/personality_slider_editor.gd")
const AppearanceEditor := preload("res://scripts/ui/appearance_slider_editor.gd")

var main: Node
var _session := Session.new()
var _first: LineEdit
var _last: LineEdit
var _age: SpinBox
var _height: SpinBox
var _grammar: OptionButton
var _gender: OptionButton
var _hair: OptionButton
var _trait: OptionButton
var _style: OptionButton
var _visual_preview: VBoxContainer
var _sliders: VBoxContainer
var _appearance: VBoxContainer
var _status: Label
var _undo: Button
var _redo: Button

func _ready() -> void:
    name = "CharacterCreatorPanel"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var shade := ColorRect.new()
    shade.color = Color(0.04, 0.05, 0.08, 0.93)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(shade)
    var panel := PanelContainer.new()
    panel.anchor_left = 0.03
    panel.anchor_top = 0.035
    panel.anchor_right = 0.97
    panel.anchor_bottom = 0.965
    add_child(panel)
    var layout := VBoxContainer.new()
    panel.add_child(layout)
    var title := Label.new()
    title.text = "Vytvořit vlastní postavu — offline"
    title.add_theme_font_size_override("font_size", 22)
    layout.add_child(title)
    var info := Label.new()
    info.text = "Nová postava se přidá k domácnosti teprve po potvrzení. Rod, identita, tělo, vzhled i povaha jsou nezávislé."
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(info)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(scroll)
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)
    _first = LineEdit.new()
    _first.name = "FirstName"
    _first.max_length = 24
    _label_field(body, "Jméno", _first)
    _first.text_changed.connect(_on_name_changed.bind("first_name"))
    _last = LineEdit.new()
    _last.name = "LastName"
    _last.max_length = 24
    _label_field(body, "Příjmení (nepovinné)", _last)
    _last.text_changed.connect(_on_name_changed.bind("last_name"))
    _grammar = OptionButton.new()
    _grammar.name = "Grammar"
    for id in Schema.GRAMMAR:
        _grammar.add_item(String(Schema.GRAMMAR[id]))
        _grammar.set_item_metadata(_grammar.item_count - 1, String(id))
    _label_field(body, "Gramatický rod", _grammar)
    _grammar.item_selected.connect(_on_identity_selected.bind("grammar"))
    _gender = OptionButton.new()
    _gender.name = "GenderIdentity"
    for id in Schema.GENDER_IDENTITY:
        _gender.add_item(String(Schema.GENDER_IDENTITY[id]))
        _gender.set_item_metadata(_gender.item_count - 1, String(id))
    _label_field(body, "Genderová identita", _gender)
    _gender.item_selected.connect(_on_identity_selected.bind("gender_identity"))
    _age = SpinBox.new()
    _age.name = "Age"
    _age.min_value = 18
    _age.max_value = 95
    _age.step = 1
    _label_field(body, "Věk (18+)", _age)
    _age.value_changed.connect(_on_body_changed.bind("age"))
    _height = SpinBox.new()
    _height.name = "Height"
    _height.min_value = 145
    _height.max_value = 205
    _height.step = 1
    _height.suffix = " cm"
    _label_field(body, "Výška", _height)
    _height.value_changed.connect(_on_body_changed.bind("height_cm"))
    _hair = OptionButton.new()
    _hair.name = "HairStyle"
    for id in Schema.HAIR_STYLES:
        _hair.add_item(String(Schema.HAIR_STYLES[id]))
        _hair.set_item_metadata(_hair.item_count - 1, String(id))
    _label_field(body, "Účes", _hair)
    _hair.item_selected.connect(_on_hair_selected)
    _style = OptionButton.new()
    _style.name = "ClothingStyle"
    _style.add_item("Výchozí oblečení")
    _style.set_item_metadata(0, "")
    for id in Wardrobe.names():
        _style.add_item(String(Wardrobe.STYLES[id]["label"]))
        _style.set_item_metadata(_style.item_count - 1, String(id))
    _label_field(body, "Styl oblečení", _style)
    _style.item_selected.connect(_on_style_selected)
    _trait = OptionButton.new()
    _trait.name = "StartingTrait"
    for id in Schema.TRAIT_SLIDERS:
        _trait.add_item(String(Schema.TRAIT_SLIDERS[id]))
        _trait.set_item_metadata(_trait.item_count - 1, String(id))
    _label_field(body, "Výchozí osobnostní rys", _trait)
    _trait.item_selected.connect(_on_trait_selected)
    _visual_preview = Preview.new()
    body.add_child(_visual_preview)
    _appearance = AppearanceEditor.new()
    _appearance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _appearance.appearance_changed.connect(_on_appearance_changed)
    body.add_child(_appearance)
    body.add_child(HSeparator.new())
    _sliders = SliderEditor.new()
    _sliders.custom_minimum_size = Vector2(0, 370)
    _sliders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sliders.character_changed.connect(_on_sliders_changed)
    body.add_child(_sliders)
    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(_status)
    var buttons := HBoxContainer.new()
    layout.add_child(buttons)
    _undo = Button.new()
    _undo.text = "Zpět"
    _undo.pressed.connect(_on_undo)
    buttons.add_child(_undo)
    _redo = Button.new()
    _redo.text = "Znovu"
    _redo.pressed.connect(_on_redo)
    buttons.add_child(_redo)
    var apply := Button.new()
    apply.name = "CreateCharacter"
    apply.text = "Vytvořit a hrát"
    apply.pressed.connect(_on_create)
    buttons.add_child(apply)
    var cancel := Button.new()
    cancel.name = "Cancel"
    cancel.text = "Zrušit"
    cancel.pressed.connect(_on_cancel)
    buttons.add_child(cancel)
    var source: Resource = CharacterData.create()
    var initial: Dictionary = source.to_dict()
    initial["identity"]["first_name"] = "Alex"
    initial["identity"]["last_name"] = ""
    initial["personality"]["traits"] = ["aktivni"]
    source.set_from_dict(initial)
    _session.begin(source)
    _refresh()

func _label_field(parent: Node, caption: String, widget: Control) -> void:
    var label := Label.new()
    label.text = caption
    parent.add_child(label)
    widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(widget)

func _select_metadata(button: OptionButton, value: String) -> void:
    for i in button.item_count:
        if String(button.get_item_metadata(i)) == value:
            button.select(i)
            return

func _refresh() -> void:
    if not _session.is_open():
        return
    var data: Dictionary = _session.draft()
    _first.text = String(data["identity"]["first_name"])
    _last.text = String(data["identity"]["last_name"])
    _select_metadata(_grammar, String(data["identity"]["grammar"]))
    _select_metadata(_gender, String(data["identity"]["gender_identity"]))
    _select_metadata(_hair, String(data["hair"]["style"]))
    var traits: Array = data["personality"].get("traits", [])
    if not traits.is_empty():
        _select_metadata(_trait, String(traits[0]))
    _age.set_value_no_signal(float(data["body"]["age"]))
    _height.set_value_no_signal(float(data["body"]["height_cm"]))
    _visual_preview.show_draft(data)
    var cd := CharacterData.new()
    cd.set_from_dict(data)
    _sliders.load_character(cd)
    _appearance.load_data(data)
    _undo.disabled = not _session.can_undo()
    _redo.disabled = not _session.can_redo()

func _push(data: Dictionary, description: String, redraw_sliders := true) -> void:
    if not _session.replace_draft(data, description):
        return
    if redraw_sliders:
        _refresh()
    else:
        _visual_preview.show_draft(data)
        _undo.disabled = not _session.can_undo()
        _redo.disabled = not _session.can_redo()
    _status.text = ""

func _on_name_changed(value: String, field: String) -> void:
    if not _session.is_open():
        return
    var data: Dictionary = _session.draft()
    data["identity"][field] = value
    _push(data, "Name", false)

func _on_identity_selected(index: int, field: String) -> void:
    var button: OptionButton = _grammar if field == "grammar" else _gender
    if index < 0 or index >= button.item_count:
        return
    var data: Dictionary = _session.draft()
    data["identity"][field] = button.get_item_metadata(index)
    _push(data, "Identity")

func _on_body_changed(value: float, field: String) -> void:
    var data: Dictionary = _session.draft()
    data["body"][field] = int(value) if field == "age" else value
    _push(data, "Body")

func _on_hair_selected(index: int) -> void:
    if index < 0 or index >= _hair.item_count:
        return
    var data: Dictionary = _session.draft()
    data["hair"]["style"] = _hair.get_item_metadata(index)
    _push(data, "Hair")

func _on_trait_selected(index: int) -> void:
    if index < 0 or index >= _trait.item_count:
        return
    var data: Dictionary = _session.draft()
    data["personality"]["traits"] = [String(_trait.get_item_metadata(index))]
    _push(data, "Starting trait")


func _on_style_selected(index: int) -> void:
    if index < 0 or index >= _style.item_count:
        return
    var key: String = String(_style.get_item_metadata(index))
    if key.is_empty():
        return
    var changed: Dictionary = Wardrobe.apply_to_character(_session.draft(), key, "bezne")
    _push(changed, "Wardrobe")

func _on_appearance_changed(group: String, key: String, value: Variant) -> void:
    if not _session.is_open() or group not in AppearanceEditor.GROUP_ORDER:
        return
    var fields: Dictionary = Schema.fields(group)
    if not fields.has(key):
        return
    var spec: Array = fields[key]
    if (spec[0] == "f" and (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT)) or (spec[0] == "e" and (typeof(value) != TYPE_STRING or not spec[1].has(value))):
        return
    var data: Dictionary = _session.draft()
    data[group][key] = value
    _push(data, "Appearance: " + group + "." + key, false)


func _on_sliders_changed(group: String, _key: String, _value: float) -> void:
    if not _session.is_open():
        return
    var data: Dictionary = _session.draft()
    var edited: Dictionary = _sliders.character.to_dict()
    var section: String = "personality" if group == "trait_levels" or group == "hexaco" else "mind"
    if group == "mind_belief" and _key == "self_defectiveness":
        data["mind"][_key] = float(edited["mind"].get(_key, 0.0))
    else:
        data[section][group] = edited[section][group].duplicate(true)
    _push(data, "Slider", false)

func _on_undo() -> void:
    _session.undo()
    _refresh()

func _on_redo() -> void:
    _session.redo()
    _refresh()

func _on_create() -> void:
    if main == null or not _session.is_open():
        return
    var result: Dictionary = main.create_offline_character(_session.draft())
    if not result.get("ok", false):
        _status.text = "Postavu nelze vytvořit: " + String(result.get("reason", "invalid"))
        if result.has("errors"):
            _status.text += " · " + ", ".join(result["errors"])
        return
    _session.cancel()
    if main.hud != null and is_instance_valid(main.hud):
        main.hud.show_notice("Postava vytvořena. Teď můžeš hrát a upravovat ji.")
    queue_free()

func _on_cancel() -> void:
    _session.cancel()
    queue_free()

func _exit_tree() -> void:
    _session.cancel()