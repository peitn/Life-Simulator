extends "res://tests/test_base.gd"
## Test příkazů hráče (offline): fronta, přerušení, zrušení spánku, urážka a její následky,
## validace příkazů v NetSession a to, že AI si akci „jen pro hráče“ nevybere.

const Main := preload("res://main.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")

var world: Node3D
var clock: Node


func _ready() -> void:
	clock = get_node("/root/GameClock")
	clock.running = false
	world = Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(world)
	_run.call_deferred()


func _idx(tag: String) -> int:
	var objs: Array = world.get_smart_objects()
	for i in objs.size():
		if objs[i].object_tag == tag:
			return i
	return -1


func _run() -> void:
	var sims: Array = world.get_sims()
	section("Svět")
	check(sims.size() == 3, "offline spawn 3 postav", str(sims.size()))
	var jana = world.find_sim(SimAgent.node_name_for("Jana Nováková"))
	var petr = world.find_sim(SimAgent.node_name_for("Petr Dvořák"))
	check(jana != null and petr != null, "find_sim podle jména uzlu")
	var net = world.net

	section("Validace příkazů (handle_command)")
	check(net.handle_command(1, "Neexistuje", "watch_tv", _idx("tv")) != "", "neexistující postava odmítnuta")
	check(net.handle_command(1, jana.name, "teleport", "") != "", "neznámá akce odmítnuta")
	check(net.handle_command(1, jana.name, "watch_tv", 9999) != "", "index objektu mimo rozsah")
	check(net.handle_command(1, jana.name, "watch_tv", _idx("fridge")) != "", "objekt, který akci nenabízí")
	check(net.handle_command(1, jana.name, "watch_tv", "0") != "", "index jako String odmítnut")
	check(net.handle_command(1, jana.name, "chat", String(jana.name)) != "", "hovor sám se sebou odmítnut")
	check(net.handle_command(1, jana.name, "daydream", 3) != "", "akce bez cíle s cílem odmítnuta")
	check(net.handle_command(1, 42, "watch_tv", 0) != "", "jméno postavy jako int odmítnuto")
	var before: int = net.stats["rejected"]
	check(before >= 8, "počítadlo odmítnutí", str(before))

	section("Fronta a provedení")
	var log_lines: PackedStringArray = []
	jana.action_started.connect(func(_s, act): log_lines.append("start:" + String(act["id"])))
	jana.action_finished.connect(func(_s, id, intr): log_lines.append("end:" + id + ("!" if intr else "")))
	jana.memory_added.connect(func(_s, t): log_lines.append("mem:" + t))
	# Ostatní postavy „zmrazit“ (stojí a nic nezabírají), ať je pořadí deterministické.
	for s in sims:
		if s != jana:
			s.command({"id": "cancel"}, null)
			s.think_cooldown = 1.0e9
	var err: String = net.handle_command(1, jana.name, "watch_tv", _idx("tv"))
	check(err == "", "platný příkaz přijat", err)
	check(jana.state != SimAgent.State.IDLE and jana.current_action.get("id", "") == "watch_tv",
		"postava hned vyrazí k televizi", "%s %s" % [jana.state, jana.current_action.get("id", "")])
	net.handle_command(1, jana.name, "read", _idx("bookshelf"))
	net.handle_command(1, jana.name, "snack", _idx("fridge"))
	check(jana.player_queue.size() == 2, "další příkazy čekají ve frontě", str(jana.player_queue.size()))
	check(net.handle_command(1, jana.name, "cook", _idx("stove")) == "", "třetí příkaz do fronty")
	check(net.handle_command(1, jana.name, "relax", _idx("sofa")) != "", "plná fronta odmítne další")
	for i in 240:
		clock.advance(1.0)
		if jana.current_action.get("id", "") == "read":
			break
	check(jana.current_action.get("id", "") == "read", "po televizi přijde na řadu kniha", " ".join(log_lines))
	net.handle_command(1, jana.name, "cancel", "")
	check(jana.state == SimAgent.State.IDLE and jana.player_queue.is_empty(), "zrušení vyprázdní frontu i akci")

	section("Obsazený objekt")
	var shelf = world.get_smart_objects()[_idx("bookshelf")]
	shelf.reserve(petr)
	net.handle_command(1, jana.name, "read", _idx("bookshelf"))
	check(jana.state == SimAgent.State.IDLE and jana.mood.has_moodlet("obsazeno"), "obsazený objekt → příkaz propadne s moodletem Obsazeno")
	shelf.release(petr)
	for s in sims:
		if s != jana:
			s.think_cooldown = 0.0

	section("Spánek a probuzení")
	jana.needs.values["energy"] = 20.0
	net.handle_command(1, jana.name, "sleep", _idx("bed"))
	for i in 60:
		clock.advance(1.0)
		if jana.state == SimAgent.State.ACTING:
			break
	check(jana.current_action.get("id", "") == "sleep" and jana.state == SimAgent.State.ACTING, "postava usnula")
	net.handle_command(1, jana.name, "watch_tv", _idx("tv"))
	check(jana.current_action.get("id", "") == "sleep", "nepřerušitelný spánek příkaz nepřeruší (čeká ve frontě)")
	net.handle_command(1, jana.name, "cancel", "")
	check(jana.mood.has_moodlet("rozespaly"), "vzbuzení ze spánku → moodlet Rozespalý")
	for b in world.get_smart_objects():
		if b.object_tag == "bed":
			check(not b.users.has(jana), "postel po probuzení uvolněna")

	section("Urážka mezi postavami")
	jana.needs.values["energy"] = 80.0
	petr.command({"id": "cancel"}, null)
	var rel_before: float = float(petr.relationships.get(jana.sim_name, 0.0))
	var jana_rel_before: float = float(jana.relationships.get(petr.sim_name, 0.0))
	check(net.handle_command(1, jana.name, "insult", String(petr.name)) == "", "urážka přijata")
	var done := false
	for i in 120:
		clock.advance(1.0)
		if int(jana.action_counts.get("insult", 0)) > 0:
			done = true
			break
	check(done, "urážka proběhla")
	var rel_after: float = float(petr.relationships.get(jana.sim_name, 0.0))
	check(rel_after <= rel_before - 8.0, "vztah Petra k Janě výrazně klesl", "%.1f → %.1f" % [rel_before, rel_after])
	check(float(jana.relationships.get(petr.sim_name, 0.0)) < jana_rel_before, "vztah klesl oboustranně")
	check(petr.mood.has_moodlet("urazka_" + String(jana.name)), "uražený má moodlet Urážka")
	check(jana.mood.has_moodlet("vycitky_" + String(petr.name)) or jana.mood.has_moodlet("ulevil_" + String(petr.name)),
		"urážející má výčitky nebo úlevu podle povahy")
	var mem_ok := false
	for e in petr.memories:
		if String(e["text"]).find("urazil") >= 0:
			mem_ok = true
	check(mem_ok, "uražený si urážku pamatuje")
	check(jana.speech != "" or petr.speech != "", "v bublině je replika")

	section("Ochrana proti griefingu")
	for i in 30:
		clock.advance(1.0)
	petr.command({"id": "cancel"}, null)
	jana.command({"id": "cancel"}, null)
	var rel_mid: float = float(petr.relationships.get(jana.sim_name, 0.0))
	var petr_insults: int = int(petr.action_counts.get("chat", 0))
	net.handle_command(1, jana.name, "insult", String(petr.name))
	var ignored := false
	for i in 120:
		clock.advance(1.0)
		if petr.mood.has_moodlet("obtezuje_" + String(jana.name)):
			ignored = true
			break
	check(ignored, "opakovaná urážka do 2 h: oběť odejde, jen ji to otráví")
	check(int(petr.action_counts.get("chat", 0)) == petr_insults, "oběť nebyla znovu vtažena do hádky")
	var rel_end: float = float(petr.relationships.get(jana.sim_name, 0.0))
	check(rel_end < rel_mid and rel_end > rel_mid - 5.0, "vztah klesl jen mírně", "%.1f → %.1f" % [rel_mid, rel_end])
	for i in 30:
		clock.advance(1.0)
	petr.command({"id": "cancel"}, null)
	net.handle_command(1, petr.name, "watch_tv", _idx("tv"))
	check(petr.by_player and not petr.can_join_social(jana), "postavu plnící hráčův příkaz nikdo nepřeruší")
	var eli = world.find_sim(SimAgent.node_name_for("Eliška Malá"))
	eli.command({"id": "cancel"}, null)
	check(eli.can_join_social(jana), "postava pod AI pozvání k hovoru přijme")

	section("AI a akce jen pro hráče")
	var picked := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 300:
		var c: Dictionary = Planner.choose(petr, world.get_smart_objects(), world.get_sims(), rng, 14)
		if not c.is_empty() and c["action"]["id"] == "insult":
			picked += 1
	check(picked == 0, "plánovač nikdy nevybere urážku", str(picked))

	section("HUD data")
	var info: Dictionary = jana.hud_info()
	check(info.has("needs") and info["needs"].size() == 6 and info.has("rel") and info.has("mem"), "hud_info má potřeby, vztahy, vzpomínky")
	check(jana.net_needs.size() == 6 and jana.net_label != "", "replikované vlastnosti se plní")
	finish("test_player_commands")
