extends RefCounted
## 3D hit testing for the household, independent of physics colliders.
## Ray-vs-local-AABB tests match actual furniture dimensions instead of
## requiring a click near one arbitrarily projected object-center point.
## Results are local UI candidates ONLY; NetSession remains command authority.

const BOXES := {
    "fridge": [Vector3(0, 1.0, 0), Vector3(0.90, 2.05, 0.85)],
    "stove": [Vector3(0, 0.5, 0), Vector3(0.96, 1.05, 0.80)],
    "tv": [Vector3(0, 0.75, 0), Vector3(1.85, 1.50, 0.56)],
    "sofa": [Vector3(0, 0.50, 0), Vector3(2.45, 1.02, 1.30)],
    "bookshelf": [Vector3(0, 1.0, 0), Vector3(1.54, 2.08, 0.65)],
    "bed": [Vector3(0, 0.55, 0), Vector3(1.85, 1.10, 2.24)],
    "shower": [Vector3(0, 1.1, 0), Vector3(1.28, 2.22, 1.28)],
    "treadmill": [Vector3(0, 0.70, 0), Vector3(0.96, 1.48, 2.04)],
}
const PERSON_CENTER := Vector3(0, 0.92, 0)
const PERSON_SIZE := Vector3(0.64, 1.84, 0.58)

# Returns ray distance (in *world metres*) or INF. Works for rotations,
# nonuniform object scale, cameras inside hitbox, and parallel rays.
static func _aabb_hit(node: Node3D, world_from: Vector3, world_dir: Vector3,
        local_center: Vector3, local_size: Vector3) -> float:
    var from: Vector3 = node.to_local(world_from)
    var direction: Vector3 = node.global_transform.basis.inverse() * world_dir
    var low: Vector3 = local_center - local_size * 0.5
    var high: Vector3 = local_center + local_size * 0.5
    var near_t := -INF
    var far_t := INF
    for axis in 3:
        var component := direction[axis]
        if absf(component) <= 0.000001:
            if from[axis] < low[axis] or from[axis] > high[axis]:
                return INF
        else:
            var a: float = (low[axis] - from[axis]) / component
            var b: float = (high[axis] - from[axis]) / component
            if a > b:
                var swap := a
                a = b
                b = swap
            near_t = maxf(near_t, a)
            far_t = minf(far_t, b)
            if far_t < near_t:
                return INF
    if far_t < 0.0:
        return INF
    return maxf(0.0, near_t)


static func pick(camera: Camera3D, objects: Array, sims: Array, screen: Vector2) -> Dictionary:
    if camera == null or not is_instance_valid(camera):
        return {}
    var viewport := camera.get_viewport()
    if viewport == null:
        return {}
    var sz: Vector2 = viewport.get_visible_rect().size
    if screen.x < 0.0 or screen.y < 0.0 or screen.x >= sz.x or screen.y >= sz.y:
        return {}
    var origin := camera.project_ray_origin(screen)
    var ray := camera.project_ray_normal(screen).normalized()
    var nearest := INF
    var best := {}
    for i in sims.size():
        var actor = sims[i]
        if actor == null or not is_instance_valid(actor):
            continue
        var t := _aabb_hit(actor, origin, ray, PERSON_CENTER, PERSON_SIZE)
        if t < nearest:
            nearest = t
            best = {"kind": "sim", "index": i, "distance": t}
    for i in objects.size():
        var obj = objects[i]
        if obj == null or not is_instance_valid(obj):
            continue
        var shape: Array = BOXES.get(String(obj.object_tag), [])
        if shape.is_empty():
            continue
        var box_center: Vector3 = shape[0]
        var box_size: Vector3 = shape[1]
        if obj.object_tag == "bed" and int(obj.capacity) == 1:
            box_size.x = 1.12
        var t := _aabb_hit(obj, origin, ray, box_center, box_size)
        if t < nearest:
            nearest = t
            best = {"kind": "object", "index": i, "distance": t}
    return best
