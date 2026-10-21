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

## Plan: one axis per run

The expansion agreed with the reviewers adds one axis per development run. Each step must include agency
tests, a full/muted/off switch and a **diversity test**: two characters with the same label must behave
measurably differently.

1. **Shared framework of 9 interpretable dimensions:**
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
