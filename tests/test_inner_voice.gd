extends "res://tests/test_base.gd"
## Psychika I – vnitřní hlas (mind.thoughts, v12): myšlenky jen z dat, smyčky ruminace (růst, rozptýlení,
## opora, řešení, spánek), náklady (spánek, energie, deprese), sebekritika z vnitřního přesvědčení,
## naděje; opt-in pasivní beznaděj (soukromá, nikdy akce, zvyšuje užitek pomoci, krizová pomoc vlastníkovi,
## slábne s oporou a spánkem); režimy, determinismus, uložení, soukromí, editor.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const InnerVoice := preload("res://scripts/sim/inner_voice.gd")
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
	_test_schema()
	_test_loops()
	_test_hopelessness_module()
	await _test_world()
	await _test_world_sensitive()
	gs.reset()
	U.Main.household_override = []
	finish("test_inner_voice")


func _test_schema() -> void:
	section("Schéma v12")
	check(Schema.VERSION >= 12 and Schema.THOUGHT_SLIDERS.size() == 3, "mind.thoughts se třemi osami")
	var d := U.character(0, {"thoughts": {"rumination": 0.9}})
	check(Validator.validate(d)["ok"], "platné")
	var old := d.duplicate(true)
	old["v"] = 11
	old["mind"].erase("thoughts")
	check(Codec.migrate(old)["data"]["mind"]["thoughts"] == {}, "migrace v11 → v12")
	check(Validator.validate(d, {"mental_health": "off"})["data"]["mind"]["thoughts"] == {}, "off: nepřijme se")


func _test_loops() -> void:
	section("Smyčky ruminace")
	var v := InnerVoice.new()
	v.tick(DAY, {"idle": true, "night_awake": true, "stress": 80.0}, 1.0)
	check(v.loops.is_empty(), "bez události žádná myšlenka (žádná náhodná výplň)")
	var txt := v.trigger("grievance", "u1", "Petr Dvořák", 0.5, 0.0, 1.0)
	check(txt != "" and v.loops.size() == 1, "událost otevře smyčku a dá myšlenku", txt)
	var s0 := float(v.loops[0]["strength"])
	var idle := InnerVoice.new()
	idle.trigger("grievance", "u1", "Petr", 0.5, 0.0, 1.0)
	var busy := InnerVoice.new()
	busy.trigger("grievance", "u1", "Petr", 0.5, 0.0, 1.0)
	for i in 36:
		idle.tick(10.0, {"night_awake": true, "stress": 60.0}, 1.0)
		busy.tick(10.0, {"distraction": 0.8, "stress": 60.0}, 1.0)
	check(float(idle.loops[0]["strength"]) > s0, "v nočním bdění smyčka sílí", "%.2f" % float(idle.loops[0]["strength"]))
	check(busy.loops.is_empty() or float(busy.loops[0]["strength"]) < s0 * 0.6, "rozptýlení ji tlumí")
	var sup := InnerVoice.new()
	sup.trigger("grievance", "u1", "Petr", 0.6, 0.0, 1.0)
	var nosup := InnerVoice.new()
	nosup.trigger("grievance", "u1", "Petr", 0.6, 0.0, 1.0)
	for i in 24:
		sup.tick(10.0, {"support": 0.8, "quiet": true}, 1.0)
		nosup.tick(10.0, {"quiet": true}, 1.0)
	check(sup.strength_total() < nosup.strength_total(), "opora tlumí přemítání")
	idle.resolve("u1", 0.5)
	check(float(idle.loops[0]["strength"]) < 0.6, "řešení (omluva) smyčku oslabí")
	var sleep := InnerVoice.new()
	sleep.trigger("worry", "", "", 0.6, 0.0, 1.0)
	sleep.tick(8 * 60.0, {"sleeping": true}, 1.0)
	check(sleep.loops.is_empty() or float(sleep.loops[0]["strength"]) < 0.2, "spánek starosti rozpustí")
	check(idle.sleep_quality_mult() < 1.0 and idle.energy_drain_mult() > 1.0 and idle.rumination_feed() > 0.0,
		"ruminace stojí spánek, energii a živí depresivní ruminaci")
	var cr := InnerVoice.new()
	cr.trigger("failure", "", "", 0.5, 0.0, 1.0, 0.8)
	var cr0 := InnerVoice.new()
	cr0.trigger("failure", "", "", 0.5, 0.0, 1.0, 0.0)
	var has_crit := false
	for l in cr.loops:
		if l["topic"] == "self_critical":
			has_crit = true
	check(has_crit and cr0.loops.size() == 1, "vnitřní přesvědčení o vlastní nedostatečnosti obrací nezdar proti sobě")
	var hope := InnerVoice.new()
	check(hope.positive("warm", "u2", "Eli", 0.0, 1.0) != "", "dobré zážitky dávají vlídné myšlenky")
	var w_conf := idle.action_weight(ActionLibrary.get_action("confide"), 1.0)
	var w_jour := idle.action_weight(ActionLibrary.get_action("journal"), 1.0)
	check(w_conf > 1.0 and w_jour > 1.0, "ruminace zvyšuje užitek svěřit se a psát deník")
	var bounded := true
	for a in ActionLibrary.ACTIONS:
		var w := idle.action_weight(a, 1.0)
		if w < 0.5 or w > 2.5:
			bounded = false
	check(bounded, "náklady jen omezeně – nic se nevynucuje ani nezakazuje")
	var off := InnerVoice.new()
	check(off.trigger("grievance", "u1", "P", 0.9, 0.0, 0.0) == "" and off.loops.is_empty(), "off: žádné smyčky")
	var mu := InnerVoice.new()
	mu.trigger("grievance", "u1", "P", 0.8, 0.0, 0.5)
	var fu := InnerVoice.new()
	fu.trigger("grievance", "u1", "P", 0.8, 0.0, 1.0)
	check(mu.strength_total() < fu.strength_total(), "muted slabší")
	var r1 := InnerVoice.new()
	r1.configure({"rumination": 1.0})
	var r0 := InnerVoice.new()
	r0.configure({"rumination": 0.0})
	r1.trigger("grievance", "u", "P", 0.4, 0.0, 1.0)
	r0.trigger("grievance", "u", "P", 0.4, 0.0, 1.0)
	check(r1.strength_total() > r0.strength_total(), "posuvník sklonu k ruminaci je spojitý účinek")


func _test_hopelessness_module() -> void:
	section("Pasivní beznaděj (jen opt-in)")
	var v := InnerVoice.new()
	v.trigger("self_critical", "", "", 0.9, 0.0, 1.0)
	for i in 60:
		v.tick(30.0, {"burden": 0.95, "stress": 85.0, "self_belief": 0.9, "rejection": 0.8, "allow_hopeless": false}, 1.0)
	check(v.hopelessness == 0.0, "bez opt-in citlivého obsahu beznaděj neexistuje")
	for i in 60:
		v.tick(30.0, {"burden": 0.95, "stress": 85.0, "self_belief": 0.9, "rejection": 0.8, "allow_hopeless": true}, 1.0)
	check(v.hopelessness >= InnerVoice.HOPELESS_SHOW, "s opt-in a těžkou zátěží se objeví", "%.2f" % v.hopelessness)
	var lines := v.private_lines(1.0, [["Linka první psychické pomoci (ČR)", "116 123"], ["Mezinárodní přehled linek pomoci", "findahelpline.com"]])
	var joined := "\n".join(lines)
	check(joined.contains("116 123") and joined.contains("findahelpline.com"), "vlastník vidí krizovou pomoc")
	check(v.action_weight(ActionLibrary.get_action("seek_help"), 1.0) > 1.5 and v.action_weight(ActionLibrary.get_action("confide"), 1.0) > 1.3,
		"beznaděj zvyšuje užitek obrátit se na někoho a vyhledat pomoc")
	var no_digits := true
	for t in InnerVoice.TEXT["hopeless"]:
		for ch in String(t):
			if ch in "0123456789":
				no_digits = false
	check(no_digits, "texty beznaděje bez čísel, metod a plánů")
	var supported := InnerVoice.new()
	supported.hopelessness = v.hopelessness
	var alone := InnerVoice.new()
	alone.hopelessness = v.hopelessness
	for i in 24:
		supported.tick(30.0, {"burden": 0.7, "stress": 50.0, "support": 0.8, "allow_hopeless": true}, 1.0)
		alone.tick(30.0, {"burden": 0.7, "stress": 50.0, "allow_hopeless": true}, 1.0)
	check(supported.hopelessness < alone.hopelessness, "opora beznaděj zmírňuje", "%.2f vs %.2f" % [supported.hopelessness, alone.hopelessness])
	var slept := InnerVoice.new()
	slept.hopelessness = 0.6
	slept.tick(480.0, {"burden": 0.5, "stress": 30.0, "sleeping": true, "allow_hopeless": true}, 1.0)
	check(slept.hopelessness < 0.6, "spánek a nižší stres pomáhají")
	var mut := InnerVoice.new()
	mut.hopelessness = 0.5
	mut.tick(10.0, {"allow_hopeless": false}, 0.5)
	check(mut.hopelessness == 0.0, "bez povolení se stav okamžitě ruší")
	var forbidden := ["suicide", "sebevrazda", "self_harm", "harm"]
	var any := false
	for a in ActionLibrary.ACTIONS:
		for f in forbidden:
			if String(a["id"]).contains(f):
				any = true
	check(not any, "žádná akce sebepoškození ani sebevraždy neexistuje")


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _test_world() -> void:
	section("Ve světě: události → myšlenky, brána pomoci, uložení, soukromí")
	var world := U.make_world(U.household({1: {"self_defectiveness": 0.8}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	var petr = _find(world, "Petr")
	var eli = world.sims[2]
	var help := ActionLibrary.get_action("seek_help")
	check(Planner.score_action(jana, help, 12) == 0.0, "bez důvodu AI pomoc nevyhledá (žádná výplň)")
	petr._social_outcome(jana, -10.0, "insult")
	check(not jana.psy.voice.loops.is_empty() and String(jana.psy.voice.loops[0]["about"]) == jana.memory_key(petr),
		"urážka → smyčka o konkrétním člověku (uid)")
	var thought: String = String(jana.mental.thoughts[-1]["text"]) if not jana.mental.thoughts.is_empty() else ""
	check(thought.contains("Petr"), "myšlenka je o tom, co se stalo", thought)
	petr.psy.voice.trigger("failure", "", "", 0.6, jana.now(), 1.0, petr.self_defectiveness_belief)
	var crit := false
	for l in petr.psy.voice.loops:
		if l["topic"] == "self_critical":
			crit = true
	check(crit, "u postavy s přesvědčením o vlastní nedostatečnosti vzniká sebekritika")
	jana.psy.voice.loops[0]["strength"] = 1.0
	jana.psy.voice.trigger("worry", "", "", 1.0, jana.now(), 1.0)
	check(Planner.score_action(jana, help, 12) >= 0.0 and jana.psyche_gate("help") > 0.0, "silná ruminace otevře bránu pomoci")
	var ok: bool = eli.command(help, null)
	var did := false
	for i in 60:
		clock.advance(1.0)
		if eli.state == eli.State.ACTING and String(eli.current_action.get("id", "")) == "seek_help":
			did = true
			break
	check(ok and did, "hráč může pomoc vyhledat kdykoli (i bez důvodu)")
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.voice.to_dict()
	check(SaveGame.apply(world, snap["data"])["ok"], "uložení a načtení")
	var j2 = _find(world, "Jana")
	check(j2.psy.voice.to_dict() == before, "smyčky přežijí uložení a načtení")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["voice"]["hopelessness"] = 3.0
	check(not SaveGame.apply(world, bad)["ok"], "neplatný stav se odmítne")
	world.free()
	await get_tree().process_frame
	section("Determinismus")
	var res: Array = []
	for i in 2:
		var w := U.make_world(U.household({}), clock)
		add_child(w)
		await get_tree().process_frame
		U.run_minutes(clock, 2.0 * DAY)
		var vv := {}
		for s in w.sims:
			vv[s.sim_name] = s.psy.voice.to_dict()
		res.append([U.action_fingerprint(w), vv])
		w.free()
		await get_tree().process_frame
	check(res[0] == res[1], "stejný seed → stejné myšlenky a chování")


func _test_world_sensitive() -> void:
	section("Opt-in citlivý obsah: beznaděj soukromě, nikdy akce, nikdy po síti")
	gs.set_value("sh_ed_topics", true, false)
	var world := U.make_world(U.household({0: {"self_defectiveness": 0.9}}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = _find(world, "Jana")
	jana.mental.dep.burden = 0.95
	jana.mental.stress = 90.0
	jana.psy.voice.trigger("self_critical", "", "", 0.9, jana.now(), 1.0)
	var actions_seen := {}
	jana.action_started.connect(func(_s, a): actions_seen[String(a.get("id", ""))] = true)
	for i in 600:
		jana.mental.dep.burden = maxf(jana.mental.dep.burden, 0.9)
		clock.advance(2.0)
	check(jana.psy.voice.hopelessness >= InnerVoice.HOPELESS_SHOW, "beznaděj se objeví jen s opt-in", "%.2f" % jana.psy.voice.hopelessness)
	check(jana.psy.voice.crisis_shown, "vlastníkovi se ukázala krizová pomoc")
	var lines := "\n".join(jana.psyche_private_lines())
	check(lines.contains("116 123"), "soukromý popis obsahuje linku 116 123")
	var leaked := false
	for th in jana.mental.thoughts:
		for t in InnerVoice.TEXT["hopeless"]:
			if String(th["text"]) == String(t):
				leaked = true
	jana._update_net(100.0)
	var det_txt := JSON.stringify(jana._build_detail())
	check(not leaked and not det_txt.contains("hopeless") and not det_txt.contains("116 123") and not det_txt.contains("beznaděj"),
		"beznaděj není v síťovém detailu ani v proudu myšlenek")
	var other_lines := "\n".join(_find(world, "Petr").psyche_private_lines())
	check(not other_lines.contains("beznaděj"), "jiná postava o tom neví")
	var only_safe := true
	for id in actions_seen:
		var a: Dictionary = ActionLibrary.get_action(String(id))
		if a.is_empty() or bool(a.get("player_only", false)):
			only_safe = false
	check(only_safe, "nevznikla žádná nová ani skrytá akce (jen běžné akce domácnosti)", str(actions_seen.keys()))
	gs.set_value("sh_ed_topics", false, false)
	clock.advance(2.0)
	check(jana.psy.voice.hopelessness == 0.0, "vypnutí opt-in stav okamžitě zruší")
	world.free()
	await get_tree().process_frame
	section("Editor")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(U.character(0))["data"])
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	ui._on_slider(0.8, "thoughts", "rumination", Label.new())
	check(ui.find_child("Slider_thoughts_hope", true, false) is HSlider and absf(float(ui.export_data()["mind"]["thoughts"]["rumination"]) - 0.8) < 0.001,
		"posuvníky vnitřního hlasu v editoru")
	ui.free()
