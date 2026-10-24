# City handoff
Instantiate res://scenes/city/wall_doorway_2m.scn (PackedScene). Root placement origin: left wall endpoint, floor level; width +X, up +Y, depth Z. Snap width 2 m on 0.5 m grid; height 2.8 m. Core thickness .2 m, trim .26 m total.
Includes static physics layer 1 wall collision (three boxes); clear door 1 x 2.1 m. Cosmetic trim is excluded from collision. Navigation is NOT baked and no functional door/interaction exists.
No main scene/UI changes made. Catalogue/build-mode wiring is future integration, after core editor milestones. Manifest under docs/city/manifest.json. Main task must retain the shared project lock and current permission checks.

Validation: run `godot --headless --path <project> --script res://scripts/city/validate_doorway.gd`. This test is now read-only and must not be used to regenerate scenes. It checks the existing saved scene separately from the imported GLB; 31 checks. See review-validator-20261024.md for audit and negative tests.

## Solid wall and snap demo — 2026-10-24
Standalone res://scenes/city/wall_solid_2m.scn, 2m wide x2.8m high, core depth.2m, visual skirting depth.248m; left-floor pivot, same axes/grid as doorway. One static layer1 core collider; cosmetic trim intentionally excluded. Demo res://scenes/city/wall_snap_demo.scn contains solid/doorway/solid at x0/2/4, five colliders and two shared materials. This demo has no camera/controller/navmesh and is not main-game integration.
Read-only validate_solid_wall.gd now37checks including separately saved standalone; doorway31checks. Both passed. Four existing Blender views inspected; no new Godot visual render. Gemini audit/dispositions: review-solid-wall-20261024.md. Manifest: solid_wall_manifest.json. Blender library current verification pending Space503. Next corner module, no UI wiring requested yet.

Builder safety update: required doorway resource and Node3D root preflighted before first save. Run scripts/city/test_builder_preflight.gd with -- <owned city run_id>; fixtures stay in unique scripts/city/test-runs/<run_id>-preflight-v2/. Final26 checks; no authored scene changes. Two-output crash/IO transaction still not guaranteed. Blender503 still blocks corner production. See review-builder-preflight-20261024.md.

Availability city-1792859428-97518: Blender library list and direct solid-wall-kit lookup both UNAVAILABLE / Space503. No new integration deliverable, model or code change. Next corner remains blocked; previous test/audit results were not rerun.

## L corner — 2026-10-24
Use res://scenes/city/wall_corner_2m.scn. Origin floor at intersecting wall centerlines; legs2m along+X and-Z, height2.8,core.2. SocketA(2,0,0) accepts existing wall at rotationY0; socketB(0,0,-2) accepts existing wall at rotationY=PI/2. Outer trim extends toX=-.124/Z=.124; distinguish these bounds from grid sockets.
Three meshes492triangles; two original matching materials. Two layer1 colliders meet atZ=-.1 with no volume overlap. No interaction or navigation. Validator36 checks includes actual adjacent solid modules in memory and both seam raycasts; a saved multi-module corner demo is not supplied.
Three Blender renders inspected; source/.blend/GLB in lifesim-city-corner-wall-*; manifest corner_wall_manifest.json; Gemini dispositions review-corner-wall-20261024.md. Solid-wall library availability now verified. Next window-opening module; no main UI integration requested yet.
