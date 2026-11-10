extends RefCounted
const M1=preload("res://scripts/city/m1_materials.gd")
static var _cache:Dictionary={}
static func definitions() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/surfaces_v2.json"))
static func ids() -> Array:
	var result:Array=[]
	for id in M1.NAMES:result.append("m1:"+id)
	result.append_array(definitions().keys());return result
static func make(id:String) -> StandardMaterial3D:
	if id.begins_with("m1:"):return M1.make(id.trim_prefix("m1:")).duplicate()
	if not _cache.has(id):
		var defs:=definitions()
		if not defs.has(id):return null
		var result:=StandardMaterial3D.new();result.resource_name=id
		for part in ["albedo","normal","roughness"]:
			var img:=Image.load_from_file("res://"+defs[id].maps[part])
			if img==null or img.is_empty():return null
			img.generate_mipmaps(part=="normal");var texture:=ImageTexture.create_from_image(img)
			if part=="albedo":result.albedo_texture=texture
			elif part=="normal":result.normal_enabled=true;result.normal_texture=texture
			else:result.roughness_texture=texture;result.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
		result.texture_repeat=true;result.roughness=1;_cache[id]=result
	var copy:StandardMaterial3D=_cache[id].duplicate()
	# Meter-based local triplanar avoids stretching textures on resized parts.
	copy.uv1_triplanar=true;copy.uv1_triplanar_sharpness=8;return copy
