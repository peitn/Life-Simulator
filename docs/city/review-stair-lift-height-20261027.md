# M1 stair lift-height ablation — 2026-10-27 UTC

Run: city-fallback-1793065446-292636. Scope: city-only read-only tests and this report; no production controller, geometry, Blender kit, scene, or global project edits.

## Reproduced baseline
Original `scripts/city/validate_stair_physics_walk.gd` SHA-256 e8a8864661f467f04cf4536a4c3bd966a69f9499451ded12741ba0e4a58f3333. Fresh positive 11/11 exit 0, 496 ticks, 15 lifts, 434 floor ticks (87.5%), no timeout. Saved demo 41/41 and staircase 93/93, exit 0, no timeout. Historical saved 496-sample trajectory shows worst ascent downward correction 0.06429857 m and 16 ascent drops >5 mm (including initial settling). Historical figures were independently parsed from `trajectory-city-1793057445-289586.json`; no new render was made.

## Isolated test-only candidates
Created candidate copies of the unchanged controller, changing only three step-height occurrences (raised origin, vertical collision probe, actual vertical move). Temporary candidate files were deleted after testing with ownership and SHA-256 checks. All experiments ran in actual Godot 4.7.2 physics; no gameplay controller was modified.

| Lift height | Positive | Ticks | Lifts | Grounded | Worst ascent drop | Ascent drops >5 mm |
|---|---|---:|---:|---:|---:|---:|
| 0.220 m baseline | 11/11 exit 0 | 496 | 15 | 434 (87.5%) | 0.06430 m (saved trace) | 16 |
| 0.210 m candidate | 11/11 exit 0 | 497 | 16 | 435 (87.5%) | 0.05445 m | 16 |
| 0.205 m candidate | 11/11 exit 0 | 499 | 17 | 437 (87.6%) | 0.05024 m | 18 |

0.210 m forced-wall negative: 7/11, exit 1 EXPECTED, 900 ticks, 2 lifts, blocked at z=-0.362617 (wall at -0.6), no timeout. 0.210 m continuous two-roundtrip stress: 11/11 exit 0, 996 ticks, 34 lifts, 874 floor ticks, no timeout; baseline historical repeat: 996 ticks, 33 lifts, 874 floor ticks. All observed runs have existing Godot shutdown warning of 18 ObjectDB instances. This is a deterministic fixed-asset experiment, not an FPS benchmark.

## Skeptical audit and disposition
Gemini actually reviewed the exact three-value change and metrics; recommended not merging without more margin and repeated-trip testing. Its concern about halving clearance from 2 cm to 1 cm is geometrically correct. Assertions that 1 cm is necessarily near floating-point noise and that wall regression would break are not demonstrated: the actual wall-negative test passed its intended rejection. A two-roundtrip test also passed, but broad lateral offsets, multiple physics rates and 50-cycle robustness remain untested. Gemini did not execute tests.

## Decision
REJECT both candidates as a production fix for now: lower worst-case downward correction is accompanied by 1–2 additional lifts and a reduced step clearance margin. The original controller remains byte-for-byte unchanged. No visual smoothness claim. Next single step: test a contact-driven vertical correction that preserves the original 0.22 m clearance, with repeated-trip, lateral-offset and wall-negative checks before any merge.
