# H3 callback-time ENet state diagnostic — 2026-11-01

Run: `main-fallback-1793506164-76902`. Scope: **test-only**, no production or city-owned changes. Latest primary main task had no independently verified productive completion in the preceding 75 minutes. Read fresh CHECKPOINT, implementation sequence, lock v3 documentation, recent automation history, and the H3 fixture. Main v3 lease acquired, running history verified; remote pre-edit backup succeeded (project 406363 KB; library 123493 KB).

## Exact source change

`tests/diagnostics/h3_three_process.FAILING.gd` SHA-256 `c1f904048d6798705930a6443f9a8018a695fe326adc424c10814e19cf5a17ad` → `a086e7520bc19be06540b7932f675abc433188ef1d0b0efebaa0e716df3eae50`. Added `_transport_snapshot`: callback-time `MultiplayerPeer.get_connection_status()`, `MultiplayerAPI.get_peers()` count/target membership, network connected flag, player/pending counts, kicked counter; guards freed world/network nodes and never logs private payloads, UIDs, credentials or addresses. Traced peer_connected, peer_disconnected, server_peer_exit_context, connection_failed, server_disconnected, and net_disconnected. Preserved all 17 H3 gates, timeout thresholds and production files.

The first diagnostic run exposed a real test-only teardown error at the old `owner_transport_closed` callback: `Invalid access to property or key 'net' on a base object of type 'Nil'` (line 194). Removed the late direct world access and reused the guarded snapshot in owner/server disconnect contexts. Both intermediate source versions were backed up under `previews/automation-backups/main-fallback-1793506164-76902-pre/`; the original pre-edit source is saved as .gd.txt. No project mutation without main lock ownership, source SHA comparison and heartbeat.

## Real test evidence

- First guarded three-process cold test: **11/17 PASS, 6 FAIL**, fixture exit **1**, 49.82 s, 3 child Godot processes, 0 survivors, runner timeout **false**. Error: freed-world callback access (above). This run is **not** accepted.
- After callback guard fix: guarded three-process cold test: **14/17 PASS, 3 FAIL** (`observer_initial verified`, `observer_gone verified`, `observer_done verified`), fixture exit **1**, 39.53 s, 3 children, 0 survivors, timeout **false**. No `Invalid access ... 'net' ... Nil` error in captured stderr. Remaining stderr includes `Lambda capture at index 1 was freed`, ENet send channel 0/1 errors during teardown, and existing 20 ObjectDB warning. These remain open.
- At server `peer_disconnected` callback, the target peer is absent from `get_peers()` while server transport status still reports 2 (connected) and `kicked_total=0`; later client `net_disconnected` callback reports transport status 0 and zero peers. These are callback-time snapshots, **not** proof of timeout vs deliberate disconnect, exact socket state, or causality. One trace with `world_valid=false` confirms safe fallback after world release.
- Unchanged production `test_character_net.tscn`: **97/97 PASS**, exit 0, 18.7 s, no timeout.
- Godot syntax check: **60/60 OK**. No UI change, so no render claimed.

Gemini skeptical pre/post/follow-up audits completed on proposed code, actual diff and freed-world error. Accepted lifecycle/teardown cautions; independently rejected its unsupported claim that `MultiplayerAPI.get_peers()` is unavailable (existing fixture already uses it successfully). Audit does not establish disconnection root cause.

**State:** H3 FAILED/PARTIAL, no production fix, no GitHub write, Blender/city files/AI room untouched.

**EXACT NEXT SINGLE STEP:** isolate the observer's three failed H3 marker checks in a clean bounded three-process run by correlating server roster transitions with observer marker timing and teardown. Preserve all 17 gates and do not relax thresholds or change production ACL.
