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
const ClothingVariants := preload("res://scripts/assets/clothing_variants.gd")
const GarmentMidriffShader := preload("res://shaders/garment_midriff.gdshader")
const GarmentBuilder := preload("res://scripts/clothing/garment_builder.gd")
const ClothingWardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const DetailMaterials := preload("res://scripts/assets/character_detail_materials.gd")
const SkinLayers := preload("res://scripts/character/skin_layers.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const HandDetailBuilder := preload("res://scripts/assets/hand_detail_builder.gd")
const FingerSubrigC15 := preload("res://scripts/assets/finger_phalange_subrig_c15.gd")
const FootDetailBuilder := preload("res://scripts/assets/foot_detail_builder.gd")
const TorsoDetailBuilder := preload("res://scripts/assets/torso_detail_builder.gd")
const AnatomyOverlay := preload("res://scripts/assets/anatomy_overlay.gd")
const CharacterLod := preload("res://scripts/assets/character_lod.gd")
const LodBake := preload("res://scripts/assets/lod_bake.gd")
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
## Local, purely client-side debug depiction of Blender anatomical landmarks,
## not a new hitbox, save/network field, or actual Elmer ragdoll.
var _anatomy_overlay: Node3D = null
var _anatomy_view := "off"
var _anatomy_restore: Array = []
var _mats := {}                  # jméno materiálu -> vlastní kopie pro tuto postavu
var _posture := "stand"
var _action_id := ""
var _read_book: Node3D = null
var _held_phone: Node3D = null
## Shower removes only visual garments; canonical wardrobe is never mutated.
var _shower_garments_hidden := false
var _shower_garment_restore: Dictionary = {}
var _speed := 0.0                # vyhlazená rychlost (m/s)
var _last_pos := Vector3.ZERO
var _has_last := false
var _body_mesh_cache: Array = []
var _outfit_mats: Dictionary = {}
var _c5_nodes: Array = []
var _c5_infos: Array = []
## Procedural ten finger/nail meshes, shared geometry and per-actor materials.
var _hand_detail_nodes: Array = []
var _hand_skin_material: StandardMaterial3D
var _hand_nail_material: ShaderMaterial
## Private render-only hand pose; no CharacterData or multiplayer field.
var _hand_pose_name := "open"
## Per-digit mode keeps legacy one-slider gestures mutually exclusive with
## C14 two-joint proximal/distal pose morphs, avoiding duplicate deformation.
var _finger_joint_modes: Dictionary = {}
var _finger_skeletal_view := false
var _finger_skeletal_anchors: Dictionary = {}
var _finger_skin_before_skeleton: Array = []
## Barefoot anatomy shares original foot bones and ten clothing/body morphs.
var _foot_detail_nodes: Array = []
var _foot_skin_material: StandardMaterial3D
var _foot_nail_material: ShaderMaterial
## Neutral, gender-independent anterior torso skin, paired areola/papillae
## and umbilical relief. Rendered only with explicit no-top clothing.
var _torso_detail_nodes: Dictionary = {}
var _torso_detail_materials: Dictionary = {}
var _garment_midriff: MeshInstance3D
var _c5_signature := ""
## hair.gdshader `grey_color` (linear) – grey strands; the helmet placeholder blends towards it.
const HELMET_GREY := Color(0.60, 0.59, 0.56)
## Linear-light ratio finished strand cards / solid helmet under the same light (measured on dark and
## grey hair in the H3 render test, 0.45–0.58 per channel).
const HELMET_SHADE := 0.5
## True while the outfit waits for ClothingWardrobe's background build (placeholder clothes shown).
var _wardrobe_waiting := false
var _face_mesh_cache: Array = []
var _rest0: Array = []            # původní lokální klidové polohy kostí
var _skin_copy: Skin = null       # vlastní kopie Skin (inverzní bind matice podle kloubů této postavy)
## Authored skin is still one original Blender skinned mesh. Keep extra
## digits as real skinned morph-compatible geometry, not unsynchronized
## flat overlays. This is 5 rigid fingers per hand, NOT articulated phalanges.
func _build_hand_details() -> void:
	_hand_detail_nodes.clear()
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var source: MeshInstance3D
	for m in AssetLibrary.parts_in_group(_model, "body"):
		if AssetLibrary.part_material_name(m) == "skin_body":
			source = m
			break
	if source == null or source.skin == null:
		return
	var parts: Dictionary = HandDetailBuilder.build(source)
	if parts.is_empty():
		push_warning("Anatomy hand detail generation unavailable; retaining original hand geometry")
		return
	_hand_skin_material = StandardMaterial3D.new()
	_hand_skin_material.resource_name = "hand_detail_skin"
	_hand_skin_material.roughness = 0.62
	_hand_nail_material = DetailMaterials.nails()
	_hand_nail_material.resource_name = "hand_detail_nails"
	for label in ["skin", "nails"]:
		var mi := MeshInstance3D.new()
		mi.name = "Anatomy_fingers_" + label
		# C-LOD krok 7: automatické indexové LOD (sdílené vrcholy → morfy a póza prstů beze změny)
		mi.mesh = CharacterLod.with_lods(parts[label])
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = source.skin
		mi.material_override = _mats.get("skin_body", _hand_skin_material) if label == "skin" else _hand_nail_material
		_hand_detail_nodes.append(mi)


## Independent per-digit geometric articulation of a rigid hand skeleton:
## finger bends are isolated GPU blend shapes and apply equally to nail plates.
## Order in each hand: index, middle, ring, little finger, thumb. The underlying
## rig still has no knuckle/phalange bones or physics grasp constraints.
func set_finger_curl(side: String, finger: int, strength: float) -> bool:
	if side not in ["l", "r"] or finger < 0 or finger >= 5:
		return false
	if not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return false
	if _hand_detail_nodes.size() != 2:
		return false
	# C-LOD krok 7: ruce mohou být ve stupni 2 zapečené (bez blend shapes) – vrátit originál s vahami.
	_lod_touch_hands()
	var digit: int = finger + (5 if side == "l" else 0)
	var key: StringName = HandDetailBuilder.curl_key(digit)
	var joint_a: StringName = HandDetailBuilder.joint_key(digit,"proximal")
	var joint_b: StringName = HandDetailBuilder.joint_key(digit,"distal")
	# Validate ALL target shapes before mutation, fail atomically if absent.
	for instance in _hand_detail_nodes:
		var mesh_instance: MeshInstance3D = instance
		for shape in [key,joint_a,joint_b]:
			if mesh_instance.find_blend_shape_by_name(shape) < 0:
				return false
	for instance in _hand_detail_nodes:
		var mesh_instance: MeshInstance3D = instance
		mesh_instance.set_blend_shape_value(
			mesh_instance.find_blend_shape_by_name(joint_a),0.0)
		mesh_instance.set_blend_shape_value(
			mesh_instance.find_blend_shape_by_name(joint_b),0.0)
		mesh_instance.set_blend_shape_value(
			mesh_instance.find_blend_shape_by_name(key),strength)
	_finger_joint_modes[str(digit)] = "legacy"
	if _finger_skeletal_view and _finger_skeletal_anchors.has(side):
		var anchor:BoneAttachment3D=_finger_skeletal_anchors[side]
		FingerSubrigC15.bend(anchor,finger,"proximal",strength)
		FingerSubrigC15.bend(anchor,finger,"distal",strength)
	return true


## C14 two independent GPU bending regions per digit. Unlike the original
## combined curl, proximal and distal strengths may be different. Both target
## the exact same digit on the skinned hand mesh AND its corresponding nail.
## Visual morphs only; they do not create physical finger joint constraints.
func set_finger_joint_bend(side: String, finger: int,
		joint: String, strength: float) -> bool:
	if side not in ["l","r"] or finger < 0 or finger >= 5:
		return false
	if joint not in ["proximal","distal"] or not is_finite(strength):
		return false
	if strength < 0.0 or strength > 1.0 or _hand_detail_nodes.size() != 2:
		return false
	_lod_touch_hands()   # C-LOD krok 7: zapečené ruce → originál s vahami
	var digit: int = finger + (5 if side=="l" else 0)
	var legacy: StringName = HandDetailBuilder.curl_key(digit)
	var first: StringName = HandDetailBuilder.joint_key(digit,"proximal")
	var second: StringName = HandDetailBuilder.joint_key(digit,"distal")
	var chosen: StringName = first if joint=="proximal" else second
	for instance in _hand_detail_nodes:
		var mi:MeshInstance3D=instance
		for name in [legacy,first,second]:
			if mi.find_blend_shape_by_name(name)<0:
				return false
	for instance in _hand_detail_nodes:
		var mi:MeshInstance3D=instance
		if _finger_joint_modes.get(str(digit),"legacy")!="joint":
			mi.set_blend_shape_value(mi.find_blend_shape_by_name(legacy),0.0)
		mi.set_blend_shape_value(mi.find_blend_shape_by_name(chosen),strength)
	_finger_joint_modes[str(digit)]="joint"
	if _finger_skeletal_view and _finger_skeletal_anchors.has(side):
		# Resynchronize both real bones: switching from combined curl to joint
		# mode clears the other GPU joint, which otherwise retains a stale pose.
		var current:Dictionary=finger_joint_values(side,finger)
		var anchor:BoneAttachment3D=_finger_skeletal_anchors[side]
		FingerSubrigC15.bend(anchor,finger,"proximal",float(current.get("proximal",0.0)))
		FingerSubrigC15.bend(anchor,finger,"distal",float(current.get("distal",0.0)))
	return true


func finger_joint_values(side:String,finger:int) -> Dictionary:
	if side not in ["l","r"] or finger<0 or finger>=5 or _hand_detail_nodes.size()!=2:
		return {}
	var digit:int=finger+(5 if side=="l" else 0)
	var mi:MeshInstance3D=_hand_detail_nodes[0]
	var keys:Array=[
		HandDetailBuilder.curl_key(digit),
		HandDetailBuilder.joint_key(digit,"proximal"),
		HandDetailBuilder.joint_key(digit,"distal")]
	var values:Array=[]
	for shape in keys:
		# čtení bez rozpečení: i zapečená ruka vrací přesně uložené váhy
		var value = lod_blend_value(mi, shape)
		if value == null:return {}
		values.append(value)
	return {
		"mode":_finger_joint_modes.get(str(digit),"legacy"),
		"combined":values[0],"proximal":values[1],"distal":values[2]
	}


## Reusable genuine gestures for both hands. This is an appearance animation
## only: it does not simulate grasp collisions or change gameplay state.
func set_hand_pose(pose: String) -> bool:
	var strengths: Array
	match pose:
		"open": strengths = [0.0, 0.0, 0.0, 0.0, 0.0]
		"relaxed": strengths = [0.14, 0.22, 0.25, 0.28, 0.14]
		"fist": strengths = [1.0, 1.0, 1.0, 1.0, 0.84]
		"point": strengths = [0.0, 0.98, 0.98, 0.98, 0.48]
		"pinch": strengths = [0.68, 0.30, 0.25, 0.28, 0.75]
		_: return false
	if _hand_detail_nodes.size() != 2:
		return false
	for side in ["l", "r"]:
		for finger in 5:
			if not set_finger_curl(side, finger, float(strengths[finger])):
				return false
	_hand_pose_name = pose
	return true


## Opt-in 28-phalange genuine Skeleton3D demonstration on the actual 17-bone
## animated game character. Never sent to server or serialized.
func set_finger_skeletal_view(enabled:bool) -> bool:
	if not enabled:
		for anchor in _finger_skeletal_anchors.values():
			if is_instance_valid(anchor):
				(anchor as BoneAttachment3D).visible=false
		for item in _finger_skin_before_skeleton:
			if is_instance_valid(item[0]):
				(item[0] as MeshInstance3D).visible=bool(item[1])
		_finger_skin_before_skeleton.clear()
		_finger_skeletal_view=false
		_lod_refresh()   # ruce jsou zase vidět → ve stupni 2 je zapéct
		return true
	if _hand_detail_nodes.size()!=2 or _skeleton()==null:
		return false
	for side in ["l","r"]:
		if not _finger_skeletal_anchors.has(side):
			var anchor=FingerSubrigC15.create_hand(_skeleton(),side)
			if anchor==null:
				return false
			_finger_skeletal_anchors[side]=anchor
	if not _finger_skeletal_view:
		for item in _hand_detail_nodes:
			var mi:MeshInstance3D=item
			_finger_skin_before_skeleton.append([mi,mi.visible])
			mi.visible=false
	for side in ["l","r"]:
		var anchor:BoneAttachment3D=_finger_skeletal_anchors[side]
		anchor.visible=true
		for finger in 5:
			var state:Dictionary=finger_joint_values(side,finger)
			var proximal:float=float(state.get("proximal",0))
			var distal:float=float(state.get("distal",0))
			if state.get("mode","legacy")=="legacy":
				proximal=float(state.get("combined",0))
				distal=proximal
			FingerSubrigC15.bend(anchor,finger,"proximal",proximal)
			FingerSubrigC15.bend(anchor,finger,"distal",distal)
	_finger_skeletal_view=true
	return true


func finger_skeletal_view() -> bool:
	return _finger_skeletal_view


func hand_pose_name() -> String:
	return _hand_pose_name


## Existing shoes are hidden in barefoot outfit mode, exposing no anatomical
## foot in the original 17-bone character. Render new sole, toes, and nails ONLY
## when shoes == "bosy"; never pierce closed shoes on other outfits.
func _build_torso_details() -> void:
	_torso_detail_nodes.clear()
	_torso_detail_materials.clear()
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var shirt: MeshInstance3D = null
	for part in AssetLibrary.parts_in_group(_model, "body"):
		if AssetLibrary.part_material_name(part) == "cloth_shirt":
			shirt = part
			break
	if shirt == null or shirt.skin == null:
		return
	var parts: Dictionary = TorsoDetailBuilder.build(shirt)
	if parts.is_empty():
		push_warning("Torso skin/nipple/umbilicus atlas is unavailable; original model retained")
		return
	for label in ["surface", "areola", "nipple", "navel_rim", "navel_dark"]:
		var instance := MeshInstance3D.new()
		instance.name = "Anatomy_torso_" + label
		instance.mesh = CharacterLod.with_lods(parts[label])   # C-LOD krok 7
		skeleton.add_child(instance)
		instance.skeleton = NodePath("..")
		instance.skin = shirt.skin
		var material := StandardMaterial3D.new()
		material.resource_name = "torso_" + label
		material.roughness = .65 if label == "surface" else .77
		if label == "nipple":
			material.roughness = .59
		instance.material_override = material
		instance.visible = false
		_torso_detail_nodes[label] = instance
		_torso_detail_materials[label] = material


func torso_details_available() -> bool:
	return _torso_detail_nodes.size() == 5


func _refresh_torso_visibility(lp: Dictionary) -> void:
	var top_name := String(lp.get("outfit_top", "tricko"))
	var bare: bool = top_name == "zadne" and _anatomy_view == "off"
	for part in _torso_detail_nodes.values():
		(part as MeshInstance3D).visible = bare
	if _garment_midriff != null:
		_garment_midriff.visible = GarmentBuilder.needs_midriff(lp) and _anatomy_view == "off"
		var hem := 1.06
		for garment in _c5_nodes:
			if String(garment.name) == "C5_top_shell":
				hem = garment.mesh.get_aabb().position.y + .003
		(_garment_midriff.material_override as ShaderMaterial).set_shader_parameter("hem_height", hem)
	_lod_refresh()   # díly trupu se ukázaly/schovaly



func _build_foot_details() -> void:
	_foot_detail_nodes.clear()
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var source: MeshInstance3D
	for m in AssetLibrary.parts_in_group(_model, "body"):
		if AssetLibrary.part_material_name(m) == "shoe_leather":
			source = m
			break
	if source == null or source.skin == null:
		return
	var parts:Dictionary = FootDetailBuilder.build(source)
	if parts.is_empty():
		push_warning("Barefoot sole and toes could not be generated")
		return
	_foot_skin_material = StandardMaterial3D.new()
	_foot_skin_material.resource_name = "bare_foot_skin"
	_foot_skin_material.roughness = 0.66
	_foot_nail_material = DetailMaterials.nails()
	_foot_nail_material.resource_name = "bare_foot_nails"
	for label in ["skin", "nails"]:
		var mi := MeshInstance3D.new()
		mi.name = "Anatomy_foot_" + label
		mi.mesh = CharacterLod.with_lods(parts[label])   # C-LOD krok 7
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = source.skin
		mi.material_override = _mats.get("skin_body", _foot_skin_material) if label == "skin" else _foot_nail_material
		mi.visible = false
		_foot_detail_nodes.append(mi)


## Vlasy z karet (C4b): část → MeshInstance3D (sdílená síť na účes, vlastní materiál na postavu).
## Prázdné = karty nejdou (model bez kůže hlavy) → zůstává „helma“ z GLB (hair_short / hair_long).
var _hair_parts := {}
var _hair_mats := {}
## C-LOD krok 2: proxy účesu pro stupeň 2 (obálka karet z HairRig, materiál = helma „hair_main“ této postavy).
## null = karty se nepoužívají; _hair_proxy_ready = síť aktuálního účesu je v cache a není prázdná.
var _hair_proxy: MeshInstance3D = null
var _hair_proxy_ready := false
## C-LOD krok 3: plná síť karet skalpu a účes, ke kterému patří (ve stupni 1 se na uzlu skalpu místo ní ukazuje
## LOD1 z HairRig.cached_lod1; plná síť zůstává tady, aby šlo přepnout zpět bez nového požadavku).
var _scalp_full: ArrayMesh = null
var _scalp_style := ""
## C-LOD krok 5: totéž pro obočí a vousy – část → plná síť / styl (ve stupni ≥ 1 se ukazuje HairRig.cached_facial_lod1).
var _facial_full := {}
var _facial_style := {}
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

# C-LOD (12. 11. 2026): stupeň detailu postavy podle velikosti na obrazovce – jen prezentace klienta,
# nic se nereplikuje (viz CharacterLod). 0 = vše, 1 = mimika 10 Hz a drobné části tváře bez stínu,
# 2 = vlasové karty → helma z GLB, mimika zmrazená (oči otevřené, ústa zavřená), vnitřek úst skrytý.
## Části tváře, které ve stupni ≥ 1 nevrhají stín (materiály GLB).
const LOD_NO_SHADOW := ["eye_pupil", "eye_iris", "eye_limbus", "eye_sclera", "eye_lash", "eye_socket",
	"mouth_inner", "teeth_enamel", "mouth_gum", "mouth_tongue"]
## Vnitřek úst – ve stupni 2 skrytý.
const LOD_MOUTH := ["mouth_inner", "teeth_enamel", "mouth_gum", "mouth_tongue"]
## -1 = automaticky podle aktivní kamery; 0–2 = vynucený stupeň (testy, náhledy, cutscény).
var lod_override := -1
var _lod_tier := 0
var _lod_init := false
var _lod_check := 0.0
var _lod_expr_acc := 0.0
var _hair_ready := {}              # část vlasů → karty mají hotovou síť
var _hair_waiting := false         # skalp čeká na síť z vlákna (zatím helma)
var _lod_shadow_nodes: Array = []
var _lod_shadow_orig := {}         # MeshInstance3D → původní cast_shadow
var _lod_mouth_nodes: Array = []
## C-LOD krok 6: zapečené sítě ve stupni 2 (MeshInstance3D -> [původní síť, zapečená síť, váhy]).
var _lb_entries := {}
var _lb_dirty := false
var _lb_wait := 0.0
var _lb_task := -1
var _lb_job: Dictionary = {}
var _lb_gen := 0
## Kolikrát se postava zapekla (testy – opakované pečení bez změny = chyba).
var lod_bakes := 0
## Klid ve stupni 2 před zapečením (s) – postava, která stupněm 2 jen projde, se nepeče.
const LOD_BAKE_DELAY := 0.4


func configure(p_body: Color, p_female: bool) -> void:
	body_color = p_body
	bottom_color = p_body.darkened(0.6).lerp(Color(0.18, 0.2, 0.25), 0.5)
	female = p_female
	if _built and _model != null:
		_apply_model_variant()


## Vzhled z veřejného snapshotu CharacterData (deterministicky na všech peerech).
func apply_look(snap: Dictionary) -> void:
	_lod_touch()
	# Restore old clothes before wardrobe/morph changes, then hide newly resolved
	# ones again if the player is viewing anatomical layers.
	var prior_anatomy: String = _anatomy_view
	if prior_anatomy != "off":
		set_anatomy_view("off")
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
		# Newly built wardrobe meshes must inherit the shower-only visual mask.
		_update_shower_garments(_action_id == "shower")
		if prior_anatomy != "off":
			set_anatomy_view(prior_anatomy)
	elif _body_pivot != null and _body_pivot.get_child_count() >= 4:
		(_body_pivot.get_child(0) as MeshInstance3D).material_override = _mat(bottom_color)
		(_body_pivot.get_child(1) as MeshInstance3D).material_override = _mat(body_color, 0.85)
		(_body_pivot.get_child(2) as MeshInstance3D).material_override = _mat(skin_color, 0.55)
		(_body_pivot.get_child(3) as MeshInstance3D).material_override = _mat(hair_color, 0.9)
		_body_pivot.get_child(3).visible = String(look_params["hair_variant"]) != ""
		_body_pivot.scale = Vector3(look_params["width_scale"], look_params["height_scale"], look_params["width_scale"])


func _ready() -> void:
	_build()

func anatomy_view() -> String:
	return _anatomy_view


func anatomy_available() -> bool:
	return _model != null and AnatomyOverlay.available(_skeleton())


## Toggle on a REAL animated SimVisual instance, including actual in-world NPCs.
## Never alters character snapshot, authoritative simulation state or physics.
func set_anatomy_view(mode: String) -> bool:
	if mode not in AnatomyOverlay.VALID_LAYERS:
		return false
	if mode == "off":
		if _anatomy_overlay != null:
			AnatomyOverlay.apply_mode(_anatomy_overlay, "off")
		for pair in _anatomy_restore:
			if is_instance_valid(pair[0]):
				(pair[0] as MeshInstance3D).visible = bool(pair[1])
		_anatomy_restore.clear()
		_anatomy_view = "off"
		return true
	if not anatomy_available():
		return false
	if _anatomy_overlay == null:
		_anatomy_overlay = AnatomyOverlay.create_overlay(_skeleton())
		if _anatomy_overlay == null:
			return false
	if _anatomy_view == "off":
		for node in _model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.is_in_group("lifesim_anatomy_visual"):
				continue
			_anatomy_restore.append([mi,mi.visible])
			mi.visible = false
	if not AnatomyOverlay.apply_mode(_anatomy_overlay,mode):
		return false
	_anatomy_view = mode
	return true



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


static func preferred_character_model(web: bool, headless: bool, hq_present: bool) -> String:
	# The separately subdivided HQ import changed Skin bind order and shrank
	# lid boundaries. The rebuilt canonical mesh supplies the same detailed,
	# correctly bound character to native and web. Keep this API for callers.
	return "character"


func _build() -> void:
	if _built:
		return
	_built = true
	_body_pivot = Node3D.new()
	_body_pivot.name = "Body"
	add_child(_body_pivot)
	# Keep the original lightweight mesh for browser/WebGL and automated
	# headless simulation. Native graphical builds use the independently
	# authored higher-detail LOD without changing the 17-bone schema.
	var model_choice := preferred_character_model(
		OS.has_feature("web"), DisplayServer.get_name() == "headless",
		AssetLibrary.has_model("character_hq"))
	_model = AssetLibrary.instantiate(model_choice)
	if _model == null and model_choice != "character":
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
			_mats[mname] = skin_mat if skin_mat != null else (DetailMaterials.make(mname) if DetailMaterials.supports(mname) else src.duplicate())
		mi.material_override = _mats[mname]
	_build_hair_parts()
	_build_hand_details()
	_build_foot_details()
	# A 2162-vertex / ten-morph bare torso takes substantial CPU to assemble.
	# Do not allocate it for any clothed character; build once on first explicit
	# bare-top selection, then share the ArrayMesh between actors.
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	var clips: AnimationLibrary = CharacterAnims.library()
	# Blender HQ GLBs may wrap the original armature in a named scene root.
	# Retarget a *copy* of each animation to its actual Skeleton3D path;
	# never mutate shared low-poly/preview animation resources.
	var target_skel := _skeleton()
	if target_skel != null:
		var skeleton_path := String(_model.get_path_to(target_skel))
		if skeleton_path != "Skeleton3D":
			var rebound := AnimationLibrary.new()
			for key in clips.get_animation_list():
				var clip: Animation = clips.get_animation(key).duplicate(true)
				for ti in clip.get_track_count():
					var track_name := String(clip.track_get_path(ti))
					if track_name.begins_with("Skeleton3D:"):
						clip.track_set_path(ti, NodePath(skeleton_path + track_name.substr("Skeleton3D".length())))
				rebound.add_animation(key, clip)
			clips = rebound
	_anim.add_animation_library("", clips)
	_apply_model_variant()
	_apply_colors()
	set_hand_pose("relaxed")
	_anim.play("idle")
	_build_action_props()


## Visual-only lightweight props, parented to the actual animated right hand.
## The reading book and phone are hidden outside their corresponding actions.
func _build_action_props() -> void:
	var skel := _skeleton()
	if skel == null or skel.find_bone("hand_r") < 0:
		return
	# The book previously inherited the right wrist's rotation: it ended up
	# ~30 cm below and behind BOTH palms during the two-hand reading animation.
	# Anchor it to the chest instead, midway between both animated hands.
	var chest_mount := BoneAttachment3D.new()
	chest_mount.name = "ActionPropBookChest"
	chest_mount.bone_name = "chest"
	skel.add_child(chest_mount)
	_read_book = Node3D.new()
	_read_book.name = "HeldOpenBook"
	_read_book.position = Vector3(0.0, -0.04, 0.39)
	_read_book.rotation_degrees = Vector3(5, 0, 0)
	chest_mount.add_child(_read_book)
	var mount := BoneAttachment3D.new()
	mount.name = "ActionPropRightHand"
	mount.bone_name = "hand_r"
	skel.add_child(mount)
	var paper := _mat(Color(0.91, 0.86, 0.73), 0.95)
	var cover := _mat(Color(0.16, 0.25, 0.55), 0.65)
	for side in [-1.0, 1.0]:
		var leaf := BoxMesh.new()
		leaf.size = Vector3(0.18, 0.012, 0.22)
		_part(leaf, paper, Vector3(0.092 * side, 0.0, 0), _read_book)
		var lid := BoxMesh.new()
		lid.size = Vector3(0.184, 0.013, 0.23)
		_part(lid, cover, Vector3(0.092 * side, -0.012, 0), _read_book)
	_read_book.visible = false
	_held_phone = Node3D.new()
	_held_phone.name = "HeldPhone"
	_held_phone.position = Vector3(0, 0.05, 0.09)
	_held_phone.rotation_degrees = Vector3(25, 0, 0)
	mount.add_child(_held_phone)
	var phone := BoxMesh.new()
	phone.size = Vector3(0.08, 0.014, 0.15)
	_part(phone, _mat(Color(0.03, 0.04, 0.055), 0.2), Vector3.ZERO, _held_phone)
	var display := BoxMesh.new()
	display.size = Vector3(0.067, 0.002, 0.12)
	_part(display, _mat(Color(0.22, 0.43, 0.71), 0.35), Vector3(0, 0.009, 0), _held_phone)
	_held_phone.visible = false


## Vlasy, obočí a vousy z karet (C4b): uzly pod kostrou se stejným Skin jako hlava (kosti = bind indexy
## sdíleného Skin), síť dodá HairRig podle stylu (sdílená cache), materiál je vlastní pro postavu.
## Musí vzniknout před prvním _apply_joints, aby dostaly i kopii Skin s posunutými klouby.
func _build_hair_parts() -> void:
	_hair_parts = {}
	_hair_mats = {}
	_hair_proxy = null
	_scalp_full = null
	_scalp_style = ""
	_facial_full = {}
	_facial_style = {}
	_hair_proxy_ready = false
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
	# Proxy pro dav: stejná kostra a Skin jako karty (vzniká před prvním _apply_joints → dostane i kopii Skin).
	_hair_proxy = MeshInstance3D.new()
	_hair_proxy.name = "hair_proxy"
	skel.add_child(_hair_proxy)
	_hair_proxy.skeleton = NodePath("..")
	_hair_proxy.skin = head_mi.skin
	_hair_proxy.visible = false
	_hair_proxy.material_override = _proxy_material()


## Materiál proxy = materiál helmy této postavy (stejná kalibrovaná barva jako zástupná helma, viz
## helmet_placeholder_color); bez něj vlastní StandardMaterial3D, který barví _apply_colors.
func _proxy_material() -> Material:
	if _mats.has("hair_main"):
		return _mats["hair_main"]
	var sm := StandardMaterial3D.new()
	sm.roughness = 0.85
	sm.albedo_color = helmet_placeholder_color(look_params if not look_params.is_empty() else AppearanceResolver.resolve({}))
	return sm


## C-LOD krok 2: síť proxy podle aktuálního účesu – jen z cache (vzniká spolu s kartami skalpu, nikdy neblokuje).
## scalp_ready = karty skalpu aktuálního účesu jsou hotové; jinak proxy není a ve stupni 2 zůstává helma.
func _update_hair_proxy(lp: Dictionary, scalp_ready: bool) -> void:
	if _hair_proxy == null:
		_hair_proxy_ready = false
		return
	var m: ArrayMesh = null
	if scalp_ready:
		var style := String((lp.get("hair_look", {}) as Dictionary).get("style", "kratke"))
		var r := HairRig.cached_proxy(style)
		if bool(r["ready"]):
			m = r["mesh"]
	if lod_source_mesh(_hair_proxy) != m:
		_hair_proxy.mesh = m
		_invalidate_expression_slots()
	_hair_proxy_ready = m != null
	_hair_proxy.visible = _hair_proxy_ready and _lod_tier >= 2


## C-LOD krok 3: síť skalpu pro aktuální stupeň – ve stupni 1 LOD1 karet (jen z cache, vzniká spolu s kartami;
## null/nehotová → plné karty), jinak plné karty. Ve stupni 2 jsou karty skryté (proxy), síť se proto nemění,
## aby přechod 1 ↔ 2 nepřepisoval sítě zbytečně.
func _scalp_mesh_for_tier() -> ArrayMesh:
	if _scalp_full == null:
		return null
	if _lod_tier == 1 or (_lod_tier >= 2 and _hair_parts.has("scalp") and (_hair_parts["scalp"] as MeshInstance3D).mesh != _scalp_full):
		var r := HairRig.cached_lod1(_scalp_style)
		if bool(r["ready"]) and r["mesh"] != null:
			return r["mesh"]
	return _scalp_full


## C-LOD krok 5: síť obočí/vousů pro aktuální stupeň – ve stupni ≥ 1 LOD1 (jen z cache, vzniká spolu s plnou sítí;
## null = styl bez úspory → plná síť). Ve stupni 2 jsou části skryté, síť se proto při přechodu 1 ↔ 2 nemění.
func _facial_mesh_for_tier(part: String) -> ArrayMesh:
	var full: ArrayMesh = _facial_full.get(part)
	if full == null:
		return null
	if _lod_tier >= 1:
		var r := HairRig.cached_facial_lod1(part, String(_facial_style.get(part, "")))
		if bool(r["ready"]) and r["mesh"] != null:
			return r["mesh"]
	return full


## Po změně stupně: vyměnit sítě skalpu, obočí a vousů (plná ↔ LOD1) a hned zapsat váhy tvaru obličeje/těla,
## které LOD1 nese pod stejnými jmény (instance by jinak do příštího apply_look ukazovala neutrální tvar hlavy).
func _apply_hair_lod() -> void:
	var changed := false
	if _hair_parts.has("scalp") and _scalp_full != null:
		var mi: MeshInstance3D = _hair_parts["scalp"]
		var want := _scalp_mesh_for_tier()
		if mi.mesh != want:
			mi.mesh = want
			changed = true
	for part in ["brows", "beard"]:
		if not _hair_parts.has(part) or _facial_full.get(part) == null:
			continue
		var fmi: MeshInstance3D = _hair_parts[part]
		var fwant := _facial_mesh_for_tier(part)
		if fmi.mesh != fwant:
			fmi.mesh = fwant
			changed = true
	if not changed:
		return
	_invalidate_expression_slots()
	apply_face_shape(look_params if not look_params.is_empty() else AppearanceResolver.resolve({}))


## Síť skalpu, kterou postava právě ukazuje (testy): plná karta nebo LOD1.
func scalp_lod_mesh() -> ArrayMesh:
	if not _hair_parts.has("scalp"):
		return null
	return (_hair_parts["scalp"] as MeshInstance3D).mesh as ArrayMesh


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
	# C-LOD: ve stupni 2 je helma vidět záměrně (karty jsou hotové) – to není čekání
	return helm_visible and _hair_waiting and not (_hair_parts["scalp"] as MeshInstance3D).visible


## Uzel části vlasů z karet (testy); null = karty se nepoužívají.
func hair_part(part: String) -> MeshInstance3D:
	return _hair_parts.get(part)


func hair_material(part: String) -> ShaderMaterial:
	return _hair_mats.get(part)


## Proxy účesu pro dav (testy); null = karty se nepoužívají.
func hair_proxy() -> MeshInstance3D:
	return _hair_proxy


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
				_hair_ready[part] = false
				if part == "scalp":
					waiting = true
				continue
			var m: ArrayMesh = r["mesh"]
			var shown := m
			if part == "scalp":
				_scalp_full = m
				_scalp_style = styles[part]
				shown = _scalp_mesh_for_tier()
			else:
				_facial_full[part] = m
				_facial_style[part] = styles[part]
				shown = _facial_mesh_for_tier(part)
			if mi.mesh != shown:
				mi.mesh = shown
				_invalidate_expression_slots()
			_hair_ready[part] = m != null
			# C-LOD stupeň 2: karty schované, místo nich proxy účesu (bez proxy helma; viz _apply_lod_visibility)
			mi.visible = m != null and _lod_tier < 2
	_hair_waiting = cards and waiting
	_update_hair_proxy(lp, cards and not waiting)
	var helm := not cards or waiting or (cards and _lod_tier >= 2 and not _hair_proxy_ready)
	var show := {"body": true, "body_m": false, "body_f": false, "head": true,
		"hair_short": hair_v == "hair_short" and helm, "hair_long": hair_v == "hair_long" and helm}
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		if _hair_parts.values().has(mi) or mi == _hair_proxy:
			continue
		var grp := String(mi.name).get_slice("__", 0)
		mi.visible = bool(show.get(grp, true))
		if _lod_tier >= 2 and AssetLibrary.part_material_name(mi) in LOD_MOUTH:
			mi.visible = false
	# Ensure the first skinned torso exists BEFORE morphs and material updates.
	# Ordinary dressed characters pay ZERO procedural torso construction cost.
	if (String(lp.get("outfit_top","tricko")) == "zadne" or GarmentBuilder.needs_midriff(lp)) and _torso_detail_nodes.is_empty():
		_build_torso_details()
	if GarmentBuilder.needs_midriff(lp) and _garment_midriff == null and _torso_detail_nodes.has("surface"):
		var torso: MeshInstance3D = _torso_detail_nodes["surface"]
		var skin_mesh: ArrayMesh = GarmentBuilder.midriff_mesh(torso.mesh)
		if skin_mesh != null:
			_garment_midriff = MeshInstance3D.new()
			_garment_midriff.name = "Garment_midriff_skin"
			_garment_midriff.mesh = skin_mesh
			_skeleton().add_child(_garment_midriff)
			_garment_midriff.skeleton = NodePath("..")
			_garment_midriff.skin = torso.skin
			var midriff_material := ShaderMaterial.new()
			midriff_material.shader = GarmentMidriffShader
			midriff_material.set_shader_parameter("skin_color", lp.get("skin", skin_color))
			_garment_midriff.material_override = midriff_material
	_apply_outfit(lp)
	apply_body_shape(lp)
	apply_face_shape(lp)
	_refresh_torso_visibility(lp)


## C5: use the separate garment mesh surfaces authored in Blender as the source for
## tailored shape-key-preserving variants. All three parts retain skinning to the
## original 17-bone skeleton, and current outfit fields come from the public snapshot.
func _apply_outfit(lp: Dictionary) -> void:
	if _model == null:
		return
	if ClothingWardrobe.is_available():
		_apply_c5_wardrobe(lp)
		return
	var garments := {
		"cloth_shirt": ["top", String(lp.get("outfit_top", "tricko")), lp.get("top", body_color)],
		"cloth_pants": ["bottom", String(lp.get("outfit_bottom", "dziny")), lp.get("bottom", bottom_color)],
		"shoe_leather": ["shoe", String(lp.get("outfit_shoes", "tenisky")), Color(0.14, 0.13, 0.13)],
	}
	for mi in _body_meshes():
		var mname := AssetLibrary.part_material_name(mi)
		if not garments.has(mname):
			continue
		var props: Array = garments[mname]
		var part: String = props[0]
		var garment: String = props[1]
		if not mi.has_meta("c5_source_mesh"):
			mi.set_meta("c5_source_mesh", mi.mesh)
		var source: Mesh = mi.get_meta("c5_source_mesh")
		var tailored := ClothingVariants.variant_mesh(source, part, garment)
		if tailored != null and mi.mesh != tailored:
			mi.mesh = tailored
		var mkey := mname + "/" + garment
		if not _outfit_mats.has(mkey):
			_outfit_mats[mkey] = ClothingVariants.garment_material(garment, part, props[2])
		var mat: StandardMaterial3D = _outfit_mats[mkey]
		mat.albedo_color = props[2]
		mi.material_override = mat
		# True bare feet and dresses/skirts will get tailored meshes in stage C5b.
		mi.visible = garment != "zadne" and garment != "bosy"


## C5 authored Blender wardrobe: accessory geometry, actual skirt/shorts/hood/collar and
## PBR textures all come from Blender and are transported via the existing LSX decoder.
## We reuse the character's skeleton/Skin, do not duplicate the rig or body.
func _apply_c5_wardrobe(lp: Dictionary) -> void:
	var skel := _skeleton()
	if skel == null:
		return
	var source_skin: Skin = _skin_copy
	if source_skin == null:
		for body_mi in AssetLibrary.parts_in_group(_model, "body"):
			if body_mi.skin != null:
				source_skin = body_mi.skin
				break
	if source_skin == null:
		return
	var signature := "%s/%s/%s" % [String(lp.get("outfit_top", "tricko")),
		String(lp.get("outfit_bottom", "dziny")), String(lp.get("outfit_shoes", "tenisky"))]
	signature += "/" + JSON.stringify(lp.get("garment_designs", {}), "", true)
	if signature != _c5_signature:
		# Game (ClothingWardrobe.async_load): a garment kind seen for the first time is built in the
		# WorkerThreadPool instead of freezing this frame for seconds. Until then the previous outfit
		# stays on, or – for a brand-new character – the plain GLB clothes (never a bare body).
		if not ClothingWardrobe.ensure_kinds(ClothingWardrobe.kinds_for(lp), self):
			_wardrobe_waiting = true
			_show_wardrobe_placeholder(lp)
			return
		_wardrobe_waiting = false
		for node in _c5_nodes:
			if is_instance_valid(node):
				(node as Node).get_parent().remove_child(node)
				(node as Node).free()
		_c5_nodes.clear()
		_c5_infos.clear()
		_body_mesh_cache.clear()
		var entries := GarmentBuilder.parts(lp)
		for entry in entries:
			var mi := MeshInstance3D.new()
			mi.name = "C5_" + String(entry.get("category", "")) + "_" + String(entry["name"])
			mi.mesh = entry["mesh"]
			skel.add_child(mi)
			mi.skeleton = NodePath("..")
			mi.skin = source_skin
			mi.material_override = GarmentBuilder.material(entry, lp)
			mi.visible = true
			_c5_nodes.append(mi)
			_c5_infos.append(entry)
		_c5_signature = signature
	else:
		for i in _c5_nodes.size():
			var mi: MeshInstance3D = _c5_nodes[i]
			if is_instance_valid(mi) and mi.material_override is StandardMaterial3D:
				(mi.material_override as StandardMaterial3D).albedo_color = ClothingWardrobe.tint(_c5_infos[i], lp)
	for foot in _foot_detail_nodes:
		foot.visible = String(lp.get("outfit_shoes", "tenisky")) == "bosy"
	for body_mi in AssetLibrary.parts_in_group(_model, "body"):
		var mname := AssetLibrary.part_material_name(body_mi)
		if mname in ["cloth_shirt", "cloth_pants", "shoe_leather"]:
			body_mi.visible = false


## Placeholder while the authored wardrobe builds in the background: the GLB's own shirt, trousers
## and shoes (they carry the body morphs), shown per the outfit's coverage. If authored garments are
## already on (outfit change), they stay until the new set is ready.
func _show_wardrobe_placeholder(lp: Dictionary) -> void:
	if not _c5_nodes.is_empty() or _model == null:
		return
	var top := String(lp.get("outfit_top", "tricko"))
	var bottom := String(lp.get("outfit_bottom", "dziny"))
	var shoes := String(lp.get("outfit_shoes", "tenisky"))
	for body_mi in AssetLibrary.parts_in_group(_model, "body"):
		match AssetLibrary.part_material_name(body_mi):
			"cloth_shirt":
				body_mi.visible = top != "zadne"
			"cloth_pants":
				body_mi.visible = bottom != "zadne" or top == "saty"
			"shoe_leather":
				body_mi.visible = shoes != "bosy"
	for foot in _foot_detail_nodes:
		foot.visible = shoes == "bosy"


## ClothingWardrobe finished a garment kind in the background → rebuild the outfit from the CURRENT
## look (if the outfit changed meanwhile, the new one is used). Runs on the main thread.
func _on_wardrobe_ready(_kind: String) -> void:
	if _wardrobe_waiting and _model != null and is_inside_tree():
		_apply_model_variant()


## Is the outfit still waiting for a background garment build (placeholder shown)? (tests)
func wardrobe_waiting() -> bool:
	return _wardrobe_waiting


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
	_lod_touch()
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
	_lod_touch()
	var count := 0
	# Base body remains the four original meshes (used by anatomical tests).
	# Authored C5 garments also receive the ten body morph weights.
	var shaped_parts: Array = _body_meshes().duplicate()
	shaped_parts.append_array(_c5_nodes)
	shaped_parts.append_array(_hand_detail_nodes)
	shaped_parts.append_array(_foot_detail_nodes)
	shaped_parts.append_array(_torso_detail_nodes.values())
	if _garment_midriff != null: shaped_parts.append(_garment_midriff)
	for mi in shaped_parts:
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
		for hand in ["hand_l", "hand_r"]:
			var hi := skel.find_bone(hand)
			if hi >= 0:
				skel.set_bone_pose_scale(hi, Vector3.ONE * float(lp.get("hand_scale", 1.0)))
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
		# Proxy nese stejné přenesené klíče jako karty skalpu.
		if _hair_proxy != null:
			_face_mesh_cache.append(_hair_proxy)
	return _face_mesh_cache


func _body_meshes() -> Array:
	if _body_mesh_cache.is_empty() and _model != null:
		_body_mesh_cache = AssetLibrary.parts_in_group(_model, "body")
	return _body_mesh_cache


var _skeleton_cache: Skeleton3D = null

func _skeleton() -> Skeleton3D:
	if _skeleton_cache != null and is_instance_valid(_skeleton_cache):
		return _skeleton_cache
	if _model == null:
		return null
	_skeleton_cache = _model.get_node_or_null("Skeleton3D") as Skeleton3D
	if _skeleton_cache == null:
		# Blender's native HQ scene wraps the armature under its original
		# 'body' node; all bone-dependent systems must resolve it there.
		var matches := _model.find_children("*", "Skeleton3D", true, false)
		if not matches.is_empty():
			_skeleton_cache = matches[0] as Skeleton3D
	return _skeleton_cache


static func _morph_bones() -> Dictionary:
	var mb = AssetLibrary.manifest_meta("character").get("morph_bones", {})
	return mb if typeof(mb) == TYPE_DICTIONARY else {}


func _apply_colors() -> void:
	var set_col := func(mname: String, c: Color) -> void:
		if _mats.has(mname):
			DetailMaterials.color(_mats[mname],c)
	set_col.call("cloth_shirt", body_color)
	set_col.call("cloth_pants", bottom_color)
	set_col.call("skin_body", skin_color)
	if _hand_skin_material != null:
		_hand_skin_material.albedo_color = skin_color
	if _hand_nail_material != null:
		DetailMaterials.color(_hand_nail_material,skin_color.lerp(Color(0.82, 0.65, 0.62), 0.20))
	if _foot_skin_material != null:
		_foot_skin_material.albedo_color = skin_color
	if _foot_nail_material != null:
		DetailMaterials.color(_foot_nail_material,skin_color.lerp(Color(0.82, 0.65, 0.62), 0.20))
	if _garment_midriff != null:
		(_garment_midriff.material_override as ShaderMaterial).set_shader_parameter("skin_color", skin_color)
	# Derived only from each character's resolved SKIN color; no sexuality,
	# gender or sex-based assumptions, and no personal data propagation.
	var tone: Dictionary = {
		"surface": skin_color,
		"areola": skin_color.darkened(.14),
		"nipple": skin_color.darkened(.19),
		"navel_rim": skin_color.darkened(.08),
		"navel_dark": skin_color.darkened(.42)
	}
	for part in _torso_detail_materials:
		var material: StandardMaterial3D = _torso_detail_materials[part]
		material.albedo_color = tone.get(part,skin_color)
	var lp: Dictionary = look_params if not look_params.is_empty() else AppearanceResolver.resolve({})
	# With strand cards the GLB "helmet" is only the placeholder while HairRig builds the style in the
	# background; it must read as the same hair colour as the finished cards (H3 rendered parity,
	# 8 Nov 2026: it showed light tan over dark-brown cards). Without cards it IS the hair: unchanged.
	set_col.call("hair_main", helmet_placeholder_color(lp) if not _hair_parts.is_empty() else hair_color)
	if _hair_proxy != null:
		if _mats.has("hair_main"):
			_hair_proxy.material_override = _mats["hair_main"]
		elif _hair_proxy.material_override is StandardMaterial3D:
			(_hair_proxy.material_override as StandardMaterial3D).albedo_color = helmet_placeholder_color(lp)
	apply_skin(lp)
	for part in _hair_mats:
		HairRig.apply(_hair_mats[part], lp, part)
	set_col.call("eye_iris", lp.get("iris", Color(0.3, 0.42, 0.55)))
	set_col.call("eye_limbus", lp.get("limbus", Color(0.14, 0.2, 0.27)))
	set_col.call("eye_lash", lp.get("lash", Color(0.06, 0.045, 0.035)))
	# běh 22: tmavší kořen řas – barva vrcholů karet (HeadBuilder) násobí albedo
	if _mats.has("eye_lash") and _mats["eye_lash"] is StandardMaterial3D:
		(_mats["eye_lash"] as StandardMaterial3D).vertex_color_use_as_albedo = true
	# běh 22: dutina úst není čistě černá – sliznice odvozená z kůže (stejný model pro všechny odstíny), ztmavená hloubkou
	set_col.call("mouth_inner", skin_color.lerp(Color(0.50, 0.16, 0.16), 0.6).darkened(0.55))
	set_col.call("teeth_enamel", lp.get("teeth", Color(0.93, 0.92, 0.87)))
	set_col.call("mouth_gum", lp.get("gum", Color(0.78, 0.42, 0.44)))
	set_col.call("mouth_tongue", lp.get("tongue", Color(0.74, 0.38, 0.4)))
	set_col.call("skin_lips", lp.get("lips", skin_color.darkened(0.2)))
	# Vnitřek víček/spojivka: kůže do růžova (stejný model pro všechny odstíny kůže).
	set_col.call("eye_socket", skin_color.lerp(Color(0.72, 0.36, 0.36), 0.55))


## Albedo for the GLB hair "helmet" while it stands in for HairRig strand cards. The cards feed the
## resolver's natural colour through srgb_to_linear() into hair.gdshader (and blend per-strand grey in
## that space); the helmet reuses exactly those numbers as its (sRGB) albedo and then darkens in linear
## light by HELMET_SHADE. This is an EMPIRICAL match of what the cards look like on screen (strand
## shading, gaps, the shader's colour handling), not a physical colour-space conversion – it is
## verified by tests/test_h3_async_placeholder_render.gd (mean crown colour, dark and grey hair) under
## the preview light rig in GL Compatibility; Forward+ and night lighting are not yet measured.
static func helmet_placeholder_color(lp: Dictionary) -> Color:
	var hv: Dictionary = lp.get("hair_look", {})
	var base: Color = hv.get("natural", lp.get("hair", Color(0.3, 0.2, 0.12)))
	var lin := base.srgb_to_linear()
	var grey := clampf(float(hv.get("grey", 0.0)), 0.0, 1.0)
	var c := Color(lin.r, lin.g, lin.b).lerp(HELMET_GREY, grey)
	# Strand shading (0.62–1.12) and the gaps between cards make the cards darker than a solid shell
	# lit the same way: scale in linear light by the measured ratio.
	var l := c.srgb_to_linear()
	c = Color(l.r * HELMET_SHADE, l.g * HELMET_SHADE, l.b * HELMET_SHADE).linear_to_srgb()
	c.a = 1.0
	return c


## Kůže (C4): chromofory a vrstvy do shaderu kůže. Vrací počet nastavených parametrů (0 = StandardMaterial3D).
func apply_skin(lp: Dictionary) -> int:
	var m = _mats.get("skin_body")
	if m is ShaderMaterial:
		return SkinLayers.apply(m as ShaderMaterial, lp)
	return 0


## Materiál kůže této postavy (testy).
func skin_material() -> Material:
	return _mats.get("skin_body")


var _crying := false

## Shower state is cosmetic: do not change the saved outfit, body or multiplayer data.
## Rebuilds of C5 meshes may replace nodes while showering; remove stale entries.
func _update_shower_garments(in_shower: bool) -> void:
	if _model == null:
		return
	if not in_shower and not _shower_garments_hidden:
		return
	var garments: Array = []
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.name.begins_with("C5_") or AssetLibrary.part_material_name(mesh) in [
			"cloth_shirt", "cloth_pants", "shoe_leather"]:
			garments.append(mesh)
	if in_shower:
		for mi in garments:
			if not _shower_garment_restore.has(mi):
				_shower_garment_restore[mi] = mi.visible
			mi.visible = false
		for foot in _foot_detail_nodes:
			if is_instance_valid(foot):
				foot.visible = true
		_shower_garments_hidden = true
	else:
		for mi in _shower_garment_restore:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = bool(_shower_garment_restore[mi])
		_shower_garment_restore.clear()
		for foot in _foot_detail_nodes:
			if is_instance_valid(foot):
				foot.visible = String(look_params.get("outfit_shoes", "tenisky")) == "bosy"
		_shower_garments_hidden = false
	_lod_refresh()   # chodidla se ukázala/schovala


## posture: stand / sit / lie; mood_value −100..100; speech = replika (prázdná = nic).
func apply(posture: String, mood_value: float, emotion: String, title: String, action_text: String, speech := "", is_crying: bool = false, action_id: String = "") -> void:
	if not _built:
		_build()
	var posture_changed := _posture != posture
	_posture = posture
	_action_id = action_id
	_update_shower_garments(_action_id == "shower")
	if _read_book != null:
		_read_book.visible = _action_id == "read"
	if _held_phone != null:
		_held_phone.visible = _action_id in ["text_friend", "doomscroll"]
	match posture:
		"lie":
			if posture_changed:
				_body_pivot.rotation = Vector3(-PI / 2.0, 0, 0)
				# Face must clear the pillow (pillow ends near local z=-0.57).
				# The footward shift is bounded by the end of the ~2.1 m mattress.
				_body_pivot.position = Vector3(0, 0.79, 1.10)
		"sit":
			if posture_changed:
				_body_pivot.rotation = Vector3.ZERO
				# Start from the model's canonical seat pose. A real ankle contact
				# correction then adapts to each character's morphed leg lengths.
				var lift := float(look_params.get("lift", 0.0)) * float(look_params.get("height_scale", 1.0))
				_body_pivot.position = Vector3(0, -lift, 0) if _model != null else Vector3(0, -0.3, 0)
		_:
			if posture_changed:
				_body_pivot.rotation = Vector3.ZERO
				_body_pivot.position = Vector3.ZERO
	_update_anim()
	_emotion = emotion
	_crying = is_crying
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
	if _crying:
		txt += "\nPláče"
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
			if _action_id == "read":
				want = "read"
			elif _action_id == "cook":
				want = "cook"
			elif _action_id in ["text_friend", "doomscroll"]:
				want = "text"
			elif _action_id in ["snack", "drink", "use_caffeine"]:
				want = "eat"
			elif _action_id == "workout":
				want = "walk"
			else:
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


## Adjust seated root height from both actual animated ankle bones, not
## a fixed person's leg length. This is a small foot-floor contact solver,
## not a claim of full-body IK; do not modify the authoritative SimAgent.
func _seat_foot_contact(delta: float) -> void:
	if _posture != "sit" or _model == null or _anim == null or delta <= 0.0:
		return
	var skel := _skeleton()
	if skel == null:
		return
	var li := skel.find_bone("foot_l")
	var ri := skel.find_bone("foot_r")
	if li < 0 or ri < 0:
		return
	# The foot bone sits around 8 cm above the sole on the reference mesh.
	var foot_y := minf(skel.to_global(skel.get_bone_global_pose(li).origin).y,
		skel.to_global(skel.get_bone_global_pose(ri).origin).y)
	var target_y := global_position.y + 0.08
	var error := target_y - foot_y
	var corrected_y := clampf(_body_pivot.position.y + error, -0.26, 0.12)
	_body_pivot.position.y = lerpf(_body_pivot.position.y, corrected_y,
		clampf(delta * 7.0, 0.0, 1.0))


func _process(delta: float) -> void:
	if _gem != null:
		_gem.rotate_y(delta * 1.5)
	track_motion(delta)
	_seat_foot_contact(delta)
	if _anim != null and _posture == "stand":
		_update_anim()
	_lod_tick(delta)
	_lod_bake_tick(delta)
	if _model != null and expressions_enabled:
		if _lod_tier == 0:
			update_expression(delta)
		elif _lod_tier == 1:
			# 10 Hz se sečteným časem – mrkání i řeč běží dál, jen řidčeji
			_lod_expr_acc += delta
			if _lod_expr_acc >= CharacterLod.T1_EXPR_INTERVAL:
				update_expression(_lod_expr_acc)
				_lod_expr_acc = 0.0
		# stupeň 2: mimika zmrazená (nastavená při přechodu v set_lod_tier)


# ======================================================================================
# C-LOD – stupeň detailu postavy (12. 11. 2026)
# ======================================================================================
## Aktuální stupeň detailu: 0 plný, 1 střední, 2 dav.
func lod_tier() -> int:
	return _lod_tier


## Podíl výšky obrazu, který postava zabírá v aktivní kameře svého viewportu (INF = bez kamery → plný detail).
func lod_fraction() -> float:
	if not is_inside_tree():
		return INF
	var vp := get_viewport()
	if vp == null:
		return INF
	return CharacterLod.camera_fraction(vp.get_camera_3d(), global_position + Vector3(0.0, 1.0, 0.0))


func _lod_detail_scale() -> float:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null or not gs.has_method("get_value"):
		return 1.0
	return CharacterLod.detail_scale(int(gs.get_value("crowd_detail")))


## Přepočet stupně: poprvé hned (postava vzniklá daleko neukáže na chvíli karty), pak každých CHECK_INTERVAL s
## s fází rozloženou podle instance, ať se všechny postavy nepřepočítávají ve stejném snímku.
func _lod_tick(delta: float) -> void:
	if _model == null:
		return
	if lod_override >= 0:
		if clampi(lod_override, 0, 2) != _lod_tier:
			set_lod_tier(lod_override)
		return
	if _lod_init:
		_lod_check -= delta
		if _lod_check > 0.0:
			return
		_lod_check = CharacterLod.CHECK_INTERVAL
	else:
		_lod_init = true
		_lod_check = CharacterLod.CHECK_INTERVAL * float(get_instance_id() % 97) / 97.0
	var t := CharacterLod.tier_for(lod_fraction(), _lod_tier, _lod_detail_scale())
	if t != _lod_tier:
		set_lod_tier(t)


## Nastaví stupeň detailu hned. Vrací true, když se změnil.
func set_lod_tier(tier: int) -> bool:
	var t := clampi(tier, 0, 2)
	if t == _lod_tier:
		return false
	var prev := _lod_tier
	_lod_tier = t
	_lod_expr_acc = 0.0
	if t < 2 and prev >= 2:
		_lod_unbake()
		_lb_dirty = false
		_lb_gen += 1
	if _model == null:
		return true
	_apply_lod_visibility()
	_apply_lod_shadows()
	_apply_hair_lod()
	if t >= 2 and prev < 2:
		_freeze_expression()
		_lb_dirty = true
		_lb_wait = LOD_BAKE_DELAY
	return true


## Viditelnost podle stupně: karty vlasů ↔ helma a vnitřek úst. Neřeší nic jiného (oblečení, tvar) –
## proto je přepnutí levné a nesahá na _apply_model_variant.
func _apply_lod_visibility() -> void:
	if _model == null:
		return
	var far := _lod_tier >= 2
	if not _hair_parts.is_empty():
		for part in _hair_parts:
			(_hair_parts[part] as MeshInstance3D).visible = bool(_hair_ready.get(part, false)) and not far
		var hair_v := "hair_short" if look_params.is_empty() else String(look_params["hair_variant"])
		var helm := _hair_waiting or (far and not _hair_proxy_ready)
		if _hair_proxy != null:
			_hair_proxy.visible = far and _hair_proxy_ready and not _hair_waiting
		for g in ["hair_short", "hair_long"]:
			for mi in AssetLibrary.parts_in_group(_model, g):
				mi.visible = g == hair_v and helm
	if _lod_mouth_nodes.is_empty():
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			if AssetLibrary.part_material_name(mi) in LOD_MOUTH:
				_lod_mouth_nodes.append(mi)
	for mi in _lod_mouth_nodes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = not far


## Stíny drobných částí tváře (oči, řasy, ústa, obočí, vousy) ve stupni ≥ 1 vypnuté, ve stupni 0 původní.
func _apply_lod_shadows() -> void:
	if _model == null:
		return
	if _lod_shadow_nodes.is_empty():
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			if not _hair_parts.values().has(mi) and AssetLibrary.part_material_name(mi) in LOD_NO_SHADOW:
				_lod_shadow_nodes.append(mi)
		for part in ["brows", "beard"]:
			if _hair_parts.has(part):
				_lod_shadow_nodes.append(_hair_parts[part])
	var off := _lod_tier >= 1
	for mi in _lod_shadow_nodes:
		if not is_instance_valid(mi):
			continue
		var g := mi as GeometryInstance3D
		if off:
			if not _lod_shadow_orig.has(g):
				_lod_shadow_orig[g] = g.cast_shadow
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _lod_shadow_orig.has(g):
			g.cast_shadow = _lod_shadow_orig[g]
	if not off:
		_lod_shadow_orig = {}


## Přechod do stupně 2: dokončit výraz bez mrknutí a řeči (oči otevřené – jen případná ospalost z emoce),
## ústa zavřená, a zapsat ho. Pak se mimika nepočítá, dokud se postava nepřiblíží.
func _freeze_expression() -> void:
	_blink_phase = -1.0
	_blink_second = false
	_talk_left = 0.0
	var lid := float(_ex.get("_lid", 0.0))
	_ex["ex_blink_l"] = lid
	_ex["ex_blink_r"] = lid
	_ex["ex_jaw_open"] = 0.0
	if expressions_enabled and not _expression_slots().is_empty():
		_write_expression(true)


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
	_lod_touch()


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
	if _crying:
		ef = [0.0, 0.85, 0.28, 0.25, 0.0, 1.0]
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
	# Zapečené sítě nemají blend shapes: bez vynucení nic, s vynucením (cutscéna, test) zapečení zrušit.
	if not _lb_entries.is_empty() or (_lb_task >= 0 and _lod_tier >= 2):
		if not force:
			return 0
		_lod_touch()
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


# ======================================================================================
# C-LOD krok 6 (18. 11. 2026): zapečení blend shapes ve stupni 2
# ======================================================================================
## Ve stupni 2 se viditelné sítě s blend shapes (od kroku 7 i ruce – mutátory póz prstů volají _lod_touch(),
## finger_joint_values čte uložené váhy přes lod_blend_value) nahradí
## statickou sítí s aplikovanými vahami (LodBake, ve vlákně). Každá změna vah nebo sítí (_lod_touch) zapečení
## zruší a obnoví původní síť s přesně uloženými vahami; po LOD_BAKE_DELAY klidu se zapeče znovu.

## Původní síť instance (i když je právě zapečená).
func lod_source_mesh(mi: MeshInstance3D) -> Mesh:
	if mi == null:
		return null
	var e = _lb_entries.get(mi)
	if e != null and mi.mesh == e[1]:
		return e[0]
	return mi.mesh


## Kolik instancí má právě zapečenou síť (testy, diagnostika).
func lod_baked_count() -> int:
	var n := 0
	for mi in _lb_entries:
		if is_instance_valid(mi) and (mi as MeshInstance3D).mesh == _lb_entries[mi][1]:
			n += 1
	return n


## Váha blend shape `shape` instance – i když je právě zapečená (pak z původní sítě a uložených vah).
## null = instance takový klíč nemá. Čtení nic nerozpéká (C-LOD krok 7).
func lod_blend_value(mi: MeshInstance3D, shape: StringName):
	if mi == null:
		return null
	var e = _lb_entries.get(mi)
	if e != null and mi.mesh == e[1]:
		var src: Mesh = e[0]
		var w: PackedFloat32Array = e[2]
		for i in mini(src.get_blend_shape_count(), w.size()):
			if src.get_blend_shape_name(i) == shape:
				return w[i]
		return null
	var idx := mi.find_blend_shape_by_name(shape)
	return null if idx < 0 else mi.get_blend_shape_value(idx)


## Póza prstů mění jen váhy rukou: rozpéct jen ruce (zbytek postavy zůstane zapečený) a ve stupni 2
## naplánovat jejich nové pečení. Generace se nemění – běžící úloha smí dokončit ostatní díly; její výsledek
## pro ruce _lod_swap odmítne, protože váhy instance už neodpovídají.
func _lod_touch_hands() -> void:
	for mi in _hand_detail_nodes:
		var e = _lb_entries.get(mi)
		if e == null:
			continue
		_lb_entries.erase(mi)
		if not is_instance_valid(mi) or (mi as MeshInstance3D).mesh != e[1]:
			continue
		(mi as MeshInstance3D).mesh = e[0]
		var w: PackedFloat32Array = e[2]
		for i in mini(w.size(), (mi as MeshInstance3D).get_blend_shape_count()):
			(mi as MeshInstance3D).set_blend_shape_value(i, w[i])
	_lod_refresh()


## Změnila se jen viditelnost dílů (sprcha, trup, kostra prstů): ve stupni 2 naplánovat pečení nově
## viditelných sítí. Nic se nerozpéká – už zapečené instance _lod_bake_start přeskočí.
func _lod_refresh() -> void:
	# I při běžící úloze: po jejím dokončení _lod_bake_tick spustí další kolo jen pro nezapečené instance.
	if _lod_tier >= 2:
		_lb_dirty = true
		_lb_wait = maxf(_lb_wait, LOD_BAKE_DELAY)


## Čeká se na zapečení (odpočet nebo běžící úloha)?
func lod_bake_pending() -> bool:
	return _lb_task >= 0 or (_lb_dirty and _lod_tier >= 2)


## Váhy nebo sítě se mění: zrušit zapečení (i rozpracované) a ve stupni 2 naplánovat nové.
func _lod_touch() -> void:
	_lb_gen += 1
	if not _lb_entries.is_empty():
		_lod_unbake()
	if _lod_tier >= 2:
		_lb_dirty = true
		_lb_wait = LOD_BAKE_DELAY


## Vrátí původní sítě a jejich váhy. Instance, které mezitím dostaly jinou síť, se nechají být.
func _lod_unbake() -> void:
	for mi in _lb_entries:
		if not is_instance_valid(mi):
			continue
		var e: Array = _lb_entries[mi]
		if (mi as MeshInstance3D).mesh != e[1]:
			continue
		(mi as MeshInstance3D).mesh = e[0]
		var w: PackedFloat32Array = e[2]
		for i in mini(w.size(), (mi as MeshInstance3D).get_blend_shape_count()):
			(mi as MeshInstance3D).set_blend_shape_value(i, w[i])
	_lb_entries = {}


func _lod_bake_tick(delta: float) -> void:
	if _lb_task >= 0:
		if WorkerThreadPool.is_task_completed(_lb_task):
			WorkerThreadPool.wait_for_task_completion(_lb_task)
			_lb_task = -1
			_lod_bake_finish()
		return
	if not _lb_dirty or _lod_tier < 2 or _model == null or not LodBake.enabled:
		return
	_lb_wait -= delta
	if _lb_wait > 0.0 or _hair_waiting or wardrobe_waiting():
		return
	_lod_bake_start()


func _lod_bake_start() -> void:
	_lb_dirty = false
	var items: Array = []
	var instant := 0
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		if _lb_entries.has(mi):
			if mi.mesh == _lb_entries[mi][1]:
				continue
			_lb_entries.erase(mi)
		var m := mi.mesh as ArrayMesh
		if m == null or m.get_blend_shape_count() == 0:
			continue
		var w := PackedFloat32Array()
		w.resize(m.get_blend_shape_count())
		var ok := true
		for i in w.size():
			w[i] = mi.get_blend_shape_value(i)
			ok = ok and is_finite(w[i])
		if not ok:
			continue
		var hit := LodBake.baked_cached(m, w)
		if hit != null:
			if _lod_swap(mi, m, w, hit):
				instant += 1
			continue
		items.append({"mi": mi, "mesh": m, "w": w, "src": LodBake.source_cached(m), "raw": null})
	for it in items:
		if it["src"] == null:
			it["raw"] = LodBake.raw_of(it["mesh"])
	if items.is_empty():
		if instant > 0:
			lod_bakes += 1
		return
	_lb_job = {"items": items, "gen": _lb_gen}
	if LodBake.async:
		_lb_task = WorkerThreadPool.add_task(LodBake.run_job.bind(_lb_job), false, "lod_bake")
	else:
		LodBake.run_job(_lb_job)
		_lod_bake_finish()


## Výměna sítě, jen když instance pořád ukazuje stejnou síť se stejnými vahami.
func _lod_swap(mi: MeshInstance3D, m: Mesh, w: PackedFloat32Array, baked: ArrayMesh) -> bool:
	if baked == null or not is_instance_valid(mi) or mi.mesh != m or mi.get_blend_shape_count() != w.size():
		return false
	for i in w.size():
		if mi.get_blend_shape_value(i) != w[i]:
			return false
	mi.mesh = baked
	_lb_entries[mi] = [m, baked, w]
	return true


func _lod_bake_finish() -> void:
	var job := _lb_job
	_lb_job = {}
	if job.is_empty():
		return
	LodBake.note_job(job)
	for it in job["items"]:
		if bool(it.get("built", false)):
			LodBake.store_source(it["mesh"], it["src"])
		if it.get("baked") != null:
			LodBake.store_baked(it["mesh"], it["w"], it["baked"])
	# Zastaralá úloha (mezitím _lod_touch nebo odchod ze stupně 2): výsledky jen do cache.
	if int(job["gen"]) != _lb_gen or _lod_tier < 2 or _model == null:
		return
	for it in job["items"]:
		# uzel mohl mezitím zaniknout (výměna šatníku) – uvolněný objekt nesmí do typovaného parametru
		if is_instance_valid(it["mi"]):
			_lod_swap(it["mi"], it["mesh"], it["w"], it.get("baked"))
	lod_bakes += 1


func _exit_tree() -> void:
	# Úloha nesahá na scénu, ale výsledek se má zahodit dřív, než uzel zmizí.
	if _lb_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_lb_task)
		_lb_task = -1
		_lb_job = {}
		_lb_dirty = _lod_tier >= 2
