extends "res://tests/test_base.gd"
## Minimal real three-child-process ENet handshake + authenticated private read.
## Production NetSession, CharacterCodec and ACL; no SimVisual, gameplay or user saves.
const Net = preload("res://scripts/net/net_session.gd")
const CD = preload("res://scripts/character/character_data.gd")
const Codec = preload("res://scripts/character/character_codec.gd")
const Validator = preload("res://scripts/character/character_validator.gd")

class MiniActor:
	extends Node3D
	var sim_name := "Fixture"

class MiniWorld:
	extends Node3D
	const ARRIVAL_POS := Vector3.ZERO
	var sims_root: Node3D
	var net: Node
	var clock: Node
	var _character_records := {}
	var _character_revisions := {}
	func _ready() -> void:
		sims_root = Node3D.new()
		sims_root.name = "Sims"
		add_child(sims_root)
	func spawn_character(data: Dictionary, _pos: Vector3, _seed: int, node_name: String) -> Node:
		var a := MiniActor.new()
		a.name = node_name
		sims_root.add_child(a, true)
		var cd = load("res://scripts/character/character_data.gd").new()
		cd.set_from_dict(data)
		_character_records[node_name] = cd
		_character_revisions[node_name] = 1
		return a
	func find_sim(key: String) -> Node:
		return sims_root.get_node_or_null(NodePath(key))
	func get_sims() -> Array:
		return sims_root.get_children()
	func unregister_sim(node: Node) -> void:
		_character_records.erase(String(node.name))
		_character_revisions.erase(String(node.name))

func _ready() -> void:
	watchdog_seconds = 48.0
	_run.call_deferred()

func _file(token: String, name: String) -> String:
	return "user://h3_min_enet_" + token + "_" + name + ".json"

func _put(token: String, name: String, data: Dictionary) -> void:
	var target := _file(token, name)
	var temp := target + ".tmp." + str(OS.get_process_id()) + "." + str(Time.get_ticks_usec())
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_error("minimal ENet fixture marker write failed")
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()
	var e := DirAccess.rename_absolute(temp, target)
	if e != OK:
		push_error("minimal ENet fixture marker publish failed: " + str(e))

func _read_marker(token: String, name: String) -> Dictionary:
	if not FileAccess.file_exists(_file(token, name)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_file(token, name)))
	return d if d is Dictionary else {}

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() == 4 and a[0] == "worker":
		await _worker(String(a[1]), int(a[2]), String(a[3]))
	else:
		await _parent()

func _worker(role: String, port: int, token: String) -> void:
	var gs = get_node_or_null("/root/GameSettings")
	var clock = get_node_or_null("/root/GameClock")
	if gs == null or clock == null:
		_put(token, role + "_done", {"ok": false, "error": "autoload_missing"})
		get_tree().quit(2)
		return
	gs.persist = false
	gs.reset()
	clock.running = false
	var world := MiniWorld.new()
	world.name = "World"
	add_child(world)
	world.clock = clock
	var net := Net.new()
	net.name = "Net"
	world.add_child(net)
	world.net = net
	net.setup(world, clock)
	var welcomed := []
	var received := []
	var disconnected := []
	net.welcomed.connect(func(key: String): welcomed.append({"has_assignment": not key.is_empty()}))
	net.disconnected.connect(func(_why: String): disconnected.append(true))
	net.character_edit_snapshot_correlated.connect(func(req: String, key: String, data: Dictionary, rev: int):
		received.append({"token_ok": req == "a".repeat(32), "key_ok": key == net.my_sim, "revision_ok": rev >= 1, "has_private": data.has("mind") and data.has("uid")}))
	var err := OK
	if role == "server":
		err = net.host(port, "Dedicated", true, {})
	else:
		var code := ""
		if role == "owner":
			var cd = CD.create()
			cd.identity["first_name"] = "Fixture"
			cd.identity["last_name"] = "Owner"
			cd.personality["traits"] = ["optimista"]
			var valid: Dictionary = Validator.validate(cd.to_dict())
			if not bool(valid.get("ok", false)):
				_put(token, role + "_done", {"ok": false, "error": "fixture_invalid"})
				get_tree().quit(2)
				return
			code = Codec.encode_code(valid["data"])
		err = net.join("127.0.0.1", port, role, code)
	if err != OK:
		_put(token, role + "_done", {"ok": false, "error": "enet_create", "code": err})
		get_tree().quit(2)
		return
	if role == "server":
		_put(token, "server_ready", {"pid": OS.get_process_id(), "ok": true})
	var deadline := Time.get_ticks_msec() + 12000
	var requested := false
	var request_ok := false
	var result := {}
	var saw_owner_acl := false
	var saw_observer := false
	while Time.get_ticks_msec() < deadline:
		if role == "owner":
			if not welcomed.is_empty() and not requested:
				requested = true
				request_ok = net.request_character_edit_snapshot("a".repeat(32))
			if not received.is_empty():
				result = {"ok": requested and request_ok and received.size() == 1 and bool(received[0]["token_ok"]) and bool(received[0]["key_ok"]) and bool(received[0]["revision_ok"]) and bool(received[0]["has_private"]), "welcomed": true, "sent": request_ok, "reply": true, "private": bool(received[0]["has_private"]), "pid": OS.get_process_id()}
				break
		elif role == "observer":
			if not welcomed.is_empty():
				requested = true
				request_ok = net.request_character_edit_snapshot("b".repeat(32))
				_put(token, "observer_ready", {"pid": OS.get_process_id()})
				var overlapped := await wait_until(func(): return not _read_marker(token, "owner_done").is_empty(), 9.0)
				await get_tree().create_timer(0.35).timeout
				result = {"ok": overlapped and not request_ok and received.is_empty() and net.my_sim.is_empty(), "overlapped": overlapped, "welcomed": true, "sent": request_ok, "reply": not received.is_empty(), "pid": OS.get_process_id()}
				break
		else:
			var owner_ok := false
			var observer_ok := false
			for peer_id in net.players:
				var p: Dictionary = net.players[peer_id]
				if bool(p.get("own", false)):
					owner_ok = net.server_can_edit_character(int(peer_id), String(p.get("sim", ""))) and world._character_records.has(String(p.get("sim", "")))
				else:
					observer_ok = true
			saw_owner_acl = saw_owner_acl or owner_ok
			saw_observer = saw_observer or observer_ok
			if saw_owner_acl and saw_observer:
				result = {"ok": true, "owner_acl": saw_owner_acl, "observer_registered": saw_observer, "pid": OS.get_process_id()}
				break
		await get_tree().process_frame
	if result.is_empty():
		result = {"ok": false, "error": "deadline", "welcomed": not welcomed.is_empty(), "sent": request_ok, "reply": not received.is_empty(), "connected": net._connected, "disconnected": not disconnected.is_empty(), "pid": OS.get_process_id()}
	_put(token, role + "_done", result)
	if role == "server":
		await get_tree().create_timer(0.5).timeout
	net.shutdown()
	get_tree().quit(0 if bool(result.get("ok", false)) else 2)

func _spawn(role: String, port: int, token: String) -> int:
	return OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/diagnostics/h3_minimal_first_owner_enet.tscn", "--", "worker", role, str(port), token]))

func _parent() -> void:
	section("Minimal independent-process production NetSession: welcome / private owner RPC")
	var token := str(Time.get_ticks_usec()) + "_" + str(OS.get_process_id())
	var port := 31000 + randi() % 16000
	var pids := []
	var server := _spawn("server", port, token)
	pids.append(server)
	check(server > 0, "server child launched")
	var ready := server > 0 and await wait_until(func(): return not _read_marker(token, "server_ready").is_empty(), 8.0)
	check(ready, "server ready without SimVisual")
	var observer := _spawn("observer", port, token) if ready else -1
	pids.append(observer)
	check(observer > 0, "observer child launched")
	var observer_ready := observer > 0 and await wait_until(func(): return not _read_marker(token, "observer_ready").is_empty(), 8.0)
	check(observer_ready, "spectator connected before first owner read")
	var owner := _spawn("owner", port, token) if observer_ready else -1
	pids.append(owner)
	check(owner > 0, "owner child launched")
	var owner_done := owner > 0 and await wait_until(func(): return not _read_marker(token, "owner_done").is_empty(), 11.0)
	check(owner_done, "first owner completed handshake/read")
	var all_done := observer > 0 and await wait_until(func(): return not _read_marker(token, "observer_done").is_empty() and not _read_marker(token, "server_done").is_empty(), 11.0)
	check(all_done, "three workers reported results")
	var od := _read_marker(token, "owner_done")
	var sd := _read_marker(token, "server_done")
	var vd := _read_marker(token, "observer_done")
	check(bool(od.get("ok", false)) and bool(od.get("welcomed", false)) and bool(od.get("sent", false)) and bool(od.get("reply", false)), "owner received correlated authenticated private reply", JSON.stringify(od))
	check(bool(sd.get("ok", false)) and bool(sd.get("owner_acl", false)), "server registered first owner and passed real ACL", JSON.stringify(sd))
	check(bool(vd.get("ok", false)) and bool(vd.get("welcomed", false)) and bool(vd.get("overlapped", false)) and not bool(vd.get("sent", true)) and not bool(vd.get("reply", true)), "spectator cannot request or receive owner private read", JSON.stringify(vd))
	check(server > 0 and owner > 0 and observer > 0 and server != owner and server != observer and owner != observer, "three distinct worker PIDs")
	print("H3_MIN_ENET_SUMMARY ", JSON.stringify({"owner": od, "server": sd, "observer": vd}))
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	for key in ["server_ready", "server_done", "owner_done", "observer_ready", "observer_done"]:
		var path := ProjectSettings.globalize_path(_file(token, key))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	finish("h3_minimal_first_owner_enet")
