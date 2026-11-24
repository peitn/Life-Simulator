extends RefCounted
## LodBake (C-LOD krok 6, 18. 11. 2026) – zapečení blend shapes do statické sítě pro stupeň 2 (dav).
##
## Proč: postava ve stupni 2 má mimiku zmrazenou a tvar se nemění, ale GPU přesto každý snímek přepočítává
## všechny nenulové blend shapes (skinning zneplatní výsledek). Náhodná postava jich má aktivních desítky:
## hlava ~45 klíčů × 6 350 vrcholů, oči, řasy, proxy účesu, tělo i oblečení. Zapečená síť nese tytéž
## polohy, normály a tečny jako výstup skinovacího shaderu Godotu, ale žádné blend shapes – zbude jen skinning.
##
## Vzorec = servers/rendering/renderer_rd/shaders/skeleton.glsl (krok 7, 18. 11. večer – dřív jen NORMALIZED):
##   NORMALIZED: v = base + Σ w·(cíl − base),  n = normalize(n + Σ w·(n_cíl − n))      (absolutní cíle)
##   RELATIVE:   v = base + Σ w·cíl,           n = normalize(n + Σ w·n_cíl)            (delta cíle)
## Normály a tečny cílů jsou v Godotu uložené oktaedricky, tj. vždy jednotkové – i „nulová delta“ v režimu
## RELATIVE se čte jako (0, 0, −1) a shader ji přičte. LodBake pracuje s daty přečtenými ze sítě
## (surface_get_blend_shape_arrays dekóduje stejně jako shader), takže výsledek odpovídá GPU v obou režimech.
##
## Zachová se vše ostatní: UV, kosti a váhy, CUSTOM0 (klidové polohy pro shader kůže), barvy, indexy,
## automatické LOD indexy (CharacterLod), materiály a jména ploch, formát (komprese, vlastní kanály).
##
## Postup (SimVisual):
## 1) hlavní vlákno: `raw_of(mesh)` – C++ kopie polí, jen pro síť, která ještě nemá zdroj v cache,
## 2) vlákno (`run_job`): `build_source(raw)` – řídké delty klíčů (jen vrcholy, kterými klíč hýbe) – jednou
##    na zdrojovou síť; `bake(source, váhy)` – statická ArrayMesh,
## 3) hlavní vlákno: výměna sítě instance, pokud se mezitím nezměnila síť ani váhy.
## Čistě prezentace klienta – nic se nereplikuje a simulace o zapečení neví.

## |váha| pod touto hodnotou se neaplikuje.
const EPS_W := 0.00001
## Kvadrát délky delty, pod kterým vrchol do řídkého klíče nepatří (≈ 1 µm u poloh).
const EPS_D := 1e-12

static var enabled := true
## false = pečení synchronně na hlavním vlákně (testy, diagnostika).
static var async := true
static var _src := {}      # instance_id zdrojové sítě -> [WeakRef(síť), zdroj]
static var _baked := {}    # "id:hash vah" -> [WeakRef(zdroj), WeakRef(zapečená síť), PackedFloat32Array váhy]
static var _stores := 0    # po kolika zápisech se pročistí mrtvé záznamy (Gemini 18. 11.)
static var sources_built := 0
static var meshes_baked := 0
static var cache_hits := 0
static var last_job_ms := 0.0


# ======================================================================================
# Hlavní vlákno: surová data, cache
# ======================================================================================

## Surová data sítě (hlavní vlákno). Pro síť bez blend shapes nebo jiné primitivum vrací {}.
static func raw_of(m: ArrayMesh) -> Dictionary:
	if m == null or m.get_blend_shape_count() == 0:
		return {}
	var surfs: Array = []
	for s in m.get_surface_count():
		surfs.append({
			"arrays": m.surface_get_arrays(s),
			"blends": m.surface_get_blend_shape_arrays(s),
			"format": m.surface_get_format(s),
			"lods": rs_lods(m, s),
			"primitive": m.surface_get_primitive_type(s),
			"material": m.surface_get_material(s),
			"name": m.surface_get_name(s),
		})
	return {"surfaces": surfs, "shape_count": m.get_blend_shape_count(), "custom_aabb": m.custom_aabb,
		"resource_name": String(m.resource_name),
		"relative": m.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE}


## LOD indexy plochy z RenderingServeru (velikost hrany -> indexy), aby zapečená síť měla stejné úrovně.
static func rs_lods(m: Mesh, surface: int) -> Dictionary:
	var out := {}
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), surface)
	var main: PackedByteArray = sd.get("index_data", PackedByteArray())
	var cnt := int(sd.get("index_count", 0))
	if cnt <= 0:
		return out
	var elem := main.size() / cnt
	if elem != 2 and elem != 4:
		return out
	for lod in sd.get("lods", []):
		var b: PackedByteArray = lod.get("index_data", PackedByteArray())
		var n := b.size() / elem
		var idx := PackedInt32Array()
		idx.resize(n)
		if elem == 2:
			for i in n:
				idx[i] = b.decode_u16(i * 2)
		else:
			for i in n:
				idx[i] = b.decode_u32(i * 4)
		if n >= 3:
			out[float(lod.get("edge_length", 0.0))] = idx
	return out


static func source_cached(m: Mesh):
	if m == null:
		return null
	var e = _src.get(m.get_instance_id())
	if e == null:
		return null
	if (e[0] as WeakRef).get_ref() != m:
		_src.erase(m.get_instance_id())
		return null
	return e[1]


static func store_source(m: Mesh, src: Dictionary) -> void:
	if m == null or src.is_empty():
		return
	_prune()
	_src[m.get_instance_id()] = [weakref(m), src]


static func _key(m: Mesh, w: PackedFloat32Array) -> String:
	return "%d:%d" % [m.get_instance_id(), hash(w)]


## Už zapečená síť pro stejný zdroj a přesně stejné váhy (sdílení mezi postavami), jinak null.
static func baked_cached(m: Mesh, w: PackedFloat32Array) -> ArrayMesh:
	if m == null:
		return null
	var e = _baked.get(_key(m, w))
	if e == null:
		return null
	var hit = (e[1] as WeakRef).get_ref()
	if (e[0] as WeakRef).get_ref() != m or hit == null or e[2] != w:
		_baked.erase(_key(m, w))
		return null
	cache_hits += 1
	return hit


static func store_baked(m: Mesh, w: PackedFloat32Array, baked: ArrayMesh) -> void:
	if m == null or baked == null:
		return
	# Zapečené sítě zanikají s každým odchodem postavy ze stupně 2 → mrtvé záznamy pročistit průběžně,
	# jinak by se cache v dlouhé hře jen plnila (Gemini 18. 11.).
	_stores += 1
	if _stores % 32 == 0:
		_prune()
	_baked[_key(m, w)] = [weakref(m), weakref(baked), w]


## Odstraní záznamy, jejichž síť už neexistuje.
static func _prune() -> void:
	for k in _src.keys():
		if (_src[k][0] as WeakRef).get_ref() == null:
			_src.erase(k)
	for k in _baked.keys():
		var e: Array = _baked[k]
		if (e[0] as WeakRef).get_ref() == null or (e[1] as WeakRef).get_ref() == null:
			_baked.erase(k)


static func cache_sizes() -> Vector2i:
	return Vector2i(_src.size(), _baked.size())


static func clear_cache() -> void:
	_src = {}
	_baked = {}


## Synchronní zapečení (hlavní vlákno; testy a nástroje).
static func bake_now(m: ArrayMesh, w: PackedFloat32Array) -> ArrayMesh:
	if m == null or m.get_blend_shape_count() == 0:
		return null
	var src = source_cached(m)
	if src == null:
		src = build_source(raw_of(m))
		store_source(m, src)
		sources_built += 1
	var out := bake(src, w)
	if out != null:
		meshes_baked += 1
	return out


## Statistika po dokončené úloze (hlavní vlákno – statické čítače se ve vlákně nepíšou).
static func note_job(job: Dictionary) -> void:
	for it in job.get("items", []):
		if bool(it.get("built", false)):
			sources_built += 1
		if it.get("baked") != null:
			meshes_baked += 1
	last_job_ms = float(job.get("ms", 0.0))


# ======================================================================================
# Vlákno: řídké delty a pečení (bez přístupu ke scéně)
# ======================================================================================

## Řídké delty klíčů: pro každý klíč [indexy vrcholů, Δpoloha, Δnormála, Δtečna(xyz)] jen tam, kde se něco mění.
## NORMALIZED: Δ = cíl − base. RELATIVE: Δ = cíl (normála/tečna cíle je jednotková a shader ji přičítá vždy,
## takže v tomto režimu jsou v klíči všechny vrcholy, kde je normála/tečna přítomná).
static func build_source(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var rel := bool(raw.get("relative", false))
	var surfs: Array = []
	for sraw in raw["surfaces"]:
		var arrays: Array = sraw["arrays"]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm = arrays[Mesh.ARRAY_NORMAL]
		var tan = arrays[Mesh.ARRAY_TANGENT]
		var has_n := nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == pos.size()
		var has_t := tan is PackedFloat32Array and (tan as PackedFloat32Array).size() == pos.size() * 4
		var shapes: Array = []
		for bs in sraw["blends"]:
			var bp: PackedVector3Array = bs[Mesh.ARRAY_VERTEX] if bs[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
			var bn = bs[Mesh.ARRAY_NORMAL]
			var bt = bs[Mesh.ARRAY_TANGENT]
			var sn := has_n and bn is PackedVector3Array and (bn as PackedVector3Array).size() == pos.size()
			var st := has_t and bt is PackedFloat32Array and (bt as PackedFloat32Array).size() == pos.size() * 4
			var idx := PackedInt32Array()
			var dp := PackedVector3Array()
			var dn := PackedVector3Array()
			var dt := PackedVector3Array()
			if bp.size() == pos.size():
				for i in pos.size():
					var d: Vector3 = bp[i] if rel else bp[i] - pos[i]
					var e := d.length_squared() > EPS_D
					var vn := Vector3.ZERO
					var vt := Vector3.ZERO
					if sn:
						vn = bn[i] if rel else bn[i] - nrm[i]
						e = e or vn.length_squared() > EPS_D
					if st:
						if rel:
							vt = Vector3(bt[i * 4], bt[i * 4 + 1], bt[i * 4 + 2])
						else:
							vt = Vector3(bt[i * 4] - tan[i * 4], bt[i * 4 + 1] - tan[i * 4 + 1], bt[i * 4 + 2] - tan[i * 4 + 2])
						e = e or vt.length_squared() > EPS_D
					if e:
						idx.append(i)
						dp.append(d)
						if sn:
							dn.append(vn)
						if st:
							dt.append(vt)
			shapes.append([idx, dp, dn, dt])
		surfs.append({"arrays": arrays, "format": sraw["format"], "lods": sraw["lods"], "primitive": sraw["primitive"],
			"material": sraw["material"], "name": sraw["name"], "shapes": shapes})
	return {"surfaces": surfs, "shape_count": raw["shape_count"], "custom_aabb": raw["custom_aabb"],
		"resource_name": raw["resource_name"], "relative": rel}


## Statická síť s aplikovanými vahami (bez blend shapes). Bezpečné ve vlákně (nová ArrayMesh, žádná scéna).
## Vzorec v obou režimech: v = base + Σ w·Δ, n = normalize(n + Σ w·Δn) (Δ podle build_source).
static func bake(src: Dictionary, w: PackedFloat32Array) -> ArrayMesh:
	if src.is_empty():
		return null
	var out := ArrayMesh.new()
	for surf in src["surfaces"]:
		# Mělká kopie pole ploch; packed pole jsou v Godotu 4 předávaná ODKAZEM – měněná pole se musí zkopírovat,
		# jinak by pečení přepsalo sdílený zdroj (a každé další pečení by stavělo na už posunutém tvaru).
		var arrays: Array = (surf["arrays"] as Array).duplicate()
		var pos: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var base_n = arrays[Mesh.ARRAY_NORMAL]
		var has_n := base_n is PackedVector3Array and (base_n as PackedVector3Array).size() == pos.size()
		var tan = arrays[Mesh.ARRAY_TANGENT]
		var has_t := tan is PackedFloat32Array and (tan as PackedFloat32Array).size() == pos.size() * 4
		var nrm := PackedVector3Array()
		var tg := PackedFloat32Array()
		if has_n:
			nrm = (base_n as PackedVector3Array).duplicate()
		if has_t:
			tg = (tan as PackedFloat32Array).duplicate()
		var touched := PackedByteArray()
		touched.resize(pos.size())
		var shapes: Array = surf["shapes"]
		for k in mini(w.size(), shapes.size()):
			var wk := w[k]
			if absf(wk) < EPS_W or not is_finite(wk):
				continue
			var sh: Array = shapes[k]
			var idx: PackedInt32Array = sh[0]
			var dp: PackedVector3Array = sh[1]
			var dn: PackedVector3Array = sh[2]
			var dt: PackedVector3Array = sh[3]
			var un := has_n and dn.size() == idx.size()
			var ut := has_t and dt.size() == idx.size()
			for j in idx.size():
				var i := idx[j]
				pos[i] += dp[j] * wk
				touched[i] = 1
				if un:
					nrm[i] += dn[j] * wk
				if ut:
					var o := i * 4
					var d: Vector3 = dt[j] * wk
					tg[o] += d.x
					tg[o + 1] += d.y
					tg[o + 2] += d.z
		if has_n or has_t:
			var bn: PackedVector3Array = base_n if has_n else PackedVector3Array()
			var bt: PackedFloat32Array = tan if has_t else PackedFloat32Array()
			for i in pos.size():
				if touched[i] == 0:
					continue
				if has_n:
					var l := nrm[i].length()
					nrm[i] = nrm[i] / l if l > 1e-8 else bn[i]
				if has_t:
					var o := i * 4
					var tv := Vector3(tg[o], tg[o + 1], tg[o + 2])
					var lt := tv.length()
					if lt > 1e-8:
						tv /= lt
					else:
						tv = Vector3(bt[o], bt[o + 1], bt[o + 2])
					tg[o] = tv.x
					tg[o + 1] = tv.y
					tg[o + 2] = tv.z
		arrays[Mesh.ARRAY_VERTEX] = pos
		if has_n:
			arrays[Mesh.ARRAY_NORMAL] = nrm
		if has_t:
			arrays[Mesh.ARRAY_TANGENT] = tg
		var s := out.get_surface_count()
		out.add_surface_from_arrays(int(surf["primitive"]), arrays, [], surf["lods"], int(surf["format"]))
		if out.get_surface_count() == s:
			return null   # formát odmítnut – raději bez zapečení než rozbitá síť
		if surf["material"] != null:
			out.surface_set_material(s, surf["material"])
		out.surface_set_name(s, String(surf["name"]))
	out.custom_aabb = src["custom_aabb"]
	out.resource_name = String(src["resource_name"]) + "_baked"
	return out


## Úloha pro WorkerThreadPool: položky {mesh, w, src|null, raw} → doplní src (built=true) a baked.
static func run_job(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	for it in job["items"]:
		if it["src"] == null:
			it["src"] = build_source(it["raw"])
			it["raw"] = null
			it["built"] = true
		it["baked"] = bake(it["src"], it["w"])
	job["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
