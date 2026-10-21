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
| ⬜ C3+ B (po C4b) | **Doladění obličeje v kontextu hotové hlavy**: rty s objemem a koutky, velikost/otevření očí, vazba velikosti hlavy na stavbu v generátoru, tlumení extrémů v editoru | render z více úhlů, náhodné kombinace |
| ⭐ C4b | **Vlasy, vousy, obočí**: účesy jako geometrie (krátké, dlouhé, kudrnaté, afro, copánky, cornrows, dredy, drdol, culík, holá hlava, ustupující linie), vousy a obočí zvlášť (karty/shell), šedivění; Blender render obličeje a kůže, až Space poběží | každý účes ze schématu má síť, sleduje morfy lebky, barvy z modelu pigmentu, rozpočet trojúhelníků |
| ⬜ C5 | **Oblečení**: kategorie běžné/pracovní/společenské/spaní/sport, střihy nezávislé na těle (morfy přenesené na oblečení), barvy a materiály (PBR), převlékání podle situace ve hře | oblečení sleduje morfy těla, výběr podle situace, MP replikace outfitu |
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
  - ⬜ **Plán rozšíření (peiti #79, ChatGPT #83, Grok #85)** – 1 osa = 1 běh, vkládané mezi C4–C8: (1) společný rámec 9 interpretovatelných dimenzí (citlivost na hrozbu, sociální hrozba, impulzivita, regulační kapacita, potřeba předvídatelnosti, senzorická citlivost, energie s baseline, odměna z činností, kognitivní flexibilita; modulace s limity a popisem co/o kolik/proč); (2) sociální úzkost + strach z odmítnutí/opuštění; (3) vyhoření + úzkostná deprese; (4) OCD; (5) ADHD/ADD; (6) bipolární porucha; (7) autistické projevy jako profilové osy. Každý krok: testy agency, přepínač plně/ztlumeně/vypnuto, test rozmanitosti.
  - ⬜ **EmotionPresenter** (ChatGPT #86) po C8: póza, mimika, dech, mikroakce a adaptivní hudební vrstvy (stems, ticho jako stav, protiopakování, motiv úlevy); hudební vrstvy dřív, spolu s osou 1
- ✅ Křivdy, vina, omluva a usmíření (Den 6, `rel_ledger.gd`); čas hojí jen bez živé křivdy
- ⬜ Vyladit četnost hádek v domácnosti (experiment FCCS v3/v4 z 20.–21. 10. ukázal cestu: vyvážení zisku/ztráty, společné chvíle, drift, třenice, nálada a náhodné události – převzít do hry s testem přes 10 seedů) (vztahy po týdnu kolem −45) + pozitivní společné akce
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
- ⬜ Mimika a gesta (hádka, pláč, smích), IK chodidel, přechody sednout/vstát, oblečení podle situace
- ⬜ Export: zahrnout `assets/models/*.glb` do exportu nebo přejít na importované scény
- 🟡 Vizuál deprese: šedý filtr (PsycheFX `grey`) ✅; ⬜ těžší kamera, filmový post-processing
- ✅ vzhled z CharacterData místo hashe jména (C1); ⬜ explicitní teleport flag (review ChatGPT, zpráva 30)

## (f) Zvuk a hudba
- ✅ Vlastní syntezátor, 5 skladeb, ambience, 3D zvuky objektů, UI zvuky, melancholie podle nálady
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
