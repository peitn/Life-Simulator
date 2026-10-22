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
const _SELF := preload("res://scripts/assets/hair_rig.gd")


static func clear_cache() -> void:
	_mutex.lock()
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
	return _ctx


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
	return pack


## Uloží síť do cache (hlavní vlákno). Když ji mezitím postavil někdo jiný, vrátí tu dřívější (sdílení sítě).
static func _store(key: String, pack: Dictionary, t0: int) -> ArrayMesh:
	var m := mesh_from_pack(pack)
	_mutex.lock()
	if _meshes.has(key):
		m = _meshes[key]
	else:
		_meshes[key] = m
		build_stats[key] = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "tris": int(pack.get("tris", 0)),
			"verts": int(pack.get("verts", 0)), "keys": m.get_blend_shape_count() if m != null else 0}
	_mutex.unlock()
	return m


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
	_mutex.unlock()
	if first:
		WorkerThreadPool.add_task(Callable(_SELF, "_task").bind(part, style, Time.get_ticks_usec()), false, "hair " + key)
	return {"ready": false, "mesh": null}


## Je stavba účesu rozběhnutá ve vlákně? (testy)
static func is_pending(part: String, style: String) -> bool:
	_mutex.lock()
	var r := _waiters.has(part + ":" + style)
	_mutex.unlock()
	return r


static func _task(part: String, style: String, t0: int) -> void:
	var pack := build_pack(part, style)
	Callable(_SELF, "_finish").call_deferred(part, style, pack, t0)


static func _finish(part: String, style: String, pack: Dictionary, t0: int) -> void:
	var key := part + ":" + style
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
	var ear: PackedByteArray = src["ear"]
	var nh := hp.size()
	# Dvě mřížky: hustá hlava (HCELL) a řídké tělo (BCELL – kontrolní síť těla má vrcholy po ~4 cm).
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
	var out_i := PackedInt32Array()
	var out_w := PackedFloat32Array()
	out_i.resize(pos.size() * K)
	out_w.resize(pos.size() * K)
	# Vrcholy ve stejné buňce QCELL sdílí vazbu (výchylky kůže jsou na 4 mm hladké).
	var memo := {}
	var head_reach := 0.0
	for p in hp:
		head_reach = maxf(head_reach, p.distance_to(HairBuilder.C))
	head_reach += 0.05
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


static func mesh_from_pack(pack: Dictionary) -> ArrayMesh:
	if not pack.has("arrays"):
		return null
	var am := ArrayMesh.new()
	am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for nm in pack["names"]:
		am.add_blend_shape(StringName(nm))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pack["arrays"], pack["blend"], {}, int(pack["flags"]))
	am.resource_name = "hair_cards"
	return am


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
