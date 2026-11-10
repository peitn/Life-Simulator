extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const Doc=preload("res://scripts/city/furniture_document.gd")
const B=preload("res://scripts/city/m2_fixture_builder.gd")
var passed:=0
var failed:=0
func check(ok:bool,label:String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL ",label)
func press(editor:Node,text:String) -> void:
	for button in editor.find_children("*","Button",true,false):
		if button.text==text:button.pressed.emit();return
	check(false,"button exists "+text)
func _init() -> void:call_deferred("run")
func run() -> void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or not G.owns(args[0]):quit(2);return
	for kind in B.Fixture.catalog().entries:
		var draft:=Doc.preset(kind);check(Doc.validate(draft).is_empty(),kind+" editable template")
		var node:=Doc.build(draft);var expected:=B.build(kind)
		check(B.bounds(node).position.distance_to(B.bounds(expected).position)<.0001 and B.bounds(node).end.distance_to(B.bounds(expected).end)<.0001,kind+" template shape dimensions")
		node.free();expected.free()
	for mutation in ["nan","huge","script","path","shape","rotation","color","count","bool","string_vector","null_vector","bool_version"]:
		var d:=Doc.preset("dining_chair")
		match mutation:
			"nan":d.parts[0].size[0]=NAN
			"huge":d.parts[0].position[0]=1000000
			"script":d.parts[0].script="res://main.gd"
			"path":d.parts[0].material="res://main.gd"
			"shape":d.parts[0].shape="script"
			"rotation":d.parts[0].rotation=[0,1]
			"color":d.parts[0].tint=[1,INF,1]
			"count":d.parts.resize(65)
			"bool":d.parts[0].collide="yes"
			"string_vector":d.parts[0].size=[".5",0.5,0.5]
			"null_vector":d.parts[0].size=[null,0.5,0.5]
			"bool_version":d.version=true
		check(not Doc.validate(d).is_empty(),mutation+" malformed data rejected")
	check(not Doc.allowed("res://main.gd") and not Doc.allowed("user://furniture_editor/../game.json") and not Doc.allowed("user://furniture_editor/.json"),"storage traversal and hidden filename rejected")
	var elliptical:=Doc.preset("dining_table")
	elliptical.parts.append({"name":"Elliptical support","shape":"cylinder","size":[.6,1.3,.9],"position":[-1,.4,.2],"rotation":[35,50,-20],"material":"plaster_sage","tint":[.7,.9,.6],"collide":true})
	check(Doc.validate(elliptical).is_empty(),"nonuniform rotated cylinder accepted")
	var ellipse_path:String=Doc.DIRECTORY+"ellipse-test-"+args[0]+".glb"
	check(Doc.export_file(elliptical,ellipse_path)==OK,"mapped rotated elliptical GLB export")
	var ellipse_doc:=GLTFDocument.new();var ellipse_state:=GLTFState.new();check(ellipse_doc.append_from_file(ellipse_path,ellipse_state)==OK,"elliptical GLB reload")
	var ellipse_node:=ellipse_doc.generate_scene(ellipse_state);var ellipse_original:=Doc.build(elliptical)
	check(B.bounds(ellipse_node).position.distance_to(B.bounds(ellipse_original).position)<.0001 and B.bounds(ellipse_node).end.distance_to(B.bounds(ellipse_original).end)<.0001,"elliptical rotation and dimensions survive GLB")
	var mapped:=false;var mesh_data_ok:=true
	for m in ellipse_node.find_children("*","MeshInstance3D",true,false):
		var mat=m.get_active_material(0)
		if mat is StandardMaterial3D and mat.normal_enabled:
			mapped=mat.normal_texture!=null and mat.albedo_texture!=null and mat.roughness_texture!=null
			var arrays=m.mesh.surface_get_arrays(0)
			mesh_data_ok=mesh_data_ok and arrays[Mesh.ARRAY_TANGENT].size()==arrays[Mesh.ARRAY_VERTEX].size()*4
			for n in arrays[Mesh.ARRAY_NORMAL]:mesh_data_ok=mesh_data_ok and n.is_finite() and absf(n.length()-1)<.001
	check(mapped,"custom GLB retains albedo normal and roughness maps")
	check(mesh_data_ok,"resized elliptical mapped export keeps unit normals and tangents")
	ellipse_node.free();ellipse_original.free();DirAccess.remove_absolute(ellipse_path)
	var path:String=Doc.DIRECTORY+"test-"+args[0]+".json";var original:=Doc.preset("dining_table")
	check(Doc.save(original,path)==OK,"first atomic save")
	var updated:=original.duplicate(true);updated.name="Updated table"
	check(Doc.save(updated,path)==OK,"overwrite keeps backup")
	var saved:=Doc.read(path);check(saved.get("data",{})==JSON.parse_string(JSON.stringify(updated)) and not saved.recovered,"JSON roundtrip")
	var bad:=updated.duplicate(true);bad.parts[0].size[0]=-1
	check(Doc.save(bad,path)!=OK and Doc.read(path).data==JSON.parse_string(JSON.stringify(updated)),"invalid save preserves good primary")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("{broken");file.close()
	var recovered:=Doc.read(path);check(recovered.get("data",{})==JSON.parse_string(JSON.stringify(original)) and recovered.recovered,"corrupt primary recovers previous verified backup")
	for extension in ["tscn","glb"]:
		var export_path:String=path.get_basename()+"."+extension
		check(Doc.export_file(original,export_path)==OK,"export "+extension)
		var loaded:Node3D
		if extension=="tscn":loaded=load(export_path).instantiate()
		else:
			var document:=GLTFDocument.new();var state:=GLTFState.new();check(document.append_from_file(export_path,state)==OK,"custom GLB readable");loaded=document.generate_scene(state)
		var expected:=Doc.build(original)
		check(B.bounds(loaded).position.distance_to(B.bounds(expected).position)<.0001 and B.bounds(loaded).end.distance_to(B.bounds(expected).end)<.0001,"custom "+extension+" measured geometry survives roundtrip")
		if extension=="tscn":check(loaded.find_children("*","StaticBody3D",true,false).size()==original.parts.size(),"exported scene retains collisions")
		assert(G.owns(args[0]));check(DirAccess.copy_absolute(export_path,"res://docs/city/furniture_editor_example."+extension)==OK,"saved reviewable "+extension+" example")
		loaded.free();expected.free();DirAccess.remove_absolute(export_path)
	assert(G.owns(args[0]));file=FileAccess.open("res://docs/city/furniture_editor_example.json",FileAccess.WRITE);file.store_string(JSON.stringify(original,"\t"));file.close()
	for suffix in ["",".bak",".tmp",".bak.tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var editor=load("res://scenes/city/furniture_editor.tscn").instantiate();root.add_child(editor)
	await process_frame;await process_frame
	check(editor.list.item_count==6 and editor.materials.item_count==29,"real UI loads chair and full material palette")
	editor.title_edit.grab_focus();editor.title_edit.text="Rozepsaný návrh";editor.templates.grab_focus();await process_frame
	check(editor.data.name=="Rozepsaný návrh","focus loss commits typed draft name")
	editor.part_name.grab_focus();editor.part_name.text="Rozepsaný díl";editor.templates.grab_focus();await process_frame
	check(editor.data.parts[editor.selected].name=="Rozepsaný díl","focus loss commits typed part name")
	var count:int=editor.data.parts.size();press(editor,"Kvádr +")
	check(editor.data.parts.size()==count+1,"actual Add button creates part")
	press(editor,"Zpět");check(editor.data.parts.size()==count,"actual Undo button")
	press(editor,"Znovu");check(editor.data.parts.size()==count+1,"actual Redo button")
	editor.dimensions.size[0].value=.73;check(absf(editor.data.parts[editor.selected].size[0]-.73)<.0001,"actual inspector dimension updates geometry")
	var mi:int=editor.materials.item_count-1;editor.materials.select(mi);editor.materials.item_selected.emit(mi)
	check(editor.data.parts[editor.selected].material==editor.materials.get_item_metadata(mi),"actual material picker")
	editor.colors.color_changed.emit(Color(.2,.4,.7));check(B.vec(editor.data.parts[editor.selected].tint).distance_to(Vector3(.2,.4,.7))<.0001,"actual color picker")
	press(editor,"Duplikovat");check(editor.data.parts.size()==count+2,"actual duplicate button")
	press(editor,"Smazat díl");check(editor.data.parts.size()==count+1,"actual delete button")
	var key:=InputEventKey.new();key.keycode=KEY_Z;key.ctrl_pressed=true;key.pressed=true;editor._unhandled_key_input(key)
	check(editor.data.parts.size()==count+2,"keyboard Ctrl Z")
	editor.title_edit.text="test_"+args[0];press(editor,"Uložit JSON");var user_path:String=editor.filename
	check(FileAccess.file_exists(user_path) and editor.saved==JSON.stringify(editor.data),"actual save button")
	editor.add_part("box");press(editor,"Otevřít")
	check(editor.confirm.visible and editor.data.parts.size()==count+3,"actual Open button protects dirty draft")
	editor.confirm.confirmed.emit();editor.confirm.hide()
	check(editor.data.parts.size()==count+2,"confirmed actual Open button reloads saved draft")
	editor.files.select(-1);editor.request_open();check("Vyber" in editor.status.text,"missing file selection fails cleanly")
	for surface in Doc.Surfaces.ids():
		var first=Doc.Surfaces.make(surface);var second=Doc.Surfaces.make(surface)
		check(first!=null and first.normal_enabled and first.roughness_texture!=null and first!=second,surface+" independent mapped PBR material")
	for dimensions in [Vector2i(1280,900),Vector2i(640,900),Vector2i(390,844)]:
		root.size=dimensions;editor.size=dimensions
		for i in 4:await process_frame
		check(editor.layout.vertical==(dimensions.x<760),"responsive orientation "+str(dimensions.x))
		check(editor.get_minimum_size().x<=dimensions.x and editor.layout.size.x<=dimensions.x,"no horizontal overflow "+str(dimensions.x))
		check(editor.viewport.size.x>100 and editor.viewport.size.y>100,"usable preview "+str(dimensions.x))
	editor.queue_free();await process_frame
	for suffix in ["",".bak",".tmp",".bak.tmp"]:
		if FileAccess.file_exists(user_path+suffix):DirAccess.remove_absolute(user_path+suffix)
	print("FURNITURE_EDITOR ",passed,"/",passed+failed," failed=",failed)
	quit(0 if failed==0 else 1)
