extends "res://tests/test_base.gd"
## C3+ (běh 11) – šev hlava–tělo a krk. Ověřuje na SKUTEČNÉM character.glb:
##  - krk těla je nad smyčkou odříznutý, okraj je jedna uzavřená smyčka a vzadu leží výš než vpředu (zvednutá báze krku),
##  - spodní pás krku hlavy kryje okraj těla bez díry i průniku (paprsky v rovině smyčky proti trojúhelníkům hlavy)
##    v základu, při náhodných kombinacích morfů těla i obličeje a při ohnutí krku (CPU skinning),
##  - vrcholy švu mají váhy kostí z těla (součet 1, max. 4), SimVisual dává klíčům těla na hlavě váhy z lp["body"],
##  - samostatná hlava (bez švu) zůstává beze změny, pomocné funkce (loop_hit, seam_skin) počítají správně,
##  - krk má rozumnou šířku a s tukem nevznikne „balón“.

const HB := preload("res://scripts/assets/head_builder.gd")
const CA := preload("res://scripts/assets/character_assembly.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")

var root: Node3D
var skel: Skeleton3D
var body_mesh: ArrayMesh
var head_mesh: ArrayMesh
## Smyčka okraje těla: indexy vrcholů seřazené podle úhlu.
var loop_idx: Array = []


func _init() -> void:
	watchdog_seconds = 300.0


func _ready() -> void:
	await get_tree().process_frame
	_test_helpers()
	_test_standalone_head()
	AssetLibrary.clear_cache()
	root = AssetLibrary.instantiate("character")
	if not check(root != null, "character.glb se načte"):
		finish("test_neck_seam")
		return
	skel = root.find_children("*", "Skeleton3D", true, false)[0]
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "body__body__skin_body":
			body_mesh = mi.mesh
		elif String(mi.name) == "head__face__skin_body":
			head_mesh = mi.mesh
	if not check(body_mesh != null and head_mesh != null, "síť kůže těla i hlavy existuje"):
		finish("test_neck_seam")
		return
	_test_manifest()
	_test_cut_and_loop()
	_test_coverage()
	_test_skinning()
	_test_neck_shape()
	await _test_simvisual()
	root.free()
	finish("test_neck_seam")


# ------------------------------------------------------------------ pomocné
static func _arrays(m: ArrayMesh) -> Array:
	return m.surface_get_arrays(0)


## Deformované polohy (NORMALIZED: p = base + Σ w·(target − base)) pro váhy podle názvu blend shape.
static func _deform(m: ArrayMesh, w: Dictionary) -> PackedVector3Array:
	var base: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var p := base.duplicate()
	var bsa := m.surface_get_blend_shape_arrays(0)
	for i in m.get_blend_shape_count():
		var wt := float(w.get(String(m.get_blend_shape_name(i)), 0.0))
		if absf(wt) < 1e-6:
			continue
		var tgt: PackedVector3Array = (bsa[i] as Array)[Mesh.ARRAY_VERTEX]
		for v in p.size():
			p[v] += (tgt[v] - base[v]) * wt
	return p


## Nejvzdálenější průsečík vodorovného paprsku (start, směr) s trojúhelníky (jen kandidáti), nebo −1.
static func _ray_far(start: Vector3, dir: Vector3, p: PackedVector3Array, tris: PackedInt32Array) -> float:
	var best := -1.0
	for t in range(0, tris.size(), 3):
		var a := p[tris[t]]
		var b := p[tris[t + 1]]
		var c := p[tris[t + 2]]
		var e1 := b - a
		var e2 := c - a
		var h := dir.cross(e2)
		var det := e1.dot(h)
		if absf(det) < 1e-14:
			continue
		var f := 1.0 / det
		var s := start - a
		var u := f * s.dot(h)
		if u < -1e-7 or u > 1.0 + 1e-7:
			continue
		var q := s.cross(e1)
		var v := f * dir.dot(q)
		if v < -1e-7 or u + v > 1.0 + 1e-7:
			continue
		var dist := f * e2.dot(q)
		if dist > 0.0 and dist < 0.12:
			best = maxf(best, dist)
	return best


func _loop_points(p: PackedVector3Array) -> Array:
	var out: Array = []
	for i in loop_idx:
		out.append(p[i])
	return out


static func _centroid(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for q in pts:
		c += Vector2(q.x, q.z)
	return c / float(pts.size())


## Mezera mezi krkem hlavy a okrajem těla: pro 96 směrů průsečík paprsku v rovině smyčky (výška = interpolace
## výšky hrany smyčky) s hlavou. Vrací [nejmenší (hlava − tělo), největší (hlava − tělo), chybějících zásahů].
func _coverage(pb: PackedVector3Array, ph: PackedVector3Array, head_tris: PackedInt32Array) -> Array:
	var loop := _loop_points(pb)
	var cen := _centroid(loop)
	var lo := 1e9
	var hi := -1e9
	var miss := 0
	for k in 96:
		var th := TAU * float(k) / 96.0
		var hit := HB.loop_hit(loop, cen, th)
		var yl := lerpf(float(loop[hit[1]].y), float(loop[hit[2]].y), float(hit[3]))
		var start := Vector3(cen.x, yl, cen.y)
		var dir := Vector3(sin(th), 0.0, cos(th))
		var dh := _ray_far(start, dir, ph, head_tris)
		if dh < 0.0:
			miss += 1
			continue
		lo = minf(lo, dh - float(hit[0]))
		hi = maxf(hi, dh - float(hit[0]))
	return [lo, hi, miss]


func _neck_tris(ph: PackedVector3Array) -> PackedInt32Array:
	var idx: PackedInt32Array = _arrays(head_mesh)[Mesh.ARRAY_INDEX]
	var out := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var ymin := minf(ph[idx[t]].y, minf(ph[idx[t + 1]].y, ph[idx[t + 2]].y))
		if ymin < 1.56:
			out.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	return out


static func _rand_body(rng: RandomNumberGenerator) -> Dictionary:
	var w := {}
	for k in ["frame", "shoulders", "chest", "bust", "waist", "hips"]:
		w[k] = rng.randf_range(-1.0, 1.0)
	w["fat_hi"] = rng.randf()
	w["fat_lo"] = rng.randf() if w["fat_hi"] < 0.05 else 0.0
	w["muscle_hi"] = rng.randf()
	w["muscle_lo"] = rng.randf() if w["muscle_hi"] < 0.05 else 0.0
	return w


# ------------------------------------------------------------------ testy
func _test_helpers() -> void:
	section("Pomocné funkce švu")
	var sq: Array = [Vector3(-0.05, 1.5, -0.05), Vector3(0.05, 1.5, -0.05), Vector3(0.05, 1.5, 0.05), Vector3(-0.05, 1.5, 0.05)]
	sq.sort_custom(func(a, b): return atan2(a.x, a.z) < atan2(b.x, b.z))
	var ok := true
	for k in 16:
		var th := TAU * float(k) / 16.0
		var h := HB.loop_hit(sq, Vector2.ZERO, th)
		var expect := 0.05 / maxf(absf(sin(th)), absf(cos(th)))
		if absf(float(h[0]) - expect) > 1e-6:
			ok = false
	check(ok, "loop_hit: průsečík paprsku se čtvercem = analytická vzdálenost (16 směrů)")
	var seam := {"w": PackedFloat32Array([0.6]), "a": PackedInt32Array([0]), "b": PackedInt32Array([1]), "f": PackedFloat32Array([0.25]),
		"bones": [PackedInt32Array([3, 2, 5, 0]), PackedInt32Array([3, 2, 11, 0])],
		"weights": [PackedFloat32Array([0.7, 0.2, 0.1, 0.0]), PackedFloat32Array([0.6, 0.3, 0.1, 0.0])]}
	var sk: Array = HB.seam_skin(seam, 0, 4, 3, 0.8)
	var tot := 0.0
	for e in sk:
		tot += float(e[1])
	check(sk.size() <= 4 and absf(tot - 1.0) < 1e-5 and int(sk[0][0]) == 3, "seam_skin: max. 4 kosti, součet 1, převládá krk (%s)" % str(sk))
	var sk0: Array = HB.seam_skin({"w": PackedFloat32Array([0.0]), "a": PackedInt32Array([0]), "b": PackedInt32Array([0]), "f": PackedFloat32Array([0.0])}, 0, 4, 3, 0.25)
	check(sk0.size() == 2 and absf(float(sk0[0][1]) - 0.75) < 1e-6, "seam_skin bez dat těla = vlastní váhy hlavy")
	check(is_equal_approx(HB.seam_weight(1.50, 1.50), 1.0) and is_equal_approx(HB.seam_weight(1.40, 1.50), 1.0)
		and HB.seam_weight(1.50 + HB.SEAM_BAND, 1.50) == 0.0, "seam_weight: 1 na smyčce a pod ní, 0 od SEAM_BAND nad ní")


func _test_standalone_head() -> void:
	section("Samostatná hlava (bez švu)")
	var d := HB.build_data()
	check((d["seam"] as Dictionary).is_empty() and not (d["spec"] as Dictionary).has("_body_keys"), "build_data() bez okraje těla nemá šev ani klíče těla")
	var bad := 0
	for i in (d["base"] as PackedVector3Array).size():
		var q: Vector3 = d["base"][i]
		if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z)):
			bad += 1
	check(bad == 0, "všechny vrcholy konečné")
	# Spodní stěna mřížky: rukáv krku má víc řad (běh 11) – na přední straně je mezi víčkem a bradou ≥ 4 řad.
	var t = d["topo"]
	var ys := {}
	for i in t.recipes.size():
		var r: Array = t.recipes[i]
		if r[0] == "g" and int(r[2]) == 0 and int(r[3]) > HB.NZ / 2 and HB.bottom_ring(r[1], r[3]) >= 1:
			var q: Vector3 = d["base"][i]
			if absf(q.x) < 0.01:
				ys[snappedf(q.y, 0.001)] = true
	check(ys.size() >= 5, "rukáv krku vpředu má %d řad vrcholů (≥ 5)" % ys.size(), str(ys.keys()))


func _test_manifest() -> void:
	section("Manifest")
	var meta := AssetLibrary.manifest_meta("character")
	var bk: Array = (meta.get("face_spec", {}) as Dictionary).get("_body_keys", [])
	check(int(meta.get("seam_loop_verts", 0)) == 16, "smyčka švu má 16 vrcholů (%s)" % str(meta.get("seam_loop_verts")))
	check(int(meta.get("neck_cut_tris", 0)) > 50 and int(meta.get("neck_lifted_verts", 0)) > 50,
		"odříznuto %s trojúhelníků krku, zvednuto %s vrcholů báze krku" % [str(meta.get("neck_cut_tris")), str(meta.get("neck_lifted_verts"))])
	check(int(meta.get("seam_head_verts", 0)) > 100 and int(meta.get("seam_cap_verts", 0)) > 0, "pás švu hlavy %s vrcholů (víčko %s)" % [str(meta.get("seam_head_verts")), str(meta.get("seam_cap_verts"))])
	check(bk.has("fat_hi") and bk.has("muscle_hi") and bk.has("frame"), "hlava nese klíče těla %s" % str(bk))
	var missing: Array = []
	for k in bk:
		if head_mesh.find_blend_shape_by_name(StringName(k)) < 0:
			missing.append(k)
	check(missing.is_empty(), "klíče těla jsou blend shapes sítě hlavy", str(missing))


func _test_cut_and_loop() -> void:
	section("Řez krku těla a smyčka")
	var arr := _arrays(body_mesh)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var cnt := {}
	var above := 0
	for t in range(0, idx.size(), 3):
		var tri := [idx[t], idx[t + 1], idx[t + 2]]
		var high := true
		for i in tri:
			if not (v[i].y > 1.53 and Vector2(v[i].x, v[i].z).length() < 0.06):
				high = false
		if high:
			above += 1
		for e in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			cnt[key] = int(cnt.get(key, 0)) + 1
	check(above == 0, "nad smyčkou nezůstal žádný trojúhelník krku těla")
	var deg := {}
	for e in cnt:
		if cnt[e] == 1 and v[e.x].y > 1.45 and Vector2(v[e.x].x, v[e.x].z).length() < 0.08:
			deg[e.x] = int(deg.get(e.x, 0)) + 1
			deg[e.y] = int(deg.get(e.y, 0)) + 1
	var closed := true
	for i in deg:
		if deg[i] != 2:
			closed = false
	loop_idx = deg.keys()
	var cen := Vector2.ZERO
	for i in loop_idx:
		cen += Vector2(v[i].x, v[i].z)
	cen /= maxf(1.0, float(loop_idx.size()))
	loop_idx.sort_custom(func(a, b): return atan2(v[a].x - cen.x, v[a].z - cen.y) < atan2(v[b].x - cen.x, v[b].z - cen.y))
	check(loop_idx.size() == 16 and closed, "okraj krku těla je jedna uzavřená smyčka (%d vrcholů)" % loop_idx.size())
	var y_front := 0.0
	var y_back := 0.0
	for i in loop_idx:
		if v[i].z > 0.04:
			y_front = maxf(y_front, v[i].y)
		if v[i].z < -0.04:
			y_back = maxf(y_back, v[i].y)
	check(y_back - y_front > 0.010 and y_back < 1.535, "báze krku vzadu (%.3f m) je výš než vpředu (%.3f m) – trapéz a C7" % [y_back, y_front])


func _test_coverage() -> void:
	section("Krytí švu (paprsky v rovině smyčky)")
	var pb: PackedVector3Array = _arrays(body_mesh)[Mesh.ARRAY_VERTEX]
	var ph: PackedVector3Array = _arrays(head_mesh)[Mesh.ARRAY_VERTEX]
	var tris := _neck_tris(ph)
	var c := _coverage(pb, ph, tris)
	check(int(c[2]) == 0 and float(c[0]) > -0.0002 and float(c[1]) < 0.0015,
		"základ: hlava leží na okraji těla (odstup %.2f až %.2f mm, chybí %d/96)" % [float(c[0]) * 1000.0, float(c[1]) * 1000.0, int(c[2])])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst_lo := 1e9
	var worst_hi := -1e9
	var misses := 0
	for s in 12:
		var bw := _rand_body(rng)
		var fw := {"b_fat": bw["fat_hi"], "b_muscle": bw["muscle_hi"], "neck_width": rng.randf_range(-1.0, 1.0),
			"jaw_width": rng.randf_range(-1.0, 1.0), "chin_length": rng.randf_range(-1.0, 1.0), "head_width_pos": rng.randf()}
		var dpb := _deform(body_mesh, bw)
		var dph := _deform(head_mesh, fw.merged(bw))
		var cc := _coverage(dpb, dph, _neck_tris(dph))
		worst_lo = minf(worst_lo, float(cc[0]))
		worst_hi = maxf(worst_hi, float(cc[1]))
		misses += int(cc[2])
	check(misses == 0 and worst_lo > -0.0003 and worst_hi < 0.002,
		"12 náhodných těl a krků: bez díry a průniku (odstup %.2f až %.2f mm)" % [worst_lo * 1000.0, worst_hi * 1000.0])
	# Kontrola, že test opravdu něco měří: bez klíčů těla na hlavě se šev při tuku rozjede.
	var bw2 := {"fat_hi": 1.0, "muscle_hi": 1.0, "frame": 1.0}
	var c2 := _coverage(_deform(body_mesh, bw2), _deform(head_mesh, {"b_fat": 1.0, "b_muscle": 1.0}), tris)
	check(int(c2[2]) > 0 or float(c2[0]) < -0.0005 or float(c2[1]) > 0.003, "kontrola testu: bez morfů těla na hlavě se šev rozejde (%.2f až %.2f mm)" % [float(c2[0]) * 1000.0, float(c2[1]) * 1000.0])


func _test_skinning() -> void:
	section("Váhy kostí a ohnutí krku")
	var ab := _arrays(body_mesh)
	var ah := _arrays(head_mesh)
	var hb: PackedInt32Array = ah[Mesh.ARRAY_BONES]
	var hw: PackedFloat32Array = ah[Mesh.ARRAY_WEIGHTS]
	var ph: PackedVector3Array = ah[Mesh.ARRAY_VERTEX]
	var bad_sum := 0
	var chest_low := 0
	for i in ph.size():
		var s := hw[i * 4] + hw[i * 4 + 1] + hw[i * 4 + 2] + hw[i * 4 + 3]
		if absf(s - 1.0) > 1e-3:
			bad_sum += 1
		if ph[i].y < 1.50 and Vector2(ph[i].x, ph[i].z).length() > 0.04:
			var chest := 0.0
			for j in 4:
				if hb[i * 4 + j] == 2:
					chest += hw[i * 4 + j]
			if chest < 0.1:
				chest_low += 1
	check(bad_sum == 0, "součet vah kostí hlavy = 1 u všech vrcholů")
	check(chest_low == 0, "spodek krku hlavy má váhu hrudníku jako okraj těla")
	# CPU skinning: krk (a hlava jako jeho potomek) se otočí kolem kloubu krku, hrudník stojí.
	var neck := skel.find_bone("neck")
	var head := skel.find_bone("head")
	var j: Vector3 = skel.get_bone_global_rest(neck).origin
	var tris := _neck_tris(ph)
	var worst_lo := 1e9
	var worst_hi := -1e9
	var miss := 0
	for rot in [Quaternion(Vector3.RIGHT, deg_to_rad(25.0)), Quaternion(Vector3.FORWARD, deg_to_rad(20.0)), Quaternion(Vector3.UP, deg_to_rad(35.0))]:
		var pb := _skin(ab, rot, j, neck, head)
		var phs := _skin(ah, rot, j, neck, head)
		var c := _coverage(pb, phs, tris)
		worst_lo = minf(worst_lo, float(c[0]))
		worst_hi = maxf(worst_hi, float(c[1]))
		miss += int(c[2])
	check(miss == 0 and worst_lo > -0.0008 and worst_hi < 0.003,
		"předklon 25°, úklon 20°, otočení 35°: šev drží (odstup %.2f až %.2f mm)" % [worst_lo * 1000.0, worst_hi * 1000.0])


## Lineární skinning s rotací rot kolem kloubu j pro kosti krku a hlavy (ostatní stojí). Indexy = bindy (0–7 = kosti).
static func _skin(arr: Array, rot: Quaternion, j: Vector3, neck: int, head: int) -> PackedVector3Array:
	var p: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	out.resize(p.size())
	for i in p.size():
		var moved := j + rot * (p[i] - j)
		var acc := Vector3.ZERO
		for k in 4:
			var bi := b[i * 4 + k]
			acc += (moved if bi == neck or bi == head else p[i]) * w[i * 4 + k]
		out[i] = acc
	return out


func _test_neck_shape() -> void:
	section("Tvar krku")
	var ph: PackedVector3Array = _arrays(head_mesh)[Mesh.ARRAY_VERTEX]
	var half := 0.0
	for q in ph:
		if absf(q.y - 1.535) < 0.004 and absf(q.z) < 0.02:
			half = maxf(half, absf(q.x))
	check(half > 0.050 and half < 0.062, "šířka krku pod čelistí %.1f cm (dospělý ~10–12 cm)" % (half * 200.0))
	# S maximem tuku a svalů nesmí krk pod čelistí přerůst okraj těla o víc než 15 % („balón“).
	var bw := {"fat_hi": 1.0, "muscle_hi": 1.0}
	var dph := _deform(head_mesh, {"b_fat": 1.0, "b_muscle": 1.0, "fat_hi": 1.0, "muscle_hi": 1.0})
	var dpb := _deform(body_mesh, bw)
	var loop := _loop_points(dpb)
	var lr := 0.0
	for q in loop:
		lr = maxf(lr, absf(q.x))
	var top := 0.0
	for q in dph:
		if q.y > 1.53 and q.y < 1.55 and absf(q.z) < 0.02:
			top = maxf(top, absf(q.x))
	check(top < lr * 1.15, "tuk + svaly: krk pod čelistí %.1f cm vs. báze krku %.1f cm (bez balónu)" % [top * 200.0, lr * 200.0])


func _test_simvisual() -> void:
	section("SimVisual – klíče těla na hlavě")
	var c = CharacterData.create()
	c.set_path_value("body.body_fat", 0.9)
	c.set_path_value("body.muscle", 0.8)
	c.set_path_value("body.frame", 0.9)
	var v = SimVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.apply_look(c.public_snapshot())
	var bw: Dictionary = v.look_params["body"]
	var wrong: Array = []
	var seen := 0
	for mi in AssetLibrary.parts_in_group(v._model, "head"):
		var m: ArrayMesh = mi.mesh
		for k in bw:
			var i := m.find_blend_shape_by_name(StringName(k))
			if i < 0:
				continue
			seen += 1
			if not is_equal_approx(mi.get_blend_shape_value(i), float(bw[k])):
				wrong.append(k)
	check(seen > 0 and wrong.is_empty(), "hlava: %d hodnot klíčů těla = lp[\"body\"]" % seen, str(wrong))
	check(float(bw.get("fat_hi", 0.0)) > 0.0, "tělo s tukem má fat_hi > 0 (%.3f)" % float(bw.get("fat_hi", 0.0)))
	v.queue_free()
