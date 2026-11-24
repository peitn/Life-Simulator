extends RefCounted
## Mřížka parcely a režim nákupu (B1, 20. 11. 2026) – ČISTÁ DATA, žádné uzly.
##
## Jediný zdroj pravdy o tom, co si domácnost koupila a kam to postavila, a o rodinném rozpočtu.
## Uzly (SmartObject) z toho staví LotFurnisher; svět (main.gd) jen volá buy/sell/move a přestaví uzly.
## V multiplayeru běží změny VÝHRADNĚ na autoritě (server/offline); klienti dostanou veřejný snímek.
##
## Mřížka: buňka CELL = 0,25 m nad obdélníkem parcely (x, z ve světě). Vrstvy buněk:
##   _static  – stěny, dveřní koridory, kuchyňská linka, stůl, kmeny stromů, chodník, nestavitelné zóny (1 = blokováno)
##   _solid   – pevné předměty: 0 volno, -1 výchozí nábytek domu, >0 uid koupené položky
##   _clear   – přístupové zóny (kam postava dojde, aby předmět použila): 0 volno, -1 výchozí nábytek, >0 uid
##   _floor   – koberce (vrstva pod nábytkem): 0 volno, >0 uid
##   _inside  – 1 = buňka uvnitř domu (požadavek "indoor"/"outdoor" katalogu)
## Pravidla umístění (check):
##   * celý půdorys v parcele, žádná statická buňka;
##   * pevná položka nesmí překrýt jiný pevný předmět ani cizí přístupovou zónu (nezatarasíš lednici);
##   * její vlastní body použití musí být v parcele a volné (ne stěna, ne jiný předmět);
##   * koberec koliduje jen s jinými koberci a statickými buňkami;
##   * "indoor" = celý půdorys uvnitř, "outdoor" = celý venku.
## Peníze: celé koruny (int), nikdy záporné – na dluh se zatím nekupuje (úvěry přijdou s ekonomikou).
## Prodej: do 24 herních hodin od nákupu plná cena (spletl ses), potom 55 % klesající lineárně na 30 % za 180 dní.
##
## STĚNY (B2, 22. 11. 2026, formát v2): stěna = úsečka po HRANÁCH buněk, koncové body jsou celočíselné
## mřížkové body 0..gw × 0..gh (krok CELL). Stěny nevyplňují buňky – kolize s předměty se počítají
## geometricky vůči hraně. Pravidla (check_wall):
##   * osově zarovnaná, délka WALL_MIN_CELLS..WALL_MAX_CELLS, uvnitř parcely, nejvýš MAX_WALLS stěn;
##   * žádný překryv, duplicita ani křížení s jinou stěnou (T-spoj a roh jsou v pořádku) – build_wall_validation.gd;
##   * neprochází statickým prostředím (zeď domu, dveřní koridor, chodník – obě sousední buňky statické);
##   * neprochází předmětem (výchozí nábytek, koupená věc i koberec mají buňky po obou stranách hrany);
##   * nepřetne přístup k předmětu: úsečku střed → bod použití ani přístupovou zónu 0,5 × 0,5 m;
##   * NEODŘÍZNE cestu: každý bod použití, kam se dalo dojít od okraje parcely (ulice), musí zůstat
##     dosažitelný (BFS po buňkách; průchozí = volné buňky a "keepout" koridory/chodník, stěny blokují hrany).
## Předměty naopak nesmí stát přes stěnu ("blocked") a jejich přístup nesmí vést skrz ni ("access_blocked").
## Cena WALL_PRICE_PER_CELL za 0,25 m; zbourání do 24 h plná vratka (omyl), potom nic – materiál je odpad.
## B3 (22. 11. 2026): postavy obcházejí postavené stěny (scripts/world/lot_nav.gd). Nákup a přesun předmětu proto
## ověřují i CESTU (reach_check): nový předmět musí být dosažitelný od ulice ("access_unreachable") a nesmí
## odříznout bod použití, kam se dosud dalo dojít ("blocks_path"). Stavba zdi nesmí zazdít postavu
## (wall_traps → "traps_sim", volá main.lot_apply_action s polohami postav).
##
## DVEŘE A OKNA (B4, 23. 11. 2026, formát v3): otvor = atribut stěny {oid, wid, kind, at, built_at, paid};
## at = posun v buňkách od normalizovaného začátku stěny (x0, z0), šířka podle druhu (OPENINGS). Pravidla (check_opening):
##   * stěna existuje; nejméně OPENING_EDGE buňka plné zdi od obou konců (ostění), mezi otvory OPENING_GAP;
##   * v rozsahu otvoru se do stěny nenapojuje jiná stěna (T-spoj/roh) – a nová stěna se nesmí napojit do otvoru;
##   * dveře nesmí vést do nábytku, zdi domu ani jiné statické překážky (DOOR_DEPTH buněk na obě strany);
##   * nejvýš MAX_OPENINGS otvorů na parcelu.
## Dveře jsou PRŮCHOZÍ: hrany v jejich rozsahu se v BFS/pathfinderu neblokují a LotNav pracuje s plnými úseky
## stěny (wall_segments). Okna průchozí nejsou, dávají atmosféru (světlo, výhled). Pevný předmět nesmí stát
## v prostoru dveří ("blocks_door"; koberec smí). Vybourání dveří = jako stavba stěny: nesmí odříznout cestu
## (door_close_seals → "seals_off") ani zazdít postavu (opening_traps → "traps_sim", volá main). Zbourání stěny
## odstraní i její otvory (vratky podle stejného pravidla 24 h). Uzavřenou místnost lze postavit tak, že se dveře
## osadí dřív, než poslední stěna místnost uzavře.

const Catalog := preload("res://scripts/world/buy_catalog.gd")
const WallGeometry := preload("res://scripts/world/build_wall_validation.gd")

const VERSION := 4
const MAX_WALLS := 128
const WALL_MIN_CELLS := 2
const WALL_MAX_CELLS := 80
const WALL_PRICE_PER_CELL := 60
## Jen vizuál (uzly staví main.gd); pravidla pracují s nulovou tloušťkou hrany.
const WALL_THICK := 0.12
const WALL_HEIGHT := 2.7
## Úsečka přístupu musí být od stěny aspoň takhle daleko, jinak by postava stála ve zdi.
const WALL_CLEAR := 0.02
## Otvory ve stěnách (B4): šířka v buňkách, cena, průchozí, parapet a nadpraží (vizuál, m), atmosféra.
const OPENINGS := {
	"door": {"name": "Dveře", "cells": 4, "price": 420, "pass": true, "sill": 0.0, "head": 2.05, "appeal": 0.0},
	"window": {"name": "Okno", "cells": 4, "price": 360, "pass": false, "sill": 0.9, "head": 2.1, "appeal": 1.5},
	"window_wide": {"name": "Široké okno", "cells": 6, "price": 540, "pass": false, "sill": 0.6, "head": 2.2, "appeal": 2.5},
}
const OPENING_ORDER := ["door", "window", "window_wide"]
const MAX_OPENINGS := 64
## B4b (24. 11. 2026): zámky dveří (formát v4). "" = odemčeno, LOCK_ALL = neprojde nikdo, jinak klíč =
## jméno uzlu postavy → projde jen ona („zamkla se v koupelně“). Zamčené dveře jsou pro ostatní zeď.
const LOCK_ALL := "*"
const LOCK_MAX_LEN := 64
const MAX_LOCKED := 16
## Plná zeď od konce stěny k otvoru a mezi dvěma otvory (buňky).
const OPENING_EDGE := 1
const OPENING_GAP := 1
## Prostor dveří: kolik buněk na každou stranu musí zůstat bez pevného nábytku a statických překážek.
const DOOR_DEPTH := 2
const CELL := 0.25
const MAX_ITEMS := 64
const START_FUNDS := 15000
const MAX_FUNDS := 100000000
const LEDGER_MAX := 64
const MAX_GRID_CELLS := 40000
const REFUND_FULL_MINUTES := 1440.0
const RESALE_START := 0.55
const RESALE_FLOOR := 0.30
const RESALE_DECAY_DAYS := 180.0
## Přístupová zóna = čtverec 0,5 × 0,5 m kolem bodu použití.
const ACCESS_HALF := 0.25
## Atmosféra: plný vliv do 2 m, lineárně slábne do 5 m; součet je oříznutý na ±10.
const APPEAL_NEAR := 2.0
const APPEAL_FAR := 5.0
const APPEAL_CAP := 10.0

## Kódy důvodů – UI je překládá přes REASON_TEXT.
const REASON_TEXT := {
	"unknown_item": "Tohle se neprodává.",
	"bad_rotation": "Neplatné otočení.",
	"out_of_bounds": "Mimo parcelu.",
	"blocked": "Tady stojí zeď, dveře nebo cesta.",
	"overlap": "Překáží jiný předmět.",
	"blocks_access": "Zatarasilo by to přístup k jinému předmětu.",
	"access_blocked": "K předmětu by se nedalo dojít.",
	"indoor_only": "Tohle patří dovnitř.",
	"outdoor_only": "Tohle patří ven.",
	"funds": "Na to nemáte peníze.",
	"limit": "Parcela je plná (limit předmětů).",
	"unknown_uid": "Ten předmět už neexistuje.",
	"in_use": "Někdo ho právě používá.",
	"not_authority": "Nakupovat smí jen server.",
	"wall_bad": "Zeď musí vést rovně po mřížce.",
	"wall_short": "Zeď je moc krátká (nejméně 0,5 m).",
	"wall_long": "Jeden úsek zdi může mít nejvýš 20 m.",
	"wall_overlap": "Tady už zeď stojí.",
	"wall_crossing": "Zdi se nesmí křížit – napoj je do rohu nebo do T.",
	"wall_limit": "Na parcele je už moc zdí.",
	"unknown_wid": "Ta zeď už neexistuje.",
	"seals_off": "Zeď by odřízla cestu ke dveřím nebo k věcem.",
	"access_unreachable": "K předmětu by se nedalo dojít z ulice.",
	"blocks_path": "Zatarasilo by to cestu ke dveřím nebo k věcem.",
	"traps_sim": "Zeď by někoho zazdila.",
	"opening_bad": "Neplatné dveře nebo okno.",
	"opening_edge": "Otvor potřebuje kus zdi po obou stranách (aspoň 0,25 m).",
	"opening_overlap": "Otvory jsou moc blízko u sebe.",
	"opening_junction": "Tady se do zdi napojuje jiná zeď.",
	"opening_limit": "Na parcele je už moc dveří a oken.",
	"door_blocked": "Dveře by vedly do nábytku nebo do zdi.",
	"blocks_door": "Zatarasilo by to dveře.",
	"unknown_oid": "Ty dveře nebo okno už neexistují.",
	"wall_at_opening": "Zeď nejde napojit do dveří nebo okna.",
	"door_traps": "Bez těch dveří by někdo zůstal zavřený.",
	"not_door": "Zamknout jdou jen dveře.",
	"lock_bad": "Neplatný zámek.",
	"lock_same": "Dveře už jsou takhle zamčené.",
	"lock_limit": "Zamčených dveří je na parcele moc.",
	"lock_seals": "Zamčením pro všechny by se k některým věcem nedalo dojít.",
	"lock_traps": "Zamčením by někdo zůstal zavřený.",
	"lock_not_yours": "Tyhle dveře zamkl někdo jiný – klíč nemáš.",
	"lock_who": "Pro tuhle postavu zamknout nemůžeš.",
}

var origin := Vector2.ZERO
var gw := 0
var gh := 0
var _static := PackedByteArray()
var _inside := PackedByteArray()
var _solid := PackedInt32Array()
var _clear := PackedInt32Array()
var _floor := PackedInt32Array()
## Průchozí statické buňky (dveřní koridory, chodník): nestavitelné, ale chodí se tudy (BFS dosažitelnosti).
var _keepout := PackedByteArray()
## Předměty, do kterých se vstupuje (bod použití uvnitř půdorysu: sprcha, běžecký pás) – pro BFS průchozí.
var _enter := PackedByteArray()
## Prostor dveří (B4): 1 = buňka, kde nesmí stát pevný předmět.
var _door_side := PackedByteArray()
## Hrany zablokované stěnami: _hedge[z * gw + x] = vodorovná hrana na mřížkové přímce z nad buňkou (x, z);
## _vedge[z * (gw + 1) + x] = svislá hrana na přímce x vlevo od buňky (x, z).
var _hedge := PackedByteArray()
var _vedge := PackedByteArray()
var keepout_rects: Array = []
var _layout_serial := 0
var _reach_key := ""
var _reach_cache := PackedByteArray()
## Popis pevného prostředí (nemění se uložením, staví ho WorldBuilder): seznamy obdélníků ve světě.
var static_rects: Array = []
var interior_rects: Array = []
## Výchozí nábytek: [{"name", "rect": Rect2, "access": [Vector2]}]
var fixed: Array = []

## uid -> {"uid", "id", "cx", "cz", "rot", "bought_at", "paid"}
var items: Dictionary = {}
var next_uid := 1
var funds := START_FUNDS
## wid -> {"wid", "x0", "z0", "x1", "z1", "built_at", "paid"}; (x0, z0) ≤ (x1, z1) po normalizaci.
var walls: Dictionary = {}
var next_wid := 1
## oid -> {"oid", "wid", "kind", "at", "built_at", "paid"} (B4).
var openings: Dictionary = {}
var next_oid := 1
## Cache plných úseků stěn pro LotNav (klíč = revize + rozložení).
var _seg_key := ""
var _seg_cache: Dictionary = {}
## B4b: z čího pohledu se počítá průchodnost dveří. "" = bez zámků (stavění, kontroly cest k věcem),
## jinak klíč postavy (SimAgent ho nastaví jen na dobu výpočtu své trasy). _nav_unlock = dveře, jejichž zámek
## se dočasně ignoruje (LotNav.lock_blocker zjišťuje, čí zámek cestu zavřel).
var nav_viewer := ""
var _nav_unlock := 0
var _reach_views: Dictionary = {}
var _vk_in := ""
var _vk_out := ""
## Posledních LEDGER_MAX transakcí: {"t", "kind", "id", "amount", "by"}
var ledger: Array = []
## Roste s každou změnou (síťová synchronizace, testy).
var revision := 0


# ---------------------------------------------------------------- stavba pevného prostředí

func setup(min_xz: Vector2, max_xz: Vector2) -> void:
	origin = min_xz
	gw = maxi(1, int(ceil((max_xz.x - min_xz.x) / CELL - 1e-6)))
	gh = maxi(1, int(ceil((max_xz.y - min_xz.y) / CELL - 1e-6)))
	if gw * gh > MAX_GRID_CELLS:
		push_error("LotGrid: parcela je příliš velká")
		gw = 1
		gh = 1
	static_rects.clear()
	interior_rects.clear()
	keepout_rects.clear()
	fixed.clear()
	rebuild()


func add_static_rect(r: Rect2) -> void:
	static_rects.append(r.abs())


## Nestavitelná, ale průchozí plocha (dveřní koridor, chodník k ulici). Zároveň statická.
func add_keepout_rect(r: Rect2) -> void:
	static_rects.append(r.abs())
	keepout_rects.append(r.abs())


func add_interior_rect(r: Rect2) -> void:
	interior_rects.append(r.abs())


## Výchozí nábytek domu: center = střed ve světě (x, z), w × d v metrech, yaw ve stupních (násobek 90),
## access = body použití ve světě (x, z).
func add_fixed(fixed_name: String, center: Vector2, w: float, d: float, yaw_deg: float, access: Array) -> void:
	var q := int(roundf(yaw_deg / 90.0)) & 3
	var sz := Vector2(w, d) if q % 2 == 0 else Vector2(d, w)
	fixed.append({"name": fixed_name, "rect": Rect2(center - sz * 0.5, sz), "access": access.duplicate()})


## Buňky, jejichž čtverec se s obdélníkem překrývá víc než o 1 mm (dotyk hranou se nepočítá).
func _cells_of_rect(r: Rect2) -> Rect2i:
	var a := (r.position - origin) / CELL
	var b := (r.end - origin) / CELL
	var x0 := int(floor(a.x + 0.004))
	var z0 := int(floor(a.y + 0.004))
	var x1 := int(ceil(b.x - 0.004))
	var z1 := int(ceil(b.y - 0.004))
	return Rect2i(x0, z0, maxi(x1 - x0, 0), maxi(z1 - z0, 0))


func _in_grid(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < gw and cz < gh


func _idx(cx: int, cz: int) -> int:
	return cz * gw + cx


## Přepočítá všechny vrstvy z popisu prostředí a položek (deterministické, pořadí uid vzestupně).
func rebuild() -> void:
	var n := gw * gh
	_static = PackedByteArray()
	_static.resize(n)
	_static.fill(0)
	_inside = PackedByteArray()
	_inside.resize(n)
	_inside.fill(0)
	_solid = PackedInt32Array()
	_solid.resize(n)
	_solid.fill(0)
	_clear = PackedInt32Array()
	_clear.resize(n)
	_clear.fill(0)
	_floor = PackedInt32Array()
	_floor.resize(n)
	_floor.fill(0)
	_keepout = PackedByteArray()
	_keepout.resize(n)
	_keepout.fill(0)
	_enter = PackedByteArray()
	_enter.resize(n)
	_enter.fill(0)
	_door_side = PackedByteArray()
	_door_side.resize(n)
	_door_side.fill(0)
	_layout_serial += 1
	for r in keepout_rects:
		_fill_bytes(_keepout, _cells_of_rect(r), 1)
	for r in interior_rects:
		_fill_bytes(_inside, _cells_of_rect(r), 1)
	for r in static_rects:
		_fill_bytes(_static, _cells_of_rect(r), 1)
	for f in fixed:
		_fill_ints(_solid, _cells_of_rect(f["rect"]), -1)
		for p in f["access"]:
			_fill_ints(_clear, _access_cells(p), -1)
			if (f["rect"] as Rect2).has_point(p):
				_fill_bytes(_enter, _cells_of_rect(f["rect"]), 1)
	var uids := items.keys()
	uids.sort()
	for uid in uids:
		_stamp(items[uid])
	_stamp_doors()


func _fill_bytes(arr: PackedByteArray, cells: Rect2i, v: int) -> void:
	for cz in range(maxi(cells.position.y, 0), mini(cells.end.y, gh)):
		for cx in range(maxi(cells.position.x, 0), mini(cells.end.x, gw)):
			arr[_idx(cx, cz)] = v


func _fill_ints(arr: PackedInt32Array, cells: Rect2i, v: int) -> void:
	for cz in range(maxi(cells.position.y, 0), mini(cells.end.y, gh)):
		for cx in range(maxi(cells.position.x, 0), mini(cells.end.x, gw)):
			arr[_idx(cx, cz)] = v


func _access_cells(p: Vector2) -> Rect2i:
	return _cells_of_rect(Rect2(p - Vector2(ACCESS_HALF, ACCESS_HALF), Vector2(ACCESS_HALF, ACCESS_HALF) * 2.0))


func _stamp(it: Dictionary) -> void:
	var id: String = it["id"]
	var uid: int = int(it["uid"])
	var fp := footprint(id, int(it["cx"]), int(it["cz"]), int(it["rot"]))
	if Catalog.layer(id) == "floor":
		_fill_ints(_floor, fp, uid)
		return
	_fill_ints(_solid, fp, uid)
	var own := Rect2(origin + Vector2(fp.position) * CELL, Vector2(fp.size) * CELL)
	for p in access_points(id, int(it["cx"]), int(it["cz"]), int(it["rot"])):
		if own.has_point(p):
			_fill_bytes(_enter, fp, 1)
		var cells := _access_cells(p)
		for cz in range(maxi(cells.position.y, 0), mini(cells.end.y, gh)):
			for cx in range(maxi(cells.position.x, 0), mini(cells.end.x, gw)):
				if _clear[_idx(cx, cz)] == 0:
					_clear[_idx(cx, cz)] = uid


# ---------------------------------------------------------------- geometrie položek

## Rozměry půdorysu v buňkách (otočení 1 a 3 prohodí šířku a hloubku).
func dims(id: String, rot: int) -> Vector2i:
	var it := Catalog.get_item(id)
	var w := int(roundf(float(it.get("w", CELL)) / CELL))
	var d := int(roundf(float(it.get("d", CELL)) / CELL))
	return Vector2i(w, d) if rot % 2 == 0 else Vector2i(d, w)


## Půdorys v buňkách; (cx, cz) = buňka levého horního (min x, min z) rohu.
func footprint(id: String, cx: int, cz: int, rot: int) -> Rect2i:
	return Rect2i(Vector2i(cx, cz), dims(id, rot))


func center_of(id: String, cx: int, cz: int, rot: int) -> Vector2:
	var dd := dims(id, rot)
	return origin + (Vector2(cx, cz) + Vector2(dd) * 0.5) * CELL


static func yaw_deg(rot: int) -> float:
	return float(rot & 3) * 90.0


## Lokální bod [x, z] položky (předek = +Z) → svět (x, z). Odpovídá Node3D.rotation_degrees.y = yaw_deg(rot).
static func local_to_world(center: Vector2, rot: int, lx: float, lz: float) -> Vector2:
	var th := deg_to_rad(yaw_deg(rot))
	return center + Vector2(lx * cos(th) + lz * sin(th), -lx * sin(th) + lz * cos(th))


func access_points(id: String, cx: int, cz: int, rot: int) -> Array:
	var out: Array = []
	var c := center_of(id, cx, cz, rot)
	for u in Catalog.get_item(id).get("use", []):
		out.append(local_to_world(c, rot, float(u[0]), float(u[1])))
	return out


## Kotva (cx, cz) tak, aby střed půdorysu byl co nejblíž bodu ve světě (pro ducha pod myší).
func snap_anchor(id: String, world_xz: Vector2, rot: int) -> Vector2i:
	var dd := dims(id, rot)
	var g := (world_xz - origin) / CELL - Vector2(dd) * 0.5
	return Vector2i(int(roundf(g.x)), int(roundf(g.y)))


func cell_of_world(p: Vector2) -> Vector2i:
	var g := (p - origin) / CELL
	return Vector2i(int(floor(g.x)), int(floor(g.y)))


func world_rect() -> Rect2:
	return Rect2(origin, Vector2(gw, gh) * CELL)


func is_inside_cell(cx: int, cz: int) -> bool:
	return _in_grid(cx, cz) and _inside[_idx(cx, cz)] == 1


# ---------------------------------------------------------------- pravidla

static func _valid_rot(rot: Variant) -> bool:
	return typeof(rot) == TYPE_INT and int(rot) >= 0 and int(rot) <= 3


## "" = lze umístit; jinak kód důvodu (REASON_TEXT). ignore_uid = přesouvaná položka.
func check(id: Variant, cx: Variant, cz: Variant, rot: Variant, ignore_uid: int = 0) -> String:
	if not Catalog.has(id):
		return "unknown_item"
	if not _valid_rot(rot):
		return "bad_rotation"
	if typeof(cx) != TYPE_INT or typeof(cz) != TYPE_INT:
		return "out_of_bounds"
	var sid := String(id)
	var it := Catalog.get_item(sid)
	var fp := footprint(sid, int(cx), int(cz), int(rot))
	if fp.position.x < 0 or fp.position.y < 0 or fp.end.x > gw or fp.end.y > gh:
		return "out_of_bounds"
	if _rect_cut_by_wall(fp, 0):
		return "blocked"
	var is_floor := Catalog.layer(sid) == "floor"
	var all_in := true
	var all_out := true
	for z in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			var i := _idx(x, z)
			if _static[i] == 1:
				return "blocked"
			if _inside[i] == 1:
				all_out = false
			else:
				all_in = false
			if is_floor:
				if _floor[i] != 0 and _floor[i] != ignore_uid:
					return "overlap"
				continue
			if _solid[i] != 0 and _solid[i] != ignore_uid:
				return "overlap"
			if _clear[i] != 0 and _clear[i] != ignore_uid:
				return "blocks_access"
			if _door_side[i] == 1:
				return "blocks_door"
	var place := String(it["place"])
	if place == "indoor" and not all_in:
		return "indoor_only"
	if place == "outdoor" and not all_out:
		return "outdoor_only"
	if not is_floor:
		var own := Rect2(origin + Vector2(fp.position) * CELL, Vector2(fp.size) * CELL)
		for p in access_points(sid, int(cx), int(cz), int(rot)):
			# Bod uvnitř vlastního půdorysu (sprcha, běžecký pás) = postava stojí v předmětu.
			if own.has_point(p):
				continue
			# Přístup nesmí vést skrz zeď (gauč čelem do zdi má „sedák“ venku za zdí).
			if _segment_hits_static(own.get_center(), p, own):
				return "access_blocked"
			# … ani skrz postavenou stěnu, a postava nesmí stát ve zdi.
			for wid in walls:
				if _wall_cuts_access(walls[wid], own.get_center(), p):
					return "access_blocked"
			var cells := _access_cells(p)
			for z in range(cells.position.y, cells.end.y):
				for x in range(cells.position.x, cells.end.x):
					if not _in_grid(x, z):
						return "access_blocked"
					var i := _idx(x, z)
					if _static[i] == 1:
						return "access_blocked"
					if _solid[i] != 0 and _solid[i] != ignore_uid:
						return "access_blocked"
					if fp.has_point(Vector2i(x, z)):
						return "access_blocked"
	return ""


## Úsečka od středu předmětu k bodu použití (vzorky po čtvrt buňky mimo vlastní půdorys) narazí na statickou buňku?
func _segment_hits_static(a: Vector2, b: Vector2, own: Rect2) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / (CELL * 0.25))))
	for i in range(1, steps + 1):
		var q := a.lerp(b, float(i) / float(steps))
		if own.has_point(q):
			continue
		var c := cell_of_world(q)
		if not _in_grid(c.x, c.y) or _static[_idx(c.x, c.y)] == 1:
			return true
	return false


# ---------------------------------------------------------------- transakce (jen autorita)

func buy(id: Variant, cx: Variant, cz: Variant, rot: Variant, now: float, actor: String = "") -> Dictionary:
	if items.size() >= MAX_ITEMS:
		return {"ok": false, "reason": "limit"}
	var why := check(id, cx, cz, rot)
	if why != "":
		return {"ok": false, "reason": why}
	var sid := String(id)
	var price := int(Catalog.get_item(sid)["price"])
	if price > funds:
		return {"ok": false, "reason": "funds"}
	why = reach_check(sid, int(cx), int(cz), int(rot), 0)
	if why != "":
		return {"ok": false, "reason": why}
	var uid := next_uid
	next_uid += 1
	var it := {"uid": uid, "id": sid, "cx": int(cx), "cz": int(cz), "rot": int(rot),
		"bought_at": _finite_time(now), "paid": price}
	items[uid] = it
	funds -= price
	_stamp(it)
	_log(now, "buy", sid, -price, actor)
	revision += 1
	return {"ok": true, "reason": "", "uid": uid, "price": price}


func sell_value(uid: int, now: float) -> int:
	if not items.has(uid):
		return 0
	var it: Dictionary = items[uid]
	var paid := int(it["paid"])
	var age := _finite_time(now) - float(it["bought_at"])
	if age >= 0.0 and age <= REFUND_FULL_MINUTES:
		return paid
	# Hodiny šly dozadu (rewind) → bezpečně počítat jako starou věc, ne jako plnou vratku.
	var days := maxf(age, REFUND_FULL_MINUTES) / 1440.0
	var k := lerpf(RESALE_START, RESALE_FLOOR, clampf(days / RESALE_DECAY_DAYS, 0.0, 1.0))
	return int(floor(float(paid) * k))


func sell(uid: Variant, now: float, actor: String = "") -> Dictionary:
	if typeof(uid) != TYPE_INT or not items.has(int(uid)):
		return {"ok": false, "reason": "unknown_uid"}
	var refund := sell_value(int(uid), now)
	var it: Dictionary = items[int(uid)]
	items.erase(int(uid))
	funds = mini(funds + refund, MAX_FUNDS)
	rebuild()
	_log(now, "sell", String(it["id"]), refund, actor)
	revision += 1
	return {"ok": true, "reason": "", "refund": refund, "id": String(it["id"])}


func move(uid: Variant, cx: Variant, cz: Variant, rot: Variant, now: float, actor: String = "") -> Dictionary:
	if typeof(uid) != TYPE_INT or not items.has(int(uid)):
		return {"ok": false, "reason": "unknown_uid"}
	var it: Dictionary = items[int(uid)]
	var why := check(it["id"], cx, cz, rot, int(uid))
	if why != "":
		return {"ok": false, "reason": why}
	why = reach_check(String(it["id"]), int(cx), int(cz), int(rot), int(uid))
	if why != "":
		return {"ok": false, "reason": why}
	it["cx"] = int(cx)
	it["cz"] = int(cz)
	it["rot"] = int(rot)
	rebuild()
	_log(now, "move", String(it["id"]), 0, actor)
	revision += 1
	return {"ok": true, "reason": ""}


## Přičte/odečte peníze (výplata, pokuta…); nikdy pod nulu. Vrací skutečnou změnu.
func adjust_funds(amount: int, now: float, kind: String, actor: String = "") -> int:
	var before := funds
	funds = clampi(funds + amount, 0, MAX_FUNDS)
	if funds != before:
		_log(now, kind, "", funds - before, actor)
		revision += 1
	return funds - before


func _log(now: float, kind: String, id: String, amount: int, actor: String) -> void:
	# Délky odpovídají validate_snapshot – jinak by vlastní save neprošel kontrolou.
	ledger.append({"t": _finite_time(now), "kind": kind.substr(0, 16), "id": id.substr(0, 48),
		"amount": clampi(amount, -MAX_FUNDS, MAX_FUNDS), "by": actor.substr(0, 40)})
	while ledger.size() > LEDGER_MAX:
		ledger.pop_front()


static func _finite_time(t: float) -> float:
	return t if is_finite(t) else 0.0


# ---------------------------------------------------------------- stěny (B2, jen autorita mění)

## Normalizace koncových bodů: menší bod první (pro vodorovnou podle x, svislou podle z).
static func _norm4(x0: int, z0: int, x1: int, z1: int) -> Array:
	if x1 < x0 or (x1 == x0 and z1 < z0):
		return [x1, z1, x0, z0]
	return [x0, z0, x1, z1]


## Délka v buňkách (pro osově zarovnanou stěnu; jinak součet, který kontrola stejně odmítne).
static func _wall_len(x0: int, z0: int, x1: int, z1: int) -> int:
	return absi(x1 - x0) + absi(z1 - z0)


static func wall_price(x0: int, z0: int, x1: int, z1: int) -> int:
	return _wall_len(x0, z0, x1, z1) * WALL_PRICE_PER_CELL


static func _wall_record(w: Dictionary) -> Dictionary:
	return {"wid": int(w["wid"]), "x0": int(w["x0"]), "z0": int(w["z0"]), "x1": int(w["x1"]), "z1": int(w["z1"]),
		"built_at": float(w["built_at"]), "paid": int(w["paid"])}


func sorted_wids() -> Array:
	var u := walls.keys()
	u.sort()
	return u


## Koncové body stěny ve světě (x, z).
func wall_world(w: Dictionary) -> Array:
	return [origin + Vector2(int(w["x0"]), int(w["z0"])) * CELL, origin + Vector2(int(w["x1"]), int(w["z1"])) * CELL]


## Nejbližší mřížkový bod (průsečík hran) k bodu ve světě – přichytávání nástroje Zeď.
func snap_lattice(p: Vector2) -> Vector2i:
	var g := (p - origin) / CELL
	return Vector2i(clampi(int(roundf(g.x)), 0, gw), clampi(int(roundf(g.y)), 0, gh))


## Protíná stěna vnitřek obdélníku buněk? (Hrana na okraji obdélníku ho neprotíná.)
func _wall_cuts_cells(w: Dictionary, r: Rect2i) -> bool:
	var x0 := int(w["x0"])
	var z0 := int(w["z0"])
	var x1 := int(w["x1"])
	var z1 := int(w["z1"])
	if z0 == z1:
		return r.position.y < z0 and z0 < r.end.y and maxi(x0, r.position.x) < mini(x1, r.end.x)
	return r.position.x < x0 and x0 < r.end.x and maxi(z0, r.position.y) < mini(z1, r.end.y)


func _rect_cut_by_wall(r: Rect2i, ignore_wid: int) -> bool:
	for wid in walls:
		if int(wid) != ignore_wid and _wall_cuts_cells(walls[wid], r):
			return true
	return false


## Přetíná stěna přístup k předmětu? Úsečka c → p (střed předmětu → bod použití) ji protne, nebo stěna
## vede přístupovou zónou bodu p (postava by stála ve zdi).
func _wall_cuts_access(w: Dictionary, c: Vector2, p: Vector2) -> bool:
	var ab := wall_world(w)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	if a.y == b.y:
		var lo := minf(c.y, p.y)
		var hi := maxf(c.y, p.y)
		if lo < a.y - WALL_CLEAR and hi > a.y + WALL_CLEAR:
			var t := (a.y - c.y) / (p.y - c.y)
			var x := c.x + (p.x - c.x) * t
			if x >= a.x - WALL_CLEAR and x <= b.x + WALL_CLEAR:
				return true
		if absf(p.y - a.y) < ACCESS_HALF and minf(b.x, p.x + ACCESS_HALF) - maxf(a.x, p.x - ACCESS_HALF) > WALL_CLEAR:
			return true
		return false
	var lo2 := minf(c.x, p.x)
	var hi2 := maxf(c.x, p.x)
	if lo2 < a.x - WALL_CLEAR and hi2 > a.x + WALL_CLEAR:
		var t2 := (a.x - c.x) / (p.x - c.x)
		var z := c.y + (p.y - c.y) * t2
		if z >= a.y - WALL_CLEAR and z <= b.y + WALL_CLEAR:
			return true
	if absf(p.x - a.x) < ACCESS_HALF and minf(b.y, p.y + ACCESS_HALF) - maxf(a.y, p.y - ACCESS_HALF) > WALL_CLEAR:
		return true
	return false


static func _geometry_reason(code: String) -> String:
	match code:
		"":
			return ""
		"out_of_bounds":
			return "out_of_bounds"
		"duplicate", "overlap":
			return "wall_overlap"
		"crossing":
			return "wall_crossing"
	return "wall_bad"


## "" = stěnu lze postavit; jinak kód důvodu (REASON_TEXT). Bez kontroly peněz (to dělá build_wall).
func check_wall(x0: Variant, z0: Variant, x1: Variant, z1: Variant, reach: bool = true) -> String:
	for v in [x0, z0, x1, z1]:
		if typeof(v) != TYPE_INT:
			return "wall_bad"
	var n := _norm4(int(x0), int(z0), int(x1), int(z1))
	var ax := int(n[0])
	var az := int(n[1])
	var bx := int(n[2])
	var bz := int(n[3])
	if (ax == bx) == (az == bz):
		return "wall_bad"
	if ax < 0 or az < 0 or bx > gw or bz > gh:
		return "out_of_bounds"
	var cells := _wall_len(ax, az, bx, bz)
	if cells < WALL_MIN_CELLS:
		return "wall_short"
	if cells > WALL_MAX_CELLS:
		return "wall_long"
	if walls.size() >= MAX_WALLS:
		return "wall_limit"
	var cand := {"x0": ax, "z0": az, "x1": bx, "z1": bz}
	# Postavené stěny jsou navzájem platné → stačí kandidát proti každé zvlášť (O(n) místo O(n²) celého seznamu).
	# Geometrii rozhoduje jediný zdroj pravdy build_wall_validation.gd; vzdálené stěny se přeskočí obálkou.
	var why := _geometry_reason(WallGeometry.validate([cand], gw, gh))
	if why != "":
		return why
	for wid in walls:
		var w: Dictionary = walls[wid]
		if int(w["x1"]) < ax or int(w["x0"]) > bx or int(w["z1"]) < az or int(w["z0"]) > bz:
			continue
		why = _geometry_reason(WallGeometry.validate([{"x0": int(w["x0"]), "z0": int(w["z0"]), "x1": int(w["x1"]), "z1": int(w["z1"])}, cand], gw, gh))
		if why != "":
			return why
	# B4: konec nové stěny nesmí ležet v rozsahu dveří nebo okna jiné stěny (napojení do otvoru).
	for oid in openings:
		var o: Dictionary = openings[oid]
		if not walls.has(int(o["wid"])):
			continue
		var ow: Dictionary = walls[int(o["wid"])]
		var oc := opening_cells(String(o["kind"]))
		if _on_span(ow, int(o["at"]), oc, ax, az) or _on_span(ow, int(o["at"]), oc, bx, bz):
			return "wall_at_opening"
	# Hrana mezi dvojicí buněk v každém kroku: obě statické = skrz zeď domu / koridor; stejný předmět
	# po obou stranách = skrz předmět.
	for i in cells:
		var c1: Vector2i
		var c2: Vector2i
		if az == bz:
			c1 = Vector2i(ax + i, az - 1)
			c2 = Vector2i(ax + i, az)
		else:
			c1 = Vector2i(ax - 1, az + i)
			c2 = Vector2i(ax, az + i)
		if not _in_grid(c1.x, c1.y) or not _in_grid(c2.x, c2.y):
			continue
		var i1 := _idx(c1.x, c1.y)
		var i2 := _idx(c2.x, c2.y)
		if _static[i1] == 1 and _static[i2] == 1:
			return "blocked"
		if _solid[i1] != 0 and _solid[i1] == _solid[i2]:
			return "overlap"
		if _floor[i1] != 0 and _floor[i1] == _floor[i2]:
			return "overlap"
	# Přístup k výchozímu i koupenému nábytku.
	for f in fixed:
		var fr: Rect2 = f["rect"]
		for p in f["access"]:
			if not fr.has_point(p) and _wall_cuts_access(cand, fr.get_center(), p):
				return "blocks_access"
	for uid in sorted_uids():
		var it: Dictionary = items[uid]
		var id := String(it["id"])
		if Catalog.layer(id) == "floor":
			continue
		var fp := footprint(id, int(it["cx"]), int(it["cz"]), int(it["rot"]))
		var own := Rect2(origin + Vector2(fp.position) * CELL, Vector2(fp.size) * CELL)
		for p in access_points(id, int(it["cx"]), int(it["cz"]), int(it["rot"])):
			if not own.has_point(p) and _wall_cuts_access(cand, own.get_center(), p):
				return "blocks_access"
	if reach and _seals_off(cand):
		return "seals_off"
	return ""


# ---------------------------------------------------------------- dosažitelnost (BFS po buňkách)

func _walkable(i: int) -> bool:
	return (_static[i] == 0 or _keepout[i] == 1) and (_solid[i] == 0 or _enter[i] == 1)


## Hrany blokované stěnami. extra = zkušební stěna (bez otvorů); closed_oid = dveře, které se počítají jako
## zazděné (kontrola vybourání dveří). Hrany v rozsahu dveří zůstanou průchozí (B4).
func _build_edges(extra: Dictionary, closed_oid: int = 0) -> void:
	_hedge = PackedByteArray()
	_hedge.resize(gw * (gh + 1))
	_hedge.fill(0)
	_vedge = PackedByteArray()
	_vedge.resize((gw + 1) * gh)
	_vedge.fill(0)
	var spans := _door_spans(closed_oid)
	for wid in walls:
		_stamp_edges(walls[wid], spans.get(int(wid), []))
	if not extra.is_empty():
		_stamp_edges(extra)


## gaps = [[od, do)] v buňkách od začátku stěny – průchozí rozsahy dveří.
func _stamp_edges(w: Dictionary, gaps: Array = []) -> void:
	# Uložené stěny jsou normalizované; mini/maxi je pojistka pro budoucí volající (audit Gemini 22. 11.).
	var x0 := mini(int(w["x0"]), int(w["x1"]))
	var z0 := mini(int(w["z0"]), int(w["z1"]))
	var x1 := maxi(int(w["x0"]), int(w["x1"]))
	var z1 := maxi(int(w["z0"]), int(w["z1"]))
	if z0 == z1:
		for x in range(maxi(x0, 0), mini(x1, gw)):
			if not _in_gaps(gaps, x - x0):
				_hedge[z0 * gw + x] = 1
	else:
		for z in range(maxi(z0, 0), mini(z1, gh)):
			if not _in_gaps(gaps, z - z0):
				_vedge[z * (gw + 1) + x0] = 1


static func _in_gaps(gaps: Array, i: int) -> bool:
	for g in gaps:
		if i >= int(g[0]) and i < int(g[1]):
			return true
	return false


## wid -> [[od, do)] průchozích rozsahů dveří (closed_oid se vynechá).
func _door_spans(closed_oid: int = 0) -> Dictionary:
	var out := {}
	for oid in openings:
		var o: Dictionary = openings[oid]
		if int(oid) == closed_oid or not is_door(String(o["kind"])):
			continue
		# B4b: zamčené dveře se pro postavu bez klíče chovají jako zeď.
		if int(oid) != _nav_unlock and not door_passable(o, nav_viewer):
			continue
		var wid := int(o["wid"])
		if not out.has(wid):
			out[wid] = []
		out[wid].append([int(o["at"]), int(o["at"]) + opening_cells(String(o["kind"]))])
	return out


## Buňky dosažitelné od okraje parcely (ulice), 4-sousedství, stěny blokují hrany. extra = zkušební stěna.
func _reachable(extra: Dictionary, closed_oid: int = 0) -> PackedByteArray:
	_build_edges(extra, closed_oid)
	var seen := PackedByteArray()
	seen.resize(gw * gh)
	seen.fill(0)
	var queue := PackedInt32Array()
	# Krajní buňky jsou spojené s ulicí jen přes hranu, kterou neblokuje stěna postavená po hranici parcely
	# (B4 oprava: dřív se zakládaly všechny krajní buňky → místnost u kraje parcely nikdy nebyla „uzavřená“).
	for x in gw:
		for z in [0, gh - 1]:
			var i: int = z * gw + x
			if seen[i] == 0 and _walkable(i) and _street_open(x, z):
				seen[i] = 1
				queue.append(i)
	for z in gh:
		for x in [0, gw - 1]:
			var i2: int = z * gw + x
			if seen[i2] == 0 and _walkable(i2) and _street_open(x, z):
				seen[i2] = 1
				queue.append(i2)
	var head := 0
	while head < queue.size():
		var i3 := queue[head]
		head += 1
		var cx := i3 % gw
		var cz := i3 / gw
		# vlevo / vpravo přes svislé hrany, nahoru / dolů přes vodorovné
		if cx > 0 and _vedge[cz * (gw + 1) + cx] == 0:
			var j := i3 - 1
			if seen[j] == 0 and _walkable(j):
				seen[j] = 1
				queue.append(j)
		if cx < gw - 1 and _vedge[cz * (gw + 1) + cx + 1] == 0:
			var j2 := i3 + 1
			if seen[j2] == 0 and _walkable(j2):
				seen[j2] = 1
				queue.append(j2)
		if cz > 0 and _hedge[cz * gw + cx] == 0:
			var j3 := i3 - gw
			if seen[j3] == 0 and _walkable(j3):
				seen[j3] = 1
				queue.append(j3)
		if cz < gh - 1 and _hedge[(cz + 1) * gw + cx] == 0:
			var j4 := i3 + gw
			if seen[j4] == 0 and _walkable(j4):
				seen[j4] = 1
				queue.append(j4)
	return seen


## Vede z krajní buňky (x, z) volná hrana na ulici (mimo mřížku)? Hrany musí odpovídat _build_edges.
func _street_open(x: int, z: int) -> bool:
	if x == 0 and _vedge[z * (gw + 1)] == 0:
		return true
	if x == gw - 1 and _vedge[z * (gw + 1) + gw] == 0:
		return true
	if z == 0 and _hedge[x] == 0:
		return true
	if z == gh - 1 and _hedge[gh * gw + x] == 0:
		return true
	return false


## Buňky bodů použití (výchozí i koupený nábytek) – cíle, ke kterým musí zůstat cesta. skip_uid = vynechat položku.
func _access_targets(skip_uid: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in fixed:
		for p in f["access"]:
			var c := cell_of_world(p)
			if _in_grid(c.x, c.y):
				out.append(_idx(c.x, c.y))
	for uid in sorted_uids():
		if int(uid) == skip_uid:
			continue
		var it: Dictionary = items[uid]
		for p in access_points(String(it["id"]), int(it["cx"]), int(it["cz"]), int(it["rot"])):
			var c2 := cell_of_world(p)
			if _in_grid(c2.x, c2.y):
				out.append(_idx(c2.x, c2.y))
	return out


## Je bod použití dosažitelný od ulice? (Pro testy a UI; bez zkušební stěny.)
func access_reachable(p: Vector2) -> bool:
	var c := cell_of_world(p)
	if not _in_grid(c.x, c.y):
		return false
	var r := _reach_before()
	_build_edges({})
	return _target_reached(r, _idx(c.x, c.y))


## Cíl je dosažen, když je jeho buňka dosažitelná, nebo (bod použití uvnitř předmětu – sprcha, běžecký pás)
## když je dosažitelný soused, od kterého ho nedělí stěna. Hrany (_hedge/_vedge) musí odpovídat `reach`.
func _target_reached(reach: PackedByteArray, t: int) -> bool:
	if reach[t] == 1:
		return true
	var cx := t % gw
	var cz := t / gw
	if cx > 0 and _vedge[cz * (gw + 1) + cx] == 0 and reach[t - 1] == 1:
		return true
	if cx < gw - 1 and _vedge[cz * (gw + 1) + cx + 1] == 0 and reach[t + 1] == 1:
		return true
	if cz > 0 and _hedge[cz * gw + cx] == 0 and reach[t - gw] == 1:
		return true
	if cz < gh - 1 and _hedge[(cz + 1) * gw + cx] == 0 and reach[t + gw] == 1:
		return true
	return false


func _reach_before() -> PackedByteArray:
	var key := "%d:%d" % [revision, _layout_serial]
	if key != _reach_key:
		_reach_views.clear()
		_reach_key = key
	# Cache podle pohledu: bez zámků (nebo když zámky postavě nevadí) sdílí všichni jednu mapu.
	var vk := _view_key()
	if not _reach_views.has(vk):
		if _reach_views.size() >= 16:
			_reach_views.clear()
		_reach_views[vk] = _reachable({})
	_reach_cache = _reach_views[vk]
	return _reach_cache


## Klíč pohledu pro cache: "" = stejné jako bez zámků; jinak postava + ignorované dveře.
func _view_key() -> String:
	if nav_viewer == "":
		return ""
	var probe := "%d:%d:%s:%d" % [revision, _layout_serial, nav_viewer, _nav_unlock]
	if probe == _vk_in:
		return _vk_out
	var out := ""
	for oid in openings:
		var o: Dictionary = openings[oid]
		if String(o.get("lock", "")) != "" and int(oid) != _nav_unlock and is_door(String(o["kind"])) and not door_passable(o, nav_viewer):
			out = "%s#%d" % [nav_viewer, _nav_unlock]
			break
	_vk_in = probe
	_vk_out = out
	return out


## Odřízla by stěna cestu k bodu použití, kam se dosud dalo dojít?
func _seals_off(cand: Dictionary) -> bool:
	var targets := _access_targets()
	if targets.is_empty():
		return false
	var before := _reach_before()
	_build_edges({})
	var was := PackedByteArray()
	was.resize(targets.size())
	for k in targets.size():
		was[k] = 1 if _target_reached(before, targets[k]) else 0
	var after := _reachable(cand)
	for k in targets.size():
		if was[k] == 1 and not _target_reached(after, targets[k]):
			return true
	return false


## Kopie parcely se stejným prostředím, položkami a stěnami (simulace „co kdyby“, tento objekt se nemění).
func _sim_copy() -> RefCounted:
	var tmp = (load("res://scripts/world/lot_grid.gd") as GDScript).new()
	tmp.origin = origin
	tmp.gw = gw
	tmp.gh = gh
	tmp.static_rects = static_rects
	tmp.interior_rects = interior_rects
	tmp.keepout_rects = keepout_rects
	tmp.fixed = fixed
	tmp.items = items.duplicate(true)
	tmp.walls = walls.duplicate(true)
	tmp.openings = openings.duplicate(true)
	tmp.next_uid = next_uid
	tmp.next_oid = next_oid
	tmp.rebuild()
	return tmp


## B3: kontrola CESTY pro nákup (ignore_uid = 0) nebo přesun (ignore_uid = přesouvaná položka). Volá se až po
## check() a jen v transakci (BFS na kopii parcely – ne každý snímek v duchovi UI). "" = v pořádku, jinak
## "blocks_path" (předmět by odřízl dosud dosažitelný bod použití) nebo "access_unreachable" (k novému předmětu
## se nedá dojít od ulice). Koberce průchodnost nemění.
func reach_check(id: String, cx: int, cz: int, rot: int, ignore_uid: int) -> String:
	if not Catalog.has(id) or Catalog.layer(id) == "floor":
		return ""
	var before := _reach_before()
	_build_edges({})
	var targets := _access_targets(ignore_uid)
	var was := PackedByteArray()
	was.resize(targets.size())
	for k in targets.size():
		was[k] = 1 if _target_reached(before, targets[k]) else 0
	var tmp = _sim_copy()
	var uid := ignore_uid if ignore_uid > 0 else next_uid
	tmp.items[uid] = {"uid": uid, "id": id, "cx": cx, "cz": cz, "rot": rot, "bought_at": 0.0, "paid": 0}
	tmp.rebuild()
	var after: PackedByteArray = tmp._reachable({})
	for k in targets.size():
		if was[k] == 1 and not tmp._target_reached(after, targets[k]):
			return "blocks_path"
	for p in access_points(id, cx, cz, rot):
		var c := cell_of_world(p)
		if not _in_grid(c.x, c.y) or not tmp._target_reached(after, _idx(c.x, c.y)):
			return "access_unreachable"
	return ""


## B3: zazdila by stěna (x0, z0)–(x1, z1) postavu? pts = polohy postav ve světě (x, z). Postava, ke které se dosud
## dalo dojít od ulice, musí zůstat dosažitelná. Neplatnou stěnu nehodnotí (odmítne ji build_wall).
func wall_traps(x0: Variant, z0: Variant, x1: Variant, z1: Variant, pts: Array) -> bool:
	for v in [x0, z0, x1, z1]:
		if typeof(v) != TYPE_INT:
			return false
	var n := _norm4(int(x0), int(z0), int(x1), int(z1))
	if (int(n[0]) == int(n[2])) == (int(n[1]) == int(n[3])):
		return false
	var cells := PackedInt32Array()
	var before := _reach_before()
	_build_edges({})
	for p in pts:
		if typeof(p) != TYPE_VECTOR2 or not is_finite(p.x) or not is_finite(p.y):
			continue
		var c := cell_of_world(p)
		if _in_grid(c.x, c.y) and _target_reached(before, _idx(c.x, c.y)):
			cells.append(_idx(c.x, c.y))
	if cells.is_empty():
		return false
	var after := _reachable({"x0": n[0], "z0": n[1], "x1": n[2], "z1": n[3]})
	for i in cells:
		if not _target_reached(after, i):
			return true
	return false


func build_wall(x0: Variant, z0: Variant, x1: Variant, z1: Variant, now: float, actor: String = "") -> Dictionary:
	var why := check_wall(x0, z0, x1, z1)
	if why != "":
		return {"ok": false, "reason": why}
	var n := _norm4(int(x0), int(z0), int(x1), int(z1))
	var price := wall_price(n[0], n[1], n[2], n[3])
	if price > funds:
		return {"ok": false, "reason": "funds"}
	var wid := next_wid
	next_wid += 1
	walls[wid] = {"wid": wid, "x0": n[0], "z0": n[1], "x1": n[2], "z1": n[3], "built_at": _finite_time(now), "paid": price}
	funds -= price
	_log(now, "wall", "", -price, actor)
	revision += 1
	return {"ok": true, "reason": "", "wid": wid, "price": price}


## Do 24 herních hodin plná vratka (omyl), potom nic. Hodiny dozadu (rewind) = stará stěna.
func wall_refund_value(wid: int, now: float) -> int:
	if not walls.has(wid):
		return 0
	var w: Dictionary = walls[wid]
	var age := _finite_time(now) - float(w["built_at"])
	return int(w["paid"]) if age >= 0.0 and age <= REFUND_FULL_MINUTES else 0


func remove_wall(wid: Variant, now: float, actor: String = "") -> Dictionary:
	if typeof(wid) != TYPE_INT or not walls.has(int(wid)):
		return {"ok": false, "reason": "unknown_wid"}
	var refund := wall_refund_value(int(wid), now)
	# B4: s otvorem padají i jeho dveře a okna (vratka podle stejného pravidla 24 h).
	var gone := 0
	for o in openings_of(int(wid)):
		refund += opening_refund_value(int(o["oid"]), now)
		openings.erase(int(o["oid"]))
		gone += 1
	walls.erase(int(wid))
	funds = mini(funds + refund, MAX_FUNDS)
	_log(now, "unwall", "", refund, actor)
	revision += 1
	if gone > 0:
		rebuild()
	return {"ok": true, "reason": "", "refund": refund, "openings_removed": gone}


# ---------------------------------------------------------------- dveře a okna (B4, jen autorita mění)

static func opening_cells(kind: String) -> int:
	return int(OPENINGS[kind]["cells"]) if OPENINGS.has(kind) else 0


static func opening_price(kind: String) -> int:
	return int(OPENINGS[kind]["price"]) if OPENINGS.has(kind) else 0


static func is_door(kind: String) -> bool:
	return OPENINGS.has(kind) and bool(OPENINGS[kind]["pass"])


func sorted_oids() -> Array:
	var u := openings.keys()
	u.sort()
	return u


## Otvory jedné stěny (vzestupně podle oid).
func openings_of(wid: int) -> Array:
	var out: Array = []
	for oid in sorted_oids():
		if int(openings[oid]["wid"]) == wid:
			out.append(openings[oid])
	return out


## Leží mřížkový bod (px, pz) na stěně w v rozsahu [at, at + cells] (včetně krajů)?
static func _on_span(w: Dictionary, at: int, cells: int, px: int, pz: int) -> bool:
	var x0 := int(w["x0"])
	var z0 := int(w["z0"])
	if int(w["z0"]) == int(w["z1"]):
		return pz == z0 and px >= x0 + at and px <= x0 + at + cells
	return px == x0 and pz >= z0 + at and pz <= z0 + at + cells


## Buňky prostoru dveří: DOOR_DEPTH řad na obě strany hrany v rozsahu [at, at + cells).
static func _door_side_cells(w: Dictionary, at: int, cells: int) -> Array:
	var out: Array = []
	var x0 := int(w["x0"])
	var z0 := int(w["z0"])
	var horiz := int(w["z0"]) == int(w["z1"])
	for i in range(at, at + cells):
		for d in range(1, DOOR_DEPTH + 1):
			if horiz:
				out.append(Vector2i(x0 + i, z0 - d))
				out.append(Vector2i(x0 + i, z0 + d - 1))
			else:
				out.append(Vector2i(x0 - d, z0 + i))
				out.append(Vector2i(x0 + d - 1, z0 + i))
	return out


## Vedly by dveře do pevného předmětu nebo statické překážky (zeď domu, linka, strom)? Buňky mimo parcelu
## (ulice) a průchozí koridory/chodník jsou v pořádku.
func _door_side_blocked(w: Dictionary, at: int, cells: int) -> bool:
	for c in _door_side_cells(w, at, cells):
		if not _in_grid(c.x, c.y):
			continue
		var i := _idx(c.x, c.y)
		if (_static[i] == 1 and _keepout[i] == 0) or _solid[i] != 0:
			return true
	return false


func _stamp_doors() -> void:
	for oid in openings:
		var o: Dictionary = openings[oid]
		if not is_door(String(o["kind"])) or not walls.has(int(o["wid"])):
			continue
		for c in _door_side_cells(walls[int(o["wid"])], int(o["at"]), opening_cells(String(o["kind"]))):
			if _in_grid(c.x, c.y):
				_door_side[_idx(c.x, c.y)] = 1


## "" = otvor lze osadit; jinak kód důvodu. Bez kontroly peněz (to dělá build_opening).
func check_opening(wid: Variant, kind: Variant, at: Variant) -> String:
	if typeof(wid) != TYPE_INT or typeof(kind) != TYPE_STRING or typeof(at) != TYPE_INT or not OPENINGS.has(String(kind)):
		return "opening_bad"
	if not walls.has(int(wid)):
		return "unknown_wid"
	if openings.size() >= MAX_OPENINGS:
		return "opening_limit"
	var w: Dictionary = walls[int(wid)]
	var k := String(kind)
	var cells := opening_cells(k)
	var a := int(at)
	var wl := _wall_len(int(w["x0"]), int(w["z0"]), int(w["x1"]), int(w["z1"]))
	if a < OPENING_EDGE or a + cells > wl - OPENING_EDGE:
		return "opening_edge"
	for oid in openings:
		var o: Dictionary = openings[oid]
		if int(o["wid"]) != int(wid):
			continue
		var oa := int(o["at"])
		var ob := oa + opening_cells(String(o["kind"]))
		if a < ob + OPENING_GAP and oa < a + cells + OPENING_GAP:
			return "opening_overlap"
	for owid in walls:
		if int(owid) == int(wid):
			continue
		var ow: Dictionary = walls[owid]
		if _on_span(w, a, cells, int(ow["x0"]), int(ow["z0"])) or _on_span(w, a, cells, int(ow["x1"]), int(ow["z1"])):
			return "opening_junction"
	if is_door(k) and _door_side_blocked(w, a, cells):
		return "door_blocked"
	return ""


func build_opening(wid: Variant, kind: Variant, at: Variant, now: float, actor: String = "") -> Dictionary:
	var why := check_opening(wid, kind, at)
	if why != "":
		return {"ok": false, "reason": why}
	var price := opening_price(String(kind))
	if price > funds:
		return {"ok": false, "reason": "funds"}
	var oid := next_oid
	next_oid += 1
	openings[oid] = {"oid": oid, "wid": int(wid), "kind": String(kind), "at": int(at),
		"built_at": _finite_time(now), "paid": price, "lock": ""}
	funds -= price
	_log(now, "opening", String(kind), -price, actor)
	revision += 1
	rebuild()
	return {"ok": true, "reason": "", "oid": oid, "price": price}


## Do 24 herních hodin plná vratka (omyl), potom nic – osazené dveře ani okno nikdo nevykoupí.
func opening_refund_value(oid: int, now: float) -> int:
	if not openings.has(oid):
		return 0
	var o: Dictionary = openings[oid]
	var age := _finite_time(now) - float(o["built_at"])
	return int(o["paid"]) if age >= 0.0 and age <= REFUND_FULL_MINUTES else 0


## Odřízlo by zazdění dveří oid cestu k bodu použití, kam se dosud dalo dojít?
func door_close_seals(oid: int) -> bool:
	if not openings.has(oid) or not is_door(String(openings[oid]["kind"])):
		return false
	var targets := _access_targets()
	if targets.is_empty():
		return false
	var before := _reach_before()
	_build_edges({})
	var was := PackedByteArray()
	was.resize(targets.size())
	for k in targets.size():
		was[k] = 1 if _target_reached(before, targets[k]) else 0
	var after := _reachable({}, oid)
	for k in targets.size():
		if was[k] == 1 and not _target_reached(after, targets[k]):
			return true
	return false


## Zavřelo by zazdění dveří oid postavu, ke které se dosud dalo dojít od ulice? pts = polohy postav (x, z).
func opening_traps(oid: Variant, pts: Array) -> bool:
	if typeof(oid) != TYPE_INT or not openings.has(int(oid)) or not is_door(String(openings[int(oid)]["kind"])):
		return false
	var cells := PackedInt32Array()
	var before := _reach_before()
	_build_edges({})
	for p in pts:
		if typeof(p) != TYPE_VECTOR2 or not is_finite(p.x) or not is_finite(p.y):
			continue
		var c := cell_of_world(p)
		if _in_grid(c.x, c.y) and _target_reached(before, _idx(c.x, c.y)):
			cells.append(_idx(c.x, c.y))
	if cells.is_empty():
		return false
	var after := _reachable({}, int(oid))
	for i in cells:
		if not _target_reached(after, i):
			return true
	return false


func remove_opening(oid: Variant, now: float, actor: String = "") -> Dictionary:
	if typeof(oid) != TYPE_INT or not openings.has(int(oid)):
		return {"ok": false, "reason": "unknown_oid"}
	if door_close_seals(int(oid)):
		return {"ok": false, "reason": "seals_off"}
	var refund := opening_refund_value(int(oid), now)
	var o: Dictionary = openings[int(oid)]
	openings.erase(int(oid))
	funds = mini(funds + refund, MAX_FUNDS)
	_log(now, "unopening", String(o["kind"]), refund, actor)
	revision += 1
	rebuild()
	return {"ok": true, "reason": "", "refund": refund, "kind": String(o["kind"])}


# ---------------------------------------------------------------- zámky dveří (B4b, 24. 11. 2026)

## Platný zámek: "", LOCK_ALL nebo jméno uzlu postavy (bez řídicích a bidi znaků, platné jméno uzlu, max 64).
static func valid_lock(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s := String(v)
	if s == "" or s == LOCK_ALL:
		return true
	if s.length() > LOCK_MAX_LEN or s.validate_node_name() != s or s.strip_edges() != s or s.contains(LOCK_ALL):
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF or c == 0x2028 or c == 0x2029:
			return false
	return true


## Smí postava `who` projít dveřmi o? who "" = pohled bez zámků (stavba, kontroly cest k věcem).
static func door_passable(o: Dictionary, who: String) -> bool:
	var lk := String(o.get("lock", ""))
	return lk == "" or who == "" or (lk != LOCK_ALL and lk == who)


func lock_of(oid: int) -> String:
	return String(openings[oid].get("lock", "")) if openings.has(oid) else ""


func locked_count() -> int:
	var n := 0
	for oid in openings:
		if String(openings[oid].get("lock", "")) != "":
			n += 1
	return n


func has_locks() -> bool:
	for oid in openings:
		if String(openings[oid].get("lock", "")) != "":
			return true
	return false


## Zamčené dveře, kterými postava `who` neprojde (vzestupně podle oid).
func locked_against(who: String) -> Array:
	var out: Array = []
	for oid in sorted_oids():
		var o: Dictionary = openings[oid]
		if String(o.get("lock", "")) != "" and is_door(String(o["kind"])) and not door_passable(o, who):
			out.append(int(oid))
	return out


## Kontrola zámku (bez změny stavu). pts = [[klíč postavy, Vector2 poloha (x, z)], …] všech postav na parcele.
## Odemčení nikoho nezavře; zámek nesmí zavřít postavu bez klíče, ke které se dosud dalo dojít (lock_traps);
## zámek pro všechny nesmí odříznout věci (lock_seals). Osobní zámek ostatním věci odříznout smí – to je pointa.
func check_lock(oid: Variant, lock: Variant, pts: Array) -> String:
	if typeof(oid) != TYPE_INT or not openings.has(int(oid)):
		return "unknown_oid"
	var o: Dictionary = openings[int(oid)]
	if not is_door(String(o["kind"])):
		return "not_door"
	if not valid_lock(lock):
		return "lock_bad"
	var lk := String(lock)
	var cur := String(o.get("lock", ""))
	if cur == lk:
		return "lock_same"
	if lk == "":
		return ""
	if cur == "" and locked_count() >= MAX_LOCKED:
		return "lock_limit"
	var saved_v := nav_viewer
	var saved_u := _nav_unlock
	nav_viewer = ""
	_nav_unlock = 0
	var why := ""
	if lk == LOCK_ALL and door_close_seals(int(oid)):
		why = "lock_seals"
	elif lock_traps(int(oid), lk, pts):
		why = "lock_traps"
	nav_viewer = saved_v
	_nav_unlock = saved_u
	return why


## Zavřel by zámek lk na dveřích oid někoho bez klíče, ke komu se z jeho pohledu dosud dalo dojít od ulice?
## Postavy se stejnou sadou zámků proti sobě sdílí jeden pár BFS (audit Gemini 24. 11.: dřív 2 BFS na postavu).
func lock_traps(oid: int, lk: String, pts: Array) -> bool:
	if not openings.has(oid):
		return false
	var probe := {"lock": lk}
	var groups := _view_groups(pts, oid)
	var saved_v := nav_viewer
	var saved_u := _nav_unlock
	_nav_unlock = 0
	var trapped := false
	for sig in groups:
		var g: Dictionary = groups[sig]
		var cells: Array = []
		for k in g["cells"].size():
			if not door_passable(probe, String(g["who"][k])):
				cells.append(int(g["cells"][k]))
		if cells.is_empty():
			continue
		nav_viewer = String(g["who"][0])
		var before := _reachable({})
		var was: Array = []
		for ci in cells:
			if _target_reached(before, ci):
				was.append(ci)
		if was.is_empty():
			continue
		var after := _reachable({}, oid)
		for ci in was:
			if not _target_reached(after, ci):
				trapped = true
				break
		if trapped:
			break
	nav_viewer = saved_v
	_nav_unlock = saved_u
	return trapped


## Postavy [[klíč, Vector2], …] seskupené podle sady zamčených dveří, které je nepustí (bez skip_oid):
## {podpis: {"who": [klíče], "cells": [indexy buněk]}}. Nesmyslné záznamy a polohy mimo mřížku se vynechají.
func _view_groups(pts: Array, skip_oid: int = 0) -> Dictionary:
	var groups := {}
	for e in pts:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != 2 or typeof(e[0]) != TYPE_STRING or typeof(e[1]) != TYPE_VECTOR2:
			continue
		var who := String(e[0])
		var p: Vector2 = e[1]
		if who == "" or not is_finite(p.x) or not is_finite(p.y):
			continue
		var c := cell_of_world(p)
		if not _in_grid(c.x, c.y):
			continue
		var sig_parts: Array = []
		for loid in locked_against(who):
			if int(loid) != skip_oid:
				sig_parts.append(str(loid))
		var sig := ",".join(sig_parts)
		if not groups.has(sig):
			groups[sig] = {"who": [], "cells": []}
		groups[sig]["who"].append(who)
		groups[sig]["cells"].append(_idx(c.x, c.y))
	return groups


## B4b: stavební kontrola „nikoho to nezavře“ (zeď, vybourání dveří) i z pohledu postav, kterým zámky
## zavírají jiné cesty. check(polohy: Array[Vector2]) -> bool se volá s nastaveným nav_viewer jednou za skupinu
## postav se stejnými zámky (jen skupiny, proti kterým nějaký zámek je – pohled bez zámků řeší volající).
func traps_in_lock_views(check: Callable, pts: Array) -> bool:
	if not has_locks():
		return false
	var groups := _view_groups(pts)
	var saved_v := nav_viewer
	var saved_u := _nav_unlock
	_nav_unlock = 0
	var trapped := false
	for sig in groups:
		if String(sig) == "":
			continue
		var g: Dictionary = groups[sig]
		var where: Array = []
		for ci in g["cells"]:
			where.append(origin + (Vector2(int(ci) % gw, int(ci) / gw) + Vector2(0.5, 0.5)) * CELL)
		nav_viewer = String(g["who"][0])
		if bool(check.call(where)):
			trapped = true
			break
	nav_viewer = saved_v
	_nav_unlock = saved_u
	return trapped


## Zamkne / odemkne dveře (autorita). Peníze se nemění, do knihy transakcí se nic nepíše.
func set_lock(oid: Variant, lock: Variant, pts: Array) -> Dictionary:
	var why := check_lock(oid, lock, pts)
	if why != "":
		return {"ok": false, "reason": why}
	var o: Dictionary = openings[int(oid)]
	var prev := String(o.get("lock", ""))
	o["lock"] = String(lock)
	revision += 1
	return {"ok": true, "reason": "", "oid": int(oid), "lock": String(lock), "prev": prev}


## Koncové body otvoru ve světě (x, z), ve směru stěny.
func opening_world(o: Dictionary) -> Array:
	var w: Dictionary = walls.get(int(o["wid"]), {})
	if w.is_empty():
		return [Vector2.ZERO, Vector2.ZERO]
	var ab := wall_world(w)
	var dir: Vector2 = ((ab[1] as Vector2) - (ab[0] as Vector2)).normalized()
	var a: Vector2 = (ab[0] as Vector2) + dir * (float(o["at"]) * CELL)
	return [a, a + dir * (float(opening_cells(String(o["kind"]))) * CELL)]


## Otvor nejblíž bodu ve světě (do vzdálenosti tol), 0 = žádný.
func opening_at_world(p: Vector2, tol: float = 0.25) -> int:
	var best := 0
	var best_d := tol
	for oid in sorted_oids():
		var ab := opening_world(openings[oid])
		var q := Geometry2D.get_closest_point_to_segment(p, ab[0], ab[1])
		var dd := q.distance_to(p)
		if dd <= best_d:
			best_d = dd
			best = int(oid)
	return best


## Plné (neprůchozí) úseky stěny ve světě [[a, b], …] – bez rozsahů dveří. Okna se počítají jako plná zeď.
## Zkušební stěna bez "wid" je jeden celý úsek. Cache podle revize a rozložení (LotNav to volá často).
func wall_segments(w: Dictionary) -> Array:
	var ab := wall_world(w)
	if openings.is_empty() or not w.has("wid") or not walls.has(int(w["wid"])):
		return [ab]
	var key := "%d:%d" % [revision, _layout_serial]
	if key != _seg_key:
		_seg_key = key
		_seg_cache.clear()
	var wid := int(w["wid"])
	# B4b: zamčené dveře jsou pro postavu bez klíče plná zeď → cache i podle pohledu.
	var vk := _view_key()
	var ck: Variant = wid if vk == "" else "%s|%d" % [vk, wid]
	if _seg_cache.has(ck):
		return _seg_cache[ck]
	var gaps: Array = _door_spans().get(wid, [])
	var out: Array = []
	if gaps.is_empty():
		out = [ab]
	else:
		gaps.sort_custom(func(p, q): return int(p[0]) < int(q[0]))
		var a: Vector2 = ab[0]
		var dir: Vector2 = ((ab[1] as Vector2) - a).normalized()
		var wl := _wall_len(int(w["x0"]), int(w["z0"]), int(w["x1"]), int(w["z1"]))
		var s := 0
		for g in gaps:
			if int(g[0]) > s:
				out.append([a + dir * (float(s) * CELL), a + dir * (float(g[0]) * CELL)])
			s = int(g[1])
		if s < wl:
			out.append([a + dir * (float(s) * CELL), ab[1]])
	_seg_cache[ck] = out
	return out


## Stěna nejblíž bodu ve světě (do vzdálenosti tol), 0 = žádná.
func wall_at_world(p: Vector2, tol: float = 0.2) -> int:
	var best := 0
	var best_d := tol
	for wid in sorted_wids():
		var ab := wall_world(walls[wid])
		var a: Vector2 = ab[0]
		var b: Vector2 = ab[1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var dd := q.distance_to(p)
		if dd <= best_d:
			best_d = dd
			best = int(wid)
	return best


# ---------------------------------------------------------------- dotazy

## uid položky na buňce (pevná má přednost před kobercem), 0 = nic koupeného.
func uid_at_cell(cx: int, cz: int) -> int:
	if not _in_grid(cx, cz):
		return 0
	var s := _solid[_idx(cx, cz)]
	if s > 0:
		return s
	return _floor[_idx(cx, cz)]


func uid_at_world(p: Vector2) -> int:
	var c := cell_of_world(p)
	return uid_at_cell(c.x, c.y)


func sorted_uids() -> Array:
	var u := items.keys()
	u.sort()
	return u


## Atmosféra prostředí v bodě (x, z): vážený součet `appeal` koupených položek v okolí, ±APPEAL_CAP.
## Stěny zatím nestíní (zjednodušení, docs/world-building.md).
func appeal_at(p: Vector2) -> float:
	var s := 0.0
	for uid in sorted_uids():
		var it: Dictionary = items[uid]
		var a := float(Catalog.get_item(String(it["id"]))["appeal"])
		if a == 0.0:
			continue
		var dist := p.distance_to(center_of(String(it["id"]), int(it["cx"]), int(it["cz"]), int(it["rot"])))
		var wgt := 1.0 if dist <= APPEAL_NEAR else clampf((APPEAL_FAR - dist) / (APPEAL_FAR - APPEAL_NEAR), 0.0, 1.0)
		s += a * wgt
	# B4: okna (světlo, výhled) – jako položka se středem uprostřed otvoru.
	for oid in sorted_oids():
		var o: Dictionary = openings[oid]
		var oa := float(OPENINGS[String(o["kind"])]["appeal"])
		if oa == 0.0 or not walls.has(int(o["wid"])):
			continue
		var sp := opening_world(o)
		var od := p.distance_to(((sp[0] as Vector2) + (sp[1] as Vector2)) * 0.5)
		var ow := 1.0 if od <= APPEAL_NEAR else clampf((APPEAL_FAR - od) / (APPEAL_FAR - APPEAL_NEAR), 0.0, 1.0)
		s += oa * ow
	return clampf(s, -APPEAL_CAP, APPEAL_CAP)


# ---------------------------------------------------------------- ukládání (autorita)

func to_dict() -> Dictionary:
	var arr: Array = []
	for uid in sorted_uids():
		var it: Dictionary = items[uid]
		arr.append({"uid": int(uid), "id": String(it["id"]), "cx": int(it["cx"]), "cz": int(it["cz"]),
			"rot": int(it["rot"]), "bought_at": float(it["bought_at"]), "paid": int(it["paid"])})
	# revision se neukládá: je jen běhový čítač pro síť (uložení → načtení → uložení musí dát totéž).
	var warr: Array = []
	for wid in sorted_wids():
		warr.append(_wall_record(walls[wid]))
	var oarr: Array = []
	for oid in sorted_oids():
		oarr.append(_opening_record(openings[oid]))
	return {"version": VERSION, "funds": funds, "next_uid": next_uid, "items": arr,
		"ledger": ledger.duplicate(true), "next_wid": next_wid, "walls": warr,
		"next_oid": next_oid, "openings": oarr}


static func _opening_record(o: Dictionary) -> Dictionary:
	return {"oid": int(o["oid"]), "wid": int(o["wid"]), "kind": String(o["kind"]), "at": int(o["at"]),
		"built_at": float(o["built_at"]), "paid": int(o["paid"]), "lock": String(o.get("lock", ""))}


static func _is_int(v: Variant, lo: int, hi: int) -> bool:
	if typeof(v) == TYPE_FLOAT:
		if not is_finite(v) or floorf(v) != v:
			return false
		v = int(v)
	return typeof(v) == TYPE_INT and int(v) >= lo and int(v) <= hi


static func _is_num(v: Variant, lo: float, hi: float) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


## Typová a rozsahová kontrola uloženého snímku (bez znalosti prostředí). "" = v pořádku.
static func validate_snapshot(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "bad_lot"
	if not _is_int(d.get("version"), 1, VERSION):
		return "bad_lot_version"
	if not _is_int(d.get("funds"), 0, MAX_FUNDS) or not _is_int(d.get("next_uid"), 1, 1000000000):
		return "bad_lot"
	var arr: Variant = d.get("items")
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() > MAX_ITEMS:
		return "bad_lot_items"
	var seen := {}
	for it in arr:
		if typeof(it) != TYPE_DICTIONARY:
			return "bad_lot_items"
		if not _is_int(it.get("uid"), 1, int(d["next_uid"]) - 1) or seen.has(int(it["uid"])):
			return "bad_lot_items"
		seen[int(it["uid"])] = true
		if not Catalog.has(it.get("id")) or not _is_int(it.get("rot"), 0, 3):
			return "bad_lot_items"
		if not _is_int(it.get("cx"), -100000, 100000) or not _is_int(it.get("cz"), -100000, 100000):
			return "bad_lot_items"
		if not _is_num(it.get("bought_at"), -1.0e12, 1.0e12) or not _is_int(it.get("paid"), 0, MAX_FUNDS):
			return "bad_lot_items"
	var lg: Variant = d.get("ledger", [])
	if typeof(lg) != TYPE_ARRAY or (lg as Array).size() > LEDGER_MAX:
		return "bad_lot_ledger"
	for e in lg:
		if typeof(e) != TYPE_DICTIONARY or not _is_num(e.get("t"), -1.0e12, 1.0e12) \
				or typeof(e.get("kind")) != TYPE_STRING or typeof(e.get("id")) != TYPE_STRING \
				or not _is_int(e.get("amount"), -MAX_FUNDS, MAX_FUNDS) or typeof(e.get("by")) != TYPE_STRING \
				or String(e["kind"]).length() > 16 or String(e["id"]).length() > 48 or String(e["by"]).length() > 40:
			return "bad_lot_ledger"
	# v1 (B1) stěny neměl – případný klíč se ignoruje (migrace = parcela bez stěn).
	var wseen := {}
	if int(d["version"]) >= 2:
		if not _is_int(d.get("next_wid"), 1, 1000000000):
			return "bad_lot_walls"
		var wa: Variant = d.get("walls")
		if typeof(wa) != TYPE_ARRAY or (wa as Array).size() > MAX_WALLS:
			return "bad_lot_walls"
		for w in wa:
			if typeof(w) != TYPE_DICTIONARY or (w as Dictionary).size() != 7:
				return "bad_lot_walls"
			if not _is_int(w.get("wid"), 1, int(d["next_wid"]) - 1) or wseen.has(int(w["wid"])):
				return "bad_lot_walls"
			wseen[int(w["wid"])] = true
			for k in ["x0", "z0", "x1", "z1"]:
				if not _is_int(w.get(k), 0, 100000):
					return "bad_lot_walls"
			if not _is_num(w.get("built_at"), -1.0e12, 1.0e12) or not _is_int(w.get("paid"), 0, MAX_FUNDS):
				return "bad_lot_walls"
	# v2 otvory neměl (migrace = stěny bez dveří a oken). Geometrii otvorů ověří plan_restore proti stěnám.
	if int(d["version"]) >= 3:
		if not _is_int(d.get("next_oid"), 1, 1000000000):
			return "bad_lot_openings"
		var oa: Variant = d.get("openings")
		if typeof(oa) != TYPE_ARRAY or (oa as Array).size() > MAX_OPENINGS:
			return "bad_lot_openings"
		var oseen := {}
		# v4 (B4b) má navíc zámek; v3 se migruje na odemčené dveře.
		var ofields := 7 if int(d["version"]) >= 4 else 6
		var nlocked := 0
		for o in oa:
			if typeof(o) != TYPE_DICTIONARY or (o as Dictionary).size() != ofields:
				return "bad_lot_openings"
			if ofields == 7:
				if not valid_lock(o.get("lock")):
					return "bad_lot_openings"
				if String(o["lock"]) != "":
					nlocked += 1
					if typeof(o.get("kind")) != TYPE_STRING or not is_door(String(o["kind"])) or nlocked > MAX_LOCKED:
						return "bad_lot_openings"
			if not _is_int(o.get("oid"), 1, int(d["next_oid"]) - 1) or oseen.has(int(o["oid"])):
				return "bad_lot_openings"
			oseen[int(o["oid"])] = true
			if not _is_int(o.get("wid"), 1, 1000000000) or not wseen.has(int(o["wid"])):
				return "bad_lot_openings"
			if typeof(o.get("kind")) != TYPE_STRING or not OPENINGS.has(String(o["kind"])):
				return "bad_lot_openings"
			if not _is_int(o.get("at"), 0, WALL_MAX_CELLS):
				return "bad_lot_openings"
			if not _is_num(o.get("built_at"), -1.0e12, 1.0e12) or not _is_int(o.get("paid"), 0, MAX_FUNDS):
				return "bad_lot_openings"
	return ""


## Simulace obnovy na kopii (bez změny tohoto objektu): položky, které v aktuálním prostředí už nejdou
## umístit (jiný dům, přestavba), se vyřadí a vrátí za zaplacenou cenu. Vrací
## {"ok", "reason", "kept": [item dict], "dropped": int, "refund": int}. Pořadí kept = vzestupně uid.
func plan_restore(d: Variant) -> Dictionary:
	var why := validate_snapshot(d)
	if why != "":
		return {"ok": false, "reason": why}
	var tmp = (load("res://scripts/world/lot_grid.gd") as GDScript).new()
	tmp.origin = origin
	tmp.gw = gw
	tmp.gh = gh
	tmp.static_rects = static_rects
	tmp.interior_rects = interior_rects
	tmp.keepout_rects = keepout_rects
	tmp.fixed = fixed
	tmp.rebuild()
	# Stěny napřed (konstrukce domu); předměty, které by s nimi kolidovaly, se vyřadí a vrátí.
	var kept_walls: Array = []
	var dropped_walls := 0
	var refund := 0
	if int(d["version"]) >= 2:
		var warr: Array = (d["walls"] as Array).duplicate(true)
		warr.sort_custom(func(a, b): return int(a["wid"]) < int(b["wid"]))
		for w in warr:
			var n := _norm4(int(w["x0"]), int(w["z0"]), int(w["x1"]), int(w["z1"]))
			var wrec := {"wid": int(w["wid"]), "x0": n[0], "z0": n[1], "x1": n[2], "z1": n[3],
				"built_at": float(w["built_at"]), "paid": int(w["paid"])}
			# Bez kontroly dosažitelnosti: stěny byly platné při stavbě a BFS pro 128 stěn by zdržel načtení.
			if tmp.check_wall(n[0], n[1], n[2], n[3], false) != "":
				dropped_walls += 1
				refund += mini(int(wrec["paid"]), wall_price(n[0], n[1], n[2], n[3]))
				continue
			tmp.walls[wrec["wid"]] = wrec
			kept_walls.append(wrec)
	# B4: otvory po stěnách a před předměty (předmět v prostoru dveří se vyřadí, ne dveře).
	var kept_openings: Array = []
	var dropped_openings := 0
	if int(d["version"]) >= 3:
		var oarr: Array = (d["openings"] as Array).duplicate(true)
		oarr.sort_custom(func(a, b): return int(a["oid"]) < int(b["oid"]))
		for o in oarr:
			var orec := {"oid": int(o["oid"]), "wid": int(o["wid"]), "kind": String(o["kind"]), "at": int(o["at"]),
				"built_at": float(o["built_at"]), "paid": int(o["paid"]),
				"lock": String(o["lock"]) if int(d["version"]) >= 4 else ""}
			if tmp.check_opening(orec["wid"], orec["kind"], orec["at"]) != "":
				dropped_openings += 1
				refund += mini(int(orec["paid"]), opening_price(String(orec["kind"])))
				continue
			tmp.openings[orec["oid"]] = orec
			kept_openings.append(orec)
		tmp.rebuild()
	var arr: Array = (d["items"] as Array).duplicate(true)
	arr.sort_custom(func(a, b): return int(a["uid"]) < int(b["uid"]))
	var kept: Array = []
	var dropped := 0
	for it in arr:
		var rec := {"uid": int(it["uid"]), "id": String(it["id"]), "cx": int(it["cx"]), "cz": int(it["cz"]),
			"rot": int(it["rot"]), "bought_at": float(it["bought_at"]), "paid": int(it["paid"])}
		if tmp.check(rec["id"], rec["cx"], rec["cz"], rec["rot"]) != "":
			dropped += 1
			# Vratka nejvýš v katalogové ceně (audit Gemini: upravený save s paid = 1e8 by jinak „tiskl“ peníze).
			refund += mini(int(rec["paid"]), int(Catalog.get_item(String(rec["id"]))["price"]))
			continue
		tmp.items[rec["uid"]] = rec
		tmp._stamp(rec)
		kept.append(rec)
	return {"ok": true, "reason": "", "kept": kept, "dropped": dropped + dropped_walls + dropped_openings, "refund": refund,
		"kept_walls": kept_walls, "dropped_walls": dropped_walls,
		"kept_openings": kept_openings, "dropped_openings": dropped_openings}


## Obnoví stav ze snímku (po validaci). Vrací výsledek plan_restore.
func from_dict(d: Variant, now: float = 0.0) -> Dictionary:
	var plan := plan_restore(d)
	if not bool(plan["ok"]):
		return plan
	items.clear()
	for rec in plan["kept"]:
		items[int(rec["uid"])] = rec
	walls.clear()
	next_wid = int(d.get("next_wid", 1)) if int(d["version"]) >= 2 else 1
	for wrec in plan["kept_walls"]:
		walls[int(wrec["wid"])] = wrec
		next_wid = maxi(next_wid, int(wrec["wid"]) + 1)
	openings.clear()
	next_oid = int(d.get("next_oid", 1)) if int(d["version"]) >= 3 else 1
	for orec in plan["kept_openings"]:
		openings[int(orec["oid"])] = orec
		next_oid = maxi(next_oid, int(orec["oid"]) + 1)
	next_uid = int(d["next_uid"])
	funds = clampi(int(d["funds"]) + int(plan["refund"]), 0, MAX_FUNDS)
	ledger = []
	for e in d.get("ledger", []):
		ledger.append({"t": float(e["t"]), "kind": String(e["kind"]), "id": String(e["id"]),
			"amount": int(e["amount"]), "by": String(e["by"])})
	if int(plan["dropped"]) > 0:
		_log(now, "restore_refund", "", int(plan["refund"]), "")
	revision += 1
	rebuild()
	return plan


## Výchozí stav (nová hra): nic koupeného, startovní rozpočet.
func reset() -> void:
	items.clear()
	next_uid = 1
	walls.clear()
	next_wid = 1
	openings.clear()
	next_oid = 1
	funds = START_FUNDS
	ledger.clear()
	revision += 1
	rebuild()


# ---------------------------------------------------------------- síť (veřejný snímek)

## Co uvidí všichni klienti: položky (vč. ceny a času nákupu kvůli náhledu výkupní ceny) a rozpočet domácnosti.
## Žádná kniha transakcí, žádná jména hráčů.
func public_snapshot() -> Dictionary:
	var arr: Array = []
	for uid in sorted_uids():
		var it: Dictionary = items[uid]
		arr.append([int(uid), String(it["id"]), int(it["cx"]), int(it["cz"]), int(it["rot"]),
			float(it["bought_at"]), int(it["paid"])])
	var warr: Array = []
	for wid in sorted_wids():
		var w: Dictionary = walls[wid]
		warr.append([int(wid), int(w["x0"]), int(w["z0"]), int(w["x1"]), int(w["z1"]), float(w["built_at"]), int(w["paid"])])
	var oarr: Array = []
	for oid in sorted_oids():
		var o: Dictionary = openings[oid]
		oarr.append([int(oid), int(o["wid"]), String(o["kind"]), int(o["at"]), float(o["built_at"]), int(o["paid"]),
			String(o.get("lock", ""))])
	return {"v": VERSION, "rev": revision, "funds": funds, "items": arr, "walls": warr, "open": oarr}


## Klient: převezme snímek od serveru. Sanitizuje typy a rozsahy (server je autorita, ale paket může být
## poškozený nebo podvržený); pozice musí ležet v mřížce. Vrací false a nic nemění, když neprojde.
func apply_public(s: Variant) -> bool:
	if typeof(s) != TYPE_DICTIONARY or not _is_int(s.get("v"), 1, VERSION) \
			or not _is_int(s.get("rev"), 0, 2000000000) or not _is_int(s.get("funds"), 0, MAX_FUNDS):
		return false
	var arr: Variant = s.get("items")
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() > MAX_ITEMS:
		return false
	var out := {}
	for e in arr:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != 7:
			return false
		if not _is_num(e[5], -1.0e12, 1.0e12) or not _is_int(e[6], 0, MAX_FUNDS):
			return false
		if not _is_int(e[0], 1, 1000000000) or out.has(int(e[0])) or not Catalog.has(e[1]) or not _is_int(e[4], 0, 3):
			return false
		if not _is_int(e[2], 0, gw - 1) or not _is_int(e[3], 0, gh - 1):
			return false
		var fp := footprint(String(e[1]), int(e[2]), int(e[3]), int(e[4]))
		if fp.end.x > gw or fp.end.y > gh:
			return false
		out[int(e[0])] = {"uid": int(e[0]), "id": String(e[1]), "cx": int(e[2]), "cz": int(e[3]), "rot": int(e[4]),
			"bought_at": float(e[5]), "paid": int(e[6])}
	# Stěny (v2; snímek v1 je nemá). Typy, meze, délky i geometrie se ověří znovu – paket může být podvržený.
	var wout := {}
	var wv: Variant = s.get("walls", [])
	if typeof(wv) != TYPE_ARRAY or (wv as Array).size() > MAX_WALLS:
		return false
	var geo: Array = []
	for e in wv:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != 7:
			return false
		if not _is_int(e[0], 1, 1000000000) or wout.has(int(e[0])):
			return false
		if not _is_int(e[1], 0, gw) or not _is_int(e[2], 0, gh) or not _is_int(e[3], 0, gw) or not _is_int(e[4], 0, gh):
			return false
		if not _is_num(e[5], -1.0e12, 1.0e12) or not _is_int(e[6], 0, MAX_FUNDS):
			return false
		var n := _norm4(int(e[1]), int(e[2]), int(e[3]), int(e[4]))
		var cells := _wall_len(n[0], n[1], n[2], n[3])
		if (n[0] != n[2] and n[1] != n[3]) or cells < WALL_MIN_CELLS or cells > WALL_MAX_CELLS:
			return false
		geo.append({"x0": n[0], "z0": n[1], "x1": n[2], "z1": n[3]})
		wout[int(e[0])] = {"wid": int(e[0]), "x0": n[0], "z0": n[1], "x1": n[2], "z1": n[3],
			"built_at": float(e[5]), "paid": int(e[6])}
	if not geo.is_empty() and WallGeometry.validate(geo, gw, gh) != "":
		return false
	# Otvory (v3): stěna musí existovat, rozsah s ostěním, odstupy a žádný T-spoj v otvoru – i u klienta,
	# podvržený snímek nesmí postavit „dveře“ mimo stěnu.
	var oout := {}
	var ov: Variant = s.get("open", [])
	if typeof(ov) != TYPE_ARRAY or (ov as Array).size() > MAX_OPENINGS:
		return false
	# v4 (B4b): sedmý prvek = zámek; starší server posílá šest.
	var olen := 7 if int(s["v"]) >= 4 else 6
	var nlocked := 0
	for e in ov:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != olen:
			return false
		var lk := ""
		if olen == 7:
			if not valid_lock(e[6]):
				return false
			lk = String(e[6])
			if lk != "":
				nlocked += 1
				if typeof(e[2]) != TYPE_STRING or not is_door(String(e[2])) or nlocked > MAX_LOCKED:
					return false
		if not _is_int(e[0], 1, 1000000000) or oout.has(int(e[0])):
			return false
		if not _is_int(e[1], 1, 1000000000) or not wout.has(int(e[1])):
			return false
		if typeof(e[2]) != TYPE_STRING or not OPENINGS.has(String(e[2])) or not _is_int(e[3], 0, WALL_MAX_CELLS):
			return false
		if not _is_num(e[4], -1.0e12, 1.0e12) or not _is_int(e[5], 0, MAX_FUNDS):
			return false
		var ow: Dictionary = wout[int(e[1])]
		var cells := opening_cells(String(e[2]))
		var wl := _wall_len(int(ow["x0"]), int(ow["z0"]), int(ow["x1"]), int(ow["z1"]))
		if int(e[3]) < OPENING_EDGE or int(e[3]) + cells > wl - OPENING_EDGE:
			return false
		for owid in wout:
			if int(owid) == int(e[1]):
				continue
			var w2: Dictionary = wout[owid]
			if _on_span(ow, int(e[3]), cells, int(w2["x0"]), int(w2["z0"])) or _on_span(ow, int(e[3]), cells, int(w2["x1"]), int(w2["z1"])):
				return false
		for k in oout:
			var o2: Dictionary = oout[k]
			if int(o2["wid"]) != int(e[1]):
				continue
			var oa := int(o2["at"])
			var ob := oa + opening_cells(String(o2["kind"]))
			if int(e[3]) < ob + OPENING_GAP and oa < int(e[3]) + cells + OPENING_GAP:
				return false
		oout[int(e[0])] = {"oid": int(e[0]), "wid": int(e[1]), "kind": String(e[2]), "at": int(e[3]),
			"built_at": float(e[4]), "paid": int(e[5]), "lock": lk}
	items = out
	walls = wout
	openings = oout
	next_oid = 1
	for k in openings:
		next_oid = maxi(next_oid, int(k) + 1)
	next_wid = 1
	for k in walls:
		next_wid = maxi(next_wid, int(k) + 1)
	funds = int(s["funds"])
	revision = int(s["rev"])
	next_uid = 1
	for k in items:
		next_uid = maxi(next_uid, int(k) + 1)
	rebuild()
	return true
