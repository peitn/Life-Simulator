# Full household regression, social nuance — 2026-10-26

**Task:** actually run the whole house test under the new H5 social outcomes, learned trust/dependency and private support mechanics. **Result: 16/16 complete runs, 1 real acceptance failure in a brief hygiene threshold; other suites pass. Do NOT label whole run PASS.** Source of truth: Godot `lifesim`, original `tests/test_household_dynamics.gd::_one_run` and `tests/test_extreme_fictional_household.gd`.

## Why the 16-seed matrix was sharded
The original 16-seed monolithic 14-day suite historically hit the 120-second connector wall at final determinism; it must not be claimed to have passed. This run added `tests/test_household_full_shard.gd/.tscn`, subclassing the original household fixture and calling its **unchanged _one_run** over bounded groups of four seeds. The original default fixture has 3 NPCs, not 7. An initial harness mistakenly expected 7 and failed 4 assertions despite intact simulation: that *harness error was corrected* and all seed0–3 experiments re-run. The user-requested eight characters with foreign fictional names were separately tested in four scenarios and for 30 days. No legacy default-character names were changed.

## 16 × 14 game days, 3 existing NPCs each
| Seed | Talks | Genuine fights | Awkward | Misunderstandings | Positive talks | Critical need time |
|---|---:|---:|---:|---:|---:|---:|
|0|108|17|5|8|78|0|
|1|110|14|7|5|84|0|
|2|109|20|4|6|79|0|
|3|107|11|10|2|84|0|
|4|113|17|6|6|84|**32 simulated minutes of hygiene<10**|
|5|105|11|4|5|85|0|
|6|109|26|4|6|73|0|
|7|109|21|2|3|83|0|
|8|112|15|6|3|88|0|
|9|114|15|6|9|84|0|
|10|103|15|4|1|83|0|
|11|109|21|8|5|75|0|
|12|117|18|6|6|87|0|
|13|101|10|4|1|86|0|
|14|108|13|2|9|84|0|
|15|111|21|5|3|82|0|
|**TOTAL**|**1745**|**265**|**83**|**78**|**1319**|**32 min**|

All 16 trials actually completed 14 game days. Talk outcomes balance EXACTLY (1745). Genuine fight share **15.186% weighted**; mean per seed **15.147%**, range 9.9–23.9%. New failed social outcomes are *not* automatically fights. All seed rates within existing 8–60% wide bounds; 16-seed mean 10–40% acceptance PASS. Seed3 reproduced exactly, full social+mental snapshot signature SHA256 **92206f433ed10c71cee0a4d2980a61f2f172ff318f67f0468f88e382618bcbd4**.

Additional original-matrix checks re-evaluated from all emitted seed details:
- Conversation mood gradient: good116 fights/1064 talks=10.9%; medium135/651=20.7%; bad14/30=46.7% — correct increasing pattern.
- 45 de-escalations; 95 complaint talks with 19 real fights. House frictions and shared positive moments in **all 16 seeds**.
- Relationship mean +47.29, bounds -31.54 to +96.37, mean three-pair dispersion (sample SD) 36.28, no all-hostile nor all-idyllic seed. 1.107 life events per NPC/day. Extreme stress>85 in original three-NPC matrix: none.
- **Only unmet strict acceptance:** critical needs<10: seed4 had 32 minutes, violates canonical zero-critical-needs condition. All 15 other seeds had zero.

Batch execution:
- seeds0–3 + seed3 replay: **21/21 PASS**, exit0.
- seeds4–7: **19 pass / 1 fail**, exit1 due strictly bounded need check seed4.
- seeds8–11: **20/20 PASS**, exit0.
- seeds12–15: **20/20 PASS**, exit0.
Combined **80 passed / 1 failed** for the corrected complete matrix checks. The first wrong-NPC-count fixture error is separate and not counted as a production failure.

### Root-cause probe for seed4 (read-only, exact original RNG/setup)
Replayed seed4 from 8:00 game time over14days using original seeds: third original NPC's **hygiene** gradually fell below10 on game day3 09:26, reaching **7.861/100** at09:56. The character remained in a `cook` action then autonomously selected `shower`; completion restored hygiene and there was no prolonged collapse. Only hygiene failed: energy/hunger/social/comfort/fun never below10. 16 two-minute ticks =32 simulated minutes, and original critical criterion failed correctly. Classification: **genuine short-lived prioritization/timing failure**, not social-model NaN or a persistent needs loop; do not hide, relax acceptance or claim PASS.

## Eight NON-CZECH fictional extreme profiles: four 14-day pairwise scenarios
Original exact fixture `tests/data/extreme_profiles_fictional8.json`, eight adults including Raven Vale, Sable Wraith, Dorian Flint, Juno Vex, Orion Voss, Iris North, Ash Solace and Lucian Rook (not clinical replicas):
| Support | Seed | Talks | Actual fights | Binary save/reload | Result |
|low|3|239|45|1 at day7|14/14 PASS|
|low|7|233|51|1 at day7|14/14 PASS|
|high|3|239|48|1 at day7|14/14 PASS|
|high|7|233|32|1 at day7|14/14 PASS|
Raven mean stress in low/high: seed3 49.2 / 37.8; seed7 43.5 / 32.1. Raven max depression low/high: seed3 .690/.562; seed7 .571/.562. This is model-only descriptive comparison with BOTH initial mental support and ties varied. Stable others do not automatically remove severe psychological burden in Sable, Dorian, Orion or Lucian. Some simulated agents had high stress and saturation, **not automatically SH**, and SH-sensitive opt-in remained disabled as explicitly configured in test fixture. Each run passed actual day7 disk save/full restore and bounded needs/psychological-state invariants.

### Prolonged same eight-NPC condition
`--scenario=low_support --seed=3 --days=30`: **14/14 PASS**, 30 days, 518 talks/71 genuine arguments, four actual cold disk saves/reloads at7-day intervals, continuous social interaction and finite psychophysiological values. Raven avg stress39.6; Sable avg stress78.6, high-stress hourly samples226/720, severe depressive burden203/720; Lucian avg stress73.9 with22 hourly samples of low average needs. These indicate model-balancing questions, NOT binary technical invariants.

## Seven-NPC 30-day H4 save/resume regression
Existing `tests/test_household_resume.tscn`: **10/10 PASS**, actual seven distinct NPCs, six genuine cold disk save/reloads (every five game days), 643 talks/75 true fights; **bitwise identical complete final saved state** to separate uninterrupted30-day control. No chronic extreme stress, depression saturation or critical-need collapse in that scenario. Existing diagnostic `SOAK_CHUNK` log mislabels running *talks* as arguments; `SOAK_SUMMARY` correctly distinguishes them.

## Scope and caveats
- Across corrected matrix 81 tests, extreme 4x14=56, extreme30d14, household_resume10: **160 passing / 1 failing assertion**. Only one genuine failed acceptance invariant, specifically third default NPC hygiene<10 for32min in seed4. Do NOT present 160/161 as an unqualified PASS.
- No game source or city/Blender asset was modified in this run. Only the reusable bounded shard test fixture and project test report/checkpoint/devlog documentation were written. Original `test_household_dynamics.gd` suite was not edited or run as a single >120s job.
- Existing ~18 Godot ObjectDB exit warnings are old cleanup warnings and not test assertions. No claims of real clinical predictive validity. Need future small specific fix: when hygiene approaches critical while character cooks, decision priority or interruption timing should respond before <10; rerun seed4 and all baseline seeds, regression tests, and extreme scenarios to avoid unrelated changes.
- Original test fixture has legacy local-language names; **no new such names** were created. The requested new fictional experiment exclusively uses foreign names. No GitHub or room publication.
