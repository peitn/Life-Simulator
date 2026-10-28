# M1 completed: modular building asset kit

Accepted 28 October 2026. Run `city-m1-complete-1793194638`.
The next ordered city milestone is **M2: furniture and fixtures**.

## Delivered scope

The kit contains compatible solid walls, a corner, window/open-doorway modules,
a functional hinged door, floors, ceilings, a foundation, straight stairs with
landings, a pitched roof with gable infill, and a flat roof alternative.
Six original repeating PBR materials cover plaster, brick, concrete, wood, tile
and roof surfaces. Each has an actual color, tangent normal and roughness map.
The maps have matching edge texels; generated mipmaps improve minification.
This is a functional modular asset kit, not a finished inhabited district.

New original assets are reproducible from `tools/blender/city/m1_finish.py`.
`assets/city/m1_finishing_kit.blend` was reopened in Blender 4.3.2: three named
collections contain 1/1/5 manifold, positive-volume UV meshes, 12/12/60 triangles,
and 18 packed texture images. Their exported GLBs were actually imported and
checked in Godot. Existing modules and their original generators are reused.

The hinged leaf has a real moving collider and two interaction markers.
Opening and closing stop before an occupant or a static swing obstruction;
movement resumes after clearance. Conservative whole-box angular queries
include world layer 1 and actor layer 2. The fitted frame alone is excluded.
Only the isolated showcase binds the E key. Main-game input, persistence and
multiplayer authority remain under their existing later integration gates.

The restored stair correction derives the prospective capsule center from
whole-shape collision travel and checks actual-height forward clearance.
Center ascent downward correction is 4.4611 cm, versus the earlier 6.4299 cm.
Two successive trips at each offset retain the <=18-lift and >80%-grounded
gates. Residual corrections and 20cm upward steps are not certified smooth
locomotion; this is an isolated asset traversal validation.

## Final executed acceptance

All positive cases below exited 0, with no timeout or script errors.
`validate_m1_suite.gd` orchestrates the 22 executable suites and the static
manifest audit, verifies completion markers and stderr, and runs negative
controls. Its own orchestration result is **27/27**. The positive checks sum
to **1193/1193**, not including the orchestration checks a second time.

| Suite | Passed |
| --- | ---: |
| Doorway | 31 |
| Solid wall | 37 |
| Corner source | 37 |
| Corner wall | 36 |
| Window wall | 169 |
| Floor | 51 |
| Ceiling | 55 |
| Pitched roof | 51 |
| Roof assembly | 54 |
| Gable infill | 16 |
| Gable envelope | 28 |
| Gable collision | 35 |
| Gable assembly | 92 |
| Gable metadata (static audit) | 16 |
| Stair geometry | 93 |
| Saved stair/landing assembly | 41 |
| Scripted capsule traversal | 145 |
| Lateral stair offsets | 27 |
| Physics stair walk | 11 |
| Consecutive stair roundtrips | 36 |
| Low/clear ceiling matrix | 42 |
| New foundations, roof, door and PBR maps | 83 |
| Saved showcase and actual E input events | 7 |
| **Total** | **1193** |

Whole-project syntax tool: 60/60. New scripts also compile through their actual
execution. Known 18 ObjectDB audio shutdown warnings remain; the newly found
orphan-frame/RID leak was fixed and is absent from final runs.

Negative controls: disabling the leaf collider fails closed-door passage;
placing a wall prevents reaching the stair top; corrupt visual metadata and
a wrong gable run ID are rejected. These deliberately failing child tests
are expected and checked by the passing orchestration suite.

Three actual 1120x720 Godot Compatibility/llvmpipe captures were inspected:
`previews/m1-front.jpg`, `previews/m1-rear.jpg`, `previews/m1-door-open.jpg`.
The first capture exposed an overlapping corner arm and a missing ceiling
tile beneath the flat roof. Both were fixed; new point queries verify one
corner collider and a filled wall-to-roof seam. The accepted captures show
the corrected assembly, mapped surfaces and an open door. This is simple
game art; distant stair texture aliasing and old floor UV triangulation remain
visual polish work, not a claim of final release-quality art or performance.

Two actual Gemini audits found no concrete blocker to the scoped M1 kit.
The first review's stronger claims of general production readiness and zero
visual artifacts were not accepted; the closing review explicitly restricted
the finding to M1 and confirmed M2 as the next step. Gemini did not execute
tests or perform the image inspection.

## Corrections made during implementation

- Typed a material path explicitly after a GDScript inference error.
- Corrected the fixture's capsule-node name and waited for physics after
  teleporting the test actor before retrying a blocked close.
- Cleared the reused frame's `scene_file_path` before repacking ownership;
  otherwise inherited-scene overrides left a real orphan frame at shutdown.
- Called the RefCounted gable validator through its static `audit()` method;
  its initial direct SceneTree launch was a runner error, not a passing test.
- Replaced the visually duplicated corner arm and added the missing ceiling.
- Restored the previous tested stair improvement after it disappeared from
  the server. No thresholds were relaxed to convert failures into passes.

## Preservation and transition

The service twice restored an older server snapshot during this work. Its
full remote backup is blocked by private-storage quota. The source, native
Blender kit, maps and accepted captures were retained outside that service;
the final recovery package supplies a reproducible city-only overlay.
Do not describe an ephemeral server copy as a certified remote backup.

Work is limited to `tools/blender/city`, `assets/city`, `scripts/city`,
`scenes/city` and `docs/city`. The shared v3 lease guards writes; an expired
restored lease was recovered only through that coordinator. No GitHub push,
main-game edits, AI-room messages or hosting publication were performed.

M2 has started with a hash-verified inventory of existing sofa, single/double
bed and fridge models; see `M2_START.md`. Next implementation: define and
validate compatible sofa placement and seat interaction points while reusing
the existing simulator's object/reservation behavior. M1 is closed; M2 is not
being marked complete. Navmesh/cutaway/runtime performance remain M6 and
placement UI/undo/save integration remain M7.
