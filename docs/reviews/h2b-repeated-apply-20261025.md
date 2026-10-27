# H2b — repeated Apply, three-client production ENet regression (25 October 2026)

Run: `main-fallback-1792901722-143849` (fallback). The previous successful main *task* implementation was older than the 75-minute check; last completed fallback at 04:16 CET is not evidence of main-task work. Before editing, acquired v3 main lock (atomic coordinator, history exists, no recovered lock) and uploaded backup **114888 KB**.

## Exact source change
- `tests/test_character_net.gd` only: ten new checks in existing production World/MultiplayerSpawner real ENet fixture, after late join and before late disconnect. Two additional sequential authorized owner Apply requests, height 179 → 180 → 182, private ACK revisions +2/+3, canonical state, public appearance/revision convergence for owner/observer/late-joiner, visual `look_params` equality, no observer private ACK or `mind`/`story`/`trait_levels` exposure.
- No production runtime code, feature flag, UI or asset changes. Remote Apply defaults OFF; test explicitly enables it only in the fixture. No screenshots or actual GPU pixel render.

## Actual execution and failure history
- First two `godot_run` attempts of `res://tests/test_character_net.tscn`: **timed out** at 85s and 110s with only engine banner; these are failures, NOT passes. A separate SceneTree load diagnostic exposed the underlying parse error `Expected expression after "and" operator` at new test line 237 (multiline lambda); fixed to single-line lambda. The diagnostic exited 2 and is not a passing test.
- Corrected `godot_run` production fixture **62/62**, exit 0, no timeout, **17.1s**, repeated **62/62**, exit 0, no timeout, **16.1s**. Ten new assertions beyond prior 52/52.
- Existing staged real ENet `tests/test_character_edit_apply_enet.gd` via `godot_run_script` **60/60**, exit 0, no timeout. Character edit session scene **30/30**, exit 0, no timeout. `godot_check` **60/60**; this checker did **not** catch the added scene test parse error, so actual scene loading is mandatory.
- Successful test stderr: pre-existing `WARNING: 18 ObjectDB instances were leaked at exit`; no new reported script errors. No claim of a clean leak-free runtime.

## Skeptical Gemini review (two calls)
- First review of the proposed concrete snippet correctly confirmed ACK indices/revision expectations and warned about rate limiter and string-based privacy checks. Independently checked production preflight: token bucket capacity 3, reset before one invalid request, then two valid requests; the observed successful ENet test supports this exact sequence, **not** rate-limit stress safety. Final privacy assertion checks structured fields, not just string search.
- Second review received actual final diff description, observed 62/62 twice, 60/60 and failure/fix history. It recognized missing real packet reorder, actual GPU rendering and recycled-name MultiplayerSpawner lifecycle. Its assertion that historical ObjectDB warning proves a new severe memory leak is **not established**; warning predates this patch. No independent P0/P1 demonstrated.
- This is a focused repeated-Apply regression, not full H2b completion or a production-security proof.

## Next single step
Create a **real MultiplayerSpawner despawn/rejoin with reused actor name and deliberately delayed old-lifetime look packet** regression; demonstrate/resolve generation confusion before enabling network editor. Follow with rendered client inspection in a separate step. No GitHub writes, no city-owned files, no Blender or AI-room messages.
