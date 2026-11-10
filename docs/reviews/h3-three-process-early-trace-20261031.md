# H3 separate-process early lifecycle trace — 2026-10-31

Run: `main-fallback-1793427177-18831`. Scope: only `tests/diagnostics/h3_three_process.FAILING.gd`; production, city, Blender, GitHub and AI Room untouched.

## Decision and actual change
After reading live CHECKPOINT, implementation sequence, v3 lock protocol, automation history and file hashes, the latest successful primary MAIN completion was 2026-10-30 13:57:45 UTC, more than 75 minutes before this run. V3 main ownership acquired at 06:12:58 UTC; history confirmed and initial project/library remote backup succeeded (405738 KB / 123493 KB).

A trial change decoupled owner readiness from puppet visibility (SHA 768cf78a), but the three-process fixture still failed 6/17, exit 1, 73.04 s, timeout false, 3 children, none surviving. It did not establish any improvement and weakened the initial puppet readiness assertion, so it was **reverted**. This trial is NOT retained in the final source.

The retained single change is bounded parent stdout visibility of the first 12 non-overlapping JSONL trace entries for each role, in addition to the pre-existing last 22. Final fixture SHA-256: `b3b5cf57cd1facfd12ec260549ea8e49f27c78ba9045a051341ef6483b6417f6` (before `0b4362df26ba23292a287a774d1fd41da20656ab7fdbecdf60a8022404f88af3`). No RPC, permissions, game logic, marker conditions or data schema changed.

## Actual verification
- Godot explicit diagnostic load: PASS; syntax check 60/60 PASS.
- Final three-process Godot run through bounded Python wrapper: **5/17 PASS, 12 FAIL**, exit 1, 74.55 seconds, timed_out false, three verified children seen, zero forced/leftover. The preceding temporary-condition run was 6/17 FAIL, exit 1, 73.04 seconds, timed_out false. Neither is acceptance.
- Existing production in-process ENet regression on final source: **97/97 PASS**, exit 0, 19.8 seconds, no timeout; known ObjectDB 20-instance shutdown warning. The earlier regression before final diff was also 97/97 PASS, 21.7 seconds.
- Captured final-run stdout now contains early server/owner/observer lifecycle entries that had been omitted by tail-only printing. Server world construction: 10.626 seconds; owner connected at UTC-ms 1793427512570; server peer 895167877 connected at 1793427512571. Server's first player roster/character-spawn transition logged at 1793427519442 (~6.87 seconds after first peer connect); observer welcomed at 1793427519464. Server disconnected first peer at 1793427524448; server consumed owner_read_ready at 1793427524558 (110 ms **after** disconnect), with key empty and ACL false. Server sampled maximum frame gap 6871.6 ms. Owner's first ready marker was false with empty key and peer 0. These timestamps establish ordering **in this run**, not the underlying CPU, transport or production cause.
- Final owner-rejoin marker also failed private snapshot in this run; other runs previously showed a successful rejoin. No proof of cross-process privacy acceptance or of a production security vulnerability.

## Skeptical Gemini review
Two reviews of the trial and final changes. The trial was judged not worth retaining after no improvement, and was reverted. The final bounded early-log output was judged low-risk; independently checked that it does not alter RPC/marker semantics and avoids duplicate first/last lines. Rejected unsupported claims that a specific transport packet-loss mechanism or scheduler overload was already proven. Audit is advisory, not test evidence.

## Remaining status and next single step
**H3 PARTIAL / three-process acceptance FAILED.** Next: instrument the exact elapsed duration of server `_register_player` / `_spawn_player_character` and corresponding welcome delivery in a minimal staggered-start fixture, to distinguish expensive authoritative spawn from client scheduling/replication delay before modifying production behavior. Keep original initial-puppet readiness requirement and all owner-only privacy assertions. No release/build success claim.

Final backup and v3 release must be checked in automation history separately.
