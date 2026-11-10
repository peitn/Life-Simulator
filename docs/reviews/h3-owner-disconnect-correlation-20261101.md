# H3 guarded three-process disconnect correlation — 2026-11-01 UTC

Run: `main-fallback-1793502677-74881` (main v3 lease). No completed productive primary MAIN run was present in the preceding 75 minutes; most recent history was fallback `main-fallback-1793498931-72823` (failed H3). Initial full remote backup confirmed: project 406356 KB, library 123493 KB. No production, city, Blender, GitHub or AI-room writes.

## Exact test-only diff
`tests/diagnostics/h3_three_process.FAILING.gd`: SHA256 `18dfb3802cd03a1c2ae8efdea5f3d4931828591d4b3231230e299657f32c21fe` -> `c1f904048d6798705930a6443f9a8018a695fe326adc424c10814e19cf5a17ad`. Only the _parent() H3_CORRELATE phase whitelist gained `initial_read_result`, `server_disconnected`, `net_disconnected`, all already emitted by existing callbacks. Original 17 assertions, thresholds, process orchestration, network code and fixture data unchanged. Local source backup: `previews/automation-backups/main-fallback-1793502677-74881-h3-fixture-pre.gd.txt` (verified byte-for-byte).

## Actual Godot tests and limits
- Guarded 3-process before diff: **10/17 PASS, 7 FAIL**, exit=1, 54.88 s, timeout=false, 3 children, 0 surviving children (bounded runner report).
- Guarded 3-process after diff: **8/17 PASS, 9 FAIL**, exit=1, 70.09 s, timeout=false, 3 children, 0 surviving children (final persisted runner report). An earlier post-diff report at the same path showed 67.4 s before a connector internal error/replay; it was overwritten, so do NOT count it as a separately certified run. No 17/17 reproduction.
- Godot syntax: **60/60 OK**. Unchanged production `test_character_net`: **97/97 PASS**, no new production regression. Existing stderr ObjectDB 20-instance warning; 3-process child stderr not clean in general. No UI render required (log-only change).

## Newly surfaced event ordering
The owner emitted `net_disconnected` with generic reason "Server ukončil spojení.", and `server_disconnected` at UTC-ms 1793502929627; `initial_read_result` at 1793502935434 showed `connected=false, sent=false, reply_count=0, private_ok=false`. A later owner rejoin also disconnected. These are observation timestamps from separate Godot processes, not synchronized causal evidence. The generic reason does NOT identify why ENet disconnected. No private character payloads or real user information logged in the added correlation lines.

## Skeptical Gemini audit
Gemini reviewed plan and exact post-change diff/results; correctly warned that phase additions are observability only and temporal correlation cannot prove root cause. Independently rejected its unsupported suggestion that per-process monotonic clocks can directly prove cross-process causality, its incorrect description of 10/17 PASS as 10 failures, and unsupported proposed API names. Internal connector error occurred after launching the second test; recovered final bounded runner JSON and verified zero remaining Godot processes. No production fix claimed.

## Single next step
In the existing test-only three-process fixture, add strictly bounded, privacy-safe snapshots of local ENet connection status and server peer lifecycle at their respective disconnect callbacks; rerun the unchanged 17-gate bounded fixture and compare event order without treating inter-process wall clocks as causal proof. No production timeout or ACL change until reproducible acceptance.
