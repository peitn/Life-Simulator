
# H2b — staged public appearance replication audit (25 October 2026)

Run: `main-fallback-1792880120-125362`. Status: **PARTIAL milestone**, not remote-editor completion.

## Changed code
- `scripts/net/net_session.gd`: server publishes validated public-only appearance snapshots after a successful changed Apply, to introduced/authenticated peers only. Client checks authority sender (peer 1), wire type/size, JSON shape, strict public-only schema, revision monotonicity and target puppet before applying. Signal + per-node revision bookkeeping.
- `main.gd`: server-only `read_public_character_look` returns `CharacterData.public_snapshot()`, not private data.
- `scripts/sim/sim_puppet.gd`: `apply_public_look` validates the public snapshot again and refreshes the visual.
- `tests/test_character_edit_apply_enet.gd`: real ENet server + two clients, private acknowledgements remain owner-only, public body updates reach both peers, private mind/story/personality intensity excluded, malformed authenticated server packet rejected, stale replay/forged local invocation/disabled flag rejected.

Production feature `character_edit_apply_rpc_enabled` remains **false**. No remote editor UI enabled, no new GitHub publication. The client test currently uses a minimal puppet stub, not full SimPuppet rendering.

## Verification
- Real ENet Apply and public-look transport: **35/35**, exit 0, no timeout.
- Real ENet owner-private read: **20/20**, exit 0.
- Server ownership/canonical commit: **75/75**, exit 0.
- Live edit: **38/38**, edit session **30/30**, editor UI **55/55**, all exit 0.
- Total functional assertions: **253/253**. Godot syntax check: **60/60**.
- Existing 18 ObjectDB leak warning on process shutdown; not counted as clean stderr.
- One initial test expected `personality` to be entirely private and failed; source schema explicitly makes `personality.traits` public while `trait_levels` and `hexaco` remain private. Corrected the assertion and re-ran successfully. Added an authenticated malicious `mind` packet regression; strict public-only validator rejected it and did not advance revision.

## Independent Gemini audit
Two actual Gemini responses. First incorrectly alleged P0 missing server-sender verification. Exact source already contains `if multiplayer.get_remote_sender_id() != 1: return` and `@rpc("authority",...)`; Gemini explicitly retracted the allegation when shown the source. Actual open limitation confirmed: late-joining clients or updates arriving before a puppet is spawned may drop the public look packet; client-side revisions are not seeded from initial spawn. This is a **functional blocker** to enabling the remote editor, not a demonstrated confidentiality break. Do not claim complete live appearance synchronization.

## Next single step
Add late-join and missing-puppet replay/initial snapshot synchronization with real SimPuppet/SimVisual integration and two-client lifecycle tests, then re-audit before considering feature enablement. Keep remote editing OFF until complete.
