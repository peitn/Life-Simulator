extends RefCounted
## Staví uzly koupených položek z LotGrid (B1, 20. 11. 2026).
##
## Položka s tagem akce = SmartObject (AI i hráč ji hned používají, přidá se do world.smart_objects);
## dekorace / osvětlení / koberec = obyčejný Node3D (není v smart_objects, plánovač ji nevidí).
## Geometrie: model z Blenderu, když ho katalog uvádí a AssetLibrary je zapnutá; jinak primitiva podle
## `style` (každý styl je postavený tak, aby seděl na půdorys w × d × h a předek mířil na lokální +Z).
## Žádná logika pravidel – ta je výhradně v LotGrid.

const SmartObject := preload("res://scripts/world/smart_object.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const Catalog := preload("res://scripts/world/buy_catalog.gd")
const LotGrid := preload("res://scripts/world/lot_grid.gd")

static var _mats := {}


static func _mat(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var k := "%s|%s|%.2f|%.2f" % [key, c.to_html(false), rough, metal]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[k] = m
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, shadow := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Postaví uzel položky (ještě není ve stromu). `lot` dává pozici; uzel nese meta lot_uid a lot_item.
static func build_item(lot, uid: int, use_models: bool = true) -> Node3D:
	var rec: Dictionary = lot.items[uid]
	var id := String(rec["id"])
	var it := Catalog.get_item(id)
	var node := Node3D.new()
	var tag := String(it["tag"])
	if tag != "":
		node.set_script(SmartObject)
		node.object_tag = tag
		node.display_name = String(it["name"])
		node.capacity = int(it["cap"])
		var use: Array = []
		for u in it["use"]:
			use.append(Vector3(float(u[0]), 0.0, float(u[1])))
		node.use_offsets = use
		var pose: Array = []
		for p in it["pose"]:
			pose.append(Vector3(float(p[0]), 0.0, float(p[1])))
		node.pose_offsets = pose
		node.quality = float(it["quality"])
		node.lot_uid = uid
	node.name = "Lot_%d_%s" % [uid, id]
	node.set_meta("lot_uid", uid)
	node.set_meta("lot_item", id)
	place(lot, node, uid)
	var used_model := false
	var model_name := String(it["model"])
	if use_models and model_name != "" and AssetLibrary.enabled:
		var m := AssetLibrary.instantiate(model_name)
		if m != null:
			m.name = "Model"
			node.add_child(m)
			used_model = true
	if not used_model:
		_build_style(node, it)
	if bool(it.get("light", false)):
		var l := OmniLight3D.new()
		l.name = "LotLight"
		l.position = Vector3(0, float(it["h"]) - 0.15, 0)
		l.light_color = Color(1.0, 0.8, 0.58)
		l.omni_range = 4.5
		l.light_energy = 0.8
		l.shadow_enabled = true
		node.add_child(l)
		node.set_meta("lot_light", l)
	return node


## Nastaví pozici a otočení uzlu podle záznamu (i po přesunu).
static func place(lot, node: Node3D, uid: int) -> void:
	var rec: Dictionary = lot.items[uid]
	var c: Vector2 = lot.center_of(String(rec["id"]), int(rec["cx"]), int(rec["cz"]), int(rec["rot"]))
	node.position = Vector3(c.x, 0.0, c.y)
	node.rotation_degrees = Vector3(0.0, LotGrid.yaw_deg(int(rec["rot"])), 0.0)


static func _build_style(n: Node3D, it: Dictionary) -> void:
	var w: float = float(it["w"])
	var d: float = float(it["d"])
	var h: float = float(it["h"])
	var col := Color.html(String(it["color"]))
	var main_m := _mat("main", col, 0.85)
	var dark := _mat("dark", Color(0.07, 0.07, 0.08), 0.45)
	var steel := _mat("steel", Color(0.7, 0.72, 0.75), 0.3, 0.8)
	var wood := _mat("wood", Color(0.42, 0.27, 0.16), 0.6)
	var linen := _mat("linen", Color(0.93, 0.92, 0.88), 1.0)
	var white := _mat("white", Color(0.92, 0.92, 0.9), 0.3, 0.1)
	match String(it["style"]):
		"mattress":
			_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), _mat("stain", col, 1.0))
			# Skvrny a propadlý střed – levná věc vypadá levně.
			_box(n, Vector3(w * 0.35, 0.005, d * 0.25), Vector3(-w * 0.15, h + 0.002, d * 0.1), _mat("stain_dark", col.darkened(0.35), 1.0), false)
			_box(n, Vector3(w * 0.55, 0.12, 0.3), Vector3(0, h + 0.05, -d * 0.5 + 0.22), _mat("pillow_cheap", Color(0.78, 0.76, 0.7), 1.0))
		"bed":
			_box(n, Vector3(w, 0.35, d), Vector3(0, 0.18, 0), wood)
			_box(n, Vector3(w - 0.08, 0.2, d - 0.12), Vector3(0, 0.45, 0.02), linen)
			_box(n, Vector3(w, h, 0.08), Vector3(0, h * 0.5 + 0.05, -d * 0.5 + 0.04), wood)
			var pillows := 2 if w > 1.4 else 1
			for i in pillows:
				var px := 0.0 if pillows == 1 else (-0.4 if i == 0 else 0.4)
				_box(n, Vector3(0.6, 0.12, 0.35), Vector3(px, 0.61, -d * 0.5 + 0.35), linen)
			_box(n, Vector3(w - 0.06, 0.06, d * 0.55), Vector3(0, 0.58, d * 0.18), main_m)
		"sofa", "armchair", "bench":
			var seat_h := 0.42 if String(it["style"]) != "bench" else 0.45
			var back_m := main_m if String(it["style"]) != "bench" else wood
			_box(n, Vector3(w, seat_h, d * 0.85), Vector3(0, seat_h * 0.5, d * 0.05), back_m)
			_box(n, Vector3(w, h - seat_h, 0.2), Vector3(0, seat_h + (h - seat_h) * 0.5, -d * 0.5 + 0.1), back_m)
			if String(it["style"]) != "bench":
				for sx in [-1.0, 1.0]:
					_box(n, Vector3(0.18, 0.28, d * 0.85), Vector3(sx * (w * 0.5 - 0.09), seat_h + 0.14, d * 0.05), back_m)
			else:
				for sx in [-1.0, 1.0]:
					_box(n, Vector3(0.06, seat_h, 0.06), Vector3(sx * (w * 0.5 - 0.1), seat_h * 0.5, d * 0.35), dark)
		"fridge":
			_box(n, Vector3(w * 0.96, h, d * 0.96), Vector3(0, h * 0.5, 0), _mat("fridge", col, 0.3, 0.1))
			_box(n, Vector3(w * 0.96, 0.01, 0.01), Vector3(0, h * 0.62, d * 0.48 + 0.006), dark, false)
			_box(n, Vector3(0.04, 0.5, 0.05), Vector3(w * 0.35, h * 0.75, d * 0.48 + 0.03), steel)
			_box(n, Vector3(0.04, 0.35, 0.05), Vector3(w * 0.35, h * 0.4, d * 0.48 + 0.03), steel)
		"hotplate":
			_box(n, Vector3(w, 0.78, d), Vector3(0, 0.39, 0), _mat("cheap_table", Color(0.55, 0.5, 0.42), 0.8))
			_box(n, Vector3(w * 0.7, 0.07, d * 0.7), Vector3(0, 0.815, 0), dark)
			for x in [-0.14, 0.14]:
				_cyl(n, 0.09, 0.09, 0.012, Vector3(x, 0.855, 0.0), _mat("plate", Color(0.2, 0.2, 0.2), 0.5, 0.4))
		"stove":
			_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), white)
			_box(n, Vector3(w, 0.03, d), Vector3(0, h + 0.015, 0), dark)
			_box(n, Vector3(w * 0.7, h * 0.45, 0.01), Vector3(0, h * 0.35, d * 0.5 + 0.006), _mat("oven_glass", Color(0.05, 0.05, 0.06), 0.1), false)
			for x in [-0.22, 0.22]:
				for z in [-0.17, 0.17]:
					_cyl(n, 0.1, 0.1, 0.015, Vector3(x, h + 0.035, z), steel)
		"shower":
			_box(n, Vector3(w, 0.08, d), Vector3(0, 0.04, 0), white)
			_cyl(n, 0.02, 0.02, h, Vector3(-w * 0.42, h * 0.5, -d * 0.42), steel)
			_cyl(n, 0.1, 0.1, 0.03, Vector3(-w * 0.3, h - 0.05, -d * 0.3), steel)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.8, 0.9, 1.0, 0.25)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			_box(n, Vector3(0.02, h - 0.1, d), Vector3(w * 0.5 - 0.01, h * 0.5, 0), glass, false)
		"crt":
			_box(n, Vector3(w, 0.5, d), Vector3(0, 0.25, 0), wood)
			_box(n, Vector3(w * 0.85, 0.5, d * 0.9), Vector3(0, 0.75, -0.02), _mat("crt", col, 0.5))
			_box(n, Vector3(w * 0.6, 0.38, 0.01), Vector3(0, 0.76, d * 0.43 + 0.006), _screen(Color(0.25, 0.45, 0.35)), false)
		"tv":
			_box(n, Vector3(w, 0.45, d), Vector3(0, 0.225, 0), wood)
			_box(n, Vector3(w * 0.95, 0.8, 0.05), Vector3(0, 0.45 + 0.45, -d * 0.2), dark)
			_box(n, Vector3(w * 0.9, 0.72, 0.01), Vector3(0, 0.9, -d * 0.2 + 0.03), _screen(Color(0.35, 0.55, 0.9)), false)
		"treadmill":
			_box(n, Vector3(w, 0.15, d), Vector3(0, 0.075, 0), dark)
			_box(n, Vector3(w * 0.85, 0.02, d * 0.88), Vector3(0, 0.16, 0.0), _mat("belt", Color(0.15, 0.15, 0.15), 0.9), false)
			for x in [-1.0, 1.0]:
				_box(n, Vector3(0.05, h - 0.2, 0.05), Vector3(x * (w * 0.5 - 0.03), (h - 0.2) * 0.5 + 0.1, -d * 0.45), steel)
			_box(n, Vector3(w, 0.22, 0.1), Vector3(0, h - 0.1, -d * 0.45), dark)
		"shelf":
			_box(n, Vector3(w, h, d * 0.8), Vector3(0, h * 0.5, -d * 0.1), _mat("shelf", col, 0.6))
			var cols := [Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.85, 0.7, 0.3), Color(0.25, 0.55, 0.3), Color(0.5, 0.3, 0.6)]
			var per_row := int(floor((w - 0.1) / 0.2))
			for row in 4:
				for i in per_row:
					var c: Color = cols[(row * 3 + i) % cols.size()]
					_box(n, Vector3(0.17, 0.3, 0.05), Vector3(-w * 0.5 + 0.15 + i * 0.2, 0.32 + row * h * 0.22, d * 0.31),
						_mat("book", c, 0.8), false)
		"plant":
			_cyl(n, 0.17, 0.13, 0.32, Vector3(0, 0.16, 0), _mat("pot", Color(0.75, 0.45, 0.32), 0.9))
			var leaf := _mat("leaf", col, 0.85)
			_sphere(n, 0.3, Vector3(0, 0.75, 0), leaf)
			_sphere(n, 0.22, Vector3(0.12, 1.0, 0.05), leaf)
			_sphere(n, 0.2, Vector3(-0.12, 0.95, -0.06), leaf)
		"rug":
			_box(n, Vector3(w, h, d), Vector3(0, 0.11, 0), _mat("rug", col, 1.0), false)
			_box(n, Vector3(w * 0.8, h * 0.6, d * 0.75), Vector3(0, 0.113, 0), _mat("rug_inner", col.lightened(0.18), 1.0), false)
		"trash":
			var bag := _mat("bag", col, 0.35)
			_sphere(n, 0.24, Vector3(-0.15, 0.24, 0.0), bag)
			_sphere(n, 0.21, Vector3(0.18, 0.21, 0.05), bag)
			_sphere(n, 0.17, Vector3(0.02, 0.42, -0.04), bag)
		"lamp":
			_cyl(n, 0.16, 0.16, 0.03, Vector3(0, 0.015, 0), dark)
			_cyl(n, 0.015, 0.015, h - 0.3, Vector3(0, (h - 0.3) * 0.5, 0), steel)
			var shade := StandardMaterial3D.new()
			shade.albedo_color = col
			shade.emission_enabled = true
			shade.emission = Color(1.0, 0.82, 0.55)
			shade.emission_energy_multiplier = 0.5
			_cyl(n, 0.13, 0.2, 0.3, Vector3(0, h - 0.15, 0), shade)
		"grill":
			for x in [-1.0, 1.0]:
				_box(n, Vector3(0.04, 0.75, 0.04), Vector3(x * 0.25, 0.375, 0), steel)
			_sphere(n, 0.3, Vector3(0, 0.85, 0), _mat("grill", col, 0.4, 0.5))
		"planter":
			_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), _mat("planter", col, 0.9))
			_box(n, Vector3(w - 0.1, 0.04, d - 0.1), Vector3(0, h + 0.005, 0), _mat("soil", Color(0.25, 0.17, 0.1), 1.0), false)
			var green := _mat("herbs", Color(0.25, 0.5, 0.2), 0.9)
			for i in 5:
				_sphere(n, 0.12, Vector3(-w * 0.35 + i * w * 0.175, h + 0.1, 0.0), green)
		_:
			_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), main_m)


static func _screen(c: Color) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = Color(0.05, 0.07, 0.1)
	s.emission_enabled = true
	s.emission = c
	s.emission_energy_multiplier = 0.45
	return s
