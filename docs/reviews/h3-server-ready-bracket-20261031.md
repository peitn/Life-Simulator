# H3 first-spawn readiness bracket — 2026-10-31

Run: `main-fallback-1793437889-27158`. H2b functionally accepted; H3 remains PARTIAL. This is a **test-only diagnostic**; it does not fix multiplayer acceptance or production performance.

## Source and safety

- Changed only `tests/diagnostics/h3_three_process.FAILING.gd`, SHA256 `a7d9de5aa5d06476d922adfad477fc2a687ecbf41a7d4a244d30ed1a0da6ccae` -> `86fd805a06b1317241effc1f8cd05f167ee0db350a2a75a4d6339fd44096382e`.
- Existing 17 acceptance checks retained. Instrumentation observes server `child_entered_tree`, matching player node `ready`, optional `MultiplayerSpawner.spawned`, and `roster_changed`. Missing stages are recorded as -1, not counted as success. No private payload is logged.
- V3 MAIN lease acquired and history verified; pre-edit remote project/library backup succeeded (405737/123493 KB). No city-owned paths, Blender, GitHub, or AI room writes.

## Actual Godot results

- Explicit changed diagnostic script load: PASS, exit=0, no timeout.
- Static Godot syntax: 60/60 PASS.
- Bounded real **three separate child OS processes** via `tests/diagnostics/h3_bounded_runner.py`: **6/17 PASS, 11 FAIL, exit=1, elapsed=73.12s, timed_out=false, children_seen=3, children_cleaned=[], children_forced=[]**. Full stdout/stderr and exit captured in ephemeral `/tmp/lifesim_h3_1793437889_27158.json` (not persistent project backup).
- Existing in-process real ENet production regression `tests/test_character_net.tscn`: **97/97 PASS, exit=0, 18.9s, no timeout**.
- 3-process stderr: seven `The multiplayer instance isn't currently active` errors during shutdown and existing ObjectDB20 warning. In-process ENet stderr: ObjectDB20 warning. No UI source changed, so no UI render was required.

## Measured lifecycle, server-local event timestamps

| Stage | First owner | Rejoined owner |
| --- | ---: | ---: |
| Peer connected -> matching player child entered | 11 ms | 11 ms |
| Matching child entered -> `node.ready` | **5581 ms** | **7 ms** |
| `node.ready` -> roster update | 3 ms | 3 ms |
| Matching child entered -> roster update | 5584 ms | 10 ms |
| Server-side `MultiplayerSpawner.spawned` signal | NOT OBSERVED (-1) | NOT OBSERVED (-1) |

First owner node `Hrac1619893220_Fixture`, rejoin `Hrac1942677831_Fixture` are fictional fixture entities and were correlated by actual node name and peer id; `spawn_match=true` both times. The server-local 5.581-second bracket is **between tree entry and node ready**, not the subsequent roster callback. This narrows the earlier 4–6 second delay. It does **not** establish CPU saturation, the exact method responsible, whether child node initialization or scheduling dominates, or that the production network protocol is correct. The missing server-side spawner signal is not itself evidence of an engine defect.

## Skeptical Gemini audit and independent checks

Two Gemini reviews of concrete instrumentation and results. Accepted: possible observer overhead, timing jitter, event-order ambiguity, reuse of node names across incarnations in a general system, and the need for explicit missing-stage values. This fixture's actual first and rejoin node names and peer IDs differ, and both matched the expected peer; no observed name collision. `ready` and roster were actually seen, while server-side `spawner.spawned` was not; no assumption of a guaranteed signal ordering was used. The diagnostic's per-node stage map is test-scoped and bounded by fixture lifetime.

Rejected unsupported claims: Gemini questioned the existence of Godot 4.7.2 (the actual tool reports `Godot Engine v4.7.2.stable.official.ed1daf0bf`); inferred that 97/97 in-process proves production cannot be at fault (it does not); called elapsed `get_ticks_usec()` measurements CPU time (they are elapsed monotonic time); and interpreted absent server `spawned` as a possible architectural defect without evidence. No Gemini causal hypothesis is marked proven.

## Single next H3 step

Instrument **first-instance SimAgent readiness** in a strictly gated diagnostic to separate `SimAgent._ready` entry/exit and selected child-ready phases from the 5581ms tree-entry-to-ready interval, measuring elapsed wall time and per-frame gaps without treating elapsed time as CPU time. Then rerun unchanged 17 acceptance checks. Do not modify production RPC or relax assertions based on timing correlation alone.

Final backup and release status must be checked against the v3 run-history record.
