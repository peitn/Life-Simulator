extends RefCounted
## Jednorázová úprava SimVisual pro C-LOD krok 6 (zapečení blend shapes ve stupni 2). Každá náhrada musí
## sedět přesně jednou, jinak se nic nezapíše.

const P := "res://scripts/sim/sim_visual.gd"

const NEW_FUNCS := """

# ======================================================================================
# C-LOD krok 6 (18. 11. 2026): zapečení blend shapes ve stupni 2
# ======================================================================================
## Ve stupni 2 se viditelné sítě s blend shapes (kromě rukou – pózy prstů čtou a píšou váhy) nahradí
## statickou sítí s aplikovanými vahami (LodBake, ve vlákně). Každá změna vah nebo sítí (_lod_touch) zapečení
## zruší a obnoví původní síť s přesně uloženými vahami; po LOD_BAKE_DELAY klidu se zapeče znovu.

## Původní síť instance (i když je právě zapečená).
func lod_source_mesh(mi: MeshInstance3D) -> Mesh:
	if mi == null:
		return null
	var e = _lb_entries.get(mi)
	if e != null and mi.mesh == e[1]:
		return e[0]
	return mi.mesh


## Kolik instancí má právě zapečenou síť (testy, diagnostika).
func lod_baked_count() -> int:
	var n := 0
	for mi in _lb_entries:
		if is_instance_valid(mi) and (mi as MeshInstance3D).mesh == _lb_entries[mi][1]:
			n += 1
	return n


## Čeká se na zapečení (odpočet nebo běžící úloha)?
func lod_bake_pending() -> bool:
	return _lb_task >= 0 or (_lb_dirty and _lod_tier >= 2)


## Váhy nebo sítě se mění: zrušit zapečení (i rozpracované) a ve stupni 2 naplánovat nové.
func _lod_touch() -> void:
	_lb_gen += 1
	if not _lb_entries.is_empty():
		_lod_unbake()
	if _lod_tier >= 2:
		_lb_dirty = true
		_lb_wait = LOD_BAKE_DELAY


## Vrátí původní sítě a jejich váhy. Instance, které mezitím dostaly jinou síť, se nechají být.
func _lod_unbake() -> void:
	for mi in _lb_entries:
		if not is_instance_valid(mi):
			continue
		var e: Array = _lb_entries[mi]
		if (mi as MeshInstance3D).mesh != e[1]:
			continue
		(mi as MeshInstance3D).mesh = e[0]
		var w: PackedFloat32Array = e[2]
		for i in mini(w.size(), (mi as MeshInstance3D).get_blend_shape_count()):
			(mi as MeshInstance3D).set_blend_shape_value(i, w[i])
	_lb_entries = {}


func _lod_bake_tick(delta: float) -> void:
	if _lb_task >= 0:
		if WorkerThreadPool.is_task_completed(_lb_task):
			WorkerThreadPool.wait_for_task_completion(_lb_task)
			_lb_task = -1
			_lod_bake_finish()
		return
	if not _lb_dirty or _lod_tier < 2 or _model == null or not LodBake.enabled:
		return
	_lb_wait -= delta
	if _lb_wait > 0.0 or _hair_waiting or wardrobe_waiting():
		return
	_lod_bake_start()


func _lod_bake_start() -> void:
	_lb_dirty = false
	var items: Array = []
	var instant := 0
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or _hand_detail_nodes.has(mi):
			continue
		if _lb_entries.has(mi):
			if mi.mesh == _lb_entries[mi][1]:
				continue
			_lb_entries.erase(mi)
		var m := mi.mesh as ArrayMesh
		if m == null or m.get_blend_shape_count() == 0:
			continue
		var w := PackedFloat32Array()
		w.resize(m.get_blend_shape_count())
		var ok := true
		for i in w.size():
			w[i] = mi.get_blend_shape_value(i)
			ok = ok and is_finite(w[i])
		if not ok:
			continue
		var hit := LodBake.baked_cached(m, w)
		if hit != null:
			if _lod_swap(mi, m, w, hit):
				instant += 1
			continue
		items.append({"mi": mi, "mesh": m, "w": w, "src": LodBake.source_cached(m), "raw": null})
	for it in items:
		if it["src"] == null:
			it["raw"] = LodBake.raw_of(it["mesh"])
	if items.is_empty():
		if instant > 0:
			lod_bakes += 1
		return
	_lb_job = {"items": items, "gen": _lb_gen}
	if LodBake.async:
		_lb_task = WorkerThreadPool.add_task(LodBake.run_job.bind(_lb_job), false, "lod_bake")
	else:
		LodBake.run_job(_lb_job)
		_lod_bake_finish()


## Výměna sítě, jen když instance pořád ukazuje stejnou síť se stejnými vahami.
func _lod_swap(mi: MeshInstance3D, m: Mesh, w: PackedFloat32Array, baked: ArrayMesh) -> bool:
	if baked == null or not is_instance_valid(mi) or mi.mesh != m or mi.get_blend_shape_count() != w.size():
		return false
	for i in w.size():
		if mi.get_blend_shape_value(i) != w[i]:
			return false
	mi.mesh = baked
	_lb_entries[mi] = [m, baked, w]
	return true


func _lod_bake_finish() -> void:
	var job := _lb_job
	_lb_job = {}
	if job.is_empty():
		return
	LodBake.note_job(job)
	for it in job["items"]:
		if bool(it.get("built", false)):
			LodBake.store_source(it["mesh"], it["src"])
		if it.get("baked") != null:
			LodBake.store_baked(it["mesh"], it["w"], it["baked"])
	# Zastaralá úloha (mezitím _lod_touch nebo odchod ze stupně 2): výsledky jen do cache.
	if int(job["gen"]) != _lb_gen or _lod_tier < 2 or _model == null:
		return
	for it in job["items"]:
		_lod_swap(it["mi"], it["mesh"], it["w"], it.get("baked"))
	lod_bakes += 1


func _exit_tree() -> void:
	# Úloha nesahá na scénu, ale výsledek se má zahodit dřív, než uzel zmizí.
	if _lb_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_lb_task)
		_lb_task = -1
		_lb_job = {}
		_lb_dirty = _lod_tier >= 2
"""


static func apply() -> int:
	var t := FileAccess.open(P, FileAccess.READ).get_as_text()
	var reps := [
		["const CharacterLod := preload(\"res://scripts/assets/character_lod.gd\")\n",
		 "const CharacterLod := preload(\"res://scripts/assets/character_lod.gd\")\nconst LodBake := preload(\"res://scripts/assets/lod_bake.gd\")\n"],
		["var _lod_mouth_nodes: Array = []\n",
		 "var _lod_mouth_nodes: Array = []\n## C-LOD krok 6: zapečené sítě ve stupni 2 (MeshInstance3D -> [původní síť, zapečená síť, váhy]).\nvar _lb_entries := {}\nvar _lb_dirty := false\nvar _lb_wait := 0.0\nvar _lb_task := -1\nvar _lb_job: Dictionary = {}\nvar _lb_gen := 0\n## Kolikrát se postava zapekla (testy – opakované pečení bez změny = chyba).\nvar lod_bakes := 0\n## Klid ve stupni 2 před zapečením (s) – postava, která stupněm 2 jen projde, se nepeče.\nconst LOD_BAKE_DELAY := 0.4\n"],
		["func apply_look(snap: Dictionary) -> void:\n",
		 "func apply_look(snap: Dictionary) -> void:\n\t_lod_touch()\n"],
		["\t_lod_tick(delta)\n",
		 "\t_lod_tick(delta)\n\t_lod_bake_tick(delta)\n"],
		["\t_lod_tier = t\n\t_lod_expr_acc = 0.0\n",
		 "\t_lod_tier = t\n\t_lod_expr_acc = 0.0\n\tif t < 2 and prev >= 2:\n\t\t_lod_unbake()\n\t\t_lb_dirty = false\n\t\t_lb_gen += 1\n"],
		["\tif t >= 2 and prev < 2:\n\t\t_freeze_expression()\n\treturn true\n",
		 "\tif t >= 2 and prev < 2:\n\t\t_freeze_expression()\n\t\t_lb_dirty = true\n\t\t_lb_wait = LOD_BAKE_DELAY\n\treturn true\n"],
		["\tif _af_valid and w == _af_w and wb == _af_b:\n\t\treturn _af_count\n",
		 "\tif _af_valid and w == _af_w and wb == _af_b:\n\t\treturn _af_count\n\t_lod_touch()\n"],
		["\tvar w: Dictionary = lp.get(\"body\", {})\n\tvar count := 0\n\t# Base body remains",
		 "\tvar w: Dictionary = lp.get(\"body\", {})\n\t_lod_touch()\n\tvar count := 0\n\t# Base body remains"],
		["\tif _hair_proxy.mesh != m:\n",
		 "\tif lod_source_mesh(_hair_proxy) != m:\n"],
		["\t_ex_last = {}   # nové sítě (vlasy) musí dostat aktuální výraz\n",
		 "\t_ex_last = {}   # nové sítě (vlasy) musí dostat aktuální výraz\n\t_lod_touch()\n"],
		["func _write_expression(force := false) -> int:\n",
		 "func _write_expression(force := false) -> int:\n\t# Zapečené sítě nemají blend shapes: bez vynucení nic, s vynucením (cutscéna, test) zapečení zrušit.\n\tif not _lb_entries.is_empty() or _lb_task >= 0:\n\t\tif not force:\n\t\t\treturn 0\n\t\t_lod_touch()\n"],
	]
	for r in reps:
		var c := t.count(r[0])
		if c != 1:
			printerr("NÁHRADA NESEDÍ (%d×): %s" % [c, r[0].substr(0, 60)])
			return 1
		t = t.replace(r[0], r[1])
	t = t.rstrip("\n") + "\n" + NEW_FUNCS
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	print("OK md5 ", FileAccess.get_md5(P))
	return 0
