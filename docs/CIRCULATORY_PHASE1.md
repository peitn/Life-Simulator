# Life Simulator — Circulatory System Phase 1

**Status:** Design + data model (ready for implementation)  
**Author:** Grok  
**Date:** 2026-10-23  
**Scope:** Real-time 0D heart + systemic/pulmonary circuits, valves with defects, basic bleeding + platelet hemostasis, blood temperature, HR variability.  
**Goal:** Playable, deterministic, testable foundation that later expands to full perfusion zones, advanced coagulation, 1D wave propagation, and thermoregulation coupling.

---

## 1. Design principles

- Deterministic (same seed → same behaviour).
- Server-authoritative; private state (blood values, defects) visible only to owner + medical roles.
- One update tick ≈ 0.05–0.1 s real time (or accelerated).
- All volumes in ml, pressures in mmHg, flows in ml/s, temperatures in °C.
- No full 3D CFD at runtime. Elmer is for offline calibration only.
- Agency preserved: player actions (movement, stress, injury) affect the system; the system does not lock the player.

---

## 2. Core data structures (GDScript-oriented)

### BloodState
```gdscript
class_name BloodState
# Global + core blood properties
var volume_ml: float = 5000.0          # total blood volume
var hematocrit: float = 0.45           # 0–1
var viscosity_rel: float = 1.0         # relative to water at 37 °C
var temperature_c: float = 37.0        # core blood temperature
var o2_sat: float = 0.98               # 0–1
var co2_content: float = 0.48          # rough
var platelets_g_l: float = 250.0       # ×10^9/L typical range 150–400
var fibrinogen_g_l: float = 3.0
# Derived
func update_viscosity() -> void:
    # Simple: viscosity rises with HCT and falls with temperature
    viscosity_rel = (1.0 + 2.5 * hematocrit) * (1.0 - 0.02 * (temperature_c - 37.0))
```

### Valve
```gdscript
class_name HeartValve
enum Kind { MITRAL, AORTIC, TRICUSPID, PULMONARY }
var kind: Kind
var area_cm2: float = 4.0              # effective opening area
var stenosis: float = 0.0              # 0 = none, 1 = critical
var regurgitation: float = 0.0         # 0–1 fraction of reverse flow
var calcification: float = 0.0         # increases resistance to opening
# Effective area after defects
func effective_area() -> float:
    return area_cm2 * (1.0 - stenosis) * (1.0 - 0.5 * calcification)
```

### HeartChamber
```gdscript
class_name HeartChamber
var volume_ml: float
var pressure_mmhg: float
var elastance_max: float               # contractility proxy
var elastance_min: float
var unstressed_volume_ml: float
```

### Heart (0D)
```gdscript
class_name Heart
var hr_bpm: float = 70.0
var contractility: float = 1.0         # multiplier
var chambers: Dictionary               # "LV", "RV", "LA", "RA"
var valves: Dictionary                 # Kind -> HeartValve
# Timing
var cycle_time_s: float = 60.0 / hr_bpm
var time_in_cycle: float = 0.0
# Defects (flags + severity)
var septal_defect_asd: float = 0.0     # 0–1 shunt fraction
var septal_defect_vsd: float = 0.0
var systolic_dysfunction: float = 0.0  # reduces elastance_max
var diastolic_dysfunction: float = 0.0 # raises elastance_min
```

### CircuitNode (0D compartment)
```gdscript
class_name CircuitNode
var name: String
var volume_ml: float
var pressure_mmhg: float
var compliance_ml_per_mmhg: float
var resistance_mmhg_s_per_ml: float    # outflow resistance
var temperature_c: float = 37.0
```

### VascularNetwork (simplified Phase 1)
- Systemic arteries (Windkessel)
- Systemic veins
- Pulmonary arteries
- Pulmonary veins
- (Later: organ perfusion zones)

### Wound / BleedingPoint
```gdscript
class_name BleedingPoint
var location: String                   # "arm", "leg", "torso", "head"...
var vessel_type: String                # "artery", "vein", "capillary"
var size_cm2: float                    # wound opening
var pressure_mmhg: float               # local driving pressure
var flow_ml_s: float = 0.0             # current bleeding rate
var thrombus_progress: float = 0.0     # 0–1
var platelets_recruited: float = 0.0
var is_stopped: bool = false
```

### CirculatorySystem (main)
```gdscript
class_name CirculatorySystem
var blood: BloodState
var heart: Heart
var nodes: Dictionary                  # name -> CircuitNode
var wounds: Array[BleedingPoint] = []
var mean_arterial_pressure: float
var cardiac_output_ml_s: float
var time_s: float = 0.0
```

---

## 3. Core equations (Phase 1)

### Heart cycle (simplified elastance model)
Time-varying elastance for LV/RV:

\[
E(t) = E_{\min} + \frac{E_{\max} - E_{\min}}{2} \cdot (1 - \cos(2\pi \frac{t}{T_{sys}})) \quad \text{for } t < T_{sys}
\]

\[
E(t) = E_{\min} \quad \text{otherwise}
\]

Pressure in chamber:

\[
P = E(t) \cdot (V - V_0)
\]

Flow through valve (simple orifice):

\[
Q = C_d \cdot A_{\text{eff}} \cdot \sqrt{\frac{2 |\Delta P|}{\rho}} \cdot \operatorname{sign}(\Delta P)
\]

(with regurgitation allowing reverse when valve should be closed).

### Windkessel (systemic arteries)
\[
C \frac{dP}{dt} = Q_{in} - \frac{P - P_{vein}}{R}
\]

### Blood volume balance
Total volume conserved except for bleeding and (later) fluid shifts.

### Bleeding rate
\[
Q_{bleed} = k \cdot size \cdot \sqrt{P_{local}} \cdot (1 - thrombus\_progress)
\]

### Primary hemostasis (platelets)
Simple accumulation:

\[
\frac{d\,thrombus}{dt} = k_p \cdot platelets \cdot shear\_factor \cdot (1 - thrombus)
\]

When thrombus ≥ 0.95 → bleeding stops (with possible re-bleed if pressure spikes or movement).

### Temperature
Core blood temperature slowly exchanges with tissue and environment via perfusion (Phase 1: simple Newton cooling + metabolic heat). Full perfusion-zone heat transport comes in Phase 2.

### Baroreflex (very simple)
\[
HR = HR_0 + G \cdot (MAP_{target} - MAP)
\]
clamped to physiological range; also mild effect on contractility and venous tone.

---

## 4. Phase 1 deliverables (implementation checklist)

1. `BloodState`, `HeartValve`, `HeartChamber`, `Heart`, `CircuitNode`, `BleedingPoint`, `CirculatorySystem` classes.
2. Deterministic update loop (`_physics_process` or fixed tick).
3. Four valves with stenosis / regurgitation / area parameters.
4. Basic defects: ASD/VSD shunt, systolic & diastolic dysfunction.
5. Variable HR + simple baroreflex.
6. Systemic + pulmonary 0D circuits.
7. Wound creation → bleeding → platelet thrombus → stop.
8. Blood temperature (core) with simple loss on bleeding.
9. Unit tests: conservation of volume (no wounds), steady-state MAP ~ 90 mmHg at rest, valve stenosis raises afterload, bleeding reduces volume and MAP, thrombus eventually stops flow.
10. Content toggles / severity scales for medical accuracy vs. gameplay.
11. Multiplayer: private replication of full state; public only “is bleeding / is in shock” flags if desired.

---

## 5. Later phases (reservoir)

- Organ perfusion zones (brain, heart, muscle, skin, splanchnic…)
- 1D arterial tree (pressure wave, pulse transit time)
- Advanced coagulation cascade + fibrinolysis
- Full thermoregulation (skin blood flow, sweating, shivering)
- Drugs, shock stages, transfusion, clotting disorders
- Coupling to MentalState (anxiety → HR/vasoconstriction) and Needs (O₂, temperature)

---

## 6. Integration notes for Life Simulator

- Attach `CirculatorySystem` to character (or as component on CharacterData).
- Injury system creates `BleedingPoint`.
- Stress / panic / pain modulate HR and vascular tone.
- Long-term valve disease or heart failure → reduced max exertion, higher fatigue, possible mood impact.
- Medical examination / blood test can reveal values (with privacy rules).

---

This document is the authoritative Phase 1 specification.  
Implementation should stay inside these boundaries until the milestone is closed and tested.
