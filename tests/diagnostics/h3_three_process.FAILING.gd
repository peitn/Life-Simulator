extends "res://tests/test_base.gd"
## FAILING DIAGNOSTIC: three separate Godot child OS processes using production Main/NetSession.
## Not a passing regression; isolate until cross-process lifecycle and privacy are resolved.
## Parent is a fourth process. Only fictional fixture data; no player saves.
const Main = preload("res://main.gd")
const SimVisual = preload("res://scripts/sim/sim_visual.gd")
const HairRig = preload("res://scripts/assets/hair_rig.gd")
const ClothingWardrobe = preload("res://scripts/assets/clothing_wardrobe.gd")
const Randomizer = preload("res://scripts/character/character_randomizer.gd")
const Validator = preload("res://scripts/character/character_validator.gd")
const Codec = preload("res://scripts/character/character_codec.gd")
const Resolver = preload("res://scripts/character/appearance_resolver.gd")

var _h3_owner_stage := "worker_boot"
var _h3_owner_stage_since_us := 0

func _h3_owner_phase(stage: String) -> void:
	_h3_owner_stage = stage
	_h3_owner_stage_since_us = Time.get_ticks_usec()
	_trace("owner", "owner_stage", {"stage": stage, "ticks_us": _h3_owner_stage_since_us})

var _token := ""
var _port := 0
var _prewarm_clients := false
var _extended_enet_timeout := false
var _hair_async_test := false
var _hair_prewarm_test := false
## Opt-in (7 Nov 2026): the game's background C5 wardrobe build (ClothingWardrobe.async_load + prewarm).
var _wardrobe_async_test := false
## Opt-in (7 Nov 2026): exactly the GAME path – Main's `async_character_assets` (hair + wardrobe in
## the background, client prewarms one character visual before connecting). Used by the passing
## regression tests/test_h3_three_process_game.tscn.
var _game_assets_test := false
var _visual_light_test := false
var _visual_skip_hair_test := false
var _visual_skip_outfit_test := false
var _visual_defer_outfit_test := false

func _ready() -> void:
	watchdog_seconds = 107.0
	_run.call_deferred()

func _path(role: String) -> String:
	return "user://h3_3proc_" + _token + "_" + role + ".json"

func _put(role: String, data: Dictionary) -> void:
	# Test IPC only: readers must never observe a partially written JSON marker.
	# Temp and destination are in the same user:// directory for atomic rename.
	var target := _path(role)
	var temp := target + ".tmp." + str(OS.get_process_id()) + "." + str(Time.get_ticks_usec())
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_error("H3 marker temp open failed for " + role)
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()
	var rename_error := DirAccess.rename_absolute(temp, target)
	if rename_error != OK:
		push_error("H3 marker atomic publish failed for " + role + " (error " + str(rename_error) + ")")
		DirAccess.remove_absolute(temp)

func _read_marker(role: String) -> Dictionary:
	if not FileAccess.file_exists(_path(role)):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(_path(role)))
	return v if v is Dictionary else {}

func _trace(role: String, phase: String, details: Dictionary = {}) -> void:
	# Fixture-only, per-process trace. Never write private character payloads.
	var path := "user://h3_3proc_" + _token + "_trace_" + role + ".jsonl"
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ
	var f := FileAccess.open(path, mode)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({"ms": Time.get_ticks_msec(), "utc_ms": int(Time.get_unix_time_from_system() * 1000.0), "pid": OS.get_process_id(), "phase": phase, "details": details}))
	f.close()

func _start_frame_probe(event: Callable) -> Dictionary:
	# Fixture-only: sample frame stalls while a real RPC is pending.
	# Never record private payloads or change any acceptance deadline.
	var stats := {"last_us": Time.get_ticks_usec(), "frames": 0, "max_gap_ms": 0.0,
		"gaps_250ms": 0, "gaps_1000ms": 0, "event_seen": false, "event_utc_ms": -1}
	var cb := func():
		var now := Time.get_ticks_usec()
		var gap_ms := float(now - int(stats["last_us"])) / 1000.0
		stats["last_us"] = now
		stats["frames"] = int(stats["frames"]) + 1
		stats["max_gap_ms"] = maxf(float(stats["max_gap_ms"]), gap_ms)
		if gap_ms >= 250.0:
			stats["gaps_250ms"] = int(stats["gaps_250ms"]) + 1
		if gap_ms >= 1000.0:
			stats["gaps_1000ms"] = int(stats["gaps_1000ms"]) + 1
		if not bool(stats["event_seen"]) and bool(event.call()):
			stats["event_seen"] = true
			stats["event_utc_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	get_tree().process_frame.connect(cb)
	return {"callback": cb, "stats": stats}

func _stop_frame_probe(probe: Dictionary) -> Dictionary:
	var cb: Callable = probe["callback"]
	if get_tree().process_frame.is_connected(cb):
		get_tree().process_frame.disconnect(cb)
	var stats: Dictionary = probe["stats"]
	stats.erase("last_us")
	return stats

func _h3_async_lifecycle_begin(role: String) -> Dictionary:
	# Test-only, bounded main-thread observation. No I/O or HairRig mutex in callbacks.
	var probe := {"events": [], "seen": {}, "last_us": 0, "samples": 0}
	var added := func(node: Node):
		var script: Script = node.get_script() as Script
		if script == null or script.resource_path != "res://scripts/sim/sim_visual.gd":
			return
		var iid: int = node.get_instance_id()
		if (probe["seen"] as Dictionary).has(iid):
			return
		var entry := {"ref": weakref(node), "exiting": false, "last": {}}
		probe["seen"][iid] = entry
		if probe["events"].size() < 80:
			probe["events"].append({"kind": "added", "id": iid, "ms": Time.get_ticks_msec()})
		node.tree_exiting.connect(func():
			# Do not inspect the departing node or touch a mutex or disk.
			entry["exiting"] = true
			if probe["events"].size() < 80:
				probe["events"].append({"kind": "exiting", "id": iid, "ms": Time.get_ticks_msec(), "last": (entry["last"] as Dictionary).duplicate(true)})
		)
	var sample := func():
		var now: int = Time.get_ticks_usec()
		if now - int(probe["last_us"]) < 500000:
			return
		probe["last_us"] = now
		probe["samples"] = int(probe["samples"]) + 1
		for iid in probe["seen"]:
			var entry: Dictionary = probe["seen"][iid]
			if bool(entry["exiting"]):
				continue
			var visual = (entry["ref"] as WeakRef).get_ref()
			if visual == null or not is_instance_valid(visual) or visual.is_queued_for_deletion():
				continue
			var parts := {}
			for part in ["scalp", "brows", "beard"]:
				var mesh_node: MeshInstance3D = visual.hair_part(part)
				parts[part] = mesh_node != null and is_instance_valid(mesh_node) and mesh_node.mesh != null and mesh_node.visible
			if parts != entry["last"]:
				entry["last"] = parts
				if probe["events"].size() < 80:
					probe["events"].append({"kind": "parts", "id": iid, "ms": Time.get_ticks_msec(), "visible_mesh": parts})
	get_tree().node_added.connect(added)
	get_tree().process_frame.connect(sample)
	probe["added_cb"] = added
	probe["sample_cb"] = sample
	return probe

func _h3_async_lifecycle_end(role: String, probe: Dictionary) -> void:
	var added: Callable = probe["added_cb"]
	var sample: Callable = probe["sample_cb"]
	if get_tree().node_added.is_connected(added):
		get_tree().node_added.disconnect(added)
	if get_tree().process_frame.is_connected(sample):
		get_tree().process_frame.disconnect(sample)
	# Only now write one summary. No callback writes or HairRig mutex sampling.
	# Test-only snapshot AFTER callback disconnect; never hold the mutex during disk I/O.
	# A cached null mesh is a valid result for intentionally empty styles.
	var hair_cache := []
	HairRig._mutex.lock()
	for spec in [["scalp", "kratke"], ["scalp", "dlouhe_vlnite"], ["scalp", "copanky"], ["scalp", "afro"], ["brows", "prirozene"], ["brows", "rovne"], ["beard", "zadne"], ["beard", "strniste"]]:
		var key: String = String(spec[0]) + ":" + String(spec[1])
		var stats: Dictionary = HairRig.build_stats.get(key, {})
		hair_cache.append({"key": key, "cached": HairRig._meshes.has(key), "pending": HairRig._waiters.has(key),
			"build_ms": stats.get("ms", -1.0), "vertices": stats.get("verts", -1)})
	HairRig._mutex.unlock()
	_trace(role, "async_lifecycle_summary", {"tracked": probe["seen"].size(), "samples": probe["samples"], "events": probe["events"], "truncated": probe["events"].size() >= 80, "hair_cache_at_teardown": hair_cache})
	probe.erase("added_cb")
	probe.erase("sample_cb")

func _probe_marker(role: String, marker: String, timeout: float, w: Node3D) -> bool:
	# Diagnostic only: bounded wall-clock marker visibility and process-frame gaps.
	var started := Time.get_ticks_usec()
	var previous := started
	var last_trace := started - 1000000
	var max_gap_ms := 0.0
	var frames := 0
	var last_server_state := ""
	var last_server_sample := -1000000
	while Time.get_ticks_usec() - started < int(timeout * 1000000.0):
		var now := Time.get_ticks_usec()
		max_gap_ms = maxf(max_gap_ms, float(now - previous) / 1000.0)
		previous = now
		frames += 1
		if role == "server" and now - last_server_sample >= 250000:
			last_server_sample = now
			var lifecycle := {"pending": w.net.pending.size(), "players": w.net.players.size(), "records": w._character_records.size(), "sim_nodes": w.sims_root.get_child_count(), "spawned": w.net.stats.get("characters_spawned", 0)}
			lifecycle["kick_scheduled"] = w.net._kick_at.size()
			lifecycle["kicked_total"] = int(w.net.stats.get("kicked", 0))
			lifecycle["enet_peer_count"] = w.net.multiplayer.get_peers().size()
			var signature := JSON.stringify(lifecycle)
			if signature != last_server_state:
				_trace(role, "server_lifecycle_change", lifecycle)
				last_server_state = signature
		var visible := FileAccess.file_exists(_path(marker))
		var parsed := _read_marker(marker) if visible else {}
		if now - last_trace >= 1000000:
			var probe := {"marker": marker, "elapsed_ms": int((now - started) / 1000), "frames": frames, "max_frame_gap_ms": snappedf(max_gap_ms, 0.1), "visible": visible, "parsed": not parsed.is_empty(), "peers": str(w.net.multiplayer.get_peers()), "connected": w.net._connected}
			if role == "server":
				probe["pending"] = w.net.pending.size()
				probe["kick_scheduled"] = w.net._kick_at.size()
				probe["kicked_total"] = int(w.net.stats.get("kicked", 0))
				var oldest_pending_ms := 0
				for since in w.net.pending.values():
					oldest_pending_ms = maxi(oldest_pending_ms, int(Time.get_ticks_msec() - float(since) * 1000.0))
				probe["oldest_pending_ms"] = oldest_pending_ms
			_trace(role, "marker_probe", probe)
			last_trace = now
		if not parsed.is_empty():
			_trace(role, "marker_seen", {"marker": marker, "elapsed_ms": int((now - started) / 1000), "frames": frames, "max_frame_gap_ms": snappedf(max_gap_ms, 0.1), "peers": str(w.net.multiplayer.get_peers())})
			return true
		await get_tree().process_frame
	_trace(role, "marker_timeout", {"marker": marker, "elapsed_ms": int((Time.get_ticks_usec() - started) / 1000), "frames": frames, "max_frame_gap_ms": snappedf(max_gap_ms, 0.1), "peers": str(w.net.multiplayer.get_peers())})
	return false

func _probe_owner_ready(w: Node3D, timeout: float) -> bool:
	# Fixture-only timing: separate character assignment from puppet visibility.
	# No private character payloads or identity fields are logged.
	var started := Time.get_ticks_usec()
	var started_utc_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var previous := started
	var last_trace := started - 1000000
	var max_gap_ms := 0.0
	var last_owner_state := ""
	var last_transport_state := -999
	_trace("owner", "owner_ready_start", {"start_utc_ms": started_utc_ms, "deadline_utc_ms": started_utc_ms + int(timeout * 1000.0)})
	while Time.get_ticks_usec() - started < int(timeout * 1000000.0):
		var now := Time.get_ticks_usec()
		max_gap_ms = maxf(max_gap_ms, float(now - previous) / 1000.0)
		previous = now
		var assigned: bool = w.net.my_sim != ""
		var visible: bool = assigned and w.find_sim(w.net.my_sim) != null
		var transport_status: int = w.net.multiplayer.multiplayer_peer.get_connection_status() if w.net.multiplayer.multiplayer_peer != null else -1
		if transport_status != last_transport_state:
			_trace("owner", "owner_transport_state", {"status": transport_status, "elapsed_ms": int((now - started) / 1000), "connected": w.net._connected, "assigned": assigned, "visible": visible})
			last_transport_state = transport_status
		var owner_state := {"assigned": assigned, "visible": visible, "sims": w.get_sims().size(), "roster": w.net.roster.size(), "connected": w.net._connected}
		var owner_signature := JSON.stringify(owner_state)
		if owner_signature != last_owner_state:
			owner_state["elapsed_ms"] = int((now - started) / 1000)
			_trace("owner", "owner_lifecycle_change", owner_state)
			last_owner_state = owner_signature
		if now - last_trace >= 1000000:
			_trace("owner", "owner_ready_probe", {"elapsed_ms": int((now - started) / 1000), "assigned": assigned, "visible": visible, "connected": w.net._connected, "peers": w.net.multiplayer.get_peers().size(), "max_frame_gap_ms": snappedf(max_gap_ms, 0.1)})
			last_trace = now
		if visible:
			_trace("owner", "owner_ready_result", {"ok": true, "elapsed_ms": int((now - started) / 1000), "max_frame_gap_ms": snappedf(max_gap_ms, 0.1)})
			return true
		await get_tree().process_frame
	# Include the final process-frame wait even when it crosses the deadline.
	max_gap_ms = maxf(max_gap_ms, float(Time.get_ticks_usec() - previous) / 1000.0)
	_trace("owner", "owner_ready_result", {"ok": false, "elapsed_ms": int((Time.get_ticks_usec() - started) / 1000), "assigned": w.net.my_sim != "", "connected": w.net._connected, "max_frame_gap_ms": snappedf(max_gap_ms, 0.1), "transport_status": last_transport_state, "start_utc_ms": started_utc_ms})
	return false

func _server_acl_snapshot(w: Node3D, peer_id: int, key: String) -> Dictionary:
	# Diagnostic booleans only: never emit private character data or UID values.
	var player: Dictionary = w.net.players.get(peer_id, {})
	var sim = w.find_sim(key) if not key.is_empty() else null
	var sim_valid: bool = sim != null and is_instance_valid(sim) and not sim.is_queued_for_deletion()
	var uid: String = String(sim.get_meta("character_uid", "")) if sim_valid else ""
	var record = w._character_records.get(key)
	var record_valid: bool = record != null and is_instance_valid(record)
	var record_uid_match: bool = record_valid and not uid.is_empty() and String(record.to_dict().get("uid", "")) == uid
	var duplicate_owner := false
	for other_id in w.net.players:
		if int(other_id) != peer_id and bool(w.net.players[other_id].get("own", false)) and String(w.net.players[other_id].get("sim", "")) == key:
			duplicate_owner = true
	return {"server": w.net.multiplayer.is_server(), "connected": w.net._connected,
		"pending": w.net.pending.has(peer_id), "registered": w.net.players.has(peer_id),
		"own": bool(player.get("own", false)), "assigned_match": not key.is_empty() and String(player.get("sim", "")) == key,
		"sim_exists": sim_valid, "sim_player_meta": sim_valid and bool(sim.get_meta("player_character", false)),
		"uid_present": not uid.is_empty(), "record_exists": record_valid,
		"record_uid_match": record_uid_match, "duplicate_owner": duplicate_owner,
		"acl": w.net.server_can_edit_character(peer_id, key)}

func _trace_server_acl_roster(w: Node3D) -> void:
	for peer_id in w.net.players:
		var key: String = String(w.net.players[peer_id].get("sim", ""))
		_trace("server", "server_roster_acl", {"peer": int(peer_id), "snapshot": _server_acl_snapshot(w, int(peer_id), key)})

func _transport_snapshot(w: Node3D, target_peer: int = -1) -> Dictionary:
	# Test-only callback-time state; not a low-level ENet disconnect reason.
	# Never log private character data, UIDs, tokens or network addresses.
	if not is_instance_valid(w) or w.is_queued_for_deletion():
		return {"world_valid": false}
	var net = w.net
	if not is_instance_valid(net):
		return {"world_valid": true, "net_valid": false}
	var api: MultiplayerAPI = net.multiplayer
	var transport: MultiplayerPeer = api.multiplayer_peer
	var peer_ids = api.get_peers()
	var status: int = transport.get_connection_status() if transport != null else -1
	return {"world_valid": true, "net_valid": true, "transport_status": status,
		"peer_count": peer_ids.size(), "target_still_listed": target_peer > 0 and peer_ids.has(target_peer),
		"net_connected": net._connected, "players": net.players.size(),
		"pending": net.pending.size(), "kicked_total": int(net.stats.get("kicked", 0))}

# Test-only: do not query ENet unique ID while peer is offline/connecting.
func _h3_safe_peer_id(w: Node3D) -> int:
	if not is_instance_valid(w) or w.is_queued_for_deletion():
		return -1
	var net = w.net
	if not is_instance_valid(net):
		return -1
	var api: MultiplayerAPI = net.multiplayer
	if api == null:
		return -1
	var transport: MultiplayerPeer = api.multiplayer_peer
	if transport == null or transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return -1
	return api.get_unique_id()

func _attach_trace(w: Node3D, role: String) -> void:
	_trace(role, "world_ready", {"mode": w.net.mode, "connected": w.net._connected, "local_id": _h3_safe_peer_id(w)})
	# Fixture-only ENet timeout A/B. No production configuration or test gate changes.
	# set_timeout has no corresponding getter; these are experimental values.
	if _extended_enet_timeout:
		var transport := w.net.multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if transport != null:
			if role == "server":
				w.net.multiplayer.peer_connected.connect(func(peer_id):
					var packet: ENetPacketPeer = transport.get_peer(peer_id) if transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED else null
					if packet != null:
						packet.set_timeout(32, 30000, 60000)
						_trace(role, "enet_timeout_override", {"applied": true, "side": "server", "min_ms": 30000, "max_ms": 60000})
				)
			else:
				w.net.multiplayer.connected_to_server.connect(func():
					var packet: ENetPacketPeer = transport.get_peer(1) if transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED else null
					if packet != null:
						packet.set_timeout(32, 30000, 60000)
						_trace(role, "enet_timeout_override", {"applied": true, "side": "client", "min_ms": 30000, "max_ms": 60000})
				)
	# Lifetime fix (7 Nov 2026 evening): the SceneMultiplayer emitting these signals outlives a
	# freed world (owner rejoin), so capture it weakly – a strong capture of a freed `w` printed
	# "Lambda capture at index 1 was freed". _transport_snapshot(null) reports world_valid=false.
	var wr: WeakRef = weakref(w)
	w.net.multiplayer.peer_connected.connect(func(peer_id): _trace(role, "peer_connected", {"peer": peer_id, "transport": _transport_snapshot(wr.get_ref(), peer_id)}))
	w.net.multiplayer.peer_disconnected.connect(func(peer_id):
		_trace(role, "peer_disconnected", {"peer": peer_id, "transport": _transport_snapshot(wr.get_ref(), peer_id)})
		if role == "server":
			_trace(role, "server_peer_exit_context", {"peer": peer_id, "transport": _transport_snapshot(wr.get_ref(), peer_id)})
	)
	w.net.multiplayer.connected_to_server.connect(func(): _trace(role, "connected_to_server"))
	w.net.multiplayer.connection_failed.connect(func(): _trace(role, "connection_failed", {"transport": _transport_snapshot(wr.get_ref())}))
	w.net.multiplayer.server_disconnected.connect(func():
		_trace(role, "server_disconnected", {"transport": _transport_snapshot(wr.get_ref())})
		if role == "owner":
			_trace(role, "owner_transport_closed", {"transport": _transport_snapshot(wr.get_ref())})
	)
	w.net.welcomed.connect(func(key): _trace(role, "welcomed", {"key": key}))
	w.net.disconnected.connect(func(reason): _trace(role, "net_disconnected", {"reason": reason, "transport": _transport_snapshot(w)}))
	w.net.character_edit_snapshot.connect(func(key, _data, rev): _trace(role, "private_snapshot", {"key": key, "revision": rev}))
	w.net.character_edit_snapshot_correlated.connect(func(_req, key, _data, rev): _trace(role, "correlated_private_snapshot", {"key": key, "revision": rev}))
	# H3 fixture-only timing: bracket each server peer registration and client welcome.
	# Server callbacks are serial; a child-entered event can be correlated only
	# with the latest synchronous spawn, not interpreted as CPU-only duration.
	var phase := {"peers": {}, "last_spawn_ms": -1, "last_spawn_name": "", "spawn_stages": {}, "seen": {}, "connected_ms": -1}
	if role == "server":
		w.net.roster_changed.connect(func(_roster): _trace_server_acl_roster(w))
		w.net.multiplayer.peer_connected.connect(func(peer_id):
			phase["peers"][peer_id] = int(Time.get_unix_time_from_system() * 1000.0)
		)
		w.sims_root.child_entered_tree.connect(func(node):
			var entered_ms := int(Time.get_unix_time_from_system() * 1000.0)
			var node_key := String(node.name)
			phase["last_spawn_ms"] = entered_ms
			phase["last_spawn_name"] = node_key
			if node_key.begins_with("Hrac"):
				phase["spawn_stages"][node_key] = {"entered_ms": entered_ms, "ready_ms": -1, "spawner_ms": -1}
				# Test-only: bracket the first direct SimAgent child. SimAgent._ready
				# constructs/configures its visual before add_child(visual), so this
				# separates pre-add setup from child-tree and child-ready work.
				node.child_entered_tree.connect(func(child):
					var child_enter_ms := int(Time.get_unix_time_from_system() * 1000.0)
					# Snapshot identity before ready: instance IDs are process-local.
					var child_name := String(child.name)
					var child_id: int = child.get_instance_id()
					var child_script: Script = child.get_script() as Script
					var child_script_path := child_script.resource_path if child_script != null else ""
					_trace(role, "player_direct_child_entered", {"node": node_key, "child_name": child_name, "child_class": child.get_class(), "child_script": child_script_path, "child_instance_id": child_id, "parent_to_child_ms": child_enter_ms - entered_ms})
					child.ready.connect(func():
						var ready_ms := int(Time.get_unix_time_from_system() * 1000.0)
						_trace(role, "player_direct_child_ready", {"node": node_key, "child_name": child_name, "child_class": child.get_class(), "child_script": child_script_path, "child_instance_id": child_id, "child_enter_to_ready_ms": ready_ms - child_enter_ms, "parent_to_child_ready_ms": ready_ms - entered_ms})
					, CONNECT_ONE_SHOT)
				)
				# Node.ready is emitted after child_entered_tree. Observe rather than alter the spawn.
				node.ready.connect(func():
					var ready_ms := int(Time.get_unix_time_from_system() * 1000.0)
					var stage: Dictionary = phase["spawn_stages"].get(node_key, {})
					stage["ready_ms"] = ready_ms
					phase["spawn_stages"][node_key] = stage
					_trace(role, "player_spawn_node_ready", {"node": node_key, "entered_to_ready_ms": ready_ms - entered_ms})
				, CONNECT_ONE_SHOT)
		)
		w.net.multiplayer.peer_disconnected.connect(func(peer_id):
			# Post-disconnect snapshot only; not an ENet disconnect reason.
			var first_seen_ms := int(phase["peers"].get(peer_id, -1))
			_trace(role, "server_peer_timing", {"peer": int(peer_id), "elapsed_since_connect_ms": int(Time.get_unix_time_from_system() * 1000.0) - first_seen_ms if first_seen_ms > 0 else -1, "pending": w.net.pending.has(peer_id), "kick_scheduled": w.net._kick_at.has(peer_id), "kicked_total": int(w.net.stats.get("kicked", 0)), "transport": _transport_snapshot(w, peer_id)})
			phase["seen"].erase(peer_id)
		)
		w.net.spawner.spawned.connect(func(node):
			var node_key := String(node.name)
			if phase["spawn_stages"].has(node_key):
				var stage: Dictionary = phase["spawn_stages"][node_key]
				stage["spawner_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
				phase["spawn_stages"][node_key] = stage
		)
		w.net.roster_changed.connect(func(_roster):
			var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
			for peer_id in w.net.players:
				if int(peer_id) <= 1 or phase["seen"].has(peer_id):
					continue
				phase["seen"][peer_id] = true
				var peer_ms := int(phase["peers"].get(peer_id, -1))
				var spawn_ms := int(phase["last_spawn_ms"])
				var owns_avatar := bool(w.net.players[peer_id].get("own", false))
				var matched_spawn := String(phase["last_spawn_name"]).begins_with("Hrac%d_" % int(peer_id))
				var stage: Dictionary = phase["spawn_stages"].get(String(phase["last_spawn_name"]), {}) if matched_spawn else {}
				var ready_ms := int(stage.get("ready_ms", -1))
				var spawner_ms := int(stage.get("spawner_ms", -1))
				_trace(role, "server_registration_phase", {"peer": peer_id, "own": owns_avatar,
					"spawn_enter_to_ready_ms": ready_ms - spawn_ms if matched_spawn and ready_ms >= spawn_ms else -1,
					"ready_to_roster_ms": now_ms - ready_ms if ready_ms > 0 else -1,
					"spawn_enter_to_spawner_ms": spawner_ms - spawn_ms if matched_spawn and spawner_ms >= spawn_ms else -1,
					"spawner_to_roster_ms": now_ms - spawner_ms if spawner_ms > 0 else -1,
					"peer_to_roster_ms": now_ms - peer_ms if peer_ms > 0 else -1,
					"peer_to_spawn_ms": spawn_ms - peer_ms if owns_avatar and matched_spawn and peer_ms > 0 and spawn_ms >= peer_ms else -1,
					"spawn_to_roster_ms": now_ms - spawn_ms if owns_avatar and matched_spawn and spawn_ms > 0 else -1,
					"spawn_match": matched_spawn,
					"players": w.net.players.size(), "pending": w.net.pending.size()})
		)
	else:
		w.net.multiplayer.connected_to_server.connect(func():
			phase["connected_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
		)
		w.net.welcomed.connect(func(_key):
			var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
			var connected_ms := int(phase["connected_ms"])
			_trace(role, "client_welcome_phase", {"connect_to_welcome_ms": now_ms - connected_ms if connected_ms > 0 else -1,
				"assigned": not w.net.my_sim.is_empty(), "puppet_visible": w.find_sim(w.net.my_sim) != null})
		)

		# Test-only client cold-spawn brackets; no private character payloads.
		w.sims_root.child_entered_tree.connect(func(node):
			var parent_start_us := Time.get_ticks_usec()
			var parent_id: int = node.get_instance_id()
			var parent_script: Script = node.get_script() as Script
			_trace(role, "client_sim_entered", {"instance": parent_id, "class": node.get_class(),
				"script": parent_script.resource_path if parent_script != null else ""})
			if node.is_node_ready():
				_trace(role, "client_sim_already_ready", {"instance": parent_id})
			else:
				node.child_entered_tree.connect(func(child):
					var child_start_us := Time.get_ticks_usec()
					var child_id: int = child.get_instance_id()
					var child_script: Script = child.get_script() as Script
					_trace(role, "client_sim_child_entered", {"parent_instance": parent_id,
						"instance": child_id, "class": child.get_class(),
						"script": child_script.resource_path if child_script != null else "",
						"parent_to_child_ms": float(child_start_us - parent_start_us) / 1000.0})
					if child.is_node_ready():
						_trace(role, "client_sim_child_already_ready", {"instance": child_id})
					else:
						child.ready.connect(func():
							_trace(role, "client_sim_child_ready", {"parent_instance": parent_id,
								"instance": child_id,
								"child_enter_to_ready_ms": float(Time.get_ticks_usec() - child_start_us) / 1000.0,
								"parent_enter_to_child_ready_ms": float(Time.get_ticks_usec() - parent_start_us) / 1000.0})
							if child_script != null and child_script.resource_path == "res://scripts/sim/sim_visual.gd":
								_trace(role, "client_simvisual_ready", {"instance": child_id, "parent_instance": parent_id,
									"enter_to_ready_ms": float(Time.get_ticks_usec() - child_start_us) / 1000.0,
									"parent_enter_to_ready_ms": float(Time.get_ticks_usec() - parent_start_us) / 1000.0,
									"owner_stage": _h3_owner_stage if role == "owner" else ""})
						, CONNECT_ONE_SHOT)
				)
				node.ready.connect(func():
					_trace(role, "client_sim_ready", {"instance": parent_id,
						"enter_to_ready_ms": float(Time.get_ticks_usec() - parent_start_us) / 1000.0})
				, CONNECT_ONE_SHOT)
		)
	# H3 read-only lifecycle probes: distinguish server registration from client puppet instantiation.
	# Only aggregate counts and timestamps; never include character payloads.
	w.net.roster_changed.connect(func(_roster): _trace(role, "roster_changed", {"players": w.net.players.size(), "pending": w.net.pending.size(), "roster": w.net.roster.size(), "spawns": w.net.stats.get("characters_spawned", 0)}))
	w.net.spawner.spawned.connect(func(_node): _trace(role, "spawner_spawned", {"sims": w.get_sims().size(), "assigned": not w.net.my_sim.is_empty(), "peers": w.net.multiplayer.get_peers().size()}))
	w.sims_root.child_entered_tree.connect(func(_node): _trace(role, "sim_child_entered", {"children": w.sims_root.get_child_count(), "assigned": not w.net.my_sim.is_empty()}))

func _world(mode: String, character_code: String = "") -> Node3D:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "World"
	w.net_config = {"mode": mode, "port": _port, "address": "127.0.0.1",
		"name": "Owner" if mode == "owner" else "Observer",
		"character": character_code, "visuals": false, "hud": false,
		"camera": false, "audio": false, "autosave": false,
		"autoload": false, "network_character_editor": true,
		"eight_member_household": false}
	if _game_assets_test:
		w.net_config["async_character_assets"] = true
	if mode == "owner" or mode == "observer":
		w.net_config["mode"] = "client"
	add_child(w)
	return w

func _character_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 960241
	var d: Dictionary = Randomizer.generate(rng)
	d["identity"]["first_name"] = "Fixture"
	d["identity"]["last_name"] = "ThreeProcess"
	d["identity"]["attracted_to"] = ["zeny"]
	d["story"]["backstory"] = "fictional_private_h3_marker"
	d["mind"]["predispositions"]["anxiety"] = 0.5
	var validated: Dictionary = Validator.validate(d)
	return Codec.encode_code(validated["data"]) if validated.get("ok", false) else ""

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4 and args[0] == "worker":
		_token = args[1]
		_port = int(args[2])
		_prewarm_clients = args.has("prewarm")
		_extended_enet_timeout = args.has("enet-extended")
		_hair_async_test = args.has("hair-async")
		_hair_prewarm_test = args.has("hair-prewarm")
		_wardrobe_async_test = args.has("wardrobe-async")
		_game_assets_test = args.has("game-assets")
		_visual_light_test = args.has("visual-light")
		_visual_skip_hair_test = args.has("visual-skip-hair")
		_visual_skip_outfit_test = args.has("visual-skip-outfit")
		_visual_defer_outfit_test = args.has("visual-defer-outfit")
		await _worker(args[3])
	else:
		_prewarm_clients = args.has("prewarm")
		_extended_enet_timeout = args.has("enet-extended")
		_hair_async_test = args.has("hair-async")
		_hair_prewarm_test = args.has("hair-prewarm")
		_wardrobe_async_test = args.has("wardrobe-async")
		_game_assets_test = args.has("game-assets")
		_visual_light_test = args.has("visual-light")
		_visual_skip_hair_test = args.has("visual-skip-hair")
		_visual_skip_outfit_test = args.has("visual-skip-outfit")
		_visual_defer_outfit_test = args.has("visual-defer-outfit")
		await _parent()

func _h3_install_build_probe(role: String) -> bool:
	# TEST ONLY. Patch the already-preloaded SimVisual script resource IN MEMORY
	# in each isolated child OS process; the production .gd file stays untouched.
	const SOURCE_PATH := "res://scripts/sim/sim_visual.gd"
	const SOURCE_SHA := "d9d88354d3730d1cd415bab2b544f9906b9bfe3308f37ed4299cf010efd15fbe"
	if FileAccess.get_sha256(SOURCE_PATH) != SOURCE_SHA:
		_trace(role, "simvisual_probe_error", {"reason": "source_sha_changed"})
		return false
	var sc: GDScript = SimVisual
	var original: String = sc.source_code
	var start: int = original.find("func _build() -> void:\n")
	var end: int = original.find("func _build_primitives() -> void:", start)
	if start < 0 or end <= start:
		_trace(role, "simvisual_probe_error", {"reason": "function_bounds"})
		return false
	var body: String = original.substr(start, end - start)
	var begin_anchor := "\t_built = true\n"
	var end_anchor := "\t_place_overhead()\n"
	if body.count(begin_anchor) != 1 or body.count(end_anchor) != 1:
		_trace(role, "simvisual_probe_error", {"reason": "ambiguous_anchors"})
		return false
	var trace_path := "user://h3_3proc_" + _token + "_trace_" + role + ".jsonl"
	var begin_code := begin_anchor + "\tvar __h3_build_start_us: int = Time.get_ticks_usec()\n" + "\tvar __h3_build_start_utc_ms: int = int(Time.get_unix_time_from_system() * 1000.0)\n"
	begin_code += "\tvar __h3_model_elapsed_ms: float = -1.0\n"
	var end_code := end_anchor + "\tvar __h3_build_elapsed_ms: float = float(Time.get_ticks_usec() - __h3_build_start_us) / 1000.0\n"
	end_code += "\tvar __h3_probe_path: String = " + JSON.stringify(trace_path) + "\n"
	end_code += "\tvar __h3_probe_mode: int = FileAccess.READ_WRITE if FileAccess.file_exists(__h3_probe_path) else FileAccess.WRITE_READ\n"
	end_code += "\tvar __h3_probe_file: FileAccess = FileAccess.open(__h3_probe_path, __h3_probe_mode)\n"
	end_code += "\tif __h3_probe_file != null:\n"
	end_code += "\t\t__h3_probe_file.seek_end()\n"
	end_code += "\t\t__h3_probe_file.store_line(JSON.stringify({\"ms\": Time.get_ticks_msec(), \"utc_ms\": int(Time.get_unix_time_from_system() * 1000.0), \"pid\": OS.get_process_id(), \"phase\": \"simvisual_build_direct\", \"details\": {\"start_utc_ms\": __h3_build_start_utc_ms, \"elapsed_ms\": snappedf(__h3_build_elapsed_ms, 0.001)}}))\n"
	end_code += "\t\t__h3_probe_file.close()\n"
	# Keep timings in memory until the synchronous build has finished.
	# The nested variant duration is included in model_ms, not additive.
	var model_anchor := "\t\t_build_model()\n"
	var model_start: int = original.find("func _build_model() -> void:\n", end)
	var model_end: int = original.find("func _build_action_props() -> void:\n", model_start)
	if body.count(model_anchor) != 1 or model_start <= end or model_end <= model_start:
		_trace(role, "simvisual_probe_error", {"reason": "model_bounds_or_anchor"})
		return false
	var variant_body: String = original.substr(model_start, model_end - model_start)
	var variant_anchor := "\t_apply_model_variant()\n"
	if variant_body.count(variant_anchor) != 1:
		_trace(role, "simvisual_probe_error", {"reason": "variant_anchor"})
		return false
	var model_timed := "\t\tvar __h3_model_start_us: int = Time.get_ticks_usec()\n" + model_anchor + "\t\t__h3_model_elapsed_ms = float(Time.get_ticks_usec() - __h3_model_start_us) / 1000.0\n"
	var variant_timed := "\tvar __h3_variant_start_us: int = Time.get_ticks_usec()\n" + variant_anchor + "\t__h3_variant_elapsed_ms = float(Time.get_ticks_usec() - __h3_variant_start_us) / 1000.0\n"
	variant_body = variant_body.replace(variant_anchor, variant_timed)
	var h3_subpart_start: int = original.find("func _apply_model_variant() -> void:\n")
	var h3_subpart_end: int = original.find("func _apply_outfit(lp: Dictionary) -> void:\n", h3_subpart_start)
	if h3_subpart_start < 0 or h3_subpart_end <= h3_subpart_start:
		_trace(role, "simvisual_probe_error", {"reason": "variant_function_bounds"})
		return false
	var h3_original_body: String = original.substr(h3_subpart_start, h3_subpart_end - h3_subpart_start)
	var h3_subpart_body: String = h3_original_body
	var h3_hair_anchor: String = "\t\t\tvar r := HairRig.request_mesh(part, styles[part], self)\n"
	var h3_outfit_anchor: String = "\t_apply_outfit(lp)\n"
	var h3_body_anchor: String = "\tapply_body_shape(lp)\n"
	var h3_face_anchor: String = "\tapply_face_shape(lp)\n"
	var h3_refresh_anchor: String = "\t_refresh_torso_visibility(lp)\n"
	var h3_vars_anchor: String = "\tvar hair_v := \"hair_short\"\n"
	for h3_anchor in [h3_hair_anchor, h3_outfit_anchor, h3_body_anchor, h3_face_anchor, h3_refresh_anchor, h3_vars_anchor]:
		if h3_subpart_body.count(h3_anchor) != 1:
			_trace(role, "simvisual_probe_error", {"reason": "subpart_anchor", "anchor": h3_anchor.strip_edges()})
			return false
	h3_subpart_body = h3_subpart_body.replace(h3_vars_anchor, h3_vars_anchor + "\tvar __h3_hair_us: int = 0\n\tvar __h3_hair_calls: Array[Dictionary] = []\n\tvar __h3_outfit_us: int = 0\n\tvar __h3_body_us: int = 0\n\tvar __h3_face_us: int = 0\n")
	h3_subpart_body = h3_subpart_body.replace(h3_hair_anchor, "\t\t\tvar __h3_key: String = part + \":\" + styles[part]\n\t\t\tHairRig._mutex.lock()\n\t\t\tvar __h3_cache_before: bool = HairRig._meshes.has(__h3_key)\n\t\t\tvar __h3_pending_before: bool = HairRig._waiters.has(__h3_key)\n\t\t\tHairRig._mutex.unlock()\n\t\t\tvar __h3_hair_start_us: int = Time.get_ticks_usec()\n\t\t\tvar r := HairRig.request_mesh(part, styles[part], self)\n\t\t\tvar __h3_hair_duration_us: int = Time.get_ticks_usec() - __h3_hair_start_us\n\t\t\t__h3_hair_us += __h3_hair_duration_us\n\t\t\t__h3_hair_calls.append({\"part\": part, \"style\": styles[part], \"cached_before_probe\": __h3_cache_before, \"pending_before_probe\": __h3_pending_before, \"ready\": bool(r[\"ready\"]), \"elapsed_ms\": snappedf(float(__h3_hair_duration_us) / 1000.0, 0.001)})\n")
	h3_subpart_body = h3_subpart_body.replace(h3_outfit_anchor, "\tvar __h3_outfit_start_us: int = Time.get_ticks_usec()\n\t_apply_outfit(lp)\n\t__h3_outfit_us = Time.get_ticks_usec() - __h3_outfit_start_us\n")
	h3_subpart_body = h3_subpart_body.replace(h3_body_anchor, "\tvar __h3_body_start_us: int = Time.get_ticks_usec()\n\tapply_body_shape(lp)\n\t__h3_body_us = Time.get_ticks_usec() - __h3_body_start_us\n")
	h3_subpart_body = h3_subpart_body.replace(h3_face_anchor, "\tvar __h3_face_start_us: int = Time.get_ticks_usec()\n\tapply_face_shape(lp)\n\t__h3_face_us = Time.get_ticks_usec() - __h3_face_start_us\n")
	h3_subpart_body = h3_subpart_body.replace(h3_refresh_anchor, "\t_refresh_torso_visibility(lp)\n\t__h3_variant_parts = {\"hair_calls\": __h3_hair_calls, \"hair_ms\": snappedf(float(__h3_hair_us)/1000.0, 0.001), \"outfit_ms\": snappedf(float(__h3_outfit_us)/1000.0, 0.001), \"body_ms\": snappedf(float(__h3_body_us)/1000.0, 0.001), \"face_ms\": snappedf(float(__h3_face_us)/1000.0, 0.001)}\n")
	end_code += "\tvar __h3_subphase_file: FileAccess = FileAccess.open(__h3_probe_path, FileAccess.READ_WRITE)\n"
	end_code += "\tif __h3_subphase_file != null:\n"
	end_code += "\t\t__h3_subphase_file.seek_end()\n"
	end_code += "\t\t__h3_subphase_file.store_line(JSON.stringify({\"ms\": Time.get_ticks_msec(), \"utc_ms\": int(Time.get_unix_time_from_system() * 1000.0), \"pid\": OS.get_process_id(), \"phase\": \"simvisual_subphases\", \"details\": {\"total_ms\": snappedf(__h3_build_elapsed_ms, 0.001), \"model_ms\": snappedf(__h3_model_elapsed_ms, 0.001), \"variant_ms\": snappedf(__h3_variant_elapsed_ms, 0.001)}}))\n"
	end_code += "\t\t__h3_subphase_file.close()\n"
	end_code += "\tvar __h3_parts_file: FileAccess = FileAccess.open(__h3_probe_path, FileAccess.READ_WRITE)\n\tif __h3_parts_file != null:\n\t\t__h3_parts_file.seek_end()\n\t\t__h3_parts_file.store_line(JSON.stringify({\"utc_ms\": int(Time.get_unix_time_from_system()*1000.0), \"pid\": OS.get_process_id(), \"phase\": \"simvisual_variant_parts\", \"details\": __h3_variant_parts}))\n\t\t__h3_parts_file.close()\n"
	# Isolate costly authored-model subphases without replacing the model.
	# The in-memory test-only replacement is exclusive and checked against exact anchors.
	# The two opt-in skips can be combined for the authored-model additive-cost A/B.
	# Production SimVisual, original H3 gates and deadlines remain unchanged.
	if _visual_skip_hair_test:
		var __h3_hair_call := "\t\t\tvar r := HairRig.request_mesh(part, styles[part], self)\n"
		if h3_subpart_body.count(__h3_hair_call) != 1:
			_trace(role, "simvisual_probe_error", {"reason": "hair_skip_anchor"})
			return false
		h3_subpart_body = h3_subpart_body.replace(__h3_hair_call, "\t\t\tvar r: Dictionary = {\"ready\": true, \"mesh\": null} # H3 fixture-only skip scalp/brows/beard requests\n")
	if _visual_skip_outfit_test:
		var __h3_outfit_call := "\t_apply_outfit(lp)\n"
		if h3_subpart_body.count(__h3_outfit_call) != 1:
			_trace(role, "simvisual_probe_error", {"reason": "outfit_skip_anchor"})
			return false
		h3_subpart_body = h3_subpart_body.replace(__h3_outfit_call, "\tpass # H3 fixture-only skip garment mesh generation\n")
	# Test-only opt-in: wait for first owner private RPC before REAL garment build.
	if _visual_defer_outfit_test:
		if _visual_skip_outfit_test or _visual_light_test:
			_trace(role, "simvisual_probe_error", {"reason": "deferred_outfit_incompatible"})
			return false
		if h3_subpart_body.count("\t_apply_outfit(lp)\n") != 1:
			_trace(role, "simvisual_probe_error", {"reason": "deferred_outfit_anchor"})
			return false
		var marker_arg: String = JSON.stringify(_path("owner_initial"))
		var trace_arg: String = JSON.stringify("user://h3_3proc_" + _token + "_trace_" + role + ".jsonl")
		h3_subpart_body = h3_subpart_body.replace("\t_apply_outfit(lp)\n", "\tcall_deferred(\"__h3_deferred_outfit\", lp.duplicate(true), " + marker_arg + ", " + trace_arg + ")\n")
		h3_subpart_body = h3_subpart_body.replace("\t__h3_outfit_us = Time.get_ticks_usec() - __h3_outfit_start_us\n", "\t__h3_outfit_us = -1000 # deferred; actual duration in trace\n")
	# Opt-in H3 A/B: use existing production primitive fallback, without loading
	# authored model geometry. Only in-memory script resource; no production edits.
	if _visual_light_test:
		var __h3_asset_anchor := "\t_model = AssetLibrary.instantiate(model_choice)\n"
		if body.count(__h3_asset_anchor) != 1:
			_trace(role, "simvisual_probe_error", {"reason": "visual_light_anchor"})
			return false
		body = body.replace(__h3_asset_anchor, "\t_model = null # H3 fixture-only primitive fallback\n")
	body = body.replace(begin_anchor, begin_code).replace(end_anchor, end_code).replace(model_anchor, model_timed)
	sc.source_code = original.substr(0, start) + "var __h3_variant_elapsed_ms: float = -1.0\nvar __h3_variant_parts: Dictionary = {}\n" + body + original.substr(end, model_start - end) + variant_body + original.substr(model_end)
	sc.source_code = sc.source_code.replace(h3_original_body, h3_subpart_body)
	if _visual_defer_outfit_test:
		sc.source_code = sc.source_code.replace("var __h3_variant_parts: Dictionary = {}\n", "var __h3_variant_parts: Dictionary = {}\nvar __h3_outfit_epoch: int = 0\n")
		sc.source_code += "\n# Test-only delayed REAL garments; owner marker is scoped by unique three-process token.\nfunc __h3_deferred_outfit(lp: Dictionary, marker_path: String, trace_path: String) -> void:\n\t__h3_outfit_epoch += 1\n\tvar epoch: int = __h3_outfit_epoch\n\tvar wait_started: int = Time.get_ticks_msec()\n\tvar marker_ok: bool = false\n\twhile is_inside_tree() and epoch == __h3_outfit_epoch and Time.get_ticks_msec() - wait_started < 14000:\n\t\tif FileAccess.file_exists(marker_path):\n\t\t\tvar marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))\n\t\t\tif marker is Dictionary and bool(marker.get(\"ok\", false)):\n\t\t\t\tmarker_ok = true\n\t\t\t\tbreak\n\t\tawait get_tree().create_timer(0.15).timeout\n\tif not is_inside_tree() or epoch != __h3_outfit_epoch:\n\t\treturn\n\tvar waited_ms: int = Time.get_ticks_msec() - wait_started\n\tvar build_started: int = Time.get_ticks_usec()\n\t_apply_outfit(lp)\n\tvar meshes: int = 0\n\tvar vertices: int = 0\n\tfor item in _c5_nodes:\n\t\tif item is MeshInstance3D and is_instance_valid(item) and item.mesh != null:\n\t\t\tmeshes += 1\n\t\t\tfor surface in range(item.mesh.get_surface_count()):\n\t\t\t\tvertices += item.mesh.surface_get_array_len(surface)\n\tvar result: Dictionary = {\"phase\": \"h3_deferred_garment_done\", \"utc_ms\": int(Time.get_unix_time_from_system()*1000.0), \"details\": {\"after_owner_private_rpc\": marker_ok, \"wait_ms\": waited_ms, \"build_ms\": snappedf(float(Time.get_ticks_usec()-build_started)/1000.0, 0.001), \"mesh_nodes\": meshes, \"vertices\": vertices}}\n\tvar file: FileAccess = FileAccess.open(trace_path, FileAccess.READ_WRITE if FileAccess.file_exists(trace_path) else FileAccess.WRITE_READ)\n\tif file != null:\n\t\tfile.seek_end()\n\t\tfile.store_line(JSON.stringify(result))\n\t\tfile.close()\n"
	var err: Error = sc.reload()
	if err != OK:
		_trace(role, "simvisual_probe_error", {"reason": "reload", "error": err})
		sc.source_code = original
		sc.reload()
		return false
	_trace(role, "simvisual_probe_installed", {"source_sha_verified": true, "reload_ok": true, "visual_light": _visual_light_test, "skip_hair": _visual_skip_hair_test, "skip_outfit": _visual_skip_outfit_test, "defer_outfit": _visual_defer_outfit_test})
	return true

func _worker(role: String) -> void:
	# A/B fixture flag is process-local; production default remains untouched.
	HairRig.async_build = _hair_async_test
	_trace(role, "hair_async_mode", {"enabled": _hair_async_test})
	ClothingWardrobe.async_load = _wardrobe_async_test
	var wardrobe_queued: int = ClothingWardrobe.prewarm_async() if _wardrobe_async_test and role != "server" else 0
	_trace(role, "wardrobe_async_mode", {"enabled": _wardrobe_async_test, "prewarm_kinds": wardrobe_queued})
	get_node("/root/GameSettings").persist = false
	get_node("/root/GameSettings").reset()
	if not _h3_install_build_probe(role):
		_put(role + "_done", {"ok": false, "reason": "visual_probe_install_failed"})
		get_tree().quit(2)
		return
	var async_probe := _h3_async_lifecycle_begin(role) if _hair_async_test else {}
	# Test-only frame gap sampler, installed before owner creation.
	# Stage boundaries plus synchronous _world duration disambiguate the blocked interval.
	var owner_gap_callback := Callable()
	if role == "owner":
		var gap_state := {"last_us": Time.get_ticks_usec(), "last_stage": "worker_boot", "count": 0}
		owner_gap_callback = func():
			var now: int = Time.get_ticks_usec()
			var gap_us: int = now - int(gap_state["last_us"])
			if gap_us >= 250000 and int(gap_state["count"]) < 8:
				gap_state["count"] = int(gap_state["count"]) + 1
				_trace("owner", "owner_worker_frame_gap", {
					"gap_ms": snappedf(float(gap_us) / 1000.0, 0.1),
					"from_stage": String(gap_state["last_stage"]),
					"to_stage": _h3_owner_stage,
					"stage_since_ms": snappedf(float(now - _h3_owner_stage_since_us) / 1000.0, 0.1),
					"sample": int(gap_state["count"])})
			gap_state["last_us"] = now
			gap_state["last_stage"] = _h3_owner_stage
		get_tree().process_frame.connect(owner_gap_callback)
	if _prewarm_clients and role in ["owner", "observer"]:
		# Fixture-only A/B: warm client-side resource caches before ENet connection.
		var warm_start_us := Time.get_ticks_usec()
		var warm := Node3D.new()
		warm.set_script(SimVisual)
		add_child(warm)
		await get_tree().process_frame
		warm.queue_free()
		await get_tree().process_frame
		_trace(role, "client_previsual_warmup", {"elapsed_ms": float(Time.get_ticks_usec() - warm_start_us) / 1000.0,
			"freed": not is_instance_valid(warm)})
	if _hair_prewarm_test and role in ["owner", "observer"]:
		# TEST ONLY: warm the four fixture scalp styles before ENet startup.
		# Per-process cache; no production defaults or acceptance gates changed.
		var warm_start_us := Time.get_ticks_usec()
		var styles := []
		for style in ["kratke", "dlouhe_vlnite", "copanky", "afro"]:
			var style_start_us := Time.get_ticks_usec()
			var mesh := HairRig.mesh_for("scalp", style)
			var reuse := HairRig.mesh_for("scalp", style)
			styles.append({"style": style, "elapsed_ms": snappedf(float(Time.get_ticks_usec() - style_start_us) / 1000.0, 0.001), "mesh_ready": mesh != null, "cache_reuse": reuse == mesh})
		var summary := {"elapsed_ms": snappedf(float(Time.get_ticks_usec() - warm_start_us) / 1000.0, 0.001), "styles": styles, "role": role}
		_trace(role, "hair_prewarm_done", summary)
		print("H3_HAIR_PREWARM ", JSON.stringify(summary))
	_put(role + "_boot", {"pid": OS.get_process_id(), "role": role})
	if role == "server":
		await _server()
	elif role == "owner":
		await _owner()
	elif role == "observer":
		await _observer()
	else:
		_put(role + "_done", {"ok": false, "reason": "bad role"})
	if owner_gap_callback.is_valid() and get_tree().process_frame.is_connected(owner_gap_callback):
		get_tree().process_frame.disconnect(owner_gap_callback)
	if not async_probe.is_empty():
		_h3_async_lifecycle_end(role, async_probe)
	get_tree().quit(0)

func _server() -> void:
	var server_started := Time.get_ticks_usec()
	_trace("server", "world_construct_begin")
	var w := _world("server")
	_trace("server", "world_constructed", {"elapsed_ms": int((Time.get_ticks_usec() - server_started) / 1000), "sims": w.get_sims().size(), "records": w._character_records.size()})
	_attach_trace(w, "server")
	_put("server_ready", {"pid": OS.get_process_id(), "port": _port,
		"mode": w.net.mode, "baseline": w.get_sims().size()})
	# A fixture-only phase barrier: the server verifies the actual peer ownership
	# BEFORE the first client private-read RPC. No production RPC is modified.
	var gate_seen: bool = await _probe_marker("server", "owner_read_ready", 40.0, w)
	var gate_request: Dictionary = _read_marker("owner_read_ready")
	var gate_key: String = String(gate_request.get("key", ""))
	var gate_peer: int = int(gate_request.get("peer_id", -1))
	var gate_player: Dictionary = w.net.players.get(gate_peer, {})
	var gate_acl: bool = gate_seen and w.net.server_can_edit_character(gate_peer, gate_key)
	var gate_record: bool = w._character_records.has(gate_key)
	_trace("server", "initial_read_gate", {"seen": gate_seen, "peer": gate_peer, "key": gate_key, "acl": gate_acl, "record": gate_record, "player_present": not gate_player.is_empty(), "snapshot": _server_acl_snapshot(w, gate_peer, gate_key)})
	_put("server_read_gate", {"ok": gate_seen and gate_acl and gate_record, "peer_id": gate_peer, "key": gate_key, "acl": gate_acl, "record": gate_record})
	var server_frame_probe := _start_frame_probe(func(): return w.net._edit_limiters.has(gate_peer))
	var first_seen: bool = await wait_until(func(): return not _read_marker("owner_read_sent").is_empty(), 15.0)
	var sent_marker: Dictionary = _read_marker("owner_read_sent")
	# server_read_character_edit creates a per-peer limiter when the real RPC
	# reaches the authorized handler. Observe it without consuming a token.
	var rpc_seen: bool = first_seen and bool(sent_marker.get("sent", false)) and await wait_until(func(): return w.net._edit_limiters.has(gate_peer), 8.0)
	_trace("server", "server_rpc_frame_probe", _stop_frame_probe(server_frame_probe))
	var can_read: bool = w.net.server_can_edit_character(gate_peer, gate_key)
	var first_ok: bool = gate_acl and rpc_seen and can_read
	_trace("server", "initial_read_rpc_observation", {"marker_seen": first_seen, "client_sent": sent_marker.get("sent", false), "rpc_limiter_seen": rpc_seen, "acl_after": can_read, "key": gate_key, "snapshot": _server_acl_snapshot(w, gate_peer, gate_key)})
	_put("server_initial_diag", {"ok": first_ok, "first_key": gate_key, "peer_id": gate_peer, "client_sent": sent_marker.get("sent", false), "rpc_limiter_seen": rpc_seen, "can_read": can_read, "record_exists": w._character_records.has(gate_key)})
	var both := await wait_until(func(): return not _read_marker("observer_forgery").is_empty(), 62.0)
	var verdict := false
	if both:
		var rejoin_key: String = String(_read_marker("owner_rejoined").get("key", ""))
		var actor = w.find_sim(rejoin_key)
		var record = w._character_records.get(rejoin_key)
		var observer_peer := -1
		for peer_id in w.net.players:
			if String(w.net.players[peer_id].get("name", "")) == "Observer":
				observer_peer = int(peer_id)
		verdict = actor != null and record != null and observer_peer > 1 and not w.net.server_can_edit_character(observer_peer, rejoin_key) and record.story.get("backstory", "") == "fictional_private_h3_marker" and record.identity.get("attracted_to", []) == ["zeny"]
	_put("server_done", {"pid": OS.get_process_id(), "ok": both and verdict,
		"verified": verdict, "spawned": w.net.stats["characters_spawned"]})
	await wait_seconds(0.25)
	_trace("server", "intentional_shutdown_pre", {"phase": "server_final"})
	w.net.shutdown()
	_trace("server", "intentional_shutdown_post", {"phase": "server_final"})

func _owner() -> void:
	var owner_started := Time.get_ticks_usec()
	_h3_owner_phase("creator")
	_trace("owner", "creator_begin")
	var code := _character_code()
	_trace("owner", "creator_ready", {"elapsed_ms": int((Time.get_ticks_usec() - owner_started) / 1000), "valid": not code.is_empty()})
	if code.is_empty():
		_put("owner_done", {"ok": false, "reason": "creator validation"})
		return
	_h3_owner_phase("world_construct")
	var world_started := Time.get_ticks_usec()
	var w := _world("owner", code)
	_h3_owner_phase("world_construct_done")
	_trace("owner", "world_constructed", {"elapsed_ms": int((Time.get_ticks_usec() - world_started) / 1000), "total_ms": int((Time.get_ticks_usec() - owner_started) / 1000), "connected": w.net._connected})
	_attach_trace(w, "owner")
	_h3_owner_phase("owner_ready_wait")
	var connected := await _probe_owner_ready(w, 12.0)
	_h3_owner_phase("owner_ready_done")
	_trace("owner", "initial_owner_ready", {"ok": connected, "total_ms": int((Time.get_ticks_usec() - owner_started) / 1000)})
	var key: String = String(w.net.my_sim)
	var replies: Array = []
	w.net.character_edit_snapshot.connect(func(k, d, r): replies.append({"key":k, "data":d, "rev":r}))
	var peer_id: int = _h3_safe_peer_id(w)
	_put("owner_read_ready", {"ok": connected and peer_id > 1, "key": key, "peer_id": peer_id})
	_h3_owner_phase("server_gate_wait")
	var gate_started_us := Time.get_ticks_usec()
	_trace("owner", "owner_gate_wait_start", {"ready": connected, "net_connected": w.net._connected})
	var gate_seen: bool = connected and await _probe_marker("owner", "server_read_gate", 28.0, w)
	var gate_ok: bool = gate_seen and bool(_read_marker("server_read_gate").get("ok", false))
	_trace("owner", "initial_read_gate", {"seen": gate_seen, "ok": gate_ok, "peer": peer_id, "key": key})
	_trace("owner", "owner_gate_wait_end", {"elapsed_ms": int((Time.get_ticks_usec() - gate_started_us) / 1000), "seen": gate_seen, "ok": gate_ok})
	_h3_owner_phase("private_rpc")
	var rpc_started_us := Time.get_ticks_usec()
	_trace("owner", "owner_rpc_request_start", {"gate_ok": gate_ok, "net_connected": w.net._connected})
	var read_sent: bool = gate_ok and w.net.request_character_edit_snapshot()
	_trace("owner", "owner_rpc_request_result", {"elapsed_ms": int((Time.get_ticks_usec() - rpc_started_us) / 1000), "sent": read_sent})
	_put("owner_read_sent", {"ok": read_sent, "key": key, "peer_id": peer_id, "sent": read_sent})
	var reply_wait_started_us := Time.get_ticks_usec()
	var owner_frame_probe := _start_frame_probe(func(): return replies.size() == 1)
	var read_ok: bool = read_sent and await wait_until(func(): return replies.size() == 1, 6.0)
	_trace("owner", "owner_rpc_frame_probe", _stop_frame_probe(owner_frame_probe))
	_trace("owner", "owner_reply_wait_result", {"elapsed_ms": int((Time.get_ticks_usec() - reply_wait_started_us) / 1000), "read_ok": read_ok, "reply_count": replies.size()})
	var private_ok: bool = read_ok and replies[0]["data"].get("story", {}).get("backstory", "") == "fictional_private_h3_marker" and replies[0]["data"].get("identity", {}).get("attracted_to", []) == ["zeny"]
	_trace("owner", "initial_read_result", {"connected": connected, "sent": read_sent, "reply_count": replies.size(), "private_ok": private_ok, "peer_status": w.net.multiplayer.multiplayer_peer.get_connection_status()})
	_put("owner_initial", {"pid": OS.get_process_id(), "ok": connected and private_ok,
		"key": key, "private_ok": private_ok, "connected": connected, "read_sent": read_sent, "gate_ok": gate_ok, "read_ok": read_ok, "reply_count": replies.size(), "mode": w.net.mode, "connected_flag": w.net._connected})
	_trace("owner", "owner_initial_marker_written", {"ok": connected and private_ok, "gate_ok": gate_ok, "read_ok": read_ok})
	var observer_seen := await wait_until(func(): return not _read_marker("observer_initial").is_empty(), 12.0)
	_trace("owner", "intentional_shutdown_pre", {"phase": "owner_before_rejoin"})
	w.net.shutdown()
	_trace("owner", "intentional_shutdown_post", {"phase": "owner_before_rejoin"})
	w.queue_free()
	await get_tree().process_frame
	var gone := await wait_until(func(): return not _read_marker("observer_gone").is_empty(), 12.0)
	var rejoin = _world("owner", code)
	_attach_trace(rejoin, "owner")
	var rejoined := await wait_until(func(): return rejoin.net.my_sim != "" and rejoin.find_sim(rejoin.net.my_sim) != null, 12.0)
	var new_key: String = String(rejoin.net.my_sim)
	var second_reads: Array = []
	rejoin.net.character_edit_snapshot.connect(func(k, d, r): second_reads.append({"key":k, "data":d, "rev":r}))
	var second_sent: bool = rejoined and rejoin.net.request_character_edit_snapshot()
	var second_ok: bool = second_sent and await wait_until(func(): return second_reads.size() == 1, 6.0)
	var recovered: bool = second_ok and second_reads[0]["data"].get("story", {}).get("backstory", "") == "fictional_private_h3_marker"
	_trace("owner", "rejoin_read_result", {"rejoined": rejoined, "sent": second_sent, "reply_count": second_reads.size(), "private_ok": recovered, "key_changed": new_key != key})
	_put("owner_rejoined", {"pid": OS.get_process_id(), "ok": rejoined and recovered and new_key != key,
		"key": new_key, "first_key": key, "private_ok": recovered})
	var observer_checked := await wait_until(func(): return not _read_marker("observer_forgery").is_empty(), 12.0)
	var server_checked := await wait_until(func(): return not _read_marker("server_done").is_empty(), 8.0)
	_put("owner_done", {"pid": OS.get_process_id(), "ok": connected and private_ok and observer_seen and gone and rejoined and recovered and new_key != key and observer_checked and server_checked})
	_trace("owner", "intentional_shutdown_pre", {"phase": "owner_final"})
	rejoin.net.shutdown()
	_trace("owner", "intentional_shutdown_post", {"phase": "owner_final"})

func _public_ok(w: Node3D, key: String) -> bool:
	var puppet = w.find_sim(key)
	if puppet == null:
		return false
	var wire := JSON.stringify(puppet.look)
	for secret in ["attracted_to", "backstory", "fictional_private_h3_marker", "predispositions", "traumas", "uid"]:
		if wire.contains(secret):
			return false
	return not puppet.has_private and puppet.sim_name == "Fixture ThreeProcess"

func _observer() -> void:
	var w := _world("observer")
	_attach_trace(w, "observer")
	var observer_start_ms := Time.get_ticks_msec()
	var welcomed := await wait_until(func(): return w.net.my_sim != "", 12.0)
	_trace("observer", "observer_marker_wait_start", {"welcomed": welcomed})
	var initial := await wait_until(func(): return not _read_marker("owner_initial").is_empty(), 12.0)
	_trace("observer", "observer_marker_wait_end", {"found": initial})
	var first_key: String = String(_read_marker("owner_initial").get("key", ""))
	var spawned := initial and await wait_until(func(): return w.find_sim(first_key) != null, 12.0)
	var first_ok := spawned and _public_ok(w, first_key)
	_trace("observer", "observer_first_phase", {"elapsed_ms": Time.get_ticks_msec() - observer_start_ms, "welcomed": welcomed, "initial_marker": initial, "spawned": spawned, "public_ok": first_ok, "sims": w.get_sims().size(), "roster": w.net.roster.size(), "transport": _transport_snapshot(w)})
	_put("observer_initial", {"pid": OS.get_process_id(), "ok": welcomed and first_ok, "public_ok": first_ok, "welcomed": welcomed, "initial": initial, "spawned": spawned, "key": first_key, "sim_name": String(w.find_sim(first_key).sim_name) if spawned else "", "wire": JSON.stringify(w.find_sim(first_key).look).substr(0, 700) if spawned else ""})
	var gone := spawned and await wait_until(func(): return w.find_sim(first_key) == null, 12.0)
	_trace("observer", "observer_gone_phase", {"elapsed_ms": Time.get_ticks_msec() - observer_start_ms, "had_first_spawn": spawned, "gone": gone, "first_still_visible": w.find_sim(first_key) != null, "sims": w.get_sims().size(), "roster": w.net.roster.size(), "transport": _transport_snapshot(w)})
	_put("observer_gone", {"ok": gone, "spawned": spawned, "still_exists": w.find_sim(first_key) != null})
	var rejoined := await wait_until(func(): return not _read_marker("owner_rejoined").is_empty(), 12.0)
	var new_key: String = String(_read_marker("owner_rejoined").get("key", ""))
	var second_spawned := rejoined and await wait_until(func(): return w.find_sim(new_key) != null, 12.0)
	var second_ok: bool = second_spawned and _public_ok(w, new_key)
	_trace("observer", "observer_second_phase", {"elapsed_ms": Time.get_ticks_msec() - observer_start_ms, "rejoined_marker": rejoined, "second_spawned": second_spawned, "public_ok": second_ok, "sims": w.get_sims().size(), "roster": w.net.roster.size(), "transport": _transport_snapshot(w)})
	var stolen: Array = []
	w.net.character_edit_snapshot.connect(func(k, d, r): stolen.append({"key": k, "data": d, "rev": r}))
	var real_sim: String = String(w.net.my_sim)
	w.net.my_sim = new_key
	var sent: bool = second_spawned and w.net.request_character_edit_snapshot()
	var marker := "h3_3proc_fence_" + "a".repeat(30)
	var echoes := {"n":0}
	w.net.chat_received.connect(func(from_name, message, system):
		if from_name == "Observer" and message == marker and not system:
			echoes["n"] += 1)
	w.net.send_chat(marker)
	var fenced := await wait_until(func(): return echoes["n"] == 1, 6.0)
	w.net.my_sim = real_sim
	var denied: bool = sent and fenced and stolen.is_empty() and _public_ok(w, new_key)
	_trace("observer", "forgery_result", {"sent": sent, "fenced": fenced, "snapshot_count": stolen.size(), "second_spawned": second_spawned, "peer_status": w.net.multiplayer.multiplayer_peer.get_connection_status()})
	_put("observer_forgery", {"pid": OS.get_process_id(), "ok": second_ok and denied,
		"public_ok": second_ok, "forgery_sent": sent, "fenced": fenced, "denied": denied, "rejoined": rejoined, "second_spawned": second_spawned, "echo_count": echoes["n"], "mode": w.net.mode, "connected": w.net._connected, "new_key": new_key})
	var server_checked := await wait_until(func(): return not _read_marker("server_done").is_empty(), 10.0)
	_put("observer_done", {"pid": OS.get_process_id(), "ok": welcomed and first_ok and gone and second_ok and denied and server_checked})
	_trace("observer", "intentional_shutdown_pre", {"phase": "observer_final"})
	w.net.shutdown()
	_trace("observer", "intentional_shutdown_post", {"phase": "observer_final"})

func _spawn(role: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/diagnostics/h3_three_process.FAILING.tscn", "--", "worker", _token, str(_port), role])
	if _prewarm_clients and role in ["owner", "observer"]:
		args.append("prewarm")
	if _extended_enet_timeout:
		args.append("enet-extended")
	if _hair_async_test:
		args.append("hair-async")
	if _hair_prewarm_test:
		args.append("hair-prewarm")
	if _wardrobe_async_test:
		args.append("wardrobe-async")
	if _game_assets_test:
		args.append("game-assets")
	if _visual_light_test:
		args.append("visual-light")
	if _visual_skip_hair_test:
		args.append("visual-skip-hair")
	if _visual_skip_outfit_test:
		args.append("visual-skip-outfit")
	if _visual_defer_outfit_test:
		args.append("visual-defer-outfit")
	return OS.create_process(OS.get_executable_path(), args)

func _parent() -> void:
	section("H3 production creator + owner-private + spectator + reconnect in three child OS processes")
	print("H3_AB_MODE ", "enet-extended" if _extended_enet_timeout else ("prewarm" if _prewarm_clients else "cold"))
	print("H3_HAIR_ASYNC ", _hair_async_test)
	print("H3_HAIR_PREWARM_ENABLED ", _hair_prewarm_test)
	print("H3_WARDROBE_ASYNC ", _wardrobe_async_test)
	print("H3_GAME_ASSETS ", _game_assets_test)
	print("H3_VISUAL_LIGHT ", _visual_light_test)
	print("H3_VISUAL_SKIP_HAIR ", _visual_skip_hair_test)
	print("H3_VISUAL_SKIP_OUTFIT ", _visual_skip_outfit_test)
	print("H3_VISUAL_DEFER_OUTFIT ", _visual_defer_outfit_test)
	_token = str(Time.get_ticks_usec()) + "_" + str(OS.get_process_id())
	_port = 33000 + randi() % 18000
	var pids := []
	var server_pid := _spawn("server")
	pids.append(server_pid)
	check(server_pid > 0, "independent server process launched")
	var ready := server_pid > 0 and await wait_until(func(): return not _read_marker("server_ready").is_empty(), 22.0)
	check(ready and _read_marker("server_ready").get("baseline", -1) == 3, "production server initialized household")
	# Diagnostic-only start-order experiment: separate client process launch load.
	# Preserve every acceptance assertion; a changed result is not causal proof.
	var owner_pid := _spawn("owner") if ready else -1
	pids.append(owner_pid)
	print("H3_STAGGER_OWNER utc_ms=", int(Time.get_unix_time_from_system() * 1000.0), " pid=", owner_pid)
	if owner_pid > 0:
		await wait_seconds(2.0)
	var observer_pid := _spawn("observer") if ready else -1
	pids.append(observer_pid)
	print("H3_STAGGER_OBSERVER utc_ms=", int(Time.get_unix_time_from_system() * 1000.0), " pid=", observer_pid)
	check(observer_pid > 0 and owner_pid > 0 and server_pid != observer_pid and server_pid != owner_pid and observer_pid != owner_pid, "three distinct Godot child process IDs")
	var done := owner_pid > 0 and observer_pid > 0 and await wait_until(func(): return not _read_marker("owner_done").is_empty() and not _read_marker("observer_done").is_empty() and not _read_marker("server_done").is_empty(), 77.0)
	check(done, "all three production-network workers completed")
	for key in ["owner_read_ready", "server_read_gate", "owner_read_sent", "owner_initial", "server_initial_diag", "observer_initial", "observer_gone", "owner_rejoined", "observer_forgery", "server_done", "owner_done", "observer_done"]:
		var data := _read_marker(key)
		check(done and data.get("ok", false) == true, key + " verified", JSON.stringify(data))
	check(done and _read_marker("server_done").get("spawned", 0) >= 2, "server spawned two canonical creator-code incarnations")
	var shutdown_report: Array = []
	for role in ["server", "owner", "observer"]:
		var trace_path: String = "user://h3_3proc_" + _token + "_trace_" + role + ".jsonl"
		if FileAccess.file_exists(trace_path):
			var trace_lines := FileAccess.get_file_as_string(trace_path).split("\n", false)
			print("H3_PROCESS_TRACE ", role, " total=", trace_lines.size())
			# Preserve the first handshake/spawn events AND the last teardown
			# events. A tail-only trace hid the original disconnect cause.
			for i in range(mini(12, maxi(0, trace_lines.size() - 22))):
				print("H3_TRACE_EARLY ", role, " ", String(trace_lines[i]).substr(0, 350))
			for line in trace_lines.slice(maxi(0, trace_lines.size() - 22)):
				print("H3_TRACE ", role, " ", String(line).substr(0, 350))
			# Surface the exact child instance and its ready duration even when
			# the event falls between the early and tail windows.
			if role == "server":
				var acl_lines := 0
				for line in trace_lines:
					if (String(line).contains("\"phase\":\"server_roster_acl\"") or String(line).contains("\"phase\":\"initial_read_gate\"") or String(line).contains("\"phase\":\"initial_read_rpc_observation\"")) and acl_lines < 16:
						print("H3_TRACE_ACL ", role, " ", String(line).substr(0, 950))
						acl_lines += 1
				for line in trace_lines:
					if String(line).contains("\"phase\":\"player_direct_child_"):
						print("H3_TRACE_CHILD ", role, " ", String(line).substr(0, 550))
			if role != "server":
				var client_lines := 0
				for line in trace_lines:
					if String(line).contains("\"phase\":\"client_sim_") and client_lines < 28:
						print("H3_TRACE_CLIENT ",role," ",String(line).substr(0,460))
						client_lines += 1
			# Surface only non-sensitive event classes across process clocks for H3 timing correlation.
			var correlation_count := 0
			for trace_line in trace_lines:
				var event: Variant = JSON.parse_string(String(trace_line))
				if event is Dictionary and String(event.get("phase", "")) in ["client_simvisual_ready", "owner_worker_frame_gap", "owner_stage", "owner_ready_start", "owner_transport_state", "owner_ready_result", "initial_owner_ready", "initial_read_result", "owner_transport_closed", "server_disconnected", "net_disconnected", "peer_connected", "peer_disconnected", "server_peer_exit_context", "server_peer_timing", "server_lifecycle_change", "owner_lifecycle_change", "observer_first_phase", "observer_gone_phase", "observer_second_phase", "owner_gate_wait_start", "owner_gate_wait_end", "owner_rpc_request_start", "owner_rpc_request_result", "owner_reply_wait_result", "owner_rpc_frame_probe", "server_rpc_frame_probe", "owner_initial_marker_written", "observer_marker_wait_start", "observer_marker_wait_end"] and correlation_count < 40:
					var detail: Dictionary = event.get("details", {})
					print("H3_CORRELATE ", JSON.stringify({"role": role, "utc_ms": event.get("utc_ms", 0), "phase": event.get("phase", ""), "details": detail}))
					correlation_count += 1
			# Print EVERY measured subphase event, without early/tail or count caps.
			for trace_line in trace_lines:
				if String(trace_line).contains("\"phase\":\"simvisual_subphases\"") or String(trace_line).contains("\"phase\":\"simvisual_variant_parts\""):
					print("H3_SUBPHASE ", role, " ", String(trace_line))
			for trace_line in trace_lines:
				if String(trace_line).contains("h3_deferred_garment_done"):
					print("H3_DEFERRED_GARMENT ", role, " ", String(trace_line))
			for trace_line in trace_lines:
				if String(trace_line).contains("\"phase\":\"async_lifecycle_summary\""):
					print("H3_ASYNC_LIFECYCLE ", role, " ", String(trace_line).substr(0, 12000))
			for trace_line in trace_lines:
				var event: Variant = JSON.parse_string(String(trace_line))
				if event is Dictionary and String(event.get("phase", "")).begins_with("intentional_shutdown_"):
					shutdown_report.append({"role": role, "utc_ms": event.get("utc_ms", -1), "event": event.get("phase", ""), "phase": (event.get("details", {}) as Dictionary).get("phase", "")})
		DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_path))
	print("H3_SHUTDOWN_SUMMARY ", JSON.stringify(shutdown_report))
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	for key in ["server_boot", "owner_boot", "observer_boot", "server_ready", "owner_read_ready", "server_read_gate", "owner_read_sent", "server_initial_diag", "owner_initial", "observer_initial", "observer_gone", "owner_rejoined", "observer_forgery", "server_done", "owner_done", "observer_done"]:
		var p := ProjectSettings.globalize_path(_path(key))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	finish("test_h3_three_process_character")