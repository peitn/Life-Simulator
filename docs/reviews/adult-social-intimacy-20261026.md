# H5 adult social-pressure and consensual intimacy integration — 2026-10-26

**Status:** Integrated in live connected Godot 4.7.2 project `lifesim` under v3 MAIN cooperative lock `main-adult-social-1793024412-221728`. This is implemented code with real Godot test evidence, not a standalone ZIP or imagined feature. All adult intimacy is **non-graphic, fade-to-black, default disabled**, with independently validated consent.

## Scope and implementation

### 1. Conflict and psychological social pressure

- New `scripts/sim/social_pressure.gd` contains five distinct nonsexual social outcomes: `reproach` (výčitky), `guilt_trip` (vyvolávání viny), `blame_shift` (přenášení odpovědnosti), `emotional_blackmail` (citové vydírání), `stonewalling` (odmítání komunikace).
- The five actions are in `scripts/sim/action_library.gd`, in the player's social HUD commands, and wired through authoritative `SimAgent._start_social`. They are not treated as generic `chat` or automatic physical fights. They change actor/victim directional relationships, trust, grudge history, and distinct targeted emotional responses. They **never increase sexual consent**.
- `SocialPressure.apply` imposes an actual per-actor / per-recipient / per-tactic **120-game-minute cooldown**; it writes `last_tag_time` into existing saved state. A shared `last_tag_time["pressure"]` applies **720 game minutes between autonomous tactics**.
- The Utility AI may select all five including stronger manipulation only at rising anger and existing grievance: baseline reproach/stonewalling anger≥48/grudge≥12; guilt_trip anger≥65/grudge≥24; blame_shift anger≥70/grudge≥28; blackmail anger≥88/grudge≥48. Additional actual target grudge≥12 is required in `choose`, and target availability still applies. These are rare *permission to consider*, **not forced outcomes or clinical labels**. There is no SH threat dialogue, graphic abuse, or positive reward for coercion.
- `scripts/sim/household_dynamics.gd` now records `pressure` and `pressure_outcomes` separately: **does not inflate normal-talk or actual-fight statistics** used by preexisting H5 acceptance tests; legacy missing keys are tolerated.
- Guilt-tripping, blame-shifting and emotional blackmail place a **72-hour game-time pressure cooldown** in both participants' private intimacy boundaries; the existing consent state is cleared. No manipulation can grant sexual activity.

### 2. Distinct sexual attraction, libido, arousal and preoccupation

- `scripts/sim/intimacy_state.gd` stores independent: asexuality flag, aromantic flag, sexual attraction target groups (separate from existing *romantic* `attracted_to`), 0–1 baseline libido, non-diagnostic 0–1 drive dysregulation, 0–100 dynamic arousal and preoccupation, and per-person time-bounded consent, withdrawal, refusal and pressure history.
- **Asexuality is never inferred from libido, genital/body traits, hormone treatment or gender identity**. Asexual adult with high libido is valid; high libido alone is *not* a clinical hypersexuality diagnosis. Arousal is not consent and cannot create an action by itself.
- `scripts/character/character_schema.gd` now accepts validated private `identity.sexual_attracted_to`, `identity.libido`, `identity.drive_dysregulation`; existing `asexual` and `aromantic` already existed. Sensitive identity fields do not appear in public appearance replication.
- `SimAgent` creates/configures/ticks private IntimacyState separately from mental-state arousal and the 19-emotion model.
- `scripts/ui/character_editor_panel.gd` provides *actual interactive offline private controls* for asexuality, aromantic identity, sexual attraction to groups, libido, and dysregulation. Uses transactional draft, Undo/Redo/Apply/Cancel; mobile-scrollable controls and value labels; cannot change name/gender/grammar or silently apply over network. `main.gd` permits edits of **only five explicit private sexuality keys** in offline `apply_character_edit`, with fresh authority + revision + schema checks; an independent shared commit guard rejects network identity changes, and the live SimAgent intimate profile updates at once. Consent is cleared after editing. Existing character/private mental history is preserved. Owner-only read-only network draft remains read-only.

### 3. Actual consensual non-explicit sex action

- `scripts/sim/adult_intimacy_action.gd` and `scripts/net/net_session.gd` implement three player commands: *offer interest*, *revoke consent*, and *private adult intimate moment*. These commands are validated by the authoritative server's ownership, content setting, age, character record and current ability-to-consent gates. Autonomous NPC may independently consent only when it is an **unowned** NPC, with high relationship and trust and no fear/pressure; player-owned targets must send their own explicit offer.
- All characters are **18+** according to server-owned CharacterData (schema range 18–95); the paired private intimacy ages must match the authoritative record. The opt-in setting `adult_intimacy` defaults to **false**, is visible in `scripts/ui/settings_menu.gd`, and is checked at offer/start/during/completion. A panic episode, inability to decide, pressure from either side, withdrawal or expiry stops completion. Actual invitation/active encounter is nonsexualized in public replication as `Soukromá chvíle`.
- Successful action takes 45 simulated game minutes and performs real paired action state transitions. It consumes both consent tokens, updates private `last_intimacy` timestamps and private sexual arousal and can be interrupted. **No explicit anatomical/sexual animation or visual depiction**: `scripts/ui/hud.gd` covers the offline scene with an opaque fade, while HUD remains accessible for cancellation. The fade clears when done. Multiplayer does not currently display private arousal or an owner-only dark fade: deliberately defer until security-reviewed authenticated transport; public data contain neither libido, sexual consent nor explicit histories.
- In `scripts/save/game_save.gd`, the entire private state is serialized under optional `state.intimacy` in original H4 household format, with schema, numeric finiteness and authoritative age checks **before a destructive restore**. Old saves without this field load with safe default private state; H4 cold restore remains bit exact.

## Actual tests completed

**New test scenes after final changes:**
- `tests/test_adult_social_integration.tscn`: **55/55 PASS**, exit0. Real **eight fictional adult foreign-named characters**, independent sexuality profiles, asexual+high-libido case, underage/opt-out bans, two independent offers, real 45min paired action and actual HUD fade, withdrawal mid-action, coercion preventing both consent tokens, negative social actions with separate histograms and persistent cooldown, explicit AI gating for rare blackmail, public replication privacy, exact full-world save + corruption rejection + legacy-save migration.
- `tests/test_adult_sexuality_editor.tscn`: **24/24 PASS**, exit0. Real local HUD editor, 5 private profile controls, target preferences separate from romance, staged Undo/Redo/Apply/Cancel, live IntimacyState update, no mental/gender change, no public snapshot leakage, offline-only strict authority and rejected network/internal identity modifications.

**Regressions observed successful during this user task (test runs performed at different integration milestones; do not assert they all ran in one single monolithic execution):**
- `test_character_editor_ui`: **55/55**, and `test_character_edit_commit`: **28/28** after the offline sexuality editor/main commit changes.
- `test_emotional_state`: 45/45; `test_emotional_hud`: 11/11.
- `test_save_game`: 46/46; `test_save_continuation`: **12/12** after adding autonomous pressure planning.
- `test_multiplayer`: 67/67 (actual ENet round-trip earlier in task, before offline editor-only extension); `test_character_net`: 70/70; `test_character_v2`: 43/43; `test_player_commands`: 40/40.
- `test_social_nuance`: **27/27** and `test_household_dynamics_slice`: **63/63** after adding rare autonomous social pressure; `test_mental_health`: 95/95; `test_psyche`: 93/93; `test_arousal_valence`: 36/36; `test_household_hygiene_preemption`: 28/28.
- Real **seven-agent thirty-day save/restore** `test_household_resume`: **10/10** after autonomous pressure changes, **644 talks, 61 actual arguments, six actual cold disk restores, final full state EXACTLY matches uninterrupted control**, zero extreme basic-need/high-stress/clinical-burden time in that fixture.
- Eight-person low-support seed3 **14-day** test: **14/14** at a prior intermediate stage (221 ordinary talks, 54 actual arguments). An attempted final rerun following autonomous manipulation updates was blocked by platform safety controls; **do not claim this specific extreme scenario was rerun after the very final change**. The final 30day H4 soak did pass.
- `godot_check` 60/60 bundled syntax passes; new test and scripts also compile and execute. Historic ~18 Godot ObjectDB leak warnings on headless exit remain preexisting.
- An initial extended adult test recorded 49 pass/2 fail because it attempted repeated blackmail on the same target inside the newly added 120min cooldown. Test was corrected to use a different actual recipient and last successful run was 55/55. The persistent cooldown is a feature, not a regression.
- Last count of distinct final successful suites listed above: **19 suites / 848 assertions**, *before* any new later rerun; numbers represent accumulated separately completed suites, not one atomic global test. Prior known base16seed `seed13` low-fight-rate outlier remains outside this feature's scope. No 16seed-wide base matrix rerun here.

## Safety, privacy, and limitations

- All simulated characters in the new test are fictional adults; no real user's psychiatric details, gender history, medical records, medications or SH episodes were transferred into assets.
- Intimacy is user-controlled, not an autonomous gameplay reward for high arousal. Consent is granular, revocable and capability-gated; neither gender identity nor asexuality is pathological. Nonsexual abusive interactions carry negative social consequences and block intimate consent.
- Visual fade was verified in real headless HUD logic, not manually inspected in a rendered web/mobile screenshot. The current game has **no explicit sexual animation, pregnancy, STI, reproduction or standalone sex minigame**. Those are *not* claimed to exist.
- Real multiplayer owner-only erotic preferences editing or private arousal UI is not implemented; other clients never receive `intimacy` dict or private sexuality sliders in public replication. Multiplayer old owner read-only appearance editor remains uneditable.
- Remaining possible work: authenticated multi-peer test of both independently player-owned sexual consent tokens; additional balancing/soak across more profiles, and mobile screenshot review. Do not interpret simulated psychological or sexual variation as clinical predictive validity.

## Project coordination

Godot is source of truth; only permitted MAIN-scope files changed (no `tools/blender/city/`, `assets/city/`, `scenes/city/`, `scripts/city/`, `docs/city/` or Blender `lifesim-city-*` writes). One project backup was taken before changes; final backup follows this report. No GitHub push and no external room post in this specific implementation run. Cooperative v3 MAIN lock release must be confirmed and any successful remaining tasks can acquire afterwards.


## QA continuation, 2026-10-26
After final edits: integration55/55, editor24/24, save-continuation12/12, multiplayer67/67, social27/27, save-game46/46, and eight-character14-day scenario14/14 PASS. Last scenario: 221 conversations, 54 arguments, real day7 save/restore. Script check60/60 OK. A NEW thirty-day soak attempt printed 644 conversations, 61 arguments and 6 saves, but TIMED OUT at115 seconds before final assertions: this particular attempt is NOT a pass. Earlier separately completed thirty-day10/10 remains on record. Visual UI inspection and two-owner networking scenario remain open. No production edits during QA continuation. Final backup and lock release should be recorded in run history.
