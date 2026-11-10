# H3 three-process server registration phase probe — 2026-10-31

Run: `main-fallback-1793434651-23873`. Source of truth: live Godot `lifesim`; **H3 acceptance NOT achieved**.

## Actual scoped change
Only `tests/diagnostics/h3_three_process.FAILING.gd` changed (final SHA-256 `a7d9de5aa5d06476d922adfad477fc2a687ecbf41a7d4a244d30ed1a0da6ccae`). Fixture-only timestamp callbacks correlate server peer connection, player-character node entry, roster registration, and client connected→welcome. The second revision verifies that the last spawned node begins with the expected `Hrac<peer_id>_` prefix before attributing spawn deltas, emits `spawn_match`, and clears per-peer registration tracking on disconnect. Existing 17 acceptance assertions and their thresholds were not changed. No production, city-owned, Blender, GitHub, or room writes.

## Real executed evidence
- Initial diagnostic run after first patch: **8 PASS / 9 FAIL**, exit 1, 57.29 s, timeout false; three child processes, zero survivors.
- Final diagnostic run after Gemini-driven correlation guard: **8 PASS / 9 FAIL**, exit 1, 61.04 s, timeout false; three child processes, zero survivors. Final result stored outside project at `/tmp/lifesim_h3_1793434651_23873_final.json` (ephemeral, not a persistent backup).
- First owner registration: `spawn_match=true`, peer connected→child entered **11 ms**, child entered→roster event **4535 ms**, peer→roster **4546 ms**.
- Rejoined owner registration: `spawn_match=true`, **11 ms + 9 ms = 20 ms**. Observer initial connected→welcome **14 ms**; owner rejoin connected→welcome **27 ms**. In both sampled client welcomes, own puppet was not yet visible.
- Existing production ENet Apply/resync test: **97/97 PASS**, exit 0; Godot core syntax checker **60/60 PASS**; diagnostic script explicit `load()` PASS.
- Final diagnostic stderr: four `The multiplayer instance isn't currently active` messages at shutdown; separate runner exit warning: 20 known ObjectDB leaked instances. Neither is silently counted as clean stderr.

## Skeptical Gemini audit and independent verification
Gemini warned about falsely attributing the latest spawn to a peer, missed reconnects, timestamp heuristic, and absence of direct production timing probes. Accepted and mitigated the first two by checking the spawned node's canonical `Hrac<peer_id>_` prefix and clearing `seen` on disconnect; final trace explicitly confirms `spawn_match=true` for both registrations. Production `_register_player(id: int)` and `players[id]` use integer peer IDs, so the asserted string-key mismatch was not demonstrated. The callback/roster observations are **not proof of the root cause**; the 4.5 s interval includes any synchronous work after child entry (remaining character setup, visibility refresh, other callbacks), not necessarily a single blocking function. Wall-clock milliseconds can drift; treat these as measured intervals, not CPU profiling.

## Status and next single step
H3 **PARTIAL / FAILING**. Next: isolate the synchronous work between server `child_entered_tree` and `_broadcast_roster` with narrowly scoped opt-in timing around player-character spawn completion and visibility refresh in a controlled test, then rerun the exact three-process fixture before considering any production optimization.

Pre-edit full project+library backup succeeded (405737 KB / 123493 KB). Documentation-inclusive final backup and lock release are recorded separately in run history.
