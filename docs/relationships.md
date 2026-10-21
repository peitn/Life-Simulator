# Relationships

## Relationship values

Every pair of characters has a relationship from −100 to 100 with labels such as acquaintance, friend,
close friend or enemy. The labels are grammatically gendered in Czech. Memories record strong
experiences.

## Social interactions

- **Chat** has a chance of turning into an argument. The chance depends on trait chemistry, both moods,
  friendship, stress, bad emotions (angry, tired, tense) and the hot-headed trait.
- **Insult** is player-only and has lasting consequences. After an insult from the same person, the victim
  ignores further insults for a while and walks away, which protects against griefing.
- **Confiding**: the listener either listens or brushes it off.
- **Help during a panic attack** versus **stigma** from witnesses.
- **Jealousy** fires at most once per 4 hours per rival.

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

## Known issue: the household "cold war"

In long simulations the default household drifts into constant arguing. Relationships fall to around −45
after a week, and the characters avoid each other.

The headless FCCS experiments (`--test 14 --fccs`, October 2026) explored fixes:
- **Balancing** the asymmetry of gains versus losses (the main cause);
- **shared moments** such as watching a film or cooking together;
- slow **drift** of relationships without grudges;
- realistic **household frictions** (noise, bathroom, dishes);
- **mood**: random life events, mood shifting conflict odds by up to ±20 pp, and de-escalation by a
  listener in a good mood.

Results:
- Fights fell from a spiral to 24–50 % of conversations, with differentiated relationships: one close
  friendship, one strained relationship and one neutral.
- Fights by mood were 16–39 % in a good mood, 33–59 % in a neutral mood and 67–73 % in a bad mood.

These mechanisms are to be moved into the game with a test across 10 seeds.

## Planned

- Rivalry, manipulation, gossip, infidelity, break-ups.
- Romance with fade-to-black.
- Support versus toxicity.
- Neighbours.
- Worldview axes and "who knows what about whom", with coming out as an optional, contextual process.
