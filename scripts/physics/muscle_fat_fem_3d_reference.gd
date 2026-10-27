extends RefCounted
## Read-only offline 3D ElmerFEM verification for the two-volume 35x12x10 mm
## rectangular muscle/fat block. Source data are actual solver VTU results.
## NOT a solve on the anatomically sculpted Blender mesh and NOT live NPC
## thermoregulation, damage mechanics, blood transport or muscle contraction.
const SOURCE := "res://docs/anatomy/elmer_muscle_fat_3d_v1.json"
const EXPECTED_SCHEMA := "lifesim.fem.musclefat.3d.v1"
const APPROVED_CASES := [
    "lifesim_mfat_3d_heat_coarse_c11",
    "lifesim_mfat_3d_heat_fine_c11",
    "lifesim_mfat_3d_active_c11",
    "lifesim_mfat_3d_transient_c11",
    "lifesim_mfat_3d_mech_c11"
]
static var _cache: Dictionary = {}

static func evidence() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    if not FileAccess.file_exists(SOURCE):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var data: Dictionary = parsed
    if data.get("schema") != EXPECTED_SCHEMA or data.get("solver") != "ElmerSolver 26.2":
        return {}
    var flags: Dictionary = data.get("limitations", {})
    if not bool(flags.get("actual_3D_hex8_FEM_solved", false)):
        return {}
    if not bool(flags.get("actual_anatomy_Blendermodel_geometry_solved", true)):
        _cache = data
    return _cache


static func model_is_live_gameplay() -> bool:
    return false


## Explicitly named, bounded *record retrieval*: never fabricates time or
## pressure extrapolations from a single solved 3D grid.
static func solved_case(name: String) -> Dictionary:
    if not APPROVED_CASES.has(name):
        return {"ok": false, "reason": "no_verified_3D_solve_for_request"}
    var d: Dictionary = evidence()
    if d.is_empty():
        return {"ok": false, "reason": "3D_FEM_evidence_unavailable"}
    for item in d.get("cases", []):
        if String(item.get("name", "")) == name:
            var copied: Dictionary = item.duplicate(true)
            copied["ok"] = true
            copied["scope"] = "offline_3D_flat_two_tissue_slab_not_Blendermodel"
            copied["live_physics"] = false
            return copied
    return {"ok": false, "reason": "unknown_source_case"}


static func comparison_with_1d_rest() -> Dictionary:
    var case3d: Dictionary = solved_case("lifesim_mfat_3d_heat_fine_c11")
    if not case3d.get("ok", false):
        return case3d
    var d: Dictionary = evidence()
    var target: float = float(d.get("thermal", {}).get("analytic_1d_rest_surface_K", NAN))
    if not is_finite(target):
        return {"ok": false, "reason": "no_analytic_reference"}
    var actual: float = float(case3d.get("min_K", NAN))
    return {
        "ok": is_finite(actual),
        "verified_grid_nodes": int(case3d.get("points", -1)),
        "computed_kelvin": actual,
        "analytic_kelvin": target,
        "absolute_error_kelvin": absf(actual-target),
        "model_not_actual_anatomical_geometry": true,
        "medical_model": false
    }
