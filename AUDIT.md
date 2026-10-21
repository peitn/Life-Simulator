# Life Simulator – audit kvality

Každý běh: self-review změněných souborů, `godot_check`, automatické testy v `res://tests/`,
nezávislý audit (Gemini, příp. ChatGPT v AI místnosti). Otevřené nálezy mají v dalším běhu přednost.

Spuštění testů: `godot_run scene=res://tests/<test>.tscn` a `godot_run -- --test N` (headless simulace).

---

## 2026-10-21 (běh 10b, ~07:25–08:10 UTC, ruční spuštění) – vizuální kontrola obličeje C3 a opravy podle ní

### Jak se kontrolovalo
- Konektory: Godot ✅, Audio Engine ✅, Blender ✅ (4.0.2 – po 503 opět běží), Gemini ✅, AI room relay ✅.
- Blender umí vrátit obrázek jen ze scény z primitiv (`blender_render_frame`), vlastní síť přes JSON nepřenese (typ `mesh` → chyba 500).
- Cesta, která funguje: `tools/raster_preview.gd` vykreslí **skutečný character.glb** (blend shapes + normály sítě), Godot uloží
  JPG jako base64 do `res://previews/*.b64`, `godot_file_read` velký výstup uloží do souboru v mém prostředí, dekóduji ho
  a **obrázek si prohlédnu okem** (MD5 base64 ověřené u každého snímku). Hotové snímky jsem poslala i uživatelce.

### Co bylo vidět (nálezy) a co se opravilo
1. **Chyběla spodní plocha čelisti a úhel brada–krk** (profil: brada plynule klesala do krku pod 45°), krk byl vpředu
   (hrdlo z = 0,05 m), dolní třetina obličeje krátká (ústa–spodek brady 3 cm). **Opraveno** v `head_builder.gd`:
   osa krku za středem hlavy (`NECK_ZC −0,012`, plynule k 0 u těla – `neck_zc(y)`), eliptický krk (0,96 × 1,04),
   hranatější dolní přední část lebky (exponent +1,1), spodek brady níž (`b` 0,112 → 0,119, reliéf brady −0,106),
   ostřejší přechod hlava–krk (`smax` 0,012 → 0,009). Teď: ústa–spodek brady **4,4 cm**, brada **4,0 cm** před krkem.
2. **Schod na zátylku** mezi „rukávem“ krku hlavy a krkem těla (po posunu osy) – **opraveno** proměnnou osou krku; schod 8 mm.
3. **„Zubaté“ světlé skvrny podél linie čelist–krk** (sbíhající se paprsky → úzké plošky s prudce se měnícími normálami) –
   **opraveno** vyhlazením normál (ne poloh) v pásu čelist–krk, mimo ústa, oči a uši; stejný operátor pro základ i všechny cíle.
4. **Svislé pruhy ve stínování krku** – **zmírněno**: normály krku = gradient eliptického válce (směr nezávisí na škálování morfy).
5. **„Balón“ pod čelistí při tuku 1,0** (krk se rozšiřoval jen nahoře) – **zmírněno**: rozšíření po celé délce krku, vpředu
   slabší, koeficient tuku 0,30 → 0,22. Vzadu u extrémního tuku zůstává výrazný val – přijatelné, sledovat.
6. **Nezměněno, otevřené:** (a) zubatý šev na spodku krku, kde se protíná rukáv krku hlavy s krkem těla (dvě sítě se
   protínají; řešení = sdílená topologie krku hlava–tělo, samostatný krok); (b) rty vypadají jako plochá „nálepka“
   s hranatým obrysem, chybí objem a koutky; (c) oči působí malé a zapadlé; (d) účesy jsou přilba a dvě trubky
   (C4b); (e) extrémní kombinace (všechna pole −1) dávají propadlý obličej – v mezích, ale editor by měl extrémy tlumit.
- Testy: `test_skin` +3 kontroly profilu (dolní třetina 4–5 cm, brada ≥ 3 cm před krkem – teď 3,7 cm, zátylek bez schodu ≤ 12 mm – teď 6,1 mm),
  překalibrované body jizev na bradě a čelisti. **test_skin 60/60, test_head 43/43, test_assets 150/150,
  test_body_morphs 62/62, test_character 157/157, test_character_net 28/28, `--test 3` OK.**
- Poučení: chyba parsování ve skriptu testovací scény způsobí **zamrznutí** běhu (ne chybu) – před spuštěním ověřovat
  `GDScript.reload()`; `godot_check` složku `tests/` nekontroluje.

### Audit Gemini (flash-lite) ke změnám hlavy
1. *KRITICKÁ: váhy vyhlazení normál z polohy cíle* – **oprávněné, opraveno**: váhy (pásmo, krk) se počítají z polohy
   ZÁKLADU pro všechny cíle (`_normals(pos, faces, wpos)`), takže se stínování při míchání blend shapes nemění skokem.
2. *KRITICKÁ: nekonvergence iterace průsečíku s krkem* – **oprávněné, opraveno**: měření ukázalo pomalou konvergenci
   u paprsků mířících šikmo dozadu (residuum elipsy až 12 %); teď až 12 iterací s ukončením při změně < 1 µm → residuum 0,12 %.
3. *Godot importér přepočítá normály blend shapes* – **neoprávněné**: GLB se načítá za běhu přes GLTFDocument (importér „keep“),
   normály ze souboru se používají (test_body_morphs ověřuje normály cílů).
4. *Determinismus importu napříč platformami* – **zdůvodněno**: import běží jednou, hra načítá hotový GLB (determinismus
   za běhu ověřuje test_head na vahách); pořadí sousedů je dané pořadím ploch.
5. *Šev krk hlavy × krk těla* – **oprávněné, otevřené** (bod 6a níže).

### Stav C3
Tvar obličeje a krku je po vizuální kontrole věrohodný (přední, ¾, profil, zezadu; typické i extrémní). **C3 uzavírám
s výhradami** výše (6a–6e), které jsou v otevřených bodech; 6d řeší C4b, 6a samostatný krok „napojení hlavy na tělo“.

---

## 2026-10-21 (běh 10) – uzavření C3 (vizuální kontrola, review Grok 74 / ChatGPT 78) + C4a kůže

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 60/60 skriptů OK (pozn.: nástroj nekontroluje `tests/` – parse chyby testů se ukážou až při běhu, viz níže) |
| `tests/test_skin.tscn` (nový: SkinModel – spojitost (skok ≤ 0,0011 na 0,001), monotonie, spektrum 0,752 → 0,028 lin. světlosti, 98/100 různých barev, podtón a prokrvení na celém spektru, NaN/±∞, shoda se starými kotvami 0,041, CPU barva = chromofory pro shader (0,0005), **celá mřížka 1 386 kombinací: sytost ≥ 0,19, odstín −3°…43°**; SkinLayers – determinismus i po sdílecím kódu a JSON, kvantizace 1/10000, skryté položky, pevné délky polí, nezávislost na jménu/rodu/identitě, detail_seed mění rozmístění, vrásky s věkem, poškozený snapshot bez NaN, limit 6 jizev; **umístění jizev a tetování na povrchu modelu** (obličej 1,4 mm, krk 8,1, trup ≤ 3,6, končetiny ≤ 7,4 mm); shader se zkompiluje (39 parametrů), každý výstup má parametr, konstanty ze SkinModel; CUSTOM0 = klidové polohy jen u 2 sítí kůže, blend shapes/kosti zachované; SimVisual – vlastní ShaderMaterial na postavu, parametry = resolver, hlava+tělo sdílí materiál, 0,013 ms aplikace, 0,11 ms výpočet; schéma v3 + migrace v2→v3; C3 review – mezitvary mají rodiče, váhy těla kvantované) | **57/57 OK** |
| `tests/test_character.tscn` | **157/157 OK** (posuvník 3,30–3,80 ms, limit 4 ms) |
| `tests/test_character_v2.tscn` | **39/39 OK** (migrace v1 teď končí ve v3) |
| `tests/test_assets.tscn` | **150/150 OK** |
| `tests/test_head.tscn` | **43/43 OK** |
| `tests/test_body_morphs.tscn` | **62/62 OK** |
| `tests/test_character_net.tscn` | **28/28 OK** |
| `tests/test_multiplayer.tscn` | **67/67 OK** |
| `tests/test_depression.tscn` / `test_mental_health` / `test_reconciliation` | **92/92**, **95/95**, **58/58 OK** |
| `tests/test_player_commands` / `test_psyche_presentation` / `test_net_protocol` | **40/40**, **19/19**, **34/34 OK** |
| `--test 7` | OK (25,3 ms/herní hodinu, 0 min v kritickém stavu) |

### Vizuální kontrola C3 – co šlo a co ne (otevřeně)
- Blender Space opět **503** → žádný Cycles render.
- Napsala jsem `tools/raster_preview.gd`: softwarový rasterizér nad **skutečným character.glb** (blend shapes stejnou cestou
  jako SimVisual, z-buffer, Gouraud). Kontaktní arch 6 obličejů × 5 úhlů (výchozí, 2 typické, všechna pole +1, všechna −1,
  smíšené extrémy s asymetrií a tukem 1) je uložený v projektu: **`res://previews/c3_face_sheet.png`** (800×960).
- **Okem jsem ho neviděla**: z Godot serveru nejde obrázek přenést do mého prostředí (výstup nástroje se ořezává
  a ruční přepis 80 kB base64 by byl nespolehlivý). Prohlédla jsem jen ASCII převzorkování dvou dlaždic (silueta,
  uši, krk, vlasy bez děr) a automatickou kontrolu „díry v siluetě“ (pozadí uvnitř obrysu ≤ 46 px/dlaždici – mezery
  ucho–hlava a vlasy–krk, žádné trhliny). **C3 tím vizuálně uzavřené NENÍ** – PNG je připravené pro lidskou kontrolu
  (uživatelka / ChatGPT), případně zopakovat Blender render, až Space poběží.

### Nálezy z vlastních testů (opraveno)
- **Body jizev a tetování na trupu ležely 3–5 cm pod povrchem** (odhadnuté souřadnice; tetování by se vůbec
  nevykreslilo, protože hloubková tolerance je 2 cm). Zkalibrováno nejbližším bodem povrchu výchozí sítě, test hlídá.
- `SkinModel.chromophores` propouštěl **NaN** (clampf NaN neořízne) → nekonečné/NaN vstupy = výchozí hodnoty.
- Skryté jizvy/tetování zabíraly místo v limitu shaderu (prvních 6 položek) → počítají se jen viditelné.
- Godot **parser zamrzl** na dlouhém výrazu s `\` pokračováním řádku v testu (žádná chyba, jen visel) – přepsáno do smyčky.
- `ArrayMesh` nemá `find_blend_shape_by_name` (je na MeshInstance3D) – oprava testu.

### Review Grok 74 / ChatGPT 78 (C3)
- Mezitvary: ověřeno testem, že každý `*_mid` má rodiče a nelineární morf s mezitvarem ho má pro obě strany
  (dnes jen délka nosu). Chybějící mezitvar váhu „neztratí“ – lineární tvar se aplikuje dál, mezitvar jen opravuje.
- Kvantizace vah těla před vazbou na obličej a korekcemi: už platí (BodyMorphs kvantuje 1/1000), test hlídá.
- Hubnutí v obličeji (Grok 74/4): **zdůvodněno, beze změny** – výchozí hlava je štíhlá, vazba je záměrně jen nárůst
  (dokumentováno ve FaceMorphs); propadlé tváře přidám s mimikou/stárnutím, aby nevznikla jedna „nemocná“ tvář pro hubená těla.

### Audit Gemini (`gemini-3.5-flash-lite`; `3.5-flash` přetížený)
1. *VYSOKÁ: float nedeterminismus mezi peery* – **zdůvodněno**: všechny vstupy shaderu jsou na CPU kvantované (1/10000)
   a deterministické (test po sdílecím kódu); rozdíl GPU v posledním bitu šumu je subpixelový a nemá herní dopad.
2. *VYSOKÁ: výkon fragmentu* – **částečně oprávněné, opraveno**: LOD – jemné detaily (pihy, póry, chloupky, strniště,
   znaménka, akné) se od 6 m plynule vypínají (i proti mihotání šumu). Smyčky jizev/tetování už končí na skutečném počtu
   a přeskakují mimo hloubku. Pečení do textury nejde (síť nemá UV) – zvážit v C8 podle profileru.
3. *VYSOKÁ: Compatibility/web* – **otevřené, neověřitelné headless**: `sss_mode_skin`/`SSS_STRENGTH` Compatibility renderer
   podle dokumentace ignoruje; CUSTOM0 je podporovaný. Navržený preprocesor Gemini byl nesmyslný. Ověřit ve webovém buildu.
4. *STŘEDNÍ: DoS přes snapshot* – **neoprávněné**: kód postavy má limity velikosti (8 kB kód, 32 kB JSON, CRC, zip-bomb test),
   posílá se jednou v hello; seznamy mají limity schématu. Rate-limit změn vzhledu až s převlékáním ve hře (C5).
5. *STŘEDNÍ: bez UV tetování „plave“* – **neoprávněné**: masky jsou v klidových souřadnicích vrcholu (CUSTOM0), které se
   nemění animací ani morfy – test ověřuje CUSTOM0 = rest.
6. *STŘEDNÍ: riziko „mrtvolných“ odstínů* – **oprávněná kontrola, přidán test**: celá mřížka melanin × podtón × prokrvení
   drží sytost ≥ 0,19 a odstín −3°…43°.
7. *NÍZKÁ: 33 volání set_shader_parameter* – **zdůvodněno**: jen při změně vzhledu, změřeno 0,013 ms.

### Otevřené body
- C3: lidská kontrola `res://previews/c3_face_sheet.png` (nebo Blender render), zuby/jazyk/mimika.
- Kůže ve webovém buildu (Compatibility) neověřena; vizuál shaderu neviděn (headless).
- Vrásky jen jako ztmavení/AO (síť nemá tangenty pro normal mapu) – C8 / s mimikou.
- Posuvník vzhledu 3,3–3,8 ms (limit 4) – v editoru (C6) aplikovat jen změněnou skupinu.

---

## 2026-10-20 (běh 9) – C3 obličej (procedurální hlava s blend shapes) + review ChatGPT 48/49 + schéma v2

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 60/60 skriptů OK |
| `tests/test_head.tscn` (nový, ~45 s: každé z 32 polí obličeje má morf s účinkem ≥ 0,5 mm; tělo → obličej (tuk, svaly); mezitvary délky nosu; 8 korekčních tvarů; topologie; FaceMorphs – výchozí = 0, ±/pos/neg, korekce = součin vah ve správném kvadrantu, NaN/INF/text → výchozí, ořez, kvantizace, hubnutí nedeformuje, jméno/rod obličej nemění; determinismus (bit po bitu), souměrnost výchozí hlavy 0,0002 mm, souměrné morfy souměrné, každá osa asymetrie souměrnost poruší; **blend shapes ve hře × přesný tvar**: jedno pole ±60 % ≤ 0,61 mm, dlouhý nos + vysoký hřbet 0,00 mm s korekcí (4,32 mm bez), typické obličeje max 1,17 mm / průměr 0,044 mm, extrémy všech 32 polí max 3,89 / průměr 0,20 mm; **průniky** na 48 kombinacích extrémů (rohy oční podprostoru + náhodné): vůle kůže–oko ≥ 0,71 mm, rty se nepřekříží (≥ 0,495 mm), 0 přeložených ploch; GLB – face_spec v manifestu, zúžený krk těla (89 vrcholů), 62 blend shapes = morfy HeadBuilderu, hlava+oči 7 760 tri, vlasy převzaly 20 morfů lebky; **SimVisual: všech 268 hodnot blend shapes hlavy a vlasů = data**; aplikace obličeje 0,17 ms; 20 obličejů server × klient (veřejný snapshot přes JSON) bit po bitu stejné; domácnost má různé obličeje) | **43/43 OK** |
| `tests/test_character_v2.tscn` (nový: kontrakt `repaired()` – 5 fatálních vstupů → platná výchozí postava + `fatal`; 128bit uid, starší 16hex uid přijato, jiná délka odmítnuta; hranaté závorky v textech + `display_safe` ověřené na skutečném RichTextLabel; **korpus 42 jmen** (perština, urdština, arabština s harakát, hebrejština s niqqud, dévanágarí, bengálština, tamilština, telugština, kannadština, malajálamština, gurmukhí, gudžarátština, thajština, laoština, vietnamština NFC i NFD, gruzínština, arménština, amharština, korejština, japonština, čínština, řečtina, azbuka, turečtina, islandština, jorubština, havajština, irština…) projde, 12 záškodnických (zalgo i arabské, bidi, RLM, ZWJ/ZWNJ, emoji, číslice, _, ∑, VS16) odmítnuto; jizvy/tetování: skryté nejdou ve snapshotu, veřejně jen render klíče, hidden ve snapshotu = chyba, allowlist z poškozených dat editoru; migrace v1 → v2 + server přijme v1 kód; temeno na **6 405 kombinacích výška × nohy × head_size: max 0,0013 mm**; head_size ±6 %; validace tabulky kostí; náhled české gramatiky) | **39/39 OK** |
| `tests/test_character.tscn` (upraveno: uid 32 hex, 29 morfů + 3 osy asymetrie, fuzz „jiná verze“ = VERSION+1, vnořená data striktně) | **157/157 OK** |
| `tests/test_character_net.tscn` (+1: server klientovo uid zahodí a přidělí vlastní 128bit) | **28/28 OK** |
| `tests/test_assets.tscn` (rozpočet postavy 18 000 tri – obličej; uzel `head__face`) | **150/150 OK** |
| `tests/test_body_morphs.tscn` | **62/62 OK** (posuvník těla 1,06 ms – teď zahrnuje i obličej) |
| Regrese: test_multiplayer 67, test_depression 92, test_mental_health 95, test_reconciliation 58, test_player_commands 40, test_psyche_presentation 19, test_net_protocol 34 | **vše OK** |
| `--test 7` | OK (25,8 ms/herní hodinu vč. načtení většího GLB; vztahy v domácnosti dál −45…−58) |

### Vizuální kontrola
- **Blender (HF Space) vrací 503** – náhled v Cycles v tomto běhu nešel. Náhradou softwarový rasterizér v Godotu
  (ortografický pohled zepředu a z boku do ASCII, 64×46): silueta lebky, uši, oči, nos, ústa, brada a krk sedí;
  nosní profil je spíš decentní. **TODO:** render v Blenderu, až služba poběží (head mesh přenést jako
  delta-kódovaný blob ~30 kB textu).

### Review ChatGPT 48/49 – stav
| # | Nález | Stav |
|---|---|---|
| 48.1 | jizvy/tetování vždy veřejně | **opraveno**: per-položka `hidden`, veřejně jen render klíče neskrytých položek |
| 48.2 | snapshot ze surových dat, set_path_value bez validace | **opraveno**: allowlist ze schématu + `repaired(public_only)`; zápis bez validace zdokumentován (editor), validuje se při exportu/odeslání |
| 48.3 | 64bit uid, klientské uid jako identita | **opraveno**: 128 bit (Crypto), server přepíše vlastním (test v MP) |
| 48.4 | `repaired()` vrací `{}` | **opraveno**: `fatal` + bezpečné výchozí, novější verze → výchozí |
| 48.5 | Unicode jen vybrané bloky | **opraveno**: XID_Start/XID_Continue (`is_valid_unicode_identifier`), run kombinujících 3, korpus 42 jmen |
| 48.6 | zákaz [ ] v textech | **opraveno**: povoleno, `display_safe()` při vykreslení |
| 49.A | velikost hlavy vázaná na výšku | **opraveno**: `body.head_size` (±6 %), HEAD_EXP zdokumentován jako heuristika |
| 49.B | kvantizace temene | **opraveno**: s na 1e-4, hlava dopočtena z kvantovaného s (1e-5); změřeno 6 405 kombinací, max 0,0013 mm |
| 49.C | záporné váhy, manifest morph_bones | lineární klíče se zápornými vahami pokryté od C2 (normály, skinning); **opraveno**: tabulka kostí – allowlist, konečná čísla, |x| ≤ 0,1 m |
| 49.D | výkon 8/16/32 postav, exportovaný GLB, ztrátový MP | **otevřené** (C8) |
| 49 čeština | ono/oni opt-in, neutrální opis, náhled vět | ono/oni jsou volitelné, nikdy výchozí z identity; **přidán** `Grammar.preview()` pro editor; režim „neutrální opis“ (věty bez rodového příčestí) **otevřený do C7** – vyžaduje alternativní šablony všech hlášek |
| 49 C3 | extrémy × oči, zuby, krk, rig, asymetrie, mimika | oči/rty/krk/asymetrie testovány (viz výše); zuby zatím nejsou (dutina úst je tmavá kapsa), mimika přijde s animacemi obličeje (TODO) |

### Audit Gemini (`gemini-3.5-flash`)
1. *Vysoká: apply_face_shape nepoužívá FaceMorphs.weights* – **neoprávněné**: `look_params["face"]` je už výstup
   `FaceMorphs.weights()` z AppearanceResolveru (Gemini dostal zkrácený výňatek); test ověřuje všech 268 hodnot.
2. *Vysoká: prázdný kód postavy obejde přepis uid* – **neoprávněné**: prázdný kód = hráč bez vlastní postavy
   převezme postavu domácnosti, nic se z klientských dat nespawnuje (test_character_net „B bez kódu“).
3. *Vysoká: clothing obchází allowlist* – **neoprávněné**: celý snapshot vč. clothing jde přes validátor
   (`_clothing` – jen známé kategorie a klíče, katalogy, barvy). „deep copy“ byla zkratka v zadání auditu.
4. *Vysoká: dělení nulou v scales()* – nedosažitelné (výška ořezaná 145–205 cm → s ≈ 0,8–1,2), ale levná
   pojistka **přidána** (`s = maxf(s, 0.1)`).
5. *Střední: alokace řetězců v is_combining* – **neoprávněné pro tento rozsah**: validace jen při vstupu
   (jména ≤ 24, texty ≤ 600 znaků); návrat k ručním blokům je přesně to, co review ChatGPT 48 kritizovalo.
6. *Střední: zástupné jméno „Bezejmenná“ je rodové* – **oprávněné → opraveno**: `FALLBACK_NAME = "Bez jména"`.
7. *Nízká: escapování až při vykreslení lze zapomenout* – **vědomé rozhodnutí** (data zůstávají věrná,
   escapuje se podle konkrétního UI); do C7 (editor/HUD) přidat jediný pomocník pro všechny texty postavy a test,
   že žádný RichTextLabel nedostane text postavy bez `display_safe`.

### Nálezy z vlastních testů (opraveno)
- Lineární míchání blend shapes ujelo u kombinace délka nosu × hřbet o 4,3 mm a u délky nosu v polovině o 2,1 mm
  → **korekční tvary** (8) a **mezitvary** (2); typická chyba teď 0,04 mm průměr / 1,2 mm max.
- Rozpracovaný kód z přerušeného běhu odkazoval na neexistující soubory (head_ref.py, head_check.py) → komentář opraven.
- Domácnost neměla data obličeje (všichni stejní) → explicitní obličeje pro Janu, Petra a Elišku.
- Test: PackedInt32Array v Dictionary je hodnotový typ (append na kopii) – chyba v testu, ne v kódu.
- Nástroj zápisu souborů převádí `\uXXXX` v obsahu na skutečné znaky → bidi znak v testu shodil parser
  (Godot to správně odmítá); escapy se v testech teď skládají z kódů.

### Otevřené body
- Vizuální kontrola obličeje v Blenderu/enginu (Blender 503, headless Godot nerenderuje).
- Zuby, jazyk, mimika (blend shapes výrazů) a víčka při mrkání – s animacemi obličeje.
- Neutrální opis v češtině (C7), jeden pomocník pro escapování textů postavy (C7).
- Výkon 8/16/32 postav s různými obličeji, export GLB do buildu (C8). GLB postavy 2,6 MB.
- „Studená válka“ v domácnosti (vztahy −45…−58 po týdnu).

---

## 2026-10-15 (běh 8) – C2 tělo se shape keys: LSX v4, Catmull-Clark, blend shapes, klouby

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 55/55 skriptů OK |
| `tests/test_body_morphs.tscn` (nový: Catmull-Clark na krychli – vrcholový bod 5/9, hranový a plošný bod, linearita operátoru, normály ven, váhy kostí = 1, odmítnutí otevřené sítě; LSX v4 – 868 řídicích vrcholů → 6 928 trojúhelníků jako v Blenderu, amplitudy všech 10 morfů = Blender ± rezidua, lokálnost poprsí, normály základu i fat_hi jednotkové a ven; 8 druhů poškozených dat odmítnuto; GLB – jména a pořadí blend shapes, režim NORMALIZED, absolutní cíle, morph_bones v manifestu; mapování – výchozí = 0, extrémy, nesmysly/NaN/Inf → výchozí, fuzz 500 těl v ⟨−1,1⟩, nezávislost na rodu/identitě/jméně, determinismus přes JSON; výška temene = height_cm (max 1,3 mm analyticky, 5,0 mm CPU skinningem), chodidla na zemi; **hodnoty blend shapes na všech 4 částech těla = data**; stehno/hlava/model škálované; posun kloubu ramene; **paže posunutá morfem jen jednou** (CPU skinning, odchylka 0,02 mm); výkon změny těla 0,11 ms) | **62/62 OK** |
| `tests/test_assets.tscn` (upraveno: složená postava body v4 + character_head v3, LSX v3 stále čitelné, rozpočet postavy ≤ 12 000, jedna neutrální síť, 10 blend shapes) | 145/145 OK |
| `test_character` / `test_character_net` / `test_multiplayer` / `test_depression` / `test_mental_health` / `test_reconciliation` / `test_player_commands` / `test_psyche_presentation` / `test_net_protocol` | 157, 27, 67, 92, 95, 58, 40, 19, 34 – vše OK |
| `--test 7` | OK, 19,6 ms/herní hodinu |
| Ruční běh (offline) | bez chyb |

### Ověření mimo Godot
- Blender: `cc_matrix()` (numpy) = Blender Subdivision Surface bez limitní plochy, max. chyba 3,6e-7 m.
- Nejmenší čtverce řídicí sítě: rezidua 0,6–3 mm, u poprsí 11,8 mm (řídicí síť je na lokální lalok hrubá – výsledná
  výchylka 39 mm místo 51 mm; přijatelné, zlepší jemnější síť v C3/C5).
- Náhledy z Cycles (5 těl zepředu a z boku: výchozí, obezita, svalnatá, poprsí+boky+útlý pas, štíhlá) prohlédnuty
  – hladké tvary bez vln.
- Přenos 7 částí (21,5 kB): CRC každé části ověřeno už při přepisu; v Godotu složeno bez chyby.

### Nalezené a opravené chyby (vlastní testy)
1. `subdiv.gd`: `PackedInt32Array` v poli je hodnotový typ → `append` na kopii se ztrácel (síť se jevila jako
   otevřená) → pole seznamů jsou `Array`.
2. Morf ramen/kyčlí by se v póze přičetl dvakrát (shape key posune paži + posun kosti) → SimVisual mění REST kosti
   a inverzní bind (vlastní kopie Skin); test CPU skinningem.
3. Godot GLTF export ukládá blend shapes správně jen v režimu NORMALIZED s absolutními cíli (RELATIVE: cíle zapsané
   jako delty → zdvojení; nulové delty normál rozbije oktaedrická komprese) – ověřeno round-trip testem.
4. Indexy kostí v importovaném GLB odkazují na bind skinu, ne na kost kostry – test i SimVisual mapují přes Skin.
5. Krystal nálady a popisek nad hlavou byly ve fixní výšce (u postavy 205 cm by kolidovaly) → podle výšky.
6. Fallback z primitiv měl účes podle rodu → neutrální.

### Gemini (gemini-3.5-flash-lite; flash přetížený)
- Oprávněné (drobné): pojistka diskriminantu v `BodyMorphs.scales()` (matematicky je vždy kladný – `_val` ořezává
  výšku, b > 0) → `maxf`.
- Zdůvodněno, neopraveno: „přetečení bufferu v decode_morphs“ – délka = nv·3 a rozsah v blobu se už kontrolují
  (`_range`, test „délka morfu nesedí“); „float drift mezi peery“ – dekódování probíhá jednou při importu, peery sdílejí
  stejný GLB a váhy jsou kvantované na 1/1000; „server neověřuje váhy“ – váhy se po síti neposílají, klient posílá
  CharacterData, které server ověřuje striktně (C1), váhy si každý peer spočítá sám; „duplikace Skin za běhu“ –
  děje se jednou na postavu, dál se mění jen 17 bind matic.
- Citlivost: potvrzeno – jedna neutrální síť, žádné „mužské/ženské“ šablony.

### ChatGPT
- Plán C2 (zpráva 44) a `body_morphs.gd` k review (zpráva 45) – do konce běhu bez odpovědi; otevřené review 41/42
  (character_data, validátor) stále bez odpovědi.

### Známé limity
- Vizuál ve hře ověřen jen numericky a náhledem z Blenderu (headless Godot nerenderuje).
- Hlava a vlasy jsou zatím v3 (bez morfů) – C3/C4. Oblečení je pořád „namalované“ na těle (C5).

---

## 2026-10-15 (běh 7) – C1 tvorba postavy: CharacterData, validátor, kodek, síť; review depression.gd

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 52/52 skriptů OK |
| `tests/test_character.tscn` (nový: schéma a výchozí hodnoty, žádná volba „rasa“/etnické předvolby; round-trip JSON / sdílecí kód / soubor / Resource .tres pro 60 postav; migrace v0→v1 vč. věrnosti vzhledu (max. odchylka kanálu 0,043) a poškozené v0; filtr jmen – 14 povolených písem světa, 22 druhů odmítnutí (bidi, neviditelné, zalgo, BOM, tag znaky, emoji…); **fuzz 650 nevalidních vstupů / 26 druhů – server odmítl 100 %**, opravný režim vždy platný a idempotentní; kodek: CRC, délka, base64, zip bomba 200 kB, 16 000 úrovní vnoření, JSON ne-objekt, zalomený kód; determinismus vzhledu přes var_to_bytes i JSON; veřejný × soukromý snapshot; generátor: 600 postav platných, výška 170,8 ± 9,3 cm, nezávislost výšky a účesu na rodu, rovnoměrná kůže, predispozice se bez volby nelosují, zámky, determinismus; undo/redo vč. náhody se zámky a slučování tažení posuvníku; gramatika on/ona/ono/oni; nastavení obsahu; výkon změny posuvníku 0,76 ms; integrace – domácnost z CharacterData, přejmenování nemění vzhled) | **157/157 OK** |
| `tests/test_character_net.tscn` (nový: vstup s vlastní postavou přes ENet, spawn na serveru, bit po bitu stejný vzhled na serveru a 2 klientech, k cizímu klientovi se nedostane identita/orientace/příběh/predispozice/uid, odmítnutí bidi jména, nezletilé postavy, podvrženého CRC a příliš dlouhého kódu s důvodem pro klienta, nastavení obsahu serveru, odchod hráče = despawn u všech) | **27/27 OK** |
| `tests/test_depression.tscn` (+17 kontrol z review ChatGPT 39) | **92/92 OK** |
| `tests/test_multiplayer.tscn` | 67/67 OK (hello má nově 3. parametr) |
| `tests/test_assets.tscn` | 146/146 OK (test vzhledu ze jména nahrazen testem vzhledu ze snapshotu) |
| `tests/test_mental_health.tscn` / `test_reconciliation` / `test_player_commands` / `test_psyche_presentation` / `test_net_protocol` | 95/95, 58/58, 40/40, 19/19, 34/34 OK |
| `--test 7` | OK (0 min v kritickém stavu), 19,8 ms/herní hodinu |
| Ruční běh `--character LSC1…` | postava „Kim“ se objevila ve světě (4 postavy), bez chyb |

Očekávané chyby ve stderr `test_character`: `Decompression failed` – záměrné testy poškozeného kódu a zip bomby.

### Nálezy z vlastních testů a self-review (opraveno)
- **Odmítnutý klient nedostal důvod**: `disconnect_peer` hned po `_s2c_notice` zahodilo frontu spolehlivých paketů (týkalo se i staré hlášky o nekompatibilní verzi) → odpojení až po 0,5 s, `pending` se maže hned (další hello neprojde).
- Hostitel se registroval dřív, než existovala domácnost → mohl zůstat divákem; po spawnu domácnosti dostane volnou postavu (`assign_host_sim`).
- Opravný režim validátoru hlásil chyby typů jako fatální (import souboru by selhal) → v opravném režimu jsou to varování; fatální jen „není slovník“ a verze.
- Migrace v0 padala na `bool("ano")`; věrnost starého vzhledu byla 0,2 → hodnoty nalezené prohledáním modelu (odchylka 0,043).
- `AppearanceResolver` po JSON ignoroval celé číslo uložené jako float → numerické typy se sjednotí.
- Klientská loutka přebírala rysy ze sítě bez kontroly → jen známá id, max. 5.
- Nástroj zápisu souborů převádí `\uXXXX` na skutečné znaky → bidi znaky v testech se escapují dodatečně (poučení pro další běhy).

### Review ChatGPT
- **Zpráva 39 (depression.gd)** – vše oprávněné a opraveno: A) 2 dny = záměrná herní komprese (komentář), práh epizody podle stavu na začátku kroku (test 1/2/5 min); B) habituace bez stropu (vyprchávající počet) + společný rozpočet úlevy 1/(1+(R/0,02)³), uložení habituace; C) kontakt s kvalitou < 0,2 nic neruší, klesající přínos, ukládá se; D) from_dict – NaN/Inf, záporné n, strop velikosti.
- **Zpráva 38 (tvorba postavy)** – zásady převzaté do ROADMAP (0) a kódu: uid ≠ jméno, nezávislé osy, bez etnických předvoleb, veřejné jen vykreslení + oslovení, predispozice nezávislé na identitě a vypínatelné, pomůcky jako samostatné volby, BASIC/ADVANCED v editoru (C6), akceptační testy.
- **Zpráva 37** – založení nové místnosti pro diagnostiku relay **odmítnuto**: mimo rozsah projektu lifesim (zadání uživatelky).

### Audit Gemini (`gemini-3.5-flash-lite`)
1. *HIGH: klient posílá pos/seed/node_name* – **neoprávněné**: klient posílá jen kód postavy; pozici, seed i jméno uzlu určuje server (`_spawn_player_character`).
2. *HIGH: race při odpojení obchází limit 8 postav* – **neoprávněné**: hello se přijme jen jednou na peer (pending), hráč se maže ze seznamu hned při odpojení, `queue_free` nic neobchází; navíc MAX_CLIENTS 8.
3. *HIGH: rod generovaný z identity (muž → on 97 %)* – **zamítnuto (designové rozhodnutí)**: týká se jen náhodného generátoru a odpovídá realitě (rod volí člověk podle své identity); hráč může zvolit libovolnou kombinaci, generátor vyrábí všechny 4 rody (test) a tělo, vlasy, hlas i oblečení jsou na identitě nezávislé (testy).
4. *MED: hluboké vnoření JSON → stack overflow* – **ověřeno testem**: 16 000 úrovní v limitu 32 kB je odmítnuto bez pádu; validátor nerekurzí (pevné schéma), vnořená data v polích odmítá.
5. *MED: predispozice jako trest* – **zamítnuto**: predispozice podle zadání realisticky ovlivňují prožívání (symptomy), ale nejsou vázané na identitu ani nedávají statistické bonusy/postihy mimo duševní stav; popisy jsou neutrální (test).
6. *MED: plovoucí čárka vs. determinismus* – **neoprávněné**: kvantizace na 1/1000 + testy shody po var_to_bytes i JSON.
7. *LOW: mezery uvnitř kódu* – **oprávněné (UX)** → bílé znaky kdekoli v kódu se ignorují + test.
8. *LOW: chybí kontrola věku 18+* – **neoprávněné**: `body.age` má min. 18 (fuzz i MP test nezletilé postavy).

### Otevřené body
- Tvar těla zatím jen měřítka + výběr ze 2 sítí podle atributu `bust` (C2: spojité shape keys); obličejové morfy, kůže (pihy, jizvy, tetování…), účesy, oblečení podle kategorií a make-up se ukládají, ale ještě nevykreslují (C3–C5).
- Kontrola záměnných znaků (mixed-script / homoglyfy) ve jménech – zatím ne; jména jsou jen zobrazovaná, nikdy klíčem.
- Neutrální české tvary (ono/oni, „blízká osoba“) – čeká se na názor ChatGPT.
- Z dřívějška: studená válka v domácnosti, výkon, terapie/léky, export GLB, test MP s latencí, nastavení obsahu serveru u klientů.

---

## 2026-10-14 (běh 6) – Den 6: deprese (wanting/liking/vigour), křivdy, omluva a usmíření

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 42/42 skriptů OK |
| `tests/test_depression.tscn` (nový: 4 oddělené složky; **scénáře ChatGPT 1–6** – nízké očekávání + zachované prožití, vysoké očekávání + malé prožití, zachovaná motivace + nízké prožití, zachované potěšení + velká bariéra, série zklamání není nevratná, spam jedné aktivity „nevyléčí“; nelineární zotavení, epizoda až po trvání + stopa, která mizí; ranní vzorec jen jako individuální volba; strop zátěže při ztlumení/vypnutí; endogenní propady jen u predispozice; myšlenky bez sebevražedných obsahů (kontrola zakázaných slov přes všechny myšlenky); serializace a poškozená data; PsycheFX šeď; ve světě: váhání hráčova příkazu (nikdy neodmítne, zrušitelné, pak provede), AI nikdy neváhá, bariéra/pesimismus mění chuť, anhedonie tlumí moodlet a učí očekávání; regrese spánku) | **75/75 OK** |
| `tests/test_reconciliation.tscn` (nový: křivdy a vina, vyprchávání podle povahy nezávislé na kroku, upřímnost z chování – opakované a porušené omluvy, „teď ne“, stres, velikost křivdy, přijetí/částečně/odmítnutí/spam/„za co?“, spam ani omluva bez křivdy nikoho nepřeruší, AI se omlouvá z viny tomu správnému, pýcha, cooldown 12 h, čas hojí jen bez živé křivdy, validace serveru) | **58/58 OK** |
| `tests/test_mental_health.tscn` | 95/95 OK (1 kontrola upravena: Jana má nově predispozici k depresi) |
| `tests/test_multiplayer.tscn` | 67/67 OK |
| `tests/test_player_commands.tscn` | 40/40 OK |
| `tests/test_psyche_presentation.tscn` | 19/19 OK |
| `tests/test_net_protocol.tscn` | 34/34 OK |
| `tests/test_assets.tscn` | 145/145 OK |
| `--test 7`, `--test 14` | OK (0 min v kritickém stavu, AI nevyužívá váhání, zátěž není v saturaci); ~24–29 ms/herní hodinu |

### Nálezy z vlastních testů a self-review (opraveno)
- **AI spamovala omluvy** (26× za týden, většinou „do prázdna“) – odmítnutá omluva nesnižovala vinu → AI cooldown 12 h na stejnou postavu, odmítnutí sníží vinu na 80 %.
- **Epizoda deprese se zapínala a vypínala každou minutu** (počítadlo trvání se po konci nevynulovalo, stopa vystřelila na max.) → start epizody vyžaduje i aktuální zátěž nad prahem, konec nuluje počítadlo; test „po epizodě slabá stopa“ to chytil.
- **Spirála nespavosti z osamělosti (latentní bug z Dne 1, odhalený depresí)**: kritická potřeba *společnost* budila ze spánku každých 10 min → nevyspání → stres 100 → zátěž 1,0, hlad 0, 5 388 min v kritickém stavu (`--test 7` selhal). Spánek teď budí jen hlad; přidán regresní test. Psaní zpráv kamarádovi má nižší námahu (0,2) než osobní hovor.
- Deprese se u nepredisponované postavy rozjela za týden (příliš rychlý růst) → pomalejší zisk ze stresu/izolace, menší dopady událostí, epizoda až po 2 herních dnech nad prahem.
- Habituace aktivace byla slabá (10× stejná aktivita = 2,7× účinek) → 1/(1+2n), log 12 záznamů.
- Spam omluv snižoval vinu („odklikání výčitek“) → vinu snižuje jen skutečná (i odmítnutá) omluva, ne spam.
- `broken` (porušené omluvy) původně vyprchávalo náhodně přes globální `randf()` (nedeterministické, závislé na kroku) → exponenciální vyprchání.
- Typová chyba (`var vented :=` z netypované `mood.emotion`) – zachycena `godot_check`.

### Audit Gemini (`gemini-3.5-flash-lite`)
1. *HIGH: griefing omluvami (přerušování cizích postav)* – **částečně oprávněné**: server už validoval cíl, spam do 2 h druhého nepřerušoval a postavu plnící příkaz svého hráče nepřeruší nic. Ale omluva „za nic“ (bez křivdy) druhého na 8 min přerušila → **opraveno**: nepřeruší, jen odpoví „Za co? V pohodě.“ + test.
2. *HIGH: pasivní hojení vztahů obchází omluvy* – **zamítnuto (designové rozhodnutí)**: hojí se jen záporné vztahy *bez živé křivdy* (< 5); dokud křivda trvá, nic se nehojí – omluva je rychlejší cesta, čas pomalejší. Bez toho vztahy jen klesaly (otevřený bod z Dne 4).
3. *HIGH: klient může spamovat `on_activity`* – **neoprávněné**: klient posílá jen příkaz akce; `on_activity` volá server po skutečném dokončení akce s její délkou; navíc habituace na id a konečný katalog akcí.
4. *MED: výkon (alokace, exp() každý tick)* – **částečně**: slovníky jsou malé a omezené (log ≤ 12, expect ≤ počet akcí); `--test 7` ale zpomalil z ~17 na ~24–29 ms/herní hodinu → otevřený bod (profilovat, případně počítat pomalé složky po 5 min).
5. *MED: váhání zamyká hráče* – **neoprávněné**: po vypršení se příkaz provede sám (test „po váhání příkaz provede“), jde zrušit, lehké akce se neváhají.
6–7. *LOW: pseudokód / dělení nulou* – neoprávněné (review dostal zkrácený přepis; dělitelé jsou konstanty).
- Obsah: Gemini hodnotí psychologickou hloubku jako dobrou; žádné námitky k myšlenkám ani tónu.

### Review ChatGPT
- Návrh modelu (zpráva 29: wanting/liking/vigour/prediction error + 6 testovacích scénářů) **zapracován 1:1**; ranní zhoršení jen jako individuální vzorec, autonomie hráče zachována (váhání místo odmítnutí).
- Zpráva 30 (review sim_visual.gd): appearance_seed, teleport flag, export GLB – zapsáno do otevřených bodů na příští vizuální běh.
- `depression.gd` poslán k review (zpráva 33). Do konce běhu bez odpovědi.

### Otevřené body
- Domácnost se dál drží v „studené válce“ (vztahy kolem −45 až −50 po 7–14 dnech): omluvy a hojení fungují, ale hádek je pořád hodně – vyladit pravděpodobnost hádky (chemie, stres, nálada) a přidat pozitivní společné akce.
- Výkon: ~24–29 ms/herní hodinu (Den 5: ~17) – profilovat MentalState+Depression+RelLedger.
- Terapie, léky s vedlejšími účinky, klinika (navazuje na město) – deprese teď nemá „odbornou“ cestu, jen aktivitu, kontakt a čas.
- `hurt_at` / `apologies_from` v RelLedger nemají úklid starých jmen (v MP s mnoha hráči časem roste).
- Ze Dne 5: appearance_seed místo hashe jména, explicitní teleport flag, export GLB; z dřívějška: latence/ztráta paketů v testu MP, limit paketů ENet, nastavení obsahu serveru u klientů.

---

## 2026-10-14 (běh 5) – Den 5: 3D assety z Blenderu (Blender bridge, postava s kostrou, nábytek)

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 38/38 skriptů OK |
| `tests/test_assets.tscn` (nový: CRC-32 a skládání částí, odmítnutí poškozených/podvržených dat – špatný base64, jiná verze, odkaz mimo blob, index vrcholu mimo rozsah; zdroje ↔ manifest ↔ GLB, rozpočet ≤ 8 000 trojúhelníků; rozměry nábytku vs. herní půdorysy, stojí na podlaze, orientace předku +Z, winding Godotu, PBR detail, cache; kostra 17 kostí, skin, součet vah = 1, varianty muž/žena, nos +Z; sémantika póz – krok 0,70 m, protipohyb paží, sed s pánví 0,50 m a chodidly na zemi; SimVisual – varianty, vlastní materiály, deterministický vzhled, walk/idle podle rychlosti, teleport ≠ chůze, Ultra 36 m/s při 10 FPS, sit/lie; fallback na primitiva a WorldBuilder se stejnou herní logikou) | **145/145 OK** |
| `tests/test_multiplayer.tscn` | 67/67 OK (regrese) |
| `tests/test_mental_health.tscn` | 95/95 OK (regrese) |
| `tests/test_player_commands.tscn` | 40/40 OK (regrese) |
| `tests/test_psyche_presentation.tscn` | 19/19 OK (regrese) |
| `tests/test_net_protocol.tscn` | 34/34 OK (regrese) |
| `--test 7` | OK (0 min v kritickém stavu, zvuk 156/154/2) |
| Ruční běh offline (8 s) | bez chyb, „9 interaktivních objektů“ |
| Vizuální kontrola | náhledy z Blenderu (Cycles, 200×170 / 260×150 JPEG) prohlédnuté – postavy muž/žena, gauč s polštářem, postele, lednice; Godot headless nerenderuje, ve hře neověřeno okem |

Očekávaná chyba ve stderr `test_assets`: `base64_to_raw … b64_decode` – záměrný test nesmyslného vstupu.

### Nálezy z vlastních testů a self-review (opraveno)
- **Chyba přenosu dat**: při přepisu části 3/5 gauče vypadlo 8 znaků v opakující se sekvenci → **CRC-32 ji zachytilo**,
  porovnáním CRC po 250 znacích nalezeno místo a opraveno. Ostatních 29 částí prošlo napoprvé.
- Kódování indexů „vysoké hladiny“ selhalo (bajt mimo rozsah), protože prohození pořadí vrcholů v trojúhelníku
  (CCW → CW) rozbilo pořadí prvního použití → vrcholy se přečíslují až po prohození.
- Kontrola pózy přes `Skeleton3D.get_bone_global_pose` vracela zastaralé hodnoty (kostra mimo strom) → test počítá
  dopřednou kinematiku sám (nezávislé ověření).
- `Callable` na statickou funkci v `character_anims.gd` → nahrazeno `pose(clip, p)`; dýchání 30/min → 15/min.
- Svět má 9 (ne 10) interaktivních objektů – test teď porovnává modelovou a primitivní verzi světa.

### Audit Gemini (`gemini-3.5-flash-lite`)
1. *HIGH: DoS při dekódování (obří `jl`)* – **neoprávněné**: `4 + jl > raw.size()` se kontroluje, dekomprese má strop
   16 MB a LSX jsou lokální assety projektu, ne data od klientů.
2. *HIGH: indexy bez kontroly velikosti* – **neoprávněné**: `idx_b.size() == ni * 2` se ověřuje před smyčkou, `vi` mimo
   rozsah vrací prázdný výsledek (pokryto testem).
3. *HIGH: null v cache* – **záměr**: negativní cache, aby se chybějící model nečetl pro každou postavu znovu; volající
   mají fallback na primitiva (pokryto testem), `clear_cache()` existuje.
4. *MED: `String.hash()` nemusí být deterministický* – **oprávněné (částečně)**: algoritmus engine negarantuje mezi
   verzemi → vzhled se odvozuje z vlastního CRC-32 z UTF-8 + test.
5. *MED: únik duplikovaných materiálů* – **neoprávněné**: Resource se uvolňují počítáním referencí s postavou.
6. *MED: Ultra rychlost při nízkém FPS = „teleport“* – **oprávněné** → práh teleportu `max(3 m, 45 m/s · Δt · 1,5)` + test.
7. *LOW: `_update_anim` každý snímek* – ponecháno (≤ 8 postav, porovnání StringName); optimalizace při davech NPC.
- Obsah: odstíny kůže jsou rovnoměrně rozložené podle hashe jména, nevážou se na rysy ani role (žádné stereotypy).

### Review ChatGPT
- Plán kroku poslán (zpráva 26), kód k review poslán jako soubory. Do konce běhu bez odpovědi.

### Otevřené body
- Raw `.glb` v `res://` se v exportované hře nezabalí (načítání GLTFDocument z disku) – před exportem přidat filtr
  `assets/models/*.glb` do exportu, nebo načítat importované scény.
- Vizuál ve hře (osvětlení, SSS kůže, triplanární detaily) neověřen okem – headless.
- Animace jsou procedurální a jednoduché (bez IK, chodidla mohou při sedu na nižší židli klouzat); obličej bez mimiky.
- `--test 7` ~17 ms/herní hodinu (Den 1: ~9 ms) – nárůst hlavně z duševního zdraví (Den 4); profilovat.
- Ze Dne 4: usmíření ve vztazích, nastavení obsahu serveru u klientů, test s latencí, limit paketů ENet.

---

## 2026-10-14 (běh 4) – Den 4: stres, duševní zdraví (úzkost, panická ataka), nastavení obsahu, PsycheFX

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 33/33 skriptů OK |
| `tests/test_mental_health.tscn` (nastavení a cenzura, dynamika 3 složek úzkosti, panická ataka, **matice agency 7 copingů × 4 kontexty – žádná volba není dominantní**, antifarming krátký i dlouhý horizont, vyhýbání a alkohol, expozice a zotavení, myšlenky jako subjektivní, ve světě: ataka nezamyká hráče, svědci pomoc/stigma, svěření, žárlivost, nastavení filtruje události; po review ChatGPT i nedominance v každém kontextu zvlášť, hazard nezávislý na kroku, přerušené svěření, farmení opory) | **95/95 OK** |
| `tests/test_psyche_presentation.tscn` (PsycheFX vinětace, low-pass hudby, tlukot srdce, vypnutí zkreslení, HUD stavu a myšlenek, varování a menu s 116 123) | **19/19 OK** |
| `tests/test_player_commands.tscn` | 40/40 OK (regrese) |
| `tests/test_net_protocol.tscn` | 34/34 OK (regrese) |
| `tests/test_multiplayer.tscn` (+3 nové: vlastní duševní stav v soukromém detailu, cizí stav ani diagnóza se ke klientovi nedostane, klient nemůže vyvolat ataku ani uklidňovat postavu bez ataky) | **67/67 OK** |
| `--test 7` a `--test 14` (offline simulace) | OK – 0 min v kritickém stavu, AI pije max. 1×/týden, ataky jen u predispozice, stres se vybíjí |
| Ruční běh offline (8 s) | bez chyb |

Matice agency (průměr přes kontexty; vyšší = lepší): dýchání [úleva 15.7, citlivost 0, zvládnutelnost +5.4],
procházka [16.8, +2.4, +2.9, cena energie], deník [7.7, +4.2, +6.4], svěřit se [13.2 – ale odbytí ubližuje,
potřebuje druhého], doomscrolling [6.5, −3.6, −2.8], schovat se [25.7, −7.6, −23.0], pivo [22.6, −1.9, −7.7,
nejhorší další den]. Žádná volba není nejlepší ve všech metrikách.

### Nálezy z vlastních testů a self-review (opraveno)
- **Úpravy přes `godot_run_script` bez `extends` odsadily víceřádkové řetězce** (obalení do `_init`) → 4 soubory
  měly rozbité odsazení; opraveno, dál jen skripty s `extends SceneTree`.
- Ataka trvala vždy přesně minimum 5 min (dýchání tak nemělo měřitelný účinek) → realističtější doznívání
  (typicky ~9 min, s dýcháním/oporou ~5–6 min).
- Alkoholový rebound byl po 10 h skoro nulový → pomalejší odbourání reboundu (ranní „hangxiety“).
- Cenzura nechytala „posere“ → doplněné kmeny.
- Vztahy v domácnosti padaly do nepřátelství za 2 dny (vznětlivost počítaná dvakrát, stres v hádkách už od 0)
  → upraveno; lidé se navíc vyhýbají nepřátelům a svěřují se jen tomu, komu věří.
- **Hráč mohl být zamčený**: s plnou frontou příkazů nešlo během ataky zadat dýchání → opraveno a otestováno.
- **Visící počítadlo pomoci**: pomocníka pozvaného k hovoru `join_social` nesnížilo `_helping_me` → opraveno
  + pojistka (bez ataky se počítadlo nuluje).
- Žárlivost se spouštěla při každém hovoru (rychlá eroze vztahů) → max. 1× za 4 h na stejného „soka“.

### Audit Gemini (`gemini-3.5-flash-lite`; `3.5-pro` neexistuje v API, `3.5-flash` přetížený)
1. *HIGH: nekonzistence paniky server/klient* – **neoprávněné** (MentalState i SimAgent běží jen na serveru,
   klient vidí jen popisek). Při kontrole ale nalezen **skutečný problém**: po dodýchání se postava vrátí do ataky
   a svědci by reagovali znovu (dvojí stigma) → **opraveno**: svědci reagují jen jednou za epizodu.
2. *HIGH: únik detailu jiné postavy přes RPC* – **neoprávněné**: žádné RPC „vyžádej detail“ neexistuje, server
   posílá soukromý stav jen vlastníkovi; pokryto testem MP.
3. *HIGH: `fraction` od klienta* – **neoprávněné**: počítá ji server z uplynulé doby akce.
4. *MED: nedefinované `rate`, záporné `dm`* – **neoprávněné** (lokální proměnná; GameClock posílá jen kladné
   kroky ≤ 2 min).
5. *MED: neomezený růst `thoughts`/`coping_log`* – **už ošetřeno** (max 6 myšlenek, 8 záznamů na coping).
6. *MED: visící `_helping_me`* – **oprávněné** → opraveno (viz výše).
7. *LOW: magické konstanty* – částečně; klíčové prahy jsou konstanty, ladění vzorců zůstává v kódu.
8. *Obsah*: stigma i úzkostné interpretace hodnoceny jako realistické a ne karikaturní. Návrh vypnout při
   „vypnuto“ i stres – **zamítnuto záměrně**: běžný životní stres zůstává i bez témat duševního zdraví.

### Review ChatGPT (AI místnost)
- Model úzkosti ze 3 složek, nezamčené volby, nelineární zotavení, vyhýbání s dlouhodobou cenou, nastavitelná
  intenzita myšlenek (zprávy 9, 13) → **zapracováno**; test agency podle návrhu (proveditelnost, nedominance
  přes sadu kontextů, antifarming v krátkém i delším horizontu, myšlenky jako subjektivní, nastavení filtruje
  texty i události).
- Statický review souborů mental_state.gd, game_settings.gd, test_mental_health.gd (zpráva 21) – vše **oprávněné**:
  1. Odbytí při svěření aplikovalo plný postih i při `fraction = 0` → **opraveno** (úměrně proběhlé části;
     samotné odmítnutí už nese moodlet a vztah). Test „nedokončené svěření samo nic nezhorší“ by předtím selhal.
  2. Opora ze svěření obcházela habituaci (farmení) → **opraveno** + test.
  3. Pravděpodobnost ataky i myšlenek závisela na délce kroku (`p = k·dm`) → **hazard `1 − e^(−λ·dm)`** + test
     1 min vs 2 min přes 400 seedů.
  4. Nedominance jen v průměru → **přidána kontrola v každém kontextu zvlášť** (prošla). Další seedy a dlouhé
     sekvence – otevřené.
  5. Znění varování: místo kategorického „vždy vede cesta ven“ → „umožňuje hledat podporu a zotavovat se – ne vždy
     rychle a ne v přímé linii“ → **upraveno**.

### Otevřené body
- Vztahy se v domácnosti postupně zhoršují a chybí mechanika usmíření/omluvy.
- Stres a napětí v HUD klienta se obnovují po změně stavu nebo max. po 10 herních minutách.
- Nastavení obsahu serveru klient nevidí (jen důvod odmítnutí příkazu) – přidat do welcome zprávy.
- Agency matice: přidat více stavů/seedů a dlouhé sekvence voleb (ChatGPT).
- Test MP běží v jednom procesu – chybí test s latencí/ztrátou paketů (připomínka ChatGPT).
- Vizuál PsycheFX ověřen jen numericky (headless nerenderuje obraz).
- Limit velikosti paketů ENet, opt-out z PvP, únik ~10 objektů při ukončení headless běhu (z Dne 3).

---

## 2026-10-14 – Den 3: multiplayer (autoritativní server)

### Testy
| Test | Výsledek |
|---|---|
| `godot_check` | 27/27 skriptů OK |
| `tests/test_net_protocol.tscn` (sanitizace, unikátní jména, validace typů, medián rychlosti, rate limiter) | **34/34 OK** |
| `tests/test_player_commands.tscn` (validace příkazů, fronta, obsazený objekt, probuzení, urážka a následky, ochrana proti griefingu, AI nevybírá akce jen pro hráče, HUD data) | **40/40 OK** |
| `tests/test_multiplayer.tscn` (dedikovaný server + 4 klienti + „tichý“ klient v jednom procesu přes reálné ENet: spawn, sync, čas, hlasování, nouzová pauza, soukromí, chat, anti-cheat, příkazy, PvP urážka, pozdní připojení, divák, hello timeout, odchod hráče) | **64/64 OK** (~16 s) |
| `--test 7` (offline simulace 7 dní, zvuk) | OK – 0 min v kritickém stavu, všichni spí, AI nikdy nevybrala urážku, 173/172 zvuků objektů |
| Ruční běh `--host 24999` a offline (6 s) | bez chyb |

Očekávané chyby ve stderr testu MP: `RPC '_s2c_chat'/'_s2c_clock' is not allowed … Mode is "authority"` – to je
záměrný pokus klienta podvrhnout serverové RPC; Godot ho zahodil (test to ověřuje).

### Nálezy z vlastních testů (opraveno)
- **Server ve výchozím stavu přeposílal pakety mezi klienty** (`SceneMultiplayer.server_relay`) – klient mohl
  poslat RPC přímo jiným klientům. Opraveno: `server_relay = false`, test to hlídá.
- **Nepředstavené spojení (před hello) dostávalo spawny, stav postav, čas i roster.** Opraveno: filtr
  viditelnosti synchronizerů (`add_visibility_filter` → jen registrovaní hráči), roster/chat/čas jen přes
  `rpc_id` registrovaným hráčům. Test ověřuje, že tichému klientovi nic nespawnulo a po 5 s je odpojen.
- `valid_id` odmítal `StringName` (jméno uzlu) – sjednoceno.
- Nový příkaz hráče přebíjel jeho vlastní předchozí příkaz → zaveden `by_player`: hráčovy příkazy se řadí,
  přebíjí se jen rozhodnutí AI.
- Obsazený objekt vytvářel nesmyslnou „vzpomínku“ → nahrazeno krátkým moodletem „Obsazeno!“.
- Test uvázl kvůli chybě skriptu v korutině → `tests/test_base.gd` má watchdog (60 s → selhání místo visu).

### Audit Gemini (`gemini-3.5-flash-lite`; `3.5-pro` nedostupný, `3.5-flash` přetížený)
1. *HIGH: hlas a nouzová pauza nekontrolují registraci hráče* – **neoprávněné**, `_handle_vote` i
   `_handle_emergency` mají `players.has(id)` (pokryto testem neplatného hlasu).
2. *HIGH: podvržení `sim_node`* – **neoprávněné**: vlastnictví se porovnává se serverovým záznamem
   `players[id].sim` a `find_sim` dostane tentýž řetězec; jiná postava se vrátit nemůže (test „cizí postava“).
3. *MED: hash soukromého stavu každých 0,25 s* – **částečně**: při ≤ 8 hráčích zanedbatelné; dirty flag na
   SimAgent je lepší a je v ROADMAP jako optimalizace.
4. *MED: velký řetězec v `clean_text`* – **už ošetřeno** (oříznutí na 4× limit před zpracováním). Otevřené:
   omezení velikosti paketu na úrovni ENet (zatím jen typové a délkové kontroly).
5. *Obsah (repliky urážek)* – **OK**: verbální konflikt, žádné nadávky na skutečné skupiny, žádné násilí.
6. Druhé kolo (logika příkazů a sociálních akcí):
   - *Visící rezervace při `join_social`* – **neoprávněné** (`_leave_target()` se volá před přepsáním cíle),
     ale při kontrole jsem našla **skutečný bug**: přerušená akce oběti nevyslala `action_finished`
     (zvuk objektu doznívá, statistiky nesedí) → **opraveno**.
   - *Griefing opakovanými urážkami* – **oprávněné** → **opraveno**: (a) postavu plnící příkaz svého hráče
     nikdo nepřeruší, (b) opakovaná urážka od stejné postavy do 2 herních hodin → oběť odejde, dostane jen
     moodlet „Obtěžuje mě“ (−6) a vztah klesne o 2. Pokryto testem.
   - *Nevalidní instance / null `mood`* – neoprávněné (statické objekty, kontrola `is_instance_valid`).

### Review ChatGPT (AI místnost)
- Rychlost času: místo minima **dolní medián hlasů + nouzová pauza** (30 s, cooldown 3 min) → zapracováno, testováno.
- Soukromí: **veřejný snapshot vs. privátní RPC jen vlastníkovi** → zapracováno (potřeby, pocity, vztahy,
  vzpomínky jdou jen vlastníkovi; i hostitel vidí v HUD detail jen své postavy). Testováno.
- Ověřit cesty SimAgent/SimPuppet, pozdní připojení – pokryto testy.

### Otevřené body
- Změna vlastnictví postavy za běhu (předání postavy jinému hráči) zatím neexistuje; `has_private` loutky se pak musí resetovat.
- Limit velikosti paketů ENet / ochrana proti zahlcení na úrovni transportu.
- Opt-out z PvP konfliktů (nastavení serveru) – designová otázka.
- `net_detail` se na serveru přepočítává jen při změně nebo po 10 herních minutách – moodlety v HUD mohou být mírně zpožděné.
- Únik ~10–14 objektů při ukončení headless běhu (tweeny/streamy autoloadů) – neškodné, uklidit.
