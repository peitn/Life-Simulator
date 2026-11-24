extends "res://tests/test_base.gd"
## C-LOD krok 4 (běh main-claude-1794900129, 17. 11. 2026): trubice copánků, dredů a cornrows ve stupni 1
## + souběžná stavba LOD1 (review Grok #527 bod 2 a 3).
## 1) Parsování struktury trubic z indexů: počet trubic = HairBuilder (stats), stran k podle druhu
##    (copánky 5, dredy 7, cornrows 6), čepička jen u volných pramenů, rekonstrukce = originál bit po bitu.
## 2) Bezpečný návrat: poškozené indexy → parsování [] a lod1_tubes {} (lod1_pack pak použije meshoptimizer).
## 3) Mez chyby NEZÁVISLE na Douglas–Peuckeru: každý vrchol plné trubice leží od povrchu LOD1 téže trubice
##    (nejbližší bod trojúhelníku) nejvýš min(4 mm, 0,5 × průměrný poloměr) (+0,1 %).
## 4) Struktura LOD1: jen původní vrcholy (polohy bitově, původní pořadí), ponechané prstence celé (k+1 vrcholů),
##    první a poslední prstenec i špička zůstávají, pořadí vrcholů trojúhelníků (orientace) jako HairBuilder.tube
##    (kontrola stejnou metrikou i na plných trubicích), CUSTOM0 beze změny, úspora.
## 5) Morfy: klíče LOD1 = stejná jména ve stejném pořadí; posun nejsilnějšího klíče na LOD1 = na plné síti
##    u stejných vrcholů (žádný nový vrchol → stejná vazba).
## 6) Souběh (Grok #527/2): 6 účesů stavěných NAJEDNOU ve WorkerThreadPool (meshoptimizer/ImporterMesh ve
##    vláknech) = bitově stejné plné karty, klíče, LOD1 i proxy jako sekvenční stavba.

const HairRig := preload("res://scripts/assets/hair_rig.gd")
const HB := preload("res://scripts/assets/hair_builder.gd")

const TUBE_STYLES := {"copanky": [HB.KIND_BRAID, 5, true], "dredy": [HB.KIND_LOC, 7, true], "cornrows": [HB.KIND_BRAID, 6, false]}
const CONC_STYLES := ["copanky", "dredy", "cornrows", "afro", "kratke", "culik"]
const EPS := 0.000001

var _conc := {}
var _conc_mutex := Mutex.new()


func _init() -> void:
	watchdog_seconds = 420.0


func _ready() -> void:
	await get_tree().process_frame
	HairRig.async_build = false
	_test_parse()
	_test_fallback()
	_test_error_and_structure()
	_test_morphs()
	_test_concurrency()
	finish("test_hair_lod1_tubes")


func _kind_sub(g: Dictionary, kind: int) -> PackedInt32Array:
	var idx: PackedInt32Array = g["idx"]
	var c0: PackedFloat32Array = g["c0"]
	var sub := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if int(roundf(c0[idx[t] * 4 + 3] * 8.0)) == kind:
			sub.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	return sub


# ------------------------------------------------------------------ 1) parsování

func _test_parse() -> void:
	section("Parsování trubic z indexů")
	for style in TUBE_STYLES:
		var spec: Array = TUBE_STYLES[style]
		var g := HairRig.geometry("scalp", style)
		var sub := _kind_sub(g, int(spec[0]))
		var tubes := HairRig.lod1_tube_parse(sub, (g["pos"] as PackedVector3Array).size())
		var st: Dictionary = g.get("stats", {})
		check(tubes.size() > 0 and tubes.size() == int(st.get("tubes", -1)),
			"%s: %d trubic rozpoznáno (HairBuilder jich postavil %d)" % [style, tubes.size(), int(st.get("tubes", -1))])
		var k_ok := true
		var cap_ok := true
		var n_min := 1 << 30
		for tb in tubes:
			k_ok = k_ok and int(tb["k"]) == int(spec[1])
			cap_ok = cap_ok and bool(tb["cap"]) == bool(spec[2])
			n_min = mini(n_min, int(tb["n"]))
		check(k_ok and cap_ok and n_min >= 2, "%s: k = %d stran, čepička %s, každá trubice ≥ 2 prstence (min %d)" % [
			style, int(spec[1]), "ano" if spec[2] else "ne", n_min])
		check(HairRig.lod1_tube_indices(tubes, []) == sub, "%s: rekonstrukce všech %d trojúhelníků = originál bit po bitu" % [
			style, sub.size() / 3])


# ------------------------------------------------------------------ 2) bezpečný návrat

func _test_fallback() -> void:
	section("Poškozená struktura → návrat ke staršímu chování")
	var g := HairRig.geometry("scalp", "copanky")
	var pos: PackedVector3Array = g["pos"]
	var sub := _kind_sub(g, HB.KIND_BRAID)
	var bad := sub.duplicate()
	var mid := (bad.size() / 6) * 3
	var tmp := bad[mid + 1]
	bad[mid + 1] = bad[mid + 2]
	bad[mid + 2] = tmp
	check(HairRig.lod1_tube_parse(bad, pos.size()).is_empty() and HairRig.lod1_tubes(pos, bad).is_empty(),
		"prohozené pořadí vrcholů jednoho trojúhelníku → [] / {} (druh půjde přes meshoptimizer)")
	var cut := sub.slice(0, sub.size() - 3)
	check(HairRig.lod1_tube_parse(cut, pos.size()).is_empty(), "useknutá čepička → []")
	check(HairRig.lod1_tube_parse(sub, 10).is_empty(), "index mimo počet vrcholů → []")
	check(HairRig.lod1_tube_parse(PackedInt32Array([0, 1, 2]), 3).is_empty(), "obyčejný trojúhelník (k < 3) → []")


# ------------------------------------------------------------------ 3) + 4) chyba a struktura

static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Ericson, Real-Time Collision Detection 5.1.5
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


static func _ring_center(pos: PackedVector3Array, base: int, k: int, i: int) -> Vector3:
	var c := Vector3.ZERO
	for j in k:
		c += pos[base + i * (k + 1) + j]
	return c / float(k)


## Počet trojúhelníků těla trubice, které NEsledují pořadí vrcholů originálu (HairBuilder.tube): (A_j, B_j, A_j+1)
## nebo (A_j+1, B_j, B_j+1), kde A je prstenec před B (B může být v LOD1 o několik prstenců dál). Stejné pořadí =
## stejná orientace přední strany (geometrická kontrola normálou se ukázala nespolehlivá u zúžených konců dredů –
## hlásila 11 „obrácených“ i na PLNÝCH trubicích, 17. 11.).
static func _orient_bad(tris: PackedInt32Array, base: int, k: int, n: int) -> int:
	var bad := 0
	for t in range(0, tris.size(), 3):
		var r0 := (tris[t] - base) / (k + 1)
		var r1 := (tris[t + 1] - base) / (k + 1)
		var r2 := (tris[t + 2] - base) / (k + 1)
		if r0 >= n or r1 >= n or r2 >= n:
			continue  # čepička (špička leží za posledním prstencem)
		var j0 := (tris[t] - base) % (k + 1)
		var j1 := (tris[t + 1] - base) % (k + 1)
		var p1 := r1 > r0 and j1 == j0 and r2 == r0 and tris[t + 2] == tris[t] + 1 and j0 < k
		var p2 := r1 > r0 and j1 == j0 - 1 and r2 == r1 and tris[t + 2] == tris[t + 1] + 1
		if not (p1 or p2):
			bad += 1
	return bad


func _test_error_and_structure() -> void:
	section("Mez chyby (nezávisle) a struktura LOD1 trubic")
	for style in TUBE_STYLES:
		var spec: Array = TUBE_STYLES[style]
		var g := HairRig.geometry("scalp", style)
		var pos: PackedVector3Array = g["pos"]
		var sub := _kind_sub(g, int(spec[0]))
		var tubes := HairRig.lod1_tube_parse(sub, pos.size())
		var full := HairRig.mesh_for("scalp", style)
		var lm := HairRig.lod1_mesh(style)
		if not check(full != null and lm != null, "%s: LOD1 existuje (dřív stupeň 1 = plné trubice)" % style):
			continue
		var la := lm.surface_get_arrays(0)
		var lpos: PackedVector3Array = la[Mesh.ARRAY_VERTEX]
		var lidx: PackedInt32Array = la[Mesh.ARRAY_INDEX]
		var lc0: PackedFloat32Array = la[Mesh.ARRAY_CUSTOM0]
		var ftris := (full.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var st: Dictionary = HairRig.build_stats.get(HairRig.LOD1_PREFIX + style, {})
		check(lidx.size() / 3 < ftris and int(st.get("tubes", 0)) == tubes.size() and int(st.get("rings_out", 0)) < int(st.get("rings_in", 0)),
			"%s: %d → %d tr., prstenců %d → %d, statistika chyby %.2f mm" % [style, ftris, lidx.size() / 3,
			int(st.get("rings_in", 0)), int(st.get("rings_out", 0)), 1000.0 * float(st.get("tube_err", -1.0))])
		# mapování vrcholů LOD1 → původní (kompakce zachovává vzestupné pořadí a polohy beze změny)
		var orig_of := PackedInt32Array()
		orig_of.resize(lpos.size())
		orig_of.fill(-1)
		var where := {}
		for i in pos.size():
			if not where.has(pos[i]):
				where[pos[i]] = []
			(where[pos[i]] as Array).append(i)
		var last := -1
		var map_ok := true
		for li in lpos.size():
			var cand: Array = where.get(lpos[li], [])
			var found := -1
			for oi in cand:
				if int(oi) > last:
					found = int(oi)
					break
			if found < 0:
				map_ok = false
				break
			orig_of[li] = found
			last = found
		check(map_ok, "%s: LOD1 obsahuje jen původní vrcholy v původním pořadí (%d z %d)" % [style, lpos.size(), pos.size()])
		if not map_ok:
			continue
		# trojúhelníky LOD1 podle trubice (rozsah vrcholů)
		var owner := PackedInt32Array()
		owner.resize(pos.size())
		owner.fill(-1)
		for ti in tubes.size():
			var tb: Dictionary = tubes[ti]
			var cnt := int(tb["n"]) * (int(tb["k"]) + 1) + (1 if tb["cap"] else 0)
			for v in range(int(tb["base"]), int(tb["base"]) + cnt):
				owner[v] = ti
		var tri_of := []
		tri_of.resize(tubes.size())
		for ti in tubes.size():
			tri_of[ti] = PackedInt32Array()
		for t in range(0, lidx.size(), 3):
			var o0 := orig_of[lidx[t]]
			var ti := owner[o0]
			if ti < 0:
				continue
			var arr: PackedInt32Array = tri_of[ti]
			arr.append_array(PackedInt32Array([o0, orig_of[lidx[t + 1]], orig_of[lidx[t + 2]]]))
			tri_of[ti] = arr
		# kontrola po trubicích
		var orient_bad := 0
		var orient_ctl := 0
		var max_ratio := 0.0
		var max_err := 0.0
		var rings_ok := true
		var ends_ok := true
		var checked := 0
		for ti in tubes.size():
			var tb: Dictionary = tubes[ti]
			var base := int(tb["base"])
			var k := int(tb["k"])
			var n := int(tb["n"])
			var tris: PackedInt32Array = tri_of[ti]
			# ponechané prstence: celé nebo vůbec
			var present := {}
			for v in tris:
				present[v] = true
			for i in n:
				var c := 0
				for j in k + 1:
					if present.has(base + i * (k + 1) + j):
						c += 1
				if c != 0 and c != k + 1:
					rings_ok = false
				if (i == 0 or i == n - 1) and c != k + 1:
					ends_ok = false
			if bool(tb["cap"]) and not present.has(base + n * (k + 1)):
				ends_ok = false
			orient_bad += _orient_bad(tris, base, k, n)
			orient_ctl += _orient_bad(HairRig.lod1_tube_indices([tb], []), base, k, n)
			# nezávislá chyba: každý vrchol prstenců plné trubice → nejbližší bod povrchu LOD1 téže trubice
			if style != "cornrows" and ti % 2 == 1:
				continue  # u velkých účesů každá druhá trubice (čas testu)
			var rsum := 0.0
			for i in n:
				var c := _ring_center(pos, base, k, i)
				for j in k:
					rsum += pos[base + i * (k + 1) + j].distance_to(c)
			var tol := minf(HairRig.LOD1_TUBE_MAX_ERROR, HairRig.LOD1_TUBE_REL_ERROR * rsum / float(n * k))
			for i in n:
				for j in k + 1:
					var p := pos[base + i * (k + 1) + j]
					var best := INF
					for t in range(0, tris.size(), 3):
						best = minf(best, p.distance_to(_closest_on_tri(p, pos[tris[t]], pos[tris[t + 1]], pos[tris[t + 2]])))
						if best <= EPS:
							break
					max_err = maxf(max_err, best)
					max_ratio = maxf(max_ratio, best / maxf(tol, 1e-9))
			checked += 1
		check(rings_ok and ends_ok, "%s: ponechané prstence celé (k+1 vrcholů), první/poslední prstenec a špička zůstávají" % style)
		check(orient_bad == 0 and orient_ctl == 0, "%s: pořadí vrcholů (orientace) jako originál (odchylek v LOD1 %d, kontrola na plných trubicích %d)" % [
			style, orient_bad, orient_ctl])
		check(max_ratio <= 1.001, "%s: nejvzdálenější vrchol plné trubice od LOD1 %.3f mm = %.0f %% meze (%d trubic ověřeno)" % [
			style, 1000.0 * max_err, 100.0 * max_ratio, checked])
		# CUSTOM0 (druh, náhoda pramene) zachováno → shader kreslí trubice stejně
		var c0_ok := true
		var fc0: PackedFloat32Array = g["c0"]
		for li in lpos.size():
			for q in 4:
				if lc0[li * 4 + q] != fc0[orig_of[li] * 4 + q]:
					c0_ok = false
		check(c0_ok, "%s: CUSTOM0 všech vrcholů LOD1 = originál" % style)


# ------------------------------------------------------------------ 5) morfy

func _test_morphs() -> void:
	section("Klíče (blend shapes) trubic v LOD1")
	for style in TUBE_STYLES:
		var full := HairRig.mesh_for("scalp", style)
		var lm := HairRig.lod1_mesh(style)
		if full == null or lm == null:
			check(false, "%s: chybí síť" % style)
			continue
		var names_ok := full.get_blend_shape_count() == lm.get_blend_shape_count()
		for b in full.get_blend_shape_count():
			names_ok = names_ok and full.get_blend_shape_name(b) == lm.get_blend_shape_name(b)
		check(names_ok, "%s: %d klíčů, stejná jména ve stejném pořadí" % [style, lm.get_blend_shape_count()])
		var fa := full.surface_get_arrays(0)
		var la := lm.surface_get_arrays(0)
		var fpos: PackedVector3Array = fa[Mesh.ARRAY_VERTEX]
		var lpos: PackedVector3Array = la[Mesh.ARRAY_VERTEX]
		var fb := full.surface_get_blend_shape_arrays(0)
		var lb := lm.surface_get_blend_shape_arrays(0)
		# nejsilnější klíč na plné síti
		var best_b := -1
		var best_d := 0.0
		for b in fb.size():
			var tv: PackedVector3Array = (fb[b] as Array)[Mesh.ARRAY_VERTEX]
			for i in range(0, fpos.size(), 7):
				var d := tv[i].distance_to(fpos[i])
				if d > best_d:
					best_d = d
					best_b = b
		if not check(best_b >= 0, "%s: plná síť má hýbající se klíč" % style):
			continue
		var ftv: PackedVector3Array = (fb[best_b] as Array)[Mesh.ARRAY_VERTEX]
		var ltv: PackedVector3Array = (lb[best_b] as Array)[Mesh.ARRAY_VERTEX]
		# stejné vrcholy (podle polohy) → stejná výchylka
		var by_pos := {}
		for i in fpos.size():
			if not by_pos.has(fpos[i]):
				by_pos[fpos[i]] = i
		var max_diff := 0.0
		var lmax := 0.0
		for li in lpos.size():
			var fi: int = by_pos.get(lpos[li], -1)
			if fi < 0:
				max_diff = INF
				break
			max_diff = maxf(max_diff, ((ltv[li] - lpos[li]) - (ftv[fi] - fpos[fi])).length())
			lmax = maxf(lmax, ltv[li].distance_to(lpos[li]))
		check(max_diff < 1e-6 and lmax > 0.001, "%s: klíč „%s“ hýbe LOD1 stejně jako plnou sítí (max %.2f mm, rozdíl %.4f µm)" % [
			style, full.get_blend_shape_name(best_b), 1000.0 * lmax, 1e6 * max_diff])


# ------------------------------------------------------------------ 6) souběh

static func _pack_bytes(pack: Dictionary) -> PackedByteArray:
	var d := {}
	for key in ["arrays", "blend", "names"]:
		d[key] = pack.get(key)
	for sub in ["lod1", "proxy"]:
		var p: Dictionary = pack.get(sub, {})
		d[sub] = {"arrays": p.get("arrays"), "blend": p.get("blend"), "names": p.get("names"), "skip": p.get("skip", "")}
	return var_to_bytes(d)


static func _hash(pack: Dictionary) -> String:
	var md5 := HashingContext.new()
	md5.start(HashingContext.HASH_MD5)
	md5.update(_pack_bytes(pack))
	return md5.finish().hex_encode()


func _conc_task(i: int) -> void:
	var pack := HairRig.build_pack("scalp", CONC_STYLES[i])
	var h := _hash(pack)
	_conc_mutex.lock()
	_conc[i] = h
	_conc_mutex.unlock()


func _test_concurrency() -> void:
	section("Souběžná stavba LOD1 ve WorkerThreadPool (Grok #527/2)")
	var seq := {}
	var t0 := Time.get_ticks_msec()
	for i in CONC_STYLES.size():
		seq[i] = _hash(HairRig.build_pack("scalp", CONC_STYLES[i]))
	var seq_ms := Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	var ids := []
	for i in CONC_STYLES.size():
		ids.append(WorkerThreadPool.add_task(_conc_task.bind(i), true, "test lod1 %d" % i))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))
	var conc_ms := Time.get_ticks_msec() - t1
	var same := 0
	for i in CONC_STYLES.size():
		if _conc.get(i, "") == seq[i]:
			same += 1
		else:
			print("    rozdíl: ", CONC_STYLES[i])
	check(same == CONC_STYLES.size(), "%d/%d účesů postavených najednou ve vláknech = bitově stejné jako sekvenčně (pole, klíče, LOD1, proxy); sekvenčně %d ms, souběžně %d ms" % [
		same, CONC_STYLES.size(), seq_ms, conc_ms])
