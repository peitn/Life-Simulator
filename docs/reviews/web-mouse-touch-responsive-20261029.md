# Life Simulator web pointer / mobile responsive repair — 2026-10-29

Run: `main-webinput-1793315444-103774`, native Godot 4.7.2; source-of-truth remote `lifesim`; cooperative main v3 lease.

## Reproduction

The original production settings modal was fixed at width 640 and height 660. At a 390×720 viewport its bounds were x=-125..515; the first-run button “Rozumím, pokračovat” was x=-107..70 and its center fell off-screen. At 320×568 the HUD command panel started x=-20 and exceeded the left viewport edge.

In live Chromium 135/WebGL2 against the previously deployed web export, a real CDP mouse click at the warning confirmation position dismissed the warning and exposed the offline household (screen capture). Web rendering was extremely slow on the available software renderer; mouse-event replies took multiple seconds, and opening creator UI subsequently blocked evaluation/screenshot for 18–25 s. This is not enough to certify all browser controls or native mobile touch.

## Fix

- `scripts/ui/settings_menu.gd`: viewport- and resize-responsive modal size with 12 px minimum margin; warning body scrolls while all three 42 px high action buttons remain visible; narrow-friendly vertically stacked settings controls; OptionButton `fit_to_longest_item=false` prevents an off-screen 324 px intrinsic minimum.
- `scripts/ui/hud.gd`: responsive right-side command panel offsets; no fixed 300 px content minimum; smaller intrinsic command and needs bar widths to avoid left-edge overflow on narrow screens.
- New regression `tests/test_web_input_responsive.gd/.tscn` validates both dialog and HUD hit rectangles on 320×568, 390×720, 900×600 and 1600×900 and checks scroll area.

## Verification

- New responsive test **22/22 PASS** exit 0, no timeout.
- Existing real offline first-playthrough test **81/81 PASS** exit 0, no timeout, including creator, 2 characters, commands, save/load and cold restart.
- Godot script syntax **60/60 PASS**.
- New Godot **web debug export success**, 133 MB, https://peiti-godot-mcp.hf.space/play/lifesim/ ; subsequent HTTP 200, HTML Last-Modified Thu, 29 Oct 2026 23:23:43 GMT.
- Isolated headless mobile Chromium WebGL run loaded engine but blocked CDP Runtime.evaluate on the CPU-only software renderer. **No claim** of completed browser real tap test; needs actual end-user/device validation.
- Existing world camera uses right mouse drag, middle drag, wheel and WASD/QE. **Left-click selection / action on furniture or NPCs in 3D is not implemented**, which remains a separate UX feature. Do not misstate this repair as implementing 3D picking.
- No changes to character models, multiplayer authority, physics, city assets, GitHub or AI Room.

Sources SHA256: settings_menu.gd `856dc4a81372fa100c2605974201a0e9422e6166c17f89c3379a27105db8c633`; hud.gd `f5c00df15e90b99414ff1ac47afc5adf53deb96fc92aa094bb8ca6383182de3a`. Original files backed up in `previews/main-webinput-1793315444-103774/`.

## Next step

Real phone/browser manual touch QA: open warning, confirm, create character, scroll action HUD, select an action, camera drag/zoom and verify save. Separately design left-click 3D object/NPC interaction; address CPU/WebGL frame-time stalls without weakening gameplay/security checks.
