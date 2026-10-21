extends RefCounted
## Catmull-Clark (1 úroveň) pro UZAVŘENOU čtyřúhelníkovou síť, bez limitní plochy – stejný algoritmus jako
## cc_matrix() v tools/blender/char.py (a jako Blender Subdivision Surface s use_limit_surface = False;
## shoda ověřena v Blenderu s chybou 3,6e-7 m).
##
## Operátor je lineární, takže se sestaví jednou jako řídké řádky (jemný vrchol = vážený součet řídicích)
## a stejně se aplikuje na pozice, výchylky morfů i váhy kostí. Tím je zaručeno, že morf zjemněné sítě
## = zjemnění morfu řídicí sítě (blend shapes sedí přesně).
##
## Pořadí jemných vrcholů: [vrcholové body (nv)][hranové body v pořadí objevení po plochách][body ploch].
## Nová plocha z plochy f a jejího rohu k: (v_k, e(k,k+1), f, e(k−1,k)) – zachovává orientaci.

## Sestaví operátor. quads = 4 indexy na plochu (orientace z Blenderu, CCW zvenku).
## Vrací {"rows_c": Array[PackedInt32Array], "rows_w": Array[PackedFloat32Array], "quads": PackedInt32Array,
##        "nv": int (počet jemných vrcholů), "parent": PackedInt32Array (rodičovská plocha každé nové plochy)}
## nebo {} když síť není uzavřená 2-varieta (každá hrana právě ve 2 plochách) nebo má neplatné indexy.
static func build(quads: PackedInt32Array, nv: int) -> Dictionary:
	if quads.size() % 4 != 0 or nv <= 0:
		return {}
	var nf := quads.size() / 4
	for i in quads:
		if i < 0 or i >= nv:
			return {}
	var edge_id := {}
	var edge_a := PackedInt32Array()
	var edge_b := PackedInt32Array()
	var edge_faces: Array = []       # Array polí (ne Packed – ta jsou hodnotová, append na kopii by se ztratil)
	for f in nf:
		for k in 4:
			var a := quads[f * 4 + k]
			var b := quads[f * 4 + (k + 1) % 4]
			if a == b:
				return {}
			var key := mini(a, b) * 1048576 + maxi(a, b)
			if not edge_id.has(key):
				edge_id[key] = edge_a.size()
				edge_a.append(mini(a, b))
				edge_b.append(maxi(a, b))
				edge_faces.append([])
			(edge_faces[edge_id[key]] as Array).append(f)
	var ne := edge_a.size()
	for e in ne:
		if (edge_faces[e] as Array).size() != 2:
			return {}
	var rows: Array = []          # Dictionary col -> w (dočasně)
	rows.resize(nv + ne + nf)
	# Body ploch.
	for f in nf:
		var r := {}
		for k in 4:
			var v := quads[f * 4 + k]
			r[v] = float(r.get(v, 0.0)) + 0.25
		rows[nv + ne + f] = r
	# Hranové body: (a + b + F1 + F2) / 4.
	for e in ne:
		var r := {}
		r[edge_a[e]] = 0.25
		r[edge_b[e]] = float(r.get(edge_b[e], 0.0)) + 0.25
		for f in (edge_faces[e] as Array):
			var fr: Dictionary = rows[nv + ne + f]
			for c in fr:
				r[c] = float(r.get(c, 0.0)) + 0.25 * float(fr[c])
		rows[nv + e] = r
	# Vrcholové body: (F + 2R + (n − 3)P) / n.
	var vfaces: Array = []
	var vnb: Array = []
	vfaces.resize(nv)
	vnb.resize(nv)
	for v in nv:
		vfaces[v] = []
		vnb[v] = []
	for f in nf:
		for k in 4:
			(vfaces[quads[f * 4 + k]] as Array).append(f)
	for e in ne:
		(vnb[edge_a[e]] as Array).append(edge_b[e])
		(vnb[edge_b[e]] as Array).append(edge_a[e])
	for v in nv:
		var n := (vnb[v] as Array).size()
		var fl: Array = vfaces[v]
		if n < 3 or fl.size() != n:
			return {}
		var r := {}
		for f in fl:
			var fr: Dictionary = rows[nv + ne + f]
			for c in fr:
				r[c] = float(r.get(c, 0.0)) + float(fr[c]) / float(fl.size()) / float(n)
		for u in (vnb[v] as Array):
			r[v] = float(r.get(v, 0.0)) + 2.0 * 0.5 / float(n) / float(n)
			r[u] = float(r.get(u, 0.0)) + 2.0 * 0.5 / float(n) / float(n)
		r[v] = float(r.get(v, 0.0)) + float(n - 3) / float(n)
		rows[v] = r
	var rows_c: Array = []
	var rows_w: Array = []
	rows_c.resize(rows.size())
	rows_w.resize(rows.size())
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cs := PackedInt32Array()
		var ws := PackedFloat32Array()
		for c in r:
			cs.append(int(c))
			ws.append(float(r[c]))
		rows_c[i] = cs
		rows_w[i] = ws
	var nq := PackedInt32Array()
	nq.resize(nf * 16)
	var parent := PackedInt32Array()
	parent.resize(nf * 4)
	for f in nf:
		var fp := nv + ne + f
		for k in 4:
			var a := quads[f * 4 + k]
			var b := quads[f * 4 + (k + 1) % 4]
			var p := quads[f * 4 + (k + 3) % 4]
			var e1 := nv + int(edge_id[mini(a, b) * 1048576 + maxi(a, b)])
			var e0 := nv + int(edge_id[mini(p, a) * 1048576 + maxi(p, a)])
			var o := (f * 4 + k) * 4
			nq[o] = a
			nq[o + 1] = e1
			nq[o + 2] = fp
			nq[o + 3] = e0
			parent[f * 4 + k] = f
	return {"rows_c": rows_c, "rows_w": rows_w, "quads": nq, "nv": nv + ne + nf, "parent": parent}


## Aplikuje operátor na pole vektorů (pozice nebo výchylky morfu).
static func apply_vec3(op: Dictionary, src: PackedVector3Array) -> PackedVector3Array:
	var rc: Array = op["rows_c"]
	var rw: Array = op["rows_w"]
	var out := PackedVector3Array()
	out.resize(rc.size())
	for i in rc.size():
		var cs: PackedInt32Array = rc[i]
		var ws: PackedFloat32Array = rw[i]
		var acc := Vector3.ZERO
		for j in cs.size():
			acc += src[cs[j]] * ws[j]
		out[i] = acc
	return out


## Váhy kostí: vstup 4 kosti/vrchol (bones, weights po 4), výstup taky 4 (4 nejsilnější, normalizované).
static func apply_weights(op: Dictionary, bones: PackedInt32Array, weights: PackedFloat32Array) -> Dictionary:
	var rc: Array = op["rows_c"]
	var rw: Array = op["rows_w"]
	var ob := PackedInt32Array()
	var ow := PackedFloat32Array()
	ob.resize(rc.size() * 4)
	ow.resize(rc.size() * 4)
	for i in rc.size():
		var acc := {}
		var cs: PackedInt32Array = rc[i]
		var ws: PackedFloat32Array = rw[i]
		for j in cs.size():
			var v := cs[j]
			for k in 4:
				var w := weights[v * 4 + k] * ws[j]
				if w > 0.0:
					var b := bones[v * 4 + k]
					acc[b] = float(acc.get(b, 0.0)) + w
		var pairs := []
		for b in acc:
			pairs.append([float(acc[b]), int(b)])
		pairs.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
		var total := 0.0
		for k in mini(4, pairs.size()):
			total += float(pairs[k][0])
		for k in 4:
			if k < pairs.size() and total > 0.0:
				ob[i * 4 + k] = int(pairs[k][1])
				ow[i * 4 + k] = float(pairs[k][0]) / total
			else:
				ob[i * 4 + k] = 0
				ow[i * 4 + k] = 0.0
	return {"bones": ob, "weights": ow}


## Hladké normály vrcholů (plošně vážené) pro uzavřenou čtyřúhelníkovou síť s orientací CCW zvenku.
static func quad_normals(verts: PackedVector3Array, quads: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(verts.size())
	for f in quads.size() / 4:
		var a := quads[f * 4]
		var b := quads[f * 4 + 1]
		var c := quads[f * 4 + 2]
		var d := quads[f * 4 + 3]
		var fn := (verts[c] - verts[a]).cross(verts[d] - verts[b])
		n[a] += fn
		n[b] += fn
		n[c] += fn
		n[d] += fn
	for i in n.size():
		var l := n[i].length()
		n[i] = n[i] / l if l > 1e-12 else Vector3.UP
	return n
