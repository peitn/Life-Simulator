extends "res://tests/test_base.gd"
## Soukromí následků zrady přes skutečné ENet spojení (server + 2 klienti v jednom procesu, každý
## s vlastním SceneMultiplayer, jako tests/test_multiplayer.gd).
## Ověřuje: rána vzniká jen na autoritě (server); vlastník (klient A) dostane jen slovní soukromý
## detail své postavy; druhý hráč (klient B) nedostane z cizí postavy nic soukromého – ani přes
## replikované vlastnosti loutek, ani přes _s2c_private; nikde nejsou čísla/uid rány.
## Spuštění: godot_run scene=res://tests/test_betrayal_privacy_enet.tscn

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")

var port := 0
var server: Node3D

## Značky, které se NIKDY nesmí objevit v ničem, co dostane cizí klient (a čísla rány ani vlastník).
const FORBIDDEN_ANY := ["\"acute\"", "\"scar\"", "\"processed\"", "betrayal", "bw_", "numb_until", "self_defectiveness"]
const FORBIDDEN_OTHER := ["Zrada", "Podvedl", "Jako by chyba", "Viděl", "Tajný románek"]


func _ready() -> void:
	watchdog_seconds = 60.0
	randomize()
	port = 25400 + randi() % 700
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
	return w


func _client(bname: String, player_name: String) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"audio": false, "hud": false, "camera": false, "visuals": false})


## Vše, co klient o loutce ví (veřejné vlastnosti + případný soukromý detail), jako jeden text.
static func _puppet_blob(p: Node) -> String:
	var parts := []
	for prop in ["sim_name", "net_label", "net_emotion", "net_mood", "net_posture", "net_action", "net_speech", "trait_ids", "look", "net_detail"]:
		parts.append(var_to_str(p.get(prop)))
	return "\n".join(parts)


static func _has_any(blob: String, needles: Array) -> String:
	for n in needles:
		if blob.find(String(n)) >= 0:
			return String(n)
	return ""


func _run() -> void:
	var clock := get_node("/root/GameClock")
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	print("Port: %d" % port)
	section("Server a dva hráči")
	server = _branch("Server", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	var a := _client("ClientA", "Anna")
	var b := _client("ClientB", "Bára")
	check(await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 6.0), "oba klienti mají postavu")
	check(await wait_until(func(): return a.get_sims().size() == 3 and b.get_sims().size() == 3, 4.0), "loutky replikovány")
	var sa = server.find_sim(a.net.my_sim)
	var sb = server.find_sim(b.net.my_sim)
	var sc = null
	for s in server.get_sims():
		if s != sa and s != sb:
			sc = s
	check(sa != null and sb != null and sc != null and sa.has_method("command"), "na serveru simulované postavy (A, B, AI)")
	if sa == null or sb == null or sc == null:
		finish("test_betrayal_privacy_enet")
		return
	var pa = a.find_sim(String(sa.name))
	var pb_of_a = b.find_sim(String(sa.name))
	check(pa != null and pb_of_a != null and not pa.has_method("command") and pa.get("psy") == null and pb_of_a.get("psy") == null,
		"klienti mají jen loutky bez psychiky")

	section("Zrada na autoritě")
	var ro = server.dynamics.romance
	ro.resolve_ask(String(sc.sim_name), String(sa.sim_name), sc.romance_profile(), sa.romance_profile(), 1.0, 0.0, clock.total_minutes)
	sa.on_betrayal(sc, sb, "caught")
	sa._detail_dirty = true
	check(not sa.psy.betrayal.is_empty() and String(sa.psy.betrayal.wounds[0]["about"]) == SimAgent.memory_key(sc),
		"rána vznikla na serveru (uid zrádce, nikdy jméno jako klíč)")
	var sc_uid: String = SimAgent.memory_key(sc)

	section("Vlastník dostane slovní soukromý detail")
	var got := await wait_until(func():
		return pa.has_private and var_to_str(pa.net_detail).find("Zrada pořád bolí") >= 0, 6.0)
	check(got, "klient A: moodlet „Zrada pořád bolí“ ve vlastním soukromém detailu")
	var own := var_to_str(pa.net_detail)
	check(_has_any(own, FORBIDDEN_ANY) == "" and own.find(sc_uid) < 0, "ani vlastník nedostane čísla ani uid rány (%s)" % _has_any(own, FORBIDDEN_ANY))

	section("Druhý hráč nic soukromého z cizí postavy")
	# Pár sekund provozu: server mezitím posílá soukromé stavy (PRIVATE_INTERVAL) a replikaci.
	await wait_seconds(1.5)
	check(not pb_of_a.has_private and pb_of_a.net_detail.is_empty(), "klient B: loutka postavy A bez soukromých dat")
	var leak := ""
	for p in b.get_sims():
		var blob := _puppet_blob(p)
		var hit := _has_any(blob, FORBIDDEN_ANY)
		if hit == "" and p != b.find_sim(String(sb.name)):
			hit = _has_any(blob, FORBIDDEN_OTHER)
		if hit == "" and blob.find(sc_uid) >= 0:
			hit = "uid"
		if hit != "":
			leak = "%s: %s" % [p.sim_name, hit]
	check(leak == "", "nic z rány v žádné loutce u klienta B (%s)" % leak)
	var own_b = b.find_sim(String(sb.name))
	check(own_b != null and var_to_str(own_b.net_detail).find("Zrada") < 0, "B jako milenka/milenec: vlastní detail bez cizí rány")
	var pub_a := ""
	for prop in ["net_label", "net_emotion", "net_action", "net_posture"]:
		pub_a += var_to_str(pb_of_a.get(prop))
	check(_has_any(pub_a, FORBIDDEN_ANY + FORBIDDEN_OTHER) == "", "veřejné vlastnosti postavy A nic neprozrazují")
	check(var_to_str(pa.net_detail).find("Podvedl") >= 0 or var_to_str(pa.net_detail).find("Zrada") >= 0, "(kontrola: A svá data opravdu má)")

	section("Server: soukromý stav jen vlastníkovi")
	var sent_to := []
	for pid in server.net.players:
		if String(server.net.players[pid].get("sim", "")) == String(sa.name):
			sent_to.append(pid)
	check(sent_to.size() == 1, "postavu A vlastní právě jeden peer")

	for w in [a, b, server]:
		w.net.shutdown()
	settings.reset()
	finish("test_betrayal_privacy_enet")
