extends "res://tests/test_base.gd"
## Character Schema v8: continuous trait, psyche disposition and condition sliders.

const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const PM := preload("res://scripts/psyche/psyche_model.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")


func _ready() -> void:
	section("Slider schema, migration and backwards compatibility")
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = ["optimista"]
	check(Schema.VERSION == 8, "schema v8")
	check((d["personality"]["trait_levels"] as Dictionary).is_empty(), "legacy stays unchanged before editing")
	check((d["mind"]["dispositions"] as Dictionary).is_empty(), "unspecified dispositions are derived")
	check(is_equal_approx(float(d["mind"]["self_defectiveness"]), 0.0),
		"inner belief has neutral default and is not an emotion meter")
	var older := d.duplicate(true)
	older["v"] = 7
	older["personality"].erase("trait_levels")
	older["mind"].erase("dispositions")
	var migrated := Codec.migrate(older)
	check(migrated["ok"] and migrated["data"]["v"] == 8, "migration v7 to v8")
	check(migrated["data"]["personality"]["trait_levels"] == {}, "legacy traits preserved when migrating")
	check(absf(Traits.mood_bias(["optimista"]) - 8.0) < 0.0001, "legacy categorical personality same effect")
	section("Independent intensities affect simulation smoothly")
	check(absf(Traits.mood_bias({"optimista": 0.5}) - 4.0) < 0.0001, "half-strength optimism = half bias")
	check(absf(Traits.chemistry({"brucoun": 0.25}) - Traits.chemistry(["brucoun"]) * 0.25) < 0.0001, "quarter-strength chemistry")
	check(Traits.tag_multiplier({"samotar": 0.5}, "social") < 1.0 and Traits.tag_multiplier({"samotar": 0.5}, "social") > Traits.tag_multiplier(["samotar"], "social"), "continuous social preference")
	check(Traits.weight({"brucoun": 0.9, "optimista": 0.9}, "brucoun") == 0.9 and Traits.weight({"brucoun": 0.9, "optimista": 0.9}, "optimista") == 0.9, "opposites can coexist; no budget")
	d["personality"]["trait_levels"] = {"optimista": 0.25, "brucoun": 0.75, "spolecensky": 0.5, "samotar": 0.5}
	d["mind"]["predispositions"] = {"anxiety": 0.4, "depression": 0.7}
	d["mind"]["dispositions"] = {"social_threat": 0.9, "regulation_capacity": 0.2}
	d["mind"]["self_defectiveness"] = 0.72
	var v := Validator.validate(d)
	check(v["ok"], "slider profile accepted by validator", str(v["errors"]))
	var broken := d.duplicate(true)
	broken["personality"]["trait_levels"]["brucoun"] = 1.7
	check(not Validator.validate(broken)["ok"], "out-of-range values rejected on server")
	broken = d.duplicate(true)
	broken["mind"]["dispositions"]["social_threat"] = INF
	check(not Validator.validate(broken)["ok"], "infinite values rejected")
	broken = d.duplicate(true)
	broken["mind"]["self_defectiveness"] = 1.2
	check(not Validator.validate(broken)["ok"], "belief above one rejected by strict server validator")
	broken = d.duplicate(true)
	broken["mind"]["self_defectiveness"] = INF
	check(not Validator.validate(broken)["ok"], "non-finite private belief is rejected")
	var c := CharacterData.create()
	c.set_from_dict(v["data"])
	var pub: Dictionary = c.public_snapshot()
	check(not pub.get("personality", {}).has("trait_levels") and not pub.has("mind"), "trait and mental sliders remain private")
	check(is_equal_approx(float(c.mind.get("self_defectiveness", 0.0)), 0.72),
		"belief survives schema validator and CharacterData")
	var parsed := Codec.from_json(Codec.to_json(c.to_dict()))
	check(parsed["ok"] and absf(parsed["data"]["personality"]["trait_levels"]["brucoun"] - 0.75) < 0.001, "JSON round trip retains decimals")
	var computed := PM.compute(c.to_dict(), {"individual": false})
	check(absf(computed["D"]["social_threat"] - 0.9) < 0.001 and absf(computed["D"]["regulation_capacity"] - 0.2) < 0.001, "psychological dimensions directly editable")
	var p0 := PM.traits_personality({"spolecensky": 0.0})
	var p05 := PM.traits_personality({"spolecensky": 0.5})
	var p1 := PM.traits_personality({"spolecensky": 1.0})
	check(absf(p05["extraversion"] * 2.0 - p1["extraversion"]) < 0.001 and p0["extraversion"] == 0.0, "personality model uses continuous trait intensities")
	section("Runtime and reusable slider panel")
	var sim := Node3D.new()
	sim.set_script(SimAgent)
	sim.setup("Alex", "m", ["optimista"], Color.WHITE, 42, null)
	sim.apply_character_private(c.to_dict())
	check(absf(Traits.mood_bias(sim.trait_profile) - (0.25 * 8.0 + 0.75 * -6.0)) < 0.001, "autonomous agent consumes weighted profile")
	check(absf(sim.mental.conditions.get("anxiety", 0.0) - 0.4) < 0.001, "continuous anxiety applies to mental engine")
	check(is_equal_approx(sim.self_defectiveness_belief, 0.72),
		"simulation reads stable inner belief rather than transient emotional intensity")
	var shy_weight: float = float(sim.emotional_target_weight("Somebody", "chat"))
	sim.self_defectiveness_belief = 0.0
	check(sim.emotional_target_weight("Somebody", "chat") > shy_weight,
		"inner belief modestly biases voluntary social approach but does not force action")
	sim.free()
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var readout := Label.new()
	ui._on_slider(0.37, "trait_levels", "brucoun", readout)
	ui._on_slider(0.62, "dispositions", "social_threat", readout)
	ui._on_slider(0.86, "mind_belief", "self_defectiveness", readout)
	check(ui._list.get_child_count() > 30, "editor builds sliders for every trait and psychological axis")
	check(absf(ui.export_data()["personality"]["trait_levels"]["brucoun"] - 0.37) < 0.001, "trait slider writes strength")
	check(absf(ui.export_data()["mind"]["dispositions"]["social_threat"] - 0.62) < 0.001, "disposition slider writes strength")
	check(absf(float(ui.export_data()["mind"]["self_defectiveness"]) - 0.86) < 0.001,
		"dedicated slider saves stable private self-belief")
	check(ui.find_child("BeliefDefectiveness", true, false) is HSlider,
		"actual visible slider widget exists in psyche section")
	readout.free()
	ui.free()
	section("New characters are continuous")
	var r := RandomNumberGenerator.new()
	r.seed = 221
	var generated := Randomizer.generate(r)
	var levels: Dictionary = generated["personality"]["trait_levels"]
	check(levels.size() == Schema.TRAIT_SLIDERS.size(), "new characters populate all 15 axes")
	var has_fraction := false
	for id in levels:
		if float(levels[id]) > 0.0 and float(levels[id]) < 1.0:
			has_fraction = true
	check(has_fraction, "new characters have fractional intensities, not just on/off traits")
	finish("test_personality_sliders")
