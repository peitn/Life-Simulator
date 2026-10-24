# H2b staged Apply RPC — independent skeptical review (2026-10-24)
Run: main-fallback-1792868917-99778.

## Change surface
- scripts/net/net_session.gd: appended feature-gated Apply request, server RPC deriving sender via multiplayer.get_remote_sender_id(), synchronous delegation to world.server_apply_character_edit(), bounded/sanitized private acknowledgement, client reply origin and type checks.
- tests/test_character_edit_apply_enet.gd: isolated real ENet server and two client fixture with authenticated peer IDs; canonical fixture validation, revision, replay, forged selection, private delivery, forged local reply and feature-off tests.
- Production feature flag character_edit_apply_rpc_enabled is FALSE; no public appearance replication, remote HUD wiring, or full hello/spawn lifecycle claim.

## Evidence
Initial ENet test: exit1, 13 passed/10 failed because fixture used empty personality.traits (strict validator requires at least one trait). Corrected fixture to include optimista; final 23 passed/0 failed, exit0, no timeout. Read ENet20, ownership/commit75, live38, edit session30, editor UI55 all pass (241 assertions total). Syntax checker60/60. Only pre-existing Godot ObjectDB shutdown warnings; no new UI/visual asset.

## Gemini independent audit
Gemini reviewed the appended transport code and test plus the existing synchronous production commit contract. It found no confirmed P0/P1 in the staged code, considered owner-only categorical error acknowledgement appropriately scoped, and recommended keeping the flag disabled until public appearance replication and UI lifecycle integration. It highlighted high-concurrency and future async-commit gaps.

## Independent disposition and limitations
Confirmed from source: server reads remote sender ID, server_can_edit_character checks server authority/assignment/UID/duplicate ownership, world.server_apply_character_edit rechecks before commit with no await, and server uses rpc_id(sender) for private ack. Client accepts only sender ID 1 and matching my_sim. Production flag defaults false. Test fixture commits validated CharacterData but is not the production world; ownership suite separately tests production server commit. **Gemini's phrase 'cryptographically bound networking layer' is not substantiated:** ENet peer IDs and transport authentication are not equivalent to an end-to-end cryptographic identity guarantee; actual security depends on server-side assignment and trusted connection/hello policy. Feature remains OFF.
Open: full production hello/spawn/disconnect/reassignment two-client integration, public-only appearance replication, partial-state rollback on exceptions, rate/DoS stress and UI reconciliation. Do not enable until tested.
