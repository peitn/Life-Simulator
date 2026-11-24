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
- ✅ Lot grid and buy mode, saving the lot (B1).
- 🟡 Build mode: walls with reachability check (B2); characters path around built walls, purchases may not cut off paths, walls may not trap a character (B3); doors and windows cut into walls, passable doors, closing a door may not cut off paths or shut anyone in (B4a). Next: Blender door/window assets, door locks, floors, wallpapers and rooms.
- ⬜ A city with districts, including dangerous ones: bar, gambling hall, pawn shop, therapist and clinic,
  job centre.

## (c) Relationships and NPCs
- ✅ Romantic relationships and breakups (19 Nov 2026, `romance.gd`): dating → partners → ex, per-person satisfaction, rejection, pushy rule, heartbreak, awkward exes, MP consent guard. Next: infidelity and jealousy, gossip about breakups, a HUD status line, a confirmation dialog between players.

- ✅ Relationships with labels, arguments, insults with anti-griefing, confiding, help versus stigma,
  jealousy, grudges and apologies; household dynamics (run 15).
- ✅ Infidelity, suspicion, jealousy and confrontation (20 Nov 2026, `infidelity.gd`): flirt and spark, implied secret dates, being caught, rumours that reach the partner, confess / deny / caught lying / jealous scene, lasting betrayal consequences; breakup news as a rumour; relationship status line in the HUD.
- ✅ Betrayal aftermath (21 Nov 2026, `betrayal_wound.gd`): rumination, withdrawal, self-worth, trust scar and recovery; private to the owner, verified over real ENet.
- 🟨 Rivalry (love/status), slander as a weapon, manipulation with defense ✅ (21 Nov); slander across players (listener's owner decides, victim cap) ✅ (23 Nov); still open: workplace rivalry (needs careers). Gossip, infidelity, break-ups; romance (fade-to-black); support versus
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


- 28 Oct 2026: `test_extreme_fictional_household` watchdog finding closed by sharding (see docs/reviews/extreme-household-sharding-20261028.md); simulation speed unchanged. Next: H3 second-creator preview parity.

- 7 Nov 2026: H3 – asynchronous C5 wardrobe with frame-spread mesh realisation, client visual prewarm, clean server shutdown; the three-process game-path test passes 17/17 (five consecutive runs). Next: rendered preview ↔ spawn parity, then H4 multiplayer reconnect.

- 8 Nov 2026: H3 – rendered preview ↔ spawn parity on the async asset path (Xvfb GPU framebuffer, 78 checks): finished characters are pixel-identical to the editor preview; placeholder clothes never leave missing body regions; the hair-shell placeholder colour now matches the strand cards (was light tan over dark hair). Known: a dress waits as shirt + trousers. Next: H4 multiplayer reconnect/persistence.

- 8 Nov 2026 (evening): H4a – multiplayer reconnect: a dropped player's character waits (game default 120 s) and the player resumes the same character with a one-time, rotated token (server stores only its SHA-256); held characters are not reassigned and count toward the own-character limit; intentional leave is not held; broadcasts skip peers without a live ENet transport (fixes the "max channels: 0" errors). New test_mp_reconnect 72/72. Next: H4b networked host/server persistence (held/owned characters across a server restart), then DTLS.

- 2026-11-09: **H4b server world persistence done** — host/dedicated autosave and restore after restart, players resume with their token, private data stays server-side (`test_h4b_server_persistence` 110/110). Next: DTLS for the transport, multiplayer economy/world systems.


- 2026-11-09 (evening): **(c) relationships — gossip and rumours**: rumours from witnessed events, belief and
  distortion along chains, invented rumours from dishonest characters with grudges, exposure of the source,
  debunking by personal experience, content settings and listener stigma, saved with the household
  (`test_gossip` 106/106). Next: rivalry and manipulation on top of the network, a player command to confront or
  deny a rumour, then DTLS for multiplayer.

- 10 Nov 2026: (c) gossip — confronting the source (admit / deny / escalate) and denying rumours, AI confrontation fix, kind handling of denied panic attacks; test_gossip_confront 97/97.

	- 2026-11-11: **(0) character creation – geometry QA after the realism pass**: the nostril concavities were the cause of
	  the blend-shape error and the folded faces under the nose (fixed, plus a `nose_length × nose_tip_angle` corrective);
	  LOD0 triangle budgets accepted (head 19,000, character 28,500, hairstyle 40,000). Open: crowd LOD. See `docs/reviews/head-realism-regressions-20261111.md`.
	- 2026-11-11 (evening): **(0) eye-socket cap rebuilt** – the conjunctival ring and the posterior cap now use an
	  azimuthal-equidistant map around the eye axis (the latitude/longitude map reversed the azimuth at the deep
	  corners), two rings plus a pole fan; the fornix no longer closes with a blink. `test_head` 44/44, new
	  `test_eye_socket_cap` 14/14. See `docs/reviews/eye-socket-cap-20261111.md`.
	- 2026-11-12: **(0) neck under a lateral bend** – the neck-length ramp now ends below the jaw edge (chin → 1.605 m at
	  the side → base of the skull), fitted hold 13 mm, body-morph band on the neck 12 cm; `test_neck_seam` 60/60 (no
	  flipped triangles for a short neck × ±25° lateral bend, no collar). See `docs/reviews/neck-bend-20261112.md`.
	- 2026-11-12 (evening): **(0)/(e) crowd LOD, step 1** – automatic index LODs for the GLB meshes (borders kept,
	  blend shapes and skinning unchanged; face down to 196 triangles), three detail tiers in `SimVisual` by screen share
	  (expressions at 10 Hz, then hair shell instead of strand cards and a frozen expression), "Detail postav v dálce"
	  setting; `test_character_lod` 76/76. Next: per-style low-poly hair proxy and LODs for strand cards. See
	  `docs/reviews/crowd-lod-20261112.md`.
	- 2026-11-13 (morning): **(0)/(e) crowd LOD, step 2** – per-style hair proxy (1,344-triangle envelope of the
	  strand cards with skin and morphs) replaces the shared GLB helmet in tier 2; silhouette IoU vs. cards 0.914
	  (helmet 0.733), never worse than the helmet. `test_hair_proxy`. Next: LODs for strand cards and procedural
	  parts, blend-shape pruning, GPU/web measurement. See `docs/reviews/hair-proxy-20261113.md`.
	- 2026-11-13 (evening): **(0)/(e) crowd LOD, step 3** – strand cards for tier 1: thinned and widened cards with
	  outline protection, simplified scalp/afro shells, compact mesh with the same skin and blend shapes (all styles
	  327 k → 190 k triangles, silhouette IoU ≥ 0.965); braids and dreads keep full geometry. `test_hair_lod1` 185/185.
	  Next: tube-aware LOD for braids/dreads, brows/beard and procedural parts, blend-shape pruning in tier 2, GPU
	  measurement. See `docs/reviews/hair-lod1-20261113.md`.
	- 2026-11-17 (morning): **(0)/(e) crowd LOD, step 4** – braids, dreads and cornrows in tier 1 drop rings along the
	  strand (Douglas–Peucker, cross-section unchanged, error ≤ min(4 mm, ½ radius)): 23 k → 15 k, 28 k → 14 k,
	  11 k → 4 k triangles; all styles 327 k → 166 k; concurrent builds verified. `test_hair_lod1_tubes` 44/44,
	  `test_hair_lod1` 205/205. Next: brows/beard LOD, blend-shape pruning in tier 2. See
	  `docs/reviews/hair-lod1-tubes-20261117.md`.
	- 2026-11-17 (evening): **(0)/(e) crowd LOD, step 5** – eyebrows and beards in tier 1: about half of the cards,
	  widened by 1/keep, strand random rescaled so the per-character density works identically at every distance
	  (fixes the unaudited fallback version, which made thin brows denser with distance); moustache stays full.
	  `test_facial_lod1`. Next: blend-shape pruning in tier 2, LOD of procedural parts, then rotation to (b) world /
	  (c) relationships. See `docs/reviews/facial-lod1-20261117.md`.

- 18 Nov 2026: crowd LOD step 6 – blend shapes baked into static meshes at tier 2 (worker thread, exact restore). Next: LOD of procedural parts, then rotation to (b) world / (c) relationships.
- 18 Nov 2026 (evening): crowd LOD step 7 – procedural fingers/feet/torso get index LODs and tier-2 baking; fixed wrong GPU normals of these parts (RELATIVE -> NORMALIZED blend shapes). Next: rotation to (b) world / (c) relationships.
- 19 Nov 2026: rotation to (c) relationships – household "cold war": pair-level tension/cold-war states with avoidance, same-room tension and bystander atmosphere, and the risky "clear the air" action (breakthrough / truce / blow-up, diminishing returns for repeated cycles). `test_cold_war` 72/72 + soak. Also: truncated-save recovery tested across two processes. Next: (b) world (lot grid / build-buy) or (c) rivalry and breakups.

- 20 Nov 2026 (evening): **(b) B1 lot grid and buy mode** ✅ – `LotGrid` (0.25 m grid, walls, door corridors, access zones, no access through walls, indoor/outdoor, rugs), 22-item catalogue with price tiers, item quality (sleep/comfort/fun) and appeal (mood), household budget with resale, save section with dry-run validation and refund cap, server-authoritative multiplayer with public snapshots, buy-mode UI (B). `test_lot_buy` 111/111. Next in (b): build mode (walls, doors, floors), Blender assets for catalogue items; then rotation to (c) rivalry/manipulation and betrayal → psyche.
- 21 Nov 2026 (morning): **(c) betrayal aftermath** ✅ – `BetrayalWound` psyche axis: acute pain, trust scar and processing; rumination and intrusive questions, withdrawal and avoidance of the partner who cheated and the affair partner, a self-worth hit scaled by the private self-belief slider (the slider itself never changes), alcohol numbs then rebounds (with tolerance), hypervigilance in the next relationship, reminders (seeing them together, gossip), recovery through confiding, journalling, therapy and accepted apologies. `test_betrayal_wound` 102/102, real two-client ENet privacy test 13/13. Next: rivalry and manipulation, then (b) B2 build mode.
- 21 Nov 2026 (evening): **(c) rivalry and manipulation** ✅ – `Rivalry`: directed love/status rivalries from real sources, server-picked slander through the gossip network with listener defense, exposure and payback, "bury the hatchet", manipulation defense in `SocialPressure`, save v1 (strict + tolerant), server validation, HUD lines. `test_rivalry` 152/152. Next: (b) B2 build mode and Blender catalogue assets.
- 22 Nov 2026 (morning): **(b) B2 walls** ✅ – walls in `LotGrid` v2 (edges of the 0.25 m grid, 0.5–20 m, no overlap/crossing, not through house walls, furniture or access, no sealing off use points – BFS from the street), 240 kr/m with 24 h full refund, save v2 + v1 migration, server authority with its own rate limit, wall nodes with collision, wall tool (T) in the furnishing panel; `test_lot_walls` 128/128. Next: B3 pathfinding + doors.
- 22 Nov 2026 (evening): **(b) B3 navigation around built walls** ✅ – `LotNav` (grid BFS + smoothing, only when a built wall blocks the straight line), unreachable targets abort and are remembered for 2 game hours, walled-in characters escape, purchases/moves are checked for reachability, walls cannot trap a character; `test_lot_nav` 85/85. Next: (c) rotation or B4 doors/windows.
- 24 Nov 2026 (morning): **(b) B4b door locks** ✅ – `LotGrid` format v4 lock per door (unlocked / everybody /
  one character), per-character navigation views, no trapping and no cut-off items for household-wide locks, key
  rules on the server (own character only, abandoned locks can be cleared), relationship and memory consequences
  of being locked out, door lamp, buy-mode buttons. Blender door/window assets remain open.
- 23 Nov 2026 (morning): **(b) B4a doors and windows** ✅ – openings as wall attributes (`LotGrid` format v3), doors passable for the reachability BFS, pathfinder and `LotNav`, windows solid but add appeal, door clearance, closing a door checked like building a wall, save v3 with v2 migration, server-authoritative `open`/`unopen`, wall nodes with frames, glass and a door leaf that swings open near a character, Door/Window tool in buy mode; fixed the reachability BFS so a wall along the lot boundary separates the lot from the street. `test_lot_doors` 147/147.
- 23 Nov 2026 (evening): **(c) slander across players** ✅ – when the listener belongs to another player the AI no longer decides whether they believe it: the impact is deferred and the owner chooses believe / don't believe / tell the victim (default after 12 game hours: half in doubt); at most 3 slanders a day about a player's character; server-validated verdict RPC, owner-only list, HUD commands (`test_slander_cross_player` 97/97).

## Update 24 November 2026 (evening)
- (c) Workplace rivalry ✅ via promotion contests and scheming (K1).
- (g) Legal careers K1 ✅ (five tracks, shifts off the lot, sick days, firing, job search, wages into the household budget). Next in (g): living costs and debt, illegal careers (K2).
