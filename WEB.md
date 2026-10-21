# Webová verze Life Simulatoru

Stejná herní pravidla jako v tomto projektu (potřeby, rysy, nálada, utility AI, vztahy, křivdy a omluvy, stres, úzkost, panika, deprese,
nastavení obsahu), přenesená do JavaScriptu s rozhraním z čistého DOM + CSS. Nepotřebuje `<canvas>` ani WebGL, takže jde hrát na telefonech a tabletech.

- Hraje se na: https://lifesim.peiti.workers.dev/ (Cloudflare je jen brána)
- Hostuje ho tento server: https://peiti-godot-mcp.hf.space/lifesim/ (soubory v repozitáři Space, složka web/lifesim/)
- Co webová verze zatím NEMÁ oproti Godot projektu: 3D vizuál a modely, multiplayer, hudbu a zvuky objektů, editor postavy, město a stavění.
- Jádro je testované headless (47 kontrol, `node tests/sim.test.mjs`); pravidla v scripts/sim/*.gd zůstávají zdrojem pravdy.
