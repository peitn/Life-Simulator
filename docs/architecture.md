# Architecture

Life Simulator is a plain Godot 4.7 project written entirely in GDScript. It has no editor plugins and no
C#. Assets are loaded at runtime (GLB through `GLTFDocument`, WAV through a small loader), so the game runs
the same way headless (dedicated server, tests) as with a window.

## Big picture

```
                 ┌──────────────────────────── main.gd ─────────────────────────────┐
                 │ builds lot (WorldBuilder) · household (SimAgent ×N) · camera · HUD │
                 │ day/night · PsycheFX · NetSession (offline/host/dedicated/client)  │
                 └──────────────────────────────────────────────────────────────────┘
   autoloads:  GameClock (game minutes) · GameSettings (content settings) · AudioManager

   authority (offline game or server)                     clients (multiplayer)
   ┌───────────────────────────────────────────┐          ┌─────────────────────────┐
   │ SimAgent                                  │  public  │ SimPuppet               │
   │  ├─ Needs        ├─ Mood + moodlets       │ ───────▶ │  (no simulation; only   │
   │  ├─ Traits       ├─ Memory                │  sync    │   interpolated public   │
   │  ├─ MentalState  ├─ RelLedger             │          │   state net_*)          │
   │  │   └─ Depression                        │ private  │                         │
   │  └─ UtilityPlanner ◀─ ActionLibrary       │ ───────▶ │ HUD of the owning player│
   │       ◀─ SmartObjects (advertise actions) │   RPC    │                         │
   └───────────────────────────────────────────┘          └─────────────────────────┘
                       │
                       ▼
                  SimVisual (shared by agent and puppet): GLB model, blend shapes, skin shader, animations
```

## Autoloads (`scripts/core/`)

| Autoload | Responsibility |
|---|---|
| `GameClock` | Game time in minutes. Speeds 0–4, days of the week and phases of the day. Emits `time_advanced`, and large steps are split up for stability. Manual stepping is available for tests and the server. |
| `GameSettings` | Content and presentation settings persisted in `user://settings.cfg`: mental health full/muted/off, intrusive-thought intensity, distortion effects, addiction, profanity filter, SH/ED topics (off by default), first-run content warning, crisis lines. |
| `AudioManager` | Audio buses, the music director, layered ambience, 3D object sounds, UI sounds and anxiety audio. See [audio.md](audio.md). |

`grammar_cs.gd` is a helper, not an autoload. It produces Czech past-tense and adjective forms from a
character's chosen **grammatical gender** (`m` / `f` / `n` / `pl`), which is independent of body and
identity.

## Simulation (`scripts/sim/`)

- **`SimAgent`** is one autonomous character. It runs only where there is authority (the offline game or
  the server), driven by `GameClock.time_advanced`. Players issue *commands* to it; NetSession validates
  them in multiplayer.
- **`Needs`** has six needs (hunger, energy, hygiene, fun, social, comfort). 100 means fully satisfied.
  Urgency is quadratic.
- **`Mood`** combines needs, temporary *moodlets* (memories of experiences) and personality into an overall
  mood and 11 emotions. The dominant emotion changes what the character wants to do.
- **`Traits`** covers 15 personality traits, including negative and ambivalent ones (jealous, hot-headed,
  cynic, impulsive, anxious…). Traits affect need decay, preferred actions, mood, social chemistry and
  cravings.
- **`UtilityPlanner`** scores every available action by need relief, the expected emotional payoff, trait
  cravings, emotions, time of day, novelty and distance. It then picks randomly among the best
  candidates, because characters are not robots. `player_only` actions (insult) are never chosen by the
  AI, and `involuntary` states (panic attack) are triggered by the simulation, not the planner.
  Depression changes expectations and initiation cost but never forbids an action.
- **`ActionLibrary`** is the data-driven action catalogue: effects, posture, moodlets, sounds, memory,
  coping id, content tags, initiation effort and more.
- **`SmartObject`** (`scripts/world/`) follows the "smart objects" pattern: furniture advertises actions
  and manages capacity and use points.
- **`MentalState` / `Depression` / `RelLedger`** are pure modules with no nodes. See
  [mental-health.md](mental-health.md) and [relationships.md](relationships.md).
- **`SimPuppet`** is the client-side puppet. It simulates nothing and only interpolates the public state
  it receives from the server.
- **`SimVisual`** is the character visual shared by agent and puppet. It loads the GLB model, applies body
  and face blend shapes, gives each character its own skin shader material, and selects animations by
  speed and posture. It falls back to primitives when no model is available.
- **`HouseholdDynamics`** (`household_dynamics.gd`, run 15) is a pure module owned by `main.gd` and advanced
  from `GameClock.time_advanced` every 10 game minutes, only on the authority. It adds what happens between
  conversations: frictions (noise, bathroom, dishes) with cooldowns and trait irritability, complaints that
  colour the next chat, shared moments, life events and neglect of positive relationships. Randomness goes
  through each character's RNG, so runs are deterministic per seed. It listens to the new
  `SimAgent.conversation` signal for household statistics. See [relationships.md](relationships.md).
- **`fccs_oracle.gd`** is a headless-only **experiment**, enabled with `--test N --fccs`. It uses an
  external FCCS cognitive model as an optional modulator of the conversation outcome. Since run 15 the
  frictions, balancing and mood effects it once prototyped live in the game itself; it is off in the game.

## World (`scripts/world/`)

- **`WorldBuilder`** builds the procedural starting lot: a garden and an open-plan house with cutaway walls,
  kitchen, living room, bedroom and bathroom. The sofa, beds and fridge are Blender models. Everything
  else is still primitives.
- **`DayNight`** handles the sun, moon, sky, morning fog and interior lighting (Forward+ with SDFGI, SSAO,
  SSIL, volumetric fog and AgX tonemapping).
- **`CameraRig`** is a life-sim orbit camera (orbit, zoom, pan with WASD or arrow keys).
- **`PsycheFX`** shows what anxiety feels like (vignette, desaturation, blurred edges, heartbeat pulse) and
  what depression looks like (a grey, darker world). It applies only to the character whose private state
  the player can see, and it respects the distortion settings.

## Character creator back-end (`scripts/character/`)

`CharacterData` is the single source of truth about a character. The schema, validator, codec,
randomizer, history (undo/redo) and the pure appearance functions (`AppearanceResolver`, `BodyMorphs`,
`FaceMorphs`, `SkinModel`, `SkinLayers`) are described in [character-creator.md](character-creator.md).

## Assets (`scripts/assets/`)

| Script | Responsibility |
|---|---|
| `AssetLibrary` | Loads GLBs at runtime, caches them and adds PBR detail by material prefix (`fabric_`, `wood_`, `skin_`, `hair_`, `enamel_`, `eye_`…). |
| `LsxDecoder` | Decodes the LSX transfer format from the Blender bridge. |
| `Subdiv` | Catmull-Clark subdivision, bit-compatible with Blender's. |
| `HeadBuilder` | Builds the procedural head with its facial morphs. |
| `CharacterAssembly` | Joins body and head at import time and transfers morphs to the (fallback) GLB hair. |
| `HairBuilder` | Procedural hair cards, braids, locs, shells, eyebrows and beards on the real head mesh (C4b). |
| `HairRig` | Turns hair geometry into a skinned mesh with transferred blend shapes; one cached mesh per style; threaded first build in the game. |
| `CharacterAnims` | Procedural idle, walk, sit and lie animations on the 17-bone skeleton. |

See [asset-pipeline.md](asset-pipeline.md).

## Networking (`scripts/net/`)

`NetSession` provides an authoritative ENet server with four modes (offline, host, dedicated, client).
`NetProtocol` holds the pure, testable validation functions. See [multiplayer.md](multiplayer.md).

## UI (`scripts/ui/`)

- **`HUD`** shows time and speed and a panel for the selected character: needs, mood, feelings, stress,
  tension, mental state described in words (never numbers), relationships and memories. It also has the
  command menu with coping options, chat and the player roster.
- **`SettingsMenu`** (Esc) holds the content settings, the content warning and crisis help.

## Headless test mode

`godot --headless --path . -- --test N` simulates N game days of the default household. It prints status
snapshots every 4 game hours and a final report per character: actions, minimum needs, mood,
relationships, memories, mental state, coping, depression, grudges and guilt, plus an audio check. It
exits with `TEST OK` or a failure.
