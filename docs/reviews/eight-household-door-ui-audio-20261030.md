# Eight-young-adult household, hinged doors and audio/UI controls — 30 October 2026

## User request
Real physical opening doors instead of holes, review functional icons/buttons,
an extreme 8-person psychiatric stress-test household ages 18–27, enough beds
and additional rooms, a visible sound on/off toggle, and web deployment.

## Implementation
- Source profile data: `data/households/extreme_young_adults8.json`, 8 separate
  fictional CharacterData profiles derived from the already-existing 8-person
  simulation fixture. Ages: 18, 19, 20, 21, 23, 24, 26, 27. Distinct PRIVATE
  dispositions include elevated rejection reactivity, anxiety/depression burdens,
  sensory and social-threat sensitivity, impulsivity, poor regulation and
  unusually high resilience/support in different characters. No diagnoses are
  inferred from body/appearance or identity, and no self-harm actions added.
  All 8 profiles validated with CharacterValidator and schema v20.
- `main.gd`: enables 8-person challenge by default on graphical desktop/Web
  launches. Explicit headless test fixtures retain 3 residents unless opt-in
  `net_config.eight_member_household = true`. Independent save folder
  `user://saves_extreme8` avoids clobbering older 3-person autosaves. Initial
  stress, depression burden and support differ among residents. The existing
  private-to-public CharacterData validation/spawn pipeline is preserved.
- `scripts/world/world_builder.gd`: adds four bedrooms and an attached corridor,
  five new single beds, lamps and room labels; existing double bed (2 places) +
  single bed (1 place) + 5 single beds = **exactly 8 reservable sleeping slots**.
  These new rooms and beds are enabled together with the 8-resident scenario.
- Physical doors: reuse actual `scenes/city/door_hinged_1m.tscn` and its
  `scripts/city/m1_door.gd` motor, solid collidable animated leaf, frames,
  hinge and sweep collision checks. Six units: front entry, bathroom, four
  bedrooms. `scripts/world/auto_door.gd` automatically requests opening as
  an NPC approaches (~1.9m) and closing when the area clears (~2.65m).
  Verified actual 0→90°→0° rotation with moving SimAgent. This is LOCAL
  behavior; full networking/interactable handle/manual player click is not yet
  independently validated. Other decorative cutaway walls do not yet
  uniformly have physics collision; do not present this as a complete
  navigation/architectural simulation.
- Master sound: `scripts/core/game_settings.gd` now persists bool
  `audio_enabled` (default ON) and applies it to Godot Master audio bus.
  `scripts/ui/hud.gd` has `SoundToggle` showing `♪ Zvuk: ZAP/VYP` and
  keeping in sync with GameSettings.changed. `scripts/ui/settings_menu.gd`
  has a separate toggle for full game sound. Verified real viewport-dispatched
  mouse click on the button (not merely invoking callbacks) mutes the bus.
- UI button audit: 27 currently-instantiated HUD/settings BaseButton controls
  each have connected signals and no empty-text+missing-icon items.
  ItemList uses item_activated/item_clicked, PopupMenu uses id_pressed,
  and CheckBox/OptionButton use toggled/item_selected. Other screens also
  have existing automated acceptance tests; this is not exhaustive real-browser
  certification of every control in every in-game state.

## Verified tests
- `tests/test_eight_household_doors_audio.tscn`: 39/39 passed incl. schema
  ages, private psychic dispositions, room labels, exact bed capacity, leaf
  collision, actual door open/close, 27 controls, bus mute/restore/UI sync.
- `tests/test_full_playable_slice.tscn`: 87/87 passed.
- `tests/test_world_interaction_visual.tscn`: 27/27 passed.
- `tests/test_household_dynamics_slice.tscn`: 63/63 passed.
- `tests/test_voice.tscn`: 110/110 passed.
- `tests/test_mouse_input_real.tscn`: 20/20 passed.
- `tests/test_web_input_responsive.tscn`: 22/22 passed.
- `tests/test_character_editor_ui.tscn`: 68/68 passed.
- `tests/test_emotional_hud.tscn`: 11/11 passed.
- Godot scripts check: 60/60 OK.
- Additional real viewport mouse click on SoundToggle: after a real
  InputEventMouseButton pair, Master muted and label showed VYP.
- Fresh production web export: https://peiti-godot-mcp.hf.space/play/lifesim/
  `index.pck` 100,430,816 bytes SHA256
  `d28cbb148ce47ef9a4e98e8cded1222d4b983b7d16a883a3ce511dbf19c297d3`.
  Export included household JSON, door scene, auto_door.gd, HUD and settings.
  After exporter overwrote index, restored previously approved responsive Czech
  Canvas/WebGL warning HTML and new file-size config; `index.js` URL is
  versioned `eight8doors20261030`. HTML/JS/PCK/WASM HTTP200 verified.

## Limits
Not tested inside a real graphical WebGL browser on the user's device. The
web export remains without Piper Python/ONNX voice inference, ENet multiplayer,
some native-only high-resolution assets. Some buttons inside less frequently
opened editors and external dialogs were not clicked end-to-end. The walls
are largely visual cutaway geometry; physical collidable door leaves are real.
Eight heavily loaded characters can stress browser performance, which should
be measured interactively. No claim that all postures/animations or AI
navigation are free of clipping in the expanded house.
