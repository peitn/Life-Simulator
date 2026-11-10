# H3 dense reverse-crossfade bone continuity — 2026-10-29

Run: `main-fallback-1793311700-100192`. Scope: **test-only**, no production, city, Blender, GitHub or AI-room edits.

## Changed file
- NEW `tests/test_h3_reverse_dense_bones.gd`, SHA256 `e73f7c70979d2e52c44c376c0199c43c8a2c5bd4321a3cb5faa2c5cd9df12b97`. Based on the existing H3 completion/interruption test; samples **both** hand bones on every actual Godot `process_frame` while crossfading **back to idle** after interrupting an incomplete 0.25s idle→walk blend at ~0.10s. Checks 0.17s endpoint against a separate pure-idle reference, preview/live pose parity, monotonic animation time, temporal bins and maximum frame displacement. A deliberate +0.15m left-hand bone displacement must be detected, then restored.

## Real tests (Godot 4.7.2)
- Persisted test at `Engine.time_scale=0.15`: **28/28 PASS**, `exit=0`, `timed_out=False`. 166 frame samples / 12 time bins, max frame bone displacement 0.00179704m, max preview/live bone difference 0m, max animation clock gap 0.00104167s, injected +0.15m offset detected and restored; both final hand bones exactly match pure idle.
- Ephemeral second variant at `Engine.time_scale=0.30` (not persisted): **28/28 PASS**, `exit=0`, `timed_out=False`. 84 samples / 12 bins, max displacement 0.00360560m, preview/live 0m, 0.15m mutation detected, final pure idle exact.
- Initial pre-mutation version: **26/26 PASS** at 0.15; not the final source.
- Project syntax check: **60/60 OK**, no parse errors. Stderr retains **20 ObjectDB leak warnings** on run-script exits; no timeout or test assertion failure.

## Skeptical Gemini audit (2 rounds)
- First review suggested genuine mutation control, added and empirically verified. It also misread `reverse` as negative-speed playback: here it unambiguously means a new crossfade **back to idle**, not running an animation backward. It incorrectly claimed `time_scale=0.15` increases simulation delta; it actually slows simulated time.
- Second review accepted scope and mutation sensitivity, flagged finite sampling, hand-only skeletal coverage, missing root-motion/rotation/GPU visual QA and reduced time scales. It **overstated** proof of velocity continuity/artifact-free rendering: sampled **positions** alone cannot certify smooth velocities or visual absence of defects. The 0.10m per-frame assertion is a broad teleport guard, not a strict physical acceleration criterion.

## Completion boundary and next single step
H3 **PARTIAL**. This verifies dense bone-position parity and end-state convergence for one interrupted blend at two slowed time scales, not full 3D rendered hand-skin continuity or full-speed playback. **NEXT SINGLE STEP:** perform denser independent GPU/Mesa samples of the previously isolated hand-weighted mesh through the reverse crossfade, including a real 1.0 time-scale sample and an image-sensitive negative control.
