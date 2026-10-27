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

## Psyche expansion (27 October 2026 onwards)

The owner asked to finish the psyche system with sliders for neurodivergent profiles, a better social
memory, mood disorders, personality difficulties, OCD, substances and addiction, eating difficulties
and psychotic states. The work is split into vertical slices A–H, each finished (code, UI, tests,
documentation) before the next one starts. All slices share one coordinator,
`scripts/sim/psyche_ext.gd` (`SimAgent.psy`), and the same rules:

- a diagnosis is a predisposition over dimensions, never a switch or a template; two characters with the
  same label must behave measurably differently (diversity test);
- symptoms may be involuntary, but a player command is never refused (agency test);
- content modes: full = 1, muted = 0.5, off = 0 (every multiplier is exactly 1.0, no state change);
  with mental-health topics off the validator does not accept any `mind` field (each falls back to its
  default, including `self_defectiveness`);
- the extension has its **own RNG** seeded from the character, so a character without sliders consumes
  no random numbers from the main stream: the default household is bit-identical to before
  (`test_household_dynamics` output identical in all 16 seeds);
- private: nothing goes into the public snapshot, spawn data or `net_detail`; the owner sees short
  word descriptions only in the offline HUD (`hud_info().psyche_lines`), never numbers;
- the state is saved in the household save (`state.psyche_ext`, strictly validated; older saves load with
  a clean state) and old characters are migrated (`CharacterCodec`).

### A. Neurodivergent profile (schema v9)

`CharacterData.mind.neuro` holds 15 independent 0..1 sliders (0 = no notable difference) plus
`mind.interest_focus` (where a deep interest points: books, cooking, exercise, screens, nature). They are
edited in the creator and the editor in the section "Neurodivergentní profil". Strengths are axes just
like difficulties. The need for routine is the existing `dispositions.predictability_need` slider; it
now has a live consumer, but only when set explicitly (the derived value had no consumer before and
default characters must not change).

| Axis | Effect (continuous, bounded) |
|---|---|
| `attention_drift` | Long quiet/focus tasks are a little less appealing; an autonomous one may "fizzle out" early (hazard per minute, never a player command, never the interest activity). Fun gets a small pull. |
| `working_memory` | Cooking takes longer, an occasional "I forgot something again" moodlet; journaling relieves more stress (external memory aid as a strength). |
| `task_initiation` | Effortful chores (cooking, hygiene, exercise, repairs) are less appealing in proportion to effort; a player command may start with the existing cancellable hesitation, then runs. Fun and the interest are exempt. |
| `action_impulsivity` | More pull to fun and quick-relief coping. Separate from the emotional `impulsivity` disposition. |
| `hyperfocus` | The interest activity (and, less, other fun) lasts longer when chosen autonomously; protects against attention drift. |
| `time_blindness` | A weaker evening pull to bed and fun running over time; "I lost track of time again" when a need got low meanwhile. |
| `sens_sound`, `sens_light`, `sens_touch` | Per-channel gains on top of the broad hypersensitivity (`SensoryProfile.channel_gain`): noise, bright/morning light, crowding and touch. Exposure accumulates **sensory overload**, which adds stress, pulls to quiet/rest/hiding, lowers the appeal of socialising and TV, and fades in quiet and sleep. |
| `social_energy` | Each conversation drains a "social battery" and some energy; solitude and quiet recharge it. A flat battery lowers social appeal and raises the pull to quiet. |
| `interest_depth` | The interest activity is much more appealing and, when finished, regulates: less stress and overload, some battery. A long absence of it shows as "I miss my interest". |
| `direct_communication` | With close people a small bonus to a good conversation (valued honesty), with strangers a small extra risk of misunderstanding; complaints are swallowed less often (they get said and can be resolved). |
| `masking_cost` | Conversations with people who are not close cost stress and build "tiredness from adapting"; with close people no cost; the planner slightly prefers close people. |
| `tic_tendency` | Harmless involuntary tics, more frequent under stress and overload; near others a brief self-conscious moodlet. Nothing public. |
| `reading_effort` | Reading and journaling are less appealing (more effort). |

Interrupted plans (an occupied object, being pulled into a conversation) add a little stress to a
character with a high explicit `predictability_need`.

Tests: `tests/test_neuro_profile.gd` (57 checks: schema/migration/validation, neutral = exactly 1.0,
monotonic continuous effects, full > muted > off, channels and overload, social battery and masking,
direct communication, tics, agency with a real `cook` command, diversity of two "ADHD-like" profiles over
three game days, determinism, save/load round trip, network privacy, editor sliders).

### B. Social and affective memory (schema v10)

`scripts/sim/social_memory.gd` (`SimAgent.psy.memory`) keeps structured traces of what happened between
people. It is not free text and not an autobiography: every trace comes from a fixed catalogue
(grievance, insult, complaint, misunderstanding, breach of trust, rejection, humiliation, pressure,
apology, support, shared moment, pleasant talk, conflict seen) and stores:

- `who` (the stable uid of the person who acted, never the name) and `whom` (empty = me; for something
  seen or heard, the uid of the person it happened to);
- game time, emotional charge, severity, **certainty** and the source: experienced (`self`), seen
  (`witnessed`, lower certainty) or told by someone (`told`, lowest);
- the **interpretation** separately from the fact: "on purpose", "unclear", "by accident" (derived from
  the existing vigilance appraisal); "on purpose" weighs more, "by accident" less;
- the current strength and an optional place (the object the event is tied to).

Dynamics:
- traces fade with a time constant by kind × severity × the memory slider, so strong traces fade more
  slowly; after a long time without new events everything is forgotten (no permanent labels);
- the same kind from the same person reinforces one trace instead of adding duplicates, capped by
  severity (a hundred small things never become one big one);
- an opposite event overwrites: an apology weakens insults and grievances, support weakens a breach of
  trust, an insult weakens pleasant memories;
- cue reactivation: meeting the person or using the same object revives traces a little, at most once
  per six hours and more only when the trace has not been recalled for days, so everyday living together
  without new harm lets things heal (tested: grievance + apology + time moves monotonically back towards
  zero, without oscillation, even with regular meetings);
- relationship labels with hysteresis for the private HUD ("blízký / přátelský / neutrální / napjatý /
  nepřátelský vztah"): a label changes only after crossing a boundary by four points; updated once per
  game hour, independent of the HUD.

Influence is bounded and probabilistic only: choosing a partner for a chat or confiding ×0.85–1.15,
the chance of a good conversation ±0.04 per side, forgiveness when evaluating an apology ±0.08. Memory
never selects or blocks an action.

Private versus shared: a witness of an argument or insult gets a `witnessed` trace about what they saw;
someone who is confided in gets a `told` version of the confider's strongest grievance about a third
person; nobody else knows. Traces never leave the authority (no `net_detail`, no snapshot); the owner sees
a short word summary in the offline relationship list ("pamatuje si: urazil mě jistě, živě, myslím, že
schválně"). The aggressor does not record the victim as a grievance.

Memory abilities (`mind.memory`, 0..1, 0.5 = average, section "Paměť na lidi a události" in the creator
and editor): `retention` (how long; time constant ×0.45–×1.8), `precision` (certainty of recall) and
`emotional_weight` (how strongly the emotional charge is encoded). Muted halves the deviation from
average, off uses average abilities; the memory itself always runs because it is ordinary cognition,
not a mental-health topic.

Because memory runs for every character, the default household is no longer bit-identical after slice B;
the household suites stay within their unchanged bounds (see testing.md).

Tests: `tests/test_social_memory.gd` (41 checks).

### C. Mood course over time: bipolar spectrum and persistent low mood (schema v11)

`scripts/sim/mood_cycle.gd` (`SimAgent.psy.mood`) models the course of mood. There is no "bipolar I/II"
switch: `mind.mood` has five 0..1 sliders and the familiar patterns emerge from their combination.

| Slider | Meaning |
|---|---|
| `bipolar_tendency` | Susceptibility to episodes up and down (episode hazard `1 − e^(−λ·dm)`). |
| `elevation_ceiling` | How high an elevated phase can go: low = hypomania only (type-II-like), high = mania possible (type-I-like). |
| `cycling` | Faster, shallower and more frequent swings (cyclothymia-like): shorter episodes, lower ceiling. |
| `chronic_low` | Persistent low mood without episodes (dysthymia-like): a floor of depressive burden below the episode threshold. |
| `sleep_sensitivity` | How strongly sleep loss shakes the mood. |

The state `pole` (−1..1) is measured against the character's **own normal**, not a population average.
Phases with hysteresis and confirmation time (half a game day above the boundary; mania one more day):
depressive ↔ euthymic ↔ hypomanic ↔ manic. Triggers: sleep debt (awake at night) raises the hazard and
pushes towards elevation, high stress raises the hazard and pushes down. An episode has a duration of a
few game days (the same compression as depression), shortened by support and sleep, lengthened by sleep
debt; then the mood returns to the character's normal.

Effects of an elevated phase (bounded multipliers): less tiredness and a reduced need for sleep (sleep
refreshes faster, weaker pull to bed at night), more appetite for people, fun and exercise, more pull to
risky quick relief (drinking, doomscrolling), faster, overflowing speech lines, and irritability that grows
with stress and lowers the chance of a good conversation. A depressive phase pushes the existing
depressive burden towards and past the episode threshold, so withdrawal, anhedonia, the HUD wording and
recovery of the existing depression model apply. `chronic_low` sets `Depression.chronic_floor`: the burden
stays near a floor below the episode threshold ("Skleslost / Sklíčenost"), never an episode by itself.

Distinction from ADHD-like hyperactivity and from a naturally energetic person: without mood sliders
there is no episode at all, and a character with strong ADHD-like axes and a very high energy baseline
stays euthymic (tested). Modes: muted caps elevation at mild hypomania (no mania) and weakens depth and
the chronic floor; off removes everything. The player is never locked out (sending an elevated character
to sleep works). Private word lines only ("Nálada a energie jsou výš než moje obvyklé já…").

Tests: `tests/test_mood_cycle.gd` (38 checks).

### I. Inner voice: rumination, worry, self-criticism, hope (schema v12)

`scripts/sim/inner_voice.gd` (`SimAgent.psy.voice`) builds a private thought stream on top of the
existing intrusive thoughts (`MentalState.thoughts`) and rumination (`Depression.rumination`). A thought
is never random filler: it comes from an appraised event (insult, argument, breach of trust, rejected
apology, humiliation, a better-than-expected experience, support, reconciliation, a shared moment), from
the state (worry appears from high stress or perceived threat, once per game hour) or from traits (the
stable `self_defectiveness` belief turns failure and rejection into self-critical thoughts). Templates
are chosen by topic; the name is only the label of the person the thought is about.

Rumination loops (at most four: grievance about a person, failure, worry, self-criticism) have a
strength that grows while idle, in quiet activities and especially awake at night, and fades with
distraction (fun, exercise, people, reading, cooking), support, sleep and problem-solving (an accepted
apology releases the loop about that person for both sides, journaling and seeking help release all a
little). Costs: worse sleep quality, faster energy drain, feeding the existing depressive rumination, a
mood entry ("Pořád na to myslím", "Starosti se točí dokola", "Vnitřní kritik nedá pokoj"). Effects on
choice are bounded (×0.5–2.5): confiding, journaling, a walk and seeking help become more appealing.
Hopeful and warm thoughts come from data too (support, reconciliation, shared moments). The sliders in
`mind.thoughts` (rumination, worry, hope; 0.5 = average) only scale how strongly thoughts return.

New action `seek_help` ("Vyhledá odbornou pomoc", off-screen helpline/counselling, coping with support,
mastery and habituation): the player can always command it; the AI chooses it only with a reason
(`psyche_gate`: strong rumination or hopelessness; later also addiction and psychotic states).

**Passive hopelessness.** Represented ONLY as a private, non-graphic thought state, and only when the
existing opt-in sensitive-content setting (`sh_ed_topics`, default off) is on and mental-health topics are
full. Intensity comes from severe depressive burden, the self-defectiveness belief, rejection distress,
strong rumination and very high stress, reduced by support; it fades with support, sleep, lower stress and
recovery, and switching the setting off clears it immediately. It never produces an action or autonomous
behaviour (no such action exists), never enters `mental.thoughts`/`net_detail`, and is never visible to
other characters or players. It raises the utility of confiding and seeking help. When it appears the
owning player sees, in the offline HUD only, a notice and the crisis lines from `GameSettings.CRISIS_LINES`
(116 123, findahelpline.com). Texts contain no methods, plans or numbers.

Modes: full; muted = weaker loops and no hopelessness; off = nothing.

Tests: `tests/test_inner_voice.gd` (46 checks).

### D. Personality accents (schema v13)

Personality difficulties are a configurable personality with accentuated traits, not a "disorder
switch". `mind.accents` holds eight 0..1 sliders: sensitivity to abandonment and emotional swings,
suspiciousness, need for attention, perfectionism and rigidity, avoidance and inhibition (fear of
criticism), dependency, grandiosity and need for admiration, detachment and emotional coolness.

They act through the existing systems, so interpersonal patterns emerge instead of a script:
- each accent is an entry in `Traits.ACCENTS` with the same parameters as traits (chemistry, argument
  bias, grudge and guilt time, forgiveness, pride, stigma, jealousy, social need decay, appetite for
  social or solitary actions, irritability, novelty, mood bias, joy from social contact) and is added to
  the simulation trait profile as a weight `acc_<id>` (scaled by the content mode, rebuilt when the mode
  changes at runtime). Accents are not legacy traits: they cannot be chosen as presets, are not in the
  random generator, are never sent over the network and never appear in the public trait list;
- hooks (`scripts/sim/personality_accents.gd`): the strength of reactions to rejection (abandonment,
  attention, avoidance up; detachment down), appraisal of ambiguous intent (suspiciousness reads more
  "on purpose"), perceived rejection after a good chat, how fast trust grows (`RelLedger.trust_gain_mult`),
  the amplitude of emotional impulses (`EmotionalState.amplitude`: swings vs. blunting), learning of
  emotional dependency on a person, the cost of social actions (avoidance, `MentalState.accent_social_cost`),
  rumination loops (perfectionism ruminates failures, suspiciousness grievances), the pull to confide
  (dependency) or to apologise (grandiosity less), a rejection turning into anger (grandiosity), and mood
  entries when attention-seeking or dependent characters are alone.

An interpretive label ("rysy emoční nestability (hraniční styl)", "paranoidní rysy" …) is an optional,
private layer only: it appears in the owner's offline description only when `mind.accent_labels` is
switched on in the editor, and it never changes behaviour. Without accents the trait profile and all
hooks are exactly unchanged. Muted halves the accents, off removes them.

Tests: `tests/test_personality_accents.gd` (36 checks).
