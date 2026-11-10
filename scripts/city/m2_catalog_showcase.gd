extends Node3D
## Standalone catalogue and production-action playground; main lot stays owned
## by the main implementation sequence (M6/M7 integration).
const Main=preload("res://main.gd")
const Actions=preload("res://scripts/sim/action_library.gd")
const Fixture=preload("res://scripts/city/m2_fixture.gd")
const Furniture=preload("res://scripts/city/m2_furniture.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
const Surfaces=preload("res://scripts/city/m2_surfaces.gd")
var world:Node3D
var current:Node3D
var camera:Camera3D
var picker:OptionButton
var action_button:Button
var door_button:Button
var state_label:Label
var info:Label
var panel:VBoxContainer
var clock:Node
var next_actor:=0
var angle:=25.0
var origin:=Vector3(24,0,0)
var keys:Array=[]
var action_id:=""
func _ready() -> void:
	clock=get_node("/root/GameClock");clock.running=false
	world=Main.new();world.net_config={"mode":"offline","hud":false,"camera":false,"visuals":true,"audio":false,"autoload":false,"autosave":false};add_child(world)
	# Hide starter-lot decorative meshes in this isolated catalogue only.
	for child in world.get_children():
		if child is MeshInstance3D:child.hide()
	for sim in world.sims:sim.command({"id":"cancel"},null);sim.think_cooldown=100000;sim.position=Vector3(40,0,0)
	var floor:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(12,.1,12);floor.mesh=mesh;floor.position=origin+Vector3(0,-.05,0);var floor_mat:=B.material("enamel");floor_mat.albedo_color=Color(.28,.33,.38);floor_mat.roughness=1;floor.material_override=floor_mat;add_child(floor)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.6;add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;add_child(camera)
	var ui:=CanvasLayer.new();add_child(ui)
	var scroll:=ScrollContainer.new();scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);scroll.offset_left=12;scroll.offset_top=12;scroll.offset_right=-12;scroll.custom_minimum_size.y=200;ui.add_child(scroll)
	panel=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(panel)
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",18);panel.add_child(info)
	var bar:=HFlowContainer.new();panel.add_child(bar)
	picker=OptionButton.new();picker.accessibility_name="Katalog M2";bar.add_child(picker)
	for kind in Furniture.DEFINITIONS:keys.append(kind);picker.add_item(Furniture.DEFINITIONS[kind].label)
	for kind in Fixture.catalog().entries:keys.append(kind);picker.add_item(Fixture.catalog().entries[kind].label)
	for kind in ["window_wide","window_double","window_arch","door_panelled","door_glazed","door_metal"]:keys.append(kind);picker.add_item(kind)
	picker.item_selected.connect(select)
	action_button=button(bar,"Použít dalším Simem",use_next)
	button(bar,"Čas + 5 minut",func():advance_minutes(5))
	button(bar,"Dokončit akce",finish_actions)
	button(bar,"Zrušit akce",cancel_actions)
	door_button=button(bar,"Otevřít / zavřít dveře",func():if current.has_method("request_open"):current.request_open(not current.is_open()))
	button(bar,"Otočit náhled",func():angle+=45;view_camera())
	button(bar,"Dílna nábytku",func():get_tree().change_scene_to_file("res://scenes/city/furniture_editor.tscn"))
	var surfaces:=OptionButton.new();surfaces.accessibility_name="Náhled povrchu";bar.add_child(surfaces);surfaces.add_item("Původní povrch")
	for id in Surfaces.ids():surfaces.add_item(id);surfaces.set_item_metadata(surfaces.item_count-1,id)
	surfaces.item_selected.connect(func(i):surface_selected(i,surfaces))
	state_label=Label.new();state_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(state_label)
	select(0);get_viewport().size_changed.connect(view_camera)
func button(parent:Node,text:String,callback:Callable) -> Button:
	var b:=Button.new();b.text=text;b.accessibility_name=text;b.pressed.connect(callback);parent.add_child(b);return b
func cancel_actions() -> void:
	for sim in world.sims:sim.command({"id":"cancel"},null);sim.think_cooldown=100000
func select(index:int) -> void:
	picker.select(index)
	cancel_actions()
	for sim in world.sims:sim.position=Vector3(40,0,0)
	if current!=null:world.smart_objects.erase(current);current.free()
	var kind:String=keys[index];current=load("res://scenes/city/m2_"+kind+".tscn").instantiate();add_child(current);current.position=origin;next_actor=0
	action_id={"sofa":"relax","bed_single":"sleep","bed_double":"sleep","fridge":"snack"}.get(kind,Fixture.catalog().entries.get(kind,{}).get("action",""))
	if not action_id.is_empty():world.smart_objects.append(current)
	action_button.disabled=action_id.is_empty();door_button.disabled=not current.has_method("request_open")
	info.text="Life Simulator · Katalog M2 · "+picker.get_item_text(index)+(" · akce: "+action_id if not action_id.is_empty() else " · stavební / dekorativní objekt")
	view_camera()
func use_next() -> void:
	if action_id.is_empty():return
	var actor:Node3D=world.sims[next_actor%world.sims.size()];next_actor+=1
	actor.command({"id":"cancel"},null);actor.think_cooldown=100000
	for key in actor.needs.values:actor.needs.values[key]=70.0
	var slot:int=mini(current.users.size(),current.capacity-1)
	actor.global_position=current.to_global(current.use_offsets[slot])+current.global_basis*Vector3(0,0,.55)
	actor.command(Actions.get_action(action_id),current)
func advance_minutes(minutes:float) -> void:
	for i in ceili(minutes/.25):
		clock.advance(.25)
		for sim in world.sims:
			if sim.state==sim.State.IDLE:sim.think_cooldown=100000
func finish_actions() -> void:
	if current.get("users")==null:return
	for i in 2400:
		if current.users.is_empty():break
		advance_minutes(.5)
func apply_surface(id:String) -> void:
	for mesh in current.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var original=mesh.get_active_material(i)
			if original is BaseMaterial3D and original.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
			mesh.set_surface_override_material(i,Surfaces.make(id))
func view_camera() -> void:
	if current==null:return
	var bounds:=B.bounds(current);var center:Vector3=current.to_global(bounds.get_center());var r:=deg_to_rad(angle)
	var viewport_size:=get_viewport().get_visible_rect().size
	camera.size=maxf(5,maxf(bounds.size.x,bounds.size.z)*1.8)*maxf(1,.8*viewport_size.y/maxf(viewport_size.x,1));camera.position=center+Vector3(sin(r)*7,4,cos(r)*7);camera.look_at(center,Vector3.UP)
	# Shift content down under the wrapping catalogue controls.
	camera.v_offset=1.0
func _process(_delta:float) -> void:
	if current==null or state_label==null:return
	var lines:=""
	for sim in world.sims:
		if sim.target==current:lines+=sim.sim_name+": "+sim.display_action()+" | "+sim.current_posture()+"\n"
	state_label.text=("Obsazeno: "+str(current.users.size())+" / "+str(current.capacity)+"\n" if current.get("users")!=null else "")+lines+"Čas je ručně krokovaný. Interakce používají skutečný SimAgent a rezervace SmartObject."

func surface_selected(index:int,options:OptionButton) -> void:
	if index==0:select(picker.selected)
	else:apply_surface(options.get_item_metadata(index))
