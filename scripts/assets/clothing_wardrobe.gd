extends RefCounted
## C5: actual Blender-authored garment geometry (LSX bridge), not just recolouring.
## Loaded once; skinned garment meshes, ten body morph targets, and woven/knitted PBR tileables
## are shared by all SimVisual instances. Characters keep their own tint/material instances.
## See tools/blender/clothing_c5.py for reproducible source.

const LSX := preload("res://scripts/assets/lsx_decoder.gd")
const SOURCE := "res://assets/src/clothing_c5/"
const TEXTURES := "res://assets/textures/clothing_c5/"

const PARTS := ["top", "bottom", "shoes", "dress", "legs"]

## Blender LSX skeleton index order differs from the original character's Skin BIND order.
## A skinned garment must address Skin binds (not Skeleton3D bone indices).
## Original character skin binds: core, left arm, LEFT LEG, right arm, right leg.
## Exported LSX binds: core, left arm, RIGHT ARM, left leg, right leg.
## This remapping is essential; without it trousers can move with right-arm bones.
const C5_TO_CHARACTER_BIND := [0, 1, 2, 3, 4, 5, 6, 7, 11, 12, 13, 8, 9, 10, 14, 15, 16]
const LEG_OUTFITS := ["sukne", "kratasy", "punk_kostka", "goth_sukne", "kawaii_sukne", "harajuku_sukne"]

static var _loaded := {}
static var _textures := {}
static var _materials := {}

## Asynchronous loading (game only; H3 three-process join, 7 Nov 2026). The first decode of a
## garment kind (LSX + Catmull-Clark + sleeve fitting) costs 1.5–7 s on a slow host. On the main
## thread that froze a joining client long enough for ENet to drop the peer. With `async_load` the
## kind is built in the WorkerThreadPool; callers get {"ready": false} and a callback
## `owner._on_wardrobe_ready(kind)` on the main thread. The worker only computes plain arrays
## (`_build_kind`: LSX decode, Catmull-Clark, sleeve fitting, UV/tangents) and never touches the
## RenderingServer – a RenderingServer query from a worker waits for the main thread and could
## deadlock against a blocking wait. ArrayMesh + materials are made on the main thread
## (`_realize`). Both modes run the same two functions, so threaded and synchronous output is
## byte-identical. Headless tests stay synchronous unless they opt in. The cache dictionaries
## are guarded by `_mutex` (Godot's Mutex is reentrant).
static var async_load := false
static var _mutex := Mutex.new()
## kind -> {"gen": int, "task": int, "owners": [WeakRef]}; presence = build in flight
static var _pending := {}
## WorkerThreadPool task ids not yet waited for (every task must be waited exactly once).
static var _tasks := {}
## Bumped by reset_cache(): results of builds started earlier are discarded.
static var _generation := 0
## kind -> {"ms": wall time from request to cache, "build_ms": build time, "thread": bool}
static var load_stats := {}
## Frame-spread realisation (H3, 7 Nov 2026 evening). After a worker finished, `_finish` used to
## turn the whole kind into ArrayMeshes in ONE frame (top = 118 meshes with 10 blend shapes each,
## tens to hundreds of ms on a slow host). Now `_finish` stores a cursor in `_pending[kind]
## ["realize"]` and `_realize_frame` (connected to SceneTree.process_frame while work is queued)
## makes meshes until `realize_budget_usec` is spent – always at least one per frame. The
## synchronous `_realize` runs the very same cursor to the end, so both outputs stay identical.
## The kind stays "pending" (not "loaded") until its last mesh exists; owners registering during
## realisation are called back with the others.
static var _realize_order: Array = []
static var realize_budget_usec := 4000
## Longest main-thread time one `_realize_frame` call took since the last reset (diagnostics).
static var realize_max_frame_ms := 0.0
const _SELF := preload("res://scripts/assets/clothing_wardrobe.gd")


static func is_available() -> bool:
	return FileAccess.file_exists(SOURCE + "top.lsx") and FileAccess.file_exists(SOURCE + "bottom.lsx")


## Test hook. Waits for builds in flight, then drops every cache. Their queued results are stale
## (older generation) and are discarded; owners still waiting re-request on their next apply.
static func reset_cache() -> void:
	wait_for_builds()
	_mutex.lock()
	_generation += 1
	_pending.clear()
	_realize_order.clear()  # half-realised kinds are dropped; _realize_frame then disconnects itself
	realize_max_frame_ms = 0.0
	_loaded.clear()
	_materials.clear()
	_textures.clear()
	load_stats.clear()
	_mutex.unlock()


## Blocks until all garment build tasks have finished (tests, shutdown). Main thread only.
## The deferred _finish calls still run on a later frame.
static func wait_for_builds() -> void:
	_mutex.lock()
	var ids: Array = _tasks.keys()
	_tasks.clear()
	_mutex.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))


## Is a kind being built in the background? (tests, diagnostics)
static func is_pending(kind: String) -> bool:
	_mutex.lock()
	var r := _pending.has(kind)
	_mutex.unlock()
	return r


static func is_loaded(kind: String) -> bool:
	_mutex.lock()
	var r := _loaded.has(kind)
	_mutex.unlock()
	return r


static func _tex(name: String, suffix: String) -> Texture2D:
	var id := name + "_" + suffix
	_mutex.lock()
	if _textures.has(id):
		var cached: Texture2D = _textures[id]
		_mutex.unlock()
		return cached
	var path := TEXTURES + "C5_" + id + ".png"
	var texture: ImageTexture = null
	if FileAccess.file_exists(path):
		var im := Image.new()
		if im.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			texture = ImageTexture.create_from_image(im)
			_textures[id] = texture
	_mutex.unlock()
	return texture


## Shared base material per garment material name (main thread: _realize, material_instance,
## GarmentBuilder). Kept behind the mutex so a future threaded caller cannot create a second
## "shared" instance of the same material.
static func _mat(material_name: String) -> StandardMaterial3D:
	_mutex.lock()
	var mat := _mat_locked(material_name)
	_mutex.unlock()
	return mat


static func _mat_locked(material_name: String) -> StandardMaterial3D:
	if _materials.has(material_name):
		return _materials[material_name]
	var mat := StandardMaterial3D.new()
	var kind := material_name.trim_prefix("cloth_").trim_prefix("shoe_")
	if kind == "leather_c5":
		kind = "leather"
	mat.resource_name = material_name
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.89
	if kind in ["knit", "fleece"]:
		mat.roughness = 0.98
	elif kind == "satin":
		mat.roughness = 0.50
	elif kind == "suiting":
		mat.roughness = 0.72
	elif kind == "leather":
		mat.roughness = 0.46
	elif kind == "denim":
		mat.roughness = 0.84
	if kind == "skin_c5_legs" or material_name.begins_with("skin_"):
		mat.roughness = 0.62
	else:
		mat.albedo_texture = _tex(kind, "A")
		mat.normal_enabled = true
		mat.normal_texture = _tex(kind, "N")
		mat.normal_scale = 0.25
		if mat.normal_texture == null:
			mat.normal_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # both sides of thin skirt/sleeve panels
	_materials[material_name] = mat
	return mat


## H2b shoulder seam corrective for legacy C5 LSX, before bind remapping.
## The Blender source now authors the same higher two rings. This migration only
## recognizes the old 1.164/1.096m ring heights, so a freshly regenerated LSX is
## never offset twice. Every morph target gets the *same rest offset*, ensuring
## blend shapes remain relative to the revised base and remain deterministic.
static func _sleeve_join_delta(y: float) -> float:
	if absf(y - 1.164) < 0.001:
		return 0.045
	if absf(y - 1.096) < 0.002:
		return 0.012
	return 0.0


static func _rebuild_vertex_normals(arrays: Array, topology: PackedInt32Array = PackedInt32Array()) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = topology if not topology.is_empty() else arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or indices.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, indices.size(), 3):
		var ia: int = indices[t]
		var ib: int = indices[t + 1]
		var ic: int = indices[t + 2]
		var normal: Vector3 = (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		normals[ia] += normal
		normals[ib] += normal
		normals[ic] += normal
	var prior: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size():
		if normals[i].length_squared() > 0.000000001:
			normals[i] = normals[i].normalized()
		elif i < prior.size():
			normals[i] = prior[i]
		else:
			normals[i] = Vector3.UP
	arrays[Mesh.ARRAY_NORMAL] = normals


static func _fit_legacy_sleeve(arrays: Array, blend: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Source sleeve topology consists of exactly five 14-vertex rings.
	if verts.size() != 70:
		return
	var shifts := PackedFloat32Array()
	shifts.resize(verts.size())
	var top := 0
	var next_ring := 0
	for i in verts.size():
		var delta: float = _sleeve_join_delta(verts[i].y)
		shifts[i] = delta
		if delta > 0.03:
			top += 1
		elif delta > 0.0:
			next_ring += 1
	# Fail closed for unknown sources instead of half-changing a garment.
	if top != 14 or next_ring != 14:
		return
	# The legacy top two rings inherited ~73% FOREARM weight despite being
	# embedded in the upper shirt/shoulder shell. This detached the rim on an
	# elbow bend. Recover anatomically plausible weights from the authored ring
	# height, not from the old (wrong) nearest shirt sample. C5 bone IDs below
	# are in LSX order; remap to character Skin happens later in _textured_pack.
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bone_ids.size() != verts.size() * 4 or weights.size() != bone_ids.size():
		return
	for i in verts.size():
		if shifts[i] <= 0.0:
			continue
		var upper_id := 5 if verts[i].x > 0.0 else 8
		var forearm_id := upper_id + 1
		for k in 4:
			var w: float = weights[i * 4 + k]
			if w > 0.0001 and bone_ids[i * 4 + k] not in [upper_id, forearm_id]:
				return
	for i in verts.size():
		if shifts[i] > 0.0:
			var upper_id := 5 if verts[i].x > 0.0 else 8
			# Shoulder rim: upper-arm anchored. Next ring: smooth transition
			# towards the elbow, where forearm influence is physically expected.
			var forearm: float = 0.0 if shifts[i] > 0.03 else 0.36
			for k in 4:
				bone_ids[i * 4 + k] = upper_id if k == 0 else (upper_id + 1 if k == 1 else 0)
				weights[i * 4 + k] = (1.0 - forearm) if k == 0 else (forearm if k == 1 else 0.0)
			verts[i].y += shifts[i]
	arrays[Mesh.ARRAY_BONES] = bone_ids
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_VERTEX] = verts
	_rebuild_vertex_normals(arrays)
	for target in blend:
		var moved: PackedVector3Array = target[Mesh.ARRAY_VERTEX]
		for i in moved.size():
			if shifts[i] > 0.0:
				moved[i].y += shifts[i]
		target[Mesh.ARRAY_VERTEX] = moved
		_rebuild_vertex_normals(target, arrays[Mesh.ARRAY_INDEX])


## Legacy C5 hanging waist chains contain a duplicated central path sample:
## 12 rings x 6 vertices; rings 5 and 6 coincide, collapsing 12 triangles
## in each of three subculture bottoms. Match exact topology/duplicate
## coordinates before moving the second ring 6 mm vertically. The authored
## Blender generator uses the same asymmetry for new exports.
static func _repair_legacy_waist_chain(arrays: Array, blends: Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() != 72:
		return
	for k in 6:
		if vertices[30 + k].distance_to(vertices[36 + k]) > 0.00001:
			return
	for k in 6:
		vertices[36 + k].y += 0.006
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_rebuild_vertex_normals(arrays)
	for shape in blends:
		var moved: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
		if moved.size() != vertices.size():
			continue
		for k in 6:
			moved[36 + k].y += 0.006
		shape[Mesh.ARRAY_VERTEX] = moved
		_rebuild_vertex_normals(shape, arrays[Mesh.ARRAY_INDEX])


## Bring the sleeve rim into the matching shirt cross-section. Interpolate the
## SAME triangle's morphs and skin weights, so the seam follows torso motion.
## Retain 10% original rim spacing: no collapsed edge at a shell triangle corner.
## `shell` = the untouched part data of the matching shirt shell ({"arrays", "blend"} from
## LSX.scene_arrays, bones still in LSX order), or {} when the style has none.
static func _stitch_sleeve(arrays: Array, blends: Array, shell: Dictionary) -> void:
	if shell.is_empty():
		return
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	if points.size()!=70 or blends.size()!=(shell["blend"] as Array).size():
		return
	var src: Array=shell["arrays"]
	var sv: PackedVector3Array=src[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array=src[Mesh.ARRAY_INDEX]
	var sb: PackedInt32Array=src[Mesh.ARRAY_BONES]
	var sw: PackedFloat32Array=src[Mesh.ARRAY_WEIGHTS]
	var targets: Array=shell["blend"]
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var rim: Array=[]
	for i in points.size():
		if absf(points[i].y-1.209)<.001: rim.append(i)
	if rim.size()!=14: return
	for vi in rim:
		var p: Vector3=points[vi]
		var best: float=INF
		var tri: Array=[]
		var bary:=Vector3.ZERO
		for t in range(0,si.size(),3):
			var ids: Array=[si[t],si[t+1],si[t+2]]
			var cross_points: Array=[]
			var cross_bary: Array=[]
			for k in 3:
				var a: Vector3=sv[ids[k]]
				var b: Vector3=sv[ids[(k+1)%3]]
				if absf(b.y-a.y)<.000001: continue
				var f: float=(p.y-a.y)/(b.y-a.y)
				if f<0.0 or f>1.0: continue
				var w:=Vector3.ZERO
				w[k]=1.0-f
				w[(k+1)%3]=f
				cross_points.append(a.lerp(b,f))
				cross_bary.append(w)
			if cross_points.size()<2: continue
			var edge: Vector3=cross_points[1]-cross_points[0]
			if edge.length_squared()<1e-12: continue
			var f: float=clampf((p-cross_points[0]).dot(edge)/edge.length_squared(),0.0,1.0)
			var q: Vector3=cross_points[0]+edge*f
			var dist: float=p.distance_squared_to(q)
			if dist<best:
				best=dist
				tri=ids
				bary=(cross_bary[0] as Vector3).lerp(cross_bary[1],f)
		if tri.is_empty() or best>.08*.08: continue
		var q:=Vector3.ZERO
		for k in 3: q+=sv[tri[k]]*bary[k]
		points[vi]=p.lerp(q,.9)
		for j in blends.size():
			var v: PackedVector3Array=blends[j][Mesh.ARRAY_VERTEX]
			var tv: PackedVector3Array=targets[j][Mesh.ARRAY_VERTEX]
			var projected:=Vector3.ZERO
			for k in 3: projected+=tv[tri[k]]*bary[k]
			v[vi]=v[vi].lerp(projected,.9)
			blends[j][Mesh.ARRAY_VERTEX]=v
		var influences: Dictionary={}
		for k in 4:
			var id: int=bones[vi*4+k]
			influences[id]=float(influences.get(id,0.0))+.1*weights[vi*4+k]
		for k in 3:
			for j in 4:
				var id: int=C5_TO_CHARACTER_BIND[sb[tri[k]*4+j]]
				influences[id]=float(influences.get(id,0.0))+.9*bary[k]*sw[tri[k]*4+j]
		var ids: Array=influences.keys()
		ids.sort_custom(func(a,b):return influences[a]>influences[b])
		var total:=0.0
		for k in mini(4,ids.size()): total+=influences[ids[k]]
		for k in 4:
			bones[vi*4+k]=int(ids[k]) if k<ids.size() else 0
			weights[vi*4+k]=float(influences[ids[k]])/total if k<ids.size() else 0.0
	arrays[Mesh.ARRAY_VERTEX]=points
	arrays[Mesh.ARRAY_BONES]=bones
	arrays[Mesh.ARRAY_WEIGHTS]=weights
	_rebuild_vertex_normals(arrays)
	for target in blends: _rebuild_vertex_normals(target,arrays[Mesh.ARRAY_INDEX])


## The compact LSX stores mesh geometry but not UVs. Add deterministic world-oriented
## UV coordinates and approximate tangent frame without changing any blend shape or skin weights.
## Pure array work on a deep copy of `part` (thread-safe); returns the surface pack for _mesh_from_pack().
static func _textured_pack(part: Dictionary, piece: String = "", shell: Dictionary = {}) -> Dictionary:
	var arrays: Array = (part["arrays"] as Array).duplicate(true)
	var blend: Array = (part["blend"] as Array).duplicate(true)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if src_verts.is_empty():
		return {}
	if piece.begins_with("sleeve_"):
		_fit_legacy_sleeve(arrays, blend)
	elif piece == "waist_chain":
		_repair_legacy_waist_chain(arrays, blend)
	# LSX encodes bone IDs by its own Skin order; the existing avatar's Skin uses
	# a different bind order. Remap once while preparing the shared mesh.
	if arrays[Mesh.ARRAY_BONES] != null:
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for j in bones.size():
			var src_index := bones[j]
			if src_index >= 0 and src_index < C5_TO_CHARACTER_BIND.size():
				bones[j] = C5_TO_CHARACTER_BIND[src_index]
		arrays[Mesh.ARRAY_BONES] = bones
	if piece.begins_with("sleeve_"):
		_stitch_sleeve(arrays, blend, shell)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv := PackedVector2Array()
	var tangents := PackedFloat32Array()
	for i in verts.size():
		var v := verts[i]
		uv.append(Vector2(v.x * 7.0 + 0.5, v.y * 7.0))
		var n := norm[i] if i < norm.size() else Vector3.UP
		var axis := Vector3.RIGHT - n * n.x
		if axis.length_squared() < 0.00001:
			axis = Vector3.FORWARD - n * n.z
		axis = axis.normalized()
		tangents.append_array(PackedFloat32Array([axis.x, axis.y, axis.z, 1.0]))
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TANGENT] = tangents
	return {"arrays": arrays, "blend": blend, "morphs": part["morphs"] if not blend.is_empty() else [],
		"name": String(part["name"])}


## Main thread: ArrayMesh from a pack (cheap compared to the build), with the shared material.
static func _mesh_from_pack(pack: Dictionary, mat_name: String) -> ArrayMesh:
	if pack.is_empty():
		return null
	var m := ArrayMesh.new()
	var morphs: Array = pack["morphs"]
	if not morphs.is_empty():
		m.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		for nm in morphs:
			m.add_blend_shape(StringName(nm))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pack["arrays"], pack["blend"])
	m.surface_set_material(0, _mat(mat_name))
	m.resource_name = String(pack["name"])
	return m


## Main thread: turn a built kind ({style: [{"pack", ...}]}) into the cached form
## ({style: [{"mesh", "name", "material", "category"}]}).
static func _realize(built: Dictionary) -> Dictionary:
	var c := _realize_begin(built)
	while not _realize_one(c):
		pass
	return c["out"]


## Cursor over a built kind, in the dictionary/array order the one-shot loop always used.
static func _realize_begin(built: Dictionary) -> Dictionary:
	return {"built": built, "styles": built.keys(), "si": 0, "ei": 0, "list": [], "out": {},
		"meshes": 0, "frames": 0, "max_mesh_ms": 0.0}


## Makes at most one mesh (main thread). Returns true once the whole kind is realised.
static func _realize_one(c: Dictionary) -> bool:
	var styles: Array = c["styles"]
	while int(c["si"]) < styles.size():
		var style = styles[int(c["si"])]
		var elems: Array = (c["built"] as Dictionary)[style]
		var ei: int = int(c["ei"])
		if ei < elems.size():
			var e: Dictionary = elems[ei]
			c["ei"] = ei + 1
			var mesh := _mesh_from_pack(e["pack"], String(e["material"]))
			if mesh != null:
				(c["list"] as Array).append({"mesh": mesh, "name": e["name"], "material": e["material"],
					"category": e["category"]})
				c["meshes"] = int(c["meshes"]) + 1
			if int(c["ei"]) >= elems.size():
				_close_style(c, style)
			return int(c["si"]) >= styles.size()
		_close_style(c, style)
	return true


static func _close_style(c: Dictionary, style) -> void:
	if not (c["list"] as Array).is_empty():
		(c["out"] as Dictionary)[style] = c["list"]
	c["list"] = []
	c["si"] = int(c["si"]) + 1
	c["ei"] = 0


## Caller holds _mutex. Publishes a fully realised kind and returns the owners to notify.
static func _publish_locked(kind: String, entry: Dictionary) -> Array:
	var c: Dictionary = entry["realize"]
	_loaded[kind] = c["out"]
	load_stats[kind] = {"ms": (Time.get_ticks_usec() - int(entry["t0"])) / 1000.0,
		"build_ms": float(entry.get("build_ms", 0.0)), "thread": true,
		"realize_frames": int(c["frames"]), "realize_meshes": int(c["meshes"]),
		"realize_max_mesh_ms": float(c["max_mesh_ms"])}
	_pending.erase(kind)
	_realize_order.erase(kind)
	return entry["owners"]


## A synchronous request for a kind whose background result is being realised: finish the
## remaining meshes now instead of decoding the LSX a second time. Owners are notified on the
## next idle step (never re-entrantly inside the caller's apply). Returns false if not realising.
static func _complete_realizing(kind: String) -> bool:
	_mutex.lock()
	var entry: Dictionary = _pending.get(kind, {})
	if entry.is_empty() or not entry.has("realize"):
		_mutex.unlock()
		return false
	var c: Dictionary = entry["realize"]
	while not _realize_one(c):
		pass
	var owners := _publish_locked(kind, entry)
	_mutex.unlock()
	if not owners.is_empty():
		Callable(_SELF, "_notify").call_deferred(kind, owners)
	return true


## Main thread, once per frame while kinds wait for realisation.
static func _realize_frame() -> void:
	var t0 := Time.get_ticks_usec()
	var done: Array = []
	var touched := {}
	_mutex.lock()
	while not _realize_order.is_empty():
		var kind := String(_realize_order[0])
		var entry: Dictionary = _pending.get(kind, {})
		if entry.is_empty() or not entry.has("realize"):
			_realize_order.remove_at(0)
			continue
		var c: Dictionary = entry["realize"]
		if not touched.has(kind):
			touched[kind] = true
			c["frames"] = int(c["frames"]) + 1
		var s0 := Time.get_ticks_usec()
		var finished := _realize_one(c)
		c["max_mesh_ms"] = maxf(float(c["max_mesh_ms"]), (Time.get_ticks_usec() - s0) / 1000.0)
		if finished:
			done.append([kind, _publish_locked(kind, entry)])
		if Time.get_ticks_usec() - t0 >= realize_budget_usec:
			break
	var idle := _realize_order.is_empty()
	realize_max_frame_ms = maxf(realize_max_frame_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	_mutex.unlock()
	if idle:
		_set_driver(false)
	for d in done:
		_notify(String(d[0]), d[1])


static func _set_driver(on: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var cb := Callable(_SELF, "_realize_frame")
	if on and not tree.process_frame.is_connected(cb):
		tree.process_frame.connect(cb)
	elif not on and tree.process_frame.is_connected(cb):
		tree.process_frame.disconnect(cb)


## Is a background result being turned into meshes right now? (tests, diagnostics)
static func is_realizing(kind: String) -> bool:
	_mutex.lock()
	var r := _pending.has(kind) and (_pending[kind] as Dictionary).has("realize")
	_mutex.unlock()
	return r


static func _notify(kind: String, owners: Array) -> void:
	for w in owners:
		var o = (w as WeakRef).get_ref()
		if o != null and is_instance_valid(o) and o.has_method("_on_wardrobe_ready"):
			o._on_wardrobe_ready(kind)


## Synchronous load of one kind (default; tests, editor preview, async disabled). If a background
## build of the same kind is in flight, this still builds on the caller's thread – correctness
## over speed – and the later background result is discarded as a duplicate. If the background
## result already exists and is only being realised over frames, the rest is realised right here.
static func _load(kind: String) -> void:
	if is_loaded(kind):
		return
	if _complete_realizing(kind):
		return
	var t0 := Time.get_ticks_usec()
	var built := _realize(_build_kind(kind))
	_mutex.lock()
	if not _loaded.has(kind):
		_loaded[kind] = built
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		load_stats[kind] = {"ms": ms, "build_ms": ms, "thread": false}
	_mutex.unlock()


## Builds every style of one garment kind as plain arrays. No RenderingServer, node or shared
## cache access, so it is safe on a worker thread. Returns {style: [{"pack", "name", "material",
## "category"}]}; {} for a missing or corrupt source (cached as "no garments").
static func _build_kind(kind: String) -> Dictionary:
	var out := {}
	var path := SOURCE + kind + ".lsx"
	if not FileAccess.file_exists(path):
		return out
	var decoded := LSX.decode(FileAccess.get_file_as_string(path))
	if decoded.is_empty():
		push_warning("C5: poškozený soubor oblečení " + path)
		return out
	var pieces := LSX.scene_arrays(decoded)
	if pieces.is_empty():
		push_warning("C5: nelze sestavit model oblečení " + path)
		return out
	var shells: Dictionary = {}
	for p in pieces:
		var tokens := String(p["name"]).split("__")
		if tokens.size() >= 6 and tokens[4] == "shell":
			shells[tokens[3]] = p
	for p in pieces:
		# "<group>__C5__<part>__<style>__<piece>__<material>"
		var tokens := String(p["name"]).split("__")
		if tokens.size() < 6 or tokens[1] != "C5" or tokens[2] != kind:
			continue
		var style := String(tokens[3])
		var mat_name := String(tokens[-1])
		var pack := _textured_pack(p, String(tokens[4]), shells.get(style, {}))
		if pack.is_empty():
			continue
		if not out.has(style):
			out[style] = []
		out[style].append({"pack": pack, "name": String(tokens[4]), "material": mat_name, "category": kind})
	return out


static func parts(kind: String, style: String) -> Array:
	_load(kind)
	_mutex.lock()
	var res: Array = _loaded.get(kind, {}).get(style, [])
	_mutex.unlock()
	return res


## [kind, style] pairs an outfit needs, in draw order (shared by the sync and async paths).
static func wanted(lp: Dictionary) -> Array:
	var res := []
	var top := String(lp.get("outfit_top", "tricko"))
	var bottom := String(lp.get("outfit_bottom", "dziny"))
	var shoes := String(lp.get("outfit_shoes", "tenisky"))
	res.append(["top", top])
	if top == "saty":
		res.append(["dress", "saty"])
	elif bottom != "zadne":
		res.append(["bottom", bottom])
	if bottom in LEG_OUTFITS or top == "saty":
		res.append(["legs", "skin"])
	if shoes != "bosy":
		res.append(["shoes", shoes])
	return res


static func active_parts(lp: Dictionary) -> Array:
	var res := []
	for w in wanted(lp):
		res.append_array(parts(String(w[0]), String(w[1])))
	return res


## Garment kinds a look needs. A tailored design (Clothing Studio, GarmentBuilder) may also read
## "legs" and the dress parts, so any non-empty garment_designs needs every kind.
static func kinds_for(lp: Dictionary) -> Array:
	var designs: Variant = lp.get("garment_designs", {})
	if designs is Dictionary and not (designs as Dictionary).is_empty():
		return PARTS.duplicate()
	var res: Array = []
	for w in wanted(lp):
		if not res.has(w[0]):
			res.append(w[0])
	return res


## For a SimVisual: are these kinds ready to use without blocking? true when all are cached or
## async_load is off (the caller then loads synchronously, exactly as before). Otherwise starts
## background builds of the missing kinds, registers `owner` weakly and returns false; the owner
## gets `_on_wardrobe_ready(kind)` on the main thread once per finished kind (if still alive).
static func ensure_kinds(kinds: Array, owner: Object) -> bool:
	if not async_load:
		return true
	var missing: Array = []
	_mutex.lock()
	for kind in kinds:
		if not _loaded.has(kind) and not missing.has(kind):
			missing.append(kind)
	_mutex.unlock()
	for kind in missing:
		_start_build(String(kind), owner)
	return missing.is_empty()


## Game start: build all garment kinds in the background so the first characters rarely wait.
## No-op unless async_load. Returns the number of kinds that were queued.
static func prewarm_async() -> int:
	if not async_load or not is_available():
		return 0
	var started := 0
	for kind in PARTS:
		if not is_loaded(kind):
			_start_build(String(kind), null)
			started += 1
	return started


static func _start_build(kind: String, owner: Object) -> void:
	_mutex.lock()
	if _loaded.has(kind):
		_mutex.unlock()
		return
	var first := not _pending.has(kind)
	if first:
		_pending[kind] = {"gen": _generation, "task": -1, "owners": [], "t0": Time.get_ticks_usec()}
	if owner != null:
		var owners: Array = _pending[kind]["owners"]
		var known := false
		for w in owners:
			if (w as WeakRef).get_ref() == owner:
				known = true
				break
		if not known:
			owners.append(weakref(owner))
	var gen: int = _generation
	_mutex.unlock()
	if first:
		var id := WorkerThreadPool.add_task(Callable(_SELF, "_task").bind(kind, gen), false, "wardrobe " + kind)
		_mutex.lock()
		_tasks[id] = true
		if _pending.has(kind) and int(_pending[kind]["gen"]) == gen:
			_pending[kind]["task"] = id
		_mutex.unlock()


## Worker thread.
static func _task(kind: String, gen: int) -> void:
	var t0 := Time.get_ticks_usec()
	var built := _build_kind(kind)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	Callable(_SELF, "_finish").call_deferred(kind, gen, built, build_ms)


## Main thread: queue the result for frame-spread realisation (unless stale or already built
## synchronously, in which case the owners are notified right away).
static func _finish(kind: String, gen: int, built: Dictionary, build_ms: float) -> void:
	var owners: Array = []
	var task_id := -1
	var queued := false
	_mutex.lock()
	var entry: Dictionary = _pending.get(kind, {})
	if not entry.is_empty() and int(entry["gen"]) == gen and not entry.has("realize"):
		task_id = int(entry["task"])
		if gen == _generation and not _loaded.has(kind):
			entry["realize"] = _realize_begin(built)
			entry["build_ms"] = build_ms
			_realize_order.append(kind)
			queued = true
		else:
			owners = entry["owners"]
			_pending.erase(kind)
	if task_id >= 0 and _tasks.has(task_id):
		_tasks.erase(task_id)
	else:
		task_id = -1
	_mutex.unlock()
	if task_id >= 0:
		# The task body has already returned (this call was queued at its end), so this is immediate.
		WorkerThreadPool.wait_for_task_completion(task_id)
	if queued:
		if Engine.get_main_loop() is SceneTree:
			_set_driver(true)
		else:
			_complete_realizing(kind)  # no frames to spread over
	_notify(kind, owners)


static func tint(info: Dictionary, lp: Dictionary) -> Color:
	var mat_name := String(info.get("material", ""))
	var part := String(info.get("name", ""))
	# Cat applique keeps its own palette; the garment fabric remains independently tintable.
	if String(info.get("category", "")) == "top" and String(lp.get("outfit_top", "")) == "kawaii_kocici_mikina":
		if part == "cat_face" or part.begins_with("motif_ear_"):
			return Color(0.94, 0.91, 0.86)
		if part.begins_with("cat_eye_") or part.begins_with("whisker_"):
			return Color(0.06, 0.045, 0.065)
		if part == "cat_nose":
			return Color(0.55, 0.16, 0.28)
	if mat_name.begins_with("skin_"):
		return lp.get("skin", Color(0.8, 0.6, 0.45))
	if String(info.get("category", "")) == "shoes":
		return Color(0.22, 0.20, 0.19) if String(lp.get("outfit_shoes", "")) != "tenisky" else Color(0.71, 0.69, 0.67)
	if String(info.get("category", "")) == "bottom":
		return lp.get("bottom", Color(0.22, 0.25, 0.30))
	if mat_name == "cloth_denim":
		return lp.get("bottom", Color(0.2, 0.25, 0.3))
	if part.begins_with("pleated_skirt") or part.begins_with("cropped_pants"):
		return lp.get("bottom", Color(0.2, 0.25, 0.3))
	return lp.get("top", Color(0.35, 0.42, 0.48))


static func material_instance(info: Dictionary, lp: Dictionary) -> StandardMaterial3D:
	var material_name := String(info.get("material", "cloth_cotton"))
	var copy := (_mat(material_name) as StandardMaterial3D).duplicate() as StandardMaterial3D
	copy.albedo_color = tint(info, lp)
	return copy


static func stats() -> Dictionary:
	var out := {}
	for kind in PARTS:
		_load(kind)
		_mutex.lock()
		var styles: Dictionary = _loaded[kind]
		_mutex.unlock()
		var count := 0
		for style in styles:
			count += styles[style].size()
		out[kind] = {"styles": styles.size(), "meshes": count}
	return out
