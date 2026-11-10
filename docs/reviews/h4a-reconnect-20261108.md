# H4a reconnect — review record (8 November 2026, run main-claude-1794165732-262705)

## Change
- `scripts/net/net_session.gd` — reconnect token (server stores sha256 only), held characters
  (`_held`), `_c2s_resume`, `_c2s_leave`, `_s2c_reconnect_token`, token rotation, expiry,
  held characters excluded from `_free_sim` and counted in the own-character limit, held names
  reserved, `_remote_players()` filtered by `multiplayer.get_peers()` and ENet peer state.
- `scripts/net/net_protocol.gd` — `VERSION` 3 → 4 (new RPC methods change the RPC table).
- `main.gd` — `reconnect_grace` config (game default 120 s, injected tests 0), resume config,
  `reconnect()` (scene reload with in-memory config), window close = intentional leave.
- `scripts/ui/hud.gd` — "Znovu připojit" button after a disconnect when resuming is possible.
- New `tests/test_mp_reconnect.gd/.tscn` (72 checks).

## Verification
- `test_mp_reconnect` 72/72 (×2). After the ENet-state filter the
  "Unable to send packet … max channels: 0" error disappeared from stderr; three engine-level
  "multiplayer instance isn't currently active" errors without GDScript backtrace remain.
- Regression: test_multiplayer 67/67 (its two RPC errors are the intentional forged s2c RPC
  checks), test_character_net 97/97, test_h3_three_process_game 17/17, world_observer_late_owner
  17/17, world_enet_multiprocess 11/11, enet_process_bootstrap 7/7, net_protocol 34/34,
  live_character_edit 38/38, full_playable_slice 87/87, host_character_editor 10/10,
  character_edit_ownership 75/75, character_editor_ui 68/68, save_game 46/46; godot_check 60/60.
- Not run: `tests/diagnostics/h3_three_process_stderr_probe.gd` has a SHA gate on
  `net_session.gd` and was already intentionally stale (fail-closed) before this change.

## Gemini (models/gemini-3.5-flash)
1. *High:* "`s != null` is true for a `queue_free`d node; calling methods crashes the server —
   use `is_instance_valid`." **Rejected for this code path:** `world.find_sim()` returns only a
   node found by `sims_root.get_node_or_null()` that is also in `sims`; every despawn calls
   `unregister_sim()` before `queue_free()`, so a freed instance is never returned. No crash was
   observed in 72 checks that include despawn-on-expiry.
2. *High:* "`_remote_players()` allocates and uses reflection in a hot loop (DoS at 32+ players)."
   **Rejected as severity:** `MAX_CLIENTS = 8`, so at most 8 iterations per broadcast; the ENet
   constant is cached. Kept as a note if the client limit is ever raised.
3. A second request for a security-focused review of the token design was declined by Gemini
   ("cannot perform security analysis"). The token design therefore has **no independent
   external security review yet**; ChatGPT was asked in the AI room (#419).

## Own review notes / known limitations
- ENet is unencrypted (no DTLS): a token can be sniffed on a hostile path, like the rest of the
  session. Mitigated only by one-time use, rotation, hash-only storage and the grace window.
- Held characters live only in server memory (not persisted across a server restart — H4b).
- If the link drops after the resume request was sent but before the welcome, the client has
  discarded the token and joins as a new player (fail-safe, not fail-open).
- A held character keeps living under AI; nobody else can command it during the grace period.
