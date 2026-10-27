# H2b — Modeled fingers, nails, barefoot soles and toes

**Live Godot project:** `lifesim` • 26 October 2026 • run `main-anatomy-hands-1793040922-255607`.

Work done with the cooperative v3 main lease; read current checkpoint and implementation sequence, edited character-only files, no city-owned folders, no external GitHub publication, no CharacterData or network authority schema changes. Source backups before the prior visual project work remain available; a new backup is taken after final regression.

## Actual new geometry (not just UI sliders)

The original authored body has **no independent digits**: the mesh ends at rounded palms (~0.806 m model Y), and when the shoes are hidden the existing build lacked a suitable barefoot sole and toes. The 17-bone character rig contains only `hand_l/r` and `foot_l/r`, not separate phalange chains. These assets are generated reproducibly in Godot (no claim that Blender GLBs were rebuilt).

- New `scripts/assets/hand_detail_builder.gd`: builds **four unequal fingers plus a splayed thumb per hand** (ten distinct digit tubes) and **ten individual curved nail plates**. The geometry is genuinely meshed and skinned with 100% influence from the correct existing left/right hand bind (indices 7 and 13). The shared skin mesh has **510 vertices**, nail surface **90 vertices**. Round-capped tapered surfaces with no collapsed triangles; all outward normals and triangle windings checked. Narrow/wide natural digits share body skeleton transforms when elbow/hand moves, do not become static overlays.
- New `scripts/assets/foot_detail_builder.gd`: builds **two barefoot soles, left/right ankle bridge, five unequal toes on each foot and ten toenail plates**. Uses only corresponding `foot_l/r` bind indices 10 and 16. The sole/bridge overlaps the trouser hem to reduce the previously visible empty ankle cavity. These are shown **only when outfit shoes is `bosy`** and hidden again for sneakers, platforms, boots etc. Toes are geometry, not shoe recoloring. Outward normals and no collapsed faces tested.
- Both parts inherit the exact **ten existing body blend-shape fields** by transferring 4 nearest original skin/shoe vertices from the same side only, then are updated by `SimVisual.apply_body_shape()`. Shared `ArrayMesh` buffers are created once and cached; each actor gets **its own Skin and its own materials**. Continuous skin pigment color and subdued separate nail plate colors update from public `AppearanceResolver` data; no identity/grammatical gender/sexuality/mental state is used. No new save file fields, schema version bump, or RPC messages.
- Existing C5 garment and hair pipelines are otherwise unchanged. The runtime `scripts/sim/sim_visual.gd` creates/skinfollows 2 hand mesh instances and 2 barefoot mesh instances per actor and controls footwear visibility.

## Real validation

New automated GDScript tests:
- `tests/test_hand_detail_geometry.gd`: **53/53** headless including correct 10 digits, 10 nail plates, all 10 morphs per mesh, normalized side-specific bone weights, no degenerate/wrong-facing triangles, skin tone, isolated character Skin, left/right elbow animation, independently updated nail material.
- `tests/test_barefoot_geometry.gd`: **30/30** headless including two soles + ten toes and toenails, consistent left/right foot binds, 10 morphs, clear/unhidden based on shoe choice, no shoe clipping of toe meshes, pigmentation, independent left shin bone rotation, correctly-facing triangles.
- Via actual **graphical Godot GL Compatibility** in Xvfb: hand preview **56/56** and foot preview **34/34** with real JPG framebuffers and source locations:
  - `previews/main-anatomy-hands-1793040922-255607-hand-rest.jpg`
  - `previews/main-anatomy-hands-1793040922-255607-hand-elbow.jpg`
  - `previews/main-anatomy-hands-1793040922-255607-feet-bare.jpg`
  - `previews/main-anatomy-hands-1793040922-255607-feet-oblique.jpg`
  - `previews/main-anatomy-hands-1793040922-255607-feet-shod.jpg`
- Existing after-addition regressions actually run: appearance UI108/108, first playable45/45, offline editor55/55, body morph62/62, face details66/66, C5 clothing16/16, character preview13/13, save game46/46; native ENet character schema70/70, live owner editor27/27, native host edit10/10, entire C5 wardrobe integrity7046/7046. Godot syntax checker 60/60 existing scripts clean, new scripts executed separately.

### Debugging and visual observations (not hidden)

Initial generator returned empty meshes because PackedArray append on temporary Dictionary values did not persist; corrected explicit writeback. First composed body-morph arrays had zero-length blend vertex lists for the same reason; corrected. After resolving, geometry built and all tests passed. Triangles on nails initially faced inward (80 inverted per skin nail mesh), and rear/front ankle caps had reversed winding; both corrected and verified with geometric face-vs-vertex normal orientation tests. The barefoot screenshot initially displayed a dark cavity near the ankle; added a genuine skin-matched, capped tapered ankle bridge. Final real software-rendered screenshots show hand digits and toes, but **the ankles still have a visible ring seam** due to overlap with legacy trouser/foot geometry. Barefoot shapes and cuffs remain stylized/simple and need polish. The photo zoom/rasterizer used here is not final renderer certification.

## Limitations and next art pass

The individual fingers and toes are **not independently animated**: the existing 17-bone rig permits correct hand/foot pose motion only, not curling fingers, gripping, toe extension or individual digits. Fingernail/toenail length, individual finger size, foot width and forefoot sliders are **not yet exposed** or stored in CharacterSchema. These would require new authoritative continuous body axes with versioned CharacterCodec migration, deterministic appearance resolution, morph/rig target mapping, and save/network privacy tests.

Full physically continuous finger/palm skin, shoes/sole collisions, nail microtextures, stronger topology/SSS polish, nipple/navel geometry, broad animation deformation, and release/full-browser visual certification remain open. The base skin uses a detailed separate SkinLayers shader, but new hand/foot parts currently use skin-colored StandardMaterial3D instead of the same full microtexture shader.

This is substantial partial functional H2b anatomy work, **not completion of the user's entire anatomy list**.
