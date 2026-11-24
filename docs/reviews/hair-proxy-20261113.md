# Per-style hair proxy for crowd LOD (13 Nov 2026)

Run `main-claude-1794554507-349929`. Crowd LOD step 2, following `crowd-lod-20261112.md`.

## Problem

In LOD tier 2 (a character smaller than ~5.5 % of the screen height) `SimVisual` hid the strand cards and
showed the shared GLB "helmet" (`hair_short` / `hair_long`). For voluminous styles the helmet has a very
different silhouette (an afro became a skull cap, long hair a short bob), so the hairstyle visibly changed
when a character walked away from the camera.

## Solution

`HairRig.proxy_geometry()` builds a low-poly envelope of each style's scalp cards:

- spherical grid around the head centre `HairBuilder.C`: 32 azimuths × 21 elevations + 2 poles = **1,344
  triangles** for every style;
- each grid vertex takes the radius of the farthest card vertex in its angular cell (at least 3 mm above
  the skin); an empty cell with ≥ 5 of 8 hairy neighbours gets their mean (gaps between strands); other empty
  cells sink 4 mm below the head skin (face, neck), so they are hidden;
- skinning and blend shapes are transferred exactly like the cards (`_arrays_from`, binding to the nearest
  skin vertices), so the proxy follows head shape, neck length, shoulders and body fat;
- front faces follow Godot's convention (clockwise; `(b-a)×(c-a)` points inward, vertex normals outward),
  the same as the GLB head mesh.

The proxy is built in the same `WorkerThreadPool` task as the scalp cards and stored in the shared cache under
`scalp_proxy:<style>` (`null` for bald). `cached_proxy()` never blocks; `proxy_mesh()` is the synchronous
variant for tests and tools. The mesh is deterministic (same bytes after `clear_cache()`), so every peer
shows the same proxy. Nothing is replicated.

`SimVisual` creates a `hair_proxy` node under the skeleton with the cards' `Skin`; it uses the character's own
`hair_main` material (the calibrated helmet colour). Morph weights reach it through `_face_meshes()`. In tier
2 the proxy is shown instead of the helmet; while the cards are still building in the background the helmet
remains the placeholder.

`HairRig.context()` now also precomputes the skin grids used by `bind()` (previously rebuilt on every call).
Bindings, card meshes and proxies are byte-identical before and after this change (MD5 of three styles).

## Results

Silhouette IoU against the strand cards (independent CPU rasteriser, 4 mm, head ∪ body ∪ hair; front / side /
top), proxy vs. previous helmet:

| Style | Proxy | Helmet |
|---|---|---|
| kratke | 0.97 / 0.97 / 0.98 | 0.92 / 0.94 / 0.93 |
| dlouhe_rovne | 0.88 / 0.87 / 0.79 | 0.42 / 0.49 / 0.47 |
| afro | 0.98 / 0.97 / 0.98 | 0.56 / 0.60 / 0.53 |
| kudrnate | 0.92 / 0.92 / 0.88 | 0.74 / 0.78 / 0.65 |
| copanky | 0.75 / 0.68 / 0.68 | 0.40 / 0.57 / 0.56 |
| culik | 0.97 / 0.76 / 0.97 | 0.72 / 0.74 / 0.90 |
| mean of 15 styles × 3 views | **0.914** | 0.733 |

The proxy is at least as good as the helmet in every one of the 45 style/view pairs. Extra build cost:
150–300 ms per style, once per session, in the background thread (cards take 1–5 s).

## Visual check

`tools/render_hair_proxy.tscn` (Xvfb, GL Compatibility) renders cards / proxy / helmet side by side. The first
render showed the proxy of long brown hair as a light shell: the triangle winding was reversed, so the inside
of the envelope was drawn. The test had checked the wrong convention; both were fixed and the second render
shows the proxy with the colour and silhouette of the cards.

## Known limitations

- A star-shaped envelope fills the gaps between hanging braids and locs and between a ponytail and the neck
  (side IoU of `culik` 0.76, braids 0.68–0.75). A dedicated proxy for tube styles is an option.
- The hairline is blurred by about half a cell (~7 mm) – below one pixel at tier 2 distances.
- Only headless GL Compatibility rendering was checked; Forward+ and night lighting are not measured.

## Tests

- `tests/test_hair_proxy.gd` – geometry of all styles (budget, finite values, indices, Godot winding,
  normals, minimum triangle area, skin weights, key names, build time), silhouettes, morph transfer,
  determinism, `SimVisual` integration (tier 2 = proxy, material, morph weights, style change in a crowd,
  bald, async build), switch cost.
- `tests/test_character_lod.gd` – tier 2 now expects the proxy instead of the helmet.

## Independent review

Gemini (flash-lite; 3.5-flash was overloaded) raised five points. Rejected after checking the code: proxy
skin desync (the proxy shares the cards' skeleton and skin, and `_apply_joints` processes every skinned
node), a `_store` race (it runs only on the main thread and `_waiters` prevents duplicate builds), blend shape
index mismatch (weights are written by each mesh's own key names), main-thread stalls (`SimVisual` only
calls the non-blocking `cached_proxy`). Accepted: degenerate-triangle risk → the test now checks the minimum
triangle area.
