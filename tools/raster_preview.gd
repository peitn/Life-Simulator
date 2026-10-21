extends RefCounted
## RasterPreview – softwarový rasterizér pro VIZUÁLNÍ kontrolu modelu postavy bez GPU (headless Godot
## nerenderuje a Blender Space bývá nedostupný). Bere SKUTEČNÝ exportovaný character.glb, aplikuje váhy
## blend shapes z AppearanceResolveru (stejná cesta jako SimVisual), počítá deformované pozice na CPU
## (režim NORMALIZED: p = base + Σ w·(target − base)), normály po deformaci a kreslí z-bufferem
## s Gouraudovým stínováním (klíčové + vyplňovací + okrajové světlo). Ne PBR – slouží ke kontrole tvaru,
## siluety, průniků a švů (víčka, rty, přechod hlava–krk, vlasy při extrémech).
##
## Použití (nástroj, ne hra):
##   var img := RasterPreview.sheet([snap_a, snap_b], [Vector2(0, 0), Vector2(35, 0)], 192)
##   img.save_png("user://preview.png")

const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const AppearanceResolver := preload("res://scripts/character/appearance_resolver.gd")

const GROUPS_HEAD := ["head", "eyes"]
const LIGHT_KEY := Vector3(-0.45, 0.55, 0.7)
const LIGHT_FILL := Vector3(0.6, 0.1, 0.5)
const BG := Color(0.13, 0.13, 0.15)


## Deformované trojúhelníky modelu pro snapshot: Array [ {p: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, col: Color} ].
static func deformed_parts(snap: Dictionary, hair_group: String = "", with_body := false) -> Array:
	var lp: Dictionary = AppearanceResolver.resolve(snap)
	var model: Node3D = AssetLibrary.instantiate("character")
	if model == null:
		return []
	var groups: Array = GROUPS_HEAD.duplicate()
	if hair_group == "":
		hair_group = String(lp.get("hair_variant", "hair_short"))
	if hair_group != "":
		groups.append(hair_group)
	if with_body:
		groups.append("body")
	var out := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var grp := String(mi.name).get_slice("__", 0)
		if not groups.has(grp):
			continue
		var me := mi.mesh as ArrayMesh
		if me == null:
			continue
		# Hlava: obličej + klíče těla v pásu švu krku (stejně jako SimVisual.apply_face_shape).
		var w: Dictionary = lp["body"] if grp == "body" else (lp["face"] as Dictionary).merged(lp["body"])
		var arr := me.surface_get_arrays(0)
		var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var p := base.duplicate()
		var bsa := me.surface_get_blend_shape_arrays(0)
		# Normály ze sítě (stejné jako ve hře, vč. normál cílů blend shapes) – ne přepočtené z pozic.
		var bn = arr[Mesh.ARRAY_NORMAL]
		var n := PackedVector3Array()
		var has_n: bool = bn != null and (bn as PackedVector3Array).size() == base.size()
		if has_n:
			n = (bn as PackedVector3Array).duplicate()
		for i in me.get_blend_shape_count():
			var wt := float(w.get(String(me.get_blend_shape_name(i)), 0.0))
			if absf(wt) < 1e-6:
				continue
			var tgt: PackedVector3Array = (bsa[i] as Array)[Mesh.ARRAY_VERTEX]
			for v in p.size():
				p[v] += (tgt[v] - base[v]) * wt
			var tn = (bsa[i] as Array)[Mesh.ARRAY_NORMAL]
			if has_n and tn != null and (tn as PackedVector3Array).size() == base.size():
				for v in n.size():
					n[v] += ((tn as PackedVector3Array)[v] - (bn as PackedVector3Array)[v]) * wt
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if has_n:
			for v in n.size():
				n[v] = n[v].normalized()
		else:
			n.resize(p.size())
			for tt in range(0, idx.size(), 3):
				var a0 := p[idx[tt]]
				var fn := (p[idx[tt + 1]] - a0).cross(p[idx[tt + 2]] - a0)
				n[idx[tt]] += fn
				n[idx[tt + 1]] += fn
				n[idx[tt + 2]] += fn
			for v in n.size():
				n[v] = n[v].normalized()
		out.append({"p": p, "n": n, "idx": idx, "col": _color_for(String(mi.name), lp), "name": String(mi.name)})
	model.free()
	return out


static func _color_for(node_name: String, lp: Dictionary) -> Color:
	var mat := node_name.get_slice("__", 2)
	match mat:
		"skin_body", "skin_body2":
			return lp.get("skin", Color(0.8, 0.6, 0.5))
		"skin_lips":
			return lp.get("lips", Color(0.7, 0.4, 0.4))
		"eye_socket":
			return (lp.get("skin", Color(0.8, 0.6, 0.5)) as Color).lerp(Color(0.72, 0.36, 0.36), 0.55)
		"mouth_inner":
			return Color(0.18, 0.06, 0.06)
		"eye_pupil":
			return Color(0.02, 0.02, 0.02)
		"eye_iris":
			return lp.get("iris", Color(0.3, 0.4, 0.5))
		"eye_sclera":
			return Color(0.93, 0.92, 0.9)
		"hair_main":
			return lp.get("hair", Color(0.2, 0.15, 0.1))
		"cloth_shirt":
			return lp.get("top", Color(0.4, 0.4, 0.45))
		"cloth_pants":
			return lp.get("bottom", Color(0.2, 0.2, 0.25))
	return Color(0.5, 0.5, 0.5)


## Vykreslí díly do obrázku. yaw/pitch ve stupních (yaw 0 = zepředu, 90 = levý profil postavy).
## center/extent = střed a půlvýška záběru v metrech (ortografická kamera).
static func render(parts: Array, size: int, yaw_deg: float, pitch_deg: float, center: Vector3, extent: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(BG)
	var zbuf := PackedFloat32Array()
	zbuf.resize(size * size)
	zbuf.fill(-1e9)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	var inv := basis.inverse()
	var k := LIGHT_KEY.normalized()
	var f := LIGHT_FILL.normalized()
	var s := float(size) * 0.5 / extent
	for part in parts:
		var p: PackedVector3Array = part["p"]
		var n: PackedVector3Array = part["n"]
		var idx: PackedInt32Array = part["idx"]
		var col: Color = (part["col"] as Color).srgb_to_linear()   # stínování v lineárním prostoru
		var sp := PackedVector3Array()
		sp.resize(p.size())
		var shade := PackedColorArray()
		shade.resize(p.size())
		for v in p.size():
			var q: Vector3 = inv * (p[v] - center)
			sp[v] = Vector3(size * 0.5 + q.x * s, size * 0.5 - q.y * s, q.z)
			var nn: Vector3 = inv * n[v]
			var l := 0.3 + 1.1 * maxf(nn.dot(k), 0.0) + 0.35 * maxf(nn.dot(f), 0.0)
			var rim := pow(1.0 - absf(nn.z), 3.0) * 0.08
			var spec := pow(maxf((k + Vector3(0, 0, 1)).normalized().dot(nn), 0.0), 40.0) * 0.06
			shade[v] = Color(col.r * l + rim + spec, col.g * l + rim + spec, col.b * l + rim * 1.1 + spec).linear_to_srgb()
		for t in range(0, idx.size(), 3):
			_tri(img, zbuf, size, sp[idx[t]], sp[idx[t + 1]], sp[idx[t + 2]], shade[idx[t]], shade[idx[t + 1]], shade[idx[t + 2]])
	return img


static func _tri(img: Image, zbuf: PackedFloat32Array, size: int, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var minx := maxi(0, floori(minf(a.x, minf(b.x, c.x))))
	var maxx := mini(size - 1, ceili(maxf(a.x, maxf(b.x, c.x))))
	var miny := maxi(0, floori(minf(a.y, minf(b.y, c.y))))
	var maxy := mini(size - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
	if minx > maxx or miny > maxy:
		return
	var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if absf(area) < 1e-9:
		return
	for y in range(miny, maxy + 1):
		var py := float(y) + 0.5
		for x in range(minx, maxx + 1):
			var px := float(x) + 0.5
			var w0 := ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
			var w1 := ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var z := w0 * a.z + w1 * b.z + w2 * c.z
			var i := y * size + x
			if z <= zbuf[i]:
				continue
			zbuf[i] = z
			var cl := Color(ca.r * w0 + cb.r * w1 + cc.r * w2, ca.g * w0 + cb.g * w1 + cc.g * w2, ca.b * w0 + cb.b * w1 + cc.b * w2)
			img.set_pixel(x, y, cl.clamp())


## Kontaktní arch: řádky = snapshoty, sloupce = pohledy [Vector2(yaw, pitch)].
static func sheet(snaps: Array, views: Array, tile: int, center := Vector3(0.0, 1.64, 0.0), extent := 0.17, with_body := false) -> Image:
	var img := Image.create(tile * views.size(), tile * snaps.size(), false, Image.FORMAT_RGB8)
	for r in snaps.size():
		var parts := deformed_parts(snaps[r], "", with_body)
		for c in views.size():
			var v: Vector2 = views[c]
			var t := render(parts, tile, v.x, v.y, center, extent)
			img.blit_rect(t, Rect2i(0, 0, tile, tile), Vector2i(c * tile, r * tile))
	return img
