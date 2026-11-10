# H3 client SimVisual cold/prewarm A/B — 31 October 2026

Run: main-fallback-1793470349-48606 (v3 MAIN lock). This is a **diagnostic failed A/B**, NOT a production fix or passing H3 acceptance. Latest history had no primary MAIN productive completion in the preceding ~75 minutes. Initial remote backup succeeded: project 405770 KB, library 123493 KB.

## Exact changes
- tests/diagnostics/h3_three_process.FAILING.gd: optional client-only `prewarm` argument, creates one throwaway SimVisual per owner/observer process before the network world, measures elapsed monotonic time and verifies the node was freed. The 17 original acceptance assertions and production scripts are unchanged. SHA256 316f7a4182853ae0048313756e8e69216db3d8b2bbcb9ceb0f00cc87eab690be.
- tests/diagnostics/h3_bounded_runner.py: optional [cold|prewarm] mode with existing SHA/lease checks, timeout and verified descendant cleanup. SHA256 64566a059e3a5390777411663dd0e89cb44e7fe0ea2d8c7586ae0b41ffe325cb.
- This report, CHECKPOINT.md and DEVLOG.md. Local pre-edit recovery copies in user://. No production, city-owned, Blender, GitHub or AI-room changes.

## Actual test evidence
- Godot 4.7.2 syntax check: 60/60 PASS, no parse errors.
- Cold real H3 3-child-OS-process test: **8/17 PASS, 9 FAIL**, exit=1, 59.13s, timed_out=false, 3 children, 0 cleaned/forced. Same nine failure names as previous baseline. stderr: inactive ENet multiplayer instance warnings, pre-existing ObjectDB warnings.
- Prewarm real H3 test: **6/17 PASS, 11 FAIL**, exit=1, 71.16s, timed_out=false, 3 children, 0 cleaned/forced. Owner and observer prewarm each executed in 4579.576ms and 4472.473ms, `freed=true`. Two extra failures include observer_initial and observer_gone.
- Cold client SimVisual ready durations (ms): observer [8926,1512,2536,5237], owner [8964,1490,2521,5185]. Prewarm: observer [5575,2841,5647], owner [5580,2812,5708]. Different puppet counts and trajectories make naive sum/percentage comparison invalid.
- Independent production `tests/test_character_edit_apply_enet.gd`: **97/97 PASS**, exit=0, wall-clock retry 5.002s; no timeout.
- Original H3 gate remains FAILED. These runs do NOT establish that prewarm caused the extra failures or that visual cost is unrelated to handshake; both hypotheses require better controlled tests.

## Skeptical Gemini audit
Three consultations (plan, code, final A/B). Confirmed throwaway object lifecycle executed, warned about asynchronous rendering/cache incompleteness, timing/CPU contention, and different network trajectories. Rejected its unsupported claim that identical failed gates would *definitively* exclude cold-start causes; also rejected suggested CLI parser rewrite that would lose worker token/port positional semantics. No private player data shared.

## Single next step
In the unchanged cold H3 fixture, capture server-side `peer_connected -> player record/ACL creation -> owner_read_ready -> server_read_gate` event ordering with monotonic per-process clocks and the existing 17 gates; determine why `server_can_edit_character` and canonical record are false at the initial read gate before considering any production optimization. Do not loosen timeouts or assertion thresholds.

Final remote backup and v3 release status are recorded in the corresponding run history, not claimed here before execution.
