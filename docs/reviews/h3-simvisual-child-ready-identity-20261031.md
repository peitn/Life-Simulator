# H3 — Identified first-spawn visual readiness stall (31 Oct 2026)

Run: `main-fallback-1793445053-30844`. Scope: diagnostic-only. Production network, visuals, UI, city-owned paths, Blender, GitHub and AI Room were not modified.

## Verified change
Only `tests/diagnostics/h3_three_process.FAILING.gd` was changed (final SHA-256 `c230e087ffd80d3ccf1e1ac2f7d263ccd72eeae91e61bd709e6d2f96b254734f`). Server-side direct-child entered/ready trace now includes child name, class, script resource path and process-local instance ID; ready trace adds child-enter-to-ready elapsed milliseconds. Parent now prints all server direct-child events, including those otherwise lost between first-12 and last-22 trace windows. All original 17 acceptance assertions were retained.

First attempted edit had a GDScript inference error for `child_id := child.get_instance_id()`. Explicit fixture load exposed the parse error despite the returned resource being non-null; corrected to `var child_id: int`, reloaded with `can_instantiate() == true` and ran real tests. This initial failure is not counted as a pass.

## Actual test evidence
- Final independent 3-child-process H3 acceptance: **8/17 PASS, 9 FAIL**, fixture exit **1**, elapsed **64.20 s**, timed_out **false**, 3 observed children, none forcibly cleaned or left behind.
- Earlier diagnostic run before parent trace-window fix: **8/17 PASS, 9 FAIL**, exit 1, elapsed 69.82 s, no timeout, 3 children and no survivors. It exposed script identity in early trace but did not include first child-ready timing.
- Existing in-process ENet production regression after final edit: **97/97 PASS**, exit **0**, timed_out **false**, 20.7 s.
- Godot syntax checker: **60/60 PASS**. Explicit diagnostic fixture load after final edit: script instantiated successfully. Known ObjectDB leak warning (20) and 8 inactive-ENet shutdown errors in independent H3 stderr; not a clean acceptance run.

## Correlated server observations (same server PID and process-local instance IDs)
- First owner: `MultiplayerSynchronizer` named `Sync`, ready in **0 ms**. Direct `Node3D` child named `@Node3D@234`, script **`res://scripts/sim/sim_visual.gd`**, entered at parent+1 ms, **child entered → ready = 5299 ms**; identical instance ID on both entered and ready events.
- Owner rejoin: `Sync` ready in **0 ms**; second direct `Node3D` child named `@Node3D@244`, same **`sim_visual.gd`** script, **child entered → ready = 9 ms**, identical instance ID across both events.
- Previous H3 runs independently bracketed the first `Node3D` child at 4426 ms vs 6 ms on rejoin. The new evidence **identifies** the slow node as `SimVisual` and matches entered/ready for one instance; it does **not** prove which operation inside `SimVisual._ready() → _build()` is slow, nor whether the elapsed time is CPU time, I/O, process contention or other synchronous work.
- Read-only inspection: `scripts/sim/sim_visual.gd` has `_ready(): _build()`; `_build()` calls `AssetLibrary.instantiate`, `_build_model` / primitives and other mesh/material initialization. No production source was edited.

## Skeptical Gemini audit and independent adjudication
Gemini reviewed the planned change, the corrected code and test evidence. Valid cautions: wall-clock deltas are not CPU measurements, `get_instance_id()` is only unique inside one Godot process, node/script identity does not establish the causal sub-operation, and logging may affect timings. We correlated IDs only **within the same server process**. Gemini also incorrectly asserted Godot 4.7.2 could not exist (engine itself reports 4.7.2), and overclaimed JSON substring format instability: the actual emitted `JSON.stringify` output matched the exact filter in the final run. We did not treat speculative I/O/GC/engine claims as proven. No private character payloads were sent to Gemini.

## State and next single step
H3 remains **PARTIAL/FAILED**: no three-process privacy/replication acceptance. **NEXT:** instrument the first `SimVisual._build()` path in a gated test-only profiler to split asset instantiation, model building, hair/hand/foot and overhead setup; rerun the same 17 assertions and compare cold first spawn with warm rejoin. Avoid a production optimization until the costly substage is demonstrated.

Initial remote backup of project (405740 KB) and library (123493 KB) succeeded. Final backup and lock release must be confirmed separately in the run history.
