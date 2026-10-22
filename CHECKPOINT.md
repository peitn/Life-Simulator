# CHECKPOINT

**Stav: běh 21 dokončen (22. 10. 2026, ~21:45 UTC).** První pokus spadl v 19:05, druhé plánované spuštění (20:58) ho dokončilo.

## Cíl běhu
C3++ detaily obličeje a mimika (řasy, zuby/dáseň/jazyk, dutina úst, limbus a zornice, výrazy jako blend shapes, SimVisual
mrkání/výraz/řeč, schéma v6).

## Shrnutí
- Implementace + test_face_detail 55/55; regrese 22 sad OK (3 zastaralé testy upraveny na schéma v6 a rozpočet 20 000 tri).
- Render v Blenderu → oprava úsměvu (koutky) a řas (směr), přeimport GLB, render po opravě prohlédnut.
- Výkon posuvníku 5,8 → 3,7 ms (cache polí face, vah obličeje, názvů blend shapes, zápis jen změn).
- Gemini 8 bodů (1 opraven), AUDIT.md, DEVLOG.md, ROADMAP.md, docs (character-creator, asset-pipeline, testing, roadmap), README.

## Další krok (běh 22)
C5 oblečení + zaoblit koutky otevřených úst; potom integrovaný průchod a 2. osa psychiky.

## Testy
Všech 22 sad prošlo, `--test 7` OK, hra 25 s, `godot_check` 60/60. Dlouhé testy spouštět na pozadí (setsid, logy
previews/testlogs) – godot_run/godot_run_script mají strop 120 s.

## Rendery
- docs/images/c3pp-expressions-run21-before.jpg, docs/images/c3pp-mouth-lashes-run21-after.jpg

## Sync
- ZIP v res://previews/export/ (MD5 a počet dílů ve zprávě #152 v místnosti); GitHub push z plánovaného běhu viz DEVLOG.
