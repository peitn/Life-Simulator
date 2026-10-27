extends "res://tests/test_base.gd"
## Production listen-host path: only host-owned custom character may edit.
const Main = preload("res://main.gd")
const CD = preload("res://scripts/character/character_data.gd")
const Codec = preload("res://scripts/character/character_codec.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
var world: Node

func _ready() -> void:
    watchdog_seconds=40.0
    get_node("/root/GameClock").running=false
    Assets.enabled=false
    var source: Resource=CD.create()
    source.identity["first_name"]="Hosta"
    source.identity["last_name"]="Vlastní"
    source.personality["traits"]=["aktivni"]
    var code: String=Codec.encode_code(source.to_dict())
    world=Main.new()
    world.net_config={"mode":"host","port":0,"name":"Host","character":code,
        "network_character_editor":true,"hud":true,"camera":false,
        "visuals":false,"audio":false,"autosave":false}
    add_child(world)
    _run.call_deferred()

func _run() -> void:
    await get_tree().process_frame
    section("Actual host owner")
    check(world.net.mode==world.net.Mode.HOST,"real native ENet host starts")
    check(world.net.character_edit_apply_rpc_enabled,"network editor enabled with explicit cfg")
    var sim=world.get_selected_sim()
    check(sim != null and sim.sim_name=="Hosta Vlastní","host controls own custom character")
    if sim == null:
        finish("test_host_character_editor")
        return
    var name:String=String(sim.name)
    check(world.net.server_can_edit_character(1,name),"server authenticated host ownership")
    var snap:Dictionary=world.read_character_edit(name)
    check(snap.get("ok",false),"host reads own authoritative private character")
    var other = world.sims[0] if world.sims[0] != sim else world.sims[1]
    check(not world.read_character_edit(String(other.name)).get("ok",false),"host cannot edit unrelated resident")
    var hud=world.hud
    hud._on_edit_character()
    var panel=hud._character_editor
    check(panel != null and is_instance_valid(panel) and panel._session.is_open(),
        "host opens shared live editor through HUD")
    if panel != null and is_instance_valid(panel):
        check(panel._host_session and panel._sexuality_controls["libido"].editable==false,
            "host identity-private sexuality fields are disabled")
        var changed:Dictionary=panel._session.draft()
        changed["body"]["height_cm"]=174.0
        panel._session.replace_draft(changed,"height")
        panel._refresh()
        panel._on_apply()
        var after:Dictionary=world.read_character_edit(name)
        check(after.get("ok",false) and after["data"]["body"]["height_cm"]==174.0
            and after["revision"]==1,
            "host Apply commits through authenticated server authority")
        check(sim.look.get("body",{}).get("height_cm")==174.0,
            "host live visual look reflects committed appearance")
        panel._on_cancel()
    world.net.shutdown()
    world.queue_free()
    await get_tree().process_frame
    Assets.enabled=true
    finish("test_host_character_editor")
