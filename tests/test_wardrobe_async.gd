extends "res://tests/test_base.gd"
## H3 (7 Nov 2026): ClothingWardrobe async loading. The first decode of a garment kind used to run
## on the main thread (1.5–7 s on the test host) when the first character with that outfit spawned,
## freezing a joining client long enough for ENet to drop it. Verifies: threaded output is
## identical to the synchronous build, the main thread stays responsive, owners are called back
## (and freed owners are not), reset during a build is safe, and SimVisual shows the GLB clothes
## as a placeholder (never a bare body) and then switches to exactly the synchronous wardrobe.
## Evening run: the main-thread ArrayMesh realisation is spread over frames under a time budget
## (pending until the last mesh, joins late owners, sync callers complete it, reset drops it).

const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const Visual := preload("res://scripts/sim/sim_visual.gd")
const Library := preload("res://scripts/assets/asset_library.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")

const ALL_KINDS := ["top", "bottom", "shoes", "dress", "legs"]
const LEGACY := ["cloth_shirt", "cloth_pants", "shoe_leather"]


class Listener:
	extends Node
	var calls: Array = []
	func _on_wardrobe_ready(kind: String) -> void:
		calls.append(kind)


func _ready() -> void:
	watchdog_seconds = 280.0
	await _run()
	Wardrobe.async_load = false
	finish("test_wardrobe_async")


## Byte-exact digest of every mesh of every style of the given kinds (arrays + blend shapes +
## material name + piece names). Same digest = same geometry, skinning, UVs and morphs.
func _digest(kinds: Array) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for kind in kinds:
		Wardrobe._mutex.lock()
		var styles: Dictionary = Wardrobe._loaded.get(kind, {})
		Wardrobe._mutex.unlock()
		var names: Array = styles.keys()
		names.sort()
		for style in names:
			for e in styles[style]:
				var m: ArrayMesh = e["mesh"]
				h.update(("%s/%s/%s/%s/%d/%d" % [kind, style, e["name"], e["material"], m.get_surface_count(),
					m.get_blend_shape_count()]).to_utf8_buffer())
				for s in m.get_surface_count():
					h.update(var_to_bytes(m.surface_get_arrays(s)))
					h.update(var_to_bytes(m.surface_get_blend_shape_arrays(s)))
	return h.finish().hex_encode()


func _counts() -> Dictionary:
	var out := {}
	for kind in ALL_KINDS:
		Wardrobe._mutex.lock()
		var styles: Dictionary = Wardrobe._loaded.get(kind, {})
		Wardrobe._mutex.unlock()
		var n := 0
		for st in styles:
			n += (styles[st] as Array).size()
		out[kind] = [styles.size(), n]
	return out


func _all_loaded(kinds: Array) -> bool:
	for k in kinds:
		if not Wardrobe.is_loaded(k):
			return false
	return true


## Waits for a condition while sampling the longest main-thread frame gap (ms).
func _wait_sampling(cond: Callable, timeout: float) -> Dictionary:
	var deadline := Time.get_ticks_usec() + int(timeout * 1000000.0)
	var last := Time.get_ticks_usec()
	var max_gap := 0.0
	var frames := 0
	while Time.get_ticks_usec() < deadline and not cond.call():
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		max_gap = maxf(max_gap, (now - last) / 1000.0)
		last = now
		frames += 1
	return {"ok": bool(cond.call()), "max_gap_ms": max_gap, "frames": frames}


func _snapshot(top: String, bottom: String, shoes: String) -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Fikce"
	d["identity"]["last_name"] = "Šatník"
	d["personality"]["traits"] = ["hravy"]
	d["body"]["body_fat"] = 0.7
	d["clothing"]["active"] = "bezne"
	d["clothing"]["bezne"]["top"] = top
	d["clothing"]["bezne"]["bottom"] = bottom
	d["clothing"]["bezne"]["shoes"] = shoes
	var r: Dictionary = Validator.validate(d)
	if not r.get("ok", false):
		push_error("fixture invalid: " + str(r.get("errors")))
		return {}
	var c := CharacterData.new()
	c.set_from_dict(r["data"])
	return c.public_snapshot()


func _visual(snap: Dictionary):
	var v = Node3D.new()
	v.set_script(Visual)
	v.apply_look(snap)
	add_child(v)
	return v


func _legacy_visible(v) -> Dictionary:
	var out := {}
	for mi in Library.parts_in_group(v._model, "body"):
		var n := Library.part_material_name(mi)
		if n in LEGACY:
			out[n] = bool(out.get(n, false)) or mi.visible
	return out


func _c5_names(v) -> Array:
	var out: Array = []
	for mi in v._c5_nodes:
		out.append(String(mi.name))
	return out


func _c5_mesh_digest(v) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for mi in v._c5_nodes:
		var m: Mesh = (mi as MeshInstance3D).mesh
		h.update(String(mi.name).to_utf8_buffer())
		h.update(var_to_bytes(m.surface_get_arrays(0)))
		var fat: int = (mi as MeshInstance3D).find_blend_shape_by_name(&"fat_hi")
		h.update(var_to_bytes(snappedf((mi as MeshInstance3D).get_blend_shape_value(fat), 0.0001) if fat >= 0 else -1.0))
	return h.finish().hex_encode()


func _driver_connected() -> bool:
	return get_tree().process_frame.is_connected(Callable(Wardrobe, "_realize_frame"))


## Waits until a kind is being realised (the worker is done, meshes not yet all made).
func _wait_realizing(kind: String) -> bool:
	return await wait_until(func(): return Wardrobe.is_realizing(kind) or Wardrobe.is_loaded(kind), 90.0) \
		and Wardrobe.is_realizing(kind)


## H3 (7 Nov 2026 evening): the ArrayMesh realisation of a finished background build is spread
## over frames under a time budget instead of one long frame for all 118 top meshes.
func _realize_section(sync_digest_all: String) -> void:
	section("Frame-spread realisation (budget per frame, same output)")
	var budget_before: int = Wardrobe.realize_budget_usec
	Wardrobe.async_load = true
	# Default budget: the top kind is realised over several frames and no frame exceeds the budget
	# by more than one mesh.
	Wardrobe.reset_cache()
	var a := Listener.new()
	add_child(a)
	Wardrobe.ensure_kinds(["top"], a)
	var w: Dictionary = await _wait_sampling(func(): return Wardrobe.is_loaded("top"), 120.0)
	await get_tree().process_frame
	var ls: Dictionary = Wardrobe.load_stats.get("top", {})
	var budget_ms := Wardrobe.realize_budget_usec / 1000.0
	var mesh_ms := float(ls.get("realize_max_mesh_ms", 0.0))
	print("  top realised in %d frames, %d meshes, longest realise frame %.2f ms, longest mesh %.2f ms, longest gap %.1f ms" % [
		int(ls.get("realize_frames", 0)), int(ls.get("realize_meshes", 0)), Wardrobe.realize_max_frame_ms, mesh_ms,
		w["max_gap_ms"]])
	check(w["ok"] and int(ls.get("realize_meshes", 0)) == 118, "all 118 top meshes realised", str(ls))
	check(int(ls.get("realize_frames", 0)) >= 2, "realisation spread over more than one frame", str(ls.get("realize_frames")))
	check(Wardrobe.realize_max_frame_ms <= budget_ms + mesh_ms + 2.0,
		"no realisation frame exceeds the budget by more than one mesh (+2 ms timer slack)",
		"%.2f ms vs budget %.2f + mesh %.2f" % [Wardrobe.realize_max_frame_ms, budget_ms, mesh_ms])
	check(a.calls == ["top"] and not _driver_connected(), "owner called once at the end; frame driver disconnected when idle",
		str(a.calls))
	# One mesh per frame: deterministic windows to probe the in-between state.
	Wardrobe.realize_budget_usec = 1
	Wardrobe.reset_cache()
	a.calls.clear()
	Wardrobe.ensure_kinds(["top"], a)
	var mid: bool = await _wait_realizing("top")
	check(mid and not Wardrobe.is_loaded("top") and _driver_connected(),
		"between worker end and last mesh the kind is pending, not loaded (driver running)")
	var b := Listener.new()
	add_child(b)
	var b_ready := Wardrobe.ensure_kinds(["top"], b)
	Wardrobe._mutex.lock()
	var tasks_mid := Wardrobe._tasks.size()
	Wardrobe._mutex.unlock()
	check(not b_ready and tasks_mid == 0, "request during realisation joins it (no second decode task)", str(tasks_mid))
	for i in 3:
		await get_tree().process_frame
	var cur: Dictionary = Wardrobe._pending.get("top", {}).get("realize", {})
	var made := int(cur.get("meshes", -1))
	check(made >= 1 and made < 118, "budget 1 µs → about one mesh per frame (%d after a few frames)" % made)
	# A synchronous caller mid-realisation completes the remaining meshes at once.
	var t0 := Time.get_ticks_usec()
	var hood: Array = Wardrobe.parts("top", "mikina")
	var complete_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not hood.is_empty() and Wardrobe.is_loaded("top") and not Wardrobe.is_realizing("top"),
		"sync parts() during realisation finishes it immediately (%.0f ms) without a re-decode" % complete_ms)
	check(a.calls.is_empty() and b.calls.is_empty(), "owners are not called re-entrantly inside the sync caller")
	await get_tree().process_frame
	await get_tree().process_frame
	check(a.calls == ["top"] and b.calls == ["top"], "both owners (early and joined) called back exactly once",
		str([a.calls, b.calls]))
	check(not _driver_connected(), "driver disconnected after the sync completion emptied the queue")
	# Reset in the middle of realisation discards the half-made kind.
	Wardrobe.reset_cache()
	a.calls.clear()
	Wardrobe.ensure_kinds(["shoes"], a)
	var mid2: bool = await _wait_realizing("shoes")
	Wardrobe.reset_cache()
	for i in 4:
		await get_tree().process_frame
	check(mid2 and not Wardrobe.is_loaded("shoes") and not Wardrobe.is_pending("shoes") and a.calls.is_empty()
		and not _driver_connected(), "reset_cache() during realisation drops it: no publish, no callback, driver stops")
	# Frame-by-frame realised output of every kind equals the synchronous build.
	Wardrobe.realize_budget_usec = 2000
	Wardrobe.reset_cache()
	Wardrobe.ensure_kinds(ALL_KINDS, a)
	var all_done: bool = await wait_until(func(): return _all_loaded(ALL_KINDS), 150.0)
	await get_tree().process_frame
	check(all_done and _digest(ALL_KINDS) == sync_digest_all,
		"spread realisation (2 ms budget, five kinds queued) is byte-identical to the synchronous build")
	Wardrobe.realize_budget_usec = budget_before
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _run() -> void:
	# Hair stays synchronous here so only the wardrobe path is measured.
	HairRig.async_build = false
	section("Synchronous baseline (default: async_load off)")
	Wardrobe.async_load = false
	Wardrobe.reset_cache()
	check(Wardrobe.ensure_kinds(ALL_KINDS, null) and not Wardrobe.is_pending("top"),
		"async off: ensure_kinds says ready and starts nothing (caller loads synchronously, as before)")
	var t0 := Time.get_ticks_usec()
	var st := Wardrobe.stats()
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sync_digest := _digest(ALL_KINDS)
	var sync_counts := _counts()
	check(st["top"]["styles"] == 20 and st["top"]["meshes"] == 118 and st["bottom"]["meshes"] == 22
		and st["shoes"]["meshes"] == 29, "catalogue unchanged (20 tops/118 meshes, 22 bottoms, 29 shoes)", str(st))
	print("  sync build of all kinds: %.0f ms on the main thread" % sync_ms)
	var sync_stats: Dictionary = Wardrobe.load_stats.duplicate(true)
	check(not bool(sync_stats.get("top", {}).get("thread", true)), "sync load is recorded as main-thread build")

	section("Async build: main thread stays responsive, identical output")
	Wardrobe.reset_cache()
	Wardrobe.async_load = true
	var listener := Listener.new()
	add_child(listener)
	t0 = Time.get_ticks_usec()
	var ready_now := Wardrobe.ensure_kinds(ALL_KINDS, listener)
	var request_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not ready_now and Wardrobe.is_pending("top") and Wardrobe.is_pending("legs"),
		"cold request returns at once and queues background builds")
	check(request_ms < 50.0, "request costs the main thread < 50 ms (was the whole build)", "%.2f ms" % request_ms)
	# A second request for the same kinds must not start duplicate tasks or duplicate callbacks.
	Wardrobe.ensure_kinds(["top", "top", "shoes"], listener)
	Wardrobe._mutex.lock()
	var task_count := Wardrobe._tasks.size()
	Wardrobe._mutex.unlock()
	check(task_count == 5, "exactly one task per kind (no duplicates)", str(task_count))
	var waited: Dictionary = await _wait_sampling(func(): return _all_loaded(ALL_KINDS), 150.0)
	print("  async: %d frames while building, longest main-thread gap %.1f ms (sync build %.0f ms)" % [
		waited["frames"], waited["max_gap_ms"], sync_ms])
	check(waited["ok"], "all kinds finish in the background")
	check(waited["max_gap_ms"] < 500.0 and waited["max_gap_ms"] < sync_ms * 0.25,
		"main thread keeps ticking during the build (gap < 500 ms and < 1/4 of the sync stall)",
		"%.1f ms" % waited["max_gap_ms"])
	await get_tree().process_frame
	listener.calls.sort()
	var expected := ALL_KINDS.duplicate()
	expected.sort()
	check(listener.calls == expected, "owner called back exactly once per kind", str(listener.calls))
	check(bool(Wardrobe.load_stats.get("top", {}).get("thread", false)), "load_stats marks threaded build")
	check(_digest(ALL_KINDS) == sync_digest and _counts() == sync_counts,
		"threaded meshes are byte-identical to the synchronous build (arrays, skin, UV, 10 morphs)")
	var shared := true
	for e in Wardrobe.parts("top", "mikina"):
		var m: ArrayMesh = e["mesh"]
		shared = shared and m.surface_get_material(0) == Wardrobe._mat(String(e["material"]))
	check(shared, "garments built on the worker share the main-thread material cache (one instance)")
	Wardrobe._mutex.lock()
	var leftover := Wardrobe._tasks.size()
	Wardrobe._mutex.unlock()
	check(leftover == 0 and not Wardrobe.is_pending("top"), "every task was waited for and released", str(leftover))
	var cached_ready := Wardrobe.ensure_kinds(ALL_KINDS, listener)
	await get_tree().process_frame
	check(cached_ready and listener.calls.size() == 5, "cached request is ready immediately, no extra callback")

	section("Freed owner and reset during a build")
	Wardrobe.reset_cache()
	var doomed := Listener.new()
	add_child(doomed)
	Wardrobe.ensure_kinds(["shoes"], doomed)
	var doomed_ref: WeakRef = weakref(doomed)
	doomed.free()
	var freed_done: bool = await wait_until(func(): return Wardrobe.is_loaded("shoes"), 90.0)
	await get_tree().process_frame
	check(freed_done and doomed_ref.get_ref() == null, "build completes after its owner was freed (no crash, no call)")
	Wardrobe.reset_cache()
	var late := Listener.new()
	add_child(late)
	Wardrobe.ensure_kinds(["bottom"], late)
	Wardrobe.reset_cache()  # waits for the task; its queued result is now stale
	for i in 4:
		await get_tree().process_frame
	check(not Wardrobe.is_loaded("bottom") and not Wardrobe.is_pending("bottom") and late.calls.is_empty(),
		"result of a build started before reset_cache() is discarded")
	Wardrobe.ensure_kinds(["bottom"], late)
	var again: bool = await wait_until(func(): return Wardrobe.is_loaded("bottom"), 90.0)
	await get_tree().process_frame
	check(again and late.calls == ["bottom"], "a fresh request after reset builds and calls back")
	late.queue_free()

	await _realize_section(sync_digest)

	section("SimVisual: placeholder clothes, then the exact synchronous wardrobe")
	if not Library.has_model("character"):
		check(false, "character model available for the visual test")
		return
	var hoodie := _snapshot("mikina", "dziny", "tenisky")
	var dress := _snapshot("saty", "zadne", "lodicky")
	var barefoot := _snapshot("tricko", "kratasy", "bosy")
	check(not hoodie.is_empty() and not dress.is_empty() and not barefoot.is_empty(), "fictional fixture looks validate")
	# Reference: synchronous build in a fresh cache.
	Wardrobe.async_load = false
	Wardrobe.reset_cache()
	var ref_v = _visual(hoodie)
	var ref_names := _c5_names(ref_v)
	var ref_digest := _c5_mesh_digest(ref_v)
	var ref_v2 = _visual(dress)
	var dress_names := _c5_names(ref_v2)
	ref_v.queue_free()
	ref_v2.queue_free()
	check(ref_names.has("C5_top_hood") and dress_names.has("C5_dress_dress_lower"), "sync reference wardrobes built")
	# Async from a cold cache.
	Wardrobe.reset_cache()
	Wardrobe.async_load = true
	t0 = Time.get_ticks_usec()
	var v = _visual(hoodie)
	var spawn_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var vb = _visual(barefoot)
	var legacy: Dictionary = _legacy_visible(v)
	check(v.wardrobe_waiting() and v._c5_nodes.is_empty(), "first character waits instead of blocking")
	check(legacy.get("cloth_shirt", false) and legacy.get("cloth_pants", false) and legacy.get("shoe_leather", false),
		"placeholder: GLB shirt, trousers and shoes are shown (never a bare body)", str(legacy))
	var lb: Dictionary = _legacy_visible(vb)
	var feet_bare := true
	for f in vb._foot_detail_nodes:
		feet_bare = feet_bare and f.visible
	check(not lb.get("shoe_leather", true) and lb.get("cloth_shirt", false) and feet_bare,
		"placeholder respects coverage: barefoot outfit shows feet, no shoes", str(lb))
	print("  SimVisual spawn with cold wardrobe: %.0f ms on the main thread" % spawn_ms)
	# Outfit change while still waiting: the finished build must use the CURRENT look.
	var vd = _visual(hoodie)
	vd.apply_look(dress)
	var done: Dictionary = await _wait_sampling(func(): return not v.wardrobe_waiting() and not vd.wardrobe_waiting() and not vb.wardrobe_waiting(), 150.0)
	check(done["ok"], "visuals leave the placeholder when the background build ends")
	check(_c5_names(v) == ref_names and _c5_mesh_digest(v) == ref_digest,
		"async visual ends with exactly the synchronous garments, meshes and morph weights")
	var legacy_after: Dictionary = _legacy_visible(v)
	check(not legacy_after.get("cloth_shirt", true) and not legacy_after.get("cloth_pants", true)
		and not legacy_after.get("shoe_leather", true), "placeholder GLB clothes hidden again", str(legacy_after))
	check(_c5_names(vd) == dress_names, "outfit changed during the wait → the new outfit (dress) is built")
	# Outfit change with everything cached: immediate, no placeholder.
	vd.apply_look(hoodie)
	check(not vd.wardrobe_waiting() and _c5_names(vd) == ref_names, "cached outfit change applies in the same frame")
	# Visual freed while waiting.
	Wardrobe.reset_cache()
	var gone = _visual(hoodie)
	gone.queue_free()
	var settled: bool = await wait_until(func(): return _all_loaded(["top", "bottom", "shoes"]), 90.0)
	await get_tree().process_frame
	check(settled, "visual freed while waiting: build still settles without errors")
	for n in [v, vb, vd]:
		n.queue_free()
	listener.queue_free()
	Wardrobe.async_load = false
	await get_tree().process_frame
