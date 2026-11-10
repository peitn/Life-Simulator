# H3 three-process frame/marker/peer probe — 2026-10-31

Run: `main-fallback-1793405349-9319`. Status: **DIAGNOSTIC CHANGE IMPLEMENTED; H3 ACCEPTANCE FAILED**.

## Exact change
Only test source `tests/diagnostics/h3_three_process.FAILING.gd` changed (SHA-256 605cce18a4da909c8b367c227fe867626231b3842a75a22efc9a8b4cb1cef8cb -> f8cd61979bce03bb4ea1aacc62d2f4939b5edea96bce507cab26a354f3dfe09b). Added bounded `_probe_marker` that records wall-clock elapsed time, inter-frame maximum gap, number of process frames, marker file existence and JSON visibility, current ENet peer IDs and connection flag once per second and on first marker visibility. Replaced only the server's wait for `owner_read_ready` and owner's wait for `server_read_gate`. Production gameplay, network RPC, city paths, GitHub, Blender and AI room unchanged.

## Real tests
- Godot syntax checker: **60/60 PASS**.
- Actual isolated 3-OS-child-process Godot/ENet H3 diagnostic, first: **12/17 FAIL**, exit=1, timed_out=False, 52.6s.
- Same diagnostic, second: **7/17 FAIL**, exit=1, timed_out=False, 70.5s.
- Existing in-process production ENet regression `tests/test_character_net.tscn`: **97/97 PASS**, exit=0, timed_out=False, 19.8s. Known ObjectDB 20 leak warning persists in headless runs. Diagnostic stderr included `The multiplayer instance isn't currently active` after peer disconnect, not a clean run.

## Observations and limits
First test: owner welcome at UTC ms 1793405471001, first owner marker probe at 1793405490159 (19.2s later); server had already logged owner peer disconnect, and marker arrived after peer removal. Server maximum measured inter-frame gap 4700.1ms. Owner's rejoined private read succeeded; observer's forged read was denied.

Second test: owner welcome at UTC ms 1793405570748, first owner marker probe at 1793405587988 (17.2s later); server maximum measured inter-frame gap 5638.2ms, its peer list empty before marker arrived. Initial ACL and private read failed. Observer was disconnected and second forged-read scenario could not complete. The two tests vary, so the fixture remains non-deterministic.

The marker file is **not** shown to have been written early and delayed by the filesystem. Current trace instead shows the owner only reaching its probe after a long interval following welcome; where the time is spent is unproven. Large frame gaps show scheduling stalls, not by themselves proof of CPU saturation or a production network bug. No real three-process privacy certification is claimed.

## Skeptical Gemini audit
Gemini correctly warned that the evidence does not prove a production bug and recommended instrumentation around the owner's pre-probe wait/initialization. It overclaimed that a main-thread hang or filesystem release after disconnect was proven; neither follows from the trace. Standard Godot API calls in `_probe_marker` were validated by actual compilation and execution. No sensitive user data was sent.

## Next ONE step
Instrument the owner's `wait_until(my_sim && find_sim)` entry/exit and the time from welcome to character puppet visibility, without changing production RPC, then repeat the 3-process diagnostic to isolate the 17–19s pre-marker delay.
