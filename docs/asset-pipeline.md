# Asset pipeline

3D assets are authored by **Python scripts for Blender** (`tools/blender/`) that run on a headless Blender
service. The procedural head is the exception: it is generated in Godot by `HeadBuilder`, so its morphs
always match the character schema exactly.

## Blender bridge and the LSX format

Blender runs as a separate service, so meshes travel to the Godot project as text in parts. That is why
the project uses its own compact, checksummed format, **LSX**.

| Script | Contents |
|---|---|
| `lsx_common.py` | Helpers (rounded boxes, materials, Blender→Godot axis conversion), `export_lsx()`, `chunk()` |
| `char.py` | C2 body: one neutral control mesh (868 vertices, quads), 10 shape keys, a 17-bone skeleton with heat weights → `body.lsx` |
| `char_v3.py` | v3 character source for `character_head.lsx` (eyes, short and long hair) |
| `furn.py` | Sofa, double bed, single bed and fridge, with bevels, cushions, bedspread and fridge notes |

LSX versions:
- **v3**: meshes, materials, skeleton, weights.
- **v4**: adds int8 delta-coded morph targets, quad parts and per-face materials, with limits. v3 stays
  readable.

Every part carries a CRC-32. Corrupted, missing, mixed or out-of-range data is rejected without crashing,
and `test_assets` covers this.

### Steps

1. In Blender, run `exec(lsx_common.py)`, then the asset script, then `export_lsx(...)`. The result is
   base64 split into parts with a CRC.
2. Store the parts as `res://assets/src/<name>.<n>.part`.
3. Run `tools/import_lsx.gd`. It verifies each part's CRC and assembles `res://assets/src/<name>.lsx`.
   It then builds the scene (`LsxDecoder`, Catmull-Clark through `Subdiv`, normals for every morph) and
   writes the GLB to `res://assets/models/` together with `manifest.json`.
4. The composed model `character` is built from `body.lsx` and the procedural head (`CharacterAssembly`):
   - the body neck is cut above a seam loop;
   - the head neck band is fitted onto that loop and carries the body blend shapes and blended bone
     weights, so the seam stays closed under morphs and animation;
   - hair inherits skull morphs by weighted transfer from the nearest skull vertices.
5. At runtime `AssetLibrary` loads GLBs through `GLTFDocument` (no editor import needed). It adds PBR
   detail by material prefix and falls back to primitives when a model is missing.

Raw files read at runtime (`*.glb`, `*.wav`, `*.lsx`, `manifest.json`) use `importer="keep"` and an
`include_filter` in the export presets.

## Budgets

- The main character is at most 20,000 triangles (19,260 since run 21, which added eyelashes, teeth, gums and a
  tongue), with the head and eyes at most 11,500.
- Furniture is at most 8,000 triangles each.
- Applying a face to a character takes under 2 ms. Moving an appearance slider currently takes 3.3–3.8 ms,
  against a target of 4 ms.

## Visual verification

Tests check geometry, but a human-style look at the real model is required before a visual step is
closed.

1. **`tools/raster_preview.gd`** is a CPU z-buffer rasterizer over the real `character.glb`. It applies the
   game's blend-shape weights and normals and produces contact sheets. Helpers `tools/neck_sheet.gd` and
   `tools/face_sheet.gd` build specific sheets.
2. **Blender render** of the real GLB:
   - Split the GLB as base64 into parts of 150,000 characters in `res://previews/glb_parts/` (`previews/` is not
     exported or mirrored to this repository).
   - In Blender, fetch the parts from the Godot server's public plain-text document endpoint
     (`/doc/file:lifesim/<path>`), join them and check the MD5 against the value printed in Godot.
   - Import the GLB and set the shape keys from `AppearanceResolver` weights (face weights, plus body weights,
     which apply to the body and to the head's neck band under the same names). Set `slider_min = -1` on every
     shape key first: Blender clamps values to 0..1 by default, so negative weights (linear morphs, neck length)
     would otherwise render as 0 (found in run 13).
   - Render with Cycles: orthographic camera, 32–40 samples, several characters (default, random, extremes,
     asymmetry, heavy and muscular builds) × 5 views (front, 35°, profile, back, low angle), as one contact sheet.
   - Send the sheet back as base64 parts (≤ 140,000 characters each, because file reads are truncated at about
     200,000) with the Godot server's `godot_file_write` tool, decode it, check the MD5 and inspect it.
   - No access tokens are used for this; nothing is uploaded to third-party repositories.

### Face render check (run 18)

`tools/face_render_export.gd` writes a fixed, deterministic set of characters (default, 4 random, both
extremes, asymmetry, large and small eyes and lips, heavy, muscular) with the game's own blend-shape weights
and colours to `res://previews/<name>.json`. `tools/blender/face_render.py` is the matching Blender library:
it fetches the GLB parts and the JSON from the Godot server's document endpoint, renders close-ups (front,
35°, profile, low angle) with Cycles and sends the contact sheet back as base64 parts. Hair is left out on
purpose, so the eyes, forehead and temples stay visible.

Run 21 added `write_expressions()` (expressions and detail extremes, with the same `ex_*` weights as `SimVisual`) and
colours for the teeth, gums, tongue, lashes and limbus; `face_render.py` gives those parts their own materials. Long
renders can hit the service's HTTP timeout (524) although Blender finishes: the rendered rows stay in `/tmp/rt` and
the sheet can be assembled and sent in a second call.

Run 22 added `tools/blender/skin_micro.py`, a Cycles approximation of the C4c skin shader (zone masks for sebum and
dryness from the position, pores from a Voronoi texture and skin lines from ridged noise through a Bump node, flakes,
clear coat for sebum, sheen for vellus hair), the lash material with the root-darkening vertex colour, and the mouth
colour derived from the skin. `face_render_export.gd` writes the micro-detail parameters per row (`write_run22()`). Long
renders now run as a detached Blender process on the render service (rows land in `/tmp/rt`), which avoids the HTTP
timeout of a single call.

## Head–body seam (C3+)

The body's neck is cut above a 16-vertex loop at import (`CharacterAssembly.cut_body_neck`). The procedural head
(`HeadBuilder`) is then built against that loop:
- vertices of the head's neck band move onto a Catmull-Rom curve through the loop vertices (plus 0.4 mm), fully up to
  2 cm above the edge and fading out over 6.5 cm; the curve is a linear combination of loop vertices, so body morphs
  stay exact;
- the head carries blend shapes named after the body keys (`fat_hi`, `muscle_hi`, `frame`…): the loop's displacement,
  weighted along the whole neck tube (8 cm, not the jaw), so a heavy or muscular build widens the whole neck;
- bone weights in the band are blended with the loop's weights, normals are matched to the body within 12 mm of the
  edge, and quads in the band are split along the more convex diagonal (the neck sleeve is a diagonal grid, and the
  other diagonal could sag below the edge).
`tests/test_neck_seam.gd` checks the result on the real GLB; renders are in `docs/images/c3-neck-seam-run12-*.jpg`.

Run 13: before the cut, the body's neck base and trapezius are raised by a direction-dependent field
(4 / 30 / 46 mm front / side / back, see [character-creator.md](character-creator.md#neck-length-and-neck-base-run-13)),
and the head gets the linear `b_neck_len` blend shape (neck length ±15 mm). Renders:
`docs/images/c3-neck-length-run13-*.jpg`.

## Planned

- More assets: stove, TV, bookcase, shower, treadmill, table and chairs, doors and windows, trees, the
  city.
- Gestures, foot IK, sit and stand transitions (basic facial expressions exist since run 21).
- Clothing that follows body morphs (C5).

## Hair render check (C4b)

Hair is generated in Godot, so it is not in `character.glb`. `tools/hair_export.gd` builds a `SimVisual` for a
set of characters (styles, colours, greying, receding hairline, beards, head shapes), reads the real blend-shape
weights from it and writes the deformed card geometry (positions, UV, CUSTOM0, indices as base64 float/int
arrays) plus the head and body weights to `res://previews/hair_export/*.json`, split into 150,000-character
parts. In Blender the parts are joined (MD5 check), `character.glb` is imported with the same shape-key
weights, the cards become meshes, and a node material imitates `hair.gdshader` (strands from UV and CUSTOM0,
grey strands, receding hairline, shells). Cycles renders 5 views per character; the sheet goes back to Godot
with `godot_file_write` in equal parts (so that every part is large enough to be stored as a file on the
reviewer's side) and is decoded and checked by MD5. The Blender material is an approximation: highlights
and shells look glossier than in the game.

## C5 wardrobe — Blender to LSX to runtime, 23 October 2026

C5 is made in Blender via tools/blender/clothing_c5.py, moved through tools/blender/clothing_c5_lsx_export.py and reconstructed by scripts/assets/clothing_wardrobe.gd. The authored set contains 57 meshes, all ten body morphs and the character's 17-bone skin, split into five LSX assets in assets/src/clothing_c5/. GLB import of Blender-authored models hangs with Godot 4.7.2 on this server; the original Godot-created avatar GLB still works, so Blender->LSX is the supported wardrobe pipeline.

Original textures include seven 128x128 tileable albedo maps and seven tangent-space normal maps. Files live in assets/textures/clothing_c5 and have persistent Blender/Godot library copies. ClothingWardrobe adds missing UVs and tangents to decoded LSX meshes, creates per-character material tint instances, and remaps LSX bone indices onto the original avatar Skin bind order before attachment. Do not assume skeleton bone index equals Skin bind index. The export presets explicitly include the wardrobe PNGs and .lsx raw files.

Visual QA is reproducible via tools/blender/clothing_c5_render.py, producing previews/c5_qa_*.b64. Check front/back and body/pose extremes before closing the task; the current hoodie hood and sleeve joins remain prototype-quality.
