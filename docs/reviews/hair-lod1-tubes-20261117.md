# Crowd LOD step 4 – braids, dreads and cornrows in tier 1 (17 Nov 2026)

Run `main-claude-1794900129-31028`. Follows `docs/reviews/hair-lod1-20261113.md`.

## Problem
Tier 1 (a character at roughly 5.5–20 % of the screen height) uses a reduced hair mesh. Strand cards and
shells were reduced in step 3, but tube hairstyles (box braids, dreads, cornrows) kept their full geometry:
meshoptimizer (`ImporterMesh.generate_lods`) flattened the thin tubes (error 13.8 mm for braids, 6 mm for dreads)
and the braid silhouette failed.

## Approach
`HairRig.lod1_tubes()` drops whole **rings** along each strand instead of simplifying the surface:

- The tube structure (rings of k+1 vertices, 2k triangles per segment, optional tip cap) is parsed from the index
  buffer (`lod1_tube_parse`). The parse is accepted only if rebuilding all indices reproduces the input exactly;
  otherwise the kind falls back to meshoptimizer (the previous behaviour).
- Rings are chosen by a Douglas–Peucker pass over ring vertices (`lod1_tube_rings`): every vertex of a dropped
  ring lies within the tolerance of the linear interpolation (by axis length) of the same vertex on the
  neighbouring kept rings. First and last ring and the tip always stay.
- Tolerance = min(4 mm, 0.5 × mean tube radius). With a flat 4 mm the braid silhouette from the front dropped to
  IoU 0.933 (< 0.95): a 2.8–4.6 mm thick braid moved by its whole width visibly loses volume. Half the radius keeps
  every dropped ring inside the original strand thickness.
- No new vertices: the cross-section is unchanged, and skin, bindings, blend shapes, UVs and `CUSTOM0` are carried
  over by the existing compaction in `lod1_pack`.

Grok's suggestion (room #527) of fewer sides plus a larger radius was not used: halving the sides of a 5-sided
braid changes its cross-section and front silhouette.

## Results
| Style | Full | LOD1 | Rings | Max error | Front IoU |
|---|---|---|---|---|---|
| Box braids | 23,101 | 14,645 | 1,635 → 1,148 | 1.90 mm | 0.972 |
| Dreads | 27,716 | 13,658 | 1,502 → 754 | 3.01 mm | 0.971 |
| Cornrows | 11,071 | 4,365 | 336 → 76 | 2.09 mm | 0.999 |

All 16 hairstyles in tier 1: 327 k → about 166 k triangles (was 190 k after step 3); mean silhouette IoU 0.989.

## Thread safety (room #527, point 2)
LOD builds run inside `WorkerThreadPool` tasks. Each task creates its own `ImporterMesh` and arrays and touches no
shared state or `RenderingServer`. `test_hair_lod1_tubes` builds six styles at once in worker threads and checks
that full cards, blend shapes, LOD1 and proxy are byte-identical to a sequential build.

## Tests
- `tests/test_hair_lod1_tubes.tscn` (44 checks): parse (tube count equals the builder's, sides 5/7/6, cap,
  exact rebuild), safe fallback on corrupted indices, an independent error check (distance from every full-tube
  vertex to the nearest LOD1 triangle of the same tube ≤ tolerance), whole rings kept, ends and tip kept, vertex
  order (front face) as in `HairBuilder.tube`, `CUSTOM0` unchanged, blend-shape displacement identical, concurrency.
- `tests/test_hair_lod1.tscn` 205/205 (now covering tube styles too).

## Visual check
No GPU display is available on the server any more (`xvfb-run` missing), so `tools/render_hair_tubes_cpu.tscn`
renders full vs. LOD1 with the software rasterizer (`tools/raster_preview.gd`; shape and silhouette, not PBR).
Back views of all three styles were inspected: silhouette and volume match, no gaps.

## Review
Gemini (skeptical review): four findings, none accepted after checking –
1. "tie-breaking in Douglas–Peucker is non-deterministic": ties go to the first index (strict `>`), the inputs are
   bit-identical on every peer and the test checks byte-identical rebuilds; nothing is replicated.
2. "intermediate indices may exceed the vertex count": all ring indices are ≤ the last checked index (tip or last
   ring), and `base < 0` is rejected.
3. "allocation pressure": a few small packed arrays per tube, built once per hairstyle in a worker; not measurable
   next to the 90–280 ms build.
4. "NaN for zero-length segments": the parameter falls back to 0.5, no division by zero.

## Open
- Eyebrow and beard LOD; procedural parts; blend-shape pruning in tier 2; GPU measurement (needs a display).
