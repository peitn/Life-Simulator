# H3 three-process ENet: bounded per-process tracing (2026-10-30, fallback)

Run: `main-fallback-1793398289-5445`. The last completed PRIMARY run was at 13:57:45 UTC, more than 75 minutes earlier. The previous fallback owner `main-fallback-1793394678-5141` remained `running` with heartbeat 21:11:18 UTC and expiry 21:51:18 UTC. At 22:11:29 UTC, after the 20-minute grace and with no other Godot processes, v3 coordinator atomically archived the stale lease and granted our new main lease. We did NOT manually remove any owner. Pre-edit backup: project 405710 KB, library 123493 KB.

## Changed source (test only)
- `tests/diagnostics/h3_three_process.FAILING.gd`: original SHA-256 `5beeb442dfc8c03b50ed459307a835d2837fa72ea011b4788ebfef21b7c24e62`; final SHA-256 `f86a2348bf2676e62d99b40b08844f5980b783c1451f27a553fec5b325e5ba76`.
- Added `_trace` JSONL event recording per token+role (server, owner, observer), with event names, monotonic ticks, PID, connection status and IDs only; no private character payloads. Attached actual MultiplayerAPI connection/disconnection and NetSession welcomed/disconnected/private-read signals, including rejoin; logged ACL/owner read/observer forgery milestones. Parent prints bounded trace tails and deletes only its own token-scoped trace files.
- Raised server readiness wait from 12 to 22 seconds after an actual 13.9s false startup timeout and independently observed server world-ready at 11.6s. No production code or normal regression thresholds changed.
- No edits to city-owned, Blender, GitHub, AI room or public distribution.

## Actual tests and errors
- Initial modified diagnostic parse: `trace_path :=` inference error; fixed to typed `String`. Subsequent diagnostic script load had no parse errors. `godot_check`: 60/60 PASS.
- First long diagnostic invocation via connector failed internally (no success claim); subsequent bounded 89s invocation exited 1 after 13.9s with 1/14 because server startup exceeded original 12s; worker was directly tested and reached ready with baseline=3, and readiness bound corrected.
- Final 3-OS-process Godot run: **8/14 PASS, 6 FAIL**, `exit=1`, `timed_out=false`, 54.4s. It is STILL FAILING, not accepted H3.
- Trace proves server accepted owner and observer peers; owner received welcome and sent initial private-read but got no reply; owner disconnect/rejoin succeeded and **rejoined owner did receive** private snapshot; observer's rejoin public view and reliable forged-read fence succeeded without private snapshot. `server_initial_diag` missing (conditional server marker likely not reached within its 25s window; not proof of absent server RPC). Observer initial public spawn/gone checks and owner/observer overall checks failed. New stderr errors `Unable to send packet on channel 0/1, max channels:0` in NetSession broadcast/clock during disconnect/shutdown; not yet attributed to production vs fixture teardown.
- Existing real ENet in-process regression `tests/test_character_net.tscn`: **97/97 PASS**, `exit=0`, `timed_out=false`, 17.7s. Core syntax 60/60 PASS. Known 20 ObjectDB exit warning. No UI change, render not required.

## Skeptical Gemini audit
Gemini reviewed concrete trace code/results. Valid caution: per-process `Time.get_ticks_msec()` values are not synchronized across child process starts; no causal timestamp comparison. Its suggestions of shared-file race and missing trace-file close are NOT applicable: file paths include unique run token+role and each `_trace` call closes the file. Its diagnosis of a specific server race or ENet packet loss is unproven. Audit and root cause remain partial; no privacy security certification.

## Next ONE step
Add an explicit bounded owner-initial-read / server-receive phase handshake and server-side ACL/reply observation (with shared wall-clock event stamps) to this diagnostic fixture, then rerun the three-process test before any production-code changes. Do not mark H3 complete until independent-process privacy/rejoin checks pass.
