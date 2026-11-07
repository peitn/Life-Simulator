# Ekonomika (E0/E1) – fiktivní měna, kniha, práce, dluh, daně, vynucování, chudoba

Stav: izolovaný, deterministický, plně otestovaný modul. **Není napojen na `sim_agent`, `main.gd`, `CharacterData` ani save formát.**
Slouží jako budoucí zdroj „finančního tlaku“ pro psychologii a pro laboratoř (`tools/lab`, `docs/lab`).

> **Platnost a meze (čti první).** Jde o *mechanismové pískoviště*: ukazuje, co se stane v modelu při daných pravidlech.
> Není to předpověď reálné ekonomiky ani reálných lidí, nejsou v něm kalibrované reálné údaje a nic z něj není finanční rada.
> Všechny peníze, zaměstnání a „nelegální činnosti“ jsou fiktivní herní procesy (riziko, pokuta, pravděpodobnost odhalení);
> dokument ani kód neobsahují žádné návody k reálné trestné činnosti. Finanční tíseň smí **pouze zvýšit tlak**
> (`financial_pressure`); modul sám nikdy nespouští sebepoškozování ani jiné škodlivé jednání.

## 1. Soubory

| Soubor | Účel |
|---|---|
| `scripts/sim/economy/economy_ledger.gd` | hlavní kniha: celočíselné účty, dvojitý zápis, hash řetězec SHA-256, `verify()` |
| `scripts/sim/economy/economy_catalog.gd` | měna, povolání (legální + abstraktní nelegální), bydlení, výchozí konfigurace |
| `scripts/sim/economy/economy.gd` | jádro: agenti, mzdy, daně, povinnosti, půjčky, vynucování, tlak, metriky, (de)serializace |
| `tools/lab/economy_demo.gd/.tscn` | headless demo 8 agentů × 365 dní × seedy → CSV |
| `tests/test_economy_core.*`, `tests/test_economy_sim.*` | testy (viz bod 8) |

## 2. Měna a kniha

- Fiktivní měna **krejcar (kr)**; 1 **zlatý (zl) = 100 kr**. Všechny částky jsou `int` v krejcarech, nikde `float`.
- Účty: `agent:<id>`, `treasury` (daně, pokuty), `bank`, `underground` (zdroj abstraktních nelegálních příjmů),
  `employer:<sektor>`, propady `sink:rent|utilities|food`, a speciální `world:mint` (zdroj) a `world:burn` (cíl).
- Každý záznam je převod `amount > 0` z účtu na účet (dvojitý zápis; součet všech zůstatků včetně `world:*` je vždy 0).
- **Bez záporných zůstatků**: jen `world:*` smějí do mínusu. Převod bez krytí se odmítne (`insufficient_funds`). Dluh je evidovaný
  mimo zůstatky (půjčky, nedoplatky) – „záporný“ je tedy jen závazek, ne účet.
- **Peníze vznikají/zanikají jen explicitně**: `mint` (kapitál banky, počáteční jmění agentů, doplnění zaměstnavatelského/podsvětního účtu
  při nedostatku – `mint_wage_fund`, `mint_underground_fund`, ruční `mint`) a `burn` (volitelné spálení přebytku pokladny). Mzda se platí z účtu
  zaměstnavatele (sektoru); týdně se propady (`sink:*`) recyklují zpět zaměstnavatelům (`recycle`), takže se minting omezuje na doplnění rozdílu.
- **Hash řetězec**: `hash = SHA-256(JSON([id, den, druh, z, na, částka, memo, hash_předchozího]))`, genesis = 64 nul.
  `verify()` přepočítá celý řetězec i zůstatky; odhalí změnu, vložení, smazání, přeházení, ruční úpravu zůstatku. Limit: útočník,
  který přepočítá *celý* řetězec, projde – proto existuje externí kotva `verify(expected_head)` (uložit `ledger.head` jinde).
- **Zachování** (`conservation_report()`): `agenti + propady + instituce == Σ mint − Σ burn` (součet nezávisle z historie) a přepočet z řetězce sedí.

## 3. Pravidla jednoho herního dne (`run_day()`)

Pořadí: (1) příjmy (mzdy, nelegální směny) → (2) vynucování → (3) povinnosti (jídlo denně, nájem v `rent_due_dow`, energie v `utilities_due_dow`)
→ (4) splácení nedoplatků (jen z částky nad rezervou `arrears_reserve_days` × denní výdaje) → (5) půjčky (úrok, splátky) →
(6) týden (den % 7 == 6): dávka nezaměstnaným z pokladny (jen co v ní je), recyklace propadů, volitelný burn → (7) sandbox politika
(`auto_policy`) → (8) uzavření denních logů (28 dní příjmů a zmeškaných povinností).

- **Povolání**: legální = `hours_per_shift × wage_per_hour` za směnu; směna je v dni, kdy `(den + shift_off) % 7 < shifts_per_week`;
  výplata denně (`pay_period: day`) nebo týdně (v dni 6). Max. 1 legální + 1 nelegální práce na agenta.
- **Nelegální (abstraktní)**: příjem za směnu = rng v `[income_min, income_max]` z účtu `underground`; **nezdaněný**, hromadí se jako
  „neodhalená expozice“. Žádný popis metod, jen čísla.
- **Daně** (jen z legálních mezd): pásmová týdenní, výchozí pásma `[do 8000: 0 %] [do 20000: 15 %] [nad: 28 %]` (sazby v bp). Srážka je
  **kumulativní v rámci týdne**: `daň_teď = tax_on(hrubý_týden_po_výplatě) − už_sražená_daň`, takže součet srážek za týden je přesně
  `tax_on(hrubý týden)` bez ohledu na četnost výplat. **Zaokrouhlení**: `tax_on` sečte `úsek × sazba_bp` přes všechna pásma a dělí `10000`
  celočíselně s ořezem k nule **jednou na konci** (daň není nikdy vyšší než přesná hodnota; chyba < 1 kr na týdenní výplatu).
  Režimy: `progressive`, `flat` (`flat_rate_bp`), `none`.
- **Půjčky**: žádost `request_loan(id, částka)`; podmínky: skóre ≥ `loan_min_credit`, ≤ `loan_max_active` aktivních, celkový dluh ≤ strop
  (`max(starter_cap, 8 × týdenní příjem)`), likvidita banky. Roční sazba podle skóre (tabulka). **Úrok celými čísly**: denně
  `balance × rate_bp / (10000 × 365)`, zbytek se přenáší (`carry`) → za rok přesně `floor(jistina × sazba)`. Splátka každých 30 dní =
  `max(500, ceil(15 % dluhu))` (nejvýš celý dluh), nejdřív úrok, pak jistina; vše-nebo-nic (nelze-li zaplatit celou, je zmeškaná).
  **Selhání**: 3 zmeškané splátky po sobě → `default`: **pouze** pokles kreditního skóre (−20 za každou zmeškanou, −150 za default),
  zmrazení úroku; **žádné zabavení a žádné jednání agenta**. Dluh se dál eviduje a dá se splatit (`repay_loan`).
- **Vynucování**: každý den s expozicí > 0 se losuje odhalení s pravděpodobností `detect_bp` (nejrizikovější nelegální práce agenta; zvyšuje ji
  záznam o dřívějších odhaleních `+25 %` za záznam, strop `detect_cap_bp`). Při odhalení: pokuta `fine_pct % × expozice`; z účtu se zabaví
  `min(zůstatek, pokuta)` (záznam `fine`), zbytek je nedoplatek `fine`; expozice 0, pozastavení nelegální práce `cooldown_days`, skóre −30.
- **Nedoplatky a povinnosti**: nezaplacený nájem/energie → nedoplatek (splácí se z přebytku); nezaplacené jídlo → jen zmeškaná povinnost. Žádné
  vystěhování, hlad ani jiné automatické důsledky se nesimulují – jen zvyšují `financial_pressure`.

## 4. `financial_pressure` (0..1)

Celočíselně v promilích, pak `/1000.0`:

```
daily_burn = food_daily + (rent_weekly + utilities_weekly) / 7
runway_pm  = clamp(1000 − balance·1000 / (daily_burn · 30), 0, 1000)               # 30 dní rezervy = žádný tlak
debt_pm    = clamp((dluh·1000 / příjem_28d) · 100 / 200, 0, 1000)                  # dluh = 200 % 28denního příjmu → 1; dluh>0 a příjem 0 → 1000
missed_pm  = clamp(zmeškané_povinnosti_za_28_dní · 1000 / 6, 0, 1000)
pressure   = (450·runway_pm + 300·debt_pm + 250·missed_pm) / 1000 / 1000
```

`dluh` = nesplacené půjčky (jistina + úrok) + nedoplatky (nájem, energie, pokuty). `příjem_28d` = součet čistých mezd, dávek a nelegálních příjmů
za posledních 28 dní (u kratší historie přepočteno, dělitel min. 7). `pressure_components(id)` vrací všechny složky. Vzorec je **herní konstrukt**,
ne validovaná míra finančního stresu.

Agregáty (`metrics()`, `household_metrics()`): Gini na celočíselných zůstatcích (`(2Σ i·xᵢ − (n+1)S)·1000/(nS)`, vzestupně), míra chudoby
(`balance − dluh < 14 × daily_burn`), hluboká chudoba (`≤ 0`), podíl vysokého tlaku (≥ 0,6), medián, nabídka peněz; domácnosti: sdružené
zůstatky/dluhy a chudoba na hlavu.

## 5. Parametry: `game_balance` × `empirical_anchor`

**Žádný parametr není `empirical_anchor`.** Nic jsme neověřovali proti reálným datům a nic nekalibrovali; žádné statistiky nejsou citovány.
Všechny hodnoty níže jsou `game_balance` (odhad pro hratelnost, volně laditelný v `DEFAULT_CONFIG`/`JOBS`/`HOUSING`).
Jediné prvky s matematickým (ne empirickým) významem: definice Giniho koeficientu a celočíselný úrok `balance·rate/(10000·365)`.

| Skupina | Parametry (výchozí) | Tag |
|---|---|---|
| Ceny | `food_daily` 400; nájem/energie týdně: shared 4500/1000, flat 7500/1300, house 12500/2000 | `game_balance` |
| Mzdy | cleaner 300, courier 330, shop_assistant 350, part_timer 320, clerk 420, craftsman 520, engineer 780 kr/h; směny 8 h × 5/týden (part_timer 6 h × 3) | `game_balance` |
| Nelegální (abstraktní) | black_market_runner: 2500–6000/směnu, 3×/týden, odhalení 1,2 %/den, pokuta 150 %, pauza 14 d; smuggler_crew: 6000–16000, 2×/týden, 2,2 %/den, 200 %, 21 d | `game_balance` |
| Daně | pásma 8000/20000, sazby 0/15/28 %, flat 18 % | `game_balance` |
| Dluh | sazby 12/20/32 % ročně dle skóre (700/500/0), splátka 15 % min. 500 / 30 d, default po 3, start skóre 600, +5/−20/−150/+25/−30 | `game_balance` |
| Vynucování | bonus +25 % za záznam, strop 25 %/den, reziduální 0,4 %/den | `game_balance` |
| Tlak/chudoba | rezerva 30 d, saturace dluhu 200 %, saturace zmeškaných 6, váhy 450/300/250, práh chudoby 14 d, vysoký tlak ≥ 0,6 | `game_balance` |
| Sandbox politika | najímání 15 %/den, propouštění 0,1 %/den, 15 % agentů s nelegální prací od startu, půjčka při rezervě < 2 dny, dávka 4000/týden | `game_balance` |
| Počáteční stav | jmění 3000–40000, kapitál banky 3 000 000, 85 % agentů zaměstnaných | `game_balance` |

Poznámka k výsledkům: s výchozími hodnotami je nerovnost a chudoba v demu vysoká (např. Gini 0,5–0,8, chudoba 33–75 % ve 12 agentech/rok);
pokladna daně hromadí a rozdává jen malou dávku. To je důsledek ladění, ne zjištění o světě.

## 6. Rozhraní pro pozdější napojení na `sim_agent` (NEIMPLEMENTOVÁNO)

Jeden objekt `Economy` na domácnost/město (vlastní seed). `sim_agent` by volal:

```gdscript
var eco := Economy.new(seed, {})                  # jednou
eco.add_agent(agent_id, {"household": hid, "tier": "flat", "job": "clerk", "illegal": ""})
eco.run_day()                                     # jednou za herní den (po změně data v GameClock)
var v := eco.agent_view(agent_id)                 # {"financial_pressure": 0..1, "balance", "debt", "employed", "credit", "in_poverty", ...}
eco.financial_pressure(agent_id)                  # float 0..1 -> do StressModel/mental jako VSTUPNÍ tlak (nikdy přímo akce)
eco.assign_job(id, job) / eco.leave_job(id, job)  # volby agenta
eco.request_loan(id, amount) / eco.repay_loan(id, loan_id, amount)
eco.metrics() / eco.household_metrics()           # agregáty pro laboratoř
eco.to_dict() / Economy.from_dict(d)              # budoucí save (samostatná sekce, bez zásahu do stávajícího formátu)
```

Doporučení: pro napojení nastavit `{"auto_policy": false}` a rozhodnutí o práci/půjčce nechat na agentech. Mapování `financial_pressure` →
psychika (např. přídavek ke stresu) je samostatný, otevřeně zdokumentovaný krok; modul sám nic nespouští.

## 7. Demo a CSV pro laboratoř

```
godot --headless --path . res://tools/lab/economy_demo.tscn -- --seeds=1,2,3 --agents=8 --days=365 --out=/cesta/adresar
```
Zapíše `economy_seed<N>.csv` (sloupce `day,agent,balance,debt,financial_pressure,employed,illegal_active,credit,in_poverty`; `day` = konec dne 1..D),
`economy_summary.json` a vytiskne řádek `ECON seed=… hash=… gini=… poverty=… conservation=…`. 3 seedy × 8 agentů × 365 dní trvají ~2 s.

## 8. Testy

`tests/test_economy_core.tscn` (kniha, manipulace, daně, mzdy a povinnosti, půjčky, vynucování, tlak, metriky, serializace) a
`tests/test_economy_sim.tscn` (zachování peněz 365 dní pro 8/14/20 agentů a 5 seedů, burn a běh bez mintu, determinismus, obnova z JSONu uprostřed
běhu, demo CSV). Spuštění: `godot --headless --path . res://tests/<test>.tscn`.

## 9. Známé meze

- Jedna měna, žádné ceny na trhu, žádná nabídka/poptávka, inflace, nezaměstnanost ani mzdy se neustavují – jsou to pevné parametry.
- Zaměstnavatelé a banka jsou pasivní účty; podsvětní příjem je z účtu doplňovaného mintem.
- Politika agentů je schválně primitivní; skutečná rozhodnutí patří do `sim_agent`.
- Jedno `Economy` nesdílí účty s ostatními; převody mezi agenty jdou přes `transfer()`.
- Chudoba je absolutní (rezerva ve dnech výdajů); relativní prahy nejsou implementovány.
- Hash řetězec chrání proti nahodilé/lokální změně, ne proti útočníkovi s plnou kontrolou nad úložištěm.
