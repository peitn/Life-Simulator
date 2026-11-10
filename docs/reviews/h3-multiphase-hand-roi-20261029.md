# H3 multi-phase hand-centered GPU crossfade — 2026-10-29

Run `main-fallback-1793293877-83528`. Scope test-only; source `tests/test_h3_blend_clock_gpu_multiphase.gd` SHA256 `8b158eddd46f23fa1f71e42ccd234ab07b45b396e8207bb6a018e30f0e8e3be9`.

Primary main last productive completion 12:16 UTC. v3 main lease acquired 17:11:17 UTC; running history confirmed; pre-edit backup project377178KB/library9115KB. Original `test_h3_blend_clock_gpu_late.gd` SHA256 9c84b5ea2a6a9dd151bfccd20346a4e2a6a5916c1b50c34d5cdbdf88799fa01a remained unchanged.

New test adds `--target=` CLI argument, runs one clean frame-clock idle->walk 0.25s crossfade per new process at target 0.05, 0.14 or 0.20s. It projects `hand_l` bone to the viewport and crops a 96x96 ROI centered on it (360x280 fixed viewport). Only SimVisual's automatic animation selector is disabled in disposable test; AnimationPlayer continues ticking. Two independent authored visuals share one SubViewport, alternating visibility. Restores processing flags, process modes, visibility, time scale. PNG saves gated by G.owns+heartbeat and no-overwrite.

| Target | Actual repeat time | Bone delta | d_idle | d_walk | ROI IoU | Repeat child |
|---|---:|---:|---:|---:|---:|---|
| 0.05 | 0.0593239s | 0m | 30.44mm | 104.12mm | 1.0 | 14/14 rc0 |
| 0.14 | 0.143825s | 0m | 46.58mm | 34.01mm | 1.0 | 14/14 rc0 |
| 0.20 | 0.20566495s | 0m | 19.23mm | 4.09mm | 1.0 | 14/14 rc0 |

First three children also each 14/14 rc0; total 84/84, no child timeout. Independent Godot PNG reloader confirmed six preview/live pairs, each 96x96 and SHA-identical within pair, distinct across phases. Files `previews/h3-blend-gpu-main-fallback-1793293877-83528-phase{05,014,020}-{a,b}-0-{preview,live}.png` (12 PNGs). Syntax60/60; actual playable81/81 rc0 15.2s. Known ObjectDB20 warning and XKB/DBus/audio/Mesa unsupported feature warnings; no shader or test failure. No claim of manual screenshot inspection.

Gemini skeptical full-source audit: reported P0 ROI overflow, but current clamps exactly fit fixed viewport (264+96=360; 184+96=280), so P0 rejected; viewport-size coupling is valid limitation. P1 frame_post_draw race not reproduced in six independent runs, remains hypothetical; 100-tick limit has final fail-closed time check but would benefit from clearer assertion. Valid limits: 96x96 bone-centered ROI still includes surrounding torso/arm, shared renderer, no exact internal blend-weight proof, no real GPU hardware variety or exception-safe early-exit cleanup. No verified production P0/P1.

Next SINGLE step: test complete blend >=0.25s and restoration after interruption with stricter hand-only segmentation. No production, city, Blender, GitHub or AI Room writes.
