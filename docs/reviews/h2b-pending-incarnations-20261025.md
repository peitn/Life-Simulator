# H2b pending incarnation audit — 2026-10-25
Run main-1792911520-152521.
Scope: scripts/net/net_session.gd and tests/test_character_edit_apply_enet.gd only, plus documentation.
Before: one pending packet per node name; new-instance packet followed by old-instance packet causes loss at spawn despite correct incarnation corruption guard. Actual pre-fix test67pass1fail exit1.
After: bounded node-name -> incarnation -> latest validated full snapshot. Two variants/name; name count <=spawner.spawn_limit. Revision comparisons only per incarnation. FIFO by incarnation introduction (updates don't change order), spawn selects exact authoritative token and clears variants, disconnect/despawn clear state.
Tests: target73/73, production70/70 exit0, no timeout. Both arrivalorders, private/stale rejection, fourincarnation pressure retains lasttwo, name budget, disconnect cleanup. Existing18ObjectDB warnings.
Gemini received real before/after source and focused tests, then final additional code/results; two actual responses. Initial low empty-map defect disproved: erase is immediately followed by insert synchronously, no yielding path; capacities and noemptyentry verified. Gemini retracted. Duplicate erase harmless but removed. Broad praise not treated as security proof.
Focused harness uses real ENet but explicit callbacks and stub World. Separate production suite runs actual hello/spawner/reusedname/repeatedApply. Neither proves arbitrary jitter/spawner timing combinations.
Known limitation: finite retention can evict needed snapshot with >2incarnation histories; full recovery requires bounded authorized public resync. No automatic resync in this patch. No new UI/render, production remote editor flag false. Keep H2partial.
