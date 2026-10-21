extends RefCounted
## Procedurální stavba startovní parcely: zahrada, dům (otevřený půdorys), nábytek.
## Gauč, postele a lednice jsou modely z Blenderu (res://assets/models), ostatní zatím primitiva.
## Dočasné – v dalších krocích ho nahradí režim stavění/nákupu s ukládáním.

const SmartObject := preload("res://scripts/world/smart_object.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")

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
	# Jídelní stůl a židle (dekorace)
	box(root, Vector3(1.6, 0.05, 0.9), Vector3(-3.0, 0.76, -1.4), wood)
	for p in [Vector3(-3.7, 0.37, -1.0), Vector3(-2.3, 0.37, -1.0), Vector3(-3.7, 0.37, -1.8), Vector3(-2.3, 0.37, -1.8)]:
		box(root, Vector3(0.06, 0.74, 0.06), p, wood)
	for z in [-0.6, -2.2]:
		box(root, Vector3(0.45, 0.06, 0.45), Vector3(-3.0, 0.46, z), wood)
		box(root, Vector3(0.45, 0.5, 0.05), Vector3(-3.0, 0.72, z + (0.2 if z > -1.4 else -0.2)), wood)
	# Televize (sedí se na gauči naproti)
	var tv := smart("tv", "Televize", Vector3(2.5, 0, -4.15), 0.0, 2)
	tv.use_offsets = [Vector3(-0.5, 0, 3.6), Vector3(0.5, 0, 3.6)]
	tv.pose_offsets = [Vector3(-0.5, 0, 3.25), Vector3(0.5, 0, 3.25)]
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
	sofa.pose_offsets = [Vector3(-0.5, 0, 0.1), Vector3(0.5, 0, 0.1)]
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
		Vector3(9, 0, 11), Vector3(0, 0, -11), Vector3(-15, 0, -3), Vector3(16, 0, -2)]
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
