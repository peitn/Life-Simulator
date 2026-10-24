# Design: the psyche model (personality, values, mental-health dimensions)

Status: **design proposal** (22 October 2026), written from the room discussion (#79, #83–#85) and the owner's
request. **Axis 1 is implemented (run 20):** layers P, D and C, modulations, the coupling graph and `explain()`
in `scripts/psyche/psyche_model.gd`, profiles in `res://data/conditions/`, tests in `tests/test_psyche.gd`. Layer V
(values) is deferred until it has a consumer. Section 9 describes how the implementation avoids double counting. It is the reference for the mental-health axis runs, starting with axis 1, the shared framework.
Nothing here overrides the content rules in [../vision.md](../vision.md).

## 1. Goal

Do not simulate labels; simulate **mechanisms**. A diagnosis is not a script. It is a profile of
predispositions that **modulates** a shared model of the mind. Behaviour emerges from the interaction of:

```
stable dispositions  ×  modulators (conditions, learned patterns, support, treatment)
        ×  dynamic state (stress, mood, energy, arousal…)  ×  situation (events, people, place)
        →  interpretation of what happens  →  costs and probabilities of actions  →  the player or AI chooses
```

Two characters with the same label must behave **measurably differently**, and the same character must behave
differently in different environments.

## 2. Layers and vectors

Every character carries six groups of numbers. All of them are named and interpretable, with no hidden
embedding vector. The one exception is a small per-character jitter used to avoid clones (§5.4).

| Layer | Changes over | Stored in | Who sees it |
|---|---|---|---|
| **P – personality** | years (practically fixed) | `CharacterData.mind.personality` | owner only |
| **V – values and worldview** | months (slow, through experience) | `CharacterData.mind.values` | owner only, others infer from behaviour |
| **D – psyche dispositions** | months (therapy, lasting experience) | derived from P + conditions + seed, persisted | owner only |
| **C – condition profiles** | data files, a character has 0..n with severity | `CharacterData.mind.conditions` | owner only, **never** in spawn data |
| **S – dynamic state** | minutes to weeks | `MentalState` / `Depression` (existing) | owner only, HUD shows words, never numbers |
| **L – learned patterns** | days to weeks | expectations (`wanting`), sensitivities, grudges, mastery | owner only |

### 2.1 P – personality (6 axes, −1..1)

A HEXACO-like set that is easier to reason about than the current 15 trait labels. The traits stay as
**presets and descriptions** on top of the vector: "Hot-headed" means low agreeableness and high emotional
reactivity, and the editor can show either view.

| Axis | Low end ↔ high end | Typical effects |
|---|---|---|
| `honesty` | manipulative, status-seeking ↔ sincere, modest | apology sincerity, lying and gossip actions, pride |
| `emotionality` | thick-skinned ↔ reactive, sentimental | stress gain, threat appraisal, crying, need for support |
| `extraversion` | reserved ↔ outgoing | social need decay, energy from contact versus solitude |
| `agreeableness` | quarrelsome, grudging ↔ forgiving, gentle | argue bias, grudge decay, de-escalation chance |
| `conscientiousness` | chaotic ↔ orderly | hygiene and chores priorities, irritability about dishes, planning |
| `openness` | conventional ↔ curious | novelty bonus, value change speed, hobbies |

Mapping from the existing traits is a table of additive offsets, for example `vznetlivy` (hot-headed):
agreeableness −0.5, emotionality +0.3. Existing behaviour stays the same, which the regression tests guard.

### 2.2 V – values and worldview
	
	Each value axis is a record of five numbers:
	
	| Field | Range | Meaning |
	|---|---|---|
	| `pos` | −1..1 | where the character stands |
	| `certainty` | 0..1 | how firmly |
	| `importance` | 0..1 | how much it matters to them; low importance means a disagreement barely registers |
	| `openness_to_revise` | 0..1 | how willing they are to change their mind; correlated with personality openness, but stored separately |
	| `expression` | 0..1 | how openly they voice the view; a strong but private view can exist |
	
	The axes are kept **separate**. "Liberal versus conservative" is deliberately not a single axis, because
	economic, cultural and authority attitudes often diverge.
	
	| Axis | −1 ↔ +1 |
	|---|---|
	| `econ_equality` | market and self-reliance ↔ redistribution and social safety net |
	| `cultural_change` | tradition ↔ openness to social change |
	| `authority` | libertarian, anti-authority ↔ order and strong authority |
	| `institution_trust` | distrust of institutions and media ↔ trust |
	| `autonomy_privacy` | conformity ↔ personal freedom and privacy |
	| `solidarity` | "everyone for themselves" ↔ duty to help others |
	| `environment` | indifferent ↔ strongly protective |
	| `gender_diversity` | traditional gender norms ↔ fully accepting of LGBT+ identities |
	| `relationship_norms` | conventional (marriage, monogamy) ↔ open to other forms |
	
	**Separate dimensions, not a single "radicalism" axis.** These are tracked on their own and do not follow
	from the axes above:
	- `religiosity` (0..1) with a free tradition label;
	- `conspiracy_belief` (0..1), a tendency to explain events through hidden plots;
	- `extremism` (0..1), willingness to justify harm or coercion for a cause. It is kept very low and is
	  never glorified. In gameplay it only colours dialogue and how other characters react to the person.
	
	Rules:
	- There are no real-world parties and the game never scores an opinion as good or bad.
	- **Values are not behaviour.** They change appraisal and the probability of reactions, and they interact
	  with personality, emotion, relationship and social pressure. A traditional parent can still love their
	  child and try to keep the relationship.
	- **Mental state never determines political views.** Psyche dimensions and conditions affect
	  interpretation, certainty under stress and learning, never the *position* of a value. This prevents the
	  model from pathologising disagreement (review ChatGPT #127).
	- Values change slowly, through experience with people the character cares about, arguments in long
	  relationships and life events. Change is never guaranteed and never instant. `openness_to_revise` speeds
	  it up, high `certainty` slows it down.
	- "Who knows what about whom" (coming out, secrets) is a separate knowledge graph. It is planned after C8.
	
	### 2.3 D – psyche dispositions (9 dimensions, 0..1, default 0.5 = population average)

| # | Dimension | One-sentence meaning | Main consumers |
|---|---|---|---|
| 1 | `threat_sensitivity` | how readily ambiguity is read as danger | anxiety `threat`, panic hazard |
| 2 | `social_threat` | how strongly rejection or judgement is expected | interpretation of replies, cost of starting contact, approach–withdraw |
| 3 | `impulsivity` | how quickly urges become actions | planner temperature, interruptions, spending and drinking later |
| 4 | `regulation_capacity` | how well arousal and emotion come back down | arousal decay, shared relief budget, de-escalation |
| 5 | `predictability_need` | how much the character needs to know what comes next | stress from schedule changes and surprises, routine bonus |
| 6 | `sensory_sensitivity` | how intense noise, crowds and light feel | frictions (noise), crowd stress, preference for quiet places |
| 7 | `energy_baseline` | the character's own normal level of energy and drive | vigour, sleep need, baseline for episode detection (bipolar) |
| 8 | `reward_sensitivity` | how much joy activities bring | depression `liking`, novelty, habituation speed |
| 9 | `cognitive_flexibility` | how easily the character switches when things go differently | stress from plan disruption, rumination, OCD loop strength |

Later axes add their own dimensions, but only when needed: `working_memory`, `task_initiation` and
`attention_stability` for ADHD, `intrusion_salience` for OCD and `episode_propensity` for bipolar disorder.

**D is computed, not typed in:**
```
D = clamp( 0.5 + Σ trait/personality offsets + Σ condition modulations(severity) + jitter(seed) , 0, 1 )
```
It is recomputed when the inputs change. It can also drift slowly through lasting experience: therapy,
supportive relationships, chronic stress.

### 2.4 S – dynamic state (exists today)

These already exist and stay:
- stress;
- anxiety (`threat`, `arousal`, `sensitivity`, `regulation`, `support`, `mastery`);
- depression (`burden`, `wanting`, `liking`, `vigour`, `pessimism`, `scar`);
- mood and emotions, needs, good and bad days.

The new layers do not replace this state. **They parameterise it**: for example, the arousal decay rate is
multiplied by a function of `regulation_capacity`.

## 3. Modulations: how a profile changes the model

A modulation is a small, auditable record:

```json
{ "target": "D.social_threat", "op": "add", "amount": 0.30,
  "scale": "severity", "why": "Social anxiety: expected negative evaluation in social situations" }
```

| `op` | Meaning | Limit |
|---|---|---|
| `add` | shifts a baseline | \|amount\| ≤ 0.3 |
| `mul` | scales a sensitivity or rate | 0.5 ≤ factor ≤ 2.0 |
| `threshold` | moves a trigger threshold | \|amount\| ≤ 0.2 |
| `couple` | lets one dimension or state drive another (`from` → `to`, weight `w`) | \|w\| ≤ 0.5, graph must be **acyclic** |

Rules:
- Every modulation must have a non-empty `why`, and a test enforces this.
- Couplings are evaluated **once per game hour in a fixed topological order**, so the system cannot oscillate.
- Comorbidity: several profiles add up. The `add` ops are summed, the `mul` ops multiplied, and the result is
  clamped to the limits above, so two profiles can never produce an extreme state that neither could produce
  alone and no single condition becomes a death spiral.
- Modulations change **costs, probabilities, interpretations and rates**, never commands. No profile can
  remove an option from the player. The worst it can do is make an option "heavy", with higher initiation
  cost or a lower expected reward, and the HUD explains that in words.

## 4. Condition profiles (data, not code)

Each condition is a data file in `res://data/conditions/<id>.json`. Adding a condition does not need new code
unless it needs a new mechanism such as the OCD loop or the bipolar episode state machine.

```json
{
  "id": "social_anxiety",
  "label_cs": "Sociální úzkost",
  "content_tag": "mental_health",
  "severity": [0.2, 1.0],
  "modulations": [
    {"target": "D.social_threat", "op": "add", "amount": 0.30, "scale": "severity",
     "why": "expects negative evaluation"},
    {"target": "action.start_conversation.cost", "op": "mul", "amount": 1.6, "scale": "severity",
     "why": "initiating contact feels costly"},
    {"target": "S.anxiety.threat", "op": "couple", "from": "situation.observers", "w": 0.25,
     "why": "being watched raises threat"}
  ],
  "keeps_need": "social",
  "learning": {"exposure_mastery_gain": 1.0, "avoidance_sensitivity_gain": 1.0},
  "thought_pools": ["social_rumination"],
  "presentation": {"posture": "closed", "voice": "quieter"},
  "copings_affinity": {"breathe": 0.2, "hide": 0.3}
}
```

Notes on the example:
- `keeps_need: social` means the **need for company stays**, so the approach–withdraw cycle emerges by
  itself.
- `thought_pools` contains text pools only. They are always framed as thoughts, not facts, and never include
  methods or suicidal content.
- `presentation` is consumed by the future EmotionPresenter.

### 4.1 Planned profiles (one per run, order agreed in the room)

| Run | Profile | Mechanism beyond modulations |
|---|---|---|
| axis 1 | *(framework only: P, V, D, modulations and loader; existing anxiety and depression rewritten as profiles with identical behaviour)* | – |
| axis 2 | Social anxiety; fear of rejection and abandonment | interpretation of ambiguous replies; abandonment cue from contact gaps with close people |
| axis 3 | Burnout (a state, not a diagnosis); anxious depression | load × lack of control × lack of recovery accumulator; coupling chronic arousal → `burden` |
| axis 4 | OCD (checking, contamination, intrusive thoughts) | loop: intrusion → urge → compulsion → short relief → stronger next intrusion; exposure with response prevention weakens it |
| axis 5 | ADHD / ADD | working memory and task-initiation costs, attention drift during long actions, hyperfocus on high-reward actions (can overrun needs) |
| axis 6 | Bipolar disorder (I/II) | episode state machine over days or weeks: hypomanic or manic (less sleep need, energy far above **own** `energy_baseline`, impulsivity up) and depressive episodes; distinct from ADHD because it is episodic and relative to baseline |
| axis 7 | Autistic traits (a profile of axes, not a single label) | sensory sensitivity, predictability need, communication-style mismatch (misread replies on both sides), monotropic interests (deep reward, high switch cost) |
| later | PTSD | trigger memories bound to places, people or sounds; avoidance; flashbacks as intrusive thoughts; never graphic |
| later | Personality disorders (e.g. borderline, avoidant) | built from P and D patterns plus relationship-specific dynamics. **Never** villain templates, always with an inner perspective and a path to change |
| never playable | Self-harm, eating disorders | only through emotions, relationships and consequences; no methods, no actions, no numbers; hidden by default |

## 5. How the player configures it (character creator, C7)

1. **Default: nothing filled in.** No predispositions, D derived from personality only.
2. **Simple mode:** pick a condition from the list (only if the content settings allow it), plus severity
   (mild, moderate, severe). Each choice shows a plain explanation of what it changes and how recovery works.
3. **Advanced mode:** sliders for the 9 dimensions within ±0.3 of the derived value, and for value axes
   (position, certainty, importance). The editor shows a "what this means" text and an example situation.
4. **Individuality:** each character gets a fixed jitter of ±20 % on every modulation amount, from
   `mind.seed`. That seed is explicit, re-rollable and never derived from the name. Two "moderate social
   anxiety" characters therefore differ.
5. **Privacy:** P, V, D and C are private parts of `CharacterData`. The server validates them in strict mode
   and never puts them in spawn data. When the server's content settings are off, conditions are removed with
   a warning.

## 6. What the simulation does with it

- **Planner:** action cost, initiation barrier and expected reward come from D and S. Interruptions and
  novelty come from impulsivity and reward sensitivity.
- **Interpretation:** ambiguous signals (a short reply, a friend not answering, a look) are rated as threat
  with a probability from `social_threat` and `threat_sensitivity`, which feeds intrusive thoughts and grudges.
- **Relationships:** grudge decay and de-escalation come from agreeableness and regulation. Value distance
  multiplied by importance changes argument topics and friction. **Nothing is ever forced.**
- **Recovery:** exposure, support, routine, therapy and medication (planned) act on D and S through the same
  modulation records, as `why: "therapy: cognitive restructuring"` and so on. Recovery is never linear and
  never closed.
- **Presentation:** posture, face, breathing, music layers and silence read S and D through the future
  EmotionPresenter.

## 7. Tests required by every axis run

1. **Agency:** no action is ever removed or forced. The player can always act, also during episodes or
   attacks.
2. **Diversity:** five characters with the same profile in the same household show measurably different
   behaviour, above a threshold on action histograms.
3. **Context:** the same character in supportive, neutral and conflict environments has measurably different
   trajectories.
4. **Stability:** 16 seeds × 14 days with no oscillation, no runaway state, and recovery after stress within
   a bound.
5. **Neutral regression:** with no profile, all existing tests (anxiety 95, depression 92, reconciliation 58,
   household dynamics 78…) give the same results.
6. **Content settings:** with mental health off, profiles have no effect and are not offered. Muted caps
   intensity.
7. **Auditability:** every modulation has a `why`, all limits are respected, and the coupling graph is acyclic.
8. **Privacy:** P, V, D and C never leave the owner. There is a multiplayer test for this.

## 8. Open questions for review

- Should P use 6 HEXACO-like axes, or keep the 15 traits as the only source and derive P from them? The
  proposal is to store P and treat traits as presets.
- Should value change in V be visible to the player as a slow drift in the character sheet, in words only?
- Should D drift through life events, and if so how fast? The proposal is weeks of game time with a cap of
  ±0.15 from the derived value.

## 9. Implementation notes (run 20)

- **Residual instead of replacement.** The existing mechanics already express traits and the anxiety and
  depression predispositions. Rewriting them in one step would change every tuned test. So each
  contribution to D is marked *carried* when an existing mechanism already applies it (trait effects,
  personality derived from traits, profiles with a `legacy` block). `D_legacy` is D computed from carried
  contributions only and without individuality. Hooks read only `D − D_legacy`. Without character data
  the hooks are neutral and the old behaviour is reproduced bit for bit (tested).
- **Individuality** is deterministic: CRC-32 of `(psyche_seed, source, dimension)` gives ±20 % per
  contribution, and three uniform draws give an own offset per dimension (sd ≈ 0.05). The seed is migrated
  once from the random uid (schema v4 → v5) and is never derived from the name.
- **Hooks in MentalState:** `arousal_decay_tau`, `threat_gain`, `crowd_gain`, `social_cost`,
  `unhealthy_appeal`, `healthy_appeal`, `panic_shift` and the ordered couplings. All multipliers are
  clamped to 0.7–1.3.
- **Comorbidity:** profile `add` contributions on one dimension are clamped to ±0.3 in total, `mul` to
  0.5–2, thresholds to ±0.2.
- Axis 2 onwards adds profiles **without** a legacy block. Their D modulations then act through the
  residual directly, and the legacy numbers can be migrated to D-driven mechanics one system at a time.


## Implemented extension — hypervigilance (24 October 2026)

The D layer has **10** dimensions as implemented in `scripts/psyche/psyche_model.gd` and
`CharacterSchema.PSYCHE_SLIDERS` (the nine-row original table above documents the prior baseline).
An optional `D.hypervigilance` slider [0,1] was added; missing values are derived from personality
and retain compatible defaults. Existing `D.threat_sensitivity` interprets ambiguity as danger;
`D.social_threat` is the expectation of judgement/rejection; **neither is synonymous with vigilance**.
The existing noise-specific sensory profile (`SensoryProfile.noise_sens`) remains unchanged and independent.

Server/offline `SimAgent.vigilance` is a separate mutable state (`alertness`) that responds to
conflict, being insulted, a rejected apology, safety and passage of game time. It uses the three
D dimensions, bounded event impulses and a decay toward the individual baseline, including during
sleep. Explicit negative social cues are distinguished from ambiguous social appraisal. Safe encounters
can reduce heightened vigilance without forcing trust. No FCCS coupling, no automatic diagnosis,
no forced player action, and no private mental state in public spawn data. The `mind.dispositions`
axes are optional so schema v8 remains valid; validate range 0..1 on authority and JSON round-trip.
Regression: `tests/test_vigilance.tscn`. This is a gameplay model, not a clinical simulator.


## Implemented extension — rejection reactivity and broad hypersensitivity (24 October 2026)

The `D` model now has **11 optional dimensions**. Existing `D.social_threat` represents
**anticipated** social rejection; `D.threat_sensitivity` represents the interpretation of
ambiguity as danger; `D.hypervigilance` represents ongoing attention to possible threats.
**New `D.rejection_reactivity` (0..1)** independently determines the intensity of emotional
response to actual and *perceived* rejection. A perceived cue is always treated as subjective
appraisal, not evidence of someone else's intentions. Older schema-v8 characters without
the new key remain valid and derive their baseline from personality.

`scripts/sim/rejection_response.gd` stores short-lived private distress, attenuated
repeated cues and recovery through passage of time, rest and support. Runtime events include
explicitly rejected apologies, dismissal when seeking support, being insulted and occasional
ambiguous interpretation after an objectively positive chat. The last mechanism uses a
bounded probability derived from social/threat appraisal **independently of whether intrusive
thought text is shown**. Emotional reactions produce bounded, temporary mood/stress/arousal
effects; they never dictate behaviour, diagnoses or long-term fate.

**Self-harm is not enacted:** the optional and private `safety_concern` boolean means
"additional support may be needed" when accumulated distress coexists with severe strain
and poor regulation/support. It is available only with **both**
`mental_health = full` and the opt-in `sh_ed_topics = true`; it never enters public
snapshots, `net_detail`, actions, rewards or automated injury outcomes. It is not a
clinical risk score. Support and recovery can clear the concern. Content stays hidden by
default and the vision content restrictions remain unchanged.

`D.sensory_sensitivity` is displayed as **Hypersenzitivita (smyslová citlivost)**,
not as noise sensitivity alone. `SensoryProfile.configure(D)` applies an interpretable,
bounded gain to noise and crowd responses in the live simulation. Touch and bright-light
factors are prepared for future tactile/brightness event producers; those producers have
**not** yet been integrated. Existing independent `noise_sens`, `crowd_sens`,
noise/crowd habituation and positive daylight enjoyment remain distinct and compatible.
No FCCS wiring. New regression: `tests/test_rejection_hypersensitivity.tscn`.
