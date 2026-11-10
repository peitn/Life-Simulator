# Fiktivní akciová burza nad ekonomikou (M1) – mechanismus, profily, scénáře

Stav: izolovaný, deterministický a otestovaný modul navázaný na `scripts/sim/economy/` (viz `docs/economy.md`). **Ve výchozím stavu je vypnutý**
(`market_enabled` = false) a pak se stav, hash ani chování ekonomiky nemění. **Není napojen na `sim_agent`, `main.gd`, `CharacterData` ani
formát uložených her.**

> **Platnost a meze (čti první).** Jde o *mechanismové pískoviště* nad **vymyšlenými** firmami, tickery (přípona `-G` = game) a čísly.
> Žádná skutečná firma, ticker ani tržní data se nepoužívají. **Všechny parametry jsou `game_balance`**, žádný není `empirical_anchor`;
> nic jsme nekalibrovali na reálné trhy. Výsledky ukazují, co se stane *v modelu při daných pravidlech*, nikoli co udělají reální lidé či trhy,
> a nejsou finanční radou. Závěry níže platí pro tyto konkrétní pravidla profilů, tento cenový proces a tato měřítka.

## 1. Soubory

| Soubor | Účel |
|---|---|
| `scripts/sim/economy/market_catalog.gd` | 8 fiktivních firem v 6 sektorech, 7 profilů (parametry pravidel), výchozí konfigurace |
| `scripts/sim/economy/stock_market.gd` | cenový proces, dividendy, portfolia, nákup/prodej přes knihu, profily, margin, audit pozic, (de)serializace |
| `scripts/sim/economy/market_lab.gd` | spouštěč scénářů: kohorty po profilech, snímky před/po šoku, metriky |
| `scripts/sim/economy/market_scenarios.json` | konfigurovatelné scénáře šoků (10 scénářů) |
| `scripts/sim/economy/economy.gd` | jen malé napojení: `market` (výchozí null), volání `market.run_day()`, klíč `market` v `to_dict`, blok `market` v `agent_view` |
| `tools/lab/market_demo.gd/.tscn` | tabulka profil × scénář + CSV |
| `tools/lab/analyze_market.py` | párové kontrasty podle seedu, sign-flip test, Holmova korekce |
| `docs/data/economy_market/` | `market_runs.csv`, `market_population.csv`, `market_summary.csv`, `market_contrasts.csv`, `market_analysis_meta.json` |
| `tests/test_market_core.*`, `tests/test_market_scenarios.*` | testy (viz bod 9) |

Zapnutí: `Economy.new(seed, {"market_enabled": true, "market": {přepisy z market_catalog.DEFAULT_CONFIG}})`.

## 2. Mechanismus

- **Ceny** v millikr (1 kr = 1000), denní výnos firmy v ppm (1 000 000 = 100 %):
  `r = drift + beta·M + S_sektor + idio + událost + dopad_obchodů`, kde `M`, `S`, `idio` jsou celočíselné aproximace normální náhody
  (součet 4 rovnoměrných, SD 1000) krát SD (`market_sd_ppm` 7000, `sector_sd_ppm` 5000, `idio_sd_ppm` 6500–17000) a krát násobek volatility ze scénáře.
  Burza má **vlastní RNG** (seed odvozený ze seedu ekonomiky) a pořadí losování je pevné i bez událostí → scénáře téhož seedu sdílejí stejný šum
  (společné náhodné veličiny); před šokem jsou cenové cesty identické (ověřuje test).
- **Dopad obchodů**: čistý tok akcií firmy se příští den promítne do výnosu (`impact_pm_per_pct` = 8 pm na 1 % free-floatu, strop ±15 %). Obchoduje se za denní cenu s tvůrcem trhu `market:maker`.
- **Dividendy**: každých 91 dní (fázově posunuté), `dps = cena · výnos · 91 / 365 · (1 − škrt)`, výplata `floor(počet · dps)`. Financuje je účet `firm:<ticker>` doplněný mintem na přesnou výplatu (obdoba mzdových fondů) – dividendy tedy zvyšují nabídku peněz. Volitelná daň z dividend jde do pokladny. Cena se po dividendě neupravuje (zjednodušení).
- **Obchody**: počty akcií jsou celá čísla, žádný short ani páka. Poplatek = `max(3 kr, ceil(hodnota · 0,5 %))` → propad `sink:market_fee`; volitelná daň z obchodu → pokladna. Každá transakce je záznam knihy
  (`trade_buy`, `trade_sell`, `market_fee`, `tax_trade`, `dividend`, `tax_dividend`, `mint_dividend_fund`, `mint_market_capital`). Odmítnuto: neznámý ticker/agent, počet ≤ 0, nedostatek peněz (cena + poplatek + daň), prodej víc akcií, než agent drží, prodej při nelikviditě tvůrce trhu.
- **Zachování a řetězec**: `conservation_report()` platí (agenti + propady + instituce = mint − burn), hash-řetězec knihy se nemění. Pozice agentů lze **zpětně sestavit z knihy** (memo `TICKER|počet|cena`), `audit_positions()` odhalí ruční úpravu portfolia, kterou `ledger.verify()` nevidí.
- **Marginová půjčka** (příznak `margin_enabled`, výchozí vypnuto): jen profil momentum při „FOMO“ režimu, přes existující `request_loan`; margin call = prodej všeho a splátka, když hodnota portfolia < 135 % dluhu.
- **Nucený (likviditní) prodej** u všech profilů: hotovost pod 3 dny výdajů → prodej největších pozic do 6 dní výdajů. Počítá se zvlášť od panických prodejů.

## 3. Investorské profily

Profil se odvodí deterministicky: čtyři vlohy 0–999 (riziko, impulzivita, averze ke ztrátě, nezávislost) z SHA-256(seed, id), posunuté vstupy, které ekonomika už má
(kvalifikace, kredit, bydlení, počet odhalení, aktivní nelegální práce – ta zvyšuje riziko i impulzivitu). Větve v pořadí: impulzivita ≥ 650 a riziko ≥ 600 → momentum; impulzivita ≥ 650 → panic;
riziko < 350 → cautious; impulzivita < 250 → passive; nezávislost ≥ 650 a riziko ≥ 450 → contrarian; averze ≥ 650 → disposition; jinak balanced.
Přibližně 25 % agentů se podle náhodné vlohy účastnit nebude. `set_profile(id, profil)` profil přepíše (použito ve scénářích kvůli vyváženým kohortám).

| Profil | Cíl. podíl akcií | Pravidla (vše `game_balance`) |
|---|---|---|
| cautious | 15 % | rebalance po 30 d, defenzivní váhy, rezerva 20 d výdajů, **výprodej všeho při poklesu portfolia o 20 %** od maxima za 20 d, návrat po 60 d |
| balanced | 35 % | rebalance po 30 d, stejné váhy, rezerva 14 d |
| momentum | 45 % | po 5 d; drží firmy s 20denním výnosem > +2 % (hystereze ±2 %); index +6 % → cíl 70 % (FOMO), −6 % → 15 %; smí marginu |
| contrarian | 35 % | po 5 d; index −8 % → cíl 60 % a váhy podle propadu firem (kupuje dno), +12 % → 15 % |
| panic | 40 % | po 10 d; **výprodej všeho při poklesu portfolia o 10 %** od maxima za 20 d, 30 dní mimo trh, návrat jen při nezáporném 20denním výnosu indexu |
| passive | 40 % | jednou nakoupí stejné váhy, pak nikdy neprodává (kromě likviditního prodeje) |
| disposition | 35 % | po 7 d; prodá celou pozici při zisku ≥ 10 % vůči nákladům, ztrátové nikdy neprodává, dokupuje stejné váhy |

„Panický prodej“ v metrikách = prodej spuštěný výprodejním pravidlem (`dd_exit`); mají ho **cautious (práh 20 %) a panic (práh 10 %)**, ostatní profily 0 z definice.

## 4. Scénáře (`market_scenarios.json`)

Události: `path` (kumulativní změna cen lineárně přes `days`, rozsah `market`/sektor/ticker; denní krok je podíl sousedních bodů cesty, takže součin dává cíl), `vol` (násobek volatility), `div_cut` (škrt dividend + volitelná okamžitá cenová reakce), `rates` (posun sazeb půjček v bp, daň z obchodu, daň z dividend, poplatek + cenová reakce), `layoffs` (vlna propouštění zaměstnaných v ekonomice). Šok nastává ve dni 100.

`baseline` (kontrola) · `crash` (−30 % za 3 dny) · `crash_rebound` (−30 % za 3 dny a +35 % za 60 dní) · `bubble` (+60 % za 40 dní, pak −48 % za 5 dní) · `bear` (−35 % za 120 dní) · `highvol` (3× volatilita 60 dní) · `sector` (technologie −40 % za 2 dny) · `divcut` (dividendy −80 %, cena −6 %) · `rates` (půjčky +5 p. b., daň z obchodu 0,5 %, z dividend 15 %, cena −8 %) · `crash_layoffs` (krach + propuštění 25 % zaměstnaných ve dni 101).
Všechna tato čísla jsou herní konstrukty, ne rekonstrukce skutečných událostí.

## 5. Experimentální návrh a metriky

7 profilů × 6 agentů (42 agentů), každý profil má **stejné jmění (30–120 tis. kr), povolání a bydlení** (sloty se opakují), takže se kohorty liší jen chováním. 240 dní, 12 seedů (1–12), 10 scénářů = 120 běhů (`ok=true`, zachování i pozice ve všech 120 běhech v pořádku, 115 s na 2 CPU).
Ekonomika: `auto_policy` zapnutá s `hire_bp` 100 a `layoff_bp` 0 (náhodné propouštění vypnuto, najímání 1 %/den), bez nelegální práce.

Metriky na profil: **TWR** (časově vážená výnosnost investiční složky, pm), **max drawdown** téže složky, panický podíl prodejů, objem a poplatky, **financial_pressure** a podíl chudoby/dluhu v den 99 (před) a 240 (po), alternativní „pressure_mtm“ a „poverty_mtm“ (do rezervy se počítá i hodnota akcií), změna čistého majetku, Gini majetku celé populace před/po.
Párové kontrasty podle seedu: (A) scénář − baseline uvnitř profilu, (B) profil − passive uvnitř scénáře; exaktní sign-flip test (2^12) jako v `analyze_experiment.py`, Holmova korekce v rámci rodiny × metriky (celkem 412 testů, viz `market_contrasts.csv`).
Smysl p-hodnoty je úzký: říká, jak konzistentní je rozdíl napříč simulačními replikacemi tohoto modelu, nic o reálných trzích.

## 6. Zjištění z běhů (12 seedů, průměry; TWR a drawdown v promile)

**Jednotky:** 100 pm = 10 %. Hvězdička = Holm-upravené p < 0,05.

| Scénář | pokles indexu k minimu | TWR panic | TWR passive | rozdíl panic − passive | drawdown panic / passive |
|---|---|---|---|---|---|
| baseline | −5,4 % | 95,5 | 97,8 | −2,3 (n. s.) | 105 / 107 |
| crash | −33,1 % | −10,9 | −166,5 | +155,6* | 160 / 310 |
| crash_rebound | −30,2 % | 92,3 | 50,2 | +42,2* | 138 / 287 |
| bubble | −50,5 % | 406,8 | −50,5 | +457,3* | 190 / 429 |
| bear | −35,2 % | −84,3 | −210,8 | +126,4* | 185 / 327 |

- **Panický vs. pasivní profil.** V modelu s těmito pravidly panický profil ve všech čtyřech scénářích s poklesem *vychází lépe* než pasivní (menší drawdown, vyšší TWR). To je důsledek (a) cenového procesu bez opětovného návratu k ceně v 3 ze 4 scénářů, (b) pravidla návratu na trh až po 30 dnech a nezáporném momentu, (c) míry TWR investiční složky, která nepočítá dobu v hotovosti. Není to tvrzení, že panický prodej se v reálu vyplácí; ve scénáři s odrazem (V) je výhoda nejmenší (+42) a při jiném pravidle návratu by mohla zmizet. Test ve scénářích nepředpokládá znaménko, jen že panický profil nejdřív panicky prodává (pasivní ne).
- **Podíl panických prodejů** (prodeje `dd_exit` / všechny prodeje): panic 58–68 % v scénářích s poklesem (v baseline 6 %, náhodné výkyvy přes 10 %), cautious 100 % (prodá najednou jednou), ostatní 0. Průměrně 56 panických prodejů na běh v krachu proti 4 v baseline (populace 42 agentů).
- **Momentum** obchoduje řádově víc: objem ≈ 1,35 mil. kr na agenta za 240 dní (balanced 55 tis., passive 20 tis.), poplatky 6 820 kr proti 284 (balanced). V baseline je jeho TWR o +44 pm vyšší než passive, ale nevýznamně; po krachu s odrazem je o −81 pm horší* (prodá na dně, nákup až po obratu momenta). V bear a bubble je lepší než passive (+119*, +151*), protože v modelu trend pokračuje.
- **Contrarian** v krachu −33,5* a drawdown +28* proti passive: kupuje klesající trh (není to tvrzení o reálném kontrariánství).
- **Disposition** je v krachu horší než passive (−43*; větší drawdown +35*); v baseline bez rozdílu.
- **Šok vs. baseline (TWR)**: krach −106 až −301 pm podle profilu (nejméně panic), bear −180 až −317, rates −72 až −96 (kombinace ceny −8 % a daní), divcut −56 až −68, sector −33 až −55 (kromě cautious, který technologie téměř nedrží), `highvol` nevýznamné u všech profilů.
- **Chudoba, dluh, financial_pressure.** V čistě tržních scénářích se podíl chudoby (16,6 %), dluhu (16,6 %) ani cílový `financial_pressure` po šoku nemění – kohortám zůstává likvidní majetek nad prahem a `financial_pressure` využívá jen hotovost, dluh a zmeškané povinnosti. Pokles portfolia ho proto neovlivní (ověřuje test); alternativní `pressure_mtm` také ne. Efekt vidíme až při vlně propouštění (`crash_layoffs`): chudoba po šoku 18–26 % (cautious 18,0 %, balanced/passive/disposition 22,2 %, momentum/contrarian 23,6 %, panic 26,3 %) proti 16,6 %, `pressure_post` 175–229 proti 162 v baseline. **Rozdíly mezi profily ve scénáři `crash_layoffs` nelze číst jako účinek profilu:** propouštění vybírá agenty podle otisku jejich id, takže kohorty nejsou vyvážené v tom, kolik lidí přišlo o práci.
- **Investování zvyšuje hotovostní tlak:** před šokem (den 99) mají momentum 141 pm a contrarian/panic ≈ 90–100 pm vs. passive 83 a cautious 84, protože hotovost je v akciích.
- **Gini majetku** celé populace: 349 → 343 (baseline), 342 (krach), 326 (`crash_layoffs`). Tržní šoky ho tu skoro nehýbou, protože podíl akcií je nízký (průměrný podíl 2 %–39 % likvidního majetku) a kohorty jsou stejné.
- **Objem obchodů populace** 10,8 mil. kr (baseline) vs. 11,7–13,3 mil. (bubble, rates, highvol).

## 7. Zdroje (behaviorální finance)

Každý zdroj označen: **OVĚŘENO** (otevřena stránka s bibliografií/abstraktem a potvrzena tvrzení níže), **JEN NÁZEV**, **Z PAMĚTI**. Žádný parametr modelu nebyl kalibrován na tyto práce; slouží jen jako inspirace pro *pravidla* profilů.

| Zdroj | Stav | Co je ověřeno | Použití v modelu |
|---|---|---|---|
| Kahneman, Tversky: *Prospect Theory: An Analysis of Decision under Risk*, Econometrica 47(2), 263–292, 1979 | OVĚŘENO (stránka Econometric Society, abstrakt) | hodnotová funkce je „obecně strmější pro ztráty než pro zisky“ | inspirace pro averzi ke ztrátě / disposition |
| Odean: *Are Investors Reluctant to Realize Their Losses?* | OVĚŘENO (stránka autora: název, autor, nález; 10 000 účtů, silná preference realizovat zisky, nevysvětleno rebalancováním ani náklady, nižší výnos po zdanění); časopis a rok (J. Finance, 1998) **Z PAMĚTI** | disposition effect | profil `disposition` |
| Barber, Odean: *Trading Is Hazardous to Your Wealth*, J. Finance 55(2), 773–806, 2000 | OVĚŘENO (EconPapers) | 66 465 domácností; nejaktivnější vydělávali 11,4 % ročně proti trhu 17,9 %; autoři to přičítají přehnané sebedůvěře | pozorování vysoké obrátky a poplatků u momentum (v modelu poplatky 24× vyšší než balanced) – jen kvalitativní podobnost |
| Jegadeesh, Titman: *Returns to Buying Winners and Selling Losers*, J. Finance 48(1), 65–91, 1993 | OVĚŘENO (PDF článku, abstrakt) | strategie kupující minulé vítěze má v horizontu 3–12 měsíců významné výnosy | inspirace pravidla momentum; model nic z toho nekalibruje |
| De Bondt, Thaler: *Does the Stock Market Overreact?*, J. Finance 40(3), 793–805, 1985 | OVĚŘENO (kopie článku) | podle závěru článku portfolia minulých „losers“ překonávají minulé „winners“ | inspirace pro contrariána |
| Bikhchandani, Hirshleifer, Welch: *A Theory of Fads, Fashion, Custom, and Cultural Change in Informational Cascades*, J. Polit. Econ. 100(5), 992–1026, 1992 | OVĚŘENO (EconPapers) | pozorovatelé předchozích voleb mohou racionálně kopírovat; mnohé masové chování je křehké | pouze motivace pro zpětnou vazbu toku obchodů do cen (herding model **neobsahuje**) |
| Tvrzení „panický prodej se obvykle nevyplácí“, „investoři honí výkon“ apod. | **Z PAMĚTI / neověřeno, nepoužito jako tvrzení** | – | – |

## 8. Návrh dopadu poklesu portfolia na psychiku (implementováno jako volitelný most: `docs/economy_psyche_bridge.md`)

Rozhraní zůstává `financial_pressure` a `agent_view`. Návrh pro budoucí krok (každý parametr `game_balance`, vyžaduje samostatné rozhodnutí a testy):
1. `agent_view()["market"]` už nabízí `drawdown_pm`, `unrealized_pm`, `equity_share_pm`. Psychika by mohla vzít *nedávný* pokles (např. přes 20 dní) jako **malý, časově doznívající přídavek ke stresu** úměrný `drawdown_pm · equity_share_pm / 1000`, s horním stropem a poločasem desítek dní.
2. Teprve **realizovaná ztráta** (prodej se ztrátou) nebo propad likvidity (`pressure_mtm`) by smělo zvedat `financial_pressure`; samotný papírový pokles nikoli (jako nyní).
3. Žádná finanční ztráta nesmí sama spouštět sebepoškozování ani jiné škodlivé jednání; zůstává „jen tlak“ jako v `docs/economy.md`. Akciové ztráty by měly mít strop dopadu, aby nevznikla spirála.
4. Volitelně: osobnostní vlohy profilu (impulzivita, averze ke ztrátě) mohou násobit velikost přídavku – to je hypotéza, kterou by šlo prověřit v laboratoři, ne zjištění.

## 9. Testy

`tests/test_market_core.tscn` – 116 kontrol (vypnuto ve výchozím stavu, nákup/prodej přes knihu, poplatek jako propad, daň z obchodu, odmítnutí: nulové akcie nelze prodat, bez peněz nelze koupit, dividendy, cenová cesta, profily, zachování 3 seedy × 365 dní, determinismus, uložení/obnova přes JSON se shodným hashem, manipulace knihy i portfolií, margin call, rozhraní pro psychiku).
`tests/test_market_scenarios.tscn` – 85 kontrol (šok sníží ceny a před šokem jsou cesty shodné, panický profil prodává víc než pasivní, tvary bubliny/medvěda/volatility, sektorový šok, škrt dividend, sazby a daně, propouštění, determinismus, všechny scénáře zachovávají peníze, margin).
`test_economy_core` (107) a `test_economy_sim` (62) procházejí beze změny počtů.
Demo: `godot --headless --path . res://tools/lab/market_demo.tscn -- --seeds=1,2,3 --per=6 --days=240 --out=docs/data/economy_market [--margin] [--scenarios=crash,bear]`, poté `python3 tools/lab/analyze_market.py docs/data/economy_market`.

## 10. Známé meze

- Cenový proces je i.i.d. šum s lineárními šoky; nemá volatilitní shluky, ocasy, mean reversion, ceny po dividendě se neupravují. Výsledky pro panic/contrarian/momentum jsou přímo závislé na tom, že proces *nemá* paměť.
- TWR investiční složky ignoruje čas v hotovosti; srovnává tedy „kvalitu“ investované části, ne celkové bohatství (to je `wealth_change`, kde jsou rozdíly menší).
- Profily jsou ruční pravidla (7 variant), ne model psychologie; práh 10 %/20 % a zpožděný návrat panic ovlivňují výsledek. Herding mezi agenty (kopírování) není implementován, jen nepřímá zpětná vazba toku obchodů do ceny.
- Tvůrce trhu má kapitál 20 mil. kr; jeho případné vyčerpání (odmítnutí `market_illiquid`) se v experimentu nesledovalo, ověřuje ho jen samostatný test. Dividendy se tvoří mintem a zvyšují nabídku peněz.
- Kohorty jsou malé (6 agentů na profil), 12 seedů; 412 testů – Holmova korekce je jen v rámci rodiny a metriky. Kohorty sdílejí jednu burzu, takže profily se navzájem ovlivňují přes dopad toku obchodů.
- Chudoba/dluh před a po: v čistě tržních scénářích se nemění (viz výše); ve scénáři s propouštěním je výběr zasažených agentů nevyvážený mezi profily.
- Margin je ověřen testy a jedním scénářem; v hlavním experimentu je vypnutý.
- Spill-over na ekonomiku (propouštění) je jediný zásah burzovního scénáře do ekonomiky mimo ceny a daně.
