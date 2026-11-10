# H3: skutečný cold-process autosave test (29. 10. 2026 UTC)

Run: `main-fallback-1793236448-36878`. Scope: **test only**, no production/UI/Blender/city/GitHub/room edits.

## Evidence
- New `tests/test_h3_cold_process_reload.gd` SHA256 `639497219faa8c53927baf4e09d7545fc89da24ca041da7f130fbc21d97a8e39`; new scene `tests/test_h3_cold_process_reload.tscn` SHA256 `d79adb2098c0cb85ab19da60c143fc9d7fa7474870324d455fb5eb6161c74725`.
- Two **separate** `godot_run` invocations/OS processes, same unique isolated `user://test-h3-cold-main-fallback-1793236448-36878/`. Producer (HUD creators) made Nora Cold and Mira Cold, hand_size -0.6/+0.8, authored hand_l/hand_r bone pose scales 0.88/1.16, real hand-detail mesh nodes; wrote real binary autosave and independent PID+SHA256 marker. Consumer checked different OS PID, same binary SHA256, explicit save directory, **entire loaded world snapshot exactly equals saved snapshot**, two actual spawned Skeleton3D rigs, public mind/UID absence and distinct private anxiety values.
- Initial phase tests before audit: producer 17/17 exit0 10.8s, consumer 17/17 exit0 9.2s. After stronger full-world snapshot checks: producer **17/17 exit0 9.7s**, consumer **19/19 exit0 9.3s**. All no timeout. Regression full playable slice **81/81 exit0**, authored preview **13/13 exit0**, syntax **60/60**. Existing 20 ObjectDB shutdown warnings; no new error.
- No new UI/render code. This verifies **CPU authored rig transforms** and process-isolated persisted state, NOT GPU pixels, normal/narrow screenshots, network observer parity, cross-OS portability or full H3 completion.

## Skeptical Gemini audit (two actual responses)
First review proposed directory race after successful synchronous save, deferred `pressed.emit()` despite guard, and possible false pass on missing resident. Verified these against `Main.save_game`, synchronous Godot signal behavior and `tests/test_base.gd` (failed `check` makes exit1). Follow-up **retracted all three**. One legitimate audit improvement: stronger proof that autoload actually consumed the producer save; added explicit directory equality and full on-disk vs live world equality, reran green. Second audit speculated about asynchronous save-manager initialization; source `main.gd` initializes `_save_manager` and synchronously performs `load_slot/apply` inside `_ready()` **before** the test's process-frame await, so no concrete defect demonstrated. Marker handle is explicitly closed. A run-specific test directory remains to permit reproducibility; do not treat it as user save data.

## Next single step
H3 rendered QA: capture and inspect actual **normal and narrow viewport** 3D preview versus spawned/restored characters, including hands; distinguish GPU pixel appearance from already tested CPU bone transforms. Do not claim full H3 or publish GitHub without fresh approval.
