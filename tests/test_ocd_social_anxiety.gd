extends "res://tests/test_base.gd"
## Psychika E – OCD smyčka (obsese → nutkání → krátká úleva → posílení; odolání ji oslabuje) a sociální
## úzkost se strachem z odmítnutí (predispozice nad dimenzemi + napětí před setkáním + přehrávání).
## Režimy, agency, rozmanitost, determinismus, uložení, soukromí, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const PM := preload("res://scripts/psyche/psyche_model.gd")
const OcdLoop := preload("res://scripts/sim/ocd_loop.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
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
	_test_schema_profiles()
	_test_loop()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_ocd_social_anxiety")


func _test_schema_profiles() -> void:
	section("Schéma v14 a profily nad dimenzemi")
	check(Schema.VERSION >= 14 and Schema.PREDISPOSITIONS.has("ocd") and Schema.PREDISPOSITIONS.has("social_anxiety")
		and Schema.fields("mind").has("ocd_theme"), "predispozice ocd, social_anxiety a téma")
	check(PM.load_errors().is_empty() and PM.profiles().has("ocd") and PM.profiles().has("social_anxiety"), "profily se načtou bez chyb",
		str(PM.load_errors()))
	var d := U.character(0, {"predispositions": {"ocd": 0.7, "social_anxiety": 0.6}, "ocd_theme": "contamination"})
	var v := Validator.validate(d)
	check(v["ok"], "platné", str(v["errors"]))
	var old := d.duplicate(true)
	old["v"] = 13
	old["mind"].erase("ocd_theme")
	check(Codec.migrate(old)["data"]["mind"]["ocd_theme"] == "checking", "migrace v13 → v14")
	var base: Dictionary = PM.compute(U.character(0), {"individual": false})["D"]
	var sa: Dictionary = PM.compute(d, {"individual": false})["D"]
	check(float(sa["social_threat"]) > float(base["social_threat"]) + 0.1 and float(sa["rejection_reactivity"]) > float(base["rejection_reactivity"]),
		"sociální úzkost = očekávání odmítnutí a citlivost na něj (dimenze)")
	check(float(sa["predictability_need"]) > float(base["predictability_need"]) and float(sa["cognitive_flexibility"]) < float(base["cognitive_flexibility"]),
		"OCD = potřeba jistoty, méně flexibility (dimenze)")
	var off: Dictionary = PM.compute(d, {"individual": false, "mode": "off"})["D"]
	check(is_equal_approx(float(off["social_threat"]), float(base["social_threat"])), "off: profily bez vlivu")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["mind"]["predispositions"].is_empty(), "off: predispozice se nepřijmou")


func _test_loop() -> void:
	section("Obsese → nutkání → krátká úleva → posílení")
	var r := RandomNumberGenerator.new()
	r.seed = 2
	var o := OcdLoop.new()
	o.configure(0.8, "checking", false)
	var th := o.trigger(o.trigger_for_action("cook", ["cooking"]), 1.0, r)
	check(o.obsession > 0.25 and th.contains("sporák") or th.contains("Zamkl"), "po vaření pochybnost o sporáku", th)
	var h0 := o.habit
	var ob0 := o.obsession
	var relief := o.on_ritual(0.0, 1.0)
	check(relief < 0.0 and o.obsession < ob0 * 0.5 and o.habit > h0, "rituál: úleva, ale návyk zesílí")
	var back_strong := OcdLoop.new()
	back_strong.configure(0.8, "checking", false)
	back_strong.habit = 0.9
	var back_weak := OcdLoop.new()
	back_weak.configure(0.8, "checking", false)
	back_weak.habit = 0.1
	for x in [back_strong, back_weak]:
		x.obsession = 0.1
		for i in 60:
			x.tick(10.0, {"stress": 30.0}, 1.0)
	check(back_strong.obsession > back_weak.obsession, "silný návyk = pochybnost se vrací rychleji (posílení smyčky)")
	var res := OcdLoop.new()
	res.configure(0.8, "checking", false)
	res.habit = 0.6
	res.obsession = 0.7
	var tension := res.on_resist(1.0)
	check(tension > 0.0 and res.habit < 0.6, "odolání: napětí teď, slabší smyčka potom (expozice)")
	check(res.gate("ritual") > 0.0 and OcdLoop.new().gate("ritual") == 0.0, "bez predispozice žádný rituál")
	var w_hi := o.action_weight(ActionLibrary.get_action("compulsion"), 1.0, 0.5, 0.0)
	o.obsession = 0.9
	check(o.action_weight(ActionLibrary.get_action("compulsion"), 1.0, 0.5, 0.0) > w_hi, "silnější obsese = silnější nutkání")
	var sup := o.action_weight(ActionLibrary.get_action("resist_urge"), 1.0, 0.8, 0.6)
	var nosup := o.action_weight(ActionLibrary.get_action("resist_urge"), 1.0, 0.2, 0.0)
	check(sup > nosup, "s oporou a pocitem zvládání se odolává snáz")
	var off := OcdLoop.new()
	off.configure(0.8, "checking", false)
	off.trigger(0.5, 0.0, r)
	check(off.obsession == 0.0 and off.action_weight(ActionLibrary.get_action("compulsion"), 0.0, 0.5, 0.0) == 1.0, "off: nic")
	var mu := OcdLoop.new()
	mu.configure(0.8, "checking", false)
	mu.trigger(0.5, 0.5, r)
	var fu := OcdLoop.new()
	fu.configure(0.8, "checking", false)
	fu.trigger(0.5, 1.0, r)
	check(mu.obsession < fu.obsession, "muted slabší")
	var c1 := OcdLoop.new()
	c1.configure(0.8, "contamination", false)
	var c2 := OcdLoop.new()
	c2.configure(0.8, "checking", false)
	check(c1.trigger_for_action("snack", ["food"]) > 0.0 and c2.trigger_for_action("snack", ["food"]) == 0.0,
		"rozmanitost: stejná závažnost, jiné téma → jiné spouštěče")


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _test_world() -> void:
	section("Ve světě: autonomní smyčka, agency, sociální úzkost")
	var hh := U.household({0: {"predispositions": {"ocd": 0.9}, "ocd_theme": "checking"},
		1: {"predispositions": {"social_anxiety": 0.9}}})
	var world := U.make_world(hh, clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	var petr = _find(world, "Petr")
	var eli = world.sims[2]
	check(Planner.score_action(jana, ActionLibrary.get_action("compulsion"), 12) == 0.0, "bez pochybnosti AI rituál nevolí")
	jana.psy.ocd.obsession = 0.85
	check(Planner.score_action(jana, ActionLibrary.get_action("compulsion"), 12) > 0.0, "s pochybností nutkání láká")
	var rituals := [0]
	jana.action_started.connect(func(_s, a): if String(a.get("id", "")) == "compulsion": rituals[0] += 1)
	U.run_minutes(clock, DAY)
	check(rituals[0] > 0 and jana.psy.ocd.rituals > 0, "autonomní postava rituál opravdu provádí", str(rituals))
	check(String(ActionLibrary.get_action("compulsion")["label"]) != "" and jana.psy.ocd.COMPULSION_LABEL["checking"].contains("kontroluje"),
		"popisek podle tématu")
	jana.psy.ocd.obsession = 0.9
	jana.command({"id": "cancel"}, null)
	var ok: bool = jana.command(ActionLibrary.get_action("resist_urge"), null)
	var resisted := false
	for i in 60:
		clock.advance(1.0)
		if jana.psy.ocd.resisted > 0:
			resisted = true
			break
	check(ok and resisted, "agency: hráč může zadat „odolat nutkání“ a provede se")
	# Sociální úzkost: napětí před setkáním s méně blízkým člověkem.
	petr.relationships[eli.sim_name] = 0.0
	petr.relationships[jana.sim_name] = 80.0
	petr.mental.arousal = 10.0
	petr._social_anxiety_before(eli)
	var a_far: float = petr.mental.arousal
	petr.mental.arousal = 10.0
	petr._social_anxiety_before(jana)
	var a_near: float = petr.mental.arousal
	check(a_far > a_near + 10.0, "před setkáním s cizím víc napětí než s blízkým", "%.1f vs %.1f" % [a_far, a_near])
	var w_far: float = petr.psyche_target_weight(eli, ActionLibrary.get_action("chat"))
	var w_near: float = petr.psyche_target_weight(jana, ActionLibrary.get_action("chat"))
	check(w_far < w_near and w_far >= 0.7, "méně blízcí jsou náročnější partneři (nikdy zákaz)")
	var m0: float = petr.mental.mastery
	petr.mental.arousal = 60.0
	var th: String = petr.mental.on_social_completed(true, 60.0, eli.sim_name, eli.grammar, petr.now(), petr.mental_cfg())
	check(petr.mental.mastery > m0, "expozice: rozhovor, který dopadl dobře, zvyšuje pocit zvládnutí")
	var cmd_ok: bool = petr.command(ActionLibrary.get_action("chat"), eli)
	check(cmd_ok, "agency: hráč může poslat sociálně úzkostnou postavu mluvit")
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.ocd.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	var j2 = _find(world, "Jana")
	check(j2.psy.ocd.to_dict() == before and j2.psy.ocd.severity > 0.8, "stav OCD smyčky přesně obnoven")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["ocd"]["obsession"] = 2.0
	check(not SaveGame.apply(world, bad)["ok"], "neplatný stav se odmítne")
	j2._update_net(100.0)
	var det := JSON.stringify(j2._build_detail())
	check(not det.contains("obsession") and not det.contains("habit"), "net_detail bez vnitřního stavu OCD")
	var conds: Array = j2.mental.detail(j2.mental_cfg()).get("conditions", [])
	check(not conds.has("Obsedantně-kompulzivní porucha"), "diagnostický název ani v detailu vlastníka (jen slovní popis offline)")
	world.free()
	await get_tree().process_frame
	section("Determinismus a editor")
	var res: Array = []
	for i in 2:
		var w := U.make_world(hh, clock)
		add_child(w)
		await get_tree().process_frame
		U.run_minutes(clock, 2.0 * DAY)
		res.append([U.action_fingerprint(w), w.sims[0].psy.ocd.to_dict()])
		w.free()
		await get_tree().process_frame
	check(res[0] == res[1], "stejný seed → stejná smyčka a chování")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	ui._on_slider(0.7, "predispositions", "ocd", Label.new())
	var ob: OptionButton = ui.find_child("Enum_ocd_theme", true, false)
	check(ob != null and ui.find_child("Slider_predispositions_social_anxiety", true, false) is HSlider, "posuvníky a téma v editoru")
	var out: Dictionary = ui.export_data()
	check(absf(float(out["mind"]["predispositions"]["ocd"]) - 0.7) < 0.001 and Validator.validate(out)["ok"], "editor zapíše predispozici")
	ui.free()
