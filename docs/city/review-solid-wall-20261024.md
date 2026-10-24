# Solid-wall recovery and independent audit — 2026-10-24
Run city-1792837782-83277. Protocol v3 acquire succeeded; immediate history existence checked. Backup before edits: 114390 KB plus library 120 KB.
## Scope and evidence
Existing solid wall and three-module demo were inventoried, not regenerated. GLB SHA256 bd86dbd0f73a3d15e8f1a5688b28b980985c707aadd36c102d1201fa6fd59251; standalone scene b22a20c7fc83bf6097c6d0c2942b29eaa131b7beb8a2afe233c08e7cd3d12f15; demo cf62e29c866e38641ecda541cfceff31afd07f51fcbf52642292f55c5b31e318.
Read and visually inspected the four original stored renders solid_front/back.jpg and solid_assembly_front/back.jpg. Both sides show aligned wall tops and skirting, clear doorway, no obvious large gaps/intersections at this resolution. These are existing Blender renders, NOT newly generated Godot screenshots. Geometry unchanged in this run.
Blender library list and direct solid-wall-kit lookup both returned McpServerError: Space 503 / UNAVAILABLE. Current library .blend integrity could not be reverified. Do not claim fresh Blender verification.
## Actual change
validate_solid_wall.gd now independently loads the separately saved catalogue scene. Nine added checks cover PackedScene existence, identity root, single collider, size/placement/layer/enabled state and interior/exterior physics rays. Previous tests exercised the GLB and demo only, so an independently damaged standalone file could pass.
## Executed tests
Baseline 28/28. Updated solid validator 37/37 and doorway regression 31/31, both exit0 and no timeout. Solid import plus all validation 75.8 ms single headless run, NOT FPS/frame time.
Memory-only disabled standalone collider fault: 33 passed,4 failed,exit1,no timeout. Confirms new coverage detects the fault without altering authored assets.
Stderr: pre-existing 18 ObjectDB shutdown warning remains. No other test errors in positive runs.
## Actual Gemini audit and dispositions
Gemini generate responded twice: first reviewed full solid_wall.py, build_solid_wall.gd, old validator and manifest; second reviewed full updated validator and test results. It did not execute Godot or access Blender.
- Standalone scene coverage gap: accepted; nine checks and negative test added.
- Collision .2 versus visual .248 claimed high severity: rejected by specification; decorative skirting is intentionally non-colliding. Its projection is .024m each side, not Gemini's .004m. This convention remains explicit in HANDOFF.
- Missing doorway dependency in builder: confirmed robustness limitation on absent required input. Existing project includes it; no build was run. Future packer hardening should validate inputs before saving first output; generation is not a two-file transaction.
- Constant x==3.0 comparison alleged flaky: no reproduction; literal loop values without accumulation, rejected as speculative.
- Redundant zero triangle assignment: confirmed harmless cleanup, deferred to generator work while Blender unavailable.
- Follow-up found no additional validator defect. This is code-review evidence, not blanket visual/performance approval.
## Remaining scope
No corner/window/roof, texture maps, navigation or gameplay FPS benchmark. Existing original materials are solid-color. Fresh Blender library verification remains pending due503. No GitHub commit/push/PR, no shared UI changes.
Next single step: when Blender recovers, verify existing lifesim-city-solid-wall-kit metadata/.blend, then implement compatible corner module with snap demo and multi-view renders.
