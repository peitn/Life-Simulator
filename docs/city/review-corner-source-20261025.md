# Corner source/scene regression audit — 2026-10-25
Run city-fallback-1792882030-134300; actual file scripts/city/validate_corner_source.gd. Independent Gemini review requested after first positive and negative Godot executions; Gemini did not execute tools.

## Actual evidence
- Source GLB SHA-256 cb6b94811cdfe67f2c2baba4f355f07836dd30390a8db87e4b13912df976baea, saved scene SHA-256 f00b753f61eb4abd3cbec74616f67bef186f2671c1b83487350c109cfe423adf, both unchanged from prior manifest.
- Final positive run 37 passed / 0 failed, exit 0, timed_out false. Tests cover mesh name/transform, surface array equality (vertices, indices, normals, UV), primitive and PBR albedo/roughness.
- In-memory BoxMesh substitution in corner_core: 31 passed / 5 failed, exit 1 as expected, timed_out false. No project file mutation in negative test.
- Existing corner36/36, solid37/37, doorway31/31, all exit0/no timeout; Godot syntax check60/60. Pre-existing 18 ObjectDB shutdown warning only.
- No geometry changes, no new Blender renders or GLB export. Blender library query returned six city assets successfully.

## Gemini findings and dispositions
1. Alleged invalid Mesh.ARRAY_* indexing: REJECTED. Godot Mesh.surface_get_arrays() returns an outer Array indexed by Mesh.ArrayType integer constants. The actual 37-check test successfully indexed fields 0,12,1,4. The claim confused outer Array indexing with packed-array element indexing.
2. Exact PackedArray equality potentially brittle: ACCEPTED AS INTENTIONAL regression behavior for this fixed GLB/scene pair. It detects serialization divergence; cross-version geometric equivalence requires a separate approximate comparator, not a silent relaxation here.
3. Unindexed/non-triangle surfaces could crash or miscount: FIXED with indexed/nonindexed fallback and explicit triangle-primitive assertion; actual final 37/37.
4. Strict StandardMaterial3D cast: FIXED to BaseMaterial3D; still checks original PBR material parameters. ShaderMaterial is not supported by this intentionally fixed original-material contract.
5. Early-exit raw Node leak if packed scene unavailable: FIXED by freeing generated raw scene before exit. Other post-instantiation paths reach common cleanup.

## Remaining
No new window model, textures, navmesh, locomotion or gameplay FPS measurements in this run. Future M1 window generation should include separate source/scene and collider tests. No GitHub publishing authorization inferred.
