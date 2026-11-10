# H3 three-process owner readiness timing — 2026-10-31

Run: `main-fallback-1793409242-11108`. Scope: isolated failing diagnostic only; no production network code modified.

## Evidence and change
- Acquired v3 main lock and verified history; initial backup project 405723 KB, library 123493 KB.
- Changed `tests/diagnostics/h3_three_process.FAILING.gd` to trace creator code generation, world construction, readiness polling (own character assigned versus puppet visible), peer count, connection status, and max process-frame gap.
- First diagnostic attempt **timed out after 112 seconds** because a parse error was introduced (`var :=` with dynamic value). Corrected to explicit `bool`; explicit script load then passed.
- Fixed a separate diagnostic measurement defect: when the final `await process_frame` crossed the deadline, max gap was not recorded because the loop ended before its body ran. A final sample after the loop now includes that wait.
- Final changed file SHA256: `43b55f0b7416970f845660d531345f845b888332e1b1f9f7a838a29da0aea20d`.

## Actual tests
- Three separate child OS processes, initial fixed-parse run: **8/17 FAIL**, exit 1, no timeout, 64.3 s.
- Second run: **6/17 FAIL**, exit 1, no timeout, 71.1 s.
- After final frame-gap correction: **6/17 FAIL**, exit 1, no timeout, 69.8 s.
- Existing real ENet in-process test `tests/test_character_net.tscn`: **97/97 PASS**, exit 0, no timeout, 20.5 s.
- Godot core syntax checker: **60/60 PASS**; separate explicit diagnostic load PASS. Core checker alone does not cover diagnostic.
- Diagnostic stderr: inactive multiplayer get_unique_id errors after disconnect; known ObjectDB20 warning. Do not claim H3 accepted.

## Interpretation
Final trace: owner welcome at UTC ms 1793409744873; readiness timeout at 1793409762964, without observing its own puppet. The last sampled process-frame wait was **18,098.7 ms**; server independently recorded **4,860.8 ms** max gap. Server ACL gate ran after original owner peer disconnect and failed. This demonstrates severe process-frame scheduling/processing delay and missing initial puppet visibility *in the failing three-process fixture*. It does not distinguish blocked GDScript, CPU starvation, OS scheduling, or a production replication bug. Rejoin private snapshot later succeeded in this run, but entire test failed.

## Skeptical Gemini review
Two reviews received. Accepted: deadline may be exceeded while waiting on `process_frame`; final gap must be sampled after loop; source of stall remains unproven. Rejected as unsupported: that the server definitively caused the client delay, or that elapsed-clock probes alone identify an OS versus engine thread stall. Gemini did not execute tests.

## Next one step
Add correlated timestamped instrumentation around server hello/character creation/public spawn and client puppet replication callbacks; compare with the owner `process_frame` gap in another three-process run. Do not change production behavior until the failing stage is identified. No city, Blender, GitHub or room writes.
