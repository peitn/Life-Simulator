extends "res://tests/test_base.gd"
## MP test tvorby postavy (C1): klient vstoupí s vlastní postavou (sdílecí kód v hello),
## server ji striktně validuje a spawne; veřejný snapshot se replikuje všem a vzhled je na všech
## peerech deterministicky stejný; soukromé části (identita, orientace, příběh, predispozice)
## se k jiným klientům nedostanou; nevalidní postava je odmítnuta s důvodem; nastavení obsahu
## serveru citlivé údaje nepřijme; po odchodu hráče jeho postava zmizí všem.
## Server a klienti běží v jednom procesu přes skutečné ENet (stejně jako test_multiplayer).

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")

var port := 0
var server: Node3D
var notices := {}


func _ready() -> void:
	watchdog_seconds = 90.0
	randomize()
	port = 25500 + randi() % 800
	var gs := get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
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


func _client(bname: String, player_name: String, code := "") -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"character": code, "audio": false, "hud": false, "camera": false, "visuals": false})


func _char(seed: int, extra := {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var d := Randomizer.generate(r)
	for g in extra:
		d[g].merge(extra[g], true)
	var v := Validator.validate(d)
	return v["data"]


func _notice_has(bname: String, needle: String) -> bool:
	for t in notices[bname]:
		if String(t).find(needle) >= 0:
			return true
	return false


func _run() -> void:
	var clock := get_node("/root/GameClock")
	section("Server")
	server = _branch("Server", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(server.get_sims().size() == 3, "server: domácnost (3 postavy z CharacterData)")

	section("Vstup s vlastní postavou")
	var mine := _char(501, {"identity": {"first_name": "Robin", "last_name": "Kovalenko", "grammar": "pl",
		"gender_identity": "nebinarni", "attracted_to": ["zeny"]},
		"story": {"backstory": "Tajná minulost"}, "mind": {"predispositions": {"anxiety": 0.5}, "traumas": ["nehoda"]}})
	var code := Codec.encode_code(mine)
	var a := _client("ClientA", "Alfa", code)
	var b := _client("ClientB", "Beta")
	var joined := await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 6.0)
	check(joined, "oba klienti přivítáni")
	check(server.get_sims().size() == 4 and server.net.stats["characters_spawned"] == 1, "server spawnul vlastní postavu A (4 postavy)")
	var s_own = server.find_sim(a.net.my_sim)
	check(s_own != null and s_own.sim_name == "Robin Kovalenko" and s_own.grammar == "pl", "A ovládá svou postavu (jméno, rod „oni“)",
		a.net.my_sim)
	check(String(b.net.my_sim) != String(a.net.my_sim) and not String(b.net.my_sim).begins_with("Hrac"),
		"B bez kódu převzal postavu domácnosti")
	if s_own == null:
		finish("test_character_net")
		return
	check(s_own.mental.conditions.get("anxiety", 0.0) == 0.5, "soukromé predispozice nastavené na serveru")
	var suid := String(s_own.get_meta("character_uid", ""))
	check(suid.length() == 32 and suid != String(mine["uid"]), "server klientovo uid zahodil a přidělil vlastní 128bit (review ChatGPT 48)")
	var rep := await wait_until(func(): return a.get_sims().size() == 4 and b.get_sims().size() == 4, 4.0)
	check(rep, "obě strany vidí 4 postavy")
	var pa = a.find_sim(a.net.my_sim)
	var pb = b.find_sim(a.net.my_sim)
	check(pa != null and pb != null, "loutky vlastní postavy na obou klientech")
	if pa == null or pb == null:
		finish("test_character_net")
		return
	var rs := Resolver.resolve(s_own.look)
	check(Resolver.resolve(pa.look) == rs and Resolver.resolve(pb.look) == rs, "vzhled je na serveru i obou klientech bit po bitu stejný")
	check(pb.visual != null and pb.visual.skin_color == s_own.visual.skin_color and pb.visual.look_params == s_own.visual.look_params,
		"vykreslené parametry (kůže, proporce, varianty) shodné")
	check(pb.grammar == "pl" and pb.sim_name == "Robin Kovalenko", "ostatní znají jméno a rod (oslovení)")
	var leak := JSON.stringify(pb.look)
	var leaks := PackedStringArray()
	for needle in ["nebinarni", "gender_identity", "attracted_to", "Tajná", "backstory", "anxiety", "predispositions",
			"nehoda", "traumas", "uid", "aspirations"]:
		if leak.find(needle) >= 0:
			leaks.append(needle)
	check(leaks.is_empty(), "k cizímu klientovi se nedostala identita, orientace, příběh, predispozice ani uid", ", ".join(leaks))
	check(not pb.has_private, "cizí klient nemá soukromý stav postavy A")
	# Spawn data na serveru (to, co jde po síti) neobsahují soukromé skupiny.
	var spawn_json := JSON.stringify(s_own.look)
	check(spawn_json.find("predispositions") < 0 and spawn_json.find("Tajná") < 0, "spawn data obsahují jen veřejný snapshot")


	section("H2b staged Apply through production hello/spawn/controller")
	# Explicitly enabled only inside this fixture; production default remains false.
	check(not server.net.character_edit_apply_rpc_enabled, "production Apply defaults disabled")
	server.net.character_edit_apply_rpc_enabled = true
	a.net.character_edit_apply_rpc_enabled = true
	b.net.character_edit_apply_rpc_enabled = true
	var replies_a: Array = []
	var replies_b: Array = []
	a.net.character_edit_apply_result.connect(func(key, accepted, revision, changed, reason):
		replies_a.append({"key":key,"ok":accepted,"revision":revision,"changed":changed,"reason":reason}))
	b.net.character_edit_apply_result.connect(func(key, accepted, revision, changed, reason):
		replies_b.append({"key":key,"ok":accepted,"revision":revision,"changed":changed,"reason":reason}))
	clock.running = false
	var edit_key: String = a.net.my_sim
	var original: Dictionary = server._character_records[edit_key].to_dict()
	var edited: Dictionary = original.duplicate(true)
	edited["body"]["height_cm"] = 179.0
	edited["personality"]["trait_levels"] = {"optimista":0.49,"brucoun":0.51}
	edited["mind"]["dispositions"]["hypervigilance"] = 0.64
	edited["mind"]["dispositions"]["rejection_reactivity"] = 0.73
	var old_revision: int = server._character_revisions[edit_key]
	s_own.mental.sensitivity = 0.91
	var saved_rng = s_own.rng.state
	var saved_needs = s_own.needs.values.duplicate(true)
	check(a.net.request_character_edit_apply(old_revision,edited), "real owner sends Apply")
	check(await wait_until(func(): return replies_a.size()==1,3.0), "production controller returns private acknowledgement")
	check(replies_a.size()==1 and replies_a[0]["ok"] and replies_a[0]["revision"]==old_revision+1,
		"production commit accepted exactly one revision")
	check(replies_b.is_empty(), "other gameplay client receives no private Apply acknowledgement")
	check(server._character_records[edit_key].body["height_cm"]==179.0 and s_own.look["body"]["height_cm"]==179.0,
		"real canonical record and SimAgent appearance updated")
	check(s_own.mental.sensitivity==0.91 and s_own.rng.state==saved_rng and s_own.needs.values==saved_needs,
		"production Apply preserves adaptation RNG and needs")
	var public_wire := JSON.stringify(s_own.look)
	check(not public_wire.contains("trait_levels") and not public_wire.contains("hypervigilance") and
		not public_wire.contains("rejection_reactivity") and not public_wire.contains("Tajná"),
		"new private axes and history excluded from post-Apply public snapshot")
	a.net.request_character_edit_apply(old_revision,edited)
	check(await wait_until(func(): return replies_a.size()==2,3.0), "stale request gets owner-only response")
	check(replies_a.size()==2 and not replies_a[1]["ok"] and replies_a[1]["reason"]=="conflict",
		"production controller rejects stale replay")
	var assigned_b: String = b.net.my_sim
	b.net.my_sim = edit_key
	b.net.request_character_edit_apply(old_revision+1,edited)
	await wait_seconds(0.25)
	check(replies_b.is_empty() and server._character_revisions[edit_key]==old_revision+1,
		"household peer cannot impersonate owner or alter revision")
	b.net.my_sim = assigned_b
	# Verify fresh private read after commit via real transport, not direct fixture access.
	var snapshots: Array = []
	a.net.character_edit_snapshot.connect(func(key,data,revision): snapshots.append({"key":key,"data":data,"revision":revision}))
	a.net.request_character_edit_snapshot()
	check(await wait_until(func(): return snapshots.size()==1,3.0), "owner reads committed snapshot")
	check(snapshots.size()==1 and snapshots[0]["revision"]==old_revision+1 and
		snapshots[0]["data"]["mind"]["dispositions"]["rejection_reactivity"]==0.73,
		"private committed axes returned only through owner read")

	# Owner may edit private dispositions, but cannot bypass strict server bounds.
	server.net._edit_limiters.clear()
	var invalid_axes: Dictionary = server._character_records[edit_key].to_dict()
	invalid_axes["mind"]["dispositions"]["rejection_reactivity"] = 9.0
	a.net.request_character_edit_apply(old_revision+1,invalid_axes)
	check(await wait_until(func(): return replies_a.size()==3,3.0), "invalid axis receives bounded response")
	check(replies_a.size()==3 and not replies_a[2]["ok"] and replies_a[2]["reason"]=="invalid_character",
		"production validator rejects out-of-range private axis")
	check(server._character_revisions[edit_key]==old_revision+1 and
		server._character_records[edit_key].mind["dispositions"]["rejection_reactivity"]==0.73,
		"rejected private-axis edit preserves data and revision")

	# Public change replication is the next implementation unit, not claimed here.
	print("H2B_PUBLIC_REPLICATION_CURRENT=",pa.look==s_own.look and pb.look==s_own.look)
	server.net.character_edit_apply_rpc_enabled = false
	a.net.character_edit_apply_rpc_enabled = false
	b.net.character_edit_apply_rpc_enabled = false

	section("Odmítnutí nevalidní postavy")
	var bad := _char(502)
	bad["identity"]["first_name"] = "Rob\u202Ein"
	var bad_code := Codec.encode_code(bad)
	var c := _client("ClientC", "Gama", bad_code)
	var kicked := await wait_until(func(): return _notice_has("ClientC", "Server odmítl postavu"), 5.0)
	check(kicked, "server odmítl postavu s bidi znakem ve jméně (klient dostal důvod)", str(notices["ClientC"]))
	check(server.net.stats["characters_rejected"] >= 1 and server.net.last_character_error.find("first_name") >= 0,
		"server eviduje důvod", server.net.last_character_error)
	await wait_seconds(0.3)
	check(server.net.players.size() == 2 and server.get_sims().size() == 4, "odmítnutý klient nic nespawnul a není hráčem")
	var minor := _char(503)
	minor["body"]["age"] = 16
	var d2 := _client("ClientD", "Delta", Codec.encode_code(minor))
	check(await wait_until(func(): return _notice_has("ClientD", "Server odmítl postavu"), 5.0), "nezletilá postava odmítnuta")
	var tamper := code.substr(0, code.length() - 8) + "deadbeef"
	var e := _client("ClientE", "Epsilon", tamper)
	check(await wait_until(func(): return _notice_has("ClientE", "kontrolní součet"), 5.0), "podvržený kód (CRC) odmítnut",
		str(notices["ClientE"]))
	var huge := "LSC1." + "A".repeat(9000) + ".00000000"
	var f := _client("ClientF", "Fí", huge)
	check(await wait_until(func(): return _notice_has("ClientF", "příliš dlouhý"), 5.0), "příliš dlouhý kód odmítnut")
	check(server.net.players.size() == 2, "hráči beze změny")

	section("Nastavení obsahu serveru")
	var gs := get_node("/root/GameSettings")
	gs.set_value("mental_health", "off", false)
	var with_mind := _char(504, {"identity": {"first_name": "Mia"}, "mind": {"predispositions": {"depression": 0.6}}})
	var g := _client("ClientG", "Gáma", Codec.encode_code(with_mind))
	check(await wait_until(func(): return g.net.my_sim != "", 5.0), "s vypnutými tématy se postava přijme (citlivé údaje se jen nepoužijí)")
	var s_g = server.find_sim(g.net.my_sim)
	check(s_g != null and s_g.mental.conditions.is_empty(), "server predispozice nepřevzal")
	gs.set_value("mental_health", "full", false)

	section("Odchod hráče s vlastní postavou")
	var own_name: String = a.net.my_sim
	a.net.shutdown()
	var gone := await wait_until(func(): return server.find_sim(own_name) == null and b.find_sim(own_name) == null, 5.0)
	check(gone, "postava odpojeného hráče zmizela ze serveru i u ostatních")
	check(server.get_sims().size() == 4 and server.net.players.size() == 2, "zůstala domácnost + postava G, 2 hráči")
	var s_b = server.find_sim(b.net.my_sim)
	var b_id := -1
	for k in server.net.players:
		if server.net.players[k]["sim"] == b.net.my_sim:
			b_id = k
	check(s_b != null and b_id > 0 and server.net.handle_command(b_id, b.net.my_sim, "cancel", "") == "",
		"hra pokračuje (B dál ovládá svou postavu)")
	check(not server.net.players.values().any(func(p): return p["sim"] == own_name), "nikdo neovládá zmizelou postavu")
	for w in [b, g, c, d2, e, f]:
		w.net.shutdown()
	server.net.shutdown()
	await get_tree().process_frame
	finish("test_character_net")
