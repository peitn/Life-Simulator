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

## Current M1 continuation — 2026-10-25
Window, floor and ceiling modules now have persistent Blender kits and Godot scenes. Ceiling55/55 plus floor51/51 verified in city-1792909801-152206. Next: compatible2m pitched roof module with eave/ridge sockets. Remaining M1 includes functional doors, stairs, foundations, roof variants and genuine texture maps.

## Current continuation after saved roof demo
Roof source/kit/physics and saved open assembly now verified, including two actual Godot renders and saved55/55 checks. Next: compatible triangular gable infill module; do not regenerate existing roof.


## city-1793018567-220376 — first M1 straight staircase prototype
Created original staircase_straight_3m: 15 risers of .2m, .3m tread, 1m width, 3m rise, 4.5m run. Pivot lower-left floor; ascend -Z; sockets Bottom(0,0,0), Top(0,3,-4.5). Single manifold solid64vertices34polygons124triangles, flat outward normals, planar meter UV, original warm stone PBR solid color (no texture maps).
NEW files: tools/blender/city/staircase.py, assets/city/staircase_straight_3m.glb, scenes/city/staircase_straight_3m.scn, scripts/city/build_staircase.gd, scripts/city/validate_staircase.gd, docs/city/staircase_manifest.json, staircase_front.jpg/side.jpg/rear.jpg, review-staircase-20261026.md. Blender persistent lifesim-city-staircase-generator and lifesim-city-staircase-prototype contain source/editable .blend/GLB/geometry metadata/3renders. All6 kit hashes match originals; editable source reopened64verts34faces/manifold/volume7.2m3. All three actual320px CyclesCPU views inspected; no gross surface/normal gap, untextured block stair. No main-game changes.
Godot actual GLTF import+saved scene successful, 15 adjacent full-height box slices on layer/mask1. Final stair93/93 exit0 (3.306ms validation, NOT FPS); disabled Step07 negative90pass3fail exit1 expected; existing floor51/51 exit0. Two existing floor tiles instantiated only in memory at (0,0,2) and (0,3,-4.5) verify landing socket/height contacts. No timeout. Existing18ObjectDB warning; Blender bundled addon SyntaxWarnings. First binary transfer read stores before fetch completed, yielding invalidbase64 and empty GLB; corrected from completed bytes and verifiedSHA before any import. Initial new overlap assertion failed on4.77e-7m float seam: diagnosed, adjusted to10micron linear tolerance; before-change source backup retained in docs/city/stair-validator-city-1793018567-220376-before-tolerance.txt.
Gemini two actual skeptical code audits. False overlapping-collider/disabled-test/UV/bounds allegations disproved using actual box bounds and tests; followup acknowledged corrections. Lower floor aligns its rear corner, intentionally offset from tile origin. Suggested lateral edge rays remain coverage gap; actual disabled flag was executed. Details in review. No audit execution claimed for Gemini.
Pre-edit backup115847KB and intermediate115856KB succeeded; final backup/release follow. Ownership/history checked and heartbeats renewed. No GitHub commit/push/PR, AIroom messages or global checkpoint changes.
NEXT SINGLE STEP: saved city-only staircase/landing demo with character-size clearance and traversal verification. No handrail, ceiling opening, navmesh, gameplay FPS or integration approval; M1 remains incomplete.
