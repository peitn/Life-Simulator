extends RefCounted
## Knihovna 3D assetů z Blenderu (res://assets/models/*.glb).
##
## GLB se načítají za běhu přes GLTFDocument (nepotřebují import editoru, stejně jako WAV zvuky),
## jednou se zabalí do PackedScene a dál se jen instancují. Materiály z Blenderu nesou jen základní
## PBR hodnoty (barva, drsnost, kovovost); podle prefixu jména materiálu jim tady přidáme detail:
##   fabric_/linen_/cloth_  – jemná tkanina (triplanární normal mapa ze šumu, bez UV)
##   wood_                  – podélná kresba dřeva
##   shoe_                  – kůže
##   skin_                  – podpovrchový rozptyl (SSS), jemná drsnost pórů
##   hair_                  – matnější vlasy s lehkým okrajovým světlem
##   enamel_                – lak s clearcoatem (lednice)
##   eye_                   – lesklé oči
## Když model chybí (nebo je knihovna vypnutá – dedikovaný server), vrací null a volající
## použije primitivní náhradu.

const MODELS_DIR := "res://assets/models/"

## Dedikovaný server bez obrazu modely nepotřebuje.
static var enabled := true
static var _cache := {}          # jméno -> PackedScene, nebo null (chybí / chyba)
static var _textures := {}       # klíč -> Texture2D (sdílené detailní textury)
static var load_count := 0       # kolikrát se GLB skutečně četl z disku (test cache)


static func model_path(model_name: String) -> String:
	return MODELS_DIR + model_name + ".glb"


static func has_model(model_name: String) -> bool:
	return enabled and FileAccess.file_exists(model_path(model_name))


## Nová instance modelu, nebo null.
static func instantiate(model_name: String) -> Node3D:
	if not enabled:
		return null
	var ps: PackedScene = _get_scene(model_name)
	if ps == null:
		return null
	return ps.instantiate() as Node3D


static func _get_scene(model_name: String) -> PackedScene:
	if _cache.has(model_name):
		return _cache[model_name]
	var ps: PackedScene = null
	var path := model_path(model_name)
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			var root := doc.generate_scene(state) as Node3D
			if root != null:
				load_count += 1
				_set_owner_recursive(root, root)
				for mi in root.find_children("*", "MeshInstance3D", true, false):
					enhance_mesh(mi as MeshInstance3D)
					if is_skin_mesh(mi as MeshInstance3D):
						add_rest_positions(mi as MeshInstance3D)
				ps = PackedScene.new()
				if ps.pack(root) != OK:
					ps = null
				root.free()
	if ps == null:
		push_warning("AssetLibrary: model '%s' nejde načíst – použije se náhrada." % model_name)
	_cache[model_name] = ps
	return ps


static func _set_owner_recursive(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)


## Metadata modelu z manifest.json (např. morph_bones postavy). Prázdné, když chybí.
static var _manifest = null


static func manifest_meta(model_name: String) -> Dictionary:
	if _manifest == null:
		_manifest = {}
		var path := MODELS_DIR + "manifest.json"
		if FileAccess.file_exists(path):
			var m = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(m) == TYPE_DICTIONARY:
				_manifest = m
	var e = _manifest.get(model_name, {})
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("meta")) != TYPE_DICTIONARY:
		return {}
	return e["meta"]


## Vyčistí cache (testy).
static func clear_cache() -> void:
	_cache.clear()
	_manifest = null
	load_count = 0


static func material_kind(mat_name: String) -> String:
	var i := mat_name.find("_")
	return mat_name.substr(0, i) if i > 0 else mat_name


static func _noise_tex(key: String, freq: float, w: int, h: int, normal: bool, bump := 4.0) -> Texture2D:
	var k := "%s_%s" % [key, "n" if normal else "a"]
	if _textures.has(k):
		return _textures[k]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = 3
	noise.seed = key.hash() & 0xFFFF
	var t := NoiseTexture2D.new()
	t.width = w
	t.height = h
	t.seamless = true
	t.noise = noise
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	_textures[k] = t
	return t


## Přidá k materiálům povrchový detail podle druhu. Bezpečné volat opakovaně (materiál se
## označí metadaty).
static func enhance_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if m != null:
			enhance_material(m)


static func enhance_material(m: StandardMaterial3D) -> void:
	if m.has_meta("lsx_enhanced"):
		return
	m.set_meta("lsx_enhanced", true)
	match material_kind(m.resource_name):
		"fabric", "linen", "cloth":
			m.normal_enabled = true
			m.normal_texture = _noise_tex("weave", 0.35, 128, 128, true, 6.0)
			m.normal_scale = 0.35 if m.resource_name.begins_with("linen") else 0.5
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(9, 9, 9)
			m.roughness = clampf(m.roughness, 0.8, 1.0)
		"wood":
			m.normal_enabled = true
			m.normal_texture = _noise_tex("grain", 0.08, 256, 32, true, 3.0)
			m.normal_scale = 0.3
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.5, 1.5, 1.5)
		"shoe":
			m.normal_enabled = true
			m.normal_texture = _noise_tex("leather", 0.5, 64, 64, true, 2.0)
			m.normal_scale = 0.2
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(6, 6, 6)
		"skin":
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.25
			m.subsurf_scatter_skin_mode = true
			m.roughness = 0.4 if m.resource_name == "skin_lips" else 0.55   # rty jsou vlhčí než kůže
		"hair":
			m.roughness = 0.62
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.6
		"enamel":
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.15
		"eye":
			m.roughness = 0.08
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_:
			pass


## Síť kůže (tělo i hlava), na kterou jde shader kůže s maskami v klidových souřadnicích.
static func is_skin_mesh(mi: MeshInstance3D) -> bool:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	var m := mi.mesh.surface_get_material(0)
	return m != null and String(m.resource_name).begins_with("skin_body")


## Uloží klidovou polohu každého vrcholu do CUSTOM0 (RGBA float): shader kůže podle ní umisťuje pihy,
## jizvy, tetování, obočí a make-up, takže masky jedou s vrcholy při blend shapes i skinningu.
## Síť se přestaví se zachováním blend shapes (jména, režim), kostí a materiálu. Vrací true při úspěchu.
static func add_rest_positions(mi: MeshInstance3D) -> bool:
	var src := mi.mesh as ArrayMesh
	if src == null or src.get_surface_count() != 1:
		return false
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return false
	var c0 := PackedFloat32Array()
	c0.resize(verts.size() * 4)
	for i in verts.size():
		c0[i * 4] = verts[i].x
		c0[i * 4 + 1] = verts[i].y
		c0[i * 4 + 2] = verts[i].z
		c0[i * 4 + 3] = 1.0
	arr[Mesh.ARRAY_CUSTOM0] = c0
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var bones = arr[Mesh.ARRAY_BONES]
	if bones != null and (bones as PackedInt32Array).size() == verts.size() * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var bs := src.surface_get_blend_shape_arrays(0)
	var out := ArrayMesh.new()
	out.blend_shape_mode = src.blend_shape_mode
	for i in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(i))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bs, {}, flags)
	out.surface_set_material(0, src.surface_get_material(0))
	out.resource_name = src.resource_name
	mi.mesh = out
	return true


## Uzly modelu podle skupiny (první část jména "<skupina>__<část>__<materiál>").
static func parts_in_group(root: Node, group: String) -> Array:
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).get_slice("__", 0) == group:
			out.append(mi)
	return out


static func part_material_name(mi: MeshInstance3D) -> String:
	var parts := String(mi.name).split("__")
	return parts[2] if parts.size() >= 3 else ""
