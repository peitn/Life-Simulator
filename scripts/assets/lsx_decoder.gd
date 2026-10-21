extends RefCounted
## Dekodér kompaktního formátu LSX (v3, v4) z „Blender bridge“ (tools/blender/lsx_common.py).
##
## Proč vlastní formát: Blender běží na jiném serveru (HF Space) a do projektu se data dostávají jen
## textově po částech (~3,5 kB). LSX je proto co nejmenší:
##   [u32 délka JSON][JSON hlavička][binární bloby], celé zlib + base64.
##   - pozice: kvantované na `qb` bitů v AABB části, delta po složkách, planárně (dolní/horní bajty),
##   - normály: oktaedricky 2×int8, planárně,
##   - indexy: kódování „vysoké hladiny“ (0 = další nový vrchol, k = odkaz o k zpět), pořadí Godotu (CW),
##   - kosti: max 2 na vrchol (2×uint8 index + uint8 váha první kosti).
## v4 navíc:
##   - morph targety (shape keys): na část [jméno, měřítko, offset, délka]; výchylky 3×int8 planárně,
##     delta-kódované mezi sousedními vrcholy (mod 256); hodnota = int8 / 127 × měřítko (m);
##     hlavička 'morphs' = globální pořadí jmen, 'morph_bones' = posuny hlav kostí při plné váze;
##   - čtyřúhelníková část ('prim': 'quad'): ŘÍDICÍ síť pro Catmull-Clark (subdiv.gd) s materiálem po
##     plochách ('mats', 'fmat'), bez normál – po zjemnění se dopočítají pro základ i každý morf.
## Kosti mají v Godotu identickou rotaci klidové pozy (jen posun) – animace se pak píší v osách modelu
## (X vpravo/vlevo, Y nahoru, Z dopředu), viz character_anims.gd.
##
## Blend shapes se staví v režimu BLEND_SHAPE_MODE_NORMALIZED s ABSOLUTNÍMI cíli: jen tak je Godot
## GLTF export zapíše správně jako morph targety (v režimu RELATIVE se cíle uloží chybně a nulové
## výchylky normál se při kompresi rozbijí – ověřeno testem v běhu 8). Výsledek je stejný:
## pozice = základ + Σ wᵢ·(cílᵢ − základ), i pro záporné váhy.
##
## Výsledek `build_scene()` je obyčejná scéna (Node3D → Skeleton3D → MeshInstance3D), kterou
## tools/import_lsx.gd uloží jako GLB do res://assets/models/.

const FORMAT_VERSIONS := [3, 4]
const FORMAT_VERSION := 4
const CHUNK_HEADER := "LSXC"
## Limity (ochrana před poškozenými/podvrženými daty).
const MAX_RAW_BYTES := 16 * 1024 * 1024
const MAX_MORPHS := 32
const MAX_SUBDIV := 2
const MAX_MORPH_SCALE := 1.0      # m – větší výchylka je nesmysl

const Subdiv := preload("res://scripts/assets/subdiv.gd")


## CRC-32 (IEEE, stejné jako Python binascii.crc32) – kontrola přenesených částí.
static var _crc_table: PackedInt64Array = PackedInt64Array()


static func crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for _k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


## Ověří a spojí přenesené části. Každá část má tvar:
##   "LSXC <jméno> <k>/<n> <crc32 hex>\n<base64 data>[\nLSXEND]"
## Vrací {"ok": bool, "data": String, "error": String}.
static func assemble(parts: Array) -> Dictionary:
	var by_index := {}
	var total := -1
	var asset_name := ""
	for p in parts:
		var text: String = String(p).strip_edges()
		var lines := text.split("\n", false)
		if lines.size() < 2:
			return {"ok": false, "data": "", "error": "část bez dat"}
		var head := lines[0].strip_edges().split(" ", false)
		if head.size() != 4 or head[0] != CHUNK_HEADER:
			return {"ok": false, "data": "", "error": "špatná hlavička: %s" % lines[0]}
		var kn := head[2].split("/")
		if kn.size() != 2 or not kn[0].is_valid_int() or not kn[1].is_valid_int():
			return {"ok": false, "data": "", "error": "špatné číslo části: %s" % head[2]}
		var k := int(kn[0])
		var n := int(kn[1])
		if total == -1:
			total = n
			asset_name = head[1]
		elif n != total or head[1] != asset_name:
			return {"ok": false, "data": "", "error": "části nepatří k sobě (%s)" % lines[0]}
		if k < 0 or k >= n:
			return {"ok": false, "data": "", "error": "index části mimo rozsah: %d/%d" % [k, n]}
		var body := ""
		for i in range(1, lines.size()):
			var l := lines[i].strip_edges()
			if l == "LSXEND":
				break
			body += l
		var expect := head[3].hex_to_int()
		var got := crc32(body.to_ascii_buffer())
		if got != expect:
			return {"ok": false, "data": "", "error": "CRC nesedí v části %d/%d (%08x != %08x)" % [k, n, got, expect]}
		by_index[k] = body
	if total <= 0 or by_index.size() != total:
		return {"ok": false, "data": "", "error": "chybí části: mám %d z %d" % [by_index.size(), total]}
	var out := ""
	for k in total:
		out += String(by_index[k])
	return {"ok": true, "data": out, "error": "", "name": asset_name}


## base64 → slovník {"head": Dictionary, "blob": PackedByteArray} nebo {} při chybě.
static func decode(b64: String) -> Dictionary:
	var packed := Marshalls.base64_to_raw(b64.strip_edges())
	if packed.is_empty():
		return {}
	# Python zlib.compress = zlib obálka = Godot COMPRESSION_DEFLATE.
	var raw := packed.decompress_dynamic(MAX_RAW_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() < 4:
		return {}
	var jl := raw.decode_u32(0)
	if jl <= 0 or 4 + jl > raw.size():
		return {}
	var head = JSON.parse_string(raw.slice(4, 4 + jl).get_string_from_utf8())
	if typeof(head) != TYPE_DICTIONARY or not FORMAT_VERSIONS.has(int(head.get("v", 0))):
		return {}
	var mn = head.get("morphs", [])
	if typeof(mn) != TYPE_ARRAY or (mn as Array).size() > MAX_MORPHS:
		return {}
	for m in mn:
		if typeof(m) != TYPE_STRING or String(m).is_empty():
			return {}
	return {"head": head, "blob": raw.slice(4 + jl)}


static func _range(blob: PackedByteArray, r) -> PackedByteArray:
	if typeof(r) != TYPE_ARRAY or (r as Array).size() < 2:
		return PackedByteArray()
	var off := int(r[0])
	var ln := int(r[1])
	if off < 0 or ln < 0 or off + ln > blob.size():
		return PackedByteArray()
	return blob.slice(off, off + ln)


static func _undelta16(b: PackedByteArray, count: int, start: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	var prev := 0
	for i in count:
		var d := b[start + i] | (b[start + count + i] << 8)
		prev = (prev + d) & 0xFFFF
		out[i] = prev
	return out


static func _s8(v: int) -> float:
	return float(v - 256 if v > 127 else v) / 127.0


static func _oct_decode(x: float, y: float) -> Vector3:
	var z := 1.0 - absf(x) - absf(y)
	if z < 0.0:
		var ox := x
		x = (1.0 - absf(y)) * (1.0 if ox >= 0.0 else -1.0)
		y = (1.0 - absf(ox)) * (1.0 if y >= 0.0 else -1.0)
	return Vector3(x, y, z).normalized()


static func _positions(part: Dictionary, blob: PackedByteArray, nv: int) -> PackedVector3Array:
	var qmax := float((1 << clampi(int(part.get("qb", 16)), 1, 16)) - 1)
	var mn = part.get("min", [0, 0, 0])
	var mx = part.get("max", [0, 0, 0])
	if typeof(mn) != TYPE_ARRAY or typeof(mx) != TYPE_ARRAY or (mn as Array).size() != 3 or (mx as Array).size() != 3:
		return PackedVector3Array()
	var pos_b := _range(blob, part.get("pos"))
	if pos_b.size() != nv * 6:
		return PackedVector3Array()
	var verts := PackedVector3Array()
	verts.resize(nv)
	var comps: Array = []
	for c in 3:
		comps.append(_undelta16(pos_b, nv, c * 2 * nv))
	for i in nv:
		var p := Vector3()
		for c in 3:
			var ext := maxf(float(mx[c]) - float(mn[c]), 1e-6)
			p[c] = float(mn[c]) + float(comps[c][i]) / qmax * ext
		verts[i] = p
	return verts


static func _indices(part: Dictionary, blob: PackedByteArray, ni: int, nv: int) -> PackedInt32Array:
	var idx_b := _range(blob, part.get("idx"))
	if idx_b.size() != ni * 2:
		return PackedInt32Array()
	var indices := PackedInt32Array()
	indices.resize(ni)
	var nxt := 0
	for i in ni:
		var code := idx_b[i] | (idx_b[ni + i] << 8)
		var vi: int
		if code == 0:
			vi = nxt
			nxt += 1
		else:
			vi = nxt - code
		if vi < 0 or vi >= nv:
			return PackedInt32Array()
		indices[i] = vi
	return indices


## Kosti (max 2 na vrchol) rozšířené na formát Godotu (4 na vrchol). Vrací {} při chybě.
static func _bones(part: Dictionary, blob: PackedByteArray, nv: int, bone_count: int) -> Dictionary:
	var bi_b := _range(blob, part.get("bi"))
	var bw_b := _range(blob, part.get("bw"))
	if bi_b.size() != nv * 2 or bw_b.size() != nv:
		return {}
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(nv * 4)
	weights.resize(nv * 4)
	for i in nv:
		var w := float(bw_b[i]) / 255.0
		var b0 := bi_b[i]
		var b1 := bi_b[nv + i]
		if b0 >= bone_count or b1 >= bone_count:
			return {}
		bones[i * 4] = b0
		bones[i * 4 + 1] = b1
		weights[i * 4] = w
		weights[i * 4 + 1] = 1.0 - w
	return {"bones": bones, "weights": weights}


## Výchylky morfů části: jméno → PackedVector3Array (nv). Chybějící morf = nulový. {} = poškozená data.
static func decode_morphs(part: Dictionary, blob: PackedByteArray, nv: int, names: Array) -> Dictionary:
	var out := {}
	var ml = part.get("morphs", [])
	if typeof(ml) != TYPE_ARRAY or (ml as Array).size() > MAX_MORPHS:
		return {"__error": true}
	for e in ml:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != 4:
			return {"__error": true}
		var nm := String(e[0])
		var sc := float(e[1])
		if not names.has(nm) or out.has(nm) or is_nan(sc) or sc <= 0.0 or sc > MAX_MORPH_SCALE:
			return {"__error": true}
		if int(e[3]) != nv * 3:
			return {"__error": true}
		var b := _range(blob, [e[2], e[3]])
		if b.size() != nv * 3:
			return {"__error": true}
		var comp: Array = []
		for c in 3:
			var col := PackedFloat32Array()
			col.resize(nv)
			var prev := 0
			for i in nv:
				prev = (prev + b[c * nv + i]) & 255
				col[i] = _s8(prev) * sc
			comp.append(col)
		var d := PackedVector3Array()
		d.resize(nv)
		for i in nv:
			d[i] = Vector3(comp[0][i], comp[1][i], comp[2][i])
		out[nm] = d
	return out


## Dekóduje jednu trojúhelníkovou část na pole pro ArrayMesh. Vrací [] při poškozených datech.
## (Případné morfy trojúhelníkové části vrací decode_morphs zvlášť.)
static func decode_part(part: Dictionary, blob: PackedByteArray, skinned: bool, bone_count := 256) -> Array:
	var nv := int(part.get("nv", 0))
	var ni := int(part.get("ni", 0))
	if nv <= 0 or nv > 65535 or ni <= 0 or ni % 3 != 0:
		return []
	var verts := _positions(part, blob, nv)
	if verts.is_empty():
		return []
	var nrm_b := _range(blob, part.get("nrm"))
	if nrm_b.size() != nv * 2:
		return []
	var normals := PackedVector3Array()
	normals.resize(nv)
	for i in nv:
		normals[i] = _oct_decode(_s8(nrm_b[i]), _s8(nrm_b[nv + i]))
	var indices := _indices(part, blob, ni, nv)
	if indices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if skinned:
		var bw := _bones(part, blob, nv, bone_count)
		if bw.is_empty():
			return []
		arrays[Mesh.ARRAY_BONES] = bw["bones"]
		arrays[Mesh.ARRAY_WEIGHTS] = bw["weights"]
	return arrays


## Čtyřúhelníková řídicí síť → zjemnění Catmull-Clarkem → povrchy po materiálech.
## Vrací {"surfaces": [{"mat": String, "arrays": Array, "blend": Array[Array]}], "fine_tris": int,
##        "verts": PackedVector3Array (zjemněný základ), "morphs": {jméno: PackedVector3Array výchylek}}
## nebo {} při poškozených datech.
static func decode_quad_part(part: Dictionary, blob: PackedByteArray, skinned: bool, morph_names: Array, bone_count := 256) -> Dictionary:
	var nv := int(part.get("nv", 0))
	var ni := int(part.get("ni", 0))
	if nv <= 0 or nv > 65535 or ni <= 0 or ni % 4 != 0:
		return {}
	var nq := ni / 4
	var mats = part.get("mats", [])
	if typeof(mats) != TYPE_ARRAY or (mats as Array).is_empty() or (mats as Array).size() > 16:
		return {}
	var verts := _positions(part, blob, nv)
	var quads := _indices(part, blob, ni, nv)
	var fm_b := _range(blob, part.get("fmat"))
	if verts.is_empty() or quads.is_empty() or fm_b.size() != nq:
		return {}
	var fmat := PackedInt32Array()
	fmat.resize(nq)
	for f in nq:
		if fm_b[f] >= (mats as Array).size():
			return {}
		fmat[f] = fm_b[f]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	if skinned:
		var bw := _bones(part, blob, nv, bone_count)
		if bw.is_empty():
			return {}
		bones = bw["bones"]
		weights = bw["weights"]
	var morphs := decode_morphs(part, blob, nv, morph_names)
	if morphs.has("__error"):
		return {}
	var levels := int(part.get("subdiv", 1))
	if levels < 0 or levels > MAX_SUBDIV:
		return {}
	for _l in levels:
		var op := Subdiv.build(quads, verts.size())
		if op.is_empty():
			return {}
		verts = Subdiv.apply_vec3(op, verts)
		for k in morphs:
			morphs[k] = Subdiv.apply_vec3(op, morphs[k])
		if skinned:
			var w2 := Subdiv.apply_weights(op, bones, weights)
			bones = w2["bones"]
			weights = w2["weights"]
		var nf := PackedInt32Array()
		var par: PackedInt32Array = op["parent"]
		nf.resize(par.size())
		for i in par.size():
			nf[i] = fmat[par[i]]
		fmat = nf
		quads = op["quads"]
	var normals := Subdiv.quad_normals(verts, quads)
	# Cíle morfů (absolutní pozice + normály) – pořadí podle globálního seznamu, chybějící = základ.
	var targets: Array = []
	for nm in morph_names:
		if morphs.has(nm):
			var tp := PackedVector3Array()
			tp.resize(verts.size())
			var dd: PackedVector3Array = morphs[nm]
			for i in verts.size():
				tp[i] = verts[i] + dd[i]
			targets.append([tp, Subdiv.quad_normals(tp, quads)])
		else:
			targets.append([verts, normals])
	var surfaces: Array = []
	for mi in (mats as Array).size():
		var remap := {}
		var idx := PackedInt32Array()
		for f in quads.size() / 4:
			if fmat[f] != mi:
				continue
			var q := [quads[f * 4], quads[f * 4 + 1], quads[f * 4 + 2], quads[f * 4 + 3]]
			var l := []
			for v in q:
				if not remap.has(v):
					remap[v] = remap.size()
				l.append(remap[v])
			# CCW z Blenderu → CW pro Godot: (0,2,1), (0,3,2).
			idx.append_array(PackedInt32Array([l[0], l[2], l[1], l[0], l[3], l[2]]))
		if idx.is_empty():
			continue
		var inv := PackedInt32Array()
		inv.resize(remap.size())
		for v in remap:
			inv[remap[v]] = v
		var sv := PackedVector3Array()
		var sn := PackedVector3Array()
		sv.resize(inv.size())
		sn.resize(inv.size())
		for i in inv.size():
			sv[i] = verts[inv[i]]
			sn[i] = normals[inv[i]]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sv
		arrays[Mesh.ARRAY_NORMAL] = sn
		arrays[Mesh.ARRAY_INDEX] = idx
		if skinned:
			var sb := PackedInt32Array()
			var sw := PackedFloat32Array()
			sb.resize(inv.size() * 4)
			sw.resize(inv.size() * 4)
			for i in inv.size():
				for k in 4:
					sb[i * 4 + k] = bones[inv[i] * 4 + k]
					sw[i * 4 + k] = weights[inv[i] * 4 + k]
			arrays[Mesh.ARRAY_BONES] = sb
			arrays[Mesh.ARRAY_WEIGHTS] = sw
		var blend: Array = []
		for t in targets:
			var tv := PackedVector3Array()
			var tn := PackedVector3Array()
			tv.resize(inv.size())
			tn.resize(inv.size())
			var tpos: PackedVector3Array = t[0]
			var tnrm: PackedVector3Array = t[1]
			for i in inv.size():
				tv[i] = tpos[inv[i]]
				tn[i] = tnrm[inv[i]]
			var ba := []
			ba.resize(Mesh.ARRAY_MAX)
			ba[Mesh.ARRAY_VERTEX] = tv
			ba[Mesh.ARRAY_NORMAL] = tn
			blend.append(ba)
		surfaces.append({"mat": String(mats[mi]), "arrays": arrays, "blend": blend})
	return {"surfaces": surfaces, "fine_tris": quads.size() / 2, "verts": verts, "morphs": morphs}


static func make_material(m: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(m.get("name", "mat"))
	var c: Array = m.get("color", [0.8, 0.8, 0.8])
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.roughness = clampf(float(m.get("rough", 0.8)), 0.0, 1.0)
	mat.metallic = clampf(float(m.get("metal", 0.0)), 0.0, 1.0)
	return mat


static func _mesh_instance(name: String, arrays: Array, blend: Array, morph_names: Array, mat: Material) -> MeshInstance3D:
	var am := ArrayMesh.new()
	if not blend.is_empty():
		am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		for nm in morph_names:
			am.add_blend_shape(StringName(nm))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)
	if mat != null:
		am.surface_set_material(0, mat)
	am.resource_name = name
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = am
	return mi


## Postaví scénu z dekódovaných dat. Uzly částí se jmenují "<skupina>__<část>__<materiál>",
## aby šly za běhu vybírat (např. vlasy krátké/dlouhé).
## `extra` = [[dekódovaná data, [vynechané skupiny]], …] – části dalších assetů se stejnou kostrou
## (např. hlava a vlasy z character_head.lsx k tělu z body.lsx); kosti se párují podle jména.
static func build_scene(decoded: Dictionary, extra: Array = []) -> Node3D:
	if decoded.is_empty():
		return null
	var head: Dictionary = decoded["head"]
	var root := Node3D.new()
	root.name = String(head.get("name", "asset"))
	var bones: Array = head.get("bones", [])
	var skinned := not bones.is_empty()
	var parent_node: Node3D = root
	var skin: Skin = null
	var skel: Skeleton3D = null
	if skinned:
		skel = Skeleton3D.new()
		skel.name = "Skeleton3D"
		root.add_child(skel)
		skel.owner = root
		skin = Skin.new()
		for i in bones.size():
			var b: Dictionary = bones[i]
			var hd: Array = b["head"]
			var gpos := Vector3(float(hd[0]), float(hd[1]), float(hd[2]))
			skel.add_bone(String(b["name"]))
			var par := int(b.get("parent", -1))
			var local := gpos
			if par >= 0:
				if par >= i:
					root.free()
					return null
				skel.set_bone_parent(i, par)
				var ph: Array = bones[par]["head"]
				local = gpos - Vector3(float(ph[0]), float(ph[1]), float(ph[2]))
			skel.set_bone_rest(i, Transform3D(Basis(), local))
			skel.set_bone_pose_position(i, local)
			skin.add_named_bind(String(b["name"]), Transform3D(Basis(), -gpos))
		parent_node = skel
	var sources := [[decoded, []]]
	sources.append_array(extra)
	for src in sources:
		var dec: Dictionary = src[0]
		var skip: Array = src[1]
		if dec.is_empty():
			root.free()
			return null
		var h: Dictionary = dec["head"]
		var blob: PackedByteArray = dec["blob"]
		var mats := {}
		for m in h.get("materials", []):
			mats[String(m.get("name", ""))] = make_material(m)
		var morph_names: Array = h.get("morphs", [])
		# Přemapování kostí podle jména (extra asset může mít jiné pořadí).
		var src_bones: Array = h.get("bones", [])
		var bone_map := PackedInt32Array()
		if skinned:
			for b in src_bones:
				var bi := skel.find_bone(String(b.get("name", "")))
				if bi < 0:
					root.free()
					return null
				bone_map.append(bi)
		elif not src_bones.is_empty():
			root.free()
			return null
		for part in h.get("parts", []):
			var grp := String(part.get("group", ""))
			if skip.has(grp):
				continue
			var pname := String(part.get("name", "part"))
			var instances: Array = []
			if String(part.get("prim", "tri")) == "quad":
				var q := decode_quad_part(part, blob, skinned, morph_names, src_bones.size())
				if q.is_empty():
					root.free()
					return null
				for s in q["surfaces"]:
					var mname := String(s["mat"])
					if skinned:
						_remap_bones(s["arrays"], bone_map)
					instances.append([_mesh_instance("%s__%s__%s" % [grp if grp != "" else "main", pname, mname],
						s["arrays"], s["blend"], morph_names, mats.get(mname)), s["arrays"]])
			else:
				var arrays := decode_part(part, blob, skinned, src_bones.size() if skinned else 256)
				if arrays.is_empty():
					root.free()
					return null
				var blend: Array = []
				if part.has("morphs"):
					var ms := decode_morphs(part, blob, int(part.get("nv", 0)), morph_names)
					if ms.has("__error"):
						root.free()
						return null
					var base_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					for nm in morph_names:
						var tv := base_v.duplicate()
						if ms.has(nm):
							var dd: PackedVector3Array = ms[nm]
							for i in tv.size():
								tv[i] += dd[i]
						var ba := []
						ba.resize(Mesh.ARRAY_MAX)
						ba[Mesh.ARRAY_VERTEX] = tv
						# Trojúhelníkové části nemají topologii pro přepočet – normály zůstávají ze základu.
						ba[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
						blend.append(ba)
				if skinned:
					_remap_bones(arrays, bone_map)
				var mname := String(part.get("mat", ""))
				instances.append([_mesh_instance("%s__%s__%s" % [grp if grp != "" else "main", pname, mname],
					arrays, blend, morph_names, mats.get(mname)), arrays])
			for pair in instances:
				var mi: MeshInstance3D = pair[0]
				parent_node.add_child(mi)
				mi.owner = root
				if skinned:
					mi.skin = skin
					mi.skeleton = NodePath("..")
	return root


## Přečísluje kosti v polích povrchu podle mapy (index v assetu → index v kostře scény).
static func _remap_bones(arrays: Array, bone_map: PackedInt32Array) -> void:
	var identity := true
	for i in bone_map.size():
		if bone_map[i] != i:
			identity = false
	if identity:
		return
	var bb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	for i in bb.size():
		bb[i] = bone_map[bb[i]]
	arrays[Mesh.ARRAY_BONES] = bb


## Statistika pro manifest a testy (trojúhelníky PO zjemnění).
static func stats(decoded: Dictionary) -> Dictionary:
	var head: Dictionary = decoded.get("head", {})
	var tris := 0
	var verts := 0
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in head.get("parts", []):
		if String(p.get("prim", "tri")) == "quad":
			tris += int(p.get("ni", 0)) / 4 * 2 * int(pow(4.0, float(clampi(int(p.get("subdiv", 1)), 0, MAX_SUBDIV))))
		else:
			tris += int(p.get("ni", 0)) / 3
		verts += int(p.get("nv", 0))
		var a: Array = p.get("min", [0, 0, 0])
		var b: Array = p.get("max", [0, 0, 0])
		mn = mn.min(Vector3(float(a[0]), float(a[1]), float(a[2])))
		mx = mx.max(Vector3(float(b[0]), float(b[1]), float(b[2])))
	return {"tris": tris, "verts": verts, "aabb_min": mn, "aabb_max": mx,
		"bones": (head.get("bones", []) as Array).size(), "parts": (head.get("parts", []) as Array).size(),
		"morphs": (head.get("morphs", []) as Array).size()}
