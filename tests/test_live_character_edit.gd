extends "res://tests/test_base.gd"
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")
const Wardrobe := preload("res://scripts/assets/subculture_wardrobe.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Session := preload("res://scripts/character/character_edit_session.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
func _ready():
	run.call_deferred()
func run():
	get_node("/root/GameClock").running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	Assets.enabled = false
	var world = Main.new()
	world.net_config = {"mode":"offline","hud":false,"camera":false,"visuals":false,"audio":false}
	add_child(world)
	var sim = world.get_sims()[0]
	var key = String(sim.name)
	var read = world.read_character_edit(key)
	check(read["ok"] and read["revision"]==0,"full character available on offline authority")
	check(read["data"].has("mind") and not sim.look.has("mind"),"private data stays out of public look")
	var original = read["data"].duplicate(true)
	read["data"]["body"]["height_cm"] = 180
	check(world.read_character_edit(key)["data"]==original,"reads cannot mutate authority")
	check(not world.read_character_edit(key,99)["ok"],"untrusted peer cannot read private data")
	var cd = CharacterData.new()
	cd.set_from_dict(original)
	var session = Session.new()
	session.begin(cd)
	var draft = Wardrobe.apply_to_character(session.draft(),"kawaii_kocka","bezne")
	session.replace_draft(draft)
	check(sim.look["clothing"]["bezne"]==original["clothing"]["bezne"],"wardrobe draft leaves live actor unchanged")
	session.cancel()
	check(world.read_character_edit(key)["data"]==original,"cancel does not mutate authoritative data")
	sim.mental.stress = 37.0
	sim.mental.sensitivity = 0.91
	sim.sensory.crowd_habit = 0.23
	sim.sensory.noise_habit = 0.37
	sim.relationships["Petr Dvořák"] = 14.0
	var mental_before = sim.mental.to_dict().duplicate(true)
	var needs_before = sim.needs.values.duplicate(true)
	var rng_before = sim.rng.state
	var sensory_before = sim.sensory.to_dict().duplicate(true)
	var relationships_before = sim.relationships.duplicate(true)
	var apply = world.apply_character_edit(key,draft,0)
	check(apply["ok"] and apply["revision"]==1,"validated wardrobe commits with new revision")
	check(sim.look["clothing"]["bezne"]["top"]=="kawaii_kocici_mikina","live public appearance receives hoodie")
	check(sim.visual.look_params["outfit_top"]=="kawaii_kocici_mikina","visual resolver receives hoodie")
	check(sim.mental.to_dict()==mental_before,"wardrobe preserves entire mental state")
	check(sim.needs.values==needs_before and sim.rng.state==rng_before,"wardrobe preserves needs and simulation RNG")
	check(sim.sensory.to_dict()==sensory_before,"wardrobe preserves adaptive sensory state")
	check(sim.relationships==relationships_before,"wardrobe preserves relationships")
	check(world.apply_character_edit(key,draft,0)["reason"]=="conflict","stale second editor rejected")
	var current = world.read_character_edit(key)
	check(world.apply_character_edit(key,current["data"],1)["changed"]==false,"no-op apply does not increment revision")
	var bad = current["data"].duplicate(true)
	bad["body"]["height_cm"]=-5.0
	check(world.apply_character_edit(key,bad,1)["reason"]=="invalid","invalid update rejected")
	check(world.read_character_edit(key)==current,"invalid update changes neither data nor revision")
	bad = current["data"].duplicate(true)
	bad["uid"]=CharacterData.new_uid()
	check(world.apply_character_edit(key,bad,1)["reason"]=="identity_changed","UID replacement rejected")
	bad = current["data"].duplicate(true)
	bad["identity"]["first_name"]="Robin"
	check(world.apply_character_edit(key,bad,1)["reason"]=="identity_edit_pending","rename cannot orphan name-keyed relations")
	var p = current["data"].duplicate(true)
	p["personality"]["trait_levels"]={"optimista":0.3,"brucoun":0.7}
	check(world.apply_character_edit(key,p,1)["ok"],"continuous personality reaches live actor")
	check(abs(Traits.weight(sim.trait_profile,"brucoun")-.7)<.001,"live actor consumes exact strength")
	check(sim.needs.values==needs_before and sim.relationships==relationships_before,"personality edit preserves needs and relations")
	check(is_equal_approx(sim.mental.sensitivity,0.91),"personality edit preserves learned mental sensitivity")
	check(sim.sensory.noise_habit==0.37 and sim.sensory.crowd_habit==0.23,"personality preserves sensory habituation")
	check(sim.rng.state==rng_before and sim.mental.dep.to_dict()==mental_before["dep"],"personality preserves RNG and depression history")
	p = world.read_character_edit(key)["data"]
	p["personality"]["trait_levels"]={}
	p["personality"]["traits"]=["optimista"]
	check(world.apply_character_edit(key,p,2)["ok"],"legacy profile restore applies")
	check(sim.trait_profile==["optimista"] and sim.trait_ids==["optimista"],"cleared sliders do not leave stale weighted profile")
	check(abs(sim.mental.trait_vuln-Traits.sum_param(["optimista"],"vulnerability"))<.001,"legacy vulnerability recomputed")
	var mind_edit = world.read_character_edit(key)["data"]
	mind_edit["mind"]["predispositions"]["anxiety"] = 0.65
	check(world.apply_character_edit(key,mind_edit,3)["ok"],"live predisposition edit accepted")
	check(is_equal_approx(sim.mental.conditions.get("anxiety",0.0),0.65),"live predisposition reaches mental state")
	check(is_equal_approx(sim.mental.sensitivity,0.91),"mind edit preserves learned mental sensitivity")
	check(sim.sensory.noise_habit==0.37 and sim.sensory.crowd_habit==0.23,"mind edit preserves sensory habituation")
	check(sim.mental.stress==37.0 and sim.rng.state==rng_before,"mind edit preserves stress and RNG")
	# Initialization callers still get the specified baseline.
	sim.set_conditions({"anxiety":0.65})
	check(is_equal_approx(sim.mental.sensitivity,sim.mental.baseline_sensitivity(sim.mental_cfg())),"spawn condition setup initializes baseline")
	for mode in [world.net.Mode.HOST,world.net.Mode.DEDICATED,world.net.Mode.CLIENT]:
		world.net.mode=mode
		check(not world.read_character_edit(key)["ok"] and not world.apply_character_edit(key,p,3)["ok"],"network edit fails closed mode "+str(mode))
	world.net.mode=world.net.Mode.OFFLINE
	world.unregister_sim(sim)
	check(not world.read_character_edit(key)["ok"] and not world._character_records.has(key),"despawn removes private editor record")
	session.cancel()
	world.queue_free()
	await get_tree().process_frame
	Assets.enabled=true
	finish("test_live_character_edit")
