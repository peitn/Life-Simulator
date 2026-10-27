# Stair physics smoothing ablation — 2026-10-26
Run: city-fallback-1793047120-277067. City-only, no geometry/controller writes; the existing scripts/city/validate_stair_physics_walk.gd remains unchanged. Protocol v3 acquire, running history and pre-edit backup verified.

## Fresh actual Godot 4.7.2 headless tests (in-memory source variants)
Original baseline: 10/10 PASS, exit0, 483 physics ticks, 49 lifts/15 risers, 420 floor ticks, max per-tick displacement 0.2205866m, top and return reached. In-memory wall obstruction: 6/10, exit1 EXPECTED, 900 ticks, blocked before wall, top not reached. No timeouts. Existing 18 ObjectDB shutdown warnings in stderr.
Floor-snap-length-only changes while retaining explicit apply_floor_snap: 0.08m => 30 lifts, 227/480 floor ticks, 8/10; 0.12m => 30 lifts, 303/480 floor ticks, 8/10; 0.16m => 32 lifts, 355/496 floor ticks, 8/10; 0.20m => 40 lifts, 392/482 floor ticks, 9/10. All exit1, no timeout. The .24m baseline remained 10/10 but 49 lifts.
Removing explicit apply_floor_snap while retaining 0.24m floor_snap_length: 21 lifts, 282/485 floor ticks, 9/10, exit1. Combined no-explicit-snap and .20m: 20 lifts, 254/516 floor ticks, 8/10, exit1. No timeouts.
Seven-tick no-gravity/no-snap hold after obstacle-driven lift, original 1.5m/s: 15 lifts spaced at .30m, 345/482 grounded ticks, max airborne streak 7, top/return reached; experimental 13/13 checks exit0 only AFTER replacing original >80% floor-contact assertion with >65%. It FAILS the unchanged original floor-contact requirement (9/10). Five/six/seven tick holds and faster 1.8/2.2m/s variants did not pass the original 80% contact criterion. All variants executed in memory, no saved code edits.

## Skeptical Gemini audit (actually received)
Gemini rejected the seven-tick hold because it suppresses gravity and floor snapping in midair, is open-loop and tick-rate dependent, and weakens the 80% grounded acceptance test. This is consistent with the measured 345/482=71.6% grounded fraction. Its claim that reducing floor_snap_length alone is the likely root fix was separately tested: values .08–.20 all failed original checks. Gemini did not run tests and did not inspect any render. Do NOT merge the candidate or claim smooth movement certified.

## Decision
No change to the existing controller, stair geometry, saved scenes, Blender assets or test thresholds. No side-view motion render produced. The result is a measured negative ablation and a documented unsafe workaround, not a completed smoothing fix. No GitHub or AI Room Relay writes. Next single step: develop a collision-contact-aware step-up that retains >80% grounded ticks while reducing 49 lifts toward 15, with an actual side-view trajectory render and wall-negative regression before adoption.
