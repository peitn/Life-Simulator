# H2b: public appearance catch-up for late join (2026-10-25)
Run: `main-manual-latejoin-1792880528-129836`. Based on current Godot lifesim, building on the independently completed fallback public-appearance transport `main-fallback-1792880120-125362`. No city, Blender, GitHub or room modifications.

## Actual change
- `scripts/net/net_session.gd`: after authenticated hello / visibility refresh, selectively send the CURRENT canonical, strictly public-only appearance snapshot to newly introduced client peers for records with a nonzero revision. Existing initial spawner state is immutable/cached and could be stale after Apply.
- Buffer strictly validated server public-only appearance packets up to the existing spawner limit when a puppet has not spawned. Flush by `_on_spawned`, then set per-character monotonic revision and update the actual SimPuppet/SimVisual; drop stale revisions. Clean pending and revision maps on despawn, shutdown, connection failure and disconnection. Existing production remote Apply remains OFF.
- `tests/test_character_net.gd`: extend production hello/spawn/Apply test with eight hard assertions for two live clients, canonical revision, visual parameter equality, a third client joining after editing, its non-private snapshot and successful disconnect. This converts the formerly informational `H2B_PUBLIC_REPLICATION_CURRENT` print into a tested acceptance criterion.
- `tests/test_base.gd`: correct `wait_until` deadline to monotonic `Time.get_ticks_usec()`. Previously the TestBase Node's `get_process_delta_time()` can be zero when not processing, yielding an infinite wait on an unsatisfied condition (observed two timeout runs). No weakening of assertions or timeouts.

## Verification
- Final `tests/test_character_net.tscn`: **52/52**, exit=0, no timeout, real Godot 4.7.2 ENet server+clients. Verified that the late client's `look`, revision and 3D `look_params` equal canonical public state, and `has_private=false`. Connection cleanup works.
- Godot syntax checker: **60/60**. Existing 18 ObjectDB instance shutdown warnings; no unexpected test failures in final run.
- The first expanded test version hung because the original TestBase wait timeout never advanced; it was isolated and fixed, not counted as passed. A later attempt to inject artificial same-revision/private-wire RPCs in the same large fixture timed out; those extra tests were **reverted** and are **NOT certified**. Do not count any timeout or unsupported injection as passed.
- Skeptical Gemini read-only review actually completed against code/test excerpts. It confirmed catch-up pattern and suggested congestion, stale/malformed-message stress cases. Its speculative P1 memory leak concern is not demonstrated: pending map is bounded by spawner limit and cleared on despawn/disconnect/shutdown. Any such defect needs reproduction.
- No graphical GPU screenshot or narrow viewport captured. Assertions compare live SimVisual rendering parameters, not pixels. Production remote edit UI/Apply remains deliberately disabled.

## Next focused step
Test delayed/spurious packets with a dedicated finite-time ENet harness (not ad hoc RPC injection in the large suite), including rapid consecutive Apply, despawn/rejoin with reused IDs and late join during concurrent edit; then visually inspect rendered appearance and integrate guarded UI. H2b remains PARTIAL. GitHub publication requires separate owner approval; the historical one-off sync did not grant permanent permission.
