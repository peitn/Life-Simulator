extends "res://tests/test_base.gd"
## Psychika H – psychotické prožívání: spouštěče (spánek, extrémní stres, látky), pozvolný nástup, průběh
## a zotavení s oporou a pomocí, soukromé vjemy, přesvědčení s jistotou a náhledem, žádná vazba na násilí,
## hráč není zamčený, režimy, rozmanitost, uložení, soukromí, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const PS := preload("res://scripts/sim/psychosis_state.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

const DAY := 1440.0

var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 300.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_schema()
	_test_model()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_psychosis")


func _test_schema() -> void:
	section("Schéma v16")
	check(Schema.VERSION >= 16 and Schema.PREDISPOSITIONS.has("psychosis") and Schema.PSYCHOSIS_SLIDERS.size() == 5, "predispozice a sklony")
	var d := U.character(0, {"predispositions": {"psychosis": 0.6}, "psychosis": {"persecutory": 0.7, "insight": 0.3}})
	check(Validator.validate(d)["ok"], "platné")
	var old := d.duplicate(true)
	old["v"] = 15
	old["mind"].erase("psychosis")
	check(Codec.migrate(old)["data"]["mind"]["psychosis"] == {}, "migrace v15 → v16")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["mind"]["psychosis"] == {}, "off: nepřijme se")
	var txt := String(Schema.PREDISPOSITIONS["psychosis"]["effects"]).to_lower()
	check(not txt.contains("nebezpe") and not txt.contains("násil") and not txt.contains("agres"), "popis bez stigmatu a vazby na násilí")


func _sim(p: PS, days: float, seed: int, ctx: Dictionary, k := 1.0) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var t := 0.0
	var ep := p.episodes
	while t < days * DAY:
		var h := int(fmod(t, DAY) / 60.0)
		var c := ctx.duplicate()
		c["night"] = h >= 22 or h < 6
		if not c.has("sleeping"):
			c["sleeping"] = c["night"]
		p.tick(10.0, t, c, k, r)
		t += 10.0
	return p.episodes - ep


func _test_model() -> void:
	section("Spouštěče, průběh, zotavení")
	var none := PS.new()
	none.configure(0.0, {"hallucination": 1.0}, false)
	_sim(none, 20, 1, {"stress": 95.0, "sleeping": false})
	check(none.activity == 0.0 and none.episodes == 0, "bez predispozice nic ani v extrémní zátěži")
	var calm := 0
	var hard := 0
	for s in 6:
		var a := PS.new()
		a.configure(0.7, {}, false)
		calm += _sim(a, 30, 50 + s, {"stress": 20.0})
		var b := PS.new()
		b.configure(0.7, {}, false)
		hard += _sim(b, 30, 50 + s, {"stress": 90.0, "sleeping": false})
	check(hard > calm, "bez spánku a v extrémním stresu víc epizod", "%d vs %d" % [hard, calm])
	var drug := 0
	for s in 6:
		var c := PS.new()
		c.configure(0.7, {}, false)
		drug += _sim(c, 30, 50 + s, {"stress": 20.0, "push": 0.8})
	check(drug > calm, "některé látky zvyšují riziko", "%d vs %d" % [drug, calm])
	var p := PS.new()
	p.configure(0.8, {"hallucination": 0.9, "persecutory": 0.8, "insight": 0.4}, false)
	p.target = 0.9
	p.episode_left = 5.0 * DAY
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 36:
		p.tick(10.0, float(i) * 10.0, {"stress": 50.0}, 1.0, r)
	check(p.activity < 0.3, "nástup je pozvolný (prodrom)", "%.2f" % p.activity)
	for i in 600:
		p.tick(10.0, 360.0 + float(i) * 10.0, {"stress": 50.0}, 1.0, r)
	check(p.activity > 0.6 and p.conviction > 0.3 and p.insight_now < 0.4, "aktivní fáze: přesvědčení roste, náhled klesá",
		"%.2f %.2f %.2f" % [p.activity, p.conviction, p.insight_now])
	check(not p.perceptions.is_empty(), "soukromé neobvyklé vjemy")
	var q := PS.new()
	q.from_dict(p.to_dict())
	q.configure(0.8, {"hallucination": 0.9, "persecutory": 0.8, "insight": 0.4}, true)
	var q2 := PS.new()
	q2.from_dict(p.to_dict())
	q2.configure(0.8, {"hallucination": 0.9, "persecutory": 0.8, "insight": 0.4}, true)
	q.on_help(6400.0)
	var t := 6400.0
	for i in 400:
		t += 10.0
		q.tick(10.0, t, {"stress": 30.0, "support": 0.8, "sleeping": i % 3 == 0}, 1.0, r)
		q2.tick(10.0, t, {"stress": 30.0}, 1.0, r)
	check(q.activity < q2.activity and q.insight_now > q2.insight_now, "opora, spánek a pomoc zkracují epizodu a vracejí náhled",
		"%.2f vs %.2f" % [q.activity, q2.activity])
	section("Žádná vazba na násilí, hráč není zamčený")
	var ok := true
	for a in ActionLibrary.ACTIONS:
		var w := p.action_weight(a, 1.0)
		var tags: Array = a.get("tags", [])
		if (tags.has("pressure") or tags.has("mean")) and w != 1.0:
			ok = false
		if w < 0.4 or w > 2.5:
			ok = false
	check(ok, "nátlak ani urážky se nikdy nezvyšují, nic se nezakazuje")
	check(p.action_weight(ActionLibrary.get_action("chat"), 1.0) < 1.0, "pronásledovací přesvědčení = víc stažení (ne útok)")
	check(p.action_weight(ActionLibrary.get_action("seek_help"), 1.0) > 1.0, "s náhledem láká pomoc")
	section("Režimy a rozmanitost")
	var mu := PS.new()
	mu.configure(0.8, {"hallucination": 1.0, "persecutory": 1.0}, false)
	mu.target = 0.9
	mu.episode_left = 5.0 * DAY
	for i in 800:
		mu.tick(10.0, float(i) * 10.0, {"stress": 50.0}, 0.5, r)
	check(mu.activity <= 0.31 and mu.conviction < 0.05 and mu.perceptions.is_empty(), "muted: jen mírné zvláštní pocity, bez vjemů a bludů")
	var of := PS.new()
	of.from_dict(p.to_dict())
	of.configure(0.8, {}, true)
	for i in 100:
		of.tick(10.0, float(i) * 10.0, {}, 0.0, r)
	check(of.activity < 0.05, "off: odezní a nevzniká")
	var g := PS.new()
	g.configure(0.8, {"grandiose": 0.9}, false)
	var pe := PS.new()
	pe.configure(0.8, {"persecutory": 0.9}, false)
	for x in [g, pe]:
		x.activity = 0.8
		x.conviction = 0.7
	check(g.action_weight(ActionLibrary.get_action("chat"), 1.0) > 1.0 and pe.action_weight(ActionLibrary.get_action("chat"), 1.0) < 1.0,
		"stejná závažnost, jiný druh přesvědčení → jiné chování")


func _test_world() -> void:
	section("Ve světě")
	var world := U.make_world(U.household({0: {"predispositions": {"psychosis": 0.8}, "psychosis": {"hallucination": 0.8, "reference": 0.8, "insight": 0.5}}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = world.sims[0]
	jana.psy.psychosis.target = 0.9
	jana.psy.psychosis.episode_left = 4.0 * DAY
	U.run_minutes(clock, 2.0 * DAY)
	check(jana.psy.psychosis.activity > 0.4, "epizoda ve světě běží")
	check(jana.mental.threat > 0.0, "vztahovačnost zvyšuje vnímanou hrozbu")
	var lines := "\n".join(jana.psyche_private_lines())
	check(lines.contains("ostatní nevnímají") or lines.contains("týkají"), "vlastník vidí soukromý popis prožitku", lines)
	var ok: bool = jana.command(ActionLibrary.get_action("seek_help"), null)
	var did := false
	for i in 60:
		clock.advance(1.0)
		if jana.psy.psychosis.help_t > 0.0:
			did = true
			break
	check(ok and did, "agency: hráč může vyhledat pomoc a ta se projeví")
	jana._update_net(100.0)
	var det := JSON.stringify(jana._build_detail())
	check(not det.contains("nevnímají") and not det.contains("conviction") and not det.contains("activity"), "net_detail bez vjemů a přesvědčení")
	var other := "\n".join(world.sims[1].psyche_private_lines())
	check(not other.contains("nevnímají"), "jiné postavy o vjemech nevědí")
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.psychosis.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	check(world.sims[0].psy.psychosis.to_dict() == before, "stav obnoven")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["psychosis"]["perceptions"] = [{"t": 1.0, "text": "volný text"}]
	check(not SaveGame.apply(world, bad)["ok"], "volný text vjemu se odmítne")
	world.free()
	await get_tree().process_frame
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var sl: HSlider = ui.find_child("Slider_psychosis_insight", true, false)
	check(sl != null and absf(sl.value - 0.5) < 0.001 and ui.find_child("Slider_predispositions_psychosis", true, false) is HSlider,
		"posuvníky v editoru (náhled výchozí 0,5)")
	ui.free()
