# Experiment 2 (M1c): vztahy × stresor, faktoriální 2×2

Jen v rámci modelu (fiktivní agenti, herní balance). Neříká nic o lidech.

## Oprava experimentu 1
`mental.support` v modelu mizí s časovou konstantou 6 h (`mental_state.gd:388`), takže `initial_support` po několika hodinách nic nedělá. Závěry experimentu 1 o „opoře“ tedy neplatí; to, co působilo, byly počáteční vztahy. Tento experiment je odděluje čistě.

## Návrh
- 8 klonů téže postavy (`identical8_household.json`), 12 seedů (201–212), 10 dní, snímky po 6 h.
- Faktor A: počáteční vztahy 0 vs 50. Faktor B: stresor +40 všem ve dni 3 (vs. žádný).
- Párování podle seedu, exaktní sign-flip test, 95% t-interval.

## Výsledky (hlavní efekty a interakce)
| metrika | vztahy | stresor | interakce |
|---|---|---|---|
| peak_stress | −5,4 [−9,4; −1,4] p=0,009 | +18,8 p=0,001 | 0,3 p=0,94 |
| mean_stress_post* | −0,9 | +10,2 | −1,8 [−3,1; −0,5] p=0,008 |
| final_stress | −1,2 p=0,11 | −0,2 p=0,82 | −1,1 p=0,48 |
| mean_mood | +0,8 [0,2; 1,4] p=0,008 | +0,3 p=0,15 | 0,4 p=0,32 |
| final_relationship | +34,2 (dané konstrukcí) | 0,3 | 0,4 |
| talks | +43,8 p=0,001 | −5,0 p=0,009 | 2,2 p=0,34 |
| argument_share | 0 | 0 | 0 |

## Interpretace (opatrně)
- Vyšší počáteční vztahy snížily špičku stresu po stresoru zhruba o 5 bodů (z ~54 na ~49 u stresovaných) a mírně zvedly průměrnou náladu. Efekt je malý, ale konzistentní přes seedy.
- Pufrování: u stresovaných buněk byl stres po zásahu nižší s vtahy (9,3 vs 11,1), p=0,008. Interakce u špičky ale chybí, takže „pufr“ je spíš mírné zrychlení doznívání než nižší nárazový vrchol.
- Po 10 dnech (final_stress, final_mood) se skupiny nelišily: model stres vždy vyrovná zpět.
- Počet hovorů roste s vztahy, podíl hádek se nemění.

## Omezení
- *mean_stress_post je u skupin bez stresoru 0 z konstrukce (není „po zásahu“). Hlavní efekt stresoru a interakce u této metriky jsou proto artefakt; platný je jen prostý rozdíl uvnitř stresovaných buněk (výše).
- Vztahy jsou nastavené ručně (final_relationship +34 je důsledek manipulace, ne nález).
- 12 seedů, jedna postava klonovaná 8×, jedno okno 10 dní, jedna velikost stresoru.
- Výsledek závisí na parametrech hry; nejde o validaci proti lidským datům.
