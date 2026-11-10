# City implementation plan
Updated 29 October 2026. **M2 complete in city asset/interaction/authoring scope; M3 next.**
M0 and M1 are complete in the city asset scope. Evidence and exact limits:
`M1_ACCEPTANCE_20261028.md`. M2 acceptance: `M2_ACCEPTANCE_20261029.md`; editor: `FURNITURE_EDITOR.md`.

## Standards and ownership
Meters, Godot Y-up / Blender Z-up with glTF conversion; 0.5m placement grid.
Wall width2m, height2.8m, depth.2m; left-floor endpoint origin, width+X.
Floor/ceiling/foundation/flat-roof footprint2x2m, depth-Z.
Door opening1x2.1m. Bounds are separate from snap dimensions.
Retain generators, editable native source, GLB, manifests and inspected
multi-angle renders. Validate imported dimensions, pivots, normals, UVs and
collisions. Simple modules stay below3000triangles. Six actual repeating PBR
materials are available; do not describe solid colors as completed texture art.

Mutate only tools/blender/city,assets/city,scripts/city,scenes/city,docs/city.
Use the shared atomic protocol-v3 lease and check ownership before writes.
Preserve newer sources and main-task ownership. GitHub publication remains
restricted for this city task; no push, PR or alternate publication route.
Keep a complete current Godot backup. Dataset uploads work again; server history cleanup is configured. Retain earlier recovery evidence.

## Ordered queue
| Milestone | Scope | Status |
| --- | --- | --- |
| M0 | Inventory, conventions, first verified Blender-to-Godot doorway | Complete |
| M1 | Solid/corner/window/door walls, working hinged door, floors, ceilings, foundation, stairs/landings, pitched and flat roof variants; plaster/brick/concrete/wood/tile/roof maps | Complete in asset scope;1193positive checks, actual captures, native source |
| M2 | Furniture/fixtures, compatible variants and interaction points; reuse existing sofa,beds,fridge | Complete: 15 catalogue assets, all 9 existing furniture placements/action contracts, standalone catalogue + editor; 1719 assertions |
| M3 | Lots,terrain,sidewalks,curbs,roads/intersections/crossings,fences/gates | Pending |
| M4 | Grass,flowers,shrubs,trees and instancing | Pending |
| M5 | Modular houses,apartment blocks,shops/public buildings,demo district | Pending |
| M6 | Navmesh,entrances,cutaway,lighting,measured runtime performance | Pending |
| M7 | Catalogue,placement preview,snap/rotate,validation,delete/undo,save/load;main runtime/UI through HANDOFF | Pending |

After these: lamps,benches,bins,signs,stops,parks and further stylistic variants.

M2 extension: 3 additional closed-glass window walls,3 working hinged-door variants,12 new repeating PBR surfaces (18 mapped surfaces total). Custom furniture drafts are decorative; verified interaction points remain in the fixed catalogue. Toilets,sinks,baths,tables,chairs,counters are authored fixtures without invented new simulation actions.

NEXT SINGLE STEP: inventory existing lot/terrain/street geometry, then the first reusable M3 sidewalk/curb module with meter/grid convention,editable source,collision and seam validation. Do not restart M1 stair ablations or the already-complete stove slice.

M1 completion is not full game/world completion. Residual stair snap and
final locomotion behavior, main-game door interaction/persistence/network
authority, distant texture aliasing and final art polish retain their later
integration gates; none is silently represented as tested gameplay.
