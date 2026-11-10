# H3 observer phase timing — 2026-11-01

Run: `main-fallback-1793509741-80067`. Scope: **test-only instrumentation**, H3 still FAILED/PARTIAL. Read fresh CHECKPOINT, implementation sequence, lock v3 docs, automation history, last changes. No completed productive primary-main run in prior 75 minutes. v3 main lease acquired (ok:true, owns:true), running history verified, initial full remote backup succeeded (project 406650 KB, library 123493 KB).

## Exact source diff
`tests/diagnostics/h3_three_process.FAILING.gd`: SHA-256 `a086e7520bc19be06540b7932f675abc433188ef1d0b0efebaa0e716df3eae50` → `2e9fd33852dc0cb6067629eed3752a77b7f7fe62f3227d1ef679a59c4d2d0a66`. Five bounded edits: observer-local monotonic elapsed timer, privacy-safe `observer_first_phase`, `observer_gone_phase`, `observer_second_phase` trace points after existing waits, plus H3_CORRELATE output whitelist. No raw character payloads/UIDs/addresses in added traces. All original 17 assertions, wait windows, production code, network ACL and server behavior unchanged. Pre-edit byte-for-byte SHA-verified local copy at `previews/automation-backups/main-fallback-1793509741-80067-pre/h3_three_process.FAILING.gd.txt`. No UI changes/render needed.

## Actual tests
- Bounded **guarded** 3-process cold H3: **14/17 PASS, 3 FAIL**, fixture exit **1**, elapsed **42.58s**, runner timeout **false**, three child Godot processes, zero cleaned/forced/survivors. Runner wrapper exit 0 only means it produced a report; report `success:false`. Exact failing gates: `observer_initial verified`, `observer_gone verified`, `observer_done verified`.
- Observer first phase: UTC-ms **1793509871402**, `welcomed:true`, `initial_marker:false`, `spawned:false`, `public_ok:false`, `sims:4`, `roster:2`, connected ENet transport, one peer. Owner `initial_read_result` at UTC-ms **1793509871961**, `connected:true`, `private_ok:true`, `reply_count:1`. **559ms after** observer's first-phase timeout sample. Owner initial gate passes later; observer's missing first marker propagates into `gone:false` and `done:false` because `gone := spawned and ...`.
- Observer second phase later: `rejoined_marker:true`, `second_spawned:true`, `public_ok:true`. This narrows the failure to the first incarnation's marker timing, not an unconditional inability to spawn or replicate public look.
- Unchanged production ENet `test_character_net.tscn`: **97/97 PASS**, exit 0, no timeout, ~20.1s. Godot syntax: **60/60 OK**.
- Actual three-process stderr remains **NOT CLEAN**: freed lambda capture, ENet packet send errors during shutdown, ObjectDB20 warning. The wrapper's own stderr is separate and can be empty despite child stderr errors; do not conflate them.

## Interpretation / skeptical audit
Strong **single-run evidence** that observer's 12-second wait completed before owner wrote `owner_initial`. Because both timestamps are wall-clock UTC milliseconds from the same host, the 559ms ordering is meaningful at this precision; it does not establish what made the owner late (initialization, RPC latency, CPU load or other scheduling). The three failing gates are logically cascading in the fixture. Not a deterministic proof across runs or a production fix.

Gemini pre- and post-diff skeptical reviews performed on concrete source/outputs. Valid cautions: test-only trace overhead, limited single-run evidence, no causal proof of ENet root failure, existing teardown errors. Independently rejected an irrelevant suggestion to add ACK/flush because it would change the acceptance fixture's synchronization semantics, and the objection about comparing `Time.get_ticks_msec()` across processes does not apply to these two `utc_ms` trace fields (from `Time.get_unix_time_from_system()`). No sensitive data sent.

**EXACT NEXT SINGLE STEP:** independently reproduce and instrument the owner-side delay between initial visual readiness, private read RPC/reply and `owner_initial` marker, preserving original 17 gates and 12s observer wait; identify which phase consumes the time before deciding whether production work or a fixture synchronization redesign is justified.

GitHub READ-ONLY, no city-owned/Blender/AI-room changes. H3 NOT complete.
