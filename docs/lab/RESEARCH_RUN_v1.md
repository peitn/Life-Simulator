# Výzkumný běh „Údolí“ v1 (100 fiktivních agentů, 180 dní)

Jen simulační model s fiktivními agenty a parametry `game_balance`. Nic z toho neplatí pro skutečné lidi, firmy ani trhy. Jde o jedno nasazení (seed 20310) s jednou kontrolou, takže závěry jsou orientační, ne statistické důkazy.

## 1. Co bylo zadáno a co vyšlo

| Požadavek | Výsledek |
|---|---|
| Oblast, 100 agentů, různorodé profily | Splněno jako data: `tools/lab/experiments/udoli_v1*.json`, generátor `tools/lab/make_valley.py` (deterministický ze seedu). 100 agentů, 33 domácností, 660 vztahů, 6 investorských profilů. |
| Všechno v nastavení zapnout | Zapnuto vše relevantní pro psychiku a vztahy; vypnuto 1 téma záměrně (viz bod 4). |
| Délka 6 měsíců | 180 herních dní, obě ramena dokončena (13/13 bloků). |
| Různé události | 32 záznamů: 25 intervencí a 7 událostí burzy, deterministicky po dnech, validované runnerem. |
| Jedna společná 100členná simulace | NEVYŠLO. Engine má jeden dům s 9 chytrými objekty, takže při 100 agentech dominuje tlačenice (viz bod 2). Řešení: bloky po ≤ 8 obyvatelích se sdílenou ekonomikou. |

## 2. Výkon (naměřeno)

Krok herních hodin je pevně 2 minuty (konstanta GameClock), hrubší krok bez zásahu do hry nejde.

| Agentů v jednom světě | s / herní den | 180 dní |
|---|---|---|
| 10 | ~3,6 | ~11 min |
| 30 | ~14,4 | ~43 min |
| 100 | ~75 | ~3,75 h (extrapolace) |

Polovinu času žere `Planner.choose`. Monolit 100 agentů byl zamítnut i z vědeckých důvodů: už první den průměrný stres 54,7, na konci 94,4, nálada −68,5. Je to artefakt přeplněného jediného domu, ne chování populace. Proto 13 bloků (≤ 8 agentů), každý jeden proces světa, běží sekvenčně (2 CPU, žádné paralelní instance). Čas: ramena události 6035 s a kontrola 7564 s součtu bloků (~1,7–2,1 h na rameno).

Ekonomika a burza jsou společné: každý blok registruje všech 100 agentů (`register_all`), ověřeno, že ekonomické metriky jsou ve všech blocích shodné. Psychika na ekonomiku zpětně nepůsobí (jen ekonomika → stres/nálada přes `economy_psyche`).

## 3. Oblast a populace

Seed 20310. Domácnosti, rodiny, skupiny (Dílna, Technický ústav, úřad), komunity, věk, bohatství 0–3, rysy bez konfliktů, investorský profil (cautious, balanced, momentum, contrarian, panic, passive). Lidé jsou rozděleni do bloků podle domácností a vazeb, aby vztahy zůstaly uvnitř bloku.

## 4. Zapnuté a vypnuté systémy

Zapnuto: `mental_health: full`, `intrusive_thoughts: 3`, `distortion_fx` (síla 1.0), `addiction`, `profanity`, `adult_intimacy`; ekonomika z populace (`economy.use_population`) s mostem do psychiky; vztahy, drby a fámy, hádky, domácnosti, práce a zaměstnání, životní události, burza s profily investorů, plánovač, potřeby, maskování, stigma.

Vypnuto: `sh_ed_topics` (témata sebepoškozování a poruch příjmu potravy). Důvod: bezpečnost; výzkumný běh je nepotřebuje a bez klinického dohledu je nechceme generovat. Dále nebylo použito: 3D, HUD, audio (headless), checkpointy (nejsou bitově přesné při silném stresoru, viz omezení), zpětná vazba psychika → ekonomika (v enginu není).

## 5. Události

Dny jsou od startu; ekonomické události jsou vidět od dne d+1.

| Den | Událost | Typ | Zasaženo |
|---|---|---|---|
| 5 | Zimní tma a mrazy | moodlet + stresor | 100 |
| 12 | Zimní účty za energie | stresor | 50 |
| 20 | Propouštění v Dílně | stresor + ekonomika (layoffs) | 17 / 100 |
| 28 | Úmrtí v rodině | stresor + moodlet | 5 |
| 35 | Spor o hluk z dílen | vztah | 39 |
| 42 | Krach burzy −35 % | ekonomika (path) | 100 |
| 47 | Zvýšená volatilita | ekonomika (vol) | 100 |
| 55 | Individuální krize | stresor | 1 |
| 60 | Masopustní slavnost | moodlet + vztah | 100 |
| 70 | Recese (úvěry, dividendy, tržby) | ekonomika + stresor | 100 / 24 |
| 72 | Druhá vlna propouštění | ekonomika | 100 |
| 85 | Smíření po sporu o hluk | vztah | 39 |
| 90 | Termín daňového přiznání | stresor | 100 |
| 95 | Výhra v tombole | moodlet | 1 |
| 100 | Růst burzy +25 % | ekonomika | 100 |
| 110 | Odměny v Technickém ústavu | moodlet | 9 |
| 120 | Chřipková vlna u starších | stresor | 17 |
| 130 | Letní festival | moodlet + vztah | 100 |
| 140 | Vedro | stresor | 100 |
| 150 | Povodeň na Říčním nábřeží | stresor + moodlet | 15 |
| 152 | Sousedská solidarita | vztah | 15 |
| 165 | Hádka úřadu s ústavem | vztah + stresor | 18 |
| 175 | Smíření úřadu a ústavu | vztah | 18 |

## 6. Metoda

Dvě ramena: `events` (scénář s událostmi) a `control` (stejná oblast, stejný seed, bez událostí). Odezva události = změna průměru za týden po vs. týden před, a rozdíl proti kontrole (difference-in-differences, DiD). Intervaly jsou bootstrap přes agenty, takže jsou optimistické (nepočítají variabilitu mezi běhy). Rozdíl proti kontrole zahrnuje i chaotickou divergenci běhů, protože trajektorie se po zásahu rozcházejí.

## 7. Zjištění (čísla z `docs/lab/research_run_v1/analysis.json`)

Celkově, 180 dní, průměr přes agenty:

| Metrika | events | control |
|---|---|---|
| průměrný stres | 15,71 | 15,73 |
| průměrná nálada | 20,88 | 20,86 |
| podíl vysokého stresu | 0,03 % | 0,2 % |
| průměrný vztah | 26,5 | 24,9 |
| podíl hádek z rozhovorů | 17,8 % (6215/34976) | 18,2 % (6402/35121) |
| Gini na konci (start 0,616) | 0,591 | 0,561 |
| chudoba na konci (start 0,52) | 0,45 | 0,37 |
| podíl s vysokým finančním tlakem | 25 % | 22 % |

1. Události nezměnily dlouhodobý průměr stresu ani nálady (rozdíl −0,02 a +0,02). Jejich vliv je krátkodobý. Světy bez zásahu jsou stabilní a nízkostresové.
2. Největší zdroje stresu v modelu jsou tlačenice (crowd), závist (jealousy), hádky a tření, svědectví konfliktu; ne vnější události. Ani v blocích po 8 lidech tlačenice nezmizí.
3. Nejsilnější odezvy (DiD stres / nálada, týden po vs. před, 95% bootstrap):
   - Povodeň (den 150, n = 15): stres +5,1 [1,8; 8,2], nálada −10,6 [−15,8; −5,7]. Solidarita o dva dny později: stres −4,0 [−6,8; −1,0].
   - Zimní účty (den 12, n = 50): nálada +7,1 [3,3; 11,0] při stresu +2,0, tedy nejasné; pravděpodobně artefakt kontrolní větve.
   - Slavnost (den 60, n = 100): nálada +6,6 [4,2; 9,0]; festival (den 130): +3,8 [1,5; 6,0].
   - Zimní tma (den 5): nálada −6,3 [−8,2; −4,5].
   - Krach burzy (den 42): starost z poklesu portfolia +0,114, stres +2,0 [0,6; 3,4]; nálada −2,3 [−4,8; 0,2].
   - Výhra v tombole a individuální krize jsou n = 1, interval je degenerovaný, jen ilustrace (nálada +32, resp. stres +13,5).
   - Většina ostatních (volatilita, recese, dividendy, daně, vedro, smíření) má interval zahrnující nulu.
4. Krach burzy podle investorského profilu (změna hodnoty portfolia, jen agenti s portfoliem): contrarian +42 %, balanced −26 %, passive −35 %; cautious, momentum a panic −100 % (úplná likvidace portfolia). Poslední tři čísla jsou pravděpodobně artefakt pravidel profilů a malých n (6, 14, 9), neberte je jako reálný vzor. Stres po týdnu: nejvíc passive +3,7 a contrarian +2,9, panic −1,8.
5. Ekonomika: Gini klesl z 0,616 na 0,591 a chudoba z 0,52 na 0,45, ale kontrola dopadla lépe (0,561 a 0,37). Krach a recese tedy zhoršily rozdělení majetku oproti kontrole.
6. Drby a fámy: 12 782 sdílených drbů, 2 080 fám na konci (kontrola 12 903 / 2 079); životní události dobré 10 366 / špatné 10 281.

## 8. Omezení a poctivost

- Jeden seed, jedna kontrola. Žádná replikace mezi seedy (čas); intervaly jsou jen přes agenty a podhodnocují nejistotu. DiD obsahuje šum z divergence trajektorií.
- Bloky ≤ 8 obyvatel nejsou jedna společná vesnice: vztahy napříč bloky jsou omezené; jen ekonomika je sdílená.
- Zásahy na všech 100 agentů (stresor) dělají checkpointy nepřesné. Hlavní běh checkpointy nepoužívá.
- Efekty n ≤ 5 nejsou interpretovatelné.
- Nic z výstupu se netýká reálných osob.

## 9. Soubory a reprodukce

- Scénář a data: `tools/lab/experiments/udoli_v1.json`, `udoli_v1_control.json`, `udoli_v1_household.json`, `udoli_v1_population.json`
- Generátor: `tools/lab/make_valley.py`; ovladač: `tools/lab/run_valley.py`; analýza: `tools/lab/analyze_valley.py`; report: `tools/lab/make_valley_report.py`
- Runner: `tools/lab/lab_runner.gd` (MODEL_VERSION `lab-m1b-0.2`), `lab_cli.gd`, `perf_probe.gd`
- Test: `tests/lab/test_lab_valley.tscn` (60 kontrol)
- Agregovaná data a graf: `docs/lab/research_run_v1/` (týdenní a měsíční CSV, `event_response.csv`, `analysis.json`, `report.html`)
- Příkazy: viz `docs/testing.md`, sekce Laboratoř.
