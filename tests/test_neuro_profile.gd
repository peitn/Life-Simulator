extends "res://tests/test_base.gd"
## Psychika A – neurodivergentní profil (mind.neuro, schéma v9): validace a migrace, spojité účinky,
## režimy full/muted/off, agency (hráčův příkaz se provede), rozmanitost (stejná „nálepka“ → jiné
## chování), determinismus, uložení a načtení, soukromí v multiplayeru a posuvníky v editoru.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const NeuroProfile := preload("res://scripts/sim/neuro_profile.gd")
const PsycheExt := preload("res://scripts/sim/psyche_ext.gd")
const SensoryProfile := preload("res://scripts/sim/sensory_profile.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")

const ADHD_A := {"attention_drift": 0.8, "task_initiation": 0.7, "hyperfocus": 0.9, "interest_depth": 0.9}
const ADHD_B := {"attention_drift": 0.8, "task_initiation": 0.7, "action_impulsivity": 0.9, "time_blindness": 0.6}

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
	_test_neutral_and_continuous()
	_test_modes()
	_test_sensory()
	_test_social_and_strengths()
	await _test_agency()
	await _test_diversity_and_determinism()
	await _test_save_and_privacy()
	_test_editor()
	gs.reset()
	U.Main.household_override = []
	finish("test_neuro_profile")


func _agent(neuro: Dictionary, focus := "reading", d_over := {}) -> Node3D:
	var sim := Node3D.new()
	sim.set_script(SimAgent)
	sim.setup("Alex", "m", ["optimista"], Color.WHITE, 42, null)
	var cd := U.character(0, {"neuro": neuro, "interest_focus": focus, "dispositions": d_over})
	var v := Validator.validate(cd)
	sim.apply_character_private(v["data"])
	return sim


func _test_schema() -> void:
	section("Schéma v9: validace, migrace, soukromí, vypnutá témata")
	check(Schema.VERSION >= 9 and Schema.fields("mind").has("neuro") and Schema.fields("mind").has("interest_focus"),
		"schéma v9+ má mind.neuro a mind.interest_focus")
	check(Schema.NEURO_SLIDERS.size() == 15, "15 nezávislých os neuro profilu", str(Schema.NEURO_SLIDERS.size()))
	var d := U.character(0, {"neuro": {"hyperfocus": 0.7, "sens_sound": 0.4}, "interest_focus": "cooking"})
	var ok := Validator.validate(d)
	check(ok["ok"], "platný profil se přijme", str(ok["errors"]))
	var bad := d.duplicate(true)
	bad["mind"]["neuro"]["hyperfocus"] = 1.4
	check(not Validator.validate(bad)["ok"], "osa mimo 0..1 se na serveru odmítne")
	bad = d.duplicate(true)
	bad["mind"]["neuro"]["telepatie"] = 0.5
	check(not Validator.validate(bad)["ok"], "neznámá osa se odmítne")
	bad = d.duplicate(true)
	bad["mind"]["interest_focus"] = "hacking"
	check(not Validator.validate(bad)["ok"], "neznámý zájem se odmítne")
	bad = d.duplicate(true)
	bad["mind"]["neuro"]["tic_tendency"] = NAN
	check(not Validator.validate(bad)["ok"], "NaN se odmítne")
	var rep := Validator.validate(d.duplicate(true).merged({}), {"mode": "repair"})
	check(rep["ok"], "opravný režim je v pořádku")
	var older := d.duplicate(true)
	older["v"] = 8
	older["mind"].erase("neuro")
	older["mind"].erase("interest_focus")
	var mig := Codec.migrate(older)
	check(mig["ok"] and int(mig["data"]["v"]) == Schema.VERSION and mig["data"]["mind"]["neuro"] == {} \
		and mig["data"]["mind"]["interest_focus"] == "reading", "migrace v8 → v9 doplní prázdný profil")
	var from8 := Codec.from_dict(older)
	check(from8["ok"] and int(from8["from_version"]) == 8, "postava v8 se načte", str(from8["errors"]))
	var off := Validator.validate(ok["data"], {"mental_health": "off"})
	check(off["ok"] and off["data"]["mind"]["neuro"] == {} and off["data"]["mind"]["interest_focus"] == "reading",
		"mental_health = off: neuro profil se nepřijme (vrací se na výchozí)")
	var d2: Dictionary = ok["data"].duplicate(true)
	d2["mind"]["self_defectiveness"] = 0.6
	var off2 := Validator.validate(d2, {"mental_health": "off"})
	check(float(off2["data"]["mind"]["self_defectiveness"]) == 0.0, "mental_health = off: celé mind (i přesvědčení) se zahodí")
	var c := CharacterData.create()
	c.set_from_dict(ok["data"])
	var pub: Dictionary = c.public_snapshot()
	check(not pub.has("mind") and not U.contains_key(pub, ["neuro", "hyperfocus", "interest_focus"]),
		"veřejný snapshot neobsahuje neuro profil")


func _test_neutral_and_continuous() -> void:
	section("Neutrální postava beze změny, spojité účinky")
	var neutral := _agent({})
	check(neutral.psy.is_neutral(), "bez posuvníků je rozšíření neutrální")
	var all_one := true
	for a in ActionLibrary.ACTIONS:
		if neutral.psyche_action_weight(a) != 1.0:
			all_one = false
	check(all_one, "neutrální postava: násobič přesně 1,0 u všech akcí")
	check(neutral.psy.rng.state != 0 and neutral.psy.neuro.duration_mult(ActionLibrary.get_action("read"), false, 1.0) == 1.0,
		"neutrální postava: délka akcí beze změny")
	neutral.free()
	var cook := ActionLibrary.get_action("cook")
	var read := ActionLibrary.get_action("read")
	var w: Array = []
	for v in [0.0, 0.3, 0.6, 1.0]:
		var n := NeuroProfile.new()
		n.configure({"task_initiation": v}, "reading", {}, false)
		w.append(n.action_weight(cook, 12, 1.0))
	check(w[0] == 1.0 and w[0] > w[1] and w[1] > w[2] and w[2] > w[3] and w[3] > 0.35,
		"obtížné zahájení: vaření spojitě méně lákavé, nikdy nezakázané", str(w))
	var wi: Array = []
	for v in [0.0, 0.5, 1.0]:
		var n := NeuroProfile.new()
		n.configure({"interest_depth": v}, "reading", {}, false)
		wi.append(n.action_weight(read, 12, 1.0))
	check(wi[0] < wi[1] and wi[1] < wi[2] and wi[2] <= 2.0, "hloubka zájmu: čtení (zájem) spojitě víc", str(wi))
	var n2 := NeuroProfile.new()
	n2.configure({"task_initiation": 1.0}, "cooking", {}, false)
	check(n2.action_weight(cook, 12, 1.0) >= 1.0, "zájem o vaření ruší bariéru u vaření (silná stránka)")
	var hf := NeuroProfile.new()
	hf.configure({"hyperfocus": 1.0}, "reading", {}, false)
	check(hf.duration_mult(read, false, 1.0) > 1.4 and hf.duration_mult(read, true, 1.0) == 1.0,
		"hyperfokus natáhne autonomní čtení, hráčův příkaz ne")
	var dr := NeuroProfile.new()
	dr.configure({"attention_drift": 1.0}, "cooking", {}, false)
	check(dr.drift_hazard(read, false, 20.0, 1.0) > 0.0 and dr.drift_hazard(read, true, 20.0, 1.0) == 0.0 \
		and dr.drift_hazard(ActionLibrary.get_action("cook"), false, 20.0, 1.0) == 0.0,
		"roztěkanost: jen autonomní akce mimo zájem")
	var tb := NeuroProfile.new()
	tb.configure({"time_blindness": 1.0}, "reading", {}, false)
	var sleep := ActionLibrary.get_action("sleep")
	check(tb.action_weight(sleep, 23, 1.0) < 1.0 and tb.action_weight(sleep, 14, 1.0) == 1.0,
		"časová slepota oslabí večerní tah do postele (jen večer)")
	var ini := NeuroProfile.new()
	ini.configure({"task_initiation": 0.8}, "reading", {}, false)
	check(ini.initiation_barrier(cook, 1.0) > 0.0 and ini.initiation_barrier(ActionLibrary.get_action("watch_tv"), 1.0) == 0.0,
		"bariéra zahájení jen u povinností, ne u zábavy")


func _test_modes() -> void:
	section("Režimy obsahu full / muted / off")
	var n := NeuroProfile.new()
	n.configure({"task_initiation": 1.0, "interest_depth": 1.0}, "reading", {}, false)
	var cook := ActionLibrary.get_action("cook")
	var full := n.action_weight(cook, 12, PsycheExt.mode_k("full"))
	var muted := n.action_weight(cook, 12, PsycheExt.mode_k("muted"))
	var off := n.action_weight(cook, 12, PsycheExt.mode_k("off"))
	check(full < muted and muted < off and off == 1.0, "full silnější než muted, off přesně beze změny",
		"%.3f %.3f %.3f" % [full, muted, off])
	var sim := _agent({"sens_sound": 1.0})
	var f_full: float = sim.sensory.sensory_factor("noise")
	sim.psy.mode = "off"
	sim.sensory.channel_gain = sim.psy.neuro.channel_gains(sim.psy.k())
	check(f_full > sim.sensory.sensory_factor("noise") and sim.psyche_action_weight(cook) == 1.0,
		"off: citlivost kanálu i násobiče vypnuté")
	sim.free()


func _test_sensory() -> void:
	section("Smyslová citlivost po kanálech a přetížení")
	var sp := SensoryProfile.new()
	var base := sp.sensory_factor("noise")
	var n := NeuroProfile.new()
	n.configure({"sens_sound": 0.5, "sens_light": 1.0}, "reading", {}, false)
	sp.channel_gain = n.channel_gains(1.0)
	check(sp.sensory_factor("noise") > base and sp.sensory_factor("crowd") == SensoryProfile.new().sensory_factor("crowd"),
		"citlivost na zvuk zvedne jen zvukový kanál")
	check(sp.morning_light_factor() < sp.light_sens, "citlivost na světlo: ranní světlo potěší méně")
	var calm := NeuroProfile.new()
	calm.configure({"sens_sound": 1.0}, "reading", {}, false)
	for i in 6:
		calm.on_sensory("noise", 2.0, 1.0)
	check(calm.overload > 0.5, "opakovaný hluk → smyslové přetížení", "%.2f" % calm.overload)
	var hide := ActionLibrary.get_action("hide")
	var chat := ActionLibrary.get_action("chat")
	check(calm.action_weight(hide, 12, 1.0) > 1.0 and calm.action_weight(chat, 12, 1.0) < 1.0,
		"přetížení táhne do klidu a ubírá chuť na lidi")
	var labels: Array = []
	for e in calm.mood_entries(0.0, 1.0):
		labels.append(e["label"])
	check(labels.has("Smyslové přetížení"), "přetížení je pocit (slovy)")
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var before := calm.overload
	calm.tick(60.0, {"quiet": true}, 1.0, r)
	check(calm.overload < before * 0.5, "v klidu přetížení odezní")


func _test_social_and_strengths() -> void:
	section("Sociální energie, maskování, přímost")
	var n := NeuroProfile.new()
	n.configure({"social_energy": 1.0, "masking_cost": 1.0}, "reading", {}, false)
	var r1 := n.on_social_finished(10.0, 1.0)
	check(float(r1["energy"]) < 0.0 and float(r1["stress"]) > 0.0 and n.social_battery < 1.0,
		"hovor s cizím člověkem stojí energii a přizpůsobování")
	var n2 := NeuroProfile.new()
	n2.configure({"masking_cost": 1.0}, "reading", {}, false)
	check(float(n2.on_social_finished(80.0, 1.0)["stress"]) == 0.0, "s blízkým člověkem se nemaskuje")
	var chat := ActionLibrary.get_action("chat")
	for i in 3:
		n.on_social_finished(10.0, 1.0)
	check(n.action_weight(chat, 12, 1.0) < 0.8 and n.action_weight(ActionLibrary.get_action("relax"), 12, 1.0) > 1.0,
		"vybitá baterka: méně chuti na lidi, víc na klid (nikdy zákaz)")
	var r := RandomNumberGenerator.new()
	r.seed = 1
	n.tick(720.0, {"quiet": true}, 1.0, r)
	check(n.social_battery > 0.95, "baterka se v klidu dobije")
	var d := NeuroProfile.new()
	d.configure({"direct_communication": 1.0}, "reading", {}, false)
	check(d.talk_bias(80.0, 1.0) > 0.0 and d.talk_bias(0.0, 1.0) < 0.0 and d.swallow_mult(1.0) < 1.0,
		"přímost: u blízkých plus, u cizích riziko nedorozumění, výtku tolik nespolkne")
	var tic := NeuroProfile.new()
	tic.configure({"tic_tendency": 1.0}, "reading", {}, false)
	var rr := RandomNumberGenerator.new()
	rr.seed = 9
	var tics := 0
	for i in 200:
		if bool(tic.tick(10.0, {"stress": 70.0}, 1.0, rr)["tic"]):
			tics += 1
	var calm := NeuroProfile.new()
	calm.configure({"tic_tendency": 1.0}, "reading", {}, false)
	var rc := RandomNumberGenerator.new()
	rc.seed = 9
	var tics_calm := 0
	for i in 200:
		if bool(calm.tick(10.0, {"stress": 5.0, "quiet": true}, 1.0, rc)["tic"]):
			tics_calm += 1
	check(tics > tics_calm and tics_calm >= 0, "tiky jsou častější ve stresu", "%d vs %d" % [tics, tics_calm])


func _test_agency() -> void:
	section("Agency: hráčův příkaz se provede i při silné obtíži zahájit")
	var hh := U.household({0: {"neuro": {"task_initiation": 1.0, "attention_drift": 1.0}, "predispositions": {}}})
	var world := U.make_world(hh, clock)
	add_child(world)
	await get_tree().process_frame
	var s = world.sims[0]
	s.needs.values["hunger"] = 40.0
	var stove = null
	for o in world.smart_objects:
		if o.object_tag == "stove":
			stove = o
	check(stove != null, "v domě je sporák")
	var accepted: bool = s.command(ActionLibrary.get_action("cook"), stove)
	var cooked := false
	for i in 240:
		clock.advance(1.0)
		if s.state == s.State.ACTING and String(s.current_action.get("id", "")) == "cook":
			cooked = true
			break
	check(accepted and cooked, "příkaz „vařit“ se provede (případně po zrušitelném váhání)")
	check(s.by_player and float(s.current_action.get("duration", 0.0)) == float(ActionLibrary.get_action("cook")["duration"]),
		"hráčův příkaz se nezkracuje ani neprodlužuje")
	world.free()


func _sim_world(hh: Array, minutes: float) -> Dictionary:
	var world := U.make_world(hh, clock)
	add_child(world)
	await get_tree().process_frame
	var spent := {}
	var left := minutes
	var s0 = world.sims[0]
	while left > 0.0:
		clock.advance(2.0)
		left -= 2.0
		if s0.state == s0.State.ACTING:
			var id := String(s0.current_action.get("id", ""))
			spent[id] = int(spent.get(id, 0)) + 2
	var fp := U.action_fingerprint(world)
	var psy: Dictionary = world.sims[0].psy.to_dict()
	var stats := {"fp": fp, "psy": psy, "stress": world.sims[0].mental.stress, "minutes": spent}
	world.free()
	await get_tree().process_frame
	return stats


func _test_diversity_and_determinism() -> void:
	section("Rozmanitost a determinismus")
	var a: Dictionary = await _sim_world(U.household({0: {"neuro": ADHD_A}}), 3 * 1440.0)
	var a2: Dictionary = await _sim_world(U.household({0: {"neuro": ADHD_A}}), 3 * 1440.0)
	var b: Dictionary = await _sim_world(U.household({0: {"neuro": ADHD_B}}), 3 * 1440.0)
	var name: String = (a["fp"] as Dictionary).keys()[0]
	check(a["fp"] == a2["fp"] and a["psy"] == a2["psy"], "stejný seed → stejné chování i stav (determinismus)")
	var fa: Dictionary = a["fp"][name]
	var fb: Dictionary = b["fp"][name]
	var diff := 0
	for k in fa.keys() + fb.keys():
		diff += absi(int(fa.get(k, 0)) - int(fb.get(k, 0)))
	check(diff >= 6, "stejná nálepka (roztěkanost + obtížné zahájení), jiný profil → měřitelně jiné chování",
		"rozdíl %d: %s | %s" % [diff, str(fa), str(fb)])
	var ma: Dictionary = a["minutes"]
	var mb: Dictionary = b["minutes"]
	print("    čtení A %d min, B %d min" % [int(ma.get("read", 0)), int(mb.get("read", 0))])
	check(int(ma.get("read", 0)) > int(mb.get("read", 0)), "hyperfokus + zájem o knihy: víc času čtením",
		"%d vs %d min" % [int(ma.get("read", 0)), int(mb.get("read", 0))])
	var fun_b := int(mb.get("watch_tv", 0)) + int(mb.get("doomscroll", 0)) + int(mb.get("daydream", 0))
	var fun_a := int(ma.get("watch_tv", 0)) + int(ma.get("doomscroll", 0)) + int(ma.get("daydream", 0))
	check(fun_b > fun_a, "impulzivní profil: víc času rychlou zábavou", "%d vs %d min" % [fun_b, fun_a])
	var base: Dictionary = await _sim_world(U.household({}), 3 * 1440.0)
	check(not (base["fp"] as Dictionary).is_empty(), "výchozí domácnost běží")


func _test_save_and_privacy() -> void:
	section("Uložení, načtení a soukromí")
	var hh := U.household({0: {"neuro": {"social_energy": 0.9, "sens_sound": 0.8, "tic_tendency": 0.5}}})
	var world := U.make_world(hh, clock)
	add_child(world)
	await get_tree().process_frame
	U.run_minutes(clock, 600.0)
	var s = world.sims[0]
	s.psy.neuro.overload = 0.66
	s.psy.neuro.social_battery = 0.21
	var snap: Dictionary = SaveGame.capture(world)
	check(snap["ok"], "uložení domácnosti s neuro profilem")
	var before: Dictionary = s.psy.to_dict()
	s.psy.neuro.overload = 0.0
	var applied: Dictionary = SaveGame.apply(world, snap["data"])
	check(applied["ok"], "načtení", str(applied))
	var s2 = world.sims[0]
	check(s2.psy.to_dict() == before, "stav neuro profilu přežije uložení a načtení přesně")
	check(not s2.psy.is_neutral() and s2.psy.neuro.a("social_energy") > 0.89, "profil se po načtení znovu nastaví z CharacterData")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"] = {"neuro": {"overload": 7.0}}
	check(not SaveGame.apply(world, bad)["ok"], "poškozený stav rozšíření se odmítne celý")
	s2._update_net(100.0)
	var detail: Dictionary = s2._build_detail()
	check(not U.contains_key(detail, ["psyche_lines", "neuro", "overload", "social_battery", "psyche_ext"]),
		"net_detail (síť) neobsahuje nic z neuro profilu")
	var look: Dictionary = s2.look
	check(not U.contains_key(look, ["mind", "neuro"]), "spawn / veřejný vzhled neobsahuje mind")
	var info: Dictionary = s2.hud_info()
	check(info.has("psyche_lines"), "offline vlastník vidí slovní popis (hud_info)")
	var as_text := JSON.stringify(info.get("psyche_lines", []))
	var has_digit := false
	for ch in as_text:
		if ch in "0123456789":
			has_digit = true
	check(not has_digit, "popis bez čísel")
	world.free()
	await get_tree().process_frame


func _test_editor() -> void:
	section("Posuvníky v editoru")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var found := 0
	for id in Schema.NEURO_SLIDERS:
		if ui.find_child("Slider_neuro_" + id, true, false) is HSlider:
			found += 1
	check(found == Schema.NEURO_SLIDERS.size(), "každá osa má svůj posuvník", "%d" % found)
	var readout := Label.new()
	ui._on_slider(0.44, "neuro", "hyperfocus", readout)
	var ob: OptionButton = ui.find_child("Enum_interest_focus", true, false)
	check(ob != null, "výběr oblasti zájmu existuje")
	var idx := -1
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == "nature":
			idx = i
	ui._on_enum(idx, "interest_focus", ob)
	var out: Dictionary = ui.export_data()
	check(absf(float(out["mind"]["neuro"]["hyperfocus"]) - 0.44) < 0.001 and out["mind"]["interest_focus"] == "nature",
		"posuvník a výběr zapíšou soukromý profil")
	check(Validator.validate(out)["ok"], "výsledek editoru projde striktní validací")
	readout.free()
	ui.free()
