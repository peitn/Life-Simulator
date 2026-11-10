# H3 – rendered async placeholder parity (8 Nov 2026)

Run: `main-claude-1794122510-255186` (v3 main lease).

## What was tested
New `tests/test_h3_async_placeholder_render.gd/.tscn`, real GPU framebuffer (Xvfb, Mesa llvmpipe,
GL Compatibility) of the CharacterPreview SubViewport. Four fictional outfits (hoodie/jeans/trainers,
dress/pumps, t-shirt/shorts/barefoot, t-shirt/jeans with light grey hair).

| Phase | Result |
|---|---|
| REF (editor preview, sync) vs FINAL (spawn, async wardrobe) | mean RGB delta 0.0, IoU 1.0, same C5 pieces (all 3 outfits) |
| REF vs FINAL with async wardrobe AND hair | 0.0 / 1.0 (dark and grey hair) |
| HOLD (placeholder) coverage vs REF | torso/legs >= 75 %, feet >= 40 % (GLB shoe is smaller) |
| HOLD silhouette IoU | 0.85-0.99; dress 0.71 (GLB has no skirt - known limitation) |
| Hair shell crown colour vs cards | before fix 0.44 (dark) / 0.16 (grey); after fix 0.032 / 0.018 |

## Bug found and fixed
While HairRig built strand cards asynchronously, the GLB hair shell placeholder was rendered with the
resolver's sRGB colour as albedo and looked light tan over dark-brown cards. `SimVisual._apply_colors`
now uses `helmet_placeholder_color(lp)` when cards exist (no change when the shell is the real hair).

## Gemini audit (gemini-3.5-flash) - evaluation
1. "Double gamma conversion" (high): REJECTED as a bug, ACCEPTED as a documentation issue. The mapping is
   deliberately empirical (mirrors how the cards look on screen) and verified by measurement; the
   suggested "pure linear" version reproduces the light mismatch. Comment rewritten to say so.
2. Thread-safety of `_hair_parts` (high): REJECTED - `_hair_parts` is created and read on the main
   thread only; workers compute arrays, meshes are assigned in main-thread callbacks.
3. Forward+ vs Compatibility and day/night lighting (medium): VALID, open - only measured in GL
   Compatibility under the preview light. Using the hair shader on the shell is not drop-in (it needs
   CUSTOM0 strand attributes the shell mesh lacks).
4. Dress IoU 0.65 too loose (medium): PARTIALLY VALID - the "no missing body" guarantee comes from the
   per-region coverage checks (proved by the no-clothes control), not from IoU; the dress limitation is
   documented. A negative test for a failed asset load remains open.
5. Untyped `grey` from clients (low): REJECTED - CharacterValidator range-checks hair fields on the
   server before replication; the resolver outputs floats.

## Other observations
- `test_h3_three_process_game` 17/17 x4 after the change (SHA gate updated). One run logged ENet
  "Unable to send packet ... max channels: 0" from `NetSession._on_peer_disconnected` broadcasts
  (roster/chat/clock) - a peer already closed at ENet level while another disconnect is handled. No
  assertion failed; open item for the H4 network step.
- `test_multiplayer` 66/67 once (known clock-pause timing flake), then 67/67 x2.
