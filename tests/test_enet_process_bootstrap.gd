extends "res://tests/test_base.gd"
## Independent Godot OS processes + real ENet handshake. No character data or Apply.
var _joined := false

func _ready() -> void:
	watchdog_seconds = 40.0
	_run.call_deferred()

func _path(token: String, key: String) -> String:
	return "user://enet_boot_" + token + "_" + key + ".json"

func _write(token: String, key: String, value: Dictionary) -> void:
	var f := FileAccess.open(_path(token, key), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(value))
		f.close()

func _read(token: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(_path(token, key)):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path(token, key)))
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 4 and args[0] == "worker":
		await _worker(args[1], int(args[2]), args[3])
	else:
		await _parent()

func _worker(role: String, port: int, token: String) -> void:
	_write(token, role + "_boot", {"pid": OS.get_process_id(), "role": role})
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 2) if role == "server" else peer.create_client("127.0.0.1", port)
	if err != OK:
		_write(token, role + "_done", {"pid": OS.get_process_id(), "error": "create_peer", "code": err})
		get_tree().quit(2)
		return
	if role == "server":
		multiplayer.peer_connected.connect(func(_peer_id: int): _joined = true)
		_write(token, "server_ready", {"pid": OS.get_process_id(), "port": port})
	else:
		multiplayer.connected_to_server.connect(func(): _joined = true)
	multiplayer.multiplayer_peer = peer
	var deadline := Time.get_ticks_msec() + 10000
	while not _joined and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_write(token, role + "_done", {"pid": OS.get_process_id(), "joined": _joined})
	await get_tree().create_timer(0.4).timeout
	peer.close()
	get_tree().quit(0 if _joined else 2)

func _spawn(role: String, port: int, token: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/test_enet_process_bootstrap.tscn", "--", "worker", role, str(port), token])
	return OS.create_process(OS.get_executable_path(), args)

func _parent() -> void:
	section("Independent-process ENet bootstrap (no production character lifecycle)")
	var token := str(Time.get_ticks_usec()) + "_" + str(OS.get_process_id())
	var port := 29000 + randi() % 10000
	var server_pid := _spawn("server", port, token)
	check(server_pid > 0, "server child process launched")
	var ready := false
	if server_pid > 0:
		ready = await wait_until(func(): return not _read(token, "server_ready").is_empty(), 8.0)
	check(ready, "server bound UDP and reported ready")
	var client_pid := -1
	if ready:
		client_pid = _spawn("client", port, token)
	check(client_pid > 0, "client child process launched")
	var done := false
	if client_pid > 0:
		done = await wait_until(func(): return not _read(token, "server_done").is_empty() and not _read(token, "client_done").is_empty(), 14.0)
	check(done, "both independent processes reported results")
	var server := _read(token, "server_done")
	var client := _read(token, "client_done")
	check(server_pid > 0 and client_pid > 0 and server_pid != client_pid and server_pid != OS.get_process_id() and client_pid != OS.get_process_id(), "three distinct OS process IDs")
	check(done and server.get("joined", false) == true and client.get("joined", false) == true, "real ENet handshake across process boundary")
	check(done and server.get("pid", -1) == server_pid and client.get("pid", -1) == client_pid, "reported PIDs match spawned workers")
	for pid in [server_pid, client_pid]:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	for key in ["server_boot", "server_ready", "server_done", "client_boot", "client_done"]:
		var path := ProjectSettings.globalize_path(_path(token, key))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	finish("test_enet_process_bootstrap")
