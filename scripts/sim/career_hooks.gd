extends RefCounted
## CareerHooks – adaptér mezi Career (čistá data v HouseholdDynamics) a světem (SimAgent, parcela, síť).
## Jen autorita (offline / server): klient nic z toho nevolá, vidí jen „V práci“ a repliky nahlas.
## Všechny dopady na postavy (moodlety, stres, vzpomínky, vztahy, rivalita, výplata) se aplikují tady,
## aby Career zůstala testovatelná bez scény.

const Career := preload("res://scripts/sim/career.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Rivalry := preload("res://scripts/sim/rivalry.gd")

const TICK := 10.0
const COWORKER_REL := 1.0
const VICTIM_LEARN_REL := 10.0
const VICTIM_LEARN_HEAT := 0.4


static func career_of(world):
	if world == null or not is_instance_valid(world):
		return null
	var d = world.get("dynamics")
	return d.get("career") if d != null else null


static func _now(world) -> float:
	return float(world.clock.total_minutes)


static func _sim_by_name(world, n: String):
	for s in world.get_sims():
		if is_instance_valid(s) and s.has_method("command") and String(s.sim_name) == n:
			return s
	return null


## Registrace postav (podle příběhu: minulá práce → obor), kontrola absencí, konec soubojů o povýšení,
## odpočinek ve dny bez směny. Volá main po kroku domácnosti; sám se omezí na jeden průchod za TICK.
static func tick(world) -> void:
	var c = career_of(world)
	if c == null:
		return
	var now := _now(world)
	var last := float(c.get_meta("tick_t", -1.0e12))
	if now - last < TICK and now >= last:
		return
	c.set_meta("tick_t", now)
	var day: int = Career.day_of(now)
	var new_day: bool = int(c.get_meta("tick_day", -1000000)) != day
	c.set_meta("tick_day", day)
	for s in world.get_sims():
		if not is_instance_valid(s) or not s.has_method("command") or not s.is_inside_tree():
			continue
		var n := String(s.sim_name)
		if not c.jobs.has(n):
			c.ensure(n, _past_work(world, s), int(s.romance_profile().get("age", 18)), now)
		if new_day:
			c.rest_day(n, day)
		var ab: Dictionary = c.check_absence(n, now)
		if not ab.is_empty():
			_apply_absence(world, s, ab, now)
	for ev in c.day_tick(now):
		_apply_race(world, ev, now)


static func _past_work(world, s) -> Array:
	var recs = world.get("_character_records")
	if typeof(recs) != TYPE_DICTIONARY or not recs.has(String(s.name)):
		return []
	var cd = recs[String(s.name)]
	var st = cd.get("story") if cd != null else null
	if typeof(st) != TYPE_DICTIONARY:
		return []
	var pw = st.get("past_work", [])
	return pw if typeof(pw) == TYPE_ARRAY else []


# ------------------------------------------------------------------ rozhodování AI a blokace

static func ai_choice(world, s) -> String:
	var c = career_of(world)
	if c == null or s.get("away") == true:
		return ""
	var n := String(s.sim_name)
	if not c.jobs.has(n):
		return ""
	var now := _now(world)
	var inp := {}
	if c.ai_pending(n, now):
		var mh: bool = s.content_allowed("mental_health")
		inp = {"dep": float(s.mental.dep.burden) if mh else 0.0,
			"barrier": float(s.mental.dep.barrier(0.6)) if mh else 0.0,
			"stress": float(s.mental.stress), "energy": float(s.needs.values["energy"]),
			"honesty": float(s.infidelity_profile("").get("honesty", 0.5)),
			"lazy": Traits.weight(s.trait_profile, "lenoch") > 0.5,
			"panic_recent": bool(s.mental.panic_active) if mh else false, "roll": s.rng.randf()}
	return c.ai_choice(n, inp, now)


## Budík: spící postava, které za chvíli (okno příchodu) začíná směna a dnes do práce jít má, vstane.
## Kdo se dnes rozhodl nejít / zavolat, že nepřijde, spí dál. Bez náhody (budík zvoní vždy).
static func alarm(world, s) -> bool:
	var c = career_of(world)
	if c == null:
		return false
	var n := String(s.sim_name)
	var now := _now(world)
	if not c.has_job(n) or c.arrival(n, now) == "":
		return false
	var r: Dictionary = c.record(n)
	return not (int(r["ai_day"]) == Career.day_of(now) and String(r["ai_pick"]) in ["", "call_in_sick"])


static func command_block(world, s, action_id: String) -> String:
	var c = career_of(world)
	if c == null:
		return "unknown"
	if s.get("away") == true:
		return "already_worked"
	return c.command_block(String(s.sim_name), action_id, _now(world))


## Začátek směny (SimAgent._begin_acting u akce „away“). Zapíše den směny a pozdní příchod do akce.
static func begin(world, s, action_id: String) -> Dictionary:
	var c = career_of(world)
	if c == null or not Career.SHIFT_ACTIONS.has(action_id):
		return {"ok": false}
	var r: Dictionary = c.begin_shift(String(s.sim_name), String(Career.SHIFT_ACTIONS[action_id]), _now(world))
	if not bool(r.get("ok", false)):
		if s.by_player:
			s.say(Career.block_text(String(r.get("reason", ""))))
		return r
	s.current_action = s.current_action.duplicate(true)
	s.current_action["career_late"] = bool(r.get("late", false))
	return r


## Konec pracovní akce (SimAgent._finish). act = slovník akce (i s career_late), frac = odpracovaný podíl.
static func finished(world, s, act: Dictionary, frac: float, interrupted: bool, reason: String) -> void:
	var c = career_of(world)
	if c == null:
		return
	var id := String(act.get("id", ""))
	var n := String(s.sim_name)
	var now := _now(world)
	if Career.SHIFT_ACTIONS.has(id):
		var mh: bool = s.content_allowed("mental_health")
		var inp := {"mode": String(Career.SHIFT_ACTIONS[id]), "fraction": frac, "late": bool(act.get("career_late", false)),
			"reason": reason if interrupted else "", "dep": float(s.mental.dep.burden) if mh else 0.0,
			"stress": float(s.mental.stress), "energy": float(s.needs.values["energy"]),
			"honesty": float(s.infidelity_profile("").get("honesty", 0.5)), "now": now}
		var ev: Dictionary = c.resolve_shift(n, inp, Career.make_rolls(s.rng))
		if not ev.is_empty():
			_apply_shift(world, s, ev, now)
		return
	if interrupted:
		return
	match id:
		"call_in_sick":
			var mental: bool = s.content_allowed("mental_health") and (float(s.mental.dep.burden) > 0.4 \
				or float(s.mental.stress) > 70.0 or bool(s.mental.panic_active))
			var r: Dictionary = c.call_in_sick(n, mental, now)
			if bool(r.get("ok", false)):
				_apply_sick(s, r)
		"job_search":
			var dep: float = float(s.mental.dep.burden) if s.content_allowed("mental_health") else 0.0
			var pref := Career.track_from_story(_past_work(world, s))
			var r2: Dictionary = c.job_search(n, s.rng.randf(), dep, pref, now)
			if bool(r2.get("ok", false)):
				_apply_search(s, r2)
		"quit_job":
			var r3: Dictionary = c.quit(n)
			if bool(r3.get("ok", false)):
				if bool(r3.get("relief", false)):
					s.add_joy_moodlet("vypoved_ulevou", "Konečně pryč z té práce", "spokojeny", 6.0, 1440.0)
				else:
					s.mood.add_moodlet("vypoved_obava", "Bez práce. Co teď?", "nesvuj", -4.0, 1440.0)
				s.say(ActionLibrary.random_line("quit_job", s.rng))
				s.remember(s.gendered("Dal(a) jsem výpověď."))
				s._detail_dirty = true


# ------------------------------------------------------------------ dopady

static func _stress(s, amount: float) -> void:
	if amount > 0.0:
		s.mental.on_stressor("life", amount * Traits.mult_param(s.trait_profile, "stress_gain"), s.mental_cfg())


static func _bad(s, id: String, label: String, emo: String, strength: float, minutes: float) -> void:
	s.mood.add_moodlet(id, s.gendered(label), emo, strength, minutes)


static func _apply_shift(world, s, ev: Dictionary, now: float) -> void:
	var n := String(s.sim_name)
	# Výplata do rozpočtu domácnosti (veřejný snímek parcely jde klientům).
	var wage := int(ev.get("wage", 0))
	var lot = world.get("lot")
	if wage > 0 and lot != null and lot.has_method("adjust_funds"):
		if lot.adjust_funds(wage, now, "wage", n.substr(0, 40)) != 0:
			if world.has_signal("lot_changed"):
				world.lot_changed.emit()
			var net = world.get("net")
			if net != null and is_instance_valid(net) and net.has_method("broadcast_lot"):
				net.broadcast_lot()
	_stress(s, float(ev.get("stress", 0.0)))
	var pd := float(ev.get("perf_delta", 0.0))
	if pd >= 3.0:
		s.add_joy_moodlet("prace_den", "Dobrý den v práci", "spokojeny", 5.0, 360.0)
	elif pd <= -2.0:
		_bad(s, "prace_den", "Blbý den v práci", "nesvuj", -5.0, 360.0)
	var npc_first := String(ev.get("npc", "")).split(" ")[0]
	match String(ev.get("event", "")):
		"praise":
			s.add_joy_moodlet("prace_pochvala", "Šéf mě pochválil", "stastny", 8.0, 480.0)
			s.emotions.impulse("life_good")
		"credit_stolen":
			_bad(s, "prace_zasluhy", "Ukradli mi v práci zásluhy (%s)" % npc_first, "nastvany", -8.0, 480.0)
			s.emotions.impulse("life_bad")
		"blamed":
			_bad(s, "prace_vina", "V práci to svalili na mě (%s)" % npc_first, "nastvany", -7.0, 480.0)
			s.emotions.impulse("life_bad")
		"boss_yelled":
			_bad(s, "prace_rev", "Šéf na mě řval", "smutny", -8.0, 480.0)
			s.emotions.impulse("life_bad")
		"support":
			s.add_joy_moodlet("prace_opora", "V práci se mě zeptali, jak mi je (%s)" % npc_first, "spokojeny", 4.0, 480.0)
		"small_talk":
			s.add_joy_moodlet("prace_kec", "Pokec s kolegy", "spokojeny", 2.0, 240.0)
		"burnout_moment":
			_bad(s, "prace_hrana", "V práci jsem se málem sesypal(a)", "unaveny", -8.0, 480.0)
	if bool(ev.get("strain_high", false)):
		_bad(s, "vyhoreni", "Jsem na hraně vyhoření", "unaveny", -6.0, 720.0)
	if bool(ev.get("slack_caught", false)):
		_bad(s, "prace_flakani", "Načapali mě, jak se flákám", "nesvuj", -5.0, 360.0)
	if bool(ev.get("left_early", false)) and String(ev.get("reason", "")) == "panic" and s.content_allowed("mental_health"):
		if String(ev.get("stigma", "")) == "stigma":
			_bad(s, "prace_stigma", "Šéf to bral, jako bych simuloval(a)", "smutny", -6.0, 1440.0)
		else:
			s.add_joy_moodlet("prace_pochopeni", "Šéf to vzal s pochopením", "spokojeny", 2.0, 720.0)
	var victim := String(ev.get("victim", ""))
	var vs = _sim_by_name(world, victim) if victim != "" else null
	var rv = world.dynamics.get("rivalry")
	match String(ev.get("scheme", "")):
		"worked":
			var hon := float(s.infidelity_profile("").get("honesty", 0.5))
			if hon >= 0.35:
				_bad(s, "prace_spina", "Hraju v práci špinavě", "nesvuj", -4.0, 720.0)
			else:
				s.add_joy_moodlet("prace_naskok", "Konkurence dostala na frak", "spokojeny", 3.0, 480.0)
			if vs != null:
				_bad(vs, "prace_klacky", "Někdo mi v práci hází klacky pod nohy", "nastvany", -6.0, 720.0)
				vs.say(ActionLibrary.random_line("work_sabotaged", vs.rng))
				vs._detail_dirty = true
		"caught":
			_bad(s, "prace_nacapan", "Načapali mě při intrikách", "nesvuj", -10.0, 1440.0)
			s.say(ActionLibrary.random_line("work_scheme_caught", s.rng))
			s.remember("Načapali mě při intrikách v práci (%s)." % victim.split(" ")[0])
	if vs != null and bool(ev.get("victim_learned", false)):
		_victim_learns(vs, s, rv, now)
	if bool(ev.get("warning", false)) and not bool(ev.get("fired", false)):
		_bad(s, "prace_vytka", "Dostal(a) jsem v práci výtku", "smutny", -8.0, 1440.0)
		s.remember(s.gendered("Dostal(a) jsem v práci výtku."))
	if bool(ev.get("forgiven", false)):
		s.add_joy_moodlet("prace_cisto", "Šéf mi smazal výtku", "spokojeny", 3.0, 720.0)
	# Kolegové (skutečné postavy, které dnes pracovaly ve stejném oboru): pár slov u kafe (ne soci).
	for cw in ev.get("coworkers", []):
		var o = _sim_by_name(world, String(cw))
		if o == null or (rv != null and rv.heat(n, String(cw), now) >= Rivalry.RIVAL_MIN):
			continue
		var cur := float(s.relationships.get(String(cw), 0.0))
		var nv := clampf(cur + COWORKER_REL * s.ledger.warmth_mult(String(cw)), -100.0, 100.0)
		s.relationships[String(cw)] = nv
		s.last_talk[String(cw)] = now
		s.note_relationship_change(o, cur, nv)
	if bool(ev.get("fired", false)):
		_apply_fired(s)
	elif String(ev.get("event", "")) == "praise":
		s.say(ActionLibrary.random_line("work_back_good", s.rng))
	elif s.rng.randf() < 0.3:
		s.say(ActionLibrary.random_line("work_back", s.rng))
	s._detail_dirty = true


## Oběť intriky zjistila, kdo za tím je: rivalita „o postavení“, vztah dolů, vzpomínka.
static func _victim_learns(vs, author, rv, now: float) -> void:
	var a := String(author.sim_name)
	if rv != null:
		rv.feel(String(vs.sim_name), a, "status", VICTIM_LEARN_HEAT, now)
	var cur := float(vs.relationships.get(a, 0.0))
	var nv := clampf(cur - VICTIM_LEARN_REL, -100.0, 100.0)
	vs.relationships[a] = nv
	vs.ledger.on_hurt_by(a, 6.0, now)
	vs.note_relationship_change(author, cur, nv)
	vs.mood.add_moodlet("prace_zrada_" + String(author.name), "%s mi v práci hází klacky pod nohy" % author.first_name(), "nastvany", -10.0, 1440.0)
	vs.remember("Zjistil%s jsem, že mi %s v práci škodí." % [Grammar.past(vs.grammar), author.first_name()])
	vs._detail_dirty = true


static func _apply_fired(s) -> void:
	_bad(s, "vyhazov", "Dostal(a) jsem padáka", "smutny", -25.0, 4320.0)
	_stress(s, 25.0)
	s.emotions.impulse("life_bad")
	s.say(ActionLibrary.random_line("work_fired", s.rng))
	s.remember(s.gendered("Vyhodili mě z práce."))


static func _apply_absence(world, s, ev: Dictionary, _now: float) -> void:
	if bool(ev.get("fired", false)):
		_apply_fired(s)
	else:
		_bad(s, "prace_absence", "Nepřišel(a) jsem do práce. Bude průšvih", "nesvuj", -6.0, 720.0)
		_stress(s, 4.0)
		if int(ev.get("warnings", 0)) > 0:
			s.remember(s.gendered("Nepřišel(a) jsem do práce a dostal(a) jsem výtku."))
	s._detail_dirty = true


static func _apply_sick(s, r: Dictionary) -> void:
	s.say(ActionLibrary.random_line("call_sick", s.rng))
	if s.content_allowed("mental_health"):
		match String(r.get("stigma", "")):
			"stigma":
				_bad(s, "nemoc_stigma", "Šéf mi do telefonu dal najevo, že si vymýšlím", "smutny", -6.0, 1440.0)
			"understood":
				s.add_joy_moodlet("nemoc_pochopeni", "Šéf to vzal překvapivě v pohodě", "spokojeny", 3.0, 720.0)
	if not bool(r.get("excused", true)):
		_bad(s, "nemoc_casto", "Zase jsem si vzal(a) volno. Šéf už je nervózní", "nesvuj", -4.0, 720.0)
	s._detail_dirty = true


static func _apply_search(s, r: Dictionary) -> void:
	if bool(r.get("hired", false)):
		s.add_joy_moodlet("nova_prace", "Mám novou práci", "stastny", 12.0, 2880.0)
		s.say(ActionLibrary.random_line("job_hired", s.rng))
		s.remember(s.gendered("Vzali mě do nové práce: %s." % Career.job_title(String(r["track"]), int(r["level"]), Grammar.noun_col(s.grammar))))
	else:
		_bad(s, "prace_odmitnuti", "Další odmítnutí", "smutny", -5.0, 720.0)
		s.say(ActionLibrary.random_line("job_rejected", s.rng))
	s._detail_dirty = true


static func _apply_race(world, ev: Dictionary, now: float) -> void:
	var win := String(ev.get("winner", ""))
	var lose := String(ev.get("loser", ""))
	var ws = _sim_by_name(world, win)
	var ls = _sim_by_name(world, lose)
	var rv = world.dynamics.get("rivalry")
	if ws != null and ev.has("new_level"):
		ws.add_joy_moodlet("povyseni", "Povýšili mě!", "stastny", 15.0, 2880.0)
		ws.say(ActionLibrary.random_line("work_promoted", ws.rng))
		var title := Career.job_title(String(ev.get("track", "")), int(ev["new_level"]), Grammar.noun_col(ws.grammar))
		ws.remember(ws.gendered("Povýšili mě: %s." % title))
		ws._detail_dirty = true
	if ls != null:
		_bad(ls, "povyseni_prohra", "Prohraný souboj o povýšení (%s)" % win.split(" ")[0], "nastvany", -10.0, 2880.0)
		ls.say(ActionLibrary.random_line("work_lost_race", ls.rng))
		ls.remember(ls.gendered("Prohrál(a) jsem souboj o povýšení (%s)." % win.split(" ")[0]))
		_stress(ls, 6.0)
		if ws != null and rv != null:
			rv.feel(lose, win, "status", Career.RACE_LOST_HEAT, now)
		ls._detail_dirty = true


# ------------------------------------------------------------------ HUD

static func private_lines(world, s) -> PackedStringArray:
	var c = career_of(world)
	if c == null or s == null:
		return PackedStringArray()
	return c.private_lines(String(s.sim_name), Grammar.noun_col(s.grammar), _now(world))
