extends RefCounted
const MAX_SEGMENTS := 256
static func validate(segments: Variant, width: int, height: int) -> String:
	if width < 1 or height < 1 or width > 40000 or height > 40000 or width * height > 40000:
		return "invalid_grid"
	if typeof(segments) != TYPE_ARRAY or segments.size() > MAX_SEGMENTS:
		return "invalid_segments"
	var seen := {}
	for s in segments:
		if typeof(s) != TYPE_DICTIONARY or s.size() != 4:
			return "invalid_segment"
		for k in ["x0", "z0", "x1", "z1"]:
			if not s.has(k) or typeof(s[k]) != TYPE_INT:
				return "invalid_segment"
		var x0: int = s["x0"]
		var z0: int = s["z0"]
		var x1: int = s["x1"]
		var z1: int = s["z1"]
		if x0 < 0 or x1 < 0 or z0 < 0 or z1 < 0 or x0 > width or x1 > width or z0 > height or z1 > height:
			return "out_of_bounds"
		if (x0 == x1) == (z0 == z1):
			return "not_axis_aligned"
		var a := Vector2i(x0,z0)
		var b := Vector2i(x1,z1)
		if b.x < a.x or b.y < a.y:
			var tmp := a
			a = b
			b = tmp
		var key := "%d,%d:%d,%d" % [a.x,a.y,b.x,b.y]
		if seen.has(key):
			return "duplicate"
		seen[key] = true

	var normalized: Array = []
	for s in segments:
		var a := Vector2i(s["x0"],s["z0"])
		var b := Vector2i(s["x1"],s["z1"])
		if b.x < a.x or b.y < a.y:
			var tmp := a
			a = b
			b = tmp
		for other in normalized:
			var c: Vector2i = other[0]
			var d: Vector2i = other[1]
			if a.y == b.y and c.y == d.y and a.y == c.y and maxi(a.x,c.x) < mini(b.x,d.x):
				return "overlap"
			if a.x == b.x and c.x == d.x and a.x == c.x and maxi(a.y,c.y) < mini(b.y,d.y):
				return "overlap"
			if a.y == b.y and c.x == d.x and a.x < c.x and c.x < b.x and c.y < a.y and a.y < d.y:
				return "crossing"
			if a.x == b.x and c.y == d.y and c.x < a.x and a.x < d.x and a.y < c.y and c.y < b.y:
				return "crossing"
		normalized.append([a,b])
	return ""
