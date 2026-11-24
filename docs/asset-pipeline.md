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

- **Triangle budgets (LOD0, revised 11 November 2026).** The 30 October "realism pass" refined the head lattice
  (32×36×20), the ears (10×32) and the eyeballs (48 segments). The resulting counts were accepted as the LOD0
  budgets because realism is the project goal: the head and eyes at most **19,000** (measured 18,302), the whole
  main character at most **28,500** (measured 27,418; previously 20,000), and one hairstyle at most **40,000**
  (dense styles measure 26,000–39,500 because hair grows from the finer scalp; previously 26,000).
  Known cost: eight characters with dense hair are roughly 0.5–0.7 million triangles, a large share of them
  alpha-tested hair, plus about 90 blend shapes per head surface. This has not been profiled on real GPUs or in
  the web export. These budgets are upper limits for the close-up model, not a performance guarantee.
- **Crowd LOD (step 1, 12 November 2026).** `CharacterLod.with_lods` adds automatic index LODs
  (`ImporterMesh.generate_lods`) to every GLB mesh of at least 600 triangles when `AssetLibrary` loads it; the
  LODs share the vertices, so blend shapes, skinning and `CUSTOM0` are unchanged, and a LOD that would change the
  mesh border (neck seam, eye, lip and mouth openings) is dropped with all coarser ones. Face: 12,560 → 6,280 /
  3,140 / 1,570 / 784 / 392 / 196 triangles, about 150 ms once per game. On top of that `SimVisual` has three
  detail tiers by screen share (≥ 0.20 full; ≥ 0.055 expressions at 10 Hz and no shadows from small face parts;
  below that the GLB hair shell replaces the strand cards, the mouth interior is hidden and the expression is
  frozen), with hysteresis and the "Detail postav v dálce" setting. Not done yet: LODs for strand cards and
  procedural parts, a per-style hair proxy, pruned blend shapes, GPU/web measurements.
  See `docs/reviews/crowd-lod-20261112.md`.
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
  weighted along the whole neck tube (12 cm since 12 Nov 2026, earlier 8 cm; not the jaw), so a heavy or muscular build widens the whole neck;
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


## Background garment builds (7 Nov 2026)
`LSX.scene_arrays(decoded)` returns the same per-part arrays that `build_scene()` puts into
ArrayMeshes, without nodes or RenderingServer calls. `ClothingWardrobe` uses it on a worker thread
(`_build_kind` → `_textured_pack`), then creates the ArrayMeshes and shared materials on the main
thread (`_realize`). Calling RenderingServer queries (e.g. `ArrayMesh.surface_get_arrays`) from a
worker can deadlock against a main thread that waits for that worker, so worker code must stay
array-only. Garment meshes no longer take a round trip through an intermediate ArrayMesh, so normals
and weights are no longer quantised twice (differences are below 1e-4 and all garment tests pass).


## Hair shell as placeholder (8 Nov 2026)
When strand cards are available, the GLB hair shell (`hair_main`) is only shown while `HairRig`
builds a style in the background. Its albedo comes from `SimVisual.helmet_placeholder_color()`:
the same numbers the cards send to `hair.gdshader` (natural colour → `srgb_to_linear`, grey blend)
used as albedo and darkened by `HELMET_SHADE` (0.5) in linear light. This is an empirical match,
verified by the rendered H3 test for dark and grey hair under the preview light in GL Compatibility.
Without cards (e.g. no shader) the shell is the real hair and keeps the resolver colour. Not yet
measured: Forward+ and night lighting.


## Eye-socket cap (11 November 2026)

Behind the eyelids the head has a hidden conjunctival sac: ring 5 of the eyelid annulus and a cap that closes it
towards the back pole of the eyeball (material `eye_socket`, sphere R + 1.2 mm). Both use an azimuthal-equidistant
map around the eye's front axis (`HeadBuilder._ae_polar/_ae_point/_sph_ae`, `EC_K5`), so the azimuth of every ring
vertex stays monotonic for any face; the latitude/longitude map used before reversed it at the deep corners and the
cap folded. The cap is two rings (`EC_RINGS`) and a triangle fan to the pole; vertex recipes are
`["ec", side, m, a, b]`. Ring 5 and the cap ignore blink and the smile's lower-lid raise (the fornix is attached to
the orbit). Details and the rejected variants: `docs/reviews/eye-socket-cap-20261111.md`; invariant test
`tests/test_eye_socket_cap.tscn`.

## Hair proxy for crowds (13 Nov 2026)
`HairRig` builds, together with each style's scalp cards, a 1,344-triangle envelope (`proxy_geometry`,
cache key `scalp_proxy:<style>`) with the same skin binding and transferred blend shapes as the cards.
`SimVisual` shows it in crowd LOD tier 2 instead of the shared GLB helmet. Triangles use Godot's clockwise
front-face convention like the GLB meshes. Details: `docs/reviews/hair-proxy-20261113.md`.

### Hair cards for crowd LOD tier 1 (13 Nov 2026)
`HairRig.lod1_pack` derives a thinned card mesh (`scalp_lod1:<style>`) from the finished card arrays in the same
worker task: whole cards kept per layer (25–60 %) and widened by 1/√share, outline segments always kept (spherical
and cylindrical grids, 2 mm), every second inner afro shell, meshoptimizer for shells/tubes per kind (error ≤ 4 mm,
≤ 1 % border change), compacted vertices with identical blend-shape names and skin. Since 17 Nov 2026 braids, dreads and cornrows get a ring-dropping tube LOD1 (`HairRig.lod1_tubes`, cross-section unchanged, error ≤ min(4 mm, ½ tube radius); see `docs/reviews/hair-lod1-tubes-20261117.md`). Before that, braids and dreads got no LOD1
(tube error 13.8 / 6 mm). All 16 styles: 327 k → 190 k triangles. Details: `docs/reviews/hair-lod1-20261113.md`.

### Eyebrows and beards for crowd LOD tier 1 (17 Nov 2026)
The same reducer runs for `brows` and `beard` (`lod1_pack(pack, {facial, outline, keep, widen_full})`, cache keys
`brows_lod1:<style>` / `beard_lod1:<style>`, non-blocking lookup `HairRig.cached_facial_lod1`). Kept cards get their
strand random rescaled (`CUSTOM0.x / keep`) because the shader hides facial cards above the per-character density;
the visible LOD1 cards are then a nested subset of the full mesh at every density. Eyebrows: keep 0.5, no outline
protection; beards: keep 0.425, outline protection on; both widened by 1/keep (cap 2.5). Meshes under 300 triangles
(moustache) get no LOD1. Brows 320–760 → 128–368 triangles, beards 1.6–5.4 k → 0.9–3.2 k. Details:
`docs/reviews/facial-lod1-20261117.md`.

## Crowd LOD step 6 – baked blend shapes at tier 2 (18 Nov 2026)
At tier 2 the visible character meshes with blend shapes (except hands) are replaced by static meshes with the current shape baked in (`scripts/assets/lod_bake.gd`, worker thread, weak-ref caches). Any change of weights or meshes restores the originals with their exact weights and re-bakes after 0.4 s. Everything except positions/normals/tangents is carried over unchanged, including automatic LOD index buffers. Details: docs/reviews/lod-bake-20261118.md.

## Crowd LOD step 7 – procedural parts (18 Nov 2026, evening)
Procedural meshes from `HandDetailBuilder._bake` (fingers + nails, bare feet + toenails, bare torso) now use `BLEND_SHAPE_MODE_NORMALIZED` with absolute targets, like every other character mesh. The previous RELATIVE delta encoding could not express an unchanged normal: Godot stores blend-shape normals octahedrally (unit length), so a zero delta decoded as (0, 0, -1) and body morphs tilted the normals by ~50-78 degrees on the GPU (measured with `tools/diag_procedural_blend.gd`). Positions are unchanged. Use `HandDetailBuilder.morph_delta()` in tests instead of reading target arrays as deltas.

`LodBake` reproduces the skinning shader for both modes (RELATIVE: delta = target, the decoded unit target normal is always added). Hands are now baked at tier 2 too: finger-pose setters un-bake only the hands (`_lod_touch_hands`), reads go through `lod_blend_value()`, visibility changes call `_lod_refresh()`. Procedural meshes get automatic index LODs (`CharacterLod.with_lods`): finger skin 3 040 -> 1 520/760/380/190 triangles, foot skin 2 928 -> 1 464/732, borders preserved; nails stay below the 600-triangle threshold. Limitation: if per-frame finger animation is added later, hands at tier 2 must be excluded or the animation frozen at tier 2. Review: `docs/reviews/procedural-lod-20261118.md`.
