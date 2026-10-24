# Doorway validator review — 2026-10-24
Run: city-1792817254-67782.
Gemini audit: COMPLETED. gemini_generate actually returned a review of the full old/new validate_doorway.gd code and existing Blender doorway.py contract. It had no direct project access. No credentials or user-private files were sent.

## Change
Removed scene-directory creation and ResourceSaver.save from the regression test. Previously merely running validation overwrote wall_doorway_2m.scn without ownership checks and then validated its own replacement. Test now checks existing saved scene independently, including unique collision boxes, root transform, enabled status, layers/masks and actual physics queries after removing the temporary GLB instance.
No Blender source, mesh, texture, .blend, GLB or scene changed. No new render was needed or performed for this nonvisual test repair.

## Gemini findings and disposition
- Claimed high-severity global/local mismatch and incorrect Z=-0.1 bounds. Rejected as a defect in this origin-placement asset test: AABB.position is the minimum, not the center; center z=0 and thickness .2 gives min z=-.1. Added explicit identity root assertion to make contract clear. Real stored scene passes; in-memory x=10 corruption fails 8 checks with exit 1, as intended.
- Claimed tree insertion happens after shape traversal. Rejected by source inspection: root.add_child(reloaded) is immediately after instantiate, before traversal, and two physics frames elapse before querying. Real headless test succeeds.
- Claimed missing resource silently bypasses testing, while acknowledging failure exit. Rejected as false-success issue: null resource injection reports failure and exits 1 (14 passed, 1 failed), no timeout.
- Collision-layer coverage gap accepted: now verify layer 1 / mask 1 and enabled shapes. In-memory disabling of saved collisions produces six failures including solid-wall/lintel ray checks, exit 1.
- UV quality/material assignment gaps accepted as remaining limitations. Existing test verifies UV count and finite unit normals, not texture stretching, material sharing, multi-module seams or gameplay performance. No new material quality claim.

## Executed verification
- Unmodified stored scene: 31 passed / 0 failed, exit 0, no timeout.
- Fault injection, disabled saved collisions: 25 passed / 6 failed, expected exit 1.
- Fault injection, saved root shifted 10m: 23 passed / 8 failed, expected exit 1.
- Null PackedScene injection: 14 passed / 1 failed, expected exit 1.
All fault injections only changed instantiated objects or ephemeral script text, never persisted scenes.
Scene SHA-256 before and after normal test: fdd4ffe7378c2d49be0f30ee623c6b35541a70468d6f2eb3934548faa80cab01.
stderr inspected: existing 18 ObjectDB shutdown warning on normal and geometry-fault runs; no parse errors or timeouts. Null-resource injection completed without warning.
Normal import+in-memory pack: 59.689ms, a single cold measurement, not FPS benchmark.
