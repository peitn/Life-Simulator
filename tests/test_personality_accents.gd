extends "res://tests/test_base.gd"
## Psychika D – osobnostní akcenty (mind.accents, v13): zvýrazněné rysy jako váhy existujících parametrů
## a háčky do vztahových systémů, mezilidské vzorce, volitelný soukromý výklad, režimy, rozmanitost,
## agency, uložení, soukromí, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const PersonalityAccents := preload("res://scripts/sim/personality_accents.gd")
const RelLedger := preload("res://scripts/sim/rel_ledger.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 240.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_schema()
	_test_weights_and_hooks()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_personality_accents")


func _agent(accents: Dictionary, labels := false) -> Node3D:
	var sim := Node3D.new()
	sim.set_script(SimAgent)
	sim.setup("Alex", "m", ["optimista"], Color.WHITE, 42, null)
	sim.apply_character_private(Validator.validate(U.character(0, {"accents": accents, "accent_labels": labels}))["data"])
	return sim


func _test_schema() -> void:
	section("Schéma v13")
	check(Schema.VERSION >= 13 and Schema.ACCENT_SLIDERS.size() == 8 and Schema.fields("mind").has("accent_labels"), "mind.accents (8 os) a accent_labels")
	var d := U.character(0, {"accents": {"suspicious": 0.7}, "accent_labels": true})
	check(Validator.validate(d)["ok"], "platné")
	var bad := d.duplicate(true)
	bad["mind"]["accents"]["villain"] = 1.0
	check(not Validator.validate(bad)["ok"], "neznámý akcent se odmítne (žádné šablony záporáků)")
	var old := d.duplicate(true)
	old["v"] = 12
	old["mind"].erase("accents")
	old["mind"].erase("accent_labels")
	var m := Codec.migrate(old)
	check(m["data"]["mind"]["accents"] == {} and m["data"]["mind"]["accent_labels"] == false, "migrace v12 → v13")
	var off: Dictionary = Validator.validate(d, {"mental_health": "off"})["data"]["mind"]
	check(off["accents"] == {} and off["accent_labels"] == false, "off: akcenty se nepřijmou")
	var leg := d.duplicate(true)
	leg["personality"]["traits"] = ["optimista", "acc_suspicious"]
	check(not Validator.validate(leg)["ok"], "akcent nejde vybrat jako legacy rys / předvolbu")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(d)["data"])
	check(not U.contains_key(c.public_snapshot(), ["accents", "accent_labels"]) and not (c.public_snapshot()["personality"]["traits"] as Array).has("acc_suspicious"),
		"veřejný snapshot bez akcentů")
	check(not Traits.random_traits(RandomNumberGenerator.new(), 5).any(func(x): return String(x).begins_with("acc_")), "náhodný generátor akcenty nebere")


func _test_weights_and_hooks() -> void:
	section("Váhy existujících parametrů a háčky")
	var neutral := _agent({})
	check(typeof(neutral.trait_profile) == typeof(neutral._base_trait_profile) and neutral.trait_profile == neutral._base_trait_profile \
		and neutral.emotions.amplitude == 1.0 and neutral.ledger.trust_gain_mult == 1.0 and neutral.mental.accent_social_cost == 0.0,
		"bez akcentů: profil a háčky přesně beze změny")
	var s4 := _agent({"suspicious": 0.4})
	var s8 := _agent({"suspicious": 0.8})
	check(Traits.chemistry(s8.trait_profile) < Traits.chemistry(s4.trait_profile) and Traits.chemistry(s4.trait_profile) < Traits.chemistry(neutral.trait_profile),
		"podezíravost: spojitě horší chemie")
	check(Traits.sum_param(s8.trait_profile, "forgiveness") < Traits.sum_param(neutral.trait_profile, "forgiveness")
		and Traits.mult_param(s8.trait_profile, "grudge_tau") > Traits.mult_param(neutral.trait_profile, "grudge_tau"), "odpouští hůř, zášť drží déle")
	var l1 := RelLedger.new()
	var l2 := RelLedger.new()
	l2.trust_gain_mult = s8.ledger.trust_gain_mult
	l1.record_trust("x", "warm", 10.0)
	l2.record_trust("x", "warm", 10.0)
	check(l2.trust_in("x") < l1.trust_in("x"), "důvěra roste pomaleji")
	check(s8.perceived_rejection_chance() > neutral.perceived_rejection_chance(), "víc domnělého odmítnutí")
	var ab := _agent({"abandonment": 0.9})
	var det := _agent({"detachment": 0.9})
	check(ab.psy.accents.rejection_mult() > 1.4 and det.psy.accents.rejection_mult() < 1.0, "citlivost na opuštění zesílí reakci na odmítnutí, odstup ji tlumí")
	check(ab.emotions.amplitude > 1.3 and det.emotions.amplitude < 0.7, "emoční výkyvy vs. oploštění")
	check(Traits.flag_strength(ab.trait_profile, "jealous") > 0.8, "citlivost na opuštění vede k žárlivosti (existující mechanika)")
	check(Traits.tag_multiplier(det.trait_profile, "social") < Traits.tag_multiplier(neutral.trait_profile, "social") * 0.7, "odstup: méně chuti na lidi")
	var av := _agent({"avoidance": 1.0})
	av.mental.arousal = 40.0
	neutral.mental.arousal = 40.0
	check(av.mental.social_difficulty() > neutral.mental.social_difficulty(), "vyhýbavost: sociální akce náročnější (omezeně)")
	var dep := _agent({"dependency": 1.0})
	check(dep.psyche_action_weight(ActionLibrary.get_action("confide")) > 1.2, "závislost: víc se svěřuje")
	var gr := _agent({"grandiosity": 1.0})
	check(Traits.mult_param(gr.trait_profile, "pride") < 0.6 and gr.psyche_action_weight(ActionLibrary.get_action("apologize")) < 1.0,
		"grandiozita: omlouvá se nerad (pýcha z existující mechaniky)")
	var pf := _agent({"perfectionism": 1.0})
	check(pf.psy.accents.rumination_mult("failure") > 1.7 and Traits.mult_param(pf.trait_profile, "irritability") > 1.3,
		"perfekcionismus: nezdar se přemílá, drobnosti v domácnosti víc vadí")
	section("Rozmanitost a výklad")
	var a1 := _agent({"abandonment": 0.8, "detachment": 0.6})
	var a2 := _agent({"abandonment": 0.8, "dependency": 0.8})
	check(absf(a1.emotions.amplitude - a2.emotions.amplitude) > 0.2 and a2.psy.accents.attachment_mult() > a1.psy.accents.attachment_mult() + 0.4,
		"stejný „hraniční“ akcent, jiný zbytek profilu → jiné vzorce")
	check(a1.psy.accents.labels().is_empty(), "bez souhlasu žádný výkladový název")
	var lab := _agent({"abandonment": 0.8}, true)
	check(String("".join(lab.psyche_private_lines())).contains("emoční nestability"), "volitelný soukromý výklad názvem")
	section("Režimy")
	var pa := PersonalityAccents.new()
	pa.configure({"suspicious": 0.8}, false, 0.5)
	var po := PersonalityAccents.new()
	po.configure({"suspicious": 0.8}, false, 0.0)
	check(is_equal_approx(pa.a("suspicious"), 0.4) and po.is_empty(), "muted poloviční, off žádné")
	for x in [neutral, s4, s8, ab, det, av, dep, gr, pf, a1, a2, lab]:
		x.free()


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _test_world() -> void:
	section("Ve světě: vzorce přes existující vztahy, agency, uložení, soukromí")
	var world := U.make_world(U.household({1: {"accents": {"suspicious": 0.9, "grandiosity": 0.7}, "accent_labels": true}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	var petr = _find(world, "Petr")
	var ref := U.make_world(U.household({}), clock)
	add_child(ref)
	await get_tree().process_frame
	var p_acc: float = petr.talk_success_chance(jana)
	var p_ref: float = _find(ref, "Petr").talk_success_chance(_find(ref, "Jana"))
	check(p_acc < p_ref, "podezíravost + grandiozita: rozhovory snáz skončí hádkou", "%.3f vs %.3f" % [p_acc, p_ref])
	petr.ledger.on_hurt_other(jana.sim_name, 40.0)
	_find(ref, "Petr").ledger.on_hurt_other(jana.sim_name, 40.0)
	var ap := Planner.apology_score(petr, jana, 1.0, 0.0)
	var ap_ref := Planner.apology_score(_find(ref, "Petr"), _find(ref, "Jana"), 1.0, 0.0)
	check(ap < ap_ref, "grandiozita: AI se omlouvá méně", "%.2f vs %.2f" % [ap, ap_ref])
	var ok: bool = petr.command(ActionLibrary.get_action("apologize"), jana)
	var did := false
	for i in 90:
		clock.advance(1.0)
		if not petr.last_apology.is_empty():
			did = true
			break
	check(ok and did, "agency: hráč se může omluvit i za grandiózní postavu")
	ref.free()
	await get_tree().process_frame
	check((petr.trait_profile as Dictionary).has("acc_suspicious"), "akcenty jsou v profilu rysů simulace")
	gs.set_value("mental_health", "muted", false)
	clock.advance(1.0)
	check(is_equal_approx(float(petr.trait_profile["acc_suspicious"]), 0.45), "přepnutí na muted za běhu akcenty oslabí")
	gs.set_value("mental_health", "full", false)
	clock.advance(1.0)
	var snap: Dictionary = SaveGame.capture(world)
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	var p2 = _find(world, "Petr")
	check(is_equal_approx(float(p2.trait_profile.get("acc_suspicious", 0.0)), 0.9), "po načtení se akcenty znovu nastaví z CharacterData")
	p2._update_net(100.0)
	var det_txt := JSON.stringify(p2._build_detail())
	check(not det_txt.contains("acc_") and not det_txt.contains("paranoid") and not (p2.net_detail.get("traits", []) as Array).has("acc_suspicious"),
		"net_detail ani veřejné rysy neobsahují akcenty ani výklad")
	check(not U.contains_key(p2.look, ["accents"]), "spawn bez akcentů")
	world.free()
	await get_tree().process_frame
	section("Editor")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var n := 0
	for id in Schema.ACCENT_SLIDERS:
		if ui.find_child("Slider_accents_" + id, true, false) is HSlider:
			n += 1
	ui._on_slider(0.55, "accents", "perfectionism", Label.new())
	var cb: CheckBox = ui.find_child("Bool_accent_labels", true, false)
	cb.button_pressed = true
	var out: Dictionary = ui.export_data()
	check(n == 8 and absf(float(out["mind"]["accents"]["perfectionism"]) - 0.55) < 0.001 and out["mind"]["accent_labels"] == true,
		"posuvníky akcentů a volba výkladu v editoru")
	check(Validator.validate(out)["ok"], "výstup editoru projde validací")
	ui.free()
