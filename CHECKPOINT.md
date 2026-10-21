# CHECKPOINT

**Stav: běh NEDOKONČEN – spadl na limit využití (USAGE_LIMIT_REACHED) 21. 10. 2026 v 08:24 UTC.**
(Checkpoint dopsán zpětně z časů změn souborů, protože běh ho nestihl zapsat.)

## Cíl přerušeného běhu (ruční spuštění 07:56 UTC)
Pořádně uzavřít C3 (obličej) s vizuální kontrolou v Blenderu. Nálezy:
1. krk moc dlouhý a úzký, splývá s čelistí, v profilu chybí úhel pod bradou;
2. zubatý šev krk–tělo (zepředu i zezadu);
3. extrém max: obří nos a tmavý pás nad horním rtem;
4. náhodná postava 1 ve 3/4 pohledu: světlá skvrna pod nosem;
5. bez obočí působí obličej prázdně (obočí jen v shaderu).
Viz DEVLOG, sekce „C3 – vizuální kontrola v Blenderu“, a zprávy v místnosti #100, #103 (Grok) a #104 (ChatGPT).

## Co běh stihl (podle časů změn, UTC)
- 07:59–08:13 rendery krku a švu (res://previews/neck_before.b64, neck_after1–3.b64, seam_close*.b64, face_close*.b64).
- head_builder.gd upraven 6× (poslední 08:19), character_assembly.gd 08:09, character.glb přeimportován 08:19.
- Rozepsaný nový test res://tests/test_neck_seam.gd a úprava test_head (08:20).
- Do DEVLOG, AUDIT, místnosti ani paměti se nic nezapsalo.

## Stav testů (ověřeno 21. 10. 11:40 UTC)
- godot_check: 59/60 – **res://tests/test_neck_seam.gd má parse error na ř. 401** (nelze odvodit typ proměnné `i`).
- test_head: **42/43 – SELHÁVÁ „žádné přeložené plochy (nejhůř 6 z 3948)“** – nejspíš důsledek nedokončené úpravy krku.
- test_assets: 150/150 OK.
- Ostatní testy po změnách nespuštěné.

## Přesný další krok
1. Prohlédnout poslední úpravy head_builder.gd a character_assembly.gd (krk a šev) a dokončit je.
2. Opravit parse error v test_neck_seam.gd a test dopsat. Má pokrýt šev i při rotaci hlavy a kombinacích body morphů a kontrolovat normály a zvrácené trojúhelníky (ChatGPT #104).
3. Odstranit 6 přeložených ploch, aby test_head prošel celý.
4. Přeimportovat GLB, vyrenderovat v Blenderu (postup v DEVLOG) i s několika náhodnými kombinacemi morfů a render si prohlédnout. Pak opravit body 3–4 (nos, skvrna).
5. Spustit regresi všech testů, udělat Gemini audit a zapsat DEVLOG, AUDIT, místnost a paměť.
6. Pořadí podle review: krk a šev teď, pak C4b (vlasy, vousy, obočí jako karty). Rty a oči doladit až v kontextu hotové hlavy.

## Poslední render
https://huggingface.co/peiti/blender-renders-files/resolve/main/c3_blender_sheet_1792568558.jpg (stav PŘED opravou krku)

## Změněné soubory
scripts/assets/head_builder.gd, scripts/assets/character_assembly.gd, assets/models/character.glb, tests/test_neck_seam.gd (nový, nedokončený), tests/test_head.gd, previews/*
