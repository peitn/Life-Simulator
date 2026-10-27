# Fictional extreme psychological household — 25 October 2026

**Source of truth:** live Godot `lifesim`. Requested user action: ACTUALLY run a fictional household with substantially more challenging psychological configurations, exclusively non-Czech character names, and one character loosely inspired by the user's self-described *general patterns* — without making a diagnosis, copying real biography, or using real name/medical history.

## Privacy and representation
- All eight are **fictional adults** with invented English-language names: **Raven Vale, Sable Wraith, Dorian Flint, Juno Vex, Orion Voss, Iris North, Ash Solace, Lucian Rook**. They are not an attempt to reproduce any actual person; no actual user name, medication, personal trauma, health record, or private chat transcript was written into the fixture.
- `tests/data/extreme_profiles_fictional8.json` holds synthetic CharacterData schema-v8 profiles, unique arbitrary hexadecimal test UIDs, legacy trait tags (one minimal compatibility fallback), explicitly graded trait_levels, HEXACO-like sliders, all eleven independently varied psyche dispositions, and supported anxiety/depression *fictional predispositions*. All 8 passed **strict CharacterValidator**.
- Raven is an intentionally non-identifying 25-year-old fictional woman: creative + friendship aspirations, high desire for companionship (`spolecensky=.82`) alongside high social threat (.91), rejection reactivity (.95), lower energy baseline (.25), sensory sensitivity (.75), emotion regulation (.46), and cognitive flexibility (.75). Her authored game wardrobe is kawaii cat-ear sweatshirt plus goth skirt and platforms, dyed purple hair. These are **design choices**, not a clinical or psychological statement about the user. The game does not model transness as a disorder; grammar and female gender identity are independent from body.
- Other cases stress different dimensions: Sable near-maximum anxiety/sensory/social threat; Dorian severe anhedonia and low energy; Juno very high impulsivity and emotional dysregulation; Orion hypervigilance, threat sensitivity and predictability needs; Lucian high irritability and impulsivity; Iris and Ash as contrasting high-regulation/socially supportive personalities. The only currently functional clinical predispositions are `anxiety` and `depression`; unsupported diagnoses are **not fabricated**.
- Simulation uses mental-health mode FULL but explicit `sh_ed_topics=false`; no graphic injury, no suicidal/self-harm action or achievements, no public mind disclosure. The strict test confirms `CharacterData.public_snapshot()` excludes `mind` and `story`. This fixture was not made the production default household, and is not pushed to GitHub.

## Reproducible scenarios
Test `res://tests/test_extreme_fictional_household.tscn`, controlled CLI args (behind `--`):
- `--scenario=low_support --seed=3` / `--seed=7`: eight agents in a tightly stressed initial home with low Raven support.
- `--scenario=high_support --seed=3` / `--seed=7`: *same eight agents and seed*, but Raven receives higher emotional support and established mutual closeness to Iris and Ash. A single ambiguous **perceived** interpersonal cue is used; test does not assert that somebody in real life rejected anyone.
- `--scenario=low_support --seed=3 --control`: independent second 14-day **uninterrupted** run compared against a 14-day run with real on-disk H4 save/reload at day7, requiring exact entire-world equality.
- `--scenario=low_support --seed=3 --days=30`: extended 30-day run, actual disk save and full destruction/rebuild/reload on days 7,14,21,28 (four verified exact snapshots).
- Saves only to isolated `user://test-extreme-fictional-<PID>/<scenario>-<seed>/` directories; player `user://saves/` is not touched. Game runs headless/offline, no network RPC or GUI visual pass.
- Numeric safety invariants sampled hourly: finite and bounded needs, stress, total and positive arousal, threat, rejection distress, depressive burden and relationships. Tracks each agent's stress, mood range, high stress hours, severe depression hours, low needs hours, maximum sensitivity, conversations and arguments.

## Verified results in ACTUAL Godot
Four 14-day main cases (all `exit=0`, `timed_out=False` and **14/14** assertions each after bug fix):
| Scenario | Seed | Conversations | Arguments | Raven mean stress | Raven peak depressive burden |
| --- | ---: | ---: | ---: | ---: | ---: |
| low_support | 3 | 195 | 62 (31.8%) | 61.2 | 1.000 |
| low_support | 7 | 209 | 82 (39.2%) | 57.9 | 0.974 |
| high_support | 3 | 215 | 77 (35.8%) | 41.7 | 0.562 |
| high_support | 7 | 222 | 64 (28.8%) | 34.2 | 0.560 |

The better observed Raven trajectory with high fictional support is a **descriptive property of these two seeds, not a real-world medical or causal prediction**; baseline relation initialization and support differ together.

**Independent 14-day uninterrupted control:** `--control` case low_support seed3, *same full ending snapshot* compared to genuine save/reload at day7: `EXTREME_UNINTERRUPTED_CONTROL ... exact=true`, **16/16** checks, ~55.1s tool runtime, exit0. Counts include the 14 checks on the repeated low_support case and two additional control checks, so do not claim 16 more distinct household scenarios.

**Extended 30-day low_support seed3:** **14/14**, ~74.9s, 8 agents ×30 days = **240 simulated character-days**. Real saves with full world dispose/recreate at days7/14/21/28, each exact. 460 talks, 104 arguments (22.6%); no NaN, out-of-range values or sustained low average needs. Raven mean stress43.8, mood range −100…+90, peak burden1.000; Sable mean stress77.0 and 185/720 hourly stress>85 observations; Lucian mean stress78.5 and 192/720 such observations, with long negative mood. These warrant future **psychological balance review**; they are not automatic test failures nor proof of human mental health trajectories.

## Genuine production persistence defect uncovered and corrected
The first extreme run was a **real FAIL** (12pass/1fail) on day7 state equality, despite successful serialization:
- `Raven_Vale` and `Lucian_Rook` had a **completed** panic episode `panic_elapsed=26.0` minutes after the two-minute clock step crossed `PANIC_MAX_MINUTES=25`.
- `scripts/sim/mental_state.gd::from_dict` incorrectly clamped this valid historical value to25, silently changing the world snapshot and potentially subsequent consistency.
- Corrected `from_dict` to preserve finite, nonnegative elapsed durations (bounded upper limit1e7), allowing legitimate clock-step overshoot. Keeps legacy save missing field behavior. A targeted new regression asserts `panic_elapsed=26` exact save/load.
- Original low_support seed3 retested after fix: **14/14**, exact full-state on restore; independent 14-day never-saved comparison also fully equal. No changes to panic triggering, active durations, player choices, private RPC or self-harm content.

## Regression verification and limitations
After the production fix, original tests passed: `test_save_game` **46/46**, `test_save_continuation` **12/12**, `test_mental_health` **95/95**, `test_arousal_valence` **36/36**, all exit0 with no timeout. Godot script syntax check **60/60**. All four 14-day permutations rerun successfully with the final runner after optional 30-day flag additions.
The 30-day run is 1 seed/1 condition, while 14-day comparisons cover2 seeds ×2 conditions. High-risk episodes were **not** simulated as intentional harm actions. This does NOT establish clinical realism, neurological/biological illness simulation, full H4 multiplayer persistence, GUI frame performance or behavior in all possible households. Only reproducible synthetic tests. Existing legacy ObjectDB shutdown warnings persist.

**Files:** `tests/data/extreme_profiles_fictional8.json`, `tests/test_extreme_fictional_household.gd` and scene; minimal production repair `scripts/sim/mental_state.gd`; this report plus checkpoint/devlog/testing documentation. Run requires v3 main cooperative lock for writing; user saved-game slots unaffected, no GitHub/AI-room push.
