# Web version of Life Simulator

The web version follows the same game rules as this project:
- needs, traits, mood and utility AI;
- relationships, grudges and apologies;
- stress, anxiety, panic and depression;
- content settings.

The rules are ported to JavaScript, with an interface built from plain DOM and CSS. It needs neither `<canvas>` nor
WebGL, so it can be played on phones and tablets.

- Play it at: https://lifesim.peiti.workers.dev/ (Cloudflare is only a gateway).
- It is hosted by this server: https://peiti-godot-mcp.hf.space/lifesim/ (files in the Space repository, folder `web/lifesim/`).
- Compared with the Godot project, the web version does NOT yet have: 3D visuals and models, multiplayer, music and
  object sounds, the character editor, the city or building.
- The core is tested headless (47 checks, `node tests/sim.test.mjs`); the rules in `scripts/sim/*.gd` remain the source
  of truth.
