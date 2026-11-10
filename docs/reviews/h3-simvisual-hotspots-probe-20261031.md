# H3 SimVisual cold-path hotspots — 2026-10-31 (main-fallback-1793452460-35984)

Scope: test-only probe, no production multiplayer, character, UI, city, Blender, GitHub or AI-room changes. Not an H3 three-process acceptance test.

## Exact changed files
- NEW `tests/diagnostics/h3_simvisual_hotspots_probe.gd` SHA256 a3b376d6467db5a60ed80cbcf4480f5eaeaf32334b90cd86cd6cc29a925a8c7b
- NEW `tests/diagnostics/h3_simvisual_hotspots_probe.tscn` SHA256 94526cbb39d7b177b8c72a29512c60d99766cdfe866308ce9d03ff5b9b79267d
- Documentation: this review, `CHECKPOINT.md`, `DEVLOG.md` (append-only).
- Production `scripts/sim/sim_visual.gd` unchanged SHA256 2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3.

Method: assert exact production SHA and scoped unique source anchors; compile an instrumented in-memory copy of SimVisual and instantiate twice. Time each `HairRig.request_mesh` call, `GarmentBuilder.parts`, each C5 garment attachment and material construction, and full outfit stage. One fresh Godot headless process per run, three sequential independent runs. Monotonic wall-clock brackets; not CPU profiling. No private information printed.

| Phase | Cold run 1 ms | Cold run 2 ms | Cold run 3 ms | Warm typical |
|---|---:|---:|---:|---:|
| SimVisual total | 4824.486 | 4690.511 | 4680.002 | 9–16 ms |
| HairRig.request_mesh scalp | 1585.389 | 1568.520 | 1573.024 | ~0.01 ms |
| HairRig.request_mesh brows | 186.995 | 155.019 | 174.197 | ~0.006 ms |
| HairRig.request_mesh beard | 0.069 | 0.065 | 0.050 | ~0.003–0.005 ms |
| GarmentBuilder.parts | 1770.047 | 1667.468 | 1640.399 | ~0.06 ms |
| Full _apply_outfit | 1771.344 | 1668.710 | 1641.297 | ~1 ms |

All three cold garment calls returned 3 entries. Each C5 attachment <0.02ms and each material assignment <0.3ms; the garment cost is inside `GarmentBuilder.parts`, not attachment or materials. The scalp HairRig request and garment parts account for ~3.2–3.35s of ~4.7–4.8s cold visual initialization, with additional nonzero work elsewhere. `GarmentBuilder.parts` delegates to `ClothingWardrobe.active_parts` for the default empty design, and `HairRig.request_mesh` delegates to `mesh_for` when async is disabled or context empty; their internal subphases are not yet measured.

## Actual verification
- New headless Godot probe: three independent runs, all exit=0, timed_out=false, no parse/runtime errors; existing ObjectDB 20-leak warning observed.
- Static GDScript check: 60/60 PASS, zero errors.
- Existing real in-process ENet Apply/resync: 97/97 PASS; network editor ENet: 80/80 PASS (both exit=0, no timeout).
- Unchanged three-process H3 acceptance NOT rerun; latest documented result remains 8/17 PASS, 9 FAIL, exit=1. H3 is PARTIAL/FAILED. No UI changes; no render claim.

## Skeptical Gemini audit
Gemini reviewed planned instrumentation and actual source/results. Valid caveats: first-use caches and scheduling may dominate; monotonic ticks measure wall time, not CPU; warm pass after queue_free is not an independent cold start; diagnostic printing and in-memory script copy alter exact workload. Gemini speculated about JIT/GPU/shader/disk caching without isolating those causes, and described warm timings as 'submicrosecond' despite 0.06ms = 60 microseconds; these are not accepted as demonstrated facts. Its proposed isolated direct-call benchmark is a reasonable follow-up but does not alone establish the real three-process failure cause.

**NEXT SINGLE STEP:** create a test-only isolated cold-process subphase probe inside `HairRig.mesh_for/build_pack/mesh_from_pack` and `ClothingWardrobe.active_parts`, then use those measurements to decide whether any production optimization is justified. Preserve the unchanged 17-gate three-process acceptance before declaring H3 complete.
