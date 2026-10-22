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
| `test_depression` | Separate wanting, liking and vigour, prediction error, habituation with no ceiling, shared relief budget, episodes, relapse scar, commands never refused, content caps | 92 ✅ |
| `test_reconciliation` | Grudges slow warming, decay by personality, apology sincerity from behaviour, apology spam, AI apologies from guilt, healing over time | 58 ✅ |
| `test_household_dynamics` | Run 15: friction rules, cooldowns and irritability, complaints as conversation tone, mood weight and de-escalation, soft stress ceiling for arguments, memory text by direction, shared moments (cooldown, grudge gate), dishes only after real cooking, neglect and drift; **long run 16 seeds × 14 days** of the starting household with mean and spread (arguments 20–40 %, no all-hostile or all-idyllic seed, pairs differ, mood gradient, rare extreme stress, no critical needs) and determinism | 78 ✅ |
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
| `test_assets` | LSX format (CRC, corrupted data), sources ↔ manifest ↔ GLB, furniture dimensions, orientation, winding and PBR, character skeleton, skin weights and variants, animations, SimVisual, primitive fallback | 150 ✅ |
| `test_hair` | C4b: every hairstyle, eyebrow shape and beard style has a mesh within budget, no head penetration, face clear, long hair lies on chest and back, eyebrow coverage, recession ranks, determinism (also threaded versus synchronous build), morph transfer (neck length, head width), bone weights, CUSTOM0, shader parameters, SimVisual cards instead of the GLB helmet, morph weights on the cards, independence from name and gender, corrupted values; run 19: penetration confirmed against the real skin triangles, temple shell edge, braids and locs away from the face, beard line and no gap under the lip | 60 ✅ |
| `test_audio_tone` | Music v3 data (the night song unchanged, the morning song in its spirit, no v2 instruments in music), brightness of the rendered morning song between night and day, synthesizer instruments, loop seams against each file's own sample-to-sample differences, rendered files, apartment ambience, argument voices and tension | 222 ✅ |

"Last known" is the state after run 20 (22 October 2026); all 21 suites pass, plus `--test 7`. The
slider-latency check in `test_character` (limit 4 ms) measures 3.1 ms when run alone, but went over the limit
(4.2 ms) when three test suites ran in parallel on the same machine; run timing tests on their own.

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
