extends SceneTree
## Full real ENet owner UI: correlated private read -> draft -> authenticated
## authoritative Apply -> private ACK -> canonical readback -> public-only look.
const Net = preload("res://scripts/net/net_session.gd")
const Editor = preload("res://scripts/ui/character_editor_panel.gd")
const CD = preload("res://scripts/character/character_data.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
const INC = "12341234123412341234123412341234"

class Actor:
    extends Node3D
    var look: Dictionary = {}
    func apply_public_look(d: Dictionary) -> void:
        look = d.duplicate(true)

class TestWorld:
    extends Node3D
    var net: Node
    var _character_records: Dictionary = {}
    var _character_revisions: Dictionary = {}
    var fence_value := 0
    var received_count := 0
    @rpc("any_peer", "call_remote", "reliable", 0)
    func fence(v: int) -> void:
        fence_value = v
    func find_sim(key: String):
        return get_node_or_null(NodePath(key))
    func read_public_character_look(key: String) -> Dictionary:
        if not _character_records.has(key):
            return {"ok":false}
        return {"ok":true, "revision":_character_revisions[key], "look":_character_records[key].public_snapshot()}
    func server_apply_character_edit(peer: int, key: Variant, revision: Variant, wire: Variant) -> Dictionary:
        var prepared: Dictionary = net.server_prepare_character_edit(peer, key, revision, wire)
        if not prepared.get("ok", false) or not net.server_can_edit_character(peer, key):
            return prepared if not prepared.get("ok", false) else {"ok":false,"reason":"unauthorized"}
        var name := String(key)
        if _character_revisions[name] != revision:
            return {"ok":false,"reason":"conflict"}
        var changed: bool = _character_records[name].to_dict() != prepared["data"]
        if changed:
            _character_records[name].set_from_dict(prepared["data"])
            _character_revisions[name] += 1
            received_count += 1
        return {"ok":true,"revision":_character_revisions[name],"changed":changed}

var worlds: Array = []
var apis: Array = []
var peers: Array = []
var passed := 0
var failed := 0
var serial := 0

func check(ok: bool, label: String) -> void:
    print("PASS " if ok else "FAIL ", label)
    if ok: passed += 1
    else: failed += 1

func _init() -> void:
    call_deferred("run")

func step(sender: int, destination: int) -> bool:
    serial += 1
    var token := serial
    worlds[sender].fence.rpc_id(apis[destination].get_unique_id(),token)
    var deadline := Time.get_ticks_msec()+3500
    while worlds[destination].fence_value != token and Time.get_ticks_msec() < deadline:
        await process_frame
    return worlds[destination].fence_value == token

func drain() -> bool:
    for i in [1,2]:
        if not await step(i,0):
            return false
    for i in [1,2]:
        if not await step(0,i):
            return false
    return true

func run() -> void:
    root.size=Vector2i(960,720)
    Assets.enabled = false
    for i in 3:
        var branch = TestWorld.new()
        branch.name = "Peer"+str(i)
        root.add_child(branch)
        var api = SceneMultiplayer.new()
        api.server_relay = false
        set_multiplayer(api, branch.get_path())
        var net = Net.new()
        net.name = "Net"
        branch.net=net
        branch.add_child(net)
        net.set_process(false)
        net.world = branch
        net.spawner = MultiplayerSpawner.new()
        net.spawner.spawn_limit = 4
        net.add_child(net.spawner)
        net.character_edit_apply_rpc_enabled = true
        net.character_edit_read_ui_enabled = i != 0
        worlds.append(branch)
        apis.append(api)
        peers.append(ENetMultiplayerPeer.new())
    check(peers[0].create_server(0,2)==OK, "ENet server starts")
    var port: int = peers[0].host.get_local_port()
    apis[0].multiplayer_peer=peers[0]
    worlds[0].net.mode = Net.Mode.DEDICATED
    worlds[0].net._connected = true
    for i in [1,2]:
        check(peers[i].create_client("127.0.0.1",port)==OK,"ENet client connects")
        apis[i].multiplayer_peer=peers[i]
        worlds[i].net.mode = Net.Mode.CLIENT
        worlds[i].net._connected = true
        worlds[i].net.my_sim="Actor"
    var deadline := Time.get_ticks_msec()+4000
    while apis[0].get_peers().size() != 2 and Time.get_ticks_msec() < deadline:
        await process_frame
    check(apis[0].get_peers().size()==2,"both peers authenticated")
    if apis[0].get_peers().size()!=2:
        cleanup();quit(1);return

    var actor=Node3D.new()
    actor.name="Actor"
    actor.set_meta("net_incarnation",INC)
    actor.set_meta("player_character",true)
    worlds[0].add_child(actor)
    var cd: Resource=CD.create()
    cd.identity["first_name"]="Nora"
    cd.identity["last_name"]="Test"
    cd.personality["traits"]=["aktivni"]
    actor.set_meta("character_uid",cd.uid)
    worlds[0]._character_records["Actor"]=cd
    worlds[0]._character_revisions["Actor"]=1
    worlds[0].net.players[apis[1].get_unique_id()]={"sim":"Actor","own":true}
    worlds[0].net.players[apis[2].get_unique_id()]={"sim":"Actor","own":false}
    for i in [1,2]:
        var replica=Actor.new()
        replica.name="Actor"
        replica.set_meta("net_incarnation",INC)
        worlds[i].add_child(replica)
    var snapshot_counts := {"outsider": 0, "owner": 0}
    worlds[2].net.character_edit_snapshot_correlated.connect(func(_t,_s,_d,_r): snapshot_counts["outsider"]+=1)
    worlds[1].net.character_edit_snapshot_correlated.connect(func(_t,_s,_d,_r): snapshot_counts["owner"]+=1)
    # Scalars are captured by value in GDScript lambdas; a shared Dictionary
    # makes this spy observable. Prove the spy works before testing isolation.
    worlds[2].net.character_edit_snapshot_correlated.emit("probe", "Actor", {}, 0)
    check(snapshot_counts["outsider"]==1, "privacy spy detects a synthetic local snapshot signal")
    snapshot_counts["outsider"]=0
    check(worlds[2].net.request_character_edit_snapshot("c".repeat(32)), "spectator arms correlated read before unauthorized request")
    check(await drain(),"owner-isolation ENet fence")
    check(snapshot_counts["outsider"]==0,"spectator cannot read owner's private character")

    # A spectator can send a syntactically valid owner-shaped edit packet,
    # but server-derived peer ownership must reject it before any commit.
    var attack_baseline: Dictionary = worlds[0]._character_records["Actor"].to_dict().duplicate(true)
    var hostile_candidate: Dictionary = attack_baseline.duplicate(true)
    hostile_candidate["body"]["height_cm"] = 190.0
    var hostile_reply := {"count": 0}
    worlds[2].net.character_edit_apply_correlated.connect(func(_id, _key, _accepted, _rev, _changed, _reason): hostile_reply["count"] += 1)
    check(worlds[2].net.request_character_edit_apply(1, hostile_candidate, "d".repeat(32)),
        "spectator sends syntactically valid forged owner Apply over ENet")
    check(await drain(), "unauthorized Apply crosses real ENet fence")
    check(worlds[0].received_count == 0 and worlds[0]._character_revisions["Actor"] == 1
        and worlds[0]._character_records["Actor"].to_dict() == attack_baseline,
        "forged Apply cannot mutate canonical server record or revision")
    check(hostile_reply["count"] == 0, "unauthorized spectator receives no private Apply ACK")

    var panel := Editor.new()
    panel.main=worlds[1]
    worlds[1].add_child(panel)
    check(panel.open_network_character("Actor"),"owner opens real ENet editor")
    check(await drain(),"initial owner private read delivered")
    check(panel._session.is_open() and panel._revision==1,"UI receives canonical private draft, revision 1")
    check(not panel._apply_button.disabled,"verified owner may Apply")
    check(snapshot_counts["owner"]==1,"owner spy observes actual canonical ENet reply")
    var baseline: Dictionary=panel._session.draft()
    var server_baseline: Dictionary=worlds[0]._character_records["Actor"].to_dict().duplicate(true)
    var discarded: Dictionary=baseline.duplicate(true)
    discarded["body"]["height_cm"]=181.0
    check(panel._session.replace_draft(discarded,"discarded network draft"),"create draft to cancel")
    panel._refresh()
    panel._on_cancel()
    await process_frame
    check(not is_instance_valid(panel),"Cancel frees editor before any Apply")
    check(await drain(),"cancelled draft ENet fence")
    check(worlds[0].received_count==0 and worlds[0]._character_revisions["Actor"]==1,
        "Cancel sends no authoritative commit")
    check(worlds[0]._character_records["Actor"].to_dict()==server_baseline,"Cancel preserves complete server character")
    panel=Editor.new()
    panel.main=worlds[1]
    worlds[1].add_child(panel)
    check(panel.open_network_character("Actor"),"reopen after Cancel")
    check(await drain(),"reopened canonical reply delivered")
    check(panel._session.draft()==baseline and not panel._session.can_undo(),
        "reopen discards cancelled draft and its history")
    var edited: Dictionary=panel._session.draft()
    edited["body"]["height_cm"]=175.0
    edited["clothing"]["bezne"]["top"]="kawaii_kocici_mikina"
    check(panel._session.replace_draft(edited,"network test"),"owner creates isolated local draft")
    panel._refresh()
    check(worlds[0]._character_records["Actor"].body["height_cm"] != 175.0,
        "draft has not mutated server before Apply")
    panel._on_undo()
    check(panel._session.draft()==baseline and not panel._session.is_dirty(),"network Undo restores canonical draft")
    panel._on_redo()
    check(panel._session.draft()==edited and panel._session.is_dirty(),"network Redo restores body and wardrobe draft")
    check(worlds[0].received_count==0 and worlds[0]._character_revisions["Actor"]==1,
        "Undo and Redo never commit server state")
    # Open + reopen consumed two of the shared 3 edit tokens. Let one token
    # refill for Apply + canonical readback; do not disable the production limiter.
    await create_timer(5.1).timeout
    panel._on_apply()
    panel._on_apply()
    check(not panel._apply_token.is_empty() and panel._apply_button.disabled,"one correlated Apply in flight")
    check(await drain(),"server accepted Apply and sent private ACK")
    check(await drain(),"fresh private readback delivered after ACK")
    check(worlds[0].received_count==1 and worlds[0]._character_revisions["Actor"]==2,
        "double click cannot duplicate authoritative commit")
    check(panel._revision==2 and panel._session.is_open() and not panel._session.is_dirty(),
        "UI canonical readback resets draft to confirmed revision 2")
    check(panel._session.draft()["body"]["height_cm"]==175.0,
        "actual server height survives private readback")
    check(panel._apply_token.is_empty() and not panel._await_readback and panel._read_token.is_empty(),
        "transaction has no leftover pending token")
    check(worlds[2].find_sim("Actor").look.get("body",{}).get("height_cm")==175.0,
        "spectator sees public appearance change")
    check(not worlds[2].find_sim("Actor").look.has("uid") and not worlds[2].find_sim("Actor").look.has("mind"),
        "spectator never receives private UID or mental state")
    check(snapshot_counts["outsider"]==0,"no private readback ever reaches spectator")
    # A newer server revision invalidates a draft: do not silently overwrite it.
    var stale: Dictionary = panel._session.draft()
    stale["body"]["height_cm"]=179.0
    panel._session.replace_draft(stale,"stale test")
    panel._refresh()
    worlds[0]._character_revisions["Actor"]=3
    panel._on_apply()
    check(await drain(),"real ENet conflict reply arrives")
    check(panel._apply_token.is_empty() and panel._session.is_dirty(),
        "conflict reply preserves unsaved local edits")
    check(panel._reopen_required and panel._apply_button.disabled,
        "stale draft remains blocked until a canonical reopen")
    check(worlds[0].received_count==1 and worlds[0]._character_records["Actor"].body["height_cm"]==175.0,
        "stale revision never mutates authoritative character")
    panel._on_cancel()
    await process_frame
    check(not is_instance_valid(panel),"Cancel frees authenticated editor")
    # A transport reconnect must not restore private editor access merely
    # because the client claims the same character name as its prior session.
    var old_owner_id: int = apis[1].get_unique_id()
    peers[1].close()
    apis[1].multiplayer_peer = OfflineMultiplayerPeer.new()
    worlds[1].net._on_server_disconnected()
    var reconnect_deadline := Time.get_ticks_msec() + 3500
    while apis[0].get_peers().size() != 1 and Time.get_ticks_msec() < reconnect_deadline:
        await process_frame
    check(apis[0].get_peers().size() == 1, "owner ENet transport actually disconnects")
    worlds[0].net.players.erase(old_owner_id)
    worlds[0].net._edit_limiters.erase(old_owner_id)
    var replacement_peer := ENetMultiplayerPeer.new()
    check(replacement_peer.create_client("127.0.0.1", port) == OK,
        "owner creates a fresh ENet connection")
    peers[1] = replacement_peer
    apis[1].multiplayer_peer = replacement_peer
    worlds[1].net._connected = true
    reconnect_deadline = Time.get_ticks_msec() + 3500
    while apis[0].get_peers().size() != 2 and Time.get_ticks_msec() < reconnect_deadline:
        await process_frame
    check(apis[0].get_peers().size() == 2, "fresh ENet transport reaches server")
    var new_owner_id: int = apis[1].get_unique_id()
    check(not worlds[0].net.server_can_edit_character(new_owner_id, "Actor"),
        "transport reconnect alone never grants private character ownership")
    var reads_before: int = snapshot_counts["owner"]
    check(worlds[1].net.request_character_edit_snapshot("e".repeat(32)),
        "unregistered reconnect can send a syntactically valid read request")
    check(await drain(), "unregistered reconnect ENet read fence")
    check(snapshot_counts["owner"] == reads_before,
        "unregistered reconnect receives no private character snapshot")
    worlds[1].net.cancel_character_edit_snapshot("e".repeat(32))
    worlds[0].net.players[new_owner_id] = {"sim":"Actor","own":true}
    panel = Editor.new()
    panel.main = worlds[1]
    worlds[1].add_child(panel)
    check(panel.open_network_character("Actor"), "re-authorized owner opens fresh editor")
    check(await drain(), "re-authorized owner ENet read fence")
    check(panel._session.is_open() and panel._revision == 3
        and panel._session.draft()["body"]["height_cm"] == 175.0
        and not panel._session.can_undo(),
        "re-authorized owner gets canonical revision, not stale pre-disconnect draft")
    check(snapshot_counts["outsider"] == 0,
        "reconnection never discloses private draft to spectator")
    panel._on_cancel()
    await process_frame
    # Transfer ownership while both transports remain connected. Neither a
    # previous valid editor nor a cached client identity grants access.
    var former_owner_id: int = apis[1].get_unique_id()
    var transferred_owner_id: int = apis[2].get_unique_id()
    worlds[0].net.players[former_owner_id]["own"] = false
    worlds[0].net.players[transferred_owner_id]["own"] = true
    check(not worlds[0].net.server_can_edit_character(former_owner_id, "Actor")
        and worlds[0].net.server_can_edit_character(transferred_owner_id, "Actor"),
        "server reassigns sole edit authority without reconnect")
    var former_reads: int = snapshot_counts["owner"]
    var new_reads: int = snapshot_counts["outsider"]
    var former_acks := {"count": 0}
    worlds[1].net.character_edit_apply_correlated.connect(
        func(_id, _key, _accepted, _rev, _changed, _reason): former_acks["count"] += 1)
    check(worlds[1].net.request_character_edit_snapshot("f".repeat(32)),
        "former owner can send a syntactically valid private read request")
    check(await drain(), "reassigned private read ENet fence")
    check(snapshot_counts["owner"] == former_reads,
        "former owner receives no private snapshot after reassignment")
    worlds[1].net.cancel_character_edit_snapshot("f".repeat(32))
    var former_candidate: Dictionary = worlds[0]._character_records["Actor"].to_dict().duplicate(true)
    former_candidate["body"]["height_cm"] = 188.0
    check(worlds[1].net.request_character_edit_apply(3, former_candidate, "a".repeat(32)),
        "former owner can send a syntactically valid Apply after revocation")
    check(await drain(), "reassigned unauthorized Apply ENet fence")
    check(former_acks["count"] == 0 and worlds[0].received_count == 1
        and worlds[0]._character_revisions["Actor"] == 3,
        "revoked Apply receives no private ACK and cannot commit")
    var transferred_panel := Editor.new()
    transferred_panel.main = worlds[2]
    worlds[2].add_child(transferred_panel)
    check(transferred_panel.open_network_character("Actor"),
        "new owner opens real ENet character editor")
    check(await drain(), "new owner canonical private read ENet fence")
    check(transferred_panel._session.is_open() and transferred_panel._revision == 3,
        "new owner receives canonical revision without previous draft")
    check(snapshot_counts["outsider"] == new_reads + 1
        and snapshot_counts["owner"] == former_reads,
        "private canonical read reaches only newly authorized owner")
    var transferred_draft: Dictionary = transferred_panel._session.draft()
    transferred_draft["body"]["height_cm"] = 178.0
    check(transferred_panel._session.replace_draft(transferred_draft, "ownership transfer edit"),
        "new owner prepares isolated post-transfer draft")
    transferred_panel._refresh()
    transferred_panel._on_apply()
    check(await drain(), "new owner authenticated Apply ENet fence")
    check(await drain(), "new owner canonical readback ENet fence")
    check(worlds[0].received_count == 2 and worlds[0]._character_revisions["Actor"] == 4,
        "new owner alone commits and advances revision exactly once")
    check(transferred_panel._revision == 4 and not transferred_panel._session.is_dirty(),
        "new owner receives confirmed canonical revision 4")
    check(worlds[1].find_sim("Actor").look.get("body", {}).get("height_cm") == 178.0,
        "former owner receives only updated public appearance")
    check(snapshot_counts["owner"] == former_reads
        and not worlds[1].find_sim("Actor").look.has("uid")
        and not worlds[1].find_sim("Actor").look.has("mind"),
        "former owner never receives new private data after transfer")
    transferred_panel._on_cancel()
    await process_frame
    check(not is_instance_valid(transferred_panel), "transferred editor closes cleanly")
    cleanup()
    await process_frame
    print("NETWORK_EDITOR_LIVE_RESULT=",passed," passed ",failed," failed")
    quit(0 if failed==0 else 1)

func cleanup() -> void:
    Assets.enabled = true
    for w in worlds:
        w.net._connected=false
    for peer in peers:
        peer.close()
    for i in worlds.size():
        set_multiplayer(null,worlds[i].get_path())
        worlds[i].queue_free()