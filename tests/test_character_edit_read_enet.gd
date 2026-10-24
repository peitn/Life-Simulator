extends SceneTree
# Real ENet UDP transport with server and two independent SceneMultiplayer roots.
# Registration is a server fixture; existing hello/spawner flow is outside this test.
const Net=preload("res://scripts/net/net_session.gd")
const CD=preload("res://scripts/character/character_data.gd")
class World:
	extends Node
	var _character_records={}
	var _character_revisions={}
	func find_sim(key):
		return get_node_or_null(NodePath(key))
var passed=0
var failed=0
var branches=[]
var apis=[]
var peers=[]
var nets=[]
var inboxes=[[],[]]
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
