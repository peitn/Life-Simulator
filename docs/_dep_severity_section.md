
## Severity range of depressive episodes (23 October 2026)

A depressive episode is no longer a single state. It has three severities, shown only in words, never as numbers:

| Severity | HUD label | When |
|---|---|---|
| Mild | Mírná depresivní epizoda | Every episode starts here (burden above 0.6 for 2 game days) |
| Moderate | Středně těžká depresivní epizoda | Burden above 0.70; drops back below 0.64 |
| Severe | Těžká depresivní epizoda | Burden above 0.85 for at least one game day; drops back below 0.79 |

The bands use hysteresis, so the label does not flip back and forth near a boundary.

**Vulnerability decides how deep an episode can go.** Burden growth slows near a soft ceiling of
`0.72 + 0.28 × vulnerability`:
- a character with no predisposition reaches at most a mild episode, even under long stress and isolation;
- moderate predisposition leads to moderate episodes;
- strong predisposition (or the scar left by earlier episodes) can lead to severe ones.

Large life events (`on_event`) can still push anyone past the ceiling.

**Effects scale with severity:**
- Burden already drives anhedonia, pessimism, low vigour, fatigue and poor sleep.
- A moderate episode adds the mood entry "Všechno je těžké".
- A severe episode adds "Sotva zvládám den", plus extra fatigue, worse sleep and a stronger pull to bed and sofa.

**Recovery:**
- Recovery is faster from a mild episode (×1.15) and slower from a severe one (×0.75), but always possible.
- The scar after an episode is `0.03 + 0.02 × peak severity` and fades over time.
- Episodes are counted by peak severity (`severity_counts`), which is saved and validated on load.

With the mental-health topics turned off there are still no episodes and no diagnostic names, only "Skleslost" or "Sklíčenost".

Tests: `test_depression` section "Rozpětí deprese" (13 checks) covers:
- the three predisposition levels and the label;
- the mood entry and the stronger effects;
- the delayed onset of severe episodes and the hysteresis;
- recovery and scar by severity, and save/load including garbage input.
