extends RefCounted
## CharacterLod (C-LOD, 12. 11. 2026) – úrovně detailu postav pro dav.
##
## Dvě nezávislé vrstvy:
## 1) GEOMETRIE: `with_lods(mesh)` doplní k ArrayMesh automatické indexové LOD (ImporterMesh.generate_lods,
##    meshoptimizer). LOD sdílí vrcholy s originálem, takže blend shapes (tvar obličeje, mimika), skinning
##    i vlastní pole (CUSTOM0 = klidové polohy pro shader kůže) fungují beze změny; Godot vybírá úroveň sám
##    podle chyby v pixelech na obrazovce. LOD, která by změnila hranici sítě (šev krk/hlava, okraje očí,
##    rtů a úst), se zahodí i se všemi hrubšími – jinak by v dálce vznikly škvíry mezi díly.
##    Výsledek je v cache (jedna LOD síť na zdrojovou síť, sdílená všemi postavami).
## 2) STUPEŇ DETAILU POSTAVY (`tier_for`): 0 = vše, 1 = mimika řidčeji a drobné části tváře bez stínu,
##    2 = vlasové karty nahradí nízkopolygonová „helma“ z GLB (barevně sladěná, viz SimVisual), mimika
##    zmrazená v neutrálu, vnitřek úst skrytý. Rozhoduje podíl výšky postavy na výšce obrazu (nezávislé
##    na rozlišení i zoomu kamery), s hysterezí proti blikání na hranici. Čistě prezentace klienta –
##    nic se nereplikuje a simulace o stupni neví.

## Podíl výšky obrazu (výška postavy / viditelná výška ve vzdálenosti postavy), pod kterým nastává stupeň 1 / 2.
## Kamera hry (FOV 50°, výchozí 18 m): postava ≈ 0,107 výšky obrazu → stupeň 1; stupeň 2 od ≈ 35 m.
const T1_FRACTION := 0.20
const T2_FRACTION := 0.055
## Návrat k vyššímu detailu až při podílu o 15 % větším než hranice (hystereze).
const HYSTERESIS := 1.15
## Výška postavy pro výpočet podílu (m). Nezávisí na skutečné výšce postavy – stupeň je o čitelnosti tváře.
const REF_HEIGHT := 1.8
## Násobič podílu podle nastavení „Detail postav v davu“ (0 nízký, 1 střední, 2 vysoký).
const DETAIL_SCALE := [0.6, 1.0, 1.6]
## Interval mimiky ve stupni 1 (s) – 10 Hz stačí na mrknutí i řeč u obličeje o pár desítkách pixelů.
const T1_EXPR_INTERVAL := 0.1
## Jak často postava přepočítává stupeň (s); fáze se rozkládá podle instance, aby se nepočítaly všechny naráz.
const CHECK_INTERVAL := 0.25

## Sítě s méně trojúhelníky nemá smysl zjednodušovat (oči, zuby, jazyk – jsou malé a levné).
const MIN_TRIS := 600
## Úhel slučování normál pro zjednodušení (stupně) – jako výchozí import Godotu.
const NORMAL_MERGE_ANGLE := 60.0
const NORMAL_SPLIT_ANGLE := 25.0
## Kvantizace poloh při svařování švů UV/normál při kontrole hranice (m).
const WELD := 0.00001

static var enabled := true
static var _cache := {}            # instance_id zdroje -> [WeakRef(zdroj), WeakRef(výsledná síť)]
static var generated := 0          # kolik sítí dostalo LOD (testy, diagnostika)
static var rejected_lods := 0      # kolik úrovní se zahodilo kvůli hranici
static var last_ms := 0.0          # čas poslední generace (ms)


# ======================================================================================
# Stupeň detailu
# ======================================================================================

## Podíl výšky obrazu, který zabírá postava výšky REF_HEIGHT ve vzdálenosti `distance` (perspektiva, svislé FOV).
static func screen_fraction(distance: float, fov_deg: float) -> float:
	if not is_finite(distance) or not is_finite(fov_deg) or distance <= 0.0:
		return INF
	var half := deg_to_rad(clampf(fov_deg, 1.0, 179.0)) * 0.5
	return REF_HEIGHT / (2.0 * distance * tan(half))


## Podíl pro ortografickou kameru (size = viditelná výška v metrech).
static func ortho_fraction(size: float) -> float:
	if not is_finite(size) or size <= 0.0:
		return INF
	return REF_HEIGHT / size


## Podíl z kamery a bodu ve světě; INF = blízko / neznámo (→ plný detail).
static func camera_fraction(cam: Camera3D, world_pos: Vector3) -> float:
	if cam == null:
		return INF
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return ortho_fraction(cam.size)
	# hloubka podél osy pohledu, ne přímá vzdálenost: na okraji obrazu je postava stejně velká jako uprostřed
	var to := world_pos - cam.global_position
	var depth := to.dot(-cam.global_transform.basis.z.normalized())
	if depth <= 0.0:
		depth = to.length()   # za kamerou (není vidět) – rozhodne prostá vzdálenost
	return screen_fraction(depth, cam.fov)


static func detail_scale(level: int) -> float:
	return float(DETAIL_SCALE[clampi(level, 0, DETAIL_SCALE.size() - 1)])


## Stupeň detailu z podílu výšky obrazu. Vzdalování přepíná hned na hranici, přibližování až s hysterezí.
static func tier_for(fraction: float, current: int, scale := 1.0) -> int:
	if is_nan(fraction) or fraction == INF:
		return 0
	var f := fraction * maxf(scale, 0.01)
	var raw := 0 if f >= T1_FRACTION else (1 if f >= T2_FRACTION else 2)
	var cur := clampi(current, 0, 2)
	if raw >= cur:
		return raw
	var up := 0 if f >= T1_FRACTION * HYSTERESIS else (1 if f >= T2_FRACTION * HYSTERESIS else 2)
	return mini(cur, up)


# ======================================================================================
# Geometrie
# ======================================================================================

## Má síť už nějaké LOD? (RenderingServer – ArrayMesh to jinak neprozradí)
static func lod_count(mesh: Mesh, surface := 0) -> int:
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return 0
	var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	return (sd.get("lods", []) as Array).size()


## Počty trojúhelníků LOD dané plochy (od nejjemnější), pro testy a diagnostiku.
static func lod_triangle_counts(mesh: Mesh, surface := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return out
	var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	# velikost indexu (2 nebo 4 bajty) podle hlavního indexového bufferu plochy
	var main_bytes: PackedByteArray = sd.get("index_data", PackedByteArray())
	var main_count := int(sd.get("index_count", 0))
	var elem := 2 if main_count <= 0 else maxi(main_bytes.size() / main_count, 1)
	for lod in sd.get("lods", []):
		var bytes: PackedByteArray = lod.get("index_data", PackedByteArray())
		out.append(bytes.size() / elem / 3)
	return out


## Kopie sítě s automatickými LOD (nebo zdroj beze změny, když se nehodí). Výsledek je v cache.
static func with_lods(src: Mesh, min_tris := MIN_TRIS) -> Mesh:
	if not enabled or not (src is ArrayMesh):
		return src
	var am := src as ArrayMesh
	var key := am.get_instance_id()
	if _cache.has(key):
		var entry: Array = _cache[key]
		var hit = (entry[1] as WeakRef).get_ref()
		if (entry[0] as WeakRef).get_ref() == am and hit != null:
			return hit
		_cache.erase(key)
	_prune()
	var out := _build(am, min_tris)
	# Cache drží jen slabé odkazy (zdroj i výsledek): LOD síť žije, dokud ji drží scéna/instance;
	# po uvolnění všech postav se uvolní i ona (Gemini 12. 11.: silný odkaz na výsledek = únik).
	_cache[key] = [weakref(am), weakref(out)]
	if out != am:
		# výsledek se může dostat znovu na vstup (druhé volání nad už zpracovanou sítí) – nezpracovávat dvakrát
		_cache[out.get_instance_id()] = [weakref(out), weakref(out)]
	return out


## Odstraní záznamy, jejichž zdroj nebo výsledek už neexistuje (volá se před každou novou generací).
static func _prune() -> void:
	for k in _cache.keys():
		var e: Array = _cache[k]
		if (e[0] as WeakRef).get_ref() == null or (e[1] as WeakRef).get_ref() == null:
			_cache.erase(k)


static func cache_size() -> int:
	return _cache.size()


static func clear_cache() -> void:
	_cache = {}


static func _build(am: ArrayMesh, min_tris: int) -> Mesh:
	var t0 := Time.get_ticks_usec()
	var n := am.get_surface_count()
	if n == 0:
		return am
	var tris := 0
	for s in n:
		if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or am.surface_get_array_index_len(s) <= 0:
			return am   # neindexované nebo jiné primitivum – LOD nedává smysl
		if lod_count(am, s) > 0:
			return am   # už má LOD (např. editorový import)
		tris += am.surface_get_array_index_len(s) / 3
	if tris < min_tris:
		return am
	var im := ImporterMesh.new()
	for i in am.get_blend_shape_count():
		im.add_blend_shape(am.get_blend_shape_name(i))
	im.set_blend_shape_mode(am.blend_shape_mode)
	var arrays_per: Array = []
	var blends_per: Array = []
	for s in n:
		var arrays := am.surface_get_arrays(s)
		var blends := am.surface_get_blend_shape_arrays(s)
		arrays_per.append(arrays)
		blends_per.append(blends)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, blends, {}, null, "", am.surface_get_format(s))
	im.generate_lods(NORMAL_MERGE_ANGLE, NORMAL_SPLIT_ANGLE, [])
	var out := ArrayMesh.new()
	for i in am.get_blend_shape_count():
		out.add_blend_shape(am.get_blend_shape_name(i))
	out.blend_shape_mode = am.blend_shape_mode
	var any := false
	for s in n:
		var arrays: Array = arrays_per[s]
		var lods := {}
		var ids := _weld_ids(arrays[Mesh.ARRAY_VERTEX])
		var border := _border_edges(arrays[Mesh.ARRAY_INDEX], ids)
		for l in im.get_surface_lod_count(s):
			var idx := im.get_surface_lod_indices(s, l)
			if idx.size() < 3 or not _same_border(border, idx, ids):
				rejected_lods += im.get_surface_lod_count(s) - l
				break   # hrubší úrovně by hranici porušily také
			lods[im.get_surface_lod_size(s, l)] = idx
		any = any or not lods.is_empty()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends_per[s], lods, am.surface_get_format(s))
		out.surface_set_material(s, am.surface_get_material(s))
		out.surface_set_name(s, am.surface_get_name(s))
	if not any:
		return am
	out.resource_name = am.resource_name
	out.custom_aabb = am.custom_aabb
	if am.shadow_mesh != null:
		out.shadow_mesh = am.shadow_mesh
	for m in am.get_meta_list():
		out.set_meta(m, am.get_meta(m))
	generated += 1
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Svaření vrcholů podle polohy (švy UV/normál mají zdvojené vrcholy, hranice se počítá na svařené síti).
static func _weld_ids(pos: PackedVector3Array) -> PackedInt32Array:
	var ids := PackedInt32Array()
	ids.resize(pos.size())
	var map := {}
	for i in pos.size():
		var k := Vector3i((pos[i] / WELD).round())
		var v = map.get(k)
		if v == null:
			v = map.size()
			map[k] = v
		ids[i] = v
	return ids


## Hraniční hrany (patří jen jednomu trojúhelníku) svařené sítě (ids = _weld_ids) jako slovník Vector2i -> true.
static func _border_edges(idx: PackedInt32Array, ids: PackedInt32Array) -> Dictionary:
	var count := {}
	for t in range(0, idx.size() - 2, 3):
		for e in 3:
			var a := ids[idx[t + e]]
			var b := ids[idx[t + (e + 1) % 3]]
			if a == b:
				continue
			var k := Vector2i(mini(a, b), maxi(a, b))
			count[k] = int(count.get(k, 0)) + 1
	var out := {}
	for k in count:
		if int(count[k]) == 1:
			out[k] = true
	return out


## Má LOD přesně stejnou hranici jako originál? (Stejná množina hraničních hran svařené sítě.)
static func _same_border(border: Dictionary, idx: PackedInt32Array, ids: PackedInt32Array) -> bool:
	var b2 := _border_edges(idx, ids)
	if b2.size() != border.size():
		return false
	for k in border:
		if not b2.has(k):
			return false
	return true
