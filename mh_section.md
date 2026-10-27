
## Withdrawal and conflict avoidance (27 October 2026)

Two follow-ups to Grok's review (#169) of the severity range: severe depression now visibly changes behaviour, not just
the HUD label, and a stressed household gets a way out of escalating frictions.

**Withdrawal (`Depression.withdrawal()`, 0..0.35).** The value is 0 / 0.06 / 0.16 / 0.30 for no / mild / moderate /
severe episode, plus a small part from the burden itself. It shifts preferences only; nothing is ever forbidden:
- ordinary social actions are less appealing (× (1 − w));
- confiding is affected less (× (1 − 0.4 w)), so the path to support stays open;
- demanding chores (exercise, repairs, cooking) × (1 − 0.5 w);
- quiet activities and hiding under the duvet become more appealing (× (1 + w)).

A severe episode also dampens joy from favourite things beyond what the burden alone does
(`joy_severity_mult()`: 1 / 1 / 0.9 / 0.75 applied to `SimAgent.joy_capacity()`).

**Conflict avoidance (`MentalState.avoidance()`, 0..0.7).** It is high stress (above 55) plus withdrawal. With the
mental-health topics turned off only the stress part remains. Two effects:
- *Avoiding the person.* When choosing a social target, a character avoids the person they are sore at (a grudge or a
  fresh complaint): `UtilityPlanner.avoidance_weight()` lowers the score by up to the avoidance value. Apologies and the
  pressure actions keep their own rules.
- *Swallowing a complaint.* When a conversation would start with a complaint, the character sometimes keeps it to
  themselves (probability 0.6 × avoidance), so the talk does not turn into an argument. This is not free: rumination
  rises and the mood entry "Radši jsem mlčel(a)" ("I'd rather have kept quiet") appears.

The default healthy 3-person household is unaffected (identical argument rates in all 16 seeds of
`test_household_dynamics`); the effects show only under stress or depression.

Tests: `tests/test_withdrawal_avoidance.gd` (22 checks).
