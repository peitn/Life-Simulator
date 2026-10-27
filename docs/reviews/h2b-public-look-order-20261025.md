# H2b ENet public-appearance packet ordering regression — 25 October 2026

Run: `main-fallback-1792886972-138142`. This is a **test-only** change; no production network/UI code changed and the remote character editor flag remains OFF.

## Changed source
- `tests/test_character_edit_apply_enet.gd` (SHA-256 0235d027557c4f1c3664901dc45db51533dd6e3e19ddfac9de43018ee73e8ebf → 4c1802f4fa4d0c9ba04ac1f113f6825c2f98e602be0ce2f5806d18726cdef9b2).
- Five new assertions using a **real ENet server and two clients**: stale/duplicate authenticated public-look packets ignored; malformed JSON cannot advance revision; a newer valid full public snapshot advances look and revision; delayed older valid packet cannot roll back; no mind/story fields disclosed.
- These are **test-only simulated server RPCs**. Revision 4 is injected as a full snapshot without a corresponding canonical server edit. That tests client monotonicity, **not** production server revision issuance or real network packet reordering (the channel is reliable). No new UI render was needed or claimed.

## Verification
- `godot_run_script` on `tests/test_character_edit_apply_enet.gd` **40/40**, exit=0, timed_out=False, run **twice**. Previously 35/35; five new checks.
- Actual production lifecycle `res://tests/test_character_net.tscn` **52/52**, exit=0, timed_out=False (16.1s); includes actual late join and public look/SimVisual parameter comparisons.
- Godot syntax `godot_check` **60/60**.
- stderr: pre-existing **18 ObjectDB shutdown warnings**. No new parse/runtime failures in completed tests. No screenshots captured; no visual production change.

## Independent skeptical Gemini review and disposition
- Gemini reviewed the concrete inserted test excerpts, result counts and described receiver contract. It found the tests useful but flagged arbitrary `await wait_frames(.12)` as a possible CI timing/flakiness source (**valid limitation**; repeat run passed but does not eliminate the risk). Follow-up should use event-driven bounded waits.
- Gemini labelled skipping revision 3 to 4 a **P0** security flaw. **Rejected as unsupported**: receiver deliberately applies *full server-authoritative snapshots* with monotonic `revision > highest`; it does not require every intermediate version. A gap alone is neither an authentication bypass nor a proof of corruption. The test simulates a server-authorized packet, so it does not test malicious server compromise.
- Gemini speculated about ENet channels, heap growth and spoofing without a reproducer; none is a proven new P0/P1. Existing suite checks forged local look RPC rejection. Full congestion, pending-puppet reorder, rapid Apply and reused IDs remain untested here.
- Production remote Apply **must stay disabled**. This does not complete H2b.

## Next single step
Create a bounded event-driven real-ENet regression for **pending-puppet delivery plus stale packets during despawn/rejoin**, then capture actual rendered client appearance before wiring the network editor. Do not publish to GitHub or touch city-owned files.
