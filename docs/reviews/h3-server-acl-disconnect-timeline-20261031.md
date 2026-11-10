# H3 server owner ACL lifecycle — 2026-10-31

Run: main-fallback-1793474178-50699. **H3 remains FAILED/PARTIAL**.

## Scope
Read fresh main CHECKPOINT, implementation sequence, v3 lock documentation and automation history. No primary successful productive completion in preceding 75 minutes. MAIN v3 acquired; running history confirmed; initial remote backup succeeded (project 405771 KB, library 123493 KB). No city-owned, Blender, GitHub or AI Room changes.

Test-only modification: tests/diagnostics/h3_three_process.FAILING.gd, SHA256 316f7a4182853ae0048313756e8e69216db3d8b2bbcb9ceb0f00cc87eab690be -> 2a4809839c28ceba254fe20ed0109cfe1b626974f82274e8f6942ffe7c8dd94c. Added _server_acl_snapshot boolean-only predicate decomposition, roster_changed and private-read-gate snapshots, targeted trace printing. No UID, private record payload or identity values in added trace; original 17 acceptance assertions unchanged. No production code edits.

## Real test evidence
Bounded runner with three separate Godot child OS processes: cold mode, elapsed 63.24s, parent exit=1, 8/17 PASS and 9 FAIL, timed_out=false, three children observed, no remaining children. stderr: three ENet 'multiplayer instance isn't currently active' get_unique_id errors. First runner attempt used nonexistent /usr/bin/python3 and exited 127 without a test; corrected to python3, then the real test ran. Explicit fixture script load PASS. Independent production ENet test_character_net 97/97 PASS, exit0, 22.6s, no timeout; Godot syntax 60/60 PASS. Known ObjectDB20 warning from script-run wrapper; no new production errors established.

## Timeline (UTC millisecond timestamps, fixture peers only)
At 1793474384196 server roster ACL snapshot for owner: registered=true, own=true, assigned_match=true, sim_exists=true, sim_player_meta=true, uid_present=true, record_exists=true, record_uid_match=true, duplicate_owner=false, acl=true. Therefore the server DID create a valid canonical owner record and authorize it at that instant.

At 1793474389256 the roster contains only observer, not original owner. At 1793474404883, owner_read_ready marker appears but contains ok=false; server gate for original owner reports registered=false, sim_exists=false, record_exists=false, acl=false, while server remains connected. owner_initial connected=false, read_sent=false. Thus the false ACL at the later gate is consistent with owner disappearance before the marker was processed, not proof of a missing record during initial spawn. The reason the owner did not reach its 12-second local puppet-ready gate and disappeared is NOT established; potential client SimVisual cold-start blocking and fixture timeout remain hypotheses.

Gemini skeptical plan/results audit: accepted lifecycle evidence, cautioned about signal ordering, OS scheduling, timing and causality; some preflight sample code used nonexistent project APIs and was not adopted. No proof of a production ACL defect or successful H3 acceptance.

## Exact next single step
Instrument owner-side _probe_owner_ready timeout, client visual initialization, and server peer_disconnected in one bounded cold three-process run to establish whether the owner leaves due to fixture readiness deadline or a production disconnect; preserve all 17 gates and existing timeouts. Do not weaken tests or change production ACL on the current evidence.
