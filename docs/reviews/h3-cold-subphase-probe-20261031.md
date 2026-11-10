# H3 cold initialization attribution — 31 October 2026, 14:12 UTC

Run: `main-fallback-1793455966-37626`. This is test-only instrumentation, not a multiplayer fix or H3 acceptance.

## Exact new files

- `tests/diagnostics/h3_cold_subphase_probe.gd` SHA-256 `a3b2945ddbb14171a4c3d95738d4ef9546277b88de61cfdd5b8a687831ccc693`
- `tests/diagnostics/h3_cold_subphase_probe.tscn` SHA-256 `0dc6e00f3325b26118a5923dd3e15fd23b42247ee59c1b9a9d641399c2e71afc`

No production source, networking/authority, UI, city-owned files, Blender, GitHub or AI Room changed. Probe verifies source SHA-256 before running and runs each mode in a **fresh Godot OS process**. Each `H3_SUBPHASE_RESULT` was `ok:true`, Godot exit=0, timed_out=False. All elapsed timings use `Time.get_ticks_usec()` (wall clock, not CPU time).

## Results (ms, two independent OS-process runs per mode)

| Operation | Run 1 | Run 2 |
|---|---:|---:|
| HairRig.source | 646.846 | 573.521 |
| HairRig.context after source | 91.617 | 80.080 |
| HairRig.build_pack(scalp, kratke), context already initialized | 1480.475 | 1511.202 |
| HairRig.mesh_from_pack (10,812 vertices) | 10.478 | 8.124 |
| HairRig.mesh_for first call after source/context (rebuilds pack) | 1560.770 | 1625.027 |
| HairRig.mesh_for cache hit | 0.014 | 0.010 |
| ClothingWardrobe.parts top/tricko (first kind) | 1285.815 | 1329.532 |
| ClothingWardrobe.parts bottom/dziny (first kind) | 297.156 | 323.686 |
| ClothingWardrobe.parts shoes/tenisky (first kind) | 101.391 | 101.689 |
| Wardrobe.active_parts after kind loads | 0.014 | 0.015 |
| GarmentBuilder.parts after kind loads | 0.078 | 0.058 |
| GarmentBuilder.parts cold, independent fresh process | 1833.577 | 1646.094 |
| GarmentBuilder.parts repeated warm | 0.063 | 0.091 |

The first scalp pack assembly dominates `mesh_from_pack` by ~140–185x; source+context also incur ~0.65–0.74 s of first-time work. This distinguishes procedural preparation from the final ArrayMesh creation. Cold wardrobe time is dominated by the first `top` kind (~1.3 s), with bottom and shoes adding ~0.4 s. Subsequent access to preloaded garment arrays is <0.1 ms. Do not add the `hair_build_pack` and `hair_mesh_for_first` times as if they were one real character initialization: the diagnostic intentionally invokes both separately. Similarly, `garment_cold` and category timings come from separate OS processes.

These results reproduce prior first-vs-warm gaps, but do **not** establish a causal link to the failing three-process network test. First-time resource import, allocator behavior, disk/OS cache and scheduler effects remain possible. SHA checks happen before timing and may warm file-system caches. Two cold samples per mode are useful localization, not a statistical performance benchmark.

## Verification

- Godot 4.7.2 `godot_check`: 60/60 PASS.
- New diagnostic: six independent headless Godot executions, each exit=0, timed_out=False, source SHA checks pass and nonempty meshes/garments validated.
- Existing real production ENet `tests/test_character_net.tscn`: 97/97 PASS, TEST OK; known 20 ObjectDB warnings.
- No rendered UI changes; no render claim.
- H3 three-process 17-check acceptance **not rerun**. Latest existing result: 8 PASS / 9 FAIL, exit=1. H3 remains PARTIAL/FAILED.

## Skeptical Gemini review

Gemini received the actual new GDScript and six-run timing results. Valid cautions: only two independent samples per mode, resource/cache and scheduler confounding, and source hashes make the test intentionally sensitive to code changes. Its claimed GDScript JIT cause is unverified (Godot GDScript is a bytecode VM, not evidence of JIT at these call sites); a `match` on fixed CLI strings is not an injection vulnerability; `FileAccess.get_sha256` occurs before timers and is appropriate for this test-only harness, although it may warm OS cache. The claim that `call_deferred` necessarily creates a race is not substantiated by the six successful runs. None of these critiques establishes a production root cause.

## Exact next one step

Instrument `HairRig.build_pack` in a separate test-only cold-process probe to distinguish `HairRig.geometry`/`HairBuilder.build` from `HairRig._arrays_from` (morph/skin binding); compare both with unchanged mesh output. Only then consider a narrowly scoped production performance change, followed by full three-process H3 acceptance. Preserve v3 lock, city/GitHub/AI-room restrictions.
