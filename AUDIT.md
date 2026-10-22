# Life Simulator – audit kvality

Každý běh: self-review změněných souborů, `godot_check`, automatické testy v `res://tests/`,
nezávislý audit (Gemini, příp. ChatGPT v AI místnosti). Otevřené nálezy mají v dalším běhu přednost.

Spuštění testů: `godot_run scene=res://tests/<test>.tscn` a `godot_run -- --test N` (headless simulace).

---

## 2026-10-22 (běh 21, ~18:20–19:05 + ~20:58–21:45 UTC, plánovaný; první pokus spadl) – C3++ detaily obličeje a mimika

**Rozsah:** `scripts/assets/head_builder.gd` (řasy, zuby, dáseň, jazyk, dutina úst, limbus, zornice, mimika `ex_*`, rotace
čelisti), `scripts/character/face_morphs.gd` (detail_values, expression_weights, cache weights), `character_schema.gd` (**v6**:
FACE_DETAILS, makeup.mascara, cache polí face), `character_codec.gd` (v5→v6), `character_randomizer.gd` (_face_details),
`appearance_resolver.gd` (barvy zubů/dásně/jazyka/řas/limbu), `scripts/sim/sim_visual.gd` (mimika, mrkání, řeč, výkon),
`assets/models/character.glb` (přeimport 2×), `tests/test_face_detail.gd` (nový), úpravy test_head/test_psyche/test_character/
test_assets, `tools/face_render_export.gd`, `tools/blender/face_render.py`, docs.
První pokus (od ~18:20) spadl po implementaci a test_face_detail (checkpoint 19:05); tento běh navázal regresí.

**a) Self-review a vizuální kontrola:**
- Regrese po prvním pokusu: 3 zastaralé testy (ne chyby kódu) – test_psyche čekal `VERSION == 5`, test_character počet polí
  face bez FACE_DETAILS, test_assets rozpočet 18 000 tri (postava má 19 260 – řasy ~730, ústa ~1 600) → testy obecně na
  aktuální verzi, rozpočet 20 000 (zdůvodnění v docs/asset-pipeline.md).
- **Výkon posuvníku 5,8 ms (limit 4)** – regrese běhu 21 (~90 blend shapes na každém povrchu hlavy, víc polí). Opraveno:
  `Schema.fields("face")` v cache (jen pro čtení), `FaceMorphs.weights` s cache (klíč = hash vstupů + plné porovnání, vrací
  kopii), `apply_face_shape` přeskočí stejné váhy a zapisuje jen změněné hodnoty, cache názvů blend shapes podle sítě →
  3,68 ms v testu (nejlepší dávka 3,82 ms při zátěži hostitele ~50 na 2 jádrech; měření je hlučné).
- **Render v Blenderu** (Cycles, 8 výrazů × 4 pohledy, docs/images/c3pp-expressions-run21-before.jpg) – prohlédnut:
  (1) úsměv vypadal jako grimasa – koutky se nezvedaly, jen se rozestoupily rty → koutky +5,8 mm nahoru / −3,4 mm dozadu
  v užším poli (σ 11,5 mm), dolní ret uprostřed −1,2 mm (jen pod linií úst); (2) řasy mířily podél normály víčka nahoru,
  zepředu vypadaly jako vějíř pod obočím → vycházejí dopředu a stáčejí se, vliv lash_length 0,32 → 0,24. Po přeimportu
  detail (docs/images/c3pp-mouth-lashes-run21-after.jpg): úsměv čitelný, řasy krátké linky u víčka, mrknutí zavírá oko
  čistě, zuby/mezera/nerovnosti viditelné bez karikatury. Zůstává: otevřená ústa mají hranaté koutky; materiál řas
  v Blenderu je jen náhrada (vypadají světlejší než ve hře).
- `_write_expression`: drift pod prahem se sčítá (porovnává se s posledním zapsaným vstupem), po invalidaci slotů se
  počítá znovu; `apply_face_shape` se po výměně sítě vlasů invaliduje spolu se sloty mimiky.

**b) Testy (běží na pozadí přes setsid, logy v previews/testlogs – nástroj má strop 120 s, test_head trvá ~4 min):**
test_face_detail **55/55** (nový) · test_head 43 · test_character 157 (posuvník 3,68 ms) · test_character_v2 43 ·
test_character_net 28 · test_multiplayer 67 (1× flake „klientské hodiny převzaly pauzu“ při zátěži, samostatně 67/67) ·
test_hair 60 · test_skin 61 · test_body_morphs 62 · test_neck_length 36 · test_neck_seam 56 · test_assets 155 ·
test_psyche 93 · mental_health 95 · depression 92 · reconciliation 58 · household_dynamics 78 · player_commands 40 ·
psyche_presentation 19 · net_protocol 34 · audio_tone 222 · `--test 7` OK (hádky 40 %, stres > 85 0 min) · hra 25 s bez
chyb · `godot_check` 60/60.

**c) Gemini (flash-lite), 8 bodů, 1 zapracován:** (1) slovník vah mimiky se staví každý snímek → **opraveno** (klidová tvář
nic nepočítá ani nealokuje). (2) „chybí serverová validace polí v6“ → odmítnuto: validátor validuje všechna pole ze
`Schema.fields("face")` (FACE_DETAILS jsou jeho součástí), fuzz v test_character a test_face_detail; ořez v FaceMorphs je
druhá pojistka. (3) `get_instance_id()` v seedu mrkání nedeterministický → odmítnuto záměrně: mrkání je klientská prezentace,
nereplikuje se a peery se na něm shodnout nemusí (rozfázování mezi postavami). (4) duplicitní k (1). (5) operátor `^`
→ odmítnuto: v reálném kódu je `pow()`, `^` byl jen zkrácený zápis v zadání. (6) věk a odstín zubů/hustota řas jako
stereotyp → odmítnuto: věk posouvá jen průměr normálního rozdělení (σ 0,12–0,15), nic není garantované, žádná vazba na rod
či původ. (7) dělení nulou v tečně řas → odmítnuto: ošetřeno prahem 1e-9 s náhradní osou. (8) formátování klíče oka →
odmítnuto: offline stavba sítě, ne za běhu.

**d) ChatGPT/Grok:** Grok #148 (review běhu 20) – metrika rezidua a explain() oříznuté komorbidity → do 2. osy psychiky;
sloty oblečení jako povrchy nad morfy → C5. ChatGPT #150 (Elmer FEM) – bez akce.

**e) Otevřené:** hranaté koutky otevřených úst; GitHub push z plánovaných běhů blokovaný (nástroj add_repo v běhu není).

---

## 2026-10-22 (běh 20, ~15:40–17:00 UTC, plánovaný) – 1. osa psychiky (PsycheModel)

**Rozsah:** nový `scripts/psyche/psyche_model.gd`, `data/conditions/anxiety.json` + `depression.json`, `scripts/sim/mental_state.gd`
(CONDITIONS ze dat, háčky, vazby, `cfg_mode`), `sim_agent.gd` (`apply_character_private` → `set_psyche`), `utility_planner.gd`
(cfg do `coping_appeal`), schéma **v5** (`character_schema.gd` HEXACO + 2 pole, `character_validator.gd` typ `axes`,
`character_codec.gd` migrace v4→v5, `character_randomizer.gd` seed na konci), `tests/test_psyche.gd` (nový),
`tests/test_neck_length.gd` (verze obecně), docs. Předchozí pokus o běh 20 (~11:50) poslal jen plán #140 a nic nezapsal.

**a) Self-review:**
- Dvojí započtení: první návrh by D z rysů a diagnóz pustil do háčků navíc k dnešním mechanikám (Úzkostlivý už má
  `trait_vuln`, Impulzivní flag `impulsive`) → zavedeno **reziduum D − D_legacy** (nesené příspěvky bez individuality).
  Test: bez individuality a explicitní osobnosti je reziduum přesně 0 u 60 náhodných postav; MentalState s takovými háčky
  je bit po bitu shodný se stavem bez háčků (600 min se stresory).
- Bug nalezený testem: `pers["traits"]` při chybějícím klíči (výchozí `[]` z `get` prošlo typovou kontrolou) → čte se jednou
  do lokální proměnné. Odstraněna nepoužitá proměnná `cond_add`.
- Randomizer: nový los `psyche_seed` by posunul sekvenci RNG pro příběh a predispozice → los až na konci `generate`
  (stejný seed generátoru = stejná postava jako ve v4, kromě nového pole).
- Režim obsahu: MentalState dostává háčky pro full/muted/off a vybírá podle aktuálního cfg (přepnutí za běhu funguje);
  `cfg_mode` pozná režim i ze starého cfg bez klíče `mode`.
- Rozmanitost: v klidném prostředí byla individualita skoro neviditelná (dvě postavy shodné) → test měří v napjatém prostředí
  a požaduje, aby se každá dvojice lišila volbou copingů nebo aktivací. Efekt individuality je záměrně mírný (háčky 0,7–1,3,
  rezidua do ~0,1); výrazné rozdíly dává zadaná osobnost (emocionalita ±0,9 → threat_gain 0,70 / 1,30).
- `godot_check` hlásí 60/60 skriptů – nové soubory bez `.uid` možná nepočítá; jejich kompilaci ověřilo spuštění testů a hry.

**b) Testy:** test_psyche **93/93** (nové) · regrese 20 sad beze změny: mental_health 95, depression 92, reconciliation 58,
household_dynamics 78 (hádky 31,4 % ± 7,9 – stejné jako dřív), player_commands 40, psyche_presentation 19, net_protocol 34,
multiplayer 67, character 157 (posuvník 3,25 ms), character_v2 43, character_net 28, neck_length 36, body_morphs 62,
head 43, neck_seam 56, skin 61, hair 60, assets 150, audio_tone 222 · `--test 7` OK · hra bez argumentů 25 s bez chyb.

**c) Gemini (flash-lite; flash a flash-lite napoprvé „high demand“), 6 bodů, 0 oprav – vše zdůvodněně odmítnuto:**
(1) CRC-32 jako zdroj individuality „nedeterministický“ → odmítnuto: vstup je ASCII řetězec z int a pevného klíče, CRC je
bitově stejné na všech platformách, počítá jen server a nic se nereplikuje; test round-trip přes sdílecí kód. (2) „rysy
v reziduu dvakrát“ → odmítnuto: D počítá P→D z p_eff s individualitou, D_legacy z p_tr bez ní – reziduum je přesně rozdíl,
test 0 bez individuality. (3) součin mul bez ořezu členů → odmítnuto: každý člen je lerp(1, amount, sev) s amount ověřeným
v 0,5–2 a sev v 0–1, tedy kladný a v mezích; součin se ořízne; prahy se ořezávají kumulativně. (4) I/O při spawnu a injekce
profilu z klienta → odmítnuto: profily se načtou jednou (statická cache), klient posílá jen ID predispozic z katalogu schématu,
validátor ostatní odmítne. (5) vazby ovládají postavu → odmítnuto: vazba mění jen stav (stres/aktivace/hrozba/zátěž) jako
existující dynamika, nikdy akce; validátor profilů povoluje jen cíle D/T/S, test agency. (6) Kahn každou hodinu → odmítnuto:
pořadí se počítá v `compute()` při vstupu postavy, za hodinu se jen prochází seřazené pole.

**d) Otevřené:** hodnoty/světonázor (V) odloženy; individualita zatím jen ve 4 háčcích; HUD/editor `explain()` zatím nezobrazuje
(C7). Další krok: C5 oblečení, pak integrovaný průchod (Grok #141).

---

## 2026-10-22 (běh 19, ~10:55–11:40 UTC, ruční spuštění) – C4b+ detaily vlasů a vousů

**Rozsah:** `scripts/assets/hair_builder.gd` (skořepina s dělením okraje, copánky/dredy, plnovous), `tests/test_hair.gd`
(přesné ověření průniku, nová sekce běhu 19), `tools/hair_export.gd` (`_build()` mimo běžící strom), docs.
Payload ručního spuštění popisoval stav před během 18 (C3+ B) – ten už byl hotový, takže běh navázal checkpointem
(C4b+) a zapracoval připomínky z payloadu (vousy níž na krk, copánky/dredy pravidelné a přes obličej).

**a) Self-review:**
- Dělení skořepiny: první verze dělila každý trojúhelník s okrajem v (0;1) a u uší → +6–11 tis. trojúhelníků (afro přes
  rozpočet) → dělí se jen trojúhelníky, přes které vede samotná linie (0,42–0,62), ne u ucha, 2× jen u spánků, afro vrstvy 0×.
- Penetrace: test měřil vůči radiální mapě (max. poloměr v binu) a body na plochých trojúhelnících vycházely „pod hlavou“;
  zkoušené Phongovo zvednutí středů by dělalo trhliny u nedělených sousedů → středy zůstávají v rovině trojúhelníku (= kůže,
  jak ji hra kreslí) a test podezřelé body ověřuje přesnou projekcí na trojúhelníky kůže.
- Vousy: zóny přepočítané na nové rty (C3+ B) – brada začíná pod červení dolního rtu, hustší vzorkování pod rtem.
- Copánky/dredy: kopie stylu na pramen (`st.duplicate()` jen přepisuje skalární klíče), RNG pevné na účes → determinismus
  vlákno × synchronně ověřen testem.
- `tools/hair_export.gd`: SimVisual se mimo běžící strom nepostavil (`_ready` se nevolal) → explicitní `_build()` (idempotentní).

**b) Testy:** `godot_check` 60/60 · test_hair 60/60 (nové: hrana přes linii u spánků 18,0 → 8,6 mm; trubice ≥ 8,5/8,7 cm
od středu obličeje; plnovous nejníž 1,517 m, pod 1,53 m 1,5 %; pod rtem 45 vrcholů; rozpočty: max 25 408 kudrnaté, afro
21 497) · test_assets 150/150 · test_neck_seam 56/56 · test_character 157/157 (posuvník 3,93 ms – kolísá 3,1–3,9 ms, limit 4) ·
`--test 7` OK. Ostatní sady (mentální zdraví, deprese, vztahy, MP, audio…) běžely v běhu 18 před hodinou a jejich kód se
v běhu 19 nezměnil.
**Vizuálně:** Blender render (`docs/images/c4bp-hair-run19.jpg`: copánky, dredy+knír, undercut+plnovous, ústup+šediny+bradka,
krátké; 4 pohledy) prohlédnutý: obličej volný, prameny nepravidelné a rámují obličej, plnovous končí pod čelistí, spánky
bez schodů. Zbývá: textura copánků v Blenderu je jen náhrada shaderu (pruhy), dredy přes čelo od pěšinky (záměr – boční
pěšinka), vzadu copánky dál dost hustě a rovnoměrně.

**c) Gemini (flash-lite), 6 bodů:** (2) nulový součet normál při dělení → **zapracováno** (pojistka). (1) T-spoje u nedělených
sousedů → odmítnuto jako kritické: středy leží v rovině trojúhelníku, odchylka je jen rozdíl odsazení po normále (≪ 0,1 mm)
u 1mm skořepiny s průhledností; vedeno jako drobné. (3) mělká kopie a pořadí RNG → odmítnuto (přepisují se jen skalární
klíče; síť se staví ze stejného GLB stejným kódem, test vlákno × synchronně). (4) lambdy ve vlákně → odmítnuto (čtou jen
konstanty). (5) kolize vrstev v cache → odmítnuto (každé volání `shell()` má vlastní cache). (6) skok x v `avoid_face` →
ponecháno (dřívější chování, na renderu bez zlomu).

**d) Další krok:** 1. osa psychiky (společný rámec dimenzí), potom C5 oblečení.

---

## 2026-10-22 (běh 18, ~10:00–11:00 UTC) – C3+ B doladění obličeje (brada, oči, rty, velikost hlavy)

**Rozsah:** `scripts/assets/head_builder.gd` (projekce brady, `surface_xy`, oční štěrbina a koutky mimo kouli, rty a ústa),
`scripts/character/face_morphs.gd` (korekční dvojice eye_distance × eye_depth), `scripts/character/character_randomizer.gd`
(head_size × frame), `scripts/character/skin_layers.gd` + `shaders/skin.gdshader` (orientační body make-upu, bod brady),
`tests/test_skin.gd`, `tests/test_character_v2.gd`, `assets/models/character.glb` (+ manifest), nové nástroje
`tools/face_render_export.gd` a `tools/blender/face_render.py`, docs.

**a) Self-review:**
- Render „před“ (12 postav × 4 pohledy, `docs/images/c3b-face-run18-before.jpg`) + měření povrchu: měkký pogonion ~20 mm za
  dolním rtem (bezzubý profil), štěrbina víček 23,6 mm obtočená kolem koule (v čelním pohledu ~21 mm), vnitřní koutek 20 mm
  od středu, rty ~5 / 8,5 mm. Výška hlavy změřena 22,5 cm – v rozsahu dospělých (ž ~21,9, m ~23,2) → beze změny (původní
  tvrzení „o 1 cm nižší“ se neověřilo; dojem malé hlavy u mohutné postavy řeší generátor).
- Projekce brady nejdřív z aktuální polohy vrcholu → chyba lineárních blend shapes u extrémů 3,9 → 5,02 mm (limit 5). Diagnóza
  ukázala, že nejhorší vrchol je ve vnějším prstenci víček (ne brada) → projekce přepsána na váhu z VÝCHOZÍ hlavy na paprsku
  (`JAW_D0`, konstantní posun na vrchol), a interakce eye_distance+1 × eye_depth−1 (2,9 mm, změřeno na všech dvojicích morfů očí,
  obočí a lící) dostala korekční tvar → 4,07 mm.
- `surface_xy` – povrch už není čistě paprskový, pevný bod by zmenšoval x, y o ~dz/z → iterace opravuje cílové x, y.
- `_sph`: oblouk za `EYE_WRAP` začíná tečnou koule (C1 spojitost), směr se stáčí exponenciálně; `k == 1.0` je porovnání
  s literálem předaným volajícím (víčka 1.0, spojivka 1.55), ne výsledek aritmetiky.
- Thread-safety: `JAW_D0` je konstantní (v Godotu 4 read-only) slovník, `jaw_projection*` jsou čisté funkce.
- Výkon: `build_data` 42 → 55 s (jen import offline); aplikace obličeje 0,30 ms; posuvník 3,12 ms samostatně.
- Konstanty make-upu `EYE_SHAPE` (půlšířka 15,1 mm = průměr nesouměrné štěrbiny) a `MOUTH` sjednocené s hlavou + nový test.

**b) Testy:** `godot_check` 60/60 · test_head 43/43 (extrémy max 4,07 / průměr 0,20 mm, 48 kombinací bez průniku kůže–oko,
rty se nekříží, 0 přeložených ploch, 78 blend shapes v GLB) · test_skin 61/61 (+ make-up = hlava; bod brady 1,4 mm od povrchu)
· test_character_v2 43/43 (+ head_size: sd 0,30, r(frame) 0,24, rod max. rozdíl 0,018) · test_neck_seam 56/56 · test_neck_length
36/36 · test_hair 55/55 · test_assets 150/150 · test_body_morphs 62/62 · test_character 157/157 (posuvník 3,12 ms; při třech
souběžných testech 4,22 ms – měřit samostatně) · test_character_net 28/28 · test_multiplayer 67/67 · test_mental_health 95/95
· test_depression 92/92 · test_reconciliation 58/58 · test_household_dynamics 78/78 · test_player_commands 40/40 ·
test_net_protocol 34/34 · test_psyche_presentation 19/19 · test_audio_tone 222/222 · `--test 7` OK.
**Vizuálně:** render „po“ (`docs/images/c3b-face-run18-after.jpg`, 6 postav × 3 pohledy) prohlédnutý: profil s bradou, oči
s koutky a slzným jezírkem, plné rty; extrém −1 všech posuvníků má dál úzké oči a tenké rty (součet minim), hřbet nosu ostrý.

**c) Gemini (flash-lite), 5 bodů:** (1) „vysoká“ thread-safety `JAW_D0` → odmítnuto: konstantní slovník je v Godotu 4 jen
pro čtení a funkce nic nemutují; `derive()` vrací vždy nový slovník. (2) NaN v `pow(1 − a², …)` → odmítnuto: `a` je ořezané
do ⟨−1; 1⟩, takže 1 − a² ≥ 0 a pow(0; 0,85) = 0; `_dir_to` v `surface_xy` nikdy nedostane nulový vektor (z ≥ ~0,08).
(3) `k == 1.0` → odmítnuto (literál, geometrie se navíc počítá jen offline při importu; klienti načítají GLB). (4) head_size
nezávislé na rodu – potvrzeno jako v pořádku. (5) výkon `surface_xy` 6 iterací → ponecháno (jen import, +13 s).
**ChatGPT:** plán a otázka (anatomické cíle jako testy) poslány v #134; review souborů v místnosti po syncu.

**d) Známé problémy / další krok:** C4b+ – schodovitý okraj skořepiny vlasů u spánků, sloupcový vzor plnovousu, mezera
pod dolním rtem u plnovousu (tento běh nezačato); měkká zóna extrémů posuvníků až v editoru C6; zuby, jazyk, mimika.

---

## 2026-10-22 (běh 17, ~02:50–04:00 UTC) – hudba v3 + C4b vlasy, vousy, obočí (dokončení)

**Rozsah:** `scripts/audio/music_data.gd` (návrat k původní hudbě + nové „Mlhavé ráno“), `tests/test_audio_tone.gd`
(nová pravidla, jas, šev smyčky), `docs/audio.md`, `audio/music/*.wav`; C4b z běhů 14/16 (`hair_builder.gd`, `hair_rig.gd`,
`hair.gdshader`, `sim_visual.gd`, `appearance_resolver.gd`, `tests/test_hair.gd`) + opravy tohoto běhu; `tools/hair_export.gd`
(nový – export pro Blender), `main.gd` (async stavba vlasů ve hře, audio report 25 souborů).

**a) Self-review:**
- Hudba: renderer a data původních skladeb ověřené MD5 proti GitHubu 0518c53 (renderer `0b4c6430…`, data `585f4cbd…`);
  nástroje původních skladeb v synth.gd beze změny (porovnáno řádek po řádku) → zní jako původní demo. Pevná mez švu 0,035
  byla na původní „den“ (hi-hat, skok 0,054 < p99 0,087) moc přísná → mez = max(0,035; p99 rozdílů sousedních vzorků).
- C4b stav z běhu 16 byl hotový a nezapsaný (test_hair 40/40). `sim_visual._build_hair_parts` neresetoval `_hair_mats` a při
  chybě shaderu nechal viset už vytvořené části → opraveno. `resolve_hair_look`: NaN/∞/text v číslech a barva bez „#“ →
  `_f01` a kontrola prefixu (pojistka, snapshot je validovaný) + test.
- **Render v Blenderu** (8 postav × 5 pohledů, 3 kola + detail obličeje; materiál v Blenderu napodobuje hair.gdshader –
  prameny z UV/CUSTOM0, šediny po vlasech, ústup linie). Nálezy a opravy:
  1. copánky a dredy trčely vpředu 15–20 cm před hrudník, dlouhé vlasy odstávaly od zad → náklon gravitace jen nad
     rameny (LEAN_Y0/Y1 1,38–1,50) a jen u bočních pramenů (dopředu od |x| 7,5 cm), pod středem hlavy pramen ztrácí
     hybnost (g ≥ 0,6). Vpředu max 15,5 → 7,3 cm; vzadu medián 2,5–4 cm. Nový test `_test_drape`.
  2. **obočí se stavělo jen u kořene nosu** (bod projekce z = 0,11 m byl mimo dosah prostorového hashe) → 37 ze 140 karet,
     na renderu šedý chomáček mezi očima. Výchozí bod radiálně z mapy hlavy → 140/140, ±5,2 cm. Test pokrytí obočí.
     (Starý test „obočí nad očima“ prošel, protože kontroloval jen meze, ne pokrytí – doplněno.)
  3. undercut a krátké vlasy ježaté → lift/stiff 0,25/0,8 a 0,32/0,9.
  4. ponecháno jako známé: schodovitý okraj skořepiny u spánků (velké trojúhelníky kůže), sloupcový vzor plnovousu,
     afro v Blenderu příliš lesklé (jen náhradní materiál), mezera pod dolním rtem u plnovousu.

**b) Testy:** `godot_check` 60/60 · test_hair **55/55** (nově drape 8, pokrytí obočí, poškozené hodnoty, async 5) ·
test_audio_tone **222/222** · regrese: test_assets 150, test_character 157, test_character_v2 39, test_character_net 28,
test_multiplayer 67, test_skin 60, test_body_morphs 62, test_head 43, test_neck_seam 56, test_neck_length 36,
test_household_dynamics 78, test_mental_health 95, test_depression 92, test_reconciliation 58, test_player_commands 40,
test_net_protocol 34, test_psyche_presentation 19 – vše OK · `--test 7` OK (audio report 25/25 souborů) · hra spuštěná
bez argumentů 25 s bez chyb (async stavba vlasů).

**c) Gemini (gemini-3.5-flash-lite), 6 nálezů:**
- ✅ (2, vysoká) první sestavení účesu 0,25–1 s na hlavním vlákně → zasekne hru při vstupu postavy s novým účesem.
  **Zapracováno:** `HairRig.request_mesh` + `WorkerThreadPool` (ve vlákně jen pole: geometrie, přenos morfů, kosti;
  ArrayMesh na hlavním vlákně přes `call_deferred`), postava mezitím ukazuje helmu z GLB, `_on_hair_mesh_ready` přepne
  na karty; kontext a hash trojúhelníků se staví předem (vlákna jen čtou), mutex na cache. Zapnuto jen ve hře
  (`main.gd`), testy a `--test` synchronně. Test: helma během stavby, výměna, síť z vlákna = synchronní, zrušený vlastník.
- ❌ (1) „sdílené rng rozbije determinismus“ – rng je lokální v `HairBuilder.build`, seed jen ze stylu, stejný kód na všech
  peerech; test bit-po-bitu (i po vymazání cache) a nově i vlákno × synchronně.
- ❌ (3) „Color.html může spadnout“ – vstup je předem ověřený (7 znaků, „#“, hex); GDScript chybu nevyhazuje jako výjimku.
- ❌ (4) „dělení nulou / zacyklení ve strand“ – jmenovatel má maxf(…, 1e-6), cyklus má pevný počet kroků a break při nulovém posunu.
- ❌ (5) mez švu: minimum 0,035 je záměr (tiché smyčky), hodnoty p99 se vypisují v testu.
- ❌ (6) „smazání všech částí při chybě materiálu je destruktivní“ – shader je pro všechny části stejný; když chybí, nejde
  žádná karta a správný stav je celá helma z GLB (fallback).

**d) ChatGPT/Grok:** #127 – bouchnutí dveří podle intenzity hádky a povahy: otevřené (audio_manager z paralelního chatu).
Hystereze úrovní vztahu a uid místo jmen v household_dynamics (#127): otevřené, další běh dynamiky.

**Známé problémy:** viz (a)4; výkon: první síť účesu 0,25–1 s (teď ve vlákně), 20–27 blend shapes na účes;
GitHub push z naplánované session pravděpodobně dál nejde (viz DEVLOG).

---

## 2026-10-21 (běh 15, ~21:20–22:50 UTC) – dynamika domácnosti (konec „studené války“)

**Rozsah:** `scripts/sim/household_dynamics.gd` (nový), `scripts/sim/sim_agent.gd` (vyvážení, talk_success_chance,
de-eskalace, stížnosti, měkký strop stresu z hádek, drift, note_relationship_change, signál conversation),
`scripts/sim/traits.gd` (irritability, argue_stress_cap), `scripts/sim/action_library.gd` (repliky), `scripts/sim/fccs_oracle.gd`
(zjednodušen na modulátor rozhovoru), `main.gd` (napojení jen na autoritě + report domácnosti v `--test`),
`tests/test_base.gd` (watchdog), `tests/test_household_dynamics.gd` (nový, 78).
Rozhodnutí uživatelky (CHECKPOINT běhu 14): nejdřív dynamika postav, C4b potom.

**a) Self-review:**
- První zapojení bez kalibrace: 80 % hádek. Diagnostika rozkladu šance (`previews/diag/diag_household.gd`): průměr p 0,22,
  stres −0,21 a emoce −0,11 → spirála „hádka → stres + vztek na 200 min → další hádka“. Oprava: stres ubírá až nad 35 a
  /320 (dřív 30 a /250), emoce vztek 0,12 / únava a napětí 0,06 (dřív všechny 0,15), výchozí 0,65.
- Bug v testovací infrastruktuře: `test_base.gd` vytvářel watchdog v `_enter_tree()` – dřív, než podtřída v `_ready()`
  nastavila `watchdog_seconds`, takže každý test měl 60 s (u test_reconciliation 90 s „platilo“ jen náhodou). Opraveno
  odloženým startem.
- Vzpomínka „Vztah se zhoršil: X je teď blízká přítelkyně“ (experiment v4): text se nevybíral podle úrovně – pokles
  z nejlepší na blízkou přítelkyni zněl jako zhoršení do nepřátelství. Nově jedna funkce pro všechny cesty (hovor,
  hádka, urážka, svěření, pomoc, omluva, společná chvíle) se 4 texty podle směru a úrovně; test kontroluje, že
  „zhoršil“ vždy obsahuje „nepřítel“.
- Statistika: kalibrace je citlivá na pořadí náhody (stejné parametry, jiný počet hodů kvůli pravidlu nádobí →
  průměr z 10 seedů 36,7 % vs 45,7 %). Test proto běží na 16 seedech a kontroluje průměr i rozpětí, ne jeden běh.

**b) Testy:** `godot_check` 60/60 (nové skripty ověřeny i `load().can_instantiate()`); **test_household_dynamics 78/78**:
- 16 seedů × 14 dní: hádky **32,0 %** (sm. odch. 10,4 p. b., 17–54 %), vztahy průměr **+25,6** (−50…+100), rozdíl dvojic
  (sm. odch.) 50, gradient podle nálady 21 / 42 / 72 %, de-eskalací 44, rozhovorů se stížností 112 (hádky 36 %),
  stres > 85 průměr 0,01 % času (nejhorší 0,42 %), 0 kritických potřeb, události 1,13 na postavu a den, determinismus OK.
- Regrese: reconciliation 58, mental_health 95, depression 92, player_commands 40, multiplayer 67 (po finální kalibraci);
  character 157, character_v2 39, character_net 28, body_morphs 62, assets 150, skin 60, head 43, neck_seam 56,
  neck_length 36, psyche_presentation 19, net_protocol 34 (beze změn v jejich kódu); `--test 7` OK (26 % hádek, vztahy
  +12…+47), `--test 14` OK.

**c) Gemini (gemini-3.5-flash-lite; 3.5-flash přetížený):** 6 nálezů.
- ✅ #2 (část) griefing třenicemi přes rychlé příkazy: „vař“ zrušené po minutě nechávalo nádobí → nádobí jen po ≥ 20 min
  skutečného vaření (`DISHES_MIN_COOK`), test 60 pokusů krátké vs dlouhé vaření.
- ✅ #4 farmení vztahu společnými chvílemi přes křivdu → při křivdě > 60 (kterákoli strana) se nic nestane; pod prahem
  tlumí `warmth_mult`. Práh 30 (návrh) zkoušen: zmizela hlavní cesta zpět a hádky vyskočily na 46 % → 60.
- ❌ #1 O(n²) dvojic: třenice jsou směrové (A štve B ≠ B štve A), potřebujeme uspořádané dvojice; domácnost ≤ 8 postav =
  56 kontrol za 10 herních minut. Prostorové filtrování zapsáno do plánu pro velké parcely v MP.
- ❌ #2 (zbytek) klient falšuje stav akce: `acting_id` čte stav serverové postavy (ACTING), klient posílá jen příkazy
  validované NetSession; hluk v noci schválně vedle spícího je legitimní hra (cooldown 6 h na dvojici, +3 stres) –
  opt-out z PvP je v plánu MP.
- ❌ #3 nedeklarované proměnné: artefakt zkráceného pseudokódu v zadání, skutečný kód má `var`.
- ❌ #5 pád na null v `take_complaint`: kontrola `typeof(c) != TYPE_DICTIONARY` a `get()` s výchozí hodnotou; test
  poškozené stížnosti.
- ❌ #6 strop stresu blokuje stres: spodní mez ×0,15 (test „strop je měkký“).

**d) ChatGPT/Grok:** #117 (review běhu 13) – runtime testy krku (GLB v Godotu pro neck −1/0/+1, crown_height = max Y,
geometrie na 2 peerech) přesunuty k C4b; plán běhu 15 v #119, kód k review v místnosti po tomto zápisu.

**Otevřené:** O(n²) a opt-out z třenic v MP; víc druhů třenic (peníze, úklid) až s ekonomikou; Jana↔Eliška se často
sbližují až k +100 (povahy, ne chyba – sledovat, jestli to není nová idyla u jiných povah); statistika domácnosti v HUD.

---

## 2026-10-21 (běh 13, ~18:20–19:30 UTC) – C3+ A2 krk: anatomie báze krku + body.neck_length (schéma v4)

**Rozsah:** `scripts/assets/character_assembly.gd` (pole zvednutí báze krku podle směru), `scripts/assets/head_builder.gd`
(blend shape `b_neck_len`, `neck_len_ramp`, `SEAM_Y_TOP` 1,64, robustní `loop_hit`), `scripts/character/body_morphs.gd`
(`NECK_LEN_RANGE`, `head_links`, `neck_offset`, `scales`/`crown_height`), `face_morphs.gd` (podepsaná vazba + výkon),
`appearance_resolver.gd`, `character_schema.gd` (v4), `character_codec.gd` (`_v3_to_v4`), `character_randomizer.gd`,
`skin_layers.gd` (body krku), testy `tests/test_neck_length.gd` (nový, 36), `tests/test_neck_seam.gd` (32 → 56),
`tests/test_skin.gd`; `character.glb` přeimportováno.

**Měření (vstup):** GLB 1,78 m – jugulum 1,466 (0,82 H ✓), C7 ~1,51–1,52 (cíl 0,868 H = 1,546), bod krk–rameno
(|x| 0,10) 1,47 (cíl ~1,50), trapéz (0,14) 1,46. Krk nebyl „dlouhý“ vpředu, ale báze krku vzadu a po stranách ležela
2,5–4 cm nízko. **Po změně:** C7 1,545, bod krk–rameno 1,503, trapéz 1,475, brada 1,557, výška hlavy 22,3 cm,
přední krk 9,1 cm = 0,41 výšky hlavy (reference ~0,36–0,41).

**a) Self-review** (každý změněný soubor znovu přečten):
- `lift_dir(c)`: L(1)=4 mm, L(0)=30 mm, L(−1)=46 mm; derivace a1 + 4·a2·c < 0 na celém ⟨−1; 1⟩ → monotónní, bez
  překmitu. Řez krku dál podle výšky PŘED zvednutím (topologie smyčky beze změny, 16 vrcholů).
- `neck_len_ramp` se počítá z polohy po `_apply_seam` (přilnutí je jen radiální, y se nemění) → lineární v dl,
  v pásu plného přilnutí rampa 0 (okraj krku se nehne). Pojistka `bot ≤ top − 1 cm`. Komprese při −1: nejmenší
  poměr výšek 1 − 0,015·ṙ > 0 (test monotónnosti v 12 směrech).
- `SEAM_Y_TOP` 1,60 by po zvednutí useknul pás švu vzadu (smyčka 1,544 + 6,5 cm) → 1,64.
- `BodyMorphs.weights()` NEnese klíč krku (síť těla ho nemá; test vah těla by jinak selhal) → `head_links()`.
- Výkon: `FaceMorphs.value()` skládal `Schema.fields("face")` pro každé pole (0,9 ms/postavu) → slovník jednou;
  odezva posuvníku 4,2 → 3,7 ms (limit 4 ms; dřív hlášené kolísání 3,6–6,3 ms mělo tuto příčinu).
- Testy: v `test_neck_seam` opravené vlastní chyby (formát `%.1e` Godot nepodporuje; počáteční hodnota v testu rampy;
  brada se měří svislým paprskem, protože střední řada sítě mezi hrdlem 1,552 a spodkem brady 1,566 nemá vrchol);
  test řezu hledá zbytky krku nad 1,555 (smyčka vzadu je nově 1,545); počet vrcholů u smyčky pro srovnání normál
  ≥ 6 (dřív 8; jiná výška řad mřížky, nejhorší odchylka 2,0°).
- `skin_layers.gd`: body krku pro jizvy/tetování přeměřené paprskem na novém krku (hrdlo 1,535, boky 1,54,
  zátylek nad C7 1,565).

**b) Testy:** `godot_check` 60/60. test_neck_length 36/36 (nový), test_neck_seam 56/56, test_head 43/43, test_skin
60/60, test_assets 150/150, test_body_morphs 62/62, test_character 157/157 (posuvník 3,68 ms), test_character_v2 39/39,
test_character_net 28/28, test_multiplayer 67/67, test_depression 92/92, test_mental_health 95/95, test_reconciliation
58/58, test_player_commands 40/40, test_psyche_presentation 19/19, test_net_protocol 34/34, `--test 7` OK.

**Vizuální kontrola (Blender Cycles, 6 postav × 5 pohledů, prohlédnuto):** výchozí, krk −1, krk +1, svaly+tuk,
tuk + krk −1, štíhlá + krk +1 (tmavá kůže). Hlava už „nevisí“ nad rameny, zadní strana krku a trapéz stoupají k C7,
±1 vypadá jako běžná variabilita dospělých (ne „žirafa“ ani „bez krku“). Profil: temeno při ±1 přesně ±10 px
(= ±15 mm). **Nález v postupu renderu:** Blender ořezává hodnoty shape keys na 0..1 (`slider_min` = 0) → záporné
váhy se dřív renderovaly jako 0 (řádky „min“ v renderech běhů 10b–12 nebyly přesné). Opraveno v render knihovně
(`slider_min = -1`) a v docs/asset-pipeline.md.

**c) Nezávislý audit – Gemini (flash-lite; 3.5-flash přetížený):** 4 nálezy, všechny zdůvodněně odmítnuté:
1. „chybí clamp neck_length“ – `_val()` ořezává do rozsahu schématu, NaN/typ → výchozí; server navíc validuje
   striktně (test fuzz 400 hodnot + 11 nevalidních typů).
2. „dělení nulou ve scales()“ – b ≥ 1,48 (nohy 0,92–1,08), h ≥ 1,45 (ořez), `maxf` pojistky už existují.
3. „rel.length() ≈ 0 v rampě“ – ošetřeno (c = 1); body na ose krku jsou jen víčko uvnitř trupu (rampa 0) nebo
   temeno (rampa 1), výsledek na volbě c nezávisí.
4. „migrace spadne bez body“ – `typeof(body) == TYPE_DICTIONARY` už je; chybějící body doplní validátor.
**ChatGPT #111:** loop_hit → nejbližší průsečík + test nehvězdicové a degenerované smyčky; invarianty Catmull-Rom
(192 směrů: součet vah 1, konečné body, odchylka od polygonu ≤ 1,08 mm, pořadí zachované) – zapracováno.
**Grok #113:** test ±30° ohnutí × neck ±1 × tuk/svaly – zapracováno; „posunout kost hlavy a přepočítat váhy“ –
zdůvodněně jinak: posun je blend shape hlavy (krk pod bradou má smíšené váhy head/neck, posun kosti by táhl
podbradek), okraj švu má váhy těla a nehne se, šev drží i při ohnutí (test); temeno a vlasy se posouvají s hlavou
(test „vlasy převzaly b_neck_len“, temeno +15,00 mm); sešikmené rozdělení randomizéru ne – N(0; 0,3) s ořezem
±0,8 dává extrémy |v| > 0,7 u 1,5 % postav. Review diffu poslané do místnosti (#115) – odpověď zatím nepřišla.

**Otevřené:** hlava o ~1 cm nižší než reference (22,3 vs ~23 cm) a u svalnaté postavy působí malá (C3+ B);
přední krk 9,1 cm je na horní hraně reference. Vlasy = helma (C4b). GitHub push nejde (repo mimo autorizované zdroje
session) – viz DEVLOG.

---

## 2026-10-21 (běh 12, ~13:55–15:50 UTC) – C3+ krk a šev hlava–tělo (dokončení přerušeného běhu 11)

**Rozsah:** `scripts/assets/head_builder.gd` (šev, vyhlazení u očí/úst, mezitvary), `scripts/character/skin_layers.gd`
(body krku), testy `tests/test_neck_seam.gd` (nový, 32), `tests/test_skin.gd`, `character.glb` přeimportováno.

**a) Self-review** (každý změněný soubor znovu přečten):
- Přerušený běh nechal `test_neck_seam.gd` s parse errorem: `ArrayMesh` nemá `find_blend_shape_by_name` (to je metoda
  `MeshInstance3D`) → vlastní `_bs_index()`. Stejná chyba by v `_test_manifest` spadla až za běhu.
- `test_head` 6 přeložených ploch pod okem: běh 11 změnil vyhlazení okolí očí i úst na tečné s návratem na povrch
  (kvůli tmavému pásu nad rtem). U očí to rozbilo návaznost řady mřížky na vnější prstenec víček (ten jede s okem
  0,85 × posun středu). Oprava: tečné vyhlazení + návrat na povrch jen u úst (`Topo.relax_mouth`), u očí plné
  vyhlazení + `push_out`. Ověřeno přes 4 seedy × 48 kombinací: 0 přeložených ploch, vůle oka 0,71 mm.
- Šev: detekce smyčky v testu brala i výstřih trička (hranice materiálu je taky okraj sítě) → komponenta okraje
  s nejvyšším vrcholem. Hlava ve výšce okraje zapadala až 2 mm pod okraj těla. Diagnostika paprsky ukázala tětivu
  přes 32° mezi vrcholy rukávu (šikmá mřížka spodní stěny krychle) – úhlopříčka čtyřúhelníku vedla vodorovně ve výšce
  okraje. Oprava: `_seam_alt_diagonal()` (konvexnější úhlopříčka v pásu), cíl švu na Catmull-Rom křivce přes vrcholy
  smyčky (lineární kombinace → morfy těla přesné). Zkoušené a vrácené: plné přilnutí ploch přes okraj (bez účinku),
  kompenzace prověšení (zbytečná po úhlopříčkách).
- Mezitvar `nose_tip_angle` existoval jen pro zápornou stranu (změna vyhlazení u úst shodila kladnou pod práh) →
  když mezitvar potřebuje jedna strana, dostanou ho obě.
- `test_skin`: body krku (jizvy/tetování) byly na starém krku (14–25 mm od povrchu) → přeměřeny ve výšce 1,525 m na
  novém krku; test krku teď počítá se sítí hlavy i těla; počet blend shapes hlavy se kontroluje proti manifestu.

**b) Testy:** `godot_check` 60/60; test_neck_seam **32/32**, test_head 43/43, test_skin 60/60, test_assets 150/150,
test_body_morphs 62/62, test_character 157/157, test_character_v2 39/39, test_character_net 28/28, test_multiplayer 67/67,
test_depression 92/92, test_mental_health 95/95, test_reconciliation 58/58, test_player_commands 40/40,
test_psyche_presentation 19/19, test_net_protocol 34/34; `--test 7` OK (26,1 ms/herní hodinu).
- Šev: odstup hlava–okraj těla −0,13…+1,38 mm v základu, −0,20…+1,72 mm u 12 náhodných těl a krků, −0,16…+1,42 mm
  při předklonu 25°, úklonu 20° a otočení 35° (CPU skinning); 0 zvrácených trojúhelníků u 16 kombinací morfů ×
  ohnutí; normály u smyčky = tělo (≤ 3,8°); „bez límce“ (skok přírůstku poloměru ≤ 2,2 mm na 5 mm výšky).
- Výkon posuvníku v test_character kolísá 3,6–6,3 ms podle zatížení serveru (při souběžných během testů);
  samostatně 3,56 ms (limit 4 ms) – otevřený bod pro C6 (aplikovat jen změněnou skupinu).

**Vizuální kontrola (Blender Cycles, prohlédnuto okem):** 8 postav × 5 pohledů (výchozí, 2 náhodné, extrém max,
extrém min, asymetrie, kombinace tuk, kombinace svaly + ramena). GLB přeneseno do Blenderu přes `/doc/` endpoint Godot
serveru (MD5 ověřeno), arch zpět přes `godot_file_write` (bez tokenů a cizích přístupů). Archy: `docs/images/c3-neck-seam-run12-a.jpg`,
`-b.jpg`.
- Šev u výstřihu čistý zepředu, z boku, zezadu i zespodu (dřív zubatá čára).
- Nový nález z renderu: svalnatá/tlustá postava měla na krku světlý „límec“ → normály pásu se k normálám okraje těla
  stáčí jen do 12 mm nad smyčkou (dřív celý pás 2 cm se sklonem trapézu) a morfy těla působí na celou trubici krku
  (`body_weight`, 8 cm, ne na spodek čelisti). Po opravě znovu vyrenderováno – límec pryč, zůstává přirozený kout pod bradou.
- Nos/philtrum u extrému max: tmavý pás nad rtem už není (oprava vyhlazení u úst z běhu 11 zachována). Světlá ploška
  pod nosem u náhodné 1 je odlesk hřebene filtra, ne průnik (test rtů a ploch bez nálezu).
- Zbývá (mimo tento krok): vlasy jako helma/desky (C4b), bez obočí působí obličej prázdně (C4b), rty ploché a oči
  malé (C3+ část B po C4b), hlava působí u svalnatého těla malá (zvážit vazbu head_size v generátoru), bílé odlesky
  u ucha v pohledu zespodu (rim světlo, ne geometrie).

**c) Gemini (3.5-flash přetížený → flash-lite):** 4 nálezy.
1. „lerp v `_apply_seam` není lineární vůči morfům“ – **neoprávněné**: w a cíl jsou pevné ze základu, takže výsledek
   je lineární v poloze; morfy těla jsou samostatné blend shapes (výchylka smyčky × váha). Pokryto testem 12 náhodných těl.
2. „fallback `loop_hit` [0,…] hodí vrchol do počátku“ – **neoprávněné**: `_seam_setup` při s ≤ 0 vrací {} a import
   selže nahlas (attach_head → {}); tolerance f ±1e-6 kryje paprsek přes vrchol.
3. „normalizace vah po ořezu na 4“ – **částečně oprávněné**: normalizace tam je, ale při nulových vahách těla by
   vrchol zůstal bez kosti → pojistka `[[neck, 1]]` + test.
4. „nulová normála v `_seam_normals`“ – **oprávněné jako pojistka**: kontrola nulové délky přidána (GLB se nezměnil).

**ChatGPT #104/#106:** šev testován v pohybu a při kombinacích morfů těla, normály a zvrácené trojúhelníky, render
z více úhlů vč. náhodných kombinací – splněno. Stavy podle #106: implementováno ✅ / automaticky testováno ✅ /
vizuálně ověřeno ✅ (Blender, okem) / integrováno ✅ (GLB ve hře, SimVisual) – C3+ část A uzavřena.

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
