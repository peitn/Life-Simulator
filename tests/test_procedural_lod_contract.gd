extends RefCounted
## Isolated procedural LOD input regression: geometry builders without a character scene.
const Hand = preload("res://scripts/assets/hand_detail_builder.gd")
const Foot = preload("res://scripts/assets/foot_detail_builder.gd")
const Torso = preload("res://scripts/assets/torso_detail_builder.gd")

static func run() -> Dictionary:
    var checks := 0
    var failures: Array[String] = []
    var hand := Hand._blank()
    var nails := Hand._blank()
    var endpoints: Dictionary = Hand.finger_endpoints(0)
    Hand._finger(hand, nails, endpoints["root"], endpoints["tip"], 0.0054, 13, -1.0, false)
    for item in [{"name":"hand", "data":hand}, {"name":"nails", "data":nails}]:
        var d: Dictionary = item["data"]
        var vertices: PackedVector3Array = d["vertices"]
        var indices: PackedInt32Array = d["indices"]
        checks += 1
        if vertices.size() < 3 or indices.size() < 3 or indices.size() % 3 != 0:
            failures.append(str(item["name"]) + ": invalid geometry")
        checks += 1
        if (d["bones"] as PackedInt32Array).size() != vertices.size() * 4 or (d["weights"] as PackedFloat32Array).size() != vertices.size() * 4:
            failures.append(str(item["name"]) + ": skinning length")
        for idx in indices:
            checks += 1
            if idx < 0 or idx >= vertices.size():
                failures.append(str(item["name"]) + ": index out of bounds")
                break
    var foot := Hand._blank()
    Foot._sole(foot, 0.1, 10)
    checks += 1
    if (foot["vertices"] as PackedVector3Array).size() < 100 or (foot["indices"] as PackedInt32Array).is_empty():
        failures.append("foot sole geometry")
    var torso := Hand._blank()
    Torso._disc(torso, Vector3(0, 1.1, 0.1), 0.01, 0.015, 0.002, 1)
    checks += 1
    if (torso["vertices"] as PackedVector3Array).size() != 33 or (torso["indices"] as PackedInt32Array).is_empty():
        failures.append("torso disc geometry")
    return {"ok": failures.is_empty(), "checks": checks, "failures": failures}
