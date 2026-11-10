extends Node
## H3 test-only cold-path attribution. Run each mode in a fresh Godot OS process.
## Times are elapsed wall-clock milliseconds, NOT CPU time or multiplayer acceptance.
const HairRig = preload("res://scripts/assets/hair_rig.gd")
const Wardrobe = preload("res://scripts/assets/clothing_wardrobe.gd")
const GarmentBuilder = preload("res://scripts/clothing/garment_builder.gd")
const SOURCE_SHA = {
	"res://scripts/assets/hair_rig.gd": "9a424585912a8fbb6334f920de91846c15e7e98e850b9b30dfad17c7b90bcb31",
	"res://scripts/assets/clothing_wardrobe.gd": "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f",
	"res://scripts/clothing/garment_builder.gd": "e6bdb8aa966d7f500389b15e87f2c8c2371e68fbbdbdfd4236d065a86b8d5dfc"
}

func _ready() -> void:
	_run.call_deferred()

func _emit(phase: String, started: int, count: int = -1) -> void:
	print("H3_SUBPHASE " + JSON.stringify({"phase": phase, "ms": (Time.get_ticks_usec() - started) / 1000.0, "count": count}))

func _run() -> void:
	for path in SOURCE_SHA:
		if FileAccess.get_sha256(path) != SOURCE_SHA[path]:
			push_error("H3 subphase source changed: " + path)
			get_tree().quit(2)
			return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = String(args[0]) if args.size() > 0 else "hair"
	var ok := false
	match mode:
		"hair":
			ok = _hair()
		"hair_variants":
			ok = _hair_variants()
		"hair_cold_styles":
			ok = _hair_cold_styles()
		"wardrobe":
			ok = _wardrobe()
		"garment_cold":
			ok = _garment_cold()
		_:
			push_error("H3 subphase unknown mode: " + mode)
	print("H3_SUBPHASE_RESULT " + JSON.stringify({"mode": mode, "ok": ok}))
	get_tree().quit(0 if ok else 2)

func _hair() -> bool:
	var t: int = Time.get_ticks_usec()
	var source: Dictionary = HairRig.source()
	_emit("hair_source", t, source.size())
	if source.is_empty():
		return false
	t = Time.get_ticks_usec()
	var ctx: Dictionary = HairRig.context()
	_emit("hair_context", t, ctx.size())
	if ctx.is_empty():
		return false
	t = Time.get_ticks_usec()
	var pack: Dictionary = HairRig.build_pack("scalp", "kratke")
	_emit("hair_build_pack_after_context", t, int(pack.get("verts", 0)))
	if not pack.has("arrays") or int(pack.get("verts", 0)) <= 0:
		return false
	t = Time.get_ticks_usec()
	var mesh: ArrayMesh = HairRig.mesh_from_pack(pack)
	_emit("hair_mesh_from_pack", t, mesh.get_surface_count() if mesh != null else 0)
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	t = Time.get_ticks_usec()
	var first: ArrayMesh = HairRig.mesh_for("scalp", "kratke")
	_emit("hair_mesh_for_first_after_source_context", t, first.get_surface_count() if first != null else 0)
	t = Time.get_ticks_usec()
	var second: ArrayMesh = HairRig.mesh_for("scalp", "kratke")
	_emit("hair_mesh_for_cache_hit", t, second.get_surface_count() if second != null else 0)
	return first != null and first == second and first.get_surface_count() > 0

func _wardrobe() -> bool:
	var t: int = Time.get_ticks_usec()
	var tops: Array = Wardrobe.parts("top", "tricko")
	_emit("wardrobe_first_top_kind", t, tops.size())
	t = Time.get_ticks_usec()
	var bottoms: Array = Wardrobe.parts("bottom", "dziny")
	_emit("wardrobe_first_bottom_kind", t, bottoms.size())
	t = Time.get_ticks_usec()
	var shoes: Array = Wardrobe.parts("shoes", "tenisky")
	_emit("wardrobe_first_shoes_kind", t, shoes.size())
	var lp := {"outfit_top": "tricko", "outfit_bottom": "dziny", "outfit_shoes": "tenisky"}
	t = Time.get_ticks_usec()
	var active: Array = Wardrobe.active_parts(lp)
	_emit("wardrobe_active_after_kind_load", t, active.size())
	t = Time.get_ticks_usec()
	var garment: Array = GarmentBuilder.parts(lp)
	_emit("garment_after_kind_load", t, garment.size())
	return tops.size() > 0 and bottoms.size() > 0 and shoes.size() > 0 and garment.size() == active.size()

func _garment_cold() -> bool:
	var lp := {"outfit_top": "tricko", "outfit_bottom": "dziny", "outfit_shoes": "tenisky"}
	var t: int = Time.get_ticks_usec()
	var first: Array = GarmentBuilder.parts(lp)
	_emit("garment_first_cold", t, first.size())
	t = Time.get_ticks_usec()
	var second: Array = GarmentBuilder.parts(lp)
	_emit("garment_second_warm", t, second.size())
	return first.size() > 0 and first.size() == second.size()
## Regression: distinct cold styles must not alias the same cached geometry.
func _hair_variants() -> bool:
	var first: ArrayMesh = HairRig.mesh_for("scalp", "kratke")
	var other: ArrayMesh = HairRig.mesh_for("scalp", "stredni")
	var again: ArrayMesh = HairRig.mesh_for("scalp", "kratke")
	var valid := first != null and other != null and first.get_surface_count() > 0 and other.get_surface_count() > 0
	var distinct := first != other
	var stable := first == again
	var different_vertices := false
	if valid:
		var a: PackedVector3Array = first.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = other.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		different_vertices = a.size() > 0 and b.size() > 0 and a != b
		for v in a:
			if not is_finite(v.x) or not is_finite(v.y) or not is_finite(v.z):
				different_vertices = false
				break
		for v in b:
			if not is_finite(v.x) or not is_finite(v.y) or not is_finite(v.z):
				different_vertices = false
				break
	var topology_ok := valid
	if valid:
		for mesh in [first, other]:
			var arrays: Array = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if indices.is_empty() or indices.size() % 3 != 0 or normals.size() != verts.size():
				topology_ok = false
				break
			for index in indices:
				if index < 0 or index >= verts.size():
					topology_ok = false
					break
			for normal in normals:
				if not is_finite(normal.x) or not is_finite(normal.y) or not is_finite(normal.z):
					topology_ok = false
					break
	print("H3_VARIANT_CACHE " + JSON.stringify({"valid": valid, "distinct": distinct, "stable": stable, "different_vertices": different_vertices, "topology_ok": topology_ok}))
	return valid and distinct and stable and different_vertices and topology_ok

## Test-only cold vs warm style timing; each invocation must use a fresh process.
## Reports wall-clock elapsed time, not proof of multiplayer causality.
func _hair_cold_styles() -> bool:
	var names := ["kratke", "stredni"]
	var meshes: Array[ArrayMesh] = []
	for style in names:
		var started := Time.get_ticks_usec()
		var mesh: ArrayMesh = HairRig.mesh_for("scalp", style)
		_emit("hair_style_first_" + style, started, mesh.get_surface_count() if mesh != null else 0)
		if mesh == null or mesh.get_surface_count() < 1:
			return false
		meshes.append(mesh)
	for i in range(names.size()):
		var started := Time.get_ticks_usec()
		var cached: ArrayMesh = HairRig.mesh_for("scalp", names[i])
		_emit("hair_style_cached_" + names[i], started, cached.get_surface_count() if cached != null else 0)
		if cached != meshes[i]:
			return false
	return meshes[0] != meshes[1]
