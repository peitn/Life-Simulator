extends Node
## NetSession – multiplayer s autoritativním serverem (Godot 4 high-level multiplayer, ENet).
##
## Režimy:
##   OFFLINE   – jeden hráč, simulace lokálně, hráč ovládá všechny postavy
##   HOST      – listen server: simuluje a zároveň hraje (peer 1)
##   DEDICATED – dedikovaný server bez lokálního hráče (headless)
##   CLIENT    – jen zobrazuje: postavy jsou SimPuppet, stav chodí přes MultiplayerSynchronizer
##
## Bezpečnost: klient posílá jen ŽÁDOSTI (chat, příkaz pro svou postavu, hlas o rychlosti).
## Server ověří typy, délky, vlastnictví postavy, existenci akce a objektu a rate limit.
## RPC směrem ke klientům jsou "authority" – klient je nemůže zavolat na ostatních.
## Klient, který se do HELLO_TIMEOUT nepředstaví, je odpojen.
##
## Uzel musí mít na všech peerech stejnou cestu (world/Net) – RPC i spawner jsou adresované cestou.

const Protocol := preload("res://scripts/net/net_protocol.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const AdultIntimacy := preload("res://scripts/sim/adult_intimacy_action.gd")
const CharacterCodec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const CharacterValidator := preload("res://scripts/character/character_validator.gd")

signal chat_received(from: String, text: String, system: bool)
signal roster_changed(roster: Dictionary)
signal notice(text: String)
signal welcomed(my_sim: String)
signal disconnected(reason: String)

enum Mode { OFFLINE, HOST, DEDICATED, CLIENT }

const MODE_NAMES := ["Offline", "Hostitel", "Dedikovaný server", "Klient"]
const CLOCK_SYNC_INTERVAL := 0.5
## Klient: rozdíl času (herní minuty), nad kterým hodiny skočí na serverový čas.
const CLOCK_SNAP := 1.5
## Veřejný stav – jen to, co ostatní postavy/hráči mohou pozorovat.
const SYNC_PROPS := ["net_pos", "net_rot", "net_label", "net_emotion", "net_mood", "net_posture",
	"net_action", "net_speech"]
## Soukromý stav (potřeby, pocity, vztahy, vzpomínky) chodí jen vlastníkovi postavy přes RPC.
const PRIVATE_INTERVAL := 0.25
const MAX_CHAT_LOG := 100

var mode: int = Mode.OFFLINE
## Svět (main.gd) – spawn_sim_node(), register_sim(), unregister_sim(), find_sim(), get_sims(), get_smart_objects(), sims_root
var world: Node = null
var clock: Node = null
var spawner: MultiplayerSpawner

## Server: peer_id -> {"name", "sim", "vote", "chat", "cmd", "vote_rl"}
var players := {}
## Server: peer_id -> čas připojení (s), dokud nepošle hello
var pending := {}
## Všichni: peer_id -> {"name": String, "sim": String}
var roster := {}
var my_sim := ""
var my_name := ""
## Klient: sdílecí kód vlastní postavy (LSC1…), který se pošle v hello (prázdný = převzít postavu domácnosti).
var my_character_code := String()
## Server/host: kanonická data vlastní postavy hostitele ({} = převzít postavu domácnosti).
var my_character := {}
var my_vote := 1
var chat_log: Array = []  # [[from, text, system]]
var stats := {"rejected": 0, "commands": 0, "chat_sent": 0, "chat_blocked": 0, "kicked": 0,
	"clock_syncs": 0, "votes": 0, "characters_rejected": 0, "characters_spawned": 0}
## Server: poslední důvod odmítnutí postavy (testy, log).
var last_character_error := String()

## Délka nouzové pauzy (s) – konfigurovatelná kvůli testům.
var emergency_pause_seconds: float = Protocol.EMERGENCY_PAUSE
## Do kdy (reálný čas v s) platí nouzová pauza; 0 = neplatí.
var emergency_until := 0.0

var _clock_timer := 0.0
var _private_timer := 0.0
## peer_id -> hash posledního odeslaného soukromého stavu
var _private_sent := {}
## peer_id -> čas (s), kdy ho odpojit: odmítnutý klient má nejdřív dostat důvod (notice),
## okamžité disconnect_peer by frontu spolehlivých paketů zahodilo.
var _kick_at := {}
const KICK_DELAY := 0.5
var _connected := false


func setup(p_world: Node, p_clock: Node) -> void:
	world = p_world
	clock = p_clock
	spawner = MultiplayerSpawner.new()
	spawner.name = "SimSpawner"
	add_child(spawner)
	spawner.spawn_path = spawner.get_path_to(world.sims_root)
	spawner.spawn_limit = 32
	spawner.spawn_function = _spawn_function
	spawner.spawned.connect(_on_spawned)
	spawner.despawned.connect(_on_despawned)


func is_networked() -> bool:
	return mode != Mode.OFFLINE


func is_authority() -> bool:
	return mode != Mode.CLIENT


func mode_name() -> String:
	return MODE_NAMES[mode]


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------- start

func start_offline(player_name := "") -> void:
	mode = Mode.OFFLINE
	my_name = Protocol.sanitize_name(player_name)


## Spustí server. dedicated = bez lokálního hráče.
func host(port: int, player_name := "", dedicated := false, character := {}) -> int:
	if not ClassDB.class_exists("ENetMultiplayerPeer"):
		push_warning("Multiplayer (ENet) na této platformě není (webová verze) – hra běží offline.")
		return ERR_UNAVAILABLE
	var peer = ClassDB.instantiate("ENetMultiplayerPeer")
	var err: int = peer.create_server(port, Protocol.MAX_CLIENTS)
	if err != OK:
		return err
	# Klienti spolu nesmí mluvit napřímo přes server (relay) – vše jde přes validaci serveru.
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED if dedicated else Mode.HOST
	_connected = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	my_character = character
	if not dedicated:
		_register_player(1, player_name, character)
	else:
		_update_speed()
	return OK


func join(address: String, port: int, player_name := "", character_code := "") -> int:
	my_character_code = character_code
	if not ClassDB.class_exists("ENetMultiplayerPeer"):
		push_warning("Multiplayer (ENet) na této platformě není (webová verze) – hra běží offline.")
		return ERR_UNAVAILABLE
	var peer = ClassDB.instantiate("ENetMultiplayerPeer")
	var err: int = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	my_name = Protocol.sanitize_name(player_name)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func shutdown() -> void:
	_edit_limiters.clear()
	_public_resync_limiters.clear()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_connected = false
	_public_look_revisions.clear()
	_pending_public_looks.clear()
	_public_resync_requested.clear()
	cancel_character_edit_snapshot()


# ---------------------------------------------------------------- spawn postav

## Server/offline: vytvoří postavu. Na serveru přes MultiplayerSpawner (replikuje se
## i později připojeným klientům), offline přímo.
func spawn_sim(data: Dictionary) -> Node:
	var node: Node
	if mode == Mode.OFFLINE:
		node = world.spawn_sim_node(data)
		world.sims_root.add_child(node, true)
	elif is_authority():
		# A fresh opaque incarnation is bound to this specific spawn, never to its node name.
		var spawn_data: Dictionary = data.duplicate(true)
		spawn_data["net_incarnation"] = Crypto.new().generate_random_bytes(16).hex_encode()
		node = spawner.spawn(spawn_data)
	else:
		push_error("spawn_sim volán na klientu")
		return null
	if node != null:
		world.register_sim(node)
	return node


func _spawn_function(data: Variant) -> Node:
	# Na klientu přichází data ze sítě – ověřit typ, ať zlomyslný server neshodí klienta.
	if typeof(data) != TYPE_DICTIONARY:
		return Node3D.new()
	var node: Node = world.spawn_sim_node(data)
	# MultiplayerSpawner delivers the same server-generated token to every peer.
	# This is public lifecycle metadata, NOT the private character UID.
	var incarnation: Variant = data.get("net_incarnation", "")
	if _valid_incarnation(incarnation):
		node.set_meta("net_incarnation", incarnation)
	var sync := make_synchronizer()
	# Stav (a tím i spawn) vidí jen představení hráči – ne anonymní spojení před hello.
	sync.add_visibility_filter(_is_visible_to)
	node.add_child(sync)
	return node


func _is_visible_to(peer_id: int) -> bool:
	return players.has(peer_id)


func is_player(peer_id: int) -> bool:
	return players.has(peer_id)


## Po změně seznamu hráčů přepočítá, komu se replikují postavy (spawn + stav).
func _refresh_visibility() -> void:
	if not is_authority() or mode == Mode.OFFLINE:
		return
	for s in world.get_sims():
		var sync := s.get_node_or_null("Sync") as MultiplayerSynchronizer
		if sync != null:
			sync.update_visibility(0)


static func make_synchronizer() -> MultiplayerSynchronizer:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for p in SYNC_PROPS:
		var path := NodePath(".:" + p)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = cfg
	sync.replication_interval = 0.1
	sync.delta_interval = 0.1
	return sync


func _on_spawned(node: Node) -> void:
	world.register_sim(node)
	# A public look RPC may arrive before MultiplayerSpawner creates this puppet.
	if mode == Mode.CLIENT:
		_apply_pending_public_look(String(node.name))


func _on_despawned(node: Node) -> void:
	world.unregister_sim(node)
	_public_look_revisions.erase(String(node.name))
	_pending_public_looks.erase(String(node.name))
	_public_resync_requested.erase(String(node.name))


# ---------------------------------------------------------------- lokální hráč → server

func send_chat(text: String) -> void:
	match mode:
		Mode.CLIENT:
			if _connected:
				_c2s_chat.rpc_id(1, text)
		Mode.HOST:
			_handle_chat(1, text)
		_:
			var clean := Protocol.sanitize_chat(text)
			if clean != "":
				_add_chat(my_name, clean, false)


## target: "" (bez cíle), int (index objektu) nebo String (jméno uzlu jiné postavy).
func request_command(sim_node: String, action_id: String, target: Variant = "") -> void:
	match mode:
		Mode.CLIENT:
			if _connected:
				_c2s_command.rpc_id(1, sim_node, action_id, target)
		_:
			var err := handle_command(1, sim_node, action_id, target)
			if err != "":
				notice.emit(err)


## Nouzová pauza – zastaví čas všem na emergency_pause_seconds (s cooldownem pro hráče).
func request_emergency_pause() -> void:
	match mode:
		Mode.CLIENT:
			if _connected:
				_c2s_emergency.rpc_id(1)
		Mode.HOST:
			_handle_emergency(1)
		Mode.OFFLINE:
			clock.set_speed(0)


func request_speed(index: int) -> void:
	my_vote = clampi(index, 0, 4)
	match mode:
		Mode.CLIENT:
			if _connected:
				_c2s_speed_vote.rpc_id(1, my_vote)
		Mode.HOST:
			_handle_vote(1, my_vote)
		Mode.OFFLINE:
			clock.set_speed(my_vote)


## Postava, kterou lokální hráč smí ovládat ("" = žádná; offline = všechny).
func can_control(sim_node: String) -> bool:
	if mode == Mode.OFFLINE:
		return true
	return sim_node != "" and sim_node == my_sim


# ---------------------------------------------------------------- RPC: klient → server

@rpc("any_peer", "call_remote", "reliable")
func _c2s_hello(player_name: Variant, version: Variant, character_code: Variant) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) or not pending.has(id):
		stats["rejected"] += 1
		return
	if typeof(version) != TYPE_INT or int(version) != Protocol.VERSION:
		stats["rejected"] += 1
		_s2c_notice.rpc_id(id, "Nekompatibilní verze hry (server %d)." % Protocol.VERSION)
		_kick_later(id)
		return
	# Vlastní postava: server NIKDY nevěří datům klienta – limity, CRC, JSON, migrace, striktní validace.
	var character := {}
	if typeof(character_code) != TYPE_STRING:
		_reject_character(id, "kód postavy není text")
		return
	if String(character_code) != "":
		var r := validate_character_code(character_code)
		if not bool(r["ok"]):
			var errs: PackedStringArray = r["errors"]
			_reject_character(id, errs[0] if not errs.is_empty() else "neplatná data")
			return
		character = r["data"]
		# uid od klienta není identita ani autentizace (review ChatGPT 48) – server přidělí vlastní 128bit ID.
		character["uid"] = CharacterData.new_uid()
	pending.erase(id)
	_register_player(id, player_name, character)


## Striktní validace kódu postavy od klienta podle nastavení obsahu SERVERU.
func validate_character_code(code: Variant) -> Dictionary:
	var gs := get_node_or_null("/root/GameSettings")
	var mh: String = gs.mental_health_mode() if gs != null else "full"
	return CharacterCodec.decode_code(code, {"mode": "strict", "mental_health": mh})


func _reject_character(id: int, why: String) -> void:
	stats["rejected"] += 1
	stats["characters_rejected"] += 1
	last_character_error = why
	_s2c_notice.rpc_id(id, "Server odmítl postavu: %s" % why)
	_kick_later(id)


## Odpojí klienta po KICK_DELAY (aby dostal důvod). Hned ale přestane být „pending“, takže
## žádné další hello ani jiný požadavek už neprojde.
func _kick_later(id: int) -> void:
	pending.erase(id)
	_kick_at[id] = _now() + KICK_DELAY


@rpc("any_peer", "call_remote", "reliable")
func _c2s_chat(text: Variant) -> void:
	if multiplayer.is_server():
		_handle_chat(multiplayer.get_remote_sender_id(), text)


@rpc("any_peer", "call_remote", "reliable")
func _c2s_command(sim_node: Variant, action_id: Variant, target: Variant) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var err := handle_command(id, sim_node, action_id, target)
	if err != "" and players.has(id):
		_s2c_notice.rpc_id(id, err)


@rpc("any_peer", "call_remote", "reliable")
func _c2s_speed_vote(index: Variant) -> void:
	if multiplayer.is_server():
		_handle_vote(multiplayer.get_remote_sender_id(), index)


@rpc("any_peer", "call_remote", "reliable")
func _c2s_emergency() -> void:
	if multiplayer.is_server():
		_handle_emergency(multiplayer.get_remote_sender_id())


# ---------------------------------------------------------------- server: logika

func _register_player(id: int, raw_name: Variant, character := {}) -> void:
	var taken: Array = []
	for pid in players:
		taken.append(players[pid]["name"])
	var nm := Protocol.unique_name(Protocol.sanitize_name(raw_name), taken)
	var now := _now()
	var sim := String()
	var own := false
	if not character.is_empty():
		sim = _spawn_player_character(id, character)
		own = sim != String()
		if not own:
			_notify(id, "Na serveru už není místo pro další vlastní postavu – převezmeš postavu domácnosti.")
	if sim == String():
		sim = _free_sim()
	players[id] = {
		"name": nm, "sim": sim, "vote": 1, "own": own,
		"chat": Protocol.RateLimiter.new(Protocol.CHAT_BUCKET[0], Protocol.CHAT_BUCKET[1], now),
		"cmd": Protocol.RateLimiter.new(Protocol.COMMAND_BUCKET[0], Protocol.COMMAND_BUCKET[1], now),
		"vote_rl": Protocol.RateLimiter.new(Protocol.VOTE_BUCKET[0], Protocol.VOTE_BUCKET[1], now),
		"last_emergency": -1.0e9,
	}
	_private_sent.erase(id)
	if id == 1:
		my_name = nm
		my_sim = sim
		welcomed.emit(sim)
	else:
		_s2c_welcome.rpc_id(id, id, nm, sim)
	_refresh_visibility()
	# Spawner replays original spawn data. Catch a newly introduced peer up
	# with the current canonical look after earlier edits. The client buffers
	# these authoritative packets until its puppet exists.
	if id > 1 and character_edit_apply_rpc_enabled:
		for key in world._character_revisions:
			var revision: int = int(world._character_revisions[key])
			if revision > 0:
				_server_broadcast_character_public_look(String(key), revision, id)
	_broadcast_roster()
	var msg := "%s vstupuje do hry" % nm
	if sim != "":
		msg += " a ovládá postavu %s." % _sim_display(sim)
	else:
		msg += " jako divák (všechny postavy jsou obsazené)."
	_system_chat(msg)
	_update_speed()


## Hostitel bez vlastní postavy se registruje dřív, než existuje domácnost – po jejím spawnu
## dostane volnou postavu (jinak by zůstal divákem).
func assign_host_sim() -> void:
	if not players.has(1) or String(players[1]["sim"]) != String():
		return
	var sim := _free_sim()
	if sim == String():
		return
	players[1]["sim"] = sim
	my_sim = sim
	welcomed.emit(sim)
	_broadcast_roster()


## Spawne vlastní postavu hráče (data už jsou validovaná). Vrací jméno uzlu nebo prázdný řetězec.
func _spawn_player_character(id: int, character: Dictionary) -> String:
	var count := 0
	for pid in players:
		if bool(players[pid].get("own", false)):
			count += 1
	if count >= Protocol.MAX_PLAYER_CHARACTERS:
		return String()
	var c := CharacterData.new()
	c.set_from_dict(character)
	var base := ("Hrac%d_%s" % [id, c.first_name()]).validate_node_name().replace(" ", "_").substr(0, 40)
	var node_name := base
	var n := 2
	while world.sims_root.has_node(NodePath(node_name)):
		node_name = "%s_%d" % [base, n]
		n += 1
	var off := Vector3(float(count % 4) * 0.8, 0.0, float(count / 4) * 0.8)
	var node: Node = world.spawn_character(character, world.ARRIVAL_POS + off, 5000 + id % 100000, node_name)
	if node == null:
		return String()
	node.set_meta("player_character", true)
	node.set_meta("character_uid", String(character.get("uid", "")))   # serverem přidělené, jen na serveru
	stats["characters_spawned"] += 1
	return String(node.name)


func _free_sim() -> String:
	var owned: Array = []
	for pid in players:
		owned.append(players[pid]["sim"])
	for s in world.get_sims():
		if not owned.has(String(s.name)) and not bool(s.get_meta("player_character", false)):
			return String(s.name)
	return ""


func _sim_display(node_name: String) -> String:
	var s = world.find_sim(node_name)
	return s.sim_name if s != null else node_name


func _on_peer_connected(id: int) -> void:
	pending[id] = _now()


func _on_peer_disconnected(id: int) -> void:
	_edit_limiters.erase(id)
	_public_resync_limiters.erase(id)
	pending.erase(id)
	_kick_at.erase(id)
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	players.erase(id)
	_private_sent.erase(id)
	# Postava domácnosti se vrací pod autonomní řízení – zrušit zbytek hráčových příkazů.
	# Vlastní postava hráče odchází s ním (despawn se replikuje všem klientům).
	var s = world.find_sim(p["sim"])
	if s != null and s.has_method("command"):
		s.player_queue.clear()
		if bool(p.get("own", false)):
			if s.has_method("leave_world"):
				s.leave_world()
			world.unregister_sim(s)
			s.queue_free()
	_refresh_visibility()
	_broadcast_roster()
	_system_chat("%s opouští hru." % p["name"])
	_update_speed()


func _kick(id: int) -> void:
	stats["kicked"] += 1
	pending.erase(id)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _handle_chat(id: int, text: Variant) -> void:
	if not players.has(id):
		stats["rejected"] += 1
		return
	var p: Dictionary = players[id]
	if not p["chat"].allow(_now()):
		stats["chat_blocked"] += 1
		_notify(id, "Píšeš moc rychle – chvilku počkej.")
		return
	var clean := Protocol.sanitize_chat(text)
	if clean == "":
		return
	stats["chat_sent"] += 1
	_broadcast_chat(p["name"], clean, false)


## Authenticated, immediate two-party consent processing. Only a player's own
## avatar may create its offer. Unowned NPC evaluates willingness for itself.
## A different player's avatar never silently accepts on their behalf.
func _handle_intimacy_command(peer_id: int, actor, partner, action_id: String) -> String:
	if world == null or world.net == null or not world.net.is_authority():
		return "Intimní akce smí schválit pouze server."
	var now: float = world.clock.total_minutes
	if action_id == "intimacy_withdraw":
		actor.intimacy.revoke_consent(String(partner.name))
		if actor.current_action.get("id", "") == "adult_consensual_sex":
			if actor.state == actor.State.ACTING:
				actor._finish(true)
			elif actor.state == actor.State.WALKING:
				actor._abort()
		elif partner.current_action.get("id", "") == "adult_consensual_sex" and partner.social_partner == actor:
			partner._finish(true)
		return ""
	var gs := get_node_or_null("/root/GameSettings")
	var enabled: bool = gs != null and gs.allows_content("adult_intimacy")
	var eligible := AdultIntimacy.eligible_pair(world, actor, partner, now, enabled)
	if not bool(eligible.get("ok", false)):
		return "Intimita teď není možná (obsah, věk nebo schopnost rozhodnout)."
	if action_id == "intimacy_offer":
		if not actor.intimacy.offer_consent(String(partner.name), now, true, true):
			return "Nátlak, odmítnutí nebo bezpečnostní omezení brání nabídce."
		var controlled_target := false
		if mode == Mode.OFFLINE:
			# In offline play the selected character is the player's avatar.
			controlled_target = partner == world.get_selected_sim()
		else:
			for player in players.values():
				if String(player.get("sim", "")) == String(partner.name):
					controlled_target = true
					break
		if not controlled_target:
			if AdultIntimacy.npc_willing(world, partner, actor, now):
				partner.intimacy.offer_consent(String(actor.name), now, true, true)
			else:
				partner.intimacy.refuse(String(actor.name), now)
				actor.intimacy.revoke_consent(String(partner.name))
				return "Druhá postava intimitu odmítla."
		return ""
	if action_id == "adult_consensual_sex":
		if not bool(AdultIntimacy.check(world, actor, partner, now, true).get("ok", false)):
			return "Intimita vyžaduje aktuální dobrovolný souhlas obou postav."
		if not partner.can_join_social(actor):
			return "Druhá postava nyní nemůže společnou činnost zahájit."
	return ""


## Ověří a provede příkaz hráče. Vrací "" při úspěchu, jinak důvod odmítnutí.
func handle_command(id: int, sim_node: Variant, action_id: Variant, target: Variant) -> String:
	if mode != Mode.OFFLINE:
		if not players.has(id):
			stats["rejected"] += 1
			return "Neznámý hráč."
		if not players[id]["cmd"].allow(_now()):
			stats["rejected"] += 1
			return "Příliš mnoho příkazů najednou."
	if not Protocol.valid_id(sim_node) or not Protocol.valid_id(action_id):
		stats["rejected"] += 1
		return "Neplatný příkaz."
	var sim = world.find_sim(String(sim_node))
	if sim == null or not sim.has_method("command"):
		stats["rejected"] += 1
		return "Postava neexistuje."
	if mode != Mode.OFFLINE and players[id]["sim"] != String(sim_node):
		stats["rejected"] += 1
		return "Tahle postava ti nepatří."
	if action_id == "cancel":
		sim.command({"id": "cancel"}, null)
		stats["commands"] += 1
		return ""
	var action: Dictionary = ActionLibrary.get_action(String(action_id))
	if action.is_empty():
		stats["rejected"] += 1
		return "Neznámá akce."
	if bool(action.get("involuntary", false)) or bool(action.get("system", false)):
		stats["rejected"] += 1
		return "Tohle se nedá zadat – je to symptom, ne volba."
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and action_id != "intimacy_withdraw" and not gs.allows_content(String(action.get("content", ""))):
		stats["rejected"] += 1
		return "Tahle akce je vypnutá v nastavení obsahu serveru."
	var tgt: Node3D = null
	var obj_tag: String = action.get("object", "")
	if obj_tag == "":
		if not (typeof(target) == TYPE_STRING and String(target) == ""):
			stats["rejected"] += 1
			return "Akce nemá cíl."
	elif obj_tag == "sim":
		if not Protocol.valid_id(target):
			stats["rejected"] += 1
			return "Neplatný cíl."
		tgt = world.find_sim(String(target))
		if tgt == null or tgt == sim:
			stats["rejected"] += 1
			return "Cílová postava neexistuje."
		if bool(action.get("approach_only", false)) and not tgt.accepts_support():
			stats["rejected"] += 1
			return "%s teď pomoc nepotřebuje." % tgt.first_name()
	else:
		var objs: Array = world.get_smart_objects()
		if not Protocol.valid_int(target, 0, objs.size() - 1):
			stats["rejected"] += 1
			return "Neplatný objekt."
		tgt = objs[int(target)]
		if tgt.object_tag != obj_tag:
			stats["rejected"] += 1
			return "Tuhle akci objekt nenabízí."
	if String(action_id) in ["intimacy_offer", "intimacy_withdraw", "adult_consensual_sex"]:
		var reason: String = _handle_intimacy_command(id, sim, tgt, String(action_id))
		if reason != "":
			stats["rejected"] += 1
			return reason
		if String(action_id) != "adult_consensual_sex":
			stats["commands"] += 1
			return ""
	if not sim.command(action, tgt):
		return "Fronta příkazů je plná."
	stats["commands"] += 1
	return ""


func _handle_vote(id: int, index: Variant) -> void:
	if not players.has(id) or not Protocol.valid_int(index, 0, 4):
		stats["rejected"] += 1
		return
	if not players[id]["vote_rl"].allow(_now()):
		stats["rejected"] += 1
		return
	players[id]["vote"] = int(index)
	stats["votes"] += 1
	_update_speed()


func _handle_emergency(id: int) -> void:
	if not players.has(id):
		stats["rejected"] += 1
		return
	var now := _now()
	var since: float = now - float(players[id]["last_emergency"])
	if since < Protocol.EMERGENCY_COOLDOWN:
		stats["rejected"] += 1
		_notify(id, "Nouzovou pauzu můžeš znovu použít za %d s." % int(ceil(Protocol.EMERGENCY_COOLDOWN - since)))
		return
	players[id]["last_emergency"] = now
	emergency_until = now + emergency_pause_seconds
	_system_chat("%s zastavuje čas (nouzová pauza %d s)." % [players[id]["name"], int(emergency_pause_seconds)])
	_update_speed()


func _update_speed() -> void:
	if not is_authority() or mode == Mode.OFFLINE:
		return
	var votes: Array = []
	for pid in players:
		votes.append(players[pid]["vote"])
	# Bez hráčů dedikovaný server stojí (nikdo se nedívá); nouzová pauza má přednost.
	var eff := Protocol.effective_speed(votes, 0)
	if emergency_until > 0.0 and _now() < emergency_until:
		eff = 0
	if clock.speed_index != eff:
		clock.set_speed(eff)
	_broadcast_roster()
	_send_clock()


func _broadcast_roster() -> void:
	var r := {}
	for pid in players:
		r[pid] = {"name": players[pid]["name"], "sim": players[pid]["sim"], "vote": players[pid]["vote"]}
	roster = r
	roster_changed.emit(roster)
	for pid in _remote_players():
		_s2c_roster.rpc_id(pid, r)


## Vzdálení (ne lokální) představení hráči – jen jim server posílá stav.
func _remote_players() -> Array:
	var out: Array = []
	if not _connected:
		return out
	for pid in players:
		if pid != 1:
			out.append(pid)
	return out


func _broadcast_chat(from: String, text: String, system: bool) -> void:
	_add_chat(from, text, system)
	for pid in _remote_players():
		_s2c_chat.rpc_id(pid, from, text, system)


func _system_chat(text: String) -> void:
	_broadcast_chat("", text, true)


func _notify(id: int, text: String) -> void:
	if id == 1:
		notice.emit(text)
	else:
		_s2c_notice.rpc_id(id, text)


func _send_clock() -> void:
	for pid in _remote_players():
		_s2c_clock.rpc_id(pid, clock.total_minutes, clock.speed_index)


func _process(delta: float) -> void:
	if not _connected:
		return
	if mode == Mode.CLIENT:
		_expire_pending_character_edit_read()
		_retry_public_look_resync()
		return
	if not is_authority():
		return
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = CLOCK_SYNC_INTERVAL
		_send_clock()
	var now := _now()
	for id in pending.keys():
		if now - float(pending[id]) > Protocol.HELLO_TIMEOUT:
			_kick(id)
	for id in _kick_at.keys():
		if now >= float(_kick_at[id]):
			_kick_at.erase(id)
			_kick(id)
	if emergency_until > 0.0 and now >= emergency_until:
		emergency_until = 0.0
		_system_chat("Nouzová pauza skončila.")
		_update_speed()
	_private_timer -= delta
	if _private_timer <= 0.0:
		_private_timer = PRIVATE_INTERVAL
		_send_private_state()


## Soukromý stav postavy jen jejímu vlastníkovi (a jen při změně).
func _send_private_state() -> void:
	for pid in _remote_players():
		var s = world.find_sim(String(players[pid]["sim"]))
		if s == null or not s.has_method("command"):
			continue
		var h := hash([s.net_needs, s.net_detail])
		if _private_sent.get(pid, 0) == h:
			continue
		_private_sent[pid] = h
		_s2c_private.rpc_id(pid, String(s.name), s.net_needs, s.net_detail)


# ---------------------------------------------------------------- RPC: server → klienti

@rpc("authority", "call_remote", "reliable")
func _s2c_welcome(_peer_id: Variant, player_name: Variant, sim_node: Variant) -> void:
	if typeof(player_name) != TYPE_STRING or typeof(sim_node) != TYPE_STRING:
		return
	my_name = player_name
	my_sim = sim_node
	welcomed.emit(my_sim)


@rpc("authority", "call_remote", "reliable")
func _s2c_roster(r: Variant) -> void:
	if typeof(r) != TYPE_DICTIONARY:
		return
	roster = r
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func _s2c_chat(from: Variant, text: Variant, system: Variant) -> void:
	if typeof(from) != TYPE_STRING or typeof(text) != TYPE_STRING:
		return
	_add_chat(from, Protocol.sanitize_chat(text), bool(system))


@rpc("authority", "call_remote", "unreliable_ordered")
func _s2c_clock(total: Variant, speed: Variant) -> void:
	if typeof(total) != TYPE_FLOAT or typeof(speed) != TYPE_INT:
		return
	stats["clock_syncs"] += 1
	var diff: float = float(total) - clock.total_minutes
	if absf(diff) > CLOCK_SNAP:
		clock.total_minutes = float(total)
	else:
		clock.total_minutes += diff * 0.25
	var sp := clampi(int(speed), 0, 4)
	if clock.speed_index != sp:
		clock.set_speed(sp)


@rpc("authority", "call_remote", "reliable")
func _s2c_private(sim_node: Variant, needs: Variant, detail: Variant) -> void:
	if typeof(sim_node) != TYPE_STRING or typeof(needs) != TYPE_PACKED_BYTE_ARRAY or typeof(detail) != TYPE_DICTIONARY:
		return
	if String(sim_node) != my_sim:
		return
	var p = world.find_sim(my_sim)
	if p != null and p.has_method("apply_private"):
		p.apply_private(needs, detail)


@rpc("authority", "call_remote", "reliable")
func _s2c_notice(text: Variant) -> void:
	if typeof(text) == TYPE_STRING:
		notice.emit(Protocol.sanitize_chat(text))


func _add_chat(from: String, text: String, system: bool) -> void:
	chat_log.append([from, text, system])
	if chat_log.size() > MAX_CHAT_LOG:
		chat_log.pop_front()
	chat_received.emit(from, text, system)


# ---------------------------------------------------------------- klient: připojení

func _on_connected_to_server() -> void:
	_connected = true
	_c2s_hello.rpc_id(1, my_name, Protocol.VERSION, my_character_code)


func _on_connection_failed() -> void:
	_connected = false
	cancel_character_edit_snapshot()
	_public_look_revisions.clear()
	_pending_public_looks.clear()
	_public_resync_requested.clear()
	disconnected.emit("Nepodařilo se připojit k serveru.")


func _on_server_disconnected() -> void:
	_connected = false
	cancel_character_edit_snapshot()
	_public_look_revisions.clear()
	_pending_public_looks.clear()
	_public_resync_requested.clear()
	_add_chat("", "Spojení se serverem bylo ukončeno.", true)
	disconnected.emit("Server ukončil spojení.")

# H2b network ownership prerequisite. This is a SERVER-INTERNAL predicate, NOT an
# RPC and NOT a remote edit entry point. A future @rpc handler MUST obtain sender
# exclusively from multiplayer.get_remote_sender_id(), never from packet payload.
# Both private reads and writes must use this gate; full RPC/replication remains OFF.
func server_can_edit_character(sender_peer_id: int, sim_node: Variant) -> bool:
	if mode != Mode.HOST and mode != Mode.DEDICATED:
		return false
	if not _connected or not multiplayer.is_server():
		return false
	if sender_peer_id < 1 or not players.has(sender_peer_id):
		return false
	if typeof(sim_node) != TYPE_STRING or String(sim_node).is_empty():
		return false
	var owned: Dictionary = players[sender_peer_id]
	if not bool(owned.get("own", false)) or String(owned.get("sim", "")) != String(sim_node):
		return false
	if world == null or not is_instance_valid(world) or world.is_queued_for_deletion():
		return false
	var sim = world.find_sim(String(sim_node))
	if sim == null or not is_instance_valid(sim) or sim.is_queued_for_deletion() or not bool(sim.get_meta("player_character", false)):
		return false
	var uid := String(sim.get_meta("character_uid", ""))
	if uid.is_empty() or not world._character_records.has(String(sim_node)):
		return false
	var record: Resource = world._character_records[String(sim_node)]
	if record == null or not is_instance_valid(record) or String(record.to_dict().get("uid", "")) != uid:
		return false
	# Fail closed on an inconsistent server-side assignment (two alleged owners).
	for other_id in players:
		if other_id != sender_peer_id and bool(players[other_id].get("own", false)) and String(players[other_id].get("sim", "")) == String(sim_node):
			return false
	return true
# H2b: bounded server-internal request-envelope preflight. This does NOT
# decode/validate the candidate, perform Apply, or expose any RPC. A future
# authenticated RPC must derive sender from multiplayer.get_remote_sender_id(),
# call this gate, strictly decode/validate the candidate and recheck ownership
# and revision immediately before the authoritative commit.
const EDIT_MAX_WIRE_BYTES := 24 * 1024
const EDIT_BUCKET_CAPACITY := 3.0
const EDIT_BUCKET_REFILL := 0.2
var _edit_limiters: Dictionary = {}

func server_preflight_character_edit(sender_peer_id: int, sim_node: Variant, expected_revision: Variant, wire_payload: Variant) -> Dictionary:
	if not server_can_edit_character(sender_peer_id, sim_node):
		return {"ok":false,"reason":"unauthorized"}
	if typeof(expected_revision) != TYPE_INT or int(expected_revision) < 0:
		return {"ok":false,"reason":"invalid_revision"}
	if typeof(wire_payload) != TYPE_PACKED_BYTE_ARRAY:
		return {"ok":false,"reason":"invalid_payload_type"}
	var wire: PackedByteArray = wire_payload
	if wire.is_empty() or wire.size() > EDIT_MAX_WIRE_BYTES:
		return {"ok":false,"reason":"invalid_payload_size"}
	var key := String(sim_node)
	if not world._character_revisions.has(key):
		return {"ok":false,"reason":"missing_revision"}
	if int(expected_revision) != int(world._character_revisions[key]):
		return {"ok":false,"reason":"conflict"}
	if not _edit_limiters.has(sender_peer_id):
		_edit_limiters[sender_peer_id] = Protocol.RateLimiter.new(EDIT_BUCKET_CAPACITY, EDIT_BUCKET_REFILL, _now())
	if not _edit_limiters[sender_peer_id].allow(_now()):
		return {"ok":false,"reason":"rate_limited"}
	return {"ok":true}

# Decode the current-schema JSON envelope for a future authenticated RPC.
# SERVER-INTERNAL only; returned data is private and must never be broadcast.
# No migration/default-group substitution, no commit, and no revision reservation.
func server_prepare_character_edit(sender_peer_id: int, sim_node: Variant, expected_revision: Variant, wire_payload: Variant) -> Dictionary:
	var gate := server_preflight_character_edit(sender_peer_id, sim_node, expected_revision, wire_payload)
	if not gate.get("ok", false):
		return gate
	var wire: PackedByteArray = wire_payload
	var parser := JSON.new()
	if parser.parse(wire.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok":false,"reason":"invalid_json"}
	var candidate: Dictionary = parser.data
	var key := String(sim_node)
	var before: Dictionary = world._character_records[key].to_dict()
	# JSON numbers decode as floats: exact numeric equality, never int truncation.
	var version = candidate.get("v")
	if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or version != before["v"]:
		return {"ok":false,"reason":"schema_mismatch"}
	if candidate.get("uid") != before["uid"]:
		return {"ok":false,"reason":"identity_changed"}
	for group in CharacterData.GROUP_PROPS:
		if not candidate.has(group) or typeof(candidate[group]) != TYPE_DICTIONARY:
			return {"ok":false,"reason":"incomplete_character"}
	# Existing live edits cannot rename identity while relations use display names.
	if candidate["identity"] != before["identity"]:
		return {"ok":false,"reason":"identity_edit_pending"}
	var gs := get_node_or_null("/root/GameSettings")
	var mh: String = gs.mental_health_mode() if gs != null else "full"
	var result: Dictionary = CharacterCodec.Validator.validate(candidate, {"mode":"strict","mental_health":mh})
	if not result.get("ok",false):
		# Do not reflect arbitrary packet contents in an error response.
		return {"ok":false,"reason":"invalid_character"}
	if not server_can_edit_character(sender_peer_id, key):
		return {"ok":false,"reason":"unauthorized"}
	if not world._character_revisions.has(key) or world._character_revisions[key] != expected_revision:
		return {"ok":false,"reason":"conflict"}
	return {"ok":true,"data":result["data"],"revision":expected_revision,"warnings":result["warnings"]}

# H2b authenticated private owner read. Enabled only by the native game setup for owner editing.
signal character_edit_snapshot(sim_node: String, data: Dictionary, revision: int)
# Correlation is an opaque UI generation ID, never an ownership credential.
signal character_edit_snapshot_correlated(request_id: String, sim_node: String, data: Dictionary, revision: int)
signal character_edit_snapshot_timed_out(request_id: String)
const EDIT_READ_TIMEOUT_MS := 6000
var _pending_edit_read_id := ""
var _pending_edit_read_deadline_ms := 0

## Panel cleanup may cancel only its own generation. No argument is reserved
## for connection-wide shutdown/disconnect and internal completion/expiry.
func cancel_character_edit_snapshot(request_id: String = "") -> void:
	if not request_id.is_empty() and request_id != _pending_edit_read_id:
		return
	_pending_edit_read_id = ""
	_pending_edit_read_deadline_ms = 0

func _expire_pending_character_edit_read() -> void:
	if _pending_edit_read_id.is_empty() or _pending_edit_read_deadline_ms <= 0:
		return
	if Time.get_ticks_msec() < _pending_edit_read_deadline_ms:
		return
	var expired_id := _pending_edit_read_id
	cancel_character_edit_snapshot()
	character_edit_snapshot_timed_out.emit(expired_id)

## True means local preflight allowed an RPC send attempt, NOT server
## authorization, receipt or permission to open a private editor draft.
func request_character_edit_snapshot(request_id: String = "") -> bool:
	if not request_id.is_empty() and not _valid_incarnation(request_id):
		return false
	if mode != Mode.CLIENT or not _connected or my_sim.is_empty():
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_pending_edit_read_id = request_id
	_pending_edit_read_deadline_ms = Time.get_ticks_msec() + EDIT_READ_TIMEOUT_MS if not request_id.is_empty() else 0
	_c2s_character_edit_read.rpc_id(1, my_sim, request_id)
	return true

func server_read_character_edit(sender_peer_id: int, sim_node: Variant) -> Dictionary:
	if not server_can_edit_character(sender_peer_id, sim_node):
		return {"ok":false,"reason":"unauthorized"}
	var key := String(sim_node)
	if not world._character_revisions.has(key):
		return {"ok":false,"reason":"missing_revision"}
	if not _edit_limiters.has(sender_peer_id):
		_edit_limiters[sender_peer_id] = Protocol.RateLimiter.new(EDIT_BUCKET_CAPACITY, EDIT_BUCKET_REFILL, _now())
	if not _edit_limiters[sender_peer_id].allow(_now()):
		return {"ok":false,"reason":"rate_limited"}
	var wire := JSON.stringify(world._character_records[key].to_dict()).to_utf8_buffer()
	if wire.is_empty() or wire.size() > EDIT_MAX_WIRE_BYTES:
		return {"ok":false,"reason":"snapshot_too_large"}
	return {"ok":true,"wire":wire,"revision":int(world._character_revisions[key])}

@rpc("any_peer", "call_remote", "reliable")
func _c2s_character_edit_read(sim_node: Variant, request_id: Variant = "") -> void:
	if typeof(request_id)!=TYPE_STRING or (not request_id.is_empty() and not _valid_incarnation(request_id)):
		return
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Never accept a sender ID or ownership flag from packet contents.
	var result := server_read_character_edit(sender, sim_node)
	if not result.get("ok",false):
		return
	# No await between authorization and unicast. Never broadcast private data.
	_s2c_character_edit_snapshot.rpc_id(sender, String(sim_node), result["wire"], result["revision"], request_id)

@rpc("authority", "call_remote", "reliable")
func _s2c_character_edit_snapshot(sim_node: Variant, wire_payload: Variant, revision: Variant, request_id: Variant = "") -> void:
	if typeof(request_id)!=TYPE_STRING or (not request_id.is_empty() and not _valid_incarnation(request_id)):
		return
	if mode != Mode.CLIENT or not _connected or multiplayer.get_remote_sender_id()!=1:
		return
	if typeof(sim_node)!=TYPE_STRING or sim_node!=my_sim or typeof(revision)!=TYPE_INT or revision<0:
		return
	if typeof(wire_payload)!=TYPE_PACKED_BYTE_ARRAY:
		return
	var wire: PackedByteArray=wire_payload
	if wire.is_empty() or wire.size()>EDIT_MAX_WIRE_BYTES:
		return
	var parser:=JSON.new()
	if parser.parse(wire.get_string_from_utf8())!=OK or typeof(parser.data)!=TYPE_DICTIONARY:
		return
	if request_id.is_empty():
		# A legacy response must not reach consumers while a tagged UI read is pending.
		if not _pending_edit_read_id.is_empty():
			return
		character_edit_snapshot.emit(String(sim_node),parser.data,int(revision))
	else:
		_expire_pending_character_edit_read()
		if request_id != _pending_edit_read_id:
			return
		cancel_character_edit_snapshot()
		character_edit_snapshot_correlated.emit(request_id,String(sim_node),parser.data,int(revision))


# H2b server-authoritative write transport. Opt-in flag fails closed by default;
# native main.gd enables it only for real multiplayer sessions.
# The trusted world method performs canonical validation and rechecks ownership
# synchronously before commit. This RPC never accepts peer IDs from packets.
signal character_edit_apply_result(sim_node: String, accepted: bool, revision: int, changed: bool, reason: String)
## Private acknowledgement tied to the exact editor transaction (not an auth token).
signal character_edit_apply_correlated(request_id: String, sim_node: String, accepted: bool, revision: int, changed: bool, reason: String)
signal character_public_look_received(sim_node: String, revision: int)
var _public_look_revisions := {}
## Public-only, validated packets received before the corresponding puppet spawned.
const MAX_PENDING_LOOK_INCARNATIONS := 2
# node name -> incarnation -> latest validated snapshot; bounded by spawn_limit names.
var _pending_public_looks := {}
# One client resync per spawn incarnation; per-peer server token bucket.
const PUBLIC_RESYNC_CAPACITY := 4.0
const PUBLIC_RESYNC_REFILL := 0.25
const PUBLIC_RESYNC_RETRY_SECONDS := 5.0
const PUBLIC_RESYNC_MAX_ATTEMPTS := 3
var _public_resync_limiters := {}
var _public_resync_requested := {}
var character_edit_apply_rpc_enabled := false
## Independent gate for native owner HUD; default false outside live native setup.
var character_edit_read_ui_enabled := false

func request_character_edit_apply(expected_revision: int, candidate: Dictionary, request_id: String = "") -> bool:
	if not character_edit_apply_rpc_enabled or mode != Mode.CLIENT or not _connected or my_sim.is_empty():
		return false
	if expected_revision < 0 or (not request_id.is_empty() and not _valid_incarnation(request_id)):
		return false
	var wire := JSON.stringify(candidate).to_utf8_buffer()
	if wire.is_empty() or wire.size() > EDIT_MAX_WIRE_BYTES:
		return false
	_c2s_character_edit_apply.rpc_id(1, my_sim, expected_revision, wire, request_id)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _c2s_character_edit_apply(sim_node: Variant, expected_revision: Variant, wire_payload: Variant, request_id: Variant = "") -> void:
	if typeof(request_id) != TYPE_STRING or (not request_id.is_empty() and not _valid_incarnation(request_id)):
		return
	if not character_edit_apply_rpc_enabled or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not server_can_edit_character(sender, sim_node):
		return
	if world == null or not world.has_method("server_apply_character_edit"):
		return
	# World is the trusted authoritative game controller. It runs the existing
	# strict prepare/ownership/revision/commit path without awaiting.
	var result: Dictionary = world.server_apply_character_edit(sender, sim_node, expected_revision, wire_payload)
	# Private, bounded acknowledgement only; never send full character data.
	# A separate public-look message replicates validated public appearance only.
	var allowed_reasons := ["conflict", "invalid_character", "invalid_json",
		"invalid_revision", "invalid_payload_type", "invalid_payload_size",
		"schema_mismatch", "identity_changed", "identity_edit_pending",
		"incomplete_character", "rate_limited", "missing_character", "unauthorized"]
	var reason := ""
	if not result.get("ok", false):
		reason = str(result.get("reason", "rejected"))
		if reason not in allowed_reasons:
			reason = "rejected"
	var revision := int(result.get("revision", expected_revision)) if typeof(expected_revision) == TYPE_INT else 0
	_s2c_character_edit_apply_result.rpc_id(sender, String(sim_node),
		bool(result.get("ok", false)), max(0, revision),
		bool(result.get("changed", false)) if result.get("ok", false) else false, reason, request_id)
	if result.get("ok", false) and result.get("changed", false):
		_server_broadcast_character_public_look(String(sim_node), revision)

@rpc("authority", "call_remote", "reliable")
func _s2c_character_edit_apply_result(sim_node: Variant, accepted: Variant,
		revision: Variant, changed: Variant, reason: Variant, request_id: Variant = "") -> void:
	if not character_edit_apply_rpc_enabled or mode != Mode.CLIENT or not _connected:
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if typeof(sim_node) != TYPE_STRING or sim_node != my_sim:
		return
	if typeof(accepted) != TYPE_BOOL or typeof(changed) != TYPE_BOOL:
		return
	if typeof(revision) != TYPE_INT or revision < 0:
		return
	if typeof(reason) != TYPE_STRING or reason.length() > 40:
		return
	if typeof(request_id) != TYPE_STRING or (not request_id.is_empty() and not _valid_incarnation(request_id)):
		return
	character_edit_apply_result.emit(sim_node, accepted, revision, changed, reason)
	if not request_id.is_empty():
		character_edit_apply_correlated.emit(request_id, sim_node, accepted, revision, changed, reason)


## Exactly 128-bit lowercase hex, generated afresh by the server per spawn.
static func _valid_incarnation(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 32:
		return false
	for i in value.length():
		if "0123456789abcdef".find(value.substr(i, 1)) < 0:
			return false
	return true


## Staged public appearance replication. No private CharacterData leaves the server.
## Disabled by default with the entire remote editor. Only introduced peers receive it.
func _server_broadcast_character_public_look(sim_node: String, revision: int, only_peer: int = -1) -> void:
	if not character_edit_apply_rpc_enabled or not multiplayer.is_server() or world == null:
		return
	if not world.has_method("read_public_character_look"):
		return
	var actor = world.find_sim(sim_node)
	if actor == null:
		return
	var incarnation: Variant = actor.get_meta("net_incarnation", "")
	if not _valid_incarnation(incarnation):
		return
	var packet: Dictionary = world.read_public_character_look(sim_node)
	if not packet.get("ok", false) or int(packet.get("revision", -1)) != revision:
		return
	var checked: Dictionary = CharacterValidator.validate(packet.get("look", null),
		{"mode":"strict", "public_only":true})
	if not checked.get("ok", false):
		return
	var wire: PackedByteArray = JSON.stringify(checked["data"]).to_utf8_buffer()
	if wire.is_empty() or wire.size() > EDIT_MAX_WIRE_BYTES:
		return
	for peer_id in players:
		if int(peer_id) > 1 and (only_peer < 0 or int(peer_id) == only_peer) \
				and not pending.has(peer_id) and not _kick_at.has(peer_id):
			_s2c_character_public_look.rpc_id(int(peer_id), sim_node, incarnation, revision, wire)


## Recover a missing matching pre-spawn snapshot (e.g. bounded incarnation eviction).
## No client-supplied peer ID, character data, revision, or ownership flags.
func _request_public_look_resync(sim_node: String, incarnation: String) -> void:
	if not character_edit_apply_rpc_enabled or mode != Mode.CLIENT or not _connected:
		return
	if not Protocol.valid_id(sim_node) or not _valid_incarnation(incarnation) or spawner == null:
		return
	var existing: Dictionary = _public_resync_requested.get(sim_node, {})
	if existing.get("incarnation", "") == incarnation:
		return
	if not _public_resync_requested.has(sim_node) and _public_resync_requested.size() >= spawner.spawn_limit:
		return
	_public_resync_requested[sim_node] = {"incarnation":incarnation, "attempts":1, "last_sent":_now()}
	_c2s_character_public_look_resync.rpc_id(1, sim_node, incarnation)

## Retry at most twice, while the same spawned puppet still exists.
func _retry_public_look_resync() -> void:
	if not character_edit_apply_rpc_enabled or mode != Mode.CLIENT or not _connected or world == null:
		return
	for sim_node in _public_resync_requested.keys():
		var entry: Dictionary = _public_resync_requested[sim_node]
		var incarnation: String = String(entry.get("incarnation", ""))
		var sim = world.find_sim(String(sim_node))
		if sim == null or not is_instance_valid(sim) or sim.is_queued_for_deletion() or String(sim.get_meta("net_incarnation", "")) != incarnation:
			_public_resync_requested.erase(sim_node)
			continue
		if int(entry.get("attempts", 0)) >= PUBLIC_RESYNC_MAX_ATTEMPTS or _now() - float(entry.get("last_sent", 0.0)) < PUBLIC_RESYNC_RETRY_SECONDS:
			continue
		entry["attempts"] = int(entry.get("attempts", 0)) + 1
		entry["last_sent"] = _now()
		_public_resync_requested[sim_node] = entry
		_c2s_character_public_look_resync.rpc_id(1, String(sim_node), incarnation)

@rpc("any_peer", "call_remote", "reliable")
func _c2s_character_public_look_resync(sim_node: Variant, incarnation: Variant) -> void:
	if not character_edit_apply_rpc_enabled or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not players.has(sender) or pending.has(sender) or _kick_at.has(sender):
		return
	if typeof(sim_node) != TYPE_STRING or not Protocol.valid_id(sim_node) or not _valid_incarnation(incarnation):
		return
	if world == null or not is_instance_valid(world) or not world.has_method("read_public_character_look"):
		return
	var actor = world.find_sim(String(sim_node))
	if actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return
	if String(actor.get_meta("net_incarnation", "")) != incarnation:
		return
	if not world._character_revisions.has(String(sim_node)):
		return
	var revision := int(world._character_revisions[String(sim_node)])
	if revision < 1:
		return
	if not _public_resync_limiters.has(sender):
		_public_resync_limiters[sender] = Protocol.RateLimiter.new(PUBLIC_RESYNC_CAPACITY, PUBLIC_RESYNC_REFILL, _now())
	if not _public_resync_limiters[sender].allow(_now()):
		return
	_server_broadcast_character_public_look(String(sim_node), revision, sender)

@rpc("authority", "call_remote", "reliable")
func _s2c_character_public_look(sim_node: Variant, incarnation: Variant, revision: Variant, wire: Variant) -> void:
	if not character_edit_apply_rpc_enabled or mode != Mode.CLIENT or not _connected:
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if typeof(sim_node) != TYPE_STRING or not Protocol.valid_id(sim_node):
		return
	if not _valid_incarnation(incarnation):
		return
	if typeof(revision) != TYPE_INT or revision < 1:
		return
	if typeof(wire) != TYPE_PACKED_BYTE_ARRAY or wire.is_empty() or wire.size() > EDIT_MAX_WIRE_BYTES:
		return
	if world == null:
		return
	var sim = world.find_sim(String(sim_node))
	# Reject a valid server packet from an older actor with a recycled node name.
	if sim != null and String(sim.get_meta("net_incarnation", "")) != incarnation:
		return
	var variants: Dictionary = _pending_public_looks.get(sim_node, {})
	var pending: Dictionary = variants.get(incarnation, {})
	var highest_revision: int = int(_public_look_revisions.get(sim_node, 0)) if sim != null else 0
	highest_revision = maxi(highest_revision, int(pending.get("revision", 0)))
	if revision <= highest_revision:
		return
	var parser := JSON.new()
	if parser.parse(wire.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var checked: Dictionary = CharacterValidator.validate(parser.data,
		{"mode":"strict", "public_only":true})
	if not checked.get("ok", false) or world == null:
		return
	if sim == null or not sim.has_method("apply_public_look"):
		# Network order cannot guarantee the independent MultiplayerSpawner
		# finished before this RPC. Store no more than the spawn budget.
		if _pending_public_looks.size() >= spawner.spawn_limit and not _pending_public_looks.has(sim_node):
			return
		# Keep the two most recently introduced incarnations for this node.
		# Revisions are comparable only within one incarnation.
		if not variants.has(incarnation) and variants.size() >= MAX_PENDING_LOOK_INCARNATIONS:
			variants.erase(variants.keys()[0])
		variants[incarnation] = {"revision":int(revision), "look":checked["data"].duplicate(true)}
		_pending_public_looks[sim_node] = variants
		return
	sim.apply_public_look(checked["data"])
	_public_look_revisions[sim_node] = revision
	if _public_resync_requested.get(sim_node, {}).get("incarnation", "") == incarnation:
		_public_resync_requested.erase(sim_node)
	character_public_look_received.emit(String(sim_node), int(revision))


## Deliver a validated authoritative packet which arrived before the puppet.
func _apply_pending_public_look(sim_node: String) -> void:
	if world == null:
		return
	var sim = world.find_sim(sim_node)
	if sim == null or not sim.has_method("apply_public_look"):
		return
	var incarnation := String(sim.get_meta("net_incarnation", ""))
	if not _pending_public_looks.has(sim_node):
		_request_public_look_resync(sim_node, incarnation)
		return
	var variants: Dictionary = _pending_public_looks[sim_node]
	var packet: Dictionary = variants.get(incarnation, {})
	# Drop every variant once the actual authoritative spawn resolves the name.
	_pending_public_looks.erase(sim_node)
	if packet.is_empty():
		_request_public_look_resync(sim_node, incarnation)
		return
	var revision: int = int(packet.get("revision", 0))
	if revision > int(_public_look_revisions.get(sim_node, 0)):
		sim.apply_public_look(packet["look"])
		_public_look_revisions[sim_node] = revision
		character_public_look_received.emit(sim_node, revision)
	if _public_resync_requested.get(sim_node, {}).get("incarnation", "") == incarnation:
		_public_resync_requested.erase(sim_node)