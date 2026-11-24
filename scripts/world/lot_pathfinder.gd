extends RefCounted
## B3: shortest four-neighbour route on the authoritative LotGrid occupancy and wall edges.
## Grid coordinates refer to cells (not wall vertices). Empty result means no route.
static func find_path(lot: RefCounted, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if start.x < 0 or start.y < 0 or goal.x < 0 or goal.y < 0:
		return path
	if start.x >= lot.gw or goal.x >= lot.gw or start.y >= lot.gh or goal.y >= lot.gh:
		return path
	var first: int = start.y * lot.gw + start.x
	var target: int = goal.y * lot.gw + goal.x
	if not lot._walkable(first) or not lot._walkable(target):
		return path
	lot._build_edges({})
	var parent := PackedInt32Array()
	parent.resize(lot.gw * lot.gh)
	parent.fill(-1)
	parent[first] = first
	var queue := PackedInt32Array([first])
	var head := 0
	while head < queue.size() and parent[target] == -1:
		var i: int = queue[head]
		head += 1
		var x: int = i % lot.gw
		var z: int = int(i / lot.gw)
		var next: Array[int] = []
		if x > 0 and lot._vedge[z * (lot.gw + 1) + x] == 0:
			next.append(i - 1)
		if x + 1 < lot.gw and lot._vedge[z * (lot.gw + 1) + x + 1] == 0:
			next.append(i + 1)
		if z > 0 and lot._hedge[z * lot.gw + x] == 0:
			next.append(i - lot.gw)
		if z + 1 < lot.gh and lot._hedge[(z + 1) * lot.gw + x] == 0:
			next.append(i + lot.gw)
		for j in next:
			if parent[j] == -1 and lot._walkable(j):
				parent[j] = i
				queue.append(j)
	if parent[target] == -1:
		return path
	var at := target
	while at != first:
		path.push_front(Vector2i(at % lot.gw, int(at / lot.gw)))
		at = parent[at]
	path.push_front(start)
	return path
