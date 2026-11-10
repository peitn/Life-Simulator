# H3 three-process production ENet integration — FAILED diagnostic (2026-10-30)

Run: `main-fallback-1793391122-1633`. Source of truth: live Godot `lifesim`.
No production, city, Blender, GitHub, or AI-room changes.

## Decision and lock
Read CHECKPOINT.md, DEVLOG.md, docs/implementation-sequence.md, docs/automation-lock.md, latest previews/automation-history and source hashes. Last successful PRIMARY run was `main-ts4-real-autonomy-1793367879-183743` at 13:57:45 UTC (>75 minutes). Latest fallback `main-fallback-1793387756-192198` completed at 19:26:13 UTC and does not count as primary. v3 inspect: unlocked, no other Godot processes. Acquired main lease `main-fallback-1793391122-1633` at 20:12:02 UTC; history running confirmed, pre-backup project 405704KB and library 123493KB. All edits under G.owns and heartbeat.

## Attempted development (NOT accepted)
Created a real three-child-OS-process integration fixture for production `Main`/`NetSession`: dedicated server, owner with fictional creator code/private story and attraction, spectator, owner disconnect/rejoin, spectator forged private-read with reliable chat fence, and server canonical-record checks. New fixture could not pass. It was deliberately isolated, NOT left as a normal passing regression:
- `tests/diagnostics/h3_three_process.FAILING.gd` SHA256 `5beeb442dfc8c03b50ed459307a835d2837fa72ea011b4788ebfef21b7c24e62`
- `tests/diagnostics/h3_three_process.FAILING.tscn` SHA256 `67637d0c2308df3f91bcb963ada6a19656dcf6974feffde398fb8d2caf97bd31`
- Temporary `tests/test_h3_three_process_character.gd/.tscn` created and subsequently deleted after moving into diagnostics.

## Actual tests and limitations
- First new fixture invocation: exit=None timed_out=True at 95s because GDScript parse errors (method name collided with Node._get; dynamic := inference). Corrected and explicitly parsed.
- Subsequent new fixture runs: exit=1, timed_out=False, 71.0s **6/13**, 73.0s **7/13**, 71.5s **6/14**. These are FAILURES, not green tests.
- Evidence: 3 distinct Godot child PIDs launched, server baseline 3, server character-spawn counter 2 (two incarnations, NOT two processes); owner sometimes receives an assigned sim but initial private read has `read_sent=true`, `reply_count=0`; spectator public replication and disconnect/rejoin checks intermittently fail; forged-read fence was not reached. These symptoms do not establish a production privacy exploit, because the fixture never proved the packet reached the server.
- Known engine stderr on failed fixture includes `The multiplayer instance isn't currently active`; process-level logs are insufficient to attribute root cause. Parent cleans up only its own spawned child PIDs, not foreign processes.
- Existing in-process **real ENet** `tests/test_character_net.tscn`: **97/97 PASS**, exit=0, 17.9s, no timeout. Godot core syntax **60/60 PASS**. Diagnostic scene/script load successful. No new UI/render changes; no render required. Pre-existing ObjectDB20 shutdown warning.
- No evidence of other Godot processes on final v3 inspect.

## Skeptical Gemini audits
Two Gemini reviews performed. First inaccurately claimed production edit RPC uses unreliable channel; actual `scripts/net/net_session.gd` declares reliable RPCs. It also incorrectly called normal wait_until polling a proven spawn race. Second correctly called for improved process lifecycle diagnostics but incorrectly inferred `spawned=2` means only two OS processes (it is server character incarnation count). No unverified diagnosis accepted as fact. Root cause remains **PENDING / test failing**.

## Next ONE step
Under a new valid main lease, instrument the failing fixture with per-process server/client log files and a bounded phase handshake (server-side ACL and receive counters, client disconnect reasons, reliable RPC dispatch) BEFORE changing production code; re-run and distinguish fixture synchronization from real cross-process NetSession defect. Do not call H3 three-process privacy complete without a fully passing test.

Run outcome: **failed**. Final backup and G.release status recorded in history.
