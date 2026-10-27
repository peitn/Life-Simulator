# Offline first playable loop — 2026-10-26

Main run: `main-playable-1793030869-228281`. Live Godot project `lifesim`, GitHub remains READ-ONLY under the explicit publication block. Main lease v3 owned; pre-edit remote Godot+Blender library backups succeeded.

## Implemented
- `scripts/ui/character_creator_panel.gd`: genuine offline character draft with isolated visual preview, first/last name, 18+ age, independently selected gender identity and Czech grammatical gender, height, hair, wardrobe/subcultures (including cat hoodie), legacy starting trait, independent personality/psyche sliders, Cancel/Undo/Redo/Apply. The source remains untouched until confirmed.
- `main.gd:create_offline_character`: offline authoritative commit, strict v8 validation, 18+ gate and content settings, regenerated server-side 128-bit UID, unique node name, duplicate display-name guard, capacity limit and selectable spawned player. Public look matches the preview; private mind/UID are never in public look. No multiplayer RPC or network creator access added.
- `scripts/ui/hud.gd`: visible “Vytvořit vlastní postavu” (Create your own character) entry plus scrollable needs/commands panel for portrait/narrow windows.
- New `tests/test_full_playable_slice.gd/.tscn`: real HUD → Cancel → reopen → reject invalid age/name/network → customize → Undo/Redo → Spawn → select → player TV action → disk save/load exact continuation → brand-new Main instance autoload of the custom character and all state.
- `README.md`: accurate local offline starter loop and limitations.

## Executed evidence
- NEW full playable slice after UI scrolling: **45/45 passed**, exit 0, timeout false (headless); portrait 390×720 scrollbar scroll-into-action verified through runtime Control layout.
- Existing offline editor **55/55**, player commands **40/40**, save-game **46/46**, save-continuation **12/12**, household dynamics slice **63/63**, emotions **45/45**, all independently passed.
- Multiplayer general test: first run **66/67 (one failure)**, repeat **67/67 (pass)**. Repeated run emitted deliberate forbidden RPC errors during adversarial anti-cheat attempts. Treat first failure as intermittent and NOT established fixed.
- Godot bundled check **60/60**; new scripts loaded by the 45/45 production test. Existing 18 ObjectDB shutdown warning persists. A web debug export was built (108 MB), but browser/Android GUI interaction and frame performance are NOT yet independently certified.
- During development the initial creator Apply correctly rejected missing required legacy personality trait; the starter trait picker fixed this, rerun passed. A diagnostic test erroneously accessed a freed UI node and hung twice until repaired; final test is finite and exits 0.

## Boundaries and remaining work
- Starter flow ADDS a new adult to the already furnished initial household, not a blank-household setup/new-lot builder; H3 complete gate and all H7 release gates are NOT met.
- Staged network read/editor remains default OFF; network Apply/canonical readback, MP creator, server save/load, full GUI/pixel QA, sleeve bone-weight correction and broader performance soak remain pending.
- City-owned files and Blender assets untouched. No GitHub commit/push, AI-room message or publication of source.
- Next independently bounded step: actual graphical render and mouse/keyboard browser smoke of the exported creator+HUD and preexisting sleeve defect; then address identified failures without weakening checks. Keep the first offline loop regression in release gate.
