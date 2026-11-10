extends SceneTree
const Main=preload("res://main.gd")
const Assets=preload("res://scripts/assets/asset_library.gd")
const Design=preload("res://scripts/clothing/garment_design.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	root.get_node("GameClock").running=false
	var settings=root.get_node("GameSettings")
	settings.persist=false
	settings.reset()
	Assets.enabled=true
	var world=Main.new()
	world.net_config={"mode":"offline","hud":true,"camera":false,"visuals":true,"audio":false,"autoload":false,"autosave":false,"save_directory":"user://clothing-integration-"+str(OS.get_process_id())}
	root.add_child(world)
	await process_frame
	var sim=world.get_selected_sim()
	check(sim!=null,"real selected actor")
	var key:String=String(sim.name)
	var before:Dictionary=world.read_character_edit(key).data.duplicate(true)
	world.hud._edit_button.pressed.emit()
	var editor=world.hud._character_editor
	check(editor!=null,"real HUD opens authorized character editor")
	editor._open_clothing_studio()
	var studio=editor._clothing_studio
	await process_frame
	await process_frame
	check(studio!=null and studio._preview.visual!=sim.visual,"workshop is a separate actual visual")
	var changed:Dictionary=Design.create("top","mikina")
	changed.pattern="checks"
	changed.color="#733a9d"
	changed.accent="#ead39c"
	changed.sleeve_length=.6
	changed.ease=.3
	changed.length=.7
	changed.name="Integration jacket"
	check(studio.import_json(Design.to_json(changed)),"UI imports a complete custom garment")
	studio._accept()
	await process_frame
	check(editor._session.draft().clothing.bezne.designs.top.name==changed.name,"studio Apply updates parent draft")
	check(world.read_character_edit(key).data==before,"draft garment does not change authority")
	check(editor._visual_preview.public_snapshot().clothing.bezne.designs.top.pattern=="checks","parent preview immediately shows custom garment")
	editor._on_undo()
	check(editor._session.draft()==before,"parent Undo restores pre-workshop character")
	editor._on_redo()
	check(editor._session.draft().clothing.bezne.designs.top.pattern=="checks","parent Redo restores garment")
	editor._on_apply()
	await process_frame
	var accepted:Dictionary=world.read_character_edit(key).data
	check(accepted.clothing.bezne.designs.top.name==changed.name,"authoritative Apply stores reusable design")
	check(sim.visual.look_params.garment_designs.top.pattern=="checks","live actor receives custom design after Apply")
	# QA 11/2026: the live world uses the game asset path (async C5 wardrobe since 7 Nov 2026), so the
	# patterned garment replaces the placeholder a few frames after Apply – wait for it.
	var wait_until_ms:=Time.get_ticks_msec()+60000
	while sim.visual.wardrobe_waiting() and Time.get_ticks_msec()<wait_until_ms:
		await process_frame
	check(not sim.visual.wardrobe_waiting(),"live actor wardrobe finished building (async game path)")
	check(sim.visual._c5_nodes.any(func(mi):return mi.material_override is ShaderMaterial),"live actor actually wears patterned garment")
	check(sim.visual._garment_midriff!=null and sim.visual._garment_midriff.visible,"live cropped garment has underlying body skin")
	check(world.save_game("manual").get("ok",false),"real household save accepts custom clothing")
	var result:Dictionary=world.load_game("manual")
	check(result.get("ok",false),"real household save reloads")
	await process_frame
	var restored=world.get_selected_sim()
	check(restored.look.clothing.bezne.designs.top.name==changed.name,"custom design survives full save/reload")
	check(restored.visual.look_params.garment_designs.top.pattern=="checks","restored actor rebuilds actual custom rendering")
	check(restored.visual._garment_midriff!=null and restored.visual._garment_midriff.visible,"cropped garment reconstructs its body surface after reload")
	# Creator receives the same design through its own isolated session.
	if is_instance_valid(world.hud._character_editor):world.hud._character_editor._on_cancel()
	await process_frame
	world.hud._create_button.pressed.emit()
	var creator=world.hud._character_creator
	check(creator!=null,"real creator opens")
	creator._open_clothing_studio()
	await process_frame
	var workshop=creator._clothing_studio
	check(workshop.import_json(Design.to_json(changed)),"creator workshop loads same portable recipe")
	workshop._accept()
	await process_frame
	check(creator._session.draft().clothing.bezne.designs.top.name==changed.name,"creator accepts custom garment draft")
	check(world.sims.size()==3,"designing does not spawn actors")
	creator._on_cancel()
	await process_frame
	world.hud._open_clothing_studio()
	await process_frame
	check(world.hud._clothing_studio!=null and not world.hud._clothing_studio.allow_apply,"standalone HUD workshop cannot mutate live authority")
	world.hud._clothing_studio.close_studio()
	world.queue_free()
	await process_frame
	print("CLOTHING_INTEGRATION_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
