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
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", CharacterAnims.library())
	_apply_model_variant()
	_apply_colors()
	_anim.play("idle")


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
	var show := {"body": true, "body_m": false, "body_f": false, "head": true,
		"hair_short": hair_v == "hair_short", "hair_long": hair_v == "hair_long"}
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var grp := String(mi.name).get_slice("__", 0)
		mi.visible = bool(show.get(grp, true))
	var lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})
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
	var count := 0
	for mi in _face_meshes():
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for i in m.get_blend_shape_count():
			var nm := String(m.get_blend_shape_name(i))
			mi.set_blend_shape_value(i, clampf(float(w.get(nm, wb.get(nm, 0.0))), -1.0, 1.0))
			count += 1
	return count


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
	set_col.call("eye_iris", lp.get("iris", Color(0.3, 0.42, 0.55)))
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
