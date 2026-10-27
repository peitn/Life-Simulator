extends "res://tests/test_base.gd"
## Integration regression: pleasant vs aversive physiological arousal in Life Simulator.

const Mental := preload("res://scripts/sim/mental_state.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const PsycheFX := preload("res://scripts/world/psyche_fx.gd")
const Data := preload("res://scripts/character/character_data.gd")

func _has_id(entries: Array, id: String) -> bool:
	for e in entries:
		if String(e.get("id", "")) == id:
			return true
	return false


func _context() -> Dictionary:
	return {"energy": 70.0, "hunger": 70.0,
		"needs": {"hunger": 70.0, "energy": 70.0, "fun": 70.0, "social": 70.0},
		"sleeping": false, "night": false,
		"cfg": {"conditions": false, "episodes": false, "thought_rate": 0.0}}


func _ready() -> void:
	section("Single arousal intensity, independently signed valence")
	var happy = Mental.new()
	var before_stress: float = happy.stress
	var before_threat: float = happy.threat
	check(happy.positive_arousal == 0.0 and absf(happy.arousal_valence()) < 0.00001,
		"legacy baseline has no extra positive source or spurious valence")
	happy.on_positive_stimulus(80.0)
	check(happy.arousal >= 80.0 and happy.positive_arousal == 80.0,
		"positive event raises real physiological arousal")
	check(happy.stress == before_stress and happy.threat == before_threat,
		"excitement does not fabricate stress or perceived threat")
	check(happy.arousal_valence() > 0.70 and happy.pleasant_arousal_share() > 0.70,
		"pleasant valence and source fraction are explicitly positive")
	check(_has_id(happy.mood_entries(), "nabuzeni") and not _has_id(happy.mood_entries(), "uzkost"),
		"high pleasant arousal appears as excitement, not anxiety")
	check(happy.state_label().contains("Nadšení") and not happy.state_label().contains("úzkost"),
		"private state label distinguishes excitement from fear")

	var fear = Mental.new()
	fear.arousal = happy.arousal
	fear.stress = 85.0
	fear.threat = 0.8
	check(absf(fear.arousal - happy.arousal) < 0.00001 and fear.arousal_valence() < -0.7,
		"identical physical activation can have the opposite valence")
	check(_has_id(fear.mood_entries(), "uzkost") and not _has_id(fear.mood_entries(), "nabuzeni"),
		"threat-associated arousal still produces anxiety")
	check(fear.social_difficulty() > happy.social_difficulty() + 0.20,
		"pleasant excitement is not automatically a social anxiety penalty")
	check(fear.coping_appeal("breathe", 70.0, 70.0, 0.0) > happy.coping_appeal("breathe", 70.0, 70.0, 0.0),
		"coping urgency uses aversive arousal, not physical excitement alone")
	check(happy.sleep_quality() < Mental.new().sleep_quality() and happy.energy_drain_mult() > 1.0,
		"pleasant high arousal still has physical consequences for sleep and fatigue")
	var happy_mind: Dictionary = happy.detail()
	var fear_mind: Dictionary = fear.detail()
	check(int(happy_mind["arousal"]) > 75 and int(happy_mind["aversive_arousal"]) < 40,
		"private HUD retains true body arousal and marks the aversive portion separately")
	check(PsycheFX.target_level(happy_mind, 1.0) == 0.0 and
		PsycheFX.target_level(fear_mind, 1.0) > 0.7,
		"positive excitement does not cause anxiety vision effects; distress still does")
	check(PsycheFX.target_level({"arousal": 90}, 1.0) > 0.7,
		"legacy private packets remain compatible with anxiety screen effects")

	section("Bounded stimulus, recovery, persistence and old saves")
	var bounded = Mental.new()
	bounded.on_positive_stimulus(-10.0)
	bounded.on_positive_stimulus(NAN)
	bounded.on_positive_stimulus(INF)
	check(bounded.positive_arousal == 0.0, "negative, NaN and infinity cannot poison excitation state")
	bounded.on_positive_stimulus(10000.0)
	bounded.on_positive_stimulus(10000.0)
	check(bounded.positive_arousal == 100.0 and bounded.arousal == 100.0,
		"intensity and positive drive remain bounded even for extreme events")
	var saved: Dictionary = happy.to_dict()
	var restored = Mental.new()
	restored.from_dict(saved)
	check(absf(restored.arousal - happy.arousal) < 0.001
		and absf(restored.positive_arousal - 80.0) < 0.001,
		"save/load preserves both physical intensity and its positive source")
	check(absf(restored.arousal_valence() - happy.arousal_valence()) < 0.00001,
		"round-trip preserves derived valence without duplicate state")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("positive_arousal")
	var migrated = Mental.new()
	migrated.from_dict(legacy)
	check(migrated.positive_arousal == 0.0 and migrated.arousal == happy.arousal,
		"legacy saved character still loads with unchanged arousal")
	legacy["positive_arousal"] = INF
	migrated.from_dict(legacy)
	check(migrated.positive_arousal == 0.0,
		"invalid saved excitement is safely reset")
	var settling = Mental.new()
	settling.on_positive_stimulus(80.0)
	var early: float = settling.positive_arousal
	settling.tick(20.0, _context())
	check(settling.positive_arousal < early and settling.positive_arousal > 0.0,
		"excitement begins to decline when the positive stimulus ends")
	for i in 60:
		settling.tick(10.0, _context())
	check(settling.positive_arousal < 0.2 and settling.arousal < 30.0,
		"unstimulated character eventually returns toward baseline without runaway")
	check(not _has_id(settling.mood_entries(), "nabuzeni"),
		"positive moodlet disappears after physical recovery")
	var threatened = Mental.new()
	threatened.on_positive_stimulus(70.0)
	threatened.stress = 85.0
	threatened.threat = 0.8
	check(threatened.pleasant_arousal_share() < 0.55 and
		not _has_id(threatened.mood_entries(), "nabuzeni"),
		"strong real threat is not erased by a simultaneous pleasant stimulus")

	section("Profile coupling must not turn joy into depressive burden")
	var edges: Array = [{"from": "S.arousal", "target": "S.burden",
		"op": "couple", "w": 0.5}]
	var joyful = Mental.new()
	joyful.on_positive_stimulus(90.0)
	joyful.set_psyche({"full": {"couples": edges}})
	var distressed = Mental.new()
	distressed.arousal = joyful.arousal
	distressed.set_psyche({"full": {"couples": edges}})
	var linked_ctx: Dictionary = _context()
	linked_ctx["cfg"] = {"mode": "full", "conditions": false,
		"episodes": false, "thought_rate": 0.0}
	joyful.tick(60.0, linked_ctx)
	distressed.tick(60.0, linked_ctx)
	check(joyful.positive_arousal > 0.0 and joyful.arousal > distressed.arousal,
		"pleasant physiological intensity survives the profile graph update")
	var no_edges = Mental.new()
	no_edges.on_positive_stimulus(90.0)
	no_edges.tick(60.0, linked_ctx)
	var actual_coupling: float = joyful.dep.burden - no_edges.dep.burden
	var expected_aversive: float = joyful.aversive_arousal() / 100.0 * 0.5 * 0.1
	var incorrect_total: float = joyful.arousal / 100.0 * 0.5 * 0.1
	check(joyful.dep.burden < distressed.dep.burden,
		"higher aversive share gives higher burden despite lower physical intensity")
	check(absf(actual_coupling - expected_aversive) < 0.0002 and
		absf(actual_coupling - incorrect_total) > 0.01,
		"coupled burden matches exact aversive model, not a raw joy multiplier")
	check(no_edges.dep.burden <= joyful.dep.burden,
		"coupled effect stays bounded relative to uncoupled pleasant activation")

	section("Real autonomous character uses positive events, no refresh farming")
	var sim = SimAgent.new()
	sim.setup("Alex", "m", [], Color.WHITE, 51, null)
	var sim_stress: float = sim.mental.stress
	sim.add_joy_moodlet("exciting_event", "Úžasný zážitek", "energicky", 30.0, 120.0)
	check(sim.mental.positive_arousal > 10.0 and sim.mental.arousal > 20.0,
		"gameplay positive moodlet actually drives the character mental state")
	check(sim.mental.stress == sim_stress and sim.mental.threat == 0.0,
		"gameplay excitement does not force an anxiety condition")
	var once: float = sim.mental.positive_arousal
	sim.add_joy_moodlet("exciting_event", "Úžasný zážitek", "energicky", 30.0, 120.0)
	check(sim.mental.positive_arousal == once,
		"refreshing the same event cannot farm excitement")
	sim.mood.evaluate(sim.needs, sim.trait_profile, sim._extra_moodlets())
	check(sim.mood.emotion == "energicky"
		and Mood.emotion_tag_multiplier(sim.mood.emotion, "exercise") > 1.0,
		"positive arousal feeds Mood and autonomous Utility AI action preferences")
	var old_mood: float = sim.mental.positive_arousal
	sim.add_joy_moodlet("sad_event", "Smutek", "smutny", -8.0, 120.0)
	check(sim.mental.positive_arousal == old_mood,
		"negative moodlets cannot create positive excitation")
	var cd = Data.create()
	check(not cd.public_snapshot().has("mind"),
		"private mental state is not placed in public CharacterData snapshot")
	sim.free()

	section("Avoid a panic attack caused only by excitement")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var predisposed = Mental.new(rng)
	predisposed.conditions = {"anxiety": 0.9}
	predisposed.sensitivity = 0.8
	predisposed.on_positive_stimulus(95.0)
	check(predisposed.aversive_arousal() < Mental.PANIC_THRESHOLD
		and predisposed.arousal >= Mental.PANIC_THRESHOLD,
		"very high physical activation has non-panic pleasant valence")
	predisposed.tick(1.0, {"energy": 70.0, "hunger": 70.0,
		"needs": {}, "sleeping": false, "night": false,
		"cfg": {"conditions": true, "episodes": true, "thought_rate": 0.0}})
	check(not predisposed.panic_active,
		"single positive high-activation event does not automatically trigger panic")

	finish("test_arousal_valence")
