# H5 hygiene early-care fix — 26 October 2026

**Status:** Real production change in connected Godot `lifesim`. User asked to fix the previously reported seed4 hygiene/cooking issue, not merely explain it. Scope: strictly hygiene prioritization and safe interruption. No Blender/city/UI/GitHub/room changes.

## Original bug and up-to-date reproduction nuance

The previous 16-seed household matrix (before the emotion layer) had one genuine seed4 acceptance failure: the third NPC's hygiene was **<10/100 for32 simulated minutes**, minimum **7.861**, while completing cooking then seeking a shower. Root cause: autonomous `_act` only interrupted a task when its *lowest need* was <8 (or <3 for noninterruptible), by which time a further walk to the shower could exceed the stricter <10 acceptance threshold.

**Before this hygiene fix**, seed4 under the later 19-emotion system already had **0 critical minutes** (115 talks26 fights); unrelated changes shifted the random trajectory. Thus it is NOT accurate to attribute a numeric seed4 before/after improvement directly to this code. We fixed the **underlying latent deadline/priority defect** and added a direct controlled reproduction.

## Production edits

1. `scripts/sim/utility_planner.gd`: new `HYGIENE_SHOWER_PRIORITY=24.0`, `HYGIENE_INTERRUPT_AT=20.0`, `urgent_hygiene_plan(sim, objects)`. When hygiene<24 and neither hunger<15 nor energy<12, find the nearest **available** real shower and prioritize it *before* selecting other routine work. Empty/unavailable showers fall back to standard utility scoring; no reservations forged, and other critical body needs retain priority.
2. `scripts/sim/sim_agent.gd::_act`: for **AI-controlled, normally interruptible, nonsocial, nonsystem, nonpanic** tasks ongoing>10min, if hygiene<20, no positive hygiene effect/rate, and shower actually available, interrupt early via existing `_finish(true)` (releases stove/treadmill reservation and emits correct interrupted action) then allow replanning next tick. Never interrupt user commands or noninterruptible sleep. Negative hygiene effects (workout: hygiene-22) are explicitly considered *worsening*, not treating hygiene. No force-completed cooking or duplicated moodlet/meal.

This deliberately preserves **<10 critical-need test criterion unchanged** and does not simply make the hygiene bar decay slower. It is preventive **when a shower is accessible**; it does not claim hygiene can never fall below10 if an NPC must follow player commands, is trapped in a noninterruptible event, lacks a working shower, or has stronger biological needs.

## New focused integration fixture

`tests/test_household_hygiene_preemption.gd/.tscn`: **28/28 PASS, exit0, no timeout.** Real Godot world with eight fictional adult foreign-name NPCs, actual shower/stove/treadmill. Verifies:
- threshold24: not forced above threshold, forced early below it, nearest available reserved facility, planner chooses shower over routine temptation
- urgent hunger/energy outrank hygiene and unavailable shower not commandeered
- real cook starting hygiene21 and action elapsed11 is interrupted **before completing and while hygiene remains >=10**, stove reservation released, immediate replan to shower, character genuinely walks and cleans with hygiene never below10
- no player-owned cooking interruption, no interruption of noninterruptible sleep, no thrashing while shower occupied and proper return when freed
- workout explicitly worsens hygiene, cannot erroneously mask early shower priority, and releases treadmill on interruption

First new fixture 24/24 before workout-negative refinement, then **28/28 after final changes**. All tests completed rather than timed out.

## Whole-household regression, after the final workout refinement

Original `tests/test_household_dynamics.gd::_one_run` for **all16 seeds ×14 days** executed in four bounded real-headless batches via existing `tests/test_household_full_shard.tscn`, plus exact seed3 replay:
- Seeds0..3 + seed3 exact replay: **21/21 PASS**.
- Seeds4..7: **20/20 PASS**.
- Seeds8..11: **20/20 PASS**.
- Seeds12..15: **19/20**, **one unrelated stochastic social-rate failure**: seed13 actual arguments 6/103=5.83% vs per-seed helper acceptance bound 8–60%. Do not loosen bounds merely to hide it or claim all 81 checks PASS. Seed13 had **zero critical needs**. The original canonical suite checks aggregate conflict range10–40%, not this helper's per-seed8–60%.
- **All16 seeds: zero simulated minutes at ANY basic need below10**, including seed4. **1740 conversations,275 actual arguments (15.80% weighted)**, plus separate awkward/misunderstood conversation categories. Real full14-day seeds completed without tool timeout. Deterministic seed3 replay exactly identical.
- **80 checks PASS,1 social outlier FAIL** across the four batches. Hygienic acceptance **16/16 PASS**. No source/test acceptance criterion changed during this fix; one social issue retained honestly.

## Additional verified regressions

- `test_save_continuation.tscn`: 12/12 PASS exact long continuation.
- `test_household_dynamics_slice.tscn`: 63/63 PASS (original microtests +4x14day).
- `test_mental_health.tscn`: 95/95 PASS.
- `test_extreme_fictional_household.tscn -- --scenario=low_support --seed=3`: 14/14 PASS, eight NPC 14 days, 221 talks54 actual arguments and full day7 disk roundtrip.
- `test_household_resume.tscn`: 10/10 PASS, seven NPC30 days, six actual cold disk reloads, exact final saved state vs never-saved control; 644 talks61 actual arguments.
- `godot_check`: 60/60 bundled script checks OK; new fixture also compiled and ran. Existing benign ObjectDB18 warnings unchanged.
- **Not run:** all four extreme eight-person social-support/seed variants, full eight-agent30d, multiplayer and visual screenshots for this narrow production change. Their previous results must not be silently reported as new tests.

## Handoff and coordination

Small fix only, no new diagnoses, no SH logic and no public psychological data. The prior seed4 hygiene failure is closed as a **modeled risk mitigated with directly tested early-care behavior**, not evidence of perfect needs fulfillment for every possible household. Unrelated stochastic seed13 low-argument-rate helper acceptance needs review in H5 but must not be bundled into hygiene fix or weakened ad hoc. Authoritative network player commands and noninterruptible state left unchanged.

MAIN v3 run `main-hygiene-seed4-1793016500-218293` with hash-checked scoped writes and backups. Final backup and explicit lock release described in history.
