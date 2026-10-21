extends "res://tests/test_base.gd"
## Test křivd, viny, omluvy a usmíření: křivda brzdí oteplování, vyprchává podle povahy,
## omluva má upřímnost odvozenou z chování (opakované omluvy, porušená omluva), spam omluv
## nikoho nezamkne, AI se omlouvá z viny (pýcha ji tlumí, cooldown), čas hojí jen bez živé
## křivdy, hráč může omluvu zadat i v multiplayeru a server odmítá systémové akce.

const Main := preload("res://main.gd")
const RelLedger := preload("res://scripts/sim/rel_ledger.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Traits := preload("res://scripts/sim/traits.gd")

var world: Node3D
var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 90.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	world = Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(world)
	_run.call_deferred()


func _run() -> void:
	_test_ledger()
	_test_apology_eval()
	await _test_in_world()
	finish("test_reconciliation")


# ---------------------------------------------------------------- kniha křivd

func _test_ledger() -> void:
	section("Křivdy a vina")
	var l := RelLedger.new()
	check(l.warmth_mult("Petr") == 1.0 and l.max_guilt() == 0.0, "výchozí stav: nic nevisí")
	l.on_hurt_by("Petr", 25.0, 100.0)
	check(l.grudge("Petr") == 25.0 and l.warmth_mult("Petr") < 0.85, "urážka = křivda, brzdí oteplování")
	l.on_hurt_other("Jana", 20.0)
	check(l.guilt_of("Jana") == 20.0 and l.max_guilt() == 20.0, "ublížení druhému = vina")
	var slow := RelLedger.new()
	var fast := RelLedger.new()
	slow.on_hurt_by("X", 40.0, 0.0)
	fast.on_hurt_by("X", 40.0, 0.0)
	for i in 72:
		slow.decay(60.0, 1.6, 1.0)
		fast.decay(60.0, 0.6, 1.0)
	check(slow.grudge("X") > fast.grudge("X") and fast.grudge("X") < 10.0, "zášť drží podle povahy (bručoun déle, optimista kratší)",
		"%.1f vs %.1f" % [slow.grudge("X"), fast.grudge("X")])
	var step_a := RelLedger.new()
	var step_b := RelLedger.new()
	step_a.on_hurt_by("X", 50.0, 0.0)
	step_b.on_hurt_by("X", 50.0, 0.0)
	for i in 1440:
		step_a.decay(1.0)
	for i in 720:
		step_b.decay(2.0)
	check(absf(step_a.grudge("X") - step_b.grudge("X")) < 0.01, "vyprchávání nezávisí na délce kroku (deterministické)")
	for i in 60:
		l.decay(1440.0)
	check(not l.grudges.has("Petr") and not l.guilt.has("Jana"), "po dlouhé době se drobné křivdy i vina vytratí (úklid)")
	l.on_hurt_by("Eli", 30.0, 0.0)
	l.soften("Eli", 3.0)
	check(is_equal_approx(l.grudge("Eli"), 27.0), "příjemný hovor křivdu pomalu obrušuje")
	var d := l.to_dict()
	var l2 := RelLedger.new()
	l2.from_dict(d)
	check(l2.grudge("Eli") == l.grudge("Eli"), "uložení a načtení zachová křivdy")
	l2.from_dict({"grudges": {"A": "nesmysl", "B": 500.0}, "apologies_from": {"C": "x"}, "broken": {"D": -3}})
	check(not l2.grudges.has("A") and l2.grudge("B") == 100.0 and not l2.apologies_from.has("C") and float(l2.broken.get("D", 0.0)) == 0.0,
		"poškozená data se ořežou / zahodí")


# ---------------------------------------------------------------- vyhodnocení omluvy

func _rate(l: RelLedger, who: String, now: float, rel: float, forg: float, stress: float) -> float:
	var acc := 0
	for i in 200:
		if l.evaluate_apology(who, now, rel, forg, stress, (i + 0.5) / 200.0)["outcome"] == "accepted":
			acc += 1
	return acc / 200.0


func _test_apology_eval() -> void:
	section("Vyhodnocení omluvy (upřímnost z chování)")
	var l := RelLedger.new()
	check(l.evaluate_apology("Petr", 100.0, 0.0, 0.0, 10.0, 0.5)["outcome"] == "none", "bez křivdy: „za co?“ (žádný efekt)")
	l.on_hurt_by("Petr", 30.0, 0.0)
	var soon := _rate(l, "Petr", 20.0, 0.0, 0.0, 10.0)
	var later := _rate(l, "Petr", 300.0, 0.0, 0.0, 10.0)
	check(soon < later * 0.6, "hned po křivdě („teď ne“) je šance menší", "%.2f vs %.2f" % [soon, later])
	check(_rate(l, "Petr", 300.0, 0.0, 0.12, 10.0) > later and _rate(l, "Petr", 300.0, 60.0, 0.0, 10.0) > later,
		"smířlivá povaha a dobrý vztah pomáhají")
	check(_rate(l, "Petr", 300.0, 0.0, 0.0, 90.0) < later, "ve stresu se odpouští hůř")
	var big := RelLedger.new()
	big.on_hurt_by("Petr", 90.0, 0.0)
	check(_rate(big, "Petr", 300.0, 0.0, 0.0, 10.0) < later, "větší křivda = těžší odpuštění")
	var r := l.evaluate_apology("Petr", 300.0, 0.0, 0.0, 10.0, 0.0)
	check(r["outcome"] == "accepted" and float(r["p"]) <= 0.95 and float(r["p"]) >= 0.03, "pravděpodobnost je vždy mezi 3 a 95 %")
	var g0 := l.grudge("Petr")
	l.receive_apology("Petr", "accepted", 300.0)
	check(l.grudge("Petr") < g0 * 0.5, "přijatá omluva křivdu výrazně zmenší", "%.1f → %.1f" % [g0, l.grudge("Petr")])
	check(l.evaluate_apology("Petr", 350.0, 0.0, 0.0, 10.0, 0.0)["outcome"] in ["spam", "none"], "další omluva do 2 h = otravování")
	# Upřímnost: opakované omluvy a porušená omluva.
	var s := RelLedger.new()
	s.on_hurt_by("Petr", 40.0, 0.0)
	var s_fresh := s.sincerity("Petr", 500.0)
	s.receive_apology("Petr", "partial", 500.0)
	s.on_hurt_by("Petr", 20.0, 900.0)  # po omluvě znovu ublížil
	check(float(s.broken.get("Petr", 0.0)) >= 1.0, "nové ublížení po omluvě = porušená omluva")
	var s_after := s.sincerity("Petr", 1200.0)
	check(s_after < s_fresh - 0.5, "porušená omluva a čerstvá omluva snižují upřímnost dalších", "%.2f → %.2f" % [s_fresh, s_after])
	for i in 15:
		s.decay(1440.0)
	check(s.sincerity("Petr", 1200.0 + 15 * 1440.0) > s_after, "po čase se důvěra pomalu vrací (nic není navždy)")
	var v := RelLedger.new()
	v.on_hurt_other("Jana", 40.0)
	v.apology_given("Jana", "rejected", 10.0)
	check(v.guilt_of("Jana") < 40.0 and v.guilt_of("Jana") > 25.0, "odmítnutá omluva: vina jen trochu poleví")
	v.apology_given("Jana", "accepted", 20.0)
	check(v.guilt_of("Jana") < 10.0 and v.apologized_to.has("Jana"), "přijatá omluva: vina opadne")


# ---------------------------------------------------------------- ve světě

func _reset(s) -> void:
	s.player_queue.clear()
	s.command({"id": "cancel"}, null)
	s.mental.stress = 10.0
	s.mental.arousal = 5.0
	s.think_cooldown = 1.0e9
	s.ledger = RelLedger.new()
	for k in s.needs.values:
		s.needs.values[k] = 80.0


func _wait_apology(s, max_min := 60) -> bool:
	s.last_apology = {}
	for i in max_min:
		clock.advance(1.0)
		if not s.last_apology.is_empty():
			return true
	return false


func _test_in_world() -> void:
	section("Ve světě: urážka → křivda → omluva")
	var jana = world.find_sim(SimAgent.node_name_for("Jana Nováková"))
	var petr = world.find_sim(SimAgent.node_name_for("Petr Dvořák"))
	var eli = world.find_sim(SimAgent.node_name_for("Eliška Malá"))
	var net = world.net
	for s in [jana, petr, eli]:
		_reset(s)
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(1.5, 0, 0)
	petr.global_position = Vector3(30, 0, 0)
	jana.relationships[eli.sim_name] = 20.0
	eli.relationships[jana.sim_name] = 20.0
	jana.mood.moodlets.clear()
	check(net.handle_command(1, jana.name, "insult", String(eli.name)) == "", "urážka přijata")
	for i in 30:
		clock.advance(1.0)
		if eli.ledger.grudge(jana.sim_name) > 0.0:
			break
	check(eli.ledger.grudge(jana.sim_name) >= 20.0, "oběť má křivdu", "%.1f" % eli.ledger.grudge(jana.sim_name))
	check(jana.ledger.guilt_of(eli.sim_name) >= 6.0, "útočník cítí vinu (bručoun v ráži méně)", "%.1f" % jana.ledger.guilt_of(eli.sim_name))
	check(eli.hud_info()["grudge"].has(jana.sim_name), "soukromý detail ukazuje „křivdu“ (bez čísla)")
	# Křivda brzdí oteplování: stejný příjemný hovor přidá méně.
	for s in [jana, eli]:
		s.last_talk.clear()
	var before: float = float(eli.relationships[jana.sim_name])
	jana._social_outcome(eli, 6.0, "chat")
	var with_grudge: float = float(eli.relationships[jana.sim_name]) - before
	var fresh := RelLedger.new()
	eli.ledger = fresh
	eli.last_talk.clear()
	jana.last_talk.clear()
	before = float(eli.relationships[jana.sim_name])
	jana._social_outcome(eli, 6.0, "chat")
	var without: float = float(eli.relationships[jana.sim_name]) - before
	check(with_grudge < without * 0.9, "s křivdou přidá hovor méně než bez ní", "%.2f vs %.2f" % [with_grudge, without])

	section("Omluva: přijetí a jeho následky")
	_reset(jana)
	_reset(eli)
	clock.advance(120.0)
	eli.ledger.on_hurt_by(jana.sim_name, 15.0, clock.total_minutes - 300.0)
	jana.ledger.on_hurt_other(eli.sim_name, 30.0)
	eli.relationships[jana.sim_name] = 70.0
	jana.relationships[eli.sim_name] = 60.0
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(1.5, 0, 0)
	eli.rng.seed = 1
	var accepted := false
	for attempt in 6:
		_reset(jana)
		_reset(eli)
		eli.ledger.on_hurt_by(jana.sim_name, 15.0, clock.total_minutes - 300.0)
		jana.ledger.on_hurt_other(eli.sim_name, 30.0)
		var r0: float = float(eli.relationships[jana.sim_name])
		var res: String = net.handle_command(1, jana.name, "apologize", String(eli.name))
		if attempt == 0:
			check(res == "", "omluva přijata serverem")
		if _wait_apology(jana) and jana.last_apology["outcome"] == "accepted":
			accepted = true
			check(float(eli.relationships[jana.sim_name]) > r0 and eli.ledger.grudge(jana.sim_name) < 5.0,
				"přijatá omluva: vztah nahoru, křivda skoro pryč")
			check(jana.ledger.guilt_of(eli.sim_name) < 10.0, "omlouvající se: vina opadne")
			check(jana.mood.has_moodlet("usmireni_" + String(eli.name)) and eli.mood.has_moodlet("usmireni_" + String(jana.name)),
				"oba: moodlet „Usmířili jsme se“")
			var mem := false
			for e in eli.memories:
				if String(e["text"]).find("Usmířila jsem se") >= 0:
					mem = true
			check(mem, "usmíření zůstane v paměti (s rodem)")
			break
		clock.advance(200.0)
	check(accepted, "s malou křivdou a dobrým vztahem je omluva obvykle přijata")
	clock.advance(30.0)
	check(net.handle_command(1, jana.name, "apologize", String(eli.name)) == "", "druhá omluva hned potom")
	var eli_action_before: String = String(eli.current_action.get("id", ""))
	_wait_apology(jana, 20)
	check(String(jana.last_apology.get("outcome", "")) in ["spam", "none"], "do 2 h po omluvě = otravování / „za co?“",
		str(jana.last_apology))
	if String(jana.last_apology.get("outcome", "")) == "spam":
		check(eli.social_partner != jana and String(eli.current_action.get("id", "")) == eli_action_before,
			"spam omluv oběť nepřeruší (nejde zamknout cizí postavu)")
		check(eli.mood.has_moodlet("otravuje_" + String(jana.name)), "oběť to jen otráví")

	section("Odmítnutí")
	_reset(jana)
	_reset(eli)
	clock.advance(300.0)
	var rejected := false
	for attempt in 8:
		eli.ledger.on_hurt_by(jana.sim_name, 95.0, clock.total_minutes - 5.0)
		eli.ledger.broken[jana.sim_name] = 3.0
		eli.relationships[jana.sim_name] = -80.0
		eli.mental.stress = 90.0
		jana.ledger.on_hurt_other(eli.sim_name, 40.0)
		net.handle_command(1, jana.name, "apologize", String(eli.name))
		if _wait_apology(jana) and jana.last_apology["outcome"] == "rejected":
			rejected = true
			check(float(jana.last_apology["p"]) <= 0.1, "velká křivda, hned po ní, porušené omluvy → šance minimální",
				"%.2f" % float(jana.last_apology["p"]))
			check(jana.mood.has_moodlet("odmitnuta_omluva_" + String(eli.name)), "odmítnutí bolí („Odmítnutá omluva“)")
			check(jana.ledger.guilt_of(eli.sim_name) > 20.0, "vina po odmítnutí zůstává")
			break
		clock.advance(150.0)
		_reset(jana)
		_reset(eli)
	check(rejected, "nepřijatelná omluva je odmítnuta")

	section("AI: omluva z viny, pýcha, cooldown")
	for s in [jana, petr, eli]:
		_reset(s)
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(2, 0, 0)
	petr.global_position = Vector3(-2, 0, 0)
	clock.advance(300.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var none_picks := 0
	for i in 200:
		var c: Dictionary = Planner.choose(jana, world.get_smart_objects(), world.get_sims(), rng, 14)
		if not c.is_empty() and c["action"]["id"] == "apologize":
			none_picks += 1
	check(none_picks == 0, "bez viny se AI neomlouvá")
	jana.ledger.on_hurt_other(eli.sim_name, 60.0)
	eli.ledger.on_hurt_by(jana.sim_name, 30.0, clock.total_minutes - 300.0)
	var picks := 0
	var wrong := 0
	for i in 300:
		var c: Dictionary = Planner.choose(jana, world.get_smart_objects(), world.get_sims(), rng, 14)
		if not c.is_empty() and c["action"]["id"] == "apologize":
			if c["target"] == eli:
				picks += 1
			else:
				wrong += 1
	check(picks > 20 and wrong == 0, "s vinou se AI omlouvá – a to tomu, komu ublížila", "%d / %d" % [picks, wrong])
	petr.ledger.on_hurt_other(eli.sim_name, 60.0)
	eli.ledger.on_hurt_by(petr.sim_name, 30.0, clock.total_minutes - 300.0)
	var sj: float = Planner.apology_score(jana, eli, 1.0, 0.0)
	var sp: float = Planner.apology_score(petr, eli, 1.0, 0.0)
	check(sp < sj * 0.6, "pyšný bručoun se omlouvá nerad", "%.1f vs %.1f" % [sp, sj])
	eli.ledger.hurt_at[jana.sim_name] = clock.total_minutes - 5.0
	check(Planner.apology_score(jana, eli, 1.0, 0.0) < sj * 0.3, "hned po konfliktu (ještě to vře) je omluva méně pravděpodobná")
	jana.ledger.apologized_to[eli.sim_name] = clock.total_minutes - 10.0
	check(Planner.apology_score(jana, eli, 1.0, 0.0) == 0.0, "AI se stejné postavě neomlouvá znovu do 12 h")
	jana.ledger.apologized_to[eli.sim_name] = clock.total_minutes - Planner.APOLOGY_COOLDOWN - 1.0
	eli.ledger.hurt_at[jana.sim_name] = clock.total_minutes - 300.0
	check(Planner.apology_score(jana, eli, 1.0, 0.0) > 0.0, "po cooldownu zase může")

	section("Čas hojí – ale jen bez živé křivdy")
	for s in [jana, petr, eli]:
		_reset(s)
	jana.relationships[eli.sim_name] = -60.0
	jana.relationships[petr.sim_name] = -60.0
	jana.ledger.on_hurt_by(petr.sim_name, 100.0, clock.total_minutes)
	jana._heal_relationships(1440.0 * 5)
	check(float(jana.relationships[eli.sim_name]) > -40.0, "záporný vztah bez křivdy se pomalu vrací k neutrálu",
		"%.1f" % float(jana.relationships[eli.sim_name]))
	check(float(jana.relationships[petr.sim_name]) == -60.0, "s živou křivdou se nic nehojí (proto má smysl se omluvit)")
	jana.relationships[eli.sim_name] = 50.0
	jana._heal_relationships(1440.0 * 5)
	check(float(jana.relationships[eli.sim_name]) == 50.0, "kladné vztahy se samy nemění")

	section("Omluva „za nic“ (bez křivdy) nikoho nepřeruší")
	for s in [jana, petr, eli]:
		_reset(s)
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(1.5, 0, 0)
	clock.advance(200.0)
	check(net.handle_command(1, jana.name, "apologize", String(eli.name)) == "", "omluva bez křivdy přijata serverem")
	_wait_apology(jana, 20)
	check(String(jana.last_apology.get("outcome", "")) == "none", "bez křivdy: výsledek „za co?“", str(jana.last_apology))
	check(eli.social_partner != jana and eli.state == SimAgent.State.IDLE,
		"omluva bez křivdy druhého nepřeruší (nejde tím zdržovat cizí postavu)")

	section("Server a obsah")
	check(net.handle_command(1, jana.name, "apologize", String(jana.name)) != "", "omluva sobě se odmítne")
	check(net.handle_command(1, jana.name, "apologize", "Neexistuje") != "", "neexistující cíl se odmítne")
	check(net.handle_command(1, jana.name, "apologize", 42) != "", "špatný typ cíle se odmítne")
	var lines_ok := true
	for k in ["apology", "apology_accept", "apology_partial", "apology_reject", "apology_spam", "apology_none"]:
		if ActionLibrary.LINES.get(k, []).is_empty():
			lines_ok = false
	check(lines_ok, "repliky pro všechny výsledky omluvy existují")
	check(Traits.mult_param(["brucoun"], "pride") < 1.0 and Traits.mult_param(["uzkostlivy"], "pride") > 1.0,
		"povahy mají pýchu / sklon omlouvat se")
	for s in [jana, petr, eli]:
		_reset(s)
		s.think_cooldown = 1.0
	await get_tree().process_frame
