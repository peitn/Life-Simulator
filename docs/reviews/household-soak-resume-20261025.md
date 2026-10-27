# Long household stress tests — 25 October 2026

**Authoritative source:** live Godot project `lifesim`. **Scope:** offline headless stress testing; no claim of GUI/export/multiplayer performance.

## Setup and lock
The user asked for household stress testing, expecting H4 persistence to remove prior runtime limits. At first inspection the v3 exclusive project lock belonged to the city job, so we **only ran unmodified read-only scene tests**. The lock later became free; run `main-stress-save-1792947339-183314` acquired **main** successfully, backed up the Godot project and Blender library, then added two new isolated test scenes and this documentation. Only current main owner may mutate project files; all writes were ownership-checked, hash-checked, and release is required.

## Actual test results

### Existing crowded household — 50/50 PASS
`res://tests/test_crowded_household.tscn`: **50 passed / 0 failed**, `exit=0`, `timed_out=False`, about **70.3 s** runtime (Godot v4.7.2). Two 7-person fixtures (healthy and psychologically vulnerable) × two random seeds × 14 simulated days = **4 complete scenarios** (56 household-days; 392 character-days).
- Healthy7 seed0: 34% arguments, seed1: 18%.
- Stress7 seed0: 29%, seed1: 27%.
- Each passed the existing fixture-specific 10–40% argument bounds, no chronic low-average-needs collapse, no permanent maximum depression, max two drinks per character/day. Healthy scenarios did not accumulate excessive extreme stress. Unit probes for sensory sensitivity/habituation, alcohol tolerance, rebound, panic cooldown and noise rules passed.
- The ordinary successful run still reported an existing shutdown warning about 18 ObjectDB instances.

### Existing household dynamics — 16-seed complete simulation, final test timed out
`res://tests/test_household_dynamics.tscn` with requested `seconds=280` was **hard-killed at 120 seconds by the remote tool** (`exit=None`, `timed_out=True`). The 16 seed simulations **ALL finished** (16 × 14 days with 3 agents = 224 household-days / 672 character-days), including all printed aggregate assertions up to `== Determinismus`, but the last replay block was interrupted. Therefore **do not count this original test as a complete PASS**. The timeout is a connector execution cap, *not fixed automatically* by autosave.
- 1,674 conversations, average argument share **29.1%**, SD **6.8 percentage points**, min **14%**, max **39%**.
- Relationships: mean **+29.1**, min **−58**, max **+93**, no all-enemy spiral and no universal idyll. Relationship SD43.2, mean pair-level SD48.1.
- Mood-stratified argument share: good **18% of 938 talks**, medium **41% of 673**, poor **73% of 63**.
- 54 de-escalations, 98 complaint conversations with 41% complaints becoming arguments.
- 0 observed critically low needs (<10) and 0 observed stress>85 samples for this fixture. Random events **1.13 per person-day**. All displayed numerical invariants and non-pathological spread assertions passed before timeout.
- **Do not** present the raw `exit=None` as PASS or claim the last replay was executed there.

### Dedicated deterministic tail — 5/5 PASS
`res://tests/test_household_determinism_split.tscn` is a **new separate regression test**, reproducing the exact original seed schedule in `test_household_dynamics.gd` and same signature recipe: relationship values (4 decimal places) + stress per agent + JSON of household statistics. The 14-day simulation with seed3 replayed twice; exact signatures, 105 talks and 23 arguments both times. Different seeds 3 and 4 over two days had different signatures, as intended. **5/5**, exit0/no timeout, approximately24.3s. This independently closes the **logical** original trailing two determinism conditions, while the original monolithic test still times out.

### Thirty-day save/resume stress + never-saved control — 10/10 PASS
`res://tests/test_household_resume.tscn`: **7 psychologically vulnerable characters × 30 game-days**, private canonical H4 save-game file after every 5 days, then *dispose of the entire 7-character household*, spawn a new Godot Main and reload the actual on-disk save. Test-local slots are under `user://test-lifesim-soak-<PID>/`, **not** the player's `user://saves/`. Six checkpoints at days 6,11,16,21,26,31 were 105896,116564,123428,124728,127564,130668 bytes, each re-read and matched the complete captured snapshot exactly (`SaveGame.capture(world)["data"]`).
- A second **independent uninterrupted control simulation** of the same 7 agents × the same 30 days produced **exactly the same complete final save dictionary** as the six-times-resumed run, across clock, 7 minds, social relationships, active actions, object reservations, seeded RNG states and dynamics. Output: `SOAK_CONTROL equal=true differing_top= varying_agents=`. This is a stronger test than asserting successful deserialization alone.
- 606 talks, 136 arguments (**22.44%**), 720 hourly sampling points per character (5040 individual observations), no numerical out-of-bounds/NaNs, maximum fraction average-needs<20 = 0, maximum time depression burden>=0.95 = 0, maximum stress>85 = 0 in this specific scenario; no user-visible promise that every extreme persona will always be healthy. Agent action/event streams continued after every cold reload. Final `manual.lss.bak` verified.
- `test_household_resume` exit0/no timeout ~84.1s final with uninterrupted control, **10/10**. Its initial shorter saved-only run (9/9 in37s) is a preliminary step **not a distinct scenario** and should not be added to total test counts.
- Includes a hard `watchdog_seconds=105` guard; note external `godot_run` maximum was in practice **120s** despite requesting280s in another suite. If 30-day suite slows on different hardware, split it into two scenes or a persisted resumable CLI harness rather than pretending autosave changes tool caps.

### Combined certified suites
- Existing crowded: **50/50**
- New 30-day checkpoint + never-saved control: **10/10**
- New split determinism: **5/5**
- **65/65 PASS** across three completed suites (one original monolithic household suite remains TOOL TIMEOUT after all metric assertions, not counted).
- No production gameplay changes were required. Full H4 offline save/load was exercised in the new suite. Multiplayer H4/server-side persistence remains out of scope.
- All successful suites exited0/no timeout. Engine shutdown warnings for legacy ObjectDB tracked separately, do not label them a clean memory-leak test.
