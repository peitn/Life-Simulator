extends SceneTree
# Real ENet UDP transport with server and two independent SceneMultiplayer roots.
# Registration is a server fixture; existing hello/spawner flow is outside this test.
const Net=preload("res://scripts/net/net_session.gd")
const CD=preload("res://scripts/character/character_data.gd")
class World:
	extends Node
	var net
	var _character_records={}
	var _character_revisions={}
	func get_selected_sim():
		return find_sim(net.my_sim)
	func find_sim(key):
		return get_node_or_null(NodePath(key))
var passed=0
var failed=0
var branches=[]
var apis=[]
var peers=[]
var nets=[]
var inboxes=[[],[]]
var correlated=[[],[]]
func check(ok,label):
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _init():
	call_deferred("run")
func tick_for(seconds):
	var until=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until:
		await process_frame
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
		branch.net=net
		branches.append(branch);apis.append(api);nets.append(net)
		peers.append(ENetMultiplayerPeer.new())
	var err=peers[0].create_server(0,2)
	check(err==OK,"ENet server starts")
	if err!=OK:
		cleanup();quit(1);return
	var port=peers[0].host.get_local_port()
	apis[0].multiplayer_peer=peers[0]
	nets[0].mode=Net.Mode.DEDICATED
	nets[0]._connected=true
	for i in [1,2]:
		check(peers[i].create_client("127.0.0.1",port)==OK,"client starts "+str(i))
		apis[i].multiplayer_peer=peers[i]
		nets[i].mode=Net.Mode.CLIENT
		nets[i].my_sim="Actor"+str(i)
		nets[i].character_edit_snapshot.connect(func(key,data,rev):inboxes[i-1].append({"key":key,"data":data,"rev":rev}))
		nets[i].character_edit_snapshot_correlated.connect(func(token,key,data,rev):correlated[i-1].append({"token":token,"key":key,"data":data,"rev":rev}))
	var deadline=Time.get_ticks_msec()+3000
	while apis[0].get_peers().size()!=2 and Time.get_ticks_msec()<deadline:
		await process_frame
	check(apis[0].get_peers().size()==2,"two real ENet clients connected")
	if apis[0].get_peers().size()!=2:
		cleanup();quit(1);return
	for i in [1,2]:
		nets[i]._connected=true
		var actor=Node.new()
		actor.name="Actor"+str(i)
		branches[0].add_child(actor)
		var cd=CD.create()
		cd.identity["first_name"]="Alice" if i==1 else "Berta"
		cd.story["test_secret"]="private-"+str(i)
		actor.set_meta("player_character",true)
		actor.set_meta("character_uid",cd.uid)
		branches[0]._character_records[actor.name]=cd
		branches[0]._character_revisions[actor.name]=i
		nets[0].players[apis[i].get_unique_id()]={"sim":String(actor.name),"own":true}
	nets[1].request_character_edit_snapshot()
	await tick_for(.15)
	check(inboxes[0].size()==1,"owner A gets snapshot over RPC")
	check(inboxes[1].is_empty(),"B gets no A snapshot")
	if not inboxes[0].is_empty():
		check(inboxes[0][0]["data"]["story"]["test_secret"]=="private-1","A receives own private marker")
		check(inboxes[0][0]["rev"]==1,"canonical revision delivered")
	nets[2].request_character_edit_snapshot()
	await tick_for(.15)
	check(inboxes[1].size()==1,"owner B gets own snapshot")
	check(inboxes[0].size()==1,"A gets no B snapshot")
	if not inboxes[1].is_empty():
		check(inboxes[1][0]["data"]["story"]["test_secret"]=="private-2","B receives only own private marker")
	# Tagged reads use their own signal and cannot replace a legacy panel draft.
	nets[0]._edit_limiters.clear()
	var tag_a="a".repeat(32)
	var tag_b="b".repeat(32)
	# A future visible network editor needs an explicit accepted/denied launch result.
	check(nets[1].request_character_edit_snapshot("bad") == false, "malformed tagged read fails closed before RPC")
	check(nets[1]._pending_edit_read_id.is_empty(), "invalid request does not allocate pending state")
	nets[1]._connected = false
	check(nets[1].request_character_edit_snapshot(tag_a) == false, "disconnected client cannot launch editor read")
	nets[1]._connected = true
	nets[1].mode = Net.Mode.OFFLINE
	check(nets[1].request_character_edit_snapshot(tag_a) == false, "offline mode cannot launch network editor read")
	nets[1].mode = Net.Mode.CLIENT
	var saved_sim: String = String(nets[1].my_sim)
	nets[1].my_sim = ""
	check(nets[1].request_character_edit_snapshot(tag_a) == false, "unassigned client cannot launch editor read")
	nets[1].my_sim = saved_sim
	check(nets[1]._pending_edit_read_id.is_empty(), "rejected launches leave timeout state empty")
	check(nets[1].request_character_edit_snapshot(tag_a) == true, "connected owner launches correlated read")
	check(nets[1].request_character_edit_snapshot(tag_b) == true, "connected owner supersedes correlated read")
	var active_deadline: int = nets[1]._pending_edit_read_deadline_ms
	nets[1].cancel_character_edit_snapshot(tag_a)
	check(nets[1]._pending_edit_read_id == tag_b and nets[1]._pending_edit_read_deadline_ms == active_deadline, "stale panel Cancel preserves newer read and deadline")
	nets[1].cancel_character_edit_snapshot("invalid")
	check(nets[1]._pending_edit_read_id == tag_b, "unknown Cancel cannot discard active read")
	check(not nets[1].request_character_edit_snapshot("invalid") and nets[1]._pending_edit_read_id == tag_b and nets[1]._pending_edit_read_deadline_ms == active_deadline, "invalid launch preserves active generation and deadline")
	await tick_for(.2)
	check(correlated[0].size()==1,"only current tagged read returns over actual ENet")
	if correlated[0].size()==1:
		check(correlated[0][0]["token"]==tag_b,"obsolete generation discarded and latest token echoed")
		check(correlated[0][0]["key"]=="Actor1" and correlated[0][0]["data"]["story"]["test_secret"]=="private-1","tagged snapshot remains owner-private")
	check(correlated[1].is_empty(),"observer receives no correlated private snapshot")
	check(inboxes[0].size()==1,"correlated responses never reach legacy snapshot consumers")
	check(nets[1]._pending_edit_read_deadline_ms==0,"successful correlated read clears its timeout")
	nets[1]._c2s_character_edit_read.rpc_id(1,"Actor1","x".repeat(4096))
	nets[1]._c2s_character_edit_read.rpc_id(1,"Actor1",42)
	await tick_for(.15)
	check(correlated[0].size()==1 and inboxes[0].size()==1,"malformed correlation IDs rejected server-side")
	nets[2]._c2s_character_edit_read.rpc_id(1,"Actor1",tag_a)
	await tick_for(.15)
	check(correlated[1].is_empty(),"valid token does not authorize reading another owner")
	nets[0]._edit_limiters.clear()
	nets[1].request_character_edit_snapshot("c".repeat(32))
	nets[1].cancel_character_edit_snapshot("c".repeat(32))
	await tick_for(.15)
	check(correlated[0].size()==1 and nets[1]._pending_edit_read_id.is_empty(),"Cancel discards delayed private snapshot")
	check(nets[1]._pending_edit_read_deadline_ms==0,"Cancel clears the read deadline")
	nets[0]._edit_limiters.clear()
	# B forges local UI selection, but authenticated server assignment stays Actor2.
	nets[2].my_sim="Actor1"
	nets[2].request_character_edit_snapshot()
	await tick_for(.15)
	check(inboxes[1].size()==1,"forged character selection cannot read A")
	nets[2].my_sim="Actor2"
	var id_a=apis[1].get_unique_id()
	nets[0].players[id_a]["own"]=false
	nets[1].request_character_edit_snapshot()
	await tick_for(.15)
	check(inboxes[0].size()==1,"revoked ownership denies fresh read")
	nets[0].players[id_a]["own"]=true
	nets[0]._edit_limiters.clear()
	for i in 4:nets[1].request_character_edit_snapshot()
	await tick_for(.2)
	check(inboxes[0].size()==4,"four read requests yield only three bounded replies")
	check(inboxes[1].size()==1,"rate burst remains private")
	# Record removal simulates server-side reassignment; connected peer cannot read.
	nets[0].players.erase(id_a)
	nets[0]._edit_limiters.clear()
	nets[1].request_character_edit_snapshot()
	await tick_for(.15)
	check(inboxes[0].size()==4,"removed assignment denies connected peer")
	check(branches[0]._character_revisions["Actor1"]==1,"reads never change revision")
	# A denied owner read receives no server reply. Client must expire in real time,
	# emit only one timeout and reject a delayed authentic server response.
	var timeout_events: Array = []
	nets[1].character_edit_snapshot_timed_out.connect(func(token: String): timeout_events.append(token))
	var timeout_tag := "d".repeat(32)
	nets[1].set_process(true)
	var timeout_start := Time.get_ticks_msec()
	nets[1].request_character_edit_snapshot(timeout_tag)
	var private_wire: PackedByteArray = JSON.stringify(branches[0]._character_records["Actor1"].to_dict()).to_utf8_buffer()
	nets[0]._s2c_character_edit_snapshot.rpc_id(apis[1].get_unique_id(),"Actor1",private_wire,1,"")
	await tick_for(.15)
	check(inboxes[0].size()==4 and nets[1]._pending_edit_read_id==timeout_tag,"legacy server reply cannot bypass pending correlated read")
	await tick_for(6.3)
	check(timeout_events==[timeout_tag],"denied correlated read emits one real-time timeout")
	check(Time.get_ticks_msec()-timeout_start>=Net.EDIT_READ_TIMEOUT_MS,"timeout waits at least six real seconds")
	check(nets[1]._pending_edit_read_id.is_empty() and nets[1]._pending_edit_read_deadline_ms==0,"timeout clears pending token and deadline")
	nets[0]._s2c_character_edit_snapshot.rpc_id(apis[1].get_unique_id(),"Actor1",private_wire,1,timeout_tag)
	await tick_for(.15)
	check(correlated[0].size()==1 and timeout_events.size()==1,"late authenticated reply cannot reopen expired editor read")
	nets[1].set_process(false)
	# Exercise the real disconnect signal and production limiter cleanup after unassignment.
	nets[0]._edit_limiters[id_a]=Net.Protocol.RateLimiter.new(3.0,.2,0.0)
	apis[0].peer_disconnected.connect(nets[0]._on_peer_disconnected)
	peers[1].close()
	var disconnect_deadline=Time.get_ticks_msec()+2000
	while apis[0].get_peers().size()!=1 and Time.get_ticks_msec()<disconnect_deadline:
		await process_frame
	check(apis[0].get_peers().size()==1,"ENet disconnect observed by server")
	check(not nets[0]._edit_limiters.has(id_a),"production disconnect clears read limiter")
	var old_count=inboxes[1].size()
	nets[2]._s2c_character_edit_snapshot("Actor2",'{}'.to_utf8_buffer(),0)
	check(inboxes[1].size()==old_count,"local forged reply lacks authenticated server sender")
	# Real panel + authenticated ENet response, using still-connected owner B.
	var hud_script=load("res://scripts/ui/hud.gd")
	var client_actor=Node.new()
	client_actor.name="Actor2"
	branches[2].add_child(client_actor)
	var hud=hud_script.new()
	hud.main=branches[2]
	branches[2].add_child(hud)
	hud.set_process(false)
	nets[2].character_edit_read_ui_enabled=true
	nets[0]._edit_limiters.clear()
	hud._on_edit_character()
	var panel=hud._character_editor
	check(is_instance_valid(panel) and not panel._read_token.is_empty(),"real HUD launches own ENet panel read")
	await tick_for(.2)
	check(panel._session.is_open() and panel._revision==2,"real panel receives canonical owner snapshot")
	check(panel._session.draft().get("story",{}).get("test_secret")=="private-2","panel draft contains own private marker only")
	check(panel._apply_button.disabled,"real network panel cannot Apply")
	panel._on_cancel()
	await process_frame
	check(not is_instance_valid(panel),"real panel Cancel frees UI")
	nets[0].players[apis[2].get_unique_id()]["own"]=false
	nets[2].set_process(true)
	hud._on_edit_character()
	panel=hud._character_editor
	check(is_instance_valid(panel) and not panel._read_token.is_empty(),"revoked owner HUD request awaits server decision")
	await tick_for(6.3)
	check(not panel._session.is_open() and panel._read_token.is_empty() and panel._status.text.contains("vypršelo"),"real server denial reaches panel timeout without draft")
	panel._on_cancel()
	await process_frame
	cleanup()
	await process_frame
	print("EDIT_READ_ENET_RESULT=",passed," passed, ",failed," failed")
	quit(0 if failed==0 else 1)
func cleanup():
	for net in nets:net._connected=false
	for peer in peers:peer.close()
	for i in branches.size():
		set_multiplayer(null,branches[i].get_path())
		branches[i].queue_free()