# M2 — four original furniture adapters verified
28 October 2026. Run city-m2-furniture-1793197261. This completes the first four original furniture adapters; the broader M2 furniture/fixture catalogue remains IN PROGRESS.

## Result
Reusable Godot scenes now exist at scenes/city/m2_sofa.tscn, m2_bed_single.tscn, m2_bed_double.tscn and m2_fridge.tscn. They reuse the original GLBs and AssetLibrary material enhancements. No replacement models, duplicate reservation service, main-world patch or GitHub publication was introduced.

The adapter extends scripts/world/smart_object.gd. Its users array and base reserve/release remain the occupancy authority. A small instance-ID-to-slot map keeps physical positions stable when an earlier occupant leaves. Invalid/freed actors are pruned, release removes action callbacks, and live object-kind changes are rejected so geometry cannot diverge from its layout.

Sofa: two seated actors keep separate slots, face the actual sofa front, and reuse a free slot without moving the remaining actor. sleep_sofa reserves the entire sofa, uses a centered lying origin and aligns the actor along its width. A seated occupant prevents a sleeper taking over; a sleeper prevents both a second sleeper and a seated arrival. This uses the existing action IDs and actual SimAgent command/walk/act/cancel/leave_world flow.

Single/double beds preserve the existing bed tag and one/two sleep slots; fridge preserves the fridge tag and front standing access for snack. Actor pose origins intentionally remain floor-level because SimVisual applies posture offsets. Separate surface markers are measured from real model triangles: sofa ~0.43534m and mattresses ~0.49004m.

All four scenes have conservative full-bounds StaticBody3D collision and use/pose markers. Approach sweeps were checked with a 1.6m capsule of radius .18m at translations and all quarter-turn yaw rotations. Navigation around furniture, collision-aware seated movement, user build-mode delete/undo, persistence of a custom furniture layout and client authority remain later M6/M7 integration; these scenes are not silently installed into the starter WorldBuilder.

## Actual validation
| Suite | Result |
| --- | --- |
| Geometry/layout/collision/transform/reservation checks | 141/141, exit0 |
| Actual Main + SimAgent command/act/cancel/sleep/leave-world | 49/49, exit0 |
| Lifecycle and 120 same-frame reservation/release interleavings per two-seat model | 489/489, exit0 |
| Existing model/animation/WorldBuilder regression | 155/155, exit0 |
| Existing playable creator/command/save/reload/cold-start regression | 54/54, exit0 |
| Whole-project syntax tool | 60/60 |

Total positive assertions excluding syntax: 888. Child runs completed without timeouts or script errors. The independent negative control substitutes the old users.find(sim) slot algorithm and fails exactly four physical-slot assertions (137/141, exit1 EXPECTED), proving that the stable-slot checks detect the old behavior. Full logs: docs/city/m2-final-tests-20261028.json.

The new source and tests were directly compiled by execution. Existing 18 ObjectDB audio shutdown warnings remain; no new RID/orphan leak was observed. Runtime tests are single-thread main-loop interleavings, not a claim of arbitrary thread-safe Node access or network concurrency certification.

## Asset measurements
| Asset | Triangles | Capacity | Observed source bounds (meters) |
| --- | ---: | ---: | --- |
| Sofa | 2896 | 2 seated / 1 whole-sofa sleeper | (-1.10,0,-.45) to (1.10,.825,.44) |
| Single bed | 2472 | 1 | (-.50,0,-1.05) to (.50,.895,1.05) |
| Double bed | 4200 | 2 | (-.87,0,-1.07) to (.87,1.00129,1.05) |
| Fridge | 868 | 1 | (-.34,0,-.35) to (.34,1.87,.356) |

The original double bed is an explicit existing-asset exception to the simple-module 3000-triangle target. Its geometry was reused unchanged as required, not represented as optimized; large-scene performance remains unmeasured. Source and generated scene hashes are in m2_furniture_manifest.json. Source GLBs and core SmartObject/SimAgent files remain unchanged.

## Real visual inspection
Three real 1120x720 Godot Compatibility/llvmpipe renders were generated and inspected: m2-v2-city-m2-furniture-1793197261-front.jpg, -rear.jpg, -top.jpg. All four original models are intact, green approach markers remain outside the collision footprint, and blue surface markers align with cushions/mattresses. Initial rear labels were mirrored and top labels edge-on; billboard labels and reduced text size were applied, and all three final views were inspected. These are asset diagnostics, not human-pose clipping certification or a frame-rate benchmark.

## Independent audit and dispositions
Two actual Gemini reviews completed. Initial allegations of an unguarded _slot lookup and an asynchronous target-clearing race were disproved by the existing validity guard and the synchronous SimAgent source, then retracted. Alleged freed-callback leaks were not reproduced: explicit emitter/receiver destruction, release/disconnect and post-destruction emission checks pass without new leaks. The fixed initial ray height was safe for these source models (maxY<1.87m); the builder was nevertheless improved to derive the ray origin from measured maxY+.25m. The closing review found no evidence-backed code blocker in this scoped adapter slice and did not certify all of M2 or the whole game. Gemini did not run tests or inspect the images.

## Godot backup and next work
A complete pre-change Godot backup succeeded: 119453KB to the project dataset and 9115KB library backup. The server snapshot method archives every project plus NPC state; only rebuildable .godot/.import folders and selected Elmer result caches are excluded. The server uses a fixed backup path and periodic super_squash_history (default every six backups); this run did not change retention or manually delete history. Final close requests the same complete current Godot backup after source, scenes, tests, manifests and checkpoints are written.

M1 remains complete. M2 remains in progress: next adapt the existing starter stove/cook interaction into a reusable city fixture, then other required kitchen/bathroom fixtures. Keep existing action/reservation APIs and coordinate main runtime/UI integration through HANDOFF rather than creating duplicate systems.
