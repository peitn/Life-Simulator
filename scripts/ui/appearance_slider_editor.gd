extends VBoxContainer
## Genuine schema-backed body, face and skin controls, not cosmetic mock sliders.
## Values stay in the caller's isolated CharacterEditSession until Apply.
## Categories are switched, not duplicated; all controls fit a narrow viewport.
const Schema := preload("res://scripts/character/character_schema.gd")

signal appearance_changed(group: String, key: String, value: Variant)

const GROUP_ORDER := ["body", "face", "skin", "hair", "eyes", "makeup"]
const GROUP_LABELS := {
    "body":"Tělo a proporce", "face":"Obličej a detaily",
    "skin":"Pleť a textura", "hair":"Vlasy a obočí",
    "eyes":"Oči", "makeup":"Líčení"}
const BODY_LABELS := {
    "height_cm":"Výška (cm)", "age":"Věk",
    "frame":"Tělesná stavba", "muscle":"Svalstvo", "body_fat":"Tělesný tuk",
    "shoulders":"Šířka ramen", "chest":"Hrudník", "bust":"Poprsí",
    "waist":"Pas", "hips":"Boky", "leg_length":"Délka nohou",
    "head_size":"Velikost hlavy", "neck_length":"Délka krku"}
const SKIN_LABELS := {
    "tone":"Pigmentace pleti", "undertone":"Podtón (studený – teplý)",
    "redness":"Prokrvení", "freckles":"Pihy", "moles":"Znaménka",
    "acne":"Akné", "vitiligo":"Vitiligo", "weathering":"Stárnutí kůže",
    "oiliness":"Maz / lesk", "dryness":"Suchost / reliéf"}
const HAIR_LABELS := {
    "melanin":"Pigment vlasů", "red":"Zrzavý pigment", "grey":"Šediny",
    "hairline":"Vlasová linie", "brow_density":"Hustota obočí",
    "facial_density":"Hustota vousů"}
const EYES_LABELS := {"iris":"Barva duhovky", "heterochromia":"Heterochromie"}
const EXCLUDED_BODY := ["age", "height_cm"] # already exposed as native SpinBoxes on creator

var _group_picker: OptionButton
var _groups: Dictionary = {}
var _controls: Dictionary = {}
var _labels: Dictionary = {}
var _enum_buttons: Dictionary = {}
var _loading := false

func _ready() -> void:
    name = "AppearanceSliders"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var title := Label.new()
    title.text = "Podrobný vzhled — proporce, obličej, pleť"
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    title.add_theme_font_size_override("font_size", 17)
    add_child(title)
    var help := Label.new()
    help.text = "Posuvníky skutečně mění 3D model. Výchozí hodnoty se zachovají; změny lze vrátit zpět."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(help)
    _group_picker = OptionButton.new()
    _group_picker.name = "AppearanceCategory"
    _group_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(_group_picker)
    for group in GROUP_ORDER:
        _group_picker.add_item(GROUP_LABELS[group])
        _group_picker.set_item_metadata(_group_picker.item_count-1, group)
        var section := VBoxContainer.new()
        section.name = "Appearance_" + group
        section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_child(section)
        _groups[group] = section
        var fs: Dictionary = Schema.fields(group)
        for field in fs:
            var spec: Array = fs[field]
            var kind := String(spec[0])
            if group == "body" and field in EXCLUDED_BODY:
                continue
            if kind == "f":
                _make_slider(section, group, String(field), spec)
            elif kind == "e" and group in ["skin", "hair"]:
                _make_enum(section, group, String(field), spec)
    _group_picker.item_selected.connect(_switch_group)
    _switch_group(0)

func _caption(group: String, key: String) -> String:
    match group:
        "body": return String(BODY_LABELS.get(key, key.capitalize()))
        "face":
            if Schema.FACE_MORPHS.has(key): return String(Schema.FACE_MORPHS[key])
            if Schema.FACE_ASYMMETRY.has(key): return String(Schema.FACE_ASYMMETRY[key])
            if Schema.FACE_DETAILS.has(key): return String(Schema.FACE_DETAILS[key][0])
        "skin": return String(SKIN_LABELS.get(key, key.capitalize()))
        "hair": return String(HAIR_LABELS.get(key, key.capitalize()))
        "eyes": return String(EYES_LABELS.get(key, key.capitalize()))
        "makeup": return key.capitalize().replace("_"," ")
    return key.capitalize()

func _make_slider(parent: VBoxContainer, group: String, field: String, spec: Array) -> void:
    var row := VBoxContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(row)
    var heading := HBoxContainer.new()
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(heading)
    var caption := Label.new()
    caption.text = _caption(group, field)
    caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    heading.add_child(caption)
    var number := Label.new()
    number.custom_minimum_size.x = 52
    number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    heading.add_child(number)
    var slider := HSlider.new()
    slider.name = "AppearanceSlider_" + group + "_" + field
    slider.min_value = float(spec[1])
    slider.max_value = float(spec[2])
    slider.step = 0.01
    slider.custom_minimum_size = Vector2(80, 24)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var k := group + ":" + field
    _controls[k] = slider
    _labels[k] = number
    slider.value_changed.connect(_on_slider_changed.bind(group, field))

func _make_enum(parent: VBoxContainer, group: String, field: String, spec: Array) -> void:
    var label := Label.new()
    label.text = _caption(group,field)
    parent.add_child(label)
    var picker := OptionButton.new()
    picker.name = "AppearanceEnum_" + group + "_" + field
    picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var catalog: Dictionary = spec[1]
    for name in catalog:
        picker.add_item(String(catalog[name]))
        picker.set_item_metadata(picker.item_count-1, name)
    parent.add_child(picker)
    _enum_buttons[group + ":" + field] = picker
    picker.item_selected.connect(_on_enum_changed.bind(group, field))

func _switch_group(index: int) -> void:
    if index < 0 or index >= GROUP_ORDER.size():
        return
    var name: String = String(GROUP_ORDER[index])
    for group in GROUP_ORDER:
        (_groups[group] as VBoxContainer).visible = group == name

func load_data(data: Dictionary) -> void:
    _loading = true
    for k in _controls:
        var pair: PackedStringArray = String(k).split(":")
        var group := String(pair[0])
        var field := String(pair[1])
        var spec: Array = Schema.fields(group)[field]
        var section: Dictionary = data.get(group, {})
        var value: float = float(section.get(field, spec[3]))
        var slider: HSlider = _controls[k]
        slider.set_value_no_signal(clampf(value, slider.min_value, slider.max_value))
        (_labels[k] as Label).text = "%.2f" % slider.value
    for k in _enum_buttons:
        var pair: PackedStringArray = String(k).split(":")
        var group := String(pair[0])
        var field := String(pair[1])
        var value := String(data.get(group, {}).get(field, ""))
        var picker: OptionButton = _enum_buttons[k]
        for i in picker.item_count:
            if String(picker.get_item_metadata(i)) == value:
                picker.select(i)
                break
    _loading = false

func _on_slider_changed(value: float, group: String, field: String) -> void:
    if _loading:
        return
    var k := group + ":" + field
    if not _controls.has(k):
        return
    (_labels[k] as Label).text = "%.2f" % value
    appearance_changed.emit(group, field, value)

func _on_enum_changed(index: int, group: String, field: String) -> void:
    if _loading:
        return
    var picker: OptionButton = _enum_buttons.get(group + ":" + field)
    if picker == null or index < 0 or index >= picker.item_count:
        return
    appearance_changed.emit(group, field, String(picker.get_item_metadata(index)))

func slider(group: String, field: String) -> HSlider:
    return _controls.get(group + ":" + field)

func enum_button(group: String, field: String) -> OptionButton:
    return _enum_buttons.get(group + ":" + field)

func available_count() -> int:
    return _controls.size() + _enum_buttons.size()
