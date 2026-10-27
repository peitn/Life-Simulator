extends "res://tests/test_base.gd"
## Psychika J – světonázor, názory a hodnoty: obecná témata, síla a jistota, pomalý posun s mezemi
## (důvěra, konfirmační zkreslení, odpor podle jistoty), vliv na vřelost jen jako jeden z faktorů,
## nesouhlas a náklonnost současně, žádná polarizace v domácnosti, determinismus, uložení, soukromí,
## veřejné vyjádření jen s volbou, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Worldview := preload("res://scripts/sim/worldview.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

const DAY := 1440.0

var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 400.0
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
	finish("test_worldview")


func _pers(i: int, wv: Dictionary, vals := {}, cert := 0.5, voice := false) -> Dictionary:
	var hh: Array = U.household({})
	var p: Dictionary = (hh[i].get("personality", {}) as Dictionary).duplicate(true)
	p["worldview"] = wv
	p["values"] = vals
	p["opinion_certainty"] = cert
	p["voice_opinions"] = voice
	return p


func _test_schema() -> void:
	section("Schéma v17: obecná témata, soukromé")
	check(Schema.VERSION >= 17 and Schema.WORLDVIEW_TOPICS.size() == 9 and Schema.VALUE_SLIDERS.size() == 7, "9 témat, 7 hodnot")
	var banned := ["ods", "ano ", "komun", "kscm", "spd", "pirát", "babiš", "fiala", "křesť", "islám", "katol", "žid", "levic", "pravic", "liberál", "konzerv"]
	var clean := true
	for t in Schema.WORLDVIEW_TOPICS:
		for b in banned:
			if String(Schema.WORLDVIEW_TOPICS[t]).to_lower().contains(b) and not (b == "komun" and t == "community"):
				clean = false
	for t in Worldview.LINES:
		for l in Worldview.LINES[t]:
			for b in banned:
				if String(l).to_lower().contains(b):
					clean = false
	check(clean, "žádné skutečné strany, politici ani náboženství")
	var d := U.character(0)
	d["personality"]["worldview"] = {"tradition": -0.8, "family": 0.6}
	d["personality"]["values"] = {"care": 0.9}
	check(Validator.validate(d)["ok"], "platné")
	var bad := d.duplicate(true)
	bad["personality"]["worldview"]["tradition"] = -1.5
	check(not Validator.validate(bad)["ok"], "mimo −1..1 se odmítne")
	var old := d.duplicate(true)
	old["v"] = 16
	old["personality"].erase("worldview")
	old["personality"].erase("values")
	var m := Codec.migrate(old)
	check(m["data"]["personality"]["worldview"] == {} and m["data"]["personality"]["voice_opinions"] == false, "migrace v16 → v17")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(d)["data"])
	check(not U.contains_key(c.public_snapshot(), ["worldview", "values", "opinion_certainty"]), "veřejný snapshot bez názorů")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["personality"]["worldview"].size() == 2, "nejde o téma duševního zdraví (off ho nemaže)")


func _test_model() -> void:
	section("Pomalý posun s mezemi")
	var a := Worldview.new()
	a.configure({"tradition": 0.8}, {}, 0.3, false, false)
	var b := Worldview.new()
	b.configure({"tradition": -0.2}, {}, 0.5, false, false)
	var d1 := a.hear(b, "tradition", 90.0, true)
	check(d1 < 0.0 and absf(d1) < 0.05, "důvěryhodný člověk posune názor jen o malý krok", "%.3f" % d1)
	var dn := Worldview.new()
	dn.configure({"tradition": 0.8}, {}, 0.3, false, false)
	check(dn.hear(b, "tradition", 10.0, true) == 0.0 and dn.hear(b, "tradition", 90.0, false) == 0.0, "nedůvěra nebo hádka nic neposune")
	var sure := Worldview.new()
	sure.configure({"tradition": 0.8}, {}, 0.95, false, false)
	check(absf(sure.hear(b, "tradition", 90.0, true)) < absf(d1), "jistota = odpor ke změně")
	var far := Worldview.new()
	far.configure({"tradition": -1.0}, {}, 0.5, false, false)
	var near := Worldview.new()
	near.configure({"tradition": 0.2}, {}, 0.5, false, false)
	var x1 := Worldview.new()
	x1.configure({"tradition": 0.8}, {}, 0.3, false, false)
	var x2 := Worldview.new()
	x2.configure({"tradition": 0.8}, {}, 0.3, false, false)
	var df := absf(x1.hear(far, "tradition", 90.0, true))
	var dnr := absf(x2.hear(near, "tradition", 90.0, true))
	check(df < dnr, "konfirmační zkreslení: velmi vzdálený názor hýbe méně než bližší")
	for i in 1000:
		a.hear(far, "tradition", 100.0, true)
	check(float(a.stance["tradition"]) >= 0.8 - Worldview.MAX_DRIFT - 1e-6, "posun má mez (±0,4 od vlastního postoje)", "%.2f" % float(a.stance["tradition"]))
	a.tick(60.0 * DAY)
	check(absf(float(a.stance["tradition"]) - 0.8) < 0.1, "bez dalších podnětů se vrací k vlastnímu postoji")
	section("Vřelost: jen jeden z faktorů")
	var p := Worldview.new()
	p.configure({"family": 0.9}, {"loyalty": 0.9}, 0.5, false, false)
	var q := Worldview.new()
	q.configure({"family": -0.9}, {"loyalty": 0.9}, 0.5, false, false)
	var r := Worldview.new()
	r.configure({"family": 0.8}, {"loyalty": 0.9}, 0.5, false, false)
	check(p.talk_bias(q) < 0.0 and p.talk_bias(r) > 0.0 and absf(p.talk_bias(q)) <= 0.031, "shoda/nesouhlas posune rozhovor nanejvýš o ±0,03")
	check(p.warmth_mult(q) >= 0.93 and p.warmth_mult(r) <= 1.07, "násobič vřelosti omezený")
	var none := Worldview.new()
	none.configure({}, {}, 0.5, false, false)
	check(not none.active() and none.talk_bias(p) == 0.0 and p.talk_bias(none) == 0.0, "bez názorů žádný vliv")
	check(p.opinion_line("family") == "", "bez volby se názor nahlas neříká")
	var loud := Worldview.new()
	loud.configure({"family": 0.9}, {}, 0.5, true, false)
	check(loud.opinion_line("family") != "", "s volbou postava názor vysloví")


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _run_household(days: float) -> Dictionary:
	var hh: Array = U.household({})
	hh[0]["personality"] = _pers(0, {"tradition": 0.9, "community": 0.6, "risk": -0.5}, {"security": 0.9})
	hh[1]["personality"] = _pers(1, {"tradition": -0.9, "community": -0.5, "risk": 0.7}, {"freedom": 0.9})
	hh[2]["personality"] = _pers(2, {"tradition": 0.1, "community": 0.2, "risk": 0.0}, {"care": 0.8}, 0.3, true)
	var w := U.make_world(hh, clock)
	add_child(w)
	await get_tree().process_frame
	var pol0 := 0.0
	for s in w.sims:
		for t in s.psy.worldview.stance:
			pol0 += absf(float(s.psy.worldview.stance[t]))
	U.run_minutes(clock, days * DAY)
	var pol1 := 0.0
	var max_drift := 0.0
	var shifts := 0
	for s in w.sims:
		for t in s.psy.worldview.stance:
			pol1 += absf(float(s.psy.worldview.stance[t]))
			max_drift = maxf(max_drift, absf(float(s.psy.worldview.stance[t]) - float(s.psy.worldview.base[t])))
		shifts += s.psy.worldview.shifts
	var states := {}
	for s in w.sims:
		states[s.sim_name] = s.psy.worldview.to_dict()
	var res := {"pol0": pol0, "pol1": pol1, "drift": max_drift, "shifts": shifts, "states": states, "fp": U.action_fingerprint(w), "world": w}
	return res


func _test_world() -> void:
	section("Domácnost: žádná polarizace, determinismus")
	var r1: Dictionary = await _run_household(10.0)
	check(float(r1["pol1"]) <= float(r1["pol0"]) + 0.05, "průměrná vyhraněnost nevzrostla (žádná polarizace)", "%.2f → %.2f" % [r1["pol0"], r1["pol1"]])
	check(float(r1["drift"]) <= Worldview.MAX_DRIFT + 1e-6 and int(r1["shifts"]) > 0, "názory se pomalu posunuly v mezích",
		"drift %.3f, posunů %d" % [r1["drift"], r1["shifts"]])
	var w: Node = r1["world"]
	var snap: Dictionary = SaveGame.capture(w)
	var before: Dictionary = w.sims[0].psy.worldview.to_dict()
	check(SaveGame.apply(w, snap["data"])["ok"] and w.sims[0].psy.worldview.to_dict() == before, "uložení a načtení názorů")
	w.sims[0]._update_net(100.0)
	check(not JSON.stringify(w.sims[0]._build_detail()).contains("stance"), "net_detail bez názorů")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["worldview"]["stance"]["strana_x"] = 1.0
	check(not SaveGame.apply(w, bad)["ok"], "neznámé téma se odmítne")
	w.free()
	await get_tree().process_frame
	var r2: Dictionary = await _run_household(10.0)
	check(r1["states"] == r2["states"] and r1["fp"] == r2["fp"], "stejný seed → stejné názory i chování")
	(r2["world"] as Node).free()
	await get_tree().process_frame
	section("Nesouhlas a náklonnost současně")
	var hh: Array = U.household({})
	hh[0]["personality"] = _pers(0, {"family": 0.9, "tradition": 0.8}, {"loyalty": 0.9}, 0.8)
	hh[1]["personality"] = _pers(1, {"family": -0.9, "tradition": -0.8}, {"loyalty": 0.9}, 0.8)
	var wd := U.make_world(hh, clock)
	add_child(wd)
	await get_tree().process_frame
	var jana = _find(wd, "Jana")
	var petr = _find(wd, "Petr")
	jana.relationships[petr.sim_name] = 85.0
	petr.relationships[jana.sim_name] = 85.0
	U.run_minutes(clock, 8.0 * DAY)
	check(float(jana.relationships[petr.sim_name]) >= 60.0 and float(petr.relationships[jana.sim_name]) >= 60.0,
		"protichůdné názory a přesto blízký vztah", "%.0f / %.0f" % [jana.relationships[petr.sim_name], petr.relationships[jana.sim_name]])
	wd.free()
	await get_tree().process_frame
	section("Editor")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	ui._on_slider(-0.6, "worldview", "risk", Label.new())
	ui._on_slider(0.8, "values", "fairness", Label.new())
	ui._on_slider(0.2, "pers_scalar", "opinion_certainty", Label.new())
	var cb: CheckBox = ui.find_child("Bool_voice_opinions", true, false)
	cb.button_pressed = true
	var out: Dictionary = ui.export_data()
	check(absf(float(out["personality"]["worldview"]["risk"]) + 0.6) < 0.001 and absf(float(out["personality"]["values"]["fairness"]) - 0.8) < 0.001
		and absf(float(out["personality"]["opinion_certainty"]) - 0.2) < 0.001 and out["personality"]["voice_opinions"] == true,
		"posuvníky světonázoru, hodnot, jistoty a volba vyjadřování")
	check(Validator.validate(out)["ok"], "výstup editoru je platný")
	ui.free()
