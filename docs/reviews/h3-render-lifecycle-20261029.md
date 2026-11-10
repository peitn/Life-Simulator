# H3 graphical QA: reparent and hand-state restoration — 29 October 2026 UTC

Run: `main-fallback-1793243691-41746`. Scope: test-only repair to real GPU creator-preview versus cold-loaded SimVisual QA. No production/UI/city-owned/Blender/GitHub/AI-room changes.

## Source change and reason
`tests/test_h3_rendered_parity.gd` final SHA256 `4aac08a879d4b056eb950d5ecd6ed5d11d05828a533ae8c99992653059568a4c`. Before the patch, the graphical fixture temporarily called `live.set_hand_pose("open")` to compare renderings, then reparented the actual live model back without restoring the original hand gesture. The test itself could therefore leave a resident's hand morph state changed. Added pre-capture local/global transform, parent, body and gem/label visibility, named hand gesture and all ten per-finger mode/curl/proximal/distal values. After rendering, the fixture restores named gesture and ten individual finger morph states and checks their exact readback plus parent/transform/visibility. New screenshot stem includes this run ID, so prior captures are not overwritten.

The fixture uses the same synthetic on-disk cold-process household with Nora Cold and Mira Cold, two distinct hand scales, 1280×900 and 360×800 windows, real Xvfb/Mesa OpenGL compatibility rendering. All screenshots show public appearance only. This patch is a test harness fix, not proof of production hand gesture corruption.

## Actual execution and failures
- Initial Xvfb invocation used executable `godot`, which is not on PATH: child rc127. Corrected to `/opt/godot/godot` via `OS.get_executable_path()`. This initial failure is not a passing test.
- First actual graphical run after named-pose restoration: **64/64**, child exit0, 13.49s; eight PNGs.
- Second final graphical run after adding ten-finger exact snapshot/restore: **76/76**, child exit0, 14.04s; eight more PNGs. No timeout; old ObjectDB warning20. The four mean RGB deltas remained approximately 0.0043–0.0063, with >3% foreground, below 0.02 average delta.
- An incorrectly invoked cold-process suite with `--verify` failed 0/1 because the script requires `--phase=verify`; corrected invocation **19/19** exit0, 9.9s. H3 playable integration **81/81** exit0, 12.0s. Legacy syntax scanner **60/60**. All final runs no timeout.

## Gemini skeptical reviews and independent verification
Two actual Gemini responses audited the specific source and results. First valid observation: restoring only the hand-pose name does not necessarily restore independent C14 finger morph values. Addressed with ten per-finger snapshots and readback. Gemini's later allegation that an omitted intermediate/middle joint breaks this code is not supported: `finger_joint_values` in current `sim_visual.gd` explicitly defines combined/proximal/distal only, and production C14 exposes those two independent bend channels. Its caution about strict float dictionary equality is a portability/test-flakiness concern; this exact readback passed all four captures, not a cross-platform guarantee. Its original claim that screenshot failure leaves a live node reparented was incorrect for this code: screenshot writes occur after the reparent restoration. An interruption during an awaited render frame remains a possible QA-only lifecycle risk; GDScript has no Python-style try/finally. No demonstrated production vulnerability. Custom joint-mode restoration helper exists but this saved fixture primarily exercises preset gesture states; custom-mode parity is not independently certified.

## Exact modified/new files
- `tests/test_h3_rendered_parity.gd`
- `docs/reviews/h3-render-lifecycle-20261029.md`
- `CHECKPOINT.md`
- `DEVLOG.md`
- Sixteen new screenshot PNGs:
  - `previews/h3-render-main-fallback-1793243691-41746-Nora-Cold-1280-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Nora-Cold-1280-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Nora-Cold-360-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Nora-Cold-360-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Mira-Cold-1280-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Mira-Cold-1280-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Mira-Cold-360-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-Mira-Cold-360-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Nora-Cold-1280-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Nora-Cold-1280-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Nora-Cold-360-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Nora-Cold-360-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Mira-Cold-1280-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Mira-Cold-1280-spawn.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Mira-Cold-360-preview.png`
  - `previews/h3-render-main-fallback-1793243691-41746-fingerrestore-Mira-Cold-360-spawn.png`

## Single next step
Add isolated custom C14 joint-mode restoration regression plus hand-closeup foreground-mask/cropped-region pixel comparison for both hand sizes at normal/narrow resolution. Do not call whole-frame similarity detailed finger QA. H3 PARTIAL.
