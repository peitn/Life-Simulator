# Life Simulator

> **Working title.** The final name is still undecided.

Life Simulator is a realistic, **adult** life simulation with multiplayer, built in **Godot 4.7** (Forward+).
It is not a family-friendly dollhouse. Characters live a raw, believable life: arguments and break-ups,
debt, addiction with real consequences, petty crime, morally grey choices, illness, dark humour and swearing.
Intimacy happens only by implication (fade-to-black). Nothing involving minors appears in adult themes.

Its defining system is a **deep, carefully handled model of mental health**, inspired by *Hellblade*,
*Celeste* and *Disco Elysium*. It covers stress, a three-component anxiety model with panic attacks,
depression built on separate *wanting*, *liking* and *vigour*, intrusive thoughts and coping strategies
with trade-offs. Every sensitive theme can be muted or switched off, and crisis resources are always one
click away.

> ⚠️ **Content warning.** The game depicts mental illness, addiction, conflict and other difficult themes.
> If you are struggling, please reach out: **116 123** (Czech Republic, free, non-stop) or
> **[findahelpline.com](https://findahelpline.com)** (international).

---

## Status

The project is in **active early development**. It is built in small, fully tested steps by an
automated development process (see [Development process](docs/development-process.md)).

| Area | State |
|---|---|
| Simulation core: needs, mood, 15 traits, utility AI, player commands | ✅ playable |
| Mental health: stress, anxiety, panic, depression, coping, intrusive thoughts; psyche model (personality, 9 dispositions, conditions as data, run 20) | ✅ base done, ✅ axis 1, 🟡 expanding |
| Relationships: grudges, guilt, apologies, reconciliation, jealousy, household dynamics (frictions, shared moments, life events, de-escalation), crowded households up to 8 characters (sensory profiles, household matrix, run 23) | ✅ |
| Multiplayer: authoritative ENet server, private state, validation | ✅ |
| Character creator: data model (C1), body (C2), face (C3), skin (C4a, C4c), hair, beards and eyebrows (C4b) | ✅ C1–C3 (neck, seam, neck length, face polish; eyelashes, teeth and facial expressions in run 21; mouth, smile, lip and eyelash fixes in run 22), ✅ C4a, ✅ C4c (skin micro detail and skin type, run 22), ✅ C4b (+ hair details, run 19) |
| Character creator: clothing (C5), editor UI (C6–C7), integration (C8) | 🟡 C5 wardrobe, offline creator and authenticated owner-only native ENet editor implemented; creator → household → command → save/restore → cold restart tested. 72 appearance sliders and 4 appearance selectors now accessible from both editors. Cuff deformation, detailed hands/feet/nails and full visual QA pending. |
| Visuals: Blender asset pipeline, day/night cycle, PsycheFX | ✅ |
| Audio: custom synthesizer, 5 songs (music v3), apartment ambience, tension layer, argument voices, 3D object sounds, anxiety audio | ✅ |
| Character voice: pitch/timbre/tempo/roughness sliders with live preview in the creator and editor; every character speaks in its own synthesized voice in conversations (`test_voice`, 86 checks) | ✅ |
| City, careers, economy | ⬜ planned |
| Saving/loading | 🟡 Offline save/load, automatic save every 5 real minutes and at game-day rollover, auto-resume, manual slots and backup recovery (H4 partial) |

The current implementation queue and completion gates are in [docs/implementation-sequence.md](docs/implementation-sequence.md). The wider plan is in [docs/roadmap.md](docs/roadmap.md).

## Quick start

Requirements: **Godot 4.7** (standard build; GDScript only, no C#).

```bash
git clone https://github.com/peitn/Life-Simulator.git
cd Life-Simulator

# 1. Generate the audio. WAV files are not stored in git: they are rendered by the game's own synthesizer.
godot --headless -s res://tools/build_audio.gd

# 2. Open the project in the editor, or run it directly
godot --path .
```

### Launch options

Pass these after `--` on the command line, for example `godot --path . -- --host`.

| Option | Meaning |
|---|---|
| *(none)* | Offline single player. You control the whole household. |
| `--host [port]` | Listen server: simulate and play at the same time. |
| `--server [port]` | Dedicated headless server. |
| `--join <address[:port]>` | Join a server as a client. The default port is `24565`. |
| `--name <name>` | Player name shown to others. |
| `--character <code>` | Join with your own character (an `LSC1.` share code from the character creator). |
| `--test <days>` | Headless simulation of N game days, with a report. |

## Playable offline starter loop (live Godot project, 26 October 2026)

1. Launch in offline mode (or open the exported browser build). The starter household and its furnished home are already present.
2. In the right-hand HUD, choose **Vytvořit vlastní postavu** (Create your own character). Set an adult character's name, age, independent grammatical gender and identity, hair, clothing preset and personality. Use **Zpět / Znovu** to undo/redo. **Zrušit** discards the draft without adding a resident.
3. Set body proportions, face (including cheeks, chin, nose and lips), skin melanin/undertone and eye/hair details with the **Podrobný vzhled** (Detailed appearance) category selector (72 appearance sliders + 4 choices). Select **Vytvořit a hrát** to add the new character and play as them. Use the HUD action list to interact with objects and household members. The right-hand panel scrolls in narrow windows.
4. Choose **Upravit postavu** (Edit character) for subsequent offline wardrobe/personality changes, **Uložit hru** (Save game) or F5 to save, and F9/Shift+F9 or the HUD buttons to reload. Automatic saves restore the same user-created character and simulation on restart.

This is a **verified offline starter vertical slice**, not the completed game: it adds a character to the prebuilt household rather than offering empty-lot/house construction. Multiplayer character **creation** and network-owned save/load are not enabled; owner-only native ENet **editing** is implemented. City, advanced assets, exported GUI hands-on visual QA and broad release testing remain in progress. The Godot server source currently differs from GitHub because publication approval is pending. The executable web debug export is ~108 MB and its real browser performance has not been certified.

Validation: `tests/test_full_playable_slice.tscn` 45/45 including 390×720 scroll layout, 18+ and forged-name rejection, creator Cancel/Undo/Redo, preview/live appearance identity, live TV command, exact save/reload continuation and actual fresh Main startup from autosave.

## Native multiplayer owner editor (26 October 2026)

On desktop ENet host/client builds, a player with their **own player-created character** can open **Upravit postavu** (Edit character) from the game HUD. The owner receives an authenticated private draft; Apply validates identity/ownership on the authoritative server, accepts only strict current-schema data, returns a correlated private acknowledgement, and refreshes the owner from a canonical private snapshot. The public appearance is replicated to other clients without private mind/personality history or UID. Conflicting revisions fail closed; identity and private sexuality changes remain disabled in network mode. A listen host can also edit their own explicitly created player-character; neither the host nor a guest can edit arbitrary household NPCs.

The web export runs **offline** because ENet multiplayer is unavailable there. The web build is served by the Godot Hugging Face Space at `https://peiti-godot-mcp.hf.space/play/lifesim/`; official hosting page `https://huggingface.co/spaces/peiti/godot-mcp`. These endpoints returned HTTP 200 in the server environment on October 26, 2026, but a user's browser reported an address/typo error. That end-device access issue has not been reproduced or fixed; server reachability is not proof of mobile browser compatibility.

Real ENet client UI tests `tests/test_network_editor_live_enet.gd` 27/27; listen-host `tests/test_host_character_editor.tscn` 10/10; existing ENet staged authority/public look test 97/97. See `docs/reviews/h2b-native-network-ui-20261026.md`. Full GUI click-through, long-term reconnect soak, and final garment cuffs/joins QA are still pending; arm skin weights were repaired and a shoulder join corrective was added on 26 October 2026.

## Detailed 3D appearance editor and garment seam tests (26 October 2026)

Both the native owner-only editor and offline new-character creator now expose schema-backed actual model controls via the category dropdown **Podrobný vzhled** (Detailed appearance): 72 independent numeric sliders (11 body, 38 face, 10 skin, 6 hair, 2 eyes, 5 makeup) plus 4 hair/skin enum selectors. Existing 18–95 age and 145–205 cm height controls have been aligned with strict schema boundaries. Separate identity, grammatical gender, private mental history, and wardrobe remain untouched by these public face/body/skin sliders. The preview is isolated and changes remain transactional until Apply; Undo/Redo/Cancel work.

The Blender C5 sleeve source was adjusted and a narrowly topology-checked legacy LSX migration shifts the two upper sleeve rings (+45 mm/+12 mm) while preserving relative body morphs, the original arm skinning, and recalculating face/morph normals. This reduces the default shirt-to-sleeve actual median surface separation in rest pose from ~20.94 mm to ~10.63 mm, measured by triangle distances. A subsequent upper-arm/forearm skinning correction fixed the moving shoulder rim: elbow-bent median is now **~12.03 mm**, down from ~16.6 mm, and the maximum in the default cat hoodie is ~21.28 mm rather than ~30.07 mm. A 5-profile × 11-long-sleeve-style × 4-arm-pose × 2-side regression (440 observations) found a remaining **worst maximum 27.90 mm**. These are *surface-proximity measurements*, not a closed/watertight fit; cuff sculpting and full animations remain.

Actual tests: `tests/test_appearance_slider_ui.tscn` **108/108**, surface/default two-pose diagnostics, `tests/test_cat_hoodie_sleeve_gap.gd` 20/20 characterization, `test_body_morphs` 62/62, `test_face_detail` 66/66, `test_character_preview` 13/13, wardrobe C5 16/16, existing offline creation45/45, offline editor55/55, native network editor27/27 and character network70/70. A newer full-body hand/finger/toe and nail/nipple/navel morph mesh does **not** follow from adding sliders alone and is **not claimed implemented**. Detailed evidence: `docs/reviews/character-anatomy-ui-sleeve-20261026.md` and the newer `docs/reviews/h2b-sleeve-weight-bend-matrix-20261026.md`.

## Clothing geometry regression and sleeve pose matrix (26 October 2026)

Full C5 source audit: all **20 tops, 17 bottoms and 16 shoes** compose into **5,440 nonempty outfit combinations**. New `tests/test_clothing_mesh_integrity.gd` inspected 172 authored parts (42,664 vertices, 80,579 triangles) with geometry, normal, UV, skin-weight and 10-morph integrity. Its first run found **36 collapsed triangles** in the waist chains on punk/metal/visual-kei bottoms; a topology-guarded 6 mm chain-midpoint repair fixed them, and the final run passed **7,046 checks** with no degenerate rest triangles.

The shoulder sleeve ring no longer follows the forearm on elbow bend; a new matrix across five body shapes, eleven real sleeve styles, four arm poses and two sides passed **1,012 checks**, with an unresolved 27.90 mm maximum rim-to-shell surface separation. A real 480×480 software-rendered Godot rest/bend preview was produced; cuff geometry still looks angular. Source Blender generators were updated but no new binary LSX asset was exported in this run. See `docs/reviews/h2b-sleeve-weight-bend-matrix-20261026.md`.

## Modeled anatomy: fingers, nails, bare feet and toes (26 October 2026)

The live character model now has **ten separate finger meshes (including both thumbs), ten fingernail plates, barefoot soles, ten toes, and ten toenails**. Unlike decorative UI labels, these are actual triangle surfaces generated by `scripts/assets/hand_detail_builder.gd` and `scripts/assets/foot_detail_builder.gd`, with 10 original Blender body morphs transferred to the additions. They are skinned to existing left/right hand and foot bones, and their colors follow continuous public skin melanin/undertone without using gender or identity. Bare toes/soles only render if the character chooses **bosy** (barefoot), never through sneakers/boots/platform shoes.

The 17-bone source does **not** include distinct finger/toe articulation: digit curling, individual finger/foot-width/nail-length sliders, detailed nails/skin shader, photorealistic anatomy, and nipple/navel geometry remain unfinished. There is a visible ankle/junction seam in actual graphical captures; no claim of a watertight or production-ready mesh. Headless tests: `tests/test_hand_detail_geometry.gd` **53/53**, `tests/test_barefoot_geometry.gd` **30/30**; two true graphical Godot test runs produced five screenshots, without releasing private character state. See `docs/reviews/h2b-real-hands-barefeet-20261026.md`.

## Independent finger pose deformation and interactive hand preview (26 October 2026)

Both modeled hands now support **10 independently addressable per-finger curl morphs** with the same deformations on the corresponding 10 physical nail plates. They are per-character GPU mesh targets, not separate knuckle bones. The character creator and local/native owner editor previews now have a **Ruce** (Hands) dropdown (relaxed, open, fist, pointing, pinch) and **Detail ruky** camera zoom. These are render-only demonstrations; they do not persist in CharacterData or bypass network authority.

The procedural mesh skinning/morph builder was corrected from wrongly absolute positions in RELATIVE blend targets to actual **relative displacements** (also benefiting bare feet), verified by genuinely rendered before/after captures and automated tests. New `tests/test_finger_curl_pose.gd` passed **157/157** headless and **162/162** GUI assertions; existing `test_hand_detail_geometry.gd` now passes **73/73** with 20 body + digit morphs per hand part. The fist is stylized and partial, not collision-correct grasping or 3-joint skeletal animation. See `docs/reviews/h2b-finger-poses-20261026.md`.

## Anatomical skeleton, cartilage, muscle and physics groundwork in Blender (26 October 2026)

The Blender library now contains a new **standalone editable anatomical prototype** named `lifesim-anatomy-skeleton-v1`, with `anatomy_skeleton_v1.blend`, `anatomy_skeleton_v1.glb`, `anatomy_musculature_v1.glb`, two real rendered PNG previews and model/physics manifests. It does **not** overwrite `lifesim-character`, change the in-game 17-bone rig or activate ragdoll physics for live NPCs.

This first body-wide prototype has **194 anatomical rig bones**, **201 bone mesh pieces**, 24 vertebra proxies, 24 ribs, **60 joint/costal/intervertebral/nasal/auricular cartilage meshes**, **60 muscle volume bundles**, 136 tendon/ligament attachments, **17 actual Blender Bullet rigid bodies (nominal 63 kg total)** and **16 actual angular-limited Generic constraints**. Joint positions and 17 canonical production bone names are compatible with the existing game character's reference coordinates. The Blender mesh deform armature was actually posed and its upper-arm surface vertices moved 21.5 mm; saved BLEND and separate GLBs were reopened/imported in fresh Blender processes.

These are **approximate modeling/physics scaffolds, not a medically exact 206-bone reconstruction or realistic active muscle/soft-tissue solver**. Bullet proxies are not yet driven by the render rig or coupled to in-game Godot physics. Godot retains the source generators `tools/blender/anatomy_skeleton_v1.py` and `tools/blender/anatomy_export_musculature_v1.py`; physics metadata and 17-skeleton compatibility are checked by `tests/test_blender_anatomy_contract.gd` (**117/117**). Full details and next integration gate: `docs/anatomy/README.md`.

## ElmerSolver 26.2 offline mechanics and independent Gemini review (26 October 2026)

Real structural mechanics studies were **actually solved** in the connected ElmerFEM 26.2 environment for two simplified 2D plane-stress reference materials. The cortical-like cantilever case (15 GPa) converged under a 100 Pa traction from **0.3344 µm (14×4) → 0.3858 µm (30×8) → 0.3989 µm (60×16)**, close to **0.4000 µm** Euler–Bernoulli theory. The articular-cartilage-like rectangular compression case (5 MPa, 20 kPa top pressure) converged globally **14.8176 µm → 14.9233 µm → 14.9443 µm** at 40×8, 80×16 and 120×24 mesh. Independent Elmer runs verified that doubling pressure or halving the cartilage modulus doubles the displacement in this idealized linear model. **Corner peak stress did not converge** and is never used as an injury threshold.

Gemini was consulted for an independent numerical-methods critique, SI unit consistency and risks. Source SIFs: `tools/elmer/{bone_cantilever_v1,cartilage_compression_v1}.sif`; solved VTU case IDs, SI values and mesh-refinement data: `docs/anatomy/elmer-fem-results-v1.json`. A bounded strictly offline Godot reader `scripts/physics/anatomy_fem_atlas.gd` exposes this data (Elmer validation **69/69**). The persisted separate Blender anatomy `lifesim-anatomy-skeleton-v1` now includes the FEM JSON and explicit reference metadata in its **editable** `.blend`, with verified fresh-process reopen and unchanged 194-bone rig.

**Important:** Elmer is NOT running in the 60Hz game loop. The FEM patches are idealized **2D rectangles**, not simulations of the actual 3D sculpted joint, cartilage fluid flow, muscle activation, fracture, or live multiplayer ragdoll physics. Full actual methods, cases, results and caveats: `docs/anatomy/ELMER_FEM.md`.

## Elmer muscle/fat and transient thermodynamics — Blender visual pass (26 October 2026)

A new *real standalone Blender* visual upgrade adds **24 sculpturally curved rib meshes, 72 vertebral processes, 60 smoothed muscle bundles with fibrous materials, six manifold volumetric skin-fat envelopes**, two fascia reference strips and five actual Cycles rendered diagrams (including a separately labeled muscle/fat thermal cutaway). See the persisted **`lifesim-anatomy-skeleton-v1`** model asset, `tools/blender/anatomy_visual_soft_tissue_v2.py` and `tools/blender/anatomy_attach_musclefat_thermal_v1.py`. All existing 194 anatomy bones, 17 Bullet bodies and 16 joint constraints remain unchanged. These are stylized art/physics reference shapes rather than patient-specific anatomical segmentation.

ElmerSolver 26.2 **actually solved six** separate conforming **2D muscle+fat** FEM cases (not the above 3D mesh): steady two-layer heat conduction with metabolic sources, Robin heat loss, a 12-minute time-dependent BDF thermal run with tissue specific heats, 2D passive linear elastic tissue compression, and sensitivity to activity, fat thickness and grid refinement. Reference tissue skin-facing surface: **28.741°C at rest, 30.085°C at higher illustrative muscle heat generation, 27.023°C with double the fat thickness** (fixed core 37°C, ambient 20°C, no perfusion/sweat). Transient after 12 min from uniform 37°C: **31.535°C** exposed surface (not yet equilibrium); passive compression under 100 Pa produced **0.285811 mm** maximum displacement norm. The steady-state 2D FEM outputs agree with independent 1D multi-layer analytical heat balance within ~0.001 K.

Reproducible two-body mesh and exact solver inputs: `tools/elmer/build_muscle_fat_v1.py` and `tools/elmer/muscle_fat_*.sif`; solver evidence: `docs/anatomy/elmer_muscle_fat_v1.json`; bounded **offline-only** Godot inspector `scripts/physics/muscle_fat_thermal_reference.gd`; actual **90/90** unit checks in `tests/test_muscle_fat_fem_thermal.gd`; technical report `docs/anatomy/MUSCLE_FAT_THERMAL_V1.md`.

**Not in live game physics:** muscle contractions, nonlinear fat mechanics, blood perfusion, sweating, a complete 3D joint FEM or a medically validated temperature model. Existing production gameplay/network authority remains unchanged.

## Real 3D finite-element muscle-fat study (27 October 2026)

The latest anatomy reference now includes **five genuine 3D ElmerSolver 26.2 runs** on a **shared-node conforming 3D two-volume Hex8 mesh** (muscle 25 mm, fat 10 mm, 12 mm × 10 mm cross-section), converted from Gmsh 2.2 by ElmerGrid. This advances the previous flat **2D** benchmarks to actual three-dimensional FE elements; it is **still only a flat two-material laboratory reference**, **not** FEA on the anatomical Blender human model. The standard Rest thermal 3D simulation resolves **301.89125 K (28.74125°C) skin temperature** on 208/900-node coarse/refined grids and matches the independent 1D steady-state analytic solution. The active-muscle-heat scenario resolves **303.235 K**, a 720-second BDF1 transient resolves **304.684 K**, and 3D three-displacement-DOF linear elastic stress yields **0.282131 mm** max displacement under 100 Pa skin-side traction (not 100 N). None of these results imply clinical thermoregulation, joint injury, actual muscle actuation, blood perfusion, or running Elmer per game frame.

A **true 3D Elmer thermal VTU field**, with all 208 source node temperatures and 108 Hex8 cell geometries, has been transferred into the persisted standalone Blender model asset `lifesim-anatomy-skeleton-v1` as an explicitly labeled, **hidden-by-default diagnostic 3D collection**. Original source nodes/temperatures are available in `elmer_mfat_3d_field_v1.json`. A Cycles render `anatomy_elmer_actual_3d_temperature_v1.png` and an independently reimported vertex-colored `anatomy_elmer_actual_3d_temperature_v1.glb` show two sealed muscle/fat surfaces using the actual solved Kelvin vertex data. Original human anatomy 194-bone rig/60 muscle references/6 fat volumes/17 rigid bodies/16 constraints remain unchanged.

Reproduction: `tools/elmer/build_muscle_fat_3d_v1.py` (actual verified runnable Hex8 Gmsh/SIF generator); the visualization source `tools/blender/anatomy_elmer_3d_field_visual_v1.py`; numerical record `docs/anatomy/elmer_muscle_fat_3d_v1.json`; **88/88** automated assertions `tests/test_muscle_fat_3d_fem.gd`. All 5 remote cases and complete technical/validation limitations: `docs/anatomy/ELMER_3D_HEAT_AND_STRESS_V1.md`. **Live Godot body/physics and authenticated multiplayer are not modified.**

## Anatomical skeleton, muscle, cartilage and fat layers on the ACTUAL character in game (27 October 2026)

**Playable visual integration delivered.** Select a character in the game and click the new right-hand HUD button **Anatomie: Vypnuto** (Anatomy: Off) to switch its in-world model to animated **Kostra → Svaly → Chrupavky → Tuk → Všechny vrstvy → Vypnuto** (Skeleton → Muscles → Cartilage → Fat → All layers → Off). An independent `Anatomie` chooser exists in both the creator and editor's 3D character preview. These modes are *client-local and purely visual*: the underlying authenticated player/NPC, hair/clothing/skin and gameplay skeleton remain intact, and turning anatomy off restores the original appearance. The extra geometry is not loaded for normal characters unless explicitly chosen.

This uses **real coordinates extracted from the persisted 194-bone Blender anatomy asset** `lifesim-anatomy-skeleton-v1/anatomy_skeleton_v1.blend`, together with 60 measured original muscle endpoints, 60 cartilage locations, six fat volumes and their 17-driver mapping. Source data `assets/anatomy/anatomy_runtime_proxy_v1.json` are converted Blender Z-up → Godot Y-up and drive **320 low-detail 3D render proxies bound to the 17 real animated BoneAttachment3D drivers** of each individual player's actual `character.glb`. Arms and other modeled sections genuinely follow the existing idle/walk/sit/lie animation and character morphs. Importantly, **this is NOT yet the original high-detail 201 sculpted bone meshes nor 194 independently physical joints**: muscles and fat are approximated on screen as anchored cylinders/ellipsoids, not fully joint-deforming soft tissue or active Elmer physics. The original Blender sculpt remains available as a separate source asset.

New code: `scripts/assets/anatomy_overlay.gd`, `scripts/sim/sim_visual.gd` local mode, `scripts/ui/hud.gd` live HUD button and `scripts/ui/character_preview.gd` selector. An actual playable household/real Skeleton3D integration test `tests/test_live_anatomy_overlay.tscn` **76/76 PASS** checked all 320 parts, 17 bone attachments, actual arm-pose animation following, layer switches, restoring original clothing and isolated per-character rendering; all creator/editor/world/network regression tests remain green. Full evidence and remaining modeling/physics caveats: `docs/anatomy/IN_GAME_ANATOMY_OVERLAY_V1.md`. No gameplay physics, savegame, privacy fields or network authority changed.

## C15: genuine 28-phalange Godot subrig on an animated person (27 October 2026)

The optional anatomical hand diagnostic now has **two separately articulated fourteen-bone Godot Skeleton3D subrigs** (28 true *runtime bone transforms* total), using the original real Blender anatomical hand landmarks in `assets/anatomy/anatomy_runtime_proxy_v1.json`. Each follows an existing animated **hand_l/hand_r** bone of the actual 17-bone game avatar through `BoneAttachment3D`. There are 28 individually bone-attached procedural 3D surfaces, each following their own proximal/middle/distal skeletal joint; in opt-in **Kostra článků prstů: zapnuto**, the pre-existing combined or proximal/distal controls animate the actual new skeleton. Opt-out restores the original finger skin and nail visibility and does not alter the production 17-bone rig.

This is a **real hierarchical in-game finger skeleton, but still an optional local anatomy visualization**. The detailed standalone Blender bone GLB remains separate; these 28 shapes are simple 3D bone proxies, and there are **no 28 live physics rigid bodies, collisions, force-controlled grasp, IK, Elmer skin stress or network API changes**. Feature source `scripts/assets/finger_phalange_subrig_c15.gd`, engine integration `scripts/sim/sim_visual.gd`, UI `scripts/ui/character_preview.gd`, verification `tests/test_finger_phalange_subrig_c15.tscn` **39/39 PASS**, full scope `docs/anatomy/C15_REAL_GODOT_FINGER_SUBRIG.md`.

## C14: independent finger bends, 20 new channels and Blender bone animation (27 October 2026)

Character creator/editor 3D preview now supports **two independently configurable bend regions for each of ten fingers**, in addition to the previous ten combined curl sliders. Expand `Prsty: jednotlivě` then `Klouby prstů: základní / střední` to edit new 20 independent 0.01-step channels. This actually deforms both the GPU-skinned finger mesh and corresponding nail plates, without bending other fingers or breaking five preset gestures. Each hand mesh now has **40 blend shapes** (10 public body morphs, 10 legacy digit curls, 20 newly added independent joint-region bends). Exact bone mechanics are **not** simulated in Godot; this is still a two-region additive approximation of knuckle and interphalangeal bending, preserving the original gameplay 17-bone Skeleton3D and authenticated multiplayer.

**Separately in editable Blender**, the original **194-bone anatomy** truly has 28 individually skinned/animatable finger phalange bones. A new 28-mesh bone-following demonstration and real 6-keyframe pose action (`Anatomy_C14_IndependentFingerJoints`) were persisted and exported as `anatomy_independent_finger_joints_c14.glb` (500,796 bytes). Fresh-process Blender inspection verified all 28 3D phalanx meshes, 194-bone GLB reimport and actual animated bone pose movement, while preserving all previous anatomy and constraints. **The Blender multi-bone hand is not yet live-retargeted into the game's 17-bone rig.**

New `tests/test_independent_finger_joints_c14.tscn` **35/35 passed**, previous hand surface/nails **113/113**, torso details **63/63**, actual anatomical overlay **76/76**, editor **61/61**, multiplayer **67/67**, live ENet owner **56/56** and playable **48/48**. Reproducible Blender script: `tools/blender/anatomy_finger_joint_animation_c14.py`; full results and limitations: `docs/anatomy/C14_INDEPENDENT_FINGER_JOINTS.md`. No new save/network schema or server gameplay hand physiology.

## C13: sculpted closed torso skin and real 3D navel relief (27 October 2026)

For the playable game, `scripts/assets/anatomical_torso_surface.gd` now constructs an **independent 2162-vertex, 4320-triangle watertight skin torso** rather than reusing the original 830-vertex clothing shirt as the bare skin surface. It has proper separate chest/flank/back geometry, softly weighted original spine/chest animation joints, ten public body morphs, continuous surface color, and a genuinely **recessed 3D navel** rather than an unchanged flat skin surface with a shaded dot. Previous paired areolae, projecting nipples and other anatomical overlays remain compatible. **Performance:** this cost is lazy, incurred only upon an explicit `Bez vrchního dílu (anatomie)` selection, then shared as cached geometry; dressed NPCs no longer allocate an unused separate skin mesh.

The persistent independent Blender `lifesim-anatomy-skeleton-v1` asset now also contains `Torso_Skin_C13`: a matching **new editable 2162-vertex / 4320-triangle** closed and spine/chest-weighted anatomical torso mesh with a genuine sculptural umbilical recess. A separate `anatomy_torso_skin_c13.glb` (198,788 bytes) was genuinely exported and reimport verified with the unchanged 194-bone anatomy rig, and a corrected `anatomy_torso_skin_c13_review.png` Cycles render was visually reviewed after fixing overexposed lighting. Blender creation source: `tools/blender/anatomy_torso_skin_c13.py`. The independent Blender GLB is *not* yet substituted for production `character.glb`; this matching in-game surface is generated procedurally using original production morphs.

New `tests/test_torso_surface_c13.tscn` **24/24 passed**, checking manifold closed topology, UVs, normalized spine/chest weights, >4.5mm true inward navel relief, morphs, animations, visibility restoration. Previous C12 anatomy-fingers **63/63**, live overlay **76/76**, appearance editor **61/61**, body morph **62/62**, full playable **48/48**, multiplayer **67/67**, ENet owner **56/56** and syntax **60/60** passed. Still *not* fully detailed clinical skin, separately articulated fingers, tissue contact, or live ElmerFEM. See `docs/anatomy/C13_CLOSED_TORSO_NAVEL.md`.

## C12: fingers, nipples and navel — live in-game model (27 October 2026)

Added actual skinned body details to the playable 17-bone character in Godot, independently of character gender: a new skin-colored anatomical trunk proxy from the real Blender-authored **830-vertex/10-body-morph** top mesh, **two 3D areolae, two gently protruding papillae, a raised umbilical rim and darker centered navel relief**. They share the original `Skin`, update with existing fat/chest/bust/height and skin-color morphs, and are **hidden under every normal top garment**; to reveal, select **`Bez vrchního dílu (anatomie)`** in the character editor's active outfit. Normal gameplay appearance and clothing remain unchanged. These are visual anatomy, not simulated physiological nipples or a topologically cut body cavity.

The character creator/editor's isolated 3D preview now has expandable **`Prsty: jednotlivě`** (Fingers: individually) with ten independent 0–1 finger bend sliders and .01 precision. Each uses the existing GPU finger and corresponding nail morph; the five gesture presets still work and synchronize the sliders. Existing ten toes and toenails, hand/foot animation, 17 production animation bones and owner-only authenticated multiplayer remain untouched.

Blender editable `lifesim-anatomy-skeleton-v1` additionally contains 26 fully modeled rigged skin-detail objects: paired chest features, ringed navel, ten independent fingernail plates and ten toenail plates, exported as `anatomy_skin_and_nails_v1.glb` and verified via fresh-process reimport and 194-bone rig. No 3D FEM is yet attached to those surfaces.

**62/62 new integration assertions passed**, alongside actual in-game anatomy 76/76, first-playable 45/45, character editor 55/55, native network editor 56/56, network schema 70/70, morphs 62/62, syntax 60/60. Sources `scripts/assets/torso_detail_builder.gd`, `scripts/assets/hand_detail_builder.gd`, `scripts/sim/sim_visual.gd`, `scripts/ui/character_preview.gd`, `tools/blender/anatomy_skin_and_digit_nails_v1.py`; full scope and limitations `docs/anatomy/TORSO_FINGERS_NAVEL_C12.md`.

## Saving and loading (offline mode)
In the actual single-player GUI, the household **autosaves every 5 real minutes** and each game-day rollover. The latest autosave loads automatically at the next launch. Use **F5** or HUD **Save game** to write a separate manual save; **F9** loads the autosave, **Shift+F9** loads the manual save, and the HUD offers both Load buttons. A close-window event also attempts one final save. Files remain local under `user://saves/` (usually your operating system's Godot app data path), with a previous-valid `.bak` fallback if the primary is corrupt. Saves contain private character and psychological data and are **not encrypted**; do not publish them. Dedicated servers, multiplayer hosts and clients are **not yet supported** by this first H4 offline version. Headless test sessions never auto-load real user saves by default. See `docs/reviews/h4-save-autosave-20261025.md`.

## Running the tests

Every system has an automated test in `tests/`. Each test is a scene that exits with code 0 on success.

```bash
godot --headless --path . res://tests/test_mental_health.tscn
godot --headless --path . res://tests/test_character.tscn
# ...see docs/testing.md for the full list

# Long-run simulation check (14 game days)
godot --headless --path . -- --test 14

# Household balance across 16 seeds × 14 days (about 75 s)
godot --headless --path . res://tests/test_household_dynamics.tscn

# Crowded households: 4 / 6 / 8 characters × 4 seeds × 30 days (slow, ~25 min)
godot --headless --path . res://tests/test_household_matrix.tscn
```

## Documentation

| Document | Contents |
|---|---|
| [Vision & content policy](docs/vision.md) | Tone, design pillars, what the game does and does not depict |
| [Architecture](docs/architecture.md) | Autoloads, simulation loop, agents, planner, scenes, folder layout |
| [Character creator](docs/character-creator.md) | Data model, schema, validation, body, face and skin systems, C1–C8 plan |
| [Mental health](docs/mental-health.md) | Stress, anxiety, panic, depression, coping, safety rules, content settings |
| [Relationships](docs/relationships.md) | Social interactions, grudges, guilt, apologies, household dynamics and its measured balance |
| [Multiplayer](docs/multiplayer.md) | Authoritative server, protocol, privacy, validation, rate limits |
| [Asset pipeline](docs/asset-pipeline.md) | Blender bridge, LSX format, GLB import, visual verification |
| [Audio](docs/audio.md) | Synthesizer, music, ambience, anxiety audio, building the WAVs |
| [Testing](docs/testing.md) | Test suite, how to run it, what each test covers |
| [Roadmap](docs/roadmap.md) | Done, in progress and planned work |
| [Development process](docs/development-process.md) | Automated runs, checkpoints, review by multiple AIs, audits |

## Repository layout

```
main.gd / main.tscn     Main scene: builds the lot, household, camera, HUD; network session; headless test
scripts/core/           Autoloads: GameClock, GameSettings (content settings), Czech grammar helper
scripts/sim/            Simulation: agents, needs, mood, traits, utility AI, mental state, depression, relationships
scripts/psyche/         Psyche model: personality, dispositions, condition profiles, modulations, explanations
data/conditions/        Mental-health condition profiles as data (JSON)
scripts/character/      Character creator back-end: data, schema, validator, codec, randomizer, morphs, skin
scripts/assets/         Runtime asset library, LSX decoder, procedural head, character assembly, animations
scripts/net/            Multiplayer session and protocol validation
scripts/audio/          Synthesizer, music data, sound recipes, AudioManager
scripts/world/          World builder, smart objects, camera, day/night, PsycheFX
scripts/ui/             HUD, settings menu (content settings, crisis help)
shaders/                Skin shader (subsurface scattering, procedural skin layers)
assets/src/             Source meshes from Blender in the LSX transfer format
assets/models/          Imported GLB models and manifest
audio/                  Rendered music and SFX (generated, not in git)
tools/                  Build tools: audio render, LSX import, preview rasterizer, Blender scripts
tests/                  Automated tests (one scene per system)
DEVLOG.md, AUDIT.md,    Working journals of the automated development runs (currently in Czech)
ROADMAP.md, CHECKPOINT.md
```

## Language

- Documentation, repository metadata and commit messages are in **English**.
- The game's player-facing text is in **Czech**, and so are most code comments. The Czech grammar system
  generates verb and adjective forms from each character's chosen grammatical gender.
- `DEVLOG.md`, `AUDIT.md`, `ROADMAP.md` and `CHECKPOINT.md` in the root are the live working journals of
  the automated development runs and stay in Czech for now. [docs/roadmap.md](docs/roadmap.md) is the
  maintained English version of the roadmap.
- Translating the code comments and adding an English localisation of the game are planned.

## License

No license has been chosen yet. Until one is added, all rights are reserved by the author.