extends RefCounted
## C5 stage 1: morph-compatible tailored variants from existing Blender garment surfaces.
## Each result retains the original skeleton weights and ALL body blend shapes.
## Full separate Blender-authored cuts (dresses, skirts, coat tails) come in stage 2.
## The shape transforms here are modest by design: no severe intersections at extremes.

const Schema := preload("res://scripts/character/character_schema.gd")

const TOPS := {
	"tricko": [1.0, 0.0, 0.0],
	"tilko": [0.965, 0.0, 0.0],
	"kosile": [1.025, 0.0, 0.0],
	"halenka": [1.04, 0.0, -0.018],
	"svetr": [1.065, 0.0, 0.0],
	"rolak": [1.05, 0.0, 0.0],
	"mikina": [1.115, 0.0, -0.025],
	"sako": [1.075, 0.0, 0.01],
	"saty": [1.10, 0.0, -0.040],
	"pyzamo": [1.075, 0.0, -0.01],
	"sportovni": [0.975, 0.0, 0.0],
}
const BOTTOMS := {
	"dziny": [1.0, 0.0, 0.0],
	"kalhoty": [1.04, 0.0, 0.0],
	"oblekove": [1.045, 0.0, 0.0],
	"kratasy": [1.065, 0.0, 0.0], # placeholder cut until shorter Blender mesh stage
	"sukne": [1.08, 0.0, 0.0],   # placeholder cut until skirt geometry stage
	"teplaky": [1.12, 0.0, 0.0],
	"leginy": [0.985, 0.0, 0.0],
	"pyzamo": [1.1, 0.0, 0.0],
	"zadne": [1.0, 0.0, 0.0],
}
const SHOES := {
	"tenisky": 1.0, "polobotky": 0.985, "kozacky": 1.07,
	"lodicky": 0.96, "sandaly": 0.985, "pracovni": 1.07,
	"bacory": 1.065, "bosy": 1.0,
}
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func variant_mesh(source: Mesh, part: String, garment: String) -> ArrayMesh:
	if source == null or not (source is ArrayMesh):
		return null
	var key := "%d/%s/%s" % [source.get_instance_id(), part, garment]
	if _cache.has(key):
		return _cache[key]
	var cfg: Array = TOPS.get(garment, TOPS["tricko"]) if part == "top" else 		(BOTTOMS.get(garment, BOTTOMS["dziny"]) if part == "bottom" else [SHOES.get(garment, 1.0), 0.0, 0.0])
	var width := float(cfg[0])
	if is_equal_approx(width, 1.0) and is_zero_approx(float(cfg[2])):
		_cache[key] = source
		return source
	var out := ArrayMesh.new()
	out.blend_shape_mode = source.blend_shape_mode
	for k in source.get_blend_shape_count():
		out.add_blend_shape(source.get_blend_shape_name(k))
	for surf in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surf)
		arrays = arrays.duplicate(true)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays[Mesh.ARRAY_VERTEX] = _adjust(verts, part, width, float(cfg[2]))
		var blends: Array = source.surface_get_blend_shape_arrays(surf).duplicate(true)
		for j in blends.size():
			var vv: PackedVector3Array = blends[j][Mesh.ARRAY_VERTEX]
			blends[j][Mesh.ARRAY_VERTEX] = _adjust(vv, part, width, float(cfg[2]))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
		out.surface_set_material(surf, source.surface_get_material(surf))
	out.resource_name = "C5_" + garment
	_cache[key] = out
	return out


## Small radial fit variation in X/Z, no change to shoulders' joint positions.
## Changes are applied identically to base and target geometry, preserving linear blendshapes.
static func _adjust(verts: PackedVector3Array, part: String, width: float, hem_extension: float) -> PackedVector3Array:
	var out := verts.duplicate()
	for i in out.size():
		var p := out[i]
		var factor := width
		if part == "top":
			# shoulders and neckline stay close to base for stable skinning.
			var upper := smoothstep(1.32, 1.52, p.y)
			factor = lerpf(width, 1.0 + (width - 1.0) * 0.35, upper)
			if p.y < 1.24:
				p.y += hem_extension * smoothstep(1.26, 1.03, p.y)
		elif part == "bottom":
			# lower legs are freer in loose cuts; upper hips must fit the waist.
			factor = lerpf(width, 1.0 + (width - 1.0) * 0.45, smoothstep(0.75, 1.03, p.y))
		p.x *= factor
		p.z *= factor
		out[i] = p
	return out


static func garment_material(garment: String, part: String, base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = ("cloth_" if part != "shoe" else "shoe_") + garment
	mat.albedo_color = base_color
	mat.roughness = 0.91
	mat.metallic = 0.0
	match garment:
		"dziny":
			mat.roughness = 0.88
		"leginy", "sportovni":
			mat.roughness = 0.72
		"kosile", "halenka", "sako", "oblekove":
			mat.roughness = 0.75
		"svetr", "rolak", "mikina", "teplaky":
			mat.roughness = 0.97
		"polobotky", "lodicky", "kozacky":
			mat.roughness = 0.47
	AssetLibrary_material(mat)
	return mat


## Optional weave bump from the existing AssetLibrary material enhancer.
static func AssetLibrary_material(mat: StandardMaterial3D) -> void:
	var lib = load("res://scripts/assets/asset_library.gd")
	lib.enhance_material(mat)

