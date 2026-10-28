extends "res://tests/test_base.gd"
## Independent OS-process production Main/NetSession ENet hello/spawn.
## This is NOT a transport-only mock: real World, server CharacterData,
## authenticated owned character and real SimPuppet must materialize.
const Main := preload("res://main.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Assets := preload("res://scripts/assets/asset_library.gd")

func _ready() -> void:
    watchdog_seconds = 44.0
    _run.call_deferred()

func _file(token: String, name: String) -> String:
    return "user://realworld_mp_" + token + "_" + name + ".json"

func _write(token: String, name: String, data: Dictionary) -> void:
    var f := FileAccess.open(_file(token, name), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(data))
        f.close()

func _read(token: String, name: String) -> Dictionary:
    if not FileAccess.file_exists(_file(token, name)):
        return {}
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_file(token, name)))
    return raw if raw is Dictionary else {}

func _run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if args.size() == 4 and args[0] == "worker":
        await _worker(String(args[1]), int(args[2]), String(args[3]))
    else:
        await _parent()

func _worker(role: String, port: int, token: String) -> void:
    _write(token, role + "_stage", {"phase": "started", "pid": OS.get_process_id()})
    var settings := get_node_or_null("/root/GameSettings")
    var clock := get_node_or_null("/root/GameClock")
    if settings == null or clock == null:
        _write(token, role + "_done", {"ok": false, "error": "required_autoload_missing"})
        get_tree().quit(2)
        return
    settings.persist = false
    settings.reset()
    clock.running = false
    Assets.enabled = false
    var config := {"mode": role, "port": port, "audio": false, "hud": false,
        "camera": false, "visuals": false, "autoload": false, "autosave": false,
        "network_character_editor": true, "clock": clock}
    if role == "client":
        var cd := CharacterData.create()
        cd.identity["first_name"] = "Mira"
        cd.identity["last_name"] = "WorldProcess"
        cd.personality["traits"] = ["optimista"]
        var canonical: Dictionary = Validator.validate(cd.to_dict())
        if not bool(canonical.get("ok", false)):
            _write(token, role + "_done", {"ok": false, "error": "character_invalid",
                "errors": Array(canonical.get("errors", []))})
            get_tree().quit(2)
            return
        config["address"] = "127.0.0.1"
        config["name"] = "RealProcessClient"
        config["character"] = Codec.encode_code(canonical["data"])
    var world := Main.new()
    world.name = "World"
    world.net_config = config
    _write(token, role + "_stage", {"phase": "adding_production_world", "pid": OS.get_process_id()})
    add_child(world)
    _write(token, role + "_stage", {"phase": "world_ready", "pid": OS.get_process_id(),
        "net_mode": int(world.net.mode) if world.net != null else -1,
        "sims": world.sims.size()})
    if role == "server" and world.net != null and world.net.mode == world.net.Mode.DEDICATED and world.net._connected:
        _write(token, "server_ready", {"pid": OS.get_process_id(), "port": port,
            "net_mode": int(world.net.mode)})
    var limit := Time.get_ticks_msec() + 16000
    var finished := false
    var read_events: Array = []
    var apply_events: Array = []
    var read_token := Crypto.new().generate_random_bytes(16).hex_encode()
    var apply_token := Crypto.new().generate_random_bytes(16).hex_encode()
    var read_sent := false
    var apply_sent := false
    if role == "client" and world.net != null:
        world.net.character_edit_snapshot_correlated.connect(func(req: String, sim: String, data: Dictionary, rev: int) -> void:
            read_events.append({"token": req, "sim": sim, "data": data, "revision": rev}))
        world.net.character_edit_apply_correlated.connect(func(req: String, sim: String, ok: bool, rev: int, changed: bool, reason: String) -> void:
            apply_events.append({"token": req, "sim": sim, "ok": ok, "revision": rev, "changed": changed, "reason": reason}))
    while Time.get_ticks_msec() < limit:
        if world.net == null:
            break
        if role == "server":
            for peer_id in world.net.players:
                var assignment: Dictionary = world.net.players[peer_id]
                if int(peer_id) > 1 and bool(assignment.get("own", false)):
                    var key := String(assignment.get("sim", ""))
                    var record_ok: bool = world._character_records.has(key)
                    var owner_ok: bool = world.net.server_can_edit_character(int(peer_id), key)
                    var revision := int(world._character_revisions.get(key, -1))
                    if record_ok and owner_ok and revision >= 1:
                        var result: Dictionary = world.net.server_read_character_edit(int(peer_id), key)
                        var cd = world._character_records[key]
                        var private_ok := absf(float(cd.mind.get("self_defectiveness", -1.0)) - 0.68) < 0.001
                        var look_ok := absf(float(cd.body.get("height_cm", -1.0)) - 174.5) < 0.001
                        _write(token, "server_done", {"ok": record_ok and owner_ok and bool(result.get("ok", false)) and private_ok and look_ok,
                            "pid": OS.get_process_id(), "peer": int(peer_id), "sim": key,
                            "owner": owner_ok, "record": record_ok, "private_owner_read": bool(result.get("ok", false)),
                            "revision": revision, "private_belief_applied": private_ok, "height_applied": look_ok})
                        finished = true
                        break
        elif role == "client" and world.net._connected and not world.net.my_sim.is_empty():
            var key := String(world.net.my_sim)
            var actor := world.find_sim(key)
            if actor != null:
                if not read_sent:
                    read_sent = world.net.request_character_edit_snapshot(read_token)
                    _write(token, "client_stage", {"phase": "owner_read_requested", "sent": read_sent})
                if read_sent and not apply_sent and not read_events.is_empty():
                    var read: Dictionary = read_events.back()
                    if String(read.get("token", "")) == read_token and String(read.get("sim", "")) == key:
                        var updated: Dictionary = read["data"].duplicate(true)
                        updated["body"]["height_cm"] = 174.5
                        updated["mind"]["self_defectiveness"] = 0.68
                        apply_sent = world.net.request_character_edit_apply(int(read["revision"]), updated, apply_token)
                        _write(token, "client_stage", {"phase": "owner_apply_requested", "sent": apply_sent, "prior_revision": int(read["revision"])})
                if not apply_events.is_empty():
                    var ack: Dictionary = apply_events.back()
                    if String(ack.get("token", "")) == apply_token and String(ack.get("sim", "")) == key:
                        var accepted: bool = bool(ack.get("ok", false)) and bool(ack.get("changed", false))
                        var height: float = float(actor.look.get("body", {}).get("height_cm", 0.0))
                        var public_ok: bool = absf(height - 174.5) < 0.001 and int(world.net._public_look_revisions.get(key, 0)) == int(ack.get("revision", -1))
                        if not accepted or public_ok:
                            _write(token, "client_done", {"ok": accepted and public_ok and read_sent and apply_sent,
                                "pid": OS.get_process_id(), "sim": key, "spawned": true,
                                "connected": world.net._connected, "puppet": actor.get_script() == load("res://scripts/sim/sim_puppet.gd"),
                                "private_records": world._character_records.size(),
                                "public_private_leak": actor.look.has("mind") or actor.look.has("story"),
                                "owner_private_read": read_events.size() == 1, "apply_accepted": accepted,
                                "revision": int(ack.get("revision", -1)), "public_updated": public_ok,
                                "apply_reason": String(ack.get("reason", ""))})
                            finished = true
        if finished:
            break
        await get_tree().process_frame
    if not finished:
        _write(token, role + "_done", {"ok": false, "error": "world_lifecycle_timeout",
            "stage": _read(token, role + "_stage"), "net_connected": world.net._connected if world.net != null else false,
            "peer_count": world.net.players.size() if world.net != null else -1,
            "my_sim": world.net.my_sim if world.net != null else "",
            "sims": world.sims.size()})
    if role == "server":
        var wait_until_client := Time.get_ticks_msec() + 2200
        while _read(token, "client_done").is_empty() and Time.get_ticks_msec() < wait_until_client:
            await get_tree().process_frame
    await get_tree().create_timer(0.3).timeout
    if world.net != null:
        world.net.shutdown()
    get_tree().quit(0 if finished else 2)

func _spawn(role: String, port: int, token: String) -> int:
    var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
        "res://tests/test_world_enet_multiprocess.tscn", "--", "worker", role, str(port), token])
    return OS.create_process(OS.get_executable_path(), args)

func _parent() -> void:
    section("Production World independent-process ENet: character hello, spawn, owner ACL")
    var token := str(Time.get_ticks_usec()) + "_" + str(OS.get_process_id())
    var port := 30000 + randi() % 18000
    var server_pid := _spawn("server", port, token)
    check(server_pid > 0, "separate server OS process launched")
    var ready := false
    if server_pid > 0:
        ready = await wait_until(func(): return FileAccess.file_exists(_file(token, "server_ready")) or FileAccess.file_exists(_file(token, "server_done")), 9.0)
    var server_ready: Dictionary = _read(token, "server_ready")
    var stage_server: Dictionary = _read(token, "server_stage")
    check(ready and not server_ready.is_empty(), "real production World server initialized UDP",
        "stage=" + JSON.stringify(stage_server))
    var client_pid := -1
    if not server_ready.is_empty():
        client_pid = _spawn("client", port, token)
    check(client_pid > 0, "separate client OS process launched")
    var reported := false
    if client_pid > 0:
        reported = await wait_until(func(): return FileAccess.file_exists(_file(token, "server_done")) and FileAccess.file_exists(_file(token, "client_done")), 19.0)
    var server: Dictionary = _read(token, "server_done")
    var client: Dictionary = _read(token, "client_done")
    print("WORLD_MP_SERVER=", JSON.stringify(server))
    print("WORLD_MP_CLIENT=", JSON.stringify(client))
    print("WORLD_MP_STAGES=", JSON.stringify({"server": _read(token, "server_stage"),
        "client": _read(token, "client_stage")}))
    check(reported, "both production World OS processes reported final state")
    check(server_pid > 0 and client_pid > 0 and server_pid != client_pid
        and server_pid != OS.get_process_id() and client_pid != OS.get_process_id(),
        "all three process IDs are distinct")
    check(bool(server.get("ok", false)) and bool(client.get("ok", false))
        and String(server.get("sim", "")) == String(client.get("sim", "")),
        "authenticated server owns same character the separate client receives")
    check(bool(server.get("owner", false)) and bool(server.get("record", false))
        and bool(server.get("private_owner_read", false)),
        "actual production owner ACL permits only assigned server-side character")
    check(bool(client.get("puppet", false)) and int(client.get("private_records", -1)) == 0
        and not bool(client.get("public_private_leak", true)),
        "independent client has real SimPuppet without private CharacterData")
    check(bool(client.get("owner_private_read", false)) and bool(client.get("apply_accepted", false)),
        "real network owner received correlated private read and accepted Apply")
    check(bool(server.get("private_belief_applied", false)) and bool(server.get("height_applied", false))
        and int(server.get("revision", -1)) == 1,
        "actual production server committed both private belief and public height")
    check(bool(client.get("public_updated", false)) and int(client.get("revision", -1)) == 1,
        "client received canonical public-only revision after server Apply")
    for pid in [server_pid, client_pid]:
        if pid > 0 and OS.is_process_running(pid):
            OS.kill(pid)
    for k in ["server_stage", "server_ready", "server_done", "client_stage", "client_done"]:
        var path := ProjectSettings.globalize_path(_file(token, k))
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
    finish("test_world_enet_multiprocess")
