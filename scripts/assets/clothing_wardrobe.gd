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


static func is_available() -> bool:
	return FileAccess.file_exists(SOURCE + "top.lsx") and FileAccess.file_exists(SOURCE + "bottom.lsx")


static func reset_cache() -> void:
	_loaded.clear()
	_materials.clear()
	_textures.clear()


static func _tex(name: String, suffix: String) -> Texture2D:
	var id := name + "_" + suffix
	if _textures.has(id):
		return _textures[id]
	var path := TEXTURES + "C5_" + id + ".png"
	if not FileAccess.file_exists(path):
		return null
	var im := Image.new()
	if im.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var texture := ImageTexture.create_from_image(im)
	_textures[id] = texture
	return texture


static func _mat(material_name: String) -> StandardMaterial3D:
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
	# are in LSX order; remap to character Skin happens later in _textured_mesh.
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


## The compact LSX stores mesh geometry but not UVs. Add deterministic world-oriented
## UV coordinates and approximate tangent frame without changing any blend shape or skin weights.
static func _textured_mesh(source: ArrayMesh, mat_name: String, piece: String = "") -> ArrayMesh:
	if source == null or source.get_surface_count() == 0:
		return null
	var m := ArrayMesh.new()
	m.blend_shape_mode = source.blend_shape_mode
	for i in source.get_blend_shape_count():
		m.add_blend_shape(source.get_blend_shape_name(i))
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var blend := source.surface_get_blend_shape_arrays(s)
		if piece.begins_with("sleeve_"):
			_fit_legacy_sleeve(arrays, blend)
		elif piece == "waist_chain":
			_repair_legacy_waist_chain(arrays, blend)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# LSX encodes bone IDs by its own Skin order; the existing avatar's Skin uses
		# a different bind order. Remap once while preparing the shared mesh.
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for j in bones.size():
			var src_index := bones[j]
			if src_index >= 0 and src_index < C5_TO_CHARACTER_BIND.size():
				bones[j] = C5_TO_CHARACTER_BIND[src_index]
		arrays[Mesh.ARRAY_BONES] = bones
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
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
		m.surface_set_material(s, _mat(mat_name))
	m.resource_name = source.resource_name
	return m


static func _load(kind: String) -> void:
	if _loaded.has(kind):
		return
	_loaded[kind] = {}
	var path := SOURCE + kind + ".lsx"
	if not FileAccess.file_exists(path):
		return
	var decoded := LSX.decode(FileAccess.get_file_as_string(path))
	if decoded.is_empty():
		push_warning("C5: poškozený soubor oblečení " + path)
		return
	var scene := LSX.build_scene(decoded)
	if scene == null:
		push_warning("C5: nelze sestavit model oblečení " + path)
		return
	for o in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := o as MeshInstance3D
		# "<group>__C5__<part>__<style>__<piece>__<material>"
		var tokens := String(mi.name).split("__")
		if tokens.size() < 6 or tokens[1] != "C5" or tokens[2] != kind:
			continue
		var style := String(tokens[3])
		var mat_name := String(tokens[-1])
		var mesh := _textured_mesh(mi.mesh as ArrayMesh, mat_name, String(tokens[4]))
		if mesh == null:
			continue
		if not _loaded[kind].has(style):
			_loaded[kind][style] = []
		_loaded[kind][style].append({"mesh": mesh, "name": String(tokens[4]), "material": mat_name, "category": kind})
	scene.free()


static func parts(kind: String, style: String) -> Array:
	_load(kind)
	return _loaded.get(kind, {}).get(style, [])


static func active_parts(lp: Dictionary) -> Array:
	var res := []
	var top := String(lp.get("outfit_top", "tricko"))
	var bottom := String(lp.get("outfit_bottom", "dziny"))
	var shoes := String(lp.get("outfit_shoes", "tenisky"))
	res.append_array(parts("top", top))
	if top == "saty":
		res.append_array(parts("dress", "saty"))
	elif bottom != "zadne":
		res.append_array(parts("bottom", bottom))
	if bottom in LEG_OUTFITS or top == "saty":
		res.append_array(parts("legs", "skin"))
	if shoes != "bosy":
		res.append_array(parts("shoes", shoes))
	return res


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
		var styles: Dictionary = _loaded[kind]
		var count := 0
		for style in styles:
			count += styles[style].size()
		out[kind] = {"styles": styles.size(), "meshes": count}
	return out