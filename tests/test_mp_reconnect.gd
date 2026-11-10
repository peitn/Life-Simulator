extends "res://tests/test_base.gd"
## H4a – znovupřipojení hráče v multiplayeru (skutečné ENet, server a klienti v jednom procesu
## jako test_multiplayer). Ověřuje:
##  * server pošle jen vlastníkovi jednorázový reconnect token a drží jen jeho SHA-256 hash,
##  * neplánované odpojení → postava zůstane ve světě (stejná instance, stav, vztahy, paměť),
##    nikdo jiný ji nedostane (vlastní ani postavu domácnosti),
##  * návrat s tokenem = stejná postava, původní jméno, žádný nový spawn, vlastnictví a editace,
##    rotace tokenu (starý token už neprojde), podvržený/prošlý token = obyčejné hello,
##  * vypršení lhůty: vlastní postava odchází všem, postava domácnosti se uvolní,
##  * úmyslný odchod (_c2s_leave) postavu nedrží, limit vlastních postav počítá držené,
##  * _remote_players posílá jen opravdu připojeným peerům, výchozí lhůta v injektovaných
##    testech je 0 (staré chování), HUD po výpadku nabídne „Znovu připojit“.
## Tokeny se nikdy nevypisují.

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const Protocol := preload("res://scripts/net/net_protocol.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")

const GRACE := 3.0
var port := 0
var server: Node3D
var notices := {}
var _holders := {}


func _ready() -> void:
	watchdog_seconds = 110.0
	randomize()
	port = 25400 + randi() % 700
	_run.call_deferred()


func _branch(bname: String, cfg: Dictionary) -> Node3D:
	var holder := Node.new()
	holder.name = bname
	add_child(holder)
	_holders[bname] = holder
	get_tree().set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	if cfg.get("mode", "") == "client":
		var c := Node.new()
		c.set_script(GameClockScript)
		c.name = "Clock"
		holder.add_child(c)
		cfg["clock"] = c
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "World"
	w.net_config = cfg
	holder.add_child(w)
	notices[bname] = []
	w.net.notice.connect(func(t: String): notices[bname].append(t))
	return w


func _client(bname: String, player_name: String, code := "", token := "", hud := false) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"character": code, "reconnect_token": token, "audio": false, "hud": hud, "camera": false, "visuals": false})


func _drop(bname: String) -> void:
	var w: Node3D = _holders[bname].get_node("World")
	w.net.shutdown()
	_holders[bname].queue_free()
	_holders.erase(bname)


func _char(seed: int, extra := {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var d := Randomizer.generate(r)
	for g in extra:
		d[g].merge(extra[g], true)
	return Validator.validate(d)["data"]


func _chat_has(w: Node3D, needle: String) -> bool:
	for e in w.net.chat_log:
		if String(e[1]).find(needle) >= 0:
			return true
	return false


func _notice_has(bname: String, needle: String) -> bool:
	for t in notices[bname]:
		if String(t).find(needle) >= 0:
			return true
	return false


func _peer_of(w: Node3D) -> int:
	return w.multiplayer.get_unique_id()


func _run() -> void:
	var clock := get_node("/root/GameClock")

	section("Formát tokenu (server i klient)")
	var good := "0123456789abcdef".repeat(4)
	check(NetSession._valid_token_format(good), "64 malých hex znaků je platný formát")
	check(not NetSession._valid_token_format(good.to_upper()), "velká písmena odmítnuta")
	check(not NetSession._valid_token_format(good.substr(1)), "63 znaků odmítnuto")
	check(not NetSession._valid_token_format(good + "0"), "65 znaků odmítnuto")
	check(not NetSession._valid_token_format(good.substr(0, 63) + "g"), "ne-hex znak odmítnut")
	check(not NetSession._valid_token_format(good.substr(0, 63) + "ž"), "unicode znak odmítnut")
	check(not NetSession._valid_token_format(123) and not NetSession._valid_token_format(null)
		and not NetSession._valid_token_format(PackedByteArray([1, 2])), "jiné typy než String odmítnuty")
	check(NetSession._token_hash(good) == good.sha256_text() and NetSession._token_hash(good) != good, "server ukládá SHA-256 hash, ne token")

	section("Výchozí lhůta v injektovaných testech = 0 (staré chování)")
	var default_port := port + 1
	var srv0 := _branch("Server0", {"mode": "server", "port": default_port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(srv0.net.reconnect_grace_seconds == 0.0, "server bez reconnect_grace v net_config nečeká na návrat")
	check(NetSession.RECONNECT_GRACE_DEFAULT >= 60.0, "skutečná hra má lhůtu aspoň minutu", str(NetSession.RECONNECT_GRACE_DEFAULT))
	_drop("Server0")
	await wait_seconds(0.2)

	section("Server s lhůtou %.0f s" % GRACE)
	server = _branch("Server", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false, "reconnect_grace": GRACE})
	check(server.net.reconnect_grace_seconds == GRACE, "lhůta z konfigurace serveru")
	check(server.get_sims().size() == 3, "domácnost 3 postavy")

	var mine := _char(4401, {"identity": {"first_name": "Vendula", "last_name": "Krátká"},
		"mind": {"predispositions": {"anxiety": 0.4}}})
	var code := Codec.encode_code(mine)
	var a := _client("ClientA", "Alfa", code)
	var b := _client("ClientB", "Beta")
	check(await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 8.0), "A (vlastní postava) a B (domácnost) přivítáni")
	check(await wait_until(func(): return a.net.my_reconnect_token != "" and b.net.my_reconnect_token != "", 3.0), "oba dostali reconnect token")
	var tok_a: String = a.net.my_reconnect_token
	var tok_b: String = b.net.my_reconnect_token
	check(NetSession._valid_token_format(tok_a) and NetSession._valid_token_format(tok_b) and tok_a != tok_b, "tokeny mají platný formát a liší se")
	var id_a := _peer_of(a)
	var id_b := _peer_of(b)
	check(String(server.net._peer_token_hash.get(id_a, "")) == tok_a.sha256_text()
		and String(server.net._peer_token_hash.get(id_b, "")) == tok_b.sha256_text(), "server zná jen hashe tokenů")
	var server_state := JSON.stringify([server.net._peer_token_hash, server.net.roster, server.net.chat_log])
	check(server_state.find(tok_a) < 0 and server_state.find(tok_b) < 0, "samotný token není v serverovém stavu, rosteru ani chatu")
	check(b.net.my_reconnect_token == tok_b and String(b.net.my_reconnect_token) != tok_a, "token dostal jen jeho vlastník")
	var a_sim: String = a.net.my_sim
	var b_sim: String = b.net.my_sim
	var s_a = server.find_sim(a_sim)
	var s_b = server.find_sim(b_sim)
	check(s_a != null and bool(s_a.get_meta("player_character", false)) and s_a.sim_name == "Vendula Krátká", "A ovládá svou vlastní postavu")
	check(s_b != null and not bool(s_b.get_meta("player_character", false)), "B ovládá postavu domácnosti")
	var spawned0: int = server.net.stats["characters_spawned"]

	# Stav, který se při návratu nesmí ztratit.
	s_a.relationships["H4a Svědek"] = 42.0
	s_a.memories.append({"t": clock.total_minutes, "text": "H4A_MARKER vzpomínka"})
	var a_instance: int = s_a.get_instance_id()
	var b_instance: int = s_b.get_instance_id()

	section("Výpadek spojení A a B → postavy čekají")
	_drop("ClientA")
	check(await wait_until(func(): return not server.net.players.has(id_a), 4.0), "server odebral A z hráčů")
	check(server.net.held_count() == 1 and server.net.is_held(a_sim), "postava A je držená pro návrat")
	check(server.find_sim(a_sim) != null and server.find_sim(a_sim).get_instance_id() == a_instance, "vlastní postava A zůstala ve světě (stejná instance)")
	check(bool(server.find_sim(a_sim).get_meta("reconnect_hold", false)), "postava má značku reconnect_hold")
	check(_chat_has(server, "ztráta spojení"), "chat oznámil ztrátu spojení a čekání")
	check(not server.net._peer_token_hash.has(id_a), "hash tokenu odpojeného peeru už není vázán na peer id")
	_drop("ClientB")
	check(await wait_until(func(): return server.net.players.is_empty(), 4.0), "server odebral i B")
	check(server.net.held_count() == 2 and server.net.is_held(b_sim), "postava domácnosti B je držená taky")

	section("Nový hráč nedostane drženou postavu")
	var e := _client("ClientE", "Eva")
	check(await wait_until(func(): return e.net.my_sim != "", 6.0), "E přivítán")
	check(e.net.my_sim != b_sim and e.net.my_sim != a_sim, "E dostal jinou volnou postavu, ne drženou", e.net.my_sim)
	check(await wait_until(func(): return e.get_sims().size() == 4, 4.0), "E vidí 4 postavy (držená vlastní postava A je dál ve světě)")

	section("Limit vlastních postav počítá držené postavy")
	var injected: Array = []
	var own_now := 0
	for pid in server.net.players:
		if bool(server.net.players[pid].get("own", false)):
			own_now += 1
	for hk in server.net._held:
		if bool(server.net._held[hk].get("own", false)):
			own_now += 1
	for i in Protocol.MAX_PLAYER_CHARACTERS - own_now:
		var fake_hash := ("fake%d" % i).sha256_text()
		server.net._held[fake_hash] = {"sim": "Neexistuje%d" % i, "name": "Fake%d" % i, "own": true, "expires": NetSession._now() + 60.0}
		injected.append(fake_hash)
	check(server.net._spawn_player_character(9999, _char(4402)) == "", "při plném limitu (včetně držených) se nová vlastní postava nespawne")
	for fh in injected:
		server.net._held.erase(fh)

	section("_remote_players jen pro opravdu připojené peery")
	server.net.players[4242] = {"name": "Duch", "sim": "", "vote": 1, "own": false}
	var remote: Array = server.net._remote_players()
	check(not remote.has(4242) and remote.has(_peer_of(e)), "peer bez ENet spojení se z broadcastů vynechá")
	server.net.players.erase(4242)

	section("Návrat A s tokenem")
	var a2 := _client("ClientA2", "Jiné Jméno", code, tok_a)
	check(await wait_until(func(): return a2.net.my_sim != "", 6.0), "A se znovu připojil")
	check(a2.net.my_sim == a_sim, "vrátil se ke STEJNÉ postavě", "%s vs %s" % [a2.net.my_sim, a_sim])
	check(a2.net.my_name == "Alfa", "jméno hráče z původní relace (klient ho nemůže změnit návratem)", a2.net.my_name)
	check(server.net.stats["resumed"] == 1 and server.net.stats["characters_spawned"] == spawned0, "žádný nový spawn – postava převzata")
	var s_a2 = server.find_sim(a_sim)
	check(s_a2 != null and s_a2.get_instance_id() == a_instance, "stejná instance postavy na serveru")
	check(float(s_a2.relationships.get("H4a Svědek", 0.0)) == 42.0, "vztahy zachovány")
	var mem_ok := false
	for m in s_a2.memories:
		if String(m.get("text", "")).begins_with("H4A_MARKER"):
			mem_ok = true
	check(mem_ok, "paměť postavy zachována")
	check(not bool(s_a2.get_meta("reconnect_hold", false)) and not server.net.is_held(a_sim) and server.net.held_count() == 1, "postava už není držená")
	var id_a2 := _peer_of(a2)
	check(bool(server.net.players[id_a2].get("own", false)) and server.net.server_can_edit_character(id_a2, a_sim), "vlastnictví a právo editace vlastní postavy obnoveno")
	check(await wait_until(func(): return _chat_has(e, "se vrací ke své postavě"), 3.0), "ostatní vidí návrat v chatu")
	check(await wait_until(func(): return a2.net.my_reconnect_token != "" and a2.net.my_reconnect_token != tok_a, 3.0), "server poslal NOVÝ token (rotace)")
	check(await wait_until(func(): return a2.get_sims().size() == 4 and a2.find_sim(a_sim) != null, 4.0), "vrácený klient vidí svou loutku i ostatní")
	check(await wait_until(func(): return a2.find_sim(a_sim).has_private, 3.0), "vlastník po návratu dostává soukromý stav své postavy")
	var tok_a2: String = a2.net.my_reconnect_token

	section("Starý (použitý) a podvržený token neprojde")
	var thief := _client("ClientThief", "Zloděj", "", tok_a)
	check(await wait_until(func(): return server.net.players.has(_peer_of(thief)), 6.0), "klient se starým tokenem je obsloužen jako nový hráč")
	check(thief.net.my_sim != a_sim and thief.net.my_sim != b_sim, "starý token nepřevzal cizí ani drženou postavu", thief.net.my_sim)
	check(server.net.stats["resume_failed"] >= 1 and await wait_until(func(): return _notice_has("ClientThief", "relace už neplatí"), 3.0), "server zamítl použitý token a řekl proč")
	check(server.net.players[id_a2]["sim"] == a_sim, "A2 o postavu nepřišel")
	_drop("ClientThief")
	await wait_until(func(): return server.net.players.size() == 2, 3.0)
	var forged := Crypto.new().generate_random_bytes(32).hex_encode()
	var f := _client("ClientForge", "Padělatel", "", forged)
	check(await wait_until(func(): return server.net.players.has(_peer_of(f)), 6.0), "náhodný token = obyčejné hello")
	check(f.net.my_sim != b_sim and f.net.my_sim != a_sim, "náhodný token nic nepřevzal")
	_drop("ClientForge")
	await wait_until(func(): return server.net.players.size() == 2, 3.0)

	section("Vypršení lhůty")
	# B se nevrátí: postava domácnosti se po lhůtě uvolní (zůstává ve světě, řídí ji AI).
	check(await wait_until(func(): return not server.net.is_held(b_sim), GRACE + 3.0), "držení postavy B vypršelo")
	check(server.find_sim(b_sim) != null and server.find_sim(b_sim).get_instance_id() == b_instance, "postava domácnosti zůstala ve světě")
	check(not server.net._held.values().any(func(h): return String(h["sim"]) == b_sim), "postava domácnosti je zase volná (není mezi drženými)")
	check(server.net.stats["hold_expired"] >= 1 and _chat_has(e, "se nevrátil"), "chat oznámil, že hráč se nevrátil")
	var late_b := _client("ClientB2", "Beta", "", tok_b)
	check(await wait_until(func(): return server.net.players.has(_peer_of(late_b)), 6.0), "pozdní návrat s prošlým tokenem je obyčejné hello")
	check(await wait_until(func(): return _notice_has("ClientB2", "relace už neplatí"), 3.0), "prošlý token zamítnut s vysvětlením")
	_drop("ClientB2")
	await wait_until(func(): return server.net.players.size() == 2, 3.0)
	# A2 vypadne podruhé a nevrátí se: vlastní postava po lhůtě všem zmizí.
	var held_before: int = server.net.stats["held"]
	_drop("ClientA2")
	check(await wait_until(func(): return server.net.stats["held"] == held_before + 1, 4.0), "druhý výpadek A znovu drží postavu")
	check(await wait_until(func(): return server.find_sim(a_sim) == null, GRACE + 3.0), "po lhůtě vlastní postava A ze serveru odešla")
	check(await wait_until(func(): return e.find_sim(a_sim) == null and e.get_sims().size() == 3, 3.0), "despawn se replikoval ostatním klientům")
	var a3 := _client("ClientA3", "Alfa", "", tok_a2)
	check(await wait_until(func(): return server.net.players.has(_peer_of(a3)), 6.0), "návrat po lhůtě = obyčejné hello")
	check(await wait_until(func(): return _notice_has("ClientA3", "relace už neplatí"), 3.0) and a3.net.my_sim != a_sim, "postavu po lhůtě už nevrátí")
	_drop("ClientA3")
	await wait_until(func(): return server.net.players.size() == 1, 3.0)

	section("Úmyslný odchod postavu nedrží")
	var e_sim: String = e.net.my_sim
	var held_n: int = server.net.held_count()
	e.net.request_leave()
	check(e.net.my_reconnect_token == "", "klient po odchodu zapomněl token")
	check(await wait_until(func(): return server.net.players.is_empty(), 4.0), "server hráče po žádosti o odchod odpojil")
	check(server.net.held_count() == held_n and not server.net.is_held(e_sim), "postava se pro návrat nedrží")
	check(_chat_has(server, "Eva opouští hru."), "odchod oznámen bez „ztráty spojení“")
	_drop("ClientE")

	section("Neznámý odesílatel: leave / resume mimo pořadí")
	var g := _client("ClientG", "Gama", "", "", true)
	check(await wait_until(func(): return g.net.my_sim != "" and g.net.my_reconnect_token != "", 6.0), "G připojen s HUD a tokenem")
	var rej0: int = server.net.stats["rejected"]
	g.net._c2s_resume.rpc_id(1, "X", Protocol.VERSION, g.net.my_reconnect_token, "")
	await wait_seconds(0.4)
	check(server.net.stats["rejected"] == rej0 + 1 and server.net.players[_peer_of(g)]["sim"] == g.net.my_sim, "resume po přivítání odmítnuto (jeden pokus na spojení)")

	section("HUD po výpadku nabídne návrat")
	var cfg: Dictionary = g.resume_config()
	check(cfg.get("reconnect_token", "") == g.net.my_reconnect_token and int(cfg.get("port", 0)) == port
		and String(cfg.get("address", "")) == "127.0.0.1" and String(cfg.get("mode", "")) == "client", "resume_config nese adresu, port a token")
	check(not g.reconnect(), "reconnect() v testovacím světě (net_config) scénu nepřenačítá")
	# Výpadek ze strany klienta (server zůstává) – signál disconnected stačí simulovat na klientu.
	g.net._on_server_disconnected()
	var btn = g.hud.get_node_or_null("ReconnectButton")
	check(btn != null and btn.visible and not btn.disabled, "HUD ukazuje tlačítko „Znovu připojit“")

	for bn in _holders.keys():
		_holders[bn].get_node("World").net.shutdown()
	finish("test_mp_reconnect")
