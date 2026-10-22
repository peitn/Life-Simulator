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
| `character_codec.gd` | Canonical JSON for template files, the share code `LSC1.<base64url(zlib(JSON))>.<crc32>`, and migrations v0 → v1 → v2 → v3 → v4. Every external input goes through size limits → CRC → JSON → migration → validator. |
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
| **C3+** | A: neck and head–body seam (fitted band, body morphs on the head neck, blended skinning); A2: anatomical neck base and `body.neck_length` (schema v4) – B: lips with volume, eye size and opening, head size, damping of extremes in the editor | ✅ A (run 12), ✅ A2 (run 13), ⬜ B |
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

Budgets: up to 26,000 triangles per hairstyle (most are 5,000–22,000), 1,200 per eyebrow shape, 9,000 per
beard.

## Visual verification

Geometric tests are not enough, so every visual change is checked by rendering:
- `tools/raster_preview.gd` is a CPU rasterizer over the real exported GLB with the game's own blend-shape
  weights;
- Blender Cycles renders the real GLB from several angles, with typical, random and extreme faces.

See [asset-pipeline.md](asset-pipeline.md#visual-verification).

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
