# H2b — Real MultiplayerSpawner recycled-name stale-look diagnostic (2026-10-25)

Run: `main-fallback-1792905114-145927`. Test-only change: `tests/test_character_net.gd`. No production code, feature flag, scene, Blender, city, GitHub or AI-room changes.

## Setup and observed result
The production `test_character_net.tscn` ENet fixture first applied three legitimate owner edits (old character height 182 cm), disconnected the owner, and waited for the **actual** server/observer MultiplayerSpawner despawn. It confirmed observer `_public_look_revisions` and `_pending_public_looks` were cleared. The server then spawned a new canonical character at **160 cm** with the same freed node name; the observer's real new puppet initially had height 160 cm. With staged public-look RPC enabled only inside the fixture, the trusted server deliberately sent an old public-only snapshot for the former incarnation with revision `old_revision+3`. The observer accepted it and the new puppet's height became **182 cm**.

Reproduced in three successful production fixture runs: **66/66** functional assertions each, exit=0, no timeout (one run 15.9s). Diagnostic `H2B_RECYCLED_NAME_STALE_PACKET_ACCEPTED=true old_height=182.0 new_height=160.0 observer_height_after_old_packet=182.0`. **Packet rejection is not an assertion and is NOT counted as passed.** The 4 new assertions only prove real despawn state cleanup, recycled-name server spawn, observer spawn and correct initial new look. This run confirms a cross-incarnation validation defect, **not a security pass**.

Staged ENet regression `tests/test_character_edit_apply_enet.gd`: **60/60**, exit=0, no timeout when invoked directly as SceneTree script. One earlier incorrect wrapper invocation timed out after three initial PASS lines; it was not counted as a successful test and did not change project source. Godot syntax check: **60/60**. Existing stderr warning: 18 leaked ObjectDB instances at shutdown. No new production UI changes; no render claimed.

## Mechanism and limits
`NetSession._on_despawned` clears revision/pending maps by node name. `_s2c_character_public_look` verifies sender=server, strict public-only payload, name and monotonically increasing revision **within the currently tracked name**, but does not verify an entity-incarnation identifier. After the same name is reused, an old snapshot with a higher revision can be applied to the new puppet.

The test deliberately caused the trusted server to send the old packet *after* respawn. It does **not** demonstrate that normal ENet reliably ordered packets spontaneously reorder across the real production spawn lifecycle, nor that an ordinary malicious client can invoke an authority-only server RPC. Actual spontaneous occurrence and exploitability remain unproven. Staged remote editor remains **OFF** by default; do not enable it while this defect remains.

## Independent skeptical Gemini audit
Two actual Gemini responses reviewed the concrete handler/callback and observed test result. First confirmed missing incarnation binding but overclaimed that ordinary attackers can force replay and network jitter defeats ENet reliable ordering. Second response explicitly **retracted** those unsupported claims. Independently verified: current RPC signature has only `sim_node, revision, wire`; real new puppet accepted old look. Gemini's remediation suggestion (spawn incarnation token in replicated spawn data, same token in RPC, strict client matching and safe pending-packet binding) is a design proposal, not an implemented fix.

## Single next step
Implement a server-generated **per-spawn incarnation token** in public spawn data and appearance RPC, enforce it for live and pending puppets, then assert in the same real ENet recycled-name fixture that old-lifetime packets are rejected while valid new-lifetime packets apply. Test both early/late packet ordering before enabling any network editor.
