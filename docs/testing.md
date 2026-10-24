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
| `test_household_matrix` | Run 23, slow: 4 / 6 / 8 characters × 4 seeds × 30 days with mean ± spread, extreme-stress streaks, depression saturation, drinking, relationship spiral and spread; determinism | 105/106 (4-character argument mean 41 %, open) |
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
