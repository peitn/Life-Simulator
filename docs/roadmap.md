# Roadmap

English version of the live `ROADMAP.md` used by the automated runs, as of 23 October 2026 (after run 23).

Legend: ✅ done · 🟡 in progress · ⬜ planned · ⭐ next step

## (0) Character creator, the current priority

Eight steps, each one complete and tested. Principles and details are in
[character-creator.md](character-creator.md).

| Step | Content | Acceptance |
|---|---|---|
| ✅ **C1** | Data model and networking: `CharacterData` (identity, body, face, skin, hair, eyes, make-up, accessories, outfits per situation, voice, personality, aspirations, story, private predispositions and traumas); schema and catalogues; codec (dict, JSON, share code `LSC1.` with zlib and CRC-32, limits); migration v0→v1; validator (strict for the server, repairing for imports; name filter); randomizer with locks; undo/redo; Czech grammatical gender; deterministic `AppearanceResolver`; multiplayer join with your own character | Round trips and migration, validator fuzzing, appearance determinism, randomizer distribution, locks, undo/redo, hidden sensitive choices, multiplayer join, rejection and privacy |
| ✅ **C2** | Body: one neutral mesh (868-vertex quad control mesh) with 10 shape keys; morphs as deformation fields fitted by least squares; LSX v4 with int8 delta morph targets; Catmull-Clark matching Blender (error 3.6e-7); GLB blend shapes; `BodyMorphs` (height, leg length, head ∝ √height); joints through rest pose and inverse bind | `test_body_morphs` 62/62 |
| ✅ **C3** | Face: procedural `HeadBuilder` (3,890 vertices; eyelids, lips, ears and eyeballs as geometry), 29 morphs plus 3 asymmetry axes, body fat and muscle in the face, 62 blend shapes incl. in-between and corrective shapes, morph transfer to hair, schema v2 | `test_head`, `test_character_v2` |
| ✅ **C3+ A2** (run 13) | Anatomical neck base (C7, trapezius and neck–shoulder point measured against adult proportions) and `body.neck_length` (±15 mm, schema v4 with migration, linear head blend shape, crown height kept, randomizer); `loop_hit` returns the nearest hit | `test_neck_length` (36), `test_neck_seam` (56: seam at neck ±1 × fat/muscle × ±30° bend, linearity, no flips, anatomy, Catmull-Rom invariants); Blender renders inspected |
| ✅ **C3+ A** | Neck and head–body seam: body neck cut above a 16-vertex loop (raised neck base at the back), head neck band fitted to a Catmull-Rom curve through the loop, body blend shapes carried by the head neck, blended bone weights, matched normals, convex quad diagonals in the band | `test_neck_seam` (no gap or overlap at rest, for 12 random bodies and with the neck bent; no flipped triangles; no collar); Blender renders from 5 angles inspected |
| ✅ **C3+ B** (run 18) | Face polish: chin and lower-face projection (11 mm, linear with all morphs), a 30 mm eye opening with the corners leaving the eyeball (inner corner 15 mm from the face midline), fuller lips and a 2 mm wider mouth, a smaller `eye_size` range (no slit at −1), a corrective shape for eye distance × eye depth, head size weakly tied to frame in the randomizer (r ≈ 0.24, independent of gender). The head height turned out to be within the adult range (22.5 cm), so it was not changed | `test_head` 43 (extremes 4.07 mm), `test_skin` 61 (make-up landmarks match the head), `test_character_v2` 43 (head size × frame); Blender renders of 12 faces from 3–4 angles inspected (`docs/images/c3b-face-run18-*.jpg`) |
| ✅ **C4b+** (run 19) | Hair details: finer shell edge at the temples (split triangles, longest edge across the hairline 18 → 8.6 mm), irregular braids and locs that frame the face (≥ 8.5 cm from the midline), a full beard that ends under the jaw, without vertical columns or a gap under the lip; damping of extremes as a soft zone in the editor sliders moves to C6 | `test_hair` 60; Blender render of braids, locs, undercut with full beard, short beard and short hair inspected (`docs/images/c4bp-hair-run19.jpg`) |
| ✅ **Mental health axis 1** (run 20) | `PsycheModel`: personality P (6 axes, optional in schema v5), 9 dispositions D, condition profiles as data with limited, explained modulations and an acyclic coupling graph; only the residual (individuality, explicit personality) drives four MentalState hooks, so nothing is counted twice; values deferred (see [mental-health.md](mental-health.md#psyche-model-axis-1-run-20)) | `test_psyche` 93/93 |
| ✅ **C3++** (run 21) | Facial details and expressions: eyelash cards on the lid margins (34 + 18 per eye), a deeper mouth cavity with 10 + 10 teeth, gums and a tongue, limbal ring and pupil size; schema v6 (`face.lash_*`, `face.teeth_*`, `makeup.mascara`) with migration; expressions as `ex_*` blend shapes (blinks with an in-between shape, smile, frown, raised brows, jaw rotation up to 9°, pupil) transferred to brows, beards and hair; `SimVisual` blinking, emotion-driven expression and speech; slider latency back under 4 ms (caches) | `test_face_detail` 55, full regression of 21 suites; character budget 20,000 triangles; Blender renders of 8 expressions × 4 views and a mouth/lash close-up after fixes (`docs/images/c3pp-*.jpg`). Open: squarish corners of a fully open mouth |
| ✅ **C3++ fixes + C4c** (run 22) | Fixes from the run 21 renders: lens-shaped open mouth with rounded corners (jaw rotation fades towards the corners), Duchenne smile (corners, nasolabial fold, cheeks, lower lids), fuller lips with a Cupid's bow, smoother neck profile with the jaw open (extra bend 50° → 29°), fewer and wider eyelash cards in clumps with a darker root, mouth cavity coloured from the skin. Skin micro detail: pores, skin lines and wrinkles as a derivative-based normal perturbation with LOD, vellus fuzz, zone-based sebum and dryness; schema v7 `skin.type` / `oiliness` / `dryness` with migration | `test_skin_micro` 50, new run 22 shape checks in `test_face_detail`, full regression; Blender renders of expressions and four skin types on light to dark skin (`docs/images/c4c-*.jpg`) |
| ✅ **Household scaling** (23 October, main chat + run 23) | Crowded-household tuning (sensory profile, noise once per cooldown per sleeper, daily patience, soft stress ceiling, alcohol within a 16-hour window, growing panic refractory time, recovery in sleep, emergency sleep). Run 23: a **household matrix** of 4 / 6 / 8 characters × 4 seeds × 30 days with determinism (`test_household_matrix`), `MentalState.stress_sources`, and two fixes it found: crowd stress only while awake, and only bodily needs add stress during sleep | `test_crowded_household` 50/50, `test_household_matrix` (see testing.md) |
| ⭐ next run | **C5 clothing** (categories, cuts that follow body morphs as separate surfaces, PBR, changing clothes by situation, multiplayer replication), rounder corners of the open mouth, small items from run 22. Then an integrated pass (creator → a few days in game). Follow-ups for the matrix: controlled scenarios (support vs. isolation, sleep, stress), more seeds, the distribution of episode length and severity; slider latency (the public snapshot validates again) goes to C6 | clothing follows body morphs, choice by situation, outfit replication |
| ✅ **C4a** | Skin: `SkinModel` (Beer–Lambert with melanin, haemoglobin and carotene), `SkinLayers` (freckles, moles, acne, vitiligo, wrinkles, age spots, scars, tattoos, make-up, eyebrows, stubble), `skin.gdshader` (SSS, rest-pose masks, 8 tattoo motifs, LOD), schema v3 | `test_skin` |
| ✅ **C4b** | Hair, beards and eyebrows as hair cards: 16 hairstyles (cards, braids and locs as tubes, cornrows, shells for buzz cut, undercut and afro, bun, ponytail), 6 eyebrow shapes, 5 beard styles, receding hairline, strand-by-strand greying, dyed hair; morph transfer, shared mesh per style, threaded first build in the game | `test_hair` 55: budgets, no head penetration, face clear, hair lies on chest and back, eyebrow coverage, determinism (also threaded versus synchronous), morphs and bones, SimVisual; Blender render reviewed |
| 🟡 **C5** | Blender-authored meshes via LSX: 11 top styles, 8 bottoms, 7 shoe styles, dress and skin helpers, all 10 body morphs, seven PNG PBR materials. Active outfit selection works from character snapshot. Remaining: animation intersection polish, live commands and multiplayer wardrobe updates. | Test real mesh, texture, bind mapping and eventual live replication |
| ⬜ **C6** | Editor I: in-engine preview, appearance tabs, instant sliders, basic and advanced modes, random with locks, neutral presets, undo/redo, cinematic muted UI, fallback for weak hardware | Slider timing, undo/redo through the UI, locks |
| 🟡 **C7** | Editor II: identity, personality, story, templates, accessibility. ✅ Voice section (27 Oct 2026): pitch/timbre/tempo/roughness with live preview, own synthesized voice in conversations (`test_voice` 86) | Navigation without a mouse, hidden sensitive choices, share code from the UI |
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
  - 🟡 **Expansion, one axis per run** (see [mental-health.md](mental-health.md#plan-one-axis-per-run)):
    1. ✅ a framework of 9 dimensions (run 20);
    2. social anxiety and fear of rejection;
    3. burnout and anxious depression;
    4. OCD;
    5. ADHD/ADD;
    6. bipolar disorder;
    7. autistic traits as profile axes.
  - ⬜ **EmotionPresenter** after C8. Adaptive music layers come earlier, together with axis 1.
- ✅ Grudges, guilt, apologies, reconciliation.
- ✅ **Household dynamics** (run 15): balancing of gains and losses, frictions (noise, bathroom, dishes)
  with cooldowns and trait irritability, complaints as conversation tone, shared moments, life events,
  mood of both (±20 pp), de-escalation, soft stress ceiling for arguments, drift and neglect, memory text
  by direction. Fixes the "cold war": 32 % arguments over 16 seeds × 14 days, relationships differ by
  personality. See [relationships.md](relationships.md#household-dynamics-household_dynamicsgd).
- ⬜ Skills, ownership ("my bed"), habits and routines; pathfinding with NavigationServer3D.

## (b) World, building, buying

- 🟡 Procedural starting lot.
- ⬜ Lot grid, build and buy mode, saving the lot.
- ⬜ A city with districts, including dangerous ones: bar, gambling hall, pawn shop, therapist and clinic,
  job centre.

## (c) Relationships and NPCs

- ✅ Relationships with labels, arguments, insults with anti-griefing, confiding, help versus stigma,
  jealousy, grudges and apologies; household dynamics (run 15).
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
- ✅ Basic facial expressions and blinking as blend shapes (run 21).
- ⬜ More assets and the city; gestures; foot IK; clothing by situation;
  cinematic post-processing.

## (f) Audio

- ✅ Custom synthesizer, 5 songs, ambience, 3D object sounds, UI sounds, melancholy by mood, anxiety
  low-pass and heartbeat.
- ✅ Apartment ambience, tension layer, wordless raised voices in arguments, door slams (design v2).
- ✅ Music design v3 (run 17): the original songs are back, the night song sets the tone, a new morning song
  in its spirit.
- ⬜ Surge stems by tension, footsteps; door slams tied to argument intensity and temperament.

## (g) UI, saving, economy, stories

- ✅ HUD, content settings, content warning, crisis help.
- 🟡 Offline save/load + 5-minute real-time autosave, game-day autosave, auto-resume, previous-save backup/recovery and manual slots; server persistence and multi-version migrations pending.
- ⬜ Legal and illegal careers; an economy with debt, enforcement and poverty.
- ⬜ Emergent stories with lasting consequences; a character diary.
- ⬜ Later blocks proposed in the room, not scheduled yet: a fictional currency with integer amounts, a
  ledger with a hash chain, loans, taxes and enforcement as processes; a social-protection model; values and
  worldview (layer V of the psyche model) once something consumes them.

## Web version

A separate JavaScript port of the core rules with a pure DOM and CSS interface (no canvas or WebGL),
playable on phones, is hosted at <https://lifesim.peiti.workers.dev/>. The GDScript rules in this
repository remain the source of truth. The web port's source is not part of this repository yet.
