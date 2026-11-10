# H3 — matched walk-phase hand GPU QA (2026-10-29)

Run: `main-fallback-1793261315-53418`. Source of truth: live Godot `lifesim`. Last verified primary MAIN completion: 2026-10-29 06:41:36 UTC (Czech TTS, tests documented), 86m59s before acquire at 08:08:35 UTC; fallback did not equate scheduler execution with productive work. Main v3 lease acquired, running history verified, pre-edit HF backup project 374889 KB/library 9115 KB.

## Actual scoped work

Only test source changed: `tests/test_h3_rendered_parity.gd` (before SHA256 `65ffac139b2bf791791b32d5da427de286bb3f6eaea4875eecff6bf4b4aaee79`, final SHA256 `b867de59b57a9ff309a037152d288c7dd8ff1b469e310f15bd4bd6e57581d20c`). Four local revision backups kept under `tests/test_h3_rendered_parity.gd.main-fallback-1793261315-53418{,.iter2,.iter3,.iter4}.bak`. No production game logic, city-owned paths, Blender, GitHub, or AI-room writes.

Existing real cold-process restored Nora/Mira resident visuals and 3D creator preview rendered through Mesa/OpenGL under Xvfb. Controlled intervention explicitly forces both authored AnimationPlayers to `idle` phase 0, then to `walk` phases 0.20 and 0.70 with zero transition blend, preserving and restoring original assigned clip, phase, running state, speed, process flags, hand pose, all ten finger states, transforms and parent. `assigned_animation` is checked because Godot `pause()` clears `current_animation` while retaining the assigned clip. Two real walk poses are confirmed by different hand-bone world coordinates (>5mm) and independently different GPU frames (RGB delta >0.002). For each matched phase the raw unregistered hand-mask IoU exceeds .75 and |shift_x|<=6px; mask uses fixed background-color threshold, not bounding-box registration. The test awaits four process frames and `RenderingServer.frame_post_draw` for each capture. All screenshots are guarded by `G.owns`, heartbeat, and no-overwrite check.

**Actual final GPU test**: 204/204 assertions, child exit=0, timeout=false. 2 residents × 2 viewports (1280×900, 360×800) × 2 walk phases = 8 comparisons; each reported raw hand IoU=1.0 and horizontal shift=0px, *within this controlled fixture*, not a claim of universal pixel identity. Temporal mean RGB deltas between phases: Nora1280 .0061745, Mira1280 .0089974, Nora360 .0068224, Mira360 .0089257. 40 final PNG files retained (16 walk-crop + 24 baseline/idle/full-size); 120 intermediate PNGs from failed/superseded runs were removed with live ownership and per-file SHA guards. No new UI was added; this is test-only visual QA.

**Failed iterations retained as evidence, not reported as success**: first GPU 188 pass/8 fail (invalid `current_animation` check after pause); second 186/10 (same issue plus original clip assumption); third 196/0 after checking `assigned_animation` and explicitly forcing idle before walk; fourth/final 204/0 after Gemini-requested distinct-phase bone+pixel controls. All finished child processes, no timeouts. Known ObjectDB 20 warnings; Mesa dummy-audio warning, not a test failure.

Actual regressions on final source: H3 playable integration 81/81 exit0 no timeout (11.3s); separate-process cold verify 19/19 exit0 no timeout (10.0s); bundled Godot syntax 60/60. These do not certify production gameplay blend timing.

## Skeptical Gemini audit

Two real text audits of concrete GDScript excerpt and results. Accepted the first audit's important distinction: movement relative to idle does not prove two walk phases differ; added 5mm phase-to-phase bone displacement and >0.002 RGB temporal change checks. The second audit noted possible cached GPU frames and overly broad binary masks; independent source inspection confirms the test already waits `RenderingServer.frame_post_draw`, foreground mask requires actual nonempty thresholded pixels, and the measured phase-to-phase RGB delta is nonzero. No pixel-perfect guarantee for individual joints. Claims about unprotected path traversal were not substantiated: run ID is internally generated, validated by v3 ownership, and filenames are generated from fixed fictional test names. Gemini did not execute Godot or inspect image pixels.

**Scope limitation / NEXT SINGLE STEP:** the new test switches to the walk clip with **zero blend**, not the real `idle → walk` 0.25-second crossfade. Test the actual blended transition at multiple timestamps with phase-matched GPU hand crops, plus exact animation state restoration. H3 remains PARTIAL. No claim that all animations, all body shapes or network renders are correct.

## Final retained PNGs (exact paths)

- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Mira-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-phase0-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-phase0-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-phasewalk4-Nora-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-1280-20-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-1280-20-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-1280-70-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-1280-70-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-360-20-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-360-20-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-360-70-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Mira-Cold-360-70-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-1280-20-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-1280-20-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-1280-70-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-1280-70-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-360-20-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-360-20-spawn.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-360-70-preview.png`
- `previews/h3-render-main-fallback-1793261315-53418-walkfix4-Nora-Cold-360-70-spawn.png`
