extends VBoxContainer
## Reusable C6/C7 character editor panel for continuous personality and psyche.
## Accepts a CharacterData Resource, edits a local clone, and validates on export.
## The panel does not diagnose anyone: "predispositions" represent gameplay susceptibility.

const Schema := preload("res://scripts/character/character_schema.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const PsycheModel := preload("res://scripts/psyche/psyche_model.gd")
const Traits := preload("res://scripts/sim/traits.gd")

signal character_changed(group: String, key: String, value: float)

var character: Resource
var _list: VBoxContainer
var _readout: Label


func _ready() -> void:
	if character == null:
		character = CharacterData.create()
	_build()


func load_character(cd: Resource) -> void:
	character = cd.clone() if cd != null else CharacterData.create()
	if is_inside_tree():
		_build()


func export_data() -> Dictionary:
	return Validator.repaired(character.to_dict())


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = "Osobnost a psychika — spojité vlastnosti"
	add_child(title)
	var note := Label.new()
	note.text = "Všechny posuvníky jsou nezávislé. Žádné body ani povinné typy osobnosti."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var prof: Dictionary = character.personality
	var mind: Dictionary = character.mind
	var levels: Dictionary = prof.get("trait_levels", {})
	_section("Osobnostní rysy (0 = vůbec, 1 = výrazně)")
	for id in Schema.TRAIT_SLIDERS:
		var initial := float(levels.get(id, Traits.weight(prof.get("traits", []), String(id))))
		_row("trait_levels", String(id), String(Schema.TRAIT_SLIDERS[id]), initial, 0.0, 1.0)
	var result := PsycheModel.compute(character.to_dict(), {"individual": false})
	_section("Základní osobnost (HEXACO; −1 až +1)")
	for id in Schema.HEXACO:
		var hx: Dictionary = prof.get("hexaco", {})
		var initial := float(hx.get(id, result.get("P", {}).get(id, 0.0)))
		_row("hexaco", String(id), String(Schema.HEXACO[id]), initial, -1.0, 1.0)
	_section("Psychologické dispozice (0 až 1)")
	for id in Schema.PSYCHE_SLIDERS:
		var ds: Dictionary = mind.get("dispositions", {})
		var initial := float(ds.get(id, result.get("D", {}).get(id, 0.5)))
		_row("dispositions", String(id), String(Schema.PSYCHE_SLIDERS[id]), initial, 0.0, 1.0)
	_section("Vnitřní přesvědčení o sobě (0 = vůbec, 1 = velmi silné)")
	_row("mind_belief", "self_defectiveness", "Jsem nedostatečná/nedostatečný — pocit vlastní defektnosti",
		float(mind.get("self_defectiveness", 0.0)), 0.0, 1.0)
	_neuro_section(mind)
	_section("Paměť na lidi a události (0,5 = průměr)")
	_note("Jak dlouho a jak přesně si postava pamatuje, co se mezi lidmi stalo, a jak silně si nese emoce z minulosti.")
	var mem: Dictionary = mind.get("memory", {})
	for id in Schema.MEMORY_SLIDERS:
		_row("memory", String(id), String(Schema.MEMORY_SLIDERS[id]), float(mem.get(id, 0.5)), 0.0, 1.0)
	_section("Vnitřní hlas (0,5 = průměr)")
	_note("Myšlenky vznikají z toho, co se postavě děje; posuvníky jen mění, jak silně se k ní vracejí.")
	var th: Dictionary = mind.get("thoughts", {})
	for id in Schema.THOUGHT_SLIDERS:
		_row("thoughts", String(id), String(Schema.THOUGHT_SLIDERS[id]), float(th.get(id, 0.5)), 0.0, 1.0)
	_section("Průběh nálady v čase (0 = bez sklonu, 1 = výrazně)")
	_note("Kombinací os vzniká různý průběh (např. jen hypomanie, i mánie, rychlé střídání, dlouhodobě nízká nálada) – bez nálepky. Nálada se posuzuje vůči obvyklému já postavy.")
	var md: Dictionary = mind.get("mood", {})
	for id in Schema.MOOD_SLIDERS:
		_row("mood", String(id), String(Schema.MOOD_SLIDERS[id]), float(md.get(id, 0.0)), 0.0, 1.0)
	_section("Náchylnost k psychickým obtížím (0 = žádná, 1 = výrazná)")
	for id in Schema.PREDISPOSITIONS:
		var preds: Dictionary = mind.get("predispositions", {})
		var label_text := String(Schema.PREDISPOSITIONS[id]["label"])
		_row("predispositions", String(id), label_text, float(preds.get(id, 0.0)), 0.0, 1.0)
	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.text = "Intenzita vyjadřuje predispozici v simulaci, ne diagnózu ani předpověď chování."
	add_child(_readout)


## Neurodivergentní profil (v9): nezávislé osy, silné stránky i obtíže. Není to diagnóza ani přepínač.
func _neuro_section(mind: Dictionary) -> void:
	_section("Neurodivergentní profil (0 = bez výrazné odlišnosti, 1 = výrazně)")
	_note("Každá osa zvlášť – žádná nálepka ani šablona. Silné stránky (hyperfokus, hloubka zájmu, přímost) i obtíže. Potřebu rutiny nastavuje „Potřeba předvídatelnosti“ výše.")
	var nd: Dictionary = mind.get("neuro", {})
	for id in Schema.NEURO_SLIDERS:
		_row("neuro", String(id), String(Schema.NEURO_SLIDERS[id]), float(nd.get(id, 0.0)), 0.0, 1.0)
	_enum_row("interest_focus", "Kam směřuje hluboký zájem", Schema.INTEREST_FOCUS, String(mind.get("interest_focus", "reading")))


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.75)
	_list.add_child(l)


## Výběr z katalogu v `mind` (např. interest_focus). Signál nese index; data čte volající z `character`.
func _enum_row(field: String, title: String, catalog: Dictionary, current: String) -> void:
	var row := VBoxContainer.new()
	_list.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(caption)
	var ob := OptionButton.new()
	ob.name = "Enum_" + field
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array = catalog.keys()
	for i in ids.size():
		ob.add_item(String(catalog[ids[i]]), i)
		ob.set_item_metadata(i, String(ids[i]))
		if String(ids[i]) == current:
			ob.select(i)
	ob.item_selected.connect(_on_enum.bind(field, ob))
	row.add_child(ob)


func _on_enum(index: int, field: String, ob: OptionButton) -> void:
	var id := String(ob.get_item_metadata(index))
	character.mind[field] = id
	character_changed.emit("mind_enum", field, float(index))


func _section(title: String) -> void:
	var l := Label.new()
	l.text = title
	_list.add_child(l)
	_list.add_child(HSeparator.new())


func _row(group: String, id: String, title: String, initial: float, lo: float, hi: float) -> void:
	# Caption above the control prevents horizontal clipping in narrow viewports.
	var row := VBoxContainer.new()
	_list.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(caption)
	var controls := HBoxContainer.new()
	row.add_child(controls)
	var slider := HSlider.new()
	if group == "mind_belief" and id == "self_defectiveness":
		slider.name = "BeliefDefectiveness"
	else:
		slider.name = "Slider_%s_%s" % [group, id]
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.01
	slider.custom_minimum_size.x = 120.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 44.0
	controls.add_child(value_label)
	slider.set_value_no_signal(initial)
	value_label.text = "%.2f" % initial
	slider.value_changed.connect(_on_slider.bind(group, id, value_label))


func _on_slider(value: float, group: String, id: String, value_label: Label) -> void:
	value_label.text = "%.2f" % value
	if group == "mind_belief" and id == "self_defectiveness":
		character.mind[id] = clampf(value, 0.0, 1.0)
		character_changed.emit(group, id, value)
		return
	var container: Dictionary
	var field := group
	if group == "trait_levels" or group == "hexaco":
		container = character.personality
	else:
		container = character.mind
	var values: Dictionary = container.get(field, {}).duplicate()
	if group == "trait_levels" and values.is_empty():
		# Editing a legacy character must preserve all other selected traits.
		for name in Schema.TRAIT_SLIDERS:
			values[name] = Traits.weight(container.get("traits", []), String(name))
	values[id] = value
	container[field] = values
	character_changed.emit(group, id, value)