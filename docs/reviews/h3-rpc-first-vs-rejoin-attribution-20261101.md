# H3 first-owner vs rejoin RPC attribution — 2026-11-01 UTC

Run: main-fallback-1793528130-92098. Test-only scope; H3 remains FAILED/PARTIAL.

## Preconditions and source
Read fresh CHECKPOINT.md, docs/implementation-sequence.md, docs/automation-lock.md, automation history and diagnostics. No verified productive PRIMARY main completion in preceding ~75 minutes; latest previous fallback at 09:20:48 UTC is not PRIMARY work. Acquired v3 main lock at 10:15:30 UTC; running history verified. Initial remote backup succeeded: project 407503 KB, library 123493 KB. No city-owned, Blender, GitHub, or AI-room writes.

## Exact change
Modified only tests/diagnostics/h3_three_process_rpc_probe.gd (SHA-256 7997f0ccc0e85571c4abf79b761753a60d5df590e8778e17950146e7d4d37683 -> 733c7df77412c8d489ff964004d6a657b108b253c9c2d047d0ef69709e2c6f11). SHA-verified pre-edit backup under previews/automation-backups/main-fallback-1793528130-92098/. The derived fixture now preserves initial-owner gate/peer/send summary and bounded server handler entered/result event history (up to 8) through the inherited parent's cleanup. It explicitly refuses to infer initial RPC receipt from a later rejoin RPC. No private character payload, keys, mind or story are logged. All 17 inherited gates and timeouts unchanged; no production changes or UI/render changes.

## Actual tests and evidence
Bounded derived 3-process integration after change: 8/17 PASS, exit=1, runner timed_out=false, elapsed=75.30 s, three child OS processes, zero surviving/cleaned. Runner JSON /tmp/lifesim_h3_1793528130_rpc2.json is ephemeral, not a project artifact. Output H3_RPC_AUDIT: initial_owner_gate_ok=false, initial_owner_sent=false, initial_owner_peer=1606436912, initial_peer_handler_entered=false; server_event_count=2 (entered/result) for *different* peer 1855808003, result ok=true. This establishes a later authorized server handler invocation (rejoin), NOT receipt of the first owner's RPC, which was not sent. First-owner readiness had a ~22.7-second process-frame gap in observed diagnostic trace; causality/root cause is unproven. H3 remains FAIL.
Unchanged production ENet Apply regression 97/97 PASS (exit=0, no timeout); Godot syntax 60/60 OK. 20 ObjectDB shutdown leak warning persists. Some tool invocations returned internal connector errors even though the bounded runner report was subsequently verified directly; only complete JSON reports are counted.

## Skeptical Gemini audit and independent verification
Gemini audited the proposal and post-change output. Useful concern: scalar count=2 incorrectly attributed a later rejoin to initial-owner receipt. Rejected unsupported assertions of an ENet peer-identity exploit/ghost client: the observed second peer belongs to a legitimate reconnect in the fixture, and the first client never sent its initial read. Also rejected Gemini's claim of zero ObjectDB leaks; stderr explicitly reports 20. No root-cause claim or H3 completion.

## Exact next single step
Instrument or isolate the 22.7-second initial-owner readiness frame gap (visual construction vs network event polling) in a bounded three-process A/B, correlating server peer lifetime with client frame timing, without weakening the 17 original acceptance gates. Do not change production before causal evidence.
