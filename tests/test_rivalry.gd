extends "res://tests/test_base.gd"
## Rivalry (scripts/sim/rivalry.gd): rivalita, pomluva jako zbraň, obrana posluchače, odhalení, usmíření,
## manipulace s obranou (SocialPressure), ukládání (striktní snapshot + tolerantní načtení), server, AI, HUD.
## Spuštění: godot_run scene=res://tests/test_rivalry.tscn
const Rivalry := preload("res://scripts/sim/rivalry.gd")
const RivalryPressure := preload("res://scripts/sim/rivalry_pressure.gd")
const Romance := preload("res://scripts/sim/romance.gd")
const GossipNetwork := preload("res://scripts/sim/gossip_network.gd")
const SocialPressure := preload("res://scripts/sim/social_pressure.gd")
const Main := preload("res://main.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
var clock: Node


func _ready() -> void:
	watchdog_seconds = 115.0
	clock = get_node("/root/GameClock")
	clock.running = false
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	_units()
	_persistence()
	_gossip_units()
	await _scene()
	clock.running = false
	finish("test_rivalry")


# ------------------------------------------------------------------ jednotky
func _units() -> void:
	section("Rivalita: skládání, arény, vyhasínání")
	var rv = Rivalry.new()
	check(rv.heat("A", "B", 0.0) == 0.0 and rv.top_rival("A", 0.0) == "", "prázdný stav: žádný sok")
	var h1: float = rv.feel("A", "B", "status", 0.3, 100.0)
	check(is_equal_approx(h1, 0.3), "první přírůstek = hodnota (%.3f)" % h1)
	var h2: float = rv.feel("A", "B", "status", 0.3, 100.0)
	check(is_equal_approx(h2, 0.51), "skládání s klesajícím výnosem 1-(0,7·0,7) (%.3f)" % h2)
	check(rv.heat("B", "A", 100.0) == 0.0, "rivalita je směrovaná (B o tom nemusí vědět)")
	rv.feel("A", "B", "love", 0.5, 100.0)
	var hc: float = rv.heat("A", "B", 100.0)
	check(is_equal_approx(hc, 1.0 - (1.0 - 0.51) * 0.5), "celek = 1-(1-love)(1-status) (%.3f)" % hc)
	check(rv.main_arena("A", "B", 100.0) == "status", "hlavní aréna = silnější (status 0,51 > love 0,5)")
	var later: float = rv.heat("A", "B", 100.0 + 21.0 * 1440.0)
	check(later < hc * 0.5, "bez přiživování vyhasíná (%.3f → %.3f za 21 dní)" % [hc, later])
	check(rv.arena("A", "B", "love", 100.0 + 14.0 * 1440.0) < rv.arena("A", "B", "status", 100.0 + 14.0 * 1440.0),
		"láska vyhasíná rychleji než postavení (τ 14 vs 21 dní)")
	check(is_equal_approx(rv.heat("A", "B", 50.0), hc), "zpětný čas (rewind) rivalitu nezesílí ani nevymaže")
	check(rv.feel("A", "A", "status", 0.5, 100.0) == 0.0 and not rv.rivals.has("A>A"), "sám sobě sokem ne")
	check(rv.feel("A", "C", "work", 0.5, 100.0) == 0.0 and not rv.rivals.has("A>C"), "neznámá aréna se ignoruje")
	check(rv.feel("A>X", "C", "status", 0.5, 100.0) == 0.0, "jméno s oddělovačem se odmítne")
	rv.feel("A", "C", "status", NAN, 100.0)
	check(rv.heat("A", "C", 100.0) == 0.0, "NaN přírůstek nic nepřidá")
	rv.feel("A", "C", "status", 0.2, 100.0)
	check(rv.top_rival("A", 100.0) == "B", "nejsilnější sok = B")
	check(rv.top_rival("A", 100.0, "B") == "", "C pod prahem %.2f → po vyloučení B nikdo" % Rivalry.RIVAL_MIN)
	rv.feel("A", "C", "status", 0.5, 100.0)
	check(rv.top_rival("A", 100.0, "B") == "C", "po vyloučení posluchače B je sokem C")
	var lst: Array = rv.rivals_of("A", 100.0)
	check(lst.size() == 2 and String(lst[0]["name"]) == "B", "seznam soků seřazený (%s)" % str(lst))

	section("Zdroje rivality")
	var rc = Rivalry.new()
	rc.on_conflict("X", "Y", 50.0, -20.0, 10.0)
	check(rc.heat("X", "Y", 10.0) == 0.0 and rc.heat("Y", "X", 10.0) > 0.0, "hádka živí rivalitu jen tam, kde je vztah špatný")
	rc.on_lover_revealed("P", "L", 10.0)
	check(is_equal_approx(rc.arena("P", "L", "love", 10.0), Rivalry.LOVER_REVEALED), "milenec partnera = sok v lásce")
	rc.on_slander_exposed("V", "S", 10.0)
	check(is_equal_approx(rc.arena("V", "S", "status", 10.0), Rivalry.SLANDER_EXPOSED), "odhalený pomlouvač = sok o postavení")
	check(Rivalry.love_interest(30.0, 0.1) == 0.0, "bez vztahu nad prahem a bez jiskry žádný zájem")
	check(Rivalry.love_interest(45.0, 0.0) > 0.3 and Rivalry.love_interest(100.0, 0.0) == 1.0, "zájem roste se vztahem")
	check(Rivalry.love_interest(0.0, 0.5) > 0.0, "jiskra (Infidelity) stačí i bez vztahu")

	section("Pomluva: brány")
	var rs = Rivalry.new()
	check(String(rs.slander_block("A", "A", 0.0)["block"]) == "self", "sám sobě ne")
	check(String(rs.slander_block("A", "L", 0.0)["block"]) == "no_rival", "bez soka ne")
	rs.feel("A", "B", "status", 0.6, 0.0)
	var sb: Dictionary = rs.slander_block("A", "L", 0.0)
	check(String(sb["block"]) == "" and String(sb["rival"]) == "B", "se sokem ano, soka vybírá systém (B)")
	check(String(rs.slander_block("A", "B", 0.0)["block"]) == "no_rival", "sokovi samotnému se ho pomlouvat nedá")
	rs.note_slander("A", "L", "B", "doubted", 0.0)
	check(String(rs.slander_block("A", "M", 60.0)["block"]) == "not_now", "odstup %d min mezi pomluvami jednoho autora" % int(Rivalry.SLANDER_GAP))
	check(String(rs.slander_block("A", "M", 130.0)["block"]) == "", "po odstupu jinému posluchači ano")
	check(String(rs.slander_block("A", "L", 130.0)["block"]) == "repeat", "stejnému posluchači o stejném sokovi nejvýš 1× denně")
	check(String(rs.slander_block("A", "L", 1500.0)["block"]) == "", "další den znovu")
	check(rs.heat("A", "B", 0.0) > 0.6, "kdo pomlouvá, rivalitu v sobě sám živí")
	check(int(rs.stats["slanders"]) == 1 and int(rs.stats["doubted"]) == 1, "statistika pomluv")
	rs.note_slander("A", "L", "B", "nonsense", 2000.0)
	check(int(rs.stats["slanders"]) == 1, "neznámý výsledek se nezapíše")

	section("Reakce posluchače (obrana = hranice + podpora oběti + protidůkaz)")
	var honest_friend: Dictionary = Rivalry.listener_inputs(10.0, 80.0, 90.0, 0.95)
	var gullible_foe: Dictionary = Rivalry.listener_inputs(70.0, -40.0, 15.0, 0.1)
	var r1: Dictionary = Rivalry.listener_reaction(0.8, honest_friend)
	var r2: Dictionary = Rivalry.listener_reaction(0.8, gullible_foe)
	check(String(r1["outcome"]) == "saw_through", "poctivý přítel oběti pomluvu prokoukne (obrana %.2f)" % float(r1["defense"]))
	check(String(r2["outcome"]) == "swayed", "nepoctivý, sokovi nepřející a autorovi věřící posluchač uvěří (dopad %.2f)" % float(r2["impact"]))
	check(float(r1["defense"]) > float(r2["defense"]) and float(r1["impact"]) < float(r2["impact"]), "obrana snižuje dopad")
	check(String(Rivalry.listener_reaction(0.0, gullible_foe)["outcome"]) == "saw_through", "bez rivality žádný tlak")
	var mid: Dictionary = Rivalry.listener_reaction(0.6, Rivalry.listener_inputs(20.0, 10.0, 50.0, 0.5))
	check(String(mid["outcome"]) in Rivalry.SLANDER_OUTCOMES, "výsledek vždy z povolené množiny (%s)" % String(mid["outcome"]))
	var all_fin := true
	for i in 200:
		var inp: Dictionary = Rivalry.listener_inputs(randf_range(-300, 300), randf_range(-300, 300), randf_range(-50, 200), randf_range(-2, 3))
		var rr: Dictionary = Rivalry.listener_reaction(randf_range(-1, 2), inp)
		for k in ["attempt", "defense", "impact"]:
			if not is_finite(float(rr[k])) or float(rr[k]) < 0.0 or float(rr[k]) > 1.0:
				all_fin = false
		for k2 in inp:
			if float(inp[k2]) < 0.0 or float(inp[k2]) > 1.0:
				all_fin = false
	var nan_inp: Dictionary = Rivalry.listener_inputs(NAN, INF, -INF, NAN)
	check(all_fin and is_finite(float(nan_inp["credibility"])) and is_finite(float(nan_inp["evidence"])),
		"vstupy a reakce vždy konečné v 0..1 (200 náhodných + NaN/INF)")
	check(Rivalry.report_p(honest_friend) > Rivalry.report_p(gullible_foe) and Rivalry.report_p(honest_friend) <= 0.95,
		"přítel oběti to spíš donese (%.2f vs %.2f)" % [Rivalry.report_p(honest_friend), Rivalry.report_p(gullible_foe)])

	section("Usmíření")
	var rh = Rivalry.new()
	check(rh.hatchet_block("A", "B", 0.0) == "no_rivalry", "bez rivality není co zakopávat")
	rh.feel("A", "B", "status", 0.6, 0.0)
	rh.feel("B", "A", "love", 0.5, 0.0)
	check(rh.hatchet_block("B", "A", 0.0) == "", "usmíření může nabídnout kterákoli strana")
	check(Rivalry.hatchet_p(0.9, -1.0, -80.0, 0.0) >= 0.05 and Rivalry.hatchet_p(0.0, 1.0, 100.0, 1.0) <= 0.9, "šance v mezích")
	check(Rivalry.hatchet_p(0.2, 0.5, 30.0, 0.8) > Rivalry.hatchet_p(0.9, -0.5, -30.0, 0.2), "smířlivý vztah > zahořklý")
	check(rh.resolve_hatchet("A", "B", 0.3, 0.9, 10.0) == "refused", "hod nad šancí: odmítnuto")
	check(rh.hatchet_block("A", "B", 100.0) == "not_now" and rh.hatchet_block("B", "A", 100.0) == "not_now", "po odmítnutí 2 dny klid (obě strany)")
	var before_ab: float = rh.heat("A", "B", 3000.0)
	check(rh.resolve_hatchet("A", "B", 0.6, 0.1, 3000.0) == "accepted", "přijato")
	check(rh.heat("A", "B", 3000.0) < before_ab * 0.4 and rh.heat("B", "A", 3000.0) < 0.5 * 0.4, "rivalita obou směrů opadla")
	check(rh.respect("A", "B") > 0.0 and rh.respect("B", "A") > 0.0, "přibyl respekt")
	var rh2 = Rivalry.new()
	rh2.feel("A", "B", "status", 0.3, 0.0)
	var plain: float = rh2.arena("A", "B", "status", 0.0)
	var st0: float = rh.arena("A", "B", "status", 6000.0)
	rh.feel("A", "B", "status", 0.3, 6000.0)
	var with_respect: float = (rh.arena("A", "B", "status", 6000.0) - st0) / maxf(1.0 - st0, 1.0e-6)
	check(with_respect < plain - 1.0e-6, "respekt tlumí další přírůstky (%.3f < %.3f)" % [with_respect, plain])

	section("Limity")
	var rl = Rivalry.new()
	for i in 400:
		rl.feel("N%d" % i, "M%d" % (i % 7), "status", 0.1 + 0.001 * float(i), 0.0)
	check(rl.rivals.size() <= Rivalry.MAX_RIVALS, "počet záznamů omezen (%d)" % rl.rivals.size())
	check(rl.rivals.has("N399>M0"), "nový silnější záznam vytlačí nejslabší (ne zahodí se)")
	for i in 400:
		rl.note_slander("N%d" % (i % 300), "L%d" % i, "M%d" % (i % 7), "doubted", float(i))
	check(rl.told.size() <= Rivalry.MAX_TOLD, "seznam „komu co řekl“ omezen (%d)" % rl.told.size())


func _persistence() -> void:
	section("Ukládání: striktní snapshot, tolerantní načtení, verze")
	var rv = Rivalry.new()
	rv.feel("Ana Malá", "Bára Velká", "love", 0.4, 100.0)
	rv.feel("Bára Velká", "Ana Malá", "status", 0.3, 120.0)
	rv.note_slander("Ana Malá", "Cyril", "Bára Velká", "swayed", 130.0)
	rv.note_ai("Ana Malá", "slander", 130.0)
	rv.resolve_hatchet("Bára Velká", "Ana Malá", 0.1, 0.9, 140.0)
	var d: Dictionary = rv.to_dict()
	check(Rivalry.validate_snapshot(d), "vlastní snapshot projde striktní kontrolou")
	var j = JSON.parse_string(JSON.stringify(d))
	# JSON převádí int verzi na float → striktní kontrola ji odmítne; načtení ji přijme (tolerantní).
	check(not Rivalry.validate_snapshot(j), "striktní kontrola vyžaduje int verzi (JSON float → ne)")
	var rv2 = Rivalry.new()
	rv2.from_dict(j)
	check(rv2.load_note == "", "načtení z JSON bez poznámky")
	check(is_equal_approx(rv2.heat("Ana Malá", "Bára Velká", 200.0), rv.heat("Ana Malá", "Bára Velká", 200.0))
		and is_equal_approx(rv2.heat("Bára Velká", "Ana Malá", 200.0), rv.heat("Bára Velká", "Ana Malá", 200.0)), "rivalita přežije JSON round-trip")
	check(String(rv2.slander_block("Ana Malá", "Cyril", 300.0)["block"]) == "repeat", "„komu co řekl“ přežije uložení")
	check(rv2.hatchet_block("Ana Malá", "Bára Velká", 200.0) == "not_now", "odstup po odmítnutém usmíření přežije uložení")
	check(rv2._ai_recent("Ana Malá", "slander", Rivalry.AI_SLANDER_EVERY, 200.0), "odstup AI přežije uložení")
	check(int(rv2.stats["slanders"]) == 1 and int(rv2.stats["refused"]) == 1, "statistiky přežijí uložení")
	check(Rivalry.validate_snapshot(rv2.to_dict()), "po načtení je snapshot zase striktně platný")

	var bad := [
		[null, "null"], [[], "pole"], [{"version": 1}, "chybí klíče"],
		[_mo(d, {"extra": 1}, true), "klíč navíc"], [_mo(d, {"version": 2}, true), "budoucí verze"],
		[_mo(d, {"version": 1.0}, true), "verze jako float"],
		[_mo(d, {"rivals": {"A>A": d["rivals"].values()[0]}}), "sok sám sobě"],
		[_mo(d, {"rivals": {"A>B>C": d["rivals"].values()[0]}}), "špatný klíč"],
		[_mo(d, {"rivals": {"A>B": _mo(d["rivals"].values()[0], {"love": 1.5})}}), "love mimo rozsah"],
		[_mo(d, {"rivals": {"A>B": _mo(d["rivals"].values()[0], {"status": NAN})}}), "NaN"],
		[_mo(d, {"rivals": {"A>B": _mo(d["rivals"].values()[0], {"t": INF})}}), "INF čas"],
		[_mo(d, {"rivals": {"A>B": _mo(d["rivals"].values()[0], {"hack": 1})}}), "pole navíc v záznamu"],
		[_mo(d, {"rivals": {"A>B": "x"}}), "záznam není slovník"],
		[_mo(d, {"told": {"A>B": 1.0}}), "told se 2 jmény"],
		[_mo(d, {"last_ai": {"A": {"slander": 1.0}}}), "last_ai neúplné"],
		[_mo(d, {"stats": {"cheats": 5}}), "neznámá statistika"],
		[_mo(d, {"stats": {"slanders": -1}}), "záporná statistika"],
		[_mo(d, {"last_scan": "včera"}, true), "last_scan text"],
	]
	var rejected := 0
	for b in bad:
		if not Rivalry.validate_snapshot(b[0]):
			rejected += 1
		else:
			print("    (prošlo, nemělo: %s)" % b[1])
	check(rejected == bad.size(), "striktní kontrola odmítne všech %d vadných variant (%d)" % [bad.size(), rejected])
	var big := {}
	for i in Rivalry.MAX_RIVALS + 1:
		big["A%d>B" % i] = {"love": 0.1, "status": 0.1, "t": 0.0, "respect": 0.0, "last_slander": 0.0, "last_hatchet": 0.0}
	check(not Rivalry.validate_snapshot(_mo(d, {"rivals": big}, true)), "příliš mnoho záznamů → odmítnuto")

	var rf = Rivalry.new()
	rf.from_dict(_mo(d, {"version": 99}, true))
	check(rf.rivals.is_empty() and rf.load_note == "future_version", "snapshot budoucí verze se zahodí celý (load_note)")
	rf.from_dict({})
	check(rf.rivals.is_empty() and rf.load_note == "", "starý save bez sekce = žádní soci")
	rf.from_dict({"rivals": d["rivals"]})
	check(rf.rivals.is_empty() and rf.load_note == "legacy_unversioned", "sekce bez verze se nečte (žádný starší formát neexistoval)")
	rf.from_dict("hack")
	check(rf.rivals.is_empty() and rf.load_note == "type", "nesmyslný typ → prázdné")
	var mixed: Dictionary = d.duplicate(true)
	mixed["rivals"]["Ok>Fine"] = {"love": 2.0, "status": -1.0, "t": NAN, "respect": "x", "last_slander": INF, "last_hatchet": 5}
	mixed["rivals"]["Bad>Bad"] = {"love": 0.5}
	mixed["rivals"][7] = {"love": 0.5}
	mixed["told"]["a>b"] = 1.0
	mixed["stats"]["slanders"] = NAN
	rf.from_dict(mixed)
	var okr: Dictionary = rf.rivals.get("Ok>Fine", {})
	check(not okr.is_empty() and float(okr["love"]) == 1.0 and float(okr["status"]) == 0.0 and float(okr["t"]) == 0.0
		and float(okr["respect"]) == 0.0 and float(okr["last_slander"]) == -1.0e9, "vadné hodnoty se sevřou / nahradí výchozími")
	check(not rf.rivals.has("Bad>Bad") and not rf.told.has("a>b") and int(rf.stats["slanders"]) == 0, "nesmyslné záznamy zahozeny")
	check(Rivalry.validate_snapshot(rf.to_dict()), "po tolerantním načtení je snapshot striktně platný")
	var fuzz_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var junk := [NAN, INF, -INF, -5.0, 0.5, 1e20, "x", null, [], {}, true, 3]
	for i in 300:
		var fd := {"version": [1, 1.0, 0, 2, "1", null][rng.randi() % 6], "rivals": {}, "told": {}, "last_ai": {},
			"last_scan": junk[rng.randi() % junk.size()], "stats": {"slanders": junk[rng.randi() % junk.size()]}}
		for k in rng.randi() % 12:
			var nm: String = "N%d>M%d" % [rng.randi() % 5, rng.randi() % 5] if rng.randf() < 0.8 else ["", ">", "a>b>c", "x".repeat(80) + ">y"][rng.randi() % 4]
			fd["rivals"][nm] = {"love": junk[rng.randi() % junk.size()], "status": junk[rng.randi() % junk.size()],
				"t": junk[rng.randi() % junk.size()], "respect": junk[rng.randi() % junk.size()]}
		var rz = Rivalry.new()
		rz.from_dict(fd)
		if rz.rivals.size() > Rivalry.MAX_RIVALS or not Rivalry.validate_snapshot(rz.to_dict()):
			fuzz_ok = false
		for k2 in rz.rivals:
			if not is_finite(rz.heat(String(k2).split(">")[0], String(k2).split(">")[1], 0.0)):
				fuzz_ok = false
	check(fuzz_ok, "fuzz 300 poškozených savů: nikdy nespadne, výsledek vždy striktně platný a konečný")


func _gossip_units() -> void:
	section("GossipNetwork.slander: zbraň z pravdy, výmysl, pochybnost, odhalení")
	var g = GossipNetwork.new(7)
	var content := {"mental_health": true, "addiction": true}
	var teller := {"key": "t", "honesty": 0.1, "extraversion": 0.5, "rel": {"s": -50.0}, "grudge": {"s": 40.0}}
	var fan := {"key": "l", "honesty": 0.5, "rel": {"s": 60.0, "t": 30.0}, "stigma": 0.5}
	var ev1: Array = g.slander(teller, fan, "s", 10.0, content)
	check(ev1.size() == 1, "pomluva vznikne i bez drbu (výmysl)")
	var r1: Dictionary = g.rumors[int(ev1[0]["rid"])]
	check(String(r1["kind"]) == "badmouth" and String(r1["origin"]) == "t" and not bool(r1["truth"]) and String(r1["whom"]) == "l",
		"posluchač má oběť rád → „mluví o tobě za zády“ (klín), původce = pomlouvač, lež")
	check(bool(ev1[0]["fabricated"]) and float(ev1[0]["delta_rel"]) < 0.0, "výmysl a dopad na vztah posluchače k oběti (%.2f)" % float(ev1[0]["delta_rel"]))
	var cool := {"key": "m", "honesty": 0.5, "rel": {"s": -10.0}, "stigma": 0.5}
	var ev2: Array = g.slander(teller, cool, "s", 20.0, content)
	check(ev2.size() == 1 and String(g.rumors[int(ev2[0]["rid"])]["kind"]) == "steals", "jinak „bere ostatním věci“")
	var rid_true: int = g.observe("t", "s", "drinking", 30.0, content)
	check(rid_true > 0, "pomlouvač sám viděl, jak oběť pije (pravda)")
	var third := {"key": "n", "honesty": 0.5, "rel": {"s": 30.0}, "stigma": 0.5}
	var ev3: Array = g.slander(teller, third, "s", 40.0, content)
	check(ev3.size() == 1 and int(ev3[0]["rid"]) == rid_true and bool(ev3[0]["truth"]) and not bool(ev3[0]["fabricated"]),
		"zbraň z pravdy: skutečný drb má přednost před výmyslem")
	var ev4: Array = g.slander(teller, {"key": "o", "honesty": 0.5, "rel": {"s": 30.0}, "stigma": 0.5}, "s", 50.0, {"mental_health": true, "addiction": false})
	check(ev4.size() == 1 and int(ev4[0]["rid"]) != rid_true and not String(g.rumors[int(ev4[0]["rid"])]["kind"]) == "drinking",
		"s vypnutými závislostmi se drb o pití nepoužije (místo něj výmysl)")
	check(g.slander(teller, fan, "t", 60.0, content).is_empty() and g.slander(teller, fan, "l", 60.0, content).is_empty()
		and g.slander(teller, teller, "s", 60.0, content).is_empty(), "nesmyslné kombinace (sám o sobě, o posluchači) nic nedělají")
	var b0: float = g.belief("l", int(ev1[0]["rid"]))
	var b1: float = g.doubt("l", int(ev1[0]["rid"]), 0.3)
	check(b0 > 0.0 and is_equal_approx(b1, b0 * 0.3), "pochybnost tlumí víru (%.2f → %.2f)" % [b0, b1])
	var rep: Array = g.report_slander("l", "s", "t", int(ev1[0]["rid"]), 70.0)
	check(rep.size() == 1 and String(rep[0]["type"]) == "exposed" and bool(rep[0]["origin_known"]) and g.can_confront("s", "t"),
		"donesení oběti: odhalení se zdrojem, oběť může pomlouvače konfrontovat")
	check(g.report_slander("l", "s", "t", 99999, 70.0).is_empty() and g.report_slander("s", "s", "t", int(ev1[0]["rid"]), 70.0).is_empty(),
		"donesení s nesmyslnými údaji nic nedělá")
	check(GossipNetwork.validate_snapshot(g.to_dict()), "drbová síť po pomluvách zůstává platná pro uložení")


# ------------------------------------------------------------------ scéna
func _world(seed: int, dir := "") -> Node:
	clock.total_minutes = 10.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "RivalryWorld%d" % seed
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


func _wait_free(tgt: Node, asker: Node, minutes: int = 240) -> bool:
	for i in minutes:
		if tgt.can_join_social(asker) and not tgt._is_sleeping() and not asker._is_sleeping():
			return true
		clock.advance(1.0)
	return false


func _wait_rv(sim: Node, action: String, minutes: int) -> bool:
	for i in minutes:
		clock.advance(1.0)
		if String(sim.last_rivalry.get("action", "")) == action:
			return true
	return false


func _place(w: Node, pos: Dictionary) -> void:
	var far := 0
	for s in w.sims:
		if pos.has(s):
			s.global_position = pos[s]
		else:
			far += 1
			s.global_position = Vector3(60.0 + 8.0 * far, 0, 60.0)


func _scene() -> void:
	section("Scéna: domácnost")
	var w := _world(23, "user://test-rivalry-%d" % OS.get_process_id())
	var jana = _find(w, "Jana")
	var petr = _find(w, "Petr")
	var eliska = _find(w, "Eliška")
	var wanda = null
	if jana != null:
		var cd: Dictionary = w._character_records[String(jana.name)].to_dict()
		cd["uid"] = String(cd.get("uid", "a11ce0000000000a")).substr(0, String(cd.get("uid", "a11ce0000000000a")).length() - 2) + "7a"
		cd["identity"]["first_name"] = "Wanda"
		cd["identity"]["last_name"] = "Posluchačová"
		wanda = w.spawn_character(cd, Vector3(5, 0, 5), 4343)
		if wanda != null:
			wanda.rng.seed = 77777
	check(jana != null and petr != null and eliska != null and wanda != null, "Jana, Petr, Eliška + Wanda")
	if jana == null or petr == null or eliska == null or wanda == null:
		return
	var rv = w.dynamics.rivalry
	var ro = w.dynamics.romance
	var inf = w.dynamics.infidelity
	check(rv != null and rv.get_script() == Rivalry, "HouseholdDynamics.rivalry")
	var now := float(clock.total_minutes)

	section("Soupeření v lásce (denní sken)")
	check(ro.resolve_ask(petr.sim_name, jana.sim_name, petr.romance_profile(), jana.romance_profile(), 1.0, 0.0, now) == "yes",
		"Petr a Jana spolu chodí")
	eliska.relationships[jana.sim_name] = 75.0
	wanda.relationships[jana.sim_name] = 75.0
	rv._last_scan = -1.0e12
	rv.love_scan(w.sims, ro, inf, now)
	var fits_e: bool = Romance.fits(jana.romance_profile(), eliska.romance_profile())
	check(fits_e, "Elišku Jana přitahuje (Romance.fits)")
	var he: float = rv.arena(eliska.sim_name, petr.sim_name, "love", now)
	check(he > 0.0, "Eliška bere Petra jako soka v lásce (%.3f)" % he)
	check(rv.heat(wanda.sim_name, petr.sim_name, now) == 0.0, "Wandu (přitahují ji muži) Jana nepřitahuje → žádné soupeření")
	check(rv.heat(jana.sim_name, petr.sim_name, now) == 0.0 and rv.heat(petr.sim_name, eliska.sim_name, now) == 0.0,
		"vlastní partner/ka ani ten, kdo nic netuší, nejsou soci")
	var stored_love: float = float(rv.rivals[Rivalry.key(eliska.sim_name, petr.sim_name)]["love"])
	rv.love_scan(w.sims, ro, inf, now + 60.0)
	check(float(rv.rivals[Rivalry.key(eliska.sim_name, petr.sim_name)]["love"]) == stored_love and int(rv.stats["love_scans"]) == 1,
		"sken jen jednou denně (žádné farmení)")
	var age0: int = eliska.intimacy.age
	eliska.intimacy.age = 17
	var rv_age = Rivalry.new()
	rv_age.love_scan(w.sims, ro, inf, now)
	check(rv_age.heat(eliska.sim_name, petr.sim_name, now) == 0.0, "pojistka: postava mladší 18 let nesoupeří v lásce")
	eliska.intimacy.age = age0

	section("Pomluva přes akci hráče (posluchač prokoukne)")
	rv.feel(eliska.sim_name, petr.sim_name, "status", 0.6, now)
	eliska.hexaco["honesty"] = -0.9
	wanda.hexaco["honesty"] = 1.0
	wanda.relationships[petr.sim_name] = 80.0
	wanda.relationships[eliska.sim_name] = 10.0
	wanda.ledger.trust[petr.sim_name] = 90.0
	eliska.mood.remove_moodlet("drbani")
	var w_e0: float = float(wanda.relationships[eliska.sim_name])
	_place(w, {eliska: Vector3(0, 0, 0), wanda: Vector3(1.5, 0, 0), petr: Vector3(30, 0, 0), jana: Vector3(40, 0, 0)})
	check(_wait_free(wanda, eliska), "Wanda je volná")
	_place(w, {eliska: Vector3(0, 0, 0), wanda: Vector3(1.5, 0, 0), petr: Vector3(30, 0, 0), jana: Vector3(40, 0, 0)})
	check(w.rivalry_slander_block(eliska, wanda) == "", "server: Eliška má soka a smí pomlouvat")
	check(eliska.command(ActionLibrary.get_action("slander_rival"), wanda), "příkaz Pomlouvat soka přijat")
	check(_wait_rv(eliska, "slander_rival", 200), "pomluva proběhla")
	var lr: Dictionary = eliska.last_rivalry
	check(String(lr.get("rival", "")) == petr.sim_name, "soka vybral systém: Petr")
	check(String(lr.get("outcome", "")) == "saw_through", "poctivá Wanda, Petrova kamarádka, to prokoukla (%s)" % String(lr.get("outcome", "")))
	check(float(wanda.relationships[eliska.sim_name]) < w_e0, "Wanda si o Elišce myslí hůř (%.1f → %.1f)" % [w_e0, float(wanda.relationships[eliska.sim_name])])
	check(not eliska.mood.has_moodlet("drbani"), "pomluva se neodměňuje (žádný „dobrý drb“ ani u nepoctivé)")
	check(eliska.mood.has_moodlet("pomluva_neprosla"), "Eliška ví, že to neprošlo")
	var wk: String = SimAgent.memory_key(wanda)
	var pk: String = SimAgent.memory_key(petr)
	var ek: String = SimAgent.memory_key(eliska)
	var found := 0
	for rid in w.gossip.know.get(wk, {}):
		var r: Dictionary = w.gossip.rumors.get(rid, {})
		if String(r.get("subject", "")) == pk and String(r.get("origin", "")) == ek:
			found = int(rid)
	check(found > 0 and w.gossip.belief(wk, found) < 0.4, "drb v síti s původcem Eliškou, Wanda mu skoro nevěří (%.2f)" % (w.gossip.belief(wk, found) if found > 0 else -1.0))
	check(String(rv.slander_block(eliska.sim_name, wanda.sim_name, float(clock.total_minutes))["block"]) in ["not_now", "repeat"],
		"hned znovu nejde")
	if not bool(lr.get("reported", false)):
		# Donesení je náhodné (podpora/poctivost); obě větve se testují – tady deterministicky ručně.
		for e in w.gossip.report_slander(wk, pk, ek, found, float(clock.total_minutes)):
			w._apply_gossip_event(e, float(clock.total_minutes))
	check(w.gossip_can_confront(petr, eliska), "Petr se dozvěděl, od koho to šlo → může Elišku konfrontovat")
	check(rv.heat(petr.sim_name, eliska.sim_name, float(clock.total_minutes)) >= Rivalry.SLANDER_EXPOSED * 0.9,
		"rivalita oplátkou: Petr teď bere Elišku jako soka (%.2f)" % rv.heat(petr.sim_name, eliska.sim_name, float(clock.total_minutes)))
	check(petr.mood.has_moodlet("drb_pomluva"), "Petra mrzí, že ho pomlouvají")
	var pl: PackedStringArray = w.relationship_lines(petr)
	check(", ".join(pl).contains("Sok: Eliška") or ", ".join(pl).contains("Hořký sok: Eliška"), "HUD Petra: soukromý řádek soka (%s)" % ", ".join(pl))

	section("Pomluva u důvěřivého posluchače (zabere)")
	for i in 130:
		clock.advance(1.0)
	jana.hexaco["honesty"] = -1.0
	jana.relationships[petr.sim_name] = -30.0
	jana.relationships[eliska.sim_name] = 70.0
	jana.ledger.trust[petr.sim_name] = 10.0
	var j_p0: float = float(jana.relationships[petr.sim_name])
	var ev: Dictionary = w.rivalry_slander(eliska, jana)
	check(String(ev.get("outcome", "")) == "swayed", "Jana, která má s Petrem dusno a Elišce věří, uvěří (%s)" % String(ev.get("outcome", "")))
	check(float(jana.relationships[petr.sim_name]) < j_p0, "vztah Jany k Petrovi klesl (%.1f → %.1f)" % [j_p0, float(jana.relationships[petr.sim_name])])
	check(not bool(ev.get("reported", true)), "kdo uvěří, nic nedonáší")
	var ev_b: Dictionary = w.rivalry_slander(eliska, jana)
	check(String(ev_b.get("outcome", "")) == "blocked" and String(ev_b.get("block", "")) == "not_now", "hned další pomluva → odstup")
	check(int(rv.stats["swayed"]) >= 1 and int(rv.stats["saw_through"]) >= 1, "statistiky výsledků")

	section("Server (handle_command)")
	var net = w.get("net")
	check(net.handle_command(1, String(jana.name), "slander_rival", String(wanda.name)) != "", "pomluva bez soka → odmítnuto")
	check(net.handle_command(1, String(wanda.name), "bury_hatchet", String(jana.name)) != "", "usmíření bez rivality → odmítnuto")
	check(net.handle_command(1, String(eliska.name), "slander_rival", String(wanda.name)) != "", "pomluva v odstupu → odmítnuto")
	var old_mode: int = net.mode
	var old_players: Dictionary = net.players
	net.mode = 1
	net.players = {1: old_players.get(1, {}).merged({"sim": String(petr.name), "cmd": _AllowAll.new()}), 7: {"sim": String(eliska.name), "cmd": _AllowAll.new()}}
	check(net.handle_command(1, String(petr.name), "bury_hatchet", String(eliska.name)) != "", "usmíření s postavou jiného hráče → odmítnuto (AI by odpovídala za něj)")
	check(net.handle_command(1, String(eliska.name), "slander_rival", String(wanda.name)) != "", "cizí postavou pomlouvat nejde")
	net.mode = old_mode
	net.players = old_players

	section("AI skóre")
	var t := float(clock.total_minutes) + 2000.0
	var rv_ai = Rivalry.new()
	rv_ai.feel(eliska.sim_name, petr.sim_name, "status", 0.7, t)
	check(rv_ai.ai_slander_score(eliska, wanda, 1.0, t) > 0.0, "nepoctivá postava se silným sokem pomluvu zvažuje (%.3f)" % rv_ai.ai_slander_score(eliska, wanda, 1.0, t))
	eliska.hexaco["honesty"] = 0.6
	check(rv_ai.ai_slander_score(eliska, wanda, 1.0, t) == 0.0, "poctivá postava nepomlouvá ani při rivalitě")
	eliska.hexaco["honesty"] = -0.9
	var wr: float = float(wanda.relationships[eliska.sim_name])
	wanda.relationships[eliska.sim_name] = -50.0
	check(rv_ai.ai_slander_score(eliska, wanda, 1.0, t) == 0.0, "kdo autora nesnáší, tomu nic nevykládá")
	wanda.relationships[eliska.sim_name] = wr
	rv_ai.note_ai(eliska.sim_name, "slander", t)
	check(rv_ai.ai_slander_score(eliska, wanda, 1.0, t + 10.0) == 0.0, "odstup AI pomluv (den)")
	rv_ai.feel(petr.sim_name, eliska.sim_name, "status", 0.5, t)
	petr.hexaco["honesty"] = 0.8
	check(rv_ai.ai_hatchet_score(petr, eliska, 1.0, 0.5, t) > 0.0, "smířlivá poctivá postava zvažuje usmíření")
	check(rv_ai.ai_hatchet_score(petr, eliska, 1.0, -1.0, t) == 0.0 or rv_ai.ai_hatchet_score(petr, eliska, 1.0, -1.0, t) < rv_ai.ai_hatchet_score(petr, eliska, 1.0, 0.5, t),
		"nesmiřitelná méně (nebo vůbec)")
	check(rv_ai.contact_weight(petr.sim_name, eliska.sim_name, "chat", t) < 1.0 and rv_ai.contact_weight(petr.sim_name, eliska.sim_name, "bury_hatchet", t) == 1.0,
		"běžnému kontaktu se sokem se postavy spíš vyhýbají; usmíření se netlumí")
	check(rv_ai.contact_weight(jana.sim_name, wanda.sim_name, "chat", t) == 1.0, "bez rivality beze změny")

	section("Usmíření přes akci hráče")
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(40, 0, 0), wanda: Vector3(50, 0, 0)})
	check(_wait_free(eliska, petr), "Eliška je volná")
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(40, 0, 0), wanda: Vector3(50, 0, 0)})
	check(w.rivalry_hatchet_block(petr, eliska) == "", "mezi Petrem a Eliškou je co zakopávat")
	var h_pe: float = rv.heat(petr.sim_name, eliska.sim_name, float(clock.total_minutes))
	check(petr.command(ActionLibrary.get_action("bury_hatchet"), eliska), "příkaz Zakopat válečnou sekeru přijat")
	check(_wait_rv(petr, "bury_hatchet", 200), "usmíření proběhlo")
	var oc := String(petr.last_rivalry.get("outcome", ""))
	check(oc in ["accepted", "refused"], "výsledek %s (šance %.2f)" % [oc, float(petr.last_rivalry.get("p", 0.0))])
	if oc == "accepted":
		check(rv.heat(petr.sim_name, eliska.sim_name, float(clock.total_minutes)) < h_pe * 0.5 and rv.respect(petr.sim_name, eliska.sim_name) > 0.0,
			"rivalita opadla, přibyl respekt")
	else:
		check(w.rivalry_hatchet_block(petr, eliska) == "not_now" and petr.mood.has_moodlet("sekera_ne_" + String(eliska.name)),
			"odmítnutí: odstup a hořkost")

	section("Manipulace s obranou (SocialPressure)")
	# Zranitelná: vysoká soukromá defektnost, žádná opora, žádná zkušenost s manipulátorem.
	var saved_rel: Dictionary = jana.relationships.duplicate(true)
	for k in jana.relationships.keys():
		jana.relationships[k] = minf(float(jana.relationships[k]), 0.0)
	jana.self_defectiveness_belief = 0.9
	jana.ledger.grudges.erase(wanda.sim_name)
	var d_low: Dictionary = SocialPressure.defense_for(wanda, jana)
	check(not bool(d_low["resisted"]) and float(d_low["defense"]) < 0.2, "zranitelná bez opory: slabá obrana (%.2f)" % float(d_low["defense"]))
	var g0: float = jana.emotions.level("guilt")
	check(SocialPressure.apply("guilt_trip", wanda, jana, float(clock.total_minutes)), "vyvolávání viny proběhlo")
	var g_hit_low: float = jana.emotions.level("guilt") - g0
	check(not jana.mood.has_moodlet("ustal_" + String(wanda.name)), "neubránila se – žádné „ustála jsem to“")
	check(float(jana.self_defectiveness_belief) == 0.9, "soukromá defektnost se jen čte, nikdy nemění")
	# Silná: zdravá sebehodnota, blízký přítel, už s manipulátorkou zkušenost (zášť).
	eliska.self_defectiveness_belief = 0.0
	eliska.relationships[jana.sim_name] = 90.0
	eliska.ledger.grudges[wanda.sim_name] = 70.0
	var d_hi: Dictionary = SocialPressure.defense_for(wanda, eliska)
	check(bool(d_hi["resisted"]) and float(d_hi["defense"]) > 0.8, "zdravá sebehodnota + opora + rozpoznání vzorce: ubrání se (%.2f)" % float(d_hi["defense"]))
	var e0: float = eliska.emotions.level("guilt")
	var rel_ew0: float = float(eliska.relationships.get(wanda.sim_name, 0.0))
	check(SocialPressure.apply("guilt_trip", wanda, eliska, float(clock.total_minutes) + 1.0), "vyvolávání viny vůči silné")
	var g_hit_hi: float = eliska.emotions.level("guilt") - e0
	check(g_hit_hi < g_hit_low, "obrana tlumí vinu (%.2f < %.2f)" % [g_hit_hi, g_hit_low])
	check(g_hit_hi > 0.0, "ale zneužití bolí vždycky (minimum %.0f %%)" % (SocialPressure.MIN_HIT * 100.0))
	check(float(eliska.relationships.get(wanda.sim_name, 0.0)) < rel_ew0, "vztah k manipulátorce utrpí i při odražení")
	check(eliska.mood.has_moodlet("ustal_" + String(wanda.name)) and wanda.mood.has_moodlet("nezabralo_" + String(eliska.name)),
		"„nenechala jsem se zmanipulovat“ / „nezabralo to“ (bez odměny pro manipulátora)")
	check(eliska.has_meta("last_pressure_defense") and bool(eliska.get_meta("last_pressure_defense")["resisted"]), "výsledek obrany je k dispozici (ladění, testy)")
	jana.relationships = saved_rel
	jana.self_defectiveness_belief = 0.0

	section("Zrada: milenec partnera je sok")
	var rv_b0: float = rv.arena(jana.sim_name, eliska.sim_name, "love", float(clock.total_minutes))
	jana.on_betrayal(petr, eliska, "confess")
	check(rv.arena(jana.sim_name, eliska.sim_name, "love", float(clock.total_minutes)) > rv_b0 + 0.3,
		"Jana po odhalení bere Elišku jako soka v lásce")

	section("Uložení a načtení celé hry")
	var tsave := float(clock.total_minutes)
	var snap: Dictionary = rv.to_dict()
	check(Rivalry.validate_snapshot(snap), "živý stav projde striktní kontrolou")
	var jn := String(jana.sim_name)
	var en := String(eliska.sim_name)
	var h_save: float = rv.heat(jn, en, tsave)
	var res: Dictionary = w.save_game("manual")
	check(bool(res.get("ok", false)), "uloženo (%s)" % str(res.get("reason", "")))
	rv.from_dict({})
	check(rv.heat(jn, en, tsave) == 0.0, "stav vymazán před načtením")
	var ld: Dictionary = w.load_game("manual")
	check(bool(ld.get("ok", false)), "načteno (%s)" % str(ld.get("reason", "")))
	var rv_l = w.dynamics.rivalry
	check(is_equal_approx(rv_l.heat(jn, en, tsave), h_save), "rivalita přežila uložení na disk (%.3f)" % rv_l.heat(jn, en, tsave))
	check(rv_l.rivals.size() == snap["rivals"].size() and rv_l.told.size() == snap["told"].size(), "všechny záznamy obnoveny")

	section("Výkon")
	var big = Rivalry.new()
	for i in 200:
		big.feel("P%d" % (i % 20), "Q%d" % (i / 20), "status", 0.4, 0.0)
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		big.slander_block("P%d" % (i % 20), "Z", 10.0)
		big.top_rival("P%d" % (i % 20), 10.0)
	var us := float(Time.get_ticks_usec() - t0) / 1000.0
	check(us < 400.0, "1000× brána + výběr soka při 200 záznamech: %.1f µs/volání" % us)
	w.queue_free()


## Dictionary.merged s přepsáním existujících klíčů (merged() je ve výchozím stavu NEpřepisuje).
static func _mo(a: Dictionary, b: Dictionary, _overwrite := true) -> Dictionary:
	return a.merged(b, true)


class _AllowAll:
	func allow(_t) -> bool:
		return true
