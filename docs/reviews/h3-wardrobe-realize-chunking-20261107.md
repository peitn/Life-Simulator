# H3 – frame-spread wardrobe realisation, fixture lambda lifetime, server shutdown sends (7 Nov 2026, evening)

Run: Claude scheduled `main-claude-1794079342-248630` (v3 MAIN lease held for all writes).

## Changes

1. `scripts/assets/clothing_wardrobe.gd` (production). After a background build, `_finish` no longer
   turns the whole garment kind into ArrayMeshes in one frame (the top kind is 118 meshes with ten
   blend shapes each). It stores a cursor in `_pending[kind]["realize"]`; `_realize_frame`, connected
   to `SceneTree.process_frame` only while work is queued, makes meshes until `realize_budget_usec`
   (4 ms) is spent, always at least one per frame, and disconnects itself when the queue is empty.
   The synchronous `_realize` runs the same cursor to completion, so the output is identical.
   - The kind stays *pending* (not *loaded*) until its last mesh exists; an owner that registers during
     realisation joins the same entry and is called back with the others; no second decode task.
   - A synchronous caller (`parts()`, `stats()`, editor preview) during realisation completes the
     remaining meshes immediately (`_complete_realizing`) instead of decoding the LSX again; owners
     are then notified with `call_deferred`, never re-entrantly inside the caller.
   - `reset_cache()` drops half-realised kinds (no publish, no callback); the driver stops by itself.
   - `load_stats[kind]` gains `realize_frames`, `realize_meshes`, `realize_max_mesh_ms`;
     `realize_max_frame_ms` records the longest realisation frame.
2. `scripts/net/net_session.gd` (production). `shutdown()` sets `_connected = false` **before**
   `multiplayer_peer.close()`. Closing a server host emits `peer_disconnected` for every peer and the
   handler's roster/chat/clock broadcasts used `rpc_id` into the already closed host
   (4× "Unable to send packet … max channels: 0" per three-process run). `_remote_players()` is empty
   while not connected; local player removal and despawn still run.
3. `tests/diagnostics/h3_three_process.FAILING.gd` (fixture only). Trace lambdas on SceneMultiplayer
   signals captured the World node strongly; the multiplayer object outlives the owner's freed world on
   rejoin, which printed "Lambda capture at index 1 was freed". They now capture a `WeakRef`;
   `_transport_snapshot(null)` reports `world_valid=false`. No acceptance assertion changed.
4. `tests/test_action_visual_consistency.gd`: waited one frame and expected authored garments, which
   no longer holds since `Main` uses the async game path (morning run). It now waits for
   `visual.wardrobe_waiting() == false` (15/16 → 17/17).

## Verification (real Godot 4.7.2 headless runs)

- `tests/test_wardrobe_async.tscn` **41/41** (13 new checks): top realised in 6 frames, 118 meshes,
  longest realisation frame 5.17 ms (budget 4 ms + one mesh ≤ 2.5 ms), longest main-thread gap during
  the whole background build 11–14 ms (was 22.7 ms in the morning, 1.2–1.5 s synchronous); byte-identical
  digest of every kind with a 2 ms budget; mid-realisation join, sync completion, reset.
- `tests/test_h3_three_process_game.tscn` **17/17 ×5** after the wardrobe change (three OS processes);
  the last three runs have a clean stderr apart from the known "20 ObjectDB instances leaked" warning.
- Regression PASS: clothing_authored 14, clothing_c5 16, subculture_wardrobe 14, character_preview 13,
  body_morphs 62, multiplayer 67 (the two ERROR lines are its intentional forged s2c RPC check),
  net_protocol 34, character_net 97, live_character_edit 38, enet_process_bootstrap 7,
  world_enet_multiprocess 11, world_observer_late_owner 17, character_editor_ui 68, full_playable_slice 87,
  host_character_editor 10, save_game 46, character 157, appearance_slider_ui 111,
  world_interaction_visual 27, hq_bedding_visual 14, eight_household_doors_audio 39,
  live_anatomy_overlay 76, mouse_input_real 20, web_touch_compact_controls 10, emotional_hud 11,
  player_commands 40, psyche_presentation 19, action_visual_consistency 17.
- Pre-existing, unrelated: test_assets 153/155 (character triangle budget 27 418 > 20 000; pelvis height
  when sitting), test_hair 59/60 (hair-card triangle budgets). test_head exceeded the tool's 120 s limit
  (HeadBuilder.build_data alone 118 s on this host) – not caused by this run, not a PASS.
- Not run as standalone (need arguments or a lease): test_h3_cold_process_reload, test_h3_rendered_parity.
- The historical diagnostics `h3_three_process_rpc_probe` / `h3_three_process_stderr_probe` gate on the
  old `net_session.gd`/`main.gd` SHA-256 and therefore fail closed; intentionally left unchanged.

## Independent review (Gemini, gemini-3.5-flash-lite default model; the flash model timed out with 524)

| Finding | Verdict |
| --- | --- |
| Godot `Mutex` is not reentrant → deadlock | Rejected: Godot's `Mutex` is recursive (documented; `_realize` → `_mat` already relocks it and every test passes). |
| `_realize_order` index shift / desync | Rejected: all mutations happen on the main thread under the mutex; the loop always re-reads index 0, no stored index. |
| `_connected=false` before close() could confuse cleanup that expects a live connection | Partly valid as a caution; the peer_disconnected handler only uses `_connected` through `_remote_players()`; removal/despawn are local. Kept. |
| WeakRef in fixture could hide post-rejoin signals | Rejected for acceptance: traces only; no gate reads them. |
| Deferred owner callback after a sync completion differs in timing | Intentional (avoids re-entrancy into the caller's apply); the caller already has the data. Documented. |

## Open H3 items

- Preview ↔ spawned parity under async placeholders (rendered), more hosts/seeds.
- The prewarm visual on a client still costs ~3.4–4.6 s main-thread time *before* `net.join()`
  (GLB model + details); acceptable for joining, but a loading screen or async model load is future work.
