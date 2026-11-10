# H3 client SimPuppet/SimVisual lifecycle probe — 2026-10-31

Run: main-fallback-1793466951-45466. Baseline H3 remains FAILED/PARTIAL; this is test-only instrumentation, not a multiplayer fix.

## Exact changes
- Modified `tests/diagnostics/h3_three_process.FAILING.gd` SHA-256 `386056cbb1be581c8f32fd2ef03ab69598c1af39bcf51481ec4ae5fdea43c1a4`.
- In client-only trace attachment, instrumented `sims_root.child_entered_tree`, `SimPuppet.ready`, direct child entered/ready, script/class/instance and per-process monotonic elapsed times; prints bounded client lifecycle traces. Existing 17 assertions unchanged. No production code changed.

## Actual test evidence
- First attempt: `godot_run` timed out at 105 seconds with no test result because the diagnostic script had two GDScript type-inference parse errors in untyped lambda parameters. This attempt is a **failure**, not a pass. Corrected to explicit `int` and verified script `can_instantiate=true`.
- Corrected independent three-process ENet H3: **8/17 PASS, 9 FAIL**, `exit=1`, `timed_out=false`, 70.7 s. Failed assertions: owner_read_ready, server_read_gate, owner_read_sent, owner_initial, server_initial_diag, observer_forgery, server_done, owner_done, observer_done. Stderr includes four `The multiplayer instance isn't currently active` errors during teardown and pre-existing ObjectDB warning.
- Observer client `SimPuppet` direct `SimVisual` child entered→ready: **8569.782, 1517.548, 2806.407, 6166.983 ms** for four distinct instances; corresponding parent entered→ready: **8571.258, 1518.562, 2807.563, 6173.821 ms**. Direct `MultiplayerSynchronizer` ready was ~0.06–0.12 ms. The four visual stages are sequential in the observer trace, totalling ~19.06 seconds, and coincide with long synchronous puppet construction. This does NOT establish that visual work caused network test failure.
- Separate unchanged ENet Apply transport: **97/97 PASS**, `exit=0`, `timed_out=false`; Godot static checker **60/60**; explicit diagnostic script load PASS. Static checker did not detect the initial diagnostic parse error; direct load did.

## Skeptical Gemini audit
Gemini confirmed the evidence is limited to local lifecycle elapsed time and that visual stalls cannot be equated with packet loss/RPC failure. It raised plausible main-thread starvation and cross-process clock-order caveats. Its recommendation to stub client visuals is a hypothesis for a controlled test, not an approved production change. No private character payloads sent.

## Exact next single step
Perform a **test-only controlled client prewarm vs cold A/B** in independent processes, preserving all 17 assertions and production files; compare ENet welcome/roster and SimVisual ready timings. Do not infer a production fix or loosen timeouts from this single experiment.
