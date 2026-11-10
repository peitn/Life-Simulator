# Experiment 3: ekonomika a burza → stres a nálada (párově podle seedu)

Jen v rámci modelu (fiktivní agenti, fiktivní ekonomika, herní balance). Neříká nic o lidech ani o reálných trzích.

## Otázka
Změní zapnutý most (`docs/economy_psyche_bridge.md`) stres a náladu agentů? A zvedne burzovní krach stres a zhorší náladu víc než klidný trh?

## Návrh
- 8 klonů téže postavy (`tools/lab/experiments/identical8_household.json`), 12 seedů (301–312, zvoleno předem, žádný nebyl vyřazen), 10 dní, snímky po 6 h.
- Tři ramena na seed: `e0` bez ekonomiky; `calm` ekonomika + burza bez šoku; `crash` ekonomika + burza + krach −30 % za 3 dny od dne 3 (projeví se od herního dne 4).
- Párování podle seedu. Kontrasty: **eko** = calm − e0, **krach** = crash − calm. Exaktní sign-flip test (2^12), 95% t-interval, Holmova korekce přes metriky v rámci kontrastu.
- Metriky z okna po šoku (den > 3, stejné okno ve všech ramenech): největší stres kteréhokoli agenta (`post_peak_stress`), průměrný stres a nálada, podíl stresu ≥ 70, poslední snímek, podíl hádek, součet vstupů stresu z mostu (`stress_inputs`).
- Spuštění: `tools/lab/run_economy_experiment.py <godot> <out>`, analýza `tools/lab/analyze_economy.py <out>`. Data: `docs/lab/experiment_economy_psyche_v1_analysis.json`, per-běh metriky `docs/lab/experiment_economy_psyche_v1_runs.csv` (surové výstupy, ~11 MB, nejsou v repozitáři).

## Výsledky (průměr rozdílu na seed [95% CI], p sign-flip nekorigované)
| metrika | eko = calm − e0 | krach = crash − calm |
|---|---|---|
| post_peak_stress | +0,53 [−2,74; 3,79] p=0,56 | −0,42 [−4,05; 3,20] p=0,81 |
| post_mean_stress | +0,24 [−0,34; 0,83] p=0,35 | −0,02 [−0,82; 0,79] p=0,97 |
| post_high_share | 0 (nikdo ≥ 70) | 0 |
| post_mean_mood | −0,36 [−0,82; 0,09] p=0,049 (Holm 0,34) | −0,10 [−0,34; 0,15] p=0,41 |
| final_stress | +0,62 [−0,76; 2,00] p=0,32 | −0,88 [−3,29; 1,52] p=0,53 |
| final_mood | −3,20 [−7,93; 1,52] p=0,19 | +2,02 [−1,66; 5,69] p=0,28 |
| argument_share | +0,003 p=0,125 | −0,003 p=0,06 |
| stress_inputs (vstup mostu) | +7,5 [4,1; 10,8] p=0,001 | +25,1 [15,1; 35,1] p=0,001 (Holm 0,008) |

Průměry ramen e0 / calm / crash: post_peak_stress 42,2 / 42,8 / 42,3; post_mean_stress 9,16 / 9,40 / 9,39; post_mean_mood 33,4 / 33,0 / 32,9; stress_inputs 0 / 7,5 / 32,5.

## Interpretace (opatrně)
- Mechanismus funguje: krach zvedl součet vstupů stresu z mostu více než čtyřnásobně proti klidu (32,5 vs 7,5 bodů za 10 dní přes 8 agentů; kladný rozdíl v 11 z 12 seedů) a je to jediný efekt, který přežil korekci.
- **Dopad na měřený stres a náladu agentů jsme nezjistili**: žádný z kontrastů krach nebo eko není po Holmově korekci významný a intervaly jsou široké (včetně nuly ve všech metrikách). Jediný nominálně významný údaj (`post_mean_mood` eko, p=0,049) po korekci nevydrží; směr (nálada −0,36, 11 z 12 seedů záporně) je slabý náznak z chronické složky, ne zjištění.
- Pravděpodobné důvody (hypotézy, neověřeno): dávka stresu je malá (denní strop 8 bodů, typicky jednotky bodů a jen pro agenty s portfoliem), model psychiky stres rychle vyrovnává (v experimentu 2 se skupiny po 10 dnech nelišily), a zapnutí mostu mění tok náhodných čísel postav, takže šum mezi ramena je srovnatelný s efektem. Že by efekt neexistoval, z toho nevyplývá; experiment má na tak malý efekt nízkou citlivost.
- Žádný podíl stresu ≥ 70 nevznikl: špičky ~42 pocházejí z existující dynamiky, ne z mostu.

## Omezení
- Jen model a `game_balance`; všechny prahy a váhy mostu jsou odhad pro hratelnost. Nic není kalibrováno ani validováno proti lidským datům.
- Malý vzorek: 12 seedů, jedna postava klonovaná 8×, jedno okno 10 dní, jedna velikost a tvar krachu, výchozí `BALANCE` bez ladění. Silnější nastavení nebylo zkoušeno (zkoušet je po výsledku by bylo vybírání parametrů; patří do nového, předem zadaného experimentu).
- Klony mají v ekonomice různé náhodné jmění, profily a práci (id = jméno), takže expozice vůči burze se liší; část agentů krach vůbec nepocítí (nemají akcie).
- Efekt na chování (výběr akcí) nebyl měřen; sledovali jsme jen stres, náladu a podíl hádek.
- `mean_stress_post` z `summary` runneru je v ramenech bez šoku 0 z konstrukce; proto analýza počítá okno po šoku ze snímků sama.
