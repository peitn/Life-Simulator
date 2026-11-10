extends "res://tests/diagnostics/h3_three_process.FAILING.gd"
## Derived three-process fixture, all inherited 17 assertions/deadlines unchanged.
const H3MainHash = "5370db7978c29f4aed3af46dbc7c395584612c27256232e4a81244acff9c8c04"
const H3NetHash = "6c0a13eae03f2da6cddb16b6ef3240bb3b8577c4e3c21aa23a06c8635c84ce97"
const H3InstrumentedNet = preload("res://tests/diagnostics/h3_instrumented_net_session.gd")

func _world(mode: String, character_code: String = "") -> Node3D:
	if mode != "server":
		return super._world(mode, character_code)
	if FileAccess.get_sha256("res://main.gd") != H3MainHash or FileAccess.get_sha256("res://scripts/net/net_session.gd") != H3NetHash:
		push_error("H3 RPC probe base source changed")
		get_tree().quit(1)
		return Node3D.new()
	var src := FileAccess.get_file_as_string("res://main.gd")
	var anchor := 'const NetSession := preload("res://scripts/net/net_session.gd")'
	if src.count(anchor) != 1:
		push_error("H3 RPC probe Main anchor mismatch")
		get_tree().quit(1)
		return Node3D.new()
	src = src.replace(anchor, 'const NetSession := preload("res://tests/diagnostics/h3_instrumented_net_session.gd")')
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		push_error("H3 RPC probe Main compile failure")
		get_tree().quit(1)
		return Node3D.new()
	var w := Node3D.new()
	w.set_script(script)
	w.name = "World"
	w.net_config = {"mode":"server","port":_port,"address":"127.0.0.1","name":"Owner","character":"","visuals":false,"hud":false,"camera":false,"audio":false,"autosave":false,"autoload":false,"network_character_editor":true,"eight_member_household":false}
	add_child(w)
	if not is_instance_valid(w.net) or not w.net.has_signal("h3_private_read_event"):
		push_error("H3 RPC probe not attached")
		get_tree().quit(1)
	else:
		w.net.h3_private_read_event.connect(func(info: Dictionary): _trace("server","server_private_rpc_event",info))
		_trace("server","h3_rpc_probe_attached",{"enabled":true})
	return w

func _spawn(role: String) -> int:
	var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"res://tests/diagnostics/h3_three_process_rpc_probe.tscn","--","worker",_token,str(_port),role])
	if _prewarm_clients and role in ["owner","observer"]:
		args.append("prewarm")
	if _extended_enet_timeout:
		args.append("enet-extended")
	return OS.create_process(OS.get_executable_path(),args)

var _h3_rpc_event_count := 0

func _trace(role: String, phase: String, details: Dictionary = {}) -> void:
	super._trace(role, phase, details)
	# Parent deletes the inherited markers and traces. Keep a small, private-data-free
	# summary so a later rejoin RPC cannot masquerade as the first owner's read.
	if role == "owner" and phase == "owner_ready_result":
		_put("rpc_probe_owner", {"ready": bool(details.get("ok", false)),
			"connected": bool(details.get("connected", false)),
			"transport_status": int(details.get("transport_status", -1))})
	elif role == "owner" and phase == "initial_read_gate":
		var owner: Dictionary = _read_marker("rpc_probe_owner")
		owner["peer"] = int(details.get("peer", -1))
		owner["gate_ok"] = bool(details.get("ok", false))
		owner["sent"] = false
		_put("rpc_probe_owner", owner)
	elif role == "owner" and phase == "owner_rpc_request_result":
		var owner: Dictionary = _read_marker("rpc_probe_owner")
		owner["sent"] = bool(details.get("sent", false))
		owner["request_utc_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
		_put("rpc_probe_owner", owner)
	elif role == "owner" and phase == "owner_reply_wait_result":
		var owner: Dictionary = _read_marker("rpc_probe_owner")
		owner["reply_count"] = int(details.get("reply_count", 0))
		owner["reply_wait_ok"] = bool(details.get("read_ok", false))
		_put("rpc_probe_owner", owner)
	elif role == "server" and phase == "initial_read_gate":
		_put("rpc_probe_server_gate", {"seen": bool(details.get("seen", false)),
			"acl": bool(details.get("acl", false)), "record": bool(details.get("record", false)),
			"player_present": bool(details.get("player_present", false))})
	elif role == "server" and phase == "server_private_rpc_event":
		_h3_rpc_event_count += 1
		var previous: Dictionary = _read_marker("rpc_probe_event")
		var events: Array = previous.get("events", [])
		if events.size() < 8:
			events.append(details.duplicate(true))
		_put("rpc_probe_event", {"count": _h3_rpc_event_count, "events": events})

func _parent() -> void:
	await super._parent()
	var marker: Dictionary = _read_marker("rpc_probe_event")
	var owner: Dictionary = _read_marker("rpc_probe_owner")
	var events: Array = marker.get("events", [])
	var server_gate: Dictionary = _read_marker("rpc_probe_server_gate")
	var initial_peer := int(owner.get("peer", -1))
	var first_peer_entered := false
	for event in events:
		if event is Dictionary and String(event.get("stage", "")) == "entered" and int(event.get("peer", -2)) == initial_peer:
			first_peer_entered = true
	# No handler event is expected when the owner never reached the send phase.
	# Classify the earliest observed missing prerequisite; do not label it packet loss.
	var ready := bool(owner.get("ready", false))
	var gate_ok := bool(owner.get("gate_ok", false))
	var sent := bool(owner.get("sent", false))
	var reply_ok := bool(owner.get("reply_wait_ok", false))
	var phase := "reply_observed"
	if not ready:
		phase = "owner_not_ready"
	elif not gate_ok:
		phase = "server_gate_not_confirmed"
	elif not sent:
		phase = "client_request_not_sent"
	elif not first_peer_entered:
		phase = "server_handler_not_observed"
	elif not reply_ok:
		phase = "owner_reply_not_observed"
	var summary := {"diagnostic_phase": phase, "owner_ready": ready,
		"owner_connected_at_ready": bool(owner.get("connected", false)),
		"owner_transport_status_at_ready": int(owner.get("transport_status", -1)),
		"server_gate": server_gate,
		"initial_owner_gate_ok": gate_ok,
		"initial_owner_sent": sent,
		"initial_owner_peer": initial_peer,
		"initial_peer_handler_entered": sent and first_peer_entered,
		"owner_reply_count": int(owner.get("reply_count", 0)),
		"owner_reply_wait_ok": reply_ok,
		"server_event_count": int(marker.get("count", 0)), "server_events": events}
	print("H3_RPC_AUDIT ", JSON.stringify(summary))