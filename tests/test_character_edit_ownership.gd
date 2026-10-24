extends "res://tests/test_base.gd"
## Security-policy regression only. No remote RPC/edit feature is enabled.
const Main := preload("res://main.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	get_node("/root/GameClock").running = false
	var gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	Assets.enabled = false
	var world = Main.new()
	world.net_config = {"mode":"offline","hud":false,"camera":false,"visuals":false,"audio":false}
	add_child(world)
	var sim = world.get_sims()[0]
	var key := String(sim.name)
	var initial := world.read_character_edit(key)
	check(initial.get("ok",false), "server has canonical character record")
	var uid := String(initial["data"].get("uid",""))
	var net = world.net
	check(not net.server_can_edit_character(2,key), "offline mode denies network ownership predicate")
	net.mode = net.Mode.HOST
	net._connected = true
	net.players[2] = {"sim":key,"own":true}
	check(not net.server_can_edit_character(2,key), "unmarked household sim cannot be edited")
	sim.set_meta("player_character",true)
	sim.set_meta("character_uid",uid)
	check(net.server_can_edit_character(2,key), "server-owned character and canonical UID accepted")
	check(not net.server_can_edit_character(3,key), "unknown sender rejected")
	check(not net.server_can_edit_character(0,key), "zero sender rejected")
	check(not net.server_can_edit_character(2,"other"), "other character rejected")
	check(not net.server_can_edit_character(2,12), "non-string character ID rejected")
	net.players[2]["own"] = false
	check(not net.server_can_edit_character(2,key), "household controller is not editor owner")
	net.players[2]["own"] = true
	sim.set_meta("character_uid","forged")
	check(not net.server_can_edit_character(2,key), "UID mismatch rejected")
	sim.set_meta("character_uid",uid)
	net.players[3] = {"sim":key,"own":true}
	check(not net.server_can_edit_character(2,key), "duplicate server ownership rejected")
	net.players.erase(3)
	net._connected = false
	check(not net.server_can_edit_character(2,key), "disconnected server denies")
	net._connected = true
	net.mode = net.Mode.CLIENT
	check(not net.server_can_edit_character(2,key), "client cannot authorize edit")
	net.mode = net.Mode.DEDICATED
	check(net.server_can_edit_character(2,key), "dedicated authority policy accepts assigned own character")
	net.players.erase(2)
	check(not net.server_can_edit_character(2,key), "disconnect/removal invalidates ownership")
	check(not world.read_character_edit(key).get("ok",false), "network private read still disabled")
	check(not world.apply_character_edit(key,initial["data"],0).get("ok",false), "network Apply still disabled")
	check(not net.server_can_edit_character(2,null), "null sim ID rejected")
	check(not net.server_can_edit_character(2,NodePath(key)), "NodePath sim ID rejected")
	check(not net.server_can_edit_character(2,{}), "Dictionary sim ID rejected")
	check(not net.server_can_edit_character(2,world), "Object sim ID rejected")
	check(not net.server_can_edit_character(2,""), "empty sim ID rejected")
	check(not net.server_can_edit_character(2,"../"+key), "path traversal sim ID rejected")
	net.players[2] = {"sim":key,"own":true}
	check(net.server_can_edit_character(2,key), "valid owner accepted before teardown")
	# Preflight is a non-mutating transport guard, NOT a network edit RPC.
	var wire := PackedByteArray([123,125])
	var revision := int(world._character_revisions[key])
	check(not net.server_preflight_character_edit(3,key,revision,wire).get("ok",false), "preflight rejects unknown sender")
	check(not net.server_preflight_character_edit(2,"other",revision,wire).get("ok",false), "preflight rejects wrong character")
	check(not net.server_preflight_character_edit(2,key,"0",wire).get("ok",false), "preflight rejects string revision")
	check(not net.server_preflight_character_edit(2,key,-1,wire).get("ok",false), "preflight rejects negative revision")
	check(not net.server_preflight_character_edit(2,key,revision+1,wire).get("ok",false), "preflight rejects stale or future revision")
	check(not net.server_preflight_character_edit(2,key,revision,{}).get("ok",false), "preflight rejects dictionary payload")
	check(not net.server_preflight_character_edit(2,key,revision,PackedByteArray()).get("ok",false), "preflight rejects empty payload")
	check(not net.server_preflight_character_edit(2,key,revision,PackedByteArray().duplicate()).get("ok",false), "preflight rejects second empty payload")
	var oversized := PackedByteArray()
	oversized.resize(net.EDIT_MAX_WIRE_BYTES+1)
	check(not net.server_preflight_character_edit(2,key,revision,oversized).get("ok",false), "preflight rejects oversized payload")
	var max_wire := PackedByteArray()
	max_wire.resize(net.EDIT_MAX_WIRE_BYTES)
	check(net.server_preflight_character_edit(2,key,revision,max_wire).get("ok",false), "preflight accepts bounded wire envelope")
	check(net.server_preflight_character_edit(2,key,revision,wire).get("ok",false), "preflight allows second bounded request")
	check(net.server_preflight_character_edit(2,key,revision,wire).get("ok",false), "preflight allows third bounded request")
	var throttled: Dictionary = net.server_preflight_character_edit(2,key,revision,wire)
	check(not throttled.get("ok",false) and throttled.get("reason")=="rate_limited", "preflight rate limits fourth request")
	check(world._character_revisions[key]==revision, "preflight does not commit or advance revision")
	net._edit_limiters.clear()
	check(net.server_preflight_character_edit(2,key,revision,wire).get("ok",false), "fresh limiter permits bounded request")
	net.players[2]["own"]=false
	check(not net.server_preflight_character_edit(2,key,revision,wire).get("ok",false), "ownership loss blocks preflight despite existing limiter")
	net.players[2]["own"]=true

	# Candidate decoding consumes the preflight limiter; reset only between fixtures.
	net._edit_limiters.clear()
	var valid_wire := JSON.stringify(initial["data"]).to_utf8_buffer()
	var prepared: Dictionary = net.server_prepare_character_edit(2,key,revision,valid_wire)
	check(prepared.get("ok",false), "current schema JSON candidate accepted")
	check(world._character_records[key].to_dict()==initial["data"], "prepare leaves canonical record untouched")
	check(world._character_revisions[key]==revision, "prepare does not reserve revision")
	if prepared.get("ok",false):
		prepared["data"]["body"]["height_cm"]=190
	check(world._character_records[key].to_dict()==initial["data"], "prepared candidate does not alias canonical data")
	for malformed in ["{", "[]", "null", "42"]:
		net._edit_limiters.clear()
		var r: Dictionary=net.server_prepare_character_edit(2,key,revision,malformed.to_utf8_buffer())
		check(not r.get("ok",false) and not r.has("data"), "reject malformed/non-object JSON "+malformed)
	for field in ["uid","v","identity","body"]:
		var candidate: Dictionary=initial["data"].duplicate(true)
		if field=="uid": candidate["uid"]="forged"
		elif field=="v": candidate["v"]=float(candidate["v"])+.5
		elif field=="identity": candidate["identity"]["first_name"]="Other"
		else: candidate.erase("body")
		net._edit_limiters.clear()
		var r: Dictionary=net.server_prepare_character_edit(2,key,revision,JSON.stringify(candidate).to_utf8_buffer())
		check(not r.get("ok",false) and not r.has("data"), "reject immutable/missing field "+field)
	var invalid: Dictionary=initial["data"].duplicate(true)
	invalid["body"]["height_cm"]=9999
	net._edit_limiters.clear()
	check(not net.server_prepare_character_edit(2,key,revision,JSON.stringify(invalid).to_utf8_buffer()).get("ok",false), "strict ranges reject invalid height")
	net._edit_limiters.clear()
	var denied: Dictionary=net.server_prepare_character_edit(3,key,revision,valid_wire)
	check(not denied.get("ok",false) and not denied.has("data"), "unauthorized request receives no private data")
	check(not net.server_prepare_character_edit(2,key,revision+1,valid_wire).get("ok",false), "candidate stale revision rejected")
	net._edit_limiters.clear()
	for i in 3: net.server_prepare_character_edit(2,key,revision,"{".to_utf8_buffer())
	check(net.server_prepare_character_edit(2,key,revision,valid_wire).get("reason")=="rate_limited", "invalid JSON consumes decoder rate budget")
	check(world._character_records[key].to_dict()==initial["data"], "all rejected candidates leave canonical record untouched")
	var edited: Dictionary=initial["data"].duplicate(true)
	edited["personality"]["trait_levels"]={"optimista":.49,"brucoun":.51}
	net._edit_limiters.clear()
	var accepted: Dictionary=net.server_prepare_character_edit(2,key,revision,JSON.stringify(edited).to_utf8_buffer())
	check(accepted.get("ok",false), "valid continuous personality candidate accepted")
	check(accepted.get("data",{}).get("personality",{}).get("trait_levels",{}).get("optimista")==.49, "decoder preserves continuous intensity")
	var old_schema: Dictionary=initial["data"].duplicate(true)
	old_schema["v"]=7
	net._edit_limiters.clear()
	check(net.server_prepare_character_edit(2,key,revision,JSON.stringify(old_schema).to_utf8_buffer()).get("reason")=="schema_mismatch", "live edit rejects legacy migration")
	check(world._character_records[key].to_dict()==initial["data"], "accepted edit is preparation only, no commit")
	# H2b: exercise the real server-internal commit sink, not just preflight.
	# This is NOT a public RPC; unauthorized clients must never reach this path.
	var commit_candidate: Dictionary=initial["data"].duplicate(true)
	commit_candidate["body"]["height_cm"]=180
	commit_candidate["personality"]["trait_levels"]={"optimista":.49,"brucoun":.51}
	var commit_wire: PackedByteArray=JSON.stringify(commit_candidate).to_utf8_buffer()
	net._edit_limiters.clear()
	check(not world.server_apply_character_edit(3,key,revision,commit_wire).get("ok",false), "server commit denies unassigned peer")
	check(world._character_revisions[key]==revision, "denied commit preserves canonical revision")
	net.players[2]["own"]=false
	net._edit_limiters.clear()
	check(not world.server_apply_character_edit(2,key,revision,commit_wire).get("ok",false), "server commit denies revoked owner")
	net.players[2]["own"]=true
	net._edit_limiters.clear()
	check(not world.server_apply_character_edit(2,key,revision+1,commit_wire).get("ok",false), "server commit denies wrong revision")
	check(world._character_records[key].to_dict()==initial["data"], "denied commits preserve canonical data")
	net._edit_limiters.clear()
	var committed: Dictionary=world.server_apply_character_edit(2,key,revision,commit_wire)
	check(committed.get("ok",false) and committed.get("changed",false), "server commit accepts authorized validated edit")
	check(world._character_revisions[key]==revision+1, "successful server commit increments revision once")
	check(world._character_records[key].to_dict()["body"]["height_cm"]==180, "server commit updates canonical body")
	check(world._character_records[key].to_dict()["personality"]["trait_levels"]["optimista"]==.49, "server commit preserves continuous personality")
	check(sim.look==world._character_records[key].public_snapshot(), "server commit refreshes public live appearance")
	net._edit_limiters.clear()
	check(not world.server_apply_character_edit(2,key,revision,commit_wire).get("ok",false), "stale replay cannot commit twice")
	net._edit_limiters.clear()
	var unchanged: Dictionary=world.server_apply_character_edit(2,key,revision+1,commit_wire)
	check(unchanged.get("ok",false) and not unchanged.get("changed",true), "identical server commit is a no-op")
	check(world._character_revisions[key]==revision+1, "no-op does not increment revision")
	sim.queue_free()
	check(not net.server_can_edit_character(2,key), "queued-for-deletion sim rejected")
	net.mode = net.Mode.OFFLINE
	world.queue_free()
	await get_tree().process_frame
	Assets.enabled = true
	finish("test_character_edit_ownership")