extends RefCounted
## Minimal, deterministic pedestrian detour around the static dining tabletop.
## This is not a general navmesh; the no-collision table previously cut through
## moving human silhouettes. Same route is used on authority and test clients.
const TABLE := Rect2(-3.8, -1.85, 1.6, 0.9)
const CLEARANCE := 0.34

static func _inside(p: Vector2, bounds: Rect2) -> bool:
    return p.x > bounds.position.x and p.x < bounds.end.x and p.y > bounds.position.y and p.y < bounds.end.y

static func _crosses_interior(a: Vector2, b: Vector2, rect: Rect2) -> bool:
    # Segment / interior AABB clipping. Shrink a fraction for border travel.
    var r := rect.grow(-0.005)
    if _inside(a, r) or _inside(b, r):
        return true
    var d := b - a
    var lo := 0.0
    var hi := 1.0
    for axis in 2:
        var pos := a[axis]
        var v := d[axis]
        var lower := r.position[axis]
        var upper := r.end[axis]
        if absf(v) <= 0.000001:
            if pos <= lower or pos >= upper:
                return false
        else:
            var t0 := (lower - pos) / v
            var t1 := (upper - pos) / v
            if t0 > t1:
                var tmp := t0
                t0 = t1
                t1 = tmp
            lo = maxf(lo, t0)
            hi = minf(hi, t1)
            if lo >= hi:
                return false
    return lo < hi and hi > 0.0 and lo < 1.0


static func waypoint(start: Vector3, goal: Vector3) -> Vector3:
    var a := Vector2(start.x, start.z)
    var b := Vector2(goal.x, goal.z)
    var enlarged := TABLE.grow(CLEARANCE)
    if _inside(a, enlarged) or _inside(b, enlarged):
        # Allow exiting from chair or bed placement without trapping the actor.
        return goal
    if not _crosses_interior(a, b, enlarged):
        return goal
    var corners := [
        enlarged.position + Vector2(-0.02, -0.02),
        Vector2(enlarged.end.x + 0.02, enlarged.position.y - 0.02),
        enlarged.end + Vector2(0.02, 0.02),
        Vector2(enlarged.position.x - 0.02, enlarged.end.y + 0.02),
    ]
    # Visibility graph of start, goal and all four padded corners.
    # Crossing opposite sides can require TWO corners, never go straight
    # through the table when a one-corner path is unavailable.
    var nodes: Array[Vector2] = [a, b]
    for c in corners:
        nodes.append(c)
    var dist: Array[float] = [0.0, INF, INF, INF, INF, INF]
    var prev: Array[int] = [-1, -1, -1, -1, -1, -1]
    var visited := [false, false, false, false, false, false]
    for it in nodes.size():
        var cur := -1
        for i in nodes.size():
            if not visited[i] and (cur < 0 or dist[i] < dist[cur]):
                cur = i
        if cur < 0 or is_inf(dist[cur]):
            break
        if cur == 1:
            break
        visited[cur] = true
        for j in nodes.size():
            if j == cur or visited[j] or _crosses_interior(nodes[cur], nodes[j], enlarged):
                continue
            var candidate: float = dist[cur] + nodes[cur].distance_to(nodes[j])
            if candidate < dist[j]:
                dist[j] = candidate
                prev[j] = cur
    if prev[1] < 0:
        # Fail closed: don't produce a shortcut through the tabletop.
        return start
    var step := 1
    while prev[step] > 0:
        step = prev[step]
    var next: Vector2 = nodes[step]
    return Vector3(next.x, goal.y, next.y)
