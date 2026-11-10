extends RefCounted
## Procedurální stavba startovní parcely: zahrada, dům (otevřený půdorys), nábytek.
## Gauč, postele a lednice jsou modely z Blenderu (res://assets/models), ostatní zatím primitiva.
## Dočasné – v dalších krocích ho nahradí režim stavění/nákupu s ukládáním.

const SmartObject := preload("res://scripts/world/smart_object.gd")
const QuiltVisual := preload("res://scripts/world/quilt_visual.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const AutoDoor := preload("res://scripts/world/auto_door.gd")
const HingedDoorScene := preload("res://scenes/city/door_hinged_1m.tscn")
## Explicitly opt-in at main-scene construction so existing 3-person test fixtures
## retain their deterministic 9 smart objects and navigation acceptance scenarios.
var include_eight_suite := false

var root: Node3D
var objects: Array = []
var lamps: Array[Light3D] = []
## Kolik objektů dostalo model z Blenderu (zbytek jsou primitiva) – pro testy a log.
var models_used: Array = []
var _mats := {}


func _init(p_root: Node3D) -> void:
	root = p_root


func mat(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, shadow := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Vloží do `parent` model z Blenderu (res://assets/models/<jméno>.glb). Vrací false, když chybí –
## volající pak postaví primitivní náhradu.
func model(parent: Node3D, model_name: String) -> bool:
	var m := AssetLibrary.instantiate(model_name)
	if m == null:
		return false
	m.name = "Model"
	parent.add_child(m)
	models_used.append(model_name)
	return true


func smart(tag: String, label: String, pos: Vector3, rot_deg: float, capacity := 1) -> Node3D:
	var o := Node3D.new()
	o.set_script(SmartObject)
	o.object_tag = tag
	o.display_name = label
	o.capacity = capacity
	o.name = tag.capitalize().replace(" ", "")
	o.position = pos
	o.rotation_degrees.y = rot_deg
	root.add_child(o)
	objects.append(o)
	return o


func build() -> void:
	_build_ground()
	_build_house()
	_build_furniture()
	_build_garden()


func _build_ground() -> void:
	var grass := mat("grass", Color(0.3, 0.48, 0.2), 1.0)
	box(root, Vector3(80, 0.2, 80), Vector3(0, -0.1, 0), grass, false)
	var path := mat("path", Color(0.62, 0.6, 0.55), 0.95)
	box(root, Vector3(1.6, 0.04, 9.0), Vector3(0, 0.02, 9.0), path, false)
	var road := mat("road", Color(0.16, 0.16, 0.17), 0.9)
	box(root, Vector3(80, 0.05, 6.0), Vector3(0, 0.02, 16.5), road, false)
	var line := mat("roadline", Color(0.9, 0.88, 0.8), 0.6)
	for i in range(-9, 10):
		box(root, Vector3(2.0, 0.06, 0.15), Vector3(i * 4.0, 0.03, 16.5), line, false)


func _build_house() -> void:
	var floor_m := mat("floor", Color(0.55, 0.38, 0.24), 0.55)
	var tile := mat("tile", Color(0.82, 0.84, 0.86), 0.25)
	var wall := mat("wall", Color(0.9, 0.87, 0.8), 0.9)
	var trim := mat("trim", Color(0.95, 0.95, 0.95), 0.6)
	box(root, Vector3(12.4, 0.2, 9.4), Vector3(0, 0.0, 0), floor_m)
	box(root, Vector3(2.5, 0.205, 3.0), Vector3(-4.75, 0.003, 3.0), tile)  # koupelna
	# Zadní a levá stěna plné, přední a pravá snížené („cutaway“ pohled dovnitř domu).
	box(root, Vector3(12.4, 2.8, 0.2), Vector3(0, 1.5, -4.6), wall)
	box(root, Vector3(0.2, 2.8, 9.4), Vector3(-6.1, 1.5, 0), wall)
	box(root, Vector3(0.2, 0.6, 9.4), Vector3(6.1, 0.4, 0), wall)
	box(root, Vector3(5.2, 0.6, 0.2), Vector3(-3.5, 0.4, 4.6), wall)
	box(root, Vector3(5.2, 0.6, 0.2), Vector3(3.5, 0.4, 4.6), wall)
	# Příčka koupelny se dveřním otvorem.
	box(root, Vector3(0.15, 2.6, 1.6), Vector3(-3.5, 1.4, 3.8), wall)
	box(root, Vector3(2.5, 2.6, 0.15), Vector3(-4.75, 1.4, 1.5), wall)
	# Physical doors reused from the M1 city module instead of empty holes.
	_add_hinged_door("FrontDoor", Vector3(-1.0, 0, 4.6))
	_add_hinged_door("BathroomDoor", Vector3(-3.5, 0, 1.35), PI * 0.5)
	if include_eight_suite:
		_build_eight_suite_rooms()
	# Okna v zadní stěně (světlá skla s emisí přes den nejsou potřeba – jen rámy).
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.2
	for x in [-1.2, 4.0]:
		box(root, Vector3(1.8, 1.2, 0.05), Vector3(x, 1.6, -4.48), glass, false)
		box(root, Vector3(1.9, 0.08, 0.1), Vector3(x, 2.22, -4.46), trim)
		box(root, Vector3(1.9, 0.08, 0.1), Vector3(x, 0.98, -4.46), trim)
	# Stropní lampy (OmniLight3D, teplé světlo 2700 K).
	for p in [Vector3(-4.0, 2.5, -2.0), Vector3(2.5, 2.5, -1.5), Vector3(4.0, 2.5, 2.8), Vector3(-4.7, 2.4, 3.0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.78, 0.55)
		l.omni_range = 6.5
		l.shadow_enabled = true
		root.add_child(l)
		lamps.append(l)
		var shade := StandardMaterial3D.new()
		shade.albedo_color = Color(1.0, 0.9, 0.75)
		shade.emission_enabled = true
		shade.emission = Color(1.0, 0.8, 0.55)
		shade.emission_energy_multiplier = 0.6
		sphere(root, 0.18, p + Vector3(0, 0.15, 0), shade)


## The scene comes with a real articulated leaf and collision, including
## sweep checks. AutoDoor requests open/close as an actor approaches.
func _add_hinged_door(label: String, position: Vector3, yaw: float = 0.0) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.name = label
	wrapper.position = position
	wrapper.rotation.y = yaw
	wrapper.set_script(AutoDoor)
	var model := HingedDoorScene.instantiate()
	model.name = "HingedDoor"
	wrapper.add_child(model)
	# Add to live scene only after the child is installed: AutoDoor._ready()
	# immediately validates its HingedDoor child.
	root.add_child(wrapper)
	return wrapper


## Four separate bedrooms on an east annex and an open shared corridor.
## Bedrooms 1–3 contain one bed; bedroom 4 contains two beds.
func _build_eight_suite_rooms() -> void:
	var floor_color := mat("annex_floor", Color(0.58, 0.42, 0.30), 0.65)
	var wall_color := mat("annex_wall", Color(0.87, 0.83, 0.77), 0.90)
	var trim_color := mat("annex_trim", Color(0.75, 0.71, 0.66), 0.6)
	# Existing house right side is cut away, linking directly to this corridor.
	box(root, Vector3(13.3, 0.20, 6.7), Vector3(12.7, -0.02, 1.36), floor_color)
	box(root, Vector3(13.1, 2.6, 0.16), Vector3(12.7, 1.4, 4.63), wall_color)
	box(root, Vector3(13.1, 0.65, 0.16), Vector3(12.7, 0.38, -1.95), wall_color)
	for n in 4:
		var start_x := 6.3 + float(n) * 3.2
		var cx := start_x + 1.6
		# The M1 doorway module includes its own two rigid jambs and a lintel.
		_add_hinged_door("BedroomDoor_%d" % (n + 1), Vector3(cx - 1.0, 0.0, 0.95))
		for x_side in [start_x + 0.30, start_x + 2.90]:
			box(root, Vector3(0.6, 0.7, 0.16), Vector3(x_side, 0.42, 0.95), wall_color)
		var room_label := Label3D.new()
		room_label.name = "BedroomLabel_%d" % (n + 1)
		room_label.text = "Pokoj %d" % (n + 1)
		room_label.font_size = 34
		room_label.pixel_size = 0.004
		room_label.position = Vector3(cx, 2.1, 0.75)
		root.add_child(room_label)
	for i in 5:
		box(root, Vector3(0.12, 0.7, 3.65), Vector3(6.3 + float(i) * 3.2, 0.40, 2.8), wall_color)
	# Warm lighting makes the new rooms usable at night.
	for n in 4:
		var light := OmniLight3D.new()
		light.name = "BedroomLight_%d" % (n + 1)
		light.position = Vector3(7.9 + float(n) * 3.2, 2.35, 2.8)
		light.omni_range = 4.5
		light.light_color = Color(1.0, 0.83, 0.66)
		light.light_energy = 0.6
		root.add_child(light)
		lamps.append(light)


func _build_extra_beds(wood: Material, linen: Material) -> void:
	# Existing double bed (2) + single bed (1) + five new singles = 8 places.
	var sites := [Vector3(7.90, 0, 3.03), Vector3(11.10, 0, 3.03),
		Vector3(14.30, 0, 3.03), Vector3(17.15, 0, 3.03),
		Vector3(18.35, 0, 3.03)]
	for i in sites.size():
		var bed := smart("bed", "Postel %d" % (i + 4), sites[i], 180.0, 1)
		# Headboard faces the far bedroom wall, walking approach faces the door.
		bed.use_offsets = [Vector3(0, 0, 1.25)]
		bed.pose_offsets = [Vector3(0, 0, 0)]
		if not model(bed, "bed_single"):
			box(bed, Vector3(1.0, 0.35, 2.1), Vector3(0, 0.18, 0), wood)
			box(bed, Vector3(0.92, 0.20, 1.95), Vector3(0, 0.45, 0), linen)
			box(bed, Vector3(1.0, 0.70, 0.08), Vector3(0, 0.50, 1.05), wood)
			box(bed, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.61, 0.75), linen)
		QuiltVisual.add_to_bed(bed, 0.88, 1.48,
			mat("annex_duvet_%d" % i, Color(0.24 + 0.11 * float(i % 3), 0.38, 0.53), 0.95))


func _build_furniture() -> void:
	var white := mat("white", Color(0.92, 0.92, 0.9), 0.3, 0.1)
	var steel := mat("steel", Color(0.7, 0.72, 0.75), 0.3, 0.8)
	var dark := mat("dark", Color(0.08, 0.08, 0.09), 0.4)
	var wood := mat("wood", Color(0.42, 0.27, 0.16), 0.6)
	var fabric := mat("fabric", Color(0.25, 0.4, 0.55), 1.0)
	var linen := mat("linen", Color(0.95, 0.94, 0.9), 1.0)
	var counter := mat("counter", Color(0.3, 0.3, 0.32), 0.35)

	# Lednice
	var fridge := smart("fridge", "Lednice", Vector3(-5.4, 0, -3.95), 0.0)
	fridge.use_offsets = [Vector3(0, 0, 1.0)]
	if not model(fridge, "fridge"):
		box(fridge, Vector3(0.85, 2.0, 0.75), Vector3(0, 1.0, 0), white)
		box(fridge, Vector3(0.04, 0.6, 0.05), Vector3(0.3, 1.35, 0.4), steel)
	# Sporák + linka
	var stove := smart("stove", "Sporák", Vector3(-4.3, 0, -4.0), 0.0)
	stove.use_offsets = [Vector3(0, 0, 0.95)]
	box(stove, Vector3(0.9, 0.9, 0.7), Vector3(0, 0.45, 0), white)
	box(stove, Vector3(0.9, 0.03, 0.7), Vector3(0, 0.91, 0), dark)
	for x in [-0.2, 0.2]:
		cyl(stove, 0.12, 0.02, Vector3(x, 0.93, 0.0), steel)
	box(root, Vector3(2.0, 0.9, 0.7), Vector3(-2.75, 0.45, -4.0), wood)
	box(root, Vector3(2.0, 0.05, 0.72), Vector3(-2.75, 0.92, -4.0), counter)
	# Visible, temporary household mess: never show a "dirty dishes" accusation
	# while the counter remains perfectly empty. The actual cook-completion
	# event in HouseholdDynamics controls this marker's visibility.
	var dirty := Node3D.new()
	dirty.name = "DirtyDishes"
	dirty.position = Vector3(-2.75, 0.96, -4.0)
	dirty.visible = false
	root.add_child(dirty)
	var porcelain := mat("dirty_dish_porcelain", Color(0.86, 0.84, 0.78), 0.32)
	var leftovers := mat("dirty_dish_leftovers", Color(0.28, 0.17, 0.09), 0.92)
	for i in 3:
		var px := -0.48 + float(i) * 0.43
		var pz := -0.09 if i % 2 == 0 else 0.12
		cyl(dirty, 0.14, 0.018, Vector3(px, 0.018, pz), porcelain)
		cyl(dirty, 0.095, 0.005, Vector3(px, 0.031, pz), leftovers)
	# A mug and two pieces of cutlery next to the stained plates.
	cyl(dirty, 0.04, 0.11, Vector3(0.52, 0.072, 0.12), porcelain)
	box(dirty, Vector3(0.016, 0.009, 0.22), Vector3(-0.33, 0.014, 0.24), steel)
	box(dirty, Vector3(0.018, 0.009, 0.19), Vector3(0.09, 0.014, -0.26), steel)
	# Jídelní stůl a židle (dekorace)
	box(root, Vector3(1.6, 0.05, 0.9), Vector3(-3.0, 0.76, -1.4), wood)
	for p in [Vector3(-3.7, 0.37, -1.0), Vector3(-2.3, 0.37, -1.0), Vector3(-3.7, 0.37, -1.8), Vector3(-2.3, 0.37, -1.8)]:
		box(root, Vector3(0.06, 0.74, 0.06), p, wood)
	for z in [-0.6, -2.2]:
		# Four legs actually support each chair; backrest remains behind its seat.
		box(root, Vector3(0.48, 0.07, 0.48), Vector3(-3.0, 0.46, z), wood)
		var back_z: float = z + (0.21 if z > -1.4 else -0.21)
		box(root, Vector3(0.48, 0.52, 0.055), Vector3(-3.0, 0.72, back_z), wood)
		for dx in [-0.19, 0.19]:
			for dz in [-0.19, 0.19]:
				box(root, Vector3(0.055, 0.435, 0.055), Vector3(-3.0 + dx, 0.215, z + dz), wood)
	# Televize (sedí se na gauči naproti)
	var tv := smart("tv", "Televize", Vector3(2.5, 0, -4.15), 0.0, 2)
	# Walk to the *front* of the sofa, then sit on its cushion. The
	# previous TV points were behind the sofa (z=-0.55), causing characters
	# to teleport through its back and lose their legs in the mesh.
	# Index order mirrors the 180-degree-rotated sofa: slot 0 is +X.
	tv.use_offsets = [Vector3(0.5, 0, 2.35), Vector3(-0.5, 0, 2.35)]
	tv.pose_offsets = [Vector3(0.5, 0, 2.98), Vector3(-0.5, 0, 2.98)]
	box(tv, Vector3(1.8, 0.5, 0.45), Vector3(0, 0.25, 0), wood)
	box(tv, Vector3(1.5, 0.85, 0.06), Vector3(0, 1.0, -0.05), dark)
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.05, 0.08, 0.12)
	screen.emission_enabled = true
	screen.emission = Color(0.35, 0.55, 0.9)
	screen.emission_energy_multiplier = 0.5
	box(tv, Vector3(1.4, 0.76, 0.01), Vector3(0, 1.0, -0.015), screen, false)
	# Gauč (otočený k televizi)
	var sofa := smart("sofa", "Gauč", Vector3(2.5, 0, -0.85), 180.0, 2)
	sofa.use_offsets = [Vector3(-0.5, 0, 0.95), Vector3(0.5, 0, 0.95)]
	# Sit near the front of the cushion so shins/feet remain outside its solid volume.
	sofa.pose_offsets = [Vector3(-0.5, 0, 0.32), Vector3(0.5, 0, 0.32)]
	if not model(sofa, "sofa"):
		box(sofa, Vector3(2.2, 0.42, 0.9), Vector3(0, 0.21, 0), fabric)
		box(sofa, Vector3(2.2, 0.55, 0.22), Vector3(0, 0.62, -0.34), fabric)
		box(sofa, Vector3(0.2, 0.3, 0.9), Vector3(-1.0, 0.55, 0), fabric)
		box(sofa, Vector3(0.2, 0.3, 0.9), Vector3(1.0, 0.55, 0), fabric)
	# Koberec
	box(root, Vector3(3.0, 0.02, 2.2), Vector3(2.5, 0.11, -2.4), mat("rug", Color(0.6, 0.25, 0.2), 1.0), false)
	# Knihovna (u pravé stěny, čelem doleva)
	var shelf := smart("bookshelf", "Knihovna", Vector3(5.75, 0, -2.0), -90.0)
	shelf.use_offsets = [Vector3(0, 0, 0.9)]
	box(shelf, Vector3(1.4, 2.0, 0.35), Vector3(0, 1.0, 0), wood)
	var book_cols := [Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.85, 0.7, 0.3), Color(0.25, 0.55, 0.3), Color(0.5, 0.3, 0.6)]
	for row in 4:
		for i in 6:
			var c: Color = book_cols[(row * 3 + i) % book_cols.size()]
			box(shelf, Vector3(0.18, 0.32, 0.05), Vector3(-0.5 + i * 0.2, 0.35 + row * 0.45, 0.17), mat("book%d" % ((row * 3 + i) % 5), c, 0.8), false)
	# Postel (dvojlůžko, hlavou ke zdi vpravo)
	var bed := smart("bed", "Postel", Vector3(4.6, 0, 2.6), -90.0, 2)
	bed.use_offsets = [Vector3(-0.55, 0, 1.6), Vector3(0.55, 0, 1.6)]
	bed.pose_offsets = [Vector3(-0.4, 0, 0.0), Vector3(0.4, 0, 0.0)]
	if not model(bed, "bed_double"):
		box(bed, Vector3(1.7, 0.35, 2.15), Vector3(0, 0.18, 0), wood)
		box(bed, Vector3(1.6, 0.22, 2.0), Vector3(0, 0.46, 0), linen)
		box(bed, Vector3(1.7, 0.9, 0.08), Vector3(0, 0.55, -1.08), wood)
		for x in [-0.4, 0.4]:
			box(bed, Vector3(0.6, 0.12, 0.35), Vector3(x, 0.63, -0.75), linen)
		box(bed, Vector3(1.62, 0.06, 1.2), Vector3(0, 0.6, 0.35), mat("blanket", Color(0.55, 0.35, 0.55), 1.0))
	# Cover the lower body without obscuring the pillow / face. A simple separate
	# quilt also works when the imported bed model already has a mattress.
	QuiltVisual.add_to_bed(bed, 1.52, 1.48, mat("duvet_double", Color(0.49, 0.37, 0.55), 0.98))
	# Jednolůžko (pro třetího člena domácnosti)
	var bed2 = smart("bed", "Jednolůžko", Vector3(-1.9, 0, 3.35), 180.0, 1)
	bed2.use_offsets = [Vector3(-0.75, 0, 0.3)]
	bed2.pose_offsets = [Vector3(0, 0, 0.0)]
	if not model(bed2, "bed_single"):
		box(bed2, Vector3(1.0, 0.35, 2.1), Vector3(0, 0.18, 0), wood)
		box(bed2, Vector3(0.92, 0.2, 1.95), Vector3(0, 0.45, 0), linen)
		box(bed2, Vector3(1.0, 0.8, 0.08), Vector3(0, 0.5, -1.06), wood)
		box(bed2, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.61, -0.75), linen)
		box(bed2, Vector3(0.94, 0.06, 1.2), Vector3(0, 0.58, 0.35), mat("blanket2", Color(0.3, 0.55, 0.45), 1.0))
	QuiltVisual.add_to_bed(bed2, 0.88, 1.48, mat("duvet_single", Color(0.35, 0.54, 0.47), 0.98))
	if include_eight_suite:
		_build_extra_beds(wood, linen)
	# Sprchový kout
	var shower := smart("shower", "Sprcha", Vector3(-5.3, 0, 3.8), 0.0)
	shower.use_offsets = [Vector3(0, 0, 0.0)]
	box(shower, Vector3(1.2, 0.08, 1.2), Vector3(0, 0.14, 0), white)
	cyl(shower, 0.02, 2.1, Vector3(-0.5, 1.05, -0.5), steel)
	cyl(shower, 0.1, 0.03, Vector3(-0.35, 2.05, -0.35), steel)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	box(shower, Vector3(0.03, 2.0, 1.2), Vector3(0.6, 1.1, 0), glass, false)
	shower.use_offsets = [Vector3(0, 0, 0.1)]
	# Běžecký pás
	var tm := smart("treadmill", "Běžecký pás", Vector3(0.6, 0, 3.4), 0.0)
	tm.use_offsets = [Vector3(0, 0, 0.0)]
	box(tm, Vector3(0.8, 0.15, 1.8), Vector3(0, 0.15, 0), dark)
	box(tm, Vector3(0.7, 0.02, 1.6), Vector3(0, 0.235, 0), mat("belt", Color(0.15, 0.15, 0.15), 0.9), false)
	for x in [-0.38, 0.38]:
		box(tm, Vector3(0.05, 1.1, 0.05), Vector3(x, 0.7, -0.8), steel)
	box(tm, Vector3(0.8, 0.25, 0.1), Vector3(0, 1.25, -0.8), dark)


func _build_garden() -> void:
	var bark := mat("bark", Color(0.32, 0.22, 0.14), 1.0)
	var leaves := [mat("leaf0", Color(0.2, 0.42, 0.16), 0.9), mat("leaf1", Color(0.28, 0.5, 0.18), 0.9), mat("leaf2", Color(0.35, 0.45, 0.15), 0.9)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var spots := [Vector3(-10, 0, -8), Vector3(-12, 0, 3), Vector3(10, 0, -9), Vector3(12, 0, 4), Vector3(-9, 0, 10),
		Vector3(9, 0, 11), Vector3(0, 0, -11), Vector3(-15, 0, -3), Vector3(23, 0, -7)]
	for p in spots:
		var h := rng.randf_range(2.2, 3.6)
		cyl(root, 0.16, h, p + Vector3(0, h / 2.0, 0), bark)
		for i in 3:
			var off := Vector3(rng.randf_range(-0.6, 0.6), h + rng.randf_range(-0.2, 0.9), rng.randf_range(-0.6, 0.6))
			sphere(root, rng.randf_range(0.9, 1.5), p + off, leaves[rng.randi_range(0, 2)])
	# Plot kolem parcely
	var fence := mat("fence", Color(0.9, 0.9, 0.88), 0.7)
	for i in range(-12, 13):
		if absi(i) <= 1:
			continue
		box(root, Vector3(0.08, 0.9, 0.08), Vector3(i * 1.0, 0.45, 13.0), fence)
	box(root, Vector3(24.0, 0.08, 0.04), Vector3(0, 0.75, 13.0), fence)
	# Záhon
	var soil := mat("soil", Color(0.25, 0.17, 0.1), 1.0)
	box(root, Vector3(4.0, 0.15, 1.0), Vector3(-4.0, 0.07, 7.0), soil)
	var flower_cols := [Color(0.9, 0.2, 0.3), Color(0.95, 0.8, 0.2), Color(0.7, 0.4, 0.9)]
	for i in 10:
		var c: Color = flower_cols[i % 3]
		sphere(root, 0.12, Vector3(-5.7 + i * 0.38, 0.3, 7.0 + rng.randf_range(-0.3, 0.3)), mat("flower%d" % (i % 3), c, 0.6))