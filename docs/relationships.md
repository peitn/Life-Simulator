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


## Individual attachment and emotional dependency (24 October 2026)

**Implemented in `RelLedger`**: the legacy public liking score (−100..+100)
is NOT synonymous with the importance of the relationship. A private,
direction-specific `attachments[other_name]` entry stores two separate
0..1 values: `importance` ("how much this specific person matters") and
`dependency` ("how much acceptance/presence of this person affects
emotional stability"). `set_attachment(who, importance, dependency)`
validates inputs, `attachment_to(who, liking)` returns the actual
reaction weight, and `attachment_label(...)` offers a human-friendly
private description. The source-of-truth is the same ledger used for
grudges and guilt; to_dict/from_dict preserve bonds, with compatibility
for older saves without this field.

When no explicit bond exists, **importance derives gradually from positive
liking but dependency defaults to zero**. Thus affection does not imply
dependency; an intensely dependent character can still experience negative
or ambivalent liking toward someone. The impact is directional: A's
attachment to B need not equal B's attachment to A. Rejected apology,
being insulted, dismissal while seeking support and ambiguous
interpretations after a chat use that specific relationship's impact
in `SimAgent._on_rejection_cue`. Perceived rejection remains subjective,
not proof of the other character's intentions. The existing independent
`rejection_reactivity` slider sets temperament, not identity or diagnosis.

Offline HUD relationship labels now append the private bond description.
Multiplayer `net_detail` has deliberately **not** been changed to send
attachment maps; proper owner-only transport/editor sliders per relationship
are a separate future task. No FCCS involvement. New test suite:
`tests/test_attachment_sensitive_scene.tscn`.


## Gossip and rumours (9 November 2026)

`scripts/sim/gossip_network.gd` models who knows what about whom, who told whom and how much each person
believes it. It runs only on the authority (offline or server) and is saved with the household.

- **Sources.** True rumours come only from witnessed events: an argument or insult seen by a bystander, a panic
  attack seen by others, repeated drinking, and help received (a positive rumour). Invented rumours ("talks
  about you behind your back", "takes other people's things") appear only when a character with low HEXACO
  honesty holds a strong grudge (≥ 35) against a third person.
- **Belief.** belief = trust in the teller × plausibility (listeners who like the subject believe less) ×
  (1 − 0.3 · distortion) × the teller's own belief. A second independent source combines as
  1 − (1 − a)(1 − 0.8 b). Each retelling adds distortion (more for dishonest tellers) and inflates perceived
  severity, so weak chains die out after two or three hops unless people trust each other.
- **Effect.** Only the *increase* in belief changes the listener's opinion of the subject, capped at 12 points
  per listener–subject pair per day; teller–listener bonding is capped at 3 points per day.
- **Exposure.** A friend of the subject (relationship ≥ 20) may tell them what is being said. The subject learns
  the immediate source (the originator only if it is the same person) and loses trust in them: grudge,
  humiliation trace, stress and a mood hit (shame for true rumours, anger for lies). The informer believes a
  denied lie less.
- **Debunking and forgetting.** A good conversation with the subject weakens belief (lies faster than truths);
  eyewitnesses are not talked out of what they saw. Belief decays with τ = 12 game days.
- **Sensitive content.** Panic-attack rumours exist only in the full mental-health mode, drinking rumours only
  with addiction content on. A rumour about a panic attack changes the opinion of stigmatising listeners only;
  spreading sensitive rumours gives no mood reward. Spoken lines for these kinds never name the condition.
- **Privacy.** Nothing is replicated; the owner sees "Lidi si o mně povídají, že …" in their private lines.


### Confronting the source and denying rumours (10 November 2026)

Gossip network snapshot version 2 adds **suspects**: when a friend exposes a rumour, the subject remembers who it
came from (the immediate source, and whether that person also invented it). Only a suspect can be confronted.
Suspects expire after 14 game days, at most 8 per character, and a confrontation consumes the suspicion, so it
cannot be repeated for the same exposure. Version 1 saves load with no suspects.

- **Confront ("Vyříkat si drby")** – available to players and AI. Outcome odds depend on the accused's HEXACO
  honesty and agreeableness, the subject's agreeableness, and whether the accused invented a lie:
  `admit = clamp(0.15 + 0.55·H + 0.2·A − 0.15·[own lie], 0.05, 0.9)`, the rest splits into escalation
  (`(1 − admit) · clamp(0.06 + 0.3·(1 − A) + 0.2·(1 − A_subject), 0.05, 0.6)`) and denial.
  - *Admit*: the accused retracts the rumour with the **five most recent** people they told it to (lies ×0.5,
    truths ×0.8 belief); an invented lie also drops in the liar's own belief. Small relationship repair, guilt.
  - *Deny*: relationships drop in both directions; a liar who denies feels some guilt; nothing is retracted.
  - *Escalate*: a real argument (stress, grudges). Bystanders learn about it with severity ×0.6, which damps the
    "argument about gossip → new gossip" spiral.
- **Deny ("Popřít drby o sobě")** – player-only. The game picks the strongest negative rumour the listener
  believes. Outcomes: *nothing* (they have not heard anything; the liar who invented the rumour also plays
  dumb), *believed* / *doubted* (belief drops by `0.6·trust` for lies or `0.25·trust` for truths, divided by
  `1 + 0.5·(sources − 1)` – social proof), *caught* (denying the truth to an eyewitness damages the relationship and
  leaves a trust breach), *repeat* (once per listener per day). Part of the earlier relationship damage is returned
  when belief falls below what had already been applied.
- **AI.** Confrontation needs a suspect and a grudge ≥ 20 against them; urgency = base · grudge · 0.6 ·
  (1 − 0.35 · agreeableness), so a furious character will drop leisure to have it out, while hunger or exhaustion
  still come first. Before this fix the AI never chose it (base appeal 0).
- **Mental-health sensitivity.** Denying a witnessed panic attack is treated as shame, not as a lie: only a
  stigmatising witness cools (−4 × stigma), no trust breach is stored and the witness answers kindly. Denying a
  panic-attack rumour returns no relationship "damage" (illness is not a misdeed). All spoken lines stay generic.
- **Multiplayer.** No protocol change. The server rejects a confrontation command when the owner's character has
  no suspect for that target; all outcomes are computed on the authority.


## Household "cold war" (19 Nov 2026)

`scripts/sim/cold_war.gd` (`ColdWar`, owned by `HouseholdDynamics.cold_war`, authority only) models what happens when
one *pair* of housemates gets stuck in a conflict spiral. Household-wide balancing (frictions, shared moments, neglect)
keeps the average argument rate in range, but it did not describe a specific pair that keeps fighting.

- **Stages.** 0 none · 1 *tension* ("Dusno") · 2 *cold war* ("Nemluvíme spolu").
  Two arguments or insults between the pair within 48 game hours → tension; three → cold war. A tension can also turn
  into a cold war when its *heat* (0..1) reaches 0.7. Escalation by heat goes one stage at a time.
  - Heat rises with arguments (+0.25), insults (+0.35), coercive conversation outcomes (+0.12) and misunderstandings
    (+0.05). It falls with pleasant talks (−0.06, only half of that during a cold war) and decays exponentially. The
    time constant is 1 / 3 / 6 days by stage.
  - Downward transitions have hysteresis. Without new fights a cold war thaws to tension after about 5 days, and the
    tension ends after about a week.
- **Effects.**
  - The AI is less inclined to start ordinary social actions with the other person (×0.6 during tension, ×0.25 during
    a cold war). Apologies, confronting gossip and helping during a panic attack are exempt.
  - In the same room (< 9 m) while both are awake, each gets a small stress input and a "Dusno s / Nemluvíme spolu"
    moodlet.
  - Other housemates nearby get a weak "Doma je dusno" moodlet and a little stress, at most once per 3 hours each.
  - Shared moments (film on the sofa, cooking together) do not happen while the heat is above 0.5. Below that, a
    shared moment cools the pair by 0.15.
- **"Vyříkat si to" (`clear_air`).** A new social action for the player and the AI.
  - The chance of a breakthrough is 0.08..0.85. It is computed from heat, both characters' forgiveness, their average
    stress, their average relationship and the listener's de-escalation chance.
  - The remaining probability splits into a *truce* (55 %) and a *blow-up* (45 %):
    - breakthrough: tension ends, relationship +6..10, grudges −15;
    - truce: back to tension, small gain;
    - blow-up: a real argument, heat 1.0, cold war.
  - Every successful repair in the last 14 days lowers the next breakthrough chance by 0.08, so repeated fight–make-up
    cycles wear out. The floor stays at 0.08, so the path back is never closed.
  - There is a 6-hour cooldown per pair.
  - Asking without any tension, or during the cooldown, only produces a spoken reply. It never pulls the other
    character into a conversation, even when they are busy.
  - The AI waits: it shows little desire in the first half day of a cold war and right after a fight, and less under
    high stress. Pride lowers the desire as well.
- **Persistence.** The state is stored in the household save (`dynamics.cold_war`). `from_dict` sanitises hostile data:
  - names must be valid and pairs must be distinct;
  - at most 256 pairs, 8 argument stamps and 6 repair stamps;
  - all numbers must be finite and within limits.

  Old saves start without tension.
- **Multiplayer.** The server rejects a `clear_air` command when the pair has no tension. The HUD offers the command
  offline or on the host only when there is tension. Clients always see it, and the server decides.
- **Tests.** `tests/test_cold_war.tscn`: 72 checks in the default mode. `-- --soak`: 3 seeds × 10 days plus a
  determinism check.

## Romantic relationships and breakups (19 November 2026)

Module: `scripts/sim/romance.gd` (`Romance`), owned by `HouseholdDynamics` (authority only, saved with the household).

- **Pair states:** none → `dating` → `partners` → `ex`. The model is currently monogamous: someone who is in a relationship cannot start another one. Infidelity is a separate, planned step.
- **Asking someone out** (`ask_out`, player command and AI): the outcome is `yes`, `not_yet`, `no`, `taken` ("I'm seeing someone") or `pushy`. The chance comes from the target's relationship with and trust in the asker, plus the target's mood. It is capped at 0.02..0.90 and the roll is supplied by the character's RNG, so it is deterministic.
  - Hard rules: both characters must be 18+. An aromantic target does not accept. When the target has a filled-in romantic-attraction set, the asker's group must be in it.
  - The group comes from `gender_identity` (never from the body, the name or grammar). An unspecified group is not treated as a mismatch, and an empty attraction set means "unspecified", not "nobody".
  - Cool-downs: 1 day after `not_yet`, 3 days after `no`/`taken`, 7 days before re-dating an ex. Asking again after two refusals within 14 days is `pushy`: the target's relationship drops and their grudge grows.
  - A refusal is a real rejection (`RejectionResponse`, gated by the mental-health content setting).
  - The AI never asks after a refusal (14 days), never asks a fresh ex (30 days), never asks taken people, and asks at most once every 3 days. It only asks when it is attracted itself, the attraction is mutual, and relationship ≥ 45 and trust ≥ 50.
- **Satisfaction** (0..1) is kept **per person**:
  - Pleasant events count at most once per 2 game hours per pair, with diminishing returns (× (1 − satisfaction) / 0.45), so spamming conversations or dates cannot farm it. Negative events always count.
  - Conversations move it: chat/shared moments +, arguments −, insults and pressure hit the target harder.
  - Cold war drains it (stage 1: 0.012/day, stage 2: 0.035/day), as does neglect (no contact for over 2 days: 0.02/day). It slowly returns towards 0.55 (τ 14 days).
  - Commitment grows with time. A dating pair becomes `partners` after 14 days if both are at ≥ 0.6.
- **Breaking up** (`break_up`): the AI only breaks up after more than a day below 0.3, damped by commitment.
  - Consequences for the other person scale with commitment × their own satisfaction. Their reaction is hurt, angry or relieved. The effects:
    - heartbreak moodlet;
    - stress;
    - a real rejection cue (except relief);
    - relationship drop;
    - a grudge (×1.5 when angry).
  - The initiator gets sadness and guilt, plus "finally free" when they were very unhappy.
  - Cold-war heat +0.3 (they still live together).
  - For 14 days the exes have an awkward moodlet and a little stress when they meet in the same room, and the planner makes the AI avoid casual contact with them (×0.6). Partners get ×1.3.
- **Multiplayer:**
  - The server rejects `break_up` without a relationship. It rejects `ask_out` towards the asker's own partner, while the asker is taken, towards themselves, or towards a character owned by **another connected player**: the AI must not answer on a human's behalf, and a confirmation dialog does not exist yet.
  - The AI never asks player-owned characters.
  - Satisfaction is never replicated.
- **Saving:** `dynamics.romance`. `from_dict` sanitises everything: types, NaN/Inf, unknown states, foreign names, limits. On corrupted saves it enforces monogamy deterministically.
- **Known limits:**
  - no infidelity or jealousy coupling to partners yet;
  - no gossip about breakups;
  - no HUD relationship-status line;
  - no confirmation dialog between two human players.
  - The player's own character can still break up autonomously while idle (free will), like every other autonomous action.

## Infidelity, suspicion and jealousy (20 November 2026)

Module: `scripts/sim/infidelity.gd` (`Infidelity`), owned by `HouseholdDynamics` next to `Romance` (authority only, saved with the household as `dynamics.infidelity`). The public relationship stays monogamous (`Romance`); infidelity lives here and feeds back into `Romance` only through satisfaction events.

- **Flirt** (`flirt`): with one's own partner it is a small shared joy. With anyone else the target reciprocates with `Infidelity.flirt_p` (target's relationship, trust and mood; a partnered target's loyalty – honesty and own satisfaction – lowers the chance). A target who is not attracted to the flirter finds it uncomfortable (relationship −4) regardless of the roll. A reciprocated flirt adds **spark** (0..1, diminishing returns, at most once per 90 min, decays with τ = 7 days).
- **Secret date** (`secret_date`, implied / fade-to-black, nothing explicit): only when at least one of the two is partnered with someone else and spark ≥ 0.4. The target may refuse (spark cools). Accepted dates record an **affair** (number of dates, who betrays whom). The partnered side feels guilt and a "remorse" moodlet scaled by honesty; their partner's **suspicion** rises a little after every date (behavioural changes).
- **Intimacy outside the relationship:** a completed `adult_consensual_sex` (its own consent system) between a partnered character and someone else is recorded as infidelity. No sexual details are written to memories or rumours.
- **Witnesses:** the betrayed partner within 7.2 m of a secret date or intimacy catches them (immediate discovery). A partner who sees a flirt gets jealous (everyone a little, the *jealous* trait more), suspicion and evidence rise and their relationship satisfaction drops. Other witnesses get a true rumour (`flirting` / `cheating`, never fabricated).
- **Suspicion** (`P>A`): `v` 0..1 (τ 21 days) plus **evidence** 0..1 (τ 60 days), combined multiplicatively (many small hints do not add linearly), with an optional hint of who. Sources: seen flirts, rumours that reach the partner (`main._apply_gossip_event` → `on_rumor`, scaled by belief), behavioural hints after dates.
- **Confrontation** (`confront_cheating`, own partner only): `innocent` (nothing to hide – a jealous scene that hurts the accused and lowers their satisfaction), `confess` (chance from honesty, guilt and evidence), `caught_lying` (denial with evidence ≥ 0.6), `denied` (suspicion stays a little lower). AI confronts at most once a day from suspicion ≥ 0.35. After discovery suspicion turns into knowledge (no repeated interrogations).
- **Betrayal consequences** (`SimAgent.on_betrayal`): stress, rejection, a long "cheated on me" moodlet, relationship −(15–40), grudge and lower trust (more when lied to), grudge against the lover, relationship satisfaction −0.38 (`Romance` event `betrayal`), cold-war heat +0.55, guilt and shame for the cheater. The betrayed person becomes a first-hand source of the rumour. A breakup is **not forced**: the player decides, or the AI breaks up later through the existing low-satisfaction rule.
- **AI temptation:** `temptation = f(low satisfaction, low HEXACO honesty, impulsive trait)`. A satisfied, honest character does not flirt with others. AI flirts only where attraction is mutual, never with another player's character, and does not go on a secret date while its partner is awake within 15 m. Diagnostic run (`tools/diag_tmp/diag_infidelity_soak.tscn`): in the default 3-person household with one couple, 5–12 game days produced only flirts with the own partner and no affair – infidelity is rare unless the conditions are there.
- **Breakup rumour:** witnesses of a breakup get a `breakup` rumour, a piece of news that spreads but does not change anyone's opinion of the subject.
- **HUD:** the owner's relationship panel shows a status line ("Vztah: randí – Jana (3 dny)", "bez partnera (čerstvě po rozchodu: …)") and private lines (own secret affair; a vague feeling that the partner hides something, without naming anyone). Commands: Flirtovat, Tajná schůzka (offline/host only where it makes sense), Konfrontovat kvůli nevěře.
- **Multiplayer:** the server rejects flirt / secret date towards another player's character (except flirting with one's own partner), any romantic action with a character under 18 (defence in depth), a secret date with one's own partner, and confrontation with someone who is not the partner. Infidelity state is never replicated; other players see a secret date as an ordinary conversation (`net_action` "chat").
- **Limits and saves:** 256 sparks, 128 affairs, 256 suspicion records; a full table evicts the weakest entry. `from_dict` sanitises types, NaN/Inf, names (no `|`/`>`), drops affairs without a betrayal and betrayals pointing inside the pair.
- Known limitations: no polyamory/open-relationship model yet; a single player cannot answer another player's flirt (no confirmation dialogue); emotional affairs without dates are only represented by spark.
- Follow-up (review in the AI room): a rebuffed flirt is remembered for 3 days per direction (AI does not keep pushing; spark cools ×0.7); a rumour's weight drops when the partner trusts the subject (× clamp(1.25 − trust/100, 0.35, 1)); a good conversation or shared moment between partners softens suspicion ×0.9 (evidence stays). A jealous scene without reason always costs less than a real betrayal and never raises satisfaction, so confrontation cannot be farmed.

## Betrayal aftermath (21 November 2026)

After a betrayal is discovered, the betrayed character carries a private wound: rumination, withdrawal from the partner who cheated and the affair partner, a self-worth hit and a trust scar that makes suspicion grow faster in the next relationship. Gossip about the affair and seeing the two together reopen it; confiding, therapy and an accepted apology help it heal. Details: [mental-health.md](mental-health.md#betrayal-aftermath-21-november-2026).


## Rivalry, slander and manipulation defense (21 November 2026)

`scripts/sim/rivalry.gd` (inside `HouseholdDynamics`, authority only, saved as `dynamics.rivalry`).

- **Directed rivalry** `A>B`: A sees B as a rival; B may not know. Two arenas with their own decay: *love* (τ 14 days) and *status* (τ 21 days); `heat = 1 − (1 − love)(1 − status)`. Respect (after reconciliation) dampens new gains by up to 60 %. Rewinding time never strengthens or erases values.
- **Sources:** a once-a-day scan – A is interested in C (relationship ≥ 45 or an infidelity spark ≥ 0.3, A attracted to C, both adults, A not aromantic) while C dates B → A rivals B; arguments while the relationship is below 10; the betrayed partner learns about the lover (+0.5 love); exposed slander (+0.4 status when the victim knows the originator, +0.15 toward someone who only passed it on).
- **Slander as a weapon** (`slander_rival`): the target is the *listener*; the server picks the rival (strongest rival other than the listener), so a client cannot choose a victim. The rumour goes through `GossipNetwork.slander`: known negative rumours first (true ones preferred – they cannot be debunked), otherwise a fabrication with the slanderer as origin ("talks behind your back" if the listener likes the victim, else "takes other people's things"). Content settings still apply. The listener's reaction uses `RivalryPressure.resolve_pressure`: boundaries = listener honesty, support = listener's relationship with the victim, evidence = trust in the victim. Outcomes: *swayed* (stronger hit, still within the gossip per-pair daily cap), *doubted*, *saw through* (belief damped ×0.3, the listener thinks worse of the slanderer and may tell the victim → the victim can confront, rivalry comes back). Gates: 2 h between slanders by the same author, once a day per listener and rival. Slander is never rewarded (no "good gossip" mood); an honest slanderer feels guilt.
- **Bury the hatchet** (`bury_hatchet`): accepted → both directions drop to 35 % and respect grows; refused → 2 days of distance. Another player's character never answers through AI (rejected by the server).
- **Manipulation with defense** (`social_pressure.gd`): healthy self-worth (1 − the private self-defectiveness value, read only), the strongest supportive relationship and recognising the pattern (grudge toward the manipulator) reduce guilt, shame, fear and uncertainty (never below 25 % of the hit). Relationship and trust damage are always full; manipulation never creates consent. Resisting gives the target a small "didn't let myself be manipulated" mood and the manipulator "it didn't work".
- **AI:** only low-honesty characters (HEXACO honesty < 0.5) with a strong rival consider slander (at most once a day), preferring listeners who like the rival; forgiving, honest characters consider reconciliation. Ordinary contact with a rival is reduced (×0.4–1).
- **Privacy:** rivalry data never leaves the authority; the owner sees only lines such as "Rival: Eliška (status)". Slander that reaches another player's character is handled by the cross-player rules below.
- **Save format:** version 1 with a strict `validate_snapshot` (exact keys, ranges, limits) and a tolerant `from_dict` (bad entries dropped or clamped; a snapshot from a future version is discarded; older saves without the section start with no rivals).
- **Not yet:** workplace rivalry (needs careers), visible rival indicators in the 3D scene.

### Slander across players (23 Nov 2026)

Slander between players is allowed – scheming is part of the tone – but two rules keep it fair (`scripts/net/slander_policy.gd`, server only):

- **The listener decides, not the AI.** When the listener belongs to a different player than the author (the author can be a player or an NPC), the rumour is delivered (the listener remembers "Rumour from X …"), but its effect on relationships is deferred. The listener's owner gets a private verdict in the command list: *believe it* (full impact through the same daily gossip cap as a "swayed" listener), *don't believe it* (belief ×0.3, worse opinion of the author, a trust breach memory) or *don't believe it and tell the victim* (as before, plus the victim learns the source – confrontation and retaliatory rivalry, and the victim's owner gets a private notice). Without an answer within 12 game hours the default is "half in doubt" (belief ×0.6, half impact) – the same as the AI outcome `doubted`. Rivalry records the slander provisionally as `doubted`, so the Rivalry save schema is unchanged.
- **Victims cannot be dog-piled.** At most 3 slanders per game day about a player's character, across all authors (`victim_cap`; the server explains the refusal).
- Verdicts are keyed by the listener's character (they survive a reconnect; whoever takes over a household character inherits them), at most 8 per character (the oldest is closed with the default), 256 in total. They are runtime state like rate limits: after a server restart pending verdicts are gone (the rumour stays as heard, without relationship impact) and the victim cap starts from zero; the persisted per-author limits (2 h gap, once a day per listener and rival) still apply.
- Offline nothing changes: the AI listener model decides as before.

## Workplace rivalry (24 November 2026)
Promotion contests (see [careers.md](careers.md)) are a new source of status rivalry: losing a contest to a real character feeds `Rivalry` (status, 0.3); a scheme that is caught or later discovered gives the victim a status rivalry (0.4), a lower opinion of the schemer and a grudge. Colleagues who worked the same day get a small relationship boost unless they are rivals. NPC colleagues who steal credit or win a contest become a private source of resentment (`npc_heat`), shown to the owner in words.
