# H2b ENet pending-puppet lifecycle regression — 2026-10-25

Run: `main-fallback-1792897984-140364`. **Test-only recovery of unfinished prior main-run source**; no production implementation changed in this fallback.

## Provenance and exact files
- Previous interrupted main run `main-1792893869-140005` had left `tests/test_character_edit_apply_enet.gd` modified at 2026-10-25 02:07 UTC but its history remained `running`, last heartbeat 02:06:13 UTC. No successful main implementation was recorded in the preceding ~75 minutes.
- Protocol-v3 acquire archived the expired previous lease under the coordinator, after 40-minute lease and 20-minute grace; no manual lock manipulation. Pre-documentation backup: 114866 KB.
- Recovered test code adds same-channel reliable RPC fence and a 64-message ordering check, a pre-spawn public look snapshot, stale/private packet rejection, manual production _on_spawned/_on_despawned callbacks, and clean new-lifetime revision acceptance.
- This run **did not write to the test file**; it completed actual execution, independent audit, and checkpointing of the abandoned test changes.
- Files written by this fallback: this review, CHECKPOINT.md, DEVLOG.md. Existing changed source from interrupted main: tests/test_character_edit_apply_enet.gd (SHA-256 4ed48f47444ae1d40ddc5b10e747284bd5fe001d8a5211fb43889d7ed99731a6).

## Actual verification
- `godot_run_script` extends the real test script, **60/60**, exit 0, timed_out false, ENet server plus two clients. Prior baseline was 40/40. 64-message reliable fence checks handler ordering, not a simulated network reorder or guarantee about production scheduling.
- Production `res://tests/test_character_net.tscn` **52/52**, exit 0, timed_out false, 18.2 s. Real hello/spawn/late join/public look/cleanup and privacy. Does not exercise actual MultiplayerSpawner *pre-spawn* delivery ordering.
- `godot_check` **60/60**, no parse errors.
- Known existing warning: 18 ObjectDB instances leaked on SceneTree test shutdown; not new evidence of clean shutdown. No new UI change; no render or screenshot claimed.

## Skeptical Gemini audit and independent disposition
Two actual Gemini responses. Initial audit called old-lifetime stale packet acceptance a high-severity bug and suggested no revision reset, but source lines 243–246 **do erase** both revision and pending entries. It correctly noted the missing actual engine-level pending-before-spawn callback coverage. After the contradiction and independent production 52/52 were presented, Gemini withdrew the confirmed-bug assertion and classified a reused-name stale-packet scenario as unproven.
**Open design risk:** if a `sim_node` name is reused after despawn and a valid server packet from its previous lifetime arrives after the cleanup, revision alone cannot distinguish generations. The tests do not establish whether production server reuses names or permits that packet ordering. This is not a demonstrated remote-forgery vulnerability: RPC is authority-only and explicitly checks sender ID 1. Treat as an unresolved lifecycle edge case, not a fixed bug.
No private data shared with Gemini.

## Single next step
Run a **real MultiplayerSpawner delayed-packet/despawn/rejoin** test using an actual recycled actor name, assert old-lifetime packets cannot affect the new actor (or implement a generation/identity fence if the test demonstrates a failure). Afterward perform real client render inspection before enabling network editor. Remote Apply remains OFF by default. GitHub read-only; city-owned paths untouched.
