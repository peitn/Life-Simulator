# CHECKPOINT

**Stav: běh 17 dokončen (naplánovaný, 22. 10. 2026 02:49–~04:00 UTC).**

## Shrnutí
- Hudba v3 podle uživatelky (původní skladby, „Noční ticho“ = vzor tónu, nové „Mlhavé ráno“), demo MP3 posláno.
- C4b vlasy/vousy/obočí dokončeno: opravy z renderu v Blenderu (copánky/dredy, dlouhé vlasy na zádech, obočí, undercut),
  async stavba sítě ve hře (review Gemini), tools/hair_export.gd, docs.
- Testy: test_hair 55/55, test_audio_tone 222/222, regrese 20 sad OK, godot_check 60/60, --test 7 OK.
- GitHub: push 403 (mimo autorizované zdroje) – lokální commit 08708ea, ZIP previews/export (MD5 2d50807f…, 34 dílů).

## Další krok (běh 18)
- C3+ B: rty, oči, výška hlavy, tlumení extrémů + okraj skořepiny vlasů u spánků a plnovous.

## Rendery
- docs/images/c4b-hair-run17-before.jpg, c4b-hair-run17-a.jpg, c4b-hair-run17-face.jpg

## Změněné soubory
- scripts/audio/music_data.gd, tests/test_audio_tone.gd, docs/audio.md, audio/music/*.wav, main.gd
- scripts/assets/hair_builder.gd, scripts/assets/hair_rig.gd, scripts/sim/sim_visual.gd, scripts/character/appearance_resolver.gd
- tests/test_hair.gd, tools/hair_export.gd (nový), docs/* , README.md, ROADMAP.md, AUDIT.md, DEVLOG.md, CHECKPOINT.md
