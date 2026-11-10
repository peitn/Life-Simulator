# H3 guarded cancellation and three-process regression — 2026-11-01 UTC

Run: `main-fallback-1793498931-72823`, 02:08–02:17 UTC. v3 main lock acquired with running history, initial remote backup succeeded (project 406351 KB; library 123493 KB). No productive primary-main completion in prior 75 min found in checkpoint/history. All writes under main ownership; city/Blender/GitHub/AI room untouched.

## Actual test-only change

New `tests/diagnostics/h3_guarded_cancel_probe.gd` and `.tscn`: dynamically compile exact-hash guarded SimPuppet/SimVisual, create valid public-only fixture, queue_free the puppet while its visual is in `building` after 0, 1 or 2 process frames. Assert each visual is freed by WeakRef within eight frames and no late ready signal. **13/13 PASS twice**, exit 0, ~8.0s and ~6.8s, no timeout. stderr contains pre-existing ObjectDB20 warning. This is **local SceneTree cancellation**, not server-authoritative ENet despawn; it does not prove absence of post-cancel mutation outside the observed checks.

Initially a 50s probe attempt timed out because a new GDScript variable used Variant type inference with warnings-as-errors. Corrected explicit WeakRef type and reran successfully. The failed attempt is not a pass.

Temporary experiment: modified `tests/diagnostics/h3_guarded_script_builder.gd` to insert `is_inside_tree()/epoch` checks after every awaited subphase. The unchanged 17-gate real three-process guarded fixture returned **8/17 FAIL** (exit1, 76.23s) and **12/17 FAIL** (exit1, 45.10s). No runner timeout, three children per run, no survivors. Since integration gates failed, **restored builder byte-for-byte** from own SHA-verified pre-edit backup: SHA256 `78145a68e30e5ea56bff59707e5974cd7900824bfc8ad29ad7fe7e59c61eb91c`. New standalone probe still **13/13 PASS** after rollback. After rollback, unchanged guarded three-process test was **11/17 FAIL** (exit1, 46.11s, 3 children, no survivors), so failure cannot be attributed solely to the temporary builder edit. Historical 17/17 twice is not a guarantee of reproducibility. Some stderr shows inactive ENet peer and freed lambda; ObjectDB20 warnings remain.

Independent production `test_character_net` **97/97 PASS**, `godot_check` **60/60 PASS**. No production code modified, no new graphical UI/render changes.

Gemini skeptical audits (before and after): valid concerns about post-await lifecycle checks, network-vs-local cancellation, and nondeterministic timing. Unsupported assertions of proven causal source or fully clean stderr rejected. No private data sent.

**H3 remains FAILED/PARTIAL.** New local cancellation regression is useful, but the real three-process network-authoritative despawn has NOT been tested or passed. Next single step: isolate and reproduce the guarded 17-gate three-process regression on a clean, non-overlapping test run, inspect owner-read handshake/teardown ordering and process traces before introducing authoritative forced despawn. Do not relax any gate.
