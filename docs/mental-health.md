# Mental health

Mental health is a core system, not a label or a debuff. Conditions are modelled as realistic states.
They have triggers, good and bad days, episodes and relapses, healthy and unhealthy coping, support from
others and stigma. **The path to recovery is never closed.** Inspiration: *Hellblade*, *Celeste*,
*Disco Elysium*.

## Ground rules

- **A diagnosis is a predisposition** with a severity (`conditions`). It is never a script and never a
  personality template.
- **Symptoms can be involuntary, but the player is never locked out.** During a panic attack the player
  can still breathe, confide in someone or ask for help, even with a full command queue.
- **No dominant choice.** Every coping strategy has trade-offs, and repeating one in a short window loses
  effect (anti-farming). This is verified by a non-dominance test across contexts.
- **No numbers in the HUD.** The mental state is described in words.
- **Content rules** are in [vision.md](vision.md#content-rules-non-negotiable). Self-harm and eating
  disorders appear only through emotions, relationships and consequences, and are hidden by default.
  Suicide is not a playable action. Intrusive and depressive thoughts never contain suicidal content.

## Stress

Stress accumulates from unmet needs, arguments, insults, stigma, jealousy and crowding. Sleep, calm,
support and coping discharge it. High stress raises the risk of arguments.

## Anxiety: three components

Anxiety is the interplay of three components:

| Component | Meaning | Dynamics |
|---|---|---|
| `threat` | Perceived threat or uncertainty in the situation, distorted by personality | rises and falls quickly |
| `arousal` | Bodily activation (heart, breath, tension) | rises quickly, falls slowly |
| `sensitivity` | Sensitivity to triggers | slow (weeks): rises with avoidance and chronic stress, falls with mastery experiences and support |

Two kinds of resources work against it:
- `regulation`: the current capacity to regulate, reduced by tiredness, hunger and alcohol;
- `support` and `mastery`: recent support from close people, and the long-term sense that situations are
  manageable.

**Panic attacks** are involuntary symptoms. Witnesses can help, which shortens the attack and strengthens
the relationship, or stigmatise, which hurts and lowers the relationship. Exposure is an experience, not
a guaranteed reward. **Intrusive thoughts** are private, always framed as "a thought, not a fact". They
also bias the interpretation of conversations.

## Depression: four separate components

| Component | Meaning |
|---|---|
| `burden` | Depressive load over days to weeks. Raised by chronic stress, isolation, losses, conflicts, rumination and sleeplessness. Lowered by activity, contact, support and sleep. |
| `wanting` | The *learned* expectation of reward per action, distorted by pessimism. Decisions are made on this. |
| `liking` | Hedonic capacity: how much joy an action actually brings when performed. |
| `vigour` | Energy to *start*. The initiation barrier is `(1 − vigour) × effort` of the action. |

The model learns from **prediction error**. A positive surprise ("it was better than I expected") eases
things a little, but no action is a guaranteed cure.

Behavioural activation is subject to:
- habituation with no ceiling (100 repetitions really do almost nothing);
- a shared "relief budget" across all activities, `1 / (1 + (R / R0)³)`, so that cycling through many
  activities helps no more than a varied, normal day.

Episodes start only after the burden stays above a threshold. As a deliberate game compression, two game
days stand for the clinical two weeks. An episode leaves a fading scar that makes relapse faster.
Predisposition allows endogenous dips. Morning worsening exists only as an individual pattern.

A player command is never refused. The character may only "not be able to get going", and that can be
cancelled. Visual feedback is a grey PsycheFX filter.

## Coping

There are seven coping strategies with trade-offs and habituation:
- breathing;
- going for a walk;
- journaling;
- confiding in someone;
- doomscrolling;
- hiding away;
- a "beer for the nerves", with tolerance and a morning rebound.

Some of them also work as ordinary leisure.

## Content settings

| Setting | Values |
|---|---|
| Mental-health themes | full / muted / off. Muted caps depressive burden below episodes. Off leaves only ordinary situational low mood. |
| Intrusive thoughts | off / gentle / normal / strong |
| Perceptual distortion | on/off plus strength (PsycheFX, low-pass music, heartbeat) |
| Addiction, profanity | on/off (profanity can be censored) |
| Self-harm / eating-disorder topics | off by default |

The server applies its own content settings: it rejects predispositions and traumas when themes are off,
and refuses content forbidden by server settings.

## Psyche model (axis 1, run 20)

`scripts/psyche/psyche_model.gd` is the shared framework the later axes build on. Full design:
[design/psyche-model.md](design/psyche-model.md).

- **P, personality:** six HEXACO-like axes (−1..1). They are stored optionally in
  `CharacterData.personality.hexaco`. A missing axis is derived from the traits through an offset table,
  so traits stay as presets and descriptions on top of the vector.
- **D, dispositions:** nine named dimensions (0..1, 0.5 = population average), computed from P, direct
  trait effects and condition profiles, never typed in. `PsycheModel.explain()` lists every contribution
  with its size and reason.
- **Condition profiles are data:** `res://data/conditions/anxiety.json` and `depression.json`. Each
  modulation (`add`, `mul`, `threshold`, `couple`) has a limit and a mandatory `why`. Couplings must form
  an acyclic graph and run once per game hour in a fixed topological order. Several profiles together
  are clamped to the limit of one, so comorbidity cannot create a death spiral. A profile that fails
  validation is not loaded.
- **No double counting:** the existing mechanics (MentalState, Depression, traits) still carry the effect
  of traits and of profiles with a `legacy` block (the old numbers, identical to before). Only the
  **residual** `D − D_legacy` drives four hooks in MentalState: regulation capacity (how fast arousal
  decays), threat sensitivity (threat from stressors), social threat (cost of social actions, crowds) and
  impulsivity (appeal of unhealthy versus healthy coping). The residual comes from per-character
  individuality (`personality.psyche_seed`: ±20 % on every contribution plus a small own offset per
  dimension), from an explicit personality that differs from the traits, and from future profiles without
  a legacy block. Every hook is a multiplier clamped to 0.7–1.3, so it changes costs and rates and never
  removes an option.
- **Content settings:** off removes all profile effects, muted caps severity at 0.5. MentalState keeps
  hooks for all three modes and picks one from the current settings, so switching at runtime works.
- **Privacy:** P, D, the seed and profiles are owner/server only and never appear in spawn data.
- Values and worldview (layer V of the design) are **deferred** until something in the game consumes them.

## Plan: one axis per run

The expansion agreed with the reviewers adds one axis per development run. Each step must include agency
tests, a full/muted/off switch and a **diversity test**: two characters with the same label must behave
measurably differently.

1. **Shared framework of 9 interpretable dimensions** (done in run 20, see above):
   - threat sensitivity;
   - social threat / expected rejection;
   - impulsivity;
   - regulation capacity;
   - need for predictability;
   - sensory sensitivity;
   - energy with a personal baseline;
   - reward from activities;
   - cognitive flexibility.

   Modulations come in four kinds, each with limits and an auditable "what / how much / why":
   - additive shift of up to ±0.3;
   - multiplicative ×0.5–×2;
   - threshold shift of up to ±0.2;
   - coupling with |w| ≤ 0.5 and no cycles.
2. Social anxiety and fear of rejection or abandonment, linked to relationships, grudges and apologies.
3. Burnout and anxious depression: chronic anxiety leading into depression.
4. OCD: obsession → compulsion → short relief → reinforcement.
5. ADHD/ADD: working memory, task initiation, impulsivity, hyperfocus.
6. Bipolar disorder: episodic dynamics. Hypomania is distinguished from ADHD hyperactivity by its time
   course, reduced need for sleep and change against the person's own baseline.
7. Autistic traits as optional profile axes (sensory sensitivity, need for predictability, communication
   style, monotropic interests). They are never a single stereotype.

Later steps:
- therapy and a clinic;
- medication with side effects;
- traumas and long-term memory (PTSD);
- personality disorders, never as villain templates;
- dialogue with narrowed choices, where choices stay visible but feel "heavy";
- the **EmotionPresenter** layer (posture, face, breath, micro-actions, adaptive music).

## Tuning after the crowded-household stress test (23 October 2026)

- **Soft stress ceiling:** above 70, new stress counts only partly (down to 15 %); sleep calms more (0.05 → 0.07).
- **Unmet needs** weigh by type in stress: hunger and energy fully, social 0.5, hygiene, fun and comfort 0.4.
- **Depression:** recovery in sleep ×2.0 (was ×1.6) and under stress ×0.6 (was ×0.4); growth slows near the cap, so a long
  episode no longer freezes at 1.0. Strong predispositions keep a mild floor of low mood (0.35 × (vulnerability − 0.3)) and
  have more frequent endogenous dips (rate 0.1 × (vulnerability − 0.2) per day).
- **Anxiety:** occasional waves “out of the blue” for an anxiety predisposition (0.18 × severity² per day, lower with
  mastery); a wave can turn into a panic attack depending on severity, mastery and sensitivity. The refractory time after an
  attack grows with repeated attacks in the last 3 days (6 h → at most 24 h), followed by exhaustion with lower arousal.
  Content settings off → no waves and no attacks.
- **Alcohol:** each further drink within ~16 hours gives less relief (1 / (1 + 0.5 n)) and appeals much less
  (1 / (1 + 1.2 n²)), on top of tolerance and the next-day rebound.

## Stress sources and sleep (run 23)

`MentalState.stress_sources` records where stress came from (`needs`, `crowd`, `argue`, `friction`, `witness_conflict`,
`stigma`, `life` …) as the amount actually added. `take_stress_sources()` returns and clears it. It is not saved or sent
over the network; it serves diagnostics now and a future "what is stressing me" explanation in the UI.

The household matrix (`test_household_matrix`) found a character with a strong anxiety and a moderate depression
predisposition stuck above stress 85 for 20 game days in an 8-person household. The sources showed why:
- crowd stress was applied while asleep (with 3 beds for 8 people, characters slept on the floor next to each other);
- from about day 10, unmet needs added about 40 points a day, and loneliness (social need at 0) kept adding stress during
  sleep (about 17 points a night), so the night never brought relief.

Now crowding counts only while awake, and during sleep only bodily needs add stress (hunger at half weight; loneliness,
boredom, hygiene and comfort do not). Disturbance in sleep is handled by noise (`HouseholdDynamics`). On the same seed the
character now has a hard week (stress around 70–77, burden up to 0.47) and then recovers. Discomfort of sleeping on the
floor should reduce sleep quality rather than add stress; that belongs to the furniture and housing work.

## Severity range of depressive episodes (23 October 2026)

A depressive episode is no longer a single state. It has three severities, shown only in words, never as numbers:

| Severity | HUD label | When |
|---|---|---|
| Mild | Mírná depresivní epizoda (mild depressive episode) | Every episode starts here (burden above 0.6 for 2 game days) |
| Moderate | Středně těžká depresivní epizoda (moderate depressive episode) | Burden above 0.70; drops back below 0.64 |
| Severe | Těžká depresivní epizoda (severe depressive episode) | Burden above 0.82 for at least half a game day (depth reached during onset counts); drops back below 0.76 |

The bands use hysteresis, so the label does not flip back and forth near a boundary.

**Vulnerability decides how deep an episode can go.** Burden growth slows near a soft ceiling of
`0.72 + 0.28 × vulnerability`:
- a character with no predisposition reaches at most a mild episode, even under long stress and isolation;
- moderate predisposition leads to moderate episodes;
- strong predisposition (or the scar left by earlier episodes) can lead to severe ones.

Large life events (`on_event`) can still push anyone past the ceiling.

**Effects scale with severity:**
- Burden already drives anhedonia, pessimism, low vigour, fatigue and poor sleep.
- A moderate episode adds the mood entry "Všechno je těžké" ("Everything is hard").
- A severe episode adds "Sotva zvládám den" ("I can barely get through the day"), plus extra fatigue, worse sleep and a stronger pull to bed and sofa.

**Recovery:**
- Recovery is faster from a mild episode (×1.15) and slower from a severe one (×0.75), but always possible.
- The scar after an episode is `0.03 + 0.02 × peak severity` and fades over time.
- Episodes are counted by peak severity (`severity_counts`), which is saved and validated on load.

With the mental-health topics turned off there are still no episodes and no diagnostic names, only "Skleslost" or "Sklíčenost" (low mood / dejection).

Tests: `test_depression` section "Rozpětí deprese" (depression range; 14 checks) covers:
- the three predisposition levels and the label;
- the mood entry and the stronger effects;
- the delayed onset of severe episodes and the hysteresis;
- recovery and scar by severity, and save/load including garbage input.

## Slider-driven psychological differences (23 October 2026, schema v8)

The character-creation back-end now allows an independent slider for each of the nine dispositions in `PsycheModel.DIMS` (`mind.dispositions`, 0..1) and a slider for each supported condition's susceptibility (`mind.predispositions`, 0..1). A discrete diagnosis or a stereotyped disorder template is not required to define a character's behaviour. The original derived disposition model remains the default for axes the user has not overridden, while overrides feed the bounded residual hooks. Traits have separate continuous strengths, and an optional six-axis HEXACO-like personality description remains editable. `personality_slider_editor.gd` exposes these controls, currently as a reusable panel for the upcoming character editor.

**Distinction:** Traits and dispositions describe enduring tendencies, conditions describe optional susceptibility, while stress, arousal, reward anticipation, hedonic capacity, and episode state are dynamic simulation variables. The editor should never turn a high slider into a fixed scripted fate or mistake it for a clinical diagnosis. Private slider maps are not included in the public multiplayer snapshot; the content-off validation path clears psychological dispositions together with mental-health predispositions.


## Rejection sensitivity / hypersensitivity integration (24 October 2026)

New `rejection_reactivity` slider is separate from `social_threat` (expectations),
`threat_sensitivity` (meaning assigned to ambiguous signals) and
`hypervigilance` (attentional scanning). Transient rejection distress responds
differently to actual versus *perceived* rejection, relational significance,
regulation and support, and can fade without a new event. Perceived rejection
after a good conversation does **not** prove objective rejection.

Sensory `sensory_sensitivity` is now labelled broad "Hypersenzitivita":
audio/noise and nearby crowding are the current live consumers, touch and bright
light have separately addressable gains for later world interactions. Original
noise-specific variability and habituation are preserved.

High cumulative rejection distress plus strain can optionally create a **private,
non-graphic concern** that motivates support-aware future presentation; neither
self-harm nor suicide is a player or AI action, and no method is represented.
Concern is OFF by default under `sh_ed_topics=false`, suppressed when mental
health content is muted/off, and never replicated to other peers or assigned a
reward/score. It is a gameplay safety signal, not a predictor or diagnosis.
Tests: `test_rejection_hypersensitivity` plus original mental-health and
character-editor regression. Recovery remains possible.


## Fully obscured optional implied incident presentation (24 October 2026)

A **presentation-only prototype** now exists for an optional *completed*
self-harm-related narrative incident. It is neither an ActionLibrary action
nor generated from the rejection distress threshold. The independent
`scripts/sim/sensitive_privacy_mask.gd` completely hides the character
visual, replacing it with a neutral **opaque tiled mosaic box**; after the
short transition, the visual is restored and a **local private HUD notice**
says a self-harm episode occurred and support may be needed.
No body part, act, tool, method, animation, injury detail or score is shown.

The internal `SimAgent.present_implied_sensitive_incident()` hook is
**guarded** by adult-sensitive content opt-in (`sh_ed_topics=true`),
`mental_health=full`, offline local world with HUD and no active mask.
The default setting blocks it. It fails closed in networked worlds and
neither the hook nor the notice is added to player commands,
`net_detail`, shared snapshots or a reward system.

**Important limitations:** no autonomous self-harm incident is currently
simulated, no plot director calls the presentation hook in normal
gameplay, and there is no live-rendered visual screenshot audit yet.
Future integration requires independently reviewed non-graphic,
non-inevitable incident logic, positive support/recovery pathways,
full save/resume and dedicated privacy/accessibility controls. Relationship
dependency alone cannot force an incident, and there must never be a
playable harm action or reward. The system models adult character
experiences; it is not a psychiatric prediction.

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
