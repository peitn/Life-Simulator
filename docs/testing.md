# Testing

Every system comes with an automated test. Tests are scenes in `tests/`, built on `test_base.gd`
(`check()`, wait for a condition, summary, exit code). A watchdog stops a test that hangs.

## Running

```bash
# one test
godot --headless --path . res://tests/test_head.tscn

# all tests
for t in tests/test_*.tscn; do godot --headless --path . "res://$t" || echo "FAILED: $t"; done

# long-run simulation of the household (N game days) with a per-character report
godot --headless --path . -- --test 14

# the same with the FCCS social-modulation experiment (needs the FCCS brain service)
godot --headless --path . -- --test 14 --fccs
```

Generate the audio first (`tools/build_audio.gd`). Some tests check that the sound files exist.

## Test suite

| Test | Checks | Last known |
|---|---|---|
| `test_mental_health` | Stress, three-component anxiety, involuntary panic with no player lock-out, coping trade-offs and non-dominance, anti-farming, exposure, intrusive thoughts, witnesses (help versus stigma), content settings | 95 ✅ |
| `test_depression` | Separate wanting, liking and vigour, prediction error, habituation with no ceiling, shared relief budget, episodes, relapse scar, commands never refused, content caps; episode severity bands (23 October) | 106 ✅ |
| `test_reconciliation` | Grudges slow warming, decay by personality, apology sincerity from behaviour, apology spam, AI apologies from guilt, healing over time | 58 ✅ |
| `test_household_dynamics` | Run 15: friction rules, cooldowns and irritability, complaints as conversation tone, mood weight and de-escalation, soft stress ceiling for arguments, memory text by direction, shared moments (cooldown, grudge gate), dishes only after real cooking, neglect and drift; **long run 16 seeds × 14 days** of the starting household with mean and spread (arguments 20–40 %, no all-hostile or all-idyllic seed, pairs differ, mood gradient, rare extreme stress, no critical needs) and determinism | 78 ✅ |
| `test_crowded_household` | Crowded household tuning (23 October): sensory profile, joy and anticipation threshold, soft stress ceiling, alcohol window, panic refractory time, noise rules; 7 characters × 2 seeds × 14 days | 50 ✅ |
| `test_household_matrix` | Run 23, slow: 4 / 6 / 8 characters × 4 seeds × 30 days with mean ± spread, extreme-stress streaks, depression saturation, drinking, relationship spiral and spread; determinism | 118 ✅ (27 October 2026; criteria remapped after H5, see below) |
| `test_withdrawal_avoidance` | Withdrawal by episode severity, the joy cap of severe episodes, conflict avoidance from stress and depression (topics off: stress only), the planner avoiding a person the character is sore at, apologies unaffected, swallowed complaints with their rumination cost | 22 ✅ |
| `test_neuro_profile` | Psyche A (27 October 2026): schema v9 `mind.neuro` validation and migration, mental-health off rejects the mind, neutral character exactly unchanged, continuous bounded effects of all 15 axes, full > muted > off, sensory channels and overload, social battery and masking, direct communication, tics, agency (a real player `cook` command runs), diversity of two same-label profiles, determinism, save/load, network privacy, editor sliders | 57 ✅ |
| `test_social_memory` | Psyche B (27 October 2026): schema v10 `mind.memory`, fading (strong traces slower), reinforcement with a severity cap, overwrite by apology, cue reactivation with cooldown and recall gating (no farming), grievance + apology + time monotone without oscillation, label hysteresis, fact versus interpretation, memory sliders (continuous, muted/off), uid keys, witnesses and confiding (seen/told only), bounded influence on partner choice and conversation chance, save/load, rejection of unknown kinds, network privacy, determinism, editor sliders | 41 ✅ |
| `test_mood_cycle` | Psyche C (27 October 2026): schema v11 `mind.mood`, neutral = no swings and no random numbers, phase confirmation delay, ceiling (hypomania only vs mania), muted without mania, recovery with sleep and support, sleep loss as a trigger, bounded effects of elevation (sleep, social, risk, irritability), persistent low mood floor without an episode, diversity (ceiling vs cycling), coupling of the depressive phase to depression, ADHD-like + high energy ≠ hypomania, agency, save/load, privacy, determinism, editor | 38 ✅ |
| `test_inner_voice` | Psyche I (27 October 2026): schema v12 `mind.thoughts`, no event = no thought, loops grow at night and fade with distraction, support, sleep and resolution, costs (sleep, energy, rumination), self-criticism from the self-defectiveness belief, warm/hopeful thoughts, bounded action costs, modes; passive hopelessness only with the opt-in setting, crisis lines for the owner, support and sleep reduce it, no harmful action exists, nothing in the thought stream or network detail, switching off clears it; `seek_help` gated for the AI but always available to the player; save/load, determinism, editor | 46 ✅ |
| `test_personality_accents` | Psyche D (27 October 2026): schema v13 `mind.accents`, not selectable as legacy traits or presets, private; continuous effects through existing trait parameters (chemistry, forgiveness, grudges, pride, jealousy, social appetite, irritability) and hooks (rejection reaction, intent appraisal, perceived rejection, trust growth, emotional amplitude, social cost, rumination, confiding, apologising); interpersonal patterns in a live household (more arguments, fewer apologies), agency, diversity, optional private labels, muted/off and runtime switch, save/load, network privacy, editor | 36 ✅ |
| `test_ocd_social_anxiety` | Psyche E (27 October 2026): schema v14, condition profiles load and move the intended dimensions (off = none), obsession → ritual → short relief → stronger habit, habit makes doubt return faster, resisting costs tension and weakens the habit, gated autonomous rituals that really happen in a live household, theme-specific triggers (diversity), modes, agency (resist command), social anxiety: anticipatory arousal for strangers vs close people, partner choice bounded, exposure raises mastery, player can always send to talk; save/load, network privacy, determinism, editor | 35 ✅ |
| `test_player_commands` | Command queue, interruption, cancelling sleep, insult and its consequences, NetSession command validation, `player_only` actions | 40 ✅ |
| `test_psyche_presentation` | PsycheFX, low-pass music, heartbeat, distortion settings, HUD in words, thoughts | 19 ✅ |
| `test_net_protocol` | Sanitising, unique names, validation, rate limit, speed votes | 34 ✅ |
| `test_multiplayer` | Dedicated server plus clients in one process (separate `SceneMultiplayer` branches): spawn, sync, privacy, commands, chat, late join | 67 ✅ |
| `test_character` | C1: schema and defaults, round trips (dict, JSON, share code, file, Resource), migration, validator fuzzing, name filter, randomizer distribution and locks, undo/redo, hidden sensitive choices, grammar | 157 ✅ |
| `test_character_v2` | Schema v2 and review findings: `repaired()` contract, fatal inputs, 128-bit uid assigned by the server, Unicode name corpus, crown precision; run 18: head size in the randomizer (range, spread, weak link to frame, independence from gender) | 43 ✅ |
| `test_character_net` | Multiplayer join with your own character, strict validation, public snapshot replication, privacy, determinism across peers | 28 ✅ |
| `test_body_morphs` | C2: Catmull-Clark versus Blender, LSX v4 morphs, GLB blend shapes, data → weights, bones and scales, normals, CPU skinning, performance | 62 ✅ |
| `test_head` | C3: every face field has a visible morph, weights match the data, in-between and corrective shapes (12 since run 18), symmetry, determinism, no skin–eye or lip intersections across extreme combinations, no folded faces, GLB and SimVisual, server and client weights identical | 43 ✅ |
| `test_neck_seam` | C3+: head–body seam on the real GLB: a single closed loop, no gap or overlap at rest, for random bodies and with the neck bent (CPU skinning), bone weights, normals and flipped triangles, neck width, no collar under body morphs; run 13: neck-base anatomy, neck length ±1 × fat/muscle × ±30° bend, linear `b_neck_len`, seam edge fixed, crown height, Catmull-Rom invariants and nearest-hit `loop_hit` | 56 ✅ |
| `test_psyche` | Run 20, psyche model axis 1: profiles as data (the old anxiety and depression numbers exactly), limits and mandatory `why`, rejected invalid profiles, acyclic coupling graph and fixed order, P and D in range for 300 random characters, zero residual without individuality (no double counting), `explain()`, determinism through the share code, independence from name and gender, hooks in MentalState (bit-identical neutral regression, direction of each hook), content settings full/muted/off including a runtime switch, profiles without a legacy block, comorbidity clamp, coupling in MentalState, **diversity** (5 characters with the same profile differ in arousal and coping choices), **context** (support < neutral < conflict), **stability** 16 seeds × 14 days, agency, schema v5 privacy, validation, migration v4 → v5 and round trips, SimAgent integration, performance | 93 ✅ |
| `test_neck_length` | Run 13 data side of `body.neck_length`: schema v4+, migration v3 → current (and v1 → current), JSON / share code / file round trips, strict server validation with fuzzing, public snapshot, determinism, independence from gender and name, randomizer distribution and locks | 36 ✅ |
| `test_skin` | C4a: SkinModel continuity, spectrum, saturation and hue over 1,386 combinations, determinism, layer placement on the surface, shader compiles, CUSTOM0 holds the rest pose; run 18: make-up landmarks match the head | 61 ✅ |
| `test_assets` | LSX format (CRC, corrupted data), sources ↔ manifest ↔ GLB, furniture dimensions, orientation, winding and PBR, character skeleton, skin weights and variants, animations, SimVisual, primitive fallback | 155 ✅ |
| `test_hair` | C4b: every hairstyle, eyebrow shape and beard style has a mesh within budget, no head penetration, face clear, long hair lies on chest and back, eyebrow coverage, recession ranks, determinism (also threaded versus synchronous build), morph transfer (neck length, head width), bone weights, CUSTOM0, shader parameters, SimVisual cards instead of the GLB helmet, morph weights on the cards, independence from name and gender, corrupted values; run 19: penetration confirmed against the real skin triangles, temple shell edge, braids and locs away from the face, beard line and no gap under the lip | 60 ✅ |
| `test_face_detail` | Run 21, C3++: schema v6 and migration, detail and expression weights, eyelashes on the lid margins for every combination of eye extremes and while blinking, blinks close the eye opening (with the in-between shape), teeth inside the cavity and behind the lips, smile/frown/brows/jaw/pupil against the exact `HeadBuilder` shape, symmetry, determinism, GLB parts and `SimVisual` (blinking, speech, emotion, cost per frame); run 22: lens-shaped open mouth with rounded corners, Duchenne smile (corner, nasolabial fold, cheeks, lower lids), lip volume and Cupid's bow, neck profile bend with the jaw open, eyelash clumps and darker roots in the GLB | 66 ✅ |
| `test_skin_micro` | Run 22, C4c: schema v7 (`skin.type`, `oiliness`, `dryness`), migration v6 → v7 and v1 → v7, share code and JSON round trips, strict server validation with fuzzing (300 corrupted inputs), sebum and dryness zones per skin type, age, quantization, independence from skin tone, gender, identity and name, vellus colour from natural hair colour, randomizer distribution and locks, public snapshot, shader parameters and compilation, roughness formula against a CPU mirror, LOD, no melanin in the micro-detail code, performance | 50 ✅ |
| `test_audio_tone` | Music v3 data (the night song unchanged, the morning song in its spirit, no v2 instruments in music), brightness of the rendered morning song between night and day, synthesizer instruments, loop seams against each file's own sample-to-sample differences, rendered files, apartment ambience, argument voices and tension | 222 ✅ |
| `test_voice` | Character voice (27 October 2026): VoiceSynth ranges, untrusted-input sanitising, determinism, measurable pitch/timbre/tempo/roughness effects, whisper, independence from identity and body, performance; strict validation and randomizer distribution; Voice section in creator and live editor (draft, Undo/Redo, async preview, Create, Apply); conversation voices in AudioManager (worker thread, cache, cooldown, hearing range, no line for arguments or at fast speed) | 86 ✅ |
| `test_audio_engine_sfx` | Audio Engine sound set: file format, peak, clipping and silence, action mapping (no doubled object sounds), footstep surface and cadence, night clock, door-slam chance by stress and temperament, runtime loops and one-shots | 164 ✅ |

"Last known" is the state after run 23 (23 October 2026). All suites pass except two timing-related checks under machine load (slider latency in `test_character`, and an occasional `test_multiplayer` pause flake) and one open finding in `test_household_matrix` (see below); details are in `AUDIT.md`. The
slider-latency check in `test_character` (limit 4 ms) went to 5.8 ms after run 21 added about 90 blend shapes per head
surface; caches for the composed face fields, face weights and blend-shape names, and skipping unchanged writes, brought
it back to 3.7 ms. In run 22 it measured 4.1 ms while other suites ran in parallel and 3.94 ms on its own (the new skin
micro-detail parameters cost about 0.01 ms; the validator and the public snapshot dominate). Timing depends on the load
of the machine: run timing tests on their own. The slider path is a candidate for the C6 editor work.

The automated runs execute long suites (`test_head` takes about 4 minutes because it rebuilds the head ~100 times) as
background processes and collect their logs, because a single tool call is limited to 120 seconds.

`test_household_dynamics` takes about 75 seconds (16 simulated fortnights). The long run steps the clock
by 2 game minutes (`GameClock.MAX_STEP`), the same step the game uses at higher speeds.

Run 15 also fixed `test_base.gd`: the watchdog timer was created in `_enter_tree()`, before a test could
raise `watchdog_seconds` in `_ready()`, so every test had a 60-second watchdog. It is now started
deferred.

## Quality gate for every change

The automated development runs follow this gate (see [development-process.md](development-process.md)):

1. Self-review of every changed file.
2. `godot_check` over the whole project, plus the relevant tests and a regression of all existing tests.
3. An independent code audit by a second model (Gemini), with justified fixes or rebuttals.
4. Results logged in `AUDIT.md` and `DEVLOG.md`.

### Crowded household (`test_crowded_household`, 23 October 2026)

SensoryProfile (direction of traits, determinism, individual spread, habituation and its fading), joy capacity and the
anticipation threshold, soft stress ceiling, alcohol within a rolling window, growing refractory time after panic attacks,
anxiety waves only with a predisposition and never with the topics switched off, emergency sleep, noise at most once per
cooldown per sleeper, daily patience; long run 7 characters (healthy / with predispositions) × 2 seeds × 14 days:
arguments 10–40 %, nobody's needs permanently below 20, depression never frozen at the maximum, at most 2 drinks a day,
healthy characters rarely in extreme stress. 50 checks ✅ (about 45 s on a quiet machine, ~100 s under load).

Stress test from the command line: `godot --headless --path . -- --test 30 --daily --seed 1 --household res://tests/data/household_stress7.json`
(`--daily` prints a `DAYSTAT|…` line per character and day).

### Household matrix (`test_household_matrix`, run 23)

A slow suite (about 25 minutes on the shared server) that runs households of 4, 6 and 8 characters (the first N of
`household_stress7.json` plus `household_extra.json`) × 4 seeds × 30 days, sampling every game hour. Per run it checks:
arguments 10–40 %, nobody's needs below 20 for more than 10 % of the time, depression saturated (burden ≥ 0.95) for less
than 25 % of the time, at most 2 drinks a day, healthy characters above stress 85 for less than 10 % of the time and never
longer than 24 hours in a row, nobody above 85 for more than 72 hours in a row, fewer than half of all relationship values
at −50 or below (no universal spiral) and a spread of at least 15 between relationships (personalities still matter). It
prints mean ± standard deviation per household size and writes the full report to
`previews/testlogs/household_matrix.json`. It also checks determinism: the same seed gives the same final state, a
different seed a different one. Options after `--`: `--sizes 4,6,8 --seeds 4 --days 30`.

**Criteria after H5 (27 October 2026).** The matrix criteria were set in run 23, when every unsuccessful conversation
counted as an argument. Since H5, a conversation has four outcomes (good / argument / awkward silence /
misunderstanding). So the old bounds now apply to the share of *unpleasant* conversations (argument + awkward +
misunderstanding): 10–45 % per run and 15–40 % as the mean of a household size. Real arguments are checked separately:
they must neither disappear (≥ 5 %) nor dominate (≤ 45 %). Before this change the 6- and 8-character households failed
the old "argument" mean (13 %) although nothing in them had regressed.

Results after run 23 (with the two fixes below):

| Household | Conversations failing (arguments) | Healthy mood (mean ± sd) | Predisposed mood | Stress > 85 (predisposed, share of time) | Relationship mean |
|---|---|---|---|---|---|
| 4 characters | 41 % ± 2 | +7 ± 1 | +18 ± 12 | 0 % | +12 ± 4 |
| 6 characters | 19 % ± 3 | +26 ± 16 | +21 ± 6 | 0 % | +45 ± 6 |
| 8 characters | 24 % ± 2 | +28 ± 16 | +3 ± 29 | 2 % ± 7 | +35 ± 2 |

Determinism holds. The character with a very strong depression predisposition and two traumas has an episode in 4 of 12
runs. The first pass of the matrix found a real bug: an anxious character with depression stayed above stress 85 for up to
139 hours in an 8-person household, because crowding and loneliness kept adding stress during sleep (see
[mental-health.md](mental-health.md#stress-sources-and-sleep-run-23)). After the fix the longest such stretch in any run is
17 hours. Still open: the 4-character household (two grumpy characters out of four) fails about 41 % of its conversations,
with about three "dishes" frictions a day; the next step is to look at friction rates in small households and to separate a
failed conversation from an argument.

Acceptance follows the review in the shared room: healthy characters must stay out of extreme stress in every run, while a
long severe stretch (above 85 for more than 72 hours) for a predisposed character is allowed as a minority outcome (at most
about a quarter of the runs per household size). A single run may have 10–45 % arguments; the mean per size must be 15–40 %.

### Continuous personality and psyche sliders (23 October 2026)

`godot --headless --path . res://tests/test_personality_sliders.tscn` — **24/24 passed**. Covers schema v8, v7 migration/back-compat, weighted traits and opposing intensities, input validation including non-finite values, private serialization, direct disposition overrides, runtime `SimAgent` integration, reusable slider UI, and fractional strengths in random characters. Rechecked: character 157/157, psyche 93/93, mental health 95/95, depression 106/106, player commands 40/40, multiplayer 67/67. Three game days headless: TEST OK. The slower household dynamics regression needs a separate unloaded-server rerun before treating balancing as unchanged.

### Authored Blender C5 wardrobe regression — 23 October 2026

tests/test_clothing_authored.tscn: 14/14 PASS, checking authored style count, UV/tangent/morph/skin arrays, seven material groups with actual albedo+normal textures, source-to-avatar bone-bind index mapping, calf-to-leg bindings, runtime outfit swaps and morph application. tests/test_clothing_c5.tscn: 16/16 PASS (original fallbacks and authored meshes). tests/test_body_morphs.tscn: 62/62 PASS after preserving the original four-mesh body API and separately applying morphs to C5 assets. Other recorded PASS results after integration: test_character 157/157, test_character_net 28/28, test_assets 155/155, test_hair 60/60, test_character_v2 43/43, test_multiplayer 67/67. Syntax check: 60/60; three-day headless game run: TEST OK. The visuals themselves are not animation-ready; test clothing fit at motion extremes before marking C5 complete.

The Godot GLTF importer hangs on the Blender-exported GLB here (even an exported primitive cube), so runtime uses the existing tested LSX bridge instead. Important: Blender LSX skin bone order and original character's Skin bind order are not identical; ClothingWardrobe.C5_TO_CHARACTER_BIND remaps them and the dedicated test checks correspondence.



### Continuous trait regression (24 October 2026)

`tests/test_trait_continuity.tscn` checks order-independent parameter aggregation, boolean compatibility, fractional impulsivity and actual jealousy relationship/grudge consequences at 0, 0.1, 0.49, 0.50, 0.51 and 1. It must pass without runtime errors as well as with exit code 0.


### H4 offline persistence and autosave tests (2026-10-25)
- `res://tests/test_save_game.tscn` — **35/35** final exit0. Full authoritative three-agent snapshot including mental/pleasant arousal, RNG, needs, relationships, grudges, reservations/queues, manual save/load, actual HUD button presence, 5-real-minute timer trigger via injected elapsed state, checksum/backup/invalid quarantine, cold Main restart, invalid clock/needs/target/version rejection before mutation, stale offline editor cancellation and host/client denial. The test uses a **per-process isolated user://test-lifesim-save-PID** directory, not the player's save slots.
- `res://tests/test_save_continuation.tscn` — **12/12** final exit0. Save after 37 game minutes, advance 20 minutes uninterrupted, restore and advance the same 20 minutes; compare every serialized field (exact equality including RNG/dynamics), then simulate midnight to verify the real GameClock day-triggered autosave. Fixture also uses an isolated `user://test-lifesim-continuation-PID` directory.
- Existing regression suites tested: editor55, production character_net70, multiplayer67 (intentional rejected unauthorized RPC errors), mental_health95, psyche93, arousal_valence36, player_commands40 — **503/503** across all nine final successful suites. `godot_check` 60/60, and new classes tested directly. Existing ObjectDB leak-on-exit warnings are not new pass/fail logic.
- Long `test_crowded_household` run **timed out at 65s**, not certified. Earlier household dynamics matrix timed out70s; no end-to-end multi-hour/multi-day soak claim. Rendered HUD/narrow window screenshots, filesystem crash/power loss injection, future-version migration and authoritative multiplayer save/load were NOT tested and remain open.


### 2026-10-25 — household long-run / H4 resumability (actual Godot)
- `res://tests/test_crowded_household.tscn`: **50/50**, ~70.3s, 7 characters × two scenarios (healthy and stressed) × two seeds × 14d. Conflicts 34%,18%,29%,27% across four cases; numeric and behavioral thresholds passed.
- `res://tests/test_household_dynamics.tscn`: all **16 seeds ×14 days**, final aggregate analysis printed complete with positive unit checks and 1674 talks/conflict29.1%/relationships−58..+93, **but** remote invocation hit its 120-second HARD TIMEOUT just before its last deterministic replay step. **This monolithic suite is NOT a certified pass**. Requesting `seconds=280` did not override server cap.
- NEW `res://tests/test_household_determinism_split.tscn`: **5/5 exit0** (~24.3s). Mirrors original same-seed replay signature (14-day seed3 twice) and different seeds 3/4 two-day divergence. Seed3 had 105 talks and 23 arguments in both repeated 14-day runs.
- NEW `res://tests/test_household_resume.tscn`: **10/10 exit0** (~84.1s). 7 vulnerable characters × 30 days, physically save `manual.lss` to isolated `user://test-lifesim-soak-PID/` and cold-recreate/reload entire seven-agent scene every five days (six checkpoints). Each checkpoint exact snapshot equality. Additionally execute a separate uninterrupted 30-day reference run and assert **entire final snapshot** matches the repeatedly resumed state (passed); 606 conversations, 136 arguments, no bounds regressions. Tests current real H4 functionality without touching `user://saves/`.
- **65/65 certified across three completed suites.** Old crowded/household tool-timeouts stemmed from remote tool runtime, not from lack of save-game functionality. Avoid claiming crash tolerance beyond observed validations or calling the timed-out monolithic run PASS. Review `docs/reviews/household-soak-resume-20261025.md`.


### 2026-10-25 — extreme fictional psych-profile household stress
- `res://tests/data/extreme_profiles_fictional8.json` — **8 distinct adult characters, entirely fictional English-language names**, including a creative alt female Raven Vale loosely inspired by non-identifying user-described social/rejection/energy patterns; no real name, health record, medications, personal trauma or user secrets. Schema-v8 strict validated, 11 independent psyche dimensions, supported anxiety/depressive susceptibility only.
- `res://tests/test_extreme_fictional_household.tscn` — choose `--scenario=low_support|high_support`, `--seed=3|7`, optional `--days=30`, and `--control` (intended for one 14-day selected case only). Normal 14-day case checkpoints at day7, high-intensity 30-day case checkpoints at days7/14/21/28. Uses isolated `user://test-extreme-fictional-<PID>/`, no actual user saves.
- Four seeded 14-day cases: low3 195 talks/62 argues, low7 209/82, high3 215/77, high7 222/64. Final each **14/14 pass** exit0/no timeout. Every whole-household cold load EXACT match; support comparison descriptive, not causal or diagnostic.
- Independent `--control` low3 14-day baseline with **no save** versus an H4 day7 save/reload: final full snapshot **identical**, **16/16 exit0** (~55s). A 30-day low3 eight-agent run performed **four** real complete reload checkpoints with all exact states, 460 talks104 argues, **14/14 exit0** (~75s). High stress and severe negative mood present in some simulated personas without invalid numeric state.
- Found real old `MentalState.from_dict` bug: completed panic lasted26m when 2-minute step overshot25m limit; serialization wrote26.0 but restore clamped25.0, wrong full equality for Raven/Lucian. Source fixed to preserve finite nonnegative historical elapsed time and extra regression asserts exact26.0. Initial failing run was **NOT counted**. Regressions after fix: save46/46, continuation12/12, mental95/95, arousal36/36, syntax60/60.
- Headless/offline; does not establish psychological clinical validity, game UI performance, or multiplayer H4. See `docs/reviews/extreme-fictional-household-20261025.md`.


### 2026-10-25 — implemented H5 nuanced social outcomes / learned trust / private care
- NEW `res://tests/test_social_nuance.tscn`: **27/27**, exit0. Directed trust independent of affection, bounded longer interpersonal pattern counters, broken apology not instant repair, automatic per-person dependency growth vs stable other, decay, exact save/legacy restoration, four real conversational outcome classes, owner-only support vs opt-in SH concern/privacy.
- NEW `res://tests/test_household_dynamics_slice.tscn`: **63/63**, exit0 (~47.3s), original relationship/friction microchecks + four 14d seeds & seed3 replay. Seed0:108 talks/17 actual fights/8 misunderstandings/5 awkward; seed1:110/14/5/7; seed2:109/20/6/4; seed3:107/11/2/10. Adjusted original matrix criterion from20–40% (binary unsuccessful) to **10–40% (genuine arguments only)** with explicit histogram invariants. Original monolithic 16-seed script was NOT certified this run (previous 120s tool timeout).
- Real extended tests: crowded7 50/50 exit0 (~64s), true argument shares16/11/13/13%; extreme fictional8 low_support seed3 14/14 exit0 (~34.5s), 239 total=161 warm+45 real fight+13 awkward+20 misunderstandings; household_resume7×30d 10/10 exit0 (~72.6s), six disk cold-reload snapshots and uninterrupted30d control exact (643 talks75 arguments).
- Relevant regression sets completed during implementation: save_game46/46, save_continuation12/12, mental_health95/95, character_editor_ui55/55, attachment_sensitive_scene31/31, multiplayer67/67, arousal_valence36/36, rejection_hypersensitivity39/39. Combined **545/545 checks across 13 finished suites**, all final successful invocations exit0/no timeout. A first new compile type inference error and initial sparse trust-history restore mismatch were FIXED before passing final tests. Historical standard engine shutdown ObjectDB warnings remain; multiplayer includes expected rejected forged RPC logs.
- Emotional dependence is now a learned private **game state**, not a diagnosis. In extra 14d read-only live-life probe Raven naturally developed dependency to Iris~0.21, Juno~0.05, without reciprocal dependency in stable profiles. Rejection-specific safety-concern setting was not spontaneously reached in that short probe, even with SH opt-in; later generic high depression+stress support cue is separate and DOES NOT denote SH. No new SH actions, auto-incidents or methods. File docs/reviews/social-nuance-20261025.md.


### 2026-10-26 — FULL seeded household with current H5 mechanics
- New bounded reusable `tests/test_household_full_shard.tscn` calls unchanged `tests/test_household_dynamics.gd::_one_run` seeds0..15, 14 days each in four independent process runs to avoid120s connector deadline. Historical fixture has3 NPCs. Corrected four-shard checks: 21/21,19/20,20/20,20/20. **Seed4 hygiene<10 for32 simulated min while cooking, min7.861 before shower; one genuine failure.** Total1,745 conversations,265 actual arguments,83 awkward,78 misunderstandings,1,319 warm. All16 seed runs complete; seed3 replay exact, no NaN/other critical runs. Mood-gradient and relationship matrix acceptance preserved except zero-critical-needs invariant.
- Eight separately configured fictional NON-CZECH adult extreme agents: scenario low seed3 14/14 (239 talks/45 fights), low seed7 14/14 (233/51), high seed3 14/14 (239/48), high seed7 14/14 (233/32), each real mid-scenario save/reload; plus low seed3 **30d 14/14** (518/71,4 cold reloads). No claim of auto SH; flag disabled in fixture. Raven mean stress low/high seed3 49.2/37.8, seed7 43.5/32.1.
- Seven-agent 30d actual disk save + cold resume every5days `test_household_resume.tscn` 10/10, final entire snapshot exact to independent uninterrupted run (643 talks,75 real fights).
- Corrected current-run aggregate **160 assertions pass/1 fail** across the above tests; do not mark global suite PASS. Initial shard fixture 7-NPC assertion typo separately corrected then rerun seeds0..3. Original 16seed monolith NOT invoked. Existing18 ObjectDB cleanup warnings. Full root-cause probe and next step docs/reviews/full-household-regression-20261026.md.


### 2026-10-26 — 19-axis simultaneous emotional model integrated into live game
New `test_emotional_state.tscn`: **45/45** exit0, three full autonomous days with 8 fictional foreign-named NPCs, 19 finite axes, targeted empathy/fear/envy/safety, ambiguous perceived rejection, event impulses, soft action weighting, snapshot exact/legacy/invalid validation; no public replicated emotional values or SH actions. New `test_emotional_hud.tscn`: **11/11**, real offline private UI selected NPC, 19 numeric bars, simultaneous joy+sadness, per-person labels, expanding/closing, small mobile viewport helper. Initial HUD first run test assertion wrong target 8pass/1fail; fixed then11/11. 60 legacy script syntax OK, new scripts directly compiled/run.
Existing tested: save_game46/46, save_continuation12/12 exact, mental_health95/95, social_nuance27/27, arousal_valence36/36, psyche93/93, household_dynamics_slice63/63, multiplayer67/67 on retry (FIRST attempt failed one flaky client pause clock sync: 66/67), household_resume30d10/10 exact after6 real cold reloads versus uninterrupted, 14day extreme8 four variants each14/14 (low3 220talks/53 arguments, high3 223/42; low7 233/50, high7 259/41), 30d extreme8 low3 14/14 with four restores (500talks/80arguments). Final successful invocation aggregate **575/575**; not a claim of no intermittent issues. Full original16seed baseline not rerun; known old seed4 hygiene<10 for32min unresolved. Review docs/reviews/emotional-state-20261026.md. 19 emotions are private and NOT clinical predictions; never auto-trigger SH.


### 2026-10-26 — targeted hygiene seed4 repair
- `test_household_hygiene_preemption.tscn` **28/28 PASS** headless, real eight foreign-name adult NPCs, accessible shower/stove/treadmill; 24 initial checks plus4 exercising negative-hygiene preemption; verifies proactive hygiene priority at24, safe interruption at20, complete cook→walk→shower process above 10 threshold, no player override, no sleep interruption, busy shower no thrash, reservation release.
- Full canonical simulation method `test_household_dynamics.gd::_one_run` all 16×14 days re-executed after final code through `test_household_full_shard.tscn`: **critical-need time zero across16/16**, including seed4. 1740 talks275 actual fights. Seed3 exact deterministic replay. Four shards21/21,20/20,20/20,19/20: **one unrelated social-rate outlier seed13=6/103=5.83%** conflicts below *helper's per-seed8%* threshold; do NOT mark full overall matrix PASS. Original aggregate10–40% actual-argument band is satisfied (~15.8%), no criteria reduced.
- Regressions: save continuation12/12, social slice63/63, mental health95/95, extreme8 low_support3 14/14 including real day7 cold reload, seven-person30d save resume10/10 with6 disk reloads and final EXACT independent uninterrupted control; godot_check60/60 bundled syntax OK. Historical ObjectDB18 warnings persist.
- Historical pre-emotions seed4 failed 32min hygiene<10, min7.861. On current emotion version **seed4 already passed before** priority fix; new controlled fixture isolates and verifies original early scheduling vulnerability instead of claiming direct improvement in an unchanged seeded scenario. See docs/reviews/hygiene-early-preemption-20261026.md.


### 2026-10-26 — Adult intimacy and rare damaging social dynamics
- New `test_adult_social_integration.tscn` **55/55 PASS**: actual 8 fictional ADULT NPCs, server-owned 18+ ages and setting default-off, separate two-person consent and withdrawal/expiry, NPC refusal and coercion barrier, real simulated 45min fade-to-black sex action, true HUD fade and post-fade removal, new negative social actions and exact pressure subtype stats not polluting chats/fights, global+per-target cooldown, rare blackmail AI gating, private network details, H4 exact household save and legacy no-intimacy-slot compatibility, NaN/underage data rejection. No explicit graphics, no autonomous sexual behavior. Two early failed assertions were a fixture asking the *same coercive action within 120min*, corrected to a new target; final 55/55.
- New `test_adult_sexuality_editor.tscn` **24/24 PASS**: 5 private offline identity fields and live sliders/toggles, independent asexuality/libido/sexual vs romantic targets, staged Undo/Redo/Apply/Cancel, immediate IntimacyState configuration after commit, mental state preserved, network identity and rename denied, full H4 valid.
- After last offline editor code: `test_character_editor_ui`55/55, `test_character_edit_commit`28/28. Other suites this run: `test_multiplayer`67/67 (before editor-only extension), `test_character_net`70/70, `test_character_v2`43/43, `test_player_commands`40/40, `test_emotional_state`45/45, `test_emotional_hud`11/11, `test_save_game`46/46, `test_save_continuation`12/12 after autonomous behavioral update, `test_social_nuance`27/27, `test_household_dynamics_slice`63/63 after update, `test_mental_health`95/95, `test_psyche`93/93, `test_arousal_valence`36/36, `test_household_hygiene_preemption`28/28, `test_household_resume`30d 10/10 after final AI changes, six true cold saves and complete final state exactly equal to uninterrupted control (644 talks61 fights). `godot_check`60/60 built-in script checks; new tests compile/run.
- Extreme8 14d low3 14/14 completed at an intermediate integration stage; an attempted rerun after autonomous pressure addition was blocked by platform safety controls and thus must not be represented as executed. Historical 16seed seed13 low conflict-rate acceptance case remains open and was not rerun here. Dedicated multiplayer sexual consent between two **owned** avatars, private owner-only sexual HUD and rendered mobile screenshot are future tests/features; current implementation intentionally does NOT replicate private sexuality. Report docs/reviews/adult-social-intimacy-20261026.md.


2026-10-26 MAIN adult-social follow-up QA: same owned run, production sources unchanged. Real tests on final source: integration55/55, editor24/24, save continuation12/12, multiplayer67/67, social nuance27/27, save game46/46, 8-NPC14d14/14 (221 talks/54 arguments, day7 restore), syntax60/60. Extra 30d attempt at 115-sec limit printed 644 talks/61 arguments/6 saves but TIMED OUT before final exact-comparison checks; NOT counted as completed (earlier 30d10/10 remains separately documented). Details docs/reviews/adult-social-intimacy-20261026.md. Remaining network two-owner test and visual preview. Backup and owned lock release are final run steps.
