# H2b read-only RPC audit — 24 October 2026
Run main-1792857742-97115.
## Actual implementation
NetSession request_character_edit_snapshot sends only selected sim ID. Server RPC derives authenticated ENet sender, runs existing server_can_edit_character and bounded server_read_character_edit, then unicasts private JSON bytes and revision. No await between gate and response. Client requires authority sender1, CLIENT mode/connected, exact my_sim, integer nonnegative revision, PackedByteArray1..24576 and JSON dictionary. Signal data remains private; never feed this to public replication.
No Apply endpoint or UI network activation in this unit. Main offline read/apply methods still deny network modes.
## Evidence
Real ENet sockets on loopback; dedicated server and two client SceneMultiplayer roots in one process, server registration/character records created by fixture. Initial17/17, expanded20/20 after review. Requests for another actor, revoked/removed owner, bursts and locally forged server reply rejected. Actual ENet disconnect runs production cleanup after unassignment and removes limiter.
This is not end-to-end hello/spawn/despawn/reconnect coverage or a separate-process deployment test. Private fixture markers were synthetic, not user data.
Regression ownership62, live38, UI55;175 total checks including final network20. All exit0/no timeout. Only historical18ObjectDB warning. No visual changes/render claim.
## Gemini
One real response reviewed exact new transport, ownership/preflight and initial17-test harness. Claim limiter leaks on disconnect is false: _on_peer_disconnected already erases _edit_limiters; added executable disconnect regression demonstrates this. Future Apply must recheck synchronously at commit; accepted requirement. Current receiver only validates envelope/JSON dictionary, so UI consumer must strictly validate schema before constructing its draft; no UI consumer is attached yet. Do not present Gemini's broad PASS as proof of all multiplayer paths.
Rate limiter is shared with candidate preflight intentionally. Size check happens after serializing trusted canonical server data. Denied requests silently return, avoiding private error reflection, but transport-level spam/packet budgets remain a broader network concern.
## Next
Apply RPC/current revision commit/public-only appearance replication and real application lifecycle integration before enabling network editor.
