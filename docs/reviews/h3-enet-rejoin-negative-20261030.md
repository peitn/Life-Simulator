# H3 ENet reconnect privacy adversarial regression — 2026-10-30
Run: `main-fallback-1793387756-192198` (main fallback, Europe/Prague 20:15–20:24).

## Ownership and prior work
Read fresh CHECKPOINT.md, docs/implementation-sequence.md, docs/automation-lock.md, history and file mtimes. Last completed PRIMARY run main-ts4-real-autonomy-1793367879-183743 ended 13:57:45 UTC, >75 min before this run. Previous fallback `main-fallback-1793383758-190247` remained `running` with last heartbeat 18:15:29 UTC and expiry 18:55:29 UTC. Waited through the full 20-minute grace; coordinator v3 archived its abandoned lease atomically during successful acquire at 19:15:57 UTC. Never manually touched foreign owner/lock. Pre-edit backup project 405703 KB, library 123493 KB. No city, Blender, GitHub or room writes.

## Actual development
Inherited the prior fallback's uncompleted H3 rejoin test section already present in `tests/test_character_net.gd` (its existing baseline was 95/95 exit0, 17.3s); did not claim that inherited code as newly written here. Added two *new* assertions to that same test: spectator B spoofs the rejoined creator-character node name in local request preflight, sends an actual reliable private-read RPC over ENet, and awaits a reliable server->spectator chat echo sent after the request on the same channel. The echo is an observable receive fence, not an arbitrary sleep. Verified no private snapshot reaches B and server canonical character record remains unchanged; restored B's original local actor name. Owner's private attraction and backstory are received only by owner; spectator gets public appearance. Rejoin by code creates a NEW server-owned character; old incarnation identity is NOT persisted.

Changed source/test file: `tests/test_character_net.gd` (final SHA256 `b3c0e3788ed1fbb2a6efe14597d4313fa6787754e80a03d56af0fe021606c87a`). No production GDScript changes and no UI changes; no render required.

## Real tests and failures
- Prior inherited 95/95 baseline, actual Godot headless `tests/test_character_net.tscn`: exit0, no timeout.
- Initial post-edit attempt failed: backend tool error and own test child remained running; bounded subprocess reproduced GDScript parse error at line 485 (`var forged_read_sent :=` could not infer dynamic type), and timed out after 42s because scene failed to load. This is a real failed attempt, NOT a pass. Terminated ONLY that exact orphaned test child after checking /proc cmdline and PPid=1; no foreign worker touched.
- Fixed by explicitly typing `var forged_read_sent: bool`, then actual bounded Godot test 97/97 exit0 in 18.62s; repeat via Godot runner 97/97 exit0 in 17.8s, no timeout.
- Existing offline creator/save/cold-start regression `tests/test_full_playable_slice.tscn`: 87/87 exit0, 13.5s.
- Godot checker: 60/60 core scripts syntax OK; it does not substitute for executing this test script. Existing ObjectDB20 leaked-instance shutdown warning persists in successful runs, not introduced by this test.

## Skeptical Gemini audit and independent checks
Two connected Gemini reviews. First correctly requested an active negative observer read but incorrectly flagged cleanup variables as undefined; all are defined earlier in the same function. Second alleged unreliable RPC ordering and missing restoration on timeout. Independently checked `_c2s_character_edit_read`, `_c2s_chat`, `_s2c_character_edit_snapshot`, `_s2c_chat`: all are reliable RPCs on default channel, so the chat echo is an ordered receive fence; `wait_until` returns a bool after deadline and does not throw, and the original actor name is restored before teardown. A hard crash can still abort the test, but cannot produce a false PASS. No unverified Gemini claim was promoted to fact.

## Limitations and next single step
This is real ENet transport with server and multiple clients in **one Godot process**, not a three-OS-process test or internet/hostile-client certification. A code-based reconnect creates a new character, not recovery of the original player incarnation or private session. H3 remains PARTIAL.

**NEXT ONE STEP:** run a separately launched three-process native ENet creator-to-household spawn/privacy/reconnect fixture, with authoritative owner-only read, active spectator forgery, and explicit old-incarnation rejection; preserve server-authoritative privacy. Do not change city-owned paths or publish to GitHub without new approval.
