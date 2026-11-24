extends RefCounted
## B3 (22. 11. 2026): chůze postav kolem STAVĚNÝCH stěn parcely.
##
## Není to obecný navmesh. Postava dál chodí rovně (a kolem jídelního stolu přes DiningDetour) – LotNav zasáhne
## jen tehdy, když přímou úsečku k cíli protne postavená stěna (LotGrid.walls). Pak:
##   1. začátek a cíl se přichytí na nejbližší průchozí buňku, na kterou je z bodu vidět (stěna mezi nimi není);
##   2. LotPathfinder najde nejkratší 4-sousedskou cestu po buňkách (stěny blokují hrany, nábytek a zdi domu buňky);
##   3. cesta se vyhladí („string pulling“): z kotvy se jde k nejvzdálenějšímu středu buňky, na který je vidět –
##      viditelnost = úsečka neprotne nafouknutou stěnu a všechny vzorky leží v průchozích buňkách;
##   4. každý snímek se vrací nejvzdálenější viditelný roh (z prvních LOOKAHEAD).
## Výsledek next_point(): {"mode", "point"}; mode:
##   "direct" – stěna nepřekáží, jdi k cíli (beze změny proti dřívějšímu chování);
##   "route"  – jdi k vrácenému rohu;
##   "none"   – cíl je od postavy odříznutý stěnami → volající akci přeruší (nikdy neprochází zdí);
##   "escape" – postava sama stojí v uzavřeném prostoru bez spojení s ulicí (starý save, chyba) → smí projít,
##              jinak by uvízla navždy. Stavění nových stěn kolem postav brání main.lot_apply_action (traps_sim).
## B4 (23. 11. 2026): stěna s dveřmi se skládá z plných úseků (LotGrid.wall_segments) – rozsah dveří je volný,
## hrany v něm neblokují ani pathfinder. Okna se chovají jako plná zeď.
## B4b (24. 11. 2026): zamčené dveře. Volající (SimAgent) nastaví lot.nav_viewer = klíč postavy jen na dobu
## next_point; zamčené dveře bez klíče jsou pak pro tuto postavu plná zeď (úseky, pathfinder, BFS). Když cíl
## není dosažitelný, lock_blocker() zjistí, čí zámek cestu zavřel (pro sociální důsledky v SimAgent).
## Čisté a deterministické: stejný stav parcely a polohy = stejná trasa na serveru i v testech.
## Běží jen tam, kde běží simulace postav (autorita / offline).

const Pathfinder := preload("res://scripts/world/lot_pathfinder.gd")

## Odstup od osy stěny pro viditelnost (polovina tloušťky 0,06 m + rezerva). Středy buněk u stěny jsou 0,125 m.
const CLEAR := 0.1
## Kolik buněk kolem bodu se hledá průchozí buňka pro přichycení (8 × 0,25 m = 2 m).
const SNAP_RADIUS := 8
## Kolik dalších rohů se každý snímek zkouší (nejvzdálenější viditelný vyhrává).
const LOOKAHEAD := 6
## Krok vzorkování úsečky při kontrole průchozích buněk (čtvrt buňky).
const SAMPLE := 0.0625


# ---------------------------------------------------------------- geometrie

## Protne úsečka a→b obdélník r (otevřený vnitřek)? Slab clipping jako DiningDetour.
static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var lo := 0.0
	var hi := 1.0
	for axis in 2:
		var pos: float = a[axis]
		var v: float = d[axis]
		var lower: float = r.position[axis]
		var upper: float = r.end[axis]
		if absf(v) <= 0.000001:
			if pos <= lower or pos >= upper:
				return false
		else:
			var t0 := (lower - pos) / v
			var t1 := (upper - pos) / v
			if t0 > t1:
				var tmp := t0
				t0 = t1
				t1 = tmp
			lo = maxf(lo, t0)
			hi = minf(hi, t1)
			if lo >= hi:
				return false
	return lo < hi and hi > 0.0 and lo < 1.0


## Obdélník úseku stěny p→q nafouknutý o pad na všechny strany (ve světě x, z).
static func _seg_rect(p: Vector2, q: Vector2, pad: float) -> Rect2:
	var lo := Vector2(minf(p.x, q.x), minf(p.y, q.y))
	var hi := Vector2(maxf(p.x, q.x), maxf(p.y, q.y))
	return Rect2(lo, hi - lo).grow(pad)


## Překáží postavená stěna na úsečce a→b? Každý plný úsek stěny (bez dveří) je nafouknutý o CLEAR; když už bod a
## leží v nafouknutém pásu (postava stojí těsně u zdi nebo v zárubni), počítá se jen skutečné překročení osy
## úseku – jinak by od zdi nemohla odejít.
static func walls_block(lot: RefCounted, a: Vector2, b: Vector2) -> bool:
	for wid in lot.walls:
		for seg in lot.wall_segments(lot.walls[wid]):
			var r := _seg_rect(seg[0], seg[1], CLEAR)
			if r.has_point(a):
				if Geometry2D.segment_intersects_segment(a, b, seg[0], seg[1]) != null:
					return true
				continue
			if _segment_hits_rect(a, b, r):
				return true
	return false


## Leží všechny vzorky úsečky (kromě buňky startu a cíle) v průchozích buňkách parcely?
static func _cells_clear(lot: RefCounted, a: Vector2, b: Vector2) -> bool:
	var ca: Vector2i = lot.cell_of_world(a)
	var cb: Vector2i = lot.cell_of_world(b)
	var steps := maxi(1, int(ceil(a.distance_to(b) / SAMPLE)))
	for i in range(1, steps):
		var c: Vector2i = lot.cell_of_world(a.lerp(b, float(i) / float(steps)))
		if c == ca or c == cb:
			continue
		if not lot._in_grid(c.x, c.y):
			continue  # mimo parcelu (ulice) je volno
		if not lot._walkable(lot._idx(c.x, c.y)):
			return false
	return true


## Viditelnost pro vyhlazení trasy: ani stěna, ani neprůchozí buňka.
static func visible(lot: RefCounted, a: Vector2, b: Vector2) -> bool:
	return not walls_block(lot, a, b) and _cells_clear(lot, a, b)


static func cell_center(lot: RefCounted, c: Vector2i) -> Vector2:
	return lot.origin + (Vector2(c) + Vector2(0.5, 0.5)) * lot.CELL


## Nejbližší průchozí buňka, na jejíž střed je z bodu p vidět přes stěny. (-1, -1) = žádná v SNAP_RADIUS.
## Bod mimo parcelu se nejdřív promítne na okraj mřížky. Pořadí prohledávání je pevné → deterministické.
static func snap_cell(lot: RefCounted, p: Vector2) -> Vector2i:
	var g: Vector2i = lot.cell_of_world(p)
	g = Vector2i(clampi(g.x, 0, lot.gw - 1), clampi(g.y, 0, lot.gh - 1))
	var best := Vector2i(-1, -1)
	var best_d := INF
	for rad in SNAP_RADIUS + 1:
		for z in range(g.y - rad, g.y + rad + 1):
			for x in range(g.x - rad, g.x + rad + 1):
				if maxi(absi(x - g.x), absi(z - g.y)) != rad or not lot._in_grid(x, z):
					continue
				if not lot._walkable(lot._idx(x, z)):
					continue
				var c := cell_center(lot, Vector2i(x, z))
				var dd := p.distance_squared_to(c)
				if dd < best_d and not walls_block(lot, p, c):
					best_d = dd
					best = Vector2i(x, z)
		# Na dalším prstenci už je každá buňka dál než nejbližší nalezená ve vzdálenosti ≤ (rad + 1) buněk.
		if best.x >= 0 and sqrt(best_d) <= float(rad) * lot.CELL:
			break
	return best


# ---------------------------------------------------------------- plánování

## Celá trasa z a do b: {"mode": "route"|"none"|"escape", "pts": Array[Vector2]} – pts končí bodem b.
static func plan(lot: RefCounted, a: Vector2, b: Vector2) -> Dictionary:
	var sc := snap_cell(lot, a)
	var gc := snap_cell(lot, b)
	if sc.x < 0:
		return {"mode": "escape", "pts": []}
	if gc.x < 0:
		return {"mode": "none", "pts": []}
	var cells: Array[Vector2i] = Pathfinder.find_path(lot, sc, gc)
	if cells.is_empty():
		# Odříznutý je cíl, nebo postava? Postava bez spojení s ulicí smí uniknout (žádný softlock).
		var reach: PackedByteArray = lot._reach_before()
		if reach[lot._idx(sc.x, sc.y)] == 0:
			return {"mode": "escape", "pts": []}
		return {"mode": "none", "pts": []}
	var centers: Array = []
	for c in cells:
		centers.append(cell_center(lot, c))
	centers.append(b)
	# Dopředné vyhlazení: od kotvy po řadě, dokud je vidět; vezme se poslední viditelný. O(n · stěny).
	var pts: Array = []
	var anchor := a
	var i := -1
	while i < centers.size() - 1:
		var j := i + 1
		while j + 1 < centers.size() and visible(lot, anchor, centers[j + 1]):
			j += 1
		pts.append(centers[j])
		anchor = centers[j]
		i = j
	return {"mode": "route", "pts": pts}


## Další bod chůze. cache = slovník patřící postavě (trasa se nepočítá každý snímek).
static func next_point(lot: RefCounted, start: Vector3, goal: Vector3, cache: Dictionary) -> Dictionary:
	if lot == null or lot.walls.is_empty() or lot.gw <= 0 or lot.gh <= 0:
		_forget(cache)
		return {"mode": "direct", "point": goal}
	var a := Vector2(start.x, start.z)
	var b := Vector2(goal.x, goal.z)
	if not walls_block(lot, a, b):
		_forget(cache)
		return {"mode": "direct", "point": goal}
	# Klíč: rozložení parcely + buňka cíle (pohyblivý cíl – druhá postava – nepřepočítává trasu každý snímek).
	var gcell: Vector2i = lot.cell_of_world(b)
	var key := "%d|%d|%d|%d|%s" % [lot.revision, lot._layout_serial, gcell.x, gcell.y, lot._view_key()]
	if String(cache.get("key", "")) != key:
		_replan(lot, a, b, key, cache)
	var mode := String(cache.get("mode", "none"))
	if mode == "escape":
		return {"mode": "escape", "point": goal}
	if mode != "route":
		return {"mode": "none", "point": start}
	var pts: Array = cache["pts"]
	pts[pts.size() - 1] = b
	var best := _farthest_visible(lot, a, pts)
	# Stojí na rohu a dál není vidět (pohyblivý cíl se v buňce posunul za ochranný pás zdi) → jinak by uvízla.
	var stuck := best == 0 and pts.size() > 1 and a.distance_squared_to(pts[0]) < 0.0025
	if best < 0 or stuck:
		# Postavu něco odsunulo z trasy (sociální přistoupení, póza) nebo uvízla → jednou přeplánovat z aktuální polohy.
		_replan(lot, a, b, key, cache)
		mode = String(cache.get("mode", "none"))
		if mode == "escape":
			return {"mode": "escape", "point": goal}
		if mode != "route":
			return {"mode": "none", "point": start}
		pts = cache["pts"]
		best = maxi(_farthest_visible(lot, a, pts), 0)
	for k in best:
		pts.pop_front()
	var p: Vector2 = pts[0]
	return {"mode": "route", "point": Vector3(p.x, goal.y, p.y)}


static func _replan(lot: RefCounted, a: Vector2, b: Vector2, key: String, cache: Dictionary) -> void:
	var res := plan(lot, a, b)
	_forget(cache)
	cache["key"] = key
	cache["mode"] = res["mode"]
	cache["pts"] = res["pts"]
	cache["plans"] = int(cache.get("plans", 0)) + 1


## B4b: postava `who` se z a do b nedostane – je to kvůli zámku? Vrací klíč zámku dveří, jejichž odemčení by
## cestu otevřelo ("*" = zamčeno pro všechny, jméno uzlu = osobní zámek), nebo "" (zeď, nábytek, žádný zámek).
## Zkouší dveře po jedněch (vzestupně oid); když je potřeba odemknout víc dveří najednou, vrátí první z nich.
## Pohled parcely (nav_viewer, _nav_unlock) vrátí do původního stavu.
static func lock_blocker(lot: RefCounted, who: String, a: Vector2, b: Vector2) -> String:
	if lot == null or who == "" or lot.gw <= 0 or lot.gh <= 0:
		return ""
	var locked: Array = lot.locked_against(who)
	if locked.is_empty():
		return ""
	var saved_v: String = lot.nav_viewer
	var saved_u: int = lot._nav_unlock
	var out := ""
	lot.nav_viewer = who
	lot._nav_unlock = 0
	var sc := snap_cell(lot, a)
	var gc := snap_cell(lot, b)
	# Cesta s aktuálními zámky existuje → zámek není důvod (blokuje něco jiného, nebo nic).
	if sc.x >= 0 and gc.x >= 0 and Pathfinder.find_path(lot, sc, gc).is_empty():
		for oid in locked:
			lot._nav_unlock = int(oid)
			if not Pathfinder.find_path(lot, sc, gc).is_empty():
				out = lot.lock_of(int(oid))
				break
		if out == "":
			# Víc zamčených dveří za sebou: bez zámků cesta vede → první zámek je viník.
			lot._nav_unlock = 0
			lot.nav_viewer = ""
			var sc2 := snap_cell(lot, a)
			var gc2 := snap_cell(lot, b)
			if sc2.x >= 0 and gc2.x >= 0 and not Pathfinder.find_path(lot, sc2, gc2).is_empty():
				out = lot.lock_of(int(locked[0]))
	lot.nav_viewer = saved_v
	lot._nav_unlock = saved_u
	lot._build_edges({})
	return out


## Zapomene trasu, ale nechá čítač plánování (diagnostika a testy výkonu).
static func _forget(cache: Dictionary) -> void:
	cache.erase("key")
	cache.erase("mode")
	cache.erase("pts")


static func _farthest_visible(lot: RefCounted, a: Vector2, pts: Array) -> int:
	var best := -1
	for i in mini(pts.size(), LOOKAHEAD):
		if visible(lot, a, pts[i]):
			best = i
	return best
