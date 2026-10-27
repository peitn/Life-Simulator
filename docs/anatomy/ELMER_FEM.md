# Life Simulator — actual ElmerFEM mechanics study, v0.1
**Executed:** 26 October 2026. **Solvers:** Godot connector's actual `ElmerSolver 26.2`, coupled only to **offline** source/prototypes, and Blender 4.0 library asset `lifesim-anatomy-skeleton-v1`.

## Scope and limitations
This is a real linear elastic **2D plane-stress** finite-element study at the interface between a conceptual Blender skeleton (194 bone controls / 60 cartilage proxy meshes / 60 muscle proxies) and an isolated Elmer problem. All six principal reference families below have real generated meshes, solver exit 0, and `case_t0001.vtu` outputs accessible through the connected Elmer cases. **We have not solved the true 3D human bone geometry, curved knee contact, biphasic cartilage fluid flow, nonlinear tendon mechanics, or realtime ragdoll muscle actuation**. Blender Bullet 17 rigid bodies and 16 constraints remain structurally separate and NOT driven by the Elmer field.

### Independent review
Gemini 3.5 Flash Lite was consulted twice: once before designing the FEM experiments and once after receiving actual VTU outputs. It recommended strict SI units, a cantilever Euler–Bernoulli check, pressure/stiffness/mesh sensitivity, storing offline reference fields rather than running the sparse Elmer solver at 60 Hz, and treating fixed-corner peak stresses as potentially singular and **not** a biological injury threshold. The actual experiments, not Gemini assertions, are the results below.

### 1. Cortical-like reference beam
- 2D geometry: 0.150 m longitudinal length × 0.015 m height, model extrusion thickness **1 m by convention**. Linear, homogeneous isotropic `E=15 GPa`, `ν=0.30`, density 1900 kg/m³ (density does not affect the static load).
- BC: left vertical edge `u_x=u_y=0`; right vertical edge uniform downward **traction 100 Pa**, `Force 2 = -100.0`. **THIS IS NOT 100 N**. Integrated over 0.015 m right edge, effective force is 1.5 N **per metre of out-of-plane extrusion**.
- Euler–Bernoulli analytical `I=h³/12=2.8125e-7 m⁴` per unit extrusion, `δ=F L³/(3EI)=4.00000e-7 m` (0.4000 µm). Formula assumes slender beam, small strain, does not include shear effects and compares to the FEM **maximum displacement magnitude** (slightly differs from vertical tip component).

| Mesh (quads) | VTU points | Elmer maximum vector displacement | Relative difference to 0.4 µm | Max von Mises |
|---|---:|---:|---:|---:|
| 14×4 | 75 | 0.334422 µm | 16.39% | 4,994 Pa |
| 30×8 | 279 | 0.385813 µm | 3.55% | 5,807 Pa |
| 60×16 | 1,037 | **0.398879 µm** | **0.28%** | 6,408 Pa |

The consistent trend with mesh refinement supports unit correctness for this limited 2D elastic benchmark; it is not a statement about realistic bone fracture behavior.

### 2. Articular-cartilage-like flat compression patch
- 2D geometry: 40 mm wide × 3 mm high rectangular homogeneous flat slab, `E=5 MPa`, `ν=0.35`, density 1100 kg/m³. This is **not** 3D contact mechanics and neither fluid exudation nor time-dependent porous cartilage.
- BC: bottom y=0 fully fixed (`u_x=u_y=0`); top y=0.003 m uniformly loaded downward with `Force 2=-20000` or `-40000 Pa`; both side edges traction-free.
- The reported maximum is the **magnitude of the 2D displacement vector**, not solely vertical shortening. At the location of maximum magnitude, the 120×24 run has `u=(−6.8526875,−13.280531,0) µm`.
- Data below are **actual VTU results**, not an unrun idealized calculation.

| Pressure | Modulus | Mesh | Points | Max vector displacement | Peak von Mises |
|---:|---:|---:|---:|---:|---:|
| 20 kPa | 5 MPa | 40×8 | 369 | 14.8176 µm | 34.409 kPa |
| 40 kPa | 5 MPa | 40×8 | 369 | 29.6352 µm | 68.819 kPa |
| 20 kPa | 5 MPa | 80×16 | 1,377 | 14.9233 µm | 41.419 kPa |
| 20 kPa | 5 MPa | 120×24 | 3,025 | **14.9443 µm** | 46.143 kPa |
| 20 kPa | 2.5 MPa | 40×8 | 369 | 29.6352 µm | 34.409 kPa |

**Checks:** doubling pressure doubles displacement and stress at same mesh/material. Halving E doubles displacement under the same traction and nearly identical material model; max stress at equivalent pressure stays essentially the same in the simplified linear traction BC. Global maximum displacement changes ~0.14% from mesh 80×16 to 120×24. The **peak corner stress continues increasing** (34.4 → 41.4 → 46.1 kPa) with refinement; this is a **lack of peak-stress convergence**, consistent with concentrated reaction forces at sharply clamped corners. Do NOT use that peak to diagnose cartilage damage, pathology or clinical injury.

### Reproduction paths

Connector Elmer cases, physically executed and persisted under these independent identifiers:
- Beam: `lifesim_bone_bend_coarse_c9` (14×4), `lifesim_bone_bend_c9` (30×8), `lifesim_bone_bend_fine_c9` (60×16).
- Cartilage: `lifesim_cartilage_20k_c9`, `lifesim_cartilage_40k_c9`, `lifesim_cartilage_fine_c9`, `lifesim_cartilage_ultrafine_c9`, `lifesim_cartilage_soft_c9`.

To reproduce: recreate beam-style 2D rectangular mesh using `elmer_case_create(template="beam_stress",params={length,height,nx,ny,youngs_modulus,poisson,load})`; for cartilage **change boundaries**: bottom ID 1 clamped, top ID 3 pressure downward, sides 2/4 free, density 1100; run `elmer_run`, read `elmer_results`/VTU. The original SIFs are retained in `tools/elmer/bone_cantilever_v1.sif` and `tools/elmer/cartilage_compression_v1.sif`; only a matching generated mesh and SIF together reproduce a solve. **Do not pass negative `load` into the original beam case-create template**: it prepends the sign and has previously yielded invalid `--100.0`; use positive template load or explicitly fix the SIF to a single `-100.0` sign.

### Godot/Blender integration implemented this run
1. **Evidence + Atlas:** `docs/anatomy/elmer-fem-results-v1.json` stores actual Elmer VTU extrema, case IDs, SI materials, BCs, coarse/fine grids and flags that realtime gameplay physics and medically accurate results are **OFF**.
2. **Typed bounded offline accessor:** `scripts/physics/anatomy_fem_atlas.gd`: `cartilage_compression(pressure_pa, E_pa=5e6)` for pressure `0..40kPa`, modulus `2.5..5MPa` only; `bone_cantilever(traction_pa)` for `0..100Pa`. Reject negative/nonfinite/extrapolated pressures/moduli and never expose nonconvergent peak damage stress. Uses the measured ultrafine vector displacement and analytically valid linear E/pressure scaling; **not a timestep physics solver**.
3. **Reproducible Blender link:** `tools/blender/anatomy_attach_elmer_v1.py` stores the canonical atlas JSON as a Blender `Text` datablock and copies explicit offline-only FEA reference properties onto `Cartilage_joint_knee_l/r` as flat-slab proxies. `lifesim-anatomy-skeleton-v1/anatomy_skeleton_v1.blend` was truly saved and reopened: 194 rig bones, 17 rigid-body proxies and 16 constraints untouched, JSON block present, offline flags verified. **The 3D knee geometry was NOT directly solved in Elmer**, and joint physics in the game was not modified.
4. **Tests:** `tests/test_anatomy_elmer_lookup.gd` **69/69 passed**: mass/units, actual solved material/mesh convergence, correct signed forces, Euler analytic comparison, E/pressure proportionality, monotonicity, bounds, source SIFs, and safety flags. Prior `tests/test_blender_anatomy_contract.gd` retains the 194-bone vs. 17-bone compatibility check.

## Next technically sound development
1. Mesh the **real Blender cartilage or ligament 3D volume**, classify interfaces in Gmsh, generate 3D Elmer mesh, solve one well-defined joint-load boundary-value problem with contact or bonded interface and proper anisotropic/hyperelastic or poroelastic constitutive law.
2. Refine elements at the fixation edges and evaluate integrated force/energy, convergence of area-averaged stress/strain instead of singular maxima; test across morph/pose extremes with explicit units.
3. Implement an opt-in **server-authoritative** Godot skeleton/PhysicsServer3D debug viewer; map offline FEM compliance to safe bounded corrections at a much lower update rate than animation/ragdoll, not by calling Elmer every frame.
4. Design muscle torque/activation (Hill-type or approximate) and cartilage stress feedback with performance LOD. These require a new approved architecture and actual deformation rig tests; they are not magically created by this FEM slab benchmark.
