extends "res://tests/test_base.gd"
## B1 (20. 11. 2026): mřížka parcely a režim nákupu.
## Pravidla umístění na skutečné startovní parcele, transakce a peníze, prodej/amortizace, přesun,
## atmosféra → nálada, kvalita předmětu → rychlost spánku, ukládání (round-trip, starý save, poškozená sekce),
## fuzz snímků, MP: autorita serveru, replikace klientům, pozdní připojení, podvržené požadavky, rate limit,
## shoda indexů objektů server ↔ klient, výkon kontroly umístění.

const Main := preload("res://main.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")
const Catalog := preload("res://scripts/world/buy_catalog.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

var clock: Node
var save_dir := ""
var port := 0
var notices := {}


func _ready() -> void:
	watchdog_seconds = 110.0
	randomize()
	port = 25400 + randi() % 700
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 1000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	save_dir = "user://test-lot-buy-" + str(OS.get_process_id())
	_run.call_deferred()


func _offline_world(wname: String) -> Node3D:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = wname
	w.net_config = {"mode": "offline", "audio": false, "camera": false, "visuals": false, "hud": false,
		"autoload": false, "autosave": false, "save_directory": save_dir, "clock": clock}
	add_child(w)
	return w


## První platná kotva v obdélníku (svět x0, z0, x1, z1) pro položku a otočení; Vector2i(-9999) = nic.
func _spot(lot, id: String, rot: int, x0: float, z0: float, x1: float, z1: float) -> Vector2i:
	var a: Vector2i = lot.cell_of_world(Vector2(x0, z0))
	var b: Vector2i = lot.cell_of_world(Vector2(x1, z1))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			if lot.check(id, cx, cz, rot) == "":
				return Vector2i(cx, cz)
	return Vector2i(-9999, -9999)


func _run() -> void:
	await _test_rules()
	await _test_world_integration()
	await _test_save()
	await _test_snapshot_fuzz()
	await _test_multiplayer()
	await _test_ui()
	clock.running = false
	finish("test_lot_buy")


# ---------------------------------------------------------------- pravidla na skutečné parcele

func _test_rules() -> void:
	section("Katalog a mřížka startovní parcely")
	check(Catalog.validate(LotGrid.CELL).is_empty(), "katalog je konzistentní", str(Catalog.validate(LotGrid.CELL)))
	check(Catalog.ITEMS.size() >= 20, "katalog má aspoň 20 položek", str(Catalog.ITEMS.size()))
	var world := _offline_world("RulesWorld")
	var lot = world.lot
	check(lot != null and lot.gw == 96 and lot.gh == 99, "mřížka 0,25 m: 96 × 99 buněk", "%d×%d" % [lot.gw, lot.gh])
	check(lot.fixed.size() == world.lot_base_count and world.lot_base_count == world.smart_objects.size(),
		"výchozí nábytek zaregistrován jako pevné položky", "%d/%d" % [lot.fixed.size(), world.lot_base_count])
	var c_in: Vector2i = lot.cell_of_world(Vector2(1.0, 0.5))
	var c_out: Vector2i = lot.cell_of_world(Vector2(8.0, 8.0))
	check(lot.is_inside_cell(c_in.x, c_in.y) and not lot.is_inside_cell(c_out.x, c_out.y), "vnitřek domu vs. zahrada")
	check(lot.funds == LotGrid.START_FUNDS, "startovní rozpočet %d kr" % LotGrid.START_FUNDS)

	section("Pravidla umístění")
	var wall: Vector2i = lot.cell_of_world(Vector2(0.0, -4.6))
	check(lot.check("plant_monstera", wall.x - 1, wall.y - 1, 0) == "blocked", "na stěně nic nestojí")
	var path: Vector2i = lot.cell_of_world(Vector2(0.0, 9.0))
	check(lot.check("plant_monstera", path.x - 1, path.y, 0) == "blocked", "chodník k ulici zůstává volný")
	var door: Vector2i = lot.cell_of_world(Vector2(-0.3, 4.0))
	check(lot.check("plant_monstera", door.x, door.y, 0) == "blocked", "vchodové dveře nejdou zatarasit")
	check(lot.check("plant_monstera", -2, 5, 0) == "out_of_bounds" and lot.check("plant_monstera", lot.gw - 1, 5, 0) == "out_of_bounds",
		"mimo parcelu")
	check(lot.check("nesmysl", 10, 10, 0) == "unknown_item" and lot.check("plant_monstera", 10, 10, 4) == "bad_rotation"
		and lot.check("plant_monstera", 10.0, 10, 0) == "out_of_bounds", "neznámá položka, otočení i typ souřadnic")
	# Lednice stojí na (-5,4; -3,95), přístup 1 m před ní.
	var fr: Vector2i = lot.cell_of_world(Vector2(-5.6, -3.1))
	check(lot.check("plant_monstera", fr.x, fr.y, 0) == "blocks_access", "nezatarasíš přístup k výchozí lednici")
	var sofa_c: Vector2i = lot.cell_of_world(Vector2(2.3, -1.0))
	check(lot.check("plant_monstera", sofa_c.x, sofa_c.y, 0) == "overlap", "na výchozí gauč se nic nepostaví")
	var garden: Vector2i = lot.cell_of_world(Vector2(8.0, 8.0))
	check(lot.check("fridge_old", garden.x, garden.y, 0) == "indoor_only", "lednice na zahradu nepatří")
	var g_out: Vector2i = lot.cell_of_world(Vector2(8.0, 8.0))
	check(lot.check("bed_single_pine", g_out.x, g_out.y, 0) == "indoor_only", "postel jen dovnitř")
	var inside_grill := _spot(lot, "plant_monstera", 0, 0.5, 0.5, 5.5, 4.0)
	check(lot.check("grill_garden", inside_grill.x, inside_grill.y, 0) in ["outdoor_only", "overlap", "blocks_access", "access_blocked"],
		"gril jen ven", lot.check("grill_garden", inside_grill.x, inside_grill.y, 0))
	# Gauč u zadní stěny (x 3,5–5,75; z −4,5…−3,5): zády ke zdi jde, čelem ke zdi ne (k sedáku se nedá dojít).
	var back: Vector2i = lot.cell_of_world(Vector2(3.51, -4.49))
	var sofa_back: String = lot.check("sofa_lagom", back.x, back.y, 0)
	var sofa_face: String = lot.check("sofa_lagom", back.x, back.y, 2)
	check(sofa_back == "", "gauč zády ke stěně jde postavit", sofa_back)
	check(sofa_face == "access_blocked", "gauč čelem do zdi neprojde (přístup za zdí)", sofa_face)
	check(lot.dims("sofa_lagom", 0) == Vector2i(9, 4) and lot.dims("sofa_lagom", 1) == Vector2i(4, 9), "otočení prohodí rozměry")

	section("Nákup, peníze, limity")
	var p_spot := _spot(lot, "plant_monstera", 0, 6.5, 6.0, 11.0, 11.0)
	var r: Dictionary = world.lot_apply_action("buy", ["plant_monstera", p_spot.x, p_spot.y, 0], "Test")
	check(bool(r["ok"]) and lot.funds == LotGrid.START_FUNDS - 590 and lot.items.size() == 1, "koupě rostliny (−590 kr)", str(r))
	var plant_uid: int = int(r["uid"])
	check(world.lot_node(plant_uid) != null and not world.smart_objects.has(world.lot_node(plant_uid)),
		"dekorace má uzel, ale není chytrý objekt pro AI")
	check(lot.check("plant_monstera", p_spot.x, p_spot.y, 0) == "overlap", "na koupenou věc se nic nepostaví")
	var before: int = lot.funds
	lot.funds = 500
	var r2: Dictionary = world.lot_apply_action("buy", ["sofa_lagom", 0, 0, 0], "Test")
	var sp := _spot(lot, "sofa_lagom", 0, 0.5, -1.0, 5.5, 4.0)
	var r3: Dictionary = world.lot_apply_action("buy", ["sofa_lagom", sp.x, sp.y, 0], "Test")
	check(not bool(r3["ok"]) and String(r3["reason"]) == "funds" and lot.funds == 500, "bez peněz se nekoupí (žádný dluh)", str(r3))
	check(not bool(r2["ok"]), "neplatné místo odmítnuto dřív než peníze")
	lot.funds = before
	var rug_spot := _spot(lot, "rug_wool", 0, -1.0, -3.5, 5.0, 0.0)
	var rr: Dictionary = world.lot_apply_action("buy", ["rug_wool", rug_spot.x, rug_spot.y, 0], "Test")
	check(bool(rr["ok"]), "koberec koupen", str(rr))
	check(lot.check("rug_wool", rug_spot.x, rug_spot.y, 0) == "overlap", "koberec na koberec nejde")
	var on_rug: String = lot.check("plant_monstera", rug_spot.x + 1, rug_spot.y + 1, 0)
	check(on_rug == "", "na koberec se dá postavit nábytek (jiná vrstva)", on_rug)
	# Limit počtu předmětů: odpadkové pytle zdarma po zahradě.
	var bags := 0
	var limit_hit := ""
	for i in 200:
		var s := _spot(lot, "trash_bags", 0, -11.5, -11.5, 11.5, -5.5)
		if s.x == -9999:
			break
		var rb: Dictionary = world.lot_apply_action("buy", ["trash_bags", s.x, s.y, 0], "Test")
		if not bool(rb["ok"]):
			limit_hit = String(rb["reason"])
			break
		bags += 1
	check(limit_hit == "limit" and lot.items.size() == LotGrid.MAX_ITEMS, "limit %d předmětů na parcelu" % LotGrid.MAX_ITEMS,
		"%s / %d" % [limit_hit, lot.items.size()])
	# Prodej všech pytlů (zdarma → výkup 0).
	for uid in lot.sorted_uids():
		if String(lot.items[uid]["id"]) == "trash_bags":
			world.lot_apply_action("sell", [uid], "Test")
	check(lot.items.size() == 2, "pytle prodány", str(lot.items.size()))

	section("Prodej a amortizace")
	var f0: int = lot.funds
	var bspot := _spot(lot, "bench_garden", 0, 4.0, 6.0, 11.0, 11.0)
	var rbench: Dictionary = world.lot_apply_action("buy", ["bench_garden", bspot.x, bspot.y, 0], "Test")
	var buid: int = int(rbench["uid"])
	check(lot.sell_value(buid, clock.total_minutes + 60.0) == 2490, "do 24 h plná cena")
	check(lot.sell_value(buid, clock.total_minutes + 2.0 * 1440.0) == int(floor(2490.0 * lerpf(0.55, 0.3, 2.0 / 180.0))),
		"po 2 dnech 55 % klesajících k 30 %")
	check(lot.sell_value(buid, clock.total_minutes + 400.0 * 1440.0) == int(floor(2490.0 * 0.3)), "staré věci 30 %")
	check(lot.sell_value(buid, clock.total_minutes - 500.0) < 2490, "hodiny vrácené dozadu ≠ plná vratka (rewind)")
	var rs: Dictionary = world.lot_apply_action("sell", [buid], "Test")
	check(bool(rs["ok"]) and int(rs["refund"]) == 2490 and lot.funds == f0, "prodej týž den vrátí vše", str(rs))
	check(not bool(world.lot_apply_action("sell", [buid], "Test")["ok"]), "dvakrát prodat nejde")

	section("Přesun")
	var r_move_ok: Dictionary = world.lot_apply_action("move", [plant_uid, p_spot.x + 1, p_spot.y, 1], "Test")
	check(bool(r_move_ok["ok"]) and int(lot.items[plant_uid]["cx"]) == p_spot.x + 1, "přesun o buňku (překryv se sebou samým je OK)", str(r_move_ok))
	var node: Node3D = world.lot_node(plant_uid)
	var c: Vector2 = lot.center_of("plant_monstera", p_spot.x + 1, p_spot.y, 1)
	check(node.position.distance_to(Vector3(c.x, 0, c.y)) < 1e-4 and is_equal_approx(node.rotation_degrees.y, 90.0), "uzel se přesunul a otočil")
	check(String(world.lot_apply_action("move", [plant_uid, wall.x, wall.y - 1, 0], "Test")["reason"]) == "blocked", "přesun do zdi odmítnut")

	section("Atmosféra → nálada")
	var sim = world.sims[0]
	var pos := Vector2(8.6, 9.6)
	var placed := 0
	for i in 3:
		var ps := _spot(lot, "plant_monstera", 0, 7.5, 8.5, 9.8, 10.8)
		if ps.x > -9999 and bool(world.lot_apply_action("buy", ["plant_monstera", ps.x, ps.y, 0], "Test")["ok"]):
			placed += 1
	var app: float = lot.appeal_at(pos)
	check(placed == 3 and app >= 5.0, "tři rostliny = hezké místo", "%d / %.1f" % [placed, app])
	check(lot.appeal_at(Vector2(-11.0, -11.0)) == 0.0, "daleko od věcí atmosféra 0")
	sim.global_position = Vector3(pos.x, 0, pos.y)
	sim.set_physics_process(false)
	world._lot_appeal_tick(61.0)
	check(sim.mood.has_moodlet("hezky_domov"), "postava mezi rostlinami: „Hezky zařízený domov“")
	var cap_lot = LotGrid.new()
	cap_lot.setup(Vector2(0, 0), Vector2(10, 10))
	for i in 9:
		cap_lot.buy("plant_monstera", (i % 3) * 3, int(i / 3) * 3, 0, 0.0)
	check(cap_lot.appeal_at(Vector2(4, 4)) <= LotGrid.APPEAL_CAP, "atmosféra je oříznutá", str(cap_lot.appeal_at(Vector2(4, 4))))

	section("Kvalita předmětu mění spánek")
	var q_bad: float = await _sleep_gain(world, "mattress_bazaar")
	var q_good: float = await _sleep_gain(world, "bed_double_nocturne")
	check(q_bad > 0.0 and q_good > 0.0 and q_bad / q_good > 0.45 and q_bad / q_good < 0.68,
		"bazarová matrace dobíjí energii pomaleji (≈ 0,7/1,25)", "%.2f / %.2f" % [q_bad, q_good])

	section("Výkon a determinismus")
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in 2000:
		lot.check("sofa_lagom", 20 + i % 50, 10 + int(i / 50) % 70, i % 4)
		n += 1
	var us := float(Time.get_ticks_usec() - t0) / n
	check(us < 400.0, "kontrola umístění < 0,4 ms (%.0f µs)" % us)
	t0 = Time.get_ticks_usec()
	lot.rebuild()
	var rb_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(rb_ms < 60.0, "přepočet mřížky < 60 ms (%.1f ms)" % rb_ms)
	var l1 = LotGrid.new()
	var l2 = LotGrid.new()
	for L in [l1, l2]:
		L.setup(Vector2(-5, -5), Vector2(5, 5))
		L.add_static_rect(Rect2(Vector2(-1, -1), Vector2(2, 0.2)))
		L.rebuild()
		L.buy("sofa_bazaar", 2, 2, 0, 10.0, "a")
		L.buy("plant_monstera", 20, 20, 1, 11.0, "b")
		L.sell(1, 5000.0, "a")
	check(JSON.stringify(l1.to_dict()) == JSON.stringify(l2.to_dict()), "stejné operace = stejný stav (deterministické)")
	world.free()


## Postava spí na nově koupené posteli; vrací přírůstek energie za 60 herních minut.
func _sleep_gain(world: Node3D, id: String) -> float:
	var lot = world.lot
	lot.funds = 100000  # test kvality, ne rozpočtu
	var s := _spot(lot, id, 0, 0.5, -1.0, 5.6, 4.2)
	if s.x == -9999:
		s = _spot(lot, id, 1, -2.5, -4.2, 5.6, 4.2)
		if s.x == -9999:
			return -1.0
		var rr: Dictionary = world.lot_apply_action("buy", [id, s.x, s.y, 1], "Test")
		if not bool(rr["ok"]):
			return -2.0
		return await _sleep_on(world, int(rr["uid"]))
	var r: Dictionary = world.lot_apply_action("buy", [id, s.x, s.y, 0], "Test")
	if not bool(r["ok"]):
		return -2.0
	return await _sleep_on(world, int(r["uid"]))


func _sleep_on(world: Node3D, uid: int) -> float:
	var node: Node3D = world.lot_node(uid)
	var sim = world.sims[1]
	sim.command({"id": "cancel"}, null)
	clock.advance(2.0)
	var act: Dictionary = ActionLibrary.get_action("sleep").duplicate(true)
	sim.command(act, node)
	var waited := 0
	while sim.state != 2 and waited < 240:
		clock.advance(2.0)
		waited += 1
	if sim.state != 2:
		return -3.0
	check(world.lot_item_in_use(uid), "postel, na které se spí, je „v užívání“")
	check(String(world.lot_apply_action("sell", [uid], "Test")["reason"]) == "in_use", "obsazenou postel nejde prodat")
	sim.needs.values["energy"] = 20.0
	var e0: float = float(sim.needs.values["energy"])
	clock.advance(60.0)
	var gain: float = float(sim.needs.values["energy"]) - e0
	sim.command({"id": "cancel"}, null)
	clock.advance(2.0)
	var sold: Dictionary = world.lot_apply_action("sell", [uid], "Test")
	check(bool(sold["ok"]) and world.lot_node(uid) == null and not world.smart_objects.has(node), "po vstání prodáno, uzel i chytrý objekt pryč", str(sold))
	return gain


# ---------------------------------------------------------------- integrace se světem

func _test_world_integration() -> void:
	section("Koupené předměty v herním světě")
	var world := _offline_world("IntegrationWorld")
	var base: int = world.smart_objects.size()
	var s := _spot(world.lot, "fridge_old", 0, -2.0, -1.0, 5.6, 4.2)
	var r: Dictionary = world.lot_apply_action("buy", ["fridge_old", s.x, s.y, 0], "Test")
	check(bool(r["ok"]), "lednice koupena", str(r))
	var node = world.lot_node(int(r["uid"]))
	check(world.smart_objects.size() == base + 1 and world.smart_objects[base] == node, "koupená lednice je chytrý objekt na konci seznamu")
	check(node.object_tag == "fridge" and is_equal_approx(node.quality, 0.85) and node.lot_uid == int(r["uid"]) and node.is_inside_tree(),
		"tag, kvalita a uid předmětu")
	var use: Vector3 = node.get_use_position(world.sims[0])
	var ac: Array = world.lot.access_points("fridge_old", s.x, s.y, 0)
	check(Vector2(use.x, use.z).distance_to(ac[0]) < 1e-4, "bod použití uzlu = přístupový bod v mřížce")
	var s2 := _spot(world.lot, "tv_flat", 2, -2.0, -1.0, 5.6, 4.2)
	var r2: Dictionary = world.lot_apply_action("buy", ["tv_flat", s2.x, s2.y, 2], "Test")
	check(bool(r2["ok"]) and world.smart_objects.size() == base + 2, "televize přidána", str(r2))
	world.lot_apply_action("sell", [int(r["uid"])], "Test")
	check(world.smart_objects.size() == base + 1 and world.smart_objects[base].object_tag == "tv", "po prodeji lednice se seznam srovná podle uid")
	# Hráčský příkaz na koupený objekt → ve frontě = v užívání.
	var sim = world.sims[0]
	var tv = world.lot_node(int(r2["uid"]))
	sim.player_queue.append({"action": ActionLibrary.get_action("watch_tv") if not ActionLibrary.get_action("watch_tv").is_empty() else {"id": "x"}, "target": tv})
	check(world.lot_item_in_use(int(r2["uid"])), "předmět ve frontě příkazů nejde prodat")
	sim.player_queue.clear()
	# Načtení světa bez sekce lot (starý save) = výchozí parcela.
	var res: Dictionary = world.lot_restore({})
	check(bool(res["ok"]) and world.lot.items.is_empty() and world.smart_objects.size() == base and world.lot.funds == LotGrid.START_FUNDS,
		"obnova bez sekce = výchozí parcela")
	world.free()


# ---------------------------------------------------------------- ukládání

func _test_save() -> void:
	section("Ukládání a načtení parcely")
	var world := _offline_world("SaveWorld")
	var lot = world.lot
	var ids := ["sofa_bazaar", "plant_monstera", "lamp_floor", "bench_garden", "rug_wool"]
	var regions := [[0.5, -1.0, 5.6, 4.2], [-5.5, -3.0, 5.6, 4.2], [-5.5, -3.0, 5.6, 4.2], [3.0, 6.0, 11.0, 11.0], [0.5, -3.5, 5.6, 0.5]]
	for i in ids.size():
		var rg: Array = regions[i]
		var sp := _spot(lot, ids[i], i % 4, rg[0], rg[1], rg[2], rg[3])
		var r: Dictionary = world.lot_apply_action("buy", [ids[i], sp.x, sp.y, i % 4], "Test")
		check(bool(r["ok"]), "koupeno %s" % ids[i], str(r))
	var snap := JSON.stringify(_strip_rev(lot.to_dict()))
	var tags_before: Array = []
	for o in world.smart_objects:
		tags_before.append(String(o.object_tag))
	var saved: Dictionary = world.save_game("manual")
	check(bool(saved.get("ok", false)), "uloženo", str(saved))
	# Změny po uložení.
	for uid in lot.sorted_uids():
		world.lot_apply_action("sell", [uid], "Test")
	check(lot.items.is_empty(), "po uložení vše prodáno")
	var loaded: Dictionary = world.load_game("manual")
	check(bool(loaded.get("ok", false)), "načteno", str(loaded))
	check(JSON.stringify(_strip_rev(world.lot.to_dict())) == snap, "parcela po načtení bit po bitu (bez revize)")
	var tags_after: Array = []
	for o in world.smart_objects:
		tags_after.append(String(o.object_tag))
	check(tags_after == tags_before, "chytré objekty po načtení ve stejném pořadí", "%s vs %s" % [str(tags_after), str(tags_before)])
	var nodes_ok := true
	for uid in world.lot.sorted_uids():
		var n: Node3D = world.lot_node(uid)
		if n == null or not n.is_inside_tree():
			nodes_ok = false
	check(nodes_ok, "uzly všech předmětů postaveny znovu")
	# Poškozená sekce → načtení selže a svět zůstane beze změny.
	var data: Dictionary = load("res://scripts/save/game_save.gd").capture(world)["data"]
	var bad := data.duplicate(true)
	bad["lot"]["items"].append({"uid": 1, "id": "plant_monstera", "cx": 1, "cz": 1, "rot": 0, "bought_at": 0.0, "paid": 0})
	var GS = load("res://scripts/save/game_save.gd")
	var v1: Dictionary = GS.validate_data(bad, world)
	check(not bool(v1["ok"]) and String(v1["reason"]) == "bad_lot", "duplicitní uid → bad_lot", str(v1))
	var bad2 := data.duplicate(true)
	bad2["lot"]["funds"] = -5
	check(String(GS.validate_data(bad2, world).get("reason", "")) == "bad_lot", "záporný rozpočet → bad_lot")
	var bad3 := data.duplicate(true)
	bad3["objects"].pop_back()
	check(String(GS.validate_data(bad3, world).get("reason", "")) == "changed_lot", "nesedí počet objektů → changed_lot")
	var before := JSON.stringify(_strip_rev(world.lot.to_dict()))
	var app: Dictionary = GS.apply(world, bad)
	check(not bool(app["ok"]) and JSON.stringify(_strip_rev(world.lot.to_dict())) == before, "neplatný save nic nezmění")
	# Starý save (bez sekce lot) – výchozí parcela.
	var old := data.duplicate(true)
	old.erase("lot")
	var objs: Array = old["objects"]
	objs.resize(world.lot_base_count)
	var ok_old: Dictionary = GS.apply(world, old)
	check(bool(ok_old["ok"]) and world.lot.items.is_empty() and world.smart_objects.size() == world.lot_base_count,
		"starý save bez parcely = výchozí dům", str(ok_old))
	# Předmět, který už v domě nejde umístit (přestavba), se vrátí za zaplacenou cenu.
	var moved := data.duplicate(true)
	var wall: Vector2i = world.lot.cell_of_world(Vector2(0.0, -4.6))
	var dec := {"uid": int(moved["lot"]["next_uid"]), "id": "plant_monstera", "cx": wall.x, "cz": wall.y - 1, "rot": 0, "bought_at": 0.0, "paid": 590}
	moved["lot"]["items"].append(dec)
	moved["lot"]["next_uid"] = int(moved["lot"]["next_uid"]) + 1
	var plan: Dictionary = world.lot.plan_restore(moved["lot"])
	check(bool(plan["ok"]) and int(plan["dropped"]) == 1 and int(plan["refund"]) == 590, "nevejde se → vyřazeno a vráceno 590 kr", str(plan))
	var greedy: Dictionary = moved["lot"].duplicate(true)
	greedy["items"][greedy["items"].size() - 1]["paid"] = 99999999
	var gplan: Dictionary = world.lot.plan_restore(greedy)
	check(int(gplan["refund"]) == 590, "upravený save s přemrštěnou cenou: vratka jen do katalogové ceny", str(gplan["refund"]))
	var ok_m: Dictionary = GS.apply(world, moved)
	check(bool(ok_m["ok"]) and world.lot.funds == int(moved["lot"]["funds"]) + 590, "obnova připsala vratku", str(ok_m))
	world.free()


static func _strip_rev(d: Dictionary) -> Dictionary:
	var c := d.duplicate(true)
	c.erase("revision")
	return c


# ---------------------------------------------------------------- fuzz snímků

func _test_snapshot_fuzz() -> void:
	section("Fuzz snímků parcely (save i síť)")
	var lot = LotGrid.new()
	lot.setup(Vector2(-6, -6), Vector2(6, 6))
	check(bool(lot.buy("trash_bags", 4, 4, 0, 0.0)["ok"]) and bool(lot.buy("plant_monstera", 30, 30, 1, 5.0)["ok"]), "fuzz: dvě položky")
	var good: Dictionary = lot.to_dict()
	check(LotGrid.validate_snapshot(good) == "", "platný snímek projde")
	var bads := [null, 5, "x", {}, {"version": 1}, {"version": 99, "funds": 1, "next_uid": 3, "items": []},
		{"version": 1, "funds": NAN, "next_uid": 3, "items": []}, {"version": 1, "funds": 1.5, "next_uid": 3, "items": []},
		{"version": 1, "funds": 1, "next_uid": 0, "items": []}, {"version": 1, "funds": 1, "next_uid": 3, "items": "x"}]
	var rejected := 0
	for b in bads:
		if LotGrid.validate_snapshot(b) != "":
			rejected += 1
	check(rejected == bads.size(), "rozbité kořeny odmítnuty (%d/%d)" % [rejected, bads.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var crashes := 0
	var accepted_valid := 0
	var weird_vals: Array = [null, -1, 0, 1, 2, 3, 4, 1.5, NAN, INF, "", "plant_monstera", "x".repeat(200), [], {}, 999999, -999999, 1e18, true]
	for i in 400:
		var d: Dictionary = good.duplicate(true)
		var k := rng.randi_range(0, 5)
		if k == 0:
			d[["version", "funds", "next_uid", "items", "ledger"][rng.randi_range(0, 4)]] = weird_vals[rng.randi_range(0, weird_vals.size() - 1)]
		elif k <= 3 and not (d["items"] as Array).is_empty():
			var it: Dictionary = d["items"][rng.randi_range(0, d["items"].size() - 1)]
			it[["uid", "id", "cx", "cz", "rot", "bought_at", "paid"][rng.randi_range(0, 6)]] = weird_vals[rng.randi_range(0, weird_vals.size() - 1)]
		elif k == 4:
			for j in rng.randi_range(60, 80):
				d["items"].append({"uid": 100 + j, "id": "plant_monstera", "cx": 0, "cz": 0, "rot": 0, "bought_at": 0.0, "paid": 0})
		else:
			d["ledger"] = [{"t": "x", "kind": 5}]
		var why := LotGrid.validate_snapshot(d)
		if why == "":
			var plan: Dictionary = lot.plan_restore(d)
			if not bool(plan["ok"]):
				crashes += 1
			else:
				accepted_valid += 1
				for rec in plan["kept"]:
					if lot.check(rec["id"], rec["cx"], rec["cz"], rec["rot"]) == "unknown_item":
						crashes += 1
	check(crashes == 0, "400 mutací: validace a plán obnovy se shodují, nic nespadne", "%d chyb, %d prošlo" % [crashes, accepted_valid])
	# Veřejný snímek (síť).
	var pub: Dictionary = lot.public_snapshot()
	var other = LotGrid.new()
	other.setup(Vector2(-6, -6), Vector2(6, 6))
	check(other.apply_public(pub) and other.items.size() == 2 and other.funds == lot.funds, "veřejný snímek se převezme")
	var bad_pubs := [{"v": 1, "rev": 1, "funds": 1, "items": [[1, "plant_monstera", 0, 0, 0]]},
		{"v": 1, "rev": 1, "funds": 1, "items": [[1, "hack", 0, 0, 0, 0.0, 0]]},
		{"v": 1, "rev": 1, "funds": 1, "items": [[1, "plant_monstera", 9999, 0, 0, 0.0, 0]]},
		{"v": 1, "rev": 1, "funds": 1, "items": [[1, "plant_monstera", 0, 0, 0, 0.0, 0], [1, "plant_monstera", 4, 0, 0, 0.0, 0]]},
		{"v": 1, "rev": 1, "funds": -1, "items": []}, {"v": 1, "rev": 1, "funds": 1, "items": [[1, "sofa_lagom", 47, 47, 0, 0.0, 0]]}]
	var rej := 0
	for b in bad_pubs:
		if not other.apply_public(b):
			rej += 1
	check(rej == bad_pubs.size() and other.items.size() == 2, "podvržené síťové snímky odmítnuty a stav zůstal", "%d/%d" % [rej, bad_pubs.size()])


# ---------------------------------------------------------------- multiplayer

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


func _tags(w: Node3D) -> Array:
	var out: Array = []
	for o in w.get_smart_objects():
		out.append(String(o.object_tag))
	return out


func _test_multiplayer() -> void:
	section("Multiplayer: autorita serveru a replikace parcely")
	clock.total_minutes = 600.0
	var server := _branch("LotServer", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false})
	check(server.net.mode == NetSession.Mode.DEDICATED, "dedikovaný server běží")
	var a := _client("LotClientA", "Kupec")
	var joined := await wait_until(func(): return a.net.my_sim != "", 6.0)
	check(joined, "klient přivítán s postavou")
	check(not bool(a.lot_apply_action("buy", ["plant_monstera", 60, 70, 0], "x")["ok"]), "klient sám parcelu nezmění (jen server)")
	var sp := _spot(server.lot, "plant_monstera", 0, 6.5, 6.0, 11.0, 11.0)
	a.request_lot_action("buy", ["plant_monstera", sp.x, sp.y, 0])
	check(await wait_until(func(): return server.lot.items.size() == 1, 3.0), "server provedl nákup klienta")
	check(await wait_until(func(): return a.lot.items.size() == 1 and a.lot.funds == server.lot.funds, 3.0), "klient dostal nový stav parcely",
		"%d %d" % [a.lot.items.size(), a.lot.funds])
	var fs := _spot(server.lot, "fridge_old", 0, -2.0, -1.0, 5.6, 4.2)
	a.request_lot_action("buy", ["fridge_old", fs.x, fs.y, 0])
	check(await wait_until(func(): return a.get_smart_objects().size() == server.get_smart_objects().size() and a.lot.items.size() == 2, 3.0),
		"lednice: stejný počet chytrých objektů na serveru i klientu")
	check(_tags(a) == _tags(server), "pořadí objektů (index v příkazech) sedí server ↔ klient")
	var uid: int = server.lot.sorted_uids()[1]
	var cn: Node3D = a.lot_node(uid)
	var sn: Node3D = server.lot_node(uid)
	check(cn != null and sn != null and cn.position.distance_to(sn.position) < 1e-4, "uzel na klientu stojí stejně jako na serveru")
	# Podvržené požadavky.
	var funds0: int = server.lot.funds
	var items0: int = server.lot.items.size()
	var rejected0: int = server.net.stats["rejected"]
	a.net._c2s_lot.rpc_id(1, "buy", ["plant_monstera", 1.5, 2, 0])
	a.net._c2s_lot.rpc_id(1, "steal", [1])
	a.net._c2s_lot.rpc_id(1, "buy", "x")
	a.net._c2s_lot.rpc_id(1, "sell", [1, 2, 3])
	a.net._c2s_lot.rpc_id(1, "buy", ["x".repeat(500), 1, 1, 0])
	a.net._c2s_lot.rpc_id(1, "move", [uid, 2, 2, 7])
	await wait_seconds(0.6)
	check(server.lot.funds == funds0 and server.lot.items.size() == items0, "podvržené požadavky nic nezměnily")
	check(int(server.net.stats["rejected"]) >= rejected0 + 4, "server je odmítl a počítá", "%d → %d" % [rejected0, int(server.net.stats["rejected"])])
	# Rate limit: 12 nákupů naráz – některé odmítnuty.
	await wait_seconds(4.5)
	notices["LotClientA"].clear()
	for i in 12:
		a.net._c2s_lot.rpc_id(1, "buy", ["trash_bags", 0, 0, 0])
	await wait_seconds(0.8)
	var slow := 0
	for t in notices["LotClientA"]:
		if String(t).find("Pomaleji") >= 0:
			slow += 1
	check(slow >= 6, "rate limit nákupů (%d odmítnuto)" % slow)
	# Pozdní připojení dostane aktuální parcelu.
	var b := _client("LotClientB", "Pozdní")
	check(await wait_until(func(): return b.net.my_sim != "" and b.lot.items.size() == server.lot.items.size(), 6.0),
		"pozdě připojený hráč dostane parcelu po vstupu", "%d vs %d" % [b.lot.items.size(), server.lot.items.size()])
	check(_tags(b) == _tags(server), "i pozdní klient má stejné pořadí objektů")
	# Prodej z klienta (rostlina – nikdo ji „nepoužívá“; počkat, až se doplní rate limit).
	await wait_seconds(3.0)
	uid = server.lot.sorted_uids()[0]
	a.request_lot_action("sell", [uid])
	check(await wait_until(func(): return not server.lot.items.has(uid) and not b.lot.items.has(uid) and b.lot_node(uid) == null, 3.0),
		"prodej z klienta A se projeví na serveru i u klienta B")
	# Server ukládá parcelu do svého světa (H4b formát).
	var cap: Dictionary = load("res://scripts/save/game_save.gd").capture(server, true)
	check(bool(cap.get("ok", false)) and cap["data"].has("lot") and (cap["data"]["lot"]["items"] as Array).size() == server.lot.items.size(),
		"snímek serverového světa obsahuje parcelu")
	for w in [a, b, server]:
		w.net.shutdown()
	await wait_seconds(0.3)
	for w in [a, b, server]:
		w.get_parent().queue_free()
	await wait_seconds(0.2)


# ---------------------------------------------------------------- UI režimu nákupu (headless kouřový test)

func _test_ui() -> void:
	section("UI režimu nákupu")
	clock.set_speed(2)
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "UiWorld"
	w.net_config = {"mode": "offline", "audio": false, "camera": true, "visuals": false, "hud": true,
		"autoload": false, "autosave": false, "save_directory": save_dir + "-ui", "clock": clock}
	add_child(w)
	await get_tree().process_frame
	clock.set_speed(2)
	w.toggle_buy_mode()
	check(w.buy_mode != null and is_instance_valid(w.buy_mode), "klávesa B otevře režim nákupu")
	check(clock.speed_index == 0, "offline se při zařizování čas zastaví")
	var bm = w.buy_mode
	bm.set_process(false)
	await get_tree().process_frame
	check(bm.get_node("BuyPanel") != null and String(bm._funds.text).find("15 000 kr") >= 0, "panel ukazuje rozpočet", String(bm._funds.text))
	bm._select_category("decor")
	await get_tree().process_frame
	check(bm._list.get_child_count() >= 3, "kategorie Dekorace má položky")
	bm.pick_item("plant_monstera")
	bm.anchor = _spot(w.lot, "plant_monstera", 0, 6.5, 6.0, 11.0, 11.0)
	bm.rot = 0
	bm.update_ghost()
	check(bm.last_reason == "" and bm._ghost.visible, "duch na volném místě je zelený")
	bm.place_ghost()
	check(w.lot.items.size() == 1 and w.lot.funds == 15000 - 590, "postavení z UI = nákup přes autoritu")
	bm.update_ghost()
	check(bm.last_reason == "overlap" and String(bm._status.text) != "", "na stejném místě je duch červený s důvodem", bm.last_reason)
	bm.selected_id = ""
	bm.selected_uid = w.lot.sorted_uids()[0]
	bm._refresh()
	check(bm._sel_box.visible and String(bm._sel_label.text).find("590 kr") >= 0, "vybraný předmět ukazuje výkupní cenu", String(bm._sel_label.text))
	bm.start_move()
	bm.anchor = bm.anchor + Vector2i(2, 0)
	bm.place_ghost()
	check(int(w.lot.items[bm.selected_uid]["cx"]) == bm.anchor.x, "přesun z UI")
	bm.sell_selected()
	check(w.lot.items.is_empty() and w.lot.funds == 15000, "prodej z UI vrátil peníze")
	bm.close()
	await get_tree().process_frame
	check(w.buy_mode == null and clock.speed_index == 2, "zavření vrátí rychlost času")
	w.queue_free()
	await get_tree().process_frame
