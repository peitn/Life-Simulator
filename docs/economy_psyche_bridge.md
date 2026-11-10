# Most ekonomika/burza → psychika agentů (opt-in, výchozí VYPNUTO)

Stav: implementováno jako tenká vrstva `scripts/sim/economy_bridge.gd`. Napojuje izolovanou **fiktivní** ekonomiku (`docs/economy.md`)
a fiktivní burzu (`docs/economy_market.md`, bod 8 návrhu) na **existující** vstupy psychiky: `mental.on_stressor("life", …)` a moodlet.
Nepřidává žádný nový model psychiky ani žádný globální stav.

> **Platnost a meze (čti první).** Je to mechanismové pískoviště nad vymyšlenými daty. Všechny prahy a váhy jsou `game_balance`
> (nic není `empirical_anchor`, nic nebylo kalibrováno na reálná data ani ověřeno proti literatuře o finančním stresu).
> Výsledky experimentu v `docs/lab/EXPERIMENT_economy_psyche_v1.md` platí jen v rámci modelu.

## 1. Zákonnost a bezpečnost (pevná pravidla)

- Finanční tíseň **nikdy** nevybírá, nespouští ani nevynucuje žádnou akci (ani nelegální, ani násilnou, ani sebepoškozování). Most akce
  vůbec nezná: vrací jen čísla `stress`, `mood`, `mood_minutes`. Test `test_economy_bridge` to hlídá (kód mostu neobsahuje žádný příkaz/akci,
  `HouseholdDynamics._economy_day` volá jen `mental.on_stressor("life", …)` a `mood.add_moodlet`, knihovna akcí nemá žádnou nelegální/násilnou akci).
- Ekonomika je fiktivní (krejcary, tickery „-G“). Žádná reálná data ani návody.
- Výchozí ekonomika mostu má `illegal_share_bp = 0`: žádný agent nezačíná s (abstraktní) nelegální prací.
- Dopad je ohraničený: tvrdý strop denní dávky stresu (`stress_dose_cap`), strop moodletu (`mood_cap`), strop starosti (`acute_cap`) a měkký strop
  stresu uvnitř `MentalState.on_stressor` (`stress_gain_factor` nad 70). Žádná zpětná vazba psychiky do ekonomiky (nevzniká spirála).
- **Nepřímý kanál (poctivě):** vyšší stres/horší nálada vstupují do *existujících* modelů (např. výběr utěch, závislostní akce za existujícími
  branami `psyche_gate`, hádky). Most je nemění a nic nevynucuje, ale stres je jejich existující vstup, takže nepřímý vliv na chování nelze
  vyloučit. Tento nepřímý efekt tu **nebyl měřen** (viz bod 7).

## 2. Jak zapnout

Výchozí stav je vypnuto: bez instance mostu je hra bit-for-bit shodná (ověřeno hashem z kódu před mostem, viz testy).

| Cesta | Jak |
|---|---|
| příkazový řádek | `godot --path . -- --economy-psyche` (výchozí `BALANCE`) |
| `net_config` světa (testy, nástroje) | `{"economy_psyche": true}` nebo `{"economy_psyche": {přepisy BALANCE}}`; neplatná konfigurace → most zůstane vypnutý + varování |
| laboratoř | blok `economy` ve scénáři (bod 6) |
| programově | `world.dynamics.economy_bridge = EconomyBridge.new({...})` |

V GUI (`GameSettings`) přepínač zatím **není** (nastavení jsou obsah/prezentace; nechtěli jsme měnit jejich seznam klíčů ani testy).

## 3. Rozhraní

`economy_bridge.gd` (`RefCounted`, čistě data dovnitř/ven; nezná uzly ani `SimAgent`):

| Člen | Význam |
|---|---|
| `EconomyBridge.new(cfg)` | `cfg` přepisuje `BALANCE`; vytvoří `Economy` (seed `cfg.seed`) a volitelně burzu (`market: true`, `events`) |
| `step_day(game_day, sim_names) -> Dictionary` | volat při každém průchodu; první volání jen ukotví den; při novém dni posune ekonomiku (max `max_catchup_days`) a vrátí `{sim_name: {stress, mood, mood_minutes}}` jen pro agenty s nenulovým vstupem |
| `view(sim_name)` | jen čtení: `pressure`, `worry`, `balance`, `portfolio_value` |
| `to_dict()` / `from_dict(d)` | uložení/obnova (neplatné → `null`) |
| `validate_config(cfg)` | pole chyb, prázdné = platné |

Mapování agent → ekonomika: `sim_name` → id `sim:<sim_name>`; agenti se registrují při prvním spatření (v pořadí `sims`), max. 64. Ekonomika má vlastní RNG
(`Economy.rng`); RNG postav se nepoužívá, takže zapnutí mostu mění průběh jen přes samotné vstupy stresu/nálady.

Aplikace (`HouseholdDynamics._economy_day`, volá se z `advance()` jen když `economy_bridge != null`): `s.mental.on_stressor("life", stress, s.mental_cfg())`,
moodlet `financni_starost` („Starosti o peníze“, emoce `smutny`, síla ≤ 0, trvání `mood_minutes`; denně se nahradí). Kind `"life"` je existující druh
(stejný jako životní události); zdroj stresu se tak ve `stress_sources` hlásí jako `life`.

## 4. Mapování (denně, po `Economy.run_day()`)

```
fp      = financial_pressure(id)                         # 0..1, docs/economy.md bod 4
excess  = clamp((fp − pressure_floor) / (1 − pressure_floor), 0, 1)
stress  = excess · chronic_stress_per_day                # chronický finanční stres
mood    = excess · mood_per_pressure
worry   = worry · 0.5^(1/acute_half_life_days)           # doznívání
pokud pokles časově váženého indexu portfolia (idx_hist, očištěno od nákupů/prodejů):  loss = (idx_prev − idx)/idx_prev
  worry += loss · equity_share · acute_gain              # equity_share = podíl akcií na likvidním majetku (agent_view().market.equity_share_pm)
  stress += loss · equity_share · acute_impulse · 100    # jednorázový náraz v den poklesu
worry   = clamp(worry, 0, acute_cap)
stress += worry · acute_stress_per_day ;  mood += worry · mood_per_worry
stress  = clamp(stress, 0, stress_dose_cap) ; mood = clamp(mood, mood_cap, 0)
```

Návrh z `docs/economy_market.md` bod 8 je naplněn takto: (1) malý, časově doznívající přídavek úměrný poklesu × podílu akcií, se stropem a poločasem;
(2) papírový pokles **nemění** `financial_pressure` (ten se nemění vůbec, most ho jen čte); (3) žádná škodlivá akce, strop dopadu; (4) vlastnosti profilu
(impulzivita, averze ke ztrátě) stres zatím **nenásobí** (hypotéza zůstává otevřená). Zisky (růst indexu) starost nezvyšují ani aktivně nesnižují
(jen doznívání) a nevyvolávají pozitivní nálady, aby se nepřidával druhý, neověřený směr.

## 5. Parametry `BALANCE` (všechny `game_balance`, jediné místo v `economy_bridge.gd`)

| Klíč | Výchozí | Význam |
|---|---|---|
| `seed` | 1 | seed ekonomiky a burzy |
| `market` | false | zapnout fiktivní burzu |
| `events` | [] | události burzy (`path`, `vol`, `div_cut`, `rates`, `layoffs`); den = den ekonomiky |
| `economy` | jmění 20 000–120 000 kr, `illegal_share_bp` 0 | přepisy `Economy.DEFAULT_CONFIG` (běžné jmění 3 000–40 000 kr nechá většinu agentů mimo burzu) |
| `max_catchup_days` | 3 | kolik dnů ekonomiky se nejvýš dožene při skoku času |
| `pressure_floor` | 0,30 | pod touto úrovní tlaku žádný chronický stres |
| `chronic_stress_per_day` | 4,0 | body stresu/den při tlaku 1,0 |
| `acute_gain` | 4,0 | přírůstek starosti = ztráta × podíl akcií × gain |
| `acute_half_life_days` | 12 | poločas doznívání starosti |
| `acute_cap` | 1,0 | strop starosti |
| `acute_stress_per_day` | 5,0 | stres/den při starosti 1,0 |
| `acute_impulse` | 0,6 | jednorázový náraz v den poklesu (ztráta × podíl × 0,6 × 100 bodů) |
| `stress_dose_cap` | 8,0 | tvrdý strop denní dávky stresu |
| `mood_per_pressure` / `mood_per_worry` | −6,0 / −5,0 | síla moodletu |
| `mood_cap` | −10,0 | nejhlubší moodlet z peněz |
| `mood_minutes` | 1440 | trvání moodletu |

`validate_config` hlídá typ, konečnost a rozsah každého klíče (např. kladná síla moodletu je neplatná: most nálady jen snižuje).

## 6. Uložení a laboratoř

- **Save**: `GameSave.capture` přidá sekci `economy` (`bridge.to_dict()`) **jen když je most zapnutý**; vypnuto = stejné klíče nejvyšší úrovně jako dřív
  (test). `apply`: sekce přítomná → obnoví se; chybí/poškozená a most byl zapnutý → čerstvý most se stejnou konfigurací; starý save s vypnutým mostem se načte
  beze změny. Uložení je binární (`var_to_bytes`), obnova je bit-přesná. **Pozor:** JSON text v Godotu není u desetinných čísel bit-přesný
  (rozdíl v ~16. cifře), proto se stav mostu nemá ukládat přes JSON text; GameSave to nedělá.
- Do saveu se ukládá celá kniha ekonomiky (hash řetězec), která s časem lineárně roste. Změřeno (8 agentů s burzou, `var_to_bytes` sekce `economy`):
  den 31 ≈ 0,28 MB, den 91 ≈ 0,78 MB, den 181 ≈ 1,41 MB, den 365 ≈ 2,83 MB (7 590 záznamů). Limit `GameSave.MAX_BYTES` je 8 MB na celý save, takže
  při zapnutém mostu a 8 agentech hrozí překročení řádově po 2–2,5 letech herního času (odhad extrapolací; **neověřeno**, a nutno připočíst zbytek savu).
  Ořezávání/komprimace knihy není implementováno.
- **Laboratoř** (`tools/lab/lab_runner.gd`): volitelný blok `economy: {enabled, market, seed, shock: {day, total_pm, days}}`
  (`shock` = plošný pokles cen burzy `path`, vyžaduje `enabled` i `market`; `total_pm` −999..0; `days` 1..30; `day` 1..days). Bez bloku (nebo s `enabled:false`)
  je výsledek **bit-for-bit** shodný (`final_hash`, snímky, žádné nové klíče). Zapnuto: snímky nesou `economy: {pressure, worry, portfolio_value}` a výsledek `economy.stats`.
  Den ekonomiky *d* se projeví na začátku herního dne *d+1*.

## 7. Co zůstává neověřené / omezení

- Vše je `game_balance`; žádná validace proti datům o lidech. Velikosti efektů jsou důsledkem ladění, ne zjištění o světě.
- Nepřímý vliv zvýšeného stresu/nálady na výběr akcí (utěchy, závislostní akce za branami, hádky) přes existující modely **nebyl měřen** ani omezen.
- Sdílená burza: agenti ve hře jsou málo (3–8), takže „podíl agentů s portfoliem“ je malý a závisí na seedu a jménech (id = jméno → hash vlastností).
  Část agentů nemá žádnou expozici a na krach nereaguje.
- Žádné GUI: hráč nevidí `view()`; chybí přepínač v Nastavení; chybí HUD řádek o financích.
- Žádný vliv psychiky na ekonomiku (agent se nerozhoduje o práci, půjčce ani obchodech podle nálady) – ekonomika běží vlastní sandbox politikou (`auto_policy`).
- Zisky ani růst bohatství nezlepšují náladu. Impulzivita/averze ke ztrátě profilu stres nenásobí.
- `ServerWorldStore`/dedikovaný server: most se ukládá přes stejný `GameSave.capture`, ale **multiplayer cesta nebyla zvlášť testována**; při selhání obnovy
  světa serveru (`main.gd`, nová domácnost) se most nepřenáší.
- Velikost saveu: kniha roste lineárně (viz bod 6); ořezávání není, v dlouhých hrách může save překročit `MAX_BYTES`.
- Vstupy se aplikují při přechodu dne (po půlnoci herního času), ne při reálné události; „živý“ šok během dne se neprojeví do dalšího rána.

## 8. Testy

`tests/test_economy_bridge.tscn` (viz `docs/testing.md`): validace konfigurace, ohraničenost/konečnost (90 dní, extrémní konfigurace), krach vs klid (20 seedů),
doznívání, uložení/obnova (JSON i binárně), žádné akce, validace laboratorního bloku, hash vypnutého stavu proti kódu před mostem, determinismus zapnutého stavu,
drát do `HouseholdDynamics` (stub), extrémní chudoba ve skutečné domácnosti, `GameSave` round-trip, starý save, poškozená sekce, formát savu při vypnutí.
Experiment: `docs/lab/EXPERIMENT_economy_psyche_v1.md` (`tools/lab/run_economy_experiment.py`, `tools/lab/analyze_economy.py`).
