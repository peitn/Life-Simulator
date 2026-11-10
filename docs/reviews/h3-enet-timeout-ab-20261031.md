# H3 — controlled ENet timeout A/B (31 Oct 2026, main-fallback-1793481246-54334)

Status: **FAILED/PARTIAL**, test-only diagnostic; NOT a production multiplayer fix.

## Scope and change
- `tests/diagnostics/h3_three_process.FAILING.gd`: optional `enet-extended` CLI mode, calls `ENetPacketPeer.set_timeout(32,30000,60000)` for each connected server peer and client-server peer, with boolean-only confirmation trace. Guarded against accessing get_peer() after transport shutdown. Original 17 assertions and time limits unchanged. Production `scripts/net/net_session.gd` untouched.
- `tests/diagnostics/h3_bounded_runner.py`: allows bounded `enet-extended` mode. SHA/ownership preflight, 105s hard cap, verifies child PIDs and cleans verified descendants.
- No changes to city-owned paths, Blender, GitHub, AI room, production gameplay or user saves.

Godot 4.7.2 ClassDB confirms ENetPacketPeer has `set_timeout(timeout,timeout_min,timeout_max)` but **no timeout getter**. The value 32 is the timeout limit, **not a peer count**. The experimental override is not proof of the original default. The callback logs confirm that override code executed, not internal ENet effective state.

## Real execution (3 separate child Godot OS processes per run)
- Cold (same new fixture, no override): **8/17 PASS, 9 FAIL**, exit=1, 66.43s, runner timeout=false, 3 children, zero survivors. Server owner disconnect 10.265s after peer_connected, kicked=0. Owner readiness failed after 23.659s with max process-frame gap 18.409s.
- Extended before callback guard: **12/17 PASS, 5 FAIL**, exit=1, 46.11s; repeat **12/17 PASS, 5 FAIL**, exit=1, 47.10s. No runner timeout, 3 children, zero survivors. Both show override-applied traces on server and clients. First owner readiness failed after 27.694s, max frame gap 22.685s; server peer exit 27.667s after connection (consistent with subsequent explicit owner shutdown; do NOT label this a transport timeout).
- Final guarded extended run: **12/17 PASS, 5 FAIL**, exit=1, 52.10s, no timeout, 3 children, zero survivors; previous diagnostic `get_peer() on inactive ENet` error eliminated. Five failures: owner_read_ready, owner_read_sent, owner_initial, server_initial_diag, owner_done.
- All extended runs still have multi-second frame starvation; their success-count improvement does **not** complete H3 or prove transport default values. Cold vs extended are not matched deterministic trajectories and sample size is small.
- Production ENet `test_character_net` **97/97 PASS** twice, exit=0, 21.4s on first; Godot syntax **60/60 PASS**; fixture load PASS. Production ENet shutdown still prints pre-existing ObjectDB leak warning (20). Extended diagnostic stderr has `Unable to send packet ... max channels: 0` during peer teardown; unresolved and NOT clean stderr. Cold fixture has inactive multiplayer get_unique_id warnings.
- Remote initial backup success: project 405786KB and library 123493KB. Local SHA-checked pre-edit backups in `previews/automation-backups/main-fallback-1793481246-54334-pre/`. Final remote backup and lock release are recorded in run history, not presumed here.

## Skeptical Gemini audit and independent checks
Gemini twice reviewed the method and results. Valid caveats: no getter for original timeout, only one cold baseline, nonidentical process scheduling, extended timeout may mask an unresponsive client, root cause remains long blocking client initialization. Independent source/API inspection confirms `set_timeout` signature and callback mode. Unsupported Gemini assertions (that the first argument 32 is number of peers; that setter causes a proven main-thread stall; that longer peer lifetime proves default timeout) were rejected. Original 17 gates not weakened. No private user data sent.

**Single next step:** implement a test-only staged client `SimVisual` construction prototype that yields to the network event loop between expensive asset-building phases, preserving all 17 acceptance gates and comparing frame gaps/peer survival before any production change.
