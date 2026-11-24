extends "res://tests/test_base.gd"
## B4 (23. 11. 2026): dveře a okna jako otvory ve stěnách (LotGrid v3).
## Pravidla otvorů (typy, ostění, odstupy, T-spoje, prostor dveří, peníze, limit), navigace (BFS, pathfinder,
## LotNav přes rozsah dveří, okno neprůchozí, uzavřená místnost, vybourání dveří nesmí odříznout cestu ani zavřít
## postavu), předměty vs. dveře, zbourání stěny s otvory a vratky, save v3 + migrace v2 + validace + obnova,
## fuzz veřejných snímků, výkon, uzly ve světě (kusy stěny, kolize bez rozsahu dveří, křídlo se otevírá u postavy,
## save/load z disku, door_traps přes autoritu světa), UI nástroje Dveře/Okno a skutečné ENet.

const Main := preload("res://main.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")
const LotNav := preload("res://scripts/world/lot_nav.gd")
const Pathfinder := preload("res://scripts/world/lot_pathfinder.gd")

var clock: Node
var save_dir := ""
var port := 0
var notices := {}


func _ready() -> void:
	watchdog_seconds = 170.0
	randomize()
	port = 27000 + randi() % 700
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 1000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-lot-doors-" + str(OS.get_process_id())
	_run.call_deferred()


func _run() -> void:
	_test_rules()
	_test_navigation()
	_test_items_and_doors()
	_test_removal_and_refunds()
	_test_save_and_migration()
	_test_public_fuzz()
	_test_performance()
	await _test_world()
	await _test_ui()
	await _test_multiplayer()
	clock.running = false
	finish("test_lot_doors")


## Syntetická parcela 25 × 10 m (100 × 40 buněk): vlevo „dům“ (vnitřek x < 12,5 m) se zdí ve sloupci
## buněk 50, postel 2 × 1 m na (5, 5) s bodem použití (5, 6) – stejná jako v test_lot_walls.
func _syn(fixtures := true):
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	if fixtures:
		lot.add_interior_rect(Rect2(0.0, 0.0, 12.5, 10.0))
		lot.add_static_rect(Rect2(12.5, 0.0, 0.25, 10.0))
		lot.add_fixed("Postel", Vector2(5.0, 5.0), 2.0, 1.0, 0.0, [Vector2(5.0, 6.0)])
	lot.rebuild()
	return lot


## Tři strany krabice kolem postele: 1 horní (12,14)-(28,14), 2 levá, 3 pravá. Vrací true, když vše prošlo.
func _box3(lot) -> bool:
	return bool(lot.build_wall(12, 14, 28, 14, 1000.0)["ok"]) and bool(lot.build_wall(12, 14, 12, 30, 1000.0)["ok"]) \
		and bool(lot.build_wall(28, 14, 28, 30, 1000.0)["ok"])


func _json(lot) -> String:
	return JSON.stringify(lot.to_dict())


## Protne úsečka a→b některý PLNÝ úsek stěny (osu)?
func _crosses_solid(lot, a: Vector2, b: Vector2) -> bool:
	for wid in lot.walls:
		for seg in lot.wall_segments(lot.walls[wid]):
			if Geometry2D.segment_intersects_segment(a, b, seg[0], seg[1]) != null:
				return true
	return false


# ---------------------------------------------------------------- pravidla

func _test_rules() -> void:
	section("Pravidla dveří a oken")
	var lot = _syn()
	check(_box3(lot), "tři stěny krabice postavené")
	check(lot.check_opening(1.0, "door", 6) == "opening_bad" and lot.check_opening("1", "door", 6) == "opening_bad"
		and lot.check_opening(1, "gate", 6) == "opening_bad" and lot.check_opening(1, "door", 6.0) == "opening_bad"
		and lot.check_opening(1, 7, 6) == "opening_bad" and lot.check_opening(null, null, null) == "opening_bad",
		"jiné typy a neznámý druh odmítnuty")
	check(lot.check_opening(99, "door", 6) == "unknown_wid", "neexistující stěna")
	check(lot.check_opening(1, "door", 0) == "opening_edge", "bez ostění u začátku stěny")
	check(lot.check_opening(1, "door", 12) == "opening_edge" and lot.check_opening(1, "door", -3) == "opening_edge", "přes konec stěny / záporný posun")
	check(lot.check_opening(1, "door", 11) == "" and lot.check_opening(1, "door", 1) == "", "krajní platné polohy (ostění 0,25 m)")
	check(lot.check_opening(1, "window_wide", 10) == "opening_edge" and lot.check_opening(1, "window_wide", 9) == "", "široké okno 1,5 m potřebuje víc místa")
	# T-spoj v rozsahu otvoru.
	var t = lot.build_wall(20, 14, 20, 8, 1000.0)
	check(bool(t["ok"]), "T-spoj (20,14)-(20,8) do horní stěny", str(t))
	check(lot.check_opening(1, "door", 6) == "opening_junction", "otvor přes T-spoj odmítnut")
	check(lot.check_opening(1, "door", 4) == "opening_junction", "T-spoj na kraji otvoru se počítá (včetně okraje)")
	check(lot.check_opening(1, "door", 9) == "", "otvor vedle T-spoje lze")
	lot.remove_wall(int(t["wid"]), 1000.0)
	# Stavba.
	var f0: int = lot.funds
	var rev0: int = lot.revision
	var r: Dictionary = lot.build_opening(1, "door", 6, 1000.0, "Test")
	check(bool(r["ok"]) and int(r["price"]) == 420 and lot.funds == f0 - 420 and lot.revision == rev0 + 1, "dveře za 420 kr, revize", str(r))
	check(String(lot.ledger[-1]["kind"]) == "opening" and String(lot.ledger[-1]["id"]) == "door" and int(lot.ledger[-1]["amount"]) == -420,
		"záznam v knize transakcí")
	var o: Dictionary = lot.openings[int(r["oid"])]
	check(int(o["wid"]) == 1 and String(o["kind"]) == "door" and int(o["at"]) == 6 and (o as Dictionary).size() == 7 and String(o["lock"]) == "",
		"záznam otvoru (B4b: + odemčený zámek)")
	# Odstupy.
	check(lot.check_opening(1, "window", 10) == "opening_overlap", "okno těsně u dveří (bez buňky zdi) odmítnuto")
	check(lot.check_opening(1, "window", 3) == "opening_overlap", "okno přes dveře odmítnuto")
	check(lot.check_opening(1, "window", 11) == "", "okno o buňku dál lze")
	# Nová stěna nesmí vést do otvoru.
	check(lot.check_wall(20, 14, 20, 8) == "wall_at_opening", "stěna napojená do dveří odmítnuta")
	check(lot.check_wall(18, 14, 18, 8) == "wall_at_opening", "… i na hraně otvoru")
	check(lot.check_wall(17, 14, 17, 8) == "", "o buňku vedle otvoru lze")
	# Prostor dveří: zeď domu (statická buňka) před dveřmi.
	var house = _syn()
	check(house.check_wall(52, 4, 52, 20) == "", "stěna souběžně se zdí domu (o 0,5 m dál)")
	house.build_wall(52, 4, 52, 20, 1000.0)
	check(house.check_opening(1, "door", 6) == "door_blocked", "dveře do zdi domu odmítnuty")
	check(house.check_opening(1, "window", 6) == "", "okno na stejném místě lze (prostor před ním netřeba)")
	# Peníze.
	var poor = _syn()
	poor.build_wall(60, 20, 76, 20, 1000.0)
	poor.funds = 100
	var rp: Dictionary = poor.build_opening(1, "door", 6, 1000.0)
	check(not bool(rp["ok"]) and String(rp["reason"]) == "funds" and poor.openings.is_empty() and poor.funds == 100, "bez peněz se neosazuje")
	check(String(poor.build_opening(1, "door", 0, 1000.0)["reason"]) == "opening_edge", "neplatné místo hlášeno dřív než peníze")
	# Limit počtu otvorů.
	var full = LotGrid.new()
	full.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	full.rebuild()
	full.funds = LotGrid.MAX_FUNDS
	var built := 0
	for row in 6:
		for col in 5:
			var wr: Dictionary = full.build_wall(col * 20, 2 + row * 6, col * 20 + 16, 2 + row * 6, 1000.0)
			if not bool(wr["ok"]):
				continue
			for at in [1, 6, 11]:
				if bool(full.build_opening(int(wr["wid"]), "window", at, 1000.0)["ok"]):
					built += 1
	check(built == LotGrid.MAX_OPENINGS, "64 otvorů osazeno", str(built))
	var spare := int(full.sorted_wids()[-1])
	check(full.check_opening(spare, "window", 11) in ["opening_limit", "opening_overlap"] and full.openings.size() == LotGrid.MAX_OPENINGS,
		"strop 64 otvorů na parcelu")
	var nw: Dictionary = full.build_wall(0, 39, 16, 39, 1000.0)
	check(bool(nw["ok"]) and full.check_opening(int(nw["wid"]), "window", 6) == "opening_limit", "na nové stěně už otvor nejde (limit)")
	check(String(lot.remove_opening("1", 1000.0)["reason"]) == "unknown_oid" and String(lot.remove_opening(999, 1000.0)["reason"]) == "unknown_oid",
		"vybourání neexistujícího otvoru")
	var a = _syn()
	var b = _syn()
	for l in [a, b]:
		_box3(l)
		l.build_opening(1, "door", 6, 10.0)
		l.build_opening(2, "window", 4, 20.0)
		l.remove_opening(2, 30.0)
		l.build_opening(3, "window_wide", 5, 40.0)
	check(_json(a) == _json(b), "stejné operace = stejný stav (deterministické)")


# ---------------------------------------------------------------- navigace

func _test_navigation() -> void:
	section("Navigace přes dveře")
	var lot = _syn()
	_box3(lot)
	check(lot.check_wall(12, 30, 28, 30) == "seals_off", "bez dveří by čtvrtá stěna postel odřízla")
	var r: Dictionary = lot.build_opening(1, "door", 6, 1000.0)
	check(bool(r["ok"]), "dveře do horní stěny", str(r))
	var close: Dictionary = lot.build_wall(12, 30, 28, 30, 1000.0)
	check(bool(close["ok"]), "s dveřmi jde místnost uzavřít", str(close))
	check(lot.access_reachable(Vector2(5.0, 6.0)), "postel v uzavřené místnosti je dosažitelná přes dveře")
	lot._build_edges({})
	var open_ok := true
	for x in range(18, 22):
		if lot._hedge[14 * lot.gw + x] != 0:
			open_ok = false
	check(open_ok and lot._hedge[14 * lot.gw + 17] == 1 and lot._hedge[14 * lot.gw + 22] == 1, "hrany v rozsahu dveří volné, ostění plné")
	var path: Array = Pathfinder.find_path(lot, Vector2i(20, 2), Vector2i(20, 24))
	var through := false
	var leak := false
	for i in range(1, path.size()):
		var p0: Vector2i = path[i - 1]
		var p1: Vector2i = path[i]
		if (p0.y == 13 and p1.y == 14) or (p0.y == 14 and p1.y == 13):
			if p1.x >= 18 and p1.x <= 21:
				through = true
			else:
				leak = true
	check(not path.is_empty() and through and not leak, "nejkratší cesta po buňkách vede dveřmi", str(path.size()))
	var segs: Array = lot.wall_segments(lot.walls[1])
	check(segs.size() == 2 and (segs[0][1] as Vector2).is_equal_approx(Vector2(4.5, 3.5)) and (segs[1][0] as Vector2).is_equal_approx(Vector2(5.5, 3.5)),
		"plné úseky stěny kolem dveří", str(segs))
	var plan: Dictionary = LotNav.plan(lot, Vector2(9.0, 1.0), Vector2(5.0, 6.0))
	var ok_route := String(plan["mode"]) == "route"
	var prev := Vector2(9.0, 1.0)
	for p in plan.get("pts", []):
		if _crosses_solid(lot, prev, p):
			ok_route = false
		prev = p
	check(ok_route and prev.is_equal_approx(Vector2(5.0, 6.0)), "LotNav: trasa z ulice k posteli neprotne plnou zeď", str(plan))
	var c := {}
	var np: Dictionary = LotNav.next_point(lot, Vector3(5.0, 0, 1.0), Vector3(5.0, 0, 6.0), c)
	check(String(np["mode"]) == "direct", "přímo dveřmi = přímá chůze (bez objížďky)")
	var np2: Dictionary = LotNav.next_point(lot, Vector3(1.0, 0, 1.0), Vector3(5.0, 0, 6.0), {})
	check(String(np2["mode"]) == "route", "šikmo přes plnou zeď = objížďka ke dveřím")
	# Vybourání jediných dveří by postel odřízlo.
	check(lot.door_close_seals(1) and String(lot.remove_opening(1, 1000.0)["reason"]) == "seals_off" and lot.openings.has(1),
		"jediné dveře nejde zazdít (seals_off)")
	var r2: Dictionary = lot.build_opening(int(close["wid"]), "door", 6, 1000.0)
	check(bool(r2["ok"]), "druhé dveře do dolní stěny", str(r2))
	check(not lot.door_close_seals(1) and bool(lot.remove_opening(1, 1000.0)["ok"]), "s druhými dveřmi jde první zazdít")
	check(lot.access_reachable(Vector2(5.0, 6.0)) and lot.wall_segments(lot.walls[1]).size() == 1, "postel dosažitelná, horní stěna zase celá")
	# Okno neprůchozí.
	var win = _syn()
	_box3(win)
	check(bool(win.build_opening(1, "window_wide", 5, 1000.0)["ok"]), "široké okno do horní stěny")
	check(win.check_wall(12, 30, 28, 30) == "seals_off", "okno cestu nedává – čtvrtá stěna by odřízla")
	check(win.wall_segments(win.walls[1]).size() == 1, "okno = plná zeď pro chůzi")
	# Postava zavřená v prázdné místnosti.
	var room = _syn(false)
	room.build_wall(60, 10, 72, 10, 1000.0)
	room.build_wall(60, 10, 60, 22, 1000.0)
	room.build_wall(72, 10, 72, 22, 1000.0)
	var rd: Dictionary = room.build_opening(1, "door", 4, 1000.0)
	room.build_wall(60, 22, 72, 22, 1000.0)
	var inside := Vector2(16.5, 4.0)
	var outside := Vector2(5.0, 1.0)
	check(bool(rd["ok"]) and room.walls.size() == 4, "prázdná místnost s dveřmi")
	check(room.opening_traps(int(rd["oid"]), [inside]) and not room.opening_traps(int(rd["oid"]), [outside]),
		"zazdění dveří by zavřelo postavu uvnitř, venku ne")
	check(not room.opening_traps(int(rd["oid"]), [Vector2(NAN, 1.0), "x", inside * INF]), "nesmyslné polohy se ignorují")
	check(not room.door_close_seals(int(rd["oid"])), "bez věcí uvnitř zazdění nic neodřízne")
	var win_id: int = int(room.build_opening(2, "window", 4, 1000.0)["oid"])
	check(not room.opening_traps(win_id, [inside]), "okno nikoho nezavře (není průchozí)")
	# Místnost u kraje parcely: stěna po hranici odděluje od ulice (oprava BFS v B4).
	var edge = _syn(false)
	var ed: Dictionary = edge.build_wall(0, 10, 12, 10, 1000.0)
	var eo: Dictionary = edge.build_opening(int(ed["wid"]), "door", 4, 1000.0)
	edge.build_wall(12, 10, 12, 22, 1000.0)
	edge.build_wall(0, 22, 12, 22, 1000.0)
	var in_edge := Vector2(1.5, 4.0)
	check(bool(eo["ok"]) and not edge.opening_traps(int(eo["oid"]), [in_edge]), "bez stěny po hranici je místnost otevřená do ulice")
	check(bool(edge.build_wall(0, 10, 0, 22, 1000.0)["ok"]), "stěna po hranici parcely")
	check(edge.opening_traps(int(eo["oid"]), [in_edge]), "teď by zazdění dveří postavu zavřelo")
	check(edge.wall_traps(0, 0, 0, 2, [Vector2(0.1, 0.3)]) == false and edge.check_wall(0, 10, 0, 22) == "wall_overlap", "kontroly hranice konzistentní")


# ---------------------------------------------------------------- předměty vs. dveře

func _test_items_and_doors() -> void:
	section("Předměty a prostor dveří")
	var lot = _syn()
	var w: Dictionary = lot.build_wall(28, 34, 44, 34, 1000.0)
	check(bool(w["ok"]), "příčka uvnitř domu", str(w))
	var d: Dictionary = lot.build_opening(int(w["wid"]), "door", 6, 1000.0)
	check(bool(d["ok"]), "dveře v příčce", str(d))
	check(lot.check("plant_monstera", 35, 32, 0) == "blocks_door" and lot.check("plant_monstera", 35, 34, 0) == "blocks_door",
		"květina v prostoru dveří (z obou stran) odmítnuta")
	var rb: Dictionary = lot.buy("plant_monstera", 35, 32, 0, 1000.0)
	check(not bool(rb["ok"]) and String(rb["reason"]) == "blocks_door", "nákup do dveří odmítnut s důvodem")
	check(lot.check("plant_monstera", 35, 30, 0) == "", "o metr dál lze")
	check(lot.check("rug_wool", 32, 28, 0) == "", "koberec do prostoru dveří smí")
	# Předmět, který už stojí, dveře zablokuje.
	var lot2 = _syn()
	var w2: Dictionary = lot2.build_wall(28, 34, 44, 34, 1000.0)
	check(bool(lot2.buy("plant_monstera", 35, 32, 0, 1000.0)["ok"]), "květina koupena před dveřmi")
	check(lot2.check_opening(int(w2["wid"]), "door", 6) == "door_blocked" and lot2.check_opening(int(w2["wid"]), "window", 6) == "",
		"dveře by vedly do květiny, okno nad ní lze")
	# Přesun předmětu do dveří.
	var uid: int = int(lot2.sorted_uids()[0])
	check(bool(lot2.build_opening(int(w2["wid"]), "door", 10, 1000.0)["ok"]), "dveře o kus vedle")
	var mv: Dictionary = lot2.move(uid, 41, 32, 0, 1000.0)
	check(not bool(mv["ok"]) and String(mv["reason"]) == "blocks_door", "přesun do dveří odmítnut")


# ---------------------------------------------------------------- zbourání a vratky

func _test_removal_and_refunds() -> void:
	section("Zbourání stěny s otvory, vratky")
	var lot = _syn()
	var w: Dictionary = lot.build_wall(60, 20, 76, 20, 1000.0)
	var f0: int = lot.funds
	lot.build_opening(int(w["wid"]), "door", 2, 1000.0)
	lot.build_opening(int(w["wid"]), "window", 9, 1000.0)
	check(lot.funds == f0 - 780 and lot.openings.size() == 2, "dveře a okno osazeny (−780 kr)")
	var rr: Dictionary = lot.remove_wall(int(w["wid"]), 1100.0)
	check(bool(rr["ok"]) and int(rr["openings_removed"]) == 2 and lot.openings.is_empty(), "zbourání stěny odstraní i otvory")
	check(int(rr["refund"]) == 960 + 780 and lot.funds == f0 + 960, "týž den vratka stěny i otvorů", str(rr))
	var lot2 = _syn()
	var w2: Dictionary = lot2.build_wall(60, 20, 76, 20, 1000.0)
	var o2: Dictionary = lot2.build_opening(int(w2["wid"]), "door", 2, 1000.0)
	check(lot2.opening_refund_value(int(o2["oid"]), 2440.0) == 420 and lot2.opening_refund_value(int(o2["oid"]), 2441.0) == 0,
		"plná vratka přesně do 24 h, potom nic")
	check(lot2.opening_refund_value(int(o2["oid"]), 500.0) == 0, "hodiny dozadu (rewind) = stará věc, žádná vratka")
	var f1: int = lot2.funds
	var ro: Dictionary = lot2.remove_opening(int(o2["oid"]), 5000.0)
	check(bool(ro["ok"]) and int(ro["refund"]) == 0 and lot2.funds == f1 and String(lot2.ledger[-1]["kind"]) == "unopening", "pozdní vybourání nic nevrátí")
	check(lot2._door_side.count(1) == 0, "prostor dveří po vybourání uvolněn")


# ---------------------------------------------------------------- ukládání

func _built_lot():
	var lot = _syn()
	_box3(lot)
	lot.build_opening(1, "door", 6, 1000.0)
	lot.build_wall(12, 30, 28, 30, 1000.0)
	lot.build_opening(4, "window_wide", 5, 1010.0)
	lot.build_opening(2, "window", 6, 1020.0)
	lot.buy("rug_wool", 32, 28, 0, 1030.0)
	return lot


func _test_save_and_migration() -> void:
	section("Ukládání (v3+), migrace v2, validace a obnova")
	var lot = _built_lot()
	var d: Dictionary = lot.to_dict()
	check(int(d["version"]) == LotGrid.VERSION and (d["openings"] as Array).size() == 3 and int(d["next_oid"]) == 4, "snímek (v3+) s otvory")
	check(LotGrid.validate_snapshot(d) == "", "vlastní snímek projde validací")
	var dj: Variant = JSON.parse_string(JSON.stringify(d))
	var lot2 = _syn()
	var res: Dictionary = lot2.from_dict(dj, 1100.0)
	check(bool(res["ok"]) and int(res["dropped"]) == 0 and _json(lot2) == _json(lot), "JSON → obnova → stejný snímek bit po bitu", str(res))
	check(lot2.access_reachable(Vector2(5.0, 6.0)) and lot2._door_side.count(1) == lot._door_side.count(1), "po obnově dveře průchozí, prostor dveří obnoven")
	# Migrace v2.
	var v2: Dictionary = d.duplicate(true)
	v2["version"] = 2
	v2.erase("openings")
	v2.erase("next_oid")
	check(LotGrid.validate_snapshot(v2) == "", "snímek v2 (bez otvorů) projde")
	var lot3 = _syn()
	var r3: Dictionary = lot3.from_dict(v2, 1100.0)
	check(bool(r3["ok"]) and lot3.openings.is_empty() and lot3.next_oid == 1 and lot3.walls.size() == 4, "migrace v2: stěny ano, otvory žádné")
	check(int(lot3.to_dict()["version"]) == LotGrid.VERSION, "znovu uloženo v aktuální verzi")
	# Vadné varianty.
	var bad := 0
	var variants := 0
	var muts: Array = [
		func(x): x["openings"] = "x",
		func(x): x["openings"][0]["extra"] = 1,
		func(x): x["openings"][0].erase("paid"),
		func(x): x["openings"][0]["oid"] = 99,
		func(x): x["openings"][1]["oid"] = x["openings"][0]["oid"],
		func(x): x["openings"][0]["wid"] = 77,
		func(x): x["openings"][0]["kind"] = "portal",
		func(x): x["openings"][0]["kind"] = 3,
		func(x): x["openings"][0]["at"] = 1.5,
		func(x): x["openings"][0]["at"] = -1,
		func(x): x["openings"][0]["at"] = 81,
		func(x): x["openings"][0]["built_at"] = INF,
		func(x): x["openings"][0]["paid"] = -1,
		func(x): x.erase("next_oid"),
		func(x): x["next_oid"] = 0,
		func(x): x["openings"] = range(65).map(func(i): return x["openings"][0]),
	]
	for m in muts:
		var v: Dictionary = d.duplicate(true)
		m.call(v)
		variants += 1
		if LotGrid.validate_snapshot(v) != "":
			bad += 1
	check(bad == variants, "%d vadných variant odmítnuto" % variants, "%d/%d" % [bad, variants])
	# Geometricky neplatné otvory: vyřadí se s vratkou nejvýš v ceníkové ceně.
	var g: Dictionary = d.duplicate(true)
	g["openings"][1]["at"] = 0
	g["openings"][1]["paid"] = 100000000
	var lot4 = _syn()
	var r4: Dictionary = lot4.from_dict(g, 1100.0)
	check(bool(r4["ok"]) and int(r4["dropped_openings"]) == 1 and lot4.openings.size() == 2, "otvor bez ostění vyřazen", str(r4))
	check(int(r4["refund"]) == LotGrid.opening_price("window_wide") and lot4.funds == int(d["funds"]) + LotGrid.opening_price("window_wide"),
		"vratka podvrženého otvoru jen v ceníkové ceně")
	# Otvor na stěně, která se vyřadí, padá s ní; předmět v prostoru dveří se vyřadí, ne dveře.
	var h: Dictionary = d.duplicate(true)
	h["walls"].append({"wid": 9, "x0": 20, "z0": 10, "x1": 20, "z1": 18, "built_at": 1.0, "paid": 480})
	h["next_wid"] = 10
	h["openings"].append({"oid": 7, "wid": 9, "kind": "window", "at": 2, "built_at": 1.0, "paid": 360, "lock": ""})
	h["next_oid"] = 8
	h["items"].append({"uid": 9, "id": "plant_monstera", "cx": 20, "cz": 12, "rot": 0, "bought_at": 1.0, "paid": 590})
	h["next_uid"] = 10
	check(LotGrid.validate_snapshot(h) == "", "strukturálně platný podvržený snímek")
	var lot5 = _syn()
	var r5: Dictionary = lot5.from_dict(h, 1100.0)
	check(bool(r5["ok"]) and int(r5["dropped_walls"]) == 1 and not lot5.openings.has(7) and lot5.openings.size() == 3,
		"křížící stěna vyřazena i s oknem", str(r5))
	check(not lot5.items.has(9) and lot5.openings.has(1), "květina ve dveřích vyřazena, dveře zůstaly")


# ---------------------------------------------------------------- síť

func _test_public_fuzz() -> void:
	section("Veřejný snímek a fuzz")
	var lot = _built_lot()
	var pub: Dictionary = lot.public_snapshot()
	check((pub["open"] as Array).size() == 3 and (pub["open"][0] as Array).size() == 7, "snímek obsahuje otvory jako pole (B4b: + zámek)")
	var cl = _syn()
	check(cl.apply_public(pub) and JSON.stringify(cl.openings) == JSON.stringify(lot.openings), "klient převzal otvory")
	check(JSON.stringify(cl.wall_segments(cl.walls[1])) == JSON.stringify(lot.wall_segments(lot.walls[1])) and cl.access_reachable(Vector2(5.0, 6.0)),
		"klient vidí stejné plné úseky a průchod dveřmi")
	var base := JSON.stringify(cl.openings)
	var forged: Array = []
	var f1: Dictionary = pub.duplicate(true)
	f1["open"][0][1] = 55
	forged.append(f1)
	var f2: Dictionary = pub.duplicate(true)
	f2["open"][0][3] = 0
	forged.append(f2)
	var f3: Dictionary = pub.duplicate(true)
	f3["open"].append([9, 1, "window", 11, 1.0, 360, ""])
	f3["open"].append([10, 1, "window", 13, 1.0, 360, ""])
	forged.append(f3)
	var f4: Dictionary = pub.duplicate(true)
	f4["open"][0][2] = "hole"
	forged.append(f4)
	var f5: Dictionary = pub.duplicate(true)
	f5["open"][0] = [1, 1, "door"]
	forged.append(f5)
	var f6: Dictionary = pub.duplicate(true)
	f6["walls"].append([9, 20, 14, 20, 8, 1.0, 480])
	forged.append(f6)
	var f7: Dictionary = pub.duplicate(true)
	f7["open"] = range(65).map(func(i): return [i + 1, 1, "window", 1, 1.0, 360, ""])
	forged.append(f7)
	var f8: Dictionary = pub.duplicate(true)
	f8["open"] = "x"
	forged.append(f8)
	var rej := 0
	for f in forged:
		if not cl.apply_public(f):
			rej += 1
	check(rej == forged.size() and JSON.stringify(cl.openings) == base, "%d podvržených snímků odmítnuto, stav beze změny" % forged.size(), str(rej))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var weird: Array = [null, -1, 0, 1, 2, 5, 6, 11, 81, 1.5, INF, "door", "window", "x", [], {}, 1000000001]
	var accepted := 0
	var invalid_kept := 0
	for i in 300:
		var s: Dictionary = pub.duplicate(true)
		var e: Array = s["open"][rng.randi_range(0, 2)]
		e[rng.randi_range(0, 5)] = weird[rng.randi_range(0, weird.size() - 1)]
		var c2 = _syn()
		if c2.apply_public(s):
			accepted += 1
			# Co klient přijal, musí server pravidlům odpovídat geometricky (ostění, odstupy, T-spoje).
			for oid in c2.openings:
				var o: Dictionary = c2.openings[oid]
				var saved: Dictionary = o.duplicate()
				c2.openings.erase(oid)
				var why: String = c2.check_opening(int(o["wid"]), String(o["kind"]), int(o["at"]))
				c2.openings[oid] = saved
				if why not in ["", "door_blocked"]:
					invalid_kept += 1
	check(invalid_kept == 0, "fuzz 300: přijaté snímky mají jen geometricky platné otvory (přijato %d)" % accepted)


func _test_performance() -> void:
	section("Výkon")
	var full = LotGrid.new()
	full.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	full.rebuild()
	full.funds = LotGrid.MAX_FUNDS
	for row in 6:
		for col in 5:
			var wr: Dictionary = full.build_wall(col * 20, 2 + row * 6, col * 20 + 16, 2 + row * 6, 1000.0)
			if bool(wr["ok"]):
				for at in [1, 11]:
					full.build_opening(int(wr["wid"]), "door" if at == 1 else "window", at, 1000.0)
	check(full.openings.size() >= 50, "zátěžová parcela: %d stěn, %d otvorů" % [full.walls.size(), full.openings.size()])
	var t0 := Time.get_ticks_usec()
	for i in 200:
		full.check_opening(int(full.sorted_wids()[i % full.walls.size()]), "window", 6)
	var co := float(Time.get_ticks_usec() - t0) / 200.0
	check(co < 2000.0, "check_opening < 2 ms (%.3f ms)" % (co / 1000.0))
	var t1 := Time.get_ticks_usec()
	var first_door := int(full.sorted_oids()[0])
	for i in 10:
		full._reachable({}, first_door)
		full.opening_traps(first_door, [Vector2(1.0, 1.0)])
	var ds := float(Time.get_ticks_usec() - t1) / 10.0
	check(ds < 60000.0, "BFS se zazděnými dveřmi + kontrola zavření postavy < 60 ms (%.1f ms)" % (ds / 1000.0))
	var nseg := 0
	for wid in full.walls:
		nseg += full.wall_segments(full.walls[wid]).size()
	var t2 := Time.get_ticks_usec()
	for i in 200:
		LotNav.walls_block(full, Vector2(0.3, 0.1 + i * 0.04), Vector2(24.7, 9.9 - i * 0.04))
	var wb := float(Time.get_ticks_usec() - t2) / 200.0
	check(wb < 3000.0, "LotNav.walls_block s %d plnými úseky < 3 ms (%.3f ms)" % [nseg, wb / 1000.0])


# ---------------------------------------------------------------- herní svět

func _offline_world(wname: String) -> Node3D:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = wname
	w.net_config = {"mode": "offline", "audio": false, "camera": false, "visuals": false, "hud": false,
		"autoload": false, "autosave": false, "save_directory": save_dir, "clock": clock}
	add_child(w)
	return w


## První platná stěna dané délky v obdélníku světa [x0, z0, x1, z1]; [] = žádná.
func _find_wall(lot, rect: Array, cells: int, horizontal: bool) -> Array:
	var a: Vector2i = lot.snap_lattice(Vector2(rect[0], rect[1]))
	var b: Vector2i = lot.snap_lattice(Vector2(rect[2], rect[3]))
	for z in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var e := Vector2i(x + cells, z) if horizontal else Vector2i(x, z + cells)
			if e.x > b.x or e.y > b.y:
				continue
			if lot.check_wall(x, z, e.x, e.y) == "":
				return [x, z, e.x, e.y]
	return []


## Stěna 4 m na zahradě + dveře/okno, které jdou osadit. {} = nenašlo se místo.
func _wall_with_opening(world: Node3D, kind: String) -> Dictionary:
	for rect in [[7.0, 6.0, 12.0, 11.0], [5.0, 5.5, 13.0, 12.0], [-12.0, 5.5, 13.0, 12.0], [-12.0, -12.0, 13.0, 12.0]]:
		var spot := _find_wall(world.lot, rect, 16, true)
		if spot.is_empty():
			continue
		var r: Dictionary = world.lot_apply_action("wall", spot, "Test")
		if not bool(r["ok"]):
			continue
		for at in [6, 5, 7, 4, 8, 3, 9, 2, 10, 1, 11]:
			if world.lot.check_opening(int(r["wid"]), kind, at) == "":
				return {"wid": int(r["wid"]), "at": at, "spot": spot}
		world.lot_apply_action("unwall", [int(r["wid"])], "Test")
	return {}


func _test_world() -> void:
	section("Dveře a okna v herním světě")
	var world := _offline_world("DoorWorld")
	var lot = world.lot
	check(int(lot.to_dict()["version"]) == LotGrid.VERSION, "parcela v aktuálním formátu (v3+)")
	var t := _wall_with_opening(world, "door")
	check(not t.is_empty(), "na zahradě je stěna 4 m, do které jdou dveře", str(t))
	if t.is_empty():
		world.free()
		return
	var wid: int = t["wid"]
	var f0: int = lot.funds
	var r: Dictionary = world.lot_apply_action("open", [wid, "door", t["at"]], "Test")
	check(bool(r["ok"]) and lot.funds == f0 - 420, "dveře osazeny přes autoritu světa", str(r))
	check(String(world.lot_apply_action("open", [wid, "door"], "Test")["reason"]) == "opening_bad"
		and String(world.lot_apply_action("unopen", [1, 2], "Test")["reason"]) == "unknown_oid", "špatný počet argumentů")
	var node: Node3D = world.wall_node(wid)
	var oid: int = int(r["oid"])
	var door: Node3D = node.get_node_or_null("Door_%d" % oid) if node != null else null
	check(node != null and door != null and node.get_node_or_null("Header_%d" % oid) != null and node.get_node_or_null("Body_0") != null
		and node.get_node_or_null("Body_1") != null and node.get_node_or_null("Body") == null, "uzel stěny: dva kusy, nadpraží, dveře")
	# Kolize nesmí zasahovat do rozsahu dveří pod nadpražím.
	var ab: Array = lot.opening_world(lot.openings[oid])
	var wab: Array = lot.wall_world(lot.walls[wid])
	var s0: float = (ab[0] as Vector2).distance_to(wab[0])
	var s1: float = (ab[1] as Vector2).distance_to(wab[0])
	var half: float = (wab[0] as Vector2).distance_to(wab[1]) * 0.5
	var blocked := false
	var shapes := 0
	for ch in node.get_children():
		if ch is CollisionShape3D:
			shapes += 1
			var bs: Vector3 = (ch.shape as BoxShape3D).size
			var lx0: float = ch.position.x - bs.x * 0.5 + half
			var lx1: float = ch.position.x + bs.x * 0.5 + half
			var ly0: float = ch.position.y - bs.y * 0.5
			if lx1 > s0 + 0.01 and lx0 < s1 - 0.01 and ly0 < 2.0:
				blocked = true
	check(shapes >= 3 and not blocked, "kolize kolem dveří, rozsah dveří volný (%d tvarů)" % shapes)
	var hinge: Node3D = door.get_node_or_null("Hinge") if door != null else null
	check(hinge != null and hinge.get_script() == preload("res://scripts/world/lot_door.gd") and hinge.get_node_or_null("Leaf") != null,
		"křídlo dveří na pantu")
	var dc: Vector2 = ((ab[0] as Vector2) + (ab[1] as Vector2)) * 0.5
	check(Vector2(door.global_position.x, door.global_position.z).distance_to(dc) < 0.01, "držák dveří ve středu otvoru")
	var sim: Node3D = world.sims[0]
	var home: Vector3 = sim.global_position
	if hinge != null:
		hinge.set_process(false)
		sim.global_position = Vector3(dc.x, home.y, dc.y + 0.6)
		hinge._poll = 0.0
		hinge._process(0.2)
		var opening_angle: float = hinge.angle
		hinge._process(1.0)
		check(hinge.want_open and opening_angle > 0.0 and is_equal_approx(hinge.angle, LotDoor_OPEN()), "postava u dveří → křídlo se otevře",
			"%.1f / %.1f" % [opening_angle, hinge.angle])
		sim.global_position = Vector3(dc.x + 6.0, home.y, dc.y + 6.0)
		hinge._poll = 0.0
		hinge._process(1.0)
		check(not hinge.want_open and hinge.angle == 0.0 and is_equal_approx(hinge.rotation_degrees.y, 0.0), "postava odešla → zavřeno")
		sim.global_position = home
	# Okno.
	var tw := _wall_with_opening(world, "window")
	if not tw.is_empty():
		var rw: Dictionary = world.lot_apply_action("open", [tw["wid"], "window", tw["at"]], "Test")
		var wn: Node3D = world.wall_node(int(tw["wid"]))
		check(bool(rw["ok"]) and wn.get_node_or_null("Window_%d/Glass" % int(rw["oid"])) != null
			and wn.get_node_or_null("WindowCollision_%d" % int(rw["oid"])) != null and wn.get_node_or_null("Sill_%d" % int(rw["oid"])) != null,
			"okno: sklo, parapet, kolize přes otvor")
	else:
		check(false, "místo pro okno")
	check(world.smart_objects.size() == world.lot_base_count, "otvory nepřidávají chytré objekty")
	# Disk.
	var snap := JSON.stringify(lot.to_dict())
	var saved: Dictionary = world.save_game("manual")
	check(bool(saved.get("ok", false)), "uloženo", str(saved))
	world.lot_apply_action("unopen", [oid], "Test")
	check(not lot.openings.has(oid) and world.wall_node(wid).get_node_or_null("Door_%d" % oid) == null and world.wall_node(wid).get_node_or_null("Body") != null,
		"vybourání: uzel zase celá stěna")
	var loaded: Dictionary = world.load_game("manual")
	check(bool(loaded.get("ok", false)), "načteno", str(loaded))
	check(JSON.stringify(world.lot.to_dict()) == snap, "otvory po načtení z disku bit po bitu")
	check(world.wall_node(wid) != null and world.wall_node(wid).get_node_or_null("Door_%d" % oid) != null, "dveře ve světě postaveny znovu")
	# door_traps: místnost 3 × 3 m s dveřmi, postava uvnitř. Načtení hry postavy vytvořilo znovu → nový odkaz.
	sim = world.sims[0]
	home = sim.global_position
	var room := _room(world)
	check(not room.is_empty(), "na zahradě jde postavit místnost 3 × 3 m s dveřmi", str(room))
	if not room.is_empty():
		sim.global_position = Vector3(float(room["cx"]), home.y, float(room["cz"]))
		var rt: Dictionary = world.lot_apply_action("unopen", [int(room["oid"])], "Test")
		check(not bool(rt["ok"]) and String(rt["reason"]) == "door_traps" and lot.openings.has(int(room["oid"])), "zazdění dveří se postavou uvnitř odmítnuto",
			"%s; sim %s; room %s" % [str(rt), str(sim.global_position), str(room)])
		sim.global_position = home
		var ru: Dictionary = world.lot_apply_action("unopen", [int(room["oid"])], "Test")
		check(bool(ru["ok"]), "bez postavy uvnitř jde zazdít", str(ru))
	world.free()


static func LotDoor_OPEN() -> float:
	return preload("res://scripts/world/lot_door.gd").OPEN_DEG


## Místnost 12 × 12 buněk: horní stěna, boky, dveře v horní stěně, spodní stěna. {} = nenašlo se.
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
				# Průchozí buňka uvnitř místnosti, kam se dá dojít od ulice (dveřmi) – tam se postaví postava.
				var before: PackedByteArray = lot._reach_before()
				lot._build_edges({})
				for iz in range(z + 2, z + 11):
					for ix in range(x + 2, x + 11):
						var ci: int = lot._idx(ix, iz)
						if lot._walkable(ci) and lot._target_reached(before, ci):
							var c: Vector2 = lot.origin + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * LotGrid.CELL
							return {"oid": oid, "cx": c.x, "cz": c.y, "walls": built}
			for wid in built:
				world.lot_apply_action("unwall", [wid], "Test")
	return {}


# ---------------------------------------------------------------- UI

func _test_ui() -> void:
	section("UI: nástroj Dveře/Okno")
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "DoorUiWorld"
	w.net_config = {"mode": "offline", "audio": false, "camera": true, "visuals": false, "hud": true,
		"autoload": false, "autosave": false, "save_directory": save_dir + "-ui", "clock": clock}
	add_child(w)
	await get_tree().process_frame
	var t := _wall_with_opening(w, "door")
	check(not t.is_empty(), "stěna pro UI test")
	if t.is_empty():
		w.queue_free()
		return
	w.toggle_buy_mode()
	var bm = w.buy_mode
	check(bm != null and bm._open_btns.size() == 3, "tři tlačítka otvorů")
	bm.set_process(false)
	bm.set_open_tool("door")
	check(bm.open_kind == "door" and bm._open_btns["door"].button_pressed and not bm._open_btns["window"].button_pressed and not bm.wall_tool,
		"nástroj Dveře zapnut")
	var wab: Array = w.lot.wall_world(w.lot.walls[int(t["wid"])])
	var dir: Vector2 = ((wab[1] as Vector2) - (wab[0] as Vector2)).normalized()
	var aim: Vector2 = (wab[0] as Vector2) + dir * ((float(t["at"]) + 2.0) * LotGrid.CELL) + Vector2(0.03, 0.12)
	bm.aim_opening(aim)
	check(int(bm.open_target.get("wid", 0)) == int(t["wid"]) and int(bm.open_target.get("at", -1)) == int(t["at"]), "myš u zdi zaměří otvor na mřížku", str(bm.open_target))
	bm.update_open_ghost()
	check(bm.last_reason == "" and bm._open_ghost.visible and String(bm._status.text).find("420 kr") >= 0, "zelený duch s cenou", String(bm._status.text))
	var f0: int = w.lot.funds
	bm.place_opening()
	check(w.lot.openings.size() == 1 and w.lot.funds == f0 - 420, "klik osadí dveře přes autoritu")
	bm.update_open_ghost()
	check(bm.last_reason == "opening_overlap" and String(bm._status.text) == String(LotGrid.REASON_TEXT["opening_overlap"]), "na stejném místě červený duch s důvodem")
	bm.aim_opening(aim + Vector2(30.0, 30.0))
	bm.update_open_ghost()
	check(bm.open_target.is_empty() and not bm._open_ghost.visible, "mimo zeď žádný cíl, duch skrytý")
	bm.set_open_tool("window_wide")
	check(bm.open_kind == "window_wide" and not bm._open_btns["door"].button_pressed and bm._open_btns["window_wide"].button_pressed, "přepnutí na široké okno")
	bm.set_wall_tool(true)
	check(bm.wall_tool and bm.open_kind == "" and not bm._open_ghost.visible, "nástroj Zeď vypne nástroj otvorů")
	bm.set_wall_tool(false)
	bm.selected_oid = int(w.lot.sorted_oids()[0])
	bm._refresh()
	check(bm._open_box.visible and String(bm._open_label.text).find("420 kr") >= 0, "vybrané dveře ukazují vratku", String(bm._open_label.text))
	bm.demolish_selected_opening()
	check(w.lot.openings.is_empty() and w.lot.funds == f0, "Vybourat vrátí peníze (týž den)")
	bm._refresh()
	check(not bm._open_box.visible and bm.selected_oid == 0, "po vybourání výběr zmizí")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_V
	bm._unhandled_input(ev)
	check(bm.open_kind == "door", "klávesa V zapne dveře")
	var ev2 := InputEventKey.new()
	ev2.pressed = true
	ev2.keycode = KEY_O
	ev2.shift_pressed = true
	bm._unhandled_input(ev2)
	check(bm.open_kind == "window_wide", "Shift+O široké okno")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	bm._unhandled_input(esc)
	check(bm.open_kind == "" and w.buy_mode != null, "Esc vypne nástroj, režim zůstane otevřený")
	bm.close()
	await get_tree().process_frame
	check(w.buy_mode == null, "režim zavřen")
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
	section("Multiplayer: dveře přes autoritativní server (ENet)")
	clock.total_minutes = 600.0
	var server := _branch("DoorServer", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(server.net.mode == NetSession.Mode.DEDICATED, "dedikovaný server běží")
	var a := _client("DoorClientA", "Truhlář")
	check(await wait_until(func(): return a.net.my_sim != "", 6.0), "klient přivítán s postavou")
	var t := _wall_with_opening(server, "door")
	check(not t.is_empty(), "server: stěna pro dveře", str(t))
	if t.is_empty():
		return
	server.net.broadcast_lot()
	var wid: int = t["wid"]
	check(await wait_until(func(): return a.lot.walls.has(wid), 3.0), "klient vidí stěnu")
	check(not bool(a.lot_apply_action("open", [wid, "door", t["at"]], "x")["ok"]) and a.lot.openings.is_empty(), "klient sám dveře neosadí")
	a.request_lot_action("open", [wid, "door", t["at"]])
	check(await wait_until(func(): return server.lot.openings.size() == 1, 3.0), "server osadil dveře klienta")
	check(await wait_until(func(): return a.lot.openings.size() == 1 and a.wall_node(wid) != null and a.wall_node(wid).get_node_or_null("Door_1/Hinge") != null, 3.0),
		"klient dostal dveře i s křídlem")
	check(JSON.stringify(a.lot.wall_segments(a.lot.walls[wid])) == JSON.stringify(server.lot.wall_segments(server.lot.walls[wid])),
		"plné úseky stěny shodné na klientu i serveru (deterministický průchod)")
	await wait_seconds(1.2)
	# Regression: no assigned character means no spending of household funds.
	var spectator_peer: int = -1
	for pid in server.net.players:
		if int(pid) != 1 and String(server.net.players[pid].get("sim", "")) != "":
			spectator_peer = int(pid)
			break
	check(spectator_peer > 1, "remote peer exists for spectator test")
	if spectator_peer > 1:
		var saved_sim: String = String(server.net.players[spectator_peer]["sim"])
		var before_funds: int = server.lot.funds
		var before_open: String = JSON.stringify(server.lot.public_snapshot()["open"])
		var before_rejected: int = int(server.net.stats["rejected"])
		server.net.players[spectator_peer]["sim"] = ""
		var denial: String = server.net.handle_lot_action(spectator_peer, "open", [wid, "window", 2])
		server.net.players[spectator_peer]["sim"] = saved_sim
		check(denial == "Divák nemůže utrácet peníze domácnosti.", "spectator denied by server", denial)
		check(server.lot.funds == before_funds and JSON.stringify(server.lot.public_snapshot()["open"]) == before_open, "spectator cannot mutate lot or funds")
		check(int(server.net.stats["rejected"]) == before_rejected + 1, "spectator denial counted")
		# Real ENet spectator RPC.
		var rpc_funds: int = server.lot.funds
		var rpc_open: String = JSON.stringify(server.lot.public_snapshot()["open"])
		var rpc_rejected: int = int(server.net.stats["rejected"])
		server.net.players[spectator_peer]["sim"] = ""
		a.net._c2s_lot.rpc_id(1, "open", [wid, "window", 2])
		# Bez pevného čekání: čeká se na skutečné odmítnutí serverem (statistika rejected), teprve pak se
		# postava vrátí – RPC tak nikdy nedorazí až po obnově a test nezávisí na rychlosti stroje.
		var rpc_seen: bool = await wait_until(func(): return int(server.net.stats["rejected"]) >= rpc_rejected + 1, 4.0)
		server.net.players[spectator_peer]["sim"] = saved_sim
		check(rpc_seen, "server ENet spectator RPC skutečně přijal a odmítl (bez pevné prodlevy)")
		check(server.lot.funds == rpc_funds and JSON.stringify(server.lot.public_snapshot()["open"]) == rpc_open, "ENet spectator RPC cannot change authoritative lot or funds")
		check(int(server.net.stats["rejected"]) >= rpc_rejected + 1, "ENet spectator RPC rejected by server")
	var funds0: int = server.lot.funds
	var open0 := JSON.stringify(server.lot.public_snapshot()["open"])
	var rej0: int = server.net.stats["rejected"]
	a.net._c2s_lot.rpc_id(1, "open", ["1", "door", 6])
	a.net._c2s_lot.rpc_id(1, "open", [wid, "gate", 6])
	a.net._c2s_lot.rpc_id(1, "open", [wid, "door", 6.5])
	a.net._c2s_lot.rpc_id(1, "open", [wid, "door"])
	await wait_seconds(1.1)
	a.net._c2s_lot.rpc_id(1, "open", [wid, "door", 9999])
	a.net._c2s_lot.rpc_id(1, "open", [wid, "window_wide_xxxxxxxxxxxxxxxxxxxxxxxx", 2])
	a.net._c2s_lot.rpc_id(1, "unopen", ["x"])
	a.net._c2s_lot.rpc_id(1, "unopen", [1.0])
	await wait_seconds(0.6)
	check(server.lot.funds == funds0 and JSON.stringify(server.lot.public_snapshot()["open"]) == open0, "podvržené požadavky nic nezměnily")
	check(int(server.net.stats["rejected"]) >= rej0 + 8, "server je odmítl a počítá", "%d → %d" % [rej0, int(server.net.stats["rejected"])])
	await wait_seconds(3.0)
	notices["DoorClientA"].clear()
	a.net._c2s_lot.rpc_id(1, "open", [wid, "window", int(t["at"])])
	check(await wait_until(func(): return notices["DoorClientA"].size() > 0, 3.0) and server.lot.openings.size() == 1,
		"okno přes dveře odmítnuto pravidly, hráč dostal důvod", str(notices["DoorClientA"]))
	await wait_seconds(4.5)
	var b := _client("DoorClientB", "Pozdní")
	check(await wait_until(func(): return b.net.my_sim != "" and b.lot.openings.size() == 1 and b.wall_node(wid) != null and b.wall_node(wid).get_node_or_null("Door_1") != null, 6.0),
		"pozdě připojený hráč dostane dveře po vstupu")
	a.request_lot_action("unopen", [1])
	check(await wait_until(func(): return server.lot.openings.is_empty() and b.lot.openings.is_empty() and b.wall_node(wid) != null and b.wall_node(wid).get_node_or_null("Door_1") == null, 3.0),
		"vybourání z klienta A zmizí na serveru i u klienta B")
	check(server.lot.funds == funds0 + 420 and b.lot.funds == server.lot.funds, "vratka týž den připsána a replikována")
	var cap: Dictionary = load("res://scripts/save/game_save.gd").capture(server, true)
	check(bool(cap.get("ok", false)) and cap["data"]["lot"].has("openings") and int(cap["data"]["lot"]["version"]) == LotGrid.VERSION, "serverový snímek světa ukládá otvory")
	for w in [a, b, server]:
		w.net.shutdown()
	await wait_seconds(0.3)
	for w in [a, b, server]:
		w.get_parent().queue_free()
	await wait_seconds(0.2)
