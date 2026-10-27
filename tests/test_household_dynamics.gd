extends "res://tests/test_base.gd"
## Test dynamiky domácnosti (běh 15): třenice s cooldowny a dráždivostí povahy, stížnost jako
## tón oslovení, společné chvíle, zanedbání, drift záporných vztahů, nálada a de-eskalace,
## měkký strop stresu z hádek, vzpomínky podle směru změny vztahu – a hlavně DLOUHÝ BĚH:
## 16 seedů × 14 dní startovní domácnosti (průměr i rozptyl), kritéria proti „studené válce“
## i proti idyle, determinismus (stejný seed = stejný výsledek).

const Main := preload("res://main.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const HouseholdDynamics := preload("res://scripts/sim/household_dynamics.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const RelLedger := preload("res://scripts/sim/rel_ledger.gd")

## 16 seedů: systém je chaotický (drobná změna pořadí náhody posune jednotlivé seedy), průměr
## z 10 seedů kolísal o ±4 p. b.; 16 dává stabilnější odhad a test se vejde do limitu ~2 min
## nástroje (20 seedů = 96 s jen dlouhý běh).
const SEEDS := 16
const DAYS := 14
## Kritéria dlouhého běhu (zadání uživatelky 21. 10. 2026).
## The new model does not treat awkward/misunderstood conversation as a fight.
const ARGUE_MIN := 0.10
const ARGUE_MAX := 0.40
const SPIRAL_LEVEL := -30.0
const STRESS_HI := 85.0
## Max. podíl času se stresem > 85: průměr přes postavy a seedy / nejhorší jednotlivec.
const STRESS_HI_MEAN := 0.03
const STRESS_HI_WORST := 0.10

var clock: Node
var gs: Node
var world: Node3D
var runs: Array = []


func _ready() -> void:
	watchdog_seconds = 900.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	world = _make_world()
	_test_units()
	world.queue_free()
	await get_tree().process_frame
	await _test_long_runs()
	finish("test_household_dynamics")


func _make_world() -> Node3D:
	clock.total_minutes = 8.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var w := Node3D.new()
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(w)
	return w


func _sim(w, full_name: String):
	return w.find_sim(SimAgent.node_name_for(full_name))


func _reset(s) -> void:
	s.player_queue.clear()
	s.command({"id": "cancel"}, null)
	s.state = SimAgent.State.IDLE
	s.current_action = {}
	s.mental.stress = 10.0
	s.mental.arousal = 5.0
	s.think_cooldown = 1.0e9
	s.ledger = RelLedger.new()
	s.pending_complaints.clear()
	s.mood.moodlets.clear()
	for k in s.needs.values:
		s.needs.values[k] = 80.0


func _act(s, id: String) -> void:
	s.state = SimAgent.State.ACTING
	s.current_action = ActionLibrary.get_action(id).duplicate(true)


# ---------------------------------------------------------------- jednotkové části

func _test_units() -> void:
	var jana = _sim(world, "Jana Nováková")
	var petr = _sim(world, "Petr Dvořák")
	var eli = _sim(world, "Eliška Malá")
	for s in [jana, petr, eli]:
		_reset(s)
	var t0: float = clock.total_minutes

	section("Třenice: kdy vzniknou (bez náhody)")
	jana.global_position = Vector3(0, 0, 0)
	petr.global_position = Vector3(3, 0, 0)
	eli.global_position = Vector3(20, 0, 0)
	_act(jana, "sleep")
	_act(petr, "watch_tv")
	check(HouseholdDynamics.friction_topic(jana, petr, 23, "") == "noise", "spím a vedle v noci řve televize → hluk")
	check(HouseholdDynamics.friction_topic(jana, petr, 14, "") == "", "odpoledne to za rušení spánku nepočítá (šlofík přes den je risk)")
	petr.global_position = Vector3(15, 0, 0)
	check(HouseholdDynamics.friction_topic(jana, petr, 23, "") == "", "hluk z druhého konce domu nevadí")
	_reset(jana)
	_act(petr, "shower")
	jana.needs.values["hygiene"] = 30.0
	check(HouseholdDynamics.friction_topic(jana, petr, 10, "") == "bathroom", "potřebuju se umýt a koupelna je obsazená")
	jana.needs.values["hygiene"] = 80.0
	check(HouseholdDynamics.friction_topic(jana, petr, 10, "") == "", "čistému obsazená koupelna nevadí")
	_reset(petr)
	petr.global_position = Vector3(3, 0, 0)
	check(HouseholdDynamics.friction_topic(jana, petr, 13, "cook") == "dishes", "druhý dovařil a nechal to být → nádobí")
	check(HouseholdDynamics.friction_topic(jana, petr, 13, "read") == "", "bez vaření žádné nádobí")
	check(Traits.mult_param(["pedant"], "irritability") > 1.0 and Traits.mult_param(["lenoch"], "irritability") < 1.0
		and Traits.mult_param(["spolecensky"], "irritability") == 1.0, "dráždivost je parametr povahy (pedant víc, lenoch míň)")

	section("Třenice: následky a cooldown")
	var dyn := HouseholdDynamics.new()
	var st0: float = jana.mental.stress
	check(dyn.can_friction(jana, petr, "dishes", t0), "poprvé může")
	dyn.apply_friction(jana, petr, "dishes", t0)
	check(jana.mental.stress > st0, "třenice přidá stres", "%.1f → %.1f" % [st0, jana.mental.stress])
	check(jana.ledger.grudge(petr.sim_name) >= HouseholdDynamics.FRICTION_GRUDGE - 0.01, "drobná křivda")
	check(jana.mood.has_moodlet("trenice_dishes_" + String(petr.name)), "moodlet „Štve mě …“")
	check(String(jana.pending_complaints.get(petr.sim_name, {}).get("topic", "")) == "dishes", "stížnost čeká na příští oslovení")
	check(not dyn.can_friction(jana, petr, "dishes", t0 + 60.0), "stejné téma u stejné dvojice hned znovu ne (cooldown)")
	check(dyn.can_friction(jana, petr, "noise", t0 + 60.0), "jiné téma cooldown neblokuje")
	check(dyn.can_friction(jana, petr, "dishes", t0 + HouseholdDynamics.FRICTION_COOLDOWN["dishes"]), "po cooldownu zase může")
	check(int(dyn.stats["friction"].get("dishes", 0)) == 1, "statistika třenic")

	section("Stížnost jako tón oslovení")
	_reset(jana)
	_reset(eli)
	jana.mood.value = 0.0
	eli.mood.value = 0.0
	jana.mood.emotion = "spokojeny"
	eli.mood.emotion = "spokojeny"
	jana.relationships[eli.sim_name] = 0.0
	var p_plain: float = jana.talk_success_chance(eli, "")
	var p_compl: float = jana.talk_success_chance(eli, "dishes")
	check(absf((p_plain - p_compl) - SimAgent.COMPLAINT_PENALTY) < 1e-4, "stížnost snižuje šanci na pohodu o COMPLAINT_PENALTY",
		"%.3f vs %.3f" % [p_plain, p_compl])
	jana.pending_complaints[eli.sim_name] = {"topic": "noise", "t": clock.total_minutes}
	check(jana.take_complaint(eli) == "noise" and jana.take_complaint(eli) == "", "stížnost se použije jednou")
	jana.pending_complaints[eli.sim_name] = {"topic": "noise", "t": clock.total_minutes - SimAgent.COMPLAINT_TTL - 1.0}
	check(jana.take_complaint(eli) == "" and not jana.pending_complaints.has(eli.sim_name), "stará stížnost vyprchá (pustí to z hlavy)")
	jana.pending_complaints[eli.sim_name] = {"topic": 42}
	check(jana.take_complaint(eli) == "", "poškozená stížnost (bez času) se zahodí")
	var lines_ok := true
	for k in ["complaint_noise", "complaint_bathroom", "complaint_dishes", "complaint_ok", "deescalate"]:
		if ActionLibrary.LINES.get(k, []).is_empty():
			lines_ok = false
	check(lines_ok, "repliky pro stížnosti a de-eskalaci existují")

	section("Nálada obou a de-eskalace")
	jana.relationships[eli.sim_name] = -60.0  # mimo ořez 0,08..0,92, ať je vidět celý rozsah
	jana.mood.value = 100.0
	eli.mood.value = 100.0
	var p_hi: float = jana.talk_success_chance(eli)
	jana.mood.value = -100.0
	eli.mood.value = -100.0
	var p_lo: float = jana.talk_success_chance(eli)
	check(absf((p_hi - p_lo) - 2.0 * SimAgent.MOOD_WEIGHT) < 1e-4, "nálada posune šanci nejvýš o ±20 p. b.", "%.3f vs %.3f" % [p_hi, p_lo])
	jana.mood.value = 0.0
	jana.mood.emotion = "nastvany"
	var p_angry: float = jana.talk_success_chance(eli)
	jana.mood.emotion = "unaveny"
	var p_tired: float = jana.talk_success_chance(eli)
	jana.mood.emotion = "spokojeny"
	var p_calm: float = jana.talk_success_chance(eli)
	check(p_angry < p_tired and p_tired < p_calm, "vztek ubírá víc než únava, klid nic", "%.2f %.2f %.2f" % [p_angry, p_tired, p_calm])
	eli.mood.value = 10.0
	check(SimAgent.deescalation_chance(eli) == 0.0, "posluchač ve špatné/neutrální náladě hádku neutne")
	eli.mood.value = 35.0
	check(absf(SimAgent.deescalation_chance(eli) - SimAgent.DEESCALATE_MAX * 0.5) < 1e-4, "šance roste s náladou")
	eli.mood.value = 90.0
	check(absf(SimAgent.deescalation_chance(eli) - SimAgent.DEESCALATE_MAX) < 1e-4, "nejvýš DEESCALATE_MAX – i dobrá nálada nesnese všechno")

	section("Měkký strop stresu z hádek")
	petr.mental.stress = 20.0
	var a20: float = petr.argue_stress_amount()
	petr.mental.stress = 60.0
	var a60: float = petr.argue_stress_amount()
	eli.mental.stress = 60.0
	var e60: float = eli.argue_stress_amount()
	petr.mental.stress = 95.0
	var a95: float = petr.argue_stress_amount()
	check(a20 > SimAgent.ARGUE_STRESS, "vznětlivý nabírá stres z hádky rychle", "%.1f" % a20)
	check(a60 < a20 * 0.5 and a60 < e60, "…ale vybuchne a vyfučí: u vysokého stresu přibývá méně než u ostatních", "%.1f vs %.1f" % [a60, e60])
	check(a95 > 0.0, "strop je měkký (pořád něco přibude)")

	section("Vzpomínky podle směru změny vztahu")
	jana.memories.clear()
	jana.note_relationship_change(eli, 90.0, 70.0)
	check(_last_mem(jana).begins_with("Vztah se ochladil") and _last_mem(jana).contains("už není moje nejlepší přítelkyně"),
		"ochlazení přátelství", _last_mem(jana))
	jana.note_relationship_change(eli, -20.0, -30.0)
	check(_last_mem(jana).begins_with("Vztah se zhoršil") and _last_mem(jana).contains("je teď moje nepřítelkyně"), "zhoršení do nepřátelství", _last_mem(jana))
	jana.note_relationship_change(eli, -30.0, -10.0)
	check(_last_mem(jana).begins_with("Vztah se zlepšil") and _last_mem(jana).contains("už není moje nepřítelkyně"), "zlepšení z nepřátelství", _last_mem(jana))
	jana.note_relationship_change(eli, 10.0, 30.0)
	check(_last_mem(jana).ends_with("je teď moje kamarádka"), "nové přátelství", _last_mem(jana))
	var n_mem: int = jana.memories.size()
	jana.note_relationship_change(eli, 50.0, 52.0)
	check(jana.memories.size() == n_mem, "beze změny úrovně žádná vzpomínka")
	jana.note_relationship_change(petr, 90.0, 70.0)
	check(_last_mem(jana).contains("už není můj nejlepší přítel"), "rod druhé postavy (můj / moje)", _last_mem(jana))
	var bad := false
	for e in jana.memories:
		var t := String(e["text"])
		if t.begins_with("Vztah se zhoršil") and not t.contains("nepřítel"):
			bad = true
	check(not bad, "„zhoršil“ nikdy neoznamuje přátelskou úroveň (bug z experimentu v4)")

	section("Rozhovor: signál pro statistiku, stížnost zazní")
	for s in [jana, petr, eli]:
		_reset(s)
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(0.8, 0, 0)
	var got := []
	var cb := func(_a, _b, info): got.append(info)
	jana.conversation.connect(cb)
	jana.pending_complaints[eli.sim_name] = {"topic": "dishes", "t": clock.total_minutes}
	jana.current_action = ActionLibrary.get_action("chat").duplicate(true)
	jana.target = eli
	jana._start_social(eli)
	jana.conversation.disconnect(cb)
	check(got.size() == 1 and String(got[0].get("complaint", "")) == "dishes", "rozhovor ohlásí výsledek i tón stížnosti")
	check(got.size() == 1 and got[0].has("success") and got[0].has("avg_mood") and got[0].has("p"), "info obsahuje výsledek, náladu a šanci")
	var cl: Array = ActionLibrary.LINES["complaint_dishes"]
	var said := false
	for l in cl:
		if jana.speech == jana.gendered(String(l)):
			said = true
	check(said, "stížnost zazní v bublině", jana.speech)
	check(not jana.pending_complaints.has(eli.sim_name), "stížnost je spotřebovaná")
	for s in [jana, petr, eli]:
		_reset(s)

	section("Společné chvíle")
	var dyn2 := HouseholdDynamics.new()
	jana.global_position = Vector3(0, 0, 0)
	eli.global_position = Vector3(1.5, 0, 0)
	petr.global_position = Vector3(30, 0, 0)
	_act(jana, "watch_tv")
	_act(eli, "relax")
	jana.relationships[eli.sim_name] = 10.0
	eli.relationships[jana.sim_name] = 10.0
	eli.ledger.on_hurt_by(jana.sim_name, 20.0, t0 - 500.0)
	var now := t0 + 1000.0
	check(HouseholdDynamics.shared_kind(jana, eli) == "film", "gauč + televize vedle sebe = film spolu")
	dyn2._shared_moments([jana, eli, petr], now)
	var dj: float = float(jana.relationships[eli.sim_name]) - 10.0
	var de: float = float(eli.relationships[jana.sim_name]) - 10.0
	check(absf(dj - HouseholdDynamics.SHARED_REL) < 1e-3, "společná chvíle přidá vztah", "%.2f" % dj)
	check(de > 0.0 and de < dj, "živá křivda zisk brzdí (warmth_mult)", "%.2f vs %.2f" % [de, dj])
	check(jana.mood.has_moodlet("spolu_film_" + String(eli.name)) and float(jana.last_talk.get(eli.sim_name, -1.0)) == now,
		"moodlet „Chvíle spolu“ a počítá se jako kontakt")
	dyn2._shared_moments([jana, eli, petr], now + 30.0)
	check(is_equal_approx(float(jana.relationships[eli.sim_name]), 10.0 + dj), "cooldown: hned znovu nic (nejde farmit)")
	dyn2._shared_moments([jana, eli, petr], now + HouseholdDynamics.SHARED_COOLDOWN)
	check(float(jana.relationships[eli.sim_name]) > 10.0 + dj, "po cooldownu zase")
	eli.global_position = Vector3(8, 0, 0)
	check(HouseholdDynamics.shared_kind(jana, eli) == "", "každý v jiném koutě domu není společná chvíle")
	eli.global_position = Vector3(1.5, 0, 0)
	eli.ledger.on_hurt_by(jana.sim_name, 70.0, t0)
	var r_before: float = float(jana.relationships[eli.sim_name])
	dyn2._shared_moments([jana, eli, petr], now + 3.0 * HouseholdDynamics.SHARED_COOLDOWN)
	check(float(jana.relationships[eli.sim_name]) == r_before, "se silnou křivdou společné sezení nesbližuje (nejde farmit)")

	section("Nádobí jen po skutečném vaření")
	for s in [jana, petr, eli]:
		_reset(s)
	jana.global_position = Vector3(0, 0, 0)
	petr.global_position = Vector3(3, 0, 0)
	eli.global_position = Vector3(30, 0, 0)
	var short_hits := 0
	var long_hits := 0
	for trial in 60:
		for cook_ticks in [1, 4]:
			var d := HouseholdDynamics.new()
			var tt := now + 5000.0 + trial * 2000.0
			_act(petr, "cook")
			for k in cook_ticks:
				d.tick([jana, petr], 13, tt + k * HouseholdDynamics.TICK)
			petr.state = SimAgent.State.IDLE
			petr.current_action = {}
			d.tick([jana, petr], 13, tt + cook_ticks * HouseholdDynamics.TICK)
			var hits := int(d.stats["friction"].get("dishes", 0))
			if cook_ticks == 1:
				short_hits += hits
			else:
				long_hits += hits
	check(short_hits == 0, "vaření zrušené po pár minutách nádobí nezanechá (griefing příkazy)", "%d" % short_hits)
	check(long_hits > 0, "po opravdovém vaření nádobí občas naštve", "%d z 60" % long_hits)

	section("Zanedbání a drift")
	for s in [jana, petr, eli]:
		_reset(s)
	var dyn3 := HouseholdDynamics.new()
	jana.relationships[petr.sim_name] = 80.0
	jana.relationships[eli.sim_name] = 80.0
	jana.last_talk[petr.sim_name] = now - 5.0 * 1440.0
	jana.last_talk[eli.sim_name] = now - 60.0
	for i in 144 * 20:
		dyn3._neglect([jana], now + i * HouseholdDynamics.TICK)
	var rp: float = float(jana.relationships[petr.sim_name])
	check(rp < 70.0 and rp > HouseholdDynamics.NEGLECT_FLOOR, "bez kontaktu blízký vztah pomalu vyprchává, ale ne pod úroveň kamaráda", "%.1f" % rp)
	jana.relationships[eli.sim_name] = 80.0
	jana.last_talk[eli.sim_name] = now
	dyn3._neglect([jana], now + 60.0)
	check(float(jana.relationships[eli.sim_name]) == 80.0, "s nedávným kontaktem se nic neděje")
	jana.relationships[eli.sim_name] = -10.0
	jana._heal_relationships(1440.0 * 5.0)
	check(float(jana.relationships[eli.sim_name]) == 0.0, "záporný vztah bez křivdy se vrátí k nule (a nepřeskočí ji)")
	jana.relationships[eli.sim_name] = -40.0
	for i in 1440:
		jana._heal_relationships(1.0)
	var r_step: float = float(jana.relationships[eli.sim_name])
	jana.relationships[eli.sim_name] = -40.0
	jana._heal_relationships(1440.0)
	check(absf(r_step - float(jana.relationships[eli.sim_name])) < 0.3, "hojení skoro nezávisí na délce kroku",
		"%.2f vs %.2f" % [r_step, float(jana.relationships[eli.sim_name])])
	jana.relationships[petr.sim_name] = -40.0
	jana.ledger.on_hurt_by(petr.sim_name, 50.0, now)
	jana._heal_relationships(1440.0)
	check(float(jana.relationships[petr.sim_name]) == -40.0, "s živou křivdou se nic nehojí (smysl omluvy zůstává)")

	section("Životní události a loutky")
	var dyn4 := HouseholdDynamics.new()
	for i in 40:
		dyn4.life_event(jana, now + i)
	var ev: Dictionary = dyn4.stats["events"]
	check(int(ev["good"]) + int(ev["bad"]) == 40 and int(ev["good"]) > 5 and int(ev["bad"]) > 5, "dobré i špatné události", str(ev))
	var puppet := Node3D.new()
	add_child(puppet)
	dyn4.tick([puppet, jana], 12, now)
	check(true, "loutka (klient) v seznamu nevadí – dynamika ji ignoruje")
	puppet.queue_free()


func _last_mem(s) -> String:
	return String(s.memories[-1]["text"]) if not s.memories.is_empty() else ""


# ---------------------------------------------------------------- dlouhý běh

func _one_run(seed: int, days: int) -> Dictionary:
	var w := _make_world()
	var i := 0
	for s in w.sims:
		s.rng.seed = seed * 7919 + i * 104729 + 13
		s.think_cooldown = s.rng.randf_range(0.0, 3.0)
		i += 1
	var hi := {}
	var crit := 0
	for s in w.sims:
		hi[s.sim_name] = 0
	# Krok 2 min = GameClock.MAX_STEP (stejně jako hra při vyšší rychlosti); polovina času testu.
	for m in days * 720:
		clock.advance(2.0)
		for s in w.sims:
			if s.mental.stress > STRESS_HI:
				hi[s.sim_name] += 2
			for k in s.needs.values:
				if s.needs.values[k] < 10.0:
					crit += 2
	var rels: Array = []
	var pairs := {}
	var sig := PackedStringArray()
	for a in w.sims:
		for b in w.sims:
			if a == b:
				continue
			var r := float(a.relationships.get(b.sim_name, 0.0))
			rels.append(r)
			var key := "+".join(PackedStringArray([a.sim_name, b.sim_name]) if a.sim_name < b.sim_name else PackedStringArray([b.sim_name, a.sim_name]))
			pairs[key] = float(pairs.get(key, 0.0)) + r * 0.5
			sig.append("%.4f" % r)
		sig.append("%.4f" % a.mental.stress)
	var ds: Dictionary = w.dynamics.stats.duplicate(true)
	sig.append(JSON.stringify(ds))
	var res := {"seed": seed, "argue": w.dynamics.argue_rate(), "talks": int(ds["talks"]), "stats": ds, "rels": rels,
		"pairs": pairs.values(), "hi": hi, "crit": crit, "sig": ",".join(sig), "sims": w.sims.size()}
	w.queue_free()
	await get_tree().process_frame
	return res


func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, a.size())


func _sd(a: Array) -> float:
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += pow(float(v) - m, 2.0)
	return sqrt(s / maxf(1.0, a.size() - 1))


func _test_long_runs() -> void:
	section("Dlouhý běh: %d seedů × %d dní (startovní domácnost)" % [SEEDS, DAYS])
	var t_start := Time.get_ticks_msec()
	for k in SEEDS:
		var r: Dictionary = await _one_run(k, DAYS)
		runs.append(r)
		var hi_txt := PackedStringArray()
		for n in r["hi"]:
			hi_txt.append("%s %d" % [String(n).split(" ")[0], int(r["hi"][n])])
		var pr := PackedStringArray()
		for v in r["pairs"]:
			pr.append("%+.0f" % float(v))
		print("  seed %d: rozhovorů %d, hádky %.0f %%, de-esk. %d, dvojice [%s], stres>85 min {%s}, krit. %d, třenice %s, spolu %s, události %s" % [
			k, r["talks"], 100.0 * float(r["argue"]), int(r["stats"]["deescalated"]), ", ".join(pr), ", ".join(hi_txt), int(r["crit"]),
			JSON.stringify(r["stats"]["friction"]), JSON.stringify(r["stats"]["shared"]), JSON.stringify(r["stats"]["events"])])
	print("  (čas %.1f s)" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	var rates: Array = runs.map(func(r): return float(r["argue"]))
	var m := _mean(rates)
	var sd := _sd(rates)
	print("  hádky: průměr %.1f %%, sm. odch. %.1f p. b., min %.0f %%, max %.0f %%" % [m * 100.0, sd * 100.0,
		rates.min() * 100.0, rates.max() * 100.0])
	check(m >= ARGUE_MIN and m <= ARGUE_MAX,
		"skutečné hádky 10–40 % rozhovorů; ostatní neúspěchy nejsou hádka", "%.1f %%" % (m * 100.0))
	var histogram := {"chat": 0, "argue": 0, "awkward": 0, "misunderstanding": 0}
	var all_talks := 0
	for r in runs:
		all_talks += int(r["talks"])
		for kind in histogram:
			histogram[kind] += int(r["stats"].get("outcomes", {}).get(kind, 0))
	var outcomes_sum := 0
	for kind in histogram:
		outcomes_sum += int(histogram[kind])
	check(histogram["awkward"] > 0 and histogram["misunderstanding"] > 0 and histogram["argue"] > 0,
		"reálné nedorozumění i trapné ticho vzniká nezávisle na skutečných hádkách")
	check(outcomes_sum == all_talks,
		"každý rozhovor má přesně jeden odlišitelný výsledek")
	check(rates.min() >= 0.08 and rates.max() <= 0.6, "žádný seed neujede (8–60 %)", "%.0f–%.0f %%" % [rates.min() * 100.0, rates.max() * 100.0])
	check(runs.all(func(r): return int(r["talks"]) >= DAYS * 2), "postavy spolu mluví (aspoň 2 rozhovory denně)")

	section("Vztahy: žádná spirála, žádná idyla, různé dvojice")
	var spiral := 0
	var all_rel: Array = []
	var pair_sd: Array = []
	var idyll := 0
	for r in runs:
		all_rel.append_array(r["rels"])
		if (r["rels"] as Array).all(func(v): return float(v) < SPIRAL_LEVEL):
			spiral += 1
		if (r["rels"] as Array).all(func(v): return float(v) > 60.0):
			idyll += 1
		pair_sd.append(_sd(r["pairs"]))
	print("  vztahy: průměr %+.1f, sm. odch. %.1f, min %+.0f, max %+.0f; rozdíl dvojic (sm. odch.) průměr %.1f" % [
		_mean(all_rel), _sd(all_rel), all_rel.min(), all_rel.max(), _mean(pair_sd)])
	check(spiral == 0, "v žádném seedu nekončí všechny vztahy pod −30 (studená válka)", "%d seedů" % spiral)
	check(_mean(all_rel) > SPIRAL_LEVEL, "průměrný vztah je nad −30", "%+.1f" % _mean(all_rel))
	check(idyll == 0, "ani idyla: v žádném seedu nejsou všechny vztahy nad +60", "%d" % idyll)
	check(_mean(pair_sd) >= 8.0, "dvojice se liší (povahy dělají rozdíl)", "%.1f" % _mean(pair_sd))
	check(all_rel.max() - all_rel.min() >= 40.0, "rozptyl vztahů napříč seedy je široký (příběhy se liší)")

	section("Nálada: gradient hádek")
	var b := {"good": [0, 0], "mid": [0, 0], "bad": [0, 0]}
	for r in runs:
		for k in b:
			b[k][0] += int(r["stats"]["by_mood"][k][0])
			b[k][1] += int(r["stats"]["by_mood"][k][1])
	var rate := func(k): return float(b[k][1]) / maxf(1.0, float(b[k][0]))
	print("  dobrá nálada %d rozhovorů / hádky %.0f %% | střední %d / %.0f %% | špatná %d / %.0f %%" % [
		b["good"][0], rate.call("good") * 100.0, b["mid"][0], rate.call("mid") * 100.0, b["bad"][0], rate.call("bad") * 100.0])
	check(b["good"][0] >= 20 and b["mid"][0] >= 20 and b["bad"][0] >= 10, "dost rozhovorů ve všech pásmech nálady")
	check(rate.call("good") < rate.call("mid") and rate.call("mid") < rate.call("bad"), "čím horší nálada obou, tím častější hádka")
	var deesc := 0
	var comp := 0
	var comp_arg := 0
	for r in runs:
		deesc += int(r["stats"]["deescalated"])
		comp += int(r["stats"]["complaint_talks"])
		comp_arg += int(r["stats"]["complaint_argues"])
	print("  de-eskalací %d, rozhovorů se stížností %d (hádky %.0f %%)" % [deesc, comp, 100.0 * comp_arg / maxf(1.0, comp)])
	check(deesc > 0, "de-eskalace se ve hře opravdu děje")
	check(comp > 0 and comp_arg < comp, "stížnosti zazní a ne každá skončí hádkou")

	section("Stres, potřeby, události")
	var hi_all: Array = []
	for r in runs:
		for n in r["hi"]:
			hi_all.append(float(r["hi"][n]) / (DAYS * 1440.0))
	print("  stres > 85: průměr %.2f %% času, nejhorší %.2f %%" % [_mean(hi_all) * 100.0, hi_all.max() * 100.0])
	check(_mean(hi_all) <= STRESS_HI_MEAN, "extrémní stres je vzácný (průměr ≤ 3 % času)", "%.2f %%" % (_mean(hi_all) * 100.0))
	check(hi_all.max() <= STRESS_HI_WORST, "nikdo není v extrémním stresu přes 10 % času", "%.2f %%" % (hi_all.max() * 100.0))
	check(runs.all(func(r): return int(r["crit"]) == 0), "žádné kritické potřeby (< 10) v žádném seedu",
		str(runs.map(func(r): return int(r["crit"]))))
	var ev_rates: Array = runs.map(func(r): return float(int(r["stats"]["events"]["good"]) + int(r["stats"]["events"]["bad"])) / (DAYS * int(r["sims"])))
	print("  události na postavu a den: průměr %.2f" % _mean(ev_rates))
	check(_mean(ev_rates) > 0.6 and _mean(ev_rates) < 2.0, "náhodné události ~1× denně na postavu (mimo spánek)")
	check(runs.all(func(r): return not (r["stats"]["friction"] as Dictionary).is_empty()), "třenice se dějí v každém seedu")
	check(runs.filter(func(r): return not (r["stats"]["shared"] as Dictionary).is_empty()).size() >= SEEDS - 1, "společné chvíle skoro v každém seedu")

	section("Determinismus")
	var again: Dictionary = await _one_run(3, DAYS)
	check(again["sig"] == runs[3]["sig"], "stejný seed → stejné vztahy, stres i statistiky")
	var other: Dictionary = await _one_run(4, 2)
	var first: Dictionary = await _one_run(3, 2)
	check(other["sig"] != first["sig"], "jiný seed → jiný průběh")
