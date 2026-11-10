extends RefCounted
## Diagnostika (běh 22): ohyb profilu (úhel mezi segmenty) podél svislých řezů mřížky hlavy při otevřené čelisti.
## QA 11/2026: přesunuto z res://previews/diag/ (neverzovaná pracovní složka), odkud ji test_face_detail
## načítal – mimo živý server test padal na chybě skriptu.
const HB := preload("res://scripts/assets/head_builder.gd")

static func chain(t, i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j in range(HB.NY, -1, -1):
		var key := "g,%d,%d,%d" % [i, j, HB.NZ]
		if t.index.has(key):
			out.append(t.index[key])
	for k in range(HB.NZ - 1, -1, -1):
		var key := "g,%d,0,%d" % [i, k]
		if t.index.has(key):
			out.append(t.index[key])
	return out

static func bends(p: PackedVector3Array, ch: PackedInt32Array) -> Array:
	var res: Array = []
	for n in range(1, ch.size() - 1):
		var a := p[ch[n]] - p[ch[n - 1]]
		var b := p[ch[n + 1]] - p[ch[n]]
		if a.length() < 1e-6 or b.length() < 1e-6:
			res.append(0.0)
			continue
		res.append(rad_to_deg(a.angle_to(b)))
	return res
