# H3 owner readiness frame-gap attribution — 2026-11-01

Run: `main-fallback-1793531530-94404`. Test-only instrumentation; H3 remains FAILED/PARTIAL.

## Change and scope
Changed exactly `tests/diagnostics/h3_three_process.FAILING.gd` (SHA-256 `a66283945952e03c46665c8aba65dfab73774c32cc5835595218b31cf0aa0fc1` -> `78abfcc87416a87504dda6c2b2fa9453b908b52c64e1098b3cf4d8189de531f2`). Added owner-only `SceneTree.process_frame` monotonic gap sampler (threshold 250ms, maximum eight trace records), stage transitions around creator, synchronous world construction, owner readiness, gate and private RPC, and parent trace correlation. Callback disconnects on normal worker completion. No acceptance assertions, timeouts, production code, city files, or UI changed.

## Evidence
- Godot syntax checker: **60/60 OK**.
- Cold production three-child fixture: **FAIL**, exit 1, tool `timed_out=False`, wall time **74.3s**. Owner synchronous `_world` **25ms**; owner `process_frame` gap **22132.4ms** with both previous/current stage `owner_ready_wait`; readiness probe **27752ms**, `ok=false`, despite nominal 12s readiness window. Test runner emitted `TEST SELHAL`.
- Same fixture with existing `--prewarm` option: **FAIL**, nested Godot process exit 1, wrapper exit 0 / `timed_out=False`. Owner `_world` **22ms**; owner readiness frame gap **15432.4ms**; readiness probe **21129ms**, `ok=false`. Prewarm also incurred an earlier **4670.9ms** boot-stage frame gap. `TEST SELHAL` emitted.
- Production ENet Apply regression `tests/test_character_edit_apply_enet.gd`: **97/97 PASS**, exit 0, no timeout. All three test processes were launched by the fixture; no surviving Godot processes at subsequent coordinator inspection.
- Cold stderr included inactive multiplayer peer errors, freed lambda capture, and existing ObjectDB 20 leak warning. These are **not** fixed. No graphical UI changes, so no render test required.

## Interpretation and limitations
The long gaps occur *after* the synchronous `_world` call has returned, while the owner is awaiting its initial spawn/visibility. The 12-second deadline can overshoot because a `process_frame` wait cannot evaluate the deadline while the engine is not dispatching frames. This **does not** identify the blocking operation: scene/visual spawn work may occur later during frame processing, as may network/engine work. The two A/B samples differ, but are not sufficient to claim that prewarming causes an improvement. The sampler measures intervals between dispatched frames, not CPU utilization or the stack during the stall.

Gemini pre/post skeptical audit completed. Its valid points: potential timing observer effects, callback lifetime on abnormal termination, and stage attribution not equivalent to root cause. Its unsupported claims of proven event-loop deadlock/OS synchronization, zero instrumentation overhead, and impossible network blocking were independently rejected; no CPU trace or thread stack exists. The pre-audit's conceptual `connect(integer, CONNECT_ONE_SHOT)` example is invalid and was not used.

## Next single step
Instrument a **test-only** `SimVisual`/spawn creation boundary (entry/exit monotonic timestamps, no private payload) during first-owner readiness and correlate it with the existing frame-gap trace and server peer lifetime in a bounded cold three-process run. Do not change the 17 gates or deadlines. Do not claim H3 complete before repeated stable acceptance.
