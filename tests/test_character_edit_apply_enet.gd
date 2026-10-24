extends SceneTree
# H2b staged Apply RPC transport. Real ENet server and two independent clients.
# The World stub commits validated data; main.gd commit semantics are separately
# exercised by test_character_edit_ownership.gd.
const Net=preload("res://scripts/net/net_session.gd")
const CD=preload("res://scripts/character/character_data.gd")
class World:
	extends Node
	var _character_records={}
	var _character_revisions={}
	func find_sim(key):
		return get_node_or_null(NodePath(key))
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
func check(ok:bool,label:String):
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _init():
	call_deferred("run")
func wait_frames(seconds:float):
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
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
	for i in [1,2]:
		var actor=Node.new()
		actor.name="Actor"+str(i)
		branches[0].add_child(actor)
		var cd=CD.create()
		cd.identity["first_name"]="Alice" if i==1 else "Berta"
		cd.personality["traits"]=["optimista"]
		actor.set_meta("player_character",true)
		actor.set_meta("character_uid",cd.uid)
		branches[0]._character_records[actor.name]=cd
		branches[0]._character_revisions[actor.name]=1
		nets[0].players[apis[i].get_unique_id()]={"sim":actor.name,"own":true}
	var a=branches[0]._character_records["Actor1"].to_dict()
	a["body"]["height_cm"]=175.0
	check(nets[1].request_character_edit_apply(1,a),"owner sends bounded Apply request")
	await wait_frames(.20)
	check(inboxes[0].size()==1 and inboxes[0][0]["ok"],"owner gets private accepted result")
	check(inboxes[1].is_empty(),"other peer gets no private Apply result")
	check(branches[0]._character_revisions["Actor1"]==2,"server revision increments")
	check(branches[0]._character_records["Actor1"].body["height_cm"]==175.0,"server canonical record changed")
	check(inboxes[0][0]["revision"]==2 and inboxes[0][0]["changed"],"result revision and changed flag")
	check(nets[1].request_character_edit_apply(1,a),"replayed stale request sent")
	await wait_frames(.20)
	check(inboxes[0].size()==2 and not inboxes[0][1]["ok"] and inboxes[0][1]["reason"]=="conflict","stale replay rejected")
	check(branches[0]._character_revisions["Actor1"]==2,"replay has no side effects")
	nets[2].my_sim="Actor1"
	check(nets[2].request_character_edit_apply(2,a),"forged selection transmitted")
	await wait_frames(.20)
	check(inboxes[1].is_empty(),"forged owner receives no result")
	check(branches[0]._character_revisions["Actor1"]==2,"forgery did not mutate A")
	nets[2].my_sim="Actor2"
	var b=branches[0]._character_records["Actor2"].to_dict()
	b["body"]["height_cm"]=181.0
	check(nets[2].request_character_edit_apply(1,b),"B submits own valid edit")
	await wait_frames(.20)
	check(inboxes[1].size()==1 and inboxes[1][0]["ok"],"B gets only own result")
	check(branches[0]._character_revisions["Actor2"]==2,"B canonical revision increments")
	var previous=inboxes[1].size()
	nets[2]._s2c_character_edit_apply_result("Actor2",true,99,true,"")
	check(inboxes[1].size()==previous,"forged local server result rejected")
	nets[0].character_edit_apply_rpc_enabled=false
	var latest=branches[0]._character_records["Actor2"].to_dict()
	latest["body"]["height_cm"]=184.0
	check(nets[2].request_character_edit_apply(2,latest),"disabled server test request sent")
	await wait_frames(.20)
	check(branches[0]._character_revisions["Actor2"]==2,"server feature flag fails closed")
	nets[2].character_edit_apply_rpc_enabled=false
	check(not nets[2].request_character_edit_apply(2,latest),"client feature flag fails closed")
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
