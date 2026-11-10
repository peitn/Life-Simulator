# Neural Piper cache integrity — 30 October 2026

Run: `main-fallback-1793344274-155938` (MAIN fallback, cooperative v3 lock). Scope: narrow native speech cache validation; not H3/H6/H7 completion.

## Why
`NeuralVoice.render` previously accepted a cached WAV whenever `AudioStreamWAV.load_from_file` returned a stream with at least 2,000 data bytes, without checking stereo, PCM format or sample rate. A stereo cache entry could therefore bypass the stricter fresh-inference checks and be played as an NPC voice.

## Changed project files
- `scripts/audio/neural_voice.gd`: validate cached AND fresh streams for mono, 16-bit PCM, >=16 kHz and >=2,000 bytes. Existing Piper helper still atomically replaces invalid cached files; no new network, privacy or character-schema changes.
- NEW `tests/test_neural_cache_integrity.gd` and `.tscn`: inject loadable 22,050 Hz stereo 16-bit WAV of 8,192 data bytes into a unique deterministic `user://piper_tts` cache key; verify the invalid entry is not returned, real Piper regenerates mono 16-bit speech, disk cache is replaced, and test key removed.
- `CHECKPOINT.md`, `DEVLOG.md`, this review. No city, Blender, GitHub or AI-room edits.

## Actual evidence
- **RED** (before production fix): new test 6 passed / 3 failed, exit=1, timed_out=False, explicitly returned invalid stereo cache.
- **GREEN** (after production fix): new test **9/9**, exit=0, timed_out=False (5.0 s), real Piper inference and on-disk replacement.
- Existing suites after final production fix: neural TTS **18/18** exit0/no timeout; legacy TTS **82/82** exit0/no timeout; Voice **110/110** exit0/no timeout. `godot_check` **60/60** scripts (not a substitute for running the new test).
- Known preexisting Godot ObjectDB leak warnings: 20/22 objects. No UI modification or render requested.
- A later experimental expansion of the test to 8-bit/8 kHz fixtures hung under the connector and yielded tool errors/timeouts, **NOT a pass**. That expansion was **reverted byte-for-byte** to the previously green 9/9 test (SHA256 `7d426c02ee1f36dfa7e840ecfcc21be9513d5efacc196f6f3c65a82af3d36a52`). Two exact-match orphan Godot child test processes were identified and terminated; no other worker touched. Do not claim those unverified scenarios pass.

## Independent Gemini audit
One skeptical Gemini audit of actual before/after conditions, fixture and RED/GREEN results completed. It raised potential unbounded WAV sizes, concurrent cache writes and parser exposure. No demonstrated P0/P1 exploit in this local, hashed-cache setup: key is SHA-256 of bounded text/style/speaker/tempo, Python writes to a temporary file in the same directory and atomically replaces, and current test confirms replacement. A claimed test of 8-bit/low-rate files was factually incorrect at the time of audit. Parser hardening/upper size limits and concurrent cache-stress remain unverified, not silently dismissed.

## Backup and state
Pre-edit HF backup succeeded: project 405455 KB and library 123493 KB. Final backup/release must be verified separately in history. H3/H6/H7 remain open.

**NEXT SINGLE STEP:** independently isolate and test 8-bit and 8 kHz invalid cache entries in bounded separate Godot runs (without leaving orphan children), before expanding the neural voice feature.
