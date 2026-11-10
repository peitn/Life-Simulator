# H3 cold HairRig geometry versus skin/morph transfer — 2026-10-31
Run: main-fallback-1793459347-39414. Scope: test-only. Main v3 lock acquired, running history verified, pre-edit remote project/library backup SUCCESS (405756/123493 KB). No production, city-owned, Blender, GitHub or AI-room edits.

## Changed files
NEW `tests/diagnostics/h3_hair_build_split_probe.gd` SHA256 `5f741d50d11b42b955461203625751619b5c52d390ec1dd0eb0413d39e4adc93`.
NEW `tests/diagnostics/h3_hair_build_split_probe.tscn` SHA256 `dcf11efcab004e69444f76ce6b4e58c7355a768cdc9210c7667518d576bf04a0`.
This report, CHECKPOINT.md and DEVLOG.md (append only).
Production HairRig SHA `9a424585912a8fbb6334f920de91846c15e7e98e850b9b30dfad17c7b90bcb31`, HairBuilder SHA `0b9a8276f1d20a8981192968608704d30b55800655b4f16b51271d7fe40b719b` verified in test.

## Real Godot measurements
Three separate headless Godot OS runs of the new scene, all exit=0, timed_out=false. All used scalp/kratke and verified *exact* equality of six pack fields (arrays, blend, names, flags, tris, verts) against production HairRig.build_pack: 10812 vertices, 12707 triangles, 21 morph keys. Wall-clock times in ms:
- source: 612.117 / 529.267 / 492.549
- context: 81.319 / 82.197 / 80.564
- geometry: 549.157 / 499.980 / 628.290
- _arrays_from(g,false) skin/morph binding: 1110.271 / 997.793 / 1021.864
- canonical build_pack with prewarmed source/context: 1477.965 / 1559.578 / 1598.074.
These are independent sequential measurements; do not add canonical build_pack to geometry + arrays_from as if distinct work. No CPU-time or H3 multiplayer causality proven. Static caches are warmed for context but the geometry and pack are rebuilt; process is fresh each run.

Godot static check: 60/60 PASS. Real production ENet test_character_net: 97/97 PASS, exit=0, timed_out=false (23.5 s). **Independent existing test_hair: 59/60 PASS, 1 FAIL, exit=1, no timeout (54.8s)**. Five hair styles violate its 26000-triangle budget: kratke_kudrny 26034, dlouhe_vlnite 26565, kudrnate 31114, afro 39525, dredy 27716. This failure is real in the current tree, but cannot establish when introduced; not caused by this test-only edit. Known ObjectDB 20 leaked-instance warnings; no new parse errors. H3 three-process 17-gate acceptance NOT rerun; last 8/17 PASS, 9 FAIL remains, H3 FAILED/PARTIAL.

## Skeptical Gemini audit
Plan and concrete results independently reviewed. Valid caveats: shared static cache, small sample, wall-clock jitter, missing visual validation and missing 3-process acceptance; existing hair budget failure cannot be hidden behind ENet 97/97. Independently verified exact equality and budget failures via Godot output. Rejected Gemini's unsupported claim that Godot 4.7.2 does not exist and its earlier suggestion to instantiate static HairRig twice; source is RefCounted with static methods/cache. No sensitive data sent.

## NEXT SINGLE STEP
Inspect why authoritative headless server constructs full SimVisual/HairRig on player spawn and design a narrowly gated server-only visual bypass that preserves node identity, replication, ownership and client rendering; do not modify production before verifying those invariants and run unchanged 17-gate three-process acceptance. Separately track the newly observed hair polygon-budget failure.
