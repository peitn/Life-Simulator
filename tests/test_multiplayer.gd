extends "res://tests/test_base.gd"
## Integrační test multiplayeru: dedikovaný server + klienti v JEDNOM procesu.
## Každý účastník má vlastní větev stromu s vlastním SceneMultiplayer
## (SceneTree.set_multiplayer), komunikuje se přes skutečné ENet spojení na localhostu.
## Ověřuje: spawn a replikaci postav, synchronizaci stavu a času, hlasování o rychlosti,
## chat (sanitizace, rate limit), anti-cheat (cizí postava, špatné typy, neplatné objekty,
## volání authority RPC klientem, opakované hello), pozdní připojení, diváka,
## odpojení klienta bez hello a odchod hráče.

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const Protocol := preload("res://scripts/net/net_protocol.gd")

var port := 0
var server: Node3D
var notices := {}  # jméno větve -> [texty]


func _ready() -> void:
	randomize()
	port = 24600 + randi() % 800
	_run.call_deferred()


func _branch(bname: String, cfg: Dictionary) -> Node3D:
	var holder := Node.new()
	holder.name = bname
	add_child(holder)
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


func _client(bname: String, player_name: String, hud := false, audio := false) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"audio": audio, "hud": hud, "camera": false, "visuals": false})


func _sim_on(w: Node3D, node_name: String) -> Node3D:
	return w.find_sim(node_name)


func _chat_has(w: Node3D, needle: String) -> bool:
	for e in w.net.chat_log:
		if String(e[1]).find(needle) >= 0:
			return true
	return false


func _count_chat(w: Node3D, prefix: String) -> int:
	var n := 0
	for e in w.net.chat_log:
		if String(e[1]).begins_with(prefix):
			n += 1
	return n


func _obj_index(w: Node3D, tag: String) -> int:
	var objs: Array = w.get_smart_objects()
	for i in objs.size():
		if objs[i].object_tag == tag:
			return i
	return -1


func _run() -> void:
	var clock := get_node("/root/GameClock")
	print("Port: %d" % port)

	section("Server")
	server = _branch("Server", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(server.net.mode == NetSession.Mode.DEDICATED, "dedikovaný server běží")
	check(server.get_sims().size() == 3, "server spawnul 3 postavy")
	check(server.get_sims()[0].has_method("command"), "na serveru jsou simulované postavy (SimAgent)")
	check(clock.speed_index == 0, "prázdný server stojí (rychlost 0)")

	section("Připojení dvou hráčů")
	var a := _client("ClientA", "Hráč", true, true)
	var b := _client("ClientB", "Hráč")
	var joined := await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 6.0)
	check(joined, "oba klienti přivítáni a mají postavu")
	check(a.net.my_name == "Hráč" and b.net.my_name == "Hráč 2", "duplicitní jméno dostalo příponu",
		"%s / %s" % [a.net.my_name, b.net.my_name])
	check(a.net.my_sim != b.net.my_sim, "každý hráč ovládá jinou postavu")
	var spawned := await wait_until(func(): return a.get_sims().size() == 3 and b.get_sims().size() == 3, 4.0)
	check(spawned, "klienti dostali 3 replikované postavy", "%d/%d" % [a.get_sims().size(), b.get_sims().size()])
	var names_ok := true
	for s in server.get_sims():
		var p := _sim_on(a, String(s.name))
		if p == null or p.has_method("command") or p.sim_name != s.sim_name:
			names_ok = false
	check(names_ok, "na klientu jsou loutky (SimPuppet) se stejnými jmény")
	check(server.net.players.size() == 2, "server eviduje 2 hráče")
	check(await wait_until(func(): return a.net.roster.size() == 2, 2.0), "seznam hráčů dorazil klientům")
	check(await wait_until(func(): return clock.speed_index == 1, 2.0), "po připojení hráčů čas běží (hlasy 1)")

	section("Hlasování o rychlosti")
	a.net.request_speed(4)
	b.net.request_speed(4)
	check(await wait_until(func(): return clock.speed_index == 4, 2.0), "oba chtějí Ultra → Ultra")
	a.net.request_speed(0)
	check(await wait_until(func(): return clock.speed_index == 0, 2.0), "jeden pauzne → pauza pro všechny")
	# Reálný čas: na přetíženém hostiteli trvá doručení stavu hodin klientům déle (běh 21 a 23: občasný flake při 2 s).
	check(await wait_until(func(): return a.clock.speed_index == 0 and b.clock.speed_index == 0, 5.0), "klientské hodiny převzaly pauzu",
		"klienti %d/%d, server %d, synchronizací %d/%d" % [a.clock.speed_index, b.clock.speed_index, clock.speed_index,
		int(a.net.stats.get("clock_syncs", -1)), int(b.net.stats.get("clock_syncs", -1))])
	a.net.request_speed(3)
	check(await wait_until(func(): return clock.speed_index == 3, 2.0), "remíza hlasů 3 vs 4 → pomalejší (3)")
	await wait_seconds(2.5)

	section("Nouzová pauza")
	server.net.emergency_pause_seconds = 1.5
	b.net.request_emergency_pause()
	check(await wait_until(func(): return clock.speed_index == 0, 2.0), "nouzová pauza zastaví čas i proti hlasům")
	check(await wait_until(func(): return _chat_has(a, "nouzová pauza"), 2.0), "ostatní vidí, kdo pauzu spustil")
	b.net.request_emergency_pause()
	check(await wait_until(func(): return notices["ClientB"].size() > 0, 2.0), "opakovaná nouzová pauza je v cooldownu")
	check(await wait_until(func(): return clock.speed_index == 3, 4.0), "po skončení pauzy se vrátí hlasovaná rychlost")
	await wait_seconds(1.0)

	section("Synchronizace stavu")
	a.net.request_speed(0)
	await wait_until(func(): return clock.speed_index == 0, 2.0)
	await wait_seconds(0.6)
	var max_d := 0.0
	var labels_ok := true
	var needs_ok := true
	var privacy_ok := true
	for s in server.get_sims():
		var p := _sim_on(a, String(s.name))
		if p == null:
			labels_ok = false
			continue
		max_d = maxf(max_d, p.net_pos.distance_to(s.position))
		if p.net_label != s.display_action():
			labels_ok = false
		if String(s.name) == a.net.my_sim:
			if p.net_needs != s.net_needs:
				needs_ok = false
		elif p.has_private or not p.net_detail.is_empty() or p.net_needs.size() > 0:
			privacy_ok = false
	check(max_d < 0.05, "pozice loutek odpovídají serveru", "max odchylka %.3f m" % max_d)
	check(labels_ok, "popisky akcí odpovídají serveru")
	check(needs_ok, "potřeby vlastní postavy odpovídají serveru (privátní RPC)")
	check(privacy_ok, "cizí postavy nemají na klientu soukromá data (potřeby, vztahy, vzpomínky)")
	check(absf(a.clock.total_minutes - clock.total_minutes) < 1.5, "čas klienta odpovídá serveru",
		"%.1f vs %.1f" % [a.clock.total_minutes, clock.total_minutes])
	check(clock.total_minutes > 8.0 * 60.0 + 10.0, "simulace na serveru běžela", "%.0f min" % clock.total_minutes)
	var info: Dictionary = _sim_on(a, a.net.my_sim).hud_info()
	check(info.get("needs", {}).size() == 6 and info.has("traits") and info.has("rel") and bool(info.get("private", false)), "hud_info vlastní loutky obsahuje soukromý detail")
	check(a.hud != null and a.hud._name_label.text != "", "HUD klienta vykresluje postavu", a.hud._name_label.text if a.hud != null else "")
	# Duševní stav: vlastník ho vidí (soukromý detail), ostatní ne; predispozice se neposílá ve spawnu.
	check(info.has("mind") and String(info["mind"].get("label", "")) != "", "vlastní loutka má duševní stav v soukromém detailu")
	var mind_leak := false
	for s2 in server.get_sims():
		if String(s2.name) == a.net.my_sim:
			continue
		var p2 := _sim_on(a, String(s2.name))
		if p2 != null and (p2.hud_info().has("mind") or "mental" in p2):
			mind_leak = true
	check(not mind_leak, "cizí duševní stav (ani diagnóza) se ke klientovi nedostane")
	var rej_mh: int = server.net.stats["rejected"]
	a.net.request_command(a.net.my_sim, "panic", "")
	a.net.request_command(a.net.my_sim, "comfort_panic", b.net.my_sim)
	check(await wait_until(func(): return server.net.stats["rejected"] >= rej_mh + 2, 2.0), "klient nemůže vyvolat ataku ani uklidňovat postavu bez ataky")

	section("Chat")
	var rlo := String.chr(0x202E)
	a.net.send_chat("Ahoj [b]všichni[/b]" + rlo + " !")
	check(await wait_until(func(): return _chat_has(b, "Ahoj"), 2.0), "zpráva od A dorazila k B")
	check(_chat_has(b, "Ahoj (b)všichni(/b) !"), "zpráva je sanitizovaná (BBCode, bidi)")
	check(_chat_has(server, "Ahoj"), "server má zprávu v logu")
	await wait_seconds(2.1)
	a.net.send_chat("x".repeat(500))
	check(await wait_until(func(): return _chat_has(b, "x".repeat(200)), 2.0), "dlouhá zpráva oříznutá na 200 znaků")
	var too_long := false
	for e in b.net.chat_log:
		if String(e[1]).length() > Protocol.MAX_CHAT_LEN:
			too_long = true
	check(not too_long, "žádná zpráva delší než limit")
	for i in 12:
		a.net.send_chat("spam %d" % i)
	await wait_seconds(0.8)
	var spam := _count_chat(b, "spam ")
	check(spam > 0 and spam < 12, "rate limit chatu zastavil spam", "%d/12 prošlo" % spam)
	check(server.net.stats["chat_blocked"] > 0, "server počítá zablokované zprávy")
	check(notices["ClientA"].size() > 0, "spammer dostal upozornění")

	section("Anti-cheat")
	var rej0: int = server.net.stats["rejected"]
	a.net.request_command(b.net.my_sim, "watch_tv", _obj_index(a, "tv"))
	await wait_seconds(0.4)
	check(server.net.stats["rejected"] > rej0, "příkaz pro cizí postavu odmítnut")
	check(notices["ClientA"].has("Tahle postava ti nepatří."), "klient dostal důvod odmítnutí")
	var rej1: int = server.net.stats["rejected"]
	a.net.request_command(a.net.my_sim, "watch_tv", 999)
	a.net._c2s_command.rpc_id(1, 123, "watch_tv", 0)
	a.net._c2s_command.rpc_id(1, a.net.my_sim, "watch_tv", Vector3.ONE)
	a.net._c2s_command.rpc_id(1, a.net.my_sim, "x".repeat(5000), 0)
	a.net._c2s_speed_vote.rpc_id(1, 99)
	a.net._c2s_speed_vote.rpc_id(1, "4")
	a.net._c2s_hello.rpc_id(1, "Podvodník", Protocol.VERSION, "")
	await wait_seconds(0.5)
	check(server.net.stats["rejected"] >= rej1 + 7, "neplatná data (index, typy, délka, hlas, opakované hello) odmítnuta",
		"%d nových" % (server.net.stats["rejected"] - rej1))
	check(clock.speed_index == 0, "neplatný hlas rychlost nezměnil")
	check(server.net.players[a.multiplayer.get_unique_id()]["name"] == "Hráč", "opakované hello nepřejmenovalo hráče")
	# Klient se pokusí zavolat RPC vyhrazené serveru – Godot ho na serveru zahodí.
	a.net._s2c_chat.rpc("Server", "FALEŠNÁ SYSTÉMOVÁ ZPRÁVA", true)
	a.net._s2c_clock.rpc(99999.0, 4)
	await wait_seconds(0.5)
	check(not _chat_has(b, "FALEŠNÁ") and not _chat_has(server, "FALEŠNÁ"), "klient nemůže poslat zprávu za server")
	check(clock.total_minutes < 99000.0 and clock.speed_index == 0, "klient nemůže posunout serverový čas")
	check((server.multiplayer as SceneMultiplayer).server_relay == false, "server nepřeposílá pakety mezi klienty (server_relay vypnutý)")

	section("Příkazy hráče přes síť")
	var my_server_sim := _sim_on(server, a.net.my_sim)
	var tv := _obj_index(a, "tv")
	a.net.request_command(a.net.my_sim, "watch_tv", tv)
	var cmd_ok := await wait_until(func(): return my_server_sim.current_action.get("id", "") == "watch_tv", 2.0)
	check(cmd_ok, "platný příkaz provedla serverová postava", str(my_server_sim.current_action.get("id", "")))
	a.net.request_speed(1)
	b.net.request_speed(1)
	var my_puppet := _sim_on(b, a.net.my_sim)
	check(await wait_until(func(): return my_puppet.net_label.to_lower().find("televiz") >= 0, 3.0),
		"ostatní hráči vidí akci (popisek loutky)", my_puppet.net_label)
	a.net.request_command(a.net.my_sim, "cancel", "")
	check(await wait_until(func(): return my_server_sim.current_action.get("id", "") != "watch_tv", 2.0), "zrušení akce přes síť")

	section("Konflikt mezi hráči (urážka)")
	var target_sim := _sim_on(server, b.net.my_sim)
	var rel0: float = float(target_sim.relationships.get(my_server_sim.sim_name, 0.0))
	a.net.request_speed(2)
	b.net.request_speed(2)
	var insulted := false
	for attempt in 4:
		a.net.request_command(a.net.my_sim, "insult", b.net.my_sim)
		insulted = await wait_until(func(): return int(my_server_sim.action_counts.get("insult", 0)) > 0, 3.0)
		if insulted:
			break
	check(insulted, "urážka mezi postavami hráčů proběhla")
	var rel1: float = float(target_sim.relationships.get(my_server_sim.sim_name, 0.0))
	check(rel1 <= rel0 - 8.0, "vztah oběti k útočníkovi klesl", "%.1f → %.1f" % [rel0, rel1])
	check(await wait_until(func(): return int(_sim_on(b, b.net.my_sim).net_detail.get("rel", {}).get(my_server_sim.sim_name, 0)) <= int(rel1) + 1, 3.0),
		"klient oběti vidí zhoršený vztah v detailu")
	var audio_events := 0
	for p in a.get_sims():
		audio_events += int(p.stats["actions_started"])
	check(audio_events > 0, "loutky na klientu vysílají akce (pro 3D zvuky)", str(audio_events))

	section("Pozdní připojení a divák")
	var c := _client("ClientC", "Cecílie")
	check(await wait_until(func(): return c.net.my_sim != "" and c.get_sims().size() == 3, 5.0),
		"pozdě připojený hráč dostal všechny postavy a třetí volnou postavu")
	var d := _client("ClientD", "Divák")
	check(await wait_until(func(): return d.net.roster.size() == 4 and d.get_sims().size() == 3, 5.0), "čtvrtý hráč připojen")
	check(d.net.my_sim == "", "čtvrtý hráč je divák (postavy obsazené)")
	var rej2: int = server.net.stats["rejected"]
	d.net.request_command(c.net.my_sim, "watch_tv", tv)
	await wait_seconds(0.4)
	check(server.net.stats["rejected"] > rej2, "divák nemůže ovládat cizí postavu")

	section("Klient bez představení (timeout hello)")
	var silent := Node.new()
	silent.name = "Silent"
	add_child(silent)
	var smp := SceneMultiplayer.new()
	get_tree().set_multiplayer(smp, silent.get_path())
	var raw := ENetMultiplayerPeer.new()
	raw.create_client("127.0.0.1", port)
	smp.multiplayer_peer = raw
	check(await wait_until(func(): return server.net.pending.size() == 1, 3.0), "server eviduje nepředstaveného klienta")
	var silent_id: int = server.net.pending.keys()[0] if server.net.pending.size() > 0 else -1
	check(silent_id > 0 and not server.net._is_visible_to(silent_id), "filtr viditelnosti skryje postavy před nepředstaveným klientem")
	check(silent.get_child_count() == 0, "nepředstavenému klientovi nic nespawnulo")
	check(await wait_until(func(): return server.net.pending.is_empty() and server.net.stats["kicked"] >= 1, Protocol.HELLO_TIMEOUT + 3.0),
		"nepředstavený klient odpojen po %.0f s" % Protocol.HELLO_TIMEOUT)
	check(server.net.players.size() == 4, "odpojení nepředstaveného klienta neovlivnilo hráče")

	section("Odchod hráče")
	var b_sim: String = b.net.my_sim
	b.net.shutdown()
	check(await wait_until(func(): return server.net.players.size() == 3, 3.0), "server odebral odpojeného hráče")
	check(await wait_until(func(): return _chat_has(a, "opouští hru"), 2.0), "ostatní dostali systémovou zprávu")
	check(await wait_until(func(): return a.net.roster.size() == 3, 2.0), "seznam hráčů aktualizován")
	check(server.find_sim(b_sim) != null, "postava odpojeného hráče zůstává ve světě (řídí ji AI)")

	# úklid
	for w in [a, c, d, server]:
		w.net.shutdown()
	smp.multiplayer_peer = OfflineMultiplayerPeer.new()
	finish("test_multiplayer")
