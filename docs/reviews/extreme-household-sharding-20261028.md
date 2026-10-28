# Extreme fictional household: profiling and sharding (28 October 2026)

Run: `main-claude-sched` (scheduled Claude run). Scope: the open finding from the rollback
recovery — `test_extreme_fictional_household` exceeded its 110 s watchdog.

## Measurement (before any change)

Sandbox, Godot 4.7.2 headless, 2 cores, GitHub `791cf3d`:

- One 14-day case (8 NPCs, 720 two-minute ticks per day, day-7 disk save/reload) took **48.8 s**
  (`low_support`, seed 3). Four cases therefore need ~200 s, far above 110 s. On 25 October the
  same case took ~34.5 s; psyche slices A–J added roughly 40 % per tick.
- Temporary instrumentation of `SimAgent.sim_tick` (reverted, never committed) gave the share of
  the measured time per segment: decision/walk/act 20.9 %, `mood.evaluate` (incl. moodlets from all
  psyche systems) 15.1 %, `_mental_tick` 13.5 %, `emotions.tick` 12.3 %, `_psyche_tick` 12.2 %,
  `ledger.decay` (incl. two `Traits.mult_param` look-ups) 5.5 %, net fields 4.7 %, cravings 3.0 %,
  household dynamics 2.2 %, the rest below 2 % each. Each marker costs about 1 µs, so small segments
  are dominated by instrumentation overhead.
- Conclusion: there is **no single hotspot**. A 2× speed-up would mean restructuring many systems,
  with a real risk to the exact-determinism checks used by save/reload and household tests. That is
  not a one-run change and was not attempted.

## Change

`tests/test_extreme_fictional_household.gd` only; simulation code is unchanged.

- The watchdog is derived from the measured cost: 35 s + 75 s per selected case per 14 days
  (one shard: 110 s; full four-case run in one process: 335 s; `--control` pair: 185 s).
- `--owner-run-id=main-…` writes one JSON report per shard to
  `previews/testlogs/extreme_household_<run>_<scenario>_s<seed>_<cp|ctrl>.json`. The write requires
  current ownership of the v3 automation lock (same rule as the household matrix); invalid run IDs
  are rejected. The report contains the result, Raven's metrics, the SHA-256 of the canonical final
  state (`JSON.stringify(sort_keys, full_precision)`), the number of simulated agents in it and
  SHA-256 provenance of seven source files (test, fixture, `main.gd`, `sim_agent.gd`,
  `mental_state.gd`, `household_dynamics.gd`, `game_save.gd`).
- `--control-only` runs the uninterrupted (no save/reload) case in its own process.
- `--aggregate=main-…` runs no simulation. It requires all four checkpointed shards (passing,
  one save, 8 agents, no bad floats, matching run ID, kind and days, 8 agents in the final state)
  produced by the current sources, at least one control shard, and identical final-state hashes
  for each control and its checkpointed case. It then prints the descriptive Raven comparison.

## Verification (sandbox)

Four checkpointed shards 15/15 each (46.9–48.3 s), control shard 12/12 (44.8 s), aggregate 12/12.
Negative checks: a report tampered to `ok=false` fails the aggregate; a control with a different
final-state hash fails; invalid aggregate and owner run IDs fail; a shard without lock ownership
cannot write a report. Server results are recorded in `AUDIT.md`.

## Independent review (Gemini, 28 October 2026)

Accepted: an empty final state would hash identically → reports now carry `final_state_sims` and the
aggregate requires 8. Disputed with reason: path injection through `scenario` (only the constant
`SCENARIOS` values reach the path), lock TOCTOU (the v3 coordinator serialises ownership checks
under an `fcntl` gate and each shard writes its own file), JSON argument order (verified against
Godot 4.7: `stringify(data, indent, sort_keys, full_precision)`), corrupt JSON crashing the
aggregate (`parse_string` returns `null`, which is a failed check). Noted limitation: the control
comparison is exact only on the same machine/build; shards should run sequentially on the server
so that CPU contention does not eat into the per-shard budget.

## Open

Performance itself is unchanged. If the per-tick psyche cost keeps growing, a profiling-driven
optimisation pass (caching trait multipliers, skipping net fields offline) should come with
before/after determinism proofs.
