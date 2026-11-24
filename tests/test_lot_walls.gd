extends "res://tests/test_base.gd"
## B2 (22. 11. 2026): stavění stěn na parcele (LotGrid v2).
## Pravidla stěn na syntetické parcele (typy, geometrie, statické prostředí, předměty, přístup, peníze, limit),
## předměty vs. stěny, zbourání a vratky, ukládání v2 + migrace v1, validace a obnova (vyřazení s vratkou),
## fuzz veřejných snímků, výkon kontroly, uzly stěn ve světě (kolize, rozměry, save/load z disku),
## UI nástroje Zeď a skutečné ENet: klient staví přes server, podvržené požadavky, pozdní připojení.

const Main := preload("res://main.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")
const WallGeometry := preload("res://scripts/world/build_wall_validation.gd")

var clock: Node
var save_dir := ""
var port := 0
var notices := {}


func _ready() -> void:
	watchdog_seconds = 150.0
	randomize()
	port = 26200 + randi() % 700
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 1000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-lot-walls-" + str(OS.get_process_id())
	_run.call_deferred()


func _run() -> void:
	_test_wall_rules()
	_test_items_vs_walls()
	_test_refunds()
	_test_save_and_migration()
	_test_public_fuzz()
	_test_performance()
	await _test_world()
	await _test_ui()
	await _test_multiplayer()
	clock.running = false
	finish("test_lot_walls")


## Syntetická parcela 25 × 10 m (100 × 40 buněk): vlevo „dům“ (vnitřek x < 12,5 m) se zdí ve sloupci
## buněk 50, postel 2 × 1 m na (5, 5) s bodem použití (5, 6).
func _syn(fixtures := true):
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	if fixtures:
		lot.add_interior_rect(Rect2(0.0, 0.0, 12.5, 10.0))
		lot.add_static_rect(Rect2(12.5, 0.0, 0.25, 10.0))
		lot.add_fixed("Postel", Vector2(5.0, 5.0), 2.0, 1.0, 0.0, [Vector2(5.0, 6.0)])
	lot.rebuild()
	return lot


func _snapshot_json(lot) -> String:
	return JSON.stringify(lot.to_dict())


# ---------------------------------------------------------------- pravidla stěn

func _test_wall_rules() -> void:
	section("Pravidla stavění stěn")
	var lot = _syn()
	check(lot.gw == 100 and lot.gh == 40, "syntetická parcela 100 × 40 buněk")
	check(lot.check_wall(1.0, 4, 6, 4) == "wall_bad" and lot.check_wall("1", 4, 6, 4) == "wall_bad" and lot.check_wall(null, 4, 6, 4) == "wall_bad",
		"jiné typy než celé číslo odmítnuty")
	check(lot.check_wall(2, 2, 6, 6) == "wall_bad", "šikmá stěna odmítnuta")
	check(lot.check_wall(3, 3, 3, 3) == "wall_bad", "nulová délka odmítnuta")
	check(lot.check_wall(2, 4, 3, 4) == "wall_short", "0,25 m je moc krátká")
	var big = LotGrid.new()
	big.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	big.rebuild()
	check(big.check_wall(0, 1, 81, 1) == "wall_long" and big.check_wall(0, 1, 80, 1) == "", "nejvýš 20 m (80 buněk) v jednom úseku")
	check(lot.check_wall(-1, 4, 5, 4) == "out_of_bounds" and lot.check_wall(95, 4, 101, 4) == "out_of_bounds" and lot.check_wall(2, 38, 2, 41) == "out_of_bounds",
		"mimo parcelu")
	check(lot.check_wall(0, 2, 8, 2) == "" and lot.check_wall(100, 0, 100, 40) == "", "okraj parcely je platný bod (stěna po hranici 10 m)")
	# Statické prostředí.
	check(lot.check_wall(48, 20, 53, 20) == "blocked", "skrz zeď domu neprojde")
	check(lot.check_wall(50, 4, 50, 12) == "" and lot.check_wall(51, 4, 51, 12) == "", "podél zdi domu (jedna strana volná) lze")
	# Výchozí nábytek.
	check(lot.check_wall(20, 16, 20, 26) == "overlap", "skrz postel neprojde")
	check(lot.check_wall(15, 10, 15, 30) == "", "vedle postele lze")
	check(lot.check_wall(14, 23, 26, 23) == "blocks_access", "nezatarasí přístup k posteli (úsečka střed → bod použití)")
	check(lot.check_wall(14, 24, 26, 24) == "blocks_access", "stěna přístupovou zónou postele (postava by stála ve zdi)")
	check(lot.check_wall(14, 27, 26, 27) == "", "o metr dál od postele už lze")
	# Stavba a geometrie mezi stěnami.
	var f0: int = lot.funds
	var rev0: int = lot.revision
	var r: Dictionary = lot.build_wall(30, 30, 40, 30, 1000.0, "Test")
	check(bool(r["ok"]) and int(r["price"]) == 10 * LotGrid.WALL_PRICE_PER_CELL and lot.funds == f0 - 600, "stěna 2,5 m za 600 kr", str(r))
	check(lot.revision == rev0 + 1 and lot.walls.size() == 1 and String(lot.ledger[-1]["kind"]) == "wall" and int(lot.ledger[-1]["amount"]) == -600,
		"revize, záznam v knize transakcí")
	var w: Dictionary = lot.walls[int(r["wid"])]
	var r2: Dictionary = lot.build_wall(45, 34, 45, 31, 1000.0, "Test")
	var w2: Dictionary = lot.walls[int(r2["wid"])]
	check(int(w2["z0"]) == 31 and int(w2["z1"]) == 34, "obrácené koncové body se normalizují")
	check(int(w["x0"]) == 30 and int(w["x1"]) == 40, "záznam stěny")
	check(lot.check_wall(40, 30, 30, 30) == "wall_overlap", "duplicitní (obrácená) stěna")
	check(lot.check_wall(35, 30, 44, 30) == "wall_overlap", "částečný překryv")
	check(lot.check_wall(35, 26, 35, 34) == "wall_crossing", "křížení odmítnuto")
	check(lot.check_wall(35, 30, 35, 36) == "" and lot.check_wall(35, 24, 35, 30) == "", "T-spoj z obou stran povolen")
	check(lot.check_wall(40, 30, 40, 36) == "" and lot.check_wall(40, 30, 46, 30) == "", "roh a navázání na konec povoleny")
	# Peníze.
	var poor = _syn()
	poor.funds = 100
	var rp: Dictionary = poor.build_wall(30, 30, 34, 30, 1000.0)
	check(not bool(rp["ok"]) and String(rp["reason"]) == "funds" and poor.walls.is_empty() and poor.funds == 100, "bez peněz se nestaví (žádný dluh)")
	var rb: Dictionary = poor.build_wall(48, 20, 53, 20, 1000.0)
	check(String(rb["reason"]) == "blocked", "neplatné místo hlášeno dřív než peníze")
	# Limit počtu stěn.
	var full = LotGrid.new()
	full.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	full.rebuild()
	full.funds = LotGrid.MAX_FUNDS
	var built := 0
	for i in LotGrid.MAX_WALLS:
		var x := i % 100
		var z0 := (i / 100) * 3
		if bool(full.build_wall(x, z0, x, z0 + 2, 1000.0)["ok"]):
			built += 1
	check(built == LotGrid.MAX_WALLS, "128 stěn postaveno", str(built))
	check(full.check_wall(5, 20, 5, 25) == "wall_limit" and String(full.build_wall(5, 20, 5, 25, 1000.0)["reason"]) == "wall_limit",
		"limit 128 stěn na parcelu")
	# Dosažitelnost: krabice kolem postele – poslední stěna by ji odřízla od ulice.
	var box = _syn()
	check(box.access_reachable(Vector2(5.0, 6.0)), "bod použití postele je od ulice dosažitelný")
	var ok3 := bool(box.build_wall(12, 14, 28, 14, 1000.0)["ok"]) and bool(box.build_wall(12, 14, 12, 30, 1000.0)["ok"]) \
		and bool(box.build_wall(28, 14, 28, 30, 1000.0)["ok"])
	check(ok3 and box.access_reachable(Vector2(5.0, 6.0)), "tři strany krabice postavené, postel pořád dosažitelná")
	check(box.check_wall(12, 30, 28, 30) == "seals_off" and String(box.build_wall(12, 30, 28, 30, 1000.0)["reason"]) == "seals_off",
		"čtvrtá stěna by postel odřízla → odmítnuto")
	check(box.check_wall(12, 30, 26, 30) == "", "s mezerou 0,5 m (dveře) lze")
	check(box.check_wall(12, 30, 28, 30, false) == "", "bez kontroly cesty (obnova savu) by prošla – kontrola je opravdu BFS")


# ---------------------------------------------------------------- předměty a stěny

func _test_items_vs_walls() -> void:
	section("Předměty vs. stěny")
	var lot = _syn()
	var rp: Dictionary = lot.buy("plant_monstera", 70, 10, 0, 1000.0)
	check(bool(rp["ok"]), "rostlina koupena", str(rp))
	check(lot.check_wall(71, 8, 71, 14) == "overlap", "stěna skrz koupenou rostlinu neprojde")
	check(lot.check_wall(72, 8, 72, 14) == "", "těsně vedle rostliny lze")
	var rr: Dictionary = lot.buy("rug_wool", 30, 4, 0, 1000.0)
	check(bool(rr["ok"]), "koberec koupen", str(rr))
	check(lot.check_wall(34, 2, 34, 12) == "overlap", "stěna přes koberec neprojde")
	var rf: Dictionary = lot.buy("fridge_old", 8, 8, 0, 1000.0)
	check(bool(rf["ok"]), "lednice koupena", str(rf))
	check(lot.check_wall(6, 12, 13, 12) == "blocks_access", "stěna před lednicí by zatarasila přístup")
	check(lot.check_wall(6, 15, 13, 15) == "", "o kus dál lze")
	# Předměty k postaveným stěnám.
	var rw: Dictionary = lot.build_wall(60, 30, 80, 30, 1000.0)
	check(bool(rw["ok"]), "venkovní stěna 5 m", str(rw))
	check(lot.check("plant_monstera", 66, 29, 0) == "blocked", "předmět přes stěnu nejde")
	check(lot.check("plant_monstera", 66, 30, 0) == "" and lot.check("plant_monstera", 66, 28, 0) == "", "předmět těsně u stěny z obou stran lze")
	check(lot.check("bench_garden", 64, 26, 0) == "access_blocked", "lavička čelem do stěny: přístup by vedl skrz zeď")
	check(lot.check("bench_garden", 64, 26, 2) == "", "otočená lavička zády ke stěně lze")
	var rm: Dictionary = lot.move(int(rp["uid"]), 66, 29, 0, 1000.0)
	check(not bool(rm["ok"]) and String(rm["reason"]) == "blocked", "ani přesun přes stěnu")
	check(lot.check("rug_wool", 62, 27, 0) == "blocked", "koberec přes stěnu nejde")


# ---------------------------------------------------------------- zbourání

func _test_refunds() -> void:
	section("Zbourání a vratky")
	var lot = _syn()
	var f0: int = lot.funds
	var r: Dictionary = lot.build_wall(30, 30, 34, 30, 1000.0)
	var rr: Dictionary = lot.remove_wall(int(r["wid"]), 1000.0 + 1440.0)
	check(bool(rr["ok"]) and int(rr["refund"]) == 240 and lot.funds == f0 and lot.walls.is_empty(), "do 24 h plná vratka (omyl)")
	r = lot.build_wall(30, 30, 34, 30, 1000.0)
	check(lot.wall_refund_value(int(r["wid"]), 1000.0 + 1441.0) == 0, "po 24 h zbourání nic nevrátí")
	rr = lot.remove_wall(int(r["wid"]), 5000.0)
	check(bool(rr["ok"]) and int(rr["refund"]) == 0 and lot.funds == f0 - 240 and String(lot.ledger[-1]["kind"]) == "unwall", "stará stěna: suť bez vratky")
	r = lot.build_wall(30, 30, 34, 30, 5000.0)
	check(lot.wall_refund_value(int(r["wid"]), 100.0) == 0, "hodiny dozadu (rewind) ≠ vratka")
	check(String(lot.remove_wall(999, 5000.0)["reason"]) == "unknown_wid" and String(lot.remove_wall("1", 5000.0)["reason"]) == "unknown_wid"
		and String(lot.remove_wall(1.0, 5000.0)["reason"]) == "unknown_wid", "neznámá stěna / špatný typ")
	var wid := int(r["wid"])
	lot.remove_wall(wid, 5000.0)
	check(String(lot.remove_wall(wid, 5000.0)["reason"]) == "unknown_wid", "dvakrát zbourat nejde")
	check(lot.wall_at_world(Vector2(8.0, 7.55)) == 0, "po zbourání na místě nic není")
	var r3: Dictionary = lot.build_wall(32, 20, 40, 20, 5000.0)
	check(lot.wall_at_world(Vector2(9.0, 5.1)) == int(r3["wid"]) and lot.wall_at_world(Vector2(9.0, 5.5)) == 0, "výběr stěny myší (do 0,2 m)")


# ---------------------------------------------------------------- ukládání

func _test_save_and_migration() -> void:
	section("Ukládání stěn (v2) a migrace v1")
	var lot = _syn()
	lot.build_wall(30, 30, 40, 30, 1000.0, "A")
	lot.build_wall(35, 30, 35, 36, 1010.0, "A")
	lot.buy("plant_monstera", 70, 10, 0, 1020.0, "A")
	var d: Dictionary = JSON.parse_string(_snapshot_json(lot))
	check(int(d["version"]) == LotGrid.VERSION and (d["walls"] as Array).size() == 2 and int(d["next_wid"]) == 3, "snímek (v2+) se stěnami")
	check(LotGrid.validate_snapshot(d) == "", "platný snímek po JSON projde (float → int)")
	var b = _syn()
	var res: Dictionary = b.from_dict(d, 1100.0)
	check(bool(res["ok"]) and int(res["dropped"]) == 0, "obnova bez ztrát", str(res))
	check(_snapshot_json(b) == _snapshot_json(lot), "round-trip bit po bitu")
	var r4: Dictionary = b.build_wall(50, 4, 50, 12, 1100.0)
	check(int(r4["wid"]) == 3, "číslování stěn pokračuje (next_wid)")
	# Migrace v1.
	var v1: Dictionary = d.duplicate(true)
	v1["version"] = 1
	v1.erase("walls")
	v1.erase("next_wid")
	check(LotGrid.validate_snapshot(v1) == "", "save v1 (bez stěn) je platný")
	var c = _syn()
	c.build_wall(60, 30, 80, 30, 1000.0)
	res = c.from_dict(v1, 1100.0)
	check(bool(res["ok"]) and c.walls.is_empty() and c.next_wid == 1 and c.items.size() == 1, "v1 → parcela bez stěn, předměty zůstanou")
	v1["walls"] = "nesmysl"
	check(LotGrid.validate_snapshot(v1) == "", "v1 s cizím klíčem walls: ignorován (B1 stěny neměl)")
	check(int(c.to_dict()["version"]) == LotGrid.VERSION, "uloží se už v aktuálním formátu (v3 od B4)")
	# Neplatné stěny ve snímku v2.
	var bads := {}
	var base: Dictionary = d.duplicate(true)
	var m: Dictionary
	m = base.duplicate(true); m.erase("walls"); bads["chybí walls"] = m
	m = base.duplicate(true); m.erase("next_wid"); bads["chybí next_wid"] = m
	m = base.duplicate(true); m["walls"] = "x"; bads["walls není pole"] = m
	m = base.duplicate(true); m["walls"][0]["x0"] = 1.5; bads["necelá souřadnice"] = m
	m = base.duplicate(true); m["walls"][0]["evil"] = 1; bads["klíč navíc"] = m
	m = base.duplicate(true); m["walls"][0].erase("paid"); bads["chybí klíč"] = m
	m = base.duplicate(true); m["walls"][1]["wid"] = m["walls"][0]["wid"]; bads["duplicitní wid"] = m
	m = base.duplicate(true); m["walls"][0]["wid"] = 3; bads["wid ≥ next_wid"] = m
	m = base.duplicate(true); m["walls"][0]["paid"] = -5; bads["záporná cena"] = m
	m = base.duplicate(true); m["walls"][0]["built_at"] = NAN; bads["NaN čas"] = m
	m = base.duplicate(true); m["walls"][0]["z1"] = -1; bads["záporná souřadnice"] = m
	m = base.duplicate(true); m["walls"][0]["x1"] = "40"; bads["řetězec"] = m
	var many: Array = []
	for i in LotGrid.MAX_WALLS + 1:
		many.append({"wid": i + 1, "x0": i % 100, "z0": 0, "x1": i % 100, "z1": 2, "built_at": 0.0, "paid": 0})
	m = base.duplicate(true); m["walls"] = many; m["next_wid"] = 1000; bads["129 stěn"] = m
	var all_bad := true
	var which := ""
	for k in bads:
		if LotGrid.validate_snapshot(bads[k]) == "":
			all_bad = false
			which += k + "; "
	check(all_bad, "neplatné stěny ve snímku odmítnuty (%d variant)" % bads.size(), which)
	var before := _snapshot_json(b)
	var rbad: Dictionary = b.from_dict(bads["duplicitní wid"], 1200.0)
	check(not bool(rbad["ok"]) and _snapshot_json(b) == before, "neplatný snímek nic nezmění")
	# Změněné prostředí: stěna už nejde → vyřazena s vratkou max. v ceníkové ceně.
	var changed = _syn()
	changed.add_static_rect(Rect2(8.25, 7.25, 0.5, 0.5))
	changed.rebuild()
	var dd: Dictionary = d.duplicate(true)
	dd["walls"][0]["paid"] = 99999999
	var funds_before: int = int(dd["funds"])
	res = changed.from_dict(dd, 2000.0)
	check(bool(res["ok"]) and int(res["dropped_walls"]) == 1 and changed.walls.size() == 1, "stěna skrz nové prostředí vyřazena, druhá zůstala", str(res))
	check(int(res["refund"]) == 600 and changed.funds == funds_before + 600, "vratka jen do ceníkové ceny (upravený save netiskne peníze)",
		"%d %d" % [int(res["refund"]), changed.funds])
	# Pořadí obnovy: stěny napřed, předmět přes stěnu se vyřadí.
	var dw: Dictionary = d.duplicate(true)
	dw["items"].append({"uid": 2, "id": "plant_monstera", "cx": 36, "cz": 29, "rot": 0, "bought_at": 0.0, "paid": 590})
	dw["next_uid"] = 3
	var e = _syn()
	res = e.from_dict(dw, 2000.0)
	check(bool(res["ok"]) and e.walls.size() == 2 and e.items.size() == 1 and int(res["refund"]) == 590, "předmět přes uloženou stěnu vyřazen a vrácen", str(res))


# ---------------------------------------------------------------- síť: veřejný snímek

func _walls_valid(lot) -> bool:
	var geo: Array = []
	for wid in lot.sorted_wids():
		var w: Dictionary = lot.walls[wid]
		var cells: int = absi(int(w["x1"]) - int(w["x0"])) + absi(int(w["z1"]) - int(w["z0"]))
		if cells < LotGrid.WALL_MIN_CELLS or cells > LotGrid.WALL_MAX_CELLS:
			return false
		geo.append({"x0": int(w["x0"]), "z0": int(w["z0"]), "x1": int(w["x1"]), "z1": int(w["z1"])})
	return geo.is_empty() or WallGeometry.validate(geo, lot.gw, lot.gh) == ""


func _test_public_fuzz() -> void:
	section("Veřejný snímek stěn (síť) a fuzz")
	var srv = _syn()
	srv.build_wall(30, 30, 40, 30, 1000.0)
	srv.build_wall(35, 30, 35, 36, 1000.0)
	srv.build_wall(60, 30, 80, 30, 1000.0)
	var pub: Dictionary = srv.public_snapshot()
	check((pub["walls"] as Array).size() == 3 and (pub["walls"][0] as Array).size() == 7, "snímek obsahuje stěny jako pole")
	var cl = _syn()
	check(cl.apply_public(JSON.parse_string(JSON.stringify(pub))) and cl.walls.size() == 3 and cl.next_wid == 4, "klient převezme stěny (i po JSON)")
	var old_pub := {"v": 1, "rev": 5, "funds": 100, "items": []}
	var cl1 = _syn()
	check(cl1.apply_public(old_pub) and cl1.walls.is_empty(), "snímek bez stěn (v1) = žádné stěny")
	var crafted := {
		"křížení": [[1, 30, 30, 40, 30, 0.0, 0], [2, 35, 26, 35, 34, 0.0, 0]],
		"mimo mřížku": [[1, 30, 30, 101, 30, 0.0, 0]],
		"šikmá": [[1, 30, 30, 34, 34, 0.0, 0]],
		"krátká": [[1, 30, 30, 31, 30, 0.0, 0]],
		"duplicitní wid": [[1, 30, 30, 34, 30, 0.0, 0], [1, 30, 32, 34, 32, 0.0, 0]],
		"float": [[1, 30.5, 30, 34, 30, 0.0, 0]],
		"krátký záznam": [[1, 30, 30, 34]],
	}
	var ok := true
	var bad_names := ""
	for k in crafted:
		var s: Dictionary = pub.duplicate(true)
		s["walls"] = crafted[k]
		var before := JSON.stringify(cl.public_snapshot())
		if cl.apply_public(s) or JSON.stringify(cl.public_snapshot()) != before:
			ok = false
			bad_names += k + "; "
	check(ok, "podvržené stěny ve snímku odmítnuty, stav beze změny (%d variant)" % crafted.size(), bad_names)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	var weird := [null, -1, 0, 1, 2, 7, 39, 40, 41, 99, 100, 101, 1.5, "1", [], {}, NAN, INF, 1e12, 2147483647]
	var accepted := 0
	var consistent := true
	for i in 300:
		var s2: Dictionary = pub.duplicate(true)
		var ws: Array = s2["walls"]
		match rng.randi_range(0, 4):
			0:
				var e: Array = ws[rng.randi_range(0, ws.size() - 1)]
				e[rng.randi_range(0, 6)] = weird[rng.randi_range(0, weird.size() - 1)]
			1:
				ws.append([rng.randi_range(1, 9), rng.randi_range(0, 100), rng.randi_range(0, 40), rng.randi_range(0, 100), rng.randi_range(0, 40), 0.0, 0])
			2:
				ws.append(ws[rng.randi_range(0, ws.size() - 1)].duplicate())
			3:
				var e2: Array = ws[rng.randi_range(0, ws.size() - 1)]
				var dx := rng.randi_range(-6, 6)
				e2[1] = int(e2[1]) + dx
				e2[3] = int(e2[3]) + dx
			4:
				s2["walls"] = weird[rng.randi_range(0, weird.size() - 1)]
		var c2 = _syn()
		var before2 := JSON.stringify(c2.public_snapshot())
		if c2.apply_public(s2):
			accepted += 1
			if not _walls_valid(c2):
				consistent = false
		elif JSON.stringify(c2.public_snapshot()) != before2:
			consistent = false
	check(consistent, "300 mutací: přijatý snímek má vždy platnou geometrii, odmítnutý nic nezmění (přijato %d)" % accepted)


# ---------------------------------------------------------------- výkon

func _test_performance() -> void:
	section("Výkon")
	var lot = LotGrid.new()
	lot.setup(Vector2.ZERO, Vector2(25.0, 10.0))
	lot.rebuild()
	lot.funds = LotGrid.MAX_FUNDS
	for i in LotGrid.MAX_WALLS - 1:
		lot.build_wall(i % 100, (i / 100) * 3, i % 100, (i / 100) * 3 + 2, 0.0)
	# Nejhorší případ: kandidát 20 m se dotýká konců 81 stěn (všechny v obálce, žádný konflikt).
	check(lot.check_wall(0, 2, 80, 2) == "", "dlouhá stěna napojená na 81 konců je platná")
	var t0 := Time.get_ticks_usec()
	for i in 50:
		lot.check_wall(0, 2, 80, 2)
	var per := float(Time.get_ticks_usec() - t0) / 50.0
	check(per < 2500.0, "kontrola stěny při 127 stěnách (nejhorší případ) < 2,5 ms (%.0f µs)" % per)
	var t0b := Time.get_ticks_usec()
	for i in 50:
		lot.check_wall(3, 20, 3, 30)
	var perb := float(Time.get_ticks_usec() - t0b) / 50.0
	check(perb < 500.0, "běžná kontrola stěny < 0,5 ms (%.0f µs)" % perb)
	var t1 := Time.get_ticks_usec()
	for i in 200:
		lot.check("plant_monstera", 40, 30, 0)
	var per2 := float(Time.get_ticks_usec() - t1) / 200.0
	check(per2 < 1000.0, "kontrola předmětu při 127 stěnách < 1 ms (%.0f µs)" % per2)
	var a = _syn()
	var b = _syn()
	for l in [a, b]:
		l.build_wall(30, 30, 40, 30, 10.0)
		l.build_wall(35, 30, 35, 36, 20.0)
		l.remove_wall(1, 30.0)
		l.build_wall(60, 30, 80, 30, 40.0)
	check(_snapshot_json(a) == _snapshot_json(b), "stejné operace = stejný stav (deterministické)")


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


func _test_world() -> void:
	section("Stěny v herním světě (startovní parcela)")
	var world := _offline_world("WallWorld")
	var lot = world.lot
	check(int(lot.to_dict()["version"]) == LotGrid.VERSION, "parcela v aktuálním formátu (v3 od B4)")
	# Skutečné zdi domu a dveře.
	var p1: Vector2i = lot.snap_lattice(Vector2(-3.0, 3.75))
	var p2: Vector2i = lot.snap_lattice(Vector2(-3.0, 5.5))
	check(lot.check_wall(p1.x, p1.y, p2.x, p2.y) == "blocked", "přes jižní zeď domu neprojde")
	var q1: Vector2i = lot.snap_lattice(Vector2(-2.0, 5.0))
	var q2: Vector2i = lot.snap_lattice(Vector2(2.0, 5.0))
	check(lot.check_wall(q1.x, q1.y, q2.x, q2.y) == "blocked", "vchod nejde zazdít")
	var fixed_ok := true
	var unreach := ""
	for f in lot.fixed:
		for ap in f["access"]:
			if not lot.access_reachable(ap):
				fixed_ok = false
				unreach += String(f["name"]) + "; "
	check(fixed_ok, "všechny body použití výchozího nábytku jsou od ulice dosažitelné", unreach)
	# Zazdění koupelny „zvenku“: stěna těsně za koncem koupelnového koridoru (koridoru se nedotýká).
	var s1: Vector2i = lot.snap_lattice(Vector2(-4.4, 3.25))
	var s2: Vector2i = lot.snap_lattice(Vector2(-2.6, 3.25))
	var seal := String(lot.check_wall(s1.x, s1.y, s2.x, s2.y))
	check(seal != "", "koupelnu nejde odříznout stěnou za koridorem (%s)" % seal, seal)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		lot._reachable({})
	var bfs := float(Time.get_ticks_usec() - t0) / 10.0
	check(bfs < 40000.0, "BFS dosažitelnosti na skutečné parcele < 40 ms (%.1f ms)" % (bfs / 1000.0))
	var base_objs: int = world.smart_objects.size()
	var inner := _find_wall(lot, [0.5, -3.5, 5.6, 3.0], 8, false)
	check(not inner.is_empty(), "uvnitř domu je místo na příčku 2 m", str(inner))
	if inner.is_empty():
		world.free()
		return
	var r: Dictionary = world.lot_apply_action("wall", inner, "Test")
	check(bool(r["ok"]), "příčka postavena přes autoritu světa", str(r))
	var node: Node3D = world.wall_node(int(r["wid"]))
	check(node is StaticBody3D and node.is_inside_tree() and int(node.get_meta("lot_wall")) == int(r["wid"]), "uzel stěny ve světě")
	var shape: CollisionShape3D = null
	for ch in node.get_children():
		if ch is CollisionShape3D:
			shape = ch
	var ab: Array = lot.wall_world(lot.walls[int(r["wid"])])
	var len_m: float = (ab[0] as Vector2).distance_to(ab[1])
	check(shape != null and (shape.shape as BoxShape3D).size.is_equal_approx(Vector3(len_m + LotGrid.WALL_THICK, LotGrid.WALL_HEIGHT, LotGrid.WALL_THICK)),
		"kolize: kvádr délka + tloušťka × 2,7 m × 0,12 m")
	var mid: Vector2 = ((ab[0] as Vector2) + (ab[1] as Vector2)) * 0.5
	check(Vector2(node.position.x, node.position.z).distance_to(mid) < 1e-4 and is_equal_approx(node.rotation_degrees.y, 90.0), "poloha a otočení svislé stěny")
	check(node.get_node_or_null("Body") != null and node.get_node_or_null("Skirting") != null, "omítka a sokl")
	check(world.smart_objects.size() == base_objs, "stěna nepřidává chytré objekty (indexy příkazů beze změny)")
	var r2: Dictionary = world.lot_apply_action("wall", inner, "Test")
	check(not bool(r2["ok"]) and String(r2["reason"]) == "wall_overlap", "druhá stejná stěna odmítnuta")
	check(String(world.lot_apply_action("wall", [1, 2, 3], "Test")["reason"]) == "wall_bad", "špatný počet argumentů")
	# Uložení a načtení z disku.
	var snap := JSON.stringify(lot.to_dict())
	var saved: Dictionary = world.save_game("manual")
	check(bool(saved.get("ok", false)), "uloženo", str(saved))
	world.lot_apply_action("unwall", [int(r["wid"])], "Test")
	check(lot.walls.is_empty() and world.wall_node(int(r["wid"])) == null, "zbourání odstraní uzel")
	var loaded: Dictionary = world.load_game("manual")
	check(bool(loaded.get("ok", false)), "načteno", str(loaded))
	check(JSON.stringify(world.lot.to_dict()) == snap, "stěny po načtení z disku bit po bitu")
	var n2: Node3D = world.wall_node(int(r["wid"]))
	check(n2 != null and n2.is_inside_tree() and Vector2(n2.position.x, n2.position.z).distance_to(mid) < 1e-4, "uzel stěny postaven znovu")
	var rr: Dictionary = world.lot_apply_action("unwall", [int(r["wid"])], "Test")
	check(bool(rr["ok"]) and int(rr["refund"]) == int(r["price"]), "zbourání týž den vrátí cenu")
	world.free()


# ---------------------------------------------------------------- UI nástroje Zeď

func _test_ui() -> void:
	section("UI: nástroj Zeď")
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "WallUiWorld"
	w.net_config = {"mode": "offline", "audio": false, "camera": true, "visuals": false, "hud": true,
		"autoload": false, "autosave": false, "save_directory": save_dir + "-ui", "clock": clock}
	add_child(w)
	await get_tree().process_frame
	w.toggle_buy_mode()
	var bm = w.buy_mode
	check(bm != null and bm._wall_btn != null and bm._wall_btn.is_inside_tree(), "tlačítko Stavět zeď")
	bm.set_process(false)
	bm.set_wall_tool(true)
	check(bm.wall_tool and bm._wall_btn.button_pressed and bm.selected_id == "", "nástroj Zeď zapnut")
	var spot := _find_wall(w.lot, [7.0, 6.0, 12.0, 11.0], 8, true)
	check(not spot.is_empty(), "na zahradě je místo na zeď", str(spot))
	if spot.is_empty():
		bm.close()
		w.queue_free()
		return
	bm.wall_dragging = true
	bm.set_wall_drag(Vector2i(spot[0], spot[1]), Vector2i(spot[2], spot[1] + 2))
	check(bm.wall_end == Vector2i(spot[2], spot[1]), "osový zámek: delší směr vyhraje")
	bm.update_wall_ghost()
	check(bm.last_reason == "" and bm._wall_ghost.visible and String(bm._status.text).find("2,00 m") >= 0 and String(bm._status.text).find("480 kr") >= 0,
		"zelený duch s délkou a cenou", String(bm._status.text))
	var funds0: int = w.lot.funds
	bm.place_wall()
	check(w.lot.walls.size() == 1 and w.lot.funds == funds0 - 480, "puštění myši postaví zeď přes autoritu")
	bm.wall_dragging = true
	bm.set_wall_drag(Vector2i(spot[0], spot[1]), Vector2i(spot[2], spot[1]))
	bm.update_wall_ghost()
	check(bm.last_reason == "wall_overlap" and String(bm._status.text) == String(LotGrid.REASON_TEXT["wall_overlap"]), "na stejném místě červený duch s důvodem")
	bm.wall_dragging = false
	bm.selected_wid = int(w.lot.sorted_wids()[0])
	bm._refresh()
	check(bm._wall_box.visible and String(bm._wall_label.text).find("480 kr") >= 0, "vybraná zeď ukazuje vratku", String(bm._wall_label.text))
	bm.demolish_selected_wall()
	check(w.lot.walls.is_empty() and w.lot.funds == funds0, "Zbourat vrátí peníze (týž den)")
	bm._refresh()
	check(not bm._wall_box.visible and bm.selected_wid == 0, "po zbourání výběr zmizí")
	bm.set_wall_tool(false)
	check(not bm.wall_tool and not bm._wall_ghost.visible, "nástroj vypnut, duch skrytý")
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
	w.net.notice.connect(func(t: String): notices[bname].append(t))
	return w


func _client(bname: String, player_name: String) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"audio": false, "hud": false, "camera": false, "visuals": false})


func _test_multiplayer() -> void:
	section("Multiplayer: stěny přes autoritativní server (ENet)")
	clock.total_minutes = 600.0
	var server := _branch("WallServer", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(server.net.mode == NetSession.Mode.DEDICATED, "dedikovaný server běží")
	var a := _client("WallClientA", "Zedník")
	check(await wait_until(func(): return a.net.my_sim != "", 6.0), "klient přivítán s postavou")
	var spot := _find_wall(server.lot, [7.0, 6.0, 12.0, 11.0], 8, true)
	check(not spot.is_empty(), "místo na zeď", str(spot))
	check(not bool(a.lot_apply_action("wall", spot, "x")["ok"]) and a.lot.walls.is_empty(), "klient sám stěnu nepostaví (jen server)")
	a.request_lot_action("wall", spot)
	check(await wait_until(func(): return server.lot.walls.size() == 1, 3.0), "server postavil stěnu klienta")
	check(await wait_until(func(): return a.lot.walls.size() == 1 and a.lot.funds == server.lot.funds and a.wall_node(1) != null, 3.0),
		"klient dostal stěnu, rozpočet i uzel")
	var sn: Node3D = server.wall_node(1)
	var cn: Node3D = a.wall_node(1)
	check(sn != null and cn != null and sn.position.distance_to(cn.position) < 1e-4 and is_equal_approx(sn.rotation_degrees.y, cn.rotation_degrees.y),
		"uzel stěny stojí na klientu stejně jako na serveru")
	# Podvržené požadavky (obchází UI, posílá rovnou RPC).
	await wait_seconds(1.2)
	var funds0: int = server.lot.funds
	var walls0 := JSON.stringify(server.lot.public_snapshot()["walls"])
	var rej0: int = server.net.stats["rejected"]
	a.net._c2s_lot.rpc_id(1, "wall", [1.5, 2, 9, 2])
	a.net._c2s_lot.rpc_id(1, "wall", [0, 0, 100000, 0])
	a.net._c2s_lot.rpc_id(1, "wall", [-1, 3, 5, 3])
	a.net._c2s_lot.rpc_id(1, "wall", [1, 2, 3, 4, 5])
	await wait_seconds(1.1)
	a.net._c2s_lot.rpc_id(1, "unwall", ["1"])
	a.net._c2s_lot.rpc_id(1, "unwall", [1, 2])
	a.net._c2s_lot.rpc_id(1, "wall", "x")
	await wait_seconds(0.6)
	check(server.lot.funds == funds0 and JSON.stringify(server.lot.public_snapshot()["walls"]) == walls0, "podvržené požadavky nic nezměnily")
	check(int(server.net.stats["rejected"]) >= rej0 + 7, "server je odmítl a počítá", "%d → %d" % [rej0, int(server.net.stats["rejected"])])
	# Platné typy, ale porušená pravidla (křížení přes střed stěny) → hláška hráči.
	await wait_seconds(3.0)
	notices["WallClientA"].clear()
	var mx := int((int(spot[0]) + int(spot[2])) / 2)
	a.net._c2s_lot.rpc_id(1, "wall", [mx, int(spot[1]) - 3, mx, int(spot[1]) + 3])
	check(await wait_until(func(): return notices["WallClientA"].size() > 0, 3.0) and server.lot.walls.size() == 1,
		"křížící stěna odmítnuta pravidly, hráč dostal důvod", str(notices["WallClientA"]))
	# Vlastní limit stěn (BFS je drahé): 4 platně typované požadavky naráz → aspoň 2 odmítnuty limitem zedníka.
	await wait_seconds(4.5)
	notices["WallClientA"].clear()
	for i in 4:
		a.net._c2s_lot.rpc_id(1, "wall", [mx, int(spot[1]) - 3, mx, int(spot[1]) + 3])
	await wait_seconds(0.8)
	var mason := 0
	for t in notices["WallClientA"]:
		if String(t).find("zedník") >= 0:
			mason += 1
	check(mason >= 2 and server.lot.walls.size() == 1, "přísnější limit stavby stěn (%d odmítnuto)" % mason, str(notices["WallClientA"]))
	await wait_seconds(4.5)
	# Pozdní připojení.
	var b := _client("WallClientB", "Pozdní")
	check(await wait_until(func(): return b.net.my_sim != "" and b.lot.walls.size() == 1 and b.wall_node(1) != null, 6.0),
		"pozdě připojený hráč dostane stěny po vstupu")
	# Zbourání z klienta A se projeví všude.
	await wait_seconds(1.2)
	a.request_lot_action("unwall", [1])
	check(await wait_until(func(): return server.lot.walls.is_empty() and b.lot.walls.is_empty() and b.wall_node(1) == null and a.wall_node(1) == null, 3.0),
		"zbourání z klienta A zmizí na serveru i u klienta B")
	check(server.lot.funds == funds0 + 480 and b.lot.funds == server.lot.funds, "vratka týž den připsána a replikována")
	var cap: Dictionary = load("res://scripts/save/game_save.gd").capture(server, true)
	check(bool(cap.get("ok", false)) and cap["data"]["lot"].has("walls"), "serverový snímek světa ukládá stěny")
	for w in [a, b, server]:
		w.net.shutdown()
	await wait_seconds(0.3)
	for w in [a, b, server]:
		w.get_parent().queue_free()
	await wait_seconds(0.2)
