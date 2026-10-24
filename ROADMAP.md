# Life Simulator – Roadmapa

Pracovní název: **Life Simulator** (finální název později). Cíl: co nejrealističtější, dospělý life-sim
s multiplayerem v Godotu 4.7 (Forward+). Syrový, uvěřitelný život včetně temných stránek (konflikty, rozchody,
nevěra, dluhy, závislosti s reálnými důsledky, drobná kriminalita, nemoc a smrt, černý humor, sprostá mluva),
intimita jen náznakem / fade-to-black, nic s nezletilými v dospělých tématech, žádná glorifikace násilí.
Duševní zdraví jako hluboký, citlivě zpracovaný systém (inspirace Hellblade, Celeste, Disco Elysium).

Legenda: ✅ hotovo · 🟡 rozpracováno · ⬜ plánováno · ⭐ další krok

## (0) TVORBA POSTAVY – aktuální priorita (rozložená do 8 běhů, každý ucelený a otestovaný)
Zásady (vč. připomínek ChatGPT, zpráva 38): **CharacterData = jediný zdroj pravdy** (vzhled, identita,
povaha, historie), verzovaný a migrovaný; vzhled je explicitní atribut, **nikdy odvozený ze jména**.
Tělo, identita, zájmena, orientace, hlas a oblečení jsou **nezávislé osy** – žádná volba „rasa“, žádné
etnické archetypy, žádné svazování pohlaví ↔ výška ↔ vlasy ↔ hlas ↔ oblečení, žádná vazba identity
na povahu či diagnózu. Data normalizovaná (0..1 / −1..1) nebo ve fyzikálních jednotkách (cm, roky),
UI s měkkými limity. Postavy 18+. Citlivé volby (traumata, predispozice) jen podle nastavení obsahu,
nevyplněno = výchozí, nikdy bonus ani trest určité identity. Čeština: gramatický rod (on/ona/ono/oni)
je samostatná volba, slovesné tvary se generují z něj; ono/oni jen opt-in, editor ukáže náhled vět (`Grammar.preview`),
režim „neutrální opis“ (bez rodového příčestí) přijde v C7 (review ChatGPT 49).

| Běh | Obsah | Akceptační testy |
|---|---|---|
| ✅ **C1** (běh 7) | **Datový model a síť**: `CharacterData` v1 (identita, tělo, obličej, kůže, vlasy, oči, make-up, pomůcky, oblečení podle situací, hlas, povaha, aspirace, příběh, soukromé predispozice a traumata), katalogy a rozsahy (`character_schema.gd`), kodek (slovník, JSON soubor, sdílecí kód `LSC1.` se zlib + CRC-32, limity), migrace v0 → v1 (stará domácnost: pohlaví/barva → explicitní atributy), validátor (striktní pro server, opravný pro import; filtr jmen – řídicí/bidi/neviditelné znaky, délky, písma), rozumný náhodný generátor se zámky, historie undo/redo, česká gramatika rodu, deterministický `AppearanceResolver`; integrace: domácnost z CharacterData, SimVisual z vzhledu (už ne z hashe jména), MP: klient posílá kód postavy v hello, server validuje, veřejný snapshot replikuje, soukromé jen vlastníkovi | round-trip a migrace, fuzz validátoru, determinismus vzhledu, distribuce generátoru, zámky, undo/redo, skrytí citlivých voleb, MP vstup s vlastní postavou + odmítnutí nevalidní + soukromí |
| ✅ **C2** (běh 8) | **Tělo**: jedna neutrální síť (řídicí síť 868 vrcholů, čtyřúhelníky) se 10 shape keys – lineární frame/shoulders/chest/bust/waist/hips (váha −1..1 kolem výchozí hodnoty) + asymetrické páry svaly/tuk; morfy = deformační pole nad stromem uzlů spočítané na jemné síti a převedené nejmenšími čtverci; **LSX v4** (morph targety int8 s delta kódováním, čtyřúhelníková část + materiál po plochách, limity, v3 čitelné); import: Catmull-Clark (= Blender, chyba 3,6e-7) + normály pro každý morf → GLB s blend shapes (NORMALIZED); `BodyMorphs` (data → váhy, výška temene = height_cm, délka nohou škálováním stehen, hlava ∝ √výšky); SimVisual: blend shapes, klouby ramen/kyčlí přes rest + inverzní bind (žádný dvojí posun) | test_body_morphs 62/62: hodnoty blend shapes = data, výška/nohy/hlava, rozpočet (10 800 tri postava), normály po morfu, CPU skinning, v3 kompatibilita, poškozená data, výkon 0,11 ms |
| ✅ **C3** (běh 9, vizuálně běh 10b s výhradami) | **Obličej**: procedurální hlava (`HeadBuilder`, pevná topologie 3 890 vrcholů: lebka, víčka a rty jako skutečná geometrie, uši s lemem a mušlí, oční koule s rohovkou) – 29 morfů + **3 osy asymetrie** (oči / nos a ústa / čelist), tuk a svaly těla v obličeji; 62 blend shapes (lineární, ±, **mezitvary** délky nosu, **korekční tvary** nos×hřbet a nos×špička); vlasy přebírají morfy lebky přenosem, krk těla zúžený pod krkem hlavy; `FaceMorphs` (data → váhy), SimVisual; **schéma v2** (head_size, hidden u jizev/tetování, důlek 0..1) s migrací v1→v2; review ChatGPT 48/49 (snapshot allowlist, 128bit uid přidělené serverem, `repaired()` nikdy {}, Unicode XID, [ ] v textech, přesnost temene) | test_head 43/43 (blend × přesný tvar typicky ≤ 1,2 mm, 48 kombinací extrémů bez průniku kůže–oko a rtů, 0 přeložených ploch, symetrie, determinismus server×klient, 0,17 ms), test_character_v2 39/39 (korpus 42 jmen, temeno na 6 405 kombinacích ≤ 0,0013 mm) |
| 🟡 **C4a** (běh 10) | **Kůže**: SkinModel (Beer–Lambert melanin/hemoglobin/karoten, jedna spojitá funkce), SkinLayers (pihy, znaménka, akné s pozánětlivou pigmentací, vitiligo, vrásky a stařecké skvrny z věku + weathering, jizvy a tetování na zkalibrovaných bodech povrchu, make-up, obočí, strniště), `skin.gdshader` (SSS, masky v klidových souřadnicích CUSTOM0, 8 motivů tetování, LOD), schéma v3 `skin.detail_seed` + migrace; C3: mezitvary/kvantizace testem, rasterizovaný arch `res://previews/c3_face_sheet.png` (čeká na lidskou kontrolu) | test_skin 57/57: spojitost, spektrum, sytost/odstín na 1 386 kombinacích, determinismus po síti, poloha na povrchu, shader se kompiluje, CUSTOM0 = rest |
| ✅ **C3+ A** (běh 11–12) | **Krk a šev hlava–tělo**: krk těla odříznutý nad smyčkou (16 vrcholů, báze krku vzadu zvednutá – trapéz, C7), pás krku hlavy přilnutý na Catmull-Rom křivku přes smyčku, blend shapes těla na krku hlavy (šev sleduje tuk, svaly, ramena a morfy celé trubice krku), váhy kostí smíchané s tělem, normály navázané na tělo, konvexní úhlopříčky v pásu | test_neck_seam 32/32 (bez díry a průniku v základu, u 12 náhodných těl a při ohnutí krku; 0 zvrácených trojúhelníků; bez límce); Blender render 8 postav × 5 pohledů prohlédnutý okem (docs/images/c3-neck-seam-run12-*.jpg) |
| ✅ **C3+ A2** (běh 13) | **Krk – anatomie a délka**: báze krku a trapéz zvednuté polem podle směru (vpředu 4 / do stran 30 / vzadu 46 mm) podle měření GLB proti antropometrii (C7 0,868 H, bod krk–rameno, jugulum 0,82 H); posuvník `body.neck_length` −1..1 (±15 mm ≈ ±16 % předního krku) jako lineární blend shape hlavy `b_neck_len` (rampa od švu k bradě/týlu, oči/ústa/vlasy jdou s hlavou, okraj švu se nehne), schéma **v4** + migrace v3→v4, temeno dál = height_cm, randomizér N(0; 0,3); robustní `loop_hit` (review #111) | test_neck_length 36/36, test_neck_seam 56/56 (šev při ±1 × tuk/svaly × ohnutí ±30°, linearita, 0 flipů, anatomie, Catmull-Rom); Blender render 6 postav × 5 pohledů prohlédnutý (docs/images/c3-neck-length-run13-*.jpg) |
| ✅ **C3+ B** (běh 18) | **Doladění obličeje**: projekce brady a oblasti pod rtem 11 mm (váha z výchozí hlavy → lineární s morfy), oční štěrbina 30 mm s koutky mimo oční kouli (vnitřní koutek 15 mm od středu, slzné jezírko), rty s objemem a o 2 mm širší ústa, menší rozsah eye_size (−1 už není škvíra), korekční tvar vzdálenost × hloubka očí, generátor: velikost hlavy slabě s kostrou (r ≈ 0,24, nezávisle na rodu); výška hlavy změřena 22,5 cm = v normě (beze změny) | test_head 43/43 (extrémy 4,07 mm), test_skin 61/61 (make-up = hlava), test_character_v2 43/43; Blender render 12 obličejů × 3–4 pohledy prohlédnutý (docs/images/c3b-face-run18-*.jpg) |
| ✅ **C4b+** (běh 19) | **Detaily vlasů**: okraj skořepiny u spánků (dělení trojúhelníků přes linii, nejdelší hrana 18 → 8,6 mm), nepravidelné copánky a dredy, které rámují obličej (≥ 8,5 cm od středu), plnovous končí pod čelistí, bez sloupců a bez mezery pod rtem; měkká zóna extrémů posuvníků přesunuta do editoru C6 | test_hair 60/60; Blender render copánků, dredů, undercutu s plnovousem, bradky a krátkých vlasů prohlédnutý (docs/images/c4bp-hair-run19.jpg) |
| ✅ **1. osa psychiky** (běh 20) | `PsycheModel` (scripts/psyche/): osobnost P (6 os HEXACO-like, volitelně ve schématu **v5** `personality.hexaco`, jinak z rysů), 9 dispozic D, profily úzkosti a deprese jako data (`data/conditions/*.json`, legacy čísla beze změny), modulace add/mul/threshold/couple s limity a „why“, acyklický graf vazeb, `explain()`; do 4 háčků MentalState jde jen **reziduum** D − D_legacy (individualita z `personality.psyche_seed`, zadaná osobnost, budoucí profily) → nic se nepočítá dvakrát; hodnoty/světonázor (V) odloženy, dokud nemají konzumenta | test_psyche 93/93 (agency, rozmanitost 5 postav, kontext, stabilita 16 × 14 dní, obsah off/muted, schéma v5, bitově stejná neutrální regrese) |
| ✅ **C3++** (běh 21, dokončen po pádu) | **Detaily obličeje a mimika**: řasy jako karty na okraji víček (34 + 18 na oko, sledují morfy i mrkání; po renderu míří dopředu a stáčejí se), hlubší dutina úst, 10 + 10 zubů na obloucích (řezáky až premoláry; stoličky v hloubce nejsou vidět), dáseň, jazyk, limbus a zornice; schéma **v6** (`face.lash_length/lash_density/lash_curl/teeth_shade/teeth_gap/teeth_crooked`, `makeup.mascara`) + migrace v5→v6, generátor (věk jen posouvá průměr, nezávislé na rodu); mimika `ex_*` jako blend shapes (mrkání L/P s mezitvarem, úsměv – po renderu koutky nahoru a dozadu, zamračení, obočí, čelist rotací kolem kloubu do 9°, zornice), přenos na obočí/vousy/vlasy; SimVisual: výraz podle emoce (≤ 0,6), mrkání 2–6 s / rychlost emoce, 12 % dvojité, čelist při replice, klidová tvář nic nepočítá; výkon posuvníku (cache polí face, vah obličeje a názvů blend shapes, zápis jen změn) | test_face_detail 55/55, regrese 21 sad (test_character posuvník 3,68 ms při zátěži hostitele ~50), rozpočet postavy 20 000 tri (19 260); Blender render 8 výrazů × 4 pohledy + detail úst a řas po opravě (docs/images/c3pp-*.jpg). Otevřené: hranaté koutky otevřených úst |
| ✅ **C3++ opravy + C4c** (běh 22, zadání uživatelky) | **Opravy z renderu běhu 21**: otevřená ústa jako čočka se zaoblenými koutky (rotace čelisti se ke koutkům vytrácí, rty se zúží a horní zvedne), Duchennův úsměv (koutky výš a do stran, nasolabiální rýha, tváře, dolní víčka), objem rtů s Cupidovým lukem a filtrem, profil krku při otevřené čelisti (lom 50° → 29°), řasy 24 + 13 širších karet ve shlucích s tmavším kořenem, dutina úst z barvy kůže. **Mikrodetail kůže (C4c)**: póry, kožní linie a vrásky jako porucha normály z derivací s LOD, chloupky (vellus) na siluetě, maz a suchost po zónách (clearcoat, šupinky); schéma **v7** `skin.type/oiliness/dryness` + migrace, validátor, randomizér (nezávislý na rodu a tónu), veřejný snapshot | test_skin_micro 50/50, nové kontroly tvaru v test_face_detail, regrese všech sad; Blender render mimiky a 4 typů pleti na světlé až tmavé kůži |
| ✅ **Škálování domácnosti** (hlavní chat 23. 10. + běh 23) | Ladění plné domácnosti z hlavního chatu (#161: SensoryProfile, hluk jednou za cooldown na spáče, denní trpělivost, měkký strop stresu, alkohol v okně 16 h, rostoucí refrakterní doba atak, zotavení ve spánku, nouzový spánek); běh 23: **zátěžová matice** 4/6/8 postav × 4 seedy × 30 dní + determinismus (`test_household_matrix`), `MentalState.stress_sources` (zdroje stresu), opravy z matice: tlačenice jen v bdělosti, ve spánku stresují jen tělesné potřeby (hlad ×0,5) | test_crowded_household 50/50, test_household_matrix (viz AUDIT běh 23), regrese simulace |
| ⭐ další běh | **C5 oblečení** (kategorie, střihy přes morfy těla jako vlastní povrchy, PBR, převlékání podle situace, MP replikace) + zaoblit koutky otevřených úst; drobnosti z běhu 22 (jemnější mřížka pod bradou, mezera mezi horními jedničkami). Potom integrovaný průchod (tvorba → pár dní ve hře). Navazující práce na matici (#164): kontrolované scénáře (podpora × izolace, spánek, stres), víc seedů, distribuce délky/závažnosti epizod; výkon posuvníku (public_snapshot znovu validuje) do C6 | oblečení sleduje morfy těla, výběr podle situace, MP replikace outfitu |
| ✅ **C4b** (běhy 14, 16, 17) | **Vlasy, vousy, obočí jako karty**: `HairBuilder` (16 účesů – karty pramenů s tokem/pěšinkou, kadeře a vlny, trubice copánků a dredů, cornrows, skořepiny na ježka/undercut/afro, drdol, culík; kolize s hlavou a trupem, náklon přes ramena jen nad nimi; 6 tvarů obočí; 5 stylů vousů v zónách), `HairRig` (přenos morfů hlavy a těla K=4, kosti z kůže, sdílená síť na účes, **stavba ve vlákně** ve hře), `hair.gdshader` (prameny v UV, šediny po vlasech, ústup linie a řídnutí temene přes CUSTOM0, anizotropie, alpha scissor), `AppearanceResolver.hair_look` (přirozená barva, barvení jen hlavy), SimVisual (karty místo „helmy“, fallback na helmu); export pro Blender `tools/hair_export.gd` | test_hair 55/55 (rozpočty, bez průniku do hlavy, obličej volný, vlasy leží na hrudníku a zádech, pokrytí obočí, determinismus i vlákno × synchronně, morfy krku a lebky na vlasech, kosti, SimVisual, nezávislost na rodu/jménu, poškozená data); Blender render 8 postav × 5 pohledů + detail obličeje prohlédnutý (3 kola oprav) |
| 🟡 C5 | **Oblečení**: kategorie běžné/pracovní/společenské/spaní/sport, střihy nezávislé na těle (morfy přenesené na oblečení), barvy a materiály (PBR), převlékání podle situace ve hře | oblečení sleduje morfy těla, výběr podle situace, MP replikace outfitu |
| ⬜ C6 | **Editor I – náhled a vzhled**: scéna editoru ve skutečném enginu (rotace, zoom celá postava/obličej, světla den/noc/interiér, pózy a animace), záložky Tělo/Obličej/Kůže/Vlasy/Oblečení, posuvníky s okamžitou odezvou, režim ZÁKLAD / POKROČILÉ, náhodná postava se zámky, předvolby (neutrální tvary, žádné etnické), undo/redo; filmové UI v tlumené paletě; fallback pro slabý HW | čas aplikace posuvníku (výkon), undo/redo přes UI, zámky při náhodě |
| ⬜ C7 | **Editor II – kdo je to**: Identita (jméno, přezdívka, zájmena a rod, identita, orientace, hlas s náhledem přes Audio Engine), Povaha (rysy s body a konflikty, aspirace), Příběh (rodina, dětství, minulá práce, volitelná traumata a predispozice s vysvětlením dopadů – jen podle nastavení obsahu), šablony (soubor + krátký kód); **přístupnost**: klávesnice/gamepad bez nutnosti trefovat malé posuvníky, škálování UI, čitelná typografie, popisky pro čtečky | navigace bez myši, citlivé volby skryté při vypnutých tématech, sdílecí kód z UI |
| ⬜ C8 | **Integrace a audit**: menu → editor → hra (offline i MP vstup s vlastní postavou), převlékání ve hře, výkon, Gemini audit citlivosti (stereotypy, inkluzivita) a bezpečnosti vstupů, review ChatGPT | E2E test vstupu do hry, privacy test spawnu, determinismus napříč peery |

## (a) Jádro simulace
- ✅ GameClock: herní minuty, rychlosti 0–4, dny v týdnu, fáze dne, krokování pro testy/server
- ✅ Potřeby: hlad, energie, hygiena, zábava, společnost, pohodlí (kvadratická naléhavost, váhy)
- ✅ **Stres** (MentalState): akumulace z neuspokojených potřeb, hádek, urážek, stigmatu, žárlivosti, tlačenice;
  vybíjení spánkem, klidem, oporou a copingy; zvyšuje riziko hádek
- ✅ Osobnostní rysy (15) vč. negativních/ambivalentních: Žárlivý, Vznětlivý, Cynik, Impulzivní, Úzkostlivý
  – ⬜ další: manipulativní, líný ke druhým, zbabělý, narcistní rysy (ne jako diagnóza)
- ✅ Nálada a 11 emocí (nově Úzkostný), moodlety, touhy rysů, moodlety z duševního stavu
- ✅ Utility AI plánovač; akce `player_only` a `involuntary` AI nevybírá; obsahové štítky respektují nastavení
- ✅ Příkazy hráče: fronta (max 3), přebíjí jen rozhodnutí AI, zrušení, probuzení s moodletem „Rozespalý“
- ✅ Headless testy (`--test N`, `res://tests/*.tscn` s watchdogem)
- 🟡 **Duševní zdraví** – hotový základ (Den 4; deprese po review ChatGPT 39: habituace bez stropu, společný rozpočet úlevy, robustní načtení):
  - ✅ úzkost jako 3 složky (vnímaná hrozba / tělesná aktivace / citlivost na spouštěče) + regulace, opora,
    zvládnutelnost, dobré a špatné dny; diagnóza = predispozice se závažností (úzkostná porucha)
  - ✅ panická ataka jako mimovolný symptom; hráč není zamčený (dýchání/svěření i během ataky, i s plnou frontou)
  - ✅ 7 copingů s kompromisy a habituací (dýchání, procházka, deník, svěřit se, doomscrolling, schovat se,
    pivo na nervy s tolerancí a ranním reboundem); test nedominance napříč kontexty
  - ✅ expozice (zkušenost, ne garantovaná odměna), cesta k zotavení nikdy uzavřená
  - ✅ rušivé myšlenky (soukromé, vždy „myšlenka, ne fakt“), úzkostná interpretace hovorů
  - ✅ svědci: pomoc (zkrátí ataku, posílí vztah) vs. stigma (bolí, vztah klesne)
  - ✅ **deprese** (Den 6, `depression.gd`): zátěž (dny–týdny) + oddělené *wanting* (naučené očekávání
    s pesimismem), *liking* (prožitá radost), *vigour* (bariéra iniciace × námaha akce) a učení z rozdílu
    očekávání; behaviorální aktivace s habituací (spam nevyléčí), kontakt, opora, spánek; epizoda až po
    trvání, slabá stopa po ní (relaps), endogenní propady u predispozice; ranní zhoršení jen jako
    individuální vzorec; hráčův příkaz se nikdy neodmítne – jen „nemůže se dokopat“ (zrušitelné);
    emoce Sklíčený, depresivní myšlenky bez SI obsahů, šedý filtr v PsycheFX
  - ⬜ terapie/klinika, léky s vedlejšími účinky (navazuje na (b) město); stigma deprese u svědků
  - ⬜ traumata a dlouhodobá paměť (spouštěče vázané na místa/osoby, vyhýbání, flashbacky jako rušivé myšlenky) → PTSD
  - ⬜ bipolární porucha, OCD, ADHD, poruchy osobnosti (ne jako šablony záporáků)
  - ⬜ PPP a sebepoškozování **jen** přes emoce, vztahy a důsledky – žádné metody, žádné hratelné akce,
    žádná čísla jako cíl; ve výchozím stavu skryté (nastavení `sh_ed_topics`). Sebevražda není hratelná akce.
  - ⬜ dialogy se zúženými volbami v úzkosti/depresi (volby viditelné, ale „těžké“)
  - 🟡 **Plán rozšíření (peiti #79, ChatGPT #83, Grok #85)** – (1) ✅ běh 20; 1 osa = 1 běh, vkládané mezi C4–C8: (1) společný rámec 9 interpretovatelných dimenzí (citlivost na hrozbu, sociální hrozba, impulzivita, regulační kapacita, potřeba předvídatelnosti, senzorická citlivost, energie s baseline, odměna z činností, kognitivní flexibilita; modulace s limity a popisem co/o kolik/proč); (2) sociální úzkost + strach z odmítnutí/opuštění; (3) vyhoření + úzkostná deprese; (4) OCD; (5) ADHD/ADD; (6) bipolární porucha; (7) autistické projevy jako profilové osy. Každý krok: testy agency, přepínač plně/ztlumeně/vypnuto, test rozmanitosti.
  - ⬜ **EmotionPresenter** (ChatGPT #86) po C8: póza, mimika, dech, mikroakce a adaptivní hudební vrstvy (stems, ticho jako stav, protiopakování, motiv úlevy); hudební vrstvy dřív, spolu s osou 1
- ✅ Křivdy, vina, omluva a usmíření (Den 6, `rel_ledger.gd`); čas hojí jen bez živé křivdy
- ✅ **Dynamika domácnosti** (běh 15, `household_dynamics.gd` + SimAgent): vyvážení zisku/ztráty (hádka ×0,6, opakovaný hovor ×0,7), třenice (hluk v noci, koupelna, nádobí jen po skutečném vaření) s cooldowny a dráždivostí povahy, stížnost jako tón oslovení, společné chvíle (cooldown, brzda křivdou, nic při křivdě > 60), náhodné životní události, nálada obou ±20 p. b., de-eskalace, měkký strop stresu z hádek (vznětlivý 65), drift záporných vztahů, zanedbání kladných, vzpomínky podle směru změny. Test 16 seedů × 14 dní: hádky 32 % ± 10 p. b., vztahy se liší podle povah, stres > 85 ~0 %.
- ⬜ Dynamika domácnosti dál: v MP opt-out z cíle třenic (PvP), prostorové filtrování dvojic pro velké parcely, víc druhů třenic (peníze, nákupy, úklid) až s ekonomikou; statistika „jak to doma vypadá“ v HUD
- ⬜ Dovednosti, vlastnictví (moje postel), návyky a rutiny
- ⬜ Pathfinding (NavigationServer3D) místo přímé chůze

## (b) Svět, stavění, nákup
- 🟡 Procedurální startovní parcela (dům s cutaway stěnami, kuchyň, obývák, ložnice, koupelna, zahrada)
- ⬜ Mřížka parcely, režim stavění a nákupu, ukládání parcely
- ⬜ Město se čtvrtěmi (i nebezpečnějšími), bar, herna, zastavárna, terapeut/klinika, úřad práce

## (c) Vztahy a NPC
- ✅ Vztahy −100..100 se štítky, hovor s rizikem hádky (nově i stres a vznětlivost), paměť
- ✅ Urážka s trvalými následky, ochrana proti griefingu
- ✅ Svěření se (naslouchá vs. odbyde), pomoc při atace, stigma, žárlivost (max 1× za 4 h na soka)
- ✅ Křivda (grudge) brzdí oteplování; omluva s upřímností z chování (opakované/porušené omluvy),
  přijetí / „uvidíme“ / odmítnutí, spam ani omluva „za nic“ nikoho nepřeruší; AI se omlouvá z viny
  (pýcha Bručouna/Cynika ji tlumí, cooldown 12 h)
- ⬜ Rivalita, manipulace, drby, nevěra, rozchody; romantika (fade-to-black); podpora vs. toxicita
- ⬜ **Světonázor a identita v kontextu** (ChatGPT #89–91) po C8: (A) víc názorových os (hodnota, jistota, důležitost; bez reálných stran a bez hodnocení „dobrý/špatný názor“), (B) „kdo o čem ví“ – graf sdílení informací, coming out jako volitelný proces, reakce z názorů, vztahu a povahy; diskriminace není nevyhnutelná, LGBT+ život i v radosti
- ⬜ NPC sousedé; FCCS mozek (mcp npc_*) pro dlouhodobé cíle a dialogy

## (d) Multiplayer
- ✅ Autoritativní server (ENet), offline / host / dedikovaný / klient; protokol v3 (vlastní postava v hello, striktní validace, despawn po odchodu)
- ✅ Spawner + Synchronizer (jen veřejný stav), soukromý stav vč. **duševního stavu a myšlenek** jen vlastníkovi
- ✅ Diagnózy se neposílají ve spawn datech; server odmítá `involuntary` akce, obsah zakázaný nastavením
  serveru a pomoc postavě bez ataky
- ✅ Validace vstupů, rate limit, hello timeout, filtr viditelnosti, `server_relay` vypnutý, sanitizace chatu
- ✅ Čas ze serveru, hlasování o rychlosti + nouzová pauza; chat, roster, divák, pozdní připojení
- ⬜ Lobby/menu, předávání postav, vlastní domácnost pro každého; ukládání stavu serveru, reconnect (token)
- ⬜ WebSocket pro web; limit velikosti paketů; test s latencí/ztrátou paketů (ne jen v jednom procesu)
- ⬜ Opt-out z PvP konfliktů; zobrazení serverového nastavení obsahu klientům při připojení

## (e) Vizuál
- ✅ Forward+, SDFGI, SSAO, SSIL, volumetrická mlha, AgX, denní cyklus, lampy
- ✅ **PsycheFX**: vinětace, desaturace, rozmazané okraje a pulz v rytmu srdce při úzkosti (vlastní postava,
  vypnutelné/ztlumitelné)
- ✅ **Blender bridge** (Den 5): skripty v `tools/blender/`, kompaktní přenosový formát LSX s CRC, import do GLB
  (`tools/import_lsx.gd`), načítání za běhu + PBR detail podle materiálu (`scripts/assets/asset_library.gd`)
- ✅ Postava z Blenderu: od C2 jedna neutrální síť těla s 10 shape keys (LSX v4 → Catmull-Clark → GLB blend shapes),
  hlava, oči, 2 účesy (v3), kostra 17 kostí s heat-weights; procedurální animace idle/walk/sit/lie; vzhled z CharacterData
- ✅ Nábytek z Blenderu: gauč (polštáře, dekorační polštářek), dvojlůžko (čalouněné čelo, peřina), jednolůžko,
  lednice (madla, lístečky na dveřích); ostatní objekty zatím primitiva
- ⬜ Další assety: sporák, TV, knihovna, sprcha, běžecký pás, stůl a židle, dveře/okna, stromy; město
- 🟡 Mimika: ✅ základní výrazy a mrkání jako blend shapes (C3++, běh 21); ⬜ gesta (hádka, pláč, smích), IK chodidel, přechody sednout/vstát, oblečení podle situace
- ⬜ Export: zahrnout `assets/models/*.glb` do exportu nebo přejít na importované scény
- 🟡 Vizuál deprese: šedý filtr (PsycheFX `grey`) ✅; ⬜ těžší kamera, filmový post-processing
- ✅ vzhled z CharacterData místo hashe jména (C1); ⬜ explicitní teleport flag (review ChatGPT, zpráva 30)

## (f) Zvuk a hudba
- ✅ Vlastní syntezátor, 5 skladeb, ambience, 3D zvuky objektů, UI zvuky, melancholie podle nálady
- ✅ **Hudba v3** (běh 17, rozhodnutí uživatelky): původní skladby zpět, „Noční ticho“ = vzor tónu hry, nové „Mlhavé ráno“
  v jeho duchu; v2 (paralelní chat) přinesla ambienci bytu, vrstvu napětí a hlasy hádek bez slov (zůstávají)
- ⬜ Bouchnutí dveří podle intenzity hádky a povahy (ChatGPT #127)
- ✅ Úzkost ve zvuku: low-pass hudby podle úrovně, tlukot srdce 70→140 BPM (generovaný za běhu)
- ⬜ Přenos Surge renderů z Audio Engine (konektor běží: Surge, 3008 patchů), stems podle napětí,
  kroky, dveře, hádky (zvýšené hlasy), ambience bytu

## (g) UI, ukládání, ekonomika, příběhy
- ✅ HUD: čas, rychlost, panel postavy (+ stres, napětí, duševní stav, predispozice), rušivé myšlenky,
  nabídka příkazů (copingy, svěřit se, jít uklidnit; náročnost v úzkosti), chat, hráči
- ✅ **Nastavení obsahu** (Esc): duševní zdraví plně/ztlumeně/vypnuto, intenzita myšlenek, zkreslení,
  závislosti, cenzura sprostých slov, SH/PPP; úvodní obsahové varování; krizová pomoc
  (116 123, findahelpline.com, 112/155)
- ⬜ Ukládání/načítání hry (MentalState už má to_dict/from_dict)
- ⬜ Kariéry legální i nelegální, ekonomika s dluhy, exekuce, chudoba (stresory pro MentalState)
- ⬜ Emergentní příběhy s trvalými následky, deník postavy
- ⬜ Návrhy z místnosti (zařadit po C8, zatím bez implementace): ekonomika s vlastní měnou v celých jednotkách, účetní kniha s hash řetězem, půjčky/daně/exekuce jako procesy (ChatGPT #139); sociální ochrana podle SFPZ v0.4 (#142); hodnoty a světonázor (vrstva V psyche-modelu), až budou mít konzumenta
