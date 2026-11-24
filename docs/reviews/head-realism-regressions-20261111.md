# Head geometry after the realism pass – regressions vs. intended detail (11 November 2026)

Run `main-claude-1794381713-319961` (Claude, scheduled). Source: the QA audit of 10 November (§4.1) and
Grok's request #432 to separate real regressions from intentional detail increases.

## Findings (diagnosed on the live server project)

| Test | Before | Cause | Classification |
|---|---|---|---|
| `test_head` blend accuracy, extreme combinations | max 7.47 mm (limit 5) | New nostril/alar concavities (3.5 mm deep, σ 1.8 mm) whose position moves with nose length and tip angle (up to ±9 mm). A narrow Gaussian that moves further than its own width cannot be represented by summed linear blend shapes. | **Regression** – fixed |
| `test_head` flipped faces | 9 (limit 2) | (a) 2–4 faces under the nose (same cause, visible); (b) 1–4 thin slivers of the posterior eye-socket cap (`ec`, material `eye_socket`, < 1 mm², behind the eyeball) that flip already in the exact shape when `eye_tilt` is ±1. The cap uses a square parameterisation (max(\|a\|,\|b\|)) that projects inner points into the almost-degenerate eye corner; the finer lattice put more cap faces there. | (a) **regression** – fixed; (b) **pre-existing parameterisation defect**, made more visible by the denser mesh – isolated, open |
| `test_head` budget | 18,302 > 11,500 | Intentional density increase | **Accepted** as LOD0 budget (19,000) |
| `test_assets` budget | 27,418 > 20,000 | Same | **Accepted** (28,500) |
| `test_hair` budget | 26,034–39,525 > 26,000 | Hair cards grow from the finer scalp | **Accepted** (40,000) |
| `test_neck_seam` flipped neck triangles | 7 of 905 | Only with a lateral neck bend of −20° and `neck_length` −1: seven ~40–50 mm² triangles at y ≈ 1.556–1.560 m on the compressed side fold under linear blend skinning. Morphs alone flip nothing. | **Open** (skin weights in the bend region) |
| `test_neck_seam` "collar" | 2.9 mm step (limit 2.5) | The step is in the top rows at 60°/300°, where the horizontal ray reaches the jaw underside; the lower seam band is smooth. | **Open** – likely test geometry, needs a render to confirm |

## Changes

- `scripts/assets/head_builder.gd`: nostril depth `NOSTRIL_DEPTH` 2.4 mm with σ 3.4 × 3.0 mm; softer columella
  and alar crease. A height-field model of the nose (all five nose fields at random extremes, the game's
  in-between and corrective approximation) shows non-linearity dropping from 6.0 mm to 1.5 mm.
- `scripts/character/face_morphs.gd`: new corrective pair `nose_length × nose_tip_angle` (both move the
  base of the nose). The builder creates the quadrant shapes only where they exceed 0.3 mm.
- `character.glb` rebuilt with `tools/rebuild_character_realism.gd` (revision `2026-11-11-v4`).
- `tests/test_head.gd`: visible flipped faces must be **0** (previously "≤ 2 of any kind"); only cap slivers that
  are `ec` vertices, `eye_socket` material and smaller than 1 mm² are counted separately (limit 6), any larger
  cap fold counts as visible. Budget constant `HEAD_TRI_BUDGET` = 19,000.
- `tests/test_assets.gd`, `scripts/assets/hair_builder.gd` (`BUDGET_SCALP`): budgets above.

## Results after the fix (server, 11 November)

| Suite | Before | After |
|---|---|---|
| `test_head` | 40/43 | **43/44** – extreme blend error 7.47 → **3.88 mm**, typical faces 1.72 mm, no flipped face under the nose any more; 89 head blend shapes (97 names in the GLB). The one failure is the eye-socket cap: besides the < 1 mm² slivers (max 3, within the separate limit) one cap face of 1.6–5 mm² next to ring 5 near the canthus still flips in 11 of 48 samples. It is counted as visible on purpose and left failing until the cap is re-topologised. |
| `test_assets` | 153/155 | 154/155 – remaining failure is the sitting pose (pelvis 0.60 m vs. sofa seat ~0.44 m), unrelated to geometry budgets |
| `test_hair` | 59/60 | **60/60** |
| `test_neck_seam` | 54/56 | 54/56 (unchanged, open – see above) |
| `test_skin` | 60/61 | 60/61 (unchanged; "other meshes unchanged" check, not investigated) |
| `test_character_editor_ui` 68/68, `test_save_game` 46/46, `test_clothing_c5` 16/16, `test_host_character_editor` 10/10, `test_mp_reconnect` 72/72, `test_face_detail` 66/66, `test_skin_micro` 50/50, `test_neck_length` 36/36, `test_body_morphs` 62/62, `test_live_anatomy_overlay` 76/76, `test_torso_surface_c13` 24/24, `test_full_playable_slice` 87/87 | | pass |

Blender check: `docs/images/head-nose-20261111.jpg` (Cycles, rows from bottom: default; long nose + tip up; short nose
+ tip down; long + tip down + wide + bulbous tip; short + tip up + narrow + high bridge; columns front / from below
/ three-quarter). No folds, holes or dark disks under the nose in any combination. The nostrils read only weakly
from below – a shading/AO question rather than geometry. A light vertical streak above the upper lip in the
three-quarter view is present in every row including the default; it was not compared with a render of the
previous version, so whether it predates this change is unverified (likely philtrum shading).

`test_h3_three_process_game` fails 11/17 on the server (owner rejoin / observer forgery / done flags). The same
11/17 failure was reproduced with the **previous** `character.glb` swapped back in temporarily, so it is not caused by
this change (the QA audit measured 17/17 on a local 2-CPU machine; on the server the three-process fixture is known
to be timing-sensitive). `godot_check` 60/60.

## Independent review

- **Gemini (gemini-3.5-flash)**: accepted – a magic-number tolerance for hidden faces can mask a defect, so the
  hidden category is now restricted to `ec` faces in `eye_socket` smaller than 1 mm², anything larger fails as
  visible (this is why `test_head` stays 43/44); performance risk of the raised budgets (overdraw of alpha-tested
  hair, blend shapes × vertices, web export) – documented, crowd LOD scheduled. Rejected – "SimVisual will spam
  errors for missing blend shapes": `apply_face_shape` iterates the mesh's own blend shape names, so weights without
  a shape are ignored; "a peer with an old asset sees a broken nose": assets ship with the build, peers cannot mix
  GLB versions. Three-field interactions (length × angle × width): the nose model already sampled all five nose
  fields at random extremes (1.5 mm) and `test_head` measures all 32 fields (3.88 mm), so no further pair was added.
  Normals of the corrective shapes: not checked in this run.
- **Grok (#467)**: asked for 15–20 % headroom in the budgets. Kept tight on purpose (counts are deterministic, a
  tight limit catches the next unintended growth).

## Attempts that did not work (eye-socket cap)

Clamping the projected corner parameter, Laplacian relaxation of the cap, and a harmonic fill (both gnomonic
and azimuthal-equidistant projection around the back pole) all left 2–7 flipped cap faces. The cap boundary
(ring 5) wraps past the eyeball equator and contains an almost-degenerate segment at each canthus, so a
proper fix is a re-topologised cap (for example a fan from the canthus or merged corner vertices), not a
different interpolation.

## Not verified

- Performance of the accepted budgets on real GPUs and in the web export (see `docs/asset-pipeline.md`).


## Update (11 November 2026, evening)

The eye-socket cap is resolved: the cause was the latitude/longitude map of ring 5, not only the square
parametrisation. Ring 5 and the cap now use an azimuthal-equidistant map; `test_head` is 44/44. See
[eye-socket-cap-20261111.md](eye-socket-cap-20261111.md).
