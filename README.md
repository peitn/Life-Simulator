# Life Simulator

> **Working title.** The final name is still undecided.

Life Simulator is a realistic, **adult** life simulation with multiplayer, built in **Godot 4.7** (Forward+).
It is not a family-friendly dollhouse. Characters live a raw, believable life: arguments and break-ups,
debt, addiction with real consequences, petty crime, morally grey choices, illness, dark humour and swearing.
Intimacy happens only by implication (fade-to-black). Nothing involving minors appears in adult themes.

Its defining system is a **deep, carefully handled model of mental health**, inspired by *Hellblade*,
*Celeste* and *Disco Elysium*. It covers stress, a three-component anxiety model with panic attacks,
depression built on separate *wanting*, *liking* and *vigour*, intrusive thoughts and coping strategies
with trade-offs. Every sensitive theme can be muted or switched off, and crisis resources are always one
click away.

> ⚠️ **Content warning.** The game depicts mental illness, addiction, conflict and other difficult themes.
> If you are struggling, please reach out: **116 123** (Czech Republic, free, non-stop) or
> **[findahelpline.com](https://findahelpline.com)** (international).

---

## Status

The project is in **active early development**. It is built in small, fully tested steps by an
automated development process (see [Development process](docs/development-process.md)).

| Area | State |
|---|---|
| Simulation core: needs, mood, 15 traits, utility AI, player commands | ✅ playable |
| Mental health: stress, anxiety, panic, depression, coping, intrusive thoughts | ✅ base done, 🟡 expanding |
| Relationships: grudges, guilt, apologies, reconciliation, jealousy | ✅ |
| Multiplayer: authoritative ENet server, private state, validation | ✅ |
| Character creator: data model (C1), body (C2), face (C3), skin (C4a) | ✅ C1–C3 (neck, seam, neck length done), ✅ C4a |
| Character creator: hair (C4b), clothing (C5), editor UI (C6–C7), integration (C8) | ⬜ planned |
| Visuals: Blender asset pipeline, day/night cycle, PsycheFX | ✅ |
| Audio: custom synthesizer, 5 songs, ambience, 3D object sounds, anxiety audio | ✅ |
| City, careers, economy, save games | ⬜ planned |

The full plan is in [docs/roadmap.md](docs/roadmap.md).

## Quick start

Requirements: **Godot 4.7** (standard build; GDScript only, no C#).

```bash
git clone https://github.com/peitn/Life-Simulator.git
cd Life-Simulator

# 1. Generate the audio. WAV files are not stored in git: they are rendered by the game's own synthesizer.
godot --headless -s res://tools/build_audio.gd

# 2. Open the project in the editor, or run it directly
godot --path .
```

### Launch options

Pass these after `--` on the command line, for example `godot --path . -- --host`.

| Option | Meaning |
|---|---|
| *(none)* | Offline single player. You control the whole household. |
| `--host [port]` | Listen server: simulate and play at the same time. |
| `--server [port]` | Dedicated headless server. |
| `--join <address[:port]>` | Join a server as a client. The default port is `24565`. |
| `--name <name>` | Player name shown to others. |
| `--character <code>` | Join with your own character (an `LSC1.` share code from the character creator). |
| `--test <days>` | Headless simulation of N game days, with a report. |

## Running the tests

Every system has an automated test in `tests/`. Each test is a scene that exits with code 0 on success.

```bash
godot --headless --path . res://tests/test_mental_health.tscn
godot --headless --path . res://tests/test_character.tscn
# ...see docs/testing.md for the full list

# Long-run simulation check (14 game days)
godot --headless --path . -- --test 14
```

## Documentation

| Document | Contents |
|---|---|
| [Vision & content policy](docs/vision.md) | Tone, design pillars, what the game does and does not depict |
| [Architecture](docs/architecture.md) | Autoloads, simulation loop, agents, planner, scenes, folder layout |
| [Character creator](docs/character-creator.md) | Data model, schema, validation, body, face and skin systems, C1–C8 plan |
| [Mental health](docs/mental-health.md) | Stress, anxiety, panic, depression, coping, safety rules, content settings |
| [Relationships](docs/relationships.md) | Social interactions, grudges, guilt, apologies, the "cold war" issue |
| [Multiplayer](docs/multiplayer.md) | Authoritative server, protocol, privacy, validation, rate limits |
| [Asset pipeline](docs/asset-pipeline.md) | Blender bridge, LSX format, GLB import, visual verification |
| [Audio](docs/audio.md) | Synthesizer, music, ambience, anxiety audio, building the WAVs |
| [Testing](docs/testing.md) | Test suite, how to run it, what each test covers |
| [Roadmap](docs/roadmap.md) | Done, in progress and planned work |
| [Development process](docs/development-process.md) | Automated runs, checkpoints, review by multiple AIs, audits |

## Repository layout

```
main.gd / main.tscn     Main scene: builds the lot, household, camera, HUD; network session; headless test
scripts/core/           Autoloads: GameClock, GameSettings (content settings), Czech grammar helper
scripts/sim/            Simulation: agents, needs, mood, traits, utility AI, mental state, depression, relationships
scripts/character/      Character creator back-end: data, schema, validator, codec, randomizer, morphs, skin
scripts/assets/         Runtime asset library, LSX decoder, procedural head, character assembly, animations
scripts/net/            Multiplayer session and protocol validation
scripts/audio/          Synthesizer, music data, sound recipes, AudioManager
scripts/world/          World builder, smart objects, camera, day/night, PsycheFX
scripts/ui/             HUD, settings menu (content settings, crisis help)
shaders/                Skin shader (subsurface scattering, procedural skin layers)
assets/src/             Source meshes from Blender in the LSX transfer format
assets/models/          Imported GLB models and manifest
audio/                  Rendered music and SFX (generated, not in git)
tools/                  Build tools: audio render, LSX import, preview rasterizer, Blender scripts
tests/                  Automated tests (one scene per system)
DEVLOG.md, AUDIT.md,    Working journals of the automated development runs (currently in Czech)
ROADMAP.md, CHECKPOINT.md
```

## Language

- Documentation, repository metadata and commit messages are in **English**.
- The game's player-facing text is in **Czech**, and so are most code comments. The Czech grammar system
  generates verb and adjective forms from each character's chosen grammatical gender.
- `DEVLOG.md`, `AUDIT.md`, `ROADMAP.md` and `CHECKPOINT.md` in the root are the live working journals of
  the automated development runs and stay in Czech for now. [docs/roadmap.md](docs/roadmap.md) is the
  maintained English version of the roadmap.
- Translating the code comments and adding an English localisation of the game are planned.

## License

No license has been chosen yet. Until one is added, all rights are reserved by the author.
