# Experiment 1 – nízká vs vysoká sociální opora (ilustrační, M1a/M1b)

Fiktivní agenti. Výsledky platí jen v rámci modelu `lab-m1a-0.1`; část parametrů je herní balance (viz EVIDENCE.md). Nejde o diagnostiku ani predikci lidí.

## Návrh
- 8 stejných agentů (jedna šablona, jen jména/uid se liší; rys „společenský"; bez předispozic), 14 dní, snímek každých 24 h.
- Podmínky se stejným seedem (párování), jinak shodné: **low** = `initial_support` 0,1 a počáteční přátelství 0; **high** = `initial_support` 0,8 a přátelství +50.
- 6 seedů (101–106) × 2 podmínky = 12 běhů, každý v samostatném procesu (`tools/lab/lab_cli.tscn`).
- Analýza: `tools/lab/analyze_experiment.py` – párový rozdíl, 95% interval (t), exaktní permutační test se záměnou znamének, dz. Surová data: `docs/lab/experiment_social_support_v1/`, souhrn `experiment_social_support_v1_analysis.json`.

## Výsledky (průměr přes 6 seedů)
| metrika | low | high | rozdíl (high−low) | 95% CI | p (flip) |
|---|---|---|---|---|---|
| střední stres (0–100) | 3,52 | 2,94 | −0,58 | −1,41…0,24 | 0,156 |
| konečný stres | 3,78 | 2,49 | −1,29 | −5,25…2,67 | 0,469 |
| podíl hodin se stresem ≥70 | 0,000 | 0,000 | 0 | – | – |
| střední nálada | 35,7 | 35,2 | −0,49 | −3,33…2,34 | 0,750 |
| střední přátelství | 28,5 | 67,5 | +39,0 | 38,3…39,7 | 0,031 |
| konečné přátelství | 51,7 | 81,3 | +29,6 | 28,4…30,7 | 0,031 |
| podíl hádek z rozhovorů | 4,7 % | 3,3 % | −1,4 p. b. | −2,1…−0,6 | 0,031 |
| počet rozhovorů | 571 | 625 | +54,5 | 42,5…66,5 | 0,031 |
| počet hádek | 27,0 | 20,8 | −6,2 | −10,6…−1,7 | 0,062 |

## Co z toho plyne a co ne
1. **Konflikt a kontakt se mění jedním směrem**: při vyšším počátečním přátelství jsou rozhovory častější a podíl hádek menší (malý, ale u všech 6 seedů stejným směrem; nejmenší možné p při 6 seedech je 0,031).
2. **Stres se nelišil průkazně.** Zde je **podlahový efekt**: stejní zdraví agenti žijí v domě bez stresorů, stres zůstává kolem 3–4 ze 100 a podíl hodin se stresem ≥ 70 je 0 v obou podmínkách. Experiment tedy *nemůže* ukázat tlumení stresu oporou; to by vyžadovalo stresor.
3. **Rozdíl ve vztazích je z velké části dán samotnou manipulací** (počáteční hodnota). Zajímavé je, že rozdíl se během 14 dní zmenšil (z 50 na ~30 bodů): model táhne vztahy k podobné úrovni. To je vlastnost modelu, ne zjištění o lidech.
4. **Manipulace spojuje dvě veličiny** (vnímaná opora a skutečné vztahy). Literatura (EVIDENCE.md, bod 1) rozlišuje vnímanou a přijatou oporu; tento návrh jejich příspěvky neodděluje.
5. Šest seedů je málo na jemné rozdíly; interval pro stres je široký.

## Další kroky (M1c)
- Přidat do scénáře **intervenci** (stresor v den N na vybraného agenta či všechny, bez sebepoškozujících obsahů) a opakovat; tím se stres dostane nad podlahu.
- **Faktoriální návrh**: oddělit `initial_support` a `initial_relationship` (4 podmínky).
- 20+ seedů, negativní kontrola (dvě shodné podmínky ⇒ rozdíl přesně 0; náhodné přiřazení štítků ⇒ rozdělení nulové hypotézy).
- Citlivostní analýza vybraných herních parametrů.
