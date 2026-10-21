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

- The main character is at most 18,000 triangles (about 17,000 currently), with the head and eyes at most
  9,000.
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
     which apply to the body and to the head's neck band under the same names).
   - Render with Cycles: orthographic camera, 32–40 samples, several characters (default, random, extremes,
     asymmetry, heavy and muscular builds) × 5 views (front, 35°, profile, back, low angle), as one contact sheet.
   - Send the sheet back as base64 parts (≤ 140,000 characters each, because file reads are truncated at about
     200,000) with the Godot server's `godot_file_write` tool, decode it, check the MD5 and inspect it.
   - No access tokens are used for this; nothing is uploaded to third-party repositories.

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

## Planned

- More assets: stove, TV, bookcase, shower, treadmill, table and chairs, doors and windows, trees, the
  city.
- Facial expressions and gestures, foot IK, sit and stand transitions.
- Hair cards (C4b) and clothing that follows body morphs (C5).
