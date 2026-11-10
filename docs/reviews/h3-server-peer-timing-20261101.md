# H3 server peer lifetime and owner/observer timing — 2026-11-01

Run: `main-fallback-1793516908-83395`. **H3 PARTIAL / NOT ACCEPTED.** No production edits. Original 17 gates and their deadlines unchanged.

## Scope and provenance
Read live CHECKPOINT.md, docs/implementation-sequence.md, docs/automation-lock.md, automation history, fixture and NetSession. No independently completed productive primary MAIN step in prior ~75 min. Acquired v3 main lock, verified running history and owns, initial remote project/library backup succeeded (407216 KB / 123493 KB). Pre-edit SHA-verified fixture copy: `previews/automation-backups/main-fallback-1793516908-83395-pre/h3_three_process.FAILING.gd.txt`.

Exactly one diagnostic fixture modified: `tests/diagnostics/h3_three_process.FAILING.gd` SHA-256 `c3aeaa3ecde73a7bd152ba3ab2cf1de7c023672c4534f5665282114635fe4c2d` -> `68bba27f9fd221d748177fa9b7058e5fea0d8e4979377fc3166871d5f9b2ac15`. Changes: 250ms server lifecycle *change-only* snapshot adds kick-schedule count, kicked count and ENet peer count; existing 1s marker probe adds server pending/kick counts and oldest pending age; post-disconnect server callback records peer lifetime and transport state; correlation whitelist includes the new event. No private data/UIDs/addresses logged. Callback is **after** NetSession's own disconnect handling; its cleared pending/kick fields alone cannot prove pre-disconnect state.

## Actual bounded Godot results
- Guarded **cold** three-process run A: **17/17 PASS**, parent exit=0, 49.82s, timeout=false, 3 child processes, 0 survivors; owner private RPC reply waited **22,679 ms** and succeeded. Observer first marker was seen; server recorded kicked_total=0.
- Independent same-fixture guarded **cold** run B: **14/17 FAIL**, parent exit=1, 46.37s, timeout=false, 3 children, 0 survivors. Failed exactly observer_initial, observer_gone, observer_done. Owner RPC **was sent** and private reply **succeeded** after **18,148 ms**; owner_initial marker written at UTC-ms **1793517159542**, observer marker wait ended without it at **1793517159310** (**232 ms earlier**). Observer later saw the second incarnation's public spawn. Nominal 12s observer wait is not a hard wall-clock deadline under large frame stalls; the measured wait lasted longer. This does NOT establish a deterministic root cause.
- Both runs: server `stats.kicked` remained 0 in observed snapshots (and `_kick()` in production increments this counter), no scheduled kick at post-disconnect callbacks. Peer lifetimes A ~32.3s; B ~25.1s. This is evidence **against application-level kick in these two runs**, not proof against ENet timeout/transport loss in other runs.
- Unmodified production ENet `res://tests/test_character_net.tscn`: **97/97 PASS**, exit=0, ~20.2s. `godot_check`: **60/60 OK**. No UI changes, so no render required.
- Child stderr NOT CLEAN: freed lambda capture and ENet channel-0/channel-1 send failures on teardown (stack through `NetSession._on_peer_disconnected`), plus parent ObjectDB20 warning. These remain real unresolved issues even when all 17 gates pass.

## Skeptical Gemini audit and independent verification
Gemini pre/post reviewed planned diff and actual results. Valid concerns: diagnostic file I/O can perturb scheduling; callback order is post-cleanup; two runs do not prove stability; 232ms marker order is correlation, not root cause; teardown errors are not cleared. Independently verified `NetSession._kick()` increments `stats.kicked`, and `_on_peer_disconnected()` erases `pending` and `_kick_at` before diagnostic callback. Rejected Gemini's unsupported assertion that timing variability is independent of production behavior and its proposal to increase the observer timeout to 15s: that would violate the unchanged 17-gate acceptance contract. No sensitive data shared with Gemini.

## Single exact next step
Instrument **server-side receipt/dispatch/response** of the owner's first private read alongside client frame gaps during its 18–23s reply wait, preserving the existing 17 assertions, deadlines and owner authorization; compare independent bounded three-process runs before proposing a production fix. H3 remains FAILED/PARTIAL.
