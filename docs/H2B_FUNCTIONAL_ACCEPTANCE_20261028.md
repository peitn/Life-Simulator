# H2 / H2b functional acceptance — 28 October 2026

**Status: FUNCTIONAL GATE COMPLETE for the playable native Godot character editor.**
This is not a claim that the whole Life Simulator, H3–H8, final 3D visual polish,
or every network stress scenario is finished.

## Deliverable (actual code and UI)

The main-game HUD **Upravit postavu** entry opens a real transactional
`CharacterEditorPanel` for an offline character or the authenticated
ENet host/client owner. The panel contains an isolated `SubViewport`
character preview, continuous personality and psychological sliders,
appearance controls, all five outfit contexts (`bezne`, `pracovni`,
`spolecenske`, `spani`, `sport`), independent top/bottom/shoes selectors,
and subculture presets including the pink cat-ear hoodie.

- Draft edits, Undo and Redo never write live character state.
- Cancel closes the panel and discards uncommitted changes.
- Apply is validated against server-owned state/revision and only successful
  changes refresh the live appearance.
- In native ENet, the owner receives an authenticated private read,
  sends one bounded Apply request, and receives a canonical private readback;
  non-owners cannot read or modify the private character record. Only
  validated public appearance is broadcast.
- Server and client must both enable native editor RPC support. With explicit
  programmatic `net_config`, `network_character_editor` is opt-in; the
  native CLI launch follows the existing default. Browser ENet is not claimed.
- Offline private sexuality fields are editable under strict validation;
  identity/name/gender/grammar migration remains separately constrained.
- Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z, Ctrl+Enter, Esc shortcuts are wired.
  The action footer reflows 4 columns on desktop / 2 at narrow widths;
  constrained inner content can scroll horizontally so Apply/Cancel remain
  visible at a tested **320x600** viewport, as well as desktop sizes.
- During an in-flight server Apply / canonical readback, all draft mutations
  (Undo/Redo, appearance/personality sliders, garment changes, styles) are
  guarded; the footer buttons are visibly disabled and the draft is hidden.
  Explicit read-only/feature-gated sessions may still adjust a local draft,
  but cannot Apply. A revoked owner or changed network mode fails closed.

## Direct verification on the live `lifesim` project

All listed test commands were **actually executed in Godot 4.7.2**, not
inferred from scheduler triggers. Successful suites ended with **exit=0**
and without timeout. Counts are pass/fail assertions, not estimates:

| Test source | Actual result |
| --- | ---: |
| `tests/test_character_editor_ui.tscn` — real HUD, 320px footer, keyboard, draft, wardrobe, Apply/Cancel/Undo | **62/62** |
| `tests/test_network_editor_live_enet.gd` — real ENet owner UI, in-flight guard, canonical readback, conflict, disconnect | **58/58** |
| `tests/test_character_network_panel.gd` — feature gate, pending/late/disconnect read cleanup | **24/24** |
| `tests/test_character_edit_read_enet.gd` — private owner-only network read | **53/53** |
| `tests/test_character_edit_apply_enet.gd` — Apply, public resync and incarnation checks | **97/97** |
| `tests/test_character_edit_ownership.tscn` — server authorization, revisions, stale rejection | **75/75** |
| `tests/test_character_edit_session.tscn` — transactional draft | **30/30** |
| `tests/test_host_character_editor.tscn` — actual native host HUD/owner | **10/10** |
| `tests/test_character_preview.tscn` — isolated actual model, clothing, normal/narrow layout | **13/13** |
| `tests/test_appearance_slider_ui.tscn` — anatomy/appearance controls | **108/108** |
| `tests/test_personality_sliders.tscn` — continuous personality and psyche | **24/24** |
| `tests/test_subculture_wardrobe.tscn` — authored wardrobe and cat hoodie | **14/14** |
| `tests/test_adult_sexuality_editor.tscn` — offline-only private preferences | **24/24** |
| `tests/test_character_net.tscn` — multiplayer privacy, respawn and incarnation | **70/70** |
| `tests/test_character_edit_commit.tscn` — validated server commit | **28/28** |
| `tests/test_full_playable_slice.tscn` — creator, playable home and persistence | **45/45** |
| Godot GDScript syntax check | **60/60 scripts** |

Existing shutdown warnings of roughly 18 leaked ObjectDB instances are
observed and not attributed to this patch. No test assertion failed in
the final checked suites.

## Review and remaining boundaries

Gemini performed a skeptical review of the editor's in-flight race, footer
layout and keyboard usability before the fixes. All three were addressed
and covered by new tests. Network security is still bounded by the actual
tested transport/authority contract; this is not a security certification
against every packet-loss or reconnection edge case.

**Pixel-by-pixel rendered screenshots remain UNVERIFIED.** The connected
Godot tool uses the headless display driver; attempted `frame_post_draw` /
viewport image capture timed out. Stalled screenshot workers were
terminated and coordinator process visibility checked. Actual Godot UI
tree, button rectangles, isolated 3D model instance, authored garment
geometry and preview-to-live equality were tested; never interpret those
as independently viewed screenshot QA. Front/side/back model renders,
visual clipping and performance measurements belong to **H6**.

This milestone does not implement identity index migration in a live editor,
browser multiplayer ENet, H3 household flows beyond existing smoke tests,
or H4 complete save-state fidelity.

## Exact source changes in the final H2b pass

- `scripts/ui/character_editor_panel.gd`: narrow responsive footer,
  scrollable narrow body, keyboard shortcuts, centralized guarded
  draft-mutability checks, busy-state footer protection.
- `tests/test_character_editor_ui.gd`: 320px footer, keyboard and Escape
  functional checks through the real HUD.
- `tests/test_network_editor_live_enet.gd`: explicit in-flight Undo/Redo,
  slider, appearance, outfit and style mutation denial in actual ENet.

Production `scripts/net/net_session.gd` was intentionally **not changed**.
The older server owner-only protocol and revision validation remain the
authority of record. GitHub was kept **read-only**; no city-owned paths,
Blender projects or AI Room messages were modified.

**Next milestone:** H3 — end-to-end character creator to actual household,
identity/grammar/body/personality/psyche independence and preview parity.
Do not keep reopening H2b for unrelated H6 visual polish or H4 persistence.
