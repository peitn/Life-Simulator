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
| `character_codec.gd` | Canonical JSON for template files, the share code `LSC1.<base64url(zlib(JSON))>.<crc32>`, and migrations v0 → v1 → v2 → v3. Every external input goes through size limits → CRC → JSON → migration → validator. |
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
| **C3+** | A: neck and head–body seam (fitted band, body morphs on the head neck, blended skinning) – B: lips with volume, eye size and opening, damping of extremes in the editor | ✅ A (run 12), ⬜ B |
| **C4a** | Skin: `SkinModel` (two-layer Beer–Lambert with melanin, haemoglobin and carotene) and `SkinLayers` (freckles, moles, acne with post-inflammatory pigmentation, vitiligo, wrinkles and age spots, scars, tattoos, make-up, eyebrows, stubble). `skin.gdshader` adds SSS and masks in rest-pose coordinates (CUSTOM0), so the details follow morphs. Schema v3. | ✅ |
| **C4b** | Hair, beards and eyebrows as geometry (hair cards): short, long, curly, afro, braids, cornrows, locs, bun, ponytail, bald, receding hairline, greying | ⬜ next |
| **C5** | Clothing: everyday, work, formal, sleepwear and sport. Cuts follow body morphs. Changing clothes in game, replicated in multiplayer. | ⬜ |
| **C6** | Editor I: an in-engine 3D preview (rotate, zoom to face, day/night/interior light, poses), tabs for body, face, skin, hair and clothing, instant sliders, basic and advanced modes, random character with locks, neutral presets, undo/redo | ⬜ |
| **C7** | Editor II: identity (name, nickname, pronouns and grammatical gender, identity, orientation, voice preview), personality (traits with a point budget and conflicts, aspirations), story (family, childhood, past jobs, optional traumas and predispositions only when content settings allow), templates. Accessibility: keyboard and gamepad without fiddly sliders, UI scaling, readable typography, screen-reader labels. | ⬜ |
| **C8** | Integration: menu → editor → game (offline and multiplayer join), changing clothes in game, performance, sensitivity and input-safety audit | ⬜ |

## Visual verification

Geometric tests are not enough, so every visual change is checked by rendering:
- `tools/raster_preview.gd` is a CPU rasterizer over the real exported GLB with the game's own blend-shape
  weights;
- Blender Cycles renders the real GLB from several angles, with typical, random and extreme faces.

See [asset-pipeline.md](asset-pipeline.md#visual-verification).

Findings from the latest render (run 12, `docs/images/c3-neck-seam-run12-a.jpg` and `-b.jpg`):
- fixed: the head–body seam (no gap or jagged line from any angle), the long thin neck without a chin–neck angle,
  the dark band above the upper lip at the max extreme, and a light "collar" on muscular or heavy bodies;
- open: hair is still a shell ("helmet", C4b), the face looks empty without geometric eyebrows (C4b), the lips are
  flat and the eyes small (C3+ B), and the head can look small on a very muscular body.