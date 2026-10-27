extends RefCounted
## H2b sleeve-to-shell vertex proximity regression AFTER the legacy shoulder
## ring corrective. This metric overestimates the actual triangle distance,
## so it is deliberately not a watertightness certificate.
const WARDROBE = preload("res://scripts/assets/clothing_wardrobe.gd")

static func _nearest(point: Vector3, shell: PackedVector3Array) -> float:
    var best := INF
    for v in shell:
        best = minf(best, point.distance_to(v))
    return best

static func _rim_gaps(sleeve: PackedVector3Array, shell: PackedVector3Array) -> Array:
    var y := -INF
    for v in sleeve:
        y = maxf(y, v.y)
    var gaps: Array = []
    for v in sleeve:
        if v.y >= y - 0.001:
            gaps.append(_nearest(v, shell))
    gaps.sort()
    return gaps

static func run() -> Dictionary:
    var checks := 0
    var failed: Array = []
    var report: Array = []
    for style in ["kawaii_kocici_mikina", "mikina"]:
        var meshes := {}
        for part in WARDROBE.parts("top", style):
            if str(part.name) in ["shell", "sleeve_-1", "sleeve_1"]:
                meshes[str(part.name)] = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        checks += 1
        if meshes.size() != 3:
            failed.append(style + ": missing authored shell/sleeves")
            continue
        var shell: PackedVector3Array = meshes["shell"]
        checks += 1
        if shell.size() != 830:
            failed.append(style + ": unexpected shell vertex count")
        var medians := []
        for side in ["sleeve_-1", "sleeve_1"]:
            var sleeve: PackedVector3Array = meshes[side]
            var gaps := _rim_gaps(sleeve, shell)
            checks += 1
            if gaps.size() != 14:
                failed.append(style + "/" + side + ": unexpected upper-rim vertex count")
                continue
            var median: float = gaps[gaps.size() / 2]
            medians.append(median)
            checks += 1
            if median < 0.009 or median > 0.016:
                failed.append(style + "/" + side + ": baseline changed; re-inspect join")
            checks += 1
            if gaps.back() > 0.025:
                failed.append(style + "/" + side + ": outlier distance exceeds characterization")
            report.append({"style":style,"side":side,"rim_vertices":gaps.size(),"min_m":gaps.front(),"median_m":median,"max_m":gaps.back()})
        checks += 1
        if medians.size() != 2 or absf(medians[0] - medians[1]) > 0.001:
            failed.append(style + ": asymmetric upper-rim proximity")
        # In-memory sensitivity fixture: a point exactly at a shell vertex must
        # yield zero. This does NOT alter authored meshes or production assets.
        checks += 1
        if _nearest(shell[0], shell) > 0.000001:
            failed.append(style + ": nearest-vertex metric broken")
    return {"ok":failed.is_empty(),"checks":checks,"failures":failed,"measurements":report,
        "scope":"vertex-only corrected rest baseline; skinned pose surface checked separately"}