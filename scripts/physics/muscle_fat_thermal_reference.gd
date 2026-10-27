extends RefCounted
## ElmerSolver-validated OFFLINE SI reference: 2D aligned muscle+fat patch.
## No live avatar thermoregulation, circulation, injury, metabolism network,
## active muscle contraction or full 3D soft-tissue solver is implied.
const SOURCE := "res://docs/anatomy/elmer_muscle_fat_v1.json"
const CORE_T_K := 310.15
const AMBIENT_T_K := 293.15
const H_SURFACE := 10.0
const KM := 0.5
const KF := 0.2
const LM := 0.025
const Q_FAT := 60.0
const MIN_FAT_M := 0.010
const MAX_FAT_M := 0.020
const MIN_QM_W_M3 := 700.0
const MAX_QM_W_M3 := 5000.0

static var _cached: Dictionary = {}


static func atlas() -> Dictionary:
    if not _cached.is_empty():
        return _cached
    if not FileAccess.file_exists(SOURCE):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if typeof(value) != TYPE_DICTIONARY:
        return {}
    var parsed: Dictionary = value
    if parsed.get("schema") != "lifesim.fem.musclefat.v1" or parsed.get("solver") != "ElmerSolver 26.2":
        return {}
    var flags: Dictionary = parsed.get("flags", {})
    if flags.get("live_gameplay_physics", true) or flags.get("medical_model", true):
        return {}
    _cached = parsed
    return _cached


static func is_production_physics() -> bool:
    return false


## 1D analytical steady-state heat equation with volumetric source in each
## layer and convection on exposed face. Verified at 3 distinct parameter
## combinations against actual Elmer 2D solution, NOT a full body heat field.
static func steady_reference(muscle_heat_w_m3: float, fat_thickness_m: float) -> Dictionary:
    if not is_finite(muscle_heat_w_m3) or not is_finite(fat_thickness_m):
        return {"ok": false, "reason": "nonfinite"}
    if muscle_heat_w_m3 < MIN_QM_W_M3 or muscle_heat_w_m3 > MAX_QM_W_M3:
        return {"ok": false, "reason": "outside_tested_muscle_heat_range"}
    if fat_thickness_m < MIN_FAT_M or fat_thickness_m > MAX_FAT_M:
        return {"ok": false, "reason": "outside_tested_fat_thickness_range"}
    if atlas().is_empty():
        return {"ok": false, "reason": "no_elmer_reference"}
    var q: float = muscle_heat_w_m3
    var f: float = fat_thickness_m
    var resistance: float = LM / KM + f / KF + 1.0 / H_SURFACE
    var core_flux: float = (CORE_T_K - AMBIENT_T_K - q * LM * LM / (2.0 * KM)
        - q * LM * f / KF - Q_FAT * f * f / (2.0 * KF)
        - (q * LM + Q_FAT * f) / H_SURFACE) / resistance
    var interface_flux: float = core_flux + q * LM
    var outer_flux: float = interface_flux + Q_FAT * f
    var skin_K: float = AMBIENT_T_K + outer_flux / H_SURFACE
    var tissue_interface_K: float = CORE_T_K - (core_flux * LM + q * LM * LM * 0.5) / KM
    var max_interior_K: float = maxf(CORE_T_K, skin_K)
    if core_flux < 0.0 and interface_flux > 0.0:
        max_interior_K = maxf(max_interior_K,
            CORE_T_K + core_flux * core_flux / (2.0 * KM * q))
    return {
        "ok": true,
        "core_temperature_K": CORE_T_K,
        "skin_temperature_K": skin_K,
        "skin_temperature_C": skin_K - 273.15,
        "muscle_fat_interface_K": tissue_interface_K,
        "maximum_temperature_K": max_interior_K,
        "outward_heat_flux_W_m2": outer_flux,
        "muscle_heat_source_W_m3": q,
        "fat_heat_source_W_m3": Q_FAT,
        "fat_thickness_m": f,
        "insulating_resistance_m2K_W": resistance,
        "model_type": "validated_1d_analytic_against_Elmer_2d_not_real_body",
        "live_physics": false
    }


## The last of 12 actual 60s BDF time steps, starting from uniform core T.
## Not a continuous realtime/medical temperature curve; no time extrapolation.
static func transient_twelve_minute_reference() -> Dictionary:
    var info: Dictionary = atlas()
    if info.is_empty():
        return {"ok": false}
    for c in info.get("cases", []):
        if c.get("name") == "lifesim_mfat_thermal_transient_t10":
            return {
                "ok": true,
                "elapsed_seconds": 720.0,
                "initial_temperature_K": 310.15,
                "min_temperature_K": float(c.get("temperature_min_at_12min_K", NAN)),
                "max_temperature_K": float(c.get("temperature_max_at_12min_K", NAN)),
                "heat_capacity_was_solved": true,
                "live_physics": false
            }
    return {"ok": false}


## Elmer 2D passive pressure test, same muscle/fat reference dimensions.
## Returns 2D max *vector magnitude*; not vertical skin movement, not
## contraction or tendon forces. This is a bounded linear material case.
static func passive_skin_compression(pressure_pa: float) -> Dictionary:
    if not is_finite(pressure_pa) or pressure_pa < 0.0 or pressure_pa > 100.0:
        return {"ok": false, "reason": "pressure_outside_tested_range"}
    var info: Dictionary = atlas()
    if info.is_empty():
        return {"ok": false}
    for c in info.get("cases", []):
        if c.get("name") == "lifesim_mfat_mech_t10":
            var factor: float = pressure_pa / 100.0
            return {
                "ok": true,
                "pressure_pa": pressure_pa,
                "max_vector_displacement_m": factor * float(c["measured_max_vector_displacement_m"]),
                "reference_1d_series_displacement_m": factor * float(c["uniaxial_series_analytic_m"]),
                "live_ragdoll": false,
                "muscle_contraction": false
            }
    return {"ok": false}
