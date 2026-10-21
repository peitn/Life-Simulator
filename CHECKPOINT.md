# CHECKPOINT

**Stav: běh dokončen (běh 13, 21. 10. 2026, ~18:20–19:40 UTC).**

## Shrnutí
- C3+ A2 (krk, rozhodnutí #110) hotovo: anatomická báze krku (pole zvednutí podle směru 4/30/46 mm; C7 1,545,
  bod krk–rameno 1,503, přední krk 9,1 cm = 0,41 výšky hlavy) + posuvník `body.neck_length` (lineární blend shape
  hlavy `b_neck_len` ±15 mm), schéma v4 s migrací v3→v4, temeno = height_cm, randomizér, robustní loop_hit.
- Testy: 17 sad OK (test_neck_length 36 nový, test_neck_seam 56), godot_check 60/60, `--test 7` OK.
- Render v Blenderu 6 postav × 5 pohledů prohlédnut; opravená chyba render knihovny (záporné váhy shape keys).
- Gemini: 4 nálezy zdůvodněně odmítnuté. ChatGPT #111 a Grok #113 zapracováno. Diff k review v místnosti #115.
- Místnost: plán 114, diff 115, shrnutí 116, AUDIT.md rev. 10, paměť (stav rev. 8, otevřené body rev. 10).
- GitHub: **push nejde** (proxy 403 – repo mimo autorizované zdroje naplánované session); lokální commit v klonu
  zanikne s kontejnerem → ruční sync z hlavního chatu (Godot projekt je kompletní a aktuální).

## Další krok (příští běh)
1. GitHub sync (pokud bude přístup) – zahrnout běh 13 (export ZIP s include_hidden).
2. C4b: vlasy, vousy a obočí jako hair cards (shell jen LOD), s renderem v Blenderu (render knihovna v Blenderu
   /tmp/render_lib.py je dočasná – při restartu Space napsat znovu VČETNĚ `kb.slider_min = -1.0`).
3. Potom C3+ B (výška/velikost hlavy ~1 cm, rty, oči).

## Poslední render
docs/images/c3-neck-length-run13-a.jpg (výchozí, krk −1, krk +1) a -b.jpg (svaly+tuk, tuk+krk −1, štíhlá+krk +1);
zdroj res://previews/blender_c13c_*.b64 a blender_c13d_*.b64 (MD5 819b6aae…, e83176ce…). GLB character.glb MD5
a1103c17dace00fad456e6f7c5c644ae (2 759 524 B).

## Stav testů
test_neck_length 36, test_neck_seam 56, test_head 43, test_skin 60, test_assets 150, test_body_morphs 62,
test_character 157, test_character_v2 39, test_character_net 28, test_multiplayer 67, test_depression 92,
test_mental_health 95, test_reconciliation 58, test_player_commands 40, test_psyche_presentation 19,
test_net_protocol 34 – vše OK.

## Otevřené vizuální nálezy
- hlava ~1 cm nižší než reference, u svalnaté postavy působí malá (C3+ B); vlasy = helma, obočí jen shader (C4b);
  rty ploché, oči malé (C3+ B).

## Změněné soubory
scripts/assets/character_assembly.gd, scripts/assets/head_builder.gd, scripts/character/body_morphs.gd,
scripts/character/face_morphs.gd, scripts/character/appearance_resolver.gd, scripts/character/character_schema.gd,
scripts/character/character_codec.gd, scripts/character/character_randomizer.gd, scripts/character/skin_layers.gd,
tests/test_neck_seam.gd, tests/test_neck_length.gd + .tscn (nové), tests/test_skin.gd, assets/models/character.glb +
manifest.json, docs/images/c3-neck-length-run13-a.jpg, -b.jpg, AUDIT.md, DEVLOG.md, ROADMAP.md, README.md,
docs/character-creator.md, docs/roadmap.md, docs/testing.md, docs/asset-pipeline.md, CHECKPOINT.md
(+ dev nástroje previews/devtools/apply_bundle.gd, previews/patches/run13_*.txt mimo repozitář)
