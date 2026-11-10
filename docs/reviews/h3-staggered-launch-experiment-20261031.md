# H3 three-process controlled launch-order experiment — 2026-10-31

Run: `main-fallback-1793430686-22135` (v3 main lease). Scope: test-only; no production RPC, editor, city, Blender, GitHub or AI-room changes.

## Change and provenance
Read current main CHECKPOINT, DEVLOG, implementation sequence, lock v3, automation history, file hashes and mtime. No successful primary productive step in preceding 75 minutes (last documented 2026-10-30 13:57:45 UTC); previous fallback was `failed` and lease was free. Acquired main v3 lease, verified running history, and verified pre-edit remote backup (project 405738 KB, library 123493 KB).

Modified only `tests/diagnostics/h3_three_process.FAILING.gd` SHA256 `b3b5cf57cd1facfd12ec260549ea8e49f27c78ba9045a051341ef6483b6417f6` -> `58b52e562129dc735e3fde80693a85d1589cc7afbbd19472173e27e7d28eb6c8`. In the diagnostic parent only, start owner first, delay observer start by 2.0 s, and print both UTC start timestamps. Preserve all 17 acceptance assertions, all private-state checks, fixture timeout, server/client production behavior and no private payload logging. The controlled stagger is an experiment, not a proposed permanent acceptance-test fix.

## Real execution
- Bounded three-process Godot run: **6/17 PASS, 11 FAIL**, exit **1**, elapsed **74.53 s**, fixture timeout **false**, three child PIDs observed, cleaned/forced survivors **none**. Runner startup launcher itself returned a tool timeout because child process held its pipe; the independently written /tmp result JSON confirmed final fixture status and stdout/stderr/exit. Do not conflate launcher timeout with fixture timeout.
- Start owner UTCms 1793430787273; start observer 1793430789274: measured stagger **2001 ms**.
- Server world construction **9916 ms**, completed UTCms 1793430787267. Owner server peer_connected UTCms 1793430788939; server sim_child_entered UTCms 1793430788950 (11 ms later); server roster_changed/spawn count update UTCms 1793430793568 (**4618 ms** after child_entered, **4629 ms** after peer connect); max measured server frame gap **4628.8 ms**. The gap is observed, not proven to be caused by any one function.
- Server initial-read gate at UTCms 1793430817192: marker seen, but ACL=false, record=false, player_present=false. Initial owner read not sent; owner rejoin later received its private snapshot. No three-process privacy acceptance.
- Previous concurrent-start baseline: 5/17 PASS, 12 FAIL, 74.55 s (single run). New 6/17 does **not** establish improvement or root cause; outcomes remain unstable and the changed order changes the test scenario.
- Production in-process real ENet regression `tests/test_character_net.tscn`: **97/97 PASS**, exit 0, 17.9 s, no timeout. Godot core syntax **60/60 PASS**; explicit modified diagnostic load PASS. No UI change, render not applicable.
- Diagnostic stderr includes 7 `The multiplayer instance isn't currently active` get_unique_id messages during shutdown, plus known 20 ObjectDB leak warning. The successful in-process test has the known ObjectDB warning. Do not call stderr clean.

## Independent skeptical Gemini audit
Two reviews: before and after actual test. Valid concern: fixed 2s delay is not deterministic synchronization and can mask races; a PASS would not prove a load-related cause. Post-test review agrees measured 4.6s gap is correlation and test still fails. Its wording that `6/17 FAIL` meant six failed was imprecise: **six passed, eleven failed** according to actual fixture output. No proposed speculative causal mechanism was accepted without trace evidence.

**Status:** Diagnostic experiment completed; **H3 acceptance FAILED**, not a production fix. Final backup and v3 release are separately recorded in run history.

**NEXT SINGLE STEP:** Instrument exact server registration/spawn/welcome timing in a bounded fixture-only profiling run, focusing on the measured 4.6s interval from sim_child_entered to roster_changed, without altering production RPC behavior.
