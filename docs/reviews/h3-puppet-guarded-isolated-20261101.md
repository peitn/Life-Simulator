# H3 isolated guarded SimPuppet integration — 2026-11-01
Run: `main-fallback-1793491851-67526`. Status: **PARTIAL / H3 NOT ACCEPTED**.

## Scope
Read main CHECKPOINT.md, docs/implementation-sequence.md, docs/automation-lock.md, recent main history and source. No successful primary MAIN work in preceding ~75 min. v3 main lock acquired, running history verified; initial remote backup project 406345 KB/library 123493 KB. City, Blender, GitHub, AI room and production files untouched.

New test-only `tests/diagnostics/h3_puppet_guarded_probe.gd` (SHA256 c1152e80477de9be2c3d6340fca05bc8c3fc8d6868a2eb58e8b4ef62a7551808) and `.tscn` (SHA256 fcf0013a5d30f47c5b4a6c01f4ef63b5bd98eea45884739aecb9492622b97654). Source hashes are pinned: production SimVisual SHA256 2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3; SimPuppet SHA256 725d228d40a97711ad6757b71cc45dbfbd3add64862696682a92d875316d6554. No production edit.

The test reuses the existing guarded staged SimVisual in-memory patch and compiles a test-only SimPuppet from exact production source with three scoped modifications: injectable H3VisualScript, new() uses it, and _process calls visual.apply only when visual state is ready. A real Node3D SimPuppet is added to a SceneTree. A seeded CharacterRandomizer fixture is repaired to a valid public snapshot. Checks: public snapshot validation, private UID rejection, valid appearance change during building and deferred latest application, no private data, ready transition and cancellation of unfinished puppet, plus 19 prior visual lifecycle checks.

## Actual test evidence
- Initial run: exit=1, 25/31 PASS, 6 FAIL because `Validator.repaired({}, public_only)` has no personality traits and fails strict validation; independent validator diagnostic returned exactly `personality.traits: aspoň 1 rys`. Corrected fixture with seeded Randomizer (seed 42) + repaired public snapshot, verified strict public validity.
- Corrected two separate Godot headless runs: **31/31 PASS** each, exit=0, 9.5s and 9.7s, timed_out=false.
- Existing `tests/test_character_net.tscn` real ENet **97/97 PASS**, exit=0, 19.0s, timed_out=false.
- `godot_check`: **60/60 PASS**.
- stderr: pre-existing warning of 20 ObjectDB instances at exit; not clean stderr.
- Original `tests/diagnostics/h3_three_process.FAILING.tscn` attempt returned connector internal error with no test output. Four verified fixture process IDs were observed, later all exited; no survivors. **17-gate result is PENDING / NOT CERTIFIED**. No claim that staged variant ran over ENet or that H3 is fixed.
- No UI source change; no render comparison performed.

## Skeptical Gemini audit and independent resolution
Gemini reviewed design and post-test results. Valid concerns: before-add_child apply_look timing, test-only altered static preload contract, missing actual three-process integration, insufficient interleaving/stress and non-clean stderr. Its claim that this test does not use a real SceneTree is false: `add_child(puppet)` triggers actual _ready/_process/_exit_tree; it is still not a real multiplayer fixture. The initial invalid fixture was independently reproduced; corrected valid fixture passes. No private data was sent to Gemini.

## Next single step
Introduce the guarded staged client SimPuppet variant **only in the three-process H3 test fixture**, run the unchanged 17 acceptance gates using the bounded runner with captured stdout/stderr/exit/timeout, and compare to the unmodified baseline. Do not change production until 17/17 and ENet regressions pass.
