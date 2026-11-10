extends "res://scripts/net/net_session.gd"
## Fixture-only RPC receipt and authorization probe. No private payload or key logging.
signal h3_private_read_event(info: Dictionary)

func server_read_character_edit(sender_peer_id: int, sim_node: Variant) -> Dictionary:
	h3_private_read_event.emit({"stage":"entered","utc_ms":int(Time.get_unix_time_from_system()*1000.0),"peer":sender_peer_id,"registered":players.has(sender_peer_id),"connected":_connected})
	var result: Dictionary = super.server_read_character_edit(sender_peer_id, sim_node)
	h3_private_read_event.emit({"stage":"result","utc_ms":int(Time.get_unix_time_from_system()*1000.0),"peer":sender_peer_id,"ok":bool(result.get("ok",false)),"reason":String(result.get("reason","ok" if result.get("ok",false) else "unknown"))})
	return result
