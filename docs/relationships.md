# Relationships

## Relationship values

Every pair of characters has a relationship from −100 to 100 with labels such as acquaintance, friend,
close friend or enemy. The labels are grammatically gendered in Czech. Memories record strong
experiences.

When a relationship crosses a level, the memory text now depends on the direction and the level
(`SimAgent.note_relationship_change`): "X is now my friend", "X is no longer my enemy" (improvement from
hostility), "relationship cooled: X is no longer my best friend" (a friendship weakening) and "relationship
got worse: X is now my enemy". The same helper is used for chats, arguments, insults, confiding, support,
apologies and shared moments. This fixes the old text "relationship got worse: X is now my close friend".

## Social interactions

- **Chat** has a chance of turning into an argument (`SimAgent.talk_success_chance`, clamped to 8–92 %):
  - base 0.65 for two neutral people at rest;
  - trait chemistry of both;
  - **mood of both**: the average mood shifts the chance by at most ±20 percentage points;
  - friendship (relationship / 300);
  - stress above 35 for each person ((stress − 35) / 320);
  - the hot-headed trait (`argue_bias`);
  - the dominant emotion of each person: angry −0.12, tired or tense −0.06 (tired or nervous people are
    curt rather than hostile);
  - a pending **complaint** from a household friction (−0.08).
- **De-escalation**: if a chat is about to turn into an argument, a listener in a good mood may defuse it
  with a calm reply. The chance grows linearly from 0 at mood 20 to 35 % at mood 50 and never goes higher.
- **Insult** is player-only and has lasting consequences. After an insult from the same person, the victim
  ignores further insults for a while and walks away, which protects against griefing.
- **Confiding**: the listener either listens or brushes it off.
- **Help during a panic attack** versus **stigma** from witnesses.
- **Jealousy** fires at most once per 4 hours per rival.

Every ordinary chat emits `SimAgent.conversation(sim, partner, info)` with `success`, `avg_mood`,
`complaint`, `deescalated` and `p`. It is emitted only on the authority (server or offline).

### Balancing gains and losses

Earlier, an argument cost its full nominal value while a pleasant chat gained little (diminishing returns,
×0.35 for a repeat within three hours, grudges). At roughly 30 % arguments relationships had to fall: the
household drifted into a "cold war" (−41 to −61 after 14 days, about 400 minutes of stress above 85). Now:

- an argument changes the relationship by ×0.6 of its nominal value;
- a repeat chat within 3 hours counts ×0.7 (was ×0.35);
- arguments add stress with a **soft ceiling**: above (cap − 25) each argument adds less, down to ×0.15.
  The cap is 85 by default and 65 for the hot-headed trait (`argue_stress_cap`): they flare up quickly but
  the anger does not turn into chronic stress.
- Negative relationships without a live grudge drift back towards zero: exponentially (about 10 days) plus
  2 points per day. A live grudge still blocks healing, so apologies keep their purpose.

## Household dynamics (`household_dynamics.gd`)

Life under one roof is more than conversations. `HouseholdDynamics` runs every 10 game minutes, only on
the authority. All randomness goes through the characters' own RNGs, so a run is deterministic for a
given seed. Every value is a named constant with a comment.

- **Frictions** that do not depend on a conversation:
  - noise at night (22:00–06:00): someone sleeps and another person within 9 m watches TV, works out or
    cooks;
  - an occupied bathroom when your hygiene is below 40;
  - dishes left after cooking (only after at least 20 minutes of real cooking, so a cancelled "cook"
    command cannot be used for griefing).

  The base chance per check is 25 / 20 / 12 %, multiplied by the trait parameter `irritability` (tidy,
  grumpy, hot-headed and anxious ×1.4; lazy and optimist ×0.7). There is a cooldown per pair and topic
  (6 / 6 / 12 hours). A friction adds stress (+3 × stress gain), a small grudge (+2), a mood penalty and a
  **complaint** that colours the next conversation with that person for up to 6 hours. The complaint is
  spoken aloud. If the chat goes well ("yeah, sorry, I'll sort it"), the grudge softens; if not, it becomes
  an argument.
- **Shared moments**: two characters on the sofa or at the TV within 4 m ("a film together"), or cooking
  side by side. Each gets +2 relationship × `warmth_mult` (a live grudge dampens it), the grudge softens by
  2, a mood boost, and it counts as contact. There is a 4-hour cooldown per pair. With a grudge above 60
  (either side) nothing happens: you do not bond with someone you are furious with.
- **Life events** from outside the home (a boss's praise, an electricity bill, a message from an ex): about
  once a day per character, never during sleep, half good and half bad, ±7–13 mood for 4–8 hours. Bad
  events also add a little stress.
- **Neglect**: a positive relationship with no contact for more than 3 days slowly fades towards 25
  (about a month). Old friends are not lost completely.

### Measured result (run 15, `tests/test_household_dynamics.gd`)

The starting household over 16 seeds × 14 days:

| Metric | Before (run 14 state) | After |
|---|---|---|
| Arguments per conversation | not counted then; one interim run (new mood term, old weights) gave 80 % | 32.0 % mean, SD 10.4 pp, range 17–54 % |
| Relationships after 14 days | −41 to −61 (all hostile) | mean +25.6, range −50 to +100; pairs differ (pair SD 50) |
| Arguments by mood (good / mid / bad) | – | 21 % / 42 % / 72 % |
| Time with stress above 85 | ~400 min per person | mean 0.01 %, worst 0.42 % |
| Critical needs | 0 | 0 |

The personalities shape the stories: Jana and Eliška usually end up close friends, Petr (lazy, grumpy,
hot-headed) is in a strained or neutral relationship with them, and some seeds are calmer or worse. No seed
ends with every relationship below −30 or above +60.

The calibration is sensitive: a small change in the order of random draws moves individual seeds by
10–20 percentage points. That is why the test uses 16 seeds and checks the mean and the spread rather
than one run.

### The FCCS experiment

The headless FCCS experiments (`--test 14 --fccs`, October 2026) found these mechanisms first.
`fccs_oracle.gd` is now only an optional modulator of the conversation outcome: it blends the game's
probability with the FCCS brain's reaction to an opening line, including the complaint line. It needs
an external service and is not deterministic, so it is never used in multiplayer or in the game's tests.

## Grudges, guilt and apologies (`rel_ledger.gd`)

The relationship value says how much people like each other. The **grudge** says what is still hanging
between them.

- A grudge slows the warming of a relationship: a pleasant chat helps less until the grudge fades or an
  apology closes it.
- **Guilt** leads to an apology, or to private remorse that nobody sees.
- **Sincerity is derived from behaviour, not text.** It depends on how many apologies came recently and
  whether new hurt followed the previous apology ("sorry… and again"). Apologies cannot be farmed or used
  for griefing.
- The outcome is accept, "we'll see" or reject. The AI apologises out of guilt. Pride (grumpy and cynic
  traits) dampens it, with a 12-hour cooldown.
- Time heals only negative relationships with no live grudge.

## Planned

- Rivalry, manipulation, gossip, infidelity, break-ups.
- Romance with fade-to-black.
- Support versus toxicity.
- Neighbours.
- Worldview axes and "who knows what about whom", with coming out as an optional, contextual process.
- Household dynamics in multiplayer: a per-player opt-out from being the target of frictions, and spatial
  filtering when lots hold many characters (the pair check is O(n²) per 10 game minutes).

## Crowded households (tuning of 23 October 2026)

A stress test with 7 characters for 30 game days collapsed: 5 of 7 ended in a permanent depressive episode, 68 % of
conversations were arguments and there were 573 noise frictions. Control runs showed the cause was the scaling of social
systems with the number of people (pair-wise frictions and shared moments grow with n²), not the illnesses or the furniture:
7 healthy characters collapsed too, and 4 extra beds did not help. The tuning (`sensory_profile.gd` and changes in
`household_dynamics.gd`, `sim_agent.gd`, `mental_state.gd`, `depression.gd`, `utility_planner.gd`, `action_library.gd`):

- **Individual sensitivities** (`SensoryProfile`, deterministic from traits, predispositions and the character's seed, never
  from the name): noise sensitivity (a lazy sleeper sleeps through anything, an anxious one wakes up), crowd sensitivity
  (a loner is drained, a sociable person barely notices), joy sensitivity, light sensitivity and an **anticipation
  threshold**. Characters get used to noise and crowds over time (habituation, max 0.7, fades over ~10 days).
- **Noise:** probability × sensitivity × (1 − habituation) × distance fall-off²; one sleeper is annoyed by noise at most once
  per cooldown, however many sources there are.
- **Daily patience:** after two frictions in a day, further ones weigh less (1, 1, 0.5, 0.33 …).
- **Crowds:** stress per extra person × crowd sensitivity; a liked person (relationship > 30) counts half. Since run 23,
  only while awake (sleeping next to others is not crowd stress).
- **Shared moments:** at most one per person per 2 hours (a film with 7 people no longer creates 21 moments at once).
- **Joy capacity:** pleasant moodlets (a nice conversation, shared moments, good news, being listened to, reconciliation,
  new **morning light**) scale with `joy_sens × liking × (1 − 0.45 × high-stress share)`; too weak a joy is not felt at all.
- **Anticipation threshold:** expected pleasure must exceed a personal threshold to motivate fully (low for optimists and
  playful characters, high for cynics and grumps); pessimism and stress raise it. Nothing ever drops to zero.
- **The body comes first:** at critical hunger (< 15) or exhaustion (< 12) everything that does not address it loses most of
  its appeal. This fixed a loop of “fall asleep → hunger wakes me → TV → sleep again”.
- **Emergency sleep** (`sleep_floor`, “sleeps in the armchair”) when beds and the sofa are taken; worse than the sofa.

Measured (local Godot 4.7.2, 30 days, 4 seeds per household): 3-person household arguments 18–29 %, all moods positive;
7 healthy characters arguments 16–24 %, nobody collapses; 7 characters with predispositions arguments 14–23 %, the severe
cases have episodes **with recovery** (no saturation), panic attacks 0–2 per month, at most ~1 drink a day.
