extends SceneTree
# H2b staged Apply RPC transport. Real ENet server and two independent clients.
# The World stub commits validated data; main.gd commit semantics are separately
# exercised by test_character_edit_ownership.gd.
const Net=preload("res://tests/run-main-1792929654-164976/net_no_cooldown.gd")
const CD=preload("res://scripts/character/character_data.gd")
class ClientActor:
	extends Node3D
	var look:Dictionary={}
	func apply_public_look(data:Dictionary)->void:
		look=data.duplicate(true)
class World:
	extends Node
	# Test-only ordered fence, same reliable channel 0 as production RPCs.
	var fence_token := 0
	var received_sequence: Array[int] = []
	@rpc("any_peer", "call_remote", "reliable", 0)
	func test_sequence(value: int) -> void:
		received_sequence.append(value)
	@rpc("any_peer", "call_remote", "reliable", 0)
	func test_fence(token: int) -> void:
		fence_token = token
	func register_sim(_node: Node) -> void:
		pass
	func unregister_sim(_node: Node) -> void:
		pass
	var _character_records={}
	var _character_revisions={}
	func find_sim(key):
		return get_node_or_null(NodePath(key))
	func read_public_character_look(key:String)->Dictionary:
		if not _character_records.has(key) or not _character_revisions.has(key):
			return {"ok":false}
		return {"ok":true,"revision":_character_revisions[key],
			"look":_character_records[key].public_snapshot()}
	func server_apply_character_edit(peer_id:int, key:Variant, revision:Variant, wire:Variant)->Dictionary:
		var net=get_node("Net")
		var prepared:Dictionary=net.server_prepare_character_edit(peer_id,key,revision,wire)
		if not prepared.get("ok",false):
			return prepared
		var id=String(key)
		if not net.server_can_edit_character(peer_id,id):
			return {"ok":false,"reason":"unauthorized"}
		if _character_revisions[id]!=revision:
			return {"ok":false,"reason":"conflict"}
		var old=_character_records[id].to_dict()
		var changed=old!=prepared["data"]
		if changed:
			_character_records[id].set_from_dict(prepared["data"])
			_character_revisions[id]+=1
		return {"ok":true,"revision":_character_revisions[id],"changed":changed}
var passed=0
var failed=0
var branches=[]
var apis=[]
var peers=[]
var nets=[]
var inboxes=[[],[]]
const INC_ACTOR1 = "11111111111111111111111111111111"
const INC_ACTOR2 = "22222222222222222222222222222222"
const INC_PENDING = "33333333333333333333333333333333"
const INC_REPLACEMENT = "44444444444444444444444444444444"
func check(ok:bool,label:String):
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _init():
	call_deferred("run")
var next_fence := 0
func fence(sender: int, receiver: int) -> bool:
	next_fence += 1
	var token := next_fence
	branches[sender].test_fence.rpc_id(apis[receiver].get_unique_id(), token)
	var deadline := Time.get_ticks_msec() + 3000
	while branches[receiver].fence_token != token and Time.get_ticks_msec() < deadline:
		await process_frame
	return branches[receiver].fence_token == token
func flush_network() -> bool:
	# Client requests are processed before server acknowledgement/look fences.
	for i in [1,2]:
		if not await fence(i,0):
			return false
	for i in [1,2]:
		if not await fence(0,i):
			return false
	return true
func run():
	for i in 3:
		var branch=World.new()
		branch.name="Peer"+str(i)
		root.add_child(branch)
		var api=SceneMultiplayer.new()
		api.server_relay=false
		set_multiplayer(api,branch.get_path())
		var net=Net.new()
		net.name="Net"
		branch.add_child(net)
		net.set_process(false)
		net.world=branch
		net.spawner=MultiplayerSpawner.new()
		net.spawner.spawn_limit=4
		net.add_child(net.spawner)
		net.character_edit_apply_rpc_enabled=true
		branches.append(branch)
		apis.append(api)
		nets.append(net)
		peers.append(ENetMultiplayerPeer.new())
	var err=peers[0].create_server(0,2)
	check(err==OK,"ENet server created")
	if err!=OK:
		cleanup();quit(1);return
	var port=peers[0].host.get_local_port()
	apis[0].multiplayer_peer=peers[0]
	nets[0].mode=Net.Mode.DEDICATED
	nets[0]._connected=true
	for i in [1,2]:
		check(peers[i].create_client("127.0.0.1",port)==OK,"client connects "+str(i))
		apis[i].multiplayer_peer=peers[i]
		nets[i].mode=Net.Mode.CLIENT
		nets[i]._connected=true
		nets[i].my_sim="Actor"+str(i)
		nets[i].character_edit_apply_result.connect(func(key,accepted,revision,changed,reason):
			inboxes[i-1].append({"key":key,"ok":accepted,"revision":revision,"changed":changed,"reason":reason}))
	var deadline=Time.get_ticks_msec()+3000
	while apis[0].get_peers().size()!=2 and Time.get_ticks_msec()<deadline:
		await process_frame
	check(apis[0].get_peers().size()==2,"two authenticated ENet peer IDs")
	if apis[0].get_peers().size()!=2:
		cleanup();quit(1);return
	# Independently exercise ordered handler execution before the fence.
	for sequence in 64:
		branches[0].test_sequence.rpc_id(apis[2].get_unique_id(),sequence)
	check(await fence(0,2),"burst fence completes")
	check(branches[2].received_sequence==range(64),"all 64 prior reliable handlers execute in order before fence")
	for i in [1,2]:
		var actor=Node.new()
		actor.name="Actor"+str(i)
		branches[0].add_child(actor)
		var cd=CD.create()
		cd.identity["first_name"]="Alice" if i==1 else "Berta"
		cd.personality["traits"]=["optimista"]
		actor.set_meta("net_incarnation",INC_ACTOR1 if i==1 else INC_ACTOR2)
		actor.set_meta("player_character",true)
		actor.set_meta("character_uid",cd.uid)
		branches[0]._character_records[actor.name]=cd
		branches[0]._character_revisions[actor.name]=1
		nets[0].players[apis[i].get_unique_id()]={"sim":actor.name,"own":true}
	for branch in branches.slice(1):
		for i in [1,2]:
			var replica=ClientActor.new()
			replica.name="Actor"+str(i)
			replica.set_meta("net_incarnation",INC_ACTOR1 if i==1 else INC_ACTOR2)
			branch.add_child(replica)
	var a=branches[0]._character_records["Actor1"].to_dict()
	a["body"]["height_cm"]=175.0
	check(nets[1].request_character_edit_apply(1,a),"owner sends bounded Apply request")
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(inboxes[0].size()==1 and inboxes[0][0]["ok"],"owner gets private accepted result")
	check(inboxes[1].is_empty(),"other peer gets no private Apply result")
	check(branches[0]._character_revisions["Actor1"]==2,"server revision increments")
	check(branches[0]._character_records["Actor1"].body["height_cm"]==175.0,"server canonical record changed")
	check(inboxes[0][0]["revision"]==2 and inboxes[0][0]["changed"],"result revision and changed flag")
	check(branches[1].find_sim("Actor1").look.get("body",{}).get("height_cm")==175.0,"owner sees public appearance update")
	check(branches[2].find_sim("Actor1").look.get("body",{}).get("height_cm")==175.0,"other client sees public appearance update")
	check(not branches[2].find_sim("Actor1").look.has("mind") and not branches[2].find_sim("Actor1").look.has("story") and not branches[2].find_sim("Actor1").look.get("personality",{}).has("trait_levels") and not branches[2].find_sim("Actor1").look.get("personality",{}).has("hexaco"),"public look excludes private mind, story and personality intensities")
	check(nets[1]._public_look_revisions.get("Actor1",0)==2 and nets[2]._public_look_revisions.get("Actor1",0)==2,"both peers track public revision")
	var before_invalid=branches[2].find_sim("Actor1").look.duplicate(true)
	var invalid_public=before_invalid.duplicate(true)
	invalid_public["mind"]={"stress":100}
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,3,JSON.stringify(invalid_public).to_utf8_buffer())
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[2].find_sim("Actor1").look==before_invalid,"authenticated server packet with private mind is rejected")
	check(nets[2]._public_look_revisions.get("Actor1",0)==2,"rejected private packet cannot advance public revision")

	check(nets[1].request_character_edit_apply(1,a),"replayed stale request sent")
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(inboxes[0].size()==2 and not inboxes[0][1]["ok"] and inboxes[0][1]["reason"]=="conflict","stale replay rejected")
	check(branches[0]._character_revisions["Actor1"]==2,"replay has no side effects")
	check(nets[2]._public_look_revisions.get("Actor1",0)==2,"stale Apply did not replicate appearance")
	nets[2].my_sim="Actor1"
	check(nets[2].request_character_edit_apply(2,a),"forged selection transmitted")
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(inboxes[1].is_empty(),"forged owner receives no result")
	check(branches[0]._character_revisions["Actor1"]==2,"forgery did not mutate A")
	nets[2].my_sim="Actor2"
	var b=branches[0]._character_records["Actor2"].to_dict()
	b["body"]["height_cm"]=181.0
	check(nets[2].request_character_edit_apply(1,b),"B submits own valid edit")
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(inboxes[1].size()==1 and inboxes[1][0]["ok"],"B gets only own result")
	check(branches[0]._character_revisions["Actor2"]==2,"B canonical revision increments")
	check(branches[1].find_sim("Actor2").look.get("body",{}).get("height_cm")==181.0,"A sees B public appearance")
	check(branches[2].find_sim("Actor2").look.get("body",{}).get("height_cm")==181.0,"B sees own public appearance")
	var previous=inboxes[1].size()
	nets[2]._s2c_character_edit_apply_result("Actor2",true,99,true,"")
	check(inboxes[1].size()==previous,"forged local server result rejected")
	var old_look=branches[1].find_sim("Actor2").look.duplicate(true)
	nets[1]._s2c_character_public_look("Actor2",INC_ACTOR2,99,JSON.stringify({"mind":{"stress":100}}).to_utf8_buffer())
	check(branches[1].find_sim("Actor2").look==old_look,"direct fake public look RPC rejected")
	check(nets[1]._public_look_revisions.get("Actor2",0)==2,"forged local look cannot advance revision")
	# Focused real-ENet out-of-order public look regression (test-only server packets).
	var order_before: Dictionary = branches[2].find_sim("Actor1").look.duplicate(true)
	var order_wire: PackedByteArray = JSON.stringify(order_before).to_utf8_buffer()
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,1,order_wire)
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,2,order_wire)
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[2].find_sim("Actor1").look==order_before and
		int(nets[2]._public_look_revisions.get("Actor1",0))==2,
		"stale and duplicate authenticated look packets do not roll back revision")
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,3,
		"{malformed".to_utf8_buffer())
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[2].find_sim("Actor1").look==order_before and
		int(nets[2]._public_look_revisions.get("Actor1",0))==2,
		"malformed authenticated look packet does not advance revision")
	var order_new: Dictionary = order_before.duplicate(true)
	order_new["body"]["height_cm"]=178.0
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,4,
		JSON.stringify(order_new).to_utf8_buffer())
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[2].find_sim("Actor1").look.get("body",{}).get("height_cm")==178.0 and
		int(nets[2]._public_look_revisions.get("Actor1",0))==4,
		"newer valid server look packet advances revision and appearance")
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Actor1",INC_ACTOR1,3,order_wire)
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[2].find_sim("Actor1").look.get("body",{}).get("height_cm")==178.0 and
		int(nets[2]._public_look_revisions.get("Actor1",0))==4,
		"delayed older valid packet cannot overwrite newer appearance")
	check(not branches[2].find_sim("Actor1").look.has("mind") and
		not branches[2].find_sim("Actor1").look.has("story"),
		"reordered public packets do not expose private state")

	# Real ENet delivery before puppet availability; explicit production lifecycle
	# callbacks below, not an assertion about MultiplayerSpawner scheduling.
	var ghost_wire: PackedByteArray = JSON.stringify(order_new).to_utf8_buffer()
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"PendingActor",INC_PENDING,7,ghost_wire)
	check(await flush_network(),"pre-spawn packet fence")
	check(nets[2]._pending_public_looks.get("PendingActor",{}).get(INC_PENDING,{}).get("revision",0)==7 and
		not nets[2]._public_look_revisions.has("PendingActor"),
		"missing puppet buffers validated snapshot without recording applied revision")
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"PendingActor",INC_PENDING,6,order_wire)
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"PendingActor",INC_PENDING,8,
		JSON.stringify(invalid_public).to_utf8_buffer())
	check(await flush_network(),"pending stale/private packets fence")
	check(nets[2]._pending_public_looks["PendingActor"][INC_PENDING]["revision"]==7 and
		nets[2]._pending_public_looks["PendingActor"][INC_PENDING]["look"]==order_new,
		"pending newer look survives stale and private-data packets")
	var pending_actor=ClientActor.new()
	pending_actor.name="PendingActor"
	pending_actor.set_meta("net_incarnation",INC_PENDING)
	branches[2].add_child(pending_actor)
	nets[2]._on_spawned(pending_actor)
	check(pending_actor.look==order_new and nets[2]._public_look_revisions.get("PendingActor",0)==7 and
		not nets[2]._pending_public_looks.has("PendingActor"),
		"production spawn callback consumes buffered look once")
	nets[2]._on_despawned(pending_actor)
	branches[2].remove_child(pending_actor)
	pending_actor.free()
	check(not nets[2]._public_look_revisions.has("PendingActor") and
		not nets[2]._pending_public_looks.has("PendingActor"),"despawn callback clears appearance state")
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"PendingActor",INC_REPLACEMENT,1,order_wire)
	check(await flush_network(),"new lifetime packet fence")
	var replacement=ClientActor.new()
	replacement.name="PendingActor"
	replacement.set_meta("net_incarnation",INC_REPLACEMENT)
	branches[2].add_child(replacement)
	nets[2]._on_spawned(replacement)
	check(replacement.look==order_before and nets[2]._public_look_revisions.get("PendingActor",0)==1,
		"fresh lifetime accepts initial revision after despawn cleanup")
	# A queued look from a prior incarnation cannot apply to a different spawned node.
	nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"PreSpawnOld",INC_PENDING,9,order_wire)
	check(await flush_network(),"old pre-spawn look delivered")
	var other_actor=ClientActor.new()
	other_actor.name="PreSpawnOld"
	other_actor.set_meta("net_incarnation",INC_REPLACEMENT)
	branches[2].add_child(other_actor)
	nets[2]._on_spawned(other_actor)
	check(other_actor.look.is_empty() and not nets[2]._pending_public_looks.has("PreSpawnOld") and not nets[2]._public_look_revisions.has("PreSpawnOld"),"old pre-spawn incarnation never applies to new puppet")
	nets[2]._on_despawned(other_actor)
	branches[2].remove_child(other_actor)
	other_actor.free()

	# Two incarnations share a node name before it exists. Latest packet arrival
	# must not discard the other incarnation's validated full snapshot.
	for reverse_order in [false,true]:
		var key := "PendingOrderB" if reverse_order else "PendingOrderA"
		var tokens := [INC_PENDING,INC_REPLACEMENT] if reverse_order else [INC_REPLACEMENT,INC_PENDING]
		for token in tokens:
			var wire_for_token: PackedByteArray = ghost_wire if token==INC_REPLACEMENT else order_wire
			var rev_for_token := 2 if token==INC_REPLACEMENT else 99
			nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),key,token,rev_for_token,wire_for_token)
		check(await flush_network(),"both pre-spawn incarnations delivered "+key)
		var arriving=ClientActor.new()
		arriving.name=key
		arriving.set_meta("net_incarnation",INC_REPLACEMENT)
		branches[2].add_child(arriving)
		nets[2]._on_spawned(arriving)
		check(arriving.look==order_new and nets[2]._public_look_revisions.get(key,0)==2,
			"matching pending incarnation survives either arrival order "+key)
		check(not nets[2]._pending_public_looks.has(key),"spawn removes pending variants "+key)
		nets[2]._on_despawned(arriving)
		branches[2].remove_child(arriving)
		arriving.free()
	nets[0].character_edit_apply_rpc_enabled=false
	var latest=branches[0]._character_records["Actor2"].to_dict()
	latest["body"]["height_cm"]=184.0
	check(nets[2].request_character_edit_apply(2,latest),"disabled server test request sent")
	check(await flush_network(),"ordered ENet fence completes within deadline")
	check(branches[0]._character_revisions["Actor2"]==2,"server feature flag fails closed")
	check(nets[1]._public_look_revisions.get("Actor2",0)==2,"disabled server sends no appearance update")
	nets[2].character_edit_apply_rpc_enabled=false
	check(not nets[2].request_character_edit_apply(2,latest),"client feature flag fails closed")

	nets[2].character_edit_apply_rpc_enabled=true
	# Capacity is bounded independently for names and incarnations.
	for idx in 4:
		var token := str(idx+5).repeat(32)
		nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"Capacity",token,1,order_wire)
	check(await flush_network(),"capacity variants delivered")
	var variants: Dictionary = nets[2]._pending_public_looks.get("Capacity",{})
	check(variants.size()==Net.MAX_PENDING_LOOK_INCARNATIONS and variants.has("7".repeat(32)) and
		variants.has("8".repeat(32)),"two latest introduced incarnations retained without empty key")
	for idx in 6:
		nets[0]._s2c_character_public_look.rpc_id(apis[2].get_unique_id(),"CapacityName"+str(idx),INC_PENDING,1,order_wire)
	check(await flush_network(),"capacity names delivered")
	check(nets[2]._pending_public_looks.size()==nets[2].spawner.spawn_limit,
		"pending name count cannot exceed spawn budget")
	# A previously evicted incarnation is recovered only from the authoritative
	# server after the actual spawn binds its token; no private data is requested.
	var recovered_token := "5".repeat(32)
	var recovered_server_actor := Node.new()
	recovered_server_actor.name = "Capacity"
	recovered_server_actor.set_meta("net_incarnation", recovered_token)
	branches[0].add_child(recovered_server_actor)
	var recovered_data := CD.create()
	recovered_data.identity["first_name"] = "Cora"
	recovered_data.personality["traits"] = ["optimista"]
	recovered_data.body["height_cm"] = 177.0
	branches[0]._character_records["Capacity"] = recovered_data
	branches[0]._character_revisions["Capacity"] = 2
	nets[0].character_edit_apply_rpc_enabled = true
	var recovered_client_actor := ClientActor.new()
	recovered_client_actor.name = "Capacity"
	recovered_client_actor.set_meta("net_incarnation", recovered_token)
	branches[2].add_child(recovered_client_actor)
	nets[2]._on_spawned(recovered_client_actor)
	check(recovered_client_actor.look.is_empty() and
		nets[2]._public_resync_requested.get("Capacity", {}).get("incarnation", "") == recovered_token,
		"evicted matching incarnation triggers one bounded resync request")
	check(await flush_network(), "public resync request and reply complete over real ENet")
	check(recovered_client_actor.look == recovered_data.public_snapshot() and
		nets[2]._public_look_revisions.get("Capacity", 0) == 2,
		"server resync restores canonical public appearance for evicted incarnation")
	check(not recovered_client_actor.look.has("mind") and
		not recovered_client_actor.look.get("personality", {}).has("trait_levels"),
		"resync exposes no private mind or personality intensities")
	# A client cannot request an older incarnation's current canonical snapshot.
	recovered_data.body["height_cm"] = 188.0
	branches[0]._character_revisions["Capacity"] = 3
	nets[2]._c2s_character_public_look_resync.rpc_id(1, "Capacity", INC_PENDING)
	check(await flush_network(), "mismatched resync request fence")
	check(recovered_client_actor.look.get("body", {}).get("height_cm") == 177.0 and
		nets[2]._public_look_revisions.get("Capacity", 0) == 2,
		"server refuses resync for incorrect incarnation")
	nets[2]._c2s_character_public_look_resync.rpc_id(1, "Capacity", recovered_token)
	check(await flush_network(), "valid authenticated resync request fence")
	check(recovered_client_actor.look.get("body", {}).get("height_cm") == 188.0 and
		nets[2]._public_look_revisions.get("Capacity", 0) == 3,
		"valid resync delivers newer canonical snapshot")
	nets[2]._on_despawned(recovered_client_actor)
	branches[2].remove_child(recovered_client_actor)
	recovered_client_actor.free()
	check(not nets[2]._public_resync_requested.has("Capacity"),
		"despawn clears client resync deduplication state")
	nets[2]._on_server_disconnected()
	check(nets[2]._pending_public_looks.is_empty() and nets[2]._public_look_revisions.is_empty(),
		"disconnect clears all pending variants and applied revisions")
	nets[2]._connected=true
	# Entire pending name absent: spawn must request the current public snapshot.
	var missing_server=Node.new()
	missing_server.name="MissingName"
	missing_server.set_meta("net_incarnation", INC_REPLACEMENT)
	branches[0].add_child(missing_server)
	var missing_data=CD.create()
	missing_data.identity["first_name"]="Mira"
	missing_data.personality["traits"]=["optimista"]
	missing_data.body["height_cm"]=169.0
	branches[0]._character_records["MissingName"]=missing_data
	branches[0]._character_revisions["MissingName"]=2
	var missing_client=ClientActor.new()
	missing_client.name="MissingName"
	missing_client.set_meta("net_incarnation", INC_REPLACEMENT)
	branches[2].add_child(missing_client)
	nets[0].character_edit_apply_rpc_enabled=false
	nets[2]._on_spawned(missing_client)
	check(nets[2]._public_resync_requested.get("MissingName",{}).get("attempts",0)==1, "spawn with no pending name starts bounded resync")
	check(await flush_network(), "dropped first resync reply fence")
	check(missing_client.look.is_empty(), "no reply leaves appearance unmodified")
	# Exercise production _process and real monotonic time, not a timestamp edit.
	var observed_retry: Dictionary = nets[2]._public_resync_requested["MissingName"]
	var sent_at: float = float(observed_retry["last_sent"])
	check(nets[2]._now()-sent_at<1.0, "wall-clock fixture starts from fresh request")
	nets[2].set_process(true)
	var early_deadline := Time.get_ticks_msec()+1000
	var premature := false
	while Time.get_ticks_msec()<early_deadline:
		if nets[2]._public_resync_requested.get("MissingName",{}).get("attempts",0)!=1:
			premature=true
		await process_frame
	check(not premature and missing_client.look.is_empty(), "real process does not retry within first second")
	nets[0].character_edit_apply_rpc_enabled=true
	var recovery_deadline := Time.get_ticks_msec()+7000
	while missing_client.look.is_empty() and Time.get_ticks_msec()<recovery_deadline:
		await process_frame
	var recovery_elapsed: float = nets[2]._now()-sent_at
	nets[2].set_process(false)
	check(not missing_client.look.is_empty(), "production process retries unanswered resync without manual invocation")
	check(int(observed_retry["attempts"])==2 and float(observed_retry["last_sent"])-sent_at>=Net.PUBLIC_RESYNC_RETRY_SECONDS,
		"actual retry send respects five-second minimum independent of delivery latency")
	print("WALL_CLOCK_RETRY_SEND_SECONDS=",float(observed_retry["last_sent"])-sent_at)
	print("WALL_CLOCK_RESYNC_SECONDS=",recovery_elapsed)
	check(await flush_network(), "retried resync reply fence")
	check(missing_client.look==missing_data.public_snapshot() and nets[2]._public_look_revisions.get("MissingName",0)==2, "retry recovers canonical public appearance")
	check(not nets[2]._public_resync_requested.has("MissingName"), "valid response cancels further retries")
	# No server actor: retries stop at three attempts, never unbounded.
	var absent=ClientActor.new()
	absent.name="NeverReply"
	absent.set_meta("net_incarnation", INC_PENDING)
	branches[2].add_child(absent)
	nets[2]._on_spawned(absent)
	check(await flush_network(), "unanswered resync initial fence")
	for attempt in 2:
		var exhausted:Dictionary=nets[2]._public_resync_requested["NeverReply"]
		exhausted["last_sent"]-=Net.PUBLIC_RESYNC_RETRY_SECONDS+1.0
		nets[2]._retry_public_look_resync()
		check(await flush_network(), "unanswered resync retry fence")
	check(nets[2]._public_resync_requested["NeverReply"]["attempts"]==Net.PUBLIC_RESYNC_MAX_ATTEMPTS, "retry budget capped at three attempts")
	var capped:Dictionary=nets[2]._public_resync_requested["NeverReply"]
	capped["last_sent"]-=Net.PUBLIC_RESYNC_RETRY_SECONDS+1.0
	nets[2]._retry_public_look_resync()
	check(nets[2]._public_resync_requested["NeverReply"]["attempts"]==Net.PUBLIC_RESYNC_MAX_ATTEMPTS, "exhausted request never retransmits")
	nets[2]._on_despawned(absent)
	branches[2].remove_child(absent)
	absent.free()
	nets[2]._on_despawned(missing_client)
	branches[2].remove_child(missing_client)
	missing_client.free()
	cleanup()
	await process_frame
	print("EDIT_APPLY_ENET_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed==0 else 1)
func cleanup():
	for net in nets:net._connected=false
	for peer in peers:peer.close()
	for i in branches.size():
		set_multiplayer(null,branches[i].get_path())
		branches[i].queue_free()