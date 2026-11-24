extends "res://tests/test_base.gd"
## Romance (scripts/sim/romance.gd): randění, vážný vztah, rozchod, ex.
## Spuštění: godot_run scene=res://tests/test_romance.tscn
##   bez argumentů: jednotky + fuzz + scéna (příkazy hráče, AI skóre, server, uložení) (rychlé)
##   -- --soak: 3 seedy × 10 dní (statistiky) + determinismus (pomalejší)
const Romance := preload("res://scripts/sim/romance.gd")
const ColdWar := preload("res://scripts/sim/cold_war.gd")
const Main := preload("res://main.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
var clock: Node

const MAN := {"age": 35, "aromantic": false, "attracted_to": ["zeny"], "group": "muzi"}
const WOMAN := {"age": 30, "aromantic": false, "attracted_to": ["muzi"], "group": "zeny"}


func _ready() -> void:
	watchdog_seconds = 110.0
	clock = get_node("/root/GameClock")
	clock.running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	if "--soak" in OS.get_cmdline_user_args():
		await _soak()
	else:
		_units()
		_fuzz()
		await _scene()
	clock.running = false
	finish("test_romance")


# ------------------------------------------------------------------ jednotky
func _units() -> void:
	section("Přitažlivost a dospělost (nezávislé na těle a jménu)")
	check(Romance.group_of("muz") == "muzi" and Romance.group_of("zena") == "zeny" and Romance.group_of("agender") == "nebinarni"
		and Romance.group_of("neuvedeno") == "" and Romance.group_of("xyz") == "", "genderová identita → skupina přitažlivosti")
	check(Romance.fits(MAN, WOMAN) and Romance.fits(WOMAN, MAN), "vzájemná shoda muž ↔ žena podle vyplněných preferencí")
	var lesbian := {"age": 28, "aromantic": false, "attracted_to": ["zeny"], "group": "zeny"}
	check(Romance.fits(lesbian, lesbian) and not Romance.fits(MAN, lesbian), "žena přitahovaná ženami: žena ano, muž ne")
	check(not Romance.fits(MAN, {"age": 30, "aromantic": true, "attracted_to": [], "group": "zeny"}), "aromantický cíl romantickou nabídku nepřijme")
	check(not Romance.fits({"age": 17, "group": "muzi"}, WOMAN) and not Romance.fits(MAN, {"age": 16, "attracted_to": [], "group": "zeny"}),
		"pod 18 let nikdy (pojistka pro poškozená data)")
	check(Romance.fits({"age": 40, "group": ""}, WOMAN), "neuvedená skupina žadatele není nesoulad")
	check(Romance.fits(MAN, {"age": 40, "attracted_to": [], "group": ""}), "prázdná množina přitažlivosti = neuvedeno, ne „nikdo“")
	check(Romance.fits({"age": 30, "group": "nebinarni"}, {"age": 30, "attracted_to": ["nebinarni", "zeny"], "group": "zeny"}),
		"nebinární žadatel u cíle přitahovaného nebinárními lidmi")

	section("Šance na „ano“")
	var lo := Romance.accept_p(-100.0, 0.0, -100.0)
	var hi := Romance.accept_p(100.0, 100.0, 100.0)
	check(lo >= 0.02 and hi <= 0.9 and lo < hi, "meze 0,02..0,90 (%.2f..%.2f)" % [lo, hi])
	check(Romance.accept_p(30.0, 50.0, 0.0) < Romance.accept_p(70.0, 50.0, 0.0), "lepší vztah → vyšší šance")
	check(Romance.accept_p(70.0, 50.0, -60.0) < Romance.accept_p(70.0, 50.0, 40.0), "špatná nálada šanci snižuje")
	var dist := {"yes": 0, "not_yet": 0, "no": 0}
	for i in 1000:
		var r = Romance.new()
		dist[r.resolve_ask("A", "B", MAN, WOMAN, 0.5, (float(i) + 0.5) / 1000.0, 0.0)] += 1
	check(dist["yes"] == 500 and abs(dist["not_yet"] - 175) <= 1 and abs(dist["no"] - 325) <= 1,
		"rozložení výsledků při p=0,5 odpovídá (ano %d / ještě ne %d / ne %d)" % [dist["yes"], dist["not_yet"], dist["no"]])

	section("Pozvání: stavový automat")
	var ro = Romance.new()
	check(ro.resolve_ask("A", "B", MAN, WOMAN, 0.9, 0.1, 100.0) == "yes", "ano → spolu chodí")
	check(ro.status("A", "B") == "dating" and ro.status("B", "A") == "dating", "stav dvojice nezávisí na pořadí")
	check(ro.partner_of("A") == "B" and ro.partner_of("B") == "A" and ro.partner_of("C") == "", "partner_of")
	check(ro.ask_block("A", "B", 200.0) == "already", "znovu pozvat vlastního partnera nejde")
	check(ro.ask_block("A", "C", 200.0) == "taken_self", "zadaný(á) nezačne jiný vztah (monogamní model)")
	check(ro.resolve_ask("C", "A", MAN, WOMAN, 0.9, 0.0, 200.0) == "taken" and ro.status("A", "C") == "", "zadaný cíl: „mám někoho“, nic nevznikne")
	check(ro.ask_block("A", "A", 0.0) == "self" and ro.resolve_ask("A", "A", MAN, MAN, 1.0, 0.0, 0.0) == "self", "sám se sebou ne")

	var nn = Romance.new()
	check(nn.resolve_ask("A", "B", MAN, WOMAN, 0.5, 0.6, 0.0) == "not_yet", "ještě ne")
	check(nn.ask_block("A", "B", 1000.0) == "not_now" and nn.ask_block("A", "B", 1441.0) == "", "po „ještě ne“ odstup 1 den")
	check(nn.ask_block("B", "A", 10.0) == "", "odstup platí jen pro toho, kdo se ptal")
	var no = Romance.new()
	check(no.resolve_ask("A", "B", MAN, WOMAN, 0.5, 0.99, 0.0) == "no", "ne")
	check(no.ask_block("A", "B", 4000.0) == "not_now" and no.ask_block("A", "B", 4321.0) == "", "po „ne“ odstup 3 dny")
	check(no.resolve_ask("A", "B", MAN, WOMAN, 0.5, 0.99, 4400.0) == "no", "druhé ne")
	check(no.noes("A", "B", 4400.0) == 2, "počítadlo odmítnutí (%d)" % no.noes("A", "B", 4400.0))
	check(no.resolve_ask("A", "B", MAN, WOMAN, 0.9, 0.0, 9000.0) == "pushy", "po 2× ne za 14 dní: „nedá si říct“ i při dobrém hodu")
	check(no.status("A", "B") == "", "dotírání vztah nezaloží")
	check(no.noes("A", "B", 9000.0 + 20160.0 + 5000.0) == 0, "po 14 dnech odmítnutí vyprší")
	no.tick([], 9000.0 + 20160.0 + 5000.0, 10.0, null)
	check(no.pairs.is_empty(), "záznam jen s prošlými odmítnutími se uklidí (limit dvojic se nezaplní)")
	var mis = Romance.new()
	check(mis.resolve_ask("A", "B", MAN, lesbian, 0.9, 0.0, 0.0) == "no", "nesoulad přitažlivosti = ne, bez ohledu na hod")

	section("Spokojenost (každý zvlášť)")
	var s = Romance.new()
	s.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	var a0: float = s.satisfaction("A", "B")
	s.note("A", "B", "chat", 10.0)
	check(s.satisfaction("A", "B") > a0 and s.satisfaction("B", "A") > a0, "příjemný rozhovor zvedá oběma")
	var a1: float = s.satisfaction("A", "B")
	var b1: float = s.satisfaction("B", "A")
	s.note("A", "B", "insult", 20.0)
	check(b1 - s.satisfaction("B", "A") > a1 - s.satisfaction("A", "B"), "urážka víc bolí uraženého než útočníka")
	s.note("A", "B", "stonewalling", 30.0)
	check(s.satisfaction("B", "A") < b1 - 0.12, "nátlak (stonewalling) se počítá jako nátlak")
	var fa = Romance.new()
	fa.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	for i in 50:
		fa.note("A", "B", "chat", 1.0 + i)  # spam rozhovorů během hodiny
	check(fa.satisfaction("A", "B") < Romance.SAT_START + 0.03, "spam rozhovorů nefarmí spokojenost (%.3f)" % fa.satisfaction("A", "B"))
	var tt := 0.0
	for i in 20:
		tt += 130.0
		fa.note("A", "B", "chat", tt)
	check(fa.satisfaction("A", "B") < 0.95 and fa.satisfaction("A", "B") > 0.8, "20 rozhovorů po 2 h: roste, ale rozhovory mají klesající výnos (%.3f, ne lineárně)" % fa.satisfaction("A", "B"))
	var before_arg: float = fa.satisfaction("A", "B")
	fa.note("A", "B", "argue", tt + 1.0)
	check(is_equal_approx(fa.satisfaction("A", "B"), before_arg - 0.05), "hádka se počítá vždy, i hned po rozhovoru")
	var outside = Romance.new()
	outside.note("A", "B", "argue", 0.0)
	check(outside.pairs.is_empty(), "mimo vztah note() nic nezakládá")

	section("Čas: zanedbávání, studená válka, závazek, vážný vztah")
	var tn = Romance.new()
	tn.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	var tc = Romance.new()
	tc.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	var cw = ColdWar.new()
	for i in 3:
		cw.note("A", "B", "argue", float(i))
	var t := 0.0
	while t < 10.0 * 1440.0:
		t += 10.0
		tn.tick([], t, 10.0, null)
		tc.tick([], t, 10.0, cw)
		cw.pairs[ColdWar.key("A", "B")]["stage"] = 2  # držet studenou válku pro srovnání
	check(tn.satisfaction("A", "B") < Romance.SAT_START, "bez kontaktu spokojenost klesá (%.2f)" % tn.satisfaction("A", "B"))
	check(tc.satisfaction("A", "B") < tn.satisfaction("A", "B") - 0.1, "studená válka ji sráží výrazně rychleji (%.2f vs %.2f)" % [tc.satisfaction("A", "B"), tn.satisfaction("A", "B")])
	check(tc.pairs[Romance.key("A", "B")]["low_since"].has("A"), "dlouhodobě nízká spokojenost se eviduje")
	check(tn.commitment("A", "B") > 0.1 and tn.commitment("A", "B") < 0.25, "závazek roste s časem (%.2f po 10 dnech)" % tn.commitment("A", "B"))
	var tp = Romance.new()
	tp.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	t = 0.0
	var promoted_at := -1.0
	while t < 20.0 * 1440.0:
		t += 10.0
		if int(t) % 720 == 0:
			tp.note("A", "B", "chat", t)
		tp.tick([], t, 10.0, null)
		if promoted_at < 0.0 and tp.status("A", "B") == "partners":
			promoted_at = t
	check(promoted_at >= 14.0 * 1440.0 and promoted_at < 15.0 * 1440.0, "spokojená dvojice je po 14 dnech „spolu vážně“ (%.1f dne)" % (promoted_at / 1440.0))
	check(tp.stats["became_partners"] == 1, "statistika vážných vztahů")
	check(tn.status("A", "B") == "dating", "nespokojená dvojice vážnou nezačne")

	section("Rozchod a ex")
	var bu = Romance.new()
	bu.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	check(bu.breakup("C", "D", 10.0).is_empty(), "rozchod s nikým = nic")
	var info: Dictionary = bu.breakup("A", "B", 5000.0)
	check(not info.is_empty() and String(info["status_before"]) == "dating" and is_equal_approx(float(info["days"]), 5000.0 / 1440.0), "rozchod vrací podklady pro následky")
	check(bu.status("A", "B") == "ex" and bu.partner_of("A") == "" and bu.stats["breakups"] == 1, "ex, nikdo s nikým")
	check(bu.breakup("A", "B", 5001.0).is_empty(), "dvakrát se rozejít nejde")
	check(bu.ask_block("B", "A", 5000.0 + 10079.0) == "not_now" and bu.ask_block("B", "A", 5000.0 + 10081.0) == "", "nové randění nejdřív po 7 dnech")
	check(is_equal_approx(bu.contact_weight("A", "B", "chat", 6000.0), Romance.EX_CONTACT) and bu.contact_weight("A", "B", "chat", 5000.0 + 20200.0) == 1.0,
		"čerstvý ex: méně kontaktu, po 14 dnech normál")
	check(bu.contact_weight("A", "B", "apologize", 6000.0) == 1.0, "omluva se vyhýbání netýká")
	var pc = Romance.new()
	pc.resolve_ask("A", "B", MAN, WOMAN, 1.0, 0.0, 0.0)
	check(is_equal_approx(pc.contact_weight("A", "B", "chat", 10.0), Romance.PARTNER_CONTACT) and pc.contact_weight("A", "C", "chat", 10.0) == 1.0,
		"s partnerem víc kontaktu, s ostatními beze změny")

	section("Ukládání")
	var rt = Romance.new()
	rt.from_dict(s.to_dict())
	check(JSON.stringify(rt.to_dict(), "", true) == JSON.stringify(s.to_dict(), "", true), "round-trip to_dict/from_dict beze ztráty")
	var rt2 = Romance.new()
	rt2.from_dict(bu.to_dict())
	check(rt2.status("A", "B") == "ex" and rt2.ask_block("B", "A", 6000.0) == "not_now", "ex a odstup přežijí uložení")
	rt.from_dict(null)
	check(rt.pairs.is_empty() and rt.stats["breakups"] == 0, "starý save bez sekce → čistý stav")


func _fuzz() -> void:
	section("Fuzz from_dict (nepřátelská data)")
	var bad := [
		1, "x", [], {"pairs": 5}, {"pairs": {"A|B": 7}}, {"pairs": {"A": {}}}, {"pairs": {"A|A": {"status": "dating"}}},
		{"pairs": {"A|B|C": {}}}, {"pairs": {"|B": {}}},
		{"pairs": {"A|B": {"status": "married", "sat": {"A": INF, "B": NAN, "Z": 0.5}, "commitment": 9.0, "since": NAN}}},
		{"pairs": {"A|B": {"status": 5, "asks": [["A", 1.0, "yes"], ["Z", 1.0, "no"], ["A", NAN, "no"], ["A", 1.0, "hack"], [1, 2], "x", ["A", 1.0, "no", 4]]}}},
		{"pairs": {"A|B": {"status": "dating", "low_since": {"A": "x", "B": INF}, "dumper": "Z", "last_breakup": "x"}}},
		{"stats": {"breakups": -9, "together_minutes": INF, "unknown": 5}, "last_ai_ask": {"": 1, "B": NAN, 5: 1}},
	]
	var huge := {}
	for i in 1000:
		huge["p%d|q%d" % [i, i]] = {"status": "dating", "sat": {}}
	bad.append({"pairs": huge})
	bad.append({"pairs": {"x".repeat(100) + "|B": {"status": "dating"}}})
	var many_asks: Array = []
	for i in 50:
		many_asks.append(["A", float(i), "no"])
	bad.append({"pairs": {"A|B": {"status": "", "asks": many_asks}}})
	var ok := true
	for d in bad:
		var ro = Romance.new()
		ro.from_dict(d)
		for k in ro.pairs:
			var r: Dictionary = ro.pairs[k]
			ok = ok and (String(r["status"]) == "" or String(r["status"]) in Romance.STATUSES)
			ok = ok and float(r["commitment"]) >= 0.0 and float(r["commitment"]) <= 1.0 and is_finite(float(r["since"]))
			ok = ok and (r["asks"] as Array).size() <= Romance.MAX_ASKS and (r["sat"] as Dictionary).size() <= 2
			for v in (r["sat"] as Dictionary).values():
				ok = ok and float(v) >= 0.0 and float(v) <= 1.0
			for v in (r["low_since"] as Dictionary).values():
				ok = ok and is_finite(float(v))
			for e in r["asks"]:
				ok = ok and is_finite(float(e[1])) and String(e[2]) in ["yes", "not_yet", "no", "taken", "pushy"]
		ok = ok and ro.pairs.size() <= Romance.MAX_PAIRS and int(ro.stats["breakups"]) >= 0 and is_finite(float(ro.stats["together_minutes"]))
		ro.tick([], 100.0, 10.0, null)  # po načtení nespadne ani krok
		ro.note("A", "B", "chat", 101.0)
	check(ok, "%d nepřátelských vstupů: bez pádu, v mezích (stav, spokojenost, časy, limity)" % bad.size())
	var r1 = Romance.new()
	r1.from_dict({"pairs": {"A|B": {"status": "married", "sat": {"A": INF}}}})
	check(r1.status("A", "B") == "" and r1.satisfaction("A", "B") == Romance.SAT_BASE, "neznámý stav a nesmyslná čísla zahozeny / nahrazeny výchozími")
	var r2 = Romance.new()
	r2.from_dict({"pairs": {"A|B": {"status": "dating"}, "A|C": {"status": "partners"}, "B|D": {"status": "dating"}}})
	var together := 0
	for k in r2.pairs:
		if String(r2.pairs[k]["status"]) in ["dating", "partners"]:
			together += 1
	check(together == 1 and r2.status("A", "B") == "dating" and r2.status("A", "C") == "ex" and r2.status("B", "D") == "ex",
		"poškozený save se souběžnými vztahy → monogamie vynucena deterministicky (podle klíče)")
	var r3 = Romance.new()
	r3.from_dict({"pairs": {"A|B": {"status": "dating", "dumper": "Z", "asks": [["Z", 1.0, "no"]]}}})
	check(String(r3.pairs["A|B"]["dumper"]) == "" and (r3.pairs["A|B"]["asks"] as Array).is_empty(), "cizí jména uvnitř záznamu zahozena")


# ------------------------------------------------------------------ scéna
func _world(seed: int, dir := "") -> Node:
	clock.total_minutes = 10.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "RomanceWorld%d" % seed
	var cfg := {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false, "clock": clock}
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


## Příkaz ke společenské akci se zahodí, když cíl zrovna nemůže do rozhovoru (stejně jako „Povídat si“).
## Test proto počká, až je cíl volný – nejde o obcházení pravidla, jen o deterministické načasování.
func _wait_free(tgt: Node, asker: Node, minutes: int = 240) -> bool:
	for i in minutes:
		if tgt.can_join_social(asker) and not tgt._is_sleeping():
			return true
		clock.advance(1.0)
	return false


func _wait_romance(sim: Node, minutes: int) -> bool:
	for i in minutes:
		clock.advance(1.0)
		if not sim.last_romance.is_empty():
			return true
	return false


func _scene() -> void:
	section("Scéna: profily z CharacterData")
	var w := _world(5, "user://test-romance-%d" % OS.get_process_id())
	var jana = _find(w, "Jana")    # žena, přitahují ji muži
	var petr = _find(w, "Petr")    # muž, přitahují ho ženy
	var eliska = _find(w, "Eliška")  # žena, přitahují ji ženy i muži
	check(jana != null and petr != null and eliska != null, "startovní domácnost (Jana, Petr, Eliška)")
	if jana == null or petr == null or eliska == null:
		return
	var ro = w.dynamics.romance
	check(jana.romance_group == "zeny" and petr.romance_group == "muzi", "skupina z genderové identity (ne z těla/jména)")
	check(Romance.fits(petr.romance_profile(), jana.romance_profile()) and not Romance.fits(eliska.romance_profile(), jana.romance_profile()),
		"Petr ↔ Jana sedí; Eliška Janu romanticky nezajímá (Jana: jen muži)")

	section("Příkaz hráče: Pozvat na rande – nesoulad přitažlivosti")
	for s in w.sims:
		s.global_position = Vector3(float(w.sims.find(s)) * 1.5, 0, 0)
	eliska.relationships[jana.sim_name] = 90.0
	jana.relationships[eliska.sim_name] = 90.0
	var ask: Dictionary = ActionLibrary.get_action("ask_out")
	check(_wait_free(jana, eliska), "Jana je volná")
	check(not ask.is_empty() and eliska.command(ask, jana), "příkaz přijat")
	check(_wait_romance(eliska, 300), "pokus proběhl")
	check(String(eliska.last_romance.get("outcome", "")) == "no" and ro.status(eliska.sim_name, jana.sim_name) == "",
		"i při skvělém vztahu: „ne“ (%s)" % str(eliska.last_romance))
	check(eliska.mood.has_moodlet("kosem_" + String(jana.name)), "košem bolí (moodlet)")
	for i in 40:
		clock.advance(1.0)

	section("Příkaz hráče: Pozvat na rande – Petr → Jana")
	petr.relationships[jana.sim_name] = 85.0
	jana.relationships[petr.sim_name] = 85.0
	jana.ledger.trust[petr.sim_name] = 80.0
	petr.last_romance = {}
	check(_wait_free(jana, petr), "Jana je volná")
	check(petr.command(ask, jana), "příkaz přijat")
	var tr: PackedStringArray = []
	var happened := false
	for i in 300:
		clock.advance(1.0)
		if i % 15 == 0:
			tr.append("%d:P st=%d id=%s q=%d | J st=%d id=%s sleep=%s" % [i, petr.state, str(petr.current_action.get("id", "")), petr.player_queue.size(), jana.state, str(jana.current_action.get("id", "")), str(jana._is_sleeping())])
		if not petr.last_romance.is_empty():
			happened = true
			break
	check(happened, "pokus proběhl", " | ".join(tr.slice(0, 20)))
	var oc := String(petr.last_romance.get("outcome", ""))
	var p_used := float(petr.last_romance.get("p", 0.0))
	check(oc in ["yes", "not_yet", "no"] and p_used > 0.5 and p_used <= 0.9, "výsledek %s, šance %.2f" % [oc, p_used])
	check((oc == "yes") == (ro.status(petr.sim_name, jana.sim_name) == "dating"), "stav odpovídá výsledku")
	if oc == "yes":
		check(jana.mood.has_moodlet("rande_" + String(petr.name)) and petr.mood.has_moodlet("rande_" + String(jana.name)), "radost u obou")
	else:
		# Pro další části scény potřebujeme dvojici: ustavit vztah přímo (výsledek pokusu už byl ověřen výše).
		ro.pairs.erase(Romance.key(petr.sim_name, jana.sim_name))
		check(ro.resolve_ask(petr.sim_name, jana.sim_name, petr.romance_profile(), jana.romance_profile(), 1.0, 0.0, clock.total_minutes) == "yes", "vztah ustaven přímo (hod nevyšel)")
	check(w.romance_status(petr, jana) == "dating" and w.romance_ask_block(eliska, petr) == "" and w.romance_ask_block(petr, eliska) == "taken_self",
		"main.romance_status / romance_ask_block")
	for i in 40:
		clock.advance(1.0)

	section("Zadaný cíl")
	eliska.last_romance = {}
	eliska.relationships[petr.sim_name] = 90.0
	ro.pairs[Romance.key(eliska.sim_name, jana.sim_name)]["asks"] = []  # odstup po předchozím „ne“ netýká se Petra
	check(_wait_free(petr, eliska), "Petr je volný")
	check(eliska.command(ask, petr), "příkaz přijat")
	check(_wait_romance(eliska, 300) and String(eliska.last_romance.get("outcome", "")) == "taken", "„mám někoho“ (%s)" % str(eliska.last_romance))
	check(ro.partner_of(petr.sim_name) == jana.sim_name, "vztah Petr–Jana trvá")
	for i in 40:
		clock.advance(1.0)

	section("Server (handle_command) – validace")
	var net = w.get("net")
	check(net != null and net.has_method("handle_command"), "NetSession v offline světě")
	if net != null:
		check(net.handle_command(1, String(eliska.name), "break_up", String(jana.name)) != "", "rozchod s někým, s kým nechodí → odmítnuto")
		check(net.handle_command(1, String(petr.name), "ask_out", String(jana.name)) != "", "pozvat vlastní partnerku → odmítnuto")
		check(net.handle_command(1, String(petr.name), "ask_out", String(eliska.name)) != "", "zadaný(á) nezve jiné (monogamní model) → odmítnuto")
		check(net.handle_command(1, String(petr.name), "ask_out", String(petr.name)) != "", "sám sebe → odmítnuto")
		var rej_ok: String = net.handle_command(1, String(petr.name), "break_up", String(jana.name))
		check(rej_ok == "", "rozchod s vlastní partnerkou přijat (%s)" % rej_ok)
		petr.command({"id": "cancel"}, null)

	section("AI: chuť pozvat / rozejít se")
	var now := float(clock.total_minutes)
	var rk := Romance.key(petr.sim_name, jana.sim_name)
	ro.pairs[rk]["sat"][petr.sim_name] = 0.1
	ro.pairs[rk]["sat"][jana.sim_name] = 0.8
	ro.pairs[rk]["low_since"] = {petr.sim_name: now - 2000.0}
	ro.pairs[rk]["commitment"] = 0.5
	check(ro.ai_breakup_score(petr, jana, 1.0, now) > 0.0 and ro.ai_breakup_score(jana, petr, 1.0, now) == 0.0,
		"rozejít se chce jen ten nespokojený (%.2f)" % ro.ai_breakup_score(petr, jana, 1.0, now))
	ro.pairs[rk]["low_since"] = {petr.sim_name: now - 100.0}
	check(ro.ai_breakup_score(petr, jana, 1.0, now) == 0.0, "první den nízké spokojenosti se nikdo nerozchází")
	ro.pairs[rk]["low_since"] = {petr.sim_name: now - 2000.0}
	check(ro.ai_ask_score(jana, eliska, 1.0, now) == 0.0, "AI zadaná nezve")
	check(ro.ai_ask_score(eliska, jana, 1.0, now) == 0.0, "AI nezve zadané ani bez vzájemné přitažlivosti")
	# Zpět „spokojený“ Petr, ať se AI nerozejde dřív než příkaz hráče (rozchod níže je hráčova volba).
	ro.pairs[rk]["sat"][petr.sim_name] = 0.6
	ro.pairs[rk]["low_since"] = {}

	section("Příkaz hráče: Rozejít se")
	var rel_before: float = float(jana.relationships.get(petr.sim_name, 0.0))
	var grudge_before: float = jana.ledger.grudge(petr.sim_name)
	petr.last_romance = {}
	check(_wait_free(jana, petr), "Jana je volná")
	check(petr.command(ActionLibrary.get_action("break_up"), jana), "příkaz přijat")
	check(_wait_romance(petr, 300), "rozchod proběhl")
	var reaction := String(petr.last_romance.get("outcome", ""))
	check(reaction in ["hurt", "angry"], "spokojenou partnerku to zasáhne (%s, bolest %.2f)" % [reaction, float(petr.last_romance.get("hurt", 0.0))])
	check(ro.status(petr.sim_name, jana.sim_name) == "ex", "teď jsou ex")
	check(jana.mood.has_moodlet("rozchod_" + String(petr.name)) and not jana.mood.has_moodlet("rande_" + String(petr.name)), "zlomené srdce místo radosti")
	check(float(jana.relationships.get(petr.sim_name, 0.0)) < rel_before - 10.0, "vztah k Petrovi klesl (%.1f → %.1f)" % [rel_before, float(jana.relationships.get(petr.sim_name, 0.0))])
	check(jana.ledger.grudge(petr.sim_name) > grudge_before, "zášť roste")
	check(petr.mood.has_moodlet("rozchod_" + String(jana.name)) and petr.ledger.guilt_of(jana.sim_name) > 0.0, "ani tomu, kdo končí, to není jedno (smutek, vina)")
	check(w.dynamics.cold_war.heat(petr.sim_name, jana.sim_name) > 0.2, "pod jednou střechou po rozchodu dusno (žár %.2f)" % w.dynamics.cold_war.heat(petr.sim_name, jana.sim_name))
	check(int(w.dynamics.stats["talks"]) >= 1, "rozhovory se počítají do statistik domácnosti")

	section("Ex v jedné místnosti")
	jana.global_position = Vector3(0, 0, 0)
	petr.global_position = Vector3(2, 0, 0)
	if not jana._is_sleeping() and not petr._is_sleeping():
		var sj: float = jana.mental.stress
		ro.tick(w.sims, float(clock.total_minutes), 10.0, w.dynamics.cold_war)
		check(jana.mood.has_moodlet("ex_" + String(petr.name)) and jana.mental.stress >= sj, "trapas s ex")
	petr.global_position = Vector3(40, 0, 0)

	section("AI: nová pozvánka po rozchodu")
	var now3 := float(clock.total_minutes)
	petr.relationships[eliska.sim_name] = 80.0
	petr.ledger.trust[eliska.sim_name] = 70.0
	check(not ro._last_ai_ask.has(petr.sim_name), "hráčův příkaz nespotřebuje odstup AI pozvánek")
	ro.note_ai_ask(petr.sim_name, now3 - 60.0)
	check(ro.ai_ask_score(petr, eliska, 1.0, now3) == 0.0, "po vlastní nedávné AI pozvánce 3 dny nic")
	ro._last_ai_ask.erase(petr.sim_name)
	var sc_e: float = ro.ai_ask_score(petr, eliska, 1.0, now3)
	check(sc_e > 0.0, "volný Petr s dobrým vztahem a vzájemnou přitažlivostí: AI uvažuje o pozvání (%.2f)" % sc_e)
	check(ro.ai_ask_score(petr, jana, 1.0, now3) == 0.0, "čerstvou ex AI znovu nezve")
	var net2 = w.get("net")
	check(net2.owner_peer_of(String(eliska.name)) == 0 and not eliska.romance_owned_by_player(), "offline: postavy nikomu „nepatří“")
	var old_mode: int = net2.mode
	var old_players: Dictionary = net2.players
	net2.mode = 1  # HOST (bez síťového provozu – jen čtení vlastnictví)
	net2.players = {7: {"sim": String(eliska.name)}}
	check(net2.owner_peer_of(String(eliska.name)) == 7 and eliska.romance_owned_by_player() and ro.ai_ask_score(petr, eliska, 1.0, now3) == 0.0,
		"v MP AI nezve postavu jiného hráče (odpověděla by za něj)")
	net2.mode = old_mode
	net2.players = old_players
	petr.ledger.trust[eliska.sim_name] = 30.0
	check(ro.ai_ask_score(petr, eliska, 1.0, now3) == 0.0, "bez důvěry AI nezve")

	section("Uložení hry")
	var pn := String(petr.sim_name)
	var jn := String(jana.sim_name)
	var snap: Dictionary = ro.to_dict()
	var res: Dictionary = w.save_game("manual")
	check(res.get("ok", false), "save ok", str(res))
	ro.pairs.clear()
	var ld: Dictionary = w.load_game("manual")
	check(ld.get("ok", false), "load ok", str(ld))
	var ro_l = w.dynamics.romance
	check(ro_l.status(pn, jn) == "ex", "ex obnoveni z uložení")
	check(JSON.stringify(ro_l.to_dict(), "", true) == JSON.stringify(snap, "", true), "stav Romance po načtení = stav při uložení")
	w.queue_free()
	await get_tree().process_frame

	section("Výkon")
	var big = Romance.new()
	for i in 60:
		var a := "s%d" % (2 * i)
		var b := "s%d" % (2 * i + 1)
		big.resolve_ask(a, b, MAN, WOMAN, 1.0, 0.0, 0.0)
	for i in 120:
		big.resolve_ask("x%d" % i, "y%d" % i, MAN, WOMAN, 0.0, 0.99, 0.0)
	var t0 := Time.get_ticks_usec()
	for k in 100:
		big.tick([], 10.0 + k * 10.0, 10.0, null)
	var per := float(Time.get_ticks_usec() - t0) / 100.0
	check(per < 2000.0, "tick 180 dvojic: %.0f µs/krok (< 2 ms)" % per)


# ------------------------------------------------------------------ dlouhý běh
func _soak_run(seed: int, days: int, warm := false) -> Dictionary:
	var w := _world(seed)
	if warm:
		# Řízený scénář: Petr a Eliška (vzájemná přitažlivost) mají od začátku blízko k sobě.
		var pe = _find(w, "Petr")
		var el = _find(w, "Eliška")
		for pr in [[pe, el], [el, pe]]:
			pr[0].relationships[pr[1].sim_name] = 72.0
			pr[0].ledger.trust[pr[1].sim_name] = 72.0
	for m in days * 720:
		clock.advance(2.0)
	var ro = w.dynamics.romance
	var rels: PackedStringArray = []
	for x in w.sims:
		for y in w.sims:
			if x != y:
				rels.append("%s→%s rel=%.0f trust=%.0f" % [x.first_name(), y.first_name(), float(x.relationships.get(y.sim_name, 0.0)), x.ledger.trust_in(y.sim_name)])
	print("REL seed=%d %s" % [seed, ", ".join(rels)])
	var out := {"stats": ro.stats.duplicate(true), "summary": ro.summary(float(clock.total_minutes)),
		"sig": JSON.stringify(ro.to_dict(), "", true) + JSON.stringify(w.dynamics.stats, "", true),
		"talks": int(w.dynamics.stats["talks"]), "argues": int(w.dynamics.stats["argues"]), "n": w.sims.size()}
	w.queue_free()
	await get_tree().process_frame
	return out


func _soak() -> void:
	section("Dlouhý běh: 3 seedy × 10 dní")
	var tot := {"asked": 0, "yes": 0, "no": 0, "pushy": 0, "breakups": 0, "talks": 0, "argues": 0}
	for seed in [1, 3, 7]:
		var r: Dictionary = await _soak_run(seed, 10)
		print("SOAK seed=%d n=%d talks=%d argues=%d stats=%s pairs=%s" % [seed, r["n"], r["talks"], r["argues"], str(r["stats"]), str(r["summary"])])
		for k in ["asked", "yes", "no", "pushy", "breakups"]:
			tot[k] += int(r["stats"][k])
		tot["talks"] += r["talks"]
		tot["argues"] += r["argues"]
	print("SOAK TOTAL %s" % str(tot))
	check(tot["talks"] > 60, "domácnosti spolu opravdu žijí")
	check(tot["pushy"] == 0, "AI nikdy nedotírá po odmítnutí")
	check(tot["asked"] <= 3 * 4 * 4, "AI nezve každou chvíli (%d pozvání za 30 dní domácností)" % tot["asked"])
	check(float(tot["argues"]) / maxf(1.0, float(tot["talks"])) < 0.45, "podíl hádek drží pod 45 %")
	section("Řízený scénář: blízká dvojice se vzájemnou přitažlivostí (3 seedy × 10 dní)")
	var wt := {"asked": 0, "yes": 0, "not_yet": 0, "no": 0, "taken": 0, "pushy": 0, "breakups": 0, "became_partners": 0}
	for seed in [1, 3, 7]:
		var r2: Dictionary = await _soak_run(seed, 10, true)
		print("WARM seed=%d talks=%d argues=%d stats=%s pairs=%s" % [seed, r2["talks"], r2["argues"], str(r2["stats"]), str(r2["summary"])])
		for k in wt:
			wt[k] += int(r2["stats"][k])
	print("WARM TOTAL %s" % str(wt))
	check(wt["asked"] >= 2, "AI se sama odhodlá pozvat (%d× ve 3 bězích)" % wt["asked"])
	check(wt["pushy"] == 0, "ani v blízké dvojici AI po „ne“ nedotírá")
	check(wt["asked"] == wt["yes"] + wt["not_yet"] + wt["no"] + wt["taken"], "každé pozvání má právě jeden výsledek")
	check(wt["asked"] <= 3 * 4, "AI nezve víc než jednou za 3 dny (%d)" % wt["asked"])
	section("Determinismus")
	var x: Dictionary = await _soak_run(3, 3)
	var y: Dictionary = await _soak_run(3, 3)
	check(x["sig"] == y["sig"], "stejný seed → stejný stav vztahů i statistiky")
