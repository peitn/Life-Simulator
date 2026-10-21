# Roadmap

English version of the live `ROADMAP.md` used by the automated runs, as of 21 October 2026.

Legend: ✅ done · 🟡 in progress · ⬜ planned · ⭐ next step

## (0) Character creator, the current priority

Eight steps, each one complete and tested. Principles and details are in
[character-creator.md](character-creator.md).

| Step | Content | Acceptance |
|---|---|---|
| ✅ **C1** | Data model and networking: `CharacterData` (identity, body, face, skin, hair, eyes, make-up, accessories, outfits per situation, voice, personality, aspirations, story, private predispositions and traumas); schema and catalogues; codec (dict, JSON, share code `LSC1.` with zlib and CRC-32, limits); migration v0→v1; validator (strict for the server, repairing for imports; name filter); randomizer with locks; undo/redo; Czech grammatical gender; deterministic `AppearanceResolver`; multiplayer join with your own character | Round trips and migration, validator fuzzing, appearance determinism, randomizer distribution, locks, undo/redo, hidden sensitive choices, multiplayer join, rejection and privacy |
| ✅ **C2** | Body: one neutral mesh (868-vertex quad control mesh) with 10 shape keys; morphs as deformation fields fitted by least squares; LSX v4 with int8 delta morph targets; Catmull-Clark matching Blender (error 3.6e-7); GLB blend shapes; `BodyMorphs` (height, leg length, head ∝ √height); joints through rest pose and inverse bind | `test_body_morphs` 62/62 |
| ✅ **C3** | Face: procedural `HeadBuilder` (3,890 vertices; eyelids, lips, ears and eyeballs as geometry), 29 morphs plus 3 asymmetry axes, body fat and muscle in the face, 62 blend shapes incl. in-between and corrective shapes, morph transfer to hair, schema v2 | `test_head`, `test_character_v2` |
| 🟡 **C3+** | Head polish after the Blender render review: shared neck topology between head and body (no seam), correct neck length and width with a chin–neck angle, lips with volume and corners, eye size and opening, fixes for nose extremes and the light patch under the nose, damping of extremes in the editor | Rendered from several angles and inspected; no visible seam; seam stable under morphs and head rotation |
| ✅ **C4a** | Skin: `SkinModel` (Beer–Lambert with melanin, haemoglobin and carotene), `SkinLayers` (freckles, moles, acne, vitiligo, wrinkles, age spots, scars, tattoos, make-up, eyebrows, stubble), `skin.gdshader` (SSS, rest-pose masks, 8 tattoo motifs, LOD), schema v3 | `test_skin` |
| ⭐ **C4b** | Hair, beards and eyebrows as geometry (hair cards; shells only as a distant LOD): short, long, curly, afro, braids, cornrows, locs, bun, ponytail, bald, receding hairline, greying | Every hairstyle in the schema has a mesh, follows skull morphs, uses pigment colours and stays within the triangle budget |
| ⬜ **C5** | Clothing: everyday, work, formal, sleepwear, sport. Cuts independent of the body (morph transfer), PBR materials, changing by situation | Clothing follows body morphs, selection by situation, multiplayer replication |
| ⬜ **C6** | Editor I: in-engine preview, appearance tabs, instant sliders, basic and advanced modes, random with locks, neutral presets, undo/redo, cinematic muted UI, fallback for weak hardware | Slider timing, undo/redo through the UI, locks |
| ⬜ **C7** | Editor II: identity, personality, story, templates, accessibility | Navigation without a mouse, hidden sensitive choices, share code from the UI |
| ⬜ **C8** | Integration and audit: menu → editor → game, changing clothes in game, performance, sensitivity and input audit | End-to-end join test, spawn privacy, determinism across peers |

## (a) Simulation core

- ✅ GameClock, six needs, stress, 15 traits including negative ones, mood with 11 emotions and moodlets,
  utility AI, player commands, headless tests.
- ⬜ More traits: manipulative, cowardly, narcissistic traits (never as a diagnosis).
- 🟡 **Mental health**:
  - ✅ Done: three-component anxiety, involuntary panic attacks with no lock-out, 7 coping strategies
    with trade-offs, exposure, intrusive thoughts, witnesses, depression (wanting, liking, vigour,
    burden).
  - ⬜ Therapy and clinic, medication with side effects.
  - ⬜ Stigma of depression.
  - ⬜ Traumas and PTSD.
  - ⬜ Personality disorders.
  - ⬜ Self-harm and eating disorders, only through emotions and consequences, hidden by default.
  - ⬜ Dialogue with narrowed choices.
  - ⬜ **Expansion, one axis per run** (see [mental-health.md](mental-health.md#plan-one-axis-per-run)):
    1. a framework of 9 dimensions;
    2. social anxiety and fear of rejection;
    3. burnout and anxious depression;
    4. OCD;
    5. ADHD/ADD;
    6. bipolar disorder;
    7. autistic traits as profile axes.
  - ⬜ **EmotionPresenter** after C8. Adaptive music layers come earlier, together with axis 1.
- ✅ Grudges, guilt, apologies, reconciliation.
- ⬜ Fix the household "cold war": move balancing, shared moments, drift, frictions, mood and random
  events from the FCCS experiments into the game, with a 10-seed test. Also fix the memory text that says
  "relationship got worse" when it improved.
- ⬜ Skills, ownership ("my bed"), habits and routines; pathfinding with NavigationServer3D.

## (b) World, building, buying

- 🟡 Procedural starting lot.
- ⬜ Lot grid, build and buy mode, saving the lot.
- ⬜ A city with districts, including dangerous ones: bar, gambling hall, pawn shop, therapist and clinic,
  job centre.

## (c) Relationships and NPCs

- ✅ Relationships with labels, arguments, insults with anti-griefing, confiding, help versus stigma,
  jealousy, grudges and apologies.
- ⬜ Rivalry, manipulation, gossip, infidelity, break-ups; romance (fade-to-black); support versus
  toxicity.
- ⬜ Worldview and identity in context after C8: several opinion axes and "who knows what about whom", with
  optional coming out.
- ⬜ Neighbour NPCs; the FCCS brain for long-term goals and dialogue.

## (d) Multiplayer

- ✅ Authoritative ENet server, protocol v3, private state, validation, rate limits, server-owned time with
  voting and emergency pause, chat, roster, spectator, late join.
- ⬜ Lobby, a household per player, saving server state, reconnect.
- ⬜ WebSocket for the web, packet limits, latency tests.
- ⬜ PvP opt-out, showing server content settings to clients.

## (e) Visuals

- ✅ Forward+, SDFGI, SSAO, SSIL, volumetric fog, AgX, day/night, PsycheFX, Blender bridge, Blender
  character and furniture, grey depression filter.
- ⬜ More assets and the city; facial expressions and gestures; foot IK; clothing by situation;
  cinematic post-processing.

## (f) Audio

- ✅ Custom synthesizer, 5 songs, ambience, 3D object sounds, UI sounds, melancholy by mood, anxiety
  low-pass and heartbeat.
- ⬜ Surge stems by tension, footsteps, doors, raised voices, apartment ambience.

## (g) UI, saving, economy, stories

- ✅ HUD, content settings, content warning, crisis help.
- ⬜ Save and load.
- ⬜ Legal and illegal careers; an economy with debt, enforcement and poverty.
- ⬜ Emergent stories with lasting consequences; a character diary.

## Web version

A separate JavaScript port of the core rules with a pure DOM and CSS interface (no canvas or WebGL),
playable on phones, is hosted at <https://lifesim.peiti.workers.dev/>. The GDScript rules in this
repository remain the source of truth. The web port's source is not part of this repository yet.
