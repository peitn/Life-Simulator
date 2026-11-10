# H3 guarded asynchronous SimVisual lifecycle — isolated test (2026-10-31 23:13 UTC)

Run: `main-fallback-1793488398-60765`. v3 MAIN acquired; no productive primary MAIN completion in previous ~75 minutes; history running verified. Initial remote backup SUCCESS project 406079 KB/library 123493 KB. Only test-only files and documentation were changed, no production/authority/ACL/network/city/Blender/GitHub/AI-room writes.

## Exact test-only files
- NEW `tests/diagnostics/h3_visual_lifecycle_probe.gd` (final SHA256 6baba2625efb7b65f5a61c62f047b71ac77643a8c2c1be874b1f29efd11eb3ac)
- NEW `tests/diagnostics/h3_visual_lifecycle_probe.tscn` (SHA256 c390127f5fdc9a829e1feb99055e4aaff1a806288b7b8e359b700bb0c826a594)
- NEW this report; APPENDED CHECKPOINT.md and DEVLOG.md.
- Own pre-fix/pre-mid test backups in `previews/automation-backups/main-fallback-1793488398-60765-lifecycle-pre-fix.gd.txt` and `...-lifecycle-pre-mid.txt` (not loaded by Godot syntax scanner).

## Actual evidence
In-memory SHA-pinned copy of original `scripts/sim/sim_visual.gd` (production SHA 2883e642...) adds `new/building/ready/cancelled`, completion signal, generation guard, pending latest-only `apply_look`, and frame yields after hair/feet/before wardrobe. Production remains unchanged. Real headless Godot test ran twice independently, **19/19 PASS each, exit=0, timed_out=false, 4.5 and 4.8 seconds**. Verified early building, delayed mid-stage look, coalesced last hair color, no partial look, explicit ready, 35 meshes/1 skeleton/1 label, immediate post-ready look, immediate and mid-stage cancellation (weakref freed, no completion signal). Source-hash and exact anchor checks fail closed. Test itself does not change canonical data, multiplayer ACL, or snapshots.

Initial test invocation **timed out after 65 seconds** because test script had a GDScript parse error (Variant inference of weakref at line 83), discovered by explicit script-load check; not counted as success. Corrected to typed `WeakRef`. The first post-fix syntax scan failed because a backup was accidentally stored as `.gd`; own backup renamed to `.gd.txt` under lock. Final syntax scan **60/60 PASS**. Independent production ENet `test_character_net` **97/97 PASS, exit0, no timeout** (twice). Existing shutdown warning: **20 ObjectDB instances leaked**, also present in unchanged ENet and standalone snippets; not clean stderr and not attributed to this change. No graphical render or 17-gate H3 three-process acceptance in this run; last known H3 baseline 8/17 FAIL, extended timeout 12/17 FAIL.

## Skeptical Gemini audits and independent verification
Gemini reviewed the proposed guard and actual test code, then audited the 19/19 follow-up. Valid concerns: external setters still see `_built=true` early, only `apply_look` is guarded; late/multiple updates, node removal, C++ resources, visual parity and real ENet interaction are not proven. Mid-stage cancellation and interleaved look were added and rerun in response. Rejected Gemini's claim that `_built` becomes true only after `await _build`: source sets it at the beginning. Also rejected its alleged ready-before-build hole: patched `ready` is assigned only after awaiting `_build`. Epoch overflow and attributing pre-existing ObjectDB warning to this probe are unsupported. This is a bounded proof of an isolated guard, **not a production fix**.

## Gate and next single step
H3 remains FAILED/PARTIAL. **NEXT SINGLE STEP:** build a test-only `SimPuppet` integration of the guarded staged `SimVisual`, verifying actual network-spawn/apply/cancel ordering and unchanged 17 H3 gates; only consider a production change if real three-process acceptance and 97/97 ENet both pass with stable render/ACL. Do not relax deadlines or security checks.
