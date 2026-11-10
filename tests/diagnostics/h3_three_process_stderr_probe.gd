extends "res://tests/diagnostics/h3_three_process.FAILING.gd"
## TEST ONLY: unchanged inherited 17 gates, worker stdout/stderr captured by role.
## Python wrapper execv() preserves PID so inherited process liveness/kill still work.
func _spawn(role: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/diagnostics/h3_three_process_stderr_probe.tscn", "--", "worker", _token, str(_port), role])
	if _prewarm_clients and role in ["owner", "observer"]:
		args.append("prewarm")
	if _extended_enet_timeout:
		args.append("enet-extended")
	if _hair_async_test:
		args.append("hair-async")
	if _hair_prewarm_test:
		args.append("hair-prewarm")
	if _visual_light_test:
		args.append("visual-light")
	if _visual_skip_hair_test:
		args.append("visual-skip-hair")
	if _visual_skip_outfit_test:
		args.append("visual-skip-outfit")
	if _visual_defer_outfit_test:
		args.append("visual-defer-outfit")
	var log_path := ProjectSettings.globalize_path("user://h3_3proc_" + _token + "_stderr_" + role + ".log")
	var wrapper := ProjectSettings.globalize_path("res://tests/diagnostics/h3_child_capture.py")
	var wrapped := PackedStringArray([wrapper, log_path, OS.get_executable_path()])
	wrapped.append_array(args)
	var pid := OS.create_process("python3", wrapped)
	print("H3_ROLE_LOG role=", role, " pid=", pid, " path=", log_path)
	return pid

# TEST-ONLY: annotate the two inherited guarded get_unique_id call sites.
# Do not change the 17 acceptance gates or production networking.
var _h3_id_probe_sequence: int = 0

func _h3_safe_peer_id(w: Node3D) -> int:
	_h3_id_probe_sequence += 1
	var argv := OS.get_cmdline_user_args()
	var role: String = String(argv[3]) if argv.size() >= 4 and String(argv[0]) == "worker" else "unknown"
	var net = w.net if is_instance_valid(w) else null
	var api: MultiplayerAPI = net.multiplayer if is_instance_valid(net) else null
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	var before: int = peer.get_connection_status() if peer != null else -1
	var connected: bool = bool(net._connected) if is_instance_valid(net) else false
	var seq: int = _h3_id_probe_sequence
	var before_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_trace(role, "id_guard_pre", {"seq": seq, "utc_ms": before_ms, "transport": before, "net_connected": connected})
	print("H3_ID_GUARD_PRE role=", role, " seq=", seq, " utc_ms=", before_ms, " transport=", before, " net_connected=", connected)
	var result: int = super._h3_safe_peer_id(w)
	var after: int = peer.get_connection_status() if peer != null and is_instance_valid(peer) else -1
	var after_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	print("H3_ID_GUARD_POST role=", role, " seq=", seq, " utc_ms=", after_ms, " transport=", after, " peer_id=", result)
	_trace(role, "id_guard_post", {"seq": seq, "utc_ms": after_ms, "transport": after, "peer_id": result})
	return result
# TEST ONLY: observe transport transitions without calling get_unique_id().
# UTC timestamps correlate separate processes; monotonic ticks are process-local.
func _h3_transport_state(w: Node3D) -> Dictionary:
	if not is_instance_valid(w):
		return {"world_valid": false}
	var net = w.net
	if not is_instance_valid(net):
		return {"net_valid": false}
	var api: MultiplayerAPI = net.multiplayer
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	var status: int = peer.get_connection_status() if is_instance_valid(peer) else -1
	return {
		"transport": status,
		"net_connected": bool(net._connected),
		"assigned": not String(net.my_sim).is_empty(),
		"peer_count": api.get_peers().size() if api != null and status == MultiplayerPeer.CONNECTION_CONNECTED else -1
	}

func _attach_trace(w: Node3D, role: String) -> void:
	super._attach_trace(w, role)
	if not is_instance_valid(w) or not w.is_inside_tree():
		_trace(role, "transport_watch_unavailable", {"reason": "world_not_in_tree"})
		return
	var watcher := Timer.new()
	watcher.name = "H3TransportStateWatcher"
	watcher.wait_time = 0.10
	watcher.one_shot = false
	w.add_child(watcher)
	var weak_world: WeakRef = weakref(w)
	var last: Dictionary = {"state": JSON.stringify(_h3_transport_state(w))}
	var started_ticks: int = Time.get_ticks_msec()
	_trace(role, "transport_watch_start", {
		"utc_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"ticks_ms": started_ticks,
		"state": _h3_transport_state(w)
	})
	watcher.timeout.connect(func():
		var live = weak_world.get_ref()
		if not is_instance_valid(live):
			return
		var snapshot: Dictionary = _h3_transport_state(live)
		var encoded: String = JSON.stringify(snapshot)
		if encoded == String(last["state"]):
			return
		last["state"] = encoded
		var utc_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
		var ticks_ms: int = Time.get_ticks_msec()
		_trace(role, "transport_watch_change", {
			"utc_ms": utc_ms,
			"ticks_ms": ticks_ms,
			"elapsed_ms": ticks_ms - started_ticks,
			"state": snapshot
		})
		print("H3_TRANSPORT_CHANGE role=", role, " utc_ms=", utc_ms, " state=", encoded)
	)
	watcher.start()
	if role == "server":
		# Test-only change-only snapshots. No player names, character or private data.
		var server_last: Dictionary = {"encoded": JSON.stringify(_h3_server_registry(w))}
		_trace(role, "server_registry_start", _h3_server_registry(w))
		watcher.timeout.connect(func():
			var live = weak_world.get_ref()
			if not is_instance_valid(live):
				return
			var snap: Dictionary = _h3_server_registry(live)
			var encoded: String = JSON.stringify(snap)
			if encoded != String(server_last["encoded"]):
				server_last["encoded"] = encoded
				_trace(role, "server_registry_change", snap)
				print("H3_SERVER_REGISTRY_CHANGE ",JSON.stringify(snap))
		)
		w.net.multiplayer.peer_disconnected.connect(func(peer_id):
			var live = weak_world.get_ref()
			if is_instance_valid(live):
				_trace(role, "server_registry_peer_disconnected", {"peer": peer_id, "registry": _h3_server_registry(live)})
				print("H3_SERVER_REGISTRY_DISCONNECT peer=",peer_id," snapshot=",JSON.stringify(_h3_server_registry(live)))
		)

# TEST ONLY: integer peer-ID membership snapshots, no private character payload.
func _h3_server_registry(w: Node3D) -> Dictionary:
	if not is_instance_valid(w):
		return {"world_valid": false}
	var net = w.net
	if not is_instance_valid(net):
		return {"net_valid": false}
	var api: MultiplayerAPI = net.multiplayer
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	var status: int = peer.get_connection_status() if is_instance_valid(peer) else -1
	var transport_ids: Array = []
	if api != null and status == MultiplayerPeer.CONNECTION_CONNECTED:
		for peer_id in api.get_peers():
			transport_ids.append(int(peer_id))
	transport_ids.sort()
	var registered: Array = net.players.keys()
	registered.sort()
	var pending: Array = net.pending.keys()
	pending.sort()
	var kicks: Array = net._kick_at.keys()
	kicks.sort()
	return {"transport": status, "connected": bool(net._connected),
		"transport_ids": transport_ids, "registered_ids": registered,
		"pending_ids": pending, "scheduled_kick_ids": kicks}

# H3 TEST-ONLY server NetSession lifecycle probe. No on-disk production changes.
var _h3_net_probe_installed: bool = false

func _world(mode: String, character_code: String = "") -> Node3D:
	if mode == "server" and not _h3_net_probe_installed:
		if not _h3_install_net_probe():
			push_error("H3_NET_PROBE_INSTALL_FAILED; refusing uninstrumented server test")
			get_tree().quit(2)
			return null
		_h3_net_probe_installed = true
	return super._world(mode, character_code)

func _h3_install_net_probe() -> bool:
	const PATH := "res://scripts/net/net_session.gd"
	const EXPECTED_SHA := "6c0a13eae03f2da6cddb16b6ef3240bb3b8577c4e3c21aa23a06c8635c84ce97"
	if FileAccess.get_sha256(PATH) != EXPECTED_SHA:
		print("H3_NET_PROBE_ERROR source_hash_changed")
		return false
	var sc: GDScript = load(PATH)
	if sc == null:
		return false
	var original: String = sc.source_code
	var patched: String = original
	var anchors := [
		"func _kick_later(id: int) -> void:\n\tpending.erase(id)",
		"func _kick(id: int) -> void:\n\tstats[\"kicked\"] += 1",
		"func _on_peer_disconnected(id: int) -> void:\n\t_edit_limiters.erase(id)"
	]
	var labels := ["kick_later", "kick", "peer_disconnected"]
	for i in range(anchors.size()):
		if patched.count(anchors[i]) != 1:
			print("H3_NET_PROBE_ERROR anchor_mismatch ",labels[i])
			return false
		var prefix: String = anchors[i].get_slice("\n", 0)
		var rest: String = anchors[i].substr(prefix.length())
		var injected: String = "\n\tprint(\"H3_NET_PRE event="+labels[i]+" utc_ms=\",int(Time.get_unix_time_from_system()*1000.0),\" peer=\",id,\" registered=\",players.has(id),\" pending=\",pending.has(id),\" kick_scheduled=\",_kick_at.has(id),\" transport=\",multiplayer.multiplayer_peer.get_connection_status() if multiplayer.multiplayer_peer != null else -1)"
		patched = patched.replace(anchors[i],prefix+injected+rest)
	sc.source_code = patched
	var err: int = sc.reload()
	if err != OK:
		print("H3_NET_PROBE_ERROR reload=",err)
		sc.source_code = original
		sc.reload()
		return false
	print("H3_NET_PROBE_INSTALLED server_only=1 source_disk_sha=",FileAccess.get_sha256(PATH))
	return true

# H3 TEST-ONLY: per-worker frame/event-loop gap timestamps. No acceptance gates altered.
# Captures the first frame after a synchronous stall; not an ENet disconnect reason.
var _h3_gap_role: String = ""
var _h3_gap_last_us: int = 0
var _h3_gap_count: int = 0
var _h3_gap_max_us: int = 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4 and String(args[0]) == "worker":
		_h3_gap_role = String(args[3])
		_h3_gap_last_us = Time.get_ticks_usec()
		print("H3_FRAME_PROBE_START role=", _h3_gap_role, " utc_ms=", int(Time.get_unix_time_from_system() * 1000.0))
	await super._run()

func _process(_delta: float) -> void:
	if _h3_gap_role.is_empty() or _h3_gap_last_us == 0:
		return
	var now_us: int = Time.get_ticks_usec()
	var gap_us: int = now_us - _h3_gap_last_us
	_h3_gap_last_us = now_us
	if gap_us < 250000:
		return
	_h3_gap_count += 1
	var new_max: bool = gap_us > _h3_gap_max_us
	_h3_gap_max_us = maxi(gap_us, _h3_gap_max_us)
	if _h3_gap_count <= 32 or new_max:
		var end_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
		print("H3_FRAME_GAP role=", _h3_gap_role, " utc_end_ms=", end_ms,
			" utc_start_est_ms=", end_ms - int(gap_us / 1000), " gap_ms=", int(gap_us / 1000),
			" sample=", _h3_gap_count, " max_ms=", int(_h3_gap_max_us / 1000),
			" owner_stage=", _h3_owner_stage if _h3_gap_role == "owner" else "n/a")
