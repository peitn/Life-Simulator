extends "res://tests/test_base.gd"
## Psychika B – sociální a afektivní paměť (strukturované stopy) a schopnosti paměti (mind.memory, v10):
## vyhasínání (silné pomaleji), zesílení, přepsání omluvou, oživení podnětem bez kmitání, hystereze
## popisků, fakt vs. výklad, soukromé vs. sdílené (viděl / slyšel / řekli mu), vliv jen na náklady a
## pravděpodobnosti, posuvníky paměti, determinismus, uložení a načtení, soukromí v síti.

const U := preload("res://tests/psyche_test_util.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const SocialMemory := preload("res://scripts/sim/social_memory.gd")
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
	_test_schema()
	_test_dynamics()
	_test_direction_no_oscillation()
	_test_cues_and_labels()
	_test_abilities()
	await _test_world()
	gs.reset()
	U.Main.household_override = []
	finish("test_social_memory")


func _test_schema() -> void:
	section("Schéma v10: schopnosti paměti")
	check(Schema.VERSION >= 10 and Schema.fields("mind").has("memory") and Schema.MEMORY_SLIDERS.size() == 3,
		"mind.memory se třemi osami")
	var d := U.character(1, {"memory": {"retention": 0.9, "precision": 0.2}})
	check(Validator.validate(d)["ok"], "platné schopnosti paměti se přijmou")
	var bad := d.duplicate(true)
	bad["mind"]["memory"]["retention"] = -0.1
	check(not Validator.validate(bad)["ok"], "mimo rozsah se odmítne")
	var old := d.duplicate(true)
	old["v"] = 9
	old["mind"].erase("memory")
	var m := Codec.migrate(old)
	check(m["ok"] and m["data"]["mind"]["memory"] == {} and int(m["data"]["v"]) == Schema.VERSION, "migrace v9 → v10")
	var off := Validator.validate(d, {"mental_health": "off"})
	check(off["data"]["mind"]["memory"] == {}, "mental_health = off: schopnosti paměti se nepřijmou (průměr)")
	var c := CharacterData.create()
	c.set_from_dict(Validator.validate(d)["data"])
	check(not U.contains_key(c.public_snapshot(), ["memory", "retention"]), "veřejný snapshot bez paměti")
	var ui: Control = load("res://scripts/ui/personality_slider_editor.gd").new()
	ui.load_character(c)
	ui._build()
	var sl: HSlider = ui.find_child("Slider_memory_retention", true, false)
	check(sl != null and absf(sl.value - 0.9) < 0.001 and ui.find_child("Slider_memory_precision", true, false) is HSlider,
		"editor: posuvníky paměti v samostatné sekci")
	ui._on_slider(0.15, "memory", "emotional_weight", Label.new())
	check(absf(float(ui.export_data()["mind"]["memory"]["emotional_weight"]) - 0.15) < 0.001, "posuvník paměti zapíše hodnotu")
	ui.free()


func _test_dynamics() -> void:
	section("Vyhasínání, zesílení, přepsání")
	var m := SocialMemory.new()
	m.record("u1", "Petr", "insult", 0.9, 0.0)
	m.record("u2", "Eli", "complaint", 0.2, 0.0)
	var s_big0 := float(m.traces_about("u1")[0]["strength"])
	var s_small0 := float(m.traces_about("u2")[0]["strength"])
	m.tick(DAY * 2.0)
	var s_big := float(m.traces_about("u1")[0]["strength"]) / s_big0
	var s_small_list := m.traces_about("u2")
	var s_small := (float(s_small_list[0]["strength"]) / s_small0) if not s_small_list.is_empty() else 0.0
	check(s_big > s_small, "silná stopa vyhasíná pomaleji než drobnost", "%.2f vs %.2f" % [s_big, s_small])
	var before := float(m.traces_about("u1")[0]["strength"])
	m.record("u1", "Petr", "insult", 0.6, DAY * 2.0)
	check(m.traces_about("u1").size() == 1 and float(m.traces_about("u1")[0]["strength"]) > before \
		and int(m.traces_about("u1")[0]["count"]) == 2, "stejný druh od stejné osoby stopu zesílí (žádný duplikát)")
	var g_before := float(m.traces_about("u1")[0]["strength"])
	m.record("u1", "Petr", "apology", 0.8, DAY * 2.0 + 10.0)
	var ins := 0.0
	for tr in m.traces_about("u1"):
		if tr["kind"] == "insult":
			ins = float(tr["strength"])
	check(ins < g_before, "omluva oslabí stopu urážky (přepsání)")
	m.tick(DAY * 60.0)
	check(m.traces.is_empty(), "po dlouhé době bez podnětů se zapomene všechno (žádné trvalé „nálepky“)")
	var big := SocialMemory.new()
	for i in 200:
		big.record("u%d" % i, "X", "pleasant_talk", 0.2 + float(i % 7) * 0.1, float(i))
	check(big.traces.size() <= SocialMemory.MAX_TRACES, "počet stop má strop", str(big.traces.size()))
	var fact := SocialMemory.new()
	fact.record("u1", "Petr", "grievance", 0.5, 0.0, "self", "intended")
	var fact2 := SocialMemory.new()
	fact2.record("u1", "Petr", "grievance", 0.5, 0.0, "self", "accidental")
	check(fact.bias("u1") < fact2.bias("u1") and fact.traces[0]["kind"] == fact2.traces[0]["kind"],
		"stejný fakt, jiný výklad (schválně × nechtěně) → jiná bilance")


func _test_direction_no_oscillation() -> void:
	section("Křivda + omluva + čas: očekávaný směr bez kmitání")
	var m := SocialMemory.new()
	m.record("u1", "Petr", "grievance", 0.6, 0.0, "self", "unclear")
	m.record("u1", "Petr", "insult", 0.7, 30.0, "self", "intended")
	var b0 := m.bias("u1")
	m.record("u1", "Petr", "apology", 0.6, 120.0)
	var b1 := m.bias("u1")
	check(b0 < -0.3 and b1 > b0, "po křivdě je bilance záporná, omluva ji zlepší", "%.2f → %.2f" % [b0, b1])
	var series: Array = [b1]
	var t := 120.0
	for i in 40:
		t += 360.0
		m.tick(360.0)
		m.cue("u1", t)
		series.append(m.bias("u1"))
	var monotone := true
	var flips := 0
	for i in range(1, series.size()):
		if float(series[i]) + 1e-6 < float(series[i - 1]) and float(series[i]) < 0.0:
			monotone = false
		if signf(float(series[i])) != signf(float(series[i - 1])) and absf(float(series[i])) > 1e-4:
			flips += 1
	check(monotone and flips <= 1, "s časem se bilance vrací k nule bez kmitání (i při setkáních)",
		"flips %d, %s" % [flips, str(series.slice(0, 6))])
	check(absf(float(series[-1])) < absf(b1), "čas hojí")


func _test_cues_and_labels() -> void:
	section("Oživení podnětem (omezené) a hystereze popisků")
	var m := SocialMemory.new()
	m.record("u1", "Petr", "insult", 0.8, 0.0, "self", "intended", "stove")
	m.tick(DAY * 3.0)
	var s0 := float(m.traces[0]["strength"])
	m.cue("u1", DAY * 3.0)
	var s1 := float(m.traces[0]["strength"])
	m.cue("u1", DAY * 3.0 + 5.0)
	var s2 := float(m.traces[0]["strength"])
	check(s1 > s0 and is_equal_approx(s1, s2), "setkání stopu oživí, ale ne opakovaně hned za sebou (žádné farmení)")
	m.cue("", DAY * 3.0 + 400.0, "stove")
	check(float(m.traces[0]["strength"]) > s2, "stejné místo je také podnět")
	var farm := SocialMemory.new()
	farm.record("u1", "Petr", "pleasant_talk", 0.15, 0.0)
	for i in 500:
		farm.cue("u1", float(i) * 400.0)
	check(float(farm.traces[0]["strength"]) <= 0.35 + 0.65 * 0.15 + 1e-6, "oživení má strop podle závažnosti")
	var v := SocialMemory.new()
	var labels: Array = []
	for value in [20.0, 26.0, 24.0, 27.0, 23.0, 30.0, 20.0]:
		labels.append(v.view_label("u1", value))
	var changes := 0
	for i in range(1, labels.size()):
		if labels[i] != labels[i - 1]:
			changes += 1
	check(changes <= 2, "popisek vztahu nekmitá kolem hranice (hystereze)", str(labels))
	check(labels[-1] == "neutrální vztah" and labels[5] == "přátelský vztah", "výrazná změna se ale projeví", str(labels))
	var desc := v.describe("u1", Callable(), 2)
	m.record("u2", "Eli", "support", 0.7, DAY * 3.0)
	var lines := m.describe("u2", Callable(), 2)
	var has_digit := false
	for ch in "".join(lines):
		if ch in "0123456789":
			has_digit = true
	check(not lines.is_empty() and not has_digit and desc.is_empty(), "popis vzpomínek ve slovech, bez čísel", str(lines))


func _test_abilities() -> void:
	section("Posuvníky schopností paměti")
	var strong := SocialMemory.new()
	strong.configure({"retention": 1.0, "precision": 1.0, "emotional_weight": 1.0}, 1.0)
	var weak := SocialMemory.new()
	weak.configure({"retention": 0.0, "precision": 0.0, "emotional_weight": 0.0}, 1.0)
	var muted := SocialMemory.new()
	muted.configure({"retention": 1.0}, 0.5)
	var off := SocialMemory.new()
	off.configure({"retention": 1.0}, 0.0)
	for m in [strong, weak]:
		m.record("u1", "Petr", "grievance", 0.6, 0.0)
		m.tick(DAY * 4.0)
	var ss := float(strong.traces[0]["strength"]) if not strong.traces.is_empty() else 0.0
	var ws := float(weak.traces[0]["strength"]) if not weak.traces.is_empty() else 0.0
	check(ss > ws * 2.0, "dobrá paměť si křivdu nese déle", "%.3f vs %.3f" % [ss, ws])
	check(float(strong.traces[0]["certainty"]) > 0.95, "přesná paměť = vysoká jistota")
	check(muted.retention == 0.75 and off.retention == 0.5, "muted tlumí odchylku, off = průměrná paměť")
	var mid := SocialMemory.new()
	mid.configure({"retention": 0.25}, 1.0)
	var mid2 := SocialMemory.new()
	mid2.configure({"retention": 0.75}, 1.0)
	mid.record("u", "x", "grievance", 0.5, 0.0)
	mid2.record("u", "x", "grievance", 0.5, 0.0)
	mid.tick(DAY * 2.0)
	mid2.tick(DAY * 2.0)
	check(float(mid.traces[0]["strength"]) < float(mid2.traces[0]["strength"]), "účinek je spojitý")


func _find(world: Node, first: String) -> Node:
	for s in world.sims:
		if s.first_name() == first:
			return s
	return null


func _test_world() -> void:
	section("Ve světě: uid, svědci, svěření, vliv, determinismus, uložení, soukromí")
	var world := U.make_world(U.household({}), clock)
	add_child(world)
	await get_tree().process_frame
	var jana = world.sims[0]
	var petr = world.sims[1]
	var eli = world.sims[2]
	check(jana.char_uid != "" and jana.memory_key(petr) == petr.char_uid and not jana.memory_key(petr).contains(petr.sim_name),
		"stopy jsou klíčované stabilním uid, ne jménem")
	# Eli stojí opodál a vidí, jak Petr Janu urazí.
	eli.global_position = jana.global_position + Vector3(2.0, 0, 0)
	petr.global_position = jana.global_position + Vector3(0.8, 0, 0)
	petr._social_outcome(jana, -10.0, "insult")
	var jt: Array = jana.psy.memory.traces_about(jana.memory_key(petr))
	var et: Array = eli.psy.memory.traces_about(eli.memory_key(petr))
	check(not jt.is_empty() and jt[0]["kind"] == "insult" and jt[0]["source"] == "self" and jt[0]["interp"] == "intended",
		"oběť: urážka zažitá, výklad „schválně“")
	check(not et.is_empty() and et[0]["source"] == "witnessed" and float(et[0]["certainty"]) < float(jt[0]["certainty"]) \
		and et[0]["whom"] == eli.memory_key(jana), "svědek ví jen, co viděl (nižší jistota, komu se to stalo)")
	check(petr.psy.memory.traces_about(petr.memory_key(jana)).is_empty(), "útočník si oběť jako křivdu nezapíše")
	var w_before: float = eli.psyche_target_weight(petr, ActionLibrary.get_action("chat"))
	check(w_before < 1.0 and w_before >= 0.85, "viděná urážka: k Petrovi o něco méně chuti (omezeně)", "%.3f" % w_before)
	var p_j: float = jana.talk_success_chance(petr)
	var fresh := U.make_world(U.household({}), clock)
	add_child(fresh)
	await get_tree().process_frame
	check(p_j < fresh.sims[0].talk_success_chance(fresh.sims[1]), "křivda sníží šanci na dobrý rozhovor (jen posun)")
	fresh.free()
	await get_tree().process_frame
	# Svěření: Jana se svěří Eli → Eli se dozví (told) o Petrovi.
	var eli_before: int = eli.psy.memory.traces_about(eli.memory_key(petr)).size()
	jana._share_memory_with(eli)
	var told := 0
	for tr in eli.psy.memory.traces_about(eli.memory_key(petr)):
		if tr["source"] == "told":
			told += 1
	check(told == 1 and eli.psy.memory.traces_about(eli.memory_key(petr)).size() == eli_before + 1,
		"svěření předá jen řečenou verzi (zdroj „slyšel(a)“)")
	# Uložení a načtení.
	var snap: Dictionary = SaveGame.capture(world)
	var before: Dictionary = jana.psy.memory.to_dict()
	jana.psy.memory.traces.clear()
	check(SaveGame.apply(world, snap["data"])["ok"], "načtení domácnosti se vzpomínkami")
	var j2 = _find(world, "Jana")
	check(j2.psy.memory.to_dict() == before, "vzpomínky přežijí uložení a načtení přesně")
	var bad: Dictionary = snap["data"].duplicate(true)
	bad["sims"][0]["state"]["psyche_ext"]["memory"]["traces"][0]["kind"] = "volny_text"
	check(not SaveGame.apply(world, bad)["ok"], "neznámý druh stopy (volný text) se odmítne")
	j2._update_net(100.0)
	check(not U.contains_key(j2._build_detail(), ["traces", "memory", "psyche_ext"]), "net_detail bez vzpomínek")
	var labels: Dictionary = j2.private_attachment_labels()
	var any_mem := false
	for n in labels:
		if String(labels[n]).contains("pamatuje si"):
			any_mem = true
	check(any_mem, "offline vlastník vidí slovní souhrn vzpomínek")
	world.free()
	await get_tree().process_frame
	section("Determinismus a dlouhý běh")
	var runs: Array = []
	for r in 2:
		var w := U.make_world(U.household({}), clock)
		add_child(w)
		await get_tree().process_frame
		U.run_minutes(clock, 2.0 * DAY)
		var mem := {}
		for s in w.sims:
			mem[s.sim_name] = s.psy.memory.to_dict()
		runs.append({"fp": U.action_fingerprint(w), "mem": mem})
		w.free()
		await get_tree().process_frame
	check(runs[0]["fp"] == runs[1]["fp"] and runs[0]["mem"] == runs[1]["mem"], "stejný seed → stejné vzpomínky i chování")
	var total := 0
	for n in runs[0]["mem"]:
		total += (runs[0]["mem"][n]["traces"] as Array).size()
	check(total > 0, "za dva dny vzniknou vzpomínky z běžného života", str(total))
