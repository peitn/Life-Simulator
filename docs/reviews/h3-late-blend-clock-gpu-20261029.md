# H3 late-frame idle→walk GPU blend — 2026-10-29 UTC

Run: main-fallback-1793290131-81156. Test-only change; no production, city, Blender, GitHub, or AI Room edits.

## Scope and causal diagnostic

Primary main last productive completed at 12:16 UTC (Clothing Studio v1), >75 min before 16:08 UTC check; v3 MAIN acquired 16:08:51 UTC and verified running history. Pre-edit project backup succeeded: 377108 KB; library 9115 KB.

Earlier H3 test manually requested AnimationPlayer.play("walk",0.25) while SimVisual._process() still ran. Actual production source scripts/sim/sim_visual.gd:1157–1162 calls _update_anim() each frame; with stationary model _speed below WALK_THRESHOLD it selects idle at 1124–1133. Thus earlier early-frame GPU parity by itself does NOT establish that the walk crossfade was running. This is a TEST HARNESS flaw, not a demonstrated production animation bug. Previous test remains unchanged for historical comparability.

New tests/test_h3_blend_clock_gpu_late.gd (final SHA256 9c84b5ea2a6a9dd151bfccd20346a4e2a6a5916c1b50c34d5cdbdf88799fa01a): isolated one late real process-frame sample at 0.12–0.20s of 0.25s idle→walk request. During the disposable test only, disables SimVisual script _process on both draft and live models while leaving their child AnimationPlayers active; awaits frame_post_draw for consistent clock capture; verifies assigned walk, exact draft/live clock parity, bone parity <1mm, raw unregistered GPU crop-mask IoU >0.95, RGB delta <0.04, and pose >1mm from both matched-time pure endpoints. Restores original processing flags, process modes, visibility and Engine.time_scale. Test PNG writes gated by G.owns+heartbeat and unique tag.

## Transparent test history

- Initial 3-sample version: Xvfb/Mesa rc=1, 25 pass / 3 fail. Late t=.14082s but d_idle=.000513m, draft/live clock mismatch, not accepted.
- Isolated late version without prior pause/resume: Xvfb/Mesa rc=1, 10 pass / 2 fail. t=.14857s, d_idle=.000343m, draft/live clock mismatch .01277s. Not accepted.
- Inspected actual SimVisual._process and identified automatic idle selector as the cause of the misleading pose. Added scoped set_process(false) and full-frame sync; no production change.
- Final Xvfb/Mesa OpenGL 4.5 llvmpipe late3: **13/13, child rc=0, ~6.05s, timeout=false**. t=.14357845s, draft/live time exactly equal, bone delta 0m, GPU crop IoU 1.0, RGB delta 0, d_idle=.047416m, d_walk=.033385m, endpoint separation=.080701m.
- Independent repeat late4: **13/13, child rc=0, ~5.93s, timeout=false**. t=.14331365s, draft/live time exactly equal, bone delta 0m, GPU crop IoU 1.0, RGB delta 0, d_idle=.047447m, d_walk=.033552m, endpoint separation=.080898m.
- Independent new Godot process loaded final late4 preview/live PNGs (240×187, both SHA256 d6122778478d4a0b36dbede255694f874e57284ab7c3c1bd4bcc22c58d7f3a30).
- Existing playable slice **81/81, exit=0, timeout=false**; static checker **60/60**. Known ObjectDB20 warnings, missing XKB/DBus/audio libraries and unsupported renderer settings; no shader failure observed.

## Skeptical Gemini audit

Gemini reviewed planned diff, two failing run logs, and final full source/results. Valid limits: one late sample (repeated), not whole blend curve or exact internal interpolation weights; crop includes non-hand pixels and samples every second pixel; one shared SubViewport with sequential visibility, not independent GPU pipelines; cleanup not exception-safe on abnormal early termination; Mesa llvmpipe not real consumer GPU. Its P0 classification of unmeasured exact blend weights is overstated for this scoped parity test. Its initial suggestion to replace real frame ticks with seek() was rejected because it would invalidate the objective. Causal override was verified directly in actual production source and isolated in test only. No proven production P0/P1.

H3 remains PARTIAL. **NEXT SINGLE STEP:** add independent multiple clean real-frame crossfade samples (e.g. ~0.05, ~0.14, ~0.20s) without SimVisual automatic animation override, with hand-specific ROI or bone-projected hand mask and restore checks; do not claim exact AnimationPlayer blend weights absent direct evidence.
