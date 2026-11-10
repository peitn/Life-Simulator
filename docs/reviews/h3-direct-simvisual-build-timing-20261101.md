# H3 — direct SimVisual._build timing in real three-process ENet (2026-11-01)

Run: `main-fallback-1793538821-97902`. H3 remains FAILED/PARTIAL; this is a test-only diagnostic, **not** a production fix.

## Change and guard
- Changed `tests/diagnostics/h3_three_process.FAILING.gd` SHA-256 `f00659ef8994937f31be5bbf5a3772dd38f92d51522c4be5ac4069467daccc39` → `6ed0ca38a330c19d24f93962ba344adeb6b5c99e9ecf10f7afbf38a843450d6c`.
- Before each isolated server/owner/observer worker starts production World, it verifies the exact on-disk `SimVisual.gd` SHA `2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3`, checks unique anchors in `_build()`, instruments the preloaded script resource **in memory** and verifies `GDScript.reload()==OK`. No production source file is modified. Instrumentation samples ticks after `_built=true` and immediately after `_place_overhead()`; only then does it append timing-only JSON to per-worker `user://` trace.
- All original 17 acceptance assertions and timeouts remain unchanged; no UI changes, so no render required. In-memory reload can alter caching and execution timing; the tracing file write happens after the measured interval.

## Actual tests and evidence
- Real bounded three-child H3 fixture: **8/17 PASS (FAIL)**, exit=1, runner timeout=false, elapsed 66.33s, 3 child processes tracked, 0 descendants left/cleaned. Initial Godot tool invocation returned an internal error, but the runner's independent JSON report was recovered and inspected; do not treat the tool error as a passing run.
- `simvisual_probe_installed` confirmed on all three child roles. Direct measured `_build` intervals include server **8342.145ms**, **1626.133ms**, **2641.556ms** and observer **9468.674ms**, **6166.796ms**. Observer `child_enter_to_ready` at the same timestamps measured **9469.04ms**, **6167.157ms**, respectively, strongly associating the long ready interval with synchronous `_build`. These are wall-clock elapsed intervals, not CPU profiles or proof of specific subfunction cost. Other direct events are not all surfaced by the fixture's early/tail trace export limit.
- Server peer disconnects at UTCms 1793539029450 and 1793539029463, with `kicked_total=0`; these overlap one long observer build (UTCms 1793539024453–1793539033922), but temporal overlap is **not proof** that visual building caused ENet disconnection. Child stderr still reports inactive ENet peer, freed lambda capture and 20 ObjectDB warnings. No root cause established.
- Unchanged production ENet Apply regression **97/97 PASS**, exit=0, timed_out=false; `godot_check` **60/60 OK**. No UI render necessary.
- Skeptical Gemini audit reviewed concrete instrumentation and numbers. Valid cautions: in-memory `reload()` may change timing/caches; elapsed `_build` does not identify its slow subfunction; no causal ENet claim. Rejected Gemini's unsupported assertion that disconnect is *necessarily* a consequence of a main-thread stall.

## Boundaries and next step
No city-owned, Blender, GitHub, AI Room, or production source writes. Test source, this report, `CHECKPOINT.md`, `DEVLOG.md` are the only planned project changes. Local SHA-verified pre-edit copies and initial full remote backup completed. Final backup/release status recorded in coordinator history.

**NEXT SINGLE STEP:** in a bounded test-only in-memory SimVisual probe, timestamp the `_build_model()` and `_apply_model_variant()` subphases for all four initial client visuals, export *all* events without early/tail truncation, and compare with peer disconnect timestamps across repeat runs. Do not change 17 gates or production source until a causal test supports a fix.
