# H3: controlled identical idle animation phase — 29 October 2026

Run: main-fallback-1793254587-49439. Main primary last verified completion: 2026-10-28 20:56:25 UTC; no completed primary development within 75 minutes. v3 MAIN exclusive lease acquired with running history, no other Godot process; pre-edit project backup 374491 KB, library backup 9115 KB. Only QA test and documentation changed; no production, city-owned, Blender, GitHub or AI-room writes.

## Exact change and causal control

Changed `tests/test_h3_rendered_parity.gd`, final SHA256 `65ffac139b2bf791791b32d5da427de286bb3f6eaea4875eecff6bf4b4aaee79`. The existing test compares actual cold-loaded SimVisual with CharacterPreview in the same SubViewport and camera. New paired intervention pauses both actual AnimationPlayers, seeks both `idle` to t=0, calls `advance(0.0)`, waits for real rendered frames, captures independent preview/spawn hand crops, then restores both players' clip/time/play-state/speed and all existing gameplay hand gesture, ten C14 finger states, parent, transforms and visibility. New assertions require phase0 raw unregistered IoU >.85, improvement >.6, and |horizontal shift| <=4px; these are bounded to the actual two residents and two viewports, not a universal renderer guarantee. PNG writes are lease-guarded and unique.

Actual Xvfb/Mesa OpenGL child runs: first 148/148, second/final 156/156, exit=0, no timeout (~22.4s and 19.1s). 24 PNGs each run, 48 total. Original baseline raw IoU .021–.109, shift +36–38px. At identical idle t=0 raw IoU .908–.979, shift -2..0px, registered IoU .945–.979. Actual final per case:
- Nora Cold 1280x900: baseline .0394 shift+38; phase0 .9083 shift-2.
- Mira Cold 1280x900: baseline .1086 shift+38; phase0 .9587 shift0.
- Nora Cold 360x800: baseline .0214 shift+36; phase0 .9689 shift0.
- Mira Cold 360x800: baseline .0590 shift+38; phase0 .9791 shift0.

This controlled within-run intervention strongly establishes that different idle pose/phase accounts for the large hand displacement **in this QA setup**. It does NOT demonstrate a production spawn defect, full pixel identity, other clips, all finger joints under motion, or absence of screenshot timing effects. Residual mismatch is nonzero. No gameplay fix was needed.

Actual other Godot regressions: H3 full playable slice 81/81 exit0, cold-process restore 19/19 exit0, legacy syntax scan 60/60. Existing ObjectDB20 warning, no new test error.

## Skeptical Gemini audits and independent verification

Two Gemini reviews of the concrete animation-phase diff and numerical results. Valid caveats: animation seek/play state restoration is not a full engine-wide pose snapshot; 4 frames + frame_post_draw is empirical; cropped IoU only measures the defined hand region and idle at t=0. Gemini suggested checking AnimationTree/IK/SkeletonModifier3D, but source `scripts/sim/sim_visual.gd` has none; the test already sets `SubViewport.UPDATE_ALWAYS`. Gemini labeled lack of process_mode restoration critical, but test never mutates process_mode and the preexisting test restores visibility; that specific claim was rejected after source inspection. Live and draft AnimationPlayer clip/time/running/speed restoration now explicitly asserted. Gemini did not run Godot.

## Exact artifacts

Changed source/doc paths: `tests/test_h3_rendered_parity.gd`, `docs/reviews/h3-idle-phase-causal-20261029.md`, `CHECKPOINT.md`, `DEVLOG.md`. Added screenshots, individually listed below (48 PNGs, 2 runs × 2 residents × 2 viewports × 6 views).

- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Mira-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-animdiag-Nora-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Mira-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793254587-49439-phasecheck-Nora-Cold-360-spawn.png`
