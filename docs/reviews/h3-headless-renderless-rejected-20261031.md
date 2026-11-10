# H3 dedicated headless renderless prototype — REJECTED (2026-10-31)

Run: main-fallback-1793463279-41048. This is a negative experiment, not an accepted optimization or H3 completion.

## Hypothesis and bounded change
A dedicated headless authoritative SimAgent need not build visual geometry to replicate gameplay and public look. Temporarily added an explicit SimVisual.renderless flag, skipped _build in _ready and apply, and set the flag from SimAgent before add_child only when its own ../../Net mode was DEDICATED and DisplayServer was headless. The SimVisual node and public look metadata were retained. No RPC, CharacterData, city-owned paths, or multiplayer authority were intentionally changed.

## Real test evidence
- Godot static check: 60/60 PASS after prototype and after rollback.
- Existing production in-process ENet test_character_net: baseline 97/97 PASS; with prototype two independent runs each **6 PASS / 3 FAIL, exit 1, no timeout, 21.5s and 21.2s**. Failed unchanged checks: both clients welcomed within 6s, both peers see four characters within 4s, and owner puppet on both clients. Server spawned four characters and accepted owner data; this does not establish client completion.
- Existing unchanged separate-OS-process H3 acceptance: **8/17 PASS, 9 FAIL, exit 1, timed_out=false, ~50s**. Owner was welcomed quickly but observer visual spawn took many seconds; ownership/private read gates and observer forgery were still not accepted. H3 remains FAIL.
- Reverted BOTH production files. After rollback existing ENet **97/97 PASS, exit 0, no timeout**. Final SHA-256 matches exact pre-edit originals: scripts/sim/sim_visual.gd = 2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3; scripts/sim/sim_agent.gd = 8ad45c0abd6aa7425f6dea415dd16b1e7f1b1625ab933012917eea5986f61ec2. The intermediate SimAgent hash mismatch was caused solely by one missing final LF; verified SHA-256 of the text plus LF matched the original and restored it.

## Skeptical Gemini audit and independent review
Gemini correctly required renderless to be set before add_child, and warned about missing node lifecycle dependencies and headless/client test coverage. Its proposed lifecycle/RPC root cause is speculative; the observable alternative is that skipping server cold visual initialization shifts first-time geometry cost onto clients, causing strict timeout checks to fail. No root cause was proven. Gemini also incorrectly claimed only SimVisual was reverted and called SHA-256 values Git commit hashes; both claims were independently corrected. Never relax acceptance timeouts or count this prototype as success.

## Next SINGLE step
Build a **test-only, read-only** timeline of first client SimPuppet/SimVisual initialization and ENet welcome/spawn events under the unchanged baseline; distinguish cold client visual build from server-side blocking before proposing any new production optimization. Re-run unchanged 97/97 and 17-gate tests for any future candidate.
