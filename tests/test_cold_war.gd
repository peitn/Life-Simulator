extends "res://tests/test_base.gd"
## ColdWar (scripts/sim/cold_war.gd): dusno / studená válka dvojice v domácnosti.
## Spuštění: godot_run scene=res://tests/test_cold_war.tscn
##   bez argumentů: jednotky + scéna + uložení + příkaz hráče (rychlé)
##   -- --soak: 3 seedy × 10 dní, statistiky a determinismus (pomalejší)
const ColdWar := preload("res://scripts/sim/cold_war.gd")
const Main := preload("res://main.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
var clock: Node


func _ready() -> void:
	watchdog_seconds = 110.0
	clock = get_node("/root/GameClock")
	clock.running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	if "--soak" in OS.get_cmdline_user_args():
		await _soak()
	else:
		_units()
		_fuzz()
		await _scene()
	clock.running = false
	finish("test_cold_war")


# ------------------------------------------------------------------ jednotky
func _units() -> void:
	section("Stavový automat")
	var cw = ColdWar.new()
	check(cw.note("A", "B", "argue", 100.0) == 0, "jedna hádka = nic")
	check(cw.note("B", "A", "argue", 200.0) == 1, "druhá hádka (kterýkoli směr) = dusno")
	check(cw.note("A", "B", "argue", 300.0) == 2, "třetí hádka v 48 h = studená válka")
	check(cw.stats["entered_tense"] == 1 and cw.stats["entered_cold"] == 1, "statistiky vstupů")
	check(ColdWar.key("B", "A") == ColdWar.key("A", "B"), "klíč dvojice nezávisí na pořadí")

	var w = ColdWar.new()
	w.note("A", "B", "argue", 0.0)
	w.decay(3000.0, 3000.0)
	w.note("A", "B", "argue", 3000.0)  # mimo okno 48 h
	check(w.stage("A", "B") == 0, "hádky dál než 48 h od sebe spirálu nespustí")
	w.note("A", "B", "argue", 3100.0)
	check(w.stage("A", "B") == 1, "…ale dvě v okně ano (dusno, ne rovnou studená válka; žár %.2f)" % w.heat("A", "B"))
	var w2 = ColdWar.new()
	for i in 2:
		w2.note("A", "B", "argue", float(i))
	w2.pairs[ColdWar.key("A", "B")]["stage"] = 0
	w2.pairs[ColdWar.key("A", "B")]["heat"] = 0.9
	check(w2._update(w2.pairs[ColdWar.key("A", "B")], 3.0) == 1, "eskalace po stupních: z ničeho přes žár nejvýš do dusna")

	var h = ColdWar.new()
	h.note("A", "B", "argue", 0.0)
	h.note("A", "B", "argue", 10.0)
	h.note("A", "B", "reproach", 20.0)
	check(h.stage("A", "B") == 1, "dusno, žár %.2f pod prahem" % h.heat("A", "B"))
	h.note("A", "B", "stonewalling", 30.0)
	check(h.stage("A", "B") == 2 and h.recent_argues("A", "B", 30.0) == 2, "nátlak dožene dusno do studené války přes žár")
	var before: float = h.heat("A", "B")
	h.note("A", "B", "chat", 40.0)
	check(is_equal_approx(h.heat("A", "B"), before - ColdWar.HEAT_CHAT * 0.5), "ve studené válce zdvořilý hovor chladí jen napůl")
	check(h.note("A", "B", "awkward", 41.0) == 2 and is_equal_approx(h.heat("A", "B"), before - ColdWar.HEAT_CHAT * 0.5), "neutrální výsledek žár nemění")

	section("Vychladnutí v čase (hystereze)")
	var d = ColdWar.new()
	for i in 3:
		d.note("A", "B", "argue", float(i) * 10.0)
	var t := 30.0
	var thaw_cold := -1.0
	var thaw_all := -1.0
	while t < 30.0 * 1440.0:
		t += 10.0
		d.decay(10.0, t)
		if thaw_cold < 0.0 and d.stage("A", "B") < 2:
			thaw_cold = t
		if thaw_all < 0.0 and d.stage("A", "B") == 0:
			thaw_all = t
			break
	check(thaw_cold > 2880.0, "studená válka sama neodezní dřív než za 2 dny (%.1f dne)" % (thaw_cold / 1440.0))
	check(thaw_cold > 0.0 and thaw_cold < 14.0 * 1440.0, "…ale bez nových hádek časem povolí")
	check(thaw_all > thaw_cold and thaw_all < 21.0 * 1440.0, "dusno odezní později (%.1f dne)" % (thaw_all / 1440.0))
	for i in 600:
		t += 10.0
		d.decay(10.0, t)
	check(d.pairs.is_empty(), "vychladlá dvojice se z paměti uklidí")
	check(d.stats["cold_minutes"] > 2880.0, "statistika minut ve studené válce")

	section("Vyhýbání a společné chvíle")
	check(is_equal_approx(cw.avoid_weight("A", "B", "chat"), 0.25), "studená válka: chuť oslovit 0,25")
	check(is_equal_approx(cw.avoid_weight("A", "C", "chat"), 1.0), "ostatní dvojice beze změny")
	for ex in ["apologize", "clear_air", "comfort_panic"]:
		check(is_equal_approx(cw.avoid_weight("A", "B", ex), 1.0), "výjimka z vyhýbání: " + ex)
	check(cw.blocks_shared("A", "B"), "rozpálená studená válka blokuje společnou chvíli")
	var s2 = ColdWar.new()
	s2.note("A", "B", "argue", 0.0)
	s2.note("A", "B", "argue", 1.0)
	s2.decay(1440.0 * 2.0, 1500.0)
	check(not s2.blocks_shared("A", "B") and s2.stage("A", "B") == 1, "vlažné dusno společnou chvíli dovolí")
	var hb: float = s2.heat("A", "B")
	s2.on_shared("A", "B", 1500.0)
	check(s2.heat("A", "B") < hb, "společná chvíle ochladí")

	section("Vyříkat si to")
	check(ColdWar.clear_air_p(1.0, -1.0, -1.0, 100.0, -100.0, 0.0) >= 0.08, "nejhorší případ ≥ 0,08 (cesta nikdy zavřená)")
	check(ColdWar.clear_air_p(0.0, 1.0, 1.0, 0.0, 100.0, 1.0) <= 0.85, "nejlepší případ ≤ 0,85 (nikdy jistota)")
	var mono := true
	for st in [0.0, 50.0, 100.0]:
		for hh in [0.2, 0.5, 0.9]:
			var p0 := ColdWar.clear_air_p(hh, 0.0, 0.0, st, 0.0, 0.3)
			mono = mono and ColdWar.clear_air_p(hh + 0.1, 0.0, 0.0, st, 0.0, 0.3) <= p0
			mono = mono and ColdWar.clear_air_p(hh, 0.0, 0.0, st + 10.0, 0.0, 0.3) <= p0
			mono = mono and ColdWar.clear_air_p(hh, 0.5, 0.0, st, 0.0, 0.3) >= p0
			mono = mono and ColdWar.clear_air_p(hh, 0.0, 0.0, st, 30.0, 0.3) >= p0
	check(mono, "šance klesá se žárem a stresem, roste s odpouštěním a vztahem")
	var c = ColdWar.new()
	check(c.resolve_clear_air("A", "B", 0.5, 0.0, 0.0) == "nothing", "bez napětí: není co řešit")
	for i in 3:
		c.note("A", "B", "argue", float(i))
	check(c.resolve_clear_air("A", "B", 0.5, 0.1, 500.0) == "breakthrough" and c.stage("A", "B") == 0, "průlom → konec napětí")
	for i in 3:
		c.note("A", "B", "argue", 600.0 + float(i))
	check(c.resolve_clear_air("A", "B", 0.5, 0.95, 1000.0) == "blowup", "výbuch")
	check(c.stage("A", "B") == 2 and is_equal_approx(c.heat("A", "B"), 1.0), "výbuch = studená válka, žár 1,0")
	check(c.resolve_clear_air("B", "A", 0.5, 0.0, 1100.0) == "not_now", "cooldown dvojice (i z druhé strany)")
	check(c.resolve_clear_air("A", "B", 0.5, 0.6, 1000.0 + ColdWar.CLEAR_COOLDOWN) == "truce" and c.stage("A", "B") == 1, "příměří → dusno")
	var dist := {"breakthrough": 0, "truce": 0, "blowup": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 4000:
		var e = ColdWar.new()
		for j in 3:
			e.note("A", "B", "argue", float(j))
		dist[e.resolve_clear_air("A", "B", 0.5, rng.randf(), 100.0)] += 1
	check(absf(dist["breakthrough"] / 4000.0 - 0.5) < 0.03 and absf(dist["truce"] / 4000.0 - 0.275) < 0.03 \
		and absf(dist["blowup"] / 4000.0 - 0.225) < 0.03, "rozložení výsledků odpovídá p (%s)" % str(dist))

	section("Opakované cykly hádka → smíření")
	var cy = ColdWar.new()
	var tt0 := 0.0
	var outs: Array = []
	for cycle in 4:
		for j in 3:
			cy.note("A", "B", "argue", tt0 + j)
		outs.append(cy.resolve_clear_air("A", "B", 0.5, 0.45, tt0 + 400.0))
		tt0 += 1440.0
	check(outs[0] == "breakthrough" and outs[1] == "truce", "stejný hod: první smíření projde, druhé už jen příměří (%s)" % str(outs))
	check(cy.recent_repairs("A", "B", tt0) >= 3, "dvojice si pamatuje smíření (%d)" % cy.recent_repairs("A", "B", tt0))
	check(cy.resolve_clear_air("A", "B", 0.1, 0.079, tt0 + 400.0) == "breakthrough", "dolní mez šance 0,08 platí i po mnoha cyklech (cesta nikdy zavřená)")
	var cz = ColdWar.new()
	for j in 3:
		cz.note("A", "B", "argue", float(j))
	cz.resolve_clear_air("A", "B", 1.0, 0.0, 10.0)
	cz.decay(20160.0 + 100.0, 20160.0 + 200.0)
	check(cz.recent_repairs("A", "B", 20160.0 + 200.0) == 0, "po 14 dnech paměť smíření vyprší")
	var crt = ColdWar.new()
	crt.from_dict(cy.to_dict())
	check(crt.recent_repairs("A", "B", tt0) == cy.recent_repairs("A", "B", tt0), "smíření přežijí uložení")

	section("Ukládání")
	var rt = ColdWar.new()
	rt.from_dict(h.to_dict())
	check(JSON.stringify(rt.to_dict(), "", true) == JSON.stringify(h.to_dict(), "", true), "round-trip to_dict/from_dict beze ztráty")
	rt.from_dict(null)
	check(rt.pairs.is_empty() and rt.stats["entered_cold"] == 0, "starý save bez sekce → čistý stav")


func _fuzz() -> void:
	section("Fuzz from_dict (nepřátelská data)")
	var bad := [
		1, "x", [], {"pairs": 5}, {"pairs": {"A|B": 7}}, {"pairs": {"A": {}}}, {"pairs": {"A|A": {"stage": 2}}},
		{"pairs": {"A|B|C": {}}}, {"pairs": {"|B": {}}},
		{"pairs": {"A|B": {"stage": 99, "heat": INF, "since": NAN, "stamps": [NAN, INF, "x", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]}}},
		{"pairs": {"A|B": {"stage": -5, "heat": -3.0, "stamps": "nope", "last_clear": "x"}}},
		{"stats": {"blowup": -9, "cold_minutes": INF, "unknown": 5}, "bystander": {"": 1, "B": NAN, 5: 1}},
		{"pairs": {"A|B": {"stage": 1, "repairs": [NAN, "x", 1, 2, 3, 4, 5, 6, 7, 8, 9]}}},
	]
	var huge := {}
	for i in 1000:
		huge["p%d|q%d" % [i, i]] = {"stage": 2, "heat": 0.9, "stamps": [1.0]}
	bad.append({"pairs": huge})
	var long_name := "x".repeat(100)
	bad.append({"pairs": {long_name + "|B": {"stage": 1}}})
	var ok := true
	for d in bad:
		var cw = ColdWar.new()
		cw.from_dict(d)
		for k in cw.pairs:
			var r: Dictionary = cw.pairs[k]
			ok = ok and int(r["stage"]) >= 0 and int(r["stage"]) <= 2
			ok = ok and float(r["heat"]) >= 0.0 and float(r["heat"]) <= 1.0 and is_finite(float(r["since"]))
			ok = ok and (r["stamps"] as Array).size() <= ColdWar.MAX_STAMPS and (r["repairs"] as Array).size() <= ColdWar.MAX_REPAIRS
			for s in r["repairs"]:
				ok = ok and is_finite(float(s))
			for s in r["stamps"]:
				ok = ok and is_finite(float(s))
		ok = ok and cw.pairs.size() <= ColdWar.MAX_PAIRS and cw.stats["blowup"] >= 0 and is_finite(float(cw.stats["cold_minutes"]))
		cw.decay(10.0, 100.0)  # po načtení nespadne ani krok
	check(ok, "%d nepřátelských vstupů: bez pádu, v mezích (stupeň, žár, časy, limity)" % bad.size())
	var cw2 = ColdWar.new()
	cw2.from_dict({"pairs": {"A|B": {"stage": 99, "heat": INF}}})
	check(cw2.stage("A", "B") == 2 and cw2.heat("A", "B") == 0.0, "nesmyslná čísla oříznuta / nahrazena výchozími")
	var cw3 = ColdWar.new()
	cw3.from_dict({"pairs": {long_name + "|B": {"stage": 1}, "A|A": {"stage": 2}, "A|B|C": {}}})
	check(cw3.pairs.is_empty(), "dlouhá jména, dvojice se sebou a vícenásobné klíče zahozeny")


# ------------------------------------------------------------------ scéna
func _world(seed: int, dir := "") -> Node:
	clock.total_minutes = 10.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "ColdWarWorld%d" % seed
	var cfg := {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false, "clock": clock}
	if dir != "":
		cfg["save_directory"] = dir
	w.net_config = cfg
	add_child(w)
	var n := 0
	for sim in w.sims:
		sim.rng.seed = seed * 7919 + n * 104729 + 13
		sim.think_cooldown = sim.rng.randf_range(0.0, 3.0)
		n += 1
	return w


func _scene() -> void:
	section("Scéna: napětí v místnosti a atmosféra v domě")
	var w := _world(5, "user://test-cold-war-%d" % OS.get_process_id())
	check(w.sims.size() >= 3, "domácnost má aspoň 3 lidi (%d)" % w.sims.size())
	var a = w.sims[0]
	var b = w.sims[1]
	var c = w.sims[2]
	var cw = w.dynamics.cold_war
	var now := float(clock.total_minutes)
	for i in 3:
		cw.note(a.sim_name, b.sim_name, "argue", now - 30.0 + i)
	check(w.cold_war_stage(a, b) == 2 and w.cold_war_stage(a, c) == 0, "main.cold_war_stage čte stav dvojice")
	a.global_position = Vector3(0, 0, 0)
	b.global_position = Vector3(2, 0, 0)
	c.global_position = Vector3(4, 0, 0)
	var sa: float = a.mental.stress
	var sb: float = b.mental.stress
	var sc: float = c.mental.stress
	var awake: bool = not a._is_sleeping() and not b._is_sleeping() and not c._is_sleeping()
	check(awake, "všichni vzhůru (předpoklad scény)")
	cw.tick(w.sims, now, 10.0)
	check(a.mental.stress > sa and b.mental.stress > sb, "dvojice ve stejné místnosti: stres roste u obou")
	check(a.mood.has_moodlet("dusno_" + String(b.name)) and b.mood.has_moodlet("dusno_" + String(a.name)), "moodlet „Nemluvíme spolu“ u obou")
	check(c.mental.stress > sc and c.mood.has_moodlet("dusno_doma"), "třetí v domě cítí dusno")
	var sc2: float = c.mental.stress
	cw.tick(w.sims, now + 10.0, 10.0)
	check(is_equal_approx(c.mental.stress, sc2), "atmosféra pro přihlížející má cooldown (bez farmy stresu)")
	b.global_position = Vector3(30, 0, 0)
	var sa2: float = a.mental.stress
	cw.tick(w.sims, now + 20.0, 10.0)
	check(is_equal_approx(a.mental.stress, sa2), "v jiné místnosti napětí nepůsobí")

	section("Plánovač: vyhýbání a chuť vyříkat si to")
	var base := 1.0
	check(cw.ai_clear_air_score(a, b, base, now + 20.0) == 0.0 or cw.ai_clear_air_score(a, b, base, now + 20.0) < cw.ai_clear_air_score(a, b, base, now + 20.0 + ColdWar.CLEAR_FRESH),
		"hned po hádce je chuť vyříkat si to tlumená")
	var later: float = cw.ai_clear_air_score(a, b, base, now + 1440.0)
	check(later > 0.0, "po dni ve studené válce AI chce vyříkat (%.2f)" % later)
	check(cw.ai_clear_air_score(a, c, base, now + 1440.0) == 0.0, "bez napětí nic")

	section("Příkaz hráče: Vyříkat si to")
	b.global_position = Vector3(2, 0, 0)
	var act: Dictionary = ActionLibrary.get_action("clear_air")
	check(not act.is_empty() and a.command(act, b), "příkaz přijat")
	var done := false
	for i in 400:
		clock.advance(1.0)
		if not a.last_clear_air.is_empty():
			done = true
			break
	check(done, "pokus proběhl")
	var oc := String(a.last_clear_air.get("outcome", ""))
	check(oc in ["breakthrough", "truce", "blowup"], "výsledek: " + oc)
	var stage_after: int = cw.stage(a.sim_name, b.sim_name)
	check((oc == "breakthrough" and stage_after == 0) or (oc == "truce" and stage_after == 1) or (oc == "blowup" and stage_after == 2),
		"stav dvojice odpovídá výsledku (stupeň %d)" % stage_after)
	var p_used := float(a.last_clear_air.get("p", 0.0))
	check(p_used >= 0.08 and p_used <= 0.85, "použitá šance v mezích (%.2f)" % p_used)
	var stamps_before := (cw.pairs.get(ColdWar.key(a.sim_name, b.sim_name), {"stamps": []})["stamps"] as Array).size()
	check(int(w.dynamics.stats["talks"]) >= 1, "pokus se počítá do statistik domácnosti")
	# Druhý pokus hned: nesmí zastavit druhou postavu ani přičíst hádku.
	for i in 60:
		clock.advance(1.0)
	a.last_clear_air = {}
	var c_act: String = String(c.current_action.get("id", ""))
	var c_state = c.state
	check(a.command(act, c), "příkaz vůči postavě bez napětí přijat (offline)")
	var trace: PackedStringArray = ["q=%d st=%d id=%s bp=%s" % [a.player_queue.size(), a.state, str(a.current_action.get("id", "")), str(a.by_player)]]
	for i in 200:
		clock.advance(1.0)
		if i % 5 == 0:
			trace.append("%d:q=%d st=%d id=%s" % [i, a.player_queue.size(), a.state, str(a.current_action.get("id", ""))])
		if not a.last_clear_air.is_empty():
			break
	check(String(a.last_clear_air.get("outcome", "")) == "nothing", "bez napětí: „není co řešit“", " | ".join(trace.slice(0, 12)))
	check(c.social_partner != a, "postava bez napětí nebyla vtažena do rozhovoru")
	var stamps_after := (cw.pairs.get(ColdWar.key(a.sim_name, b.sim_name), {"stamps": []})["stamps"] as Array).size()
	check(stamps_after <= stamps_before, "pokus bez napětí nepřidal hádku dvojici A–B")

	section("Uložení hry")
	var now2 := float(clock.total_minutes)
	for i in 3:
		cw.note(a.sim_name, c.sim_name, "argue", now2 + i)
	var an := String(a.sim_name)
	var cn := String(c.sim_name)
	var snap: Dictionary = cw.to_dict()
	var res: Dictionary = w.save_game("manual")
	check(res.get("ok", false), "save ok", str(res))
	cw.resolve_clear_air(a.sim_name, c.sim_name, 1.0, 0.0, now2 + 5.0)
	check(cw.stage(a.sim_name, c.sim_name) == 0, "po uložení změněno (průlom)")
	var ld: Dictionary = w.load_game("manual")
	check(ld.get("ok", false), "load ok", str(ld))
	var cw_l = w.dynamics.cold_war
	check(cw_l.stage(an, cn) == 2, "studená válka obnovena z uložení")
	check(JSON.stringify(cw_l.to_dict(), "", true) == JSON.stringify(snap, "", true), "stav ColdWar po načtení = stav při uložení")
	w.queue_free()
	await get_tree().process_frame

	section("Výkon")
	var big = ColdWar.new()
	for i in 40:
		for j in range(i + 1, 40):
			big.note("s%d" % i, "s%d" % j, "argue", 0.0)
			big.note("s%d" % i, "s%d" % j, "argue", 1.0)
	var t0 := Time.get_ticks_usec()
	for k in 100:
		big.decay(10.0, 10.0 + k)
	var per := float(Time.get_ticks_usec() - t0) / 100.0
	check(per < 2000.0, "decay 780 dvojic: %.0f µs/krok (< 2 ms)" % per)


# ------------------------------------------------------------------ dlouhý běh
func _soak_run(seed: int, days: int) -> Dictionary:
	var w := _world(seed)
	var max_cold := 0.0
	var cold_since := {}
	for m in days * 720:
		clock.advance(2.0)
		if m % 30 == 0:
			var now := float(clock.total_minutes)
			for e in w.dynamics.cold_war.summary(now):
				if int(e["stage"]) == 2:
					var k := String(e["a"]) + "|" + String(e["b"])
					if not cold_since.has(k):
						cold_since[k] = now
					max_cold = maxf(max_cold, now - float(cold_since[k]))
				else:
					cold_since.erase(String(e["a"]) + "|" + String(e["b"]))
	var st: Dictionary = w.dynamics.cold_war.stats.duplicate(true)
	var out := {"stats": st, "talks": int(w.dynamics.stats["talks"]), "argues": int(w.dynamics.stats["argues"]),
		"max_cold_days": max_cold / 1440.0, "sig": JSON.stringify(w.dynamics.cold_war.to_dict(), "", true) + JSON.stringify(w.dynamics.stats, "", true),
		"n": w.sims.size()}
	w.queue_free()
	await get_tree().process_frame
	return out


func _soak() -> void:
	section("Dlouhý běh: 3 seedy × 10 dní")
	var tot := {"entered_cold": 0, "breakthrough": 0, "truce": 0, "blowup": 0, "talks": 0, "argues": 0, "cold_minutes": 0.0}
	var max_cold := 0.0
	for seed in [1, 3, 7]:
		var r: Dictionary = await _soak_run(seed, 10)
		print("SOAK seed=%d n=%d talks=%d argues=%d (%.0f %%) cold=%s max_cold=%.2f d" % [seed, r["n"], r["talks"], r["argues"],
			100.0 * r["argues"] / maxf(1.0, r["talks"]), str(r["stats"]), r["max_cold_days"]])
		for k in ["entered_cold", "breakthrough", "truce", "blowup"]:
			tot[k] += int(r["stats"][k])
		tot["cold_minutes"] += float(r["stats"]["cold_minutes"])
		tot["talks"] += r["talks"]
		tot["argues"] += r["argues"]
		max_cold = maxf(max_cold, r["max_cold_days"])
	var rate: float = float(tot["argues"]) / maxf(1.0, float(tot["talks"]))
	print("SOAK TOTAL %s rate=%.3f max_cold=%.2f d" % [str(tot), rate, max_cold])
	check(tot["talks"] > 60, "domácnosti spolu opravdu žijí")
	check(rate < 0.45, "podíl hádek drží pod 45 %% (%.0f %%)" % (100.0 * rate))
	check(max_cold < 9.0, "žádná studená válka netrvá skoro celý běh (max %.1f dne)" % max_cold)
	check(float(tot["cold_minutes"]) < 0.5 * 3.0 * 10.0 * 1440.0 * 3.0, "studená válka není výchozí stav domácnosti")
	section("Determinismus")
	var x: Dictionary = await _soak_run(3, 3)
	var y: Dictionary = await _soak_run(3, 3)
	check(x["sig"] == y["sig"], "stejný seed → stejný stav dvojic i statistiky")
