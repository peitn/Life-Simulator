extends "res://tests/test_base.gd"
## Career (scripts/sim/career.gd) + CareerHooks: obory a rozvrh, směna mimo parcelu, výkon a šéf, docházka,
## nemocenská a stigma, vyhazov, hledání práce, souboj o povýšení (NPC i skutečná postava), intriky a jejich
## odhalení, AI rozvrh, ukládání (striktní snapshot, fuzz, tolerantní načtení), scéna se skutečným světem
## (odchod po chodníku, výplata do rozpočtu, save během směny, absence, vyhazov, HUD, loutka).
## Spuštění: godot_run scene=res://tests/test_career.tscn
const Career := preload("res://scripts/sim/career.gd")
const CareerHooks := preload("res://scripts/sim/career_hooks.gd")
const Rivalry := preload("res://scripts/sim/rivalry.gd")
const Main := preload("res://main.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimPuppet := preload("res://scripts/sim/sim_puppet.gd")
const GameSave := preload("res://scripts/save/game_save.gd")
var clock: Node
var _digit := RegEx.new()


func _ready() -> void:
	watchdog_seconds = 115.0
	_digit.compile("[0-9]")
	clock = get_node("/root/GameClock")
	clock.running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	_units_schedule()
	_units_shift()
	_units_attendance()
	_units_race()
	_units_ai()
	_units_save()
	await _scene()
	clock.running = false
	finish("test_career")


static func T(day: int, hour: int, minute: int = 0) -> float:
	return float(day - 1) * 1440.0 + float(hour) * 60.0 + float(minute)


static func R(q := 0.5, slack := 0.9, ev := 0.99, kind := 0.5, scheme := 0.9, learn := 0.9) -> Array:
	return [q, slack, ev, kind, scheme, learn]


func _emp(c, n: String, track: String, now: float) -> void:
	c.ensure(n, [], 30, now)
	c.hire(n, track, 0, now - 2880.0)


# ------------------------------------------------------------------ katalog a rozvrh
func _units_schedule() -> void:
	section("Katalog oborů a rozvrh")
	check(Career.TRACK_IDS.size() == 5 and Career.TRACKS.size() == 5, "5 oborů")
	var ok_titles := true
	var ok_wage := true
	for tr in Career.TRACK_IDS:
		for lv in 5:
			for col in 3:
				if Career.job_title(tr, lv, col) == "":
					ok_titles = false
			if lv > 0 and Career.shift_wage(tr, lv) <= Career.shift_wage(tr, lv - 1):
				ok_wage = false
	check(ok_titles, "název pozice pro všechny úrovně a rody (mužský/ženský/neutrální opis)")
	check(ok_wage, "mzda roste s úrovní")
	check(Career.job_title("retail", 1, 0) == "prodavač" and Career.job_title("retail", 1, 1) == "prodavačka"
		and Career.job_title("retail", 1, 2) == "osoba v prodeji", "rod řídí gramatika, ne tělo (prodavač/ka/opis)")
	check(Career.weekday_of(1) == 0 and Career.weekday_of(7) == 6 and Career.weekday_of(8) == 0, "den 1 = pondělí")
	check(Career.is_workday("care", 6) and Career.is_workday("care", 7) and not Career.is_workday("office", 6),
		"péče má víkendy, kancelář ne")
	check(Career.track_from_story(["gastro"]) == "kitchen" and Career.track_from_story(["sklad", "doprava"]) == "warehouse"
		and Career.track_from_story(["neco"]) == "" and Career.track_from_story("gastro") == "", "obor z minulé práce v příběhu")
	var c = Career.new()
	check(c.ensure("Jana Nováková", ["gastro"], 34, T(1, 10)) and c.record("Jana Nováková")["track"] == "kitchen",
		"dospělá postava s minulou prací začíná v oboru")
	c.ensure("Bez Práce", [], 30, T(1, 10))
	check(not c.has_job("Bez Práce"), "bez minulé práce = bez práce")
	c.ensure("Mlady Clovek", ["gastro"], 17, T(1, 10))
	check(not c.has_job("Mlady Clovek"), "pojistka: mladší 18 let žádná kariéra")
	check(not c.ensure("Jana Nováková", ["it"], 34, T(1, 10)), "registrace jen jednou")
	check(not c.ensure("A>B", [], 30, 0.0) and not c.jobs.has("A>B"), "jméno s oddělovačem se odmítne")

	section("Okno příchodu a blokace")
	var n := "Jana Nováková"   # gastro: začátek 11:00, út–so; den 1 = po → den 2 = út
	check(c.command_block(n, "work_shift", T(1, 11)) == "not_workday", "gastro v pondělí nepracuje")
	check(c.command_block(n, "work_shift", T(2, 9, 30)) == "too_early", "9:30 na směnu od 11 moc brzo")
	check(c.command_block(n, "work_shift", T(2, 10, 15)) == "" and c.arrival(n, T(2, 10, 15)) == "early", "hodinu předem lze vyrazit")
	check(c.arrival(n, T(2, 11, 10)) == "on_time" and c.arrival(n, T(2, 12, 0)) == "late", "včas / pozdě (+30 min)")
	check(c.command_block(n, "work_shift", T(2, 13, 30)) == "too_late", "po +2 h je pozdě")
	check(c.command_block(n, "work_scheme", T(2, 11)) == "no_race", "intrikovat jde jen v souboji o povýšení")
	check(c.command_block(n, "job_search", T(2, 11)) == "employed" and c.command_block(n, "nonsense", T(2, 11)) == "unknown",
		"hledat práci se zaměstnáním ne; neznámá akce ne")
	check(c.command_block("Nikdo", "work_shift", T(2, 11)) == "no_record", "bez záznamu ne")
	var b: Dictionary = c.begin_shift(n, "hard", T(2, 11, 40))
	check(bool(b["ok"]) and bool(b["late"]), "začátek směny 11:40 = pozdní příchod")
	check(c.command_block(n, "work_shift", T(2, 12)) == "already_worked" and c.command_block(n, "call_in_sick", T(2, 12)) == "already_worked",
		"dnes už odpracováno (ani nemocenská)")
	check(c.command_block(n, "work_shift", T(1, 11)) == "not_workday" and c.worked_today(n, 1), "rewind: zpětně se nic neopakuje")
	check(not bool(c.begin_shift(n, "normal", T(2, 12))["ok"]), "druhá směna týž den ne")
	var cg = Career.new()
	_emp(cg, "G", "kitchen", T(1, 11))
	check(cg.command_block("G", "work_shift", T(2, 13, 10)) == "too_late" and bool(cg.begin_shift("G", "normal", T(2, 13, 10))["ok"]),
		"cesta na chodník: začátek směny toleruje %d min po konci okna příkazu" % int(Career.BEGIN_GRACE))
	var cg2 = Career.new()
	_emp(cg2, "G", "kitchen", T(1, 11))
	check(cg2.check_absence("G", T(2, 13, 15)).is_empty() and not cg2.check_absence("G", T(2, 13, 25)).is_empty(),
		"absence se kontroluje až po uplynutí tolerance")
	for k in Career.CAREER_ACTIONS:
		check(not ActionLibrary.get_action(k).is_empty() and bool(ActionLibrary.get_action(k).get("player_only", false))
			and bool(ActionLibrary.get_action(k).get("career", false)), "akce %s v knihovně (player_only, career)" % k)
	check(bool(ActionLibrary.get_action("work_shift").get("away", false)) and String(ActionLibrary.get_action("work_shift")["posture"]) == "away",
		"směna je mimo parcelu (away)")


# ------------------------------------------------------------------ směna
func _units_shift() -> void:
	section("Kapacita (deprese/stres/únava/vyhoření berou sílu, ne trest)")
	var c0: float = Career.capacity(0.0, 20.0, 80.0, 0.0)
	var c1: float = Career.capacity(0.8, 20.0, 80.0, 0.0)
	var c2: float = Career.capacity(0.0, 90.0, 10.0, 1.0)
	check(c0 == 1.0 and c1 < c0 and c2 < c0, "kapacita klesá s depresí, stresem, únavou (%.2f / %.2f / %.2f)" % [c0, c1, c2])
	check(Career.capacity(1.0, 100.0, 0.0, 1.0) >= 0.25 and Career.capacity(NAN, INF, -INF, 5.0) >= 0.25, "spodní mez 0,25 i pro nesmysly")

	section("Výkon, šéf, mzda podle režimu")
	var c = Career.new()
	for n in ["H", "S", "N"]:
		_emp(c, n, "office", T(1, 9))
	var base := {"fraction": 1.0, "dep": 0.0, "stress": 20.0, "energy": 80.0, "honesty": 0.6, "now": T(2, 17)}
	var eh: Dictionary = c.resolve_shift("H", _with(base, {"mode": "hard"}), R())
	var es: Dictionary = c.resolve_shift("S", _with(base, {"mode": "slack"}), R())
	var en: Dictionary = c.resolve_shift("N", _with(base, {"mode": "normal"}), R())
	check(float(eh["perf_delta"]) > float(en["perf_delta"]) and float(en["perf_delta"]) > float(es["perf_delta"]),
		"makat naplno > běžně > flákat (%.1f / %.1f / %.1f)" % [float(eh["perf_delta"]), float(en["perf_delta"]), float(es["perf_delta"])])
	check(float(eh["stress"]) > float(en["stress"]) and float(en["stress"]) > float(es["stress"]), "makání stresuje víc")
	check(float(c.record("H")["strain"]) > float(c.record("N")["strain"]) and float(c.record("S")["strain"]) == 0.0, "vyhoření roste z makání")
	check(int(en["wage"]) == Career.shift_wage("office", 0), "celá směna = celá mzda (%d)" % int(en["wage"]))
	check(int(eh["wage"]) == int(es["wage"]), "flákání mzdu nemění (pokud nechytí šéf)")
	var dep: Dictionary = c.resolve_shift("N", _with(base, {"mode": "hard", "dep": 0.9}), R())
	check(float(dep["perf_delta"]) < float(eh["perf_delta"]), "v depresi stejná dřina vynese méně")

	section("Odchod dřív: panická ataka vs. ostatní (pochopení / stigma podle šéfa)")
	var cc = Career.new()
	_emp(cc, "Pece", "care", T(1, 7))
	_emp(cc, "Gastro", "kitchen", T(1, 11))
	_emp(cc, "Jinak", "kitchen", T(1, 11))
	var half := _with(base, {"mode": "normal", "fraction": 0.4, "reason": "panic"})
	var ep: Dictionary = cc.resolve_shift("Pece", half, R())
	var eg: Dictionary = cc.resolve_shift("Gastro", half, R())
	var eo: Dictionary = cc.resolve_shift("Jinak", _with(half, {"reason": "needs"}), R())
	check(String(ep["stigma"]) == "understood" and String(eg["stigma"]) == "stigma" and String(eo["stigma"]) == "",
		"péče (chápavý šéf) pochopí, gastro stigmatizuje, jiný důvod bez nálepky")
	check(float(ep["boss_delta"]) > float(eg["boss_delta"]) and float(eg["boss_delta"]) > float(eo["boss_delta"]),
		"panika u chápavého šéfa stojí nejméně, odchod bez důvodu nejvíc (%.1f / %.1f / %.1f)" % [float(ep["boss_delta"]), float(eg["boss_delta"]), float(eo["boss_delta"])])
	check(bool(ep["left_early"]) and int(ep["wage"]) == int(round(Career.shift_wage("care", 0) * 0.4)), "mzda jen za odpracovaný podíl")

	section("Flákání načapané šéfem → výtka až při špatném vztahu")
	var cs = Career.new()
	_emp(cs, "F", "retail", T(1, 8))
	var e1: Dictionary = cs.resolve_shift("F", _with(base, {"mode": "slack"}), R(0.5, 0.1))
	check(bool(e1["slack_caught"]) and not bool(e1["warning"]), "načapán – šéf dolů, výtka zatím ne")
	cs.jobs["F"]["boss"] = -30.0
	var e2: Dictionary = cs.resolve_shift("F", _with(base, {"mode": "slack", "now": T(3, 17)}), R(0.5, 0.1))
	check(bool(e2["warning"]) and int(cs.record("F")["warnings"]) == 1, "se šéfem na štíru = výtka")

	section("Události v práci")
	var kinds := {}
	var ce = Career.new()
	_emp(ce, "E", "kitchen", T(1, 11))
	for i in 60:
		var ev: Dictionary = ce.resolve_shift("E", _with(base, {"mode": "normal", "now": T(2 + i, 18)}), R(0.5, 0.9, 0.1, float(i) / 60.0))
		if String(ev["event"]) != "":
			kinds[String(ev["event"])] = true
		if ev.get("fired", false):
			break
	check(kinds.size() >= 4, "různé události (%s)" % str(kinds.keys()))
	var allowed := ["praise", "credit_stolen", "blamed", "boss_yelled", "support", "small_talk", "burnout_moment"]
	var ok_k := true
	for k in kinds:
		if not k in allowed:
			ok_k = false
	check(ok_k, "jen povolené druhy událostí")
	var cd = Career.new()
	_emp(cd, "D0", "office", T(1, 9))
	_emp(cd, "D1", "office", T(1, 9))
	var sup0 := 0
	var sup1 := 0
	for i in 40:
		var roll := float(i) / 40.0
		if String(cd.resolve_shift("D0", _with(base, {"now": T(2, 17), "dep": 0.0}), R(0.5, 0.9, 0.1, roll))["event"]) == "support":
			sup0 += 1
		if String(cd.resolve_shift("D1", _with(base, {"now": T(2, 17), "dep": 0.9}), R(0.5, 0.9, 0.1, roll))["event"]) == "support":
			sup1 += 1
		cd.jobs["D0"]["last_shift_day"] = Career.DAY_MIN
		cd.jobs["D1"]["last_shift_day"] = Career.DAY_MIN
	check(sup1 > sup0, "na postavu v depresi se kolegové častěji ohlédnou (%d > %d)" % [sup1, sup0])


func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate(true)
	for k in b:
		o[k] = b[k]
	return o


# ------------------------------------------------------------------ docházka, nemocenská, vyhazov, hledání
func _units_attendance() -> void:
	section("Absence a výtky")
	var c = Career.new()
	var n := "Kancl"
	_emp(c, n, "office", T(1, 9))
	check(c.check_absence(n, T(2, 10)).is_empty(), "během okna příchodu ještě žádná absence")
	var a1: Dictionary = c.check_absence(n, T(2, 11, 30))
	check(String(a1.get("kind", "")) == "absent" and int(c.record(n)["warnings"]) == 1, "pracovní den bez směny = výtka")
	check(c.check_absence(n, T(2, 15)).is_empty() and int(c.record(n)["warnings"]) == 1, "jen jednou za den")
	check(c.check_absence(n, T(1, 15)).is_empty() and int(c.record(n)["warnings"]) == 1, "rewind: zpětně žádná další výtka")
	c.begin_shift(n, "normal", T(3, 9))
	check(c.check_absence(n, T(3, 15)).is_empty() and int(c.record(n)["warnings"]) == 1, "po odpracované směně žádná absence")
	check(c.check_absence(n, T(6, 15)).is_empty() and int(c.record(n)["warnings"]) == 1, "sobota = volno, žádná absence")
	var cnew = Career.new()
	cnew.ensure(n, ["it"], 30, T(2, 10))
	check(cnew.check_absence(n, T(2, 15)).is_empty(), "den nástupu se nepočítá")

	section("Nemocenská (rozpočet omluvených dnů, reakce šéfa)")
	var cs = Career.new()
	_emp(cs, "Pece", "care", T(1, 7))
	_emp(cs, "Gastro", "kitchen", T(1, 11))
	var s1: Dictionary = cs.call_in_sick("Pece", true, T(2, 6))
	check(bool(s1["ok"]) and bool(s1["excused"]) and String(s1["stigma"]) == "understood", "péče: kvůli psychice s pochopením")
	var s2: Dictionary = cs.call_in_sick("Gastro", true, T(2, 10))
	check(bool(s2["ok"]) and String(s2["stigma"]) == "stigma", "gastro: stigma")
	check(cs.check_absence("Pece", T(2, 12)).is_empty() and cs.sick_today("Pece", 2), "nemocenská není absence")
	check(cs.command_block("Pece", "work_shift", T(2, 7)) == "sick_today", "na nemocenské se do práce nejde")
	cs.call_in_sick("Pece", false, T(4, 6))
	var s3: Dictionary = cs.call_in_sick("Pece", false, T(6, 6))
	check(bool(s3["ok"]) and not bool(s3["excused"]) and float(s3["boss_delta"]) < -5.0, "třetí den za 14 dní už není omluvený")
	check(cs.call_in_sick("Pece", false, T(6, 12)).get("reason", "") != "", "po okně příchodu už volat nejde")

	section("Vyhazov a hledání práce")
	var cf = Career.new()
	_emp(cf, "Petr", "warehouse", T(1, 6))
	for d in [2, 3, 4]:
		var ev: Dictionary = cf.check_absence("Petr", T(d, 12))
		if d == 4:
			check(bool(ev.get("fired", false)), "třetí výtka = vyhazov")
	check(not cf.has_job("Petr") and String(cf.record("Petr")["last_track"]) == "warehouse" and int(cf.record("Petr")["fired_day"]) == 4,
		"bez práce, pamatuje si obor a den vyhazovu")
	check(cf.command_block("Petr", "work_shift", T(5, 6)) == "no_job" and cf.command_block("Petr", "job_search", T(5, 6)) == "", "bez práce: hledat ano, pracovat ne")
	var j1: Dictionary = cf.job_search("Petr", 0.99, 0.0, "", T(5, 9))
	check(bool(j1["ok"]) and not bool(j1["hired"]), "odmítnutí")
	check(cf.command_block("Petr", "job_search", T(5, 10)) == "search_cooldown", "další obvolávání až za %d min" % int(Career.SEARCH_GAP))
	var cg = Career.new()
	_emp(cg, "Q", "warehouse", T(1, 6))
	cg.quit("Q")
	var j_clean: Dictionary = cg.job_search("Q", 0.99, 0.0, "", T(5, 9))
	check(float(j1["p"]) < float(j_clean["p"]), "čerstvý vyhazov snižuje šanci (%.2f < %.2f)" % [float(j1["p"]), float(j_clean["p"])])
	var j2: Dictionary = cf.job_search("Petr", 0.0, 0.0, "retail", T(5, 14))
	check(bool(j2["hired"]) and cf.record("Petr")["track"] == "retail" and int(cf.record("Petr")["level"]) == 0, "přijat do preferovaného oboru od začátku")
	check(int(cf.record("Petr")["warnings"]) == 0 and float(cf.record("Petr")["perf"]) == Career.PERF_START, "nová práce = čistý štít")

	section("Odpuštění výtky a výpověď")
	var cw = Career.new()
	_emp(cw, "W", "office", T(1, 9))
	cw.jobs["W"]["warnings"] = 1
	var forgiven := false
	for i in Career.CLEAN_SHIFTS_FORGIVE:
		var e: Dictionary = cw.resolve_shift("W", {"mode": "normal", "fraction": 1.0, "now": T(2 + i, 17), "energy": 80.0}, R(0.6))
		forgiven = forgiven or bool(e.get("forgiven", false))
	check(forgiven and int(cw.record("W")["warnings"]) == 0, "%d čistých směn smaže výtku" % Career.CLEAN_SHIFTS_FORGIVE)
	cw.jobs["W"]["strain"] = 0.8
	var q: Dictionary = cw.quit("W")
	check(bool(q["ok"]) and bool(q["relief"]) and not cw.has_job("W"), "výpověď z vyhoření = úleva")
	check(not bool(cw.quit("W")["ok"]), "bez práce nejde dát výpověď")

	section("Vyhazov ze špatného výkonu a šéfa")
	var cp = Career.new()
	_emp(cp, "P", "retail", T(1, 8))
	cp.jobs["P"]["perf"] = 5.0
	cp.jobs["P"]["boss"] = -70.0
	var ep: Dictionary = cp.resolve_shift("P", {"mode": "slack", "fraction": 1.0, "now": T(2, 17), "energy": 80.0}, R(0.5, 0.9))
	check(bool(ep["fired"]) and not cp.has_job("P"), "slabý výkon a šéf, který tě nesnáší = vyhazov")


# ------------------------------------------------------------------ souboj o povýšení a intriky
func _units_race() -> void:
	section("Souboj o povýšení s NPC kolegou")
	var c = Career.new()
	_emp(c, "Pilná", "office", T(1, 9))
	_emp(c, "Líný", "office", T(1, 9))
	for n in ["Pilná", "Líný"]:
		c.jobs[n]["perf"] = 72.0
		c.jobs[n]["level_shifts"] = 4
	var base := {"fraction": 1.0, "dep": 0.0, "stress": 20.0, "energy": 80.0, "honesty": 0.6}
	c.resolve_shift("Pilná", _with(base, {"mode": "hard", "now": T(2, 17)}), R())
	var rc: Dictionary = c.race_of("Pilná")
	check(not rc.is_empty() and String(rc["vs"]) == "Líný", "dvě skutečné postavy na stejné úrovni → souboj spolu (%s)" % str(rc))
	var c2 = Career.new()
	_emp(c2, "Pilná", "office", T(1, 9))
	_emp(c2, "Líný", "kitchen", T(1, 11))
	for n in ["Pilná", "Líný"]:
		c2.jobs[n]["perf"] = 72.0
		c2.jobs[n]["level_shifts"] = 4
	c2.resolve_shift("Pilná", _with(base, {"mode": "hard", "now": T(2, 17)}), R())
	var rn: Dictionary = c2.race_of("Pilná")
	check(bool(rn.get("npc", false)) and String(rn["vs"]) == "Marek Vlk", "jinak NPC kolega s největší ambicí (%s)" % str(rn))
	c2.resolve_shift("Líný", _with(base, {"mode": "slack", "now": T(3, 18)}), R())
	check(c2.race_of("Líný").get("npc", false), "druhá postava má vlastní souboj s NPC")
	for d in range(3, 8):
		c2.jobs["Pilná"]["last_shift_day"] = Career.DAY_MIN
		c2.resolve_shift("Pilná", _with(base, {"mode": "hard", "now": T(d, 17)}), R(0.7))
		if d >= 4:
			c2.jobs["Líný"]["last_shift_day"] = Career.DAY_MIN
			c2.resolve_shift("Líný", _with(base, {"mode": "slack", "now": T(d, 18)}), R(0.3))
	var evs: Array = c2.day_tick(T(10, 1))
	var won := false
	var lost := false
	for e in evs:
		if String(e["winner"]) == "Pilná":
			won = true
		if String(e["loser"]) == "Líný" and bool(e["npc_winner"]):
			lost = true
	check(won and int(c2.record("Pilná")["level"]) == 1 and float(c2.record("Pilná")["perf"]) == Career.PROMO_PERF_RESET,
		"dřina vyhrála: povýšení a nová laťka výkonu (%s)" % str(evs))
	check(lost and int(c2.record("Líný")["level"]) == 0 and float(c2.record("Líný")["npc_heat"].values().max() if not c2.record("Líný")["npc_heat"].is_empty() else 0.0) >= Career.RACE_LOST_HEAT,
		"flákač prohrál s NPC: zůstává, NPC kolega ho štve")
	check(int(c2.record("Líný")["level_shifts"]) < 6 and not c2.in_race("Pilná") and c2.races.is_empty(), "souboje uzavřené")

	section("Intrika proti skutečné postavě: vyjde / praskne, strop škody, oběť se může dozvědět")
	var cr = Career.new()
	_emp(cr, "Intrikán", "retail", T(1, 8))
	_emp(cr, "Oběť", "retail", T(1, 8))
	for n in ["Intrikán", "Oběť"]:
		cr.jobs[n]["perf"] = 70.0
		cr.jobs[n]["level_shifts"] = 4
	cr.resolve_shift("Oběť", _with(base, {"mode": "normal", "now": T(2, 17)}), R())
	check(cr.in_race("Intrikán") and cr.in_race("Oběť"), "souboj otevřen (a obě strany o něm vědí)")
	check(cr.command_block("Intrikán", "work_scheme", T(3, 8)) == "", "v souboji intrikovat lze")
	var vp0: float = float(cr.record("Oběť")["perf"])
	var w1: Dictionary = cr.resolve_shift("Intrikán", _with(base, {"mode": "scheme", "now": T(3, 17), "honesty": 0.2}), R(0.5, 0.9, 0.99, 0.5, 0.9, 0.9))
	check(String(w1["scheme"]) == "worked" and String(w1["victim"]) == "Oběť" and not bool(w1["victim_learned"]), "vyšlo, oběť nic netuší")
	check(float(cr.record("Oběť")["perf"]) == vp0 - Career.SCHEME_VICTIM_PERF, "oběť přišla o výkon (%.1f → %.1f)" % [vp0, float(cr.record("Oběť")["perf"])])
	cr.jobs["Intrikán"]["last_shift_day"] = Career.DAY_MIN
	cr.resolve_shift("Intrikán", _with(base, {"mode": "scheme", "now": T(3, 18), "honesty": 0.2}), R(0.5, 0.9, 0.99, 0.5, 0.9, 0.9))
	var rpts: float = float(cr.races.values()[0]["pb"] if String(cr.races.values()[0]["b"]) == "Oběť" else cr.races.values()[0]["pa"])
	cr.jobs["Intrikán"]["last_shift_day"] = Career.DAY_MIN
	cr.resolve_shift("Intrikán", _with(base, {"mode": "scheme", "now": T(3, 19), "honesty": 0.2}), R(0.5, 0.9, 0.99, 0.5, 0.9, 0.9))
	var rpts2: float = float(cr.races.values()[0]["pb"] if String(cr.races.values()[0]["b"]) == "Oběť" else cr.races.values()[0]["pa"])
	check(float(cr.record("Oběť")["perf"]) == vp0 - Career.SCHEME_VICTIM_PERF and rpts2 == rpts, "strop: týž den oběť víc neztratí výkon ani body souboje")
	cr.jobs["Intrikán"]["last_shift_day"] = Career.DAY_MIN
	var w3: Dictionary = cr.resolve_shift("Intrikán", _with(base, {"mode": "scheme", "now": T(4, 17), "honesty": 0.2}), R(0.5, 0.9, 0.99, 0.5, 0.9, 0.1))
	check(bool(w3["victim_learned"]), "oběť se to může dozvědět (hod)")
	cr.jobs["Intrikán"]["last_shift_day"] = Career.DAY_MIN
	var w4: Dictionary = cr.resolve_shift("Intrikán", _with(base, {"mode": "scheme", "now": T(5, 17), "honesty": 0.2}), R(0.5, 0.9, 0.99, 0.5, 0.1))
	check(String(w4["scheme"]) == "caught" and bool(w4["warning"]) and bool(w4["victim_learned"]) and int(cr.record("Intrikán")["warnings"]) == 1,
		"prasklo: výtka a oběť ví, kdo za tím je")
	check(float(w4["boss_delta"]) < 0.0, "šéf zuří (%.1f)" % float(w4["boss_delta"]))
	cr.forget("Oběť")
	check(not cr.in_race("Intrikán") and cr.races.is_empty(), "odchod postavy zruší souboj")


# ------------------------------------------------------------------ AI
func _units_ai() -> void:
	section("AI rozvrh")
	var c = Career.new()
	_emp(c, "A", "office", T(1, 9))
	var calm := {"dep": 0.0, "barrier": 0.0, "stress": 20.0, "energy": 80.0, "honesty": 0.6, "lazy": false, "roll": 0.9}
	check(c.ai_choice("A", calm, T(2, 7)) == "", "brzy ráno ještě nic")
	check(c.ai_pending("A", T(2, 8, 40)), "v okně příchodu je potřeba rozhodnout")
	var p1: String = c.ai_choice("A", calm, T(2, 8, 40))
	check(p1 == "work_shift", "klidná postava jde normálně do práce (%s)" % p1)
	check(not c.ai_pending("A", T(2, 8, 45)) and c.ai_choice("A", {}, T(2, 8, 45)) == p1, "rozhodnutí platí celý den (rng se znovu nečerpá)")
	var c2 = Career.new()
	_emp(c2, "D", "office", T(1, 9))
	check(c2.ai_choice("D", _with(calm, {"dep": 0.8}), T(2, 8, 40)) == "call_in_sick", "těžká deprese → zavolá, že nepřijde")
	var c3 = Career.new()
	_emp(c3, "B", "office", T(1, 9))
	check(c3.ai_choice("B", _with(calm, {"barrier": 0.9, "roll": 0.1}), T(2, 8, 40)) == "call_in_sick", "bariéra iniciace s volnou nemocenskou → aspoň zavolá (symptom ≠ přestupek)")
	var c3b = Career.new()
	_emp(c3b, "B", "office", T(1, 9))
	c3b.jobs["B"]["sick"] = [1, 2]
	check(c3b.ai_choice("B", _with(calm, {"barrier": 0.9, "roll": 0.1}), T(3, 8, 40)) == "", "s vyčerpanou nemocenskou se někdy nezvedne ani nezavolá (absence má následky)")
	var c4 = Career.new()
	_emp(c4, "L", "office", T(1, 9))
	check(c4.ai_choice("L", _with(calm, {"lazy": true}), T(2, 8, 40)) == "work_slack", "lenoch se fláká")
	var c5 = Career.new()
	_emp(c5, "U", "office", T(1, 9))
	c5.quit("U")
	check(c5.ai_choice("U", {}, T(2, 8, 40)) == "job_search", "bez práce hledá")
	c5.job_search("U", 0.99, 0.0, "", T(2, 9))
	check(c5.ai_choice("U", {}, T(2, 15)) == "", "hledání nejvýš jednou denně")


# ------------------------------------------------------------------ ukládání
func _units_save() -> void:
	section("Ukládání: striktní snapshot, tolerantní načtení, fuzz")
	var c = Career.new()
	_emp(c, "Jana", "kitchen", T(1, 11))
	_emp(c, "Petr", "kitchen", T(1, 11))
	for n in ["Jana", "Petr"]:
		c.jobs[n]["perf"] = 70.0
		c.jobs[n]["level_shifts"] = 4
	c.resolve_shift("Jana", {"mode": "normal", "fraction": 1.0, "now": T(2, 19), "energy": 80.0}, R(0.5, 0.9, 0.1, 0.2))
	c.call_in_sick("Petr", true, T(3, 9))
	var d: Dictionary = c.to_dict()
	check(Career.validate_snapshot(d), "vlastní snapshot projde striktní kontrolou")
	var js := JSON.stringify(d)
	var back = JSON.parse_string(js)
	check(Career.validate_snapshot(back), "i po JSON (int → float) projde")
	var c2 = Career.new()
	c2.from_dict(back)
	check(c2.load_note == "", "načteno bez poznámky")
	check(c2.has_job("Jana") and c2.in_race("Jana") and c2.in_race("Petr") and c2.sick_today("Petr", 3), "obsah sedí (souboj, nemocenská)")
	check(Career.validate_snapshot(c2.to_dict()), "načtený stav znovu projde")
	var bad := []
	var b1: Dictionary = d.duplicate(true); b1["version"] = 2; bad.append(b1)
	var b2: Dictionary = d.duplicate(true); b2["extra"] = 1; bad.append(b2)
	var b3: Dictionary = d.duplicate(true); b3["jobs"]["Jana"]["perf"] = 150.0; bad.append(b3)
	var b4: Dictionary = d.duplicate(true); b4["jobs"]["Jana"]["track"] = "astronaut"; bad.append(b4)
	var b5: Dictionary = d.duplicate(true); b5["jobs"]["Jana"]["warnings"] = 9; bad.append(b5)
	var b6: Dictionary = d.duplicate(true); b6["jobs"]["Jana"]["boss"] = NAN; bad.append(b6)
	var b7: Dictionary = d.duplicate(true); b7["jobs"]["A>B"] = d["jobs"]["Jana"].duplicate(true); bad.append(b7)
	var b8: Dictionary = d.duplicate(true); b8["jobs"]["Jana"]["race"] = 999; bad.append(b8)
	var b9: Dictionary = d.duplicate(true); b9["races"].values()[0]["track"] = "x"; bad.append(b9)
	var b10: Dictionary = d.duplicate(true); b10["jobs"]["Jana"]["sick"] = [1, 2, 3, 4, 5, 6, 7, 8, 9]; bad.append(b10)
	var b11: Dictionary = d.duplicate(true); b11["jobs"]["Jana"]["npc_heat"] = {"X": 3.0}; bad.append(b11)
	var b12: Dictionary = d.duplicate(true); b12["jobs"]["Jana"]["ai_pick"] = "rob_bank"; bad.append(b12)
	var b13: Dictionary = d.duplicate(true); b13["jobs"]["Jana"].erase("strain"); bad.append(b13)
	var b14: Dictionary = d.duplicate(true); b14["stats"]["shifts"] = -1; bad.append(b14)
	var b15: Dictionary = d.duplicate(true); b15["next_race"] = 0; bad.append(b15)
	var b16: Dictionary = d.duplicate(true); b16["jobs"]["Jana"]["level"] = 1.5; bad.append(b16)
	var rejected := 0
	for x in bad:
		if not Career.validate_snapshot(x):
			rejected += 1
	check(rejected == bad.size(), "striktní kontrola odmítne všech %d vadných variant (%d)" % [bad.size(), rejected])
	var tolerant_ok := true
	for x in bad:
		var cx = Career.new()
		cx.from_dict(x)
		if cx.load_note == "" and not Career.validate_snapshot(cx.to_dict()):
			tolerant_ok = false
	check(tolerant_ok, "tolerantní načtení z vadných dat vždy vyrobí platný stav")
	var cfz = Career.new()
	cfz.from_dict(b1)
	check(cfz.load_note == "future_version" and cfz.jobs.is_empty(), "budoucí verze se zahodí celá")
	var cleg = Career.new()
	cleg.from_dict({"jobs": {}})
	check(cleg.load_note == "legacy_unversioned", "bez verze = nic k migraci")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var fuzz_ok := true
	var junk := [null, -1, 1.5, NAN, INF, "", "x", [], {}, [1, "a"], {"a": 1}, true, 1.0e30, -1.0e30, "A>B"]
	for i in 300:
		var x: Dictionary = d.duplicate(true)
		var target: Dictionary = x
		if rng.randf() < 0.6:
			target = x["jobs"]["Jana"]
		var ks: Array = target.keys()
		target[ks[rng.randi() % ks.size()]] = junk[rng.randi() % junk.size()]
		var cx = Career.new()
		cx.from_dict(x)
		if cx.load_note == "" and not Career.validate_snapshot(cx.to_dict()):
			fuzz_ok = false
	check(fuzz_ok, "fuzz 300: načtení nikdy nespadne a vždy dá platný stav")

	section("Soukromé řádky HUD (bez čísel)")
	var lines: PackedStringArray = c.private_lines("Jana", 1, T(3, 10))
	var no_digits := true
	for l in lines:
		if _digit.search(l) != null:
			no_digits = false
	check(lines.size() >= 2 and String(lines[0]).begins_with("Práce: pomocná síla v kuchyni (Gastro)") and no_digits,
		"řádky: pozice v rodě postavy, souboj, bez čísel (%s)" % " | ".join(lines))
	var cu = Career.new()
	cu.ensure("U", [], 30, 0.0)
	check(String(cu.private_lines("U", 0, 0.0)[0]) == "Práce: bez práce", "bez práce")


# ------------------------------------------------------------------ scéna
func _world(seed: int, dir := "") -> Node:
	clock.total_minutes = T(2, 9)   # úterý 9:00
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "CareerWorld%d" % seed
	var cfg := {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false, "clock": clock, "careers": true}
	if dir != "":
		cfg["save_directory"] = dir
	w.net_config = cfg
	add_child(w)
	var n := 0
	for sim in w.sims:
		sim.rng.seed = seed * 7919 + n * 104729 + 13
		sim.think_cooldown = sim.rng.randf_range(0.0, 3.0)
		n += 1
	return w


func _find(w: Node, first: String) -> Node:
	for s in w.sims:
		if s.first_name() == first:
			return s
	return null


func _scene() -> void:
	section("Scéna: domácnost s prací")
	var w := _world(31, "user://test-career-%d" % OS.get_process_id())
	var jana = _find(w, "Jana")
	var petr = _find(w, "Petr")
	var eliska = _find(w, "Eliška")
	check(jana != null and petr != null and eliska != null, "Jana, Petr, Eliška")
	if jana == null or petr == null or eliska == null:
		return
	var c = w.dynamics.career
	check(c != null and c.get_script() == Career and w.careers_enabled, "HouseholdDynamics.career, kariéry zapnuté")
	CareerHooks.tick(w)   # registrace hned (bez posunu času – AI ještě nerozhodla)
	check(c.record(jana.sim_name).get("track", "") == "kitchen" and c.record(petr.sim_name).get("track", "") == "warehouse"
		and c.record(eliska.sim_name).get("track", "") == "office", "obory podle příběhu: gastro / sklad / kancelář")
	# Pro jistotu: AI dnes nikoho samo neposílá (rozhodují testy příkazy).
	for s in [jana, petr, eliska]:
		c.jobs[s.sim_name]["ai_day"] = 2
		c.jobs[s.sim_name]["ai_pick"] = ""
		c.jobs[s.sim_name]["hired_day"] = 1   # nastoupili dřív (den nástupu se do absence nepočítá)
	var jw0: int = int(c.record(jana.sim_name)["warnings"])
	clock.advance(12.0)

	section("Server odmítne nesmysly (rozvrh, zaměstnání, souboj)")
	check(w.net.handle_command(0, String(jana.name), "work_shift", "") == Career.block_text("too_early"), "Jana (gastro od 11) v 9:12 ještě ne")
	check(w.net.handle_command(0, String(petr.name), "job_search", "") == Career.block_text("employed"), "Petr práci má")
	var r_s: String = w.net.handle_command(0, String(eliska.name), "work_scheme", "")
	check(r_s == Career.block_text("no_race"), "Eliška nemá proti komu intrikovat (%s)" % r_s)
	var r_h: String = w.net.handle_command(0, String(eliska.name), "work_hard", "")
	check(r_h == "", "Eliška (kancelář od 9) jde makat naplno (%s)" % r_h)

	section("Odchod po chodníku a směna mimo parcelu")
	var gone := false
	for i in 90:
		clock.advance(1.0)
		if eliska.away:
			gone = true
			break
	check(gone, "Eliška došla na chodník a odešla do práce")
	check(not eliska.visible and eliska.global_position.y < -100.0, "mimo parcelu: skrytá, zaparkovaná pod světem")
	check(eliska.current_posture() == "away" and eliska.display_action() == "V práci (maká naplno)", "veřejně jen „V práci“ (%s / %s)" % [eliska.current_posture(), eliska.display_action()])
	var pts: Array = w.lot_sim_points()
	var listed := false
	for p in pts:
		if String(p[0]) == String(eliska.name):
			listed = true
	check(not listed, "postava v práci nepočítá do kontrol zámků a zdí")
	check(eliska.away_return.distance_to(w.work_exit().global_position) < 1.0, "návratový bod = konec chodníku")
	check(not eliska.can_join_social(jana), "v práci si s ní nikdo nepopovídá")
	var funds0: int = int(w.lot.funds)

	section("Save během směny a návrat")
	var sv: Dictionary = w.save_game("manual")
	check(bool(sv.get("ok", false)), "uloženo během směny (%s)" % str(sv))
	var ld: Dictionary = w.load_game("manual")
	check(bool(ld.get("ok", false)), "načteno (%s)" % str(ld))
	eliska = _find(w, "Eliška")
	jana = _find(w, "Jana")
	petr = _find(w, "Petr")
	c = w.dynamics.career
	check(eliska != null and eliska.away and not eliska.visible, "po načtení je Eliška pořád v práci")
	check(c.worked_today(eliska.sim_name, 2), "záznam směny přežil uložení")
	var back := false
	for i in 600:
		clock.advance(1.0)
		if not eliska.away:
			back = true
			break
	check(back and eliska.visible and eliska.global_position.y > -1.0, "po směně zpět (viditelná, na zemi)")
	check(eliska.global_position.distance_to(w.work_exit().global_position) < 1.5, "vrátila se po chodníku (nestavitelný koridor – nic ji nezazdí)")
	check(int(w.lot.funds) > funds0, "výplata do rozpočtu domácnosti (%d → %d kr)" % [funds0, int(w.lot.funds)])
	var wage_logged := false
	for e in w.lot.ledger:
		if String(e.get("kind", "")) == "wage":
			wage_logged = true
	check(wage_logged, "ve výpisu rozpočtu je položka „wage“")
	check(int(c.stats["shifts"]) == 1 and int(c.stats["hard"]) == 1, "statistika směn (%s)" % str(c.stats))
	check(w.net.handle_command(0, String(eliska.name), "work_shift", "") == Career.block_text("already_worked"), "dnes už podruhé ne")

	section("Absence: AI se dnes „nezvedne“ → výtka")
	# Jana: gastro (út) od 11; rozhodnutí na dnešek = nejít a nezavolat.
	clock.total_minutes = maxf(clock.total_minutes, T(2, 13, 35))
	clock.advance(12.0)
	check(int(c.record(jana.sim_name)["warnings"]) == jw0 + 1, "Jana nepřišla → výtka")
	check(jana.mood.has_moodlet("prace_absence"), "Jana ví, že bude průšvih")

	section("AI chodí do práce sama (rozvrh)")
	# Středa: sklad od 6:00. Petr bez zásahu.
	clock.total_minutes = T(3, 4, 55)
	clock.advance(2.0)
	var petr_went := false
	var petr_sick := false
	for i in 240:
		clock.advance(1.0)
		if petr.away:
			petr_went = true
			break
		if c.sick_today(petr.sim_name, 3):
			petr_sick = true
			break
	check(petr_went or petr_sick, "Petr ráno sám vyrazil do skladu (nebo zavolal, že nepřijde) – %s" % String(c.record(petr.sim_name).get("ai_pick", "")))

	section("Vyhazov v domácnosti")
	c.jobs[jana.sim_name]["warnings"] = 2
	c.jobs[jana.sim_name]["ai_day"] = 3
	c.jobs[jana.sim_name]["ai_pick"] = ""
	clock.total_minutes = maxf(clock.total_minutes, T(3, 13, 35))
	clock.advance(12.0)
	check(not c.has_job(jana.sim_name) and jana.mood.has_moodlet("vyhazov"), "třetí výtka: Jana dostala padáka")
	var rl: PackedStringArray = w.relationship_lines(jana)
	var has_line := false
	for l in rl:
		if String(l).begins_with("Práce: bez práce"):
			has_line = true
	check(has_line, "HUD (soukromé řádky): bez práce (%s)" % " | ".join(rl))
	check(w.net.handle_command(0, String(jana.name), "job_search", "") == "", "Jana může hledat práci")

	section("Prohraný souboj a odhalená intrika (dopady na postavy)")
	var now := float(clock.total_minutes)
	var rv = w.dynamics.rivalry
	CareerHooks._apply_race(w, {"winner": petr.sim_name, "loser": eliska.sim_name, "track": "warehouse", "new_level": 1}, now)
	check(petr.mood.has_moodlet("povyseni") and eliska.mood.has_moodlet("povyseni_prohra"), "vítěz se raduje, poražená zuří")
	check(rv.heat(eliska.sim_name, petr.sim_name, now) >= Career.RACE_LOST_HEAT * 0.9, "prohra živí rivalitu „o postavení“ (%.2f)" % rv.heat(eliska.sim_name, petr.sim_name, now))
	var r0: float = float(eliska.relationships.get(jana.sim_name, 0.0))
	CareerHooks._victim_learns(eliska, jana, rv, now)
	check(float(eliska.relationships.get(jana.sim_name, 0.0)) < r0 and rv.heat(eliska.sim_name, jana.sim_name, now) >= CareerHooks.VICTIM_LEARN_HEAT * 0.9,
		"oběť intriky: vztah dolů, sok o postavení")

	section("Loutka v multiplayeru")
	var pup = SimPuppet.new()
	pup.setup_from_data({"name": "Loutka", "pos": Vector3(1, 0, 1)}, w)
	add_child(pup)
	pup.net_posture = "away"
	pup._process(0.016)
	check(not pup.visible, "posture away → loutka se skryje")
	pup.net_posture = "stand"
	pup._process(0.016)
	check(pup.visible, "po návratu je vidět")
	pup.queue_free()
	w.queue_free()
	await get_tree().process_frame
