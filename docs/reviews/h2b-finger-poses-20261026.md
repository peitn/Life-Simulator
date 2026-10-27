# H2b independently poseable fingers (procedural flex morphs), live preview and real GPU render — 26 October 2026

Work executed directly in canonical `lifesim` Godot 4.7.2 under cooperative `main` lease `main-anatomy-c9-1793043452-267414`. Read CHECKPOINT, implementation sequence, lock policy, ROADMAP, previous hand review. Backed up project before writes, never touched city-owned folders, no GitHub push. **This is genuine per-digit geometry deformation, not new skeletal phalange chains.**

## Implementation

The previous procedural hand mesh had ten visible individual fingers and nail plates but they were bound entirely to `hand_l/r`, so could not perform different gestures. Now `scripts/assets/hand_detail_builder.gd` adds **ten extra independent named GPU blend shapes** `finger_curl_0`.. `finger_curl_9` to each of the two actual hand geometry surfaces. The original **ten body morph keys remain in their original indices 0..9**, and the bend shapes follow at indices 10..19. Right-hand digits 0..4 and left-hand digits 5..9; within each hand: index, middle, ring, pinky, thumb.

Each target contains a two-stage, anatomically oriented curl deformation (knuckle and intermediate-bend approximation), including rotated vertex normals. Only vertices of that particular digit change; the other nine digits have zero displacement. The corresponding 3D nail plate uses the *same* deformation for its digit so it remains attached. Absolute skin/torso target morphs are transferred as **relative displacements** for new procedural meshes.

**Bug fixed after genuine rendered inspection:** Previous procedural mesh builder set `BLEND_SHAPE_MODE_RELATIVE` but incorrectly encoded **absolute positions** for its target arrays. A single active curl shifted the entire hand; multiple simultaneous curls made all fingers disappear off-screen. Rewrote all body + finger/foot targets to carry **true target minus base deltas** and normal differences, then reran tests and made new graphical captures. This also corrects previous barefoot body-target encoding from the same `_bake` helper.

In `scripts/sim/sim_visual.gd`:
- `set_finger_curl(side, index, 0..1)`: real independently controlled deformation with strict side/index/numeric bounds, both skin and nail material meshes updated. Invalid input returns false without editing any morph.
- `set_hand_pose("open" | "relaxed" | "fist" | "point" | "pinch")`: five deterministic render-only presets. Default relaxed. Fist is **stylized and not yet a closed, realistic knuckle-to-palm grip**, despite an actual morphological curl.
- Actor-specific mesh instance weights remain isolated while immutable source ArrayMesh buffers are shared. No fields are added to CharacterData, no server-authoritative gameplay input is bypassed, and gestures do not leak to other network users automatically.

In `scripts/ui/character_preview.gd`, creator/editor 3D preview now offers a **Ruce** (Hands) dropdown with 5 poses and **Detail ruky / Celá postava** (Hand detail / Full character) camera control, separate from the draft/Apply/Cancel/Undo/Redo flow. Preview gesture is local-only and **does not persist into the save or multiplayer**, intentionally. This is a visual gesture control, not a stored finger-length or joint-angle slider.

## Tests and real visuals

New `tests/test_finger_curl_pose.gd`: **157/157 headless assertions, 162/162 graphical**. Tests all 10 unique morph names and correct slots on both skin and nails, per-digit target boundaries and no movement of other nine fingers, normalized values, invalid argument rejection, full pointing/open/fist/pinch presets, per-character mesh-instance isolation with shared geometry, actual UI dropdown, read-only preview draft/privacy and close-up camera. Existing `tests/test_hand_detail_geometry.gd` adapted to 10 body + 10 finger morphs and passed **73/73**; `tests/test_barefoot_geometry.gd` passed **30/30**.

Four real framebuffer screenshots from Godot GL Compatibility under Xvfb, rendered at close-up and visually inspected:
- `previews/main-anatomy-c9-1793043452-267414-fingers-open.jpg`
- `previews/main-anatomy-c9-1793043452-267414-fingers-fist.jpg`
- `previews/main-anatomy-c9-1793043452-267414-fingers-point.jpg`
- `previews/main-anatomy-c9-1793043452-267414-fingers-pinch.jpg`

First captures actually showed missing fingers in fist/point and led to the aforementioned **relative-blend displacement fix**. Second captures show genuine differences in finger positions between poses while skin and nail meshes remain visible. Fine hand sculpting, wrist transition and high-quality photographic articulation **still need improvements**.

Existing post-change regressions, all exit0 and 0 failure: `test_full_playable_slice` 45/45, `test_character_editor_ui` 55/55, `test_appearance_slider_ui`108/108, `test_body_morphs`62/62, `test_face_detail`66/66, `test_character_preview`13/13, `test_clothing_c5`16/16, `test_save_game`46/46, `test_character_net`70/70, true ENet owner editor27/27, host10/10, full wardrobe7046/7046; Godot 60 existing scripts syntax OK. Pre-existing GL Compatibility renderer warnings (SSS unavailable) and 18 ObjectDB cleanup instances remain unrelated.

## Open gaps

- Real 3-bone fingers per digit, joint constraints, IK and physics-driven grips are NOT implemented. This stage has ten **individually addressable flexion morphs**, not full digital skeletal articulation. Separate finger/foot size, toe length and nail-length sliders require versioned CharacterData/Codec, server allow-list and storage tests.
- No complete navel/nipple anatomy or clothing/rig collision signoff. Original sleeve cuffs and bare ankle seam still remain visibly stylized in renders.
- Further real animation interpolation, nail-surface shader integration and extreme profile visual QA needed. Web browser link problems on the user's Android aren't guaranteed resolved by this anatomy patch.
