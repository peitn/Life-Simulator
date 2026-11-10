extends SceneTree
var checks := 0
var failed := 0
var connected_peers := 0
var disconnected_peers := 0
var event_trace: Array[String] = []
func check(value: bool, label: String) -> void:
 checks += 1
 if not value: failed += 1
 print(("PASS " if value else "FAIL ") + label)
func _initialize() -> void:
 call_deferred("probe")
func probe() -> void:
 var server := ENetMultiplayerPeer.new()
 var client := ENetMultiplayerPeer.new()
 server.peer_connected.connect(func(_id):
  connected_peers += 1
  event_trace.append("server_connected:%d" % Time.get_ticks_msec()))
 server.peer_disconnected.connect(func(_id):
  disconnected_peers += 1
  event_trace.append("server_disconnected:%d:status=%d:peer_entry_present=%d" % [Time.get_ticks_msec(), server.get_connection_status(), int(server.get_peer(_id) != null)]))
 var port := 33000 + OS.get_process_id() % 20000
 var err := server.create_server(port, 2)
 check(err == OK, "server create")
 if err != OK:
  quit(1)
  return
 err = client.create_client("127.0.0.1", port)
 check(err == OK, "client create")
 if err != OK:
  server.close()
  quit(1)
  return
 var deadline := Time.get_ticks_msec() + 2500
 while Time.get_ticks_msec() < deadline and client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
  server.poll()
  client.poll()
  await process_frame
 check(client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "connected")
 deadline = Time.get_ticks_msec() + 1000
 while Time.get_ticks_msec() < deadline and connected_peers == 0:
  server.poll()
  client.poll()
  await process_frame
 check(connected_peers == 1, "server peer listed")
 var payload := "enet-lifecycle-reliable-probe".to_utf8_buffer()
 client.set_target_peer(1)
 check(client.put_packet(payload) == OK, "client reliable packet queued")
 var received := false
 deadline = Time.get_ticks_msec() + 2500
 while Time.get_ticks_msec() < deadline and not received:
  server.poll()
  client.poll()
  while server.get_available_packet_count() > 0:
   var sender := server.get_packet_peer()
   var packet := server.get_packet()
   received = packet == payload and sender > 1
  if not received:
   await process_frame
 check(received, "server receives reliable payload")
 event_trace.append("client_close_begin:%d" % Time.get_ticks_msec())
 client.close()
 event_trace.append("client_close_end:%d" % Time.get_ticks_msec())
 check(client.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "client closed")
 deadline = Time.get_ticks_msec() + 2500
 while Time.get_ticks_msec() < deadline and disconnected_peers == 0:
  server.poll()
  await process_frame
 check(disconnected_peers == 1, "server peer removed")
 check(event_trace.size() == 4, "four ordered lifecycle events")
 if event_trace.size() == 4:
  check(event_trace[0].begins_with("server_connected:") and event_trace[1].begins_with("client_close_begin:") and event_trace[2].begins_with("client_close_end:") and event_trace[3].begins_with("server_disconnected:"), "disconnect callback after close")
 print("ENET_EVENT_TRACE ", JSON.stringify(event_trace))
 server.close()
 check(server.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "server closed")
 print("ENET_LIFECYCLE %d/%d" % [checks-failed, checks])
 quit(0 if failed == 0 else 1)