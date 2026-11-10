# H3 owner-readiness vs ENet disconnect: two-process-clock correlation (2026-10-31)

Run: `main-fallback-1793477569-52476` (main v3 lock, diagnostic-only). No production, city-owned, Blender, GitHub or AI-room writes.

## Change

Modified only `tests/diagnostics/h3_three_process.FAILING.gd` (SHA-256 `2a4809839c28ceba254fe20ed0109cfe1b626974f82274e8f6942ffe7c8dd94c` → `7c5d4841ea9d38d36741070e3e6a4c79a7544ae052af25b33b8870aede346920`). Added fixture-only owner 12-second monotonic readiness start/deadline, ENet connection-status transitions, server peer-exit context (players/pending/kicked counter), client transport-close context, and a privacy-safe UTC event summary. No assertion or timeout thresholds changed (original 17 H3 gates intact). A checksum-verified pre-edit copy was saved as `previews/automation-backups/main-fallback-1793477569-52476-h3-fixture-pre.txt`. Full remote pre-edit project/library backup succeeded (405771/123493 KB).

## Actual runs

| Check | Cold run A | Cold run B |
|---|---:|---:|
| 3-process H3 gates | **6/17 PASS, 11 FAIL** | **8/17 PASS, 9 FAIL** |
| Exit / timeout | 1 / false | 1 / false |
| Wall seconds | 71.71 | 65.15 |
| Child processes / survivors | 3 / 0 | 3 / 0 |
| Server owner peer_connected UTC ms | 1793477712488 | 1793477845865 |
| Server owner peer_disconnected UTC ms | 1793477722496 | 1793477855762 |
| Connect → disconnect | **10008 ms** | **9897 ms** |
| Server kicked_total at exit | **0** | **0** |
| Owner readiness started UTC ms | 1793477712465 | 1793477845838 |
| Owner 12s deadline UTC ms | 1793477724465 | 1793477857838 |
| Owner readiness false UTC ms | 1793477736986 | 1793477869473 |
| Owner elapsed / max frame gap | 24521 / **19549.5 ms** | 23635 / **18727.4 ms** |
| Owner transport status at false | 2 (connected) | 2 (connected) |
| Owner server_disconnected callback UTC ms | 1793477737010 | 1793477869501 |

Server detects owner disconnect **before** the fixture's 12s readiness deadline in both runs, about 1.969/2.076s early. The owner probe returns false **after** its deadline because its per-frame coroutine cannot check elapsed time during a large frame stall. This is not evidence that the while-loop lacks a deadline guard: it already uses monotonic `Time.get_ticks_usec()` each iteration. The owner processes their server_disconnected callbacks 24/28ms after the delayed probe returns. Server `_kick` counter remains zero; this excludes that instrumented explicit kick path in these runs, not every possible network/OS disconnect cause.

In run A the first owner `SimVisual` child entered at UTC 1793477717448 and completed at 1793477726394 (**8947ms**), **after** the server detected disconnect at 1793477722496. Other visual builds also ran synchronously. The 18–20s owner frame gaps and nearly 10s server disconnect intervals are **consistent with** client main-thread starvation causing an ENet transport timeout, but do not prove the exact transport timeout configuration or exclude server-side scheduling/load, network retransmission, test-process contention, or other close paths. The UTC timestamps are comparable within a shared host but are event-observation times, not physical packet send times.

## Independent regressions and stderr

`godot_check` **60/60 PASS**; explicit diagnostic fixture load PASS; production `tests/test_character_net.tscn` **97/97 PASS**, `TEST OK`. Both 3-process H3 runs **FAILED** with exit 1, no timeout, 3 child processes and zero survivors. H3 stderr had existing Godot ObjectDB warnings (20 in run A, 2 in run B) and no reported parse error. ENet regression had existing 20 ObjectDB warnings. The changing 6/17 vs 8/17 failure counts emphasize timing variability, not success.

## Skeptical Gemini review and independent corrections

Gemini reviewed concrete instrumentation and run-A timing, then the two-run evidence. Valid concerns: UTC timestamps reflect callback execution, not packet times; client-side status can lag server detection; a frame gap does not isolate the blocking function; a ~10s disconnect is not yet a measured ENet timeout parameter. Gemini initially suggested adding a deadline break using `Time.get_ticks_msec() >= deadline_utc_ms`, which mixes monotonic and wall-clock domains and overlooks the existing correct monotonic loop condition; rejected. It also gave an inconsistent arithmetic example in the second response (using the owner's start instead of server peer_connected). Actual independently calculated server peer intervals are **10008ms and 9897ms**. No unsupported JIT/GPU/network-cause claim accepted.

## Status and exactly one next step

H3 **FAILED/PARTIAL**; no production change. **Next:** in a test-only experiment, inspect the actual ENet peer timeout/disconnect settings through engine-supported APIs and timestamp a lightweight independent heartbeat while the owner constructs its first `SimVisual`, then rerun the unchanged 17-gate cold fixture. Do not increase timeouts, weaken ACL or claim transport cause without verification.
