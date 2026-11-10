# H3 server private-read RPC receipt probe — 2026-11-01 09:09–09:20 UTC

Run: main-fallback-1793524157-88746. Scope: TEST-ONLY. Production networking, original 17 acceptance gates, timeout thresholds, city-owned paths, GitHub, Blender, AI Room unchanged.

## Motivation
Prior bounded three-process H3 tests alternated between 8–17/17 and owner disconnects before or during private read. Absence of an _edit_limiters entry does not prove RPC was not delivered: server_read_character_edit can reject before limiter creation. Need direct server handler receipt/authorization evidence.

## Files
- NEW tests/diagnostics/h3_instrumented_net_session.gd (SHA256 0d49f0f82af9c3235497b0ffda578a9f01c6735c3801bde8f729f87492aa38ad). Subclass of production NetSession overrides server_read_character_edit, emits two privacy-safe signals around super call (entered/result; sender peer, registered/connected, success/reason, timestamp; no key, UID, payload, identity).
- NEW tests/diagnostics/h3_three_process_rpc_probe.gd (SHA256 7997f0ccc0e85571c4abf79b761753a60d5df590e8778e17950146e7d4d37683). Inherits original fixture unchanged; only server Main script is compiled in memory with NetSession preload replaced by test subclass. Source SHA guards for main.gd and net_session.gd. Test-only server signal listener and persistent user:// marker survive parent trace cleanup.
- NEW tests/diagnostics/h3_three_process_rpc_probe.tscn (SHA256 70df5c72023d857abf05ef531823644b5256c0cd743398320ee2819c84474572).
- UPDATED CHECKPOINT.md and DEVLOG.md (this entry and status).
- No production changes.

## Actual tests and errors
1. Initial 3-process diagnostic: 5/17 PASS, exit 1, 81.1 s, runner timeout false. No reliable server RPC handler event; owner readiness and later gates failed. This is a failed integration, not evidence of server receipt.
2. Repeat after test-only signal null-multiplayer fix: 7/17 PASS, exit 1, 66.7 s, runner timeout false. No reliable server RPC event. This does not prove non-delivery; the owner read itself failed before the handler could be demonstrated.
3. Isolated test-only NetSession subclass: first attempt exit0 but stderr SCRIPT ERROR accessing multiplayer.is_server on unattached Node; result empty, signals zero. Corrected by removing unnecessary multiplayer.is_server diagnostic field. Final independent direct method call: two signals entered/result, unauthorized result, exit0, no timeout. This proves local override dispatch only, NOT real ENet RPC routing.
4. Actual production ENet Apply regression: 97/97 PASS, exit0, timeout false; existing security and public-only replication unaffected.
5. Godot syntax check: 60/60 OK. Note global syntax checker may not exhaustively exercise new diagnostics; integration scene parsed and executed.
6. First parent diagnostic printed no server trace because inherited _parent deletes trace files before derived _parent resumes. Fixed test-only by persisting a minimal user:// RPC event marker during server callback; not yet rerun as three-process acceptance after this final marker correction.
7. Stderr in three-process runs: inactive ENet peer get_unique_id, freed lambda capture, ObjectDB leaks; unresolved. No render needed: no UI edits.

## Skeptical Gemini audit
Pre-implementation audit warned that in-memory script patching can perturb RPC mapping/clock, dynamic source replacement is brittle, and absence of events cannot establish non-delivery. Post-code audit warned about await super._parent, signal loss, source hashes, and marker race. Independently verified the claimed coroutine truncation is unsupported: parent produced complete 17-gate result and printed derived H3_RPC_AUDIT after await. The source hashes are deliberate fail-closed guards. No evidence establishes signal loss/re-instantiation; the first missing trace was directly explained by parent cleanup. Marker write is synchronous and closed; a future ENet test must verify actual receipt. Gemini audit is not certification.

## Status and single next step
Diagnostic implementation created, local signal test and production ENet regression pass, but three-process RPC receipt remains PENDING/FAILED. Next ONE step: run the revised derived three-process fixture under a bounded isolated environment until an owner private-read request is demonstrably sent, then verify server-side entered/result marker against owner/client timestamp and peer disconnect; if no event, explicitly check RPC method mapping/ENet error before inferring transport non-delivery. Preserve all original 17 gates, no production changes.
