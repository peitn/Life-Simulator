# Sims 4 Psychology Alpha 0.3 — panic attacks and private crisis model (30 Oct 2026)

## Scope
Developed in independent `integrations/sims4/source/` branch of Godot
Life Simulator project, NOT a patch to the game's runtime 3D scenes.
Source of truth for inspiration: `scripts/sim/mental_state.gd` and
`scripts/sim/sim_agent.gd`. Existing Godot game already had panic episodes
with fear/arousal thresholds, cooldown, grounding and optional offscreen
privacy-masked self-harm incidents. The Sims 4 portable Python kernel
did not yet have those mechanisms.

## Implemented
- `lifesim_psyche/crisis_states.py`: independent per-Sim panic state,
  strong fear PLUS high general arousal PLUS threat PLUS stress, modulated by
  anxiety predisposition and self-regulation. A person may have high fear
  without panic, pleasant arousal does not trigger panic.
- Episode lasts 5–25 simulated minutes with 360 minute cooldown, recovery
  period and per-Sim panic count, optional private notices; actual panic is
  an episode state, not a new psychiatric diagnosis.
- Support API: grounding, trusted person, quiet space and professional support;
  modest changes in fear, perceived threat, arousal and distress, but no
  instantaneous guaranteed resolution.
- Private distress/SH urge indicator derived from several current fictional
  states; high value itself is NOT proof of intent or a real behavior and does
  NOT trigger SH or any autonomous gameplay action.
- Optional non-graphic `implied_sensitive_incident` narrative marker:
  only on a verified external, local/private, explicitly opted-in event for
  a verified adult with content mode `full`. Full is offscreen ONLY. Mode
  defaults to `muted`, also `off` available. Never includes injuries,
  techniques, objects, graphic content or numeric gameplay rewards.
  No console command to trigger this incident.
- Private state save/load with strict validation and backward compatible
  default crisis state for older data; no public/client data replication.
- Extra mock Sims4 commands `lifesim.crisis` (private state read),
  `lifesim.support` and `lifesim.content`. These do not directly modify
  vanilla Sims 4 buffs/animations.
- Standalone web editor: content mode option off/muted/full,
  adult-restricted full, explanatory panel. Export/import
  `profile_patch.json` carries `crisis_content` and age gate.
- Prior catalog counts preserved: 108 numeric + 5 bool fields,
  19 concurrent emotions and 6 additional meters; 13 social memory kinds.

## Verification
- 44/44 Python 3.7-compatible unit tests passed, including 12 crisis
  regressions and one deterministic 8-Sim/7-day stress test (all 8 private
  state objects stable, no auto-harm incidents and bounded metrics).
- Entire source Python3.7 AST parse, zip archive and .ts4script repack.
- Candidate ZIP: 87,568 bytes,
  SHA256 7b2ad1fbfdf3bfb697eb1715fd6992ef85b1d06423f45a0061ae706a6067c2a6.
- Editor 37,248 bytes; 113 configurable fields, 19 emotions and six
  dynamic meters plus mature content selector.
- Source: `integrations/sims4/source/`, release artifacts in
  `integrations/sims4/source/release/` and HF web exported assets.
- Actual interactive TS4 engine, true SimInfo age identity, native game
  emotion buffs and native gameplay outcome callbacks are NOT validated.
  Offline unit tests and mocked console commands cannot establish these.

## Real game event integration research / next step
Documented Sims4CommunityLibrary API supports
`S4CLInteractionOutcomeEvent.is_success()`, which could distinguish a
performed real interaction from a queued/failed one; it also offers
`CommonEventRegistry.handle_events()`. Source:
https://sims4communitylibrarywiki.readthedocs.io/en/latest/sims4communitylib.events.interaction.events.html
Actual ModInfo identity, exact tuning IDs for friendly/argument/comfort,
S4CL presence and the active game patch MUST be verified in a real installed
Sims 4 before installing the bridge. No direct game hook is falsely claimed.
Then add real Sims interaction→ emotion impulses → panic-risk model →
support action menu/buffs, and in-game UI/privacy warnings.

## URLs
Editor: https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyEditor.html
ZIP: https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyAlpha.zip

## Product/safety limitations
No clinical validity claimed. No automatic causation from a diagnosis or
identity. SH urge scoring is a fictional alert, not a prediction of real
behavior. Content option 'full' still omits visible harmful acts, method
descriptions, tools and glamorization. Players may disable sensitive content
without disabling ordinary relationships or emotional system.
