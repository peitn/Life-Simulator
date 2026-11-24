# Multiplayer

Godot 4 high-level multiplayer over **ENet** with an **authoritative server**. The default port is
`24565`, and up to 8 clients can connect.

## Modes

| Mode | Launch | Description |
|---|---|---|
| Offline | *(default)* | Local simulation. The player controls the whole household. |
| Host | `--host [port]` | Listen server that simulates and plays at the same time (peer 1). |
| Dedicated | `--server [port]` | Headless server with no local player. Models and audio are not loaded. |
| Client | `--join <address[:port]>` | Only displays. Characters are `SimPuppet`s fed by the server. |

ENet does not exist on the web platform. `NetSession` checks for it with `ClassDB` and reports
`ERR_UNAVAILABLE` there; a WebSocket transport is planned.

## Security model

- **Clients send only requests:** chat, a command for their own character, a vote on game speed. The
  server checks types, lengths, ownership of the character, that the action and object exist, and the
  rate limit.
- RPCs towards clients are `authority`-only, so a client cannot call them on others. `server_relay` is
  disabled.
- A client that does not introduce itself within the hello timeout is disconnected. A rejected client gets
  a reason, and the disconnect happens 0.5 s later.
- Validation lives in pure, unit-tested functions in `net_protocol.gd`: sanitising text, unique names,
  ids and rate limits.
- The server rejects:
  - `involuntary` actions (a panic attack cannot be commanded);
  - system actions;
  - content forbidden by the server's content settings;
  - "help" for a character that is not having an attack.

## Privacy

| Data | Who receives it |
|---|---|
| Position, rotation, label, emotion, mood, posture, current action, speech bubble (`net_*`) | everyone (`MultiplayerSynchronizer`) |
| Needs, feelings, relationships, memories, mental state, thoughts, diagnoses | **the owning player only**, via RPC |
| Public appearance snapshot (allowlist from the schema, visible scars and tattoos only) | everyone |
| Identity, orientation, aspirations, story, mental-health predispositions, traumas | owner only. Diagnoses never appear in spawn data. |

## Joining with your own character

The client sends its character's share code (`LSC1.…`) in `hello`. The server decodes it, migrates it and
validates it in **strict** mode. It assigns its own 128-bit uid (a client uid is not an identity) and
spawns the character. Only the public snapshot is replicated. Appearance is deterministic, so every peer
renders the same character bit for bit.

## Time

The server owns the clock and syncs it twice per second. Speed is the lower median of player votes. An
emergency pause lasts 30 s, with a 3-minute cooldown.

## Planned

- Lobby and menu, character hand-off, a household per player.
- Saving server state, reconnect tokens.
- WebSocket for the web build.
- Packet size limits, tests under latency and packet loss.
- Opt-out from PvP conflicts.
- Showing the server's content settings to clients on connect.


## Lifecycle note (5 Nov 2026)
A player's own character leaves the world with the player: on disconnect the server frees it and
MultiplayerSpawner replicates the despawn to every client. A client that joined before another player still
receives that player's later spawn and public look updates (verified across separate OS processes by
`tests/test_world_observer_late_owner`). Tests that keep checking another player's character must keep that
player connected until the checks finish.


## Joining without main-thread stalls (7 Nov 2026)
A client used to freeze for several seconds right after the ENet handshake: the first replicated
character built its GLB model, hand/foot detail meshes, hair cards and authored C5 garments on the
main thread (measured 4–7 s per first visual under load). The server then dropped the peer, which was
the root cause of the long-standing `h3_three_process` failures. Now, in the game path
(`Main` config `async_character_assets`, default = `visuals` and not `--test`):
- `HairRig.async_build` and `ClothingWardrobe.async_load` build hair and garments in the
  WorkerThreadPool; the character shows the GLB helmet hair and the GLB's basic shirt/trousers/shoes
  until then (never a bare body);
- `ClothingWardrobe.prewarm_async()` starts all garment kinds at game start;
- a client builds one throw-away character visual **before** `net.join()` so the model and detail
  meshes are cached.
Regression: `tests/test_h3_three_process_game.tscn` (three OS processes, real model) 17/17. The
diagnostic `tests/diagnostics/h3_three_process.FAILING.tscn` without flags keeps the synchronous
worst case (5/17).

Evening of 7 Nov 2026: the main-thread half of a background garment build (creating the ArrayMeshes)
is spread over frames with a 4 ms budget (`ClothingWardrobe.realize_budget_usec`) instead of one long
frame per kind; a kind is reported ready only after its last mesh exists. `NetSession.shutdown()` marks
the session disconnected before closing the ENet host, so the server's `peer_disconnected` handling during
shutdown no longer tries to send roster/chat/clock packets into the closed host. The three-process
game-path test passed 17/17 five times in a row after these changes.


## H4a — reconnect to the same character (8 November 2026)

A player whose connection drops no longer loses their character immediately.

- **Token.** After welcoming a player who controls a character, the server sends only that
  client a one-time reconnect token (32 random bytes from `Crypto`, 64 lowercase hex chars,
  RPC `_s2c_reconnect_token`). The server stores only `sha256(token)` (`_peer_token_hash`).
  The client keeps the token in memory only (never on disk, never logged).
- **Hold.** On an *unplanned* disconnect (not `_c2s_leave`, not server shutdown) and with
  `reconnect_grace_seconds > 0`, the character stays in the world under AI control (the
  player's command queue is cleared) and is recorded in `_held[hash]` with the original player
  name and an expiry. A held character is never handed to another player (`_free_sim`), held
  own characters count toward `MAX_PLAYER_CHARACTERS`, and held names are reserved for
  `unique_name` (no impersonation in chat during the grace period).
- **Resume.** A client that has a token sends `_c2s_resume(name, version, token, code)`
  instead of hello. Only a pending peer may call it (one attempt per connection). A valid,
  unexpired token restores the *same* node (needs, relationships, memories, mental state,
  ownership/edit ACL, public-look catch-up and private state stream) with the original name,
  and the server immediately issues a new token (rotation; the old one is dead). An invalid,
  reused or expired token silently falls back to the normal strict hello path with the
  character code, so a guess gains nothing.
- **Expiry.** After the grace period an own character despawns for everyone (as before H4a);
  a household character is released to the pool.
- **Leave.** `request_leave()` (also sent when the game window is closed) tells the server not
  to hold the character; the server disconnects the client after `KICK_DELAY`.
- **Broadcast filter.** `_remote_players()` now includes only peers that SceneMultiplayer still
  lists *and* whose ENet packet peer is `STATE_CONNECTED`, which removes the
  "Unable to send packet … max channels: 0" errors during concurrent disconnects.
- **Defaults.** The real game (`Main` without `net_config`) uses
  `RECONNECT_GRACE_DEFAULT = 120 s`; injected test configurations default to 0 (pre-H4a
  behaviour) unless they set `reconnect_grace`. Protocol `VERSION` is 4 (new RPCs).
- **UI.** After a disconnect the HUD shows a "Znovu připojit" button when resuming is
  possible; `Main.reconnect()` reloads the scene with an in-memory resume configuration.

Known limitations: ENet traffic is not encrypted (no DTLS yet), so a token could be sniffed
on a hostile network path exactly like the rest of the session; held characters are not yet
persisted across a server restart (networked save remains H4b); if the connection fails
after the resume request was sent but before the welcome, the client has already discarded
the token and joins as a new player.

## Server world persistence (H4b, 9 November 2026)
The host and the dedicated server save the multiplayer world and restore it after a restart.
- `scripts/save/server_world_store.gd` reuses the offline save format (atomic write, `.bak`, SHA-256 envelope, no objects decoded, strict character validation) and adds a `server` section: player-created characters, pending reconnect holds `{hash, sim, name, own, remaining}` and the listen host's own character.
- Only SHA-256 hashes of reconnect tokens are stored. Private character data (mind, story, memories) stays on the server's disk and is never sent to clients beyond the existing owner-only private state.
- On start, before any client connects, a valid snapshot replaces the fresh household. Players connected at save time get the full reconnect grace from the restart; existing holds keep only their remaining time. Clients return with the token they already hold (HUD "Reconnect"). Player-created characters nobody can return to are not restored.
- Any invalid or corrupted snapshot falls back to `.bak`, then to a fresh household. Restore is refused for a non-empty world, with connected/pending peers, or on a client.
- Config: `server_persistence` (default on in the real game, opt-in in injected tests), `server_save_directory` (default `user://server_world`), `server_autosave_seconds` (default 120). Saves also happen on game-day rollover, window close and scene exit while the session is live.
- Not covered: DTLS (tokens travel unencrypted), a player who leaves on purpose between the last autosave and a crash is restored as a hold until the grace expires.


## Walls (B2, 22 Nov 2026)

- Clients request `wall` [x0, z0, x1, z1] (lattice points) and `unwall` [wid] through `_c2s_lot`. The server checks
  the player (must control a character), the shared lot bucket and a stricter wall bucket (2, refill 0.5/s), integer
  types and lattice bounds, then `LotGrid.check_wall` decides (geometry, surroundings, access, reachability, money).
- Walls are in the public lot snapshot; clients re-check types, bounds, lengths and geometry and drop the whole
  snapshot if anything is off. A real ENet test covers building, forged requests, late join and demolition.
- Doors and windows (B4a, 23 Nov 2026): `open` [wid, kind, at] and `unopen` [oid] use the same path and the wall
  bucket; the server checks types (kind is a known string of at most 16 characters, `at` 0..80) and `LotGrid` decides.
  Closing a door is refused if it would shut a character in (`door_traps`) or cut off an access point. Openings are in
  the public snapshot (`open`) and re-validated by clients. There is still one shared household lot: any player who
  controls a character may build on it; per-lot ownership comes with the shared city.

## Lot and buy mode (B1, 20 Nov 2026)

- Clients request `buy` / `sell` / `move` with `_c2s_lot`; only the authority applies them through `LotGrid` (see [world-building.md](world-building.md)).
- The server checks the sender is a player with a character (spectators cannot spend the household budget), a per-player rate limit (4 burst, 1/s), the request shape and value ranges (coordinates inside the grid, rotation 0–3, known catalog id).
- The public lot snapshot (items with price and purchase time, budget; no ledger or player names) goes to all players after each change and to a new player right after the welcome. Clients sanitise it before rebuilding nodes.
- Smart-object order is default furniture followed by purchased items by ascending uid, so object indices in player commands match on server and clients.


## Slander across players (23 Nov 2026)

- `_c2s_slander_verdict(vid, choice)` – any peer; the sender comes from the transport only. The server checks: registered player, shared command token bucket, the peer currently controls a character, `vid` is an `int`, `choice` is a `String` from `believe` / `dismiss` / `tell`, and the verdict belongs to that peer's character (a guessed `vid` of another character is rejected with `owner`). `default` can only be applied by the server (expiry, overflow, character leaving).
- `_s2c_slander_pending(items)` – authority only, sent only to the listener's owner and only when the list changes (checked every 0.5 s; the host's own list is updated locally). Items are `[vid, author first name, rival first name, rumour line]`; the client sanitises the packet (types, at most 8 items, control/bidi characters removed, length limits). No relationship numbers or psyche data are sent.
- Private notices go only to the listener's owner (and, after *tell*, to the victim's owner).
- The victim cap and slander gates are enforced on the server for both player commands and AI decisions.

### Door locks (B4b, 24 November 2026)

- Lot action `lock` with arguments `[oid, lock]` through the existing `_c2s_lot` RPC. The server validates the
  types, the lock string (`""`, `"*"` or a valid node name without control, bidi or zero-width characters, at most
  64 characters) and applies both the general lot rate limit and the stricter builder limit (the check runs BFS).
- Key rules: a client may lock a door only for **its own** character or for everybody. A personal lock of another
  character can only be changed by that character's player while the character has a player (connected or held
  for reconnection); a lock of a character without a player (left for good, AI-controlled) or of a deleted
  character can be cleared by anyone in the household, so an abandoned lock cannot block the house forever.
  Otherwise the remaining options are knocking, waiting or demolishing the door (which costs household money).
  Spectators cannot lock. Offline, the player controls the whole household and may set any lock.
- The lock is part of the public lot snapshot (7th element of each opening; v3 servers send 6). Clients re-validate
  it (valid lock string, doors only, at most 16 locks) and the door leaf/lamp follow it locally.

### Careers (K1, 24 November 2026)
Career commands (`work_shift`, `work_hard`, `work_slack`, `work_scheme`, `call_in_sick`, `job_search`, `quit_job`) carry `career: true` and are validated by the server via `main.career_command_block` (schedule window, employment, sick/worked today, a running promotion contest for scheming, unemployment and cooldown for job search) after the usual ownership and rate-limit checks. Career data never leaves the server. A character at work has posture `away`; its node is parked below the world and client puppets hide. Wages are added to the shared lot budget and broadcast with the public lot snapshot. Scheming against another player's character is only possible inside a promotion contest between characters of the same track and level, and the harm is capped to once per victim per day. See [careers.md](careers.md).
