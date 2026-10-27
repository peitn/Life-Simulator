extends "res://tests/test_base.gd"
## Psychika C – průběh nálady (mind.mood, v11): bipolární spektrum (hypomanie / mánie / depresivní fáze),
## rychlé střídání, dlouhodobě nízká nálada, spouštěče (spánek, stres), zotavení, rozlišení od ADHD a
## od přirozeně vysoké energie, režimy, agency, rozmanitost, determinismus, uložení, soukromí.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const MoodCycle := preload("res://scripts/sim/mood_cycle.gd")
const Depression := preload("res://scripts/sim/depression.gd")
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
	_test_neutral()
	_test_state_machine()
	_test_triggers_and_recovery()
	_test_effects()
	_test_chronic_low()
	_test_diversity()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_mood_cycle")


## Simulace samotného modulu: dny s pravidelným spánkem (22–6) nebo s probděnými nocemi.
func _simulate(mc: MoodCycle, days: int, seed: int, sleep_loss: bool, k := 1.0, stress := 20.0, support := 0.0) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var t := 0.0
	var phases := {}
	while t < days * DAY:
		var h := int(fmod(t, DAY) / 60.0)
		var night := h >= 22 or h < 6
		var sleeping := night and not (sleep_loss and h >= 22)
		mc.tick(10.0, {"sleeping": sleeping, "night": night, "stress": stress, "support": support}, k, r)
		phases[mc.phase] = int(phases.get(mc.phase, 0)) + 10
		t += 10.0
	return phases


func _test_schema() -> void:
	section("Schéma v11")
	check(Schema.VERSION >= 11 and Schema.MOOD_SLIDERS.size() == 5 and Schema.fields("mind").has("mood"), "mind.mood s pěti osami")
	var d := U.character(0, {"mood": {"bipolar_tendency": 0.7, "elevation_ceiling": 0.2}})
	check(Validator.validate(d)["ok"], "platný průběh se přijme")
	var bad := d.duplicate(true)
	bad["mind"]["mood"]["cycling"] = 2.0
	check(not Validator.validate(bad)["ok"], "mimo rozsah se odmítne")
	var old := d.duplicate(true)
	old["v"] = 10
	old["mind"].erase("mood")
	var m := Codec.migrate(old)
	check(m["ok"] and m["data"]["mind"]["mood"] == {}, "migrace v10 → v11")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["mind"]["mood"] == {}, "off: průběh se nepřijme")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(d)["data"])
	check(not U.contains_key(c.public_snapshot(), ["mood", "bipolar_tendency"]), "veřejný snapshot bez průběhu nálady")


func _test_neutral() -> void:
	section("Bez posuvníků nic")
	var mc := MoodCycle.new()
	mc.configure({}, false)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var st := r.state
	for i in 500:
		mc.tick(30.0, {"night": true, "stress": 90.0}, 1.0, r)
	check(mc.pole == 0.0 and mc.phase == "euthymic" and r.state == st, "neutrální: žádné výkyvy a žádná spotřeba náhody")
	check(mc.action_weight(ActionLibrary.get_action("sleep"), 23, 1.0) == 1.0 and mc.energy_mult(1.0) == 1.0, "neutrální násobiče přesně 1")


func _test_state_machine() -> void:
	section("Fáze: nástup, potvrzení, strop, odeznění")
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var lo := MoodCycle.new()
	lo.configure({"bipolar_tendency": 0.01, "elevation_ceiling": 0.0}, false)
	lo.target = lo.ceiling(1.0)
	lo.episode_left = 5.0 * DAY
	var hi := MoodCycle.new()
	hi.configure({"bipolar_tendency": 0.01, "elevation_ceiling": 1.0}, false)
	hi.target = hi.ceiling(1.0)
	hi.episode_left = 5.0 * DAY
	var saw_hypo_early := false
	for i in 72:
		lo.tick(10.0, {"sleeping": false}, 1.0, r)
		if lo.phase != "euthymic":
			saw_hypo_early = true
	check(not saw_hypo_early, "fáze se potvrdí až po delší době nad hranicí (ne hned)")
	for i in 400:
		lo.tick(10.0, {"sleeping": false}, 1.0, r)
		hi.tick(10.0, {"sleeping": false}, 1.0, r)
	check(lo.phase == "hypomanic", "nízký strop: jen hypomanie", lo.phase)
	check(hi.phase == "manic", "vysoký strop: i mánie", hi.phase)
	var mu := MoodCycle.new()
	mu.configure({"bipolar_tendency": 0.01, "elevation_ceiling": 1.0}, false)
	mu.target = mu.ceiling(0.5)
	mu.episode_left = 5.0 * DAY
	for i in 600:
		mu.tick(10.0, {"sleeping": false}, 0.5, r)
	check(mu.phase != "manic" and mu.pole <= 0.26, "muted: bez mánie, jen mírně", "%s %.2f" % [mu.phase, mu.pole])
	for i in 1200:
		hi.tick(10.0, {"sleeping": true, "support": 0.5}, 1.0, r)
	check(hi.phase == "euthymic" and absf(hi.pole) < 0.25, "epizoda odezní (spánek, opora)", "%s %.2f" % [hi.phase, hi.pole])
	check(hi.episodes_up == 1, "epizoda se započítá jednou")
	var off := MoodCycle.new()
	off.configure({"bipolar_tendency": 1.0}, false)
	_simulate(off, 20, 4, true, 0.0)
	check(off.phase == "euthymic" and off.pole == 0.0, "off: žádné epizody")


func _test_triggers_and_recovery() -> void:
	section("Spouštěče a zotavení")
	var with_loss := 0
	var without := 0
	for s in 6:
		var a := MoodCycle.new()
		a.configure({"bipolar_tendency": 0.6, "sleep_sensitivity": 0.8}, false)
		_simulate(a, 30, 100 + s, true)
		with_loss += a.episodes_up + a.episodes_down
		var b := MoodCycle.new()
		b.configure({"bipolar_tendency": 0.6, "sleep_sensitivity": 0.8}, false)
		_simulate(b, 30, 100 + s, false)
		without += b.episodes_up + b.episodes_down
	check(with_loss > without, "probděné noci spouštějí víc epizod", "%d vs %d" % [with_loss, without])
	var dur_sup := 0
	var dur_no := 0
	for s in 4:
		for sup in [0.0, 0.8]:
			var m := MoodCycle.new()
			m.configure({"bipolar_tendency": 0.01}, false)
			m.target = -0.8
			m.episode_left = 3.0 * DAY
			var r := RandomNumberGenerator.new()
			r.seed = s
			var t := 0
			while m.episode_left > 0.0 and t < 10000:
				m.tick(10.0, {"sleeping": false, "support": sup}, 1.0, r)
				t += 1
			if sup > 0.0:
				dur_sup += t
			else:
				dur_no += t
	check(dur_sup < dur_no, "opora epizodu zkracuje (zotavení není nikdy zavřené)", "%d vs %d" % [dur_sup, dur_no])


func _test_effects() -> void:
	section("Účinky zvýšené fáze (omezené násobiče)")
	var m := MoodCycle.new()
	m.configure({"bipolar_tendency": 0.5}, false)
	m.pole = 0.7
	check(m.action_weight(ActionLibrary.get_action("sleep"), 23, 1.0) < 1.0 and m.action_weight(ActionLibrary.get_action("chat"), 12, 1.0) > 1.0,
		"méně tahu do postele, víc chuti na lidi")
	check(m.action_weight(ActionLibrary.get_action("drink"), 12, 1.0) > m.action_weight(ActionLibrary.get_action("chat"), 12, 1.0),
		"riskantnější volby lákají víc")
	check(m.energy_mult(1.0) < 1.0 and m.sleep_rate_mult(1.0) > 1.0, "menší potřeba spánku")
	check(m.talk_bias(80.0, 1.0) < m.talk_bias(10.0, 1.0) and m.talk_bias(10.0, 1.0) <= 0.0, "podrážděnost (víc ve stresu)")
	var all_bounded := true
	for a in ActionLibrary.ACTIONS:
		var w := m.action_weight(a, 23, 1.0)
		if w <= 0.0 or w > 2.0:
			all_bounded = false
	check(all_bounded, "žádná akce není zakázaná ani extrémní")


func _test_chronic_low() -> void:
	section("Dlouhodobě nízká nálada (dystymní průběh)")
	var m := MoodCycle.new()
	m.configure({"chronic_low": 1.0}, false)
	var d := Depression.new()
	d.chronic_floor = m.chronic_floor(1.0)
	var d0 := Depression.new()
	var cfg := {"conditions": true, "episodes": true}
	for i in 30 * 24:
		for x in [d, d0]:
			x.tick(60.0, {"stress": 20.0, "social": 70.0, "energy": 70.0, "support": 0.2, "sleeping": (i % 24) < 8, "hour": i % 24, "cfg": cfg})
	check(d.burden > 0.3 and d0.burden < 0.15, "trvale nízká nálada drží zátěž výš", "%.2f vs %.2f" % [d.burden, d0.burden])
	check(not d.episode_active and d.label(cfg) != "", "bez epizody, ale slovně „skleslost“", d.label(cfg))
	check(m.chronic_floor(0.5) < m.chronic_floor(1.0) and m.chronic_floor(0.0) == 0.0, "muted slabší, off nic")


func _test_diversity() -> void:
	section("Rozmanitost: stejná tendence, jiný průběh")
	var typ1 := MoodCycle.new()
	typ1.configure({"bipolar_tendency": 0.8, "elevation_ceiling": 1.0}, false)
	var cyc := MoodCycle.new()
	cyc.configure({"bipolar_tendency": 0.8, "cycling": 1.0}, false)
	var p1 := _simulate(typ1, 40, 7, true)
	var p2 := _simulate(cyc, 40, 7, true)
	check(typ1.peak > cyc.peak + 0.15, "vysoký strop: vyšší vrcholy", "%.2f vs %.2f" % [typ1.peak, cyc.peak])
	check(cyc.episodes_up + cyc.episodes_down != typ1.episodes_up + typ1.episodes_down or p1 != p2,
		"rychlé střídání: jiný počet a délka fází", "%s | %s" % [str(p1), str(p2)])


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _test_world() -> void:
	section("Ve světě: vazba na depresi, ADHD a energie ≠ hypomanie, agency, uložení, soukromí")
	var hh := U.household({0: {"mood": {"bipolar_tendency": 0.9, "elevation_ceiling": 0.8}},
		1: {"neuro": {"action_impulsivity": 1.0, "attention_drift": 1.0}, "dispositions": {"energy_baseline": 0.95}}})
	var world := U.make_world(hh, clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	var petr = _find(world, "Petr")
	jana.psy.mood.target = -0.9
	jana.psy.mood.episode_left = 3.0 * DAY
	var b0: float = jana.mental.dep.burden
	U.run_minutes(clock, DAY)
	check(jana.mental.dep.burden > b0 + 0.15, "depresivní fáze zvedá existující depresivní zátěž",
		"%.2f → %.2f" % [b0, jana.mental.dep.burden])
	jana.psy.mood.target = 0.8
	jana.psy.mood.episode_left = 4.0 * DAY
	U.run_minutes(clock, 1.5 * DAY)
	check(jana.psy.mood.phase in ["hypomanic", "manic"], "zvýšená fáze se projeví i ve světě", jana.psy.mood.phase)
	var lines: PackedStringArray = jana.psyche_private_lines()
	check(not lines.is_empty() and not "".join(lines).contains("0."), "soukromý popis fáze slovy")
	jana.needs.values["energy"] = 30.0
	var bed = null
	for o in world.smart_objects:
		if o.object_tag == "bed" and o.is_available(jana):
			bed = o
	var ok: bool = jana.command(ActionLibrary.get_action("sleep"), bed) if bed != null else false
	var slept := false
	for i in 120:
		clock.advance(1.0)
		if jana.state == jana.State.ACTING and String(jana.current_action.get("id", "")) == "sleep":
			slept = true
			break
	check(ok and slept, "agency: i ve zvýšené fázi jde poslat postavu spát")
	check(petr.psy.mood.is_empty() and petr.psy.mood.phase == "euthymic",
		"ADHD-like profil s vysokou obvyklou energií nemá epizody (průběh se měří vůči vlastnímu normálu)")
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.mood.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	var j2 = _find(world, "Jana")
	check(j2.psy.mood.to_dict() == before, "stav průběhu nálady přesně obnoven")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["mood"]["phase"] = "superman"
	check(not SaveGame.apply(world, bad)["ok"], "neplatná fáze se odmítne")
	j2._update_net(100.0)
	check(not U.contains_key(j2._build_detail(), ["pole", "phase", "psyche_lines", "mood_cycle"]), "net_detail bez průběhu nálady")
	world.free()
	await get_tree().process_frame
	section("Determinismus")
	var res: Array = []
	for i in 2:
		var w := U.make_world(U.household({0: {"mood": {"bipolar_tendency": 1.0, "cycling": 0.5}}}), clock)
		add_child(w)
		await get_tree().process_frame
		U.run_minutes(clock, 3.0 * DAY)
		res.append([U.action_fingerprint(w), w.sims[0].psy.mood.to_dict()])
		w.free()
		await get_tree().process_frame
	check(res[0] == res[1], "stejný seed → stejný průběh")
	section("Editor")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var n := 0
	for id in Schema.MOOD_SLIDERS:
		if ui.find_child("Slider_mood_" + id, true, false) is HSlider:
			n += 1
	ui._on_slider(0.6, "mood", "cycling", Label.new())
	check(n == 5 and absf(float(ui.export_data()["mind"]["mood"]["cycling"]) - 0.6) < 0.001, "posuvníky průběhu nálady v editoru")
	ui.free()
