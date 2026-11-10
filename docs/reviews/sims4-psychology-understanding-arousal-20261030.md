# Sims 4 Psychology Alpha v0.2 — Understanding, arousal, adult-intimacy axis audit
Date: 2026-10-30. Development lock: main-sims4-psych-expanded-1793365417-180381

## Actual original Life Simulator state
- scripts/sim/mental_state.gd has physiological 'arousal' (0–100),
  separate positive_arousal, stress, and threat. Pleasant activation is not
  assumed to be threat/panic; 'aversive_arousal()' uses negative share.
- scripts/sim/intimacy_state.gd separately models sexual_arousal,
  sexual_preoccupation, baseline libido and drive dysregulation, orientation
  and valid consent. sexual_arousal does not grant consent.
- scripts/character/character_schema.gd has independent identity.libido,
  drive_dysregulation, asexual, aromantic fields. Character schema personality
  has HEXACO agreeableness and values.care; **there was no direct
  willingness-to-understand-another-person slider**.

## Implemented in separate Python Sims4 adaptation (NOT original Godot game)
- Three new explicit and distinct social sliders:
  mind.social.understanding_willingness, perspective_taking, empathic_concern.
  These are labelled Sims4 extensions rather than claimed pre-existing fields.
- Adult identity fields copied from actual CharacterSchema: two floats
  identity.libido and identity.drive_dysregulation; 2 bools identity.asexual,
  identity.aromantic, explicitly independent.
- Six dynamic meter definitions, distinct from 19 emotions:
  general_arousal, positive_arousal, stress, perceived_threat,
  sexual_arousal and sexual_preoccupation. Only the last two are adult-only.
- Counts updated from 103 numerics +3 booleans to 108 numerics +5 booleans;
  19 emotional meters plus six physiological/intimate meters; 13 original
  social memory types, nine worldview topics, seven values.
- Implemented age gate and bounded numerical APIs, private storage,
  temporal decay/targets for activation and sexual drive (approximate port
  of the original GDScript mechanics, not identical implementation).
  No sexual act, forced consent, or sexual-scored autonomous action.
- Understanding willingness influences propensity to listen, clarify
  and soften misunderstandings without deleting an actual interaction or
  assuming one can read someone's private mind.
- Tested social-event adapter VerifiedSocialEventBridge: accepts only
  externally verified completed interaction with unique token and known
  event type; map from chat, argument, apology, comfort, listening etc to
  psyche events. Real Sims4 interaction-completion hook is not yet installed.
- Companion HTML editor now offers new sliders, meters and age/explicit adult
  controls. Unknown-age profiles omit adult fields on import. Profile user age
  is not proof of real TS4 Sim age; future binding must use actual SimInfo.
- Extended mock TS4 commands: lifesim.adult, lifesim.meter,
  lifesim.social (info about missing real integration).
- Reproducible rebuild_catalog.py from immutable original
  godot_psyche_source_v20.json prevents repeated duplication.

## Tests and limits
- 31/31 Python unit tests passed: base memory and worldview + social willingness,
  distinct general vs sexual arousal, age guard, saved private state, value
  independence, no arousal to consent, verified-event boundary, mocked TS4
  command registration. Python 3.7 AST parse passes.
- Package ZIP and .ts4script generated; editor embeds all 113 character fields,
  19 emotional values and six dynamic meters; actual ZIP is byte-valid.
- No actual EA The Sims 4 installation/runtime available. Its event hooks,
  buffs, autonomous actions, UI integration, save slot handling and game patch
  1.129.39 compatibility are NOT verified. Offline tests are not in-game tests.
- No web browser interactive click test for the companion editor. Source HTML
  contains the age toggle, all fields and exported JSON boundaries; browser
  download and UI still require device check.

Public:
https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyAlpha.zip
https://peiti-godot-mcp.hf.space/play/lifesim/LifeSimPsychologyEditor.html

Further work: obtain a real installed TS4 process, validate current game
SimInfo age + interaction callback semantics, configure actual verified social
completion in adapter, enable native buffs/relationship integration and
in-game psychology editor. Do not use unverified game API by guesswork.
