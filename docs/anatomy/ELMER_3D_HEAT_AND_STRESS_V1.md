# Life Simulator — Real 3D ElmerFEM muscle/fat numerical reference, C11
**Executed 27 October 2026** on the connected ElmerSolver 26.2 and persisted Blender 4.0 model asset. This is a **first real three-dimensional finite-element volume** for thermal diffusion and passive compression; not an FEM simulation of the anatomically sculpted body geometry.

## Model and honest technical scope
The preceding C10 milestone created 2D two-domain muscle/adipose heat and stress solutions. C11 generates a **conforming three-dimensional pair of actual Hex8 volume meshes** in Gmsh v2.2 and imports them using **ElmerGrid 14 2**. The muscle occupies x=0..0.025 m; the fat occupies x=.025.. .035 m; the y extent is 12 mm and z extent 10 mm. Shared nodes on the muscle-fat interface mean a continuous temperature/displacement field at the interface, without a special contact resistance. Hex8 body tags are muscle 1 and adipose 2; outer Quad4 surfaces have tags core 11, skin 12 and otherwise insulated/free 13. ElmerGrid explicitly reported ONE conforming mesh piece, and both full 3D volume and two material domains were recognized.

**Important distinction:** Physically this is 3D *rectangular two-tissue material sampling*, NOT a 3D actual femur, muscle fiber atlas, knee cartilage, skin, patient-specific anatomy, or simulated live NPC with blood, sweating or locomotion. The Blender 194-bone sculpt + 60 muscle bundles + 6 fat shells remains separate and unchanged.

### Materials and boundary values
Steady and transient HeatSolve:
- Muscle: **k=0.50 W/m/K**, density **1050 kg/m³**, specific heat **3750 J/kg/K**, resting heat generation 700 W/m³; separate illustrative activated heat generation 5000 W/m³.
- Fat: **k=0.20 W/m/K**, density **900 kg/m³**, specific heat **2300 J/kg/K**, constant heat generation 60 W/m³.
- Elmer `Heat Source` is **W/kg** in these tested cases; therefore write `q_volume/rho` (700/1050=0.6666667 and 60/900=0.0666667), not 700 W/kg. The earlier experimental setup using W/m³ directly had produced impossible values above 600K, which was corrected in C10.
- Core at x=0 held to **310.15K** (37 °C). External x=.035m is Robin convection to ambient **293.15K** (20 °C) with h=10 W/m²/K. Side boundaries are naturally insulated in the thermal cases.
- The transient case is 12×60 s implicit BDF1 steps starting from uniformly 310.15K. This is **actual 3D thermal energy storage** via density×specific heat, not a steady-state animation.
- Passive stress is a separate 3D, 3-DOF Linear elasticity solve. Muscle E=30000 Pa, fat E=5000 Pa, isotropic ν=0.35. All three axes clamped on x=0; outer x=.035m experiences **Force1=-100 Pa traction** (a stress pressure, not 100 N). Lateral faces are traction-free. This is **passive** continuum material stress only; there is **no muscle contractile model or tissue contact mechanics**.

## Actual Elmer 26.2 solves and VTU observations

| Elmer case ID | True volume mesh | What was solved | Actual output |
|---|---|---|---|
| `lifesim_mfat_3d_heat_coarse_c11` | 208 nodes, 108 Hex8, 162 boundary Quad4 | 3D rest steady conduction | **minimum/skin 301.89125 K** (28.74125°C); maximum 310.15 K |
| `lifesim_mfat_3d_heat_fine_c11` | 900 nodes, 600 Hex8, 530 boundary Quad4 | 3D rest refined mesh | **minimum/skin 301.89125 K**; maximum 310.15 K |
| `lifesim_mfat_3d_active_c11` | 208 nodes, 108 Hex8 | More muscle metabolic source | **skin 303.235 K** (30.085°C); max 310.264 K |
| `lifesim_mfat_3d_transient_c11` | 208 nodes, 108 Hex8 | BDF1 720s starting at 310.15K | **skin/min 304.684 K** (31.534°C) at 12 min, max 310.168K |
| `lifesim_mfat_3d_mech_c11` | 208 nodes, 108 Hex8 | Full 3D passive compression, three displacement DOFs | **max displacement magnitude 0.000282131 m** (0.282131 mm); maximum von Mises **136.307 Pa** |

All five runs report **ElmerSolver exit0**, actual Hex8 input conversion and actual VTU output. `elmer_grid` conversion reported all 3D meshes conforming and preserved physical tags.

**Analytical agreement and dimensional checks:** independent 1D steady multi-layer conduction predicts 301.89125 K surface for rest and 303.235 K for increased heat generation. BOTH coarse 208-node and refined 900-node **true 3D** rest results give **301.89125 K** at the skin surface. The 3D activated case yields 303.235 K. This exact agreement is expected here because the y/z boundaries are insulated and the physics reduces to a 1D temperature profile on the flat cuboid; it **does not validate a real 3D anatomical temperature simulation**. The 3D 720s transient skin 304.684K differs from prior 2D 720s 304.685K by 0.001K, validating the time-dependent heat-storage implementation for this test. The 3D passive max displacement 0.282131mm is 0.42% below ideal equal-axial-stress series approximation 0.283333mm, and differs from prior 2D 0.285811mm by ~1.3% due to full 3D lateral response.

### Actual solved 3D field transferred to Blender
The **actual VTU temperature values at all 208 finite-element nodes**, along with all 108 volume elements and 3D node coordinates, are stored in `lifesim-anatomy-skeleton-v1/elmer_mfat_3d_field_v1.json`. Source `tools/blender/anatomy_elmer_3d_field_visual_v1.py` builds a **separate watertight Blender collection `Anatomy_Elmer3D_Diagnostic`** from the *actual Elmer outer-volume faces* (including the muscle-fat interface). The surfaces use exact per-vertex numeric `actual_elmer_kelvin` data for their false-color emission material. This is true visualization of an **actual 3D FEA volume field**, with 116 vertices/114 faces for the muscle and 68 vertices/66 faces for adipose. Both surfaces have **zero non-manifold edges**. Values on muscle range 306.24686..310.15K; fat surface 301.89125..306.24689K.

The data are displayed enlarged **38×**, in a non-gameplay collection clearly marked as a flat block, NOT assigned to actual 3D human-body muscles/skin. Blender saved:
- `anatomy_elmer_actual_3d_temperature_v1.png` — real Cycles-rendered diagnostic gradient (visually inspected).
- `anatomy_elmer_actual_3d_temperature_v1.glb` — independently exported and **reimport tested** two genuine 3D surface mesh objects WITH vertex colors.
- `elmer_mfat_3d_field_v1.json` — original temperature measurements and mesh node/element ordering, stored also as Blender Text datablock.
- The original `anatomy_skeleton_v1.blend` retains 194 bone rig controls, 60 muscle bundles, 6 previous manifold fat shells, 17 Bullet rigid proxies, 16 angular constraints, previous C10 textures, 2D source data and all five C10 render PNGs. New diagnostic collection hidden outside its own inspection render.

**Run details:** the initial SIF output `Output File Name = case3d` placed VTU under `mesh/case3d_t0001.vtu`. For cases to be discoverable by `elmer_results` directly, revised SIF to `Output File Name = ../case` (writing root `case_t0001.vtu`). All output files remain in their respective case directories. Reproducible `tools/elmer/build_muscle_fat_3d_v1.py` script generates conforming Gmsh v2.2 3D Hex8 mesh + validated 3D SIF for four simulation modes `rest`, `active`, `transient`, `mechanics`; the generator was actually executed via connected Godot OS/Python and returned 208 nodes/108 hexes/162 surfaces.

## Acceptance testing
`tests/test_muscle_fat_3d_fem.gd` **88/88** headless assertions verify 5 actual case summaries, geometry SI, 3D physical-tag topology, thermal source normalization, 3D vs independent analytical and previous 2D results, 3-DOF vector stress, safe non-gameplay flags and source presence. Blender reopened the saved scene in a new process, checked all 194 bones/17 Bullet/16 constraints/60 muscles/6 prior fat shells, zero mesh non-manifold edges for both solver geometry shells, numerical `actual_elmer_kelvin` node attributes, JSON VTU evidence persistence, and reimported the 2-mesh vertex-colored diagnostic GLB successfully.

## Next practical milestone (not falsely completed)
Generate anatomically fitting volumetric FE meshes of the **actual** Blender muscle-fat shells with conforming boundaries, integrate fluid perfusion/Pennes bioheat with clothing/evaporation/heat radiation, add nonlinear viscoelastic behavior and muscle contractility with tendon force pathways, validate energy balance and surface temperatures against reference literature/benchmarks, design server-authoritative bounded low-frequency thermal compartments and prevent external data leakage. A finite-element solve on this deliberately flat 3D block cannot be promoted to a medically realistic injury, warmth or biomechanical model merely by adding colored shaders.
