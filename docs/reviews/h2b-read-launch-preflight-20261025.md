# H2b correlated read launch preflight — 25 October 2026

Run: `main-fallback-1792962925-189949` (main fallback). The previous completed MAIN implementation was more than 75 minutes old. Atomic v3 acquire recovered an expired CITY lock by coordinator archival, without manually deleting or editing city ownership. No city-owned assets or docs changed.

## Actual production change
`scripts/net/net_session.gd`: `request_character_edit_snapshot(request_id)` now returns a bool indicating only that local client preflight allowed an RPC send attempt. It rejects malformed 32-lowercase-hex correlation tokens, non-CLIENT mode, disconnected client flag, missing local assigned actor, absent peer or peer not in CONNECTED status. Rejected calls do not allocate pending correlation/timeout state. This is NOT proof of server authorization, RPC delivery or permission to open an editor. Existing server-side authenticated ownership, private response correlation and six-second timeout remain unchanged. Remote Apply stays OFF and visible network editor is NOT wired.

`tests/test_character_edit_read_enet.gd`: added seven positive/negative checks covering malformed token, no pending state, disconnected, offline, unassigned, accepted correlated send and supersession. Actual ENet owner/observer privacy, cancellation, timeout and denial cases remain tested.

## Verified outcomes
- Targeted real ENet read test: **43/43**, exit=0, timed_out=false, final rerun after all changes.
- Production ENet hello/spawn/Apply/lifecycle: **70/70**, exit=0, timed_out=false, final rerun after all changes.
- Godot syntax check: **60/60**. Existing shutdown warning: 18 ObjectDB instances, not a new test failure.
- No UI layout/asset change, so no new render. Prior UI visuals do not prove a network UI flow.

## Skeptical Gemini audit, disposition
Two actual responses on the exact code/results. First response correctly warned that local send acceptance is not server authorization and proposed checking the `rpc_id()` return value before pending state. This proposal was **actually tried**; syntax passed, but targeted and production ENet runs repeatedly timed out (exit=None, not PASS). The proposed change was fully reverted from the verified intermediate backup. The final code was rerun and both suites passed. No precise cause of those timeouts was isolated; Gemini's second explanation about low-level ENet queue readiness and its suggestion of a mathematical guarantee from successful tests are **unverified speculation** and are not accepted as facts. The accepted fix is explicit documentation of bool semantics and fail-closed local preflight. Remaining risk: an RPC can be lost after a local send attempt; the existing six-second timeout and correlated cancellation limit stale editor reads, but the visible UI is not connected yet. Do not treat the local bool as an authorization result.

## Files and coordination
Changed: `scripts/net/net_session.gd`, `tests/test_character_edit_read_enet.gd`, `CHECKPOINT.md`, `DEVLOG.md`, this review. No GitHub push/commit/PR, no Blender/city/AI-room writes. Pre-edit project backup uploaded (115542 KB); per-file before/intermediate copies in `previews/automation-backups/main-fallback-1792962925-189949/`. Final backup and release recorded separately.

**Single next step:** implement a disabled-by-default staged HUD/panel owner-only correlated read flow, with fresh token per open, Cancel and six-second timeout, tests and actual normal/narrow renders; do NOT enable remote Apply.
