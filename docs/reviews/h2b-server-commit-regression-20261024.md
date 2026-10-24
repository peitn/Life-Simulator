# H2b internal server Apply regression — 2026-10-24

Run: `main-fallback-1792865414-97937`. This fallback resumed after a main task stalled at 17:10 UTC. Its existing `main.gd` already contained `server_apply_character_edit` and `_commit_validated_character_edit`; this run did not claim authorship of those production functions. Changed code: only `tests/test_character_edit_ownership.gd`, 14 additional assertions.

## Test evidence
- `res://tests/test_character_edit_ownership.tscn`: **75 passed / 0 failed**, exit 0, no timeout.
- `res://tests/test_character_edit_read_enet.gd` executed as SceneTree script: **20/20**, two real ENet clients, exit 0.
- `res://tests/test_live_character_edit.tscn`: **38/38**; `test_character_edit_session.tscn`: **30/30**; `test_character_editor_ui.tscn`: **55/55**. Total **218/218**.
- `godot_check`: **60/60** syntax. Existing 18-ObjectDB shutdown warning in stderr; no new runtime errors in successful runs.
- An initial attempt to execute `test_character_edit_read_enet.tscn` failed (file does not exist); reran the existing .gd script successfully. Not counted as a passed attempt.

## Gemini skeptical audit and disposition
Gemini was asked to audit the concrete production commit functions and new tests, and returned substantive feedback. It classified two issues as P0: (a) hypothetical interleaving of prepare and commit, and (b) unvalidated sim_node path/key injection. Checked against code: current execution is synchronous with no await or callbacks between preparation, fresh authorization and revision recheck and commit; the authoritative store rechecks the revision immediately before mutation. The network predicate rejects non-String sim_node, empty values, unauthorized peer-to-sim mappings, missing/queued-for-deletion sims, mismatched UID and duplicate ownership. Thus neither P0 is demonstrated for the present server-internal code. Do not generalize to future async RPC work.
Gemini also raised partial live state side effects if an internal apply operation fails; this is a legitimate test/hardening gap before enabling RPC, not a demonstrated regression in passing tests. Its no-op CPU-flood claim omitted the existing 24KiB cap and per-peer 3-token burst/0.2-token-per-second limiter before JSON parsing; rate limiting still deserves ENet load tests. Generic unauthorized reasons are intentional privacy protection; server-only diagnostics can be improved separately.

## Limits / next step
No remote Apply RPC, owner-only Apply result, public appearance replication, full hello/spawn lifecycle or adversarial two-client Apply test exists yet. The test invokes server-internal Apply under controlled server fixtures; do not label multiplayer editor complete. Next: implement authenticated RPC and owner-private response/public-only replication, test stale revision, disconnect, ownership reassignment, payload limits and live-state rollback before enabling UI. No GitHub/city changes.
