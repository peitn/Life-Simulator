# Life Simulator — Blender Anatomy v0.1 (26 October 2026)

**Status: REAL, persisted standalone Blender asset and actual preliminary physics. NOT yet plugged into live gameplay.**

The user requested a full skeleton, joints, physical properties, cartilage and possibly muscles. This milestone creates a reproducible body-wide **anatomy-inspired modular prototype**, not a medically exact human skeleton or calibrated ragdoll.

## Verified delivered files in Blender asset library

**Blender library model asset:** `lifesim-anatomy-skeleton-v1` (separate from original `lifesim-character`).

| File | Contents |
|---|---|
| `anatomy_skeleton_v1.blend` | **Editable actual Blender scene**, ~8.8 MB: armature, bone meshes, cartilage, muscle bundles, tendons, physics rigid bodies and 16 Bullet constraints. |
| `anatomy_skeleton_v1.glb` | ~2.0 MB, separate rigged osteology/cartilage/ligament GLB, intentionally not replacing production `character.glb`. |
| `anatomy_musculature_v1.glb` | ~264 KB, separately re-import verified 60 muscle bundle meshes + 194-bone armature. |
| `anatomy_osteology_overview.png` | Actual Blender Cycles orthographic full-body bone render. |
| `anatomy_musculature_overview.png` | Actual Blender Cycles orthographic muscle pass. |
| `anatomy_manifest.json`, `muscle_manifest.json` | Real inventory and stage limitations. |
| `anatomy_skeleton_v1.py.txt` | Original Blender Python source copy (library model type cannot accept `.py`), source also under `tools/blender/anatomy_skeleton_v1.py`. |

The model is **actually created and persisted in the Blender model library**, not a design mock-up. `bpy.ops.wm.open_mainfile` in a fresh Blender process re-opened the `.blend`; Blender GLB import reproduced 194 armature bones, and muscle GLB import reproduced 60 muscle meshes/one armature. Real viewport Cycles previews were generated and inspected at reduced resolution.

## Contents measured from Blender

- **194 anatomical rig bones, 201 visual bone mesh pieces**, including preserved 17 canonical production bone names to allow a future retargeting adapter.
- 24 modeled vertebral segments (7 cervical, 12 thoracic, 5 lumbar) and 24 ribs (12 paired).
- 28 distinct hand phalanx references + 28 toe phalanx references, metacarpals, carpals, metatarsals, tarsals, radius/ulna, tibia/fibula, pelvis/sacrum, kneecaps, clavicles and scapulae. Skull/orbits/jaw are **coarse references** rather than complete cranial osteology.
- **60 separately shaped cartilage meshes**, including intervertebral discs, joint surface caps (shoulder, elbow, hip, knee, ankle, wrist), costal cartilage, nasal and ear proxies.
- **60 muscle belly bundles** distributed across chest, back, arms, hands/forearms, abdomen, pelvis, thighs, calves, and neck, with tendon endpoints and force/length/damping custom properties. These are simplified fusiform volume proxies, **not exact anatomical origins/insertions or complete muscle fiber architecture**.
- **136 ligament/tendon meshes** including simple attachments and lateral joint constraints visualizations.
- **17 Blender Bullet rigid-body proxy meshes** (pelvis passive fixed; others active) with mass, friction, restitution, damping, collision shape/margin, totaling **63 kg nominal**.
- **16 actual Blender Generic rigid-body constraint objects**, with three locked linear axes, bounded angular joint limits and disabled direct parent-child collision. Only major torso/neck/shoulder/elbow/wrist/hip/knee/ankle joints are physics-driven; no per-phalange ragdoll joints, joint motors, muscle-actuation mechanics or dynamic skin deformation.

**Coordinate convention:** Blender Z-up, scene units METRIC meters; exported GLB is Godot Y-up, meters. Meshes and masses use separate anatomical reference asset so existing multiplayer and characters remain unchanged.

**Physics numerical caveat:** Rigidbody values (bone density 1500 kg/m³, cartilage stiffness examples, muscle-force reference values in N, 63 kg nominal proxy total) are authoring defaults and intentionally **not certified physiological or clinical values**. Blender Bullet joint constraints are real stored editable physics components, but they are **not yet coupled to the render rig or deployed in Godot's life simulation**. There is no actual cartilage deformable-body finite-element solution, calibrated tendon constitutive law, muscle contraction motor or nervous system link.

## Actual tests and integration contract

- Fresh Blender process opened saved `.blend`: **194 rig bones, 17 rigid proxies, 16 correctly connected constraints, mass sum 63.0 kg**, pelvis passive. Frame 1→20 evaluated without a Python exception; this is a **smoke check, not stability validation**.
- Fresh Blender GLB import: **194 bones**; osteology 201 bone mesh elements and 60 cartilage meshes. Separate muscle GLB import: **60 genuine muscle meshes**, same 194-bone armature.
- Godot `docs/anatomy/anatomy-physics-v1.json` mirrors version, inventory, 17 production rig compatibility names, 17 masses, 16 joint limit pairs and explicit `physics_in_live_gameplay:false`.
- `tests/test_blender_anatomy_contract.gd` **117/117 PASS**, compares 17 Blender compatibility names against the actual existing Godot character GLB skeleton, checks physics manifest masses and constraints, presence of reproducible Python sources. **No pretend runtime model import.**

## Next safe integration steps

1. Transfer optional separate Blender GLB into Godot asset library (no current binary transport in this action); build **visual anatomical debug viewer**, never silently replace `assets/models/character.glb` or private identity/psych data. Retarget high-res rig to 17 live control bones, with optional per-digit driver values.
2. Link Bullet-to-visual rig in Blender or implement separate deterministic Godot PhysicsServer3D 6DOF ragdoll with server-authoritative simulation and explicit activation. Physics proxies must avoid unstable interpenetration and must have mass/inertia and joint limits unit-tested before in-game use.
3. Sculpt anatomically accurate cortical meshes, vertebral processes, scapula, cranial bones and metacarpals, realistic phalange joint pivots and tendon paths; refine cartilage material and articular shapes.
4. Implement real tendon/muscle actuator dynamics with activation/fatigue, passive stretch, joint torque and neural control separately; deformable cartilage/ligament mechanics can be a low-frequency/LOD approximation or FEA research branch.
5. Only after approved body and anatomy pipeline validation, develop optional sensitive body details, clothing and collision/animation QA. Character gender/identity, psyche and private data must remain separate from physical body variants.

**Do not represent this standalone modeling milestone as a complete anatomical human simulator or as an already active physics feature in the game.**
