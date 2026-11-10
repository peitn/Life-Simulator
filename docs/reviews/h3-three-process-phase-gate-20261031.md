# H3 three-process ENet: initial owner-read phase barrier — FAILED (2026-10-31 local)

Run: `main-fallback-1793401877-7420`. Main last productive completion 2026-10-30 13:57:45 UTC (>75min); latest previous fallback 22:19:54 UTC had FAILED diagnostic, not a completed H3 gate. v3 main lock acquired 2026-10-30 23:11:17 UTC; history and ownership verified; initial project backup 405717 KB, library 123493 KB.

## Changed files and scope
- ONLY test fixture `tests/diagnostics/h3_three_process.FAILING.gd`, SHA256 final `605cce18a4da909c8b367c227fe867626231b3842a75a22efc9a8b4cb1cef8cb` (previous `f86a2348bf2676e62d99b40b08844f5980b783c1451f27a553fec5b325e5ba76`).
- Added wall-clock UTC milliseconds alongside per-process monotonic timestamps in token/role JSONL trace. Added owner_read_ready -> server_read_gate -> owner_read_sent fixture-only barrier; server checks peer ownership, canonical record and observes the rate limiter created by accepted edit-read processing without invoking a second private read. Added marker assertions/cleanup. Raised owner gate wait 10->28s after first diagnostic. No production/UI/city/Blender/GitHub/AI-room changes.

## Actual execution
- Godot syntax: 60/60 PASS. Existing real ENet in-process regression: 97/97 PASS, exit=0, 17.8s, no timeout; ObjectDB20 warning.
- First independent three-child-process diagnostic: **12/17, exit=1, 48.3s, no timeout**. Server owner peer disconnected at UTC ms 1793402016438, but gate evaluated at 1793402028858, after disconnect: ACL false, record absent, owner did not send initial read. Rejoined owner private snapshot and observer forged-read fence passed. Shutdown ENet errors persisted.
- Second diagnostic after increased wait: **7/17, exit=1, 66.5s, no timeout**. Server owner peer connected 1793402072771, disconnected 1793402082168, gate evaluated 1793402093942; again AFTER disconnect. Initial read intentionally not sent; rejoin owner private read passed, spectator initial/rejoin flow failed due disconnect. Godot stderr included inactive ENet peer calls; no direct evidence of leaked private data.
- The phase barrier prevents an unauthorized/meaningless read attempt after server-side ownership has disappeared, but it does NOT establish successful independent-process H3. The 17-22s delay in server gate processing is observed, not explained: could be test scheduling/CPU/file-marker visibility or other process issue. Do not assert a production transport vulnerability or a verified event-loop starvation root cause.

## Skeptical Gemini review and independent verification
Gemini correctly warned that `_edit_limiters.has(peer)` is not an acknowledgement of a SPECIFIC RPC, and that ACL evaluation after disconnect is invalid evidence of authorized access. It overclaimed that the limiter initializes on connection and that the timestamps prove event-loop starvation. Inspection of production `net_session.gd` shows limiter creation in server read/preflight, not at connection; the timestamps establish ordering only. Gemini proposed `multiplayer.has_peer(peer)`, but Godot ClassDB confirms this method does NOT exist; `MultiplayerAPI.get_peers()` does. No production code changed on the basis of unverified advice.

## Next ONE step
Instrument server and owner fixture around each `wait_until` with wall-clock timestamps, observed peer list via `multiplayer.get_peers()`, marker-file visibility and process-frame gap measurements. Identify why the server processes the owner-ready marker only AFTER ENet disconnect before changing production networking. H3 remains PARTIAL / three-process test FAILING.
