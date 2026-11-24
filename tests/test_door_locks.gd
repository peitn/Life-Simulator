extends "res://tests/test_base.gd"
## B4b (24. 11. 2026): zámky dveří (LotGrid v4).
## Validace zámku, pravidla (jen dveře, stejný zámek, limit, lock_seals, lock_traps), navigace z pohledu postav
## (BFS, pathfinder, plné úseky, LotNav, lock_blocker, escape, cache pohledů), save v4 + migrace v3 + validace,
## veřejný snímek + fuzz, výkon, herní svět (autorita, LotDoor kontrolka a otevírání, AI důsledek v _walk,
## disk), UI v režimu zařizování a skutečné ENet (cizí klíč, divák, podvržené požadavky, replikace).

const Main := preload("res://main.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")
const LotNav := preload("res://scripts/world/lot_nav.gd")
const LotDoor := preload("res://scripts/world/lot_door.gd")
const Pathfinder := preload("res://scripts/world/lot_pathfinder.gd")

var clock: Node
var save_dir := ""
var port := 0
var notices := {}


func _ready() -> void:
	watchdog_seconds = 200.0
	randomize()
	port = 27700 + randi() % 700
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 1000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-door-locks-" + str(OS.get_process_id())
	_run.call_deferred()


func _run() -> void:
	_test_valid_lock()
	_test_rules()
	_test_traps()
	_test_navigation()
	_test_save()
	_test_public()
	_test_performance()
	await _test_world()
	await _test_ui()
	await _test_multiplayer()
	clock.running = false
	finish("test_door_locks")


# ---------------------------------------------------------------- pomocné

func _syn(fixtures := true):
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	if fixtures:
		lot.add_interior_rect(Rect2(0.0, 0.0, 12.5, 10.0))
		lot.add_static_rect(Rect2(12.5, 0.0, 0.25, 10.0))
		lot.add_fixed("Postel", Vector2(5.0, 5.0), 2.0, 1.0, 0.0, [Vector2(5.0, 6.0)])
	lot.rebuild()
	return lot


## Uzavřená místnost kolem postele: tři stěny, dveře v horní (oid 1), čtvrtá stěna dole (wid 4).
func _bed_room():
	var lot = _syn()
	lot.build_wall(12, 14, 28, 14, 1000.0)
	lot.build_wall(12, 14, 12, 30, 1000.0)
	lot.build_wall(28, 14, 28, 30, 1000.0)
	lot.build_opening(1, "door", 6, 1000.0)
	lot.build_wall(12, 30, 28, 30, 1000.0)
	return lot


## Prázdná místnost 3 × 3 m s dveřmi (oid 1) bez věcí uvnitř.
func _empty_room():
	var room = _syn(false)
	room.build_wall(60, 10, 72, 10, 1000.0)
	room.build_wall(60, 10, 60, 22, 1000.0)
	room.build_wall(72, 10, 72, 22, 1000.0)
	room.build_opening(1, "door", 4, 1000.0)
	room.build_wall(60, 22, 72, 22, 1000.0)
	return room


func _json(lot) -> String:
	return JSON.stringify(lot.to_dict())


## Parcela s mnoha dveřmi (bez věcí) – limit zámků a výkon.
func _many_doors():
	var full = LotGrid.new()
	full.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	full.rebuild()
	full.funds = LotGrid.MAX_FUNDS
	for row in 6:
		for col in 5:
			var wr: Dictionary = full.build_wall(col * 20, 2 + row * 6, col * 20 + 16, 2 + row * 6, 1000.0)
			if bool(wr["ok"]):
				full.build_opening(int(wr["wid"]), "door", 1, 1000.0)
				full.build_opening(int(wr["wid"]), "window", 11, 1000.0)
	return full


# ---------------------------------------------------------------- validace zámku

func _test_valid_lock() -> void:
	section("Platný zámek")
	var good := ["", "*", "Player_abc123", "Sim-2", "Šárka"]
	var bad: Array = [5, null, 1.5, [], "a/b", "a:b", "a.b", "a@b", "a%b", "x".repeat(65), "Ana\u202E", "A\nB", "A\tB",
		" Ana", "Ana ", "A\u200Bna", "A\u2066na", "\u0085X", "\uFEFFAna", "**"]
	var g_ok := true
	for s in good:
		if not LotGrid.valid_lock(s):
			g_ok = false
	var b_ok := 0
	for s in bad:
		if not LotGrid.valid_lock(s):
			b_ok += 1
	check(g_ok, "platné: prázdný, *, jména uzlů (i diakritika)")
	check(b_ok == bad.size(), "%d neplatných zámků odmítnuto (typy, /:.@%%, délka, řídicí, bidi, nulová šířka, mezery)" % bad.size(), "%d/%d" % [b_ok, bad.size()])
	check(LotGrid.door_passable({"lock": ""}, "Bob") and LotGrid.door_passable({"lock": "Ana"}, "Ana")
		and not LotGrid.door_passable({"lock": "Ana"}, "Bob") and not LotGrid.door_passable({"lock": "*"}, "Ana")
		and LotGrid.door_passable({"lock": "*"}, "") and LotGrid.door_passable({}, "Bob"), "průchodnost podle klíče; pohled \"\" zámky ignoruje")


# ---------------------------------------------------------------- pravidla

func _test_rules() -> void:
	section("Pravidla zámků")
	var lot = _bed_room()
	lot.build_opening(2, "window", 6, 1000.0)
	check(lot.openings.size() == 2 and lot.lock_of(1) == "" and String(lot.openings[1]["lock"]) == "", "nové dveře odemčené (záznam má klíč lock)")
	check(lot.check_lock(99, "Ana", []) == "unknown_oid" and lot.check_lock("1", "Ana", []) == "unknown_oid"
		and lot.check_lock(1.0, "Ana", []) == "unknown_oid", "neznámé / jinak typované oid")
	check(lot.check_lock(2, "*", []) == "not_door", "okno zamknout nejde")
	check(lot.check_lock(1, "a/b", []) == "lock_bad" and lot.check_lock(1, 7, []) == "lock_bad", "neplatný zámek")
	check(lot.check_lock(1, "", []) == "lock_same", "odemčené odemknout nejde (nic se nemění)")
	check(lot.check_lock(1, "*", []) == "lock_seals", "zámek pro všechny by odřízl postel → lock_seals")
	var f0: int = lot.funds
	var l0: int = lot.ledger.size()
	var rev0: int = lot.revision
	var r: Dictionary = lot.set_lock(1, "Ana", [["Bob", Vector2(9.0, 1.0)], ["Ana", Vector2(9.5, 1.0)]])
	check(bool(r["ok"]) and String(r["prev"]) == "" and lot.lock_of(1) == "Ana", "osobní zámek smí ostatním postel odříznout", str(r))
	check(lot.funds == f0 and lot.ledger.size() == l0 and lot.revision == rev0 + 1, "zámek nestojí peníze, nepíše do knihy, zvedne revizi")
	check(lot.check_lock(1, "Ana", []) == "lock_same", "stejný zámek znovu ne")
	check(lot.has_locks() and lot.locked_count() == 1 and lot.locked_against("Bob") == [1] and lot.locked_against("Ana").is_empty()
		and lot.locked_against("").is_empty(), "přehled zámků podle postavy")
	check(lot.access_reachable(Vector2(5.0, 6.0)), "stavební pohled (bez zámků): postel dál dosažitelná")
	check(lot.check_wall(30, 2, 30, 10) == "", "zámky neblokují stavění jinde")
	var ru: Dictionary = lot.set_lock(1, "", [])
	check(bool(ru["ok"]) and String(ru["prev"]) == "Ana" and lot.lock_of(1) == "" and not lot.has_locks(), "odemčení")
	# Zámek padá s dveřmi.
	lot.set_lock(1, "Ana", [])
	var d2: Dictionary = lot.build_opening(4, "door", 6, 1000.0)
	check(bool(d2["ok"]) and bool(lot.remove_opening(1, 1000.0)["ok"]) and not lot.has_locks(), "vybourané zamčené dveře zámek odnesou")
	# Limit.
	var full = _many_doors()
	var doors: Array = []
	for oid in full.sorted_oids():
		if LotGrid.is_door(String(full.openings[oid]["kind"])):
			doors.append(int(oid))
	check(doors.size() > LotGrid.MAX_LOCKED, "%d dveří na zkoušku limitu" % doors.size())
	var locked := 0
	for i in LotGrid.MAX_LOCKED:
		if bool(full.set_lock(doors[i], "*", [])["ok"]):
			locked += 1
	check(locked == LotGrid.MAX_LOCKED, "16 zámků projde", str(locked))
	check(full.check_lock(doors[LotGrid.MAX_LOCKED], "*", []) == "lock_limit", "17. zámek → lock_limit")
	check(bool(full.set_lock(doors[0], "Ana", [])["ok"]), "přezamknutí už zamčených dveří limit nepočítá")
	full.set_lock(doors[1], "", [])
	check(full.check_lock(doors[LotGrid.MAX_LOCKED], "*", []) == "", "po odemčení jedněch zase jde")


func _test_traps() -> void:
	section("Zámek nikoho nezavře (lock_traps)")
	var room = _empty_room()
	var inside := Vector2(16.5, 4.0)
	var outside := Vector2(5.0, 1.0)
	check(room.check_lock(1, "Ana", [["Bob", inside]]) == "lock_traps", "Bob uvnitř, zámek pro Anu → zavřel by ho")
	check(room.check_lock(1, "Ana", [["Ana", inside]]) == "", "Ana uvnitř se svým klíčem smí")
	check(room.check_lock(1, "*", [["Ana", inside]]) == "lock_traps", "pro všechny s kýmkoli uvnitř ne")
	check(room.check_lock(1, "*", [["Ana", outside], ["Bob", outside]]) == "", "všichni venku → zamknout pro všechny jde (prázdná místnost)")
	check(room.check_lock(1, "Ana", [["Bob", Vector2(NAN, 1.0)], "x", [1, inside], ["", inside], ["Bob"], ["Bob", inside * INF]]) == "",
		"nesmyslné záznamy poloh se ignorují")
	check(room.nav_viewer == "" and room._nav_unlock == 0, "kontrola vrátí pohled parcely")
	var two = _empty_room()
	check(bool(two.build_opening(4, "door", 4, 1000.0)["ok"]), "místnost s druhými dveřmi")
	check(two.check_lock(1, "Ana", [["Bob", inside]]) == "", "Bob odejde druhými dveřmi → smí se zamknout")
	two.set_lock(2, "Cyril", [])
	check(two.check_lock(1, "Ana", [["Bob", inside]]) == "lock_traps", "… ale ne, když druhé dveře zamkl Cyril")
	check(two.check_lock(1, "Ana", [["Cyril", inside]]) == "", "Cyril má klíč od druhých dveří → odejde jimi")
	# Stavební kontroly z pohledu zámků: vybourání odemčených dveří by Boba uvěznilo za cizím zámkem.
	var three = _empty_room()
	three.build_opening(4, "door", 4, 1000.0)
	three.set_lock(1, "Ana", [])
	check(not three.opening_traps(2, [inside]), "pohled bez zámků: Bob by odešel dveřmi Any")
	check(three.traps_in_lock_views(func(p: Array) -> bool: return three.opening_traps(2, p), [["Bob", inside]]),
		"z pohledu Boba by ho vybourání druhých dveří zavřelo")
	check(not three.traps_in_lock_views(func(p: Array) -> bool: return three.opening_traps(2, p), [["Ana", inside], ["Bob", outside]]),
		"Ana s klíčem uvnitř a Bob venku: v pořádku")
	check(three.traps_in_lock_views(func(p: Array) -> bool: return three.wall_traps(0, 30, 8, 30, p), [["Bob", inside]]) == false
		and three.nav_viewer == "", "vzdálená zeď nikoho nezavře, pohled vrácen")
	var groups: Dictionary = three._view_groups([["Bob", inside], ["Cyril", inside], ["Ana", inside], ["X", Vector2(NAN, 0)]])
	check(groups.size() == 2 and (groups["1"]["who"] as Array).size() == 2 and (groups[""]["who"] as Array) == ["Ana"],
		"skupiny pohledů: Bob a Cyril sdílí BFS, Ana zvlášť, nesmysly ven", str(groups))


# ---------------------------------------------------------------- navigace

func _test_navigation() -> void:
	section("Navigace z pohledu postav")
	var lot = _bed_room()
	lot.set_lock(1, "Ana", [])
	var bed := Vector2(5.0, 6.0)
	lot.nav_viewer = "Bob"
	var p_bob: Array = Pathfinder.find_path(lot, Vector2i(20, 2), Vector2i(20, 24))
	var seg_bob: int = lot.wall_segments(lot.walls[1]).size()
	lot.nav_viewer = "Ana"
	var p_ana: Array = Pathfinder.find_path(lot, Vector2i(20, 2), Vector2i(20, 24))
	var seg_ana: int = lot.wall_segments(lot.walls[1]).size()
	lot.nav_viewer = ""
	var seg_god: int = lot.wall_segments(lot.walls[1]).size()
	check(p_bob.is_empty() and not p_ana.is_empty(), "pathfinder: Bob se dovnitř nedostane, Ana ano")
	check(seg_bob == 1 and seg_ana == 2 and seg_god == 2, "plné úseky: pro Boba celá zeď, pro Anu a stavbu s dveřmi", "%d %d %d" % [seg_bob, seg_ana, seg_god])
	lot.nav_viewer = "Bob"
	var nb: Dictionary = LotNav.next_point(lot, Vector3(5.0, 0, 1.0), Vector3(5.0, 0, 6.0), {})
	lot.nav_viewer = "Ana"
	var na: Dictionary = LotNav.next_point(lot, Vector3(5.0, 0, 1.0), Vector3(5.0, 0, 6.0), {})
	lot.nav_viewer = ""
	check(String(nb["mode"]) == "none" and String(na["mode"]) == "direct", "LotNav: Bob none, Ana rovnou dveřmi", "%s / %s" % [nb["mode"], na["mode"]])
	check(LotNav.lock_blocker(lot, "Bob", Vector2(5.0, 1.0), bed) == "Ana" and LotNav.lock_blocker(lot, "Ana", Vector2(5.0, 1.0), bed) == ""
		and LotNav.lock_blocker(lot, "", Vector2(5.0, 1.0), bed) == "", "lock_blocker: Boba zastavil zámek Any")
	check(lot.nav_viewer == "" and lot._nav_unlock == 0, "lock_blocker vrátí pohled")
	check(LotNav.lock_blocker(lot, "Bob", Vector2(9.0, 1.0), Vector2(9.0, 8.0)) == "", "cesta mimo místnost: žádný viník")
	# Cache pohledů: střídání postav nesmí míchat výsledky.
	var stable := true
	for i in 6:
		lot.nav_viewer = "Bob" if i % 2 == 0 else "Ana"
		var segs: int = lot.wall_segments(lot.walls[1]).size()
		var reach: PackedByteArray = lot._reach_before()
		lot._build_edges({})
		var r_bed: bool = lot._target_reached(reach, lot._idx(20, 24))
		if (i % 2 == 0 and (segs != 1 or r_bed)) or (i % 2 == 1 and (segs != 2 or not r_bed)):
			stable = false
	lot.nav_viewer = ""
	check(stable, "střídání pohledů Bob/Ana: cache úseků a dosažitelnosti drží správné výsledky")
	# Dvoje dveře: osobní + pro všechny.
	var two = _bed_room()
	two.build_opening(4, "door", 6, 1000.0)
	two.set_lock(1, "Ana", [])
	check(bool(two.set_lock(2, "*", [])["ok"]), "druhé dveře pro všechny (první vedou dovnitř) – bez lock_seals")
	two.nav_viewer = "Ana"
	var na2: Dictionary = LotNav.next_point(two, Vector3(1.0, 0, 1.0), Vector3(5.0, 0, 6.0), {})
	two.nav_viewer = ""
	check(String(na2["mode"]) == "route", "Ana jde svými dveřmi (route)")
	check(LotNav.lock_blocker(two, "Bob", Vector2(5.0, 1.0), bed) in ["Ana", "*"], "Bob: viníkem je jeden z obou zámků")
	# Escape: postava bez klíče uvnitř (starý save) nesmí uvíznout.
	var esc = _bed_room()
	esc.openings[1]["lock"] = "Ana"
	esc.revision += 1
	esc.nav_viewer = "Bob"
	var pe: Dictionary = LotNav.plan(esc, Vector2(3.5, 6.5), Vector2(9.0, 1.0))
	esc.nav_viewer = ""
	check(String(pe["mode"]) == "escape", "Bob zavřený bez klíče → escape (žádný softlock)", str(pe["mode"]))


# ---------------------------------------------------------------- ukládání

func _locked_lot():
	var lot = _bed_room()
	lot.build_opening(4, "door", 6, 1000.0)
	lot.build_opening(2, "window", 6, 1000.0)
	lot.set_lock(1, "Ana", [])
	lot.set_lock(2, "*", [])
	return lot


func _test_save() -> void:
	section("Ukládání v4, migrace v3, validace")
	var lot = _locked_lot()
	var d: Dictionary = lot.to_dict()
	var locks := {}
	for o in d["openings"]:
		locks[int(o["oid"])] = String(o["lock"])
	check(int(d["version"]) == 4 and (d["openings"][0] as Dictionary).size() == 7 and locks == {1: "Ana", 2: "*", 3: ""}, "snímek v4 se zámky", str(locks))
	check(LotGrid.validate_snapshot(d) == "", "vlastní snímek projde")
	var l2 = _syn()
	var r2: Dictionary = l2.from_dict(JSON.parse_string(JSON.stringify(d)), 1100.0)
	check(bool(r2["ok"]) and _json(l2) == _json(lot) and l2.lock_of(1) == "Ana" and l2.lock_of(2) == "*", "JSON → obnova → stejné bit po bitu",
		_json(l2) + " VS " + _json(lot))
	l2.nav_viewer = "Bob"
	var blocked := Pathfinder.find_path(l2, Vector2i(20, 2), Vector2i(20, 24)).is_empty()
	l2.nav_viewer = ""
	check(blocked, "po obnově zámky platí pro navigaci")
	var v3: Dictionary = d.duplicate(true)
	v3["version"] = 3
	for o in v3["openings"]:
		o.erase("lock")
	check(LotGrid.validate_snapshot(v3) == "", "snímek v3 (bez zámků) projde")
	var l3 = _syn()
	var r3: Dictionary = l3.from_dict(v3, 1100.0)
	check(bool(r3["ok"]) and l3.openings.size() == 3 and not l3.has_locks() and int(l3.to_dict()["version"]) == 4, "migrace v3: dveře odemčené, uloží se jako v4")
	var muts: Array = [
		func(x): x["openings"][0]["lock"] = 5,
		func(x): x["openings"][0]["lock"] = "a/b",
		func(x): x["openings"][0]["lock"] = "Ana\u202E",
		func(x): x["openings"][0]["lock"] = "x".repeat(65),
		func(x): x["openings"][2]["lock"] = "*",
		func(x): x["openings"][0].erase("lock"),
		func(x): x["openings"][0]["extra"] = 1,
		func(x): x["version"] = 3,
		func(x): x["version"] = 5,
	]
	var bad := 0
	for m in muts:
		var v: Dictionary = d.duplicate(true)
		m.call(v)
		if LotGrid.validate_snapshot(v) != "":
			bad += 1
	check(bad == muts.size(), "%d vadných variant odmítnuto (typ, znaky, délka, zámek na okně, chybějící klíč, v3 se zámkem, budoucí verze)" % muts.size(),
		"%d/%d" % [bad, muts.size()])
	var full = _many_doors()
	var n := 0
	for oid in full.sorted_oids():
		if LotGrid.is_door(String(full.openings[oid]["kind"])) and n < LotGrid.MAX_LOCKED:
			full.set_lock(int(oid), "*", [])
			n += 1
	var fd: Dictionary = full.to_dict()
	check(LotGrid.validate_snapshot(fd) == "", "16 zámků v uloženém snímku projde")
	for o in fd["openings"]:
		if String(o["kind"]) == "door" and String(o["lock"]) == "":
			o["lock"] = "*"
			break
	check(LotGrid.validate_snapshot(fd) == "bad_lot_openings", "17 zámků v podvrženém snímku odmítnuto")


func _test_public() -> void:
	section("Veřejný snímek a fuzz")
	var lot = _locked_lot()
	var pub: Dictionary = lot.public_snapshot()
	check(int(pub["v"]) == 4 and (pub["open"][0] as Array).size() == 7 and String(pub["open"][0][6]) == "Ana", "snímek nese zámek jako 7. prvek")
	var cl = _syn()
	check(cl.apply_public(pub) and cl.lock_of(1) == "Ana" and cl.lock_of(2) == "*" and cl.lock_of(3) == "", "klient převzal zámky")
	var base := JSON.stringify(cl.openings)
	var forged: Array = []
	for mut in [[0, 6, 5], [0, 6, "a/b"], [0, 6, "Ana\u2067"], [2, 6, "*"]]:
		var f: Dictionary = pub.duplicate(true)
		f["open"][int(mut[0])][int(mut[1])] = mut[2]
		forged.append(f)
	var f_short: Dictionary = pub.duplicate(true)
	f_short["open"][0] = (f_short["open"][0] as Array).slice(0, 6)
	forged.append(f_short)
	var f_v3long: Dictionary = pub.duplicate(true)
	f_v3long["v"] = 3
	forged.append(f_v3long)
	var rej := 0
	for f in forged:
		if not cl.apply_public(f):
			rej += 1
	check(rej == forged.size() and JSON.stringify(cl.openings) == base, "%d podvržených snímků odmítnuto, stav beze změny" % forged.size(), str(rej))
	var old: Dictionary = pub.duplicate(true)
	old["v"] = 3
	for e in old["open"]:
		(e as Array).resize(6)
	var c3 = _syn()
	check(c3.apply_public(old) and not c3.has_locks() and c3.openings.size() == 3, "snímek starého serveru (v3, šest prvků) → dveře odemčené")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2411
	var weird: Array = ["", "*", "Ana", "Bob", 0, null, "a/b", "x".repeat(70), "\u202E", [], "**", "Ana "]
	var bad_kept := 0
	var accepted := 0
	for i in 200:
		var s: Dictionary = pub.duplicate(true)
		s["open"][rng.randi_range(0, 2)][6] = weird[rng.randi_range(0, weird.size() - 1)]
		var c2 = _syn()
		if c2.apply_public(s):
			accepted += 1
			for oid in c2.openings:
				var o: Dictionary = c2.openings[oid]
				if not LotGrid.valid_lock(o["lock"]) or (String(o["lock"]) != "" and not LotGrid.is_door(String(o["kind"]))):
					bad_kept += 1
	check(bad_kept == 0 and accepted > 0, "fuzz 200: přijaté snímky mají jen platné zámky na dveřích (přijato %d)" % accepted)


func _test_performance() -> void:
	section("Výkon")
	var full = _many_doors()
	var doors: Array = []
	for oid in full.sorted_oids():
		if LotGrid.is_door(String(full.openings[oid]["kind"])):
			doors.append(int(oid))
	for i in 8:
		full.set_lock(doors[i], "Sim_%d" % i, [])
	var pts: Array = []
	for i in 8:
		pts.append(["Sim_%d" % i, Vector2(1.0 + i * 2.5, 0.2)])
	var t0 := Time.get_ticks_usec()
	full.check_lock(doors[10], "*", pts)
	var ck := float(Time.get_ticks_usec() - t0)
	check(ck < 400000.0, "check_lock s 8 postavami (BFS po skupinách pohledů) < 400 ms (%.1f ms)" % (ck / 1000.0))
	var t1 := Time.get_ticks_usec()
	for i in 200:
		full.nav_viewer = "Sim_%d" % (i % 8)
		LotNav.walls_block(full, Vector2(0.3, 0.1 + i * 0.04), Vector2(24.7, 9.9 - i * 0.04))
	full.nav_viewer = ""
	var wb := float(Time.get_ticks_usec() - t1) / 200.0
	check(wb < 4000.0, "walls_block se střídáním 8 pohledů < 4 ms (%.3f ms)" % (wb / 1000.0))
	var t2 := Time.get_ticks_usec()
	for i in 20:
		LotNav.lock_blocker(full, "Sim_0", Vector2(0.2, 0.2), Vector2(24.0, 9.0))
	var lb := float(Time.get_ticks_usec() - t2) / 20.0
	check(lb < 60000.0, "lock_blocker < 60 ms (%.1f ms)" % (lb / 1000.0))


# ---------------------------------------------------------------- herní svět

func _offline_world(wname: String, hud := false) -> Node3D:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = wname
	w.net_config = {"mode": "offline", "audio": false, "camera": hud, "visuals": false, "hud": hud,
		"autoload": false, "autosave": false, "save_directory": save_dir + ("-ui" if hud else ""), "clock": clock}
	add_child(w)
	return w


## Místnost 12 × 12 buněk s dveřmi v horní stěně (jako test_lot_doors). {} = nenašlo se.
func _room(world: Node3D) -> Dictionary:
	var lot = world.lot
	var a: Vector2i = lot.snap_lattice(Vector2(-12.0, -12.0))
	var b: Vector2i = lot.snap_lattice(Vector2(13.0, 12.0))
	for z in range(a.y, b.y - 12, 3):
		for x in range(a.x, b.x - 12, 3):
			var ws := [[x, z, x + 12, z], [x, z, x, z + 12], [x + 12, z, x + 12, z + 12]]
			var fine := true
			for wq in ws + [[x, z + 12, x + 12, z + 12]]:
				if lot.check_wall(wq[0], wq[1], wq[2], wq[3], false) != "":
					fine = false
					break
			if not fine:
				continue
			var built: Array = []
			var ok := true
			for wq in ws:
				var r: Dictionary = world.lot_apply_action("wall", wq, "Test")
				if not bool(r["ok"]):
					ok = false
					break
				built.append(int(r["wid"]))
			var oid := 0
			if ok:
				var ro: Dictionary = world.lot_apply_action("open", [built[0], "door", 4], "Test")
				ok = bool(ro["ok"])
				oid = int(ro.get("oid", 0))
			if ok:
				var rb: Dictionary = world.lot_apply_action("wall", [x, z + 12, x + 12, z + 12], "Test")
				ok = bool(rb["ok"])
				if ok:
					built.append(int(rb["wid"]))
			if ok:
				var before: PackedByteArray = lot._reach_before()
				lot._build_edges({})
				for iz in range(z + 8, z + 11):
					for ix in range(x + 2, x + 11):
						var ci: int = lot._idx(ix, iz)
						if lot._walkable(ci) and lot._target_reached(before, ci):
							var c: Vector2 = lot.origin + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * LotGrid.CELL
							var ab: Array = lot.opening_world(lot.openings[oid])
							var dc: Vector2 = ((ab[0] as Vector2) + (ab[1] as Vector2)) * 0.5
							var outside: Vector2 = dc + Vector2(0.0, -0.7)
							return {"oid": oid, "cx": c.x, "cz": c.y, "walls": built, "door": dc, "out": outside}
			for wid in built:
				world.lot_apply_action("unwall", [wid], "Test")
	return {}


func _test_world() -> void:
	section("Zámky v herním světě (offline autorita, LotDoor, AI)")
	var world := _offline_world("LockWorld")
	var lot = world.lot
	check(world.sims.size() >= 2, "domácnost má aspoň dvě postavy")
	var room := _room(world)
	check(not room.is_empty(), "místnost s dveřmi na zahradě", str(room))
	if room.is_empty() or world.sims.size() < 2:
		world.free()
		return
	var a: Node3D = world.sims[0]
	var b: Node3D = world.sims[1]
	var home_a: Vector3 = a.global_position
	var home_b: Vector3 = b.global_position
	var oid: int = room["oid"]
	var inside := Vector3(float(room["cx"]), home_a.y, float(room["cz"]))
	a.global_position = inside
	check(String(world.lot_apply_action("lock", [oid, String(b.name)], "Test")["reason"]) == "lock_traps", "zámek pro B s A uvnitř → lock_traps")
	check(String(world.lot_apply_action("lock", [oid, "*"], "Test")["reason"]) == "lock_traps", "pro všechny s A uvnitř → lock_traps")
	check(String(world.lot_apply_action("lock", [oid, "Nikdo_Takovy"], "Test")["reason"]) == "lock_who", "neexistující postava → lock_who")
	check(String(world.lot_apply_action("lock", [oid], "Test")["reason"]) == "lock_bad" and String(world.lot_apply_action("lock", [oid, "a/b"], "Test")["reason"]) == "lock_bad",
		"špatné argumenty → lock_bad")
	var rl: Dictionary = world.lot_apply_action("lock", [oid, String(a.name)], "Test")
	check(bool(rl["ok"]) and lot.lock_of(oid) == String(a.name), "A se zamkne uvnitř (osobní zámek)", str(rl))
	check(world.lot_lock_text(lot.lock_of(oid)).begins_with("zamčeno – jen ") and world.lot_lock_text("") == "odemčeno"
		and world.lot_lock_text("*") == "zamčeno pro všechny", "popis zámku pro UI")
	# LotDoor: kontrolka a otevírání jen pro klíč.
	var hinge: Node3D = null
	for wid in room["walls"]:
		var wn: Node3D = world.wall_node(int(wid))
		if wn != null and wn.get_node_or_null("Door_%d/Hinge" % oid) != null:
			hinge = wn.get_node("Door_%d/Hinge" % oid)
	check(hinge != null and int(hinge.oid) == oid and hinge.get_node_or_null("LockLamp") != null, "křídlo zná svůj oid a má kontrolku")
	if hinge != null:
		hinge.set_process(false)
		var dc: Vector2 = room["door"]
		a.global_position = home_a + Vector3(30.0, 0, 30.0)
		b.global_position = Vector3(dc.x, home_b.y, dc.y - 0.5)
		hinge._poll = 0.0
		hinge._process(0.3)
		check(hinge.lock_state == String(a.name) and not hinge.want_open and hinge.angle == 0.0 and hinge.lamp_color() == LotDoor.LAMP_OWN,
			"B bez klíče u dveří: zůstanou zavřené, kontrolka jantarová")
		a.global_position = Vector3(dc.x, home_a.y, dc.y + 0.5)
		hinge._poll = 0.0
		hinge._process(0.3)
		check(hinge.want_open and hinge.angle > 0.0, "A s klíčem u dveří: otevřou se")
		a.global_position = inside
	# Navigace a AI důsledek přes skutečné SimAgent._walk.
	var bpos := Vector3((room["out"] as Vector2).x, home_b.y, (room["out"] as Vector2).y - 1.5)
	b.global_position = bpos
	lot.nav_viewer = String(b.name)
	var nb: Dictionary = LotNav.next_point(lot, bpos, inside, {})
	lot.nav_viewer = ""
	check(String(nb["mode"]) == "none", "B se do zamčené místnosti nedostane (none)", String(nb["mode"]))
	check(LotNav.lock_blocker(lot, String(b.name), Vector2(bpos.x, bpos.z), Vector2(inside.x, inside.z)) == String(a.name), "viník: zámek A")
	var dummy := Node3D.new()
	dummy.name = "LockTarget"
	world.add_child(dummy)
	dummy.global_position = inside
	var rel0 := float(b.relationships.get(a.sim_name, 0.0))
	b.current_action = {"id": "test_lock_walk", "label": "Test"}
	b.target = dummy
	b.target_point = inside
	b.walk_elapsed = 0.0
	b._walk(0.1)
	var rel1 := float(b.relationships.get(a.sim_name, 0.0))
	check(b.target == null and b.nav_blocked.has(dummy.get_instance_id()), "_walk: B to vzdá a cíl si zapamatuje jako nedostupný")
	check(is_equal_approx(rel1, clampf(rel0 - 2.0, -100.0, 100.0)) and b.mood.has_moodlet("zamceno_" + String(a.name)), "vztah B→A −2 a moodlet zamčeno", "%.2f → %.2f" % [rel0, rel1])
	check(lot.nav_viewer == "" and lot._nav_unlock == 0, "po chůzi je pohled parcely zase stavební")
	var mem_ok := false
	if b.get("psy") != null:
		for tr in b.psy.memory.traces_about(b.memory_key(a)):
			if String(tr.get("kind", "")) == "rejection":
				mem_ok = true
	check(mem_ok, "B si pamatuje odmítnutí od A (sociální paměť)")
	check(a.mood.has_moodlet("busi_na_dvere"), "A uvnitř slyší bušení")
	b.current_action = {"id": "test_lock_walk", "label": "Test"}
	b.target = dummy
	b.target_point = inside
	b._walk(0.1)
	check(is_equal_approx(float(b.relationships.get(a.sim_name, 0.0)), rel1), "druhé bušení do 6 h vztah dál nezhorší")
	dummy.free()
	# Stavění z pohledu zámků: druhé dveře, B uvnitř; jejich vybourání by B zavřelo za zámkem A.
	a.global_position = home_a
	var bottom: int = int(room["walls"][3])
	var d2: Dictionary = {}
	for at in [4, 5, 3, 6, 2, 7]:
		if lot.check_opening(bottom, "door", at) == "":
			d2 = world.lot_apply_action("open", [bottom, "door", at], "Test")
			break
	check(bool(d2.get("ok", false)), "druhé dveře do místnosti", str(d2))
	if bool(d2.get("ok", false)):
		b.global_position = inside
		var ru: Dictionary = world.lot_apply_action("unopen", [int(d2["oid"])], "Test")
		check(not bool(ru["ok"]) and String(ru["reason"]) == "door_traps" and lot.openings.has(int(d2["oid"])),
			"vybourání jediných dveří, kterými B smí, odmítnuto (door_traps z pohledu zámků)", str(ru))
		b.global_position = home_b
		check(bool(world.lot_apply_action("unopen", [int(d2["oid"])], "Test")["ok"]), "bez B uvnitř jde vybourat")
	# Disk.
	a.global_position = home_a
	b.global_position = home_b
	var snap := JSON.stringify(lot.to_dict())
	var saved: Dictionary = world.save_game("manual")
	check(bool(saved.get("ok", false)), "uloženo", str(saved))
	world.lot_apply_action("lock", [oid, ""], "Test")
	check(lot.lock_of(oid) == "", "odemčeno před načtením")
	var loaded: Dictionary = world.load_game("manual")
	check(bool(loaded.get("ok", false)) and JSON.stringify(world.lot.to_dict()) == snap and world.lot.lock_of(oid) != "", "zámek po načtení z disku", str(loaded))
	world.free()


# ---------------------------------------------------------------- UI

func _test_ui() -> void:
	section("UI: zámek v režimu zařizování")
	var w := _offline_world("LockUiWorld", true)
	await get_tree().process_frame
	var room := _room(w)
	check(not room.is_empty(), "místnost pro UI test")
	if room.is_empty():
		w.queue_free()
		await get_tree().process_frame
		return
	w.toggle_buy_mode()
	var bm = w.buy_mode
	bm.set_process(false)
	bm.selected_oid = int(room["oid"])
	bm._refresh()
	var box: Node = bm._lock_box
	check(box != null and box.visible and box.get_node("LockMe") != null and box.get_node("LockAll") != null and (box.get_node("Unlock") as Button).disabled,
		"u dveří tři tlačítka zámku, Odemknout neaktivní")
	check(String(bm._open_label.text).find("odemčeno") >= 0, "popis ukazuje odemčeno", String(bm._open_label.text))
	var me: String = w.lot_my_sim()
	check(me != "" and me == String(w.sims[w.selected].name), "„já“ offline = vybraná postava")
	bm.lock_selected("me")
	bm._refresh()
	check(w.lot.lock_of(int(room["oid"])) == me and String(bm._open_label.text).find("zamčeno – jen") >= 0 and (box.get_node("LockMe") as Button).disabled,
		"Zamknout pro mě", String(bm._open_label.text))
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_L
	bm._unhandled_input(ev)
	check(w.lot.lock_of(int(room["oid"])) == "", "L odemkne")
	var ev2 := InputEventKey.new()
	ev2.pressed = true
	ev2.keycode = KEY_L
	ev2.shift_pressed = true
	bm._unhandled_input(ev2)
	check(w.lot.lock_of(int(room["oid"])) == "*", "Shift+L pro všechny")
	bm.lock_selected("none")
	check(w.lot.lock_of(int(room["oid"])) == "", "Odemknout")
	var win: Dictionary = {}
	for wid in room["walls"]:
		for at in [2, 3, 5, 6, 7]:
			if w.lot.check_opening(int(wid), "window", at) == "":
				win = w.lot_apply_action("open", [int(wid), "window", at], "Test")
				break
		if not win.is_empty():
			break
	if bool(win.get("ok", false)):
		bm.selected_oid = int(win["oid"])
		bm._refresh()
		check(not box.visible, "u okna tlačítka zámku nejsou")
	else:
		check(false, "okno pro UI test", str(win))
	bm.close()
	await get_tree().process_frame
	w.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- multiplayer (skutečné ENet)

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
	w.net.notice.connect(func(tx: String): notices[bname].append(tx))
	return w


func _client(bname: String, player_name: String) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"audio": false, "hud": false, "camera": false, "visuals": false})


func _test_multiplayer() -> void:
	section("Multiplayer: zámky přes autoritativní server (ENet)")
	clock.total_minutes = 600.0
	var server := _branch("LockServer", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	var a := _client("LockClientA", "Zamykač")
	var b := _client("LockClientB", "Soused")
	check(await wait_until(func(): return a.net.my_sim != "" and b.net.my_sim != "", 8.0), "dva klienti s postavami")
	var room := _room(server)
	check(not room.is_empty(), "server: místnost s dveřmi", str(room))
	if room.is_empty():
		for w in [a, b, server]:
			w.net.shutdown()
		return
	var oid: int = room["oid"]
	server.net.broadcast_lot()
	check(await wait_until(func(): return a.lot.openings.has(oid) and b.lot.openings.has(oid), 4.0), "klienti vidí dveře")
	await wait_seconds(2.2)
	a.request_lot_action("lock", [oid, a.net.my_sim])
	check(await wait_until(func(): return server.lot.lock_of(oid) == a.net.my_sim, 3.0), "A se zamkl pro sebe")
	check(await wait_until(func(): return b.lot.lock_of(oid) == a.net.my_sim and a.lot.lock_of(oid) == a.net.my_sim, 3.0), "zámek replikován oběma klientům")
	var hinge_b: Node = b.wall_node(int(room["walls"][0])).get_node_or_null("Door_%d/Hinge" % oid) if b.wall_node(int(room["walls"][0])) != null else null
	check(hinge_b != null and hinge_b.read_lock() == a.net.my_sim, "LotDoor u klienta B čte zámek A")
	var rej0: int = int(server.net.stats["rejected"])
	notices["LockClientB"].clear()
	b.request_lot_action("lock", [oid, ""])
	check(await wait_until(func(): return notices["LockClientB"].has(String(LotGrid.REASON_TEXT["lock_not_yours"])), 3.0)
		and server.lot.lock_of(oid) == a.net.my_sim, "B cizí zámek neodemkne (lock_not_yours)", str(notices["LockClientB"]))
	await wait_seconds(2.2)
	b.request_lot_action("lock", [oid, "*"])
	check(await wait_until(func(): return notices["LockClientB"].size() >= 2, 3.0) and server.lot.lock_of(oid) == a.net.my_sim, "B ho nepřezamkne ani pro všechny")
	await wait_seconds(2.2)
	notices["LockClientB"].clear()
	b.request_lot_action("lock", [oid, a.net.my_sim])
	check(await wait_until(func(): return notices["LockClientB"].has(String(LotGrid.REASON_TEXT["lock_who"])), 3.0), "B nezamkne za A (lock_who)")
	check(int(server.net.stats["rejected"]) >= rej0 + 3, "server odmítnutí počítá")
	await wait_seconds(2.2)
	a.request_lot_action("lock", [oid, "*"])
	check(await wait_until(func(): return server.lot.lock_of(oid) == "*" and b.lot.lock_of(oid) == "*", 3.0), "A přezamkne pro všechny")
	await wait_seconds(2.2)
	b.request_lot_action("lock", [oid, ""])
	check(await wait_until(func(): return server.lot.lock_of(oid) == "" and a.lot.lock_of(oid) == "", 3.0), "zámek pro všechny odemkne kdokoli z domácnosti")
	# Divák.
	await wait_seconds(2.2)
	var a_peer := -1
	for pid in server.net.players:
		if String(server.net.players[pid].get("sim", "")) == a.net.my_sim:
			a_peer = int(pid)
	check(a_peer > 1, "peer klienta A na serveru")
	if a_peer > 1:
		var saved_sim := String(server.net.players[a_peer]["sim"])
		var r1: int = int(server.net.stats["rejected"])
		server.net.players[a_peer]["sim"] = ""
		a.net._c2s_lot.rpc_id(1, "lock", [oid, "*"])
		var seen: bool = await wait_until(func(): return int(server.net.stats["rejected"]) >= r1 + 1, 4.0)
		server.net.players[a_peer]["sim"] = saved_sim
		check(seen and server.lot.lock_of(oid) == "", "divák nezamyká (skutečné RPC odmítnuto)")
	# Podvržené požadavky.
	await wait_seconds(2.2)
	var r2: int = int(server.net.stats["rejected"])
	var snap := JSON.stringify(server.lot.public_snapshot()["open"])
	a.net._c2s_lot.rpc_id(1, "lock", [oid, "a/b"])
	a.net._c2s_lot.rpc_id(1, "lock", [oid, 5])
	a.net._c2s_lot.rpc_id(1, "lock", ["1", "*"])
	a.net._c2s_lot.rpc_id(1, "lock", [oid])
	a.net._c2s_lot.rpc_id(1, "lock", [oid, "*", "x"])
	a.net._c2s_lot.rpc_id(1, "lock", [oid, "Ana\u202E"])
	var all_seen: bool = await wait_until(func(): return int(server.net.stats["rejected"]) >= r2 + 6, 4.0)
	check(all_seen and JSON.stringify(server.lot.public_snapshot()["open"]) == snap, "6 podvržených požadavků odmítnuto, nic se nezměnilo",
		"%d → %d" % [r2, int(server.net.stats["rejected"])])
	# Uložení serveru.
	await wait_seconds(2.2)
	a.request_lot_action("lock", [oid, a.net.my_sim])
	check(await wait_until(func(): return server.lot.lock_of(oid) == a.net.my_sim, 3.0), "znovu zamčeno pro A")
	# Opuštěný zámek: postava A bez hráče (odešel) → klíč neplatí, odemkne kdokoli z domácnosti.
	if a_peer > 1:
		await wait_seconds(2.2)
		var keep_sim := String(server.net.players[a_peer]["sim"])
		check(server.net.sim_has_player(keep_sim) and not server.net.sim_has_player("Nikdo"), "sim_has_player: A má hráče")
		server.net.players[a_peer]["sim"] = ""
		b.request_lot_action("lock", [oid, ""])
		var freed: bool = await wait_until(func(): return server.lot.lock_of(oid) == "", 3.0)
		server.net.players[a_peer]["sim"] = keep_sim
		check(freed, "zámek postavy bez hráče odemkne B")
		await wait_seconds(2.2)
		a.request_lot_action("lock", [oid, a.net.my_sim])
		check(await wait_until(func(): return server.lot.lock_of(oid) == a.net.my_sim, 3.0), "A se zase zamkl")
	var cap: Dictionary = load("res://scripts/save/game_save.gd").capture(server, true)
	var saved_lock := ""
	if bool(cap.get("ok", false)):
		for o in cap["data"]["lot"]["openings"]:
			if int(o["oid"]) == oid:
				saved_lock = String(o["lock"])
	check(int(cap.get("data", {}).get("lot", {}).get("version", 0)) == 4 and saved_lock == a.net.my_sim, "serverový snímek ukládá zámek (v4)")
	for w in [a, b, server]:
		w.net.shutdown()
	await wait_seconds(0.3)
	for w in [a, b, server]:
		w.get_parent().queue_free()
	await wait_seconds(0.2)
