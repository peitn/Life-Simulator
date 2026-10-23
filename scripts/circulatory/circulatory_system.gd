# circulatory_system.gd
# Life Simulator — Circulatory System Phase 1 (skeleton)
# Author: Grok | 2026-10-23
# Deterministic 0D heart + circuits + basic bleeding/hemostasis + temperature

class_name CirculatorySystem
extends RefCounted

# ------------------------------------------------------------------
# Blood
# ------------------------------------------------------------------
class BloodState:
	var volume_ml: float = 5000.0
	var hematocrit: float = 0.45
	var viscosity_rel: float = 1.0
	var temperature_c: float = 37.0
	var o2_sat: float = 0.98
	var platelets_g_l: float = 250.0
	var fibrinogen_g_l: float = 3.0

	func update_viscosity() -> void:
		# Rough physiological approximation
		viscosity_rel = (1.0 + 2.5 * hematocrit) * (1.0 - 0.02 * (temperature_c - 37.0))
		viscosity_rel = clampf(viscosity_rel, 0.8, 4.0)


# ------------------------------------------------------------------
# Valve
# ------------------------------------------------------------------
class HeartValve:
	enum Kind { MITRAL, AORTIC, TRICUSPID, PULMONARY }

	var kind: Kind
	var area_cm2: float = 4.0
	var stenosis: float = 0.0          # 0–1
	var regurgitation: float = 0.0     # 0–1
	var calcification: float = 0.0     # 0–1

	func effective_area() -> float:
		return area_cm2 * (1.0 - stenosis) * (1.0 - 0.5 * calcification)


# ------------------------------------------------------------------
# Chamber
# ------------------------------------------------------------------
class HeartChamber:
	var volume_ml: float = 50.0
	var pressure_mmhg: float = 10.0
	var elastance_max: float = 2.5     # mmHg/ml
	var elastance_min: float = 0.08
	var unstressed_volume_ml: float = 15.0


# ------------------------------------------------------------------
# Heart
# ------------------------------------------------------------------
class Heart:
	var hr_bpm: float = 70.0
	var contractility: float = 1.0
	var chambers: Dictionary = {}      # "LV", "RV", "LA", "RA" -> HeartChamber
	var valves: Dictionary = {}        # Kind -> HeartValve

	# Defects
	var septal_defect_asd: float = 0.0
	var septal_defect_vsd: float = 0.0
	var systolic_dysfunction: float = 0.0
	var diastolic_dysfunction: float = 0.0

	var time_in_cycle: float = 0.0

	func _init() -> void:
		for name in ["LV", "RV", "LA", "RA"]:
			chambers[name] = HeartChamber.new()
		# Typical resting values (very rough)
		chambers["LV"].elastance_max = 2.8
		chambers["LV"].volume_ml = 120.0
		chambers["RV"].elastance_max = 0.6
		chambers["RV"].volume_ml = 120.0
		chambers["LA"].elastance_max = 0.4
		chambers["RA"].elastance_max = 0.3

		for k in HeartValve.Kind.values():
			var v := HeartValve.new()
			v.kind = k
			match k:
				HeartValve.Kind.MITRAL, HeartValve.Kind.TRICUSPID:
					v.area_cm2 = 4.5
				HeartValve.Kind.AORTIC, HeartValve.Kind.PULMONARY:
					v.area_cm2 = 3.5
			valves[k] = v

	func cycle_duration() -> float:
		return 60.0 / maxf(hr_bpm, 30.0)


# ------------------------------------------------------------------
# Circuit compartment (0D)
# ------------------------------------------------------------------
class CircuitNode:
	var name: String
	var volume_ml: float = 500.0
	var pressure_mmhg: float = 10.0
	var compliance: float = 2.0        # ml/mmHg
	var resistance: float = 1.0        # mmHg·s/ml
	var temperature_c: float = 37.0

	func _init(p_name: String) -> void:
		name = p_name


# ------------------------------------------------------------------
# Bleeding / wound
# ------------------------------------------------------------------
class BleedingPoint:
	var location: String = "torso"
	var vessel_type: String = "artery"   # artery | vein | capillary
	var size_cm2: float = 0.2
	var local_pressure_mmhg: float = 90.0
	var flow_ml_s: float = 0.0
	var thrombus_progress: float = 0.0
	var is_stopped: bool = false

	func update_bleed(delta: float, platelets: float) -> float:
		if is_stopped:
			flow_ml_s = 0.0
			return 0.0
		# Simple orifice-like bleeding
		var drive := maxf(local_pressure_mmhg, 0.0)
		flow_ml_s = 0.15 * size_cm2 * sqrt(drive) * (1.0 - thrombus_progress)
		# Platelet accumulation (very simplified)
		var shear_factor := 1.0 if vessel_type == "artery" else 0.6
		thrombus_progress += delta * 0.002 * (platelets / 250.0) * shear_factor * (1.0 - thrombus_progress)
		thrombus_progress = clampf(thrombus_progress, 0.0, 1.0)
		if thrombus_progress >= 0.95:
			is_stopped = true
			flow_ml_s = 0.0
		return flow_ml_s


# ------------------------------------------------------------------
# Main system
# ------------------------------------------------------------------
var blood: BloodState
var heart: Heart
var nodes: Dictionary = {}             # name -> CircuitNode
var wounds: Array[BleedingPoint] = []

var mean_arterial_pressure: float = 90.0
var cardiac_output_ml_s: float = 90.0  # ~5.4 L/min
var time_s: float = 0.0

# Targets / gains for simple baroreflex
var map_target: float = 90.0
var baroreflex_gain_hr: float = 0.8

func _init() -> void:
	blood = BloodState.new()
	heart = Heart.new()
	_setup_nodes()

func _setup_nodes() -> void:
	nodes["sys_art"] = CircuitNode.new("sys_art")
	nodes["sys_art"].compliance = 1.6
	nodes["sys_art"].resistance = 0.9
	nodes["sys_art"].pressure_mmhg = 90.0
	nodes["sys_art"].volume_ml = 800.0

	nodes["sys_ven"] = CircuitNode.new("sys_ven")
	nodes["sys_ven"].compliance = 50.0
	nodes["sys_ven"].resistance = 0.05
	nodes["sys_ven"].pressure_mmhg = 8.0
	nodes["sys_ven"].volume_ml = 3200.0

	nodes["pul_art"] = CircuitNode.new("pul_art")
	nodes["pul_art"].compliance = 4.0
	nodes["pul_art"].resistance = 0.1
	nodes["pul_art"].pressure_mmhg = 15.0
	nodes["pul_art"].volume_ml = 200.0

	nodes["pul_ven"] = CircuitNode.new("pul_ven")
	nodes["pul_ven"].compliance = 8.0
	nodes["pul_ven"].resistance = 0.03
	nodes["pul_ven"].pressure_mmhg = 8.0
	nodes["pul_ven"].volume_ml = 400.0


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------
func add_wound(location: String, vessel_type: String, size_cm2: float) -> void:
	var w := BleedingPoint.new()
	w.location = location
	w.vessel_type = vessel_type
	w.size_cm2 = size_cm2
	w.local_pressure_mmhg = nodes["sys_art"].pressure_mmhg if vessel_type == "artery" else nodes["sys_ven"].pressure_mmhg
	wounds.append(w)


func set_valve_defect(kind: HeartValve.Kind, stenosis: float = 0.0, regurgitation: float = 0.0) -> void:
	if heart.valves.has(kind):
		heart.valves[kind].stenosis = clampf(stenosis, 0.0, 1.0)
		heart.valves[kind].regurgitation = clampf(regurgitation, 0.0, 1.0)


func set_heart_rate(bpm: float) -> void:
	heart.hr_bpm = clampf(bpm, 30.0, 220.0)


# ------------------------------------------------------------------
# Main update (call every physics tick)
# ------------------------------------------------------------------
func update(delta: float) -> void:
	time_s += delta
	blood.update_viscosity()

	# --- Baroreflex (very simple) ---
	var map_error := map_target - mean_arterial_pressure
	heart.hr_bpm = clampf(70.0 + baroreflex_gain_hr * map_error, 40.0, 180.0)

	# --- Heart cycle timing ---
	var T := heart.cycle_duration()
	heart.time_in_cycle = fmod(heart.time_in_cycle + delta, T)
	var t_norm := heart.time_in_cycle / T
	var sys_duration := 0.35   # fraction of cycle that is systole (rough)

	# Elastance modulation (LV example)
	var e_lv := _elastance(t_norm, sys_duration,
		heart.chambers["LV"].elastance_min * (1.0 + heart.diastolic_dysfunction),
		heart.chambers["LV"].elastance_max * heart.contractility * (1.0 - heart.systolic_dysfunction))
	heart.chambers["LV"].pressure_mmhg = e_lv * maxf(heart.chambers["LV"].volume_ml - heart.chambers["LV"].unstressed_volume_ml, 0.0)

	# --- Simplified flows (placeholder – full valve orifice model comes next iteration) ---
	# For Phase 1 skeleton we keep cardiac output roughly stable and focus on volume & bleeding
	cardiac_output_ml_s = 90.0 * (heart.hr_bpm / 70.0) * heart.contractility

	# --- Windkessel systemic arteries ---
	var art: CircuitNode = nodes["sys_art"]
	var ven: CircuitNode = nodes["sys_ven"]
	var q_out := (art.pressure_mmhg - ven.pressure_mmhg) / maxf(art.resistance, 0.01)
	art.pressure_mmhg += delta * (cardiac_output_ml_s - q_out) / maxf(art.compliance, 0.1)
	mean_arterial_pressure = art.pressure_mmhg

	# --- Bleeding ---
	var total_bleed := 0.0
	for w in wounds:
		w.local_pressure_mmhg = art.pressure_mmhg if w.vessel_type == "artery" else ven.pressure_mmhg
		total_bleed += w.update_bleed(delta, blood.platelets_g_l)

	if total_bleed > 0.0:
		blood.volume_ml = maxf(blood.volume_ml - total_bleed * delta, 1500.0)
		# Losing warm blood cools the remaining volume slightly
		blood.temperature_c -= total_bleed * delta * 0.0008
		blood.temperature_c = maxf(blood.temperature_c, 30.0)

	# Very crude volume → pressure coupling for veins
	ven.volume_ml = blood.volume_ml * 0.65
	ven.pressure_mmhg = ven.volume_ml / maxf(ven.compliance, 1.0)


func _elastance(t_norm: float, sys_frac: float, e_min: float, e_max: float) -> float:
	if t_norm < sys_frac:
		var phase := t_norm / sys_frac
		return e_min + (e_max - e_min) * 0.5 * (1.0 - cos(PI * phase))
	return e_min


# ------------------------------------------------------------------
# Debug / inspection helpers
# ------------------------------------------------------------------
func get_status() -> Dictionary:
	return {
		"hr": heart.hr_bpm,
		"map": mean_arterial_pressure,
		"co_l_min": cardiac_output_ml_s * 0.06,
		"volume_ml": blood.volume_ml,
		"temp_c": blood.temperature_c,
		"wounds": wounds.size(),
		"bleeding": wounds.any(func(w): return not w.is_stopped),
	}
