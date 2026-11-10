# Isolated malformed Piper cache QA — 30 October 2026

Run: `main-fallback-1793351549-159471`. MAIN fallback, valid cooperative v3 lock; previous expired `main-fallback-1793344274-155938` was archived **automatically** by the v3 coordinator after lease + grace, with no competing Godot processes. No manual lock deletion. Pre-edit HF backup: project 405461 KB; library 123493 KB.

## Scope and exact files
- NEW `tests/test_neural_cache_formats.gd` (SHA256 `005c90a9b957d7796413c99b24060ac159d65cba1328bb087caa206f55a6b820`).
- NEW `tests/test_neural_cache_formats.tscn` (SHA256 `f1737b7f22f36cb54c3eab99995eb03fd52d7c9ff279bfdb295ae1dddf8ddcee`).
- This review, `CHECKPOINT.md`, `DEVLOG.md`. Production voice source, city files, Blender, GitHub and AI room untouched.

## Actual Godot evidence
Each malformed cache fixture uses its own deterministic Piper key including case/time/PID and is cleaned after the test. Real local Piper synthesis must replace the invalid cache with mono, 16-bit, >=16kHz, >=2000-byte WAV. Old size-only cache validation would have accepted each planted 8192-byte fixture.

- `--case=8bit`: mono 8-bit / 22050Hz fixture; **10/10**, exit 0, no timeout, 3.8s; independent repeat **10/10**, exit 0, no timeout, 4.5s.
- `--case=8khz`: mono 16-bit / 8000Hz fixture; **10/10**, exit 0, no timeout, 3.9s; independent repeat **10/10**, exit 0, no timeout, 4.4s.
- Prior stereo cache regression `test_neural_cache_integrity.tscn`: **9/9**, exit 0, no timeout, 3.3s.
- Real neural voice regression `test_neural_tts.tscn`: **18/18**, exit 0, no timeout, 0.4s.
- `godot_check`: **60/60** script checks.
- Stderr: pre-existing ObjectDB 20/22 leaked-instance warnings; no new parse/runtime errors reported. No UI changes, no render required.

## Skeptical Gemini audit and independent adjudication
Two actual Gemini audits were requested: before writing the test and after receiving the exact results. Accepted limitation: synchronous `OS.execute` of external Piper is not forcibly bounded by a GDScript watchdog; tests demonstrate these four runs completed, not a general no-hang guarantee. A crashed process can leave a cache fixture. A hypothetical concurrent identical-key race is not disproven by sequential tests, but test cases include PID/time/mode and did not share keys.

Rejected unsupported audit statements: the installed Godot binary **reports 4.7.2**, despite Gemini claiming the version did not exist; `invalid` intentionally means a **loadable malformed fixture**, not acceptance by the new validator; `check()` in `tests/test_base.gd` increments failure counts and does **not** throw or skip the cleanup line. GDScript has no `try/finally`. No concurrency, parser-fuzz, giant-WAV, real-time GPU, or general Piper timeout certification is claimed.

## Completion gate and next step
The previously unverified 8-bit and 8kHz corrupt-cache rejection cases are now independently reproduced and passing. H3/H6/H7 remain open. **NEXT SINGLE STEP:** resume H3 with a real creator-to-household spawn-parity integration test for independent identity, appearance, personality and psyche, including owner/privacy assertions. Final backup and release are recorded in v3 history separately.
