# H2b — correlated private read timeout (25 October 2026)

Run: `main-fallback-1792941381-168335`. Scope: bounded client-side timeout and lifecycle cancellation for already authenticated, correlated owner-only snapshot reads. **Not** visible network UI integration, Apply enablement, or completion of H2b.

## Verified change

- `scripts/net/net_session.gd`: tagged 32-lowerhex private reads now have a 6000 ms monotonic deadline; client process expires a pending read once and emits `character_edit_snapshot_timed_out(request_id)` after clearing state. A valid correlated reply checks expiry and clears both token and deadline. Cancel, shutdown, connection failure and server disconnect clear both fields. Untagged legacy responses are ignored while a tagged request is pending, so they cannot feed an unrelated legacy consumer. Server-derived peer ownership, private unicast, 24 KiB cap and feature-off remote Apply are unchanged.
- `tests/test_character_edit_read_enet.gd`: real ENet two-client tests for deadline cleanup on success/Cancel, denied-owner timeout after >6 real seconds, exactly one timeout event, rejection of an authenticated late tagged reply, and legacy reply suppression during a tagged read.

## Test evidence

- Targeted real ENet private read: **35/35**, exit 0, timed_out=False; elapsed >=6000 ms tested against real monotonic clock (not a synthetic timestamp).
- Production MultiplayerSpawner/ENet: **70/70**, exit 0, timed_out=False, after final production change.
- Staged ENet Apply/resync: **97/97**, exit 0, timed_out=False, after final production change.
- Godot syntax: **60/60** OK. No UI files or rendered pixels changed in this unit, so no screenshot claimed.
- Known pre-existing **18 ObjectDB instances leaked** warning on test shutdown; no new runtime/parse errors in final suites. One diagnostic hash-check snippet had a mixed-indentation parse error and was corrected; it did not modify the project.

## Skeptical Gemini audit — two actual responses

First response correctly identified the need to keep legacy responses from reaching legacy listeners during a pending tagged read; this was fixed and tested over ENet. It incorrectly labeled expiry on receipt of an already-expired request as a P1, claimed the legacy branch called expiry, and claimed Godot 4 Time.get_ticks_msec() wraps at 32 bits. Source inspection and second review rejected these assertions. The second response found no concrete remaining blocker in the shown implementation, but incorrectly stated that a legacy response after the tagged timeout is always dropped; in fact it is allowed once no tagged request is pending, for backward compatibility. That behavior is not a security claim or a tested UI integration.

## Remaining limitations and next single step

No visible network editor opens yet; the HUD still permits only offline editing, the panel calls offline Main methods, and `character_edit_apply_rpc_enabled` defaults to false. Owner reassignment without disconnect is protected by server authorization for new reads, but already-received drafts will need explicit UI invalidation on owner change. No adverse-WAN tests. **Next:** behind a default-OFF staging flag, wire HUD/panel to unique correlated owner read with timeout/Cancel and no unauthorized Apply; add actual UI tests and normal/narrow render before proceeding to asynchronous server Apply acknowledgment and fresh canonical read. Do not modify city-owned paths or publish to GitHub.
