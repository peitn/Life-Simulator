# Review – crowd LOD step 7: procedural body parts (18 Nov 2026, evening)

Run: `main-claude-20261118b-proclod` (scheduled). Scope: fingers + nails, bare feet + toenails, bare torso (5 meshes).

## Finding that changed the plan
`HandDetailBuilder._bake` (shared by hands, feet and torso) built its meshes in `BLEND_SHAPE_MODE_RELATIVE` with
*delta* targets, including delta normals (all-zero for the ten body morphs). Godot stores blend-shape normals
octahedrally, so they are always unit length after decoding; the skinning compute shader
(`servers/rendering/renderer_rd/shaders/skeleton.glsl`) then evaluates

- NORMALIZED: `v = (1−Σw)·base + Σw·target`, `n = normalize((1−Σw)·n + Σw·dec(target_n))`
- RELATIVE: `v = base + Σw·target`, `n = normalize(n + Σw·dec(target_n))`

A zero normal delta decodes as (0, 0, −1), so every non-zero body morph weight pulled the normals of fingers,
feet and torso towards −Z. Measured on a random adult character with typical body weights
(`tools/diag_procedural_blend.gd`): finger skin normals tilted by **77.6° on average (max 178.7°)**, foot skin
50.0° (max 155.3°) – at full detail, i.e. visible in normal play (lighting on hands/feet/torso was wrong).
The step-6 baker (`LodBake`) also assumed NORMALIZED semantics, so a barefoot or topless character at tier 2
would have been baked with wrong positions (error up to 2.9 m on the fingers).

## Changes
1. `scripts/assets/hand_detail_builder.gd`: NORMALIZED with absolute targets (rest + delta; body-morph target
   normals = base normals; curl/joint targets = rotated positions and normals, untouched vertices = rest).
   Positions are identical to before. New `morph_delta(mesh, shape, i)` for convention-independent tests.
2. `scripts/assets/lod_bake.gd`: records the mesh's blend-shape mode and reproduces the shader in both modes.
3. `scripts/sim/sim_visual.gd`:
   - hands are no longer excluded from tier-2 baking;
   - `set_finger_curl` / `set_finger_joint_bend` (and thus `set_hand_pose`) call `_lod_touch_hands()` – only the
     hands go back to their original mesh with exact weights, the rest of the character stays baked;
     a stale job result for the hands is rejected by `_lod_swap` (weights no longer match);
   - `finger_joint_values` reads through the new `lod_blend_value()` – no un-baking on reads;
   - `_lod_refresh()` schedules a bake for parts that became visible (shower shows feet, bare torso,
     leaving the finger-skeleton view) without un-baking anything;
   - procedural meshes go through `CharacterLod.with_lods`: finger skin 3 040 → 1 520/760/380/190 triangles,
     foot skin 2 928 → 1 464/732; every level keeps the exact border (finger roots, foot rim); nails (80 tris)
     stay below the threshold.

## Verification
- `tests/test_procedural_lod` (new) **81/81**: RELATIVE/NORMALIZED baking vs. analytic values and an independent
  shader reproduction; all 9 procedural meshes NORMALIZED with unchanged GPU normals under active body morphs
  (max 0.000°); curls move only their digit; LOD levels decrease with identical borders; real barefoot topless
  character at tier 2: everything baked incl. hands/feet/torso, baked = shader reproduction (7e-7 m, 0.006°),
  pose at tier 2 un-bakes only the hands (20 other parts stay baked) and re-bakes, shower bakes newly visible
  feet, back at tier 0 the original meshes with exact weights; warm finger bake 3.2 ms.
- Regression: test_lod_bake 54/54 (updated: hands now baked), test_character_lod 76/76, test_facial_lod1 126/126,
  test_wardrobe_async 41/41, test_full_playable_slice 87/87, test_live_character_edit 38/38, test_character 157/157,
  test_torso_fingers_v1 63/63, test_torso_surface_c13 24/24, test_finger_phalange_subrig_c15 54/54,
  test_independent_finger_joints_c14 35/35 (was 34/35 – stale 510-vertex assertion fixed),
  test_finger_curl_pose 157/157 (stale 51-vertex grouping fixed), test_hand_detail_geometry 115/115,
  test_barefoot_geometry 30/30, the four isolated procedural-LOD tests 942/11/12/7, `godot_check` 60/60.
- test_anatomy_review_v9: 249/251 – the 2 failures (schema v8/v17 → "v18" migration expectations) exist
  unchanged in the pre-change version and are unrelated (schema has moved past v18).
- No GPU render (no xvfb on the server); correctness verified numerically against the shader formula.

## Independent review
- Gemini 2.5-flash (partial answer before the service hit "high demand"): no critical or serious findings;
  one medium note – in RELATIVE mode every vertex enters the sparse key because decoded target normals are
  unit length. Rejected as intended: the baked mesh must match what the GPU computes, and no game mesh uses
  RELATIVE any more. Further attempts (3.5-flash, 2.5-flash, default) returned "high demand".
- Gemini 2.5-flash, second pass (focused on SimVisual), 5 findings:
  1. *freed instance during a bake → crash* (marked high) – **rejected with evidence**: `_lod_bake_finish` skips items whose node is no longer valid (`is_instance_valid`) and `_lod_swap` checks it again; covered by test_lod_bake "node freed during bake" and test_wardrobe_async "visual freed while waiting".
  2. *weights changed and changed back during a job → intermediate shape applied* – **rejected**: a bake is a pure function of (source mesh, weights); `_lod_swap` only applies it when the instance shows the same mesh with exactly the same weights, so the result is the correct current shape.
  3. *frequent finger animation would keep un-baking the hands* – **accepted as a documented limitation**: today hand poses are only set on demand (UI, gestures), never per frame; if per-frame finger animation is added, hands at tier 2 must be excluded again (or the animation frozen at tier 2 like facial expressions).
  4. *linear search over 40 key names in `lod_blend_value`* – **rejected**: it is only used by `finger_joint_values` (editor/skeleton view), not per frame; 40 string compares are negligible.
  5. *a part hidden during a bake still gets the baked mesh* – **rejected**: harmless, the baked mesh has the correct shape when the part is shown again.
- ChatGPT (AI room): no reply during the run.
