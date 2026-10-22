# CHECKPOINT

**Stav: běh 19 dokončen (ruční spuštění, 22. 10. 2026 ~10:55–11:40 UTC).**

## Shrnutí
- C4b+ detaily vlasů a vousů (hair_builder.gd): okraj skořepiny u spánků bez schodů (dělení trojúhelníků přes linii,
  nejdelší hrana 18 → 8,6 mm); copánky a dredy nepravidelné (tloušťka, délka, tuhost, odklon, houpání; dredy bez
  „korálků“) a rámují obličej (osa ≥ 8,5 cm od středu); plnovous končí pod čelistí (nejníž 1,517 m), bez sloupců,
  bez mezery pod rtem.
- Testy: test_hair 60/60 (+5 kontrol, průnik přesnou projekcí), test_assets 150/150, test_neck_seam 56/56,
  test_character 157/157, godot_check 60/60, --test 7 OK. Gemini: 1 oprava, 5 zdůvodněně odmítnuto.
- Render prohlédnutý: docs/images/c4bp-hair-run19.jpg.
- Běh 18 (C3+ B obličej) byl dokončen předtím ve stejný den (payload ručního spuštění o něm nevěděl).
- GitHub: push blokovaný proxy → ZIP pro ruční sync v res://previews/export (MD5 ve zprávě v místnosti).

## Další krok (běh 20)
- 1. osa psychiky – společný rámec dimenzí (docs/design/psyche-model.md), potom C5 oblečení.

## Rendery
- docs/images/c4bp-hair-run19.jpg (běh 19), docs/images/c3b-face-run18-before.jpg / -after.jpg (běh 18)

## Změněné soubory (běh 19)
- scripts/assets/hair_builder.gd, tests/test_hair.gd, tools/hair_export.gd, docs/images/c4bp-hair-run19.jpg,
  docs/character-creator.md, docs/roadmap.md, docs/testing.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md, CHECKPOINT.md
