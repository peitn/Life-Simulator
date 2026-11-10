# Voice resonance: independent formant bandwidth (30 Oct 2026)

Run: main-voice-resonance-1793330949-138588. Scope: Godot project lifesim only; no Blender/city paths, no GitHub push and no Audio Engine connector modification.

Implemented a fifth slider (VoiceEditor: `resonance`, -1..+1 step 0.01) independent of pitch, timbre/tract length, tempo and roughness. Positive values narrow the formant bandwidths and make resonances more focused; negative values widen them for a softer, less focused timbre. Acoustic multiplier: `bandwidth_scale = 2^(-0.6 * resonance)` (~0.66..1.52). The default 0 keeps the previous signal path unchanged. The same parameter controls four wordless VoiceSynth formants and CzechTTS formants F1..F6; it is saved in public CharacterData.voice and used consistently by all peers and in local audition, without reference to gender/body/identity.

CharacterSchema was advanced from v19 to v20 with default 0.0; CharacterCodec migrates v19 voices to v20 without modifying any other fields. VoiceSynth.normalized, params, quantized cache keys (both wordless and TTS), editor labels/summary and the reversible Apply/Cancel/Undo flow are integrated. Server validation rejects bad resonance input; old profiles have neutral default.

Verified on canonical Godot 4.7.2 project:
- syntax: 60/60 pass;
- tests/test_voice.tscn: 110/110 pass, including distinct waveforms for extremes, constant pitch, TTS+wordless, cache, UI Apply/Undo/Redo, v19 migration and privacy;
- tests/test_tts.tscn: 82/82 pass;
- tests/test_character.tscn: 157/157 pass (deliberate bad compressed input creates expected stderr warnings);
- tests/test_character_v2.tscn: 43/43 pass;
- tests/test_save_game.tscn: 46/46 pass;
- tests/test_character_net.tscn: 83/83 pass (real ENet).
Total run-specific assertions: 521 passed, zero failed. Reused existing test suites. Existing Godot shutdown ObjectDB warnings remain and were not introduced here.

Limits: This is formant bandwidth control, NOT physiological vocal-tract resonance, a new neural speech model, a naturalness guarantee or a subjective listening test. The Czech TTS remains synthetic and the default gameplay setting stays wordless until owner approval. Network schema v20 requires matching clients; no game export or full browser/audio-listening QA performed. Scope for a future pass: perceptual ABX across 0/±0.5/±1 resonance, vocal weight/phonation independence, dynamic coarticulation, better G2P/prosody, and actual streamed user audio samples.