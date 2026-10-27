# Life Simulator – Roadmap

Working title: **Life Simulator** (final name later).

**Goal:** the most realistic adult life sim possible, with multiplayer, in Godot 4.7 (Forward+).
- **Tone:** raw, believable life including its dark sides: conflicts, breakups, infidelity, debt, addictions with
  real consequences, petty crime, illness and death, black humour, profanity.
- **Limits:** intimacy only implied / fade-to-black; nothing involving minors in adult themes; no glorification of
  violence.
- **Mental health:** a deep, sensitively handled system (inspired by Hellblade, Celeste, Disco Elysium).

> Note: this roadmap reflects the plan up to run 23 (23 October 2026). Current work order and status are in
> [docs/implementation-sequence.md](docs/implementation-sequence.md) and `CHECKPOINT.md`.

Legend: ✅ done · 🟡 in progress · ⬜ planned · ⭐ next step

## (0) CHARACTER CREATION – current priority (split into 8 runs, each complete and tested)

Principles (including ChatGPT's comments, message 38):
- **CharacterData is the single source of truth** (appearance, identity, personality, history). It is versioned and
  migrated.
- Appearance is an explicit attribute, **never derived from the name**.
- Body, identity, pronouns, orientation, voice and clothing are **independent axes**:
  - no "race" option and no ethnic archetypes;
  - no coupling of sex ↔ height ↔ hair ↔ voice ↔ clothing;
  - no link from identity to personality or diagnosis.
- Data is normalised (0..1 / −1..1) or in physical units (cm, years), and the UI has soft limits.
- Characters are 18+.
- Sensitive options (traumas, predispositions) appear only according to the content settings. Leaving them empty
  means default, and they are never a bonus or penalty for a particular identity.
- Czech grammar:
  - Grammatical gender (on/ona/ono/oni) is a separate choice, and verb forms are generated from it.
  - ono/oni are opt-in only, and the editor shows a sentence preview (`Grammar.preview`).
  - A "neutral paraphrase" mode (no gendered participle) comes in C7 (ChatGPT review 49).

| Run | Contents | Acceptance tests |
|---|---|---|
| ✅ **C1** (run 7) | **Data model and network**:<br>• `CharacterData` v1: identity, body, face, skin, hair, eyes, make-up, accessories, clothing by situation, voice, personality, aspirations, backstory, private predispositions and traumas.<br>• Catalogues and ranges (`character_schema.gd`).<br>• Codec: dictionary, JSON file, share code `LSC1.` with zlib + CRC-32, limits.<br>• Migration v0 → v1 (old household: sex/colour → explicit attributes).<br>• Validator: strict for the server, repairing for import; name filter for control/bidi/invisible characters, lengths and scripts.<br>• Sensible random generator with locks, undo/redo history, Czech grammatical gender, deterministic `AppearanceResolver`.<br>• Integration: household from CharacterData; SimVisual from appearance (no longer from a hash of the name); MP: the client sends its character code in hello, the server validates it, the public snapshot is replicated and private data goes only to the owner. | Round-trip and migration, validator fuzzing, appearance determinism, generator distribution, locks, undo/redo, hiding of sensitive options, MP join with own character + rejection of invalid data + privacy |
| ✅ **C2** (run 8) | **Body**:<br>• One neutral mesh (868-vertex quad control mesh) with 10 shape keys: linear frame/shoulders/chest/bust/waist/hips (weight −1..1 around the default) + asymmetric muscle/fat pairs.<br>• Morphs are deformation fields over a node tree, computed on the fine mesh and transferred by least squares.<br>• **LSX v4**: int8 delta-coded morph targets, quad part + per-face material, limits; v3 stays readable.<br>• Import: Catmull-Clark (= Blender, error 3.6e-7) + normals for every morph → GLB with blend shapes (NORMALIZED).<br>• `BodyMorphs`: data → weights; crown height = height_cm; leg length by thigh scaling; head ∝ √height.<br>• SimVisual: blend shapes; shoulder/hip joints through rest + inverse bind (no double offset). | test_body_morphs 62/62: blend shape values = data, height/legs/head, budget (character 10,800 tris), normals after morphing, CPU skinning, v3 compatibility, corrupted data, performance 0.11 ms |
| ✅ **C3** (run 9; visually run 10b, with reservations) | **Face**:<br>• Procedural head (`HeadBuilder`, fixed topology of 3,890 vertices): skull; eyelids and lips as real geometry; ears with helix and concha; eyeballs with cornea.<br>• 29 morphs + **3 asymmetry axes** (eyes / nose and mouth / jaw), plus body fat and muscle in the face.<br>• 62 blend shapes: linear, ±, **in-betweens** for nose length, **corrective shapes** nose×bridge and nose×tip.<br>• Hair takes over skull morphs by transfer; the body neck is narrowed under the head neck.<br>• `FaceMorphs` (data → weights), SimVisual.<br>• **Schema v2** (head_size, hidden flag on scars/tattoos, dimple 0..1) with migration v1→v2.<br>• ChatGPT review 48/49: snapshot allowlist, 128-bit uid assigned by the server, `repaired()` never {}, Unicode XID, [ ] in texts, crown precision. | test_head 43/43 (blend × exact shape typically ≤ 1.2 mm, 48 extreme combinations without skin–eye or lip penetration, 0 folded faces, symmetry, server×client determinism, 0.17 ms), test_character_v2 39/39 (corpus of 42 names, crown over 6,405 combinations ≤ 0.0013 mm) |
| 🟡 **C4a** (run 10) | **Skin**:<br>• SkinModel: Beer–Lambert melanin/haemoglobin/carotene, one continuous function.<br>• SkinLayers: freckles, moles, acne with post-inflammatory pigmentation, vitiligo; wrinkles and age spots from age + weathering; scars and tattoos at calibrated surface points; make-up, eyebrows, stubble.<br>• `skin.gdshader`: SSS, masks in rest coordinates (CUSTOM0), 8 tattoo motifs, LOD.<br>• Schema v3 `skin.detail_seed` + migration.<br>• C3 follow-up: in-betweens/quantisation by test; rasterised sheet `res://previews/c3_face_sheet.png` (awaiting human review). | test_skin 57/57: continuity, spectrum, saturation/hue over 1,386 combinations, determinism across the network, position on the surface, shader compiles, CUSTOM0 = rest |
| ✅ **C3+ A** (runs 11–12) | **Neck and head–body seam**:<br>• The body neck is cut above a loop (16 vertices; neck base raised at the back – trapezius, C7).<br>• The head's neck band is fitted onto a Catmull-Rom curve through the loop.<br>• Body blend shapes on the head neck: the seam follows fat, muscles, shoulders and morphs of the whole neck tube.<br>• Bone weights blended with the body, normals matched to the body, convex diagonals in the band. | test_neck_seam 32/32: no hole or penetration in the base, for 12 random bodies or when bending the neck; 0 inverted triangles; no collar. Blender render 8 characters × 5 views inspected by eye (docs/images/c3-neck-seam-run12-*.jpg) |
| ✅ **C3+ A2** (run 13) | **Neck – anatomy and length**:<br>• Neck base and trapezius raised by a direction-dependent field (front 4 / sides 30 / back 46 mm), based on GLB measurements against anthropometry (C7 0.868 H, neck–shoulder point, jugulum 0.82 H).<br>• Slider `body.neck_length` −1..1 (±15 mm ≈ ±16 % of the front neck) as the linear head blend shape `b_neck_len`: a ramp from the seam to the chin/occiput; eyes, mouth and hair move with the head; the seam edge does not move.<br>• Schema **v4** + migration v3→v4; crown still = height_cm; randomiser N(0; 0.3).<br>• Robust `loop_hit` (review #111). | test_neck_length 36/36, test_neck_seam 56/56 (seam at ±1 × fat/muscle × bend ±30°, linearity, 0 flips, anatomy, Catmull-Rom); Blender render 6 characters × 5 views inspected (docs/images/c3-neck-length-run13-*.jpg) |
| ✅ **C3+ B** (run 18) | **Face polish**:<br>• Chin and sub-lip projection 11 mm (weight from the default head → linear with morphs).<br>• Eye opening 30 mm with the corners outside the eyeball (inner corner 15 mm from the centre, lacrimal lake).<br>• Fuller lips and a 2 mm wider mouth.<br>• Smaller eye_size range (−1 is no longer a slit); corrective shape for eye distance × depth.<br>• Generator: head size weakly correlated with frame (r ≈ 0.24, independent of gender).<br>• Head height measured at 22.5 cm = within norm (unchanged). | test_head 43/43 (extremes 4.07 mm), test_skin 61/61 (make-up = head), test_character_v2 43/43; Blender render 12 faces × 3–4 views inspected (docs/images/c3b-face-run18-*.jpg) |
| ✅ **C4b+** (run 19) | **Hair detail**:<br>• Shell edge at the temples: triangles split along the line, longest edge 18 → 8.6 mm.<br>• Irregular braids and dreadlocks that frame the face (≥ 8.5 cm from the centre).<br>• A full beard ends under the jaw, with no columns and no gap under the lip.<br>• The soft zone for slider extremes moved to the C6 editor. | test_hair 60/60; Blender render of braids, dreadlocks, undercut with full beard, goatee and short hair inspected (docs/images/c4bp-hair-run19.jpg) |
| ✅ **Psyche axis 1** (run 20) | `PsycheModel` (scripts/psyche/):<br>• Personality P: 6 HEXACO-like axes, optionally in schema **v5** `personality.hexaco`, otherwise derived from traits.<br>• 9 dispositions D.<br>• Anxiety and depression profiles as data (`data/conditions/*.json`; legacy numbers unchanged).<br>• Modulations add/mul/threshold/couple with limits and a "why", an acyclic coupling graph, `explain()`.<br>• Only the **residual** D − D_legacy goes into MentalState's 4 hooks (individuality from `personality.psyche_seed`, given personality, future profiles), so nothing is counted twice.<br>• Values/worldview (V) postponed until they have a consumer. | test_psyche 93/93 (agency, diversity of 5 characters, context, stability 16 × 14 days, content off/muted, schema v5, bit-identical neutral regression) |
| ✅ **C3++** (run 21, finished after a crash) | **Face detail and expressions**:<br>• Eyelashes as cards on the eyelid rims (34 + 18 per eye; they follow morphs and blinking; after the render they point forward and curl).<br>• Deeper mouth cavity; 10 + 10 teeth on arches (incisors to premolars; molars at the back are not visible); gums, tongue, limbus and pupils.<br>• Schema **v6** (`face.lash_length/lash_density/lash_curl/teeth_shade/teeth_gap/teeth_crooked`, `makeup.mascara`) + migration v5→v6. Generator: age only shifts the mean; independent of gender.<br>• Expressions `ex_*` as blend shapes: blink L/R with an in-between; smile (after the render: corners up and back); frown; brows; jaw rotation about the joint up to 9°; pupils. Transferred to brows/beard/hair.<br>• SimVisual: expression by emotion (≤ 0.6); blinking every 2–6 s scaled by emotion, 12 % double; jaw while speaking; a resting face computes nothing.<br>• Slider performance: cache of face fields, face weights and blend shape names; only changes are written. | test_face_detail 55/55, regression of 21 suites (test_character slider 3.68 ms under host load ~50), character budget 20,000 tris (19,260); Blender render 8 expressions × 4 views + mouth and lash detail after the fix (docs/images/c3pp-*.jpg). Open: angular corners of the open mouth |
| ✅ **C3++ fixes + C4c** (run 22, requested by the owner) | **Fixes from the run 21 render**:<br>• Open mouth as a lens with rounded corners: jaw rotation fades towards the corners, lips narrow and the upper lip rises.<br>• Duchenne smile: corners higher and wider, nasolabial fold, cheeks, lower eyelids.<br>• Lip volume with Cupid's bow and philtrum.<br>• Neck profile with the jaw open (bend 50° → 29°).<br>• Lashes as 24 + 13 wider cards in clumps with a darker root; mouth cavity from skin colour.<br>**Skin micro detail (C4c)**:<br>• Pores, skin lines and wrinkles as a normal perturbation from derivatives, with LOD.<br>• Vellus hair on the silhouette.<br>• Sebum and dryness by zone (clearcoat, flakes).<br>• Schema **v7** `skin.type/oiliness/dryness` + migration, validator, randomiser (independent of gender and tone), public snapshot. | test_skin_micro 50/50, new shape checks in test_face_detail, regression of all suites; Blender render of expressions and 4 skin types on light to dark skin |
| ✅ **Household scaling** (main chat 23 Oct + run 23) | Full-household tuning from the main chat (#161):<br>• SensoryProfile; noise friction once per cooldown per sleeper; daily patience.<br>• Soft stress ceiling; alcohol in a 16 h window; growing refractory time for panic attacks; recovery during sleep; emergency sleep.<br>Run 23:<br>• **Stress matrix** 4/6/8 characters × 4 seeds × 30 days + determinism (`test_household_matrix`).<br>• `MentalState.stress_sources`.<br>• Fixes found by the matrix: crowding only while awake; during sleep only bodily needs cause stress (hunger ×0.5). | test_crowded_household 50/50, test_household_matrix (see AUDIT run 23), simulation regression |
| ⭐ next run | **C5 clothing**: categories, cuts that follow body morphs as their own surfaces, PBR, changing clothes by situation, MP replication.<br>• Also: round the corners of the open mouth; small items from run 22 (finer grid under the chin, gap between the upper central incisors).<br>• Then an integrated playthrough (creation → a few days in game).<br>• Follow-up work on the matrix (#164): controlled scenarios (support × isolation, sleep, stress), more seeds, distribution of episode length/severity.<br>• Slider performance (public_snapshot re-validates) → C6. | Clothing follows body morphs, selection by situation, MP replication of the outfit |
| ✅ **C4b** (runs 14, 16, 17) | **Hair, beards and eyebrows as cards**:<br>• `HairBuilder`: 16 hairstyles — strand cards with flow/parting, curls and waves, braid and dreadlock tubes, cornrows, shells for buzz cut/undercut/afro, bun, ponytail. Collisions with the head and torso; tilting over the shoulders only above them. 6 eyebrow shapes; 5 beard styles in zones.<br>• `HairRig`: transfer of head and body morphs (K=4), bones from the skin, shared mesh per hairstyle, **threaded building** in game.<br>• `hair.gdshader`: strands in UV, grey hairs strand by strand, receding hairline and crown thinning via CUSTOM0, anisotropy, alpha scissor.<br>• `AppearanceResolver.hair_look`: natural colour, dyeing only the scalp hair.<br>• SimVisual: cards instead of a "helmet", with a helmet fallback. Export for Blender: `tools/hair_export.gd`. | test_hair 55/55: budgets, no penetration into the head, face kept clear, hair rests on the chest and back, eyebrow coverage, determinism thread × synchronous, neck and skull morphs on hair, bones, SimVisual, independence from gender/name, corrupted data. Blender render 8 characters × 5 views + face detail inspected (3 rounds of fixes) |
| 🟡 C5 | **Clothing**:<br>• Categories casual/work/formal/sleep/sport.<br>• Cuts independent of the body (body morphs transferred to clothing).<br>• Colours and materials (PBR).<br>• Changing clothes by situation in game. | Clothing follows body morphs, selection by situation, MP replication of the outfit |
| ⬜ C6 | **Editor I – preview and appearance**:<br>• Editor scene in the real engine: rotation, zoom (full body/face), lights day/night/interior, poses and animations.<br>• Tabs Body/Face/Skin/Hair/Clothing; sliders with instant feedback; BASIC / ADVANCED mode.<br>• Random character with locks; presets (neutral shapes, no ethnic ones); undo/redo.<br>• Cinematic UI in a muted palette; fallback for weak hardware. | Slider application time (performance), undo/redo through the UI, locks during randomisation |
| 🟡 C7 | **Editor II – who this is**:<br>• Identity: name, nickname, pronouns and gender, identity, orientation, ✅ voice (27 Oct 2026: VoiceSynth formant synthesis, Voice section with live async preview in creator and editor, own voice in conversations; test_voice 86).<br>• Personality: traits with points and conflicts, aspirations.<br>• Backstory: family, childhood, past jobs; optional traumas and predispositions with an explanation of their effects, only according to the content settings.<br>• Templates (file + short code).<br>• **Accessibility**: keyboard/gamepad without having to hit small sliders, UI scaling, readable typography, screen-reader labels. | Navigation without a mouse, sensitive options hidden when the topics are off, share code from the UI |
| ⬜ C8 | **Integration and audit**:<br>• Menu → editor → game (offline and MP join with own character).<br>• Changing clothes in game; performance.<br>• Gemini audit of sensitivity (stereotypes, inclusivity) and input safety; ChatGPT review. | E2E game-entry test, spawn privacy test, determinism across peers |

## (a) Simulation core
- ✅ GameClock: game minutes, speeds 0–4, days of the week, phases of the day, stepping for tests/server.
- ✅ Needs: hunger, energy, hygiene, fun, social, comfort (quadratic urgency, weights).
- ✅ **Stress** (MentalState):
  - accumulates from unmet needs, arguments, insults, stigma, jealousy and crowding;
  - is relieved by sleep, calm, support and coping;
  - increases the risk of arguments.
- ✅ Personality traits (15), including negative/ambivalent ones: Jealous, Hot-tempered, Cynic, Impulsive, Anxious.
  - ⬜ more: manipulative, lazy towards others, cowardly, narcissistic traits (not as a diagnosis).
- ✅ Mood and 11 emotions (Anxious is new), moodlets, trait cravings, moodlets from mental state.
- ✅ Utility AI planner. The AI does not choose `player_only` and `involuntary` actions; content tags respect the
  settings.
- ✅ Player commands: queue (max 3), overrides only AI decisions, cancellation, waking up with the "Groggy" moodlet.
- ✅ Headless tests (`--test N`, `res://tests/*.tscn` with a watchdog).
- 🟡 **Mental health** – the basis is done (Day 4; depression after ChatGPT review 39: habituation without a cap,
  shared relief budget, robust loading):
  - ✅ **Anxiety** as 3 components (perceived threat / bodily arousal / trigger sensitivity), plus regulation, support,
    manageability, and good and bad days. Diagnosis = predisposition with severity (anxiety disorder).
  - ✅ **Panic attack** as an involuntary symptom. The player is not locked out: breathing and confiding work even
    during an attack and even with a full queue.
  - ✅ **7 coping strategies** with trade-offs and habituation: breathing, walk, journal, confide, doomscrolling,
    hiding, and a beer for the nerves (with tolerance and a morning rebound). Non-dominance is tested across contexts.
  - ✅ **Exposure** as an experience, not a guaranteed reward; the path to recovery is never closed.
  - ✅ **Intrusive thoughts** (private, always "a thought, not a fact"); anxious interpretation of conversations.
  - ✅ **Witnesses**: help (shortens the attack, strengthens the relationship) vs. stigma (hurts, the relationship
    drops).
  - ✅ **Depression** (Day 6, `depression.gd`):
    - burden (days–weeks), plus separate *wanting* (learned expectation with pessimism), *liking* (experienced joy) and
      *vigour* (initiation barrier × effort of the action), and learning from the gap between expectation and
      experience;
    - behavioural activation with habituation (spamming does not cure it), contact, support, sleep;
    - an episode only after it has lasted; a weak trace afterwards (relapse); endogenous dips with predisposition;
      morning worsening only as an individual pattern;
    - the player's command is never refused, only "can't get going" (cancellable);
    - the emotion Downcast, depressive thoughts without SI content, a grey filter in PsycheFX.
  - ⬜ Therapy/clinic, medication with side effects (follows (b) the city); stigma of depression among witnesses.
  - ⬜ Traumas and long-term memory (triggers tied to places/people, avoidance, flashbacks as intrusive thoughts) → PTSD.
  - ⬜ Bipolar disorder, OCD, ADHD, personality disorders (not as villain templates).
  - ⬜ Eating disorders and self-harm **only** through emotions, relationships and consequences: no methods, no playable
    actions, no numbers as goals; hidden by default (setting `sh_ed_topics`). Suicide is not a playable action.
  - ⬜ Dialogues with narrowed choices under anxiety/depression (choices visible, but "hard").
  - 🟡 **Expansion plan (peiti #79, ChatGPT #83, Grok #85)**: (1) ✅ run 20. One axis = one run, inserted between C4–C8:
    1. a shared framework of 9 interpretable dimensions: threat sensitivity, social threat, impulsivity, regulatory
       capacity, need for predictability, sensory sensitivity, energy with a baseline, reward from activities, cognitive
       flexibility; modulations with limits and a description of what/by how much/why;
    2. social anxiety + fear of rejection/abandonment;
    3. burnout + anxious depression;
    4. OCD;
    5. ADHD/ADD;
    6. bipolar disorder;
    7. autistic traits as profile axes.

    Every step: agency tests, a full/muted/off switch, a diversity test.
  - ⬜ **EmotionPresenter** (ChatGPT #86) after C8: pose, facial expression, breathing, micro-actions and adaptive music
    layers (stems, silence as a state, anti-repetition, a relief motif). Music layers come earlier, together with axis 1.
- ✅ Grudges, guilt, apology and reconciliation (Day 6, `rel_ledger.gd`); time heals only without a live grudge.
- ✅ **Household dynamics** (run 15, `household_dynamics.gd` + SimAgent):
  - balance of gains and losses (argument ×0.6, repeated conversation ×0.7);
  - frictions (noise at night, bathroom, dishes only after real cooking) with cooldowns and trait irritability;
  - a complaint as the tone of an approach;
  - shared moments (cooldown, braked by a grudge, none with a grudge > 60);
  - random life events; the mood of both ±20 pp; de-escalation;
  - a soft stress ceiling from arguments (hot-tempered 65); drift of negative relationships; neglect of positive ones;
  - memories by the direction of change.

  Test 16 seeds × 14 days: arguments 32 % ± 10 pp, relationships differ by personality, stress > 85 ~0 %.
- ⬜ Household dynamics, further: in MP, opt-out from being a friction target (PvP); spatial filtering of pairs for
  large lots; more kinds of friction (money, shopping, cleaning) once there is an economy; a "how things are at home"
  statistic in the HUD.
- ⬜ Skills, ownership (my bed), habits and routines.
- ⬜ Pathfinding (NavigationServer3D) instead of straight-line walking.

## (b) World, building, buying
- 🟡 Procedural starter lot (house with cutaway walls, kitchen, living room, bedroom, bathroom, garden).
- ⬜ Lot grid, build and buy mode, lot saving.
- ⬜ City with districts (including more dangerous ones), bar, gambling hall, pawnshop, therapist/clinic, job centre.

## (c) Relationships and NPCs
- ✅ Relationships −100..100 with labels, conversation with a risk of an argument (now also stress and temper), memory.
- ✅ Insult with lasting consequences, protection against griefing.
- ✅ Confiding (listens vs. dismisses), help during an attack, stigma, jealousy (at most once per 4 h per rival).
- ✅ Grudges:
  - a grudge slows warming;
  - an apology has sincerity derived from behaviour (repeated/broken apologies);
  - outcomes are acceptance / "we'll see" / refusal; spam and apologies "for nothing" interrupt nobody;
  - the AI apologises out of guilt (the pride of the Grump/Cynic dampens it, cooldown 12 h).
- ⬜ Rivalry, manipulation, gossip, infidelity, breakups; romance (fade-to-black); support vs. toxicity.
- ⬜ **Worldview and identity in context** (ChatGPT #89–91), after C8:
  - (A) more opinion axes (value, certainty, importance; no real parties and no "good/bad opinion" rating);
  - (B) "who knows what": an information-sharing graph, coming out as an optional process, reactions based on opinions,
    the relationship and personality.

  Discrimination is not inevitable, and LGBT+ life is shown in its joy too.
- ⬜ NPC neighbours; FCCS brain (mcp npc_*) for long-term goals and dialogue.

## (d) Multiplayer
- ✅ Authoritative server (ENet): offline / host / dedicated / client. Protocol v3: own character in hello, strict
  validation, despawn after leaving.
- ✅ Spawner + Synchronizer (public state only); private state including **mental state and thoughts** only to the
  owner.
- ✅ Diagnoses are not sent in spawn data. The server rejects `involuntary` actions, content forbidden by the server
  settings, and help for a character without an attack.
- ✅ Input validation, rate limit, hello timeout, visibility filter, `server_relay` disabled, chat sanitisation.
- ✅ Time from the server, speed voting + emergency pause; chat, roster, spectator, late join.
- ⬜ Lobby/menu, handing over characters, a household of one's own for everyone; saving server state, reconnect (token).
- ⬜ WebSocket for the web; packet size limit; a test with latency/packet loss (not only within one process).
- ⬜ PvP conflict opt-out; showing the server's content settings to clients on join.

## (e) Visuals
- ✅ Forward+, SDFGI, SSAO, SSIL, volumetric fog, AgX, day cycle, lamps.
- ✅ **PsycheFX**: vignetting, desaturation, blurred edges and a pulse in time with the heartbeat during anxiety (own
  character; can be turned off or muted).
- ✅ **Blender bridge** (Day 5):
  - scripts in `tools/blender/`;
  - a compact transfer format LSX with CRC;
  - import into GLB (`tools/import_lsx.gd`);
  - runtime loading + PBR detail by material (`scripts/assets/asset_library.gd`).
- ✅ Character from Blender:
  - since C2, one neutral body mesh with 10 shape keys (LSX v4 → Catmull-Clark → GLB blend shapes);
  - head, eyes, 2 hairstyles (v3); a 17-bone skeleton with heat weights;
  - procedural idle/walk/sit/lie animations; appearance from CharacterData.
- ✅ Furniture from Blender: sofa (cushions, decorative pillow), double bed (upholstered headboard, duvet), single bed,
  fridge (handles, notes on the door). Other objects are still primitives.
- ⬜ More assets: stove, TV, bookcase, shower, treadmill, table and chairs, doors/windows, trees; the city.
- 🟡 Facial expressions:
  - ✅ basic expressions and blinking as blend shapes (C3++, run 21);
  - ⬜ gestures (argument, crying, laughing), foot IK, sit/stand transitions, clothing by situation.
- ⬜ Export: include `assets/models/*.glb` in the export, or switch to imported scenes.
- 🟡 Depression visuals: grey filter (PsycheFX `grey`) ✅; ⬜ heavier camera, cinematic post-processing.
- ✅ Appearance from CharacterData instead of a hash of the name (C1); ⬜ explicit teleport flag (ChatGPT review,
  message 30).

## (f) Sound and music
- ✅ Own synthesiser, 5 tracks, ambience, 3D object sounds, UI sounds, melancholy by mood.
- ✅ **Music v3** (run 17, the owner's decision):
  - the original tracks are back;
  - "Noční ticho" (Night silence) is the model for the game's tone, and the new "Mlhavé ráno" (Misty morning) is in its
    spirit;
  - v2 (parallel chat) brought apartment ambience, a tension layer and wordless argument voices (these stay).
- ⬜ Door slams by argument intensity and personality (ChatGPT #127).
- ✅ Anxiety in sound: low-pass on the music by level, heartbeat 70→140 BPM (generated at runtime).
- ⬜ Transfer of Surge renders from Audio Engine (the connector works: Surge, 3,008 patches), stems by tension,
  footsteps, doors, arguments (raised voices), apartment ambience.

## (g) UI, saving, economy, stories
- ✅ HUD:
  - time, speed;
  - character panel (+ stress, tension, mental state, predispositions);
  - intrusive thoughts;
  - command menu (coping, confide, go and calm someone down; difficulty under anxiety);
  - chat, players.
- ✅ **Content settings** (Esc):
  - mental health full/muted/off, thought intensity, distortion;
  - addictions, profanity censoring, SH/ED;
  - an opening content warning;
  - crisis help (116 123, findahelpline.com, 112/155).
- ⬜ Saving/loading the game (MentalState already has to_dict/from_dict).
- ⬜ Legal and illegal careers, economy with debt, enforcement, poverty (stressors for MentalState).
- ⬜ Emergent stories with lasting consequences, a character diary.
- ⬜ Proposals from the room (to be scheduled after C8, no implementation yet):
  - an economy with its own currency in whole units, a ledger with a hash chain, loans/taxes/enforcement as processes
    (ChatGPT #139);
  - social protection based on SFPZ v0.4 (#142);
  - values and worldview (layer V of the psyche model), once they have a consumer.
