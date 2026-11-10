extends Control
const Doc=preload("res://scripts/city/furniture_document.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
var data:Dictionary=Doc.preset("dining_chair")
var selected:=0
var history:Array=[]
var future:Array=[]
var saved:=""
var updating:=false
var pending:Callable
var list:ItemList
var inspector:ScrollContainer
var layout:BoxContainer
var status:Label
var title_edit:LineEdit
var part_name:LineEdit
var dimensions:Dictionary={}
var materials:OptionButton
var colors:ColorPickerButton
var collision:CheckBox
var templates:OptionButton
var files:OptionButton
var confirm:ConfirmationDialog
var viewport:SubViewport
var preview:Node3D
var camera:Camera3D
var highlight:MeshInstance3D
var yaw:=35.0
var elevation:=25.0
var zoom:=1.0
var filename:=""
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color(.045,.065,.085);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin);var outer:=VBoxContainer.new();margin.add_child(outer)
	var heading:=Label.new();heading.text="Dílna nábytku · Life Simulator";heading.add_theme_font_size_override("font_size",24);outer.add_child(heading)
	var bar:=HFlowContainer.new();outer.add_child(bar)
	button(bar,"Nový",func():guard(func():replace({"version":1,"name":"Nový nábytek","parts":[]})))
	button(bar,"Kvádr +",func():add_part("box"));button(bar,"Válec +",func():add_part("cylinder"))
	button(bar,"Duplikovat",duplicate_part);button(bar,"Smazat díl",delete_part)
	button(bar,"Zpět",undo);button(bar,"Znovu",redo)
	button(bar,"Katalog M2",func():guard(func():get_tree().change_scene_to_file("res://scenes/city/m2_catalog_showcase.tscn")))
	var row:=HFlowContainer.new();outer.add_child(row)
	templates=OptionButton.new();templates.accessibility_name="Předloha nábytku";row.add_child(templates)
	for key in B.Fixture.catalog().entries:
		templates.add_item(B.Fixture.catalog().entries[key].label);templates.set_item_metadata(templates.item_count-1,key)
		if key=="dining_chair":templates.select(templates.item_count-1)
	button(row,"Použít předlohu",func():guard(apply_template))
	layout=BoxContainer.new();layout.size_flags_vertical=Control.SIZE_EXPAND_FILL;outer.add_child(layout)
	inspector=ScrollContainer.new();inspector.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;layout.add_child(inspector)
	var form:=VBoxContainer.new();form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector.add_child(form)
	label(form,"Název návrhu")
	title_edit=LineEdit.new();title_edit.max_length=80;title_edit.accessibility_name="Název návrhu";form.add_child(title_edit)
	title_edit.text_submitted.connect(func(_value):flush_names())
	title_edit.focus_exited.connect(flush_names)
	label(form,"Díly · výběr pro úpravy")
	list=ItemList.new();list.custom_minimum_size.y=110;list.accessibility_name="Díly nábytku";form.add_child(list)
	list.item_selected.connect(func(i):selected=i;refresh())
	part_name=LineEdit.new();part_name.max_length=80;part_name.accessibility_name="Název vybraného dílu";form.add_child(part_name)
	part_name.text_submitted.connect(func(_value):flush_names())
	part_name.focus_exited.connect(flush_names)
	var grid:=GridContainer.new();grid.columns=4;form.add_child(grid)
	for text in ["","X","Y","Z"]:label(grid,text)
	for spec in [["size","Rozměry",.001,8.0],["position","Pozice",-10.0,10.0],["rotation","Otočení",-180.0,180.0]]:
		label(grid,spec[1]);dimensions[spec[0]]=[]
		for axis in 3:
			var spin:=SpinBox.new();spin.min_value=spec[2];spin.max_value=spec[3];spin.step=.001 if spec[0]=="size" else (.01 if spec[0]=="position" else 1.0)
			spin.custom_minimum_size.x=66;spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			spin.accessibility_name=spec[1]+" "+["X","Y","Z"][axis];spin.get_line_edit().accessibility_name=spin.accessibility_name
			grid.add_child(spin);dimensions[spec[0]].append(spin)
			spin.value_changed.connect(func(value):if not updating:var a:Array=data.parts[selected].get(spec[0],[0,0,0]).duplicate();a[axis]=value;edit_part(spec[0],a))
	label(form,"Povrch a barva")
	materials=OptionButton.new();materials.accessibility_name="Materiál vybraného dílu";form.add_child(materials)
	for id in B.Fixture.catalog().materials.keys()+Doc.Surfaces.ids():materials.add_item(id);materials.set_item_metadata(materials.item_count-1,id)
	materials.item_selected.connect(func(i):if not updating:edit_part("material",materials.get_item_metadata(i)))
	colors=ColorPickerButton.new();colors.text="Odstín dílu";colors.edit_alpha=false;colors.accessibility_name="Barva vybraného dílu";form.add_child(colors)
	colors.color_changed.connect(func(c):if not updating:edit_part("tint",[c.r,c.g,c.b]))
	collision=CheckBox.new();collision.text="Pevný díl (kolize)";collision.accessibility_name=collision.text;form.add_child(collision)
	collision.toggled.connect(func(value):if not updating:edit_part("collide",value))
	var note:=label(form,"Vlastní návrhy jsou dekorace. Ověřené interakce spustíš v Katalogu M2. Rozměry jsou v metrech, otočení ve stupních. Název potvrď Enterem.")
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(right)
	var container:=SubViewportContainer.new();container.stretch=true;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;container.custom_minimum_size.y=220;right.add_child(container)
	viewport=SubViewport.new();viewport.size=Vector2i(800,600);viewport.world_3d=World3D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;viewport.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.16,.2);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;viewport.add_child(env)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;viewport.add_child(camera)
	var controls:=HFlowContainer.new();right.add_child(controls)
	for spec in [["Otočit vlevo",-30],["Otočit vpravo",30]]:button(controls,spec[0],func():yaw+=spec[1];view_camera())
	button(controls,"Shora",func():elevation=75;view_camera());button(controls,"Zepředu",func():yaw=0;elevation=15;view_camera())
	button(controls,"Přiblížit",func():zoom=minf(zoom*1.25,3);view_camera());button(controls,"Oddálit",func():zoom=maxf(zoom/1.25,.5);view_camera())
	var disk:=HFlowContainer.new();outer.add_child(disk)
	button(disk,"Uložit JSON",save_draft);files=OptionButton.new();files.accessibility_name="Uložené návrhy";disk.add_child(files)
	button(disk,"Otevřít",request_open)
	button(disk,"Export scény",func():export_draft("tscn"));button(disk,"Export GLB",func():export_draft("glb"))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.accessibility_name="Stav dílny";outer.add_child(status)
	confirm=ConfirmationDialog.new();confirm.title="Neuložené úpravy";confirm.dialog_text="Pokračováním zahodíš neuložené úpravy. Ulož je nejdřív tlačítkem Uložit JSON.";confirm.ok_button_text="Zahodit a pokračovat";add_child(confirm);confirm.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	confirm.confirmed.connect(func():if pending.is_valid():pending.call())
	resized.connect(responsive);refresh_files();saved=JSON.stringify(data);refresh();responsive();announce("Vyber díl, uprav rozměry a povrch. Ctrl+S uloží, Ctrl+Z vrátí změnu.")
func label(parent:Node,text:String) -> Label:
	var item:=Label.new();item.text=text;parent.add_child(item);return item
func button(parent:Node,text:String,callback:Callable) -> Button:
	var item:=Button.new();item.text=text;item.accessibility_name=text;item.pressed.connect(callback);parent.add_child(item);return item
func announce(text:String) -> void:status.text=text
func responsive() -> void:
	if layout==null:return
	layout.vertical=size.x<760
	inspector.custom_minimum_size=Vector2(0,235) if layout.vertical else Vector2(315,0)
	inspector.size_flags_vertical=Control.SIZE_EXPAND_FILL
func guard(callback:Callable) -> void:
	flush_names()
	if JSON.stringify(data)!=saved:pending=callback;confirm.popup_centered(Vector2i(maxi(280,mini(int(size.x)-32,440)),180))
	else:callback.call()
func replace(next:Dictionary) -> void:
	data=next.duplicate(true);selected=0;history.clear();future.clear();saved=JSON.stringify(data);filename=""
	for i in templates.item_count:
		if B.Fixture.catalog().entries[templates.get_item_metadata(i)].label==data.name:templates.select(i)
	refresh();announce("Nový návrh připraven.")
func commit(next:Dictionary) -> bool:
	var error:=Doc.validate(next)
	if not error.is_empty():announce(error);return false
	if next==data:return true
	history.append(data.duplicate(true))
	if history.size()>60:history.pop_front()
	future.clear();data=next.duplicate(true);selected=clampi(selected,0,maxi(0,data.parts.size()-1));refresh();return true
func edit_part(key:String,value:Variant) -> void:
	if updating or selected<0 or selected>=data.parts.size():return
	var next:=data.duplicate(true);next.parts[selected][key]=value;commit(next)
func add_part(shape:String) -> void:
	if data.parts.size()>=Doc.MAX_PARTS:announce("Nejvýše 64 dílů.");return
	var next:=data.duplicate(true);next.parts.append({"name":"Díl "+str(next.parts.size()+1),"shape":shape,"size":[.5,.1,.5],"position":[0,.5,0],"rotation":[0,0,0],"material":"wood","tint":[1,1,1],"collide":true});selected=next.parts.size()-1;commit(next)
func duplicate_part() -> void:
	if data.parts.size()>=Doc.MAX_PARTS:announce("Nejvýše 64 dílů.");return
	if data.parts.is_empty():return
	var next:=data.duplicate(true);var p:Dictionary=next.parts[selected].duplicate(true);p.position[0]=minf(float(p.position[0])+.1,10);p.name=(p.name+" kopie").left(80);next.parts.append(p);selected=next.parts.size()-1;commit(next)
func delete_part() -> void:
	if data.parts.is_empty():return
	var next:=data.duplicate(true);next.parts.remove_at(selected);commit(next)
func undo() -> void:
	if history.is_empty():return
	future.append(data.duplicate(true));data=history.pop_back();selected=clampi(selected,0,maxi(data.parts.size()-1,0));refresh()
func redo() -> void:
	if future.is_empty():return
	history.append(data.duplicate(true));data=future.pop_back();selected=clampi(selected,0,maxi(data.parts.size()-1,0));refresh()
func refresh() -> void:
	if list==null:return
	updating=true;list.clear();title_edit.text=data.name
	for p in data.parts:list.add_item(p.name)
	var empty:bool=data.parts.is_empty();part_name.editable=not empty;materials.disabled=empty;colors.disabled=empty;collision.disabled=empty
	for group in dimensions.values():
		for spin in group:spin.editable=not empty
	if not empty:
		selected=clampi(selected,0,data.parts.size()-1);list.select(selected);var p:Dictionary=data.parts[selected];part_name.text=p.name
		for key in dimensions:
			var values:Array=p.get(key,[0,0,0])
			for axis in 3:dimensions[key][axis].value=values[axis]
		for i in materials.item_count:
			if materials.get_item_metadata(i)==p.material:materials.select(i)
		var tint:Array=p.get("tint",[1,1,1]);colors.color=Color(tint[0],tint[1],tint[2]);collision.button_pressed=p.get("collide",true)
	else:part_name.text=""
	updating=false
	if preview!=null:preview.free()
	preview=Doc.build(data);viewport.add_child(preview)
	if not empty:
		var pivot:Node3D=preview.get_node("Parts").get_child(selected);var a:=B.bounds(pivot)
		highlight=MeshInstance3D.new();var box:=BoxMesh.new();box.size=a.size+Vector3.ONE*.008;highlight.mesh=box;highlight.position=a.get_center()
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.1,.9,.6,.15);mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;highlight.material_override=mat;pivot.add_child(highlight)
	view_camera()
func view_camera() -> void:
	if preview==null:return
	# Selection overlay is preview-only, excluded from document exports.
	var a:=B.bounds(preview);var center:=a.get_center();var radius:=maxf(maxf(a.size.x,a.size.z),maxf(a.size.y,.5))
	camera.size=radius*1.7/zoom;var r:=deg_to_rad(yaw);var e:=deg_to_rad(elevation)
	camera.position=center+Vector3(sin(r)*cos(e),sin(e),cos(r)*cos(e))*maxf(radius*3,3);camera.look_at(center,Vector3.UP)
func refresh_files() -> void:
	files.clear();DirAccess.make_dir_recursive_absolute(Doc.DIRECTORY)
	for file in DirAccess.get_files_at(Doc.DIRECTORY):
		if file.ends_with(".json"):files.add_item(file)
	if files.item_count>0:files.select(0)
	for i in files.item_count:
		if files.get_item_text(i)==filename.get_file():files.select(i)
func save_draft() -> void:
	flush_names()
	filename=Doc.path_for(data.name);var error:=Doc.save(data,filename)
	if error==OK:saved=JSON.stringify(data);refresh_files();announce("Uloženo: "+filename)
	else:announce("Uložení selhalo: "+error_string(error))
func open_draft(path:String) -> void:
	var result:=Doc.read(path)
	if result.has("error"):announce(result.error);return
	replace(result.data);filename=path;saved=JSON.stringify(data);announce(("Obnoveno ze zálohy: " if result.recovered else "Otevřeno: ")+path)
func export_draft(extension:String) -> void:
	var path:=Doc.path_for(data.name,extension);var error:=Doc.export_file(data,path)
	announce("Exportováno: "+path if error==OK else "Export selhal: "+error_string(error))
func _unhandled_key_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode!=KEY_S and get_viewport().gui_get_focus_owner() is LineEdit:return
		match event.keycode:
			KEY_S:save_draft()
			KEY_Z:redo() if event.shift_pressed else undo()
			KEY_Y:redo()
			KEY_D:duplicate_part()
			_:return
		get_viewport().set_input_as_handled()

func apply_template() -> void:replace(Doc.preset(templates.get_selected_metadata()))
func request_open() -> void:
	var index:int=files.selected
	if index<0 or index>=files.item_count:announce("Vyber uložený návrh.");return
	var path:String=Doc.DIRECTORY+files.get_item_text(index)
	guard(func():open_draft(path))

func flush_names() -> void:
	if updating or not is_inside_tree() or title_edit==null or part_name==null:return
	var next:=data.duplicate(true);next.name=title_edit.text
	if selected>=0 and selected<next.parts.size():next.parts[selected].name=part_name.text
	commit(next)
