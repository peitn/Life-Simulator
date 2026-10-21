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
| `test_player_commands` | Command queue, interruption, cancelling sleep, insult and its consequences, NetSession command validation, `player_only` actions | 40 ✅ |
| `test_psyche_presentation` | PsycheFX, low-pass music, heartbeat, distortion settings, HUD in words, thoughts | 19 ✅ |
| `test_net_protocol` | Sanitising, unique names, validation, rate limit, speed votes | 34 ✅ |
| `test_multiplayer` | Dedicated server plus clients in one process (separate `SceneMultiplayer` branches): spawn, sync, privacy, commands, chat, late join | 67 ✅ |
| `test_character` | C1: schema and defaults, round trips (dict, JSON, share code, file, Resource), migration, validator fuzzing, name filter, randomizer distribution and locks, undo/redo, hidden sensitive choices, grammar | 157 ✅ |
| `test_character_v2` | Schema v2 and review findings: `repaired()` contract, fatal inputs, 128-bit uid assigned by the server, Unicode name corpus, crown precision | 39 ✅ |
| `test_character_net` | Multiplayer join with your own character, strict validation, public snapshot replication, privacy, determinism across peers | 28 ✅ |
| `test_body_morphs` | C2: Catmull-Clark versus Blender, LSX v4 morphs, GLB blend shapes, data → weights, bones and scales, normals, CPU skinning, performance | 62 ✅ |
| `test_head` | C3: every face field has a visible morph, weights match the data, in-between and corrective shapes, symmetry, determinism, no skin–eye or lip intersections across extreme combinations, no folded faces, GLB and SimVisual, server and client weights identical | 43 ✅ |
| `test_neck_seam` | C3+: head–body seam on the real GLB: a single closed loop, no gap or overlap at rest, for random bodies and with the neck bent (CPU skinning), bone weights, normals and flipped triangles, neck width, no collar under body morphs | 32 ✅ |
| `test_skin` | C4a: SkinModel continuity, spectrum, saturation and hue over 1,386 combinations, determinism, layer placement on the surface, shader compiles, CUSTOM0 holds the rest pose | 60 ✅ |
| `test_assets` | LSX format (CRC, corrupted data), sources ↔ manifest ↔ GLB, furniture dimensions, orientation, winding and PBR, character skeleton, skin weights and variants, animations, SimVisual, primitive fallback | 150 ✅ |

"Last known" is the state after run 12 (21 October 2026); all suites pass. The slider-latency check in
`test_character` (limit 4 ms) can exceed the limit when several suites run at the same time on the server.

## Quality gate for every change

The automated development runs follow this gate (see [development-process.md](development-process.md)):

1. Self-review of every changed file.
2. `godot_check` over the whole project, plus the relevant tests and a regression of all existing tests.
3. An independent code audit by a second model (Gemini), with justified fixes or rebuttals.
4. Results logged in `AUDIT.md` and `DEVLOG.md`.
