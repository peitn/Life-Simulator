# H2b scoped owner-read cancellation audit

## 25 October 2026 — H2b generation-scoped read cancellation
Run: main-1792965886-196161. Actual v3 acquire + history verified; fresh ownership and heartbeat checks. Pre-change backup115582KB.
Changed scripts/net/net_session.gd: cancel_character_edit_snapshot(request_id="") now preserves a newer pending read when cleanup supplies an obsolete/unknown token; matching token clears pending ID/deadline. No-argument connection-wide shutdown and internal completion/expiry remain compatible. This is a bounded lifecycle prerequisite, NOT completed visible network UI.
Changed tests/test_character_edit_read_enet.gd: stale/unknown Cancel and rejected launch preserve newer generation/deadline; matching Cancel still rejects late authenticated reply.
Actual final tests: owner-read ENet46/46, production multiplayer67/67 (113 total), childexit0, no final timeout. Multiplayer stderr includes two EXPECTED unauthorized-RPC rejections from anti-cheat probes; existing18 ObjectDB warnings remain. Initial prepatch test attempt timed out20s (exitNone), NOT a passing or valid red regression result. Initial read-only snippet had mixed-indentation parse error and was corrected before edits. No visual changes/render.
Gemini actually reviewed relevant production code and complete test, then surrounding authorization/disconnect contracts. Three initial claims rejected after code inspection and actual disconnect regression: limiter leak, synchronous TOCTOU, implicit type coercion. Gemini follow-up explicitly withdrew them; no remaining scoped defect found. Audit docs/reviews/h2b-scoped-read-cancel-20261025.md.
Hashes: net e13a826d507fbdecaba44912c887221155467a8f57e9f08c31dfe2d21f0db50e; test fe38898ec2ab43699b299225bd5bd831fc3d8c7885178e45c8e506f536c72649.
H2b remains PARTIAL. NEXT SINGLE STEP: wire gated HUD/panel owner read with fresh token; panel cleanup MUST pass its own nonempty token, handle real timeout/Cancel, inspect normal+narrow actual renders. Network Apply remains default OFF until canonical ACK/readback and E2E.
No GitHub commit/publication, city/Blender or AI-room writes. Final backup and verified release recorded separately in run history.

## Review disposition
Gemini first response alleged limiter accumulation despite test cleanup, a limiter/serialization race without any await, and coercion without seeing server_can_edit_character. Supplied actual strict typeof guard, peer_disconnected callback erasing limiter before early return, host signal registration and shutdown cleanup. Follow-up: first two false, type handled, no remaining optional-token Cancel defect. This is source review, not Gemini-executed tests.
No change to rate limiting, authorization, RPC payload, timeout duration or legacy signal semantics. Empty token intentionally means global cancellation for internal/connection cleanup; future panels must use their own opaque generation token. A token is not ownership authorization.
