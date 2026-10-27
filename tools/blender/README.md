# Blender bridge (Life Simulator)

These are the source scripts for the 3D assets. Blender (4.0.2, headless) runs as a separate service, and data
reaches the Godot project as text, in parts. That is why the project uses its own compact format, **LSX** (v3, and
**v4** since C2).

| File | Contents |
|---|---|
| `lsx_common.py` | Helpers (rounded boxes, materials, Blender→Godot axis conversion), `export_lsx()` (+ `_quad_part()` for control meshes) and `chunk()` |
| `char.py` | **C2 body**: one neutral control mesh (868 vertices, quads) with 10 shape keys, a 17-bone skeleton and heat weights → `body.lsx` |
| `char_v3.py` | v3 character (run 5): source of `character_head.lsx` (head, eyes, short and long hair) up to C3 |
| `furn.py` | Sofa, double bed, single bed and fridge (bevels, cushions, bedspread, notes on the fridge…) |

## Procedure
1. In Blender, run `exec(lsx_common.py)`, then either `exec(char.py)` + `export_body()` or `exec(furn.py)` +
   `build_*()`, and then `export_lsx(...)`. The result is base64 in `/tmp/lifesim_lsx/<name>.b64`; `chunk(name, k)`
   prints the k-th part (3,500 characters + CRC-32).
2. Store the parts as `res://assets/src/<name>.<n>.part` (one file may carry several parts). Check the CRC of each
   part while transcribing it (locally), not only later in Godot.
3. `tools/import_lsx.gd`:
   - verifies the CRC of every part and assembles `res://assets/src/<name>.lsx`;
   - builds the scene (`scripts/assets/lsx_decoder.gd`);
   - saves the **GLB** to `res://assets/models/` together with `manifest.json`.

   Composite models (`COMPOSE`): `character` = `body.lsx` (v4 body) + `character_head.lsx` (v3 head and hair).
4. At runtime, `scripts/assets/asset_library.gd`:
   - loads the GLB through GLTFDocument (no editor import needed);
   - adds surface detail to materials by prefix (`fabric_`, `wood_`, `skin_`…);
   - caches the PackedScene.

## LSX v4 (C2, run 8)
- **Morph targets** from shape keys:
  - Each part carries `[name, scale, offset, length]`.
  - Displacements are 3×int8, stored planar and delta-coded between neighbouring vertices; displacements under 0.5 mm
    are zeroed.
  - The `morphs` header gives the order of names (at most 32).
  - `meta.morph_bones` holds joint offsets at full weight.
  - `meta.basis_defaults` holds the schema defaults that the base mesh represents.
- **Quad part** (`prim: quad`): a CONTROL mesh plus per-face material (`mats`, `fmat`), without normals.
  - The import refines it with Catmull-Clark (`scripts/assets/subdiv.gd`). This is identical to `cc_matrix()` in
    `char.py` and to Blender's Subdivision Surface without the limit surface (error 3.6e-7 m).
  - Normals are computed for the base and for every morph.
  - Four times less data is transferred (the body is 21.5 kB of text instead of ~90 kB).
- Morphs are computed **on the fine mesh** (what the player sees) and transferred to the control mesh by least squares
  (`min |S·d − D|² + λ|d|²`). Otherwise subdivision would halve local shapes such as the bust.
- Blend shapes in Godot use `BLEND_SHAPE_MODE_NORMALIZED` with absolute targets. This is the only mode the Godot GLTF
  exporter writes correctly; RELATIVE mode stores the targets wrongly and breaks zero normal displacements.
- Bone indices in the vertices of an imported GLB refer to the **skin bind (joint)**, not to the bone index in the
  skeleton. When working with weights, always go through `Skin.get_bind_bone()`/`get_bind_name()`.

## Conventions
- Axes: Blender (Z up, front −Y) → Godot (Y up, front **+Z**); characters walk towards +Z.
- In Godot, bones have an identity rest rotation (translation only), so animations
  (`scripts/assets/character_anims.gd`) are written in model axes. In SimVisual:
  - body shape changes the rest positions of the shoulders and hips and the inverse bind;
  - leg length scales the thigh;
  - head size scales the head bone.
- Part nodes are named `<group>__<part>__<material>` (groups `body`, `head`, `hair_short`, `hair_long`).
- Budget: furniture ≤ 8,000 triangles; main character ≤ 18,000 (with the face since C3). `tests/test_assets.gd`
  enforces this.
- The head (C3) is not built in Blender but procedurally at import (`scripts/assets/head_builder.gd` +
  `character_assembly.gd`). Every facial morph is a function of schema parameters, so the blend shapes match the
  data exactly. Only the hair is taken from `character_head.lsx`, and the skull morphs are transferred onto it.

## Why not GLB directly
The Blender service can only export scenes built from primitives, and script output is limited to ~4 kB. LSX
shrinks the character from a ~290 kB GLB to ~44 kB of text. It does this with:
- 12-bit positions and octahedral normals;
- high-water-mark index coding;
- at most 2 bones per vertex;
- zlib compression.

The CRC reveals transcription errors during transfer. In run 5 it caught and fixed one transfer error in a sofa part;
in run 8 the parts were CRC-checked before they were written to the project.
