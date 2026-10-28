extends RefCounted
const NAMES := ["plaster","brick","concrete","wood","tile","roof"]
static var _cache: Dictionary = {}

static func make(kind: String) -> StandardMaterial3D:
	if kind not in NAMES: return null
	if _cache.has(kind): return _cache[kind]
	var result := StandardMaterial3D.new()
	result.resource_name = "M1_" + kind
	for part in ["albedo","normal","roughness"]:
		var path: String = "res://assets/city/materials/"+kind+"_"+part+".png"
		var img := Image.load_from_file(path)
		if img == null or img.is_empty(): return null
		img.generate_mipmaps(part == "normal")
		var tex := ImageTexture.create_from_image(img)
		if part == "albedo": result.albedo_texture = tex
		elif part == "normal":
			result.normal_enabled = true
			result.normal_texture = tex
		else:
			result.roughness_texture = tex
			result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.texture_repeat = true
	result.roughness = 1.0
	_cache[kind] = result
	return result

static func apply(node: Node, kind: String) -> bool:
	var mat := make(kind)
	if mat == null: return false
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(surface)
			if original is BaseMaterial3D and original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			mesh.set_surface_override_material(surface,mat)
	return true
