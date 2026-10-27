# C10 anatomy milestone: sculptural skeleton/muscle visuals + Elmer muscle/fat thermodynamics
**Executed in canonical `lifesim` and connected Blender/Elmer, 26 October 2026.**
Run ID: `main-anatomy-musclefat-1793049284-284701`, cooperative main project lock; city directories untouched, no GitHub push.

## Scope and honest claims
- Existing editable standalone Blender asset: `lifesim-anatomy-skeleton-v1`. Actual `.blend` preserved and reopened after changes.
- **Not** a fully accurate 206-bone or patient-specific anatomy; **not** dynamic muscle fiber actuation; **not** FEA on the Blender 3D bone, muscle or fat geometries. It is reference-quality approximate graphics + **real Elmer 2D two-material heat and passive stress solves**.
- Godot's production 17-bone characters, authenticated owner controls, savegame schema and household/city paths were **not changed**.
- Existing 17 Blender Bullet rigid proxies and 16 constraints were preserved; not coupled to Elmer or live Godot.

## Blender visual pass v0.2 — real geometry, actual Cycles renders
Generator: `tools/blender/anatomy_visual_soft_tissue_v2.py`, one-shot upgrade of the standalone `.blend`; follow with `tools/blender/anatomy_attach_musclefat_thermal_v1.py` for FEM metadata.
- Replaced geometry of **24 previously straight rib rods** with anatomically inspired **curved swept arc meshes**, preserving each corresponding bone's 100% armature skin. Added **72 vertebral posterior processes** around the previously linear 24 cervical/thoracic/lumbar segment proxies.
- All **60 muscle bundles** received Catmull–Clark smooth surfaces and fibrous procedural noise/bump material. They remain simplified fusiform volumes with approximate origins and insertions, not accurate myofascial atlas meshes.
- Added **6 separate manifold closed-shell subcutaneous fat 3D volumes** (waist, hips, 2 thighs, 2 upper arms), each with inner/outer/capped surfaces, thickness, density, conductivity, heat capacity, and correctly weighted reference rig bone. Added 2 fascia reference surfaces. The fat layers are visually translucent and have their own separately exported `anatomy_adipose_v2.glb`. This is actual modeling, not just color overlay.
- **Lighting bug found and fixed** during actual rendering: original Blender `Anatomy_Presentation` collection was hidden from render, inadvertently hiding the AREA lights. First resulting previews were too dark; reenabled lighting and rerendered every illustration with 24 Cycles samples.
- Five new *actually rendered, inspected* PNGs in the Blender model library:
  - `anatomy_skeletal_curved_ribs_v2.png`
  - `anatomy_muscular_fibers_v2.png`
  - `anatomy_muscle_with_adipose_v2.png`
  - `anatomy_full_anatomy_exploded_v2.png`
  - `anatomy_elmer_muscle_fat_thermal_diagnostic_v1.png` (three isolated **flat diagnostic cross-sections**, not body temperature field).
- The thermal diagnostic illustration has visible text labels, materials and real separated muscle/adipose color gradient. Initial text wasn't lit in its isolated collection; changed labels to emission and re-rendered.
- Blender reopened final saved `.blend`: **194 bone controls, 60 muscle meshes, 6 manifold hollow adipose volumes (0 nonmanifold edges), 17 rigid bodies, 16 constraints**, all persisted. Separate adipose GLB re-import produced **six physical meshes**.
- 3D shape/rig visuals still stylized. Full anatomical musculotendon volumes, detailed fascia networks, accurate bone silhouettes, thickness/morph sliders and render/physics skin collision checks remain open.

## ElmerFEM real solves v26.2: steady bioheat, transient heat and passive mechanics

**All 6 isolated cases solved with ElmerSolver exit 0**; their Elmer case folders contain `case.sif`, a genuine custom 2-domain conforming quad mesh (`mesh.header/nodes/elements/boundary`) and `case_t0001.vtu` with actual fields. Seven if the initial simple homogeneous heat-template smoke case is counted, but the production research set consists of the six named cases below.

### Tissue domain and SI properties
- **One 2D conforming rectangular cross-section**, along x from fixed core through 25 mm muscle to 10 mm adipose, or 20 mm adipose in thickness scenario; width in transverse y = 12 mm. Different Elmer element body ID 1 = muscle, ID 2 = fat, shared nodes on the exact material interface.
- Muscle: k = **0.50 W/(m K)**, density **1050 kg/m³**, Cp **3750 J/(kg K)**, metabolic source rest **700 W/m³**, illustrative active **5000 W/m³**, and passive 2D isotropic E = **30 kPa**.
- Fat: k = **0.20 W/(m K)**, density **900 kg/m³**, Cp **2300 J/(kg K)**, source **60 W/m³**, passive isotropic E = **5 kPa**. Linear elastic ν=0.35 for both in the passive mechanical test to avoid near-incompressibility locking; *not* active muscle.
- Boundary core x=0 **310.15 K (37°C)**, skin-facing x=L convective Robin **h=10 W/(m² K)** to air **293.15 K (20°C)**, lateral edges insulated. This is fixed-core, dry-convection only: **NO sweat, perfusion, blood feedback, radiation split or clothing**, and no temperature regulation.
- **Elmer heat-source pitfall debugged:** specifying 700 directly as `Heat Source` at density 1050 initially yielded absurd >600 K. In Elmer formulation used, Heat Source is *specific*, W/kg, so corrected to `q_volumetric/rho` for muscle/fat and verified against independent closed-form multilayer conduction. Discarded initial unphysical outputs.
- The separate **transient BDF first-order** case uses tissue Cp, initial uniform 310.15 K and 12 × 60s timesteps. At 720 s, the outer minimum is still warmer than equilibrium as expected.

### Actual Elmer VTU results
| Case | Grid | Tissue scenario | Surface (minimum) | Maximum temperature |
|---|---:|---|---:|---:|
| `lifesim_mfat_heat_rest_t10` | 20×6; 147 nodes | q_m 700 W/m³; fat 10mm | **301.891 K = 28.741°C** | 310.150 K |
| `lifesim_mfat_heat_active_t10` | 20×6; 147 nodes | q_m 5000 W/m³; fat 10mm | **303.235 K = 30.085°C** | 310.269 K |
| `lifesim_mfat_heat_thickfat_t10` | 28×6; 203 nodes | q_m 700 W/m³; fat 20mm | **300.173 K = 27.023°C** | 310.150 K |
| `lifesim_mfat_heat_fine_t10` | 40×8; 369 nodes | rest heat; fat 10mm, refinement | **301.891 K** | 310.150 K |
| `lifesim_mfat_thermal_transient_t10` | 20×6; 147 nodes | uniform initial core T, 12min heat-storage cooling | **304.685 K = 31.535°C** | 310.169 K |

The independently derived 1D steady two-layer analytical heat balance gives resting surface **301.89125 K**, active **303.235 K**, thicker fat **300.173 K**. All Elmer surface minima agree to **<0.001 K** (VTU readout rounded to 0.001K). 2D refinement maintained baseline skin result. Temperature and heat flux are continuous at the muscle-fat interface in the conforming mesh.

### Actual passive muscle + fat compression
`lifesim_mfat_mech_t10`: two materials, **30kPa muscle / 5kPa fat**, `ν=.35`, 100 Pa compressive pressure applied on the outside skin-facing edge, core edge fixed, sides free. Elmer steady plane stress output: **maximum displacement vector magnitude = 0.000285811m (0.285811 mm)**, max von Mises **127.472 Pa**. Simple uniaxial equal-stress series approximation `u≈p (L_m/E_m+L_f/E_f)=0.000283333m`, difference **0.87%**. Pressure 100 Pa, NOT 100 N. This is a passive soft-material comparison, not muscle fiber shortening or fat nonlinear compression.

### Blender connection (actual editable scene)
The script `tools/blender/anatomy_attach_musclefat_thermal_v1.py` inserted the full canonical FEM numeric results as Blender `Text` datablock `Elmer_MuscleFat_Thermodynamics_v1.json`; each fat/muscle object now has SI thermal fields and explicit `numerical_field_mapped_to_this_3D_mesh=false` flags. A **separate scaled-up** cutaway heatmap uses the 1D analytic temperature profile *validated* by Elmer (not fake 3D temperature maps). The Blender scene was saved and reopened in a second process; 6 fat shells, 60 muscles, 17 Bullet bodies and 16 joints remain.

## Reproducibility and automated gates
- Generator: `tools/elmer/build_muscle_fat_v1.py` — standalone pure Python emitting **six** two-body conforming `mesh.*` files and `case.sif`; executed on connected Godot server and printed correct mesh sizes (147, 203, 369 points). Elmer case folders use `lifesim_mfat_*` identifiers listed above. Four independently archived SIF examples are in `tools/elmer/muscle_fat_*.sif`.
- Evidence: `docs/anatomy/elmer_muscle_fat_v1.json` — actual solver fields, analytical checks, counts, limits and **false flags** for unimplemented 3D/medical features.
- Safe read-only Godot lookup: `scripts/physics/muscle_fat_thermal_reference.gd`, bounded 700..5000 W/m³ and 10..20 mm fat thickness; uses analytical 1D equations with actual Elmer validation. Separate bounded 0..100 Pa mechanical lookup, and actual 720 s transient endpoint.
- Automated: `tests/test_muscle_fat_fem_thermal.gd` **90/90 passed**; actual Elmer cases all exited 0; final Blender geometry/manifold/export validation passed; Godot syntax check 60/60 existing scripts clean.
- Production gameplay/realtime heat physics **not enabled**, to preserve deterministic server-authenticated multiplayer. Do not confuse off-engine reference fields with character temperature management.

## Next technically justified work
A 3D conforming muscle/fat Gmsh mesh with anatomically correct contact surfaces; low-frequency Pennes perfusion+vascular terms, nonlinear hyperelasticity/fiber-actuated muscle elements, separate heat source from activity, convective/radiative/sweat BCs and authored skin morph mapping. Then build a **server-authoritative low-frequency compartment thermoregulation engine** in Godot with bounded materials/time stepping, independent of individual identity or psyche. Real-time 60 Hz skeletal motion can use Bullet/Godot physics, while complex Elmer solves remain validation/offline or carefully scheduled cached updates.
