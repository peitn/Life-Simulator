extends "res://tests/test_base.gd"

const Traits := preload("res://scripts/sim/traits.gd")
const Mental := preload("res://scripts/sim/mental_state.gd")
const Agent := preload("res://scripts/sim/sim_agent.gd")

class TestWorld extends Node:
	var sims: Array = []
	func get_sims() -> Array:
		return sims

class TestAgent extends "res://scripts/sim/sim_agent.gd":
	func _ready() -> void:
		pass # real social methods, without the visual/clock lifecycle

func _ready() -> void:
	section("Order-independent scalar and profile aggregation")
	var a := {"brucoun": 0.5, "vznetlivy": 0.5}
	var b := {"vznetlivy": 0.5, "brucoun": 0.5}
	check(Traits.get_param(a, "pride", 0.0) == Traits.get_param(b, "pride", 0.0), "same values in different insertion orders are identical")
	check(is_equal_approx(Traits.get_param(a, "pride", 0.0), 0.825), "overlapping overrides have weighted mean")
	check(Traits.get_param({}, "argue_stress_cap", 80.0) == 80.0, "empty profile preserves fallback")
	check(Traits.get_param({"vznetlivy": 0.0}, "argue_stress_cap", 80.0) == 80.0, "zero strength preserves fallback")
	check(Traits.get_param({"vznetlivy": 0.5}, "argue_stress_cap", 80.0) == 72.5, "single fractional override interpolates")
	check(Traits.get_param(["vznetlivy"], "argue_stress_cap", 80.0) == 65.0, "legacy endpoint preserved")
	check(Traits.mult_param(a, "pride") == Traits.mult_param(b, "pride"), "multipliers use canonical dictionary order")
	section("No binary impulse threshold")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mental := Mental.new(rng, "f")
	mental.stress = 80.0
	mental.arousal = 70.0
	var cfg := {"mental": "full", "addiction": true}
	var low := mental.coping_appeal("drink", 50.0, 50.0, 0.0, 0.0, cfg)
	var high := mental.coping_appeal("drink", 50.0, 50.0, 0.0, 1.0, cfg)
	check(high > low and low > 0.0, "impulsivity changes an active coping score")
	for value in [0.1, 0.49, 0.5, 0.51, 0.9]:
		var score := mental.coping_appeal("drink", 50.0, 50.0, 0.0, value, cfg)
		check(is_equal_approx(score, lerpf(low, high, value)), "continuous coping at %.2f" % value)
	check(mental.coping_appeal("drink", 50.0, 50.0, 0.0, true, cfg) == high, "legacy boolean endpoint remains compatible")
	section("Real jealousy consequences scale below and above 0.5")
	var world := TestWorld.new()
	var speaker := TestAgent.new()
	var partner := TestAgent.new()
	var witness := TestAgent.new()
	speaker.setup("Speaker", "f", [], Color.WHITE, 1, world)
	partner.setup("Partner", "f", [], Color.WHITE, 2, world)
	witness.setup("Witness", "f", [], Color.WHITE, 3, world)
	world.sims = [speaker, partner, witness]
	add_child(world)
	world.add_child(speaker)
	world.add_child(partner)
	world.add_child(witness)
	witness.speech = "occupied" # avoid presentation/randomness in this consequence test
	for value in [0.0, 0.1, 0.49, 0.5, 0.51, 1.0]:
		witness.trait_profile = {"zarlivy": value}
		witness.relationships = {"Speaker": 60.0, "Partner": 0.0}
		witness.ledger.grudges.clear()
		witness.mood.remove_moodlet("zarli_" + String(partner.name))
		speaker._check_jealousy(partner, cfg)
		check(is_equal_approx(float(witness.relationships["Partner"]), -2.0 * value), "relationship consequence at %.2f" % value)
		check(is_equal_approx(witness.ledger.grudge("Partner"), 3.0 * value), "grudge consequence at %.2f" % value)
	speaker.free()
	partner.free()
	witness.free()
	world.free()
	finish("test_trait_continuity")
