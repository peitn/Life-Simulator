# H3 guarded three-process A/B — 2026-11-01 (test-only, NOT production)

Run: `main-fallback-1793495596-69609`. All modifications are in `tests/diagnostics/`; no production, city, Blender, GitHub, or AI-room edits. Initial remote backup succeeded (project 406347 KB; library 123493 KB).

## Exact changes
- NEW `h3_guarded_script_builder.gd`: extracts the already-tested, source-hash-guarded in-memory SimVisual/SimPuppet patch from `h3_puppet_guarded_probe.gd`; refuses source hash drift or missing patch anchors. Does not write production files.
- NEW `h3_three_process_guarded.gd` and `.tscn`: inherit original `h3_three_process.FAILING.gd` unchanged, including all 17 gates. Override only fixture world spawn wiring and child scene path. On clients, `MultiplayerSpawner.spawn_function` delegates to the original callable, then substitutes guarded scripts **before** the node is added to the scene tree, preserving original `MultiplayerSynchronizer` child. Re-runs `setup_from_data` on public spawn data. Server unchanged. Trace records injection count, not private payload.
- NEW `h3_guarded_runner.py`: bounded runner identical to `h3_bounded_runner.py` except it launches guarded test scene; checks main lease and original fixture SHA, captures exit/timeout/stdout/stderr, tracks child PIDs by starttime and cleans verified descendants only. Runner's `ab_mode=cold` refers to original ENet timeout mode; guarded variant is selected by scene path.

## Measured results, same current project
| Variant | Original 17 assertions | Fixture exit | Elapsed | Runner timeout | Child processes | Leftovers |
| --- | --- | --- | --- | --- | --- | --- |
| Original unmodified cold fixture | **8/17** | 1 | 69.23 s | no | 3 | 0 |
| Guarded in-memory variant #1 | **17/17** | 0 | 39.78 s | no | 3 | 0 |
| Guarded in-memory variant #2 | **17/17** | 0 | 52.12 s | no | 3 | 0 |

Both guarded logs include `guarded_spawn_hook_installed` and `guarded_puppet_injected` from owner and observer, confirming that the guarded code path actually ran. Original fixture SHA `18dfb3802cd03a1c2ae8efdea5f3d4931828591d4b3231230e299657f32c21fe` was checked by both runners. Raw bounded results are in transient `/tmp/lifesim_h3_{guarded,guarded_repeat,cold}_1793495596_69609.json`, **not** durable project artifacts. All 17 assertions were inherited without modification, but the test-only implementation is not a production fix.

Independent production `test_character_net.tscn` **97/97 PASS** (exit0, no timeout); Godot syntax checker **60/60 OK**; in-memory script builder loaded and both scripts instantiated successfully. No render change in production; test is headless.

**Known stderr limitations:** Guarded runs emit `ENetPacketPeer: Unable to send packet ... max channels: 0` during teardown and the pre-existing `20 ObjectDB instances leaked` warning; baseline emits inactive multiplayer peer errors and the same ObjectDB warning. These are genuine unresolved errors, NOT clean-stderr passes. The guarded A/B has only two successful repetitions and does not directly cover forced despawn mid-build in the three-process fixture; the isolated lifecycle test does cover cancellation. Do not extrapolate to all timing conditions or private data invariants outside the existing 17 gates.

## Skeptical Gemini audit
Gemini reviewed design and A/B results. Valid: two successes do not prove production safety; teardown errors and cancellation races require follow-up; server authority and privacy need continued regression coverage. Independently rejected unsupported claims that closure context loss, async cancellation crashes, or future production degradation were **proven** by this evidence. Likewise, demanding zero ObjectDB warnings as a new acceptance gate would incorrectly conflate the existing baseline warning with this experiment. No private user data sent.

**Exact next single step:** add a forced client despawn-while-building test to the **guarded three-process fixture**, preserving the original 17 assertions, and verify no post-cancellation visual mutations, stale private state or orphan processes. Do not modify production yet.
