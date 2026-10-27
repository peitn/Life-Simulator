# H2b — Graphical client public-look resync audit (2026-10-25)

Run: `main-fallback-1792927037-162761`. Scope: a new standalone graphical ENet integration test; **no production code modified**.

## Changed files and evidence
- NEW `tests/test_character_resync_render.gd` (SHA-256 bb093e606f3d859880a6b8130721ea26b5b7799c36a9a752a1ff1b876e7a406f).
- NEW `previews/h2b-resync-client-1280x900.png` and `previews/h2b-resync-client-360x800.png` (actual Xvfb Mesa OpenGL Compatibility captures, inspected visually; character visible in both).
- APPENDED `CHECKPOINT.md`, `DEVLOG.md`, and this review.

## Execution
- Graphical Godot via `xvfb-run -a /opt/godot/godot --path <project> --rendering-method gl_compatibility --script res://tests/test_character_resync_render.gd -- --lease <run_id>`: exit 0, no timeout, 12/12 assertions, both PNG saves OK, image sizes exactly 1280x900 and 360x800.
- Production `res://tests/test_character_net.tscn`: 70/70, exit 0, 16.8 s, no timeout.
- Staged `tests/test_character_edit_apply_enet.gd` via GDScript SceneTree: 94/94, exit 0, no timeout.
- Godot syntax checker: 60/60 OK. Existing 18 ObjectDB shutdown warning; missing optional audio libs / dummy audio fallback; Compatibility SSS/AA warnings. No new fatal errors.

## Test semantics
An actual client joins the production MultiplayerSpawner over local ENet, obtains the current spawned SimPuppet, and the test modifies canonical server CharacterData height and increments its revision **without invoking UI Apply**. The client requests public-look resync over the authenticated RPC and verifies the new revision, the canonical height, incarnation token, visual resolver equality, and absence of private fields. The live client branch is rendered in a SubViewport at both sizes; screenshots were visually inspected. This is real RPC/render integration but not proof of packet loss handling under adverse networks, UI workflow, server Apply authorization, Forward+ rendering, or automated pixel correctness.

## Gemini skeptical audit
Actual Gemini response reviewed the complete new test and production resync excerpt. It correctly flagged direct internal server mutation (bypasses UI Apply), localhost-only ENet, lack of programmatic screenshot-content assertions, and coupling to internal Main fields. The alleged **high-severity test pollution** is not supported for this isolated subprocess: GameSettings.persist is disabled, and the executable terminates after the test. The audit's claim that a public incarnation token prevents spoofing by itself is too broad: security depends on server-side authenticated peer and RPC authority checks, not token secrecy. No confirmed new production P0/P1 defect was found. Audit limitations remain open.

## Next exact step
Guarded visible UI Apply -> server commit -> observer public replication and rendered appearance, including denied non-owner and Cancel/Undo; leave remote editor feature OFF until complete.
