# Builder dependency audit — 2026-10-24
Run city-1792856089-96579.
## Fixed
Previously build_solid_wall.gd saved the solid scene before loading its required doorway. Missing/corrupt dependency could leave only one output updated. Required resource existence, PackedScene type/can_instantiate and actual Node3D root are now checked before first save. GLTF-generated model root is checked before use. Failure branches free allocated nodes.
## Actual evidence
test_builder_preflight.gd creates isolated fixture scripts/output paths using an owned run ID; refuses reuse of its directory. Missing resource, existing GDScript resource, and instantiable PackedScene whose root is plain Node all deliberately return1 and write no output. Valid dependency builds both files, loads demo with3modules5colliders. All3 authored scene hashes unchanged for every case.
Final26/26, solid regression37/37, doorway31/31;94checks total, suites exit0, no timeout. Only old18ObjectDB shutdown warnings. No geometry/UV/material changes; no new visual render needed or claimed.
## Gemini actually responded
Input included exact old/new builder, executable first harness and20/20 initial results. It alleged model.free may leak GPU resources, without a concrete reproducible defect; not accepted as a confirmed bug (normal recursive node free retained). It called Node3D check redundant/unreachable because can_instantiate passed: this is false, demonstrated by new wrong_root fixture, final26/26.
Known limitation remains: two output saves do not provide all-or-nothing crash/IO recovery. Suggested two atomic renames alone cannot guarantee a multi-file transaction; not claimed fixed by dependency preflight.
Blender503 prevents new corner production/current library verification. No Blender mutation, no new authored model, no GitHub writes.
