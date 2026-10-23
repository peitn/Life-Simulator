# Character creator

The character creator is the **current top priority** of development. It is built in eight steps
(C1–C8). Each step is a complete, tested unit.

## Principles

- **`CharacterData` is the single source of truth.** It holds appearance, identity, personality and
  history. It is versioned, serialisable and migrated from older versions.
- **Appearance is explicit.** It is never derived from the name; before C1, colours came from a hash of
  the name.
- **Independent axes.** Body, grammatical gender, gender identity, sexual orientation, voice and clothing
  never derive from each other. Every hairstyle and outfit is available to every body and identity.
- **No "race" presets and no ethnic archetypes.** Skin is a continuous physical model (melanin, undertone,
  blood perfusion), and so are hair and eye colour.
- **Adults only.** All characters are 18+.
- **Sensitive private data** (mental-health predispositions, traumas) carries a content tag and respects
  the content settings. Empty means the default, with no predisposition. A choice is never a bonus or a
  penalty for any identity.
- Data is normalised (0..1 / −1..1) or in physical units (cm, years). The UI gets soft limits.

## Data model

| Script | Responsibility |
|---|---|
| `character_schema.gd` | The **only** description of fields, ranges, defaults and catalogues. The validator, randomizer, migrations and the future editor's sliders are all generated from it. Field types: `f`, `i`, `b`, `e` (enum), `set`, `name`, `text`, `color`. |
| `character_data.gd` | The Resource: `to_dict` / `set_from_dict`, `public_snapshot()` (an allowlist from the schema) and `private_part()`. |
| `character_validator.gd` | `strict` mode for the server (any bad field rejects the data) and `repair` mode for imports (clamp, drop unknowns, fall back to defaults). Details below. |
| `character_codec.gd` | Canonical JSON for template files, the share code `LSC1.<base64url(zlib(JSON))>.<crc32>`, and migrations v0 → v1 → v2 → v3 → v4 → v5 → v6 → v7. Every external input goes through size limits → CRC → JSON → migration → validator. |
| `character_randomizer.gd` | A random character "with a sensible distribution, not chaos". Appearance is sampled independently of identity and gender. Supports attribute locks. |
| `character_history.gd` | Undo/redo over whole canonical dictionaries (a few kB each). Slider drags merge into one step. |

The validator also:
- filters names: control, bidi and invisible characters, lengths, scripts, at most 3 combining marks
  (against "zalgo" text);
- rounds numbers to 3 decimals, so appearance is deterministic across peers;
- never returns empty data. A fatal input yields safe defaults with `fatal = true`.

Schema history:
- **v2** adds three facial asymmetry axes, `body.head_size`, `hidden` scars/tattoos and a chin dimple
  0..1.
- **v3** adds `skin.detail_seed`, the explicit placement of freckles, moles, scars and tattoos, controlled
  by a "re-roll placement" button and never taken from the name.
- **v4** (run 13) adds `body.neck_length` (−1..1, default 0). Migration v3 → v4 fills in 0 and changes
  nothing else. 0 means the corrected default neck described below.
- **v5** (run 20) adds two private personality fields: `personality.hexaco` (an optional dictionary of six
  HEXACO-like axes, −1..1; a missing axis is derived from the traits) and `personality.psyche_seed`
  (0..65535, the character's individuality in the psyche model, never taken from the name). Migration
  v4 → v5 sets `hexaco` to `{}` (behaviour unchanged) and derives the seed once from the random uid. Both
  fields are excluded from the public snapshot. See [mental-health.md](mental-health.md#psyche-model-axis-1-run-20).
- **v6** (run 21) adds facial details (`face.lash_*`, `face.teeth_*`) and `makeup.mascara`, see below.
- **v7** (run 22) adds the skin type: `skin.type`, `skin.oiliness`, `skin.dryness` (public, migration v6 → v7 fills in a
  normal skin), see [Skin micro detail and skin type](#skin-micro-detail-and-skin-type-c4c-run-22).

### Neck length and neck base (run 13)

The default neck was measured on the exported GLB (model height H = 1.78 m) against adult anthropometric
ratios. The suprasternal notch (jugulum, ≈ 0.82 H) was already right, but the seventh cervical vertebra
(C7, ≈ 0.868 H ≈ 1.546 m) sat at about 1.51–1.52 m and the neck–shoulder point (≈ 1.50 m) at 1.47 m, so the
trapezius and the back of the neck base were 2.5–4 cm too low. That is why the head seemed to sit high above
the shoulders, mostly in profile and from behind. `CharacterAssembly.lift_neck_base` now raises the body's
neck base with a direction-dependent field: 4 mm at the front, 30 mm at the sides and 46 mm at the back
(a smooth monotonic function of the angle), fading out towards the shoulders (radius 0.07 → 0.22 m) and down
the upper back (1.26 → 1.45 m). The same field is applied to the base mesh, all body blend shapes and the
clothing, so clothes still fit. After the change: C7 1.545 m, neck–shoulder point 1.503 m, chin 1.557 m,
front neck (chin to jugulum) 9.1 cm = 0.41 of the head height.

`body.neck_length` moves the whole head above the neck by ±15 mm (about ±16 % of the front neck). It is a
single linear blend shape of the head, `b_neck_len`: a vertical shift times a ramp that is 0 in the fully
fitted seam band (loop height in that direction + 2 cm) and 1 below the chin at the front and at the base
of the skull at the back. Eyes, mouth and ears move with the head; hair gets the key through morph transfer.
The seam edge does not move, so the seam tests hold for ±1 combined with fat, muscle and a bent neck.
`BodyMorphs.scales()` includes the shift, so the crown still lands exactly on `height_cm`. The value goes
`BodyMorphs.head_links()` → `FaceMorphs.weights()` (signed link) → the head's blend shape. A blend shape
was chosen over moving the head bone because the neck below the chin has mixed head/neck bone weights, so
a bone translation would drag the underside of the chin. The randomizer draws N(0, 0.3) clipped to ±0.8,
independent of gender, grammar and identity.

Czech grammar: the grammatical gender (on / ona / ono / oni) is its own choice, and verb forms are
generated from it. Neuter and plural are opt-in. The editor previews sentences (`Grammar.preview`), and a
"neutral wording" mode is planned for C7.

### Face polish (C3+ B, run 18)

A Blender render of 12 faces (default, 4 random, both extremes, asymmetry, large and small eyes and lips,
heavy, muscular) showed three problems with the default head, measured on the procedural surface:
- **receding chin**: the soft-tissue chin sat about 20 mm behind the lower lip (adults: 5–10 mm, with a
  4–6 mm fold under the lip), so the mouth hung over a retreating chin and the face ran into the neck;
- **small eyes**: the eyelids were wrapped around the eyeball, so the opening measured about 21 mm in a
  front view and the inner corner sat 20 mm from the face midline (adults: 28–30 mm and about 16 mm);
- **thin lips**: about 5 mm of upper and 8.5 mm of lower vermilion, with little forward volume.

Changes in `head_builder.gd`:
- `jaw_projection_u()` moves the chin and the area under the lip forward along z only (11 mm at the chin,
  fading faster towards the neck than towards the lips, narrowing to the sides, front surface only). The
  weight is taken from the position of the *default* head on the same ray, so every vertex gets a constant
  offset whatever the morphs are, and the blend shapes stay linear. `surface_xy()` corrects its target x
  and y, because the surface is no longer purely radial.
- Eyes: the eye opening is longer (`W`), its nasal half is 14 % longer than the temporal half, and past
  50° around the eyeball the eyelid rings leave the sphere along a curve that turns from the tangent towards
  a shallow direction (nasal) or a deeper one (temporal). The eyelid margin now spans 15.3–45.5 mm from the
  midline (30 mm). The `eye_size` range is smaller, so −1 is no longer a slit.
- Lips and mouth: fuller vermilion (about 7.5 and 10 mm), more forward volume, a 2 mm wider mouth and
  deeper corners.
- `face_morphs.gd` adds a corrective shape for `eye_distance` × `eye_depth` (wide-set, protruding eyes
  interacted by 2.9 mm). The worst blend-shape error over extreme combinations is 4.07 mm (limit 5 mm).

The head height was measured at 22.5 cm crown–chin, inside the adult range (about 21.9 cm for women and
23.2 cm for men on average), so it was not changed. The impression of a small head on a heavy build is
addressed in the randomizer instead: `head_size` now has a mean of 0.6 × (frame − 0.5), a weak link
(r ≈ 0.24 over 800 characters) that stays independent of gender, identity and name. `SkinLayers` make-up
landmarks (`EYE_SHAPE`, `MOUTH`) and the chin scar/tattoo spot follow the new head; `test_skin` checks the
landmarks against `HeadBuilder`.

Damping of extremes as a soft zone at the slider ends belongs to the editor UI (C6); at the data level the
`eye_size` range was reduced, which was the main cause of the "sunken" all −1 face.

### Facial details and expressions (C3++, run 21)

Schema **v6** adds six public fields to the `face` group and one to `makeup` (migration v5 → v6 fills in defaults, so
a migrated character looks the same):

| Field | Range (default) | Effect |
|---|---|---|
| `lash_length`, `lash_density`, `lash_curl` | 0..1 (0.5) | Eyelash cards: length, how many cards are shortened or widened, how strongly they curl |
| `teeth_shade` | 0..1 (0.25) | Enamel colour only (no geometry) |
| `teeth_gap` | 0..1 (0) | Gap between the upper central incisors |
| `teeth_crooked` | 0..1 (0) | Slightly rotated and displaced lateral incisors and canines; no caricature at 1 |
| `makeup.mascara` | 0..1 (0) | Longer and denser lashes on top of the fields above |

Geometry, all built by `HeadBuilder` from the same vertex recipes as the rest of the head, so details and expressions
are exact blend shapes:
- **Eyelashes**: 34 upper and 18 lower cards per eye, rooted on the eyelid margin, so they follow every eye morph, hooded
  lids and blinking. Lengths follow real proportions (about 8–12 mm upper, 5–7 mm lower, longest in the middle). After
  the run-21 render they leave the lid mostly forwards and only then curl up (they used to point up like a fan).
- **Mouth**: a deeper cavity, 10 upper and 10 lower teeth (incisors to premolars; molars would not be visible) on elliptical arches, gums and a tongue. The teeth sit behind
  the lips at rest (tested).
- **Eyes**: a darker limbal ring around the iris and a pupil-size blend shape (`ex_pupil`).

**Expressions** are blend shapes named `ex_*`: `ex_blink_l`, `ex_blink_r` (with an in-between shape at 0.5, because the
lid travels over the eyeball, not along a chord), `ex_smile` (mouth corners up and back, cheeks raised, lower lid raised
slightly), `ex_frown`, `ex_brow_up`, `ex_jaw_open` (the lower jaw, lower teeth, lip and tongue rotate around the jaw
hinge, up to 9°) and `ex_pupil`. Eyebrows, beards and hair receive the expression shapes by the same transfer as
other skull morphs. Expressions are **not character data**: they are client-side presentation and are never
replicated.

`SimVisual` drives them: a gentle target per dominant emotion (never above 0.6, never a grimace), blinking every
2–6 s divided by an emotion-dependent rate (anxiety blinks faster, tiredness slower) with 12 % double blinks, and a jaw
movement while a speech bubble is shown. Each character's blink timing is staggered with a local seed; peers do not
need to agree on it. When the face is at rest, nothing is recomputed or written.

Budget: the character is now about 19,300 triangles (lashes about 730, mouth parts about 1,600), so the asset test
limit went from 18,000 to 20,000. Renders: `docs/images/c3pp-expressions-run21-before.jpg` (8 expressions × 4 views,
before the smile and lash fixes) and `docs/images/c3pp-mouth-lashes-run21-after.jpg`. Known issue: a fully open mouth
still has squarish corners.

### Mouth, smile and lip fixes (run 22)

The run 21 renders showed four problems, fixed in `HeadBuilder`:

- **Open mouth.** The jaw rotation used to move every lower-lip vertex by the same angle, so the side columns of the lip
  rings formed a vertical edge and the opening was a rectangle with sharp corners. The rotation weight now fades towards
  the corners as `(1 − a²)^0.55` (`mouth_taper`, `a` = position along the mouth, ±1 at the corners) on the lips, the
  cavity cap and the skin next to the mouth line. The opening is a lens with rounded ends; when the mouth opens the lips
  narrow by 6 % and the upper lip lifts by up to 0.9 mm. The cavity is no longer black: `SimVisual` derives the mucosa
  colour from the skin colour (the same rule for every skin tone).
- **Smile.** The corners move further up (7.4 mm), out (5.8 mm) and back. A nasolabial fold (`nasolabial()`: a segment
  from the nose wing to a point about 10 mm outside and below the corner) pushes the cheek forward on its outer side
  with a shallow groove along it, the cheeks rise, and the lower lids rise more (Duchenne smile). The frown pulls the
  corners down further (1.9 mm).
- **Lips.** More volume (upper 5.2 mm, lower 6.2 mm forward at the default), a deeper Cupid's bow with two peaks under
  the philtrum columns (the columns now diverge towards the peaks), a fuller lower lip with two soft "pillows", and a
  sharper vermilion border (0.7 mm roll).
- **Neck in profile.** Under the chin the jaw weight now falls off with depth (chin 1, throat about 0), and the
  vertical ramp is longer, ending 2 mm above the seam band (the neck below 1.52 m never moves). The extra bend under the
  chin with the jaw fully open went from about 50° to 29° (`previews/diag/jaw_profile.gd`, checked in
  `test_face_detail`). The remaining bend comes from the coarse lattice under the chin (one quad spans the submental
  area); a finer lattice there is a candidate for later.
- **Eyelashes.** 24 + 13 wider cards per eye instead of 34 + 18 thin ones. Neighbouring cards lean towards each other at
  the tip (clumps), the curl is stronger, the length variation smaller, and the root is darker (vertex colour 0.45 at the
  lid, 1.0 at the tip, multiplied with the lash colour).

### Skin micro detail and skin type (C4c, run 22)

Schema **v7** adds three public fields to `skin` (migration v6 → v7 fills in a "normal" skin):

| Field | Range | Default | Meaning |
|---|---|---|---|
| `type` | `normal` / `dry` / `combination` / `oily` | `normal` | *where* sebum and dryness show: T-zone (forehead, nose, chin) versus cheeks and body |
| `oiliness` | 0..1 | 0.35 | sebum: shine, a thin clear-coat film, larger pores |
| `dryness` | 0..1 | 0.25 | matte surface, more visible skin lines; very dry skin gets fine flakes |

Choosing a type in the editor sets typical values (`Schema.SKIN_TYPE_PRESETS`); both strengths stay independently
adjustable. The type is independent of gender, identity, skin tone and name. Sebum decreases with age (from about 45),
dryness increases (from about 50) and skin weathering adds dryness and micro relief.

`SkinLayers.micro()` turns this into shader parameters (quantized, identical on every peer): sebum and dryness per zone
(`oil_t`, `oil_c`, `dry_t`, `dry_c`; a combination skin has an oily T-zone and drier cheeks), pore size, micro-relief
strength and the vellus colour (the natural hair colour, lightened; dyeing the head hair does not change it).

`skin.gdshader`:
- **Roughness and specular by zone** replace the fixed "T-zone −0.08" of C4a. The default normal skin stays close to the
  old look (T-zone −0.065). Sebum also raises specular and adds a thin clear-coat film.
- **Pores** (one pit per cell of about 0.75 mm, finer on the eyelids, denser on the nose and cheeks), **skin lines**
  (ridged noise) and the **age wrinkles** perturb the normal through screen-space derivatives (no tangents or textures,
  positions in the rest pose `CUSTOM0`, so the detail stays put under morphs and animation). The detail switches off
  when a pore is smaller than a pixel (`fwidth`) or the character is far away, so it does not shimmer. `micro_bump = 0`
  disables it (quality setting).
- **Very dry skin** gets small flakes and a slight ashy cast. That is a real effect that shows more on darker skin; it
  does not change the skin tone model.
- **Vellus hair** is a faint fuzz at the silhouette (rim light plus a Fresnel mix towards the vellus colour), almost
  invisible with light hair.
- None of the micro-detail code reads the melanin or the other chromophores, so it behaves the same on every skin tone
  (`test_skin_micro` checks this in the shader source).

`tests/test_skin_micro.gd` covers the schema, migration, strict server validation with fuzzing, the zones per type, age,
quantization, determinism through the share code, independence from tone, gender and name, the randomizer
distribution (normal 35 %, combination 30 %, dry 18 %, oily 17 %, adjusted for age) and locks, the public snapshot, the
shader (parameters, compilation, the roughness formula against a CPU mirror, LOD) and performance.

Visual check (run 23, Blender approximation of the shader, `docs/images/c4c-skin-types-run22.jpg` and
`docs/images/c4c-expressions-run22-final.jpg`): normal, dry and combination skin read as intended; very dry skin shows
sparse flakes in small groups. The oily type looked wet across the whole cheek, so its cheek sebum factor went from 0.8
to 0.55 (the T-zone stays at 1.0). The Blender material is an approximation and looks glossier than the game shader.

## Appearance pipeline

```
CharacterData ──public_snapshot()──▶ AppearanceResolver (pure, deterministic)
                                       ├─ BodyMorphs  → body blend-shape weights, height, leg length, head scale
                                       ├─ FaceMorphs  → face blend-shape weights (incl. body fat/muscle in the face)
                                       ├─ SkinModel   → skin colour from chromophores (Beer–Lambert)
                                       └─ SkinLayers  → parameters for skin.gdshader
                                                         │
                                       SimVisual applies them to character.glb (same on server and every client)
```

Every function in this chain is pure and deterministic. Server and clients compute bit-identical results
from the same snapshot.

## Steps

| Step | Content | State |
|---|---|---|
| **C1** | Data model, schema, codec and share code, migration v0→v1, validator with name filter, randomizer with locks, undo/redo, Czech grammar, deterministic `AppearanceResolver`, multiplayer join with your own character | ✅ |
| **C2** | Body: one gender-neutral control mesh (868 vertices, quads) with 10 shape keys (frame, shoulders, chest, bust, waist, hips, plus muscle and fat pairs), LSX v4 with morph targets, Catmull-Clark matching Blender, GLB blend shapes, `BodyMorphs` | ✅ |
| **C3** | Face: procedural `HeadBuilder` (fixed topology of 3,890 vertices; eyelids, lips and ears as real geometry; eyeballs with cornea), 29 morphs plus 3 asymmetry axes, 62+ blend shapes incl. in-between and corrective shapes, morph transfer to hair, schema v2 | ✅ (visual check in Blender) |
| **C3+** | A: neck and head–body seam (fitted band, body morphs on the head neck, blended skinning); A2: anatomical neck base and `body.neck_length` (schema v4); B: chin projection, eye opening, lips, head size in the randomizer (see "Face polish" below) | ✅ A (run 12), ✅ A2 (run 13), ✅ B (run 18) |
| **C4a** | Skin: `SkinModel` (two-layer Beer–Lambert with melanin, haemoglobin and carotene) and `SkinLayers` (freckles, moles, acne with post-inflammatory pigmentation, vitiligo, wrinkles and age spots, scars, tattoos, make-up, eyebrows, stubble). `skin.gdshader` adds SSS and masks in rest-pose coordinates (CUSTOM0), so the details follow morphs. Schema v3. | ✅ |
| **C4b** | Hair, beards and eyebrows as hair cards (see "Hair" below): 16 hairstyles, 6 eyebrow shapes, 5 beard styles, receding hairline, greying strand by strand, dyed hair | ✅ (runs 14, 16, 17) |
| **C5** | Clothing: everyday, work, formal, sleepwear and sport. Cuts follow body morphs. Changing clothes in game, replicated in multiplayer. | ⬜ |
| **C6** | Editor I: an in-engine 3D preview (rotate, zoom to face, day/night/interior light, poses), tabs for body, face, skin, hair and clothing, instant sliders, basic and advanced modes, random character with locks, neutral presets, undo/redo | ⬜ |
| **C7** | Editor II: identity (name, nickname, pronouns and grammatical gender, identity, orientation, voice preview), personality (traits with a point budget and conflicts, aspirations), story (family, childhood, past jobs, optional traumas and predispositions only when content settings allow), templates. Accessibility: keyboard and gamepad without fiddly sliders, UI scaling, readable typography, screen-reader labels. | ⬜ |
| **C8** | Integration: menu → editor → game (offline and multiplayer join), changing clothes in game, performance, sensitivity and input-safety audit | ⬜ |

## Hair (C4b)

Hair, eyebrows and beards are built procedurally in Godot on top of the real head mesh from `character.glb`:
- `HairBuilder` builds the geometry for a style: cards (ribbons with strands drawn by the shader) that follow
  a flow (parting, whorl, swept back, pulled), with curls and waves; tubes for box braids and locs; cornrows;
  shells for buzz cuts, undercut sides and the afro; a bun and a ponytail. Strands collide with a radial map
  of the head and a cylindrical map of the torso, lean forward or back only above the shoulders, and lose
  the momentum from the root below the middle of the head, so long hair lies on the chest and back.
  Eyebrows (6 shapes, the same as the painted base layer in the skin shader) and beards (5 styles in zones)
  are projected exactly onto the skin triangles.
- The geometry depends only on the style (fixed seed per style), never on the character, name or gender,
  so every peer builds the same mesh. Receding hairline, crown thinning, greying and eyebrow/beard density
  are vertex attributes (CUSTOM0) plus shader uniforms, so one shared mesh serves every character with
  that style.
- `HairRig` turns the geometry into a mesh that behaves like part of the body: blend shapes transferred
  from the nearest skin vertices (head width and height, forehead, neck length, body fat and muscle for hair
  on the back), bone weights from the skin, one cached mesh per style. In the game the first build of a
  style (0.25–1 s) runs on a `WorkerThreadPool` thread (only arrays are computed there; the `ArrayMesh` is
  created on the main thread) and the character shows the old GLB "helmet" until the cards are ready.
- `hair.gdshader` draws strands inside each card, grey strands by count (salt and pepper, not a flat
  lightening), the receding hairline from a per-root rank, anisotropic highlights and alpha scissor (no
  sorting, shadows work).
- `AppearanceResolver.resolve_hair_look` gives the natural colour (from the pigment model, without grey),
  grey amount, hairline and densities; dyed hair colours the scalp only, eyebrows and beard keep the
  natural colour.

Budgets: up to 26,000 triangles per hairstyle (most are 8,000–25,000), 1,200 per eyebrow shape, 9,000 per
beard.

### Hair details (C4b+, run 19)

Fixes from the run 17 render and the user's review:
- **Temple edge**: shell triangles that the hairline crosses are split into four, twice at the temples and
  sideburns and once elsewhere (the volume layers of the afro are not split). New vertices lie in the plane of
  the skin triangle, so they sit exactly on the skin the game draws, and the edge value is recomputed from
  their own position. The longest edge across the hairline at the temples went from 18.0 to 8.6 mm, which
  removes the visible stair steps.
- **Braids and locs**: each strand now has its own thickness (×0.78–1.28), length, stiffness, lift and a
  gentle sway (3–8 mm); locs vary in thickness smoothly along their length (two low frequencies) instead of
  the bead-like noise, and have rounded tips. They flow from a parting to the sides and back, and the tube
  axis keeps at least 8.5 cm from the face midline, so they frame the face instead of covering it.
- **Beard**: the strip under the chin follows the underside of the jaw and ends about two fingers above the
  Adam's apple (the lowest beard vertex is now at 1.517 m instead of running down the neck); the lower edge on
  the cheeks rises towards the jaw angle; card lengths vary (0.65–1.2×) and lean up to about 20° to the
  sides, with cheek hair flowing slightly forward to the chin, so the full beard no longer forms vertical
  columns; the area under the lower lip is sampled more densely with short hairs.

## Visual verification

Geometric tests are not enough, so every visual change is checked by rendering:
- `tools/raster_preview.gd` is a CPU rasterizer over the real exported GLB with the game's own blend-shape
  weights;
- Blender Cycles renders the real GLB from several angles, with typical, random and extreme faces.

See [asset-pipeline.md](asset-pipeline.md#visual-verification).

Findings from the run 18 face render (`docs/images/c3b-face-run18-before.jpg`: 6 faces × 4 views before
the changes; `c3b-face-run18-after.jpg`: default, random, extremes and small eyes/lips after them):
- fixed: the receding chin (profile), the small eyes with the lids wrapped around the eyeball, thin lips;
- open: the all −1 extreme still has narrow eyes and thin lips (it is the sum of every minimum slider); the
  nose bridge reads as a sharp ridge; the Blender material is a simple Principled shader without the skin
  layers.

Findings from the run 17 hair render (`docs/images/c4b-hair-run17-before.jpg`, after the fixes
`c4b-hair-run17-a.jpg` and the face detail `c4b-hair-run17-face.jpg`):
- fixed: long braids and locs stuck out 15–20 cm in front of the chest and long hair stood off the back like
  a cape (the forward/back lean applied along the whole strand); the undercut and short hair looked spiky;
  eyebrows were built only near the nose bridge (the projection start point was out of reach of the
  triangle hash, so 37 of 140 cards were built – the render showed a grey tuft between the eyes);
- open: a stair-stepped shell edge at the temples (large skin triangles), a column pattern in full beards,
  a gap under the lower lip with a full beard (C3+ B).

Findings from the run 13 render (`docs/images/c3-neck-length-run13-a.jpg`: default, neck −1, neck +1;
`-b.jpg`: muscular and heavy, heavy with neck −1, slim with neck +1):
- fixed: the head no longer looks lifted above the shoulders; the back of the neck and the trapezius rise to
  C7; the neck length slider stays within believable adult proportions at both ends;
- found in the render pipeline: Blender clamps shape-key values to 0..1 by default, so negative weights
  were rendered as 0 until run 13 (the lib now sets `slider_min = -1`). Earlier "min" render rows were
  therefore not exact;
- open: the head is about 1 cm short (crown–chin 22.3 cm against ~23 cm) and can look small on a very
  muscular body (C3+ B).

Findings from the run 12 render (`docs/images/c3-neck-seam-run12-a.jpg` and `-b.jpg`):
- fixed: the head–body seam (no gap or jagged line from any angle), the long thin neck without a chin–neck angle,
  the dark band above the upper lip at the max extreme, and a light "collar" on muscular or heavy bodies;
- open then: hair was still a shell ("helmet") and there were no geometric eyebrows – both done in C4b (run 17);
  still open: the lips are flat and the eyes small (C3+ B), and the head can look small on a very muscular body.
