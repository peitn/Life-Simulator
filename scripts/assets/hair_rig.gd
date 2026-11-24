extends RefCounted
## HairRig (C4b) – za běhu z geometrie HairBuilderu udělá síť, která se chová jako část postavy:
##  - zdroj: síť kůže hlavy a těla z character.glb (klidové polohy, normály, kosti, výchylky blend shapes),
##  - PŘENOS MORFŮ: každý vrchol vlasů = vážený průměr výchylek K nejbližších vrcholů kůže (hlava bez uší,
##    pod hlavou tělo) → blend shapes se stejnými jmény jako hlava/tělo; zůstanou jen klíče, které vlasy
##    opravdu posunou (> 0,1 mm). Vlasy tak sledují šířku a výšku hlavy, čelo, délku krku, tuk a svaly
##    (dlouhé vlasy na zádech i tvar zad a ramen),
##  - KOSTI: váhy z nejbližšího vrcholu kůže (hlava → kost hlavy vč. měřítka hlavy, záda → páteř),
##  - síť se postaví jednou na účes a sdílí ji všechny postavy (váhy blend shapes nastavuje SimVisual),
##    takže GLB se nemění a na všech peerech je síť stejná (deterministický HairBuilder).
## Materiál: shaders/hair.gdshader (make_material / apply).

const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const HairBuilder := preload("res://scripts/assets/hair_builder.gd")
const Res := preload("res://scripts/character/appearance_resolver.gd")

const SHADER_PATH := "res://shaders/hair.gdshader"
const K := 4
## Klíč se uloží, jen když posune nějaký vrchol vlasů aspoň o 0,3 mm.
const KEY_MIN := 0.0003
const HCELL := 0.02
const BCELL := 0.06
const QCELL := 0.004
const MAX_RING := 7

static var _src: Dictionary = {}
static var _ctx: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shader: Shader = null
## Statistiky posledních sestavení (testy, výkon): klíč → {"ms", "tris", "verts", "keys"}.
static var build_stats: Dictionary = {}
## Asynchronní stavba (hra, běh 17 – review Gemini): první sestavení účesu (0,25–1 s) běží ve WorkerThreadPool,
## postava mezitím ukazuje „helmu“ z GLB a karty se vymění, až je síť hotová. Ve vlákně se počítají jen pole
## (geometrie, přenos morfů, kosti); ArrayMesh vzniká na hlavním vlákně. Testy a --test běží synchronně.
static var async_build := false
static var _mutex := Mutex.new()
## klíč účesu → [WeakRef vlastníků], kteří čekají na dokončení (zároveň příznak „staví se“)
static var _waiters: Dictionary = {}
## klíč účesu → id úlohy WorkerThreadPool, na kterou se ještě nečekalo (každá úloha se musí vyzvednout
## právě jednou). QA 11/2026: úlohy se dřív nevyzvedávaly vůbec a ukončení hry s rozpracovanými nebo
## ještě nespuštěnými stavbami účesů zablokovalo proces při ukončování enginu (Godot 4.7.2).
static var _tasks: Dictionary = {}
## Generace cache: výsledek stavby spuštěné před clear_cache() se zahodí.
static var _gen := 0
## Nastavené po dobu wait_for_builds(): úlohy, které ještě nezačaly, skončí bez práce.
static var _cancel := false
static var _cancelled: Dictionary = {}
const _SELF := preload("res://scripts/assets/hair_rig.gd")


## Počká na rozpracované stavby účesů (ukončení hry, testy). Jen hlavní vlákno. Úlohy, které ještě
## nezačaly, se přeskočí (jejich účes se postaví znovu při příští žádosti); rozpracované doběhnou
## a jejich odložené _finish se provede v dalším snímku (pokud ještě nějaký bude).
static func wait_for_builds() -> void:
	_mutex.lock()
	var ids: Array = _tasks.values()
	_tasks.clear()
	_cancel = true
	_mutex.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))
	_mutex.lock()
	_cancel = false
	for key in _cancelled:
		_waiters.erase(key)
	_cancelled.clear()
	_mutex.unlock()


## Počet staveb, jejichž úloha ještě nebyla vyzvednuta (testy, diagnostika).
static func tasks_in_flight() -> int:
	_mutex.lock()
	var n := _tasks.size()
	_mutex.unlock()
	return n


static func clear_cache() -> void:
	wait_for_builds()
	_mutex.lock()
	_gen += 1
	_src = {}
	_ctx = {}
	_meshes = {}
	build_stats = {}
	_waiters = {}
	_mutex.unlock()


static func _mesh_arrays(mi: MeshInstance3D) -> Dictionary:
	var m := mi.mesh as ArrayMesh
	var a: Array = m.surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var keys := {}
	var bl: Array = m.surface_get_blend_shape_arrays(0)
	for i in m.get_blend_shape_count():
		var tv: PackedVector3Array = (bl[i] as Array)[Mesh.ARRAY_VERTEX]
		var d := PackedVector3Array()
		d.resize(pos.size())
		for j in pos.size():
			d[j] = tv[j] - pos[j]
		keys[String(m.get_blend_shape_name(i))] = d
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	return {"pos": pos, "nrm": a[Mesh.ARRAY_NORMAL], "idx": a[Mesh.ARRAY_INDEX], "bones": bones, "wts": wts,
		"stride": bones.size() / maxi(pos.size(), 1), "keys": keys}


## Zdroj z character.glb (jednou za běh hry). {} když model chybí (dedikovaný server, primitiva).
static func source() -> Dictionary:
	if not _src.is_empty():
		return _src
	var model := AssetLibrary.instantiate("character")
	if model == null:
		return {}
	var head: MeshInstance3D = null
	var body: MeshInstance3D = null
	var shirt: MeshInstance3D = null
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("head__") and nm.ends_with("__skin_body"):
			head = mi
		elif nm.begins_with("body__") and nm.ends_with("__skin_body"):
			body = mi
		elif nm.begins_with("body__") and nm.ends_with("__cloth_shirt"):
			shirt = mi
	if head == null or body == null:
		model.free()
		return {}
	var h := _mesh_arrays(head)
	var b := _mesh_arrays(body)
	var s: Dictionary = _mesh_arrays(shirt) if shirt != null else {"pos": PackedVector3Array()}
	model.free()
	# Uši: vrcholy, které hýbou klíče uší (ear_size, ear_angle_*) – kořeny ani přenos morfů z nich neberou.
	var hp: PackedVector3Array = h["pos"]
	var ear := PackedByteArray()
	ear.resize(hp.size())
	for k in h["keys"]:
		if String(k).begins_with("ear_"):
			var d: PackedVector3Array = h["keys"][k]
			for i in hp.size():
				if d[i].length() > 0.0002:
					ear[i] = 1
	_src = {"head": h, "body": b, "shirt": s, "ear": ear}
	return _src


## Kontext pro HairBuilder (kůže hlavy + kolizní mapy).
static func context() -> Dictionary:
	if not _ctx.is_empty():
		return _ctx
	var src := source()
	if src.is_empty():
		return {}
	var h: Dictionary = src["head"]
	_ctx = {"hp": h["pos"], "hn": h["nrm"], "hi": h["idx"], "ear": src["ear"],
		"hmap": HairBuilder.head_map(h["pos"]),
		"tmap": HairBuilder.torso_map([src["body"]["pos"], src["shirt"]["pos"]])}
	# prostorový hash trojúhelníků pro projekci (obočí, vousy) předem – vlákna kontext jen čtou
	HairBuilder._tri_hash(_ctx)
	# Mřížky kůže pro bind() předem (13. 11. 2026): dřív se stavěly při každém volání (~95 ms, i pro 674 vrcholů
	# proxy). Stejná data i pořadí → bitově stejné vazby; vlákna mřížky jen čtou.
	_ctx["bind_grids_0"] = _bind_grids(false)
	_ctx["bind_grids_1"] = _bind_grids(true)
	return _ctx


## Mřížky vrcholů kůže pro bind(): hustá hlava (HCELL, bez uší, bez obličeje pro face_ok = false) a řídké tělo
## (BCELL, nad 0,9 m) + dosah hlavy od HairBuilder.C.
static func _bind_grids(face_ok: bool) -> Dictionary:
	var src := source()
	var hp: PackedVector3Array = src["head"]["pos"]
	var bp: PackedVector3Array = src["body"]["pos"]
	var ear: PackedByteArray = src["ear"]
	var nh := hp.size()
	var gh := {}
	var gb := {}
	for i in nh + bp.size():
		if i < nh and ear[i] == 1:
			continue
		var p: Vector3 = hp[i] if i < nh else bp[i - nh]
		if i >= nh and p.y < 0.9:
			continue
		if i < nh and not face_ok and is_face(p):
			continue
		var cell := HCELL if i < nh else BCELL
		var g: Dictionary = gh if i < nh else gb
		var k := Vector3i(int(floor(p.x / cell)), int(floor(p.y / cell)), int(floor(p.z / cell)))
		if not g.has(k):
			g[k] = PackedInt32Array()
		var arr: PackedInt32Array = g[k]
		arr.append(i)
		g[k] = arr
	var head_reach := 0.0
	for p in hp:
		head_reach = maxf(head_reach, p.distance_to(HairBuilder.C))
	return {"gh": gh, "gb": gb, "reach": head_reach + 0.05}


## Geometrie části: part = "scalp" | "brows" | "beard".
static func geometry(part: String, style: String) -> Dictionary:
	var ctx := context()
	if ctx.is_empty():
		return {}
	match part:
		"brows":
			return HairBuilder.build_brows(ctx, style)
		"beard":
			return HairBuilder.build_beard(ctx, style)
		_:
			return HairBuilder.build(ctx, style)


## Sdílená síť části (null = účes bez geometrie, např. holá hlava, strniště, žádné vousy).
static func mesh_for(part: String, style: String) -> ArrayMesh:
	var key := part + ":" + style
	_mutex.lock()
	var has := _meshes.has(key)
	var cached: ArrayMesh = _meshes.get(key)
	_mutex.unlock()
	if has:
		return cached
	var t0 := Time.get_ticks_usec()
	return _store(key, build_pack(part, style), t0)


## Pole sítě části (bez ArrayMesh – lze počítat ve vlákně). {"tris", "verts"} a u neprázdné části i "arrays".
static func build_pack(part: String, style: String) -> Dictionary:
	var g := geometry(part, style)
	if g.is_empty() or (g["pos"] as PackedVector3Array).is_empty():
		return {"tris": 0, "verts": 0}
	var pack := _arrays_from(g, part != "scalp")
	pack["tris"] = HairBuilder.tri_count(g)
	pack["verts"] = (g["pos"] as PackedVector3Array).size()
	if part == "scalp":
		# C-LOD krok 2: proxy účesu pro dav vzniká ze stejné geometrie karet (ve stejném vlákně, ~10 ms navíc).
		var t1 := Time.get_ticks_usec()
		var pg := proxy_geometry(g, context())
		if not (pg["pos"] as PackedVector3Array).is_empty():
			var pp := _arrays_from(pg, false)
			pp["tris"] = HairBuilder.tri_count(pg)
			pp["verts"] = (pg["pos"] as PackedVector3Array).size()
			pp["ms"] = (Time.get_ticks_usec() - t1) / 1000.0
			pack["proxy"] = pp
		# C-LOD krok 3: proředěné karty pro stupeň 1 – z hotových polí karet (bez nové vazby na kůži).
		var t2 := Time.get_ticks_usec()
		var lp := lod1_pack(pack)
		lp["ms"] = (Time.get_ticks_usec() - t2) / 1000.0
		pack["lod1"] = lp
	elif part == "brows" or part == "beard":
		# C-LOD krok 5: stejný redukátor karet s přeškálovanou náhodou pramene (hustota v shaderu); bez úspory
		# LOD1_MIN_SAVING zůstává plná síť (stupeň 1 ji použije). Obrys podle FACIAL_LOD1_OUTLINE.
		var t3 := Time.get_ticks_usec()
		var fl := {"skip": "small", "tris": int(pack["tris"]), "full_tris": int(pack["tris"])}
		if int(pack["tris"]) >= FACIAL_LOD1_MIN_TRIS:
			fl = lod1_pack(pack, {"facial": true, "outline": bool(FACIAL_LOD1_OUTLINE.get(part, true)),
				"keep": float(FACIAL_LOD1_KEEP.get(part, -1.0)), "widen_full": true})
		fl["ms"] = (Time.get_ticks_usec() - t3) / 1000.0
		pack["lod1"] = fl
	return pack


## Uloží síť do cache (hlavní vlákno). Když ji mezitím postavil někdo jiný, vrátí tu dřívější (sdílení sítě).
static func _store(key: String, pack: Dictionary, t0: int) -> ArrayMesh:
	var m := mesh_from_pack(pack)
	# Skalp nese i proxy pro dav (klíč scalp_proxy:<styl>; null = účes bez geometrie, např. holá hlava).
	var pkey := ""
	var pm: ArrayMesh = null
	var pp: Dictionary = pack.get("proxy", {})
	var lkey := ""
	var lm: ArrayMesh = null
	var lpk: Dictionary = pack.get("lod1", {})
	if key.begins_with("brows:") or key.begins_with("beard:"):
		lkey = key.replace(":", FACIAL_LOD1_SUFFIX)
		lm = mesh_from_pack(lpk, "facial_hair_lod1")
	if key.begins_with("scalp:"):
		pkey = PROXY_PREFIX + key.substr(6)
		pm = mesh_from_pack(pp, "hair_proxy")
		# LOD1 karet (null = účes bez úspory nebo bez geometrie → stupeň 1 použije plné karty)
		lkey = LOD1_PREFIX + key.substr(6)
		lm = mesh_from_pack(lpk, "hair_cards_lod1")
	_mutex.lock()
	if _meshes.has(key):
		m = _meshes[key]
	else:
		_meshes[key] = m
		build_stats[key] = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "tris": int(pack.get("tris", 0)),
			"verts": int(pack.get("verts", 0)), "keys": m.get_blend_shape_count() if m != null else 0}
	if pkey != "" and not _meshes.has(pkey):
		_meshes[pkey] = pm
		build_stats[pkey] = {"ms": float(pp.get("ms", 0.0)), "tris": int(pp.get("tris", 0)),
			"verts": int(pp.get("verts", 0)), "keys": pm.get_blend_shape_count() if pm != null else 0}
	if lkey != "" and not _meshes.has(lkey):
		_meshes[lkey] = lm
		build_stats[lkey] = {"ms": float(lpk.get("ms", 0.0)), "tris": int(lpk.get("tris", 0)),
			"verts": int(lpk.get("verts", 0)), "keys": lm.get_blend_shape_count() if lm != null else 0,
			"cards_kept": int(lpk.get("cards_kept", 0)), "cards_total": int(lpk.get("cards_total", 0)),
			"outline_tris": int(lpk.get("outline_tris", 0)), "other_in": int(lpk.get("other_in", 0)),
			"other_out": int(lpk.get("other_out", 0)), "full_tris": int(lpk.get("full_tris", 0)),
			"skip": String(lpk.get("skip", "")), "tubes": int(lpk.get("tubes", 0)), "rings_in": int(lpk.get("rings_in", 0)),
			"rings_out": int(lpk.get("rings_out", 0)), "tube_err": float(lpk.get("tube_err", 0.0))}
	_mutex.unlock()
	return m


## Proxy účesu pro dav (C-LOD stupeň 2) – synchronně: když ještě není, postaví se s kartami skalpu.
## null = účes bez geometrie (holá hlava) nebo bez modelu.
static func proxy_mesh(style: String) -> ArrayMesh:
	var r := cached_proxy(style)
	if bool(r["ready"]):
		return r["mesh"]
	mesh_for("scalp", style)
	return cached_proxy(style)["mesh"]


## Proxy z cache bez stavby (SimVisual – nikdy neblokuje): {"ready": je v cache, "mesh": ArrayMesh nebo null}.
static func cached_proxy(style: String) -> Dictionary:
	var key := PROXY_PREFIX + style
	_mutex.lock()
	var has := _meshes.has(key)
	var m: ArrayMesh = _meshes.get(key)
	_mutex.unlock()
	return {"ready": has, "mesh": m}


## Síť pro vlastníka (SimVisual). Hotová (nebo synchronní režim) → {"ready": true, "mesh"}; jinak spustí stavbu
## ve vlákně a vrátí {"ready": false} – po dokončení zavolá owner._on_hair_mesh_ready(part, style) (je-li naživu).
static func request_mesh(part: String, style: String, owner: Object) -> Dictionary:
	var key := part + ":" + style
	_mutex.lock()
	if _meshes.has(key):
		var m: ArrayMesh = _meshes[key]
		_mutex.unlock()
		return {"ready": true, "mesh": m}
	_mutex.unlock()
	if not async_build or context().is_empty():
		return {"ready": true, "mesh": mesh_for(part, style)}
	_mutex.lock()
	var first := not _waiters.has(key)
	if first:
		_waiters[key] = []
	if owner != null:
		(_waiters[key] as Array).append(weakref(owner))
	var gen := _gen
	_mutex.unlock()
	if first:
		var id := WorkerThreadPool.add_task(Callable(_SELF, "_task").bind(part, style, Time.get_ticks_usec(), gen), false, "hair " + key)
		_mutex.lock()
		_tasks[key] = id
		_mutex.unlock()
	return {"ready": false, "mesh": null}


## Je stavba účesu rozběhnutá ve vlákně? (testy)
static func is_pending(part: String, style: String) -> bool:
	_mutex.lock()
	var r := _waiters.has(part + ":" + style)
	_mutex.unlock()
	return r


## Pracovní vlákno.
static func _task(part: String, style: String, t0: int, gen: int = 0) -> void:
	_mutex.lock()
	var skip := _cancel
	if skip:
		_cancelled[part + ":" + style] = true
	_mutex.unlock()
	if skip:
		return
	var pack := build_pack(part, style)
	Callable(_SELF, "_finish").call_deferred(part, style, pack, t0, gen)


## Hlavní vlákno.
static func _finish(part: String, style: String, pack: Dictionary, t0: int, gen: int = 0) -> void:
	var key := part + ":" + style
	_mutex.lock()
	var stale := gen != _gen
	var task_id := -1
	if not stale and _tasks.has(key):
		task_id = int(_tasks[key])
		_tasks.erase(key)
	_mutex.unlock()
	if task_id >= 0:
		# Tělo úlohy už skončilo (toto volání zařadila na svém konci), takže se nečeká.
		WorkerThreadPool.wait_for_task_completion(task_id)
	if stale:
		return  # cache byla mezitím vymazána; noví zájemci mají vlastní úlohu
	_store(key, pack, t0)
	_mutex.lock()
	var ws: Array = _waiters.get(key, [])
	_waiters.erase(key)
	_mutex.unlock()
	for w in ws:
		var o = (w as WeakRef).get_ref()
		if o != null and is_instance_valid(o) and o.has_method("_on_hair_mesh_ready"):
			o._on_hair_mesh_ready(part, style)


## Vazba vrcholů vlasů na K nejbližších vrcholů kůže (hlava bez uší + tělo). Vrací {"idx", "w"} (K na vrchol;
## index < počet vrcholů hlavy = hlava, jinak tělo). face_ok = false (vlasy na hlavě): obličej pod vlasovou
## linií se nepoužije – vlasy u tváří se váží na spánky a boky hlavy, ne na nos, rty a oči.
static func bind(pos: PackedVector3Array, face_ok := true) -> Dictionary:
	var src := source()
	var hp: PackedVector3Array = src["head"]["pos"]
	var bp: PackedVector3Array = src["body"]["pos"]
	var nh := hp.size()
	# Dvě mřížky: hustá hlava (HCELL) a řídké tělo (BCELL – kontrolní síť těla má vrcholy po ~4 cm);
	# předpočítané v context() (bez kontextu se postaví zde).
	var grids: Dictionary = _ctx.get("bind_grids_%d" % int(face_ok), {})
	if grids.is_empty():
		grids = _bind_grids(face_ok)
	var gh: Dictionary = grids["gh"]
	var gb: Dictionary = grids["gb"]
	var out_i := PackedInt32Array()
	var out_w := PackedFloat32Array()
	out_i.resize(pos.size() * K)
	out_w.resize(pos.size() * K)
	# Vrcholy ve stejné buňce QCELL sdílí vazbu (výchylky kůže jsou na 4 mm hladké).
	var memo := {}
	var head_reach: float = grids["reach"]
	for vi in pos.size():
		var qk := Vector3i(int(floor(pos[vi].x / QCELL)), int(floor(pos[vi].y / QCELL)), int(floor(pos[vi].z / QCELL)))
		if memo.has(qk):
			var src_vi: int = memo[qk]
			for j in K:
				out_i[vi * K + j] = out_i[src_vi * K + j]
				out_w[vi * K + j] = out_w[src_vi * K + j]
			continue
		memo[qk] = vi
		var p := (Vector3(qk) + Vector3(0.5, 0.5, 0.5)) * QCELL
		var bd: Array = []
		var bi: Array = []
		if p.distance_to(HairBuilder.C) < head_reach:
			_knn(gh, HCELL, hp, bp, nh, p, 3, bd, bi)
		if p.y < 1.66:
			_knn(gb, BCELL, hp, bp, nh, p, 2, bd, bi)
		if bd.is_empty():
			_knn(gh, HCELL, hp, bp, nh, p, MAX_RING, bd, bi)
		var tot := 0.0
		var ws := PackedFloat64Array()
		for j in bd.size():
			var w := 1.0 / (float(bd[j]) + 1e-6)
			ws.append(w)
			tot += w
		# nejbližší první (kosti se berou z něj)
		var order: Array = range(bd.size())
		order.sort_custom(func(a, b): return bd[a] < bd[b])
		for j in K:
			if j < order.size():
				out_i[vi * K + j] = bi[order[j]]
				out_w[vi * K + j] = ws[order[j]] / tot
			else:
				out_i[vi * K + j] = out_i[vi * K] if j > 0 else 0
				out_w[vi * K + j] = 0.0
	return {"idx": out_i, "w": out_w}


## K nejbližších z mřížky (prstence buněk, konec, když je K-tý kandidát blíž než prohledaný poloměr).
## Doplňuje bd (vzdálenosti²) a bi (indexy; Array = předání odkazem) – lze volat postupně pro víc mřížek.
static func _knn(grid: Dictionary, cell: float, hp: PackedVector3Array, bp: PackedVector3Array, nh: int, p: Vector3, max_ring: int, bd: Array, bi: Array) -> void:
	var k0 := Vector3i(int(floor(p.x / cell)), int(floor(p.y / cell)), int(floor(p.z / cell)))
	for ring in max_ring + 1:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				for dz in range(-ring, ring + 1):
					if maxi(absi(dx), maxi(absi(dy), absi(dz))) != ring:
						continue
					var arr = grid.get(k0 + Vector3i(dx, dy, dz))
					if arr == null:
						continue
					for si in (arr as PackedInt32Array):
						var q: Vector3 = hp[si] if si < nh else bp[si - nh]
						var d2 := float(p.distance_squared_to(q))
						if bd.size() < K:
							bd.append(d2)
							bi.append(si)
						else:
							var worst := 0
							for j in range(1, K):
								if bd[j] > bd[worst]:
									worst = j
							if d2 < bd[worst]:
								bd[worst] = d2
								bi[worst] = si
		if bd.size() >= K:
			var mx := 0.0
			for d in bd:
				mx = maxf(mx, d)
			if mx <= pow(ring * cell, 2.0):
				return


## Obličej pod vlasovou linií (vpředu a do stran až po kotlety).
static func is_face(p: Vector3) -> bool:
	var ae := HairBuilder.az_el(p)
	return absf(ae.x) < 76.0 and ae.y < HairBuilder.hairline_el(ae.x) - 2.0 and p.y > 1.50


## Síť z geometrie: přenos morfů (řídce – jen vrcholy kůže, které klíč opravdu hýbe), kosti, CUSTOM0.
## face_ok: vousy a obočí se váží i na obličej, vlasy na hlavě ne (viz bind).
static func build_mesh(g: Dictionary, face_ok := true) -> ArrayMesh:
	return mesh_from_pack(_arrays_from(g, face_ok))


static func mesh_from_pack(pack: Dictionary, res_name := "hair_cards") -> ArrayMesh:
	if not pack.has("arrays"):
		return null
	var am := ArrayMesh.new()
	am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for nm in pack["names"]:
		am.add_blend_shape(StringName(nm))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pack["arrays"], pack["blend"], {}, int(pack["flags"]))
	am.resource_name = res_name
	return am


# ======================================================================================
# Proxy účesu pro dav (C-LOD krok 2, běh main-claude-1794554507)
# ======================================================================================
## Radiální obálka karet kolem středu hlavy HairBuilder.C: sférická mřížka PROXY_NA azimutů × PROXY_NE
## elevací + 2 póly (1 344 trojúhelníků). Poloměr vrcholu = nejvzdálenější vrchol karet v jeho úhlové buňce
## (nejméně PROXY_OUT nad kůží); buňka bez vlasů s ≥ PROXY_FILL vlasatými sousedy (z 8) dostane jejich průměr
## (díry mezi pramínky), ostatní buňky bez vlasů se schovají PROXY_IN pod kůži hlavy (obličej, krk).
## Deterministické (jen geometrie karet a mapa hlavy) → stejná síť na všech peerech. Známé omezení:
## hvězdicová obálka vyplní mezery mezi visícími copánky/dredy a mezi culíkem a krkem (silueta je plnější
## než karty); rozhraní vlasy/obličej je rozmazané o ~půl buňky (~7 mm) – pro postavu < 6 % výšky obrazu
## pod rozlišením pixelu. Normály hladké, UV = (azimut, elevace), CUSTOM0 = (1, 0, 0, 0).
const PROXY_PREFIX := "scalp_proxy:"
const PROXY_NA := 32
const PROXY_NE := 21
const PROXY_IN := 0.004
const PROXY_OUT := 0.003
const PROXY_FILL := 5


static func proxy_geometry(g: Dictionary, ctx: Dictionary) -> Dictionary:
	var empty := {"pos": PackedVector3Array(), "nrm": PackedVector3Array(), "tan": PackedFloat32Array(),
		"uv": PackedVector2Array(), "c0": PackedFloat32Array(), "idx": PackedInt32Array()}
	var pos: PackedVector3Array = g.get("pos", PackedVector3Array())
	if pos.is_empty() or ctx.is_empty():
		return empty
	var na := PROXY_NA
	var ne := PROXY_NE
	var step := 180.0 / (ne + 1)
	var n := na * ne + 2
	var south := na * ne
	var north := na * ne + 1
	var r := PackedFloat32Array()
	r.resize(n)
	r.fill(-1.0)
	for p in pos:
		var q: Vector3 = p - HairBuilder.C
		var L := q.length()
		if L < 1e-5 or not is_finite(L):
			continue
		var el := rad_to_deg(asin(clampf(q.y / L, -1.0, 1.0)))
		var az := rad_to_deg(atan2(q.x, q.z))
		var j := int(round((el + 90.0) / step)) - 1
		var c: int
		if j < 0:
			c = south
		elif j > ne - 1:
			c = north
		else:
			c = j * na + (int(round((az + 180.0) / 360.0 * na)) % na)
		r[c] = maxf(r[c], L)
	var dirs := PackedVector3Array()
	dirs.resize(n)
	var uvs := PackedVector2Array()
	uvs.resize(n)
	for j in ne:
		var el := -90.0 + step * (j + 1)
		for i in na:
			var az := i * 360.0 / na - 180.0
			var e := deg_to_rad(el)
			var a := deg_to_rad(az)
			dirs[j * na + i] = Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
			uvs[j * na + i] = Vector2(float(i) / na, (el + 90.0) / 180.0)
	dirs[south] = Vector3.DOWN
	dirs[north] = Vector3.UP
	uvs[south] = Vector2(0.5, 0.0)
	uvs[north] = Vector2(0.5, 1.0)
	# díry mezi pramínky: prázdná buňka s převahou vlasatých sousedů dostane jejich průměr (jeden průchod)
	var filled := r.duplicate()
	for j in ne:
		for i in na:
			var c := j * na + i
			if r[c] >= 0.0:
				continue
			var s := 0.0
			var k := 0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var jj: int = j + dj
					if (dj == 0 and di == 0) or jj < 0 or jj >= ne:
						continue
					var cc: int = jj * na + (i + di + na) % na
					if r[cc] >= 0.0:
						s += r[cc]
						k += 1
			if k >= PROXY_FILL:
				filled[c] = s / k
	var hmap: PackedFloat32Array = ctx["hmap"]
	var vpos := PackedVector3Array()
	vpos.resize(n)
	for c in n:
		var hr := HairBuilder.head_r(hmap, dirs[c])
		var R: float = maxf(filled[c], hr + PROXY_OUT) if filled[c] >= 0.0 else maxf(hr - PROXY_IN, 0.01)
		vpos[c] = HairBuilder.C + dirs[c] * R
	var idx := PackedInt32Array()
	for j in ne - 1:
		for i in na:
			var a := j * na + i
			var b := j * na + (i + 1) % na
			var c := (j + 1) * na + i
			var d := (j + 1) * na + (i + 1) % na
			idx.append_array(PackedInt32Array([a, b, d, a, d, c]))
	for i in na:
		idx.append_array(PackedInt32Array([south, (i + 1) % na, i]))
		idx.append_array(PackedInt32Array([north, (ne - 1) * na + i, (ne - 1) * na + (i + 1) % na]))
	# Přední strana ven (od C) v konvenci Godotu: přední trojúhelník je PO směru hodinových ručiček, tj.
	# (b − a) × (c − a) míří DOVNITŘ (stejně jako síť hlavy z GLB). Render 13. 11. odhalil opačné pořadí –
	# vykresloval se vnitřek obálky. Hladké normály ven, vážené plochou.
	var nrm := PackedVector3Array()
	nrm.resize(n)
	for t in range(0, idx.size(), 3):
		var pa := vpos[idx[t]]
		var pb := vpos[idx[t + 1]]
		var pc := vpos[idx[t + 2]]
		var fn := (pb - pa).cross(pc - pa)
		if fn.dot((pa + pb + pc) / 3.0 - HairBuilder.C) > 0.0:
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
			fn = -fn
		for q in 3:
			nrm[idx[t + q]] -= fn
	var tan := PackedFloat32Array()
	var c0 := PackedFloat32Array()
	for c in n:
		var nn := nrm[c].normalized() if nrm[c].length_squared() > 1e-16 else dirs[c]
		nrm[c] = nn
		var tg := Vector3.UP.cross(nn)
		tg = tg.normalized() if tg.length_squared() > 1e-8 else Vector3.RIGHT
		tan.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, 1.0]))
		c0.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return {"pos": vpos, "nrm": nrm, "tan": tan, "uv": uvs, "c0": c0, "idx": idx}


## Pole sítě z geometrie (čistý výpočet, bez zdrojů enginu – bezpečné ve vlákně).
static func _arrays_from(g: Dictionary, face_ok := true) -> Dictionary:
	var src := source()
	var pos: PackedVector3Array = g["pos"]
	var n := pos.size()
	var bnd := bind(pos, face_ok)
	var bi: PackedInt32Array = bnd["idx"]
	var bw: PackedFloat32Array = bnd["w"]
	var h: Dictionary = src["head"]
	var b: Dictionary = src["body"]
	var nh: int = (h["pos"] as PackedVector3Array).size()
	# Inverzní vazba: vrchol kůže → (vrcholy vlasů, váhy).
	var inv_v := {}
	var inv_w := {}
	for i in bi.size():
		if bw[i] <= 0.0:
			continue
		var si := bi[i]
		if not inv_v.has(si):
			inv_v[si] = PackedInt32Array()
			inv_w[si] = PackedFloat32Array()
		var a: PackedInt32Array = inv_v[si]
		a.append(i / K)
		inv_v[si] = a
		var c: PackedFloat32Array = inv_w[si]
		c.append(bw[i])
		inv_w[si] = c
	# Klíče: sjednocení jmen hlavy a těla (pás švu hlavy nese klíče těla pod stejnými jmény).
	var names := {}
	for k in h["keys"]:
		names[k] = true
	for k in b["keys"]:
		names[k] = true
	var key_list: Array = names.keys()
	key_list.sort()
	var shape_names: Array = []
	var shapes: Array = []
	for key in key_list:
		var hd = h["keys"].get(key)
		var bd = b["keys"].get(key)
		var acc := PackedVector3Array()
		acc.resize(n)
		var touched := false
		for si in inv_v:
			var d: Vector3
			if si < nh:
				if hd == null:
					continue
				d = (hd as PackedVector3Array)[si]
			else:
				if bd == null:
					continue
				d = (bd as PackedVector3Array)[si - nh]
			if d.length_squared() < 1e-12:
				continue
			touched = true
			var vv: PackedInt32Array = inv_v[si]
			var ww: PackedFloat32Array = inv_w[si]
			for j in vv.size():
				acc[vv[j]] += d * ww[j]
		if not touched:
			continue
		var mx := 0.0
		for v in acc:
			mx = maxf(mx, v.length_squared())
		if sqrt(mx) < KEY_MIN:
			continue
		var tv := pos.duplicate()
		for vi in n:
			tv[vi] += acc[vi]
		shape_names.append(key)
		shapes.append(tv)
	# Kosti z nejbližšího vrcholu kůže.
	var stride: int = maxi(int(h["stride"]), int(b["stride"]))
	stride = 8 if stride > 4 else 4
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	bones.resize(n * stride)
	wts.resize(n * stride)
	for vi in n:
		var si := bi[vi * K]
		var m: Dictionary = h if si < nh else b
		var li := si if si < nh else si - nh
		var ms: int = m["stride"]
		var mb: PackedInt32Array = m["bones"]
		var mw: PackedFloat32Array = m["wts"]
		for j in stride:
			if j < ms and mb.size() > 0:
				bones[vi * stride + j] = mb[li * ms + j]
				wts[vi * stride + j] = mw[li * ms + j]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = g["nrm"]
	arrays[Mesh.ARRAY_TANGENT] = g["tan"]
	arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
	arrays[Mesh.ARRAY_CUSTOM0] = g["c0"]
	arrays[Mesh.ARRAY_INDEX] = g["idx"]
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if (b["bones"] as PackedInt32Array).size() > 0:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = wts
		if stride == 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var blend: Array = []
	for tv in shapes:
		var ba := []
		ba.resize(Mesh.ARRAY_MAX)
		ba[Mesh.ARRAY_VERTEX] = tv
		ba[Mesh.ARRAY_NORMAL] = g["nrm"]
		ba[Mesh.ARRAY_TANGENT] = g["tan"]
		blend.append(ba)
	return {"arrays": arrays, "blend": blend, "names": shape_names, "flags": flags}


# ======================================================================================
# Karty vlasů pro stupeň detailu 1 (C-LOD krok 3, běh main-claude-1794597706, 13. 11. 2026)
# ======================================================================================
## Stupeň 1 = postava ~5,5–20 % výšky obrazu: jednotlivé karty už nejsou rozlišitelné, ale silueta a krytí
## ano. LOD1 vzniká z HOTOVÝCH polí karet (_arrays_from), takže vazba na kůži, skin i přenesené klíče hlavy
## a těla jsou přesně stejné jako u plných karet – jen méně trojúhelníků a vrcholů:
##  1) karty (druh 0): ponechá se podíl podle vrstvy (c0.z: vnitřní LOD1_KEEP_INNER … vnější LOD1_KEEP_OUTER),
##     o kartě rozhoduje náhoda pramene c0.x (stejná pro celou kartu → karta zůstane celá, nebo zmizí celá);
##     ponechané karty se rozšíří o 1/√podíl (nejvýš LOD1_WIDEN_MAX) kolem osy pramene – v klidu i ve všech
##     cílech blend shapes –, aby krytí hlavy zůstalo podobné (kompenzace geometrií, ne shaderem: materiál
##     je stejný jako u plných karet, takže přepnutí nemění barvu);
##     OBRYS: segmenty karet, které sahají do LOD1_OUTLINE_EPS od nejvzdálenějšího vrcholu karet ve své buňce,
##     zůstanou VŽDY (bez rozšíření). Dvě mřížky: kulová kolem středu hlavy (LOD1_OUTLINE_NA × NE; temeno,
##     ofina) a válcová kolem svislé osy hlavy (azimut × výška po LOD1_OUTLINE_DY; vodorovný dosah visících
##     vlasů = obrys zepředu, z boku i shora). Náhodné proředění jinak trhalo obrys dlouhých vlasů (IoU 0,91–0,93;
##     s kulovou mřížkou 0,94–0,95 shora; s oběma viz tests/test_hair_lod1, měřeno 13. 11.);
##  2) afro (druh 4): vnější skořepina vždy, směrem dovnitř každá druhá (vnitřní jsou z dálky schované);
##  3) ostatní plochy (skořepina skalpu, drdol, gumička, afro): meshoptimizer (ImporterMesh.generate_lods)
##     na lokálně zkompaktované podmnožině, každý druh zvlášť; bere se nejhrubší úroveň s ≥ LOD1_SIMPLIFY_MIN
##     indexů, chybou ≤ LOD1_MAX_ERROR a skoro stejnou hranicí svařené sítě (LOD1_BORDER_TOL); skořepina skalpu
##     0,23 mm, afro 0,94 mm. ImporterMesh vzniká lokálně v pracovním vlákně, nesdílí se a generate_lods nesahá na
##     RenderingServer – souběh ověřuje tests/test_hair_lod1_tubes (Grok #527/2);
##  3b) trubice (copánky, dredy, cornrows – druhy 2 a 3): meshoptimizer je zplošťoval (copánky 13,8 mm, dredy 6 mm),
##     proto od C-LOD kroku 4 (17. 11.) vypouštění PRSTENCŮ po délce pramene se zachovaným průřezem – viz lod1_tubes();
##  4) výsledek je zkompaktovaný (jen použité vrcholy, ve vzestupném pořadí původních indexů → deterministické),
##     klíče mají stejná jména ve stejném pořadí jako plné karty (váhy instance se při výměně sítě zachovají);
##  5) když by úspora byla < LOD1_MIN_SAVING, LOD1 nevzniká (null) a stupeň 1 použije plné karty.
## Čistě klientská prezentace, nic se nereplikuje; ze stejných vstupů vzniká na všech peerech stejná síť.
const LOD1_PREFIX := "scalp_lod1:"
const LOD1_KEEP_INNER := 0.25
const LOD1_KEEP_OUTER := 0.6
const LOD1_OUTLINE_NA := 48
const LOD1_OUTLINE_NE := 32
const LOD1_OUTLINE_EPS := 0.002
const LOD1_OUTLINE_DY := 0.02
const LOD1_OUTLINE_Y0 := 0.9
const LOD1_OUTLINE_NY := 60
## Největší chyba zjednodušení (m, ImporterMesh lod size): 4 mm ≈ ½ pixelu postavy na nejbližší hranici stupně 1
## (20 % výšky obrazu 1080p ≈ 8,3 mm/px) a rozlišení CPU testu siluety.
const LOD1_MAX_ERROR := 0.004
const LOD1_WIDEN_MAX := 1.5
const LOD1_SIMPLIFY_MIN := 0.4
const LOD1_SIMPLIFY_MIN_TRIS := 400
const LOD1_MIN_SAVING := 0.2
## C-LOD krok 5: klíč cache LOD1 obočí/vousů = část + přípona + styl (brows_lod1:prirozene).
const FACIAL_LOD1_SUFFIX := "_lod1:"
## Ochrana obrysu u obličejových chlupů. Obočí leží 1–2 mm na kůži, siluetu tvoří hlava a obrysová mřížka kolem
## středu hlavy u něj označí skoro každou kartu (5 ze 6 stylů pak nemělo úsporu) → bez obrysu. Vousy (plnovous,
## licousy) mění profil obličeje → s obrysem. Měření v docs/reviews/facial-lod1-20261117.md.
const FACIAL_LOD1_OUTLINE := {"brows": false, "beard": true}
## Podíl ponechaných karet (pevný – karty obočí i vousů mají jedinou vrstvu 0,5; Gemini 17. 11.: explicitně, ne přes
## lod1_keep(c0.z), aby změna vrstvy v HairBuilderu tiše nezměnila LOD). Obočí 0,5, vousy 0,425 (= lod1_keep(0,5)).
const FACIAL_LOD1_KEEP := {"brows": 0.5, "beard": 0.425}
## Strop plného rozšíření obličejových karet (1/podíl): obočí 0,5 → 2,0×, vousy 0,425 → 2,35×.
const FACIAL_LOD1_WIDEN_MAX := 2.5
## Pod tolik trojúhelníků plné sítě se LOD1 obličeje nestaví (skip "small", stupeň 1 = plná síť): knír má 138 tr.,
## LOD1 by ušetřil 33 a z několika málo karet rozšířených 2,35× vycházelo krytí zepředu 1,34× LOD0.
const FACIAL_LOD1_MIN_TRIS := 300
## Kolik hraničních hran svařené sítě smí zjednodušení změnit (podíl). Vlasová linie a okraje skořepin nejsou
## šev k jiné síti (na rozdíl od krku/hlavy v CharacterLod), takže drobná změna okraje nevytvoří škvíru;
## měřeno 13. 11.: skořepina skalpu na 50 % mění 11 z 1 841 hran (0,6 %), trubice copánků 0.
const LOD1_BORDER_TOL := 0.01
const CharacterLod := preload("res://scripts/assets/character_lod.gd")


## Podíl ponechaných karet ve vrstvě (0 = nejvnitřnější, 1 = vnější).
static func lod1_keep(layer: float) -> float:
	return lerpf(LOD1_KEEP_INNER, LOD1_KEEP_OUTER, clampf(layer, 0.0, 1.0))


## Rozšíření ponechané karty pro daný podíl (krytí ~ počet × šířka; odmocnina = kompromis mezi krytím a hrubostí).
static func lod1_widen(keep: float) -> float:
	return clampf(1.0 / sqrt(maxf(keep, 0.01)), 1.0, LOD1_WIDEN_MAX)


## LOD1 z pole karet (výstup _arrays_from). {} = bez LOD1 (žádná geometrie nebo malá úspora).
## opts: "facial" (obočí/vousy) = u ponechaných karet přeškálovat náhodu pramene c0.x' = c0.x / podíl, protože shader
## obličejových chlupů skrývá karty s c0.x > density (hustota je per postava, síť per styl). Viditelné karty LOD1 jsou
## pak vnořenou podmnožinou LOD0 a poměr krytí je stejný pro každou hustotu (bez přeškálování by řídké obočí bylo
## v dálce hustší a husté řidší). "outline" (výchozí true) = chránit obrysové segmenty vypuštěných karet.
static func lod1_pack(pack: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not pack.has("arrays"):
		return {}
	var facial := bool(opts.get("facial", false))
	var use_outline := bool(opts.get("outline", true))
	# pevný podíl ponechaných karet (obočí/vousy mají jednu vrstvu 0,5); < 0 = podle vrstvy (lod1_keep)
	var keep_fixed := float(opts.get("keep", -1.0))
	# rozšíření ponechaných karet: "widen_full" = 1/podíl (krytí ≈ zachované; jen obličej, kde je karta v dálce < 1 px),
	# jinak lod1_widen (1/√podíl, strop LOD1_WIDEN_MAX – u skalpu by širší karty byly vidět jako hrubé pásy)
	var widen_full := bool(opts.get("widen_full", false))
	var a: Array = pack["arrays"]
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var n := pos.size()
	if n == 0 or idx.size() < 3 or c0.size() != n * 4 or uv.size() != n:
		return {}
	# --- afro: vrstvy skořepin od vnější (hodnota c0.z) → ponechat sudé pořadí od vnější
	var afro_layers := {}
	for t in range(0, idx.size(), 3):
		var v0 := idx[t]
		if int(roundf(c0[v0 * 4 + 3] * 8.0)) == HairBuilder.KIND_AFRO:
			afro_layers[snappedf(c0[v0 * 4 + 2], 0.0001)] = true
	var afro_sorted: Array = afro_layers.keys()
	afro_sorted.sort()
	afro_sorted.reverse()
	var afro_keep := {}
	for r in afro_sorted.size():
		if r % 2 == 0:
			afro_keep[afro_sorted[r]] = true
	# --- výběr trojúhelníků
	var kept := PackedInt32Array()
	var other_by_kind := {}
	var card_ids := {}
	var card_kept := {}
	var outline_tris := 0
	var outline := PackedByteArray()
	if use_outline:
		outline = _lod1_outline(pos, c0)
	else:
		outline.resize(n)
	var widen := PackedFloat32Array()
	widen.resize(n)
	widen.fill(1.0)
	# podíl ponechaných karet u vrcholů ponechané karty (1 = beze změny c0.x; jen pro facial)
	var rnd_scale := PackedFloat32Array()
	rnd_scale.resize(n)
	rnd_scale.fill(1.0)
	for t in range(0, idx.size(), 3):
		var v0 := idx[t]
		var kind := int(roundf(c0[v0 * 4 + 3] * 8.0))
		if kind == HairBuilder.KIND_CARD:
			# náhoda pramene + vrstva identifikují kartu (pro statistiku); rozhodnutí je per trojúhelník,
			# ale všechny vrcholy karty mají stejné c0 → celá karta stejně
			var cid := Vector2(c0[v0 * 4], c0[v0 * 4 + 2])
			card_ids[cid] = true
			var keep := keep_fixed if keep_fixed > 0.0 else lod1_keep(c0[v0 * 4 + 2])
			if c0[v0 * 4] < keep:
				card_kept[cid] = true
				kept.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
				var f := clampf(1.0 / maxf(keep, 0.01), 1.0, FACIAL_LOD1_WIDEN_MAX) if widen_full else lod1_widen(keep)
				for k in 3:
					widen[idx[t + k]] = f
					if facial:
						rnd_scale[idx[t + k]] = keep
			elif outline[idx[t]] == 1 or outline[idx[t + 1]] == 1 or outline[idx[t + 2]] == 1:
				# obrysový segment vypuštěné karty: zůstává, nerozšiřuje se
				outline_tris += 1
				kept.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
		elif kind != HairBuilder.KIND_AFRO or afro_keep.has(snappedf(c0[v0 * 4 + 2], 0.0001)):
			if not other_by_kind.has(kind):
				other_by_kind[kind] = PackedInt32Array()
			var arr: PackedInt32Array = other_by_kind[kind]
			arr.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
			other_by_kind[kind] = arr
	# Každý druh zvlášť (skořepina, trubice, afro…): hranice jednoho druhu nesmí zablokovat zjednodušení jiného.
	var other := PackedInt32Array()
	var other_in := 0
	var kinds: Array = other_by_kind.keys()
	kinds.sort()
	var tube_stats := {"tubes": 0, "rings_in": 0, "rings_out": 0, "err": 0.0}
	for kd in kinds:
		var sub: PackedInt32Array = other_by_kind[kd]
		other_in += sub.size() / 3
		if kd == HairBuilder.KIND_BRAID or kd == HairBuilder.KIND_LOC:
			# C-LOD krok 4: trubice copánků/dredů/cornrows – vypuštěné prstence (průřez zůstává celý)
			var tr := lod1_tubes(pos, sub)
			if not tr.is_empty():
				other.append_array(tr["idx"])
				tube_stats["tubes"] += int(tr["tubes"])
				tube_stats["rings_in"] += int(tr["rings_in"])
				tube_stats["rings_out"] += int(tr["rings_out"])
				tube_stats["err"] = maxf(float(tube_stats["err"]), float(tr["err"]))
				continue
		other.append_array(_lod1_simplify(pos, a[Mesh.ARRAY_NORMAL], uv, sub))
	var out_idx := kept.duplicate()
	out_idx.append_array(other)
	var tris := out_idx.size() / 3
	if tris == 0 or float(tris) > (1.0 - LOD1_MIN_SAVING) * float(idx.size() / 3):
		# bez LOD1 (stupeň 1 použije plné karty); statistika říká proč
		return {"skip": "min_saving", "tris": tris, "full_tris": idx.size() / 3, "cards_total": card_ids.size(),
			"cards_kept": card_kept.size(), "outline_tris": outline_tris, "other_in": other_in, "other_out": other.size() / 3,
			"tubes": tube_stats["tubes"], "rings_in": tube_stats["rings_in"], "rings_out": tube_stats["rings_out"],
			"tube_err": tube_stats["err"]}
	# --- kompakce: jen použité vrcholy ve vzestupném pořadí původních indexů
	var used := PackedByteArray()
	used.resize(n)
	for i in out_idx:
		used[i] = 1
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var order := PackedInt32Array()
	for i in n:
		if used[i] == 1:
			remap[i] = order.size()
			order.append(i)
	var m := order.size()
	# partner páru vrcholů karty (ribbon: sudý = levý okraj, uv.x 0; následující = pravý, uv.x 1)
	var partner := PackedInt32Array()
	partner.resize(n)
	partner.fill(-1)
	for i in n:
		if widen[i] <= 1.0:
			continue
		var j := i + 1 if uv[i].x < 0.5 else i - 1
		# Gemini 13. 11.: páry sousedí jen díky ribbon(); partner musí být druhý okraj STEJNÉ karty (stejné c0),
		# jinak se vrchol nerozšíří (bezpečné) místo táhnutí k cizímu vrcholu
		if j >= 0 and j < n and absf(uv[j].y - uv[i].y) < 1e-6 and absf(uv[j].x - uv[i].x) > 0.5 \
				and c0[j * 4] == c0[i * 4] and c0[j * 4 + 2] == c0[i * 4 + 2] and c0[j * 4 + 3] == c0[i * 4 + 3]:
			partner[i] = j
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var npos := PackedVector3Array()
	npos.resize(m)
	for k in m:
		npos[k] = _lod1_widened(pos, order[k], partner, widen)
	out[Mesh.ARRAY_VERTEX] = npos
	out[Mesh.ARRAY_NORMAL] = _lod1_take3(a[Mesh.ARRAY_NORMAL], order)
	out[Mesh.ARRAY_TANGENT] = _lod1_take_f(a[Mesh.ARRAY_TANGENT], order, 4)
	var nuv := PackedVector2Array()
	nuv.resize(m)
	for k in m:
		nuv[k] = uv[order[k]]
	out[Mesh.ARRAY_TEX_UV] = nuv
	var nc0 := _lod1_take_f(c0, order, 4)
	if facial:
		for k in m:
			var sc := rnd_scale[order[k]]
			if sc < 1.0:
				nc0[k * 4] = minf(nc0[k * 4] / sc, 0.9999)
	out[Mesh.ARRAY_CUSTOM0] = nc0
	var nidx := PackedInt32Array()
	nidx.resize(out_idx.size())
	for k in out_idx.size():
		nidx[k] = remap[out_idx[k]]
	out[Mesh.ARRAY_INDEX] = nidx
	if a[Mesh.ARRAY_BONES] != null and (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() > 0:
		var stride: int = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / n
		var nb := PackedInt32Array()
		nb.resize(m * stride)
		var nw := PackedFloat32Array()
		nw.resize(m * stride)
		var bo: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var wo: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		for k in m:
			for j in stride:
				nb[k * stride + j] = bo[order[k] * stride + j]
				nw[k * stride + j] = wo[order[k] * stride + j]
		out[Mesh.ARRAY_BONES] = nb
		out[Mesh.ARRAY_WEIGHTS] = nw
	var bnrm: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	var btan: PackedFloat32Array = out[Mesh.ARRAY_TANGENT]
	var blend: Array = []
	for ba in pack["blend"]:
		var tv: PackedVector3Array = (ba as Array)[Mesh.ARRAY_VERTEX]
		var ntv := PackedVector3Array()
		ntv.resize(m)
		for k in m:
			ntv[k] = _lod1_widened(tv, order[k], partner, widen)
		var nb2 := []
		nb2.resize(Mesh.ARRAY_MAX)
		nb2[Mesh.ARRAY_VERTEX] = ntv
		nb2[Mesh.ARRAY_NORMAL] = bnrm
		nb2[Mesh.ARRAY_TANGENT] = btan
		blend.append(nb2)
	return {"arrays": out, "blend": blend, "names": (pack["names"] as Array).duplicate(), "flags": int(pack["flags"]),
		"tris": tris, "verts": m, "cards_total": card_ids.size(), "cards_kept": card_kept.size(),
		"outline_tris": outline_tris, "other_in": other_in, "other_out": other.size() / 3, "full_tris": idx.size() / 3,
		"tubes": tube_stats["tubes"], "rings_in": tube_stats["rings_in"], "rings_out": tube_stats["rings_out"],
		"tube_err": tube_stats["err"], "facial": facial, "outline_used": use_outline}


## Obrysové vrcholy karet (1 = do LOD1_OUTLINE_EPS od nejvzdálenějšího vrcholu karet ve své úhlové buňce
## kolem HairBuilder.C). Deterministické: jen polohy a pevná mřížka.
static func _lod1_outline(pos: PackedVector3Array, c0: PackedFloat32Array) -> PackedByteArray:
	var n := pos.size()
	var out := PackedByteArray()
	out.resize(n)
	var cell := PackedInt32Array()
	cell.resize(n)
	cell.fill(-1)
	var rad := PackedFloat32Array()
	rad.resize(n)
	var cmax := PackedFloat32Array()
	cmax.resize(LOD1_OUTLINE_NA * LOD1_OUTLINE_NE)
	# válcová mřížka: azimut × výška, vodorovná vzdálenost od svislé osy hlavy
	var ccell := PackedInt32Array()
	ccell.resize(n)
	var hrad := PackedFloat32Array()
	hrad.resize(n)
	var hmax := PackedFloat32Array()
	hmax.resize(LOD1_OUTLINE_NA * LOD1_OUTLINE_NY)
	for i in n:
		if int(roundf(c0[i * 4 + 3] * 8.0)) != HairBuilder.KIND_CARD:
			continue
		var d := pos[i] - HairBuilder.C
		var r := d.length()
		var el := asin(clampf(d.y / maxf(r, 1e-6), -1.0, 1.0))
		var az := atan2(d.x, d.z)
		var ai := clampi(int((az + PI) / TAU * LOD1_OUTLINE_NA), 0, LOD1_OUTLINE_NA - 1)
		var c := clampi(int((el + PI * 0.5) / PI * LOD1_OUTLINE_NE), 0, LOD1_OUTLINE_NE - 1) * LOD1_OUTLINE_NA + ai
		cell[i] = c
		rad[i] = r
		cmax[c] = maxf(cmax[c], r)
		var yi := clampi(int((pos[i].y - LOD1_OUTLINE_Y0) / LOD1_OUTLINE_DY), 0, LOD1_OUTLINE_NY - 1)
		var cc := yi * LOD1_OUTLINE_NA + ai
		var h := Vector2(d.x, d.z).length()
		ccell[i] = cc
		hrad[i] = h
		hmax[cc] = maxf(hmax[cc], h)
	for i in n:
		if cell[i] >= 0 and (rad[i] >= cmax[cell[i]] - LOD1_OUTLINE_EPS or hrad[i] >= hmax[ccell[i]] - LOD1_OUTLINE_EPS):
			out[i] = 1
	return out


## Poloha vrcholu karty rozšířená kolem středu páru (bez partnera nebo bez rozšíření beze změny).
static func _lod1_widened(p: PackedVector3Array, i: int, partner: PackedInt32Array, widen: PackedFloat32Array) -> Vector3:
	var j := partner[i]
	if j < 0:
		return p[i]
	var mid := (p[i] + p[j]) * 0.5
	return mid + (p[i] - mid) * widen[i]


static func _lod1_take3(src: PackedVector3Array, order: PackedInt32Array) -> PackedVector3Array:
	var o := PackedVector3Array()
	o.resize(order.size())
	for k in order.size():
		o[k] = src[order[k]]
	return o


static func _lod1_take_f(src: PackedFloat32Array, order: PackedInt32Array, w: int) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(order.size() * w)
	for k in order.size():
		for j in w:
			o[k * w + j] = src[order[k] * w + j]
	return o


## Zjednodušení podmnožiny trojúhelníků (ostatní plochy) meshoptimizerem. Vrací indexy do PŮVODNÍCH vrcholů;
## při jakékoli pochybnosti (malá podmnožina, změna počtu vrcholů, jiná hranice) vrátí vstup beze změny.
static func _lod1_simplify(pos: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, sub: PackedInt32Array) -> PackedInt32Array:
	if sub.size() / 3 < LOD1_SIMPLIFY_MIN_TRIS:
		return sub
	var local := {}
	var order := PackedInt32Array()
	var lidx := PackedInt32Array()
	lidx.resize(sub.size())
	for k in sub.size():
		var g := sub[k]
		var l = local.get(g)
		if l == null:
			l = order.size()
			local[g] = l
			order.append(g)
		lidx[k] = int(l)
	var lp := PackedVector3Array()
	lp.resize(order.size())
	var ln := PackedVector3Array()
	ln.resize(order.size())
	var lu := PackedVector2Array()
	lu.resize(order.size())
	for k in order.size():
		lp[k] = pos[order[k]]
		ln[k] = nrm[order[k]]
		lu[k] = uv[order[k]]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = lp
	arr[Mesh.ARRAY_NORMAL] = ln
	arr[Mesh.ARRAY_TEX_UV] = lu
	arr[Mesh.ARRAY_INDEX] = lidx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(CharacterLod.NORMAL_MERGE_ANGLE, CharacterLod.NORMAL_SPLIT_ANGLE, [])
	var back := im.get_surface_arrays(0)
	if (back[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != lp.size():
		return sub
	var ids := CharacterLod._weld_ids(lp)
	var border := CharacterLod._border_edges(lidx, ids)
	var best := PackedInt32Array()
	var min_count := int(ceil(LOD1_SIMPLIFY_MIN * lidx.size()))
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		if li.size() < 3 or li.size() < min_count or im.get_surface_lod_size(0, l) > LOD1_MAX_ERROR \
				or border_change(border, li, ids) > LOD1_BORDER_TOL:
			break
		best = li
	if best.is_empty():
		return sub
	var outi := PackedInt32Array()
	outi.resize(best.size())
	for k in best.size():
		outi[k] = order[best[k]]
	return outi


## C-LOD krok 4 (běh main-claude-1794900129, 17. 11. 2026): trubice ve stupni 1.
## Meshoptimizer trubice zplošťoval (copánky 13,8 mm, dredy 6 mm – viz výše), proto zůstávaly celé a copánky/dredy
## neměly LOD1 vůbec. Grok #527 navrhl méně stran + větší poloměr; méně stran by ale u 5boké trubice copánku
## změnilo průřez (silueta zepředu). Zvolen druhý směr: průřez zůstává PŘESNĚ (stejné vrcholy prstenců),
## vypouští se jen prstence po délce pramene, kde je pramen téměř rovný – Douglas–Peucker po prstencích:
## každý vrchol vypuštěného prstence leží od lineární interpolace stejného vrcholu sousedních ponechaných
## prstenců (parametr podle délky osy) nejvýš LOD1_TUBE_MAX_ERROR. První a poslední prstenec a špička zůstávají.
## Žádné nové vrcholy → skin, vazba, klíče (blend shapes), UV a CUSTOM0 se jen převezmou (kompakce v lod1_pack).
## Struktura trubice se čte z indexů (vzor HairBuilder.tube: prstence po k+1 vrcholech, 2k trojúhelníků na
## segment, volitelná čepička k trojúhelníků ke špičce); rekonstrukce se porovná s originálem a při jakékoli
## odchylce vrátí {} → druh jde přes meshoptimizer jako dřív (bezpečný návrat ke staršímu chování).
const LOD1_TUBE_MAX_ERROR := 0.004
## Chyba je navíc omezená tloušťkou pramene: nejvýš LOD1_TUBE_REL_ERROR × průměrný poloměr trubice. Tenký copánek
## (r 2,8–4,6 mm) posunutý o celé 4 mm by v siluetě zepředu „ztratil“ objem (CPU test 4 mm: IoU 0,933 < 0,95,
## měřeno 17. 11.); s polovinou poloměru zůstane každý vypuštěný prstenec uvnitř původní tloušťky pramene.
const LOD1_TUBE_REL_ERROR := 0.5
const LOD1_TUBE_MAX_K := 32


## Parsování trubic z podmnožiny trojúhelníků jednoho druhu: [{"base", "k", "n", "cap"}] nebo [] (nesedí vzor).
static func lod1_tube_parse(sub: PackedInt32Array, nverts: int) -> Array:
	var out := []
	var t := 0
	var m := sub.size()
	while t < m:
		if t + 6 > m:
			return []
		var base := sub[t]
		var k := sub[t + 1] - base - 1
		if base < 0 or k < 3 or k > LOD1_TUBE_MAX_K or sub[t + 2] != base + 1:
			return []
		var n := 1
		while t + 6 * k <= m:
			var ok := true
			for j in k:
				var va := base + (n - 1) * (k + 1) + j
				var vc := va + k + 1
				var q := t + j * 6
				if sub[q] != va or sub[q + 1] != vc or sub[q + 2] != va + 1 or sub[q + 3] != va + 1 \
						or sub[q + 4] != vc or sub[q + 5] != vc + 1:
					ok = false
					break
			if not ok:
				break
			n += 1
			t += 6 * k
		if n < 2:
			return []
		var last := base + (n - 1) * (k + 1)
		var tip := last + k + 1
		var cap := false
		if t + 3 * k <= m and sub[t] == last and sub[t + 1] == tip and sub[t + 2] == last + 1:
			cap = true
			for j in k:
				var q := t + j * 3
				if sub[q] != last + j or sub[q + 1] != tip or sub[q + 2] != last + j + 1:
					return []
			t += 3 * k
		if (tip if cap else last + k) >= nverts:
			return []
		out.append({"base": base, "k": k, "n": n, "cap": cap})
	# kontrola: rekonstrukce = originál (bit po bitu)
	if lod1_tube_indices(out, []) != sub:
		return []
	return out


## Indexy trubic pro dané ponechané prstence (rings[i] = PackedInt32Array vzestupně; [] = všechny prstence).
static func lod1_tube_indices(tubes: Array, rings: Array) -> PackedInt32Array:
	var o := PackedInt32Array()
	for ti in tubes.size():
		var tb: Dictionary = tubes[ti]
		var base: int = tb["base"]
		var k: int = tb["k"]
		var n: int = tb["n"]
		var kr := PackedInt32Array()
		if rings.is_empty():
			for i in n:
				kr.append(i)
		else:
			kr = rings[ti]
		for r in range(kr.size() - 1):
			var a0 := base + kr[r] * (k + 1)
			var b0 := base + kr[r + 1] * (k + 1)
			for j in k:
				o.append_array(PackedInt32Array([a0 + j, b0 + j, a0 + j + 1, a0 + j + 1, b0 + j, b0 + j + 1]))
		if bool(tb["cap"]):
			var last := base + (n - 1) * (k + 1)
			var tip := last + k + 1
			for j in k:
				o.append_array(PackedInt32Array([last + j, tip, last + j + 1]))
	return o


## Ponechané prstence jedné trubice (Douglas–Peucker po vrcholech prstenců) a největší chyba vypuštěných.
static func lod1_tube_rings(pos: PackedVector3Array, base: int, k: int, n: int, tol: float) -> Dictionary:
	# parametr podél osy = délka lomené čáry středů prstenců
	# a průměrný poloměr trubice (vzdálenost vrcholů od středu prstence) → mez chyby relativně k tloušťce
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := Vector3.ZERO
	var rsum := 0.0
	for i in n:
		var c := Vector3.ZERO
		for j in k:
			c += pos[base + i * (k + 1) + j]
		c /= float(k)
		s[i] = 0.0 if i == 0 else s[i - 1] + c.distance_to(prev)
		prev = c
		for j in k:
			rsum += pos[base + i * (k + 1) + j].distance_to(c)
	var rmean := rsum / float(n * k)
	tol = minf(tol, LOD1_TUBE_REL_ERROR * rmean)
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack := [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		if seg.y - seg.x < 2:
			continue
		var worst := -1
		var werr := -1.0
		for i in range(seg.x + 1, seg.y):
			var e := _lod1_ring_err(pos, base, k, seg.x, i, seg.y, s)
			if e > werr:
				werr = e
				worst = i
		if werr > tol:
			keep[worst] = 1
			stack.append(Vector2i(worst, seg.y))
			stack.append(Vector2i(seg.x, worst))
	var kr := PackedInt32Array()
	for i in n:
		if keep[i] == 1:
			kr.append(i)
	# skutečná největší chyba vypuštěných prstenců vůči výsledku
	var err := 0.0
	for r in range(kr.size() - 1):
		for i in range(kr[r] + 1, kr[r + 1]):
			err = maxf(err, _lod1_ring_err(pos, base, k, kr[r], i, kr[r + 1], s))
	return {"rings": kr, "err": err, "tol": tol, "r": rmean}


static func _lod1_ring_err(pos: PackedVector3Array, base: int, k: int, a: int, i: int, b: int, s: PackedFloat32Array) -> float:
	var t := 0.5 if s[b] - s[a] <= 1e-9 else (s[i] - s[a]) / (s[b] - s[a])
	var e := 0.0
	for j in k + 1:
		var pa := pos[base + a * (k + 1) + j]
		var pb := pos[base + b * (k + 1) + j]
		e = maxf(e, pos[base + i * (k + 1) + j].distance_to(pa.lerp(pb, t)))
	return e


## LOD1 trubic jednoho druhu: {"idx", "tubes", "rings_in", "rings_out", "err"} nebo {} (nesedí struktura).
static func lod1_tubes(pos: PackedVector3Array, sub: PackedInt32Array) -> Dictionary:
	var tubes := lod1_tube_parse(sub, pos.size())
	if tubes.is_empty():
		return {}
	var rings := []
	var rin := 0
	var rout := 0
	var err := 0.0
	for tb in tubes:
		var r := lod1_tube_rings(pos, int(tb["base"]), int(tb["k"]), int(tb["n"]), LOD1_TUBE_MAX_ERROR)
		rings.append(r["rings"])
		rin += int(tb["n"])
		rout += (r["rings"] as PackedInt32Array).size()
		err = maxf(err, float(r["err"]))
	return {"idx": lod1_tube_indices(tubes, rings), "tubes": tubes.size(), "rings_in": rin, "rings_out": rout, "err": err}


## Podíl hraničních hran, které se zjednodušením změnily (chybějící + nové) vůči počtu původních.
static func border_change(border: Dictionary, idx: PackedInt32Array, ids: PackedInt32Array) -> float:
	var b2 := CharacterLod._border_edges(idx, ids)
	var diff := 0
	for k in border:
		if not b2.has(k):
			diff += 1
	for k in b2:
		if not border.has(k):
			diff += 1
	return float(diff) / maxf(float(border.size()), 1.0)


## LOD1 karet z cache bez stavby (SimVisual – nikdy neblokuje): {"ready", "mesh"} (mesh null = bez LOD1).
static func cached_lod1(style: String) -> Dictionary:
	var key := LOD1_PREFIX + style
	_mutex.lock()
	var has := _meshes.has(key)
	var m: ArrayMesh = _meshes.get(key)
	_mutex.unlock()
	return {"ready": has, "mesh": m}


## LOD1 karet synchronně (testy, nástroje): když ještě není, postaví se s kartami skalpu.
static func lod1_mesh(style: String) -> ArrayMesh:
	var r := cached_lod1(style)
	if bool(r["ready"]):
		return r["mesh"]
	mesh_for("scalp", style)
	return cached_lod1(style)["mesh"]


## LOD1 obočí/vousů z cache bez stavby (SimVisual – nikdy neblokuje): {"ready", "mesh"}; mesh null = bez LOD1
## (styl bez geometrie nebo malá úspora → stupeň 1 použije plnou síť). Jiná část než brows/beard: ready true, mesh null.
static func cached_facial_lod1(part: String, style: String) -> Dictionary:
	if part != "brows" and part != "beard":
		return {"ready": true, "mesh": null}
	var key := part + FACIAL_LOD1_SUFFIX + style
	_mutex.lock()
	var has := _meshes.has(key)
	var m: ArrayMesh = _meshes.get(key)
	_mutex.unlock()
	return {"ready": has, "mesh": m}


## LOD1 obočí/vousů synchronně (testy, nástroje). null = použít plnou síť; LOD0 nikdy nenahrazuje.
static func facial_lod1_mesh(part: String, style: String) -> ArrayMesh:
	var r := cached_facial_lod1(part, style)
	if bool(r["ready"]):
		return r["mesh"]
	mesh_for(part, style)
	return cached_facial_lod1(part, style)["mesh"]

# ======================================================================================
# Materiál
# ======================================================================================
static func shader() -> Shader:
	if _shader == null and ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH)
	return _shader


static func make_material() -> ShaderMaterial:
	var sh := shader()
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## Parametry materiálu z výstupu AppearanceResolveru. part: scalp | brows | beard. Vrací počet parametrů.
static func apply(mat: ShaderMaterial, lp: Dictionary, part: String) -> int:
	if mat == null:
		return 0
	var hv: Dictionary = lp.get("hair_look", {})
	var base: Color = hv.get("natural", Color(0.3, 0.2, 0.12))
	var grey := float(hv.get("grey", 0.0))
	var density := 1.0
	var hairline := float(hv.get("hairline", 0.0))
	if part == "brows":
		base = hv.get("brow", base)
		grey = float(hv.get("brow_grey", grey * 0.6))
		density = float(hv.get("brow_density", 0.6))
		hairline = 0.0
	elif part == "beard":
		base = hv.get("facial", base)
		grey = float(hv.get("facial_grey", grey))
		density = float(hv.get("facial_density", 0.6))
		hairline = 0.0
	var lin := base.srgb_to_linear()
	mat.set_shader_parameter("hair_color", Vector3(lin.r, lin.g, lin.b))
	mat.set_shader_parameter("grey", grey)
	mat.set_shader_parameter("hairline", hairline)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("fine", 1.0 if part == "scalp" else 0.0)
	return 5
