extends "res://tests/test_base.gd"
## Psychika F – návykové látky a činnosti: chuť (wanting), libost (liking) s tolerancí, závislost,
## abstinence, podněty a relaps, následky (spánek, nálada, dojezd, peníze, podrážděnost, obava blízkých),
## cesta ven (omezit, opora, pomoc), herní jména bez dávek, obsahové přepínače, agency, rozmanitost,
## determinismus, uložení, soukromí, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Substances := preload("res://scripts/sim/substances.gd")
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
	_test_schema_and_content()
	_test_model()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_substances")


func _test_schema_and_content() -> void:
	section("Schéma v15, herní jména, žádné dávky")
	check(Schema.VERSION >= 15 and Schema.SUBSTANCE_SLIDERS.size() == 8 and Schema.PREDISPOSITIONS.has("addiction"), "mind.substances a predispozice")
	var d := U.character(0, {"substances": {"stimulant": 0.5}, "predispositions": {"addiction": 0.6}})
	check(Validator.validate(d)["ok"], "platné")
	var old := d.duplicate(true)
	old["v"] = 14
	old["mind"].erase("substances")
	check(Codec.migrate(old)["data"]["mind"]["substances"] == {}, "migrace v14 → v15")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["mind"]["substances"] == {}, "off: zvyky se nepřijmou")
	var bad_words := ["mg", "dávk", "gram", "injek", "šňup", "kouř", "kombin", "recept", "kokain", "heroin", "pervitin", "marihu"]
	var clean := true
	for a in ActionLibrary.ACTIONS:
		if a.has("substance") or String(a["id"]) == "cut_down":
			for w in bad_words:
				if String(a["label"]).to_lower().contains(w):
					clean = false
			check(String(a.get("content", "")) == "addiction", "akce %s je za přepínačem závislostí" % a["id"])
	for id in Substances.DEFS:
		for w in bad_words:
			if String(Substances.DEFS[id]["withdrawal"]).to_lower().contains(w) or String(Substances.DEFS[id]["label"]).to_lower().contains(w):
				clean = false
	check(clean, "žádné dávkování, příprava, způsob užití ani skutečné názvy drog")


func _test_model() -> void:
	section("Chuť, libost, tolerance, závislost, abstinence")
	var s := Substances.new()
	s.configure({}, 0.0, false)
	check(s.is_empty() and s.gate("stimulant") == 0.0, "bez zvyku a chuti je brána zavřená")
	var hi := Substances.new()
	hi.configure({}, 0.9, false)
	var lo := Substances.new()
	lo.configure({}, 0.0, false)
	var likes: Array = []
	var t := 0.0
	for i in 14:
		likes.append(float(hi.on_use("stimulant", t, 1.0)["liking"]))
		lo.on_use("stimulant", t, 1.0)
		hi.tick(720.0, t + 720.0, {"stress": 30.0}, 1.0)
		lo.tick(720.0, t + 720.0, {"stress": 30.0}, 1.0)
		t += 720.0
	check(float(likes[-1]) < float(likes[0]) * 0.7, "tolerance: libost s užíváním klesá", str(likes.slice(0, 3)))
	check(hi.dependence("stimulant") > lo.dependence("stimulant") + 0.1, "náchylnost k závislosti zrychluje návyk",
		"%.2f vs %.2f" % [hi.dependence("stimulant"), lo.dependence("stimulant")])
	var res := hi.tick(DAY, t + DAY, {"stress": 30.0}, 1.0)
	check(hi.craving("stimulant") > 0.3 and float(res["withdrawal"]) > 0.0 and String(res["withdrawal_id"]) == "stimulant",
		"po odstupu: chuť a abstinenční nepohodlí", "%.2f %.2f" % [hi.craving("stimulant"), float(res["withdrawal"])])
	check(hi.irritability(float(res["withdrawal"]), "stimulant") > 0.0, "abstinence podráždí (vztahy)")
	check(hi.money_worry > 0.2 and hi.psychosis_push >= 0.0, "následky: starost o peníze")
	var sl := Substances.new()
	sl.configure({}, 0.0, false)
	sl.on_use("caffeine", 1000.0, 1.0)
	check(sl.sleep_quality_mult(1060.0, 22) < 1.0 and sl.sleep_quality_mult(1600.0, 22) == 1.0, "káva před spaním zhorší spánek, ráno ne")
	var cr := Substances.new()
	cr.configure({}, 0.0, false)
	cr.on_use("stimulant", 0.0, 1.0)
	var crash := 0.0
	for i in 30:
		crash = maxf(crash, float(cr.tick(10.0, 10.0 * (i + 1), {}, 1.0)["crash"]))
	check(crash > 0.0, "po účinku Jiskry přijde dojezd")
	section("Cesta ven a relaps")
	var rec := Substances.new()
	rec.configure({"nicotine": 0.9}, 0.5, false)
	var d0 := rec.dependence("nicotine")
	rec.cut_until = 5.0 * DAY
	check(rec.use_weight("nicotine", 10.0, 1.0) < Substances.new().use_weight("nicotine", 10.0, 1.0) * 2.0 and rec.cutting_down(10.0), "rozhodnutí omezit tlumí chuť")
	var sup := Substances.new()
	sup.configure({"nicotine": 0.9}, 0.5, false)
	for i in 6:
		rec.tick(240.0, 240.0 * (i + 1), {"stress": 20.0}, 1.0)
		sup.tick(240.0, 240.0 * (i + 1), {"stress": 20.0, "support": 0.9}, 1.0)
	check(sup.craving("nicotine") < rec.craving("nicotine"), "opora chuť tlumí")
	var tt := 0.0
	for i in 60:
		tt += DAY
		rec.tick(DAY, tt, {"stress": 15.0}, 1.0)
	check(rec.dependence("nicotine") < d0 * 0.3, "bez užívání závislost během týdnů slábne (zotavení)",
		"%.2f → %.2f" % [d0, rec.dependence("nicotine")])
	var relapse := Substances.new()
	relapse.from_dict(rec.to_dict())
	relapse.configure({"nicotine": 0.9}, 0.5, true)
	var fresh := Substances.new()
	fresh.configure({}, 0.5, false)
	for x in [relapse, fresh]:
		x.on_use("nicotine", tt, 1.0)
	check(relapse.dependence("nicotine") > fresh.dependence("nicotine"), "po zotavení zůstane stopa – relaps je rychlejší")
	var calm := Substances.new()
	calm.from_dict(relapse.to_dict())
	calm.configure({"nicotine": 0.9}, 0.5, true)
	for x in [relapse, calm]:
		x.tick(600.0, tt + 600.0, {"stress": 90.0 if x == relapse else 10.0}, 1.0)
	check(relapse.craving("nicotine") > calm.craving("nicotine"), "stres jako podnět k relapsu")
	section("Režimy a rozmanitost")
	var off := Substances.new()
	off.configure({"stimulant": 1.0}, 1.0, false)
	off.tick(DAY, DAY * 3.0, {"stress": 90.0}, 0.0)
	check(off.craving("stimulant") == 0.0, "off: žádná chuť ani abstinence")
	var a := Substances.new()
	a.configure({"caffeine": 0.8}, 0.4, false)
	var b := Substances.new()
	b.configure({"gaming": 0.8}, 0.4, false)
	check(a.gate("caffeine") > 0.0 and a.gate("gaming") == 0.0 and b.gate("gaming") > 0.0 and b.gate("caffeine") == 0.0,
		"stejná náchylnost, jiný zvyk → jiné chování")


func _find(world: Node, first: String) -> Node:
	for x in world.sims:
		if x.first_name() == first:
			return x
	return null


func _test_world() -> void:
	section("Ve světě")
	var world := U.make_world(U.household({0: {"substances": {"nicotine": 0.9}, "predispositions": {"addiction": 0.7}}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	var petr = _find(world, "Petr")
	check(Planner.score_action(petr, ActionLibrary.get_action("use_stimulant"), 12) == 0.0
		and Planner.score_action(petr, ActionLibrary.get_action("play_games"), 12) == 0.0, "postava bez zvyku nic nezačne")
	var used := [0]
	jana.action_started.connect(func(_s, a): if String(a.get("substance", "")) == "nicotine": used[0] += 1)
	U.run_minutes(clock, DAY)
	check(used[0] > 0 and jana.psy.subs.uses_today("nicotine", jana.now()) > 0, "postava se zvykem si cigaretu opravdu dává", str(used[0]))
	jana.psy.subs.s["nicotine"]["dependence"] = 0.8
	jana.psy.subs.s["nicotine"]["last"] = jana.now() - DAY
	check(jana.psyche_gate("cut_down") > 0.0 and jana.psyche_gate("help") > 0.0, "silná závislost otevře „omezit“ i „vyhledat pomoc“")
	var ok: bool = jana.command(ActionLibrary.get_action("cut_down"), null)
	var cut := false
	for i in 60:
		clock.advance(1.0)
		if jana.psy.subs.cutting_down(jana.now()):
			cut = true
			break
	check(ok and cut, "agency: hráč může rozhodnout „omezit to“")
	jana.psy.subs.on_use("stimulant", jana.now(), 1.0)
	jana.psy.subs.on_use("stimulant", jana.now() + 1.0, 1.0)
	jana.global_position = petr.global_position + Vector3(1.0, 0, 0)
	petr.relationships[jana.sim_name] = 60.0
	jana.current_action = ActionLibrary.get_action("use_stimulant").duplicate(true)
	jana._substance_after_finish("use_stimulant", false)
	check(petr.mood.has_moodlet("sub_obava_" + String(jana.name)), "blízký člověk má obavu (bez odsuzování)")
	gs.set_value("addiction", false, false)
	check(jana.psyche_gate("substance:nicotine") == 0.0, "vypnutý obsah závislostí: AI nic neužívá")
	gs.set_value("addiction", true, false)
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.subs.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	var j2 = _find(world, "Jana")
	check(j2.psy.subs.to_dict() == before, "stav návyků přesně obnoven")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["subs"]["s"]["heroin"] = {}
	check(not SaveGame.apply(world, bad)["ok"], "neznámá kategorie se odmítne")
	j2._update_net(100.0)
	var det := JSON.stringify(j2._build_detail())
	check(not det.contains("dependence") and not det.contains("craving"), "net_detail bez návyků")
	world.free()
	await get_tree().process_frame
	section("Determinismus a editor")
	var r: Array = []
	for i in 2:
		var w := U.make_world(U.household({0: {"substances": {"caffeine": 0.7, "gaming": 0.6}}}), clock)
		add_child(w)
		await get_tree().process_frame
		U.run_minutes(clock, 2.0 * DAY)
		r.append([U.action_fingerprint(w), w.sims[0].psy.subs.to_dict()])
		w.free()
		await get_tree().process_frame
	check(r[0] == r[1], "stejný seed → stejný průběh")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	ui._on_slider(0.3, "substances", "gambling", Label.new())
	check(ui.find_child("Slider_substances_caffeine", true, false) is HSlider and absf(float(ui.export_data()["mind"]["substances"]["gambling"]) - 0.3) < 0.001,
		"posuvníky zvyku v editoru")
	ui.free()
