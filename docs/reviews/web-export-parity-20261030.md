# Life Simulator — web vs. native source parity audit (30 October 2026)

Web URL: https://peiti-godot-mcp.hf.space/play/lifesim/
Godot MCP project: `lifesim`, Godot 4.7.2.
This is a **new production web export** using current Godot source, not the old PCK.
Rebuilt on 30 October 2026 at ~11:01 UTC with export preset "Web" (no threads).
`index.pck`: 100,397,748 bytes, SHA-256
`1690bc6b7e4b67f52b5d191e56472df9359208c47d89a3b82bf99b05cc983e2b`.
`index.wasm`: 39,514,754 bytes, SHA-256
`fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0`.
`index.html`: restored accessibility, mobile viewport and Canvas/WebGL diagnostics
from the previous customized production HTML, while adopting freshly generated
`GODOT_CONFIG.fileSizes` and cache-busted JS URL. HTTP GET 200 verified for HTML,
PCK, WASM and JS and updated HTML content. All files have valid expected signatures.

## Code/content inclusion (tested by PCK path-string presence)

- `main.gd`, `scripts/character/character_schema.gd`, `scripts/ui/voice_editor.gd`,
  `scripts/ui/settings_menu.gd`, `scripts/core/game_settings.gd`,
  `scripts/audio/neural_voice.gd` and procedural `voice_synth.gd` are packaged.
- `assets/city/`, `scripts/city/`, and `scenes/city/` path entries found.
- H2/H2b editor, wardrobe, public character voice field and H3 creator-to-household
  code are in current source/PCK; this is code/content inclusion, **not**
  an interactive browser acceptance test or evidence that every city asset is placed.
- Latest game source updates on 30 October include voice resonance and neural voice
  cache validation changes. Test-only and documentation changes have no direct gameplay effect.

## Confirmed differences, NOT complete parity

1. **Piper neural speech** depends on Python/ONNX + two model files under
   `/app/library/lifesim/neural_models` on the native Godot host. Browser
   WebAssembly cannot invoke the local Python process. `NeuralVoice.supported()`
   returns false for web, and its editor/settings option is intentionally disabled.
   Script presence inside PCK does not make it executable. Legacy wordless/formant
   voice remains available as allowed by settings.
2. **High-detail character mesh:** `assets/models/character_hq.glb` (around
   32.8 MB) is excluded by the `Web` export preset; desktop export includes all
   resources. Web uses an available lighter representation. No promise of
   full desktop mesh/material/lighting parity.
3. **Multiplayer transport:** `scripts/net/net_session.gd` uses
   `ENetMultiplayerPeer` and lacks a WebSocket/WebRTC transport implementation.
   Godot Web exports do not provide browser UDP/ENet. Therefore do not promise
   native host/join multiplayer works in web until a browser transport exists.
4. **Rendering:** native project is configured for Forward+ while web uses
   `gl_compatibility`/WebGL2. Some GPU effects and visual fidelity will differ.
5. **Browser save input and compatibility:** browser IndexedDB/userfs, mouse
   capture, touch controls and WebGL2 support vary by device/browser. Game runtime
   not exercised in a real interactive browser on Android here; no claim
   that prior mouse/canvas/animation issues are all fixed.
6. Separate Blender libraries, offline Elmer simulations and native services
   are NOT implicitly merged into web game resources simply by exporting `lifesim`.

## Tests
- `godot_check`: 60 / 60 GDScript compile passed.
- Headless `tests/test_full_playable_slice.tscn`: 87 / 87 passed, exit 0,
  includes creator household persistence and appearance/psychological privacy.
- Headless `tests/test_neural_tts.tscn`: 18 / 18 passed, exit 0,
  for native CPU Piper. These are native/headless tests, not browser tests.
- Source scene headless startup printed `Life Simulator spuštěn (Offline) –
  3 postavy, 9 interaktivních objektů.`; command was time-limited because
  game remains running, not scored as successful completion.
- No Chromium/Firefox browser binary, browser automation framework or
  interactive graphical input test was available on the connected engine host.

## Native artifact timestamp caution
Pre-existing Windows ZIP export `lifesim-windows.zip` was built earlier
30 Oct at 00:47 UTC. New web export is **newer than that native ZIP**, but
the source-native project contains the same current core scripts. For
a byte-time-aligned binary comparison, rebuild Windows/Linux from the same
source revision; this web audit did not need to alter those artifacts.

## Next work
A browser-side voice TTS API (secured+cached), ENet-to-WebSocket/WebRTC
multiplayer transport, optional HQ asset budget, mobile browser input smoke
test and graphical screenshot comparison are independent follow-ups.
