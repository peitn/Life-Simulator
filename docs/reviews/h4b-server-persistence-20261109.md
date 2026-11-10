# H4b — server-side multiplayer world persistence (review, 2026-11-09)

Run: `main-claude-1794208938-273195` (Claude, scheduled). Scope: host and dedicated server save the
multiplayer world and restore it after a restart; players return to their characters with the
existing one-time reconnect token (H4a).

## What changed
- **New** `scripts/save/server_world_store.gd` (`ServerWorldStore`): wraps the offline `GameSave`
  format (atomic `.tmp` write + read-back verify, `.bak` rotation, SHA-256 envelope,
  `bytes_to_var` without objects, 8 MB cap, strict per-character validation) and adds a `server`
  section `{v, own[], held[{hash, sim, name, own, remaining}], host_sim}`.
  - Only SHA-256 hashes of reconnect tokens are written. The server never has the plain token.
  - `validate_server_section()` is strict: version, known keys only, 64 lowercase hex hashes,
    unique hashes and sims, referenced sims exist in the same snapshot, names already sanitized
    (no control/bidi characters), `own` flag consistent, finite `0 < remaining <= 86400`,
    `host_sim` must be an own character that is not held.
  - `restore()` runs only on a networked authority, only into an EMPTY world before any player
    or pending peer exists; everything is validated before anything spawns. Player-created
    characters that nobody can return to (no held entry, grace 0, host save loaded by a dedicated
    server) are removed from the snapshot together with references to them.
  - `load_data()` tries the primary, then `.bak`; both must pass the GameSave checks AND the
    server-section checks.
- `scripts/save/game_save.gd`: `capture()`/`apply()` take `allow_authority = false`. Without it
  the offline-only boundary is unchanged (test `test_h4b_persistence_boundary` 3/3).
- `scripts/net/net_session.gd`: `host(..., register_local)`, `register_local_host()` (listen host
  registers after the restore and gets its saved character back), `persist_snapshot()`
  (connected players with tokens → future holds with the full grace; existing holds keep only
  their remaining time), `restore_held()` (remaining time clamped to `reconnect_grace_seconds`,
  never double-held), stat `restored_held`. Protocol version unchanged (no wire change).
- `main.gd`: config `server_persistence` (default ON only for the real game, opt-in for injected
  test configs), `server_save_directory` (default `user://server_world`, separate directory for
  the eight-resident household), `server_autosave_seconds` (default 120, min 5);
  `_restore_server_world()` (fallback to a fresh household on any failure, cleans partial
  spawns), autosave on interval and on game-day rollover, save on window close and `_exit_tree`
  (only while the session is still live — after `shutdown()` nothing is overwritten).

## Tests
- **New** `tests/test_h4b_server_persistence.tscn` — **110/110** (real ENet in one process):
  default off; save + `.bak`; no plain tokens in the file; crash; restart; restored household,
  own character (meta + UID), relationships, memory, needs, game clock, private `mind` record,
  revision; full grace for players connected at save time; hash-as-token and used token take
  nothing; A (own) and B (household) resume with the same token, no new spawn, ownership + edit
  right, token rotation, owner private state; interval autosave; expiry after restart (own
  despawns and replicates, household freed); grace 0 drops own characters; 19 tampered
  server-section cases; forged primary; truncated primary → `.bak`; random-bytes primary → `.bak`; both corrupt →
  fresh household; remaining grace not extended by a restart; restore refused for non-empty
  world / connected players / clients; listen host gets its own character back.
- Regression: `test_mp_reconnect` 72/72 (×3), `test_multiplayer` 67/67 (one known clock-sync
  flake 66/67 when four suites ran in parallel; 67/67 alone), `test_character_net` 97/97,
  `test_save_game` 46/46, `test_h4b_persistence_boundary` 3/3, `test_full_playable_slice` 87/87,
  `test_world_enet_multiprocess` 11/11, `test_character_edit_ownership` 75/75,
  `test_host_character_editor` 10/10, `test_net_protocol` 34/34, `test_h3_three_process_game`
  17/17, `test_save_continuation` 12/12, `test_live_character_edit` 38/38; `godot_check` 60/60;
  real `--server` smoke start without errors.
- The fallback run at 06:10 UTC reported `test_mp_reconnect` as a 35 s TIMEOUT. Re-run with a
  sufficient tool limit: 72/72 in 24.5 s with unchanged code — the limit, not a regression.

## Independent review (Gemini `gemini-3.5-flash`)
| Finding | Verdict |
|---|---|
| Character "purged" on restart after an intentional `_c2s_leave` | Rejected: by H4a design a player-created character leaves the world together with its player on intentional leave (`_despawn_own`), so it is never in `own` without a player or hold. |
| Host character dropped when a listen-host save is loaded by a dedicated server | By design (a dedicated server has no host player who could return); now documented in the store header and docs. |
| `character_uid` meta lost for sims without a record | Rejected: every sim is spawned through `spawn_character()`, which always creates the record; `SaveGame.capture()` refuses a world with a missing record. |
| Repeated restarts extend the reconnect window indefinitely | **Accepted and fixed**: holds now persist `remaining`; restore uses `min(remaining, grace)`; tests added. |
| Attacker with disk write access can plant a hash | Out of the threat model (such an attacker can rewrite anything, including private data); documented. Validation protects against corruption/inconsistency. |

## Known limits / open
- A player who intentionally leaves between the last autosave and a crash is restored as a hold
  (expires after the grace window).
- Transport is still unencrypted ENet (DTLS open); tokens travel in clear on the wire.
- Engine-level stderr noise without GDScript backtrace remains: "multiplayer instance isn't
  currently active" (get_unique_id) and once "max channels: 0" during simultaneous test teardown.
- No visual change in this run (no render); server status in HUD is only the existing notice.

## Grok (AI room #422) — response
| Point | Response |
|---|---|
| Constant-time token compare | The server never compares tokens: it looks up `sha256(token)` as a Dictionary key among 256-bit random-token hashes; there is no secret-dependent byte loop to time. Kept. |
| Truncated/partial write, autosave + crash | Writes go to `.tmp`, are read back and verified, then renamed; a valid primary is rotated to `.bak`. **Added test**: truncated primary → `.bak` (now 110/110). |
| Reconnect in the middle of an autosave | Autosave runs synchronously on the main thread; ENet RPCs are processed on the same thread between frames, so a resume cannot interleave with a capture. |
| What happens during downtime | Nothing: the world is the snapshot of the last save; the clock and needs continue exactly from it (test checks clock, needs, relationships, memory, private record). |
| Privacy after restore, host case | **Added check**: another player (B) does not receive A's private state after restore; host restore is a separate test section. |
| Scaling for the city | Full snapshot is fine for one lot (configurable interval, min 5 s). Incremental/dirty saving is noted for the shared-city step. |
| Token rotation across restart | Covered: the rotated token appears in the autosave only as a hash; a used token after restart takes nothing. |
