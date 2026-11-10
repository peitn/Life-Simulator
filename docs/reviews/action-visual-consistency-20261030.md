# Action visuals: shower clothes, dirty dishes, reading book (30 October 2026)

## User-reported faults
- Characters showered **while still wearing their outfit**.
- NPCs complained about "dirty dishes on the counter" despite **no dirty dish geometry**.
- A read action displayed an **open book floating awkwardly at the right wrist**.

## Changes implemented
- `scripts/sim/sim_visual.gd`: `_update_shower_garments()` hides C5 top,
  bottom and shoe meshes and any legacy shirt/pants/shoes during the shower
  action. Visibility returns to its pre-shower values when the action finishes
  or changes. `apply_look()` reasserts the visual mask if the wardrobe rebuilds
  while showering. No canonical character clothing fields, identity, body shape,
  personality or replicated private state are modified. Feet show without shoes.
  This is **not** a bespoke undressing animation or a towel/curtain system.
- Reading book mesh is now attached through `ActionPropBookChest` to the chest
  bone, near the midpoint of two reading hands. Its page width was increased
  to physically reach both palms. The phone remains attached to the right hand.
  Controlled headless rig pose sample: left palm approx (0.187,1.248,0.395),
  right palm (-0.182,1.229,0.401), book (0,1.195,0.376).
  The new automated regression requires book center within 0.16m of the hand
  midpoint and centered on X. No full graphically rendered screenshot inspected.
- `scripts/world/world_builder.gd`: builds visual `DirtyDishes` child at the
  kitchen countertop (3 plates with leftovers, cup and 2 cutlery pieces).
  Initially hidden.
- `scripts/sim/household_dynamics.gd`: sets `_dirty_dishes_until` when
  a real completed cooking action lasted at least `DISHES_MIN_COOK=20`
  simulation minutes. Plates remain visible for `DISHES_VISIBLE_MINUTES=240`.
  The same event supplies the existing friction complaint trigger. Short
  aborted cooking does not produce plates.
- `main.gd`: on authoritative time advance, syncs `DirtyDishes.visible`
  with `HouseholdDynamics.has_dirty_dishes(clock.total_minutes)`.
  Does not change NPC simulation or dialogue selection.
- Updated outdated test display label in
  `tests/test_world_interaction_visual.gd` (it falsely stated that books
  should follow the right wrist).

## Validation
- New `tests/test_action_visual_consistency.tscn`: **16/16** assertions,
  exit0. Includes real skinned Godot mesh, shower/restored C5 outfit,
  preserved signature, real animated hand transforms and book location,
  real Main/world kitchen geometry, legit vs too-short cooking, expiry.
- Existing `test_world_interaction_visual.tscn`: **27/27**, exit0
  before its assertion text update (pure-label change).
- Existing `test_household_dynamics_slice.tscn`: **63/63**, exit0.
- Existing `test_voice.tscn`: **110/110**, exit0.
- Existing `test_full_playable_slice.tscn`: **87/87**, exit0.
- Godot syntax: **60/60 OK**, no errors.
- New production web export: https://peiti-godot-mcp.hf.space/play/lifesim/
  Export successful ~140 MB incl PCK 100,405,524 bytes. Restored previously
  curated Canvas/WebGL/mobile help HTML using fresh Godot export config and
  cache-busted index.js. HTTP GET HTML/PCK/WASM/JS returned 200, expected
  content signatures. No graphical browser/Android end-to-end playtest done.

## Remaining limitations
- Mesh visibility and approximate spatial alignment were tested by headless
  engine: **not** a human-reviewed rendered animation. Book grip/finger
  articulation and page turning still require a separate visual animation pass.
- Dirty dishes are currently a **temporary visual cue (4 in-game hours)**,
  not a full persistent item/inventory system and not a dedicated cleaning
  interaction. This limited visual state is not yet in SaveGame snapshots.
- Multiuser ENet clients do not receive dish visibility state independently:
  the authority updates it locally. Multiplayer cosmetic propagation is
  a later task and should not be claimed as complete.
- Web and desktop still differ in Piper/ENet and render quality as documented
  in `docs/reviews/web-export-parity-20261030.md`.
