# M2 in progress — furniture and fixtures
Updated 28 October 2026. The original sofa, single bed, double bed and fridge are now adapted into reusable city scenes. Full evidence: M2_FURNITURE_SLICE_20261028.md.

Completed: measured geometry/pivots, conservative collision, transformed use/pose points, actual triangle-sampled surface markers, inherited SmartObject reservation authority with stable physical slots, real SimAgent action/cancel/leave-world tests, and inspected front/rear/top renders. Sofa sleep reserves the entire sofa and is separate from two-seat relaxation.

Scenes:
- scenes/city/m2_sofa.tscn
- scenes/city/m2_bed_single.tscn
- scenes/city/m2_bed_double.tscn
- scenes/city/m2_fridge.tscn

Original source hashes remain unchanged and are recorded in m2_furniture_manifest.json. Assets are reused rather than regenerated. The old 4200-triangle double bed is an explicit measured reuse exception to the simple-module target, not an optimization claim.

NEXT SINGLE IMPLEMENTATION: inspect the starter stove geometry and existing cook action in WorldBuilder/ActionLibrary, then create a reusable city-owned stove fixture with measured bounds, front access, collision and occupied-use rejection. Follow with other required kitchen and bathroom fixtures. Do not mark all of M2 complete after this four-asset slice.

Use the existing users/reserve/release and production action APIs; no duplicate reservation/action service. Main WorldBuilder replacement, navmesh, custom-lot saving, client replication and build UI remain coordinated later integration gates.

Backup status: complete current Godot project + NPC snapshot and asset-library backup are working again. Keep a complete final snapshot after each verified change; server history cleanup is already configured. Preserve the shared v3 lease, city namespaces, checks, independent review and real captures. M1 remains complete; M3–M7 are pending.
