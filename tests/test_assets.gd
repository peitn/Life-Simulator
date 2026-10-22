extends "res://tests/test_base.gd"
## Test 3D assetů z Blenderu: přenosový formát LSX (CRC, dekódování, odolnost proti poškozeným
## datům), GLB modely (rozměry vs. herní půdorys, orientace, winding, kostra a váhy),
## procedurální animace (sémantika póz) a SimVisual (výběr animace podle pohybu a pózy,
## varianty těla, vlastní materiály postav), fallback na primitiva a WorldBuilder.

const LSX := preload("res://scripts/assets/lsx_decoder.gd")
const AssetLibrary := preload("res://scripts/assets/asset_library.gd")
const CharacterAnims := preload("res://scripts/assets/character_anims.gd")
const SimVisual := preload("res://scripts/sim/sim_visual.gd")
const WorldBuilder := preload("res://scripts/world/world_builder.gd")
const MODELS := ["character", "sofa", "bed_double", "bed_single", "fridge"]


func _ready() -> void:
	watchdog_seconds = 90.0
	_test_format()
	_test_sources()
	_test_furniture()
	_test_character_mesh()
	_test_animations()
	await _test_visual()
	_test_fallback_and_world()
	finish("test_assets")


# ---------------------------------------------------------------- formát LSX

func _test_format() -> void:
	section("Formát LSX: CRC, skládání částí, odmítnutí poškozených dat")
	check(LSX.crc32("123456789".to_ascii_buffer()) == 0xCBF43926, "CRC-32 odpovídá standardu (binascii.crc32)")
	var body := "QUJDREVGR0g="
	var crc := "%08x" % LSX.crc32(body.to_ascii_buffer())
	var ok := LSX.assemble(["LSXC t 0/1 %s\n%s\nLSXEND" % [crc, body]])
	check(ok["ok"] and ok["data"] == body and ok["name"] == "t", "platná část se složí")
	var bad := LSX.assemble(["LSXC t 0/1 %s\n%s\nLSXEND" % [crc, "QUJDREVGR0h="]])
	check(not bad["ok"] and String(bad["error"]).contains("CRC"), "změna jediného znaku → CRC chyba", str(bad))
	var miss := LSX.assemble(["LSXC t 0/2 %s\n%s" % [crc, body]])
	check(not miss["ok"], "chybějící část se odhalí")
	var mixed := LSX.assemble(["LSXC a 0/2 %s\n%s" % [crc, body], "LSXC b 1/2 %s\n%s" % [crc, body]])
	check(not mixed["ok"], "části různých assetů se nesmíchají")
	var oob := LSX.assemble(["LSXC t 5/1 %s\n%s" % [crc, body]])
	check(not oob["ok"], "index části mimo rozsah se odmítne")
	check(LSX.decode("tohle-neni-base64!!").is_empty(), "nesmysl se nedekóduje")
	var wrong_ver := Marshalls.raw_to_base64(_pack_raw({"v": 99, "parts": []}).compress(FileAccess.COMPRESSION_DEFLATE))
	check(LSX.decode(wrong_ver).is_empty(), "jiná verze formátu se odmítne")
	# Poškozený rozsah blobu (odkaz mimo data) nesmí spadnout – build_scene vrátí null.
	var evil := {"head": {"v": 3, "name": "x", "materials": [], "parts": [
		{"name": "p", "group": "", "mat": "", "nv": 3, "ni": 3, "qb": 12, "min": [0, 0, 0], "max": [1, 1, 1],
		"pos": [0, 9999], "nrm": [0, 6], "idx": [0, 6]}]}, "blob": PackedByteArray([1, 2, 3])}
	check(LSX.build_scene(evil) == null, "odkaz mimo blob → null (žádný pád)")
	# Index vrcholu mimo rozsah (podvržená data) → null.
	var blob := PackedByteArray()
	blob.resize(6 * 3 + 2 * 3)
	var idx := PackedByteArray([0, 0, 200, 0, 0, 0])   # kód 200 = odkaz daleko zpět
	blob.append_array(idx)
	var evil2 := {"head": {"v": 3, "name": "x", "materials": [], "parts": [
		{"name": "p", "group": "", "mat": "", "nv": 3, "ni": 3, "qb": 12, "min": [0, 0, 0], "max": [1, 1, 1],
		"pos": [0, 18], "nrm": [18, 6], "idx": [24, 6]}]}, "blob": blob}
	check(LSX.build_scene(evil2) == null, "index vrcholu mimo rozsah → null")


func _pack_raw(head: Dictionary) -> PackedByteArray:
	var js := JSON.stringify(head).to_utf8_buffer()
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, js.size())
	raw.append_array(js)
	return raw


# ---------------------------------------------------------------- zdroje a manifest

func _test_sources() -> void:
	section("Zdroje: res://assets/src/*.lsx ↔ manifest ↔ GLB")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	check(typeof(manifest) == TYPE_DICTIONARY, "manifest.json existuje")
	if typeof(manifest) != TYPE_DICTIONARY:
		return
	for m in MODELS:
		if m == "character":
			_check_composed_character(manifest.get(m, {}))
			continue
		var b64 := FileAccess.get_file_as_string("res://assets/src/%s.lsx" % m)
		var dec := LSX.decode(b64)
		check(not dec.is_empty(), "%s.lsx se dekóduje" % m)
		if dec.is_empty():
			continue
		var st := LSX.stats(dec)
		var e: Dictionary = manifest.get(m, {})
		check("%08x" % LSX.crc32(b64.strip_edges().to_ascii_buffer()) == String(e.get("lsx_crc", "")),
			"%s: CRC zdroje sedí s manifestem" % m)
		check(int(st["tris"]) == int(e.get("tris", -1)), "%s: %d trojúhelníků jako v manifestu" % [m, st["tris"]])
		check(int(st["tris"]) <= 8000, "%s: rozpočet trojúhelníků ≤ 8000" % m, str(st["tris"]))
		check(FileAccess.file_exists("res://assets/models/%s.glb" % m), "%s.glb existuje" % m)
	var parts_left := DirAccess.get_files_at("res://assets/src/")
	var leftovers := 0
	for f in parts_left:
		if f.ends_with(".part"):
			leftovers += 1
	check(leftovers == 0, "po importu nezůstaly přenosové části (.part)")


## Postava je složená (tělo v4 se shape keys + hlava/vlasy v3) – kontrola obou zdrojů a rozpočtu.
func _check_composed_character(e: Dictionary) -> void:
	var crcs = e.get("lsx_crc", {})
	check(typeof(crcs) == TYPE_DICTIONARY and crcs.has("body") and crcs.has("character_head"), "character: složená z body + character_head", str(crcs))
	if typeof(crcs) != TYPE_DICTIONARY:
		return
	for src in ["body", "character_head"]:
		var b64 := FileAccess.get_file_as_string("res://assets/src/%s.lsx" % src)
		check(not LSX.decode(b64).is_empty(), "%s.lsx se dekóduje" % src)
		check("%08x" % LSX.crc32(b64.strip_edges().to_ascii_buffer()) == String(crcs.get(src, "")), "%s: CRC zdroje sedí s manifestem" % src)
	check(int(LSX.decode(FileAccess.get_file_as_string("res://assets/src/character_head.lsx"))["head"]["v"]) == 3, "LSX v3 (hlava) je stále čitelné")
	# Od C3 má postava skutečný obličej (víčka, rty, uši a oči jako geometrie, ~7 800 tri) → rozpočet 18 000.
	# Běh 21 (C3++): + řasy (~730) a ústa – zuby, dáseň, jazyk (~1 600) → rozpočet 20 000.
	check(int(e.get("tris", 0)) > 8000 and int(e.get("tris", 0)) <= 20000, "character: rozpočet trojúhelníků ≤ 20 000 (hlavní postava s obličejem, řasami a ústy)", str(e.get("tris")))
	check(FileAccess.file_exists("res://assets/models/character.glb"), "character.glb existuje")


# ---------------------------------------------------------------- nábytek

func _aabb_of(root: Node3D, filter := "") -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if filter != "" and not String(mi.name).contains(filter):
			continue
		var a: AABB = mi.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


## Těžiště vrcholů nad výškou y_min (pro ověření orientace: kde je opěradlo / čelo postele).
func _centroid_above(root: Node3D, y_min: float) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var arr: Array = mi.mesh.surface_get_arrays(0)
		for v in arr[Mesh.ARRAY_VERTEX]:
			if v.y > y_min:
				s += v
				n += 1
	return s / maxf(1.0, float(n))


func _winding_ok(root: Node3D) -> float:
	var good := 0
	var total := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in range(0, ix.size(), 3):
			var fn := (v[ix[i + 1]] - v[ix[i]]).cross(v[ix[i + 2]] - v[ix[i]])
			if fn.length_squared() < 1e-14:
				continue
			total += 1
			if fn.dot(nn[ix[i]] + nn[ix[i + 1]] + nn[ix[i + 2]]) < 0.0:
				good += 1
	return float(good) / maxf(1.0, float(total))


func _test_furniture() -> void:
	section("Nábytek: rozměry podle herních půdorysů, orientace, winding, PBR detail")
	AssetLibrary.clear_cache()
	var expect := {
		"sofa": [Vector2(2.0, 2.4), Vector2(0.75, 1.0), Vector2(0.7, 0.95)],
		"bed_double": [Vector2(1.6, 1.9), Vector2(2.0, 2.25), Vector2(0.85, 1.15)],
		"bed_single": [Vector2(0.9, 1.1), Vector2(2.0, 2.2), Vector2(0.75, 1.0)],
		"fridge": [Vector2(0.55, 0.9), Vector2(0.6, 0.8), Vector2(1.7, 2.0)],
	}
	for m in expect:
		var root := AssetLibrary.instantiate(m)
		check(root != null, "%s se načte" % m)
		if root == null:
			continue
		var b := _aabb_of(root)
		var e: Array = expect[m]
		check(b.size.x >= e[0].x and b.size.x <= e[0].y, "%s: šířka %.2f m" % [m, b.size.x])
		check(b.size.z >= e[1].x and b.size.z <= e[1].y, "%s: hloubka/délka %.2f m" % [m, b.size.z])
		check(b.size.y >= e[2].x and b.size.y <= e[2].y, "%s: výška %.2f m" % [m, b.size.y])
		check(absf(b.position.y) < 0.01, "%s stojí na podlaze (min y %.3f)" % [m, b.position.y])
		var w := _winding_ok(root)
		check(w > 0.97, "%s: %.1f %% trojúhelníků má winding Godotu (CW = líc)" % [m, w * 100.0])
		var enhanced := 0
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if mat != null and mat.has_meta("lsx_enhanced"):
				enhanced += 1
		check(enhanced > 0, "%s: materiály mají PBR detail" % m)
		root.free()
	# Orientace: předek modelu je +Z (jako primitiva v WorldBuilderu).
	var sofa := AssetLibrary.instantiate("sofa")
	check(_centroid_above(sofa, 0.62).z < -0.1, "gauč: opěradlo vzadu (−Z)")
	sofa.free()
	var bed := AssetLibrary.instantiate("bed_double")
	check(_centroid_above(bed, 0.8).z < -0.8, "postel: čelo u hlavy (−Z)")
	bed.free()
	var fridge := AssetLibrary.instantiate("fridge")
	var handles := _aabb_of(fridge, "metal_steel")
	check(handles.get_center().z > 0.25, "lednice: madla vepředu (+Z)")
	fridge.free()
	var before := AssetLibrary.load_count
	var again := AssetLibrary.instantiate("sofa")
	check(AssetLibrary.load_count == before, "druhá instance se bere z cache (GLB se nečte znovu)")
	again.free()


# ---------------------------------------------------------------- postava

func _test_character_mesh() -> void:
	section("Postava: kostra, skin, váhy, varianty, orientace")
	var root := AssetLibrary.instantiate("character")
	check(root != null, "character.glb se načte")
	if root == null:
		return
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	check(sk.get_bone_count() == 17, "17 kostí", str(sk.get_bone_count()))
	var missing := []
	for b in CharacterAnims.BONES:
		if sk.find_bone(b) < 0:
			missing.append(b)
	check(missing.is_empty(), "všechny kosti z animací existují", str(missing))
	var groups := {}
	var bad_w := 0
	var bad_b := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		groups[String(mi.name).get_slice("__", 0)] = true
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null:
			bad_w += 1
			continue
		var per := int(bones.size() / maxi(1, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		for i in range(0, weights.size(), per):
			var s := 0.0
			for k in per:
				s += weights[i + k]
				if bones[i + k] < 0 or bones[i + k] >= 17:
					bad_b += 1
			if absf(s - 1.0) > 0.01:
				bad_w += 1
		check(mi.skin != null, "%s má Skin" % mi.name)
	check(bad_w == 0, "součet vah každého vrcholu = 1", str(bad_w))
	check(bad_b == 0, "indexy kostí v rozsahu", str(bad_b))
	for g in ["body", "head", "hair_short", "hair_long"]:
		check(groups.has(g), "skupina %s je v modelu" % g)
	check(not groups.has("body_m") and not groups.has("body_f"), "žádné „mužské/ženské“ tělo – jedna neutrální síť")
	var b := _aabb_of(root, "body__")
	var h := _aabb_of(root, "hair_short")
	check(h.end.y > 1.72 and h.end.y < 1.86, "výška postavy %.2f m" % h.end.y)
	check(b.size.x > 0.45 and b.size.x < 0.8, "rozpětí paží v A-póze %.2f m" % b.size.x)
	var head := _aabb_of(root, "head__face")
	check(head.end.z > absf(head.position.z), "nos míří dopředu (+Z), stejně jako chůze postavy")
	var bs_ok := true
	for mi in AssetLibrary.parts_in_group(root, "body"):
		var mm: ArrayMesh = mi.mesh
		if mm.get_blend_shape_count() != 10:
			bs_ok = false
	check(bs_ok and not AssetLibrary.parts_in_group(root, "body").is_empty(), "každá část těla má 10 blend shapes")
	root.free()


# ---------------------------------------------------------------- animace

## Aplikuje pózu (vlastní dopředná kinematika – nezávislá na tom, kdy Skeleton3D přepočítá pózu)
## a vrátí globální polohy kostí v souřadnicích modelu.
func _posed(sk: Skeleton3D, clip: String, p: float) -> Dictionary:
	var ps := CharacterAnims.pose(clip, p)
	var glob := {}
	var out := {}
	for i in sk.get_bone_count():
		var b := sk.get_bone_name(i)
		var local := Transform3D(Basis(Quaternion.from_euler(ps.get(b, Vector3.ZERO))), sk.get_bone_rest(i).origin)
		if b == "hips":
			local.origin = ps["pos"]
		var par := sk.get_bone_parent(i)
		glob[i] = (glob[par] * local) if par >= 0 else local
		out[b] = (glob[i] as Transform3D).origin
	# Špička chodidla = kotník + vektor ke špičce otočený globální rotací kosti chodidla.
	for s in ["l", "r"]:
		out["toe_" + s] = (glob[sk.find_bone("foot_" + s)] as Transform3D) * Vector3(0, -0.06, 0.13)
	return out


func _test_animations() -> void:
	section("Animace: knihovna a sémantika póz")
	var lib := CharacterAnims.library()
	for c in ["idle", "walk", "sit", "lie"]:
		check(lib.has_animation(c), "klip %s existuje" % c)
		if lib.has_animation(c):
			var a := lib.get_animation(c)
			check(a.loop_mode == Animation.LOOP_LINEAR, "%s je smyčka" % c)
			check(a.get_track_count() == CharacterAnims.BONES.size() + 1, "%s má stopy pro všechny kosti + pánev" % c)
	var root := AssetLibrary.instantiate("character")
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	# Stoj: kotníky u země, ruce podél těla (ne v těle).
	var st := _posed(sk, "idle", 0.0)
	check(st["foot_l"].y > 0.04 and st["foot_l"].y < 0.14, "idle: kotník ve výšce %.2f m" % st["foot_l"].y)
	check(absf(st["hand_l"].x) > 0.2, "idle: ruka mimo stehno (x %.2f)" % st["hand_l"].x)
	# Chůze: v p=0 levá noha vpředu, v p=0.5 pravá; délka kroku realistická; špičky nad zemí.
	var w0 := _posed(sk, "walk", 0.0)
	var w5 := _posed(sk, "walk", 0.5)
	check(w0["foot_l"].z > w0["foot_r"].z + 0.2, "walk p=0: levá noha vpředu (Δz %.2f)" % (w0["foot_l"].z - w0["foot_r"].z))
	check(w5["foot_r"].z > w5["foot_l"].z + 0.2, "walk p=0.5: pravá noha vpředu")
	var stride: float = w0["foot_l"].z - w0["foot_r"].z
	check(stride > 0.35 and stride < 0.95, "délka kroku %.2f m (při 1 s cyklu ≈ chůze 1,3 m/s)" % stride)
	check(w0["hand_l"].z < w0["hand_r"].z, "walk: levá ruka jde dozadu, když levá noha dopředu")
	var min_y := 9.0
	for i in 16:
		var w := _posed(sk, "walk", float(i) / 16.0)
		min_y = minf(min_y, minf(w["toe_l"].y, w["toe_r"].y))
	check(min_y > -0.06, "walk: špičky nezapadají hluboko pod podlahu (min %.3f)" % min_y)
	# Sed: pánev v úrovni sedáku, stehna dopředu, chodidla na zemi.
	var s := _posed(sk, "sit", 0.0)
	check(absf(s["hips"].y - 0.5) < 0.02, "sit: pánev ve výšce %.2f m (sedák gauče ~0,44)" % s["hips"].y)
	check(s["shin_l"].z > s["hips"].z + 0.3, "sit: kolena vpředu (stehna vodorovně)")
	check(absf(s["shin_l"].y - s["hips"].y) < 0.12, "sit: stehna zhruba vodorovně")
	check(s["foot_l"].y > 0.0 and s["foot_l"].y < 0.18, "sit: kotník u země (%.2f m)" % s["foot_l"].y)
	check(s["head"].y > 1.0, "sit: hlava nahoře (%.2f m)" % s["head"].y)
	root.free()


# ---------------------------------------------------------------- SimVisual

func _test_visual() -> void:
	section("SimVisual: model, varianty, materiály, výběr animace")
	var holder := Node3D.new()
	add_child(holder)
	var v := Node3D.new()
	v.set_script(SimVisual)
	v.configure(Color(0.8, 0.2, 0.2), true)   # rod (female) vzhled NEovlivní
	holder.add_child(v)
	check(v.uses_model(), "postava používá model z Blenderu")
	var vis := {}
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var g := String(mi.name).get_slice("__", 0)
		if mi.visible:
			vis[g] = true
	# C4b: výchozí krátké vlasy jsou karty (hair_cards_scalp), „helma“ z GLB (hair_short/hair_long) je skrytá.
	check(vis.has("body") and vis.has("hair_cards_scalp") and not vis.has("hair_short") and not vis.has("hair_long")
		and not vis.has("body_m") and not vis.has("body_f"),
		"bez snapshotu: neutrální tělo a výchozí vlasy (karty) bez ohledu na rod", str(vis.keys()))
	v.apply("stand", 10.0, "neutral", "Jana Nováková", "Nic")
	var v2 := Node3D.new()
	v2.set_script(SimVisual)
	v2.configure(Color(0.2, 0.3, 0.8), false)
	holder.add_child(v2)
	v2.apply("stand", 10.0, "neutral", "Jana Nováková", "Nic")
	check(v.skin_color == v2.skin_color and v.hair_color == v2.hair_color, "bez snapshotu: stejný výchozí vzhled (jméno vzhled neurčuje)")
	var shirt1: StandardMaterial3D = v._mats.get("cloth_shirt")
	var shirt2: StandardMaterial3D = v2._mats.get("cloth_shirt")
	check(shirt1 != null and shirt2 != null and shirt1 != shirt2, "každá postava má vlastní materiály")
	if shirt1 != null and shirt2 != null:
		check(shirt1.albedo_color.is_equal_approx(Color(0.8, 0.2, 0.2)) and shirt2.albedo_color.is_equal_approx(Color(0.2, 0.3, 0.8)),
			"barva oblečení podle postavy")
	# Vzhled jen z explicitního snapshotu CharacterData: různé snapshoty → různý vzhled,
	# stejný snapshot → stejný vzhled, jméno v popisku nic nemění.
	var tones := {}
	for tone in [0.05, 0.3, 0.5, 0.7, 0.95]:
		v2.apply_look({"skin": {"tone": tone}, "body": {"bust": 0.1}, "hair": {"style": "holy"}})
		v2.apply("stand", 10.0, "neutral", "Jana Nováková", "Nic")
		tones[v2.skin_color.to_html()] = true
	check(tones.size() == 5, "spojitý odstín kůže ze snapshotu (%d z 5)" % tones.size())
	var vis2 := {}
	for mi in v2.find_children("*", "MeshInstance3D", true, false):
		if mi.visible:
			vis2[String(mi.name).get_slice("__", 0)] = true
	check(vis2.has("body") and not vis2.has("hair_short") and not vis2.has("hair_long") and not vis2.has("hair_cards_scalp"),
		"tělo + vlasy podle explicitních atributů (účes holá hlava)", str(vis2.keys()))
	# Chůze: posun 1,3 m/s → walk, zastavení → idle.
	check(v.current_anim() == "idle", "stojící postava: idle")
	for i in 40:
		holder.position.x += 1.3 * get_process_delta_time()
		await get_tree().process_frame
	check(v.current_anim() == "walk", "pohyb 1,3 m/s → walk (rychlost %.2f)" % v.smoothed_speed())
	check(v._anim.speed_scale > 0.5 and v._anim.speed_scale < 1.6, "rychlost kroku odpovídá rychlosti (%.2f)" % v._anim.speed_scale)
	for i in 40:
		await get_tree().process_frame
	check(v.current_anim() == "idle", "zastavení → idle")
	# Teleport (snap loutky / přesun k objektu) se nepočítá jako chůze.
	holder.position.x += 10.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(v.current_anim() == "idle", "teleport o 10 m není chůze")
	# Ultra rychlost při nízkém FPS (36 m/s, 10 FPS = 3,6 m za snímek) je pořád chůze, ne teleport.
	for i in 6:
		holder.position.x += 3.6
		v.track_motion(0.1)
	check(v.smoothed_speed() > 20.0, "Ultra 36 m/s při 10 FPS se měří jako pohyb (%.1f m/s)" % v.smoothed_speed())
	for i in 30:
		v.track_motion(0.1)
	# Vzhled ze snapshotu přes deterministický AppearanceResolver (žádný hash jména).
	var snap := {"skin": {"tone": 0.62, "undertone": 0.3, "redness": 0.2}, "hair": {"style": "afro", "melanin": 0.9}}
	v.apply_look(snap)
	var r1: Color = v.skin_color
	v.apply("stand", 0.0, "neutral", "Úplně Jiné Jméno", "Nic")
	check(v.skin_color == r1 and v.look_params["hair_variant"] == "hair_long", "vzhled se změnou jména nemění (afro → dlouhá síť)")
	v.apply("sit", 0.0, "neutral", "Jana Nováková", "Kouká na TV")
	check(v.current_anim() == "sit", "póza sit → klip sit")
	v.apply("lie", 0.0, "neutral", "Jana Nováková", "Spí")
	check(v.current_anim() == "lie", "póza lie → klip lie")
	check(absf(v._body_pivot.rotation.x + PI / 2.0) < 0.01, "vleže je tělo otočené na záda")
	check(not v._gem.visible, "vleže je krystal nálady skrytý")
	v.apply("stand", 0.0, "neutral", "Jana Nováková", "Nic")
	check(v.current_anim() == "idle" and v._body_pivot.rotation.is_zero_approx(), "návrat do stoje")
	holder.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- fallback + svět

func _test_fallback_and_world() -> void:
	section("Fallback na primitiva a WorldBuilder")
	var w_root := Node3D.new()
	add_child(w_root)
	var wb = WorldBuilder.new(w_root)
	wb.build()
	var n_objects: int = wb.objects.size()
	check(n_objects >= 9, "svět má %d interaktivních objektů" % n_objects)
	for m in ["sofa", "bed_double", "bed_single", "fridge"]:
		check(wb.models_used.has(m), "WorldBuilder použil model %s" % m)
	w_root.free()
	AssetLibrary.enabled = false
	var v := Node3D.new()
	v.set_script(SimVisual)
	add_child(v)
	check(not v.uses_model() and v.current_anim() == "", "bez knihovny: postava z primitiv (žádný pád)")
	v.apply("sit", 0.0, "neutral", "Petr", "Sedí")
	check(is_equal_approx(v._body_pivot.position.y, -0.3), "primitiva: starý posun pro sed")
	v.free()
	var w2 := Node3D.new()
	add_child(w2)
	var wb2 = WorldBuilder.new(w2)
	wb2.build()
	check(wb2.models_used.is_empty() and wb2.objects.size() == n_objects, "bez knihovny: svět z primitiv, stejné objekty (herní logika beze změny)")
	w2.free()
	AssetLibrary.enabled = true
