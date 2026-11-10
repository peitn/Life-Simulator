# Sims4 psychology Alpha 0.4: completed-interaction event and conditional autonomy
Date 2026-10-30. Main project `lifesim`, held v3 lock
`main-ts4-real-autonomy-1793367879-183743`.

## Delivered
Continued the experimental Sims4 psychology code in
`integrations/sims4/source/` without changing Godot live game scenes.

**Portable autonomy** `lifesim_psyche/autonomy_director.py`:
Combines per-Sim personality/dispositions, situational emotion, trust,
memory, targeted relational context, understanding willingness, support
needs, and panic state. Generates scored recommendations for safe talk,
listen, clarify, confide and support, randomized from bounded weights.
No forced action during active panic, cooldown 35 game min per pair
and 12 min per actor, opt-in probability. Does not implement SH or intimate
actions; native Sims4 remains authoritative.

**Conditional S4CL game adapter** `ts4_s4cl_hooks.py` and
`ts4_live_bridge.py`:
Imports the actual
`sims4communitylib.events.interaction.events.interaction_outcome.S4CLInteractionOutcomeEvent`
class verified from current upstream source, subscribes via
`CommonEventRegistry.handle_events("LifeSimPsychologyAlpha")`,
uses `is_success()` and exact game tuning GUID64 to route to a
whitelisted event in `VerifiedSocialEventBridge`. Ensures actual
actor/target SimInfo IDs, unique completed interaction, optional
bounded advance of social model, no effect on failed/queued events.
For opted-in followups maps safe action to explicit validated real
Super Interaction GUID64; uses documented
`CommonSimInteractionUtils.queue_super_interaction(..., target=...,
skip_if_running=True)`. No guessed tuning IDs shipped.
Fails closed if S4CL absent/incompatible, no gameside exceptions
propagated into vanilla interaction.
A safe local in-game tuning observer can discover actual GUID64 of
successful interactions one at a time (`lifesim.observe on/list/off`).
`lifesim.bind outcome KIND ID` and
`lifesim.bind action SAFE_KIND ID` persist mapping,
and `lifesim.autonomy on/followup/off/status` controls behavior.
Restart *always disables* autonomous following (mapping retained).
Not a universal EA autonomy rewrite. Does not inject native mood buffs.
No native in-game CAS slider panels in this build.

**Documentation / game testing:** Detailed installation and exact
step-by-step commands in
`integrations/sims4/source/docs/s4cl-autonomy-alpha04.md`.
Actual Sims4 game process unavailable on connected Godot server,
thus TS4 runtime compatibility not asserted and no user device
playtest performed. S4CL is a separate dependency not bundled.

## Verifications
- Portable Python 3.7 syntax checking of entire source passed.
- **60/60 unit tests** passed, including a fake but real-API-shaped
S4CL event registry/dispatch and queue, whitelist/cooldown, positive vs
failed completion, mapping validation, panic/memory/identity/coping and
8-person/7-day simulations.
- Rebuilt `LifeSimPsychologyAlpha.ts4script` inside valid ZIP.
- Public ZIP `LifeSimPsychologyAlpha.zip` 109,685 bytes,
  SHA256 `2a09c810a0ddcf8551d7b22c455e4e60d492526005eb4855755ab982235978d0`.
- HTTP200 and ZIP integrity for:
  https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyAlpha.zip
- Offline editor unchanged, 37,248 bytes, HTTP200:
  https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyEditor.html
- Source URLs:
  https://sims4communitylibrarywiki.readthedocs.io/en/latest/sims4communitylib.events.interaction.events.html
  https://sims4communitylibrarywiki.readthedocs.io/en/latest/sims4communitylib.utils.sims.html
  https://github.com/DeviantGameMods/Sims4CommunityLibrary/blob/main/Scripts/sims4communitylib/events/interaction/events/interaction_outcome.py

## Remaining major gaps
Need a real installed The Sims 4 with S4CL to verify module autoload,
game patch API compatibility, exact tuning IDs, returned action queue
status, SimInfo age, and native mood/relationship buff side-effects.
Full native autonomy scoring overrides require separately verified
game-supported hooks/patches; this alpha only queues followups after
real successful mapped social events. No claim of full game coverage.
