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
