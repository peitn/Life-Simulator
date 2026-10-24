extends "res://tests/test_base.gd"
## C5 stage 1: independently tinted, morphed garment variants on the current Blender body.
const Lib := preload("res://scripts/assets/asset_library.gd")
const Clothes := preload("res://scripts/assets/clothing_variants.gd")
const Resolver := preload("res://scripts/character/appearance_resolver.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Visual := preload("res://scripts/sim/sim_visual.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")

func _ready() -> void:
	section("Separate source garments and morphing")
	var model: Node3D = Lib.instantiate("character")
	check(model != null, "Blender character GLB loads")
	if model == null:
		finish("test_clothing_c5")
		return
	var top: MeshInstance3D
	var pants: MeshInstance3D
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var nm := Lib.part_material_name(mi)
		if nm == "cloth_shirt":
			top = mi
		if nm == "cloth_pants":
			pants = mi
	check(top != null and pants != null, "existing garments have independent skinned meshes")
	var hoodie := Clothes.variant_mesh(top.mesh, "top", "mikina")
	var sweater := Clothes.variant_mesh(top.mesh, "top", "svetr")
	var sweats := Clothes.variant_mesh(pants.mesh, "bottom", "teplaky")
	check(hoodie != null and sweater != null and sweats != null, "three distinct garment cuts generated")
	check(hoodie.get_blend_shape_count() == top.mesh.get_blend_shape_count(), "hoodie carries all body blend shapes")
	check(sweats.get_blend_shape_count() == pants.mesh.get_blend_shape_count(), "trousers carry all body blend shapes")
	check(hoodie.surface_get_arrays(0)[Mesh.ARRAY_BONES] == top.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES], "garment skeleton weights retained")
	var hp: PackedVector3Array = hoodie.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tp: PackedVector3Array = top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(hp[25].distance_to(tp[25]) > 0.00001, "tailored cut differs geometrically from base")
	check(Clothes.variant_mesh(top.mesh, "top", "mikina") == hoodie, "garment geometry is cached")
	section("Five situations, independent choices, public appearance")
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Test"
	d["personality"]["traits"] = ["hravy"]
	d["clothing"]["active"] = "sport"
	d["clothing"]["sport"]["top"] = "mikina"
	d["clothing"]["sport"]["bottom"] = "teplaky"
	d["clothing"]["sport"]["top_color"] = "#112233"
	var v: Dictionary = Validator.validate(d)
	check(v["ok"], "active outfit validates", str(v["errors"]))
	var lp: Dictionary = Resolver.resolve(v["data"])
	check(lp["outfit_category"] == "sport" and lp["outfit_top"] == "mikina" and lp["outfit_bottom"] == "teplaky", "appearance selects active outfit")
	check(lp["top"].to_html(false) == "112233", "outfit colour preserved")
	var invalid := d.duplicate(true)
	invalid["clothing"]["active"] = "admin_secret"
	check(not Validator.validate(invalid)["ok"], "unknown outfit rejected")
	section("SimVisual follows skin, shape keys and garment selection")
	var visual := Visual.new()
	visual._model = model
	visual._apply_outfit(lp)
	check(visual._body_meshes().size() >= 3, "body mesh collection includes garments")
	var garment_names: Array = []
	for piece in visual._c5_nodes:
		garment_names.append(String(piece.name))
	check(garment_names.has("C5_top_hood") and garment_names.has("C5_bottom_shell") and not top.visible and not pants.visible,
		"runtime uses authored Blender hoodie and trousers, original garments hidden")
	var hoodie_mat: StandardMaterial3D = null
	for piece in visual._c5_nodes:
		if String(piece.name) == "C5_top_hood":
			hoodie_mat = piece.material_override as StandardMaterial3D
	check(hoodie_mat != null and hoodie_mat.resource_name == "cloth_fleece" and hoodie_mat.albedo_texture != null,
		"runtime material includes real fleece PNG")
	var default_lp: Dictionary = Resolver.resolve(Schema.defaults())
	visual._apply_outfit(default_lp)
	check(not visual._c5_nodes.is_empty() and not garment_names.is_empty() and
		visual._c5_nodes.size() < garment_names.size() and visual._c5_signature != "mikina/teplaky/tenisky",
		"changing outfit replaces C5 geometry")
	visual._model = null
	visual.free()
	model.free()
	finish("test_clothing_c5")
