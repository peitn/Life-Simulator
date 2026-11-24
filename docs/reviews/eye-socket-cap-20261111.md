# Eye-socket cap and conjunctival ring rebuilt (11 November 2026)

Run `main-claude-1794424928-330520`, part of **(0) character creation**. Follows
[head-realism-regressions-20261111.md](head-realism-regressions-20261111.md), whose one remaining failure was the
posterior eye-socket cap (`test_head` 43/44).

## Problem

Behind the eyelids the procedural head (`scripts/assets/head_builder.gd`) has a hidden "conjunctival sac": ring 5 of
the eyelid annulus (material `eye_socket`, 1.2 mm outside the eyeball) and a cap (`ec` vertices) that closes it towards
the back of the eyeball. The cap was a square grid parametrised with `max(|a|, |b|)`. Under extreme eye morphs
(`eye_size`, `eye_tilt`, `eye_depth`…) one wedge near the upper or lower medial corner flipped (1.6–5 mm²), and up to
4 smaller slivers flipped as well, already in the exact shape (not a blend-shape artefact).

## Diagnosis

Ring 5 was mapped with the latitude/longitude helper `_sph` (`ph = x/ρ·k`, `th = y/ρ·k`, k = 1.55). The corners of
the sac reach 125–130° from the front axis of the eye. Past the equator, `sin(ph)` decreases, so in the
latitude/longitude map the azimuth around the eye axis turns back. Measured on the default head: the azimuth of the
bottom-medial corner (−163.28°) and its neighbour (−163.61°) are already in reversed order; with extreme morphs the
reversal grows. Seen from the back pole, ring 5 is therefore **not star-shaped**, and any cap parametrised towards the
pole folds near the corners. Two intermediate attempts confirmed this:

| Variant | Folded faces (24 eye-morph corners) |
|---|---|
| old square grid | 4 (max 5.0 mm²) |
| polar rings towards the back pole, azimuth of ring 5 | 3 (max 8.1 mm²) |
| polar rings + harmonic (Laplacian) relaxation on the sphere | 4 (max 3.0 mm²) |
| **azimuthal-equidistant map (shipped)** | **0** |

A soft clamp of `ph` below the equator did not remove the reversal either (1 reversed step remained), so the problem is
the map, not only the depth.

## Fix

- Ring 5 and the cap use an **azimuthal-equidistant map** around the eye's front axis (`_ae_polar`, `_ae_point`,
  `_sph_ae`): an opening point `(x, y)` maps to the angle `ρ = |(x, y)|·k/r` from the front axis and the azimuth
  `atan2(y, x)`. The almond-shaped opening is star-shaped around its centre, so the azimuth of every ring vertex is
  monotonic for any face. For small `y` both maps agree; visible skin and eyelid rings 1–4 are unchanged bit for bit,
  only ring 5 moves (≤ 2 mm on the default head, ≤ 6 mm at the deep corners with extreme morphs, all behind the eyeball).
- The cap is two concentric rings (`EC_RINGS` = 0.34, 0.67 of the angular way from ring 5 to the back pole) and a
  triangle fan to the pole (`_eye_cap`, vertex recipe `["ec", side, m, a, b]`). With depth the azimuth blends linearly
  into the evenly spaced parameter angle of `(a, b)` sheared like the eye tilt (`EC_SPREAD`), which avoids needle
  triangles from the crowded corners. A convex combination of two monotonic sequences in the same cyclic order stays
  monotonic, so the invariant holds on every ring.
- Ring 5 and the cap no longer follow blinking or the smile's lower-lid raise: the fornix is attached to the orbit;
  only the lid margins close. This removed 53 → 0 folded faces during a full blink.
- Triangle count: head + eyes 18,302 → 18,346 (LOD0 budget 19,000).

## Verification

- New `tests/test_eye_socket_cap.tscn` (14 checks, ~40 s, no blend-shape build needed): recipe layout, closure (every
  edge of the cap and ring 5 has exactly two faces), consistent orientation (each such edge is traversed in opposite
  directions by its two faces), all ring 5/cap vertices on the sphere R + 1.2 mm (0.06 µm), strictly monotonic azimuth
  on every ring for 33 faces incl. blink and smile (smallest step 0.51°), nested rings, 0 folded faces of the whole head
  in 24 eye-morph corners (exact and as a linear sum of eye morphs) and 24 random extremes of all 32 fields, smallest
  socket triangle 0.19 mm², clearance from the eyeball at half and full weights of the linear sum ≥ 1.01 mm,
  determinism and mirror symmetry.
- `tests/test_head.tscn` **44/44** (was 43/44): the tolerance for hidden cap slivers was removed (limit 0).
- `character.glb` rebuilt (`tools/rebuild_character_realism.gd`, revision `2026-11-11-v5-eye-socket`).
- Visual check: CPU rasterizer contact sheet of the real GLB (default face and two eye-morph extremes × 4 views),
  [images/eye-socket-20261111.jpg](../images/eye-socket-20261111.jpg) – no holes, spikes or dark wedges at the eye
  corners. No Blender render this run (the change is behind the eyeball and visible geometry is bit-identical).

## Independent review (Gemini)

Accepted and turned into tests: consistent winding of the pole fan versus `_annulus` (it was correct – the new
directed-edge check proves it), clearance at intermediate blend weights (linear blending moves sphere vertices along
chords). Rejected with reasons: a 2π jump of the azimuth at ±π cannot move a vertex (positions use `cos`/`sin`, and the
monotonic-azimuth test covers the seam); `sin(PI)` ≈ 1.2e-16 gives a 1.6e-18 m offset at the pole, far below float32
GLB precision; per-vertex dictionary look-ups only run when the GLB is built, not at runtime (the game uses blend shapes).

## Still open

- Neck: 7 triangles fold under a −20° lateral bend with a short neck (LBS compression); "collar" of 2.9 mm at the jaw.
- Crowd LOD (simplified head and hair cards).
- `test_assets`: the pre-existing sitting-height failure (pelvis at 0.60 m on the sofa).
