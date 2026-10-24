extends "res://tests/test_base.gd"
const Main=preload("res://main.gd")
const Assets=preload("res://scripts/assets/asset_library.gd")
const Wardrobe=preload("res://scripts/assets/subculture_wardrobe.gd")
const Traits=preload("res://scripts/sim/traits.gd")
var world
var key:String
func _ready(): run.call_deferred()
func submit(data,revision,peer=2):
	return world.server_apply_character_edit(peer,key,revision,JSON.stringify(data).to_utf8_buffer())
func run():
	get_node("/root/GameClock").running=false
	var gs=get_node("/root/GameSettings")
	gs.persist=false
	gs.reset()
	Assets.enabled=false
	world=Main.new()
	world.net_config={"mode":"offline","hud":false,"camera":false,"visuals":false,"audio":false}
	add_child(world)
	var sim=world.get_sims()[0]
	key=String(sim.name)
	var initial=world.read_character_edit(key)["data"]
	var net=world.net
	net.mode=net.Mode.DEDICATED
	net._connected=true
	net.players[2]={"sim":key,"own":true}
	sim.set_meta("player_character",true)
	sim.set_meta("character_uid",initial["uid"])
	sim.mental.stress=37.0
	sim.mental.sensitivity=.91
	sim.sensory.noise_habit=.37
	var mental=sim.mental.to_dict().duplicate(true)
	var sensory=sim.sensory.to_dict().duplicate(true)
	var needs=sim.needs.values.duplicate(true)
	var relationships=sim.relationships.duplicate(true)
	var rng=sim.rng.state
	var draft=Wardrobe.apply_to_character(initial,"kawaii_kocka","bezne")
	var unauthorized=submit(draft,0,3)
	check(not unauthorized.get("ok",false) and not unauthorized.has("data"),"unknown sender denied without private response")
	check(world._character_records[key].to_dict()==initial,"denial leaves canonical data unchanged")
	var result=submit(draft,0)
	check(result.get("ok",false) and result.get("revision")==1,"owner commits validated wardrobe once")
	check(not result.has("data") and not result.has("wire"),"commit result has no private snapshot")
	check(sim.look["clothing"]["bezne"]["top"]=="kawaii_kocici_mikina","server public appearance updates")
	check(not sim.look.has("mind") and not sim.look.get("personality",{}).has("trait_levels") and not sim.look.get("personality",{}).has("psyche_seed") and not sim.look.get("personality",{}).has("aspirations"),"public appearance excludes private psyche fields (legacy trait names are public)")
	check(sim.mental.to_dict()==mental and sim.sensory.to_dict()==sensory,"wardrobe preserves mental and learned sensory state")
	check(sim.needs.values==needs and sim.relationships==relationships and sim.rng.state==rng,"wardrobe preserves needs relations RNG")
	check(submit(draft,0).get("reason")=="conflict","duplicate old revision rejected")
	var current=world._character_records[key].to_dict()
	check(submit(current,1).get("changed")==false and world._character_revisions[key]==1,"no-op keeps revision")
	net._edit_limiters.clear()
	var p=current.duplicate(true)
	p["personality"]["trait_levels"]={"optimista":.49,"brucoun":.51}
	check(submit(p,1).get("ok",false),"continuous personality commits")
	check(is_equal_approx(Traits.weight(sim.trait_profile,"brucoun"),.51),"live trait strength remains continuous")
	check(sim.mental.sensitivity==.91 and sim.sensory.noise_habit==.37,"personality preserves adaptation")
	check(sim.mental.stress==37.0 and sim.rng.state==rng,"personality preserves stress RNG")
	check(world._character_revisions[key]==2,"personality advances revision exactly once")
	current=world._character_records[key].to_dict()
	net._edit_limiters.clear()
	for field in ["uid","identity","body"]:
		var bad=current.duplicate(true)
		if field=="uid":bad["uid"]="forged"
		elif field=="identity":bad["identity"]["first_name"]="Other"
		else:bad["body"]["height_cm"]=-5
		check(not submit(bad,2).get("ok",false),"invalid "+field+" denied at commit entry")
	check(world._character_records[key].to_dict()==current and world._character_revisions[key]==2,"invalid commits change no canonical state")
	check(submit(current,2).get("reason")=="rate_limited","invalid candidates consume bounded rate budget")
	net._edit_limiters.clear()
	# A previously prepared candidate grants no capability after ownership loss.
	var wire=JSON.stringify(current).to_utf8_buffer()
	check(net.server_prepare_character_edit(2,key,2,wire).get("ok",false),"candidate prepared before revocation")
	net.players[2]["own"]=false
	check(submit(current,2).get("reason")=="unauthorized","revoked owner cannot commit prepared content")
	net.players[2]["own"]=true
	net.players[3]={"sim":key,"own":true}
	check(submit(current,2).get("reason")=="unauthorized","duplicate server assignment fails closed")
	net.players.erase(3)
	net._edit_limiters.clear()
	# Isolate final revision guard independently of earlier preflight.
	check(world._commit_validated_character_edit(key,current,1,[]).get("reason")=="conflict","commit sink independently rechecks revision")
	check(world._character_records[key].to_dict()==current and world._character_revisions[key]==2,"final conflict guard makes no mutation")
	net.mode=net.Mode.CLIENT
	check(submit(current,2).get("reason")=="unauthorized","client mode cannot commit")
	net.mode=net.Mode.DEDICATED
	net._connected=false
	check(submit(current,2).get("reason")=="unauthorized","disconnected authority cannot commit")
	check(not world.apply_character_edit(key,current,2).get("ok",false),"UI network entry remains closed")
	net.mode=net.Mode.OFFLINE
	world.queue_free()
	await get_tree().process_frame
	Assets.enabled=true
	finish("test_character_edit_commit")
