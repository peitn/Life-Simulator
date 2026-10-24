# City implementation plan
Updated 2026-10-24. Work only in city-owned namespaces; use the shared atomic previews/gpt-development.lock before mutations. GitHub publication remains blocked; do not publish through another branch/tool. Do not change main CHECKPOINT or main scene.

## Standards
Meters, Godot Y-up, Blender Z-up with glTF export conversion; grid 0.5 m. Wall sample: width 2 m, height 2.8 m, core depth 0.2 m; pivot left endpoint at floor, width +X. Door opening 1 x 2.1 m. Decorative trim extends depth to 0.26 m. Store bounds separately from snap dimensions.
Original muted materials match existing simple furnishings. UV baseline 1 unit/meter; procedural/baked texture detail is subsequent work. Budget target under 3000 triangles per simple module; share materials and measure before optimizing. Current sample 1404 triangles / 13 meshes; merge surfaces/material instances before large-scale assembly if measurements require it.

## Ordered queue
M0 inventory and conventions, first verified Blender-to-Godot sample — completed for doorway.
M1 modular solid walls, corners, window openings, doors, floors, ceilings, foundations, stairs and roofs; tileable plaster/brick/concrete/wood/tile/roof materials. Doorway and solid wall with three-module snap demo implemented; solid regression37/37 and doorway31/31. Existing renders inspected and code audit documented. Blender library reverified. Compatible L corner implemented (492 triangles,3 meshes,36 Godot checks,3 inspected renders). Next compatible window opening; M1 overall incomplete.
M2 furniture and fixtures, compatible variants, interaction points. Reuse existing sofa/beds/fridge.
M3 lots, terrain, sidewalks, curbs, roads/intersections/crossings, fences/gates.
M4 grass, flowers, shrubs, trees; instancing.
M5 modular houses, apartment blocks, shops/public buildings, small demonstration district.
M6 navmesh, entrances, cutaway, lighting, measured runtime performance.
M7 catalogue, placement preview, snap/rotate, validation, delete/undo, save/load; shared runtime/UI integration belongs to main task via HANDOFF.md.
After these: street lamps, benches, bins, signs, stops, parks and stylistic variants.

## Acceptance
Keep generator, .blend, GLB, manifest and inspected multi-angle renders. Validate imported dimensions, pivots, normals, UVs and collisions. Do not call solid-color materials finished texture art. No unverified placeholder/completion claims.
