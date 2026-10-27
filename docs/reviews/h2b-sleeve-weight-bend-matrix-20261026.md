# H2b sleeve bend, authored-wardrobe integrity and graphical review — 26 October 2026

Owner run `main-sleeve-fit-1793038998-250071`, main scope only; v3 cooperative lock with per-write ownership checks, no city directories, no GitHub publication. Pre-edit project/library backup succeeded.

## Reproduced defect and actual repair

Previous seam correction had improved the resting shirt-to-sleeve proximity but left bent elbow pose worse (16.6 mm median, 30.07 mm maximum in the default cat hoodie) and one extreme full-body profile up to 44.87 mm maximum at 90° elbow bend. Direct runtime inspection of all 14 top-ring vertices per side found source C5 arm-only influences were assigned **73.33% forearm / 26.67% upper arm** at the shoulder rim. Thus the end of the sleeve was being pulled by an elbow that should not move its shoulder rim. This defect was distinct from the earlier problem of spurious hip/leg weights, previously corrected.

The presentation-layer legacy C5 LSX adapter `scripts/assets/clothing_wardrobe.gd` now normalizes the top 14 vertices to the corresponding **upper arm 100%** and the second 14 to **upper arm 64% / forearm 36%**. Third/lower rings retain the original forearm/hand influence. The 70-vertex, two exactly matched 14-vertex-height rings and arm-only source IDs are validated *before* modifying; unknown/unexpected geometry fails closed. C5→Character bind remapping still happens afterwards. Positions/morphs/normals from the previous shoulder seam extension are unchanged. In `tools/blender/clothing_c5.py`, the authored sleeve arm-weight formula was revised to ramp from upper arm near the shoulder to the forearm at elbow, so future re-exports won't recreate the original incorrect weight curve. The actual production LSX binary was intentionally **not re-exported** in this run.

### Real pose measurements in the Godot skinned model

Default cat hoodie, point-to-actual-triangle surface distance from the upper sleeve rim to shirt shell:

| Pose | Median left/right | Maximum left/right |
| --- | --- | --- |
| Rest, after previous position-only correction | 10.63/10.64 mm | 21.08/21.09 mm |
| Elbow 90°, **before today's weight repair** | 16.61/16.59 mm | 30.07/30.07 mm |
| Elbow 90°, **after today's weight repair** | **12.03/12.03 mm** | **21.27/21.28 mm** |

Today the pose-specific improvement is ~27.5% lower median and ~29.2% lower maximum elbow-bent separation. Rest remains unchanged (bind-rest transforms identity within floating-point tolerance).

Independent **five body extremes × eleven real long-sleeve outfits × four arm poses (idle, elbow 90°, both shoulders raised 60°, raised + elbow bent) × both arms = 440 skinned upper-rim observations**, all strictly valid CharacterData, were exercised by new `tests/test_sleeve_extreme_matrix.gd`. The worst median across the whole matrix is **17.62 mm**, and worst maximum **27.90 mm**, lower than the previously observed 44.87 mm on the four-profile limited matrix. Hard fail bounds 19 mm median / 29 mm maximum. Matrix passed **1012/1012** meaningful assertions (including coverage and repeat-application idempotence). This is not a watertightness certificate and does not inspect every idle/interpolated pose or every object collision.

Additional 22 long sleeves in 11 styles: revised `tests/test_cat_sleeve_weights.gd` passed **166/166**, checking upper rim 100% upper-arm ownership, second ring ~36% forearm transition, normalization, absence of hip/leg or opposite-arm weights. `tests/test_cat_sleeve_surface.gd` passed true point-to-triangle checks in both rest and elbow bends.

## Full authored C5 inventory audit: separate detected defect

New `tests/test_clothing_mesh_integrity.gd` enumerated all 20 canonical tops, 17 bottoms (including deliberate `zadne`), 16 shoes (including deliberate `bosy`), plus dress and visible-leg assets. **All 5,440** top × bottom × shoes combinations produced nonempty assembled outfits. Inspected **172 genuine authored mesh pieces**, 42,664 vertices, 80,579 triangles, 10 body shape keys/mesh, 17-bone skin bounds, UVs, normalized weights, and finite normals.

First audit run deliberately **failed**, identifying **36 collapsed triangles**, 12 each in three waist chain meshes: `punk_kostka`, `metal_dziny`, `visualkei_kalhoty`. The source spline sampled a symmetric sine sag at 12 evenly spaced points; points 5 and 6 were exactly coincident. Added a narrowly guarded presentation-layer migration that separates the duplicated second midpoint ring by +6 mm, applies the identical offset to each 10 body morph target and recalculates normals. Source Blender generator changed at sample i==6 by the same 6 mm. A repeat application is a no-op. The **final re-run passed 7,046/7,046** with **zero remaining collapsed triangles** (outfit combinations included). No claims of full collision-free dressing or zero self-intersections.

## Actual graphical captures and honest limitations

With an owned Godot lease, launched the real project through `xvfb-run` using GL Compatibility (Mesa software), rendered `tests/test_cat_sleeve_surface.gd` at 480×480 in rest and 90° elbow bend, and wrote:
- `previews/main-sleeve-fit-1793038998-250071-sleeve-rest.jpg`
- `previews/main-sleeve-fit-1793038998-250071-sleeve-bent.jpg`

Both captures succeeded (exit0). Inspected resized images. Arm sleeves follow elbow motion instead of separating at the shoulder, but the simplified hand/cuff silhouette still has angular edges and the shirt/sleeve joint is **not closed/watertight**. Subsurface scattering is unavailable in GL Compatibility and logs a known rendering warning. This is a mesh/geometry issue still to be improved; not a full release render signoff. Individual fingers, toes, nails, nipple and navel geometry/sliders remain future authored anatomy work and are NOT claimed added.

## Other actual regressions after final code changes

- `tests/test_appearance_slider_ui.tscn`: 108/108
- `tests/test_full_playable_slice.tscn`: 45/45
- `tests/test_character_editor_ui.tscn`: 55/55
- `tests/test_body_morphs.tscn`: 62/62
- `tests/test_face_detail.tscn`: 66/66
- `tests/test_clothing_c5.tscn`: 16/16
- `tests/test_character_preview.tscn`: 13/13
- `tests/test_save_game.tscn`: 46/46
- `tests/test_character_net.tscn`: 70/70
- `tests/test_network_editor_live_enet.gd`: 27/27
- `tests/test_host_character_editor.tscn`: 10/10
- `godot_check`: 60 existing scripts clean; all new diagnostic scripts parsed and ran directly.

ObjectDB resource-exit warnings remain inherited. The Godot and Blender project source is not published to GitHub pending user authorization. Next: polish visible cuff/sleeve joins, test long animation interpolation and more accurate hands/feet/digits with separately versioned anatomy, plus true GUI/browser device QA.
