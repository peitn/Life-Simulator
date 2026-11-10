# Natural Czech voices – Piper CPU integration (30 October 2026)

The legacy `VoiceSynth` / `CzechTTS` formant voice sounds robotic to the project owner.
It remains accessible for backwards compatibility and headless/web fallbacks, but the
native game now offers a separate, **opt-in** character voice mode: `tts_neural`.
It is genuine neural speech synthesis, not a subtle filter applied to the old voice.

## Architecture
- Inference engine: Piper TTS 1.3.0 / ONNX Runtime on CPU (Python 3.11).
- Two Czech speaker models from `rhasspy/piper-voices`:
  - `cs_CZ-kasandra-medium.onnx`, 63,511,038 B, Czech Kasandra;
  - `cs_CZ-jirka-medium.onnx`, 63,201,294 B, Czech Jirka.
  - Configurations adjacent to models in `/app/library/lifesim/neural_models`.
- One-time setup: `python3 tools/audio/setup_neural_voices.py --install-deps`.
  If running elsewhere, set `LIFESIM_PIPER_MODEL_DIR` to another model directory
  and rerun the installer using `--models-dir`. Downloads total ~127 MB.
- Native inference CLI: `tools/audio/neural_tts.py`, only invoked by
  `scripts/audio/neural_voice.gd`. Text is passed as argv (not a shell command).
  Model selection is strictly whitelisted; no web API, speaker cloning, or microphone
  recording; synthesis is local. Output WAV is validated and atomically written.
- `AudioManager` handles `tts_neural` alongside legacy `tts`: jobs run in
  WorkerThreadPool with bounded concurrency and existing 3D sound positions,
  cooldowns, public-data-only restrictions and speed limits.
  On error/unavailable backend the neural mode emits no old robotic fallback.
- Individual NPC speaker default is a stable hash of character node name,
  **not** gender, sex, anatomy, sexual orientation, grammatical form or identity.
  True per-character persistent speaker selection is not yet implemented.
- Character VoiceEditor now has explicit `▶ Piper Kasandra` and
  `▶ Piper Jirka` preview buttons with background inference and playback.
  Existing pitch, timbre, resonance and roughness sliders are for **formant mode**.
  Currently only the tempo knob changes native Piper playback through its
  length_scale. Other slider effects are not misrepresented as neural control.
- GameSettings and settings menu expose the `tts_neural` option.
  It remains OFF by default (existing `wordless` mode is preserved).

## Limitations
- **Web export is not neural-enabled:** WebAssembly cannot spawn Python/ONNX.
  The corresponding item in web settings is disabled. To serve neural voices in
  browser will require a supported authenticated, rate-limited server endpoint,
  cache, consent and a Godot HTTPRequest client; none was built here.
- A server restart/redeploy can remove pip-installed packages; installer script
  is saved. Model data lives in the Hugging Face-connected library, separate
  from Godot PCK; backups should include this library.
- Piper synthesizes a plausible recorded voice timbre, but quality is subjective
  and model prosody may still sound artificial. No manual listening test on the
  user's phone has been performed.
- Dynamically launched CPU process per cache miss may introduce latency; local
  cached WAVs are reused in `user://piper_tts`. A persistent model runner can
  improve latency later.
- Neural speech mode is a **presentation** feature, with no simulation or
  multiplayer authority impact. It consumes only the already-visible speech line
  plus the character's public voice. G2P is internal to Piper / phonemizer.

## Verification
- `tests/test_neural_tts.tscn`: 18 passed, 0 failed (two ONNX voices,
  different PCM, same-speaker cache, tempo difference, threaded AudioManager,
  asynchronous UI preview, opt-in settings).
- `tests/test_tts.tscn`: 82 passed, 0 failed (legacy).
- `tests/test_voice.tscn`: 110 passed, 0 failed (legacy).
- Godot syntax check: 60 scripts checked, all passed.
- Setup script idempotence: detected both models with correct sizes.
- Real outputs:
  - Kasandra WAV: https://peiti-godot-mcp.hf.space/play/lifesim_voice_lab/neural_kasandra.wav
  - Jirka WAV: https://peiti-godot-mcp.hf.space/play/lifesim_voice_lab/neural_jirka.wav
  - Separate Audio Engine OGG samples:
    https://peiti-audio-mcp.hf.space/files/neural_piper_kasandra-025b34.ogg
    https://peiti-audio-mcp.hf.space/files/neural_piper_jirka-85e482.ogg
  The latter OGG resources were HTTP-checked (200 and 'OggS' signature).
- Audio Engine library project `lifesim` contains
  `sounds/neural_piper_kasandra.ogg` and `sounds/neural_piper_jirka.ogg`.

## Future refinement
Allow explicitly choosing speaker per character with a new validated
schema field and migration, not a gender mapping. Add more licensed Czech
speaker models; tune Piper style/phrasing; add secure remote TTS for browser
and persist generated audio by dialogue key. Consider audio A/B user feedback
before changing default away from wordless.
