# Life Simulator — actual mouse/touch repair and character HQ progress
Date: 2026-10-30; cooperative MAIN lease: `main-realism-1793318998-116142`.

## Mouse report: reproduced vs fixed
The previous "world interaction" used screen-space distance to centers of large objects; clicking visible sofa/bed edges was often missed. Previous left mouse drag had no pan behavior. Portrait web HUD covered nearly the entire world (390px screen with ~324px panel). Read-only HUD labels and top panel could swallow clicks.

Changes:
- `scripts/ui/world_interaction_picker.gd`: replaced approximate point proximity with camera-projected 3D ray intersecting rotated, locally defined AABBs for all 9 SmartObject tags and characters; chooses nearest hit. This is picking geometry, NOT physical collision; no command is executed without `NetSession.request_command`.
- `main.gd`: mouse click on button release only, gesture threshold 10px, no click after drag, touch event and emulated-mouse deduplication (450 ms); GUI consumes its own events. Existing server-side command authorization unchanged.
- `scripts/world/camera_rig.gd`: left drag pans, right drag orbits, middle drag pans, wheel zooms. Gesture end resets even over UI.
- `scripts/ui/hud.gd`: read-only title and notice overlays no longer intercept world clicks; short help text mentions mouse actions. On narrow web/mobile screens (<650px), right-side panel collapses by default so world is accessible; '☰ Ovládání' / '✕ Skrýt panel' toggles it. Desktop panel remains unchanged.
- `tests/test_mouse_input_real.gd/.tscn`: **20/20** true Viewport.push_input tests for 9 objects, real mouse press/release, no action on drag, left pan, right orbit, wheel zoom, HUD character-creator mouse click without world command.
- `tests/test_web_touch_compact_controls.gd/.tscn`: **10/10** true touch dispatch at 390x720, toggle, unobscured scene and world object popup.
- Previous `tests/test_world_interaction_visual.gd` updated to use actual ray body volumes: **27/27**. Existing first playable slice **81/81** and responsive **22/22**. Static check **60/60**.
- Re-exported web **133 MB** to `https://peiti-godot-mcp.hf.space/play/lifesim/`.

## Browser smoke test
A fresh Chromium headless shell loaded the new deployed export: DOM canvas 1200x800, WebGL2 available, focused document; engine console: 'Life Simulator spuštěn (Offline) – 3 postavy, 9 interaktivních objektů.' Native DevTools-dispatched `mousemove/mousedown/mouseup` were received on canvas **1/1/1**, ~5–6s per event on software SwiftShader. A page screenshot still timed out on CPU/software WebGL. This does **not** certify that a user's browser reaches the popup or that touch works on real Android hardware. On mobile, the first-run warning must be acknowledged to enable world input. Fresh tab / hard reload is recommended to invalidate prior build.

## Character / furnishing progress in this same lease (inherited from earlier user request)
- Blender original `lifesim-character` subdivided six rigged skin/clothing meshes, retaining 17 bones, 86 facial morphs; 32,836,172-byte HQ GLB SHA256 `6c88b5339f930f34a308290a3a69fa7d4f1e9191359610b427dd43e513a119d6` published in remote Godot `assets/models/character_hq.glb`, also 5.58MB editable Blend in persistent Blender `lifesim-character-hq-v2` backed up to Hugging Face.
- Native graphical runtime uses high-resolution model with retargeted animation skeleton under `body/Skeleton3D`, 0 missing animation-track warnings in actual Mesa X11 test; web/headless retain low-poly original. Export exclusion via `export_presets.cfg` corrected to `export_filter="exclude"` and `export_files` for HQ, yielding 133MB web export instead of accidental 166MB.
- Seated ankle contact correction, lying head/pillow offset, updated TV/sofa pose anchors, and 2 authored prebuilt draped duvet meshes toggled for occupancy. One dynamic mesh approach hung in headless; rolled back and replaced with reliable static mesh variants.
- Existing targeted regressions HQ posture 19/19, bedding 14/14, real full playable 81/81, save continuation 12/12, mouse real 20/20, touch 10/10. Native screenshot inspection revealed stylized faces, facial fidelity far from photorealistic, clipping/pillow/cloth issues remain; not a full realism overhaul or physics cloth.

## Next
Collect real-browser screenshot and tap/click outcome from actual device; profile WebGL long frames. Full H6 remains open: photorealistic sculpt/face/skin, full-body IK/furniture and clothing collision, general navigation, pose morph limits, LOD performance comparisons. Preserve privacy/ownership and existing H3 milestones.
