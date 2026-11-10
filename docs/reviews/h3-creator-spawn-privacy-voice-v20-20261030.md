# H3 creator-to-household privacy and voice-v20 regression — 2026-10-30

Run: `main-fallback-1793354885-161205`. Scope: **test-only**, no production, schema, city, Blender, GitHub or AI Room edits.

## Source and behavior
Changed `tests/test_full_playable_slice.gd` from SHA256 `7bc05b4285db71f23b09b0fd3985999651c918a0c4639f8065d620bb5da58efa` to `f0e0890b7d74488beb5c58c884414bb38b8174910eebb65ccb5273191450bfaf`.
The existing visible HUD creator → canonical offline household spawn → save/manual reload → cold-start autosave integration now includes independent private romantic attraction `identity.attracted_to=["zeny"]`, private `story.hometown="HiddenTown"`, and public schema-v20 `voice.resonance=-0.47`. It asserts private fields survive authority/save/restart but are absent from public `SimAgent.look`, that public resonance matches preview and survives restart, and that the actual spawned look exactly equals `CharacterData.public_snapshot()` regenerated from canonical stored data. Six additional checks; the prior integration already tested grammar vs identity, body/hand skeletons, continuous personality, psyche and multi-resident isolation.

## Actual verification
- Before edit `test_full_playable_slice.tscn`: 81/81, exit 0, 13.3 s, no timeout.
- After edit: 87/87, exit 0, 13.3 s, no timeout; repeated independently: 87/87, exit 0, no timeout.
- `test_save_game.tscn`: 46/46, exit 0, 11.0 s, no timeout.
- Actual ENet `tests/test_network_editor_live_enet.gd` executed with `OS.get_executable_path()`: 80/80, child exit 0, wrapper exit 0, no timeout; covers spectator privacy, owner Apply/Cancel/Undo, reconnect, reassignment, but uses its own network fixture rather than the HUD creator's new spawned character.
- Static Godot check: 60/60 scripts clean.
- First attempted ENet shell invocation used nonexistent `godot` executable in PATH (child exit 127); corrected to actual `/opt/godot/godot` and reran successfully. Do not count the first attempt as pass.
- Known Godot ObjectDB exit warnings: 20–22 instances in the tested runs. No new UI layout/production visual code, so no new render required.

## Skeptical Gemini review and independent verification
Connected Gemini reviewed exact six-assertion diff and observed 87/87. It correctly highlighted that this offline test does NOT prove real network creator-to-remote-peer transport privacy; separately ran existing real ENet 80/80 but it does not bridge the two fixtures. It also speculated that literal schema enum `"zeny"` could be localized and that `is_equal_approx` masks out-of-range resonance. Independently checked actual schema: `"zeny"` is the canonical `ATTRACTION` ID, and `voice.resonance` is explicitly bounded [-1,1]; neither speculation is a demonstrated defect. Gemini's proposed direct public projection privacy assertion is already implied by `authoritative_cd.public_snapshot()==selected.look` plus the explicit public `selected.look` exclusion checks. Resource reference is RefCounted; ObjectDB warnings predate this test and vary 20–22. Audit complete, no verified blocking issue in this test change.

## Limitations / next single step
This remains a local offline creator-spawn test, NOT an end-to-end remote creator-to-ENet spawn or browser privacy certification. H3 is partial.
**NEXT ONE STEP:** connect a real creator-produced canonical character to a three-peer ENet spawn fixture and assert owner-only private identity/psyche/story, public-only spectator appearance and voice resonance across reconnect; preserve server authority. Keep this narrowly scoped as an integration test before altering production code.
