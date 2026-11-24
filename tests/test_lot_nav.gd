extends "res://tests/test_base.gd"
## B3 (22. 11. 2026): postavy a postavené stěny.
## LotNav na syntetické parcele (obcházení konce zdi, délka trasy, odstup od zdi, nábytek v cestě, plná bariéra,
## zazděná postava – únik, cache a pohyblivý cíl, determinismus, výkon), kontrola cesty při nákupu a přesunu
## (blocks_path, access_unreachable, koberec), wall_traps, a skutečný svět: SimAgent obchází zeď, nedosažitelný
## cíl přeruší a zapamatuje si, zazdít postavu nejde (traps_sim), zazděná postava vyleze.

const Main := preload("res://main.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")
const LotNav := preload("res://scripts/world/lot_nav.gd")

var clock: Node
var save_dir := ""


func _ready() -> void:
	watchdog_seconds = 150.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 1000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-lot-nav-" + str(OS.get_process_id())
	_run.call_deferred()


func _run() -> void:
	_test_direct_and_detour()
	_test_furniture_and_barriers()
	_test_cache_and_determinism()
	_test_performance()
	_test_reach_check()
	_test_wall_traps()
	await _test_world()
	clock.running = false
	finish("test_lot_nav")


# ---------------------------------------------------------------- pomůcky

## Prázdná parcela 25 × 10 m (100 × 40 buněk), volitelně s „domem“ jako v test_lot_walls.
func _syn(fixtures := false):
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	if fixtures:
		lot.add_interior_rect(Rect2(0.0, 0.0, 12.5, 10.0))
		lot.add_static_rect(Rect2(12.5, 0.0, 0.25, 10.0))
		lot.add_fixed("Postel", Vector2(5.0, 5.0), 2.0, 1.0, 0.0, [Vector2(5.0, 6.0)])
	lot.rebuild()
	return lot


## Zeď mimo pravidla (simulace starého savu / chyby) – přímo do dat parcely.
func _force_wall(lot, x0: int, z0: int, x1: int, z1: int) -> void:
	var wid: int = lot.next_wid
	lot.next_wid += 1
	lot.walls[wid] = {"wid": wid, "x0": x0, "z0": z0, "x1": x1, "z1": z1, "built_at": 0.0, "paid": 0}
	lot.revision += 1


func _crosses_wall(lot, a: Vector2, b: Vector2) -> bool:
	for wid in lot.walls:
		var ab: Array = lot.wall_world(lot.walls[wid])
		if Geometry2D.segment_intersects_segment(a, b, ab[0], ab[1]) != null:
			return true
	return false


func _wall_dist(lot, p: Vector2) -> float:
	var best := INF
	for wid in lot.walls:
		var ab: Array = lot.wall_world(lot.walls[wid])
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ab[0], ab[1])))
	return best


## Simulovaná chůze krokem `step` přes LotNav.next_point. Vrací ok, délku, body, režimy, křížení zdi, odstup.
func _walk(lot, a: Vector2, b: Vector2, step := 0.1, max_steps := 3000, cache := {}) -> Dictionary:
	var pos := a
	var pts: Array = [a]
	var length := 0.0
	var crossed := false
	var min_clear := INF
	var modes := {}
	for i in max_steps:
		var nv: Dictionary = LotNav.next_point(lot, Vector3(pos.x, 0.0, pos.y), Vector3(b.x, 0.0, b.y), cache)
		modes[String(nv["mode"])] = int(modes.get(String(nv["mode"]), 0)) + 1
		if String(nv["mode"]) == "none":
			return {"ok": false, "none": true, "len": length, "pts": pts, "crossed": crossed, "clear": min_clear, "modes": modes}
		var p := Vector2(nv["point"].x, nv["point"].z)
		var d := pos.distance_to(p)
		var np := p if d <= step else pos + (p - pos) / d * step
		if String(nv["mode"]) != "escape" and _crosses_wall(lot, pos, np):
			crossed = true
		length += pos.distance_to(np)
		pos = np
		pts.append(pos)
		if not lot.walls.is_empty():
			min_clear = minf(min_clear, _wall_dist(lot, pos))
		if pos.distance_to(b) < 0.0005:
			return {"ok": true, "none": false, "len": length, "pts": pts, "crossed": crossed, "clear": min_clear, "modes": modes}
	return {"ok": false, "none": false, "len": length, "pts": pts, "crossed": crossed, "clear": min_clear, "modes": modes}


## Prošla trasa jen průchozími buňkami (kromě buňky startu a cíle)?
func _route_cells_ok(lot, pts: Array, a: Vector2, b: Vector2) -> String:
	var ca: Vector2i = lot.cell_of_world(a)
	var cb: Vector2i = lot.cell_of_world(b)
	for p in pts:
		var c: Vector2i = lot.cell_of_world(p)
		if c == ca or c == cb or not lot._in_grid(c.x, c.y):
			continue
		if not lot._walkable(lot._idx(c.x, c.y)):
			return "%s (buňka %s)" % [str(p), str(c)]
	return ""


# ---------------------------------------------------------------- obcházení zdi

func _test_direct_and_detour() -> void:
	section("Obcházení postavené zdi (syntetická parcela)")
	var lot = _syn()
	var cache := {}
	var nv: Dictionary = LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(15, 0, 4), cache)
	check(String(nv["mode"]) == "direct" and Vector3(nv["point"]).is_equal_approx(Vector3(15, 0, 4)) and not cache.has("pts"),
		"bez zdí jde postava rovně (beze změny chování)")
	var r: Dictionary = lot.build_wall(40, 0, 40, 32, 0.0, "Test")
	check(bool(r["ok"]), "zeď x = 10 m, z 0–8 m postavena", str(r))
	nv = LotNav.next_point(lot, Vector3(5, 0, 9), Vector3(15, 0, 9), cache)
	check(String(nv["mode"]) == "direct", "zeď mimo přímou úsečku nic nemění")
	nv = LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(15, 0, 4), cache)
	check(String(nv["mode"]) == "route", "zeď na přímce → trasa kolem")
	var w := _walk(lot, Vector2(5, 4), Vector2(15, 4))
	check(bool(w["ok"]), "postava dojde na druhou stranu", str(w["modes"]))
	check(not bool(w["crossed"]), "trasa nikdy nepřekročí zeď")
	check(float(w["clear"]) >= LotNav.CLEAR - 0.001, "odstup od zdi aspoň %.2f m (%.3f)" % [LotNav.CLEAR, float(w["clear"])])
	var ideal := Vector2(5, 4).distance_to(Vector2(10, 8)) * 2.0
	check(float(w["len"]) >= ideal - 0.01 and float(w["len"]) <= ideal * 1.12,
		"délka trasy blízko nejkratší kolem konce zdi (%.2f m, ideál %.2f m)" % [float(w["len"]), ideal])
	var w2 := _walk(lot, Vector2(15, 4), Vector2(5, 4))
	check(bool(w2["ok"]) and not bool(w2["crossed"]) and absf(float(w2["len"]) - float(w["len"])) < 0.3,
		"opačný směr: stejně dlouhá platná trasa (%.2f m)" % float(w2["len"]))
	# Postava stojí těsně u zdi (5 cm) a odchází od ní – nesmí uvíznout.
	var w3 := _walk(lot, Vector2(9.95, 4), Vector2(6, 4))
	check(bool(w3["ok"]) and int(w3["modes"].get("direct", 0)) > 0, "od zdi se dá odejít, i když postava stojí v ochranném pásu")
	var w4 := _walk(lot, Vector2(9.95, 4), Vector2(12, 4))
	check(bool(w4["ok"]) and not bool(w4["crossed"]), "těsně u zdi a cíl za ní → obejde, neproleze")
	# Postava mimo parcelu (ulice) jde dovnitř za zeď.
	var w5 := _walk(lot, Vector2(-1.0, 4), Vector2(15, 4))
	check(bool(w5["ok"]) and not bool(w5["crossed"]), "příchod z ulice (mimo mřížku) kolem zdi")


func _test_furniture_and_barriers() -> void:
	section("Nábytek v cestě, plná bariéra, zazděná postava")
	var lot = _syn(true)
	var r: Dictionary = lot.build_wall(28, 0, 28, 28, 0.0, "Test")
	check(bool(r["ok"]), "zeď x = 7 m, z 0–7 m (vedle postele)", str(r))
	var a := Vector2(2, 2)
	var b := Vector2(9, 2)
	# Kontrola smyslu testu: úsečka k rohu zdi by vedla postelí.
	check(lot._walkable(lot._idx(20, 19)) == false, "postel blokuje buňky (fixture)")
	var w := _walk(lot, a, b)
	check(bool(w["ok"]) and not bool(w["crossed"]), "trasa kolem zdi dojde")
	var bad := _route_cells_ok(lot, w["pts"], a, b)
	check(bad == "", "trasa neprochází postelí ani zdí domu", bad)
	# Plná bariéra přes celou výšku parcely: obě strany jsou od ulice dosažitelné, ale ne navzájem.
	var lot2 = _syn()
	var rb: Dictionary = lot2.build_wall(40, 0, 40, 40, 0.0, "Test")
	check(bool(rb["ok"]), "zeď přes celou parcelu (10 m) postavena", str(rb))
	var cache := {}
	var nv: Dictionary = LotNav.next_point(lot2, Vector3(5, 0, 4), Vector3(15, 0, 4), cache)
	check(String(nv["mode"]) == "none", "cíl za plnou zdí → none (nikdy skrz zeď)")
	check(Vector3(nv["point"]).is_equal_approx(Vector3(5, 0, 4)), "při none se postava nehne")
	# Grok #565: zeď postavená UPROSTŘED chůze → přeplánování a přerušení, nikdy průchod.
	var lot4 = _syn()
	lot4.build_wall(40, 0, 40, 32, 0.0, "Test")
	var c4 := {}
	var pos4 := Vector2(5, 4)
	for i in 20:
		var s4: Dictionary = LotNav.next_point(lot4, Vector3(pos4.x, 0, pos4.y), Vector3(15, 0, 4), c4)
		var q4 := Vector2(s4["point"].x, s4["point"].z)
		pos4 = pos4 + (q4 - pos4).limit_length(0.1)
	var rb4: Dictionary = lot4.build_wall(40, 32, 40, 40, 0.0, "Test")
	check(bool(rb4["ok"]), "během chůze dostavěna zeď až k okraji parcely", str(rb4))
	var s5: Dictionary = LotNav.next_point(lot4, Vector3(pos4.x, 0, pos4.y), Vector3(15, 0, 4), c4)
	check(String(s5["mode"]) == "none", "zeď postavená během chůze → none (postava to vzdá)")
	# Zazděná postava (starý save): box kolem ní bez spojení s ulicí → únik, žádný softlock.
	var lot3 = _syn()
	_force_wall(lot3, 16, 12, 24, 12)
	_force_wall(lot3, 16, 20, 24, 20)
	_force_wall(lot3, 16, 12, 16, 20)
	_force_wall(lot3, 24, 12, 24, 20)
	var esc := _walk(lot3, Vector2(5, 4), Vector2(15, 4))
	check(bool(esc["ok"]) and int(esc["modes"].get("escape", 0)) > 0, "postava uvnitř uzavřeného boxu unikne (escape)")
	var into := _walk(lot3, Vector2(15, 4), Vector2(5, 4))
	check(not bool(into["ok"]) and bool(into["none"]), "do uzavřeného boxu zvenku se nedá dojít (none)")


func _test_cache_and_determinism() -> void:
	section("Cache trasy, pohyblivý cíl, determinismus")
	var lot = _syn()
	lot.build_wall(40, 0, 40, 32, 0.0, "Test")
	var cache := {}
	var w := _walk(lot, Vector2(5, 4), Vector2(15, 4), 0.1, 3000, cache)
	check(bool(w["ok"]) and int(cache.get("plans", 0)) >= 1 and int(cache.get("plans", 0)) <= 2,
		"celá chůze = nejvýš 2 plánování (%d)" % int(cache.get("plans", 0)))
	var c2 := {}
	LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(15.0, 0, 4.0), c2)
	var p0 := int(c2.get("plans", 0))
	for i in 20:
		LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(15.0 + 0.01 * float(i % 5), 0, 4.0 + 0.01 * float(i % 3)), c2)
	check(int(c2.get("plans", 0)) == p0, "cíl se hýbe uvnitř jedné buňky → žádné nové plánování")
	var nv: Dictionary = LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(17.0, 0, 4.0), c2)
	check(int(c2.get("plans", 0)) == p0 + 1 and String(nv["mode"]) == "route", "cíl v jiné buňce → nové plánování")
	lot.build_wall(60, 0, 60, 20, 0.0, "Test")
	LotNav.next_point(lot, Vector3(5, 0, 4), Vector3(17.0, 0, 4.0), c2)
	check(int(c2.get("plans", 0)) == p0 + 2, "nová zeď (revize parcely) → nové plánování")
	var wa := _walk(lot, Vector2(5, 4), Vector2(18, 3))
	var wb := _walk(lot, Vector2(5, 4), Vector2(18, 3))
	check(bool(wa["ok"]) and var_to_str(wa["pts"]) == var_to_str(wb["pts"]), "stejný stav = stejná trasa bod po bodu")
	check(not bool(wa["crossed"]), "trasa kolem dvou zdí bez překročení")
	# Audit Gemini 22. 11.: postava na rohu, další bod trasy za zdí (pohyblivý cíl) → přeplánuje, neuvízne.
	var c3 := {}
	var start3 := Vector3(9.875, 0, 8.125)
	LotNav.next_point(lot, start3, Vector3(13, 0, 4), c3)
	var plans3 := int(c3.get("plans", 0))
	c3["pts"] = [Vector2(9.875, 8.125), Vector2(10.125, 4.0), Vector2(13, 4)]
	var nv3: Dictionary = LotNav.next_point(lot, start3, Vector3(13, 0, 4), c3)
	var p3 := Vector2(nv3["point"].x, nv3["point"].z)
	check(int(c3.get("plans", 0)) == plans3 + 1 and String(nv3["mode"]) == "route" and p3.distance_to(Vector2(9.875, 8.125)) > 0.05 \
		and LotNav.visible(lot, Vector2(9.875, 8.125), p3), "uvíznutí na rohu → přeplánování a viditelný další bod")


func _test_performance() -> void:
	section("Výkon")
	var lot = _syn()
	# Bludiště: střídavé zdi shora a zdola.
	for k in 6:
		var x := 12 + k * 12
		if k % 2 == 0:
			lot.build_wall(x, 0, x, 32, 0.0, "Test")
		else:
			lot.build_wall(x, 8, x, 40, 0.0, "Test")
	check(lot.walls.size() == 6, "bludiště 6 zdí")
	var t0 := Time.get_ticks_usec()
	var res: Dictionary
	for i in 10:
		res = LotNav.plan(lot, Vector2(1, 5), Vector2(24, 5))
	var per := float(Time.get_ticks_usec() - t0) / 10.0
	check(String(res["mode"]) == "route", "bludištěm vede cesta")
	check(per < 60000.0, "plán trasy bludištěm < 60 ms (%.2f ms)" % (per / 1000.0))
	var w := _walk(lot, Vector2(1, 5), Vector2(24, 5), 0.1, 6000)
	check(bool(w["ok"]) and not bool(w["crossed"]), "bludištěm se dá projít bez překročení zdi (%.1f m)" % float(w["len"]))
	var cache := {}
	LotNav.next_point(lot, Vector3(1, 0, 5), Vector3(24, 0, 5), cache)
	t0 = Time.get_ticks_usec()
	for i in 200:
		LotNav.next_point(lot, Vector3(1, 0, 5), Vector3(24, 0, 5), cache)
	var frame := float(Time.get_ticks_usec() - t0) / 200.0
	check(frame < 1000.0, "krok chůze s cache < 1 ms (%.3f ms)" % (frame / 1000.0))


# ---------------------------------------------------------------- nákup a cesta

func _test_reach_check() -> void:
	section("Nákup a přesun nesmí odříznout cestu")
	var lot = _syn(true)
	# Pokoj kolem postele s otvorem 1 m v pravé stěně (z 6,5–7,5 m).
	for wall in [[12, 12, 32, 12], [12, 34, 32, 34], [12, 12, 12, 34], [32, 12, 32, 26], [32, 30, 32, 34]]:
		var rw: Dictionary = lot.build_wall(wall[0], wall[1], wall[2], wall[3], 0.0, "Test")
		check(bool(rw["ok"]), "zeď pokoje %s" % str(wall), str(rw))
	check(lot.access_reachable(Vector2(5.0, 6.0)), "postel je otvorem dosažitelná")
	check(lot.check("armchair_wingback", 32, 26, 0) == "", "křeslo do otvoru projde pravidly umístění (check)")
	check(lot.reach_check("armchair_wingback", 32, 26, 0, 0) == "blocks_path", "… ale zatarasilo by cestu k posteli")
	var funds0: int = lot.funds
	var r: Dictionary = lot.buy("armchair_wingback", 32, 26, 0, 0.0, "Test")
	check(not bool(r["ok"]) and String(r["reason"]) == "blocks_path" and lot.funds == funds0 and lot.items.is_empty(),
		"nákup odmítnut: blocks_path, peníze ani položky beze změny", str(r))
	check(LotGrid.REASON_TEXT.has("blocks_path") and LotGrid.REASON_TEXT.has("access_unreachable") and LotGrid.REASON_TEXT.has("traps_sim"),
		"nové důvody mají český text")
	# Koberec průchodnost nemění.
	var rr: Dictionary = lot.buy("rug_wool", 32, 24, 0, 0.0, "Test")
	check(bool(rr["ok"]), "koberec do otvoru lze", str(rr))
	# Uzavřený prázdný box a předmět uvnitř.
	for wall in [[36, 4, 44, 4], [36, 12, 44, 12], [36, 4, 36, 12], [44, 4, 44, 12]]:
		var rb: Dictionary = lot.build_wall(wall[0], wall[1], wall[2], wall[3], 0.0, "Test")
		check(bool(rb["ok"]), "zeď boxu %s" % str(wall), str(rb))
	check(lot.check("armchair_wingback", 37, 5, 0) == "", "křeslo do boxu projde pravidly umístění")
	var rx: Dictionary = lot.buy("armchair_wingback", 37, 5, 0, 0.0, "Test")
	check(not bool(rx["ok"]) and String(rx["reason"]) == "access_unreachable", "do zazděného boxu nic s přístupem nekoupíš", str(rx))
	var rp: Dictionary = lot.buy("plant_monstera", 38, 6, 0, 0.0, "Test")
	check(bool(rp["ok"]), "dekorace bez bodu použití do boxu jde (květina)", str(rp))
	# Přesun.
	var ok: Dictionary = lot.buy("armchair_wingback", 4, 2, 0, 0.0, "Test")
	check(bool(ok["ok"]), "křeslo koupeno mimo pokoj", str(ok))
	var uid := int(ok.get("uid", 0))
	var mv: Dictionary = lot.move(uid, 32, 26, 0, 0.0, "Test")
	check(not bool(mv["ok"]) and String(mv["reason"]) == "blocks_path", "přesun do otvoru odmítnut", str(mv))
	check(int(lot.items[uid]["cx"]) == 4 and int(lot.items[uid]["cz"]) == 2, "odmítnutý přesun nechá křeslo na místě")
	var mv2: Dictionary = lot.move(uid, 6, 2, 0, 0.0, "Test")
	check(bool(mv2["ok"]), "přesun jinam projde", str(mv2))
	check(lot.reach_check("armchair_wingback", 6, 2, 0, uid) == "", "přesun na vlastní místo neblokuje sám sebe")
	var tb := Time.get_ticks_usec()
	lot.reach_check("armchair_wingback", 4, 2, 0, uid)
	check(Time.get_ticks_usec() - tb < 80000, "kontrola cesty na 100 × 40 < 80 ms")


func _test_wall_traps() -> void:
	section("Zeď nesmí zazdít postavu")
	var lot = _syn()
	for wall in [[16, 12, 24, 12], [16, 20, 24, 20], [16, 12, 16, 20]]:
		lot.build_wall(wall[0], wall[1], wall[2], wall[3], 0.0, "Test")
	var inside := Vector2(5.0, 4.0)
	var outside := Vector2(2.0, 2.0)
	check(lot.wall_traps(24, 12, 24, 20, [inside]), "poslední stěna boxu by zazdila postavu uvnitř")
	check(not lot.wall_traps(24, 12, 24, 20, [outside]), "postava venku zazděná není")
	check(not lot.wall_traps(24, 12, 24, 20, []), "bez postav nic")
	check(not lot.wall_traps(24.0, 12, 24, 20, [inside]) and not lot.wall_traps(20, 12, 24, 20, [inside]),
		"neplatná stěna se nehodnotí (odmítne ji build_wall)")
	check(not lot.wall_traps(24, 12, 24, 20, [Vector2(NAN, 1.0), "x", null]), "nesmyslné polohy se přeskočí")
	check(lot.check_wall(24, 12, 24, 20) == "", "samotná pravidla zdi by box dovolila (prázdný)")


# ---------------------------------------------------------------- skutečný svět

func _offline_world(wname: String) -> Node3D:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = wname
	w.net_config = {"mode": "offline", "audio": false, "camera": false, "visuals": false, "hud": false,
		"autoload": false, "autosave": false, "save_directory": save_dir, "clock": clock}
	add_child(w)
	return w


## Nechá postavu jít k bodu `goal` (přes skutečný SimAgent._walk) a sleduje, jestli překročí zeď.
func _agent_walk(world, sim, obj, goal: Vector3, max_steps := 4000) -> Dictionary:
	sim.player_queue.clear()
	var act := {"id": "test_walk", "label": "Test chůze", "duration": 5.0, "effects": {}, "tags": [], "posture": "stand"}
	sim.by_player = true
	sim.start_plan(act, obj)
	sim.target_point = goal
	var crossed := false
	var length := 0.0
	var steps := 0
	while sim.state == sim.State.WALKING and steps < max_steps:
		var before := Vector2(sim.global_position.x, sim.global_position.z)
		sim._walk(0.03)
		var after := Vector2(sim.global_position.x, sim.global_position.z)
		if not sim._nav_escaped and _crosses_wall(world.lot, before, after):
			crossed = true
		length += before.distance_to(after)
		steps += 1
	var arrived: bool = sim.state == sim.State.ACTING and Vector2(sim.global_position.x, sim.global_position.z).distance_to(Vector2(goal.x, goal.z)) < 0.01
	if sim.state == sim.State.ACTING:
		sim._finish(true)
	return {"arrived": arrived, "crossed": crossed, "len": length, "steps": steps, "state": int(sim.state)}


func _test_world() -> void:
	section("Skutečný svět: SimAgent a postavené zdi")
	var world := _offline_world("NavWorld")
	await get_tree().process_frame
	var lot = world.lot
	var sims: Array = world.sims
	check(sims.size() >= 2, "ve světě jsou postavy")
	if sims.size() < 2:
		world.free()
		return
	var jana = sims[0]
	var eli = sims[sims.size() - 1]
	var obj = world.get_smart_objects()[0]
	# Severní dvůr: zeď x = -2 m, z -12 … -7 m.
	var a: Vector2i = lot.snap_lattice(Vector2(-2.0, -12.0))
	var b: Vector2i = lot.snap_lattice(Vector2(-2.0, -7.0))
	var rw: Dictionary = world.lot_apply_action("wall", [a.x, a.y, b.x, b.y], "Test")
	check(bool(rw["ok"]), "zeď na dvoře postavena přes autoritu světa", str(rw))
	jana.global_position = Vector3(-5.0, jana.global_position.y, -9.0)
	var res := _agent_walk(world, jana, obj, Vector3(1.0, jana.global_position.y, -9.0))
	check(bool(res["arrived"]), "postava obešla zeď a došla k cíli", str(res))
	check(not bool(res["crossed"]), "SimAgent zeď nepřekročil")
	check(float(res["len"]) > 6.5, "šla oklikou, ne rovně (%.2f m > 6 m přímo)" % float(res["len"]))
	# Box na dvoře x 5–7 m, z -10 … -8 m; Eliška stojí uvnitř.
	var c00: Vector2i = lot.snap_lattice(Vector2(5.0, -10.0))
	var c11: Vector2i = lot.snap_lattice(Vector2(7.0, -8.0))
	var sides := [[c00.x, c00.y, c11.x, c00.y], [c00.x, c11.y, c11.x, c11.y], [c00.x, c00.y, c00.x, c11.y]]
	for s in sides:
		var rs: Dictionary = world.lot_apply_action("wall", s, "Test")
		check(bool(rs["ok"]), "stěna boxu %s" % str(s), str(rs))
	var eli_home: Vector3 = eli.global_position
	eli.global_position = Vector3(6.0, eli.global_position.y, -9.0)
	var last := [c11.x, c00.y, c11.x, c11.y]
	var rt: Dictionary = world.lot_apply_action("wall", last, "Test")
	check(not bool(rt["ok"]) and String(rt["reason"]) == "traps_sim", "zazdít postavu nejde (traps_sim)", str(rt))
	eli.global_position = eli_home
	var rt2: Dictionary = world.lot_apply_action("wall", last, "Test")
	check(bool(rt2["ok"]), "prázdný box se uzavřít dá", str(rt2))
	# Nedosažitelný cíl uvnitř boxu.
	jana.global_position = Vector3(2.0, jana.global_position.y, -9.0)
	var res2 := _agent_walk(world, jana, obj, Vector3(6.0, jana.global_position.y, -9.0))
	check(not bool(res2["arrived"]) and int(res2["state"]) == int(jana.State.IDLE), "cíl v zazděném boxu → postava to vzdá", str(res2))
	check(not bool(res2["crossed"]), "… a do boxu neproleze")
	check(jana.nav_blocked.has(obj.get_instance_id()), "předmět si zapamatovala jako nedosažitelný")
	check(jana.mood.has_moodlet("nedostupne") if jana.mood.has_method("has_moodlet") else true, "nálada: nedá se tam dojít")
	var filtered: Array = jana._reachable_objects(world.get_smart_objects())
	check(filtered.size() == world.get_smart_objects().size() - 1 and not filtered.has(obj), "AI ho teď nevybírá")
	clock.total_minutes += jana.NAV_BLOCK_MINUTES + 1.0
	check(jana._reachable_objects(world.get_smart_objects()).size() == world.get_smart_objects().size() and jana.nav_blocked.is_empty(),
		"po 2 herních hodinách to zkusí znovu")
	# Zazděná postava (box postavený mimo pravidla) vyleze.
	eli.global_position = Vector3(6.0, eli.global_position.y, -9.0)
	var res3 := _agent_walk(world, eli, obj, Vector3(9.0, eli.global_position.y, -6.0))
	check(bool(res3["arrived"]), "zazděná postava se dostane ven (únik, žádný softlock)", str(res3))
	check(eli._nav_escaped, "únik je označený (nálada „zazděný“)")
	# Bez postavených zdí se chůze nezměnila: rovně.
	for wid in lot.sorted_wids():
		world.lot_apply_action("unwall", [int(wid)], "Test")
	check(lot.walls.is_empty(), "všechny zdi zbourány")
	jana.global_position = Vector3(-5.0, jana.global_position.y, -9.0)
	var res4 := _agent_walk(world, jana, obj, Vector3(1.0, jana.global_position.y, -9.0))
	check(bool(res4["arrived"]) and absf(float(res4["len"]) - 6.0) < 0.05, "bez zdí přímá chůze jako dřív (%.3f m)" % float(res4["len"]))
	world.free()
