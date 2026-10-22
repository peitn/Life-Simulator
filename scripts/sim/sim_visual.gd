extends Node3D
## Vizuál postavy (sdílí ho serverový SimAgent i klientská SimPuppet).
## Primárně model z Blenderu (res://assets/models/character.glb) s kostrou a animacemi
## idle/walk/sit/lie; když model chybí (nebo je AssetLibrary vypnutá na dedikovaném serveru),
## postaví se náhrada z primitiv.
## Nad hlavou je „krystal nálady“ (barva podle nálady) a popisek s akcí, emocí
## a případnou replikou v dialogu.

const Mood := preload("res://scripts/sim/mood.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const CharacterAnims := preload("res://scripts/assets/character_anims.gd")
const AppearanceResolver := preload("res://scripts/character/appearance_resolver.gd")
const BodyMorphs := preload("res://scripts/character/body_morphs.gd")
const SkinLayers := preload("res://scripts/character/skin_layers.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
## Části vlasů z karet (C4b): vlasy na hlavě, obočí, vousy.
const HAIR_PARTS := ["scalp", "brows", "beard"]
const FaceMorphs := preload("res://scripts/character/face_morphs.gd")
## Mimika (C3++, běh 21) – jen prezentace na klientovi: blend shapes ex_* hlavy (HeadBuilder), obočí a vousy je
## mají přenesené. Jemný výraz podle dominantní emoce (cíle ≤ 0,6, nikdy grimasa), mrkání a pohyb čelisti při replice.
## Hodnoty: [úsměv, zamračení, zvednuté obočí, přivřená víčka, zornice, rychlost mrkání ×].
const EMOTION_FACE := {
	"spokojeny": [0.25, 0.0, 0.0, 0.0, 0.0, 1.0], "stastny": [0.55, 0.0, 0.10, 0.0, 0.1, 1.0],
	"energicky": [0.30, 0.0, 0.15, 0.0, 0.2, 1.1], "soustredeny": [0.0, 0.20, 0.0, 0.05, 0.0, 0.7],
	"napjaty": [0.0, 0.30, 0.0, 0.0, 0.3, 1.5], "smutny": [0.0, 0.10, 0.25, 0.15, 0.0, 0.9],
	"nastvany": [0.0, 0.60, 0.0, 0.05, 0.2, 1.2], "znudeny": [0.0, 0.0, 0.0, 0.15, -0.1, 0.8],
	"unaveny": [0.0, 0.0, 0.0, 0.30, -0.1, 0.8], "nesvuj": [0.0, 0.20, 0.10, 0.0, 0.2, 1.4],
	"uzkostny": [0.0, 0.25, 0.30, 0.0, 0.45, 1.8], "sklesly": [0.0, 0.10, 0.0, 0.25, -0.1, 0.8],
}
## Mrknutí: zavření 35 %, zavřeno 15 %, otevření 50 % z BLINK_DUR; další za 2–6 s / rychlost, 12 % dvojité.
const BLINK_DUR := 0.16
const BLINK_MIN := 2.0
const BLINK_MAX := 6.0
const BLINK_DOUBLE := 0.12
## Rychlost přechodu výrazu (1/s) a změna váhy, pod kterou se blend shape nepřepisuje.
const EXPR_RATE := 4.0
const EXPR_EPS := 0.002
## Vstupy mimiky, jejichž změna vyžaduje nový zápis vah (viz _write_expression).
const EXPR_INPUTS := ["ex_blink_l", "ex_blink_r", "ex_smile", "ex_frown", "ex_brow_up", "ex_jaw_open", "ex_pupil"]
var _ex_last := {}
## Poslední zapsané tvarové váhy obličeje (apply_face_shape přeskočí stejný vstup).
var _af_w := {}
var _af_b := {}
var _af_count := 0
var _af_valid := false

## Vzhled (kůže, vlasy, oči, oblečení, proporce) přichází VÝHRADNĚ z veřejného snapshotu
## CharacterData (`apply_look`) přes deterministický AppearanceResolver – nikdy ze jména.
const WALK_THRESHOLD := 0.25     # m/s – pod tím postava stojí
const BLEND := 0.25              # s – prolínání animací
## Nejvyšší rychlost postavy (Ultra ≈ 36 m/s) – posun větší než tohle za snímek je teleport/snap, ne chůze.
const MAX_SPEED := 45.0

var body_color := Color(0.85, 0.55, 0.45)
var skin_color := Color(0.93, 0.76, 0.62)
var hair_color := Color(0.25, 0.16, 0.1)
var bottom_color := Color(0.18, 0.23, 0.29)
## Rod z dřívějšího API (configure) – vzhled ani tvar těla z něj NEodvozujeme, zůstává jen pro kompatibilitu.
var female := false
## Výstup AppearanceResolveru pro aktuální snapshot (prázdné = výchozí vzhled).
var look_params := {}

var _body_pivot: Node3D
var _gem: MeshInstance3D
var _gem_mat: StandardMaterial3D
var _label: Label3D
var _built := false

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _mats := {}                  # jméno materiálu -> vlastní kopie pro tuto postavu
var _posture := "stand"
var _speed := 0.0                # vyhlazená rychlost (m/s)
var _last_pos := Vector3.ZERO
var _has_last := false
var _body_mesh_cache: Array = []
var _face_mesh_cache: Array = []
var _rest0: Array = []            # původní lokální klidové polohy kostí
var _skin_copy: Skin = null       # vlastní kopie Skin (inverzní bind matice podle kloubů této postavy)
## Vlasy z karet (C4b): část → MeshInstance3D (sdílená síť na účes, vlastní materiál na postavu).
## Prázdné = karty nejdou (model bez kůže hlavy) → zůstává „helma“ z GLB (hair_short / hair_long).
var _hair_parts := {}
var _hair_mats := {}
## Mimika: aktuální hodnoty ex_*, váhy blend shapes, cache slotů [MeshInstance3D, index, název], stav mrkání a řeči.
var expressions_enabled := true
var _ex := {}
var _expr_w := {}
var _expr_slots: Array = []
var _emotion := ""
var _last_speech := ""
var _talk_left := 0.0
var _talk_t := 0.0
var _blink_init := false
var _blink_wait := 0.0
var _blink_phase := -1.0
var _blink_second := false
var _xrng := RandomNumberGenerator.new()


func configure(p_body: Color, p_female: bool) -> void:
	body_color = p_body
	bottom_color = p_body.darkened(0.6).lerp(Color(0.18, 0.2, 0.25), 0.5)
	female = p_female
	if _built and _model != null:
		_apply_model_variant()


## Vzhled z veřejného snapshotu CharacterData (deterministicky na všech peerech).
func apply_look(snap: Dictionary) -> void:
	look_params = AppearanceResolver.resolve(snap)
	skin_color = look_params["skin"]
	hair_color = look_params["hair"]
	body_color = look_params["top"]
	bottom_color = look_params["bottom"]
	if not _built:
		return
	_place_overhead()
	if _model != null:
		_apply_model_variant()
		_apply_colors()
	elif _body_pivot != null and _body_pivot.get_child_count() >= 4:
		(_body_pivot.get_child(0) as MeshInstance3D).material_override = _mat(bottom_color)
		(_body_pivot.get_child(1) as MeshInstance3D).material_override = _mat(body_color, 0.85)
		(_body_pivot.get_child(2) as MeshInstance3D).material_override = _mat(skin_color, 0.55)
		(_body_pivot.get_child(3) as MeshInstance3D).material_override = _mat(hair_color, 0.9)
		_body_pivot.get_child(3).visible = String(look_params["hair_variant"]) != ""
		_body_pivot.scale = Vector3(look_params["width_scale"], look_params["height_scale"], look_params["width_scale"])


func _ready() -> void:
	_build()


## Krystal nálady a popisek nad hlavou podle skutečné výšky postavy (145–205 cm).
func _place_overhead() -> void:
	if _gem == null or _label == null:
		return
	var crown := float(look_params.get("height_scale", 1.0)) * BodyMorphs.MODEL_HEIGHT if not look_params.is_empty() else BodyMorphs.MODEL_HEIGHT
	_gem.position.y = crown + 0.4
	_label.position.y = crown + 0.7


func uses_model() -> bool:
	return _model != null


func current_anim() -> String:
	return String(_anim.current_animation) if _anim != null else ""


func smoothed_speed() -> float:
	return _speed


func _mat(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	if _built:
		return
	_built = true
	_body_pivot = Node3D.new()
	_body_pivot.name = "Body"
	add_child(_body_pivot)
	_model = AssetLibrary.instantiate("character")
	if _model != null:
		_build_model()
	else:
		_build_primitives()

	# Krystal nálady – osmistěn nad hlavou.
	var gem := SphereMesh.new()
	gem.radius = 0.09
	gem.height = 0.3
	gem.radial_segments = 4
	gem.rings = 1
	_gem_mat = StandardMaterial3D.new()
	_gem_mat.emission_enabled = true
	_gem_mat.emission_energy_multiplier = 1.4
	_gem_mat.roughness = 0.2
	_gem = _part(gem, _gem_mat, Vector3(0, 2.2, 0), self)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.outline_size = 10
	_label.pixel_size = 0.0035
	_label.position = Vector3(0, 2.5, 0)
	_label.width = 900.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_place_overhead()


func _build_primitives() -> void:
	var legs := CapsuleMesh.new()
	legs.radius = 0.16
	legs.height = 0.85
	_part(legs, _mat(bottom_color), Vector3(0, 0.43, 0), _body_pivot)
	var torso := CapsuleMesh.new()
	torso.radius = 0.22
	torso.height = 0.72
	_part(torso, _mat(body_color, 0.85), Vector3(0, 1.12, 0), _body_pivot)
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.3
	_part(head, _mat(skin_color, 0.55), Vector3(0, 1.64, 0), _body_pivot)
	var hair := SphereMesh.new()
	hair.radius = 0.15
	hair.height = 0.22
	var hair_mi := _part(hair, _mat(hair_color, 0.9), Vector3(0, 1.71, -0.02), _body_pivot)
	if not look_params.is_empty():
		hair_mi.visible = String(look_params["hair_variant"]) != ""
		_body_pivot.scale = Vector3(look_params["width_scale"], look_params["height_scale"], look_params["width_scale"])


func _build_model() -> void:
	_model.name = "Model"
	_body_pivot.add_child(_model)
	# Vlastní kopie materiálů – každá postava má svou barvu oblečení, kůže a vlasů.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mname := AssetLibrary.part_material_name(mi)
		var src: Material = mi.mesh.surface_get_material(0) if mi.mesh != null else null
		if mname == "" or src == null:
			continue
		if not _mats.has(mname):
			# Kůže (C4): vlastní ShaderMaterial s fyzikálním modelem a vrstvami (pihy, jizvy, tetování…);
			# bez shaderu nebo bez klidových poloh v CUSTOM0 zůstane StandardMaterial3D s albedem z modelu.
			var skin_mat: ShaderMaterial = SkinLayers.make_material() if mname == "skin_body" and AssetLibrary.is_skin_mesh(mi) \
				and (mi.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0 else null
			_mats[mname] = skin_mat if skin_mat != null else src.duplicate()
		mi.material_override = _mats[mname]
	_build_hair_parts()
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", CharacterAnims.library())
	_apply_model_variant()
	_apply_colors()
	_anim.play("idle")


## Vlasy, obočí a vousy z karet (C4b): uzly pod kostrou se stejným Skin jako hlava (kosti = bind indexy
## sdíleného Skin), síť dodá HairRig podle stylu (sdílená cache), materiál je vlastní pro postavu.
## Musí vzniknout před prvním _apply_joints, aby dostaly i kopii Skin s posunutými klouby.
func _build_hair_parts() -> void:
	_hair_parts = {}
	_hair_mats = {}
	if HairRig.context().is_empty():
		return
	var skel := _skeleton()
	var head_mi: MeshInstance3D = null
	for mi in AssetLibrary.parts_in_group(_model, "head"):
		if mi.skin != null:
			head_mi = mi
			break
	if skel == null or head_mi == null:
		return
	for part in HAIR_PARTS:
		var mi := MeshInstance3D.new()
		mi.name = "hair_cards_" + part
		skel.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = head_mi.skin
		var mat := HairRig.make_material()
		if mat == null:
			# bez shaderu karty nejdou – uklidit i už vytvořené části, zůstane „helma“ z GLB
			mi.queue_free()
			for other in _hair_parts.values():
				(other as Node).queue_free()
			_hair_parts = {}
			_hair_mats = {}
			return
		_hair_mats[part] = mat
		mi.material_override = mat
		mi.visible = false
		_hair_parts[part] = mi


## HairRig dostavěl síť účesu ve vlákně → přepnout z helmy na karty (styl se bere z aktuálního vzhledu, takže
## když se mezitím účes změnil, použije se ten nový).
func _on_hair_mesh_ready(_part: String, _style: String) -> void:
	if _model != null and is_inside_tree():
		_apply_model_variant()


## Čeká postava na síť vlasů z vlákna (ukazuje helmu)? (testy)
func hair_waiting() -> bool:
	if _hair_parts.is_empty():
		return false
	var helm_visible := false
	for g in ["hair_short", "hair_long"]:
		for mi in AssetLibrary.parts_in_group(_model, g):
			helm_visible = helm_visible or mi.visible
	return helm_visible and not (_hair_parts["scalp"] as MeshInstance3D).visible


## Uzel části vlasů z karet (testy); null = karty se nepoužívají.
func hair_part(part: String) -> MeshInstance3D:
	return _hair_parts.get(part)


func hair_material(part: String) -> ShaderMaterial:
	return _hair_mats.get(part)


## Tvar těla a proporce z CharacterData (od C2): jedna neutrální síť těla s blend shapes (váhy z
## BodyMorphs přes AppearanceResolver), posuny kloubů (ramena, kyčle) podle morfů, délka nohou škálováním
## stehen, výška uniformním měřítkem a hlava s odmocninou výšky. Vlasy: síť podle účesu (do C4).
## Bez snapshotu = neutrální výchozí tělo (nic se neodvozuje z rodu ani jména).
func _apply_model_variant() -> void:
	if _model == null:
		return
	var hair_v := "hair_short"
	if not look_params.is_empty():
		hair_v = String(look_params["hair_variant"])
	var cards := not _hair_parts.is_empty()
	var lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})
	# Karty: hotová síť → hned. Jinak (první postava s tímto účesem ve hře, HairRig.async_build) se síť staví
	# ve vlákně a do té doby zůstane vidět „helma“ z GLB; po dokončení přijde _on_hair_mesh_ready.
	var waiting := false
	if cards:
		var hl: Dictionary = lp.get("hair_look", {})
		var styles := {"scalp": String(hl.get("style", "kratke")), "brows": String(hl.get("brow_style", "prirozene")),
			"beard": String(hl.get("beard_style", "zadne"))}
		for part in HAIR_PARTS:
			var mi: MeshInstance3D = _hair_parts[part]
			var r := HairRig.request_mesh(part, styles[part], self)
			if not bool(r["ready"]):
				mi.visible = false
				if part == "scalp":
					waiting = true
				continue
			var m: ArrayMesh = r["mesh"]
			if mi.mesh != m:
				mi.mesh = m
				_invalidate_expression_slots()
			mi.visible = m != null
	var helm := not cards or waiting
	var show := {"body": true, "body_m": false, "body_f": false, "head": true,
		"hair_short": hair_v == "hair_short" and helm, "hair_long": hair_v == "hair_long" and helm}
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		if _hair_parts.values().has(mi):
			continue
		var grp := String(mi.name).get_slice("__", 0)
		mi.visible = bool(show.get(grp, true))
	apply_body_shape(lp)
	apply_face_shape(lp)


## Obličej (C3): váhy blend shapes hlavy, očí a vlasů (vlasy převzaly morfy lebky při importu, takže sedí
## i na širší/vyšší hlavě). Pás švu na krku hlavy nese blend shapes se jmény klíčů TĚLA (C3+, běh 11) –
## jejich váha se vezme z lp["body"], aby okraj krku hlavy sledoval okraj těla. Vrací počet nastavených blend shapes.
func apply_face_shape(lp: Dictionary) -> int:
	if _model == null:
		return 0
	var w: Dictionary = lp.get("face", {})
	var wb: Dictionary = lp.get("body", {})
	# Beze změny vah i sítí není co zapisovat (posuvník kůže/výšky); mimiku píše _write_expression přímo.
	if _af_valid and w == _af_w and wb == _af_b:
		return _af_count
	var count := 0
	for mi in _face_meshes():
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var names := _shape_names(m)
		for i in names.size():
			var nm := names[i]
			var v := clampf(float(w.get(nm, wb.get(nm, _expr_w.get(nm, 0.0)))), -1.0, 1.0)
			# Zápis jen při změně: set_blend_shape_value jde přes RenderingServer a hlava má od běhu 21
			# ~90 klíčů na každém povrchu – posuvník mění jen pár z nich.
			if mi.get_blend_shape_value(i) != v:
				mi.set_blend_shape_value(i, v)
			count += 1
	_af_w = w.duplicate()
	_af_b = wb.duplicate()
	_af_count = count
	_af_valid = true
	return count


## Názvy blend shapes sítě (cache podle sítě – get_blend_shape_name alokuje StringName→String pro ~90 klíčů na povrch).
static var _names_cache: Dictionary = {}

static func _shape_names(m: Mesh) -> PackedStringArray:
	var key := m.get_instance_id()
	var c = _names_cache.get(key)
	if c != null:
		return c
	var names := PackedStringArray()
	for i in m.get_blend_shape_count():
		names.append(String(m.get_blend_shape_name(i)))
	if _names_cache.size() > 512:
		_names_cache.clear()
	_names_cache[key] = names
	return names


## Aplikuje blend shapes těla a kosti. Vrací počet nastavených blend shapes (testy/výkon).
func apply_body_shape(lp: Dictionary) -> int:
	if _model == null:
		return 0
	var w: Dictionary = lp.get("body", {})
	var count := 0
	for mi in _body_meshes():
		for k in w:
			var idx: int = mi.find_blend_shape_by_name(StringName(k))
			if idx >= 0:
				mi.set_blend_shape_value(idx, clampf(float(w[k]), -1.0, 1.0))
				count += 1
	var skel := _skeleton()
	if skel != null:
		_apply_joints(skel, BodyMorphs.bone_offsets(w, _morph_bones()))
		var ls := float(lp.get("leg_scale", 1.0))
		for bone in ["thigh_l", "thigh_r"]:
			var bi := skel.find_bone(bone)
			if bi >= 0:
				skel.set_bone_pose_scale(bi, Vector3(1.0, ls, 1.0))
		var hb := skel.find_bone("head")
		if hb >= 0:
			skel.set_bone_pose_scale(hb, Vector3.ONE * float(lp.get("head_scale", 1.0)))
	var s := float(lp.get("height_scale", 1.0))
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(0.0, float(lp.get("lift", 0.0)) * s, 0.0)
	return count


## Přesune klouby (ramena, kyčle) podle morfů tak, aby skinning výchylku NEpřičetl podruhé: shape key už
## posunul vrcholy paže/nohy, proto se mění klidová poloha kosti (rest) i inverzní bind matice (vlastní
## kopie Skin pro tuto postavu) – v klidové póze je pak G·bind = I a rotace animací se točí kolem
## nového kloubu. (Posun jen pózy by paži posunul dvakrát.)
func _apply_joints(skel: Skeleton3D, offs: Dictionary) -> void:
	if _rest0.is_empty():
		for i in skel.get_bone_count():
			_rest0.append(skel.get_bone_rest(i).origin)
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			if mi.skin != null:
				if _skin_copy == null:
					_skin_copy = mi.skin.duplicate() as Skin
				mi.skin = _skin_copy
	var glob: Array = []
	glob.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		var local: Vector3 = _rest0[i] + (offs.get(skel.get_bone_name(i), Vector3.ZERO) as Vector3)
		skel.set_bone_rest(i, Transform3D(Basis(), local))
		if skel.get_bone_name(i) != "hips":     # pozici pánve řídí animace
			skel.set_bone_pose_position(i, local)
		var par := skel.get_bone_parent(i)
		glob[i] = (glob[par] as Vector3) + local if par >= 0 else local
	if _skin_copy != null:
		for j in _skin_copy.get_bind_count():
			var bname := String(_skin_copy.get_bind_name(j))
			var bi := skel.find_bone(bname) if bname != "" else _skin_copy.get_bind_bone(j)
			if bi >= 0 and bi < glob.size():
				_skin_copy.set_bind_pose(j, Transform3D(Basis(), -(glob[bi] as Vector3)))


func _face_meshes() -> Array:
	if _face_mesh_cache.is_empty() and _model != null:
		for g in ["head", "eyes", "hair_short", "hair_long"]:
			_face_mesh_cache.append_array(AssetLibrary.parts_in_group(_model, g))
		# Karty vlasů nesou přenesené klíče hlavy i těla pod stejnými jmény (HairRig).
		for part in HAIR_PARTS:
			if _hair_parts.has(part):
				_face_mesh_cache.append(_hair_parts[part])
	return _face_mesh_cache


func _body_meshes() -> Array:
	if _body_mesh_cache.is_empty() and _model != null:
		_body_mesh_cache = AssetLibrary.parts_in_group(_model, "body")
	return _body_mesh_cache


func _skeleton() -> Skeleton3D:
	if _model == null:
		return null
	return _model.get_node_or_null("Skeleton3D") as Skeleton3D


static func _morph_bones() -> Dictionary:
	var mb = AssetLibrary.manifest_meta("character").get("morph_bones", {})
	return mb if typeof(mb) == TYPE_DICTIONARY else {}


func _apply_colors() -> void:
	var set_col := func(mname: String, c: Color) -> void:
		if _mats.has(mname) and _mats[mname] is StandardMaterial3D:
			(_mats[mname] as StandardMaterial3D).albedo_color = c
	set_col.call("cloth_shirt", body_color)
	set_col.call("cloth_pants", bottom_color)
	set_col.call("skin_body", skin_color)
	set_col.call("hair_main", hair_color)
	var lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})
	apply_skin(lp)
	for part in _hair_mats:
		HairRig.apply(_hair_mats[part], lp, part)
	set_col.call("eye_iris", lp.get("iris", Color(0.3, 0.42, 0.55)))
	set_col.call("eye_limbus", lp.get("limbus", Color(0.14, 0.2, 0.27)))
	set_col.call("eye_lash", lp.get("lash", Color(0.06, 0.045, 0.035)))
	set_col.call("teeth_enamel", lp.get("teeth", Color(0.93, 0.92, 0.87)))
	set_col.call("mouth_gum", lp.get("gum", Color(0.78, 0.42, 0.44)))
	set_col.call("mouth_tongue", lp.get("tongue", Color(0.74, 0.38, 0.4)))
	set_col.call("skin_lips", lp.get("lips", skin_color.darkened(0.2)))
	# Vnitřek víček/spojivka: kůže do růžova (stejný model pro všechny odstíny kůže).
	set_col.call("eye_socket", skin_color.lerp(Color(0.72, 0.36, 0.36), 0.55))


## Kůže (C4): chromofory a vrstvy do shaderu kůže. Vrací počet nastavených parametrů (0 = StandardMaterial3D).
func apply_skin(lp: Dictionary) -> int:
	var m = _mats.get("skin_body")
	if m is ShaderMaterial:
		return SkinLayers.apply(m as ShaderMaterial, lp)
	return 0


## Materiál kůže této postavy (testy).
func skin_material() -> Material:
	return _mats.get("skin_body")


## posture: stand / sit / lie; mood_value −100..100; speech = replika (prázdná = nic).
func apply(posture: String, mood_value: float, emotion: String, title: String, action_text: String, speech := "") -> void:
	if not _built:
		_build()
	_posture = posture
	match posture:
		"lie":
			_body_pivot.rotation = Vector3(-PI / 2.0, 0, 0)
			_body_pivot.position = Vector3(0, 0.62, 0.8)
		"sit":
			_body_pivot.rotation = Vector3.ZERO
			# Model si sed „odehraje“ kostrou (pánev do výšky sedáku); primitiva se jen posunou.
			# Delší/kratší nohy zvedají model (aby chodidla stála na zemi) – vsedě to vyrovnáme, pánev patří na sedák.
			var lift := float(look_params.get("lift", 0.0)) * float(look_params.get("height_scale", 1.0))
			_body_pivot.position = Vector3(0, -lift, 0) if _model != null else Vector3(0, -0.3, 0)
		_:
			_body_pivot.rotation = Vector3.ZERO
			_body_pivot.position = Vector3.ZERO
	_update_anim()
	_emotion = emotion
	if speech != _last_speech:
		_last_speech = speech
		# Čelist se hýbe úměrně délce repliky (nová replika = nová řeč; stejná replika v dalších voláních ne).
		_talk_left = clampf(0.5 + float(speech.length()) * 0.055, 0.8, 4.5) if speech != "" else 0.0
	# Krystal: zelená (skvělá nálada) -> žlutá -> červená (mizerná).
	var t := clampf((mood_value + 60.0) / 120.0, 0.0, 1.0)
	var c := Color(0.95, 0.15, 0.1).lerp(Color(0.95, 0.85, 0.1), clampf(t * 2.0, 0.0, 1.0))
	if t > 0.5:
		c = Color(0.95, 0.85, 0.1).lerp(Color(0.15, 0.95, 0.25), (t - 0.5) * 2.0)
	_gem_mat.albedo_color = c
	_gem_mat.emission = c
	_gem.visible = posture != "lie"
	var txt := "%s\n%s · %s" % [title, action_text, Mood.emotion_label(emotion)]
	if speech != "":
		# Cenzura sprostých slov podle nastavení TOHOTO hráče (prezentace je věc klienta).
		var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
		if gs != null:
			speech = gs.filter_profanity(speech)
		txt += "\n„%s“" % speech
	_label.text = txt
	_label.modulate = Mood.emotion_color(emotion).lerp(Color.WHITE, 0.5)


## Vybere klip podle pózy a rychlosti pohybu.
func _update_anim() -> void:
	if _anim == null:
		return
	var want := "idle"
	match _posture:
		"lie":
			want = "lie"
		"sit":
			want = "sit"
		_:
			want = "walk" if _speed > WALK_THRESHOLD else "idle"
	if String(_anim.current_animation) != want:
		_anim.play(want, BLEND)
	if want == "walk":
		# Při zrychleném čase se kroky zrychlí, ale ne nesmyslně (max. 4×).
		_anim.speed_scale = clampf(_speed / CharacterAnims.WALK_SPEED, 0.5, 4.0)
	else:
		_anim.speed_scale = 1.0


## Rychlost se měří z pohybu v prostoru – funguje stejně pro serverového agenta i klientskou loutku.
func track_motion(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	var p := global_position
	if not _has_last:
		_last_pos = p
		_has_last = true
		return
	var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	# Skok (teleport do pózy u objektu, snap loutky) není chůze.
	var inst := 0.0 if d > maxf(3.0, MAX_SPEED * delta * 1.5) else d / delta
	_speed = lerpf(_speed, inst, clampf(delta * 8.0, 0.0, 1.0))


func _process(delta: float) -> void:
	if _gem != null:
		_gem.rotate_y(delta * 1.5)
	track_motion(delta)
	if _anim != null and _posture == "stand":
		_update_anim()
	if _model != null and expressions_enabled:
		update_expression(delta)


# ======================================================================================
# Mimika (C3++, běh 21)
# ======================================================================================
## Sloty blend shapes ex_* na hlavě, očích, řasách, ústech a kartách vlasů (cache; vlasy se mohou vyměnit).
func _expression_slots() -> Array:
	if _expr_slots.is_empty():
		for mi in _face_meshes():
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null:
				continue
			for i in m.get_blend_shape_count():
				var nm := String(m.get_blend_shape_name(i))
				if nm.begins_with("ex_"):
					_expr_slots.append([mi, i, nm])
	return _expr_slots


## Vynutí nové načtení slotů (po výměně sítě vlasů).
func _invalidate_expression_slots() -> void:
	_expr_slots = []
	_af_valid = false   # nová síť (vlasy) potřebuje i tvarové váhy
	_ex_last = {}   # nové sítě (vlasy) musí dostat aktuální výraz


## Mrknutí 0..1 ve fázi 0..1 (zavření – zavřeno – otevření).
static func blink_curve(ph: float) -> float:
	if ph < 0.0 or ph > 1.0:
		return 0.0
	if ph < 0.35:
		var t := ph / 0.35
		return t * t * (3.0 - 2.0 * t)
	if ph < 0.5:
		return 1.0
	var u := (ph - 0.5) / 0.5
	return 1.0 - u * u * (3.0 - 2.0 * u)


## Krok mimiky: cíle podle emoce, mrkání, čelist při řeči → váhy blend shapes (mění jen to, co se pohnulo).
## Vrací počet přepsaných vah (testy, výkon).
func update_expression(delta: float) -> int:
	if not _blink_init:
		# rozfázování mrkání mezi postavami (jen prezentace klienta, nic se nereplikuje)
		_blink_init = true
		var sl: Dictionary = look_params.get("skin_layers", {})
		_xrng.seed = hash(int(sl.get("seed", 0)) * 7919 + get_instance_id() % 997)
		_blink_wait = _xrng.randf_range(0.5, BLINK_MAX)
	var ef: Array = EMOTION_FACE.get(_emotion, [0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	var k := 1.0 - exp(-EXPR_RATE * maxf(delta, 0.0))
	var tgt := {"ex_smile": ef[0], "ex_frown": ef[1], "ex_brow_up": ef[2], "ex_pupil": ef[4]}
	for key in tgt:
		_ex[key] = lerpf(float(_ex.get(key, 0.0)), float(tgt[key]), k)
	_ex["_lid"] = lerpf(float(_ex.get("_lid", 0.0)), float(ef[3]), k)
	# mrkání
	if _blink_phase >= 0.0:
		_blink_phase += delta / BLINK_DUR
		if _blink_phase > 1.0:
			_blink_phase = -1.0
			if not _blink_second and _xrng.randf() < BLINK_DOUBLE:
				_blink_second = true
				_blink_wait = 0.12
			else:
				_blink_second = false
				_blink_wait = _xrng.randf_range(BLINK_MIN, BLINK_MAX) / maxf(float(ef[5]), 0.2)
	else:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_phase = 0.0
	var bl := maxf(float(_ex["_lid"]), blink_curve(_blink_phase))
	_ex["ex_blink_l"] = bl
	_ex["ex_blink_r"] = bl
	# řeč: čelist kmitá nepravidelně (dvě frekvence), na konci repliky se zavře
	var jaw := 0.0
	if _talk_left > 0.0:
		_talk_left -= delta
		_talk_t += delta
		jaw = 0.10 + 0.20 * absf(sin(_talk_t * 11.0 + sin(_talk_t * 3.7) * 1.6))
	_ex["ex_jaw_open"] = lerpf(float(_ex.get("ex_jaw_open", 0.0)), jaw, clampf(delta * 18.0, 0.0, 1.0))
	return _write_expression()


## Ruční výraz (cutscény, testy): hodnoty ex_* se zapíšou hned, bez animace.
func set_expression(ex: Dictionary) -> int:
	for key in ex:
		_ex[key] = ex[key]
	return _write_expression(true)


func expression_values() -> Dictionary:
	return _expr_w.duplicate()


func _write_expression(force := false) -> int:
	# Klidová tvář (žádné mrkání, výraz doběhl k cíli): beze změny vstupů nic nepočítat ani nealokovat
	# (Gemini, běh 21 – slovník vah se jinak staví každý snímek pro každou postavu).
	if not force and not _expr_slots.is_empty():
		var same := true
		for key in EXPR_INPUTS:
			if absf(float(_ex.get(key, 0.0)) - float(_ex_last.get(key, 0.0))) > EXPR_EPS * 0.5:
				same = false
				break
		if same:
			return 0
	for key in EXPR_INPUTS:
		_ex_last[key] = float(_ex.get(key, 0.0))
	var w := FaceMorphs.expression_weights(_ex)
	var n := 0
	for slot in _expression_slots():
		var mi: MeshInstance3D = slot[0]
		if not is_instance_valid(mi):
			_invalidate_expression_slots()
			return n
		var v := float(w.get(slot[2], 0.0))
		if absf(mi.get_blend_shape_value(slot[1]) - v) > EXPR_EPS or (v == 0.0 and mi.get_blend_shape_value(slot[1]) != 0.0):
			mi.set_blend_shape_value(slot[1], v)
			n += 1
	_expr_w = w
	return n
