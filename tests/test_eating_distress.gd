extends "res://tests/test_base.gd"
## Psychika G – potíže s jídlem a tělem jen přes emoce, myšlenky a následky. Nejde vybrat při tvorbě
## postavy; existuje jen s opt-in citlivým obsahem. Žádná čísla, metody ani akce; hlad má přednost;
## opora a pomoc ulevují; soukromí, uložení, determinismus.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const EatingDistress := preload("res://scripts/sim/eating_distress.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

const DAY := 1440.0

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
	_test_rules()
	_test_model()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_eating_distress")


func _test_rules() -> void:
	section("Pravidla obsahu")
	var sel := false
	for k in Schema.PREDISPOSITIONS.keys():
		for w in ["ppp", "jidl", "anorex", "bulim", "eating", "food"]:
			sel = sel or String(k).contains(w)
	for g in ["mind"]:
		for f in Schema.fields(g):
			for w in ["eating", "food", "body_image", "weight"]:
				sel = sel or String(f).contains(w)
	check(not sel, "nejde vybrat při tvorbě postavy (žádná predispozice ani posuvník)")
	var bad := false
	for a in ActionLibrary.ACTIONS:
		for w in ["fast", "starve", "diet", "purge", "nejist", "hladov", "zvrac"]:
			bad = bad or String(a["id"]).contains(w) or String(a["label"]).to_lower().contains(w)
	check(not bad, "žádná akce omezování ani jiná metoda")
	var e := EatingDistress.new()
	e.body_image = 0.9
	e.food_anxiety = 0.9
	var texts := "\n".join(e.private_lines([["Linka", "116 123"]]))
	for m in e.mood_entries():
		texts += String(m["label"])
	var digits := 0
	for ch in texts.replace("116 123", ""):
		if ch in "0123456789":
			digits += 1
	check(digits == 0 and not texts.to_lower().contains("kalor") and not texts.to_lower().contains("kil"), "žádná čísla (kalorie, váha…)")


func _test_model() -> void:
	section("Vzniká jen z dat a jen s opt-in")
	var e := EatingDistress.new()
	for i in 30:
		e.tick(DAY / 4.0, {"allow": false, "self_belief": 1.0, "perfectionism": 1.0, "stress": 90.0})
	check(not e.active(), "bez opt-in neexistuje")
	var calm := EatingDistress.new()
	for i in 30:
		calm.tick(DAY / 4.0, {"allow": true, "stress": 20.0})
	check(not calm.active(), "bez důvodu (přesvědčení, srovnávání, odmítnutí) nevznikne")
	for i in 30:
		e.tick(DAY / 4.0, {"allow": true, "self_belief": 0.9, "perfectionism": 0.6, "envy": 50.0, "stress": 70.0})
	check(e.body_image > 0.3 and e.food_anxiety > 0.2, "z vnitřního přesvědčení, perfekcionismu a srovnávání vznikne tíseň")
	check(e.food_weight(2, 60.0) < 1.0 and e.food_weight(0, 60.0) == 1.0 and e.food_weight(2, 10.0) == 1.0,
		"vyhýbání se společnému jídlu, ale hlad má vždy přednost")
	check(e.after_meal(0.0) < 0.0 and e.after_meal(10.0) == 0.0, "výčitky po jídle (ne pokaždé)")
	check(e.energy_mult() > 1.0, "méně energie")
	var before := e.body_image
	e.on_support(1.0)
	check(e.body_image < before, "opora uleví")
	var sup := EatingDistress.new()
	sup.from_dict(e.to_dict())
	var alone := EatingDistress.new()
	alone.from_dict(e.to_dict())
	for i in 12:
		sup.tick(DAY / 4.0, {"allow": true, "self_belief": 0.5, "stress": 30.0, "support": 0.9})
		alone.tick(DAY / 4.0, {"allow": true, "self_belief": 0.5, "stress": 30.0})
	check(sup.body_image < alone.body_image, "s oporou se zotavuje rychleji")
	e.tick(1.0, {"allow": false})
	check(not e.active(), "vypnutí opt-in stav zruší")


func _test_world() -> void:
	section("Ve světě")
	gs.set_value("sh_ed_topics", true, false)
	var world := U.make_world(U.household({0: {"self_defectiveness": 0.9, "accents": {"perfectionism": 0.7}}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = world.sims[0]
	jana.emotions.shift("envy", 60.0)
	jana.mental.stress = 70.0
	U.run_minutes(clock, 4.0 * DAY)
	print("    tíseň %.3f, úzkost %.3f, allow %s" % [jana.psy.eating.body_image, jana.psy.eating.food_anxiety, str(jana._allows_rejection_risk())])
	check(jana.psy.eating.active(), "stav vznikl z dat postavy")
	jana.psy.eating.food_anxiety = 0.8
	jana.needs.values["hunger"] = 50.0
	var snack := ActionLibrary.get_action("snack")
	for o in world.sims:
		if o != jana:
			o.global_position = jana.global_position + Vector3(20.0, 0, 0)
	var w_alone: float = jana.psyche_action_weight(snack)
	for o in world.sims:
		if o != jana:
			o.global_position = jana.global_position + Vector3(1.0, 0, 0)
	var w_shared: float = jana.psyche_action_weight(snack)
	check(w_shared < w_alone and w_shared >= 0.6, "společné jídlo láká méně (omezeně)", "%.2f vs %.2f" % [w_shared, w_alone])
	jana.needs.values["hunger"] = 10.0
	check(jana.psyche_action_weight(snack) == w_alone or jana.psyche_action_weight(snack) >= w_alone, "při velkém hladu vliv mizí")
	var ok: bool = jana.command(snack, world.smart_objects.filter(func(o): return o.object_tag == "fridge")[0])
	var ate := false
	for i in 90:
		clock.advance(1.0)
		if jana.state == jana.State.ACTING and String(jana.current_action.get("id", "")) == "snack":
			ate = true
			break
	check(ok and ate, "agency: hráč může postavu poslat jíst")
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.eating.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	check(world.sims[0].psy.eating.to_dict() == before, "stav obnoven")
	world.sims[0]._update_net(100.0)
	var det := JSON.stringify(world.sims[0]._build_detail())
	check(not det.contains("body_image") and not det.contains("food_anxiety") and not det.contains("tělo"), "net_detail bez citlivého stavu")
	var leaked := false
	for th in world.sims[0].mental.thoughts:
		if String(th["text"]).contains("jídl") or String(th["text"]).contains("těl"):
			leaked = true
	check(not leaked, "citlivé myšlenky nejsou v síťovém proudu myšlenek")
	gs.set_value("sh_ed_topics", false, false)
	clock.advance(2.0)
	check(not world.sims[0].psy.eating.active(), "vypnutí citlivého obsahu stav zruší")
	world.free()
	await get_tree().process_frame
