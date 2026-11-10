# Life Simulator -> The Sims 4 Psychology Alpha, 2026-10-30

Status: first executable PORTABLE psychological module + standalone editor +
Sims 4 command-bootstrap CANDIDATE. Not a fully playable Sims 4 mod, no
actual EA game binary installed or tested in this environment.

Implementation root: integrations/sims4/source/
Manifest: integrations/sims4/source/lifesim_psyche/catalog.json
Original generated catalog: integrations/sims4/source/lifesim_psyche_catalog.json
Source-of-truth Godot: CharacterSchema v20, EmotionalState, Worldview,
SocialMemory, Traits, PsycheModel, and related GDScript simulation files.

Actual generated counts: 103 numeric psychological sliders + 3 bool switches
(106 total configurable fields), 19 emotion meters, 13 social memory kinds,
9 worldview topics, 7 core values. The manifest also includes all current
named emotion-event effects and legacy trait IDs. Privacy labels stay private.
A prior interim answer used "106 sliders"; strictly it is 103 sliders and
3 boolean flags.

Implemented portable Python 3.7-compatible domain kernel in
lifesim_psyche/core.py:
- independent per-Sim continuous personality, belief and psyche fields;
- simultaneously active emotions with event-specific impulses and
  actual game-minute exponential decay;
- directed emotions, crying start/stop hysteresis, separate self-defectiveness;
- source-aware social episodic memory (self/witnessed/told), interpretations
  separate from fact, memory strengths/retention/decay, opposite-event
  weakening and bounded size;
- independent asymmetric warmth/trust/grudges, multiaction scoring,
  non-forced social outcomes;
- changing worldview attitudes with baseline drift caps and certainty;
- local privacy-preserving JSON, strict profile patch import and bounded inputs.

Built separate offline companion HTML editor using the same generated catalog
with 103 sliders, 3 flags and 19 emotion controls, search/grouping and
profile_patch.json import/export. Not a Sims in-game UI.

Created candidate LifeSimPsychologyAlpha.ts4script with Python source ZIP:
module bootstrap, core, catalog, storage, profiles and safe console commands
lifesim.help/list/inspect/set/emotion/event/link/talk/tick/save/load/import.
Command registration validated with MOCK Sims4 commands only; actual Sims4
import, active SimID, gameplay hooks, buffs, autonomy, in-game editor, native
persistence still pending. No .package tuning assets were invented.
Python 3.7 AST parse checked for all source modules.

Project tests:
- 18 tests of original category counts, emotion dynamics, memory,
  worldview, independent axes, guardrails, persistence and editor patch;
- 1 additional mocked Sims4 console-command test (12 registered);
- 19/19 passed, Python tests exit 0.
Archive ZIP checked with ZipFile.testzip() == None (valid).
Remote links HTTP200:
https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyAlpha.zip
https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyEditor.html
https://peiti-godot-mcp.hf.space/play/lifesim/lifesim_psyche_catalog.json
SHA256 release ZIP: 5dfc651ffe0bf3c7e1bf... (exact full digest from release file)
Size ZIP: 54085 bytes.
HTML embedded JSON parsed as 106 entries (103 numeric), 19 emotions.

Important engineering constraints:
- The Sims4 scripts are Python 3.7, not Godot GDScript.
- Python mod ZIP is a candidate until tested against an actual current TS4.
- The game does not load Godot Scene3D, FCCS or GDScript automatically.
- No player medical data or real-life attributes ingested.
- No new self-harm gameplay commands or diagnostic automation.
- The Sims4 mod cannot be played on a pure web browser.
- Original Godot playable build is not altered by this first port.

For next development: real TS4 bootstrap test and native SimsInfo event APIs,
tuning resources for moods/traits/sentiments, native interaction event
adapters, read-only validation of available game info and 1:1 save migrations,
UI menus for character psychology with Apply/Cancel/Undo, household performance.
