# H2b network character-edit ownership predicate — 24 October 2026
Run: `main-fallback-1792847626-91274`. Scope: `scripts/net/net_session.gd` plus `tests/test_character_edit_ownership.gd/.tscn`.

## Implemented
Added `server_can_edit_character(sender_peer_id, sim_node)` as a **server-internal predicate only**, not an RPC. It requires HOST/DEDICATED and a connected authoritative server; a server-maintained `players` entry with `own=true` and exact sim mapping; server-spawned player metadata with UID matching the authoritative CharacterData record; no duplicate owner; and valid, not queued-for-deletion world and actor. A future RPC must obtain the sender exclusively from `multiplayer.get_remote_sender_id()`, never from client-provided peer ID. No network edit functionality has been exposed. Existing `main.read_character_edit/apply_character_edit` still fail closed in every network mode.

## Actual tests
`tests/test_character_edit_ownership.tscn`: 25/25 (positive server policy simulated in a local Godot scene; negative unknown/wrong/zero sender, household controller, forged UID, duplicate owner, disconnect, CLIENT/OFFLINE, null/NodePath/Dictionary/Object/empty/path traversal IDs, deletion, network read/apply denial).
Regressions: live character edit 38/38, editor UI 55/55, session 30/30. Total 148/148. All four suites exit=0, timed_out=false. `godot_check` 60/60. Pre-existing 18 ObjectDB leak warnings on engine exit; no test failure. No UI change or new visual render. **These are policy/unit tests, not actual ENet multi-client security tests.**

## Independent Gemini audit and dispositions
Gemini actually reviewed the supplied predicate and test context. It proposed adversarial type, path, UID, duplicate, disconnect and deletion tests, and hardening of queued-for-deletion actors. We added the missing type/path/deletion tests and queued-for-deletion checks, then reran the suites.
Gemini called duplicate ownership a P1 risk, but the implementation already returns false when two peers claim the same sim; the regression confirms rejection. Its path traversal P1 hypothesis is not supported as a bypass: `Main.find_sim` uses `sims_root.get_node_or_null(NodePath(node_name))` **and** checks `sims.has(n)`, while exact `players[id].sim` and `_character_records` keys must match. A traversal negative test returns false. Metadata spoofing requires server-side code mutation, not a demonstrated remote attack.
Remaining real boundary: the predicate's `sender_peer_id` is trusted only if supplied by server code from the authenticated RPC sender. It is **not** independently authenticated by this function, and cannot be advertised as a complete multiplayer security solution.

## Open / exact next step
Implement the RPC handler and owner-only private reply with authoritative sender ID, size/rate limits, canonical server validation, revision checks, and public appearance replication; test real ENet server and two clients, hostile payloads, reconnect and owner reassignment. Until then, leave all remote character editing disabled.
