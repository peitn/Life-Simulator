extends RefCounted
## Offline Elmer FEM surrogate reader for anatomical research/debug UI.
## Values are derived from real ElmerSolver 26.2 VTU outputs (26 Oct 2026).
## DO NOT call this realtime (60Hz) biomechanical physics, or clinical data.
const SOURCE: String = "res://docs/anatomy/elmer-fem-results-v1.json"
const MAX_CARTILAGE_PRESSURE_PA: float = 40000.0
const MAX_BONE_TRACTION_PA: float = 100.0

static var _atlas: Dictionary = {}


static func read_atlas() -> Dictionary:
    if not _atlas.is_empty():
        return _atlas
    if not FileAccess.file_exists(SOURCE):
        return {}
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var table: Dictionary = raw
    if table.get("schema") != "life-simulator.anatomy.elmer-fem.v1":
        return {}
    if table.get("implementation", {}).get("live_gameplay_enabled", true):
        return {}
    _atlas = table
    return _atlas


static func _is_valid_load(value: float, maximum: float) -> bool:
    return is_finite(value) and value >= 0.0 and value <= maximum


## Estimate peak vector displacement in the *2D simplified patch*.
## `surface_vertical_displacement_m` is the vertical component at the point
## of maximum displacement MAGNITUDE. It is not the whole-field mean strain
## or the true height change of a finite-thickness 3D cartilage surface.
## Peak von Mises stress is deliberately NOT exposed because its corner values
## did not converge on mesh refinement.
static func cartilage_compression(pressure_pa: float, elastic_modulus_pa: float = 5000000.0) -> Dictionary:
    if not _is_valid_load(pressure_pa, MAX_CARTILAGE_PRESSURE_PA):
        return {"ok": false, "reason": "pressure_outside_validated_linear_range"}
    if not is_finite(elastic_modulus_pa) or elastic_modulus_pa < 2500000.0 or elastic_modulus_pa > 5000000.0:
        return {"ok": false, "reason": "modulus_outside_tested_elastic_range"}
    var table: Dictionary = read_atlas()
    if table.is_empty():
        return {"ok": false, "reason": "elmer_reference_unavailable"}
    var cases: Array = table.get("cartilage_compression", {}).get("cases", [])
    if cases.size() < 3:
        return {"ok": false, "reason": "elmer_cartilage_reference_missing"}
    var fine: Dictionary = cases.back()
    var reference_pressure: float = float(fine.get("pressure_pa", 0.0))
    if reference_pressure <= 0:
        return {"ok": false, "reason": "invalid_reference_pressure"}
    var reference_e: float = float(table["cartilage_compression"]["elastic_modulus_pa"])
    var factor: float = (pressure_pa / reference_pressure) * (reference_e / elastic_modulus_pa)
    var u_at_max: Array = fine.get("max_displacement_vector_m", [0.0, 0.0, 0.0])
    return {
        "ok": true,
        "reference": "ElmerSolver_26.2_cartilage_ultrafine_120x24",
        "pressure_pa": pressure_pa,
        "elastic_modulus_pa": elastic_modulus_pa,
        "max_vector_displacement_m": factor * float(fine["max_displacement_m"]),
        "vertical_displacement_at_vector_max_m": factor * float(u_at_max[1]),
        "lateral_displacement_at_vector_max_m": factor * float(u_at_max[0]),
        "mesh_refinement_120x24": true,
        "peak_stress_usable": false,
        "offline_lookup_only": true,
        "live_ragdoll_physics": false,
        "source_units": "SI_m_kg_s_N_Pa"
    }


## 2D cortical-like rectangular cantilever under downward EDGE TRACTION.
## The reference -100 Pa (not -100 newtons) integrates to 1.5 N per unit
## extrusion thickness on the 15 mm high free edge. Not a fracture model.
static func bone_cantilever(downward_traction_pa: float) -> Dictionary:
    if not _is_valid_load(downward_traction_pa, MAX_BONE_TRACTION_PA):
        return {"ok": false, "reason": "traction_outside_validated_linear_range"}
    var table: Dictionary = read_atlas()
    if table.is_empty():
        return {"ok": false, "reason": "elmer_reference_unavailable"}
    var cases: Array = table.get("bone_cantilever", {}).get("cases", [])
    if cases.size() != 3:
        return {"ok": false, "reason": "elmer_bone_reference_missing"}
    var finest: Dictionary = cases[2]
    var ref: float = float(table["bone_cantilever"]["boundary"]["traction_downward_pa"])
    if ref <= 0:
        return {"ok": false, "reason": "invalid_reference_traction"}
    var v: Array = finest.get("max_displacement_vector_m", [0.0, 0.0, 0.0])
    var scale: float = downward_traction_pa / ref
    return {
        "ok": true,
        "reference": "ElmerSolver_26.2_cortical_cantilever_60x16",
        "traction_pa": downward_traction_pa,
        "force_per_unit_extrusion_n_per_m": scale * 1.5,
        "max_vector_displacement_m": float(finest["max_displacement_m"]) * scale,
        "vertical_displacement_at_vector_max_m": float(v[1]) * scale,
        "analytic_euler_bernoulli_m": float(table["bone_cantilever"]["analytic_euler_bernoulli"]["tip_abs_displacement_m"]) * scale,
        "offline_lookup_only": true,
        "live_ragdoll_physics": false
    }


## An explicit integration boundary, so developers do not accidentally
## replace the existing authenticated multiplayer rigid-body authority.
static func live_physics_enabled() -> bool:
    return false