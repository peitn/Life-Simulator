# H2b — spawn-incarnation binding review (25 October 2026)

Run: `main-fallback-1792908884-149245` (Godot `lifesim`, protocol-v3 main lease). Before writing, inspected checkpoint, implementation sequence, lock rules and run-history; no proven main-task completed development in prior ~75 minutes. History confirmed this run's acquisition; pre-edit backup uploaded (114891 KB).

## Exact implementation
- `scripts/net/net_session.gd`: generate fresh 128-bit lowercase hex `net_incarnation` for each server MultiplayerSpawner spawn; store the public token as node metadata on server/client; include token in public appearance RPC; validate sender, type, token, revision and strict public-only snapshot; reject mismatched live puppet and mismatched pre-spawn pending packet. The token is a lifecycle discriminator, NOT an authentication secret or private CharacterData UID. Remote Apply remains disabled by default.
- `tests/test_character_net.gd`: previously confirmed recycled-name old-look overwrite (old 182cm vs new 160cm) is now asserted rejected, new token differs on actual server/client spawn, current-incarnation update is accepted. Four additional passing assertions relative to previous 66.
- `tests/test_character_edit_apply_enet.gd`: adapt staged two-client ENet fixture to token-bearing RPC and per-node metadata; add explicit pre-spawn old-incarnation mismatch regression (two additional assertions).

## Actual verification
- Production `test_character_net.tscn`: **70/70**, exit 0, 16.6 s, no timeout, actual MultiplayerSpawner with ENet server/clients, reused actor name and old/current incarnation packets.
- Staged `test_character_edit_apply_enet.gd` run as SceneTree script: **62/62**, exit 0, no timeout, includes early pending look, stale and malformed packet rejection, current incarnation.
- `test_character_edit_ownership.tscn`: **75/75**, exit 0, no timeout. An initial attempt to run this Node-derived script directly as SceneTree returned exit 1 due to the incorrect harness; rerun via its real .tscn succeeded and is the counted result.
- `godot_check`: **60/60** syntax checks. All successful runs retain the pre-existing 18 ObjectDB shutdown warning; no newly observed runtime errors. No UI changes; no render/screenshot claimed.

## Independent Gemini audit and disposition
Gemini actually reviewed code excerpts and real test outcomes twice. Its first claim that `_apply_pending_public_look` is never called was **false**: `setup()` connects `spawner.spawned` to `_on_spawned`, which invokes that function. Gemini explicitly retracted this. It then correctly identified a **remaining liveness limitation**: pending appearance data is a single slot per node name. If a new-incarnation look is queued before spawn and then an old-incarnation packet replaces it, the new snapshot may be lost; token comparison prevents corruption but cannot guarantee delivery. This packet ordering was not demonstrated in production network traffic. Avoid claims of universal race immunity or delivery guarantees.

## Open / exact next step
Use bounded per-incarnation pending queues (or a validated latest-state resync) and a deterministic two-incarnation pre-spawn regression, including despawn callback ordering, then actual rendered client appearance inspection. H2b remains partial and remote editor remains OFF. No GitHub publishing, city/Blender/AI-room writes.
