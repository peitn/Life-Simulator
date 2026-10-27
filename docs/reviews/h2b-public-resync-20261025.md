# H2b bounded public-look resync audit — 2026-10-25

Run: `main-fallback-1792919572-153455`. Main task's last independently recorded completed code/test run ended 07:02:58 UTC, over 75 minutes before this fallback's 09:12:52 UTC start. The city task's later progress was not counted as main-task completion. v3 main lock acquired, run history confirmed, and pre-edit backup uploaded (114948 KB).

## Actual change
- `scripts/net/net_session.gd`: added a **feature-flagged** client request when the actual spawned incarnation has no matching snapshot among already-buffered variants. Deduplicates once per name/incarnation, bounded by spawner name budget, cleared on despawn/disconnect/shutdown.
- Added `_c2s_character_public_look_resync` with authenticated sender from ENet, introduced-player gate, current actor and 128-bit incarnation binding, canonical revision check, per-peer token bucket (4 burst, 0.25/s), and a unicast through existing strictly validated **public-only** look broadcaster. No client-provided revision, peer ID, private data or authority flag accepted. Disconnected peer limiter entries are erased.
- `tests/test_character_edit_apply_enet.gd`: real ENet server/two-client overflow test. An evicted incarnation gets a canonical unicast look after explicit spawn callback; private mind/trait levels remain absent; incorrect incarnation request fails; valid later request gets latest revision; despawn clears dedupe. Test fixture explicitly enables the normally-disabled staged feature.

## Executed verification
- Targeted `test_character_edit_apply_enet.gd`: **82/82** twice, `exit=0`, `timed_out=False`; real ENet transport and explicit production spawn callback.
- Production `res://tests/test_character_net.tscn`: **70/70**, `exit=0`, `timed_out=False`, 15.5 s; actual MultiplayerSpawner lifecycle and repeated Apply regression. An initial incorrect attempt to run its Node script as SceneTree via `godot_run_script` returned exit1; corrected to the actual .tscn scene and passed. That invalid invocation is NOT counted as a test pass.
- `godot_check`: **60/60** scripts; no new parser errors. Pre-existing **18 ObjectDB** leaked-instance shutdown warning remains. No UI source changed; no screenshot/render claim.

## Independent skeptical Gemini review
Two actual responses examined implementation/test excerpts and then adversarially challenged the resync/rate-limit design. No independently demonstrated P0/P1. The audit's blanket 'secure' language was not treated as proof. Its speculative replay and cross-peer/NAT starvation claims are not demonstrated by this authority-only RPC and per-ENet-peer limiter. Real limitations:
1. Resync triggers only when a name has pending variants but none matches. **If the entire name is evicted**, no resync is requested.
2. One-shot client dedupe has no bounded retry if the server rejects due to rate limit or a response is missed. A self-spamming peer can starve its **own** resyncs.
3. Targeted test uses explicit spawn callback; it does not prove all real-world jitter/spawner timings. Rate-limit exhaustion, reconnection and malicious traffic are not exhaustively tested.
4. Remote character Apply/editor remains **OFF by default**; no new visual render verification.

## Files changed this run
`scripts/net/net_session.gd`, `tests/test_character_edit_apply_enet.gd`, `docs/reviews/h2b-public-resync-20261025.md`, `CHECKPOINT.md`, `DEVLOG.md` (documentation updates to follow this review). No city-owned paths, Blender, GitHub writes/commits/PR/push, or AI room messages.

**NEXT SINGLE STEP:** add bounded retry/queue for a missing *entire* pending name and a rate-limited/unanswered public resync, with authenticated real-ENet recovery tests. Only then continue rendered client appearance verification and guarded remote UI. H2b remains PARTIAL.
