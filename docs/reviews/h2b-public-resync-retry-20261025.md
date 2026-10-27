# H2b missing-name public-look resync and retry — 25 October 2026

Run: `main-fallback-1792922986-159387`. Scope: staged public appearance sync only; remote editor feature flag OFF.

## Exact changed source
- scripts/net/net_session.gd SHA256 b22b56b33c2498a5321934d24c3b41c549e2928d7cd81e032898cc8ce95c0ac7
- tests/test_character_edit_apply_enet.gd SHA256 e30320af5c69ac437421530c77ddd45fa724643cce641bcbbfe774fde6a41679
- CHECKPOINT.md, DEVLOG.md, this review.

A puppet with no pending name entry now requests canonical public-only resync. Request records are dictionaries {incarnation,attempts,last_sent}. _process on connected clients retries no more than twice after the initial request, at >=5s monotonic intervals. Current incarnation must match live puppet; accepted look clears pending request. Despawn/disconnect clears state. Server still checks authenticated sender, current actor/incarnation, revision and token bucket before public-only response. Does not turn on remote Apply.

## Evidence
Real staged ENet two-client test **94/94** exit0/no timeout: missing-name spawn, simulated dropped first reply, retry recovers canonical public-only look, successful response cancels retries, missing server actor exhausts three attempts. The retry elapsed time was advanced in test state, not a 5-second real-time soak. Production MultiplayerSpawner/owner/observer/late join/recycled-name **70/70** exit0 17.3s; Godot syntax **60/60**. Known 18 ObjectDB shutdown warnings. No UI changed, no rendered screenshots. An initial incorrect manual harness exited1; after code change the old test compared a dictionary request to a string and timed out; assertion corrected and final run passed. Neither failure is counted as success.

## Gemini independent skeptical audit
Two actual Gemini responses inspected concrete code/test excerpts. First alleged missing rate limiter, revision TOCTOU and stale incarnation reuse. Direct code inspection confirms server `_public_resync_limiters[sender].allow(_now())` after authoritative actor validation; server handler has no await; spawn token generated fresh by Crypto random 16 bytes. Second response withdrew the TOCTOU claim but alleged missing limiter cleanup; `_on_peer_disconnected` and `shutdown` explicitly erase/clear limiter state. These are not confirmed defects. No independently established new P0/P1. Actual limitations: client sends requests for any spawned puppet without a pending name (server ignores non-revisioned actors but adds traffic); per-peer bucket may throttle simultaneous recoveries; three attempts can exhaust without recovery; test manually advances timestamps and does not prove behavior under packet loss/jitter; no visual pixels validated.

## Next single step
Capture and inspect actual networked client appearance after resync at normal and narrow viewport, then continue guarded remote editor integration only after remaining H2b gates.
