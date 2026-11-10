extends Control
## Parametric clothing workshop. An isolated preview, portable recipes and draft-only Apply.
const Design=preload("res://scripts/clothing/garment_design.gd")
const Library=preload("res://scripts/clothing/garment_library.gd")
const Preview=preload("res://scripts/ui/character_preview.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Schema=preload("res://scripts/character/character_schema.gd")
signal design_applied(recipe:Dictionary)
var allow_apply:=true
var library_directory:String=Library.DIR
var _source:Dictionary={}
var _slot:="bezne"
var _recipe:Dictionary=Design.create()
var _history:Array=[]
var _cursor:=0
var _merge_key:=""
var _last_edit_ms:=0
var _loading:=false
var _queued:=false
var _preview:VBoxContainer
var _name_edit:LineEdit
var _kind:OptionButton
var _base:OptionButton
var _fabric:OptionButton
var _pattern:OptionButton
var _primary:ColorPickerButton
var _accent:ColorPickerButton
var _details:CheckBox
var _sliders:Dictionary={}
var _value_labels:Dictionary={}
var _rows:Dictionary={}
var _status:Label
var _saved:OptionButton
var _saved_items:Array=[]
var _code:TextEdit
var _code_panel:VBoxContainer
var _body:BoxContainer
var _preview_column:VBoxContainer
var _scroll:ScrollContainer
var _undo:Button
var _redo:Button
var _apply:Button
var _profile:=0
var _pose:=0
var _focus:=false

func _ready()->void:
	name="ClothingStudio"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new()
	shade.color=Color(.035,.04,.065,.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",8)
	margin.add_child(layout)
	var title:=Label.new()
	title.text="Dílna oblečení"
	title.add_theme_font_size_override("font_size",24)
	layout.add_child(title)
	var help:=Label.new()
	help.text="Vyber základ, uprav střih a látku. Návrh ulož nebo přenes do rozpracované postavy."
	if not allow_apply:help.text="Ulož vlastní návrh. V editoru postavy ho potom otevři v dílně a obleč na postavu."
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)
	_body=BoxContainer.new()
	_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	_preview_column=VBoxContainer.new()
	_preview_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_child(_preview_column)
	_preview=Preview.new()
	_preview_column.add_child(_preview)
	# Keep rotation controls; anatomy and finger tooling belong in the character editor.
	for child in _preview.get_children():
		if child is Control and child.name in ["AnatomyGestureRow","IndividualFingerControls","AnatomyLayerRow"]:child.hide()
	for child in _preview.get_children():
		if child is Button:child.hide()
	_preview._model_note.hide()
	_preview._image.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_preview._image.custom_minimum_size.y=220
	_preview.viewport.size=Vector2i(600,600)
	var views:=HBoxContainer.new()
	_preview_column.add_child(views)
	var profile:=OptionButton.new()
	profile.name="TestBody"
	profile.fit_to_longest_item=false
	profile.clip_text=true
	profile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for label in ["Aktuální postava","Drobná postava","Robustní postava"]:profile.add_item(label)
	profile.item_selected.connect(_on_profile)
	views.add_child(profile)
	var pose:=OptionButton.new()
	pose.name="TestPose"
	pose.fit_to_longest_item=false
	pose.clip_text=true
	pose.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for label in ["Klid","Ohnuté lokty","Zvednuté paže"]:pose.add_item(label)
	pose.item_selected.connect(_on_pose)
	views.add_child(pose)
	var focus:=CheckButton.new()
	focus.name="FocusGarment"
	focus.text="Detail oblečení"
	focus.toggled.connect(_on_focus)
	_preview_column.add_child(focus)
	_scroll=ScrollContainer.new()
	_scroll.name="GarmentControls"
	_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	var controls:=VBoxContainer.new()
	controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation",7)
	_scroll.add_child(controls)
	var presets:=OptionButton.new()
	presets.name="GarmentPresets"
	presets.fit_to_longest_item=false
	presets.clip_text=true
	presets.add_item("Začít z předvolby…")
	for label in ["Kawaii kočičí mikina","Pruhované tričko","Punková kostka","Saténové šaty s puntíky","Goth sukně","Denim kalhoty"]:presets.add_item(label)
	presets.item_selected.connect(_on_preset)
	controls.add_child(presets)
	_name_edit=LineEdit.new()
	_name_edit.name="DesignName"
	_name_edit.max_length=48
	_name_edit.placeholder_text="Název návrhu"
	_name_edit.text_changed.connect(_on_name)
	controls.add_child(_name_edit)
	_kind=_choices(controls,"Druh oblečení",Design.KINDS,"GarmentKind")
	_kind.item_selected.connect(_on_kind)
	_base=_choices(controls,"Základní střih",{},"GarmentBase")
	_base.item_selected.connect(_on_base)
	_fabric=_choices(controls,"Látka / textura",Design.FABRICS,"GarmentFabric")
	_fabric.item_selected.connect(_on_choice.bind("fabric",_fabric))
	_pattern=_choices(controls,"Vzor",Design.PATTERNS,"GarmentPattern")
	_pattern.item_selected.connect(_on_choice.bind("pattern",_pattern))
	var colors:=HBoxContainer.new()
	controls.add_child(colors)
	_primary=_color_button(colors,"Hlavní barva","MainColor")
	_primary.color_changed.connect(_on_color.bind("color"))
	_accent=_color_button(colors,"Druhá barva","AccentColor")
	_accent.color_changed.connect(_on_color.bind("accent"))
	for entry in [["length","Délka lemu",.6,1.15],["ease","Volnost střihu",0.0,1.0],["sleeve_length","Délka rukávů",.45,1.0],["cuff_flare","Rozšíření manžet",0.0,1.0],["pattern_scale","Hustota vzoru",.5,4.0],["roughness","Matnost látky",.25,1.0]]:
		_add_slider(controls,entry)
	_details=CheckBox.new()
	_details.name="GarmentDetails"
	_details.text="Kapuce, kapsy, ozdoby a aplikace"
	_details.toggled.connect(_on_details)
	controls.add_child(_details)
	controls.add_child(HSeparator.new())
	var saved_title:=Label.new()
	saved_title.text="Moje uložené návrhy"
	controls.add_child(saved_title)
	_saved=_choices(controls,"Vybrat uložený návrh",{},"SavedGarments")
	_saved.item_selected.connect(_on_saved)
	var save:=Button.new()
	save.name="SaveGarment"
	save.text="Uložit návrh do mých návrhů"
	save.pressed.connect(_save)
	controls.add_child(save)
	var share:=Button.new()
	share.name="ShareGarment"
	share.text="Import / export návrhu (JSON)"
	share.pressed.connect(_toggle_share)
	controls.add_child(share)
	_code_panel=VBoxContainer.new()
	_code_panel.visible=false
	controls.add_child(_code_panel)
	var share_help:=Label.new()
	share_help.text="Zkopíruj návrh pro přenos, nebo vlož JSON cizího návrhu a načti jej."
	share_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_code_panel.add_child(share_help)
	_code=TextEdit.new()
	_code.name="GarmentJSON"
	_code.custom_minimum_size.y=140
	_code.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	_code_panel.add_child(_code)
	var share_actions:=HBoxContainer.new()
	_code_panel.add_child(share_actions)
	_button(share_actions,"Načíst JSON",_import)
	_button(share_actions,"Kopírovat",_copy)
	_status=Label.new()
	_status.name="GarmentStatus"
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var actions:=GridContainer.new()
	actions.name="StudioActions"
	actions.columns=2
	layout.add_child(actions)
	_undo=_button(actions,"Zpět",undo_design)
	_redo=_button(actions,"Znovu",redo_design)
	_apply=_button(actions,"Použít v návrhu postavy",_accept)
	_apply.name="ApplyGarment"
	_apply.visible=allow_apply
	_button(actions,"Zavřít",close_studio).name="CloseStudio"
	if _source.is_empty():
		_source=CD.create().to_dict()
		_source.identity.first_name="Alex"
		_source.personality.traits=["aktivni"]
	_history=[_recipe.duplicate(true)]
	call_deferred("_load_ready")
	get_viewport().size_changed.connect(_responsive)
	_responsive()

func _load_ready()->void:
	_reload_saved()
	_refresh_controls()
	_refresh_preview()

func _choices(parent:Node,caption:String,catalog:Dictionary,node_name:String)->OptionButton:
	var label:=Label.new()
	label.text=caption
	parent.add_child(label)
	var picker:=OptionButton.new()
	picker.name=node_name
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item=false
	picker.clip_text=true
	for key in catalog:
		picker.add_item(catalog[key])
		picker.set_item_metadata(picker.item_count-1,key)
	parent.add_child(picker)
	return picker
func _button(parent:Node,caption:String,callback:Callable)->Button:
	var button:=Button.new()
	button.text=caption
	button.custom_minimum_size.y=36
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _color_button(parent:Node,caption:String,node_name:String)->ColorPickerButton:
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label:=Label.new()
	label.text=caption
	column.add_child(label)
	var picker:=ColorPickerButton.new()
	picker.name=node_name
	picker.edit_alpha=false
	picker.custom_minimum_size.y=36
	column.add_child(picker)
	return picker
func _add_slider(parent:Node,entry:Array)->void:
	var row:=VBoxContainer.new()
	parent.add_child(row)
	_rows[entry[0]]=row
	var label:=Label.new()
	row.add_child(label)
	_value_labels[entry[0]]=label
	label.set_meta("caption",entry[1])
	var slider:=HSlider.new()
	slider.name="Garment_"+entry[0]
	slider.min_value=entry[2]
	slider.max_value=entry[3]
	slider.step=.01
	slider.custom_minimum_size.y=28
	slider.drag_started.connect(_begin_drag)
	slider.value_changed.connect(_on_slider.bind(entry[0]))
	row.add_child(slider)
	_sliders[entry[0]]=slider
func _catalog(kind:String)->Dictionary:
	return Schema.TOPS if kind=="top" else (Schema.BOTTOMS if kind=="bottom" else Schema.SHOES)
func _select(picker:OptionButton,value:String)->void:
	for i in picker.item_count:
		if picker.get_item_metadata(i)==value:picker.select(i);return
func _supported(recipe:Dictionary)->bool:
	return _catalog(recipe.kind).has(recipe.base) and recipe.base not in ["zadne","bosy"]

func open_design(data:Dictionary,kind:String="top",slot:String="bezne")->void:
	_source=data.duplicate(true)
	_slot=slot if Schema.OUTFIT_CATEGORIES.has(slot) else "bezne"
	var outfit:Dictionary=_source.get("clothing",{}).get(_slot,{})
	var base:String=outfit.get(kind,"mikina" if kind=="top" else ("dziny" if kind=="bottom" else "tenisky"))
	if base in ["zadne","bosy"]:base="mikina" if kind=="top" else ("dziny" if kind=="bottom" else "tenisky")
	var checked:Dictionary=Design.validate(outfit.get("designs",{}).get(kind,{}))
	_recipe=checked.data if checked.ok and _supported(checked.data) else Design.create(kind,base)
	if not checked.ok:_recipe.color=outfit.get("top_color" if kind=="top" else "bottom_color","#aaaaaa")
	_history=[_recipe.duplicate(true)]
	_cursor=0
	if is_node_ready():_refresh_controls();_refresh_preview()

func recipe()->Dictionary:return _recipe.duplicate(true)
func change(key:String,value:Variant)->bool:
	if not key in Design.FIELDS:return false
	var next:Dictionary=_recipe.duplicate(true)
	next[key]=value
	return _replace(next,key)
func _replace(next:Dictionary,key:String="")->bool:
	var check:Dictionary=Design.validate(next)
	if not check.ok or not _supported(check.data):return false
	if check.data==_recipe:return true
	_recipe=check.data
	if _cursor<_history.size()-1:_history=_history.slice(0,_cursor+1)
	var now:int=Time.get_ticks_msec()
	if not key.is_empty() and _merge_key==key and _cursor>0 and now-_last_edit_ms<600:
		_history[_cursor]=_recipe.duplicate(true)
	else:
		_history.append(_recipe.duplicate(true))
		if _history.size()>64:_history.pop_front()
		_cursor=_history.size()-1
	_merge_key=key
	_last_edit_ms=now
	_refresh_controls()
	_queue_preview()
	return true
func _refresh_controls()->void:
	if not is_node_ready():return
	_loading=true
	if _name_edit.text!=_recipe.name:_name_edit.text=_recipe.name
	_select(_kind,_recipe.kind)
	_base.clear()
	for id in _catalog(_recipe.kind):
		if id in ["zadne","bosy"]:continue
		_base.add_item(_catalog(_recipe.kind)[id])
		_base.set_item_metadata(_base.item_count-1,id)
	_select(_base,_recipe.base)
	_select(_fabric,_recipe.fabric)
	_select(_pattern,_recipe.pattern)
	_primary.color=Color.html(_recipe.color)
	_accent.color=Color.html(_recipe.accent)
	_details.set_pressed_no_signal(_recipe.details)
	for key in _sliders:
		_sliders[key].set_value_no_signal(_recipe[key])
		_value_labels[key].text=String(_value_labels[key].get_meta("caption"))+": "+str(roundi(float(_recipe[key])*100))+" %"
		_rows[key].visible=not (_recipe.kind=="shoes" and key in ["length","ease","sleeve_length","cuff_flare"])
		if key in ["sleeve_length","cuff_flare"]:
			_rows[key].visible=_recipe.kind=="top" and _recipe.base in ["mikina","kawaii_kocici_mikina","svetr","rolak","sako","kosile","emo_mikina","kawaii_svetr","harajuku_bunda","grunge_kosile","visualkei_sako"]
	_undo.disabled=_cursor<=0
	_redo.disabled=_cursor>=_history.size()-1
	_loading=false
func _queue_preview()->void:
	if _queued:return
	_queued=true
	call_deferred("_refresh_preview")
func _refresh_preview()->void:
	_queued=false
	if not is_node_ready():return
	var draft:Dictionary=Design.put_on_character(_source,_recipe,_slot)
	if draft.is_empty():return
	if _profile>0:
		draft.body.merge({"frame":.1 if _profile==1 else .9,"body_fat":.1 if _profile==1 else .7,"muscle":.2 if _profile==1 else .7,"shoulders":.2 if _profile==1 else .85},true)
	_preview.show_draft(draft)
	var visual:Node3D=_preview.visual
	if visual.uses_model():
		if visual._anim!=null:visual._anim.stop()
		var sk:Skeleton3D=visual._skeleton()
		for suffix in ["l","r"]:
			sk.set_bone_pose_rotation(sk.find_bone("forearm_"+suffix),Quaternion(Vector3.RIGHT,-PI/2 if _pose==1 else 0.0))
			sk.set_bone_pose_rotation(sk.find_bone("upper_arm_"+suffix),Quaternion(Vector3.FORWARD,(.6 if suffix=="l" else -.6) if _pose==2 else 0.0))
		sk.force_update_all_bone_transforms()
	var target_y:float=.94
	_preview.camera.size=2.05
	if _focus:
		target_y=1.18 if _recipe.kind=="top" else (.6 if _recipe.kind=="bottom" else .13)
		_preview.camera.size=1.0 if _recipe.kind=="top" else (1.2 if _recipe.kind=="bottom" else .48)
	_preview.camera.position=Vector3(0,target_y,4)
	_preview.camera.look_at(Vector3(0,target_y,0))
func _responsive()->void:
	var narrow:bool=get_viewport_rect().size.x<760
	_body.vertical=narrow
	_preview_column.size_flags_stretch_ratio=1.1
	_scroll.size_flags_stretch_ratio=1.0
	_preview._image.custom_minimum_size.y=160 if narrow else 320
	_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_preview_column.size_flags_vertical=Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y=100
func _begin_drag()->void:_merge_key=""
func _on_slider(value:float,key:String)->void:
	if not _loading:change(key,value)
func _on_color(value:Color,key:String)->void:
	if not _loading:change(key,"#"+value.to_html(false))
func _on_name(value:String)->void:
	if not _loading and not value.strip_edges().is_empty():change("name",value)
func _on_choice(index:int,key:String,picker:OptionButton)->void:
	if not _loading and index>=0:change(key,picker.get_item_metadata(index))
func _on_details(value:bool)->void:
	if not _loading:change("details",value)
func _on_kind(index:int)->void:
	if _loading:return
	var kind:String=_kind.get_item_metadata(index)
	var next:Dictionary=_recipe.duplicate(true)
	next.kind=kind
	next.base="mikina" if kind=="top" else ("dziny" if kind=="bottom" else "tenisky")
	_replace(next)
func _on_base(index:int)->void:
	if not _loading:change("base",_base.get_item_metadata(index))
func _on_focus(on:bool)->void:_focus=on;_queue_preview()
func _on_profile(index:int)->void:_profile=index;_queue_preview()
func _on_pose(index:int)->void:_pose=index;_queue_preview()
func _on_preset(index:int)->void:
	if index==0:return
	var choices:Array=[
		{"kind":"top","base":"kawaii_kocici_mikina","name":"Moje kočičí mikina","fabric":"fleece","color":"#e18fbd","accent":"#f6e6f1"},
		{"kind":"top","base":"tricko","name":"Pruhované tričko","fabric":"cotton","pattern":"stripes","color":"#30313d","accent":"#ddd7df"},
		{"kind":"bottom","base":"punk_kostka","name":"Punková kostka","fabric":"cotton","pattern":"checks","color":"#8d2946","accent":"#1d202b"},
		{"kind":"top","base":"saty","name":"Puntíkované saténové šaty","fabric":"satin","pattern":"dots","color":"#346b78","accent":"#f3ead9","roughness":.35},
		{"kind":"bottom","base":"goth_sukne","name":"Dlouhá goth sukně","fabric":"satin","color":"#25202f","accent":"#803f69"},
		{"kind":"bottom","base":"dziny","name":"Vlastní denim kalhoty","fabric":"denim","color":"#4f6e95","accent":"#b3bbc9"}]
	var next:Dictionary=Design.create()
	next.merge(choices[index-1],true)
	_replace(next)
func undo_design()->void:
	if _cursor<=0:return
	_cursor-=1
	_recipe=_history[_cursor].duplicate(true)
	_merge_key=""
	_refresh_controls()
	_queue_preview()
func redo_design()->void:
	if _cursor>=_history.size()-1:return
	_cursor+=1
	_recipe=_history[_cursor].duplicate(true)
	_merge_key=""
	_refresh_controls()
	_queue_preview()
func _save()->void:
	var result:Dictionary=Library.save_design(_recipe,library_directory)
	_status.text="Návrh je uložený v mých návrzích." if result.ok else String(result.get("error","Uložení návrhu selhalo."))
	if result.ok:_reload_saved()
func _reload_saved()->void:
	if _saved==null:return
	_saved_items=Library.list_designs(library_directory)
	_saved.clear()
	_saved.add_item("Vybrat návrh…")
	for item in _saved_items:_saved.add_item(String(item.design.name))
func _on_saved(index:int)->void:
	if index<=0 or index>_saved_items.size():return
	if _replace(_saved_items[index-1].design):_status.text="Uložený návrh je načtený do dílny."
func export_json()->String:return Design.to_json(_recipe)
func import_json(text:String)->bool:
	var result:Dictionary=Design.from_json(text)
	if not result.ok or not _supported(result.data):
		_status.text="Návrh se nepodařilo načíst: "+("neznámý základní střih" if result.ok else str(result.errors[0]))
		return false
	_replace(result.data)
	_status.text="Návrh byl načtený. Před uložením ho můžeš upravit."
	return true
func _toggle_share()->void:
	_code_panel.visible=not _code_panel.visible
	if _code_panel.visible:_code.text=export_json()
func _import()->void:import_json(_code.text)
func _copy()->void:
	_code.text=export_json()
	DisplayServer.clipboard_set(_code.text)
	_status.text="JSON návrhu je připravený ke kopírování."
func _accept()->void:
	var checked:Dictionary=Design.validate(_recipe)
	if not allow_apply or not checked.ok or not _supported(checked.data):return
	design_applied.emit(checked.data.duplicate(true))
	queue_free()
func close_studio()->void:queue_free()
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:close_studio()
		elif event.ctrl_pressed and event.keycode==KEY_Z:undo_design()
		elif event.ctrl_pressed and event.keycode==KEY_Y:redo_design()
		else:return
		get_viewport().set_input_as_handled()
