extends "res://tests/test_base.gd"
## Infidelity (scripts/sim/infidelity.gd): flirt, jiskra, tajná schůzka, podezření, konfrontace, zrada.
## Spuštění: godot_run scene=res://tests/test_infidelity.tscn
##   bez argumentů: jednotky + fuzz uložení + drby + scéna (příkazy hráče, svědci, AI skóre, server, HUD, uložení)
const Infidelity := preload("res://scripts/sim/infidelity.gd")
const Romance := preload("res://scripts/sim/romance.gd")
const GossipNetwork := preload("res://scripts/sim/gossip_network.gd")
const Main := preload("res://main.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
var clock: Node

const MAN := {"age": 35, "aromantic": false, "attracted_to": ["zeny"], "group": "muzi"}
const WOMAN := {"age": 30, "aromantic": false, "attracted_to": ["muzi"], "group": "zeny"}
const BI := {"age": 32, "aromantic": false, "attracted_to": ["muzi", "zeny"], "group": "zeny"}


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
	_fuzz()
	_gossip_kinds()
	await _scene()
	clock.running = false
	finish("test_infidelity")


# ------------------------------------------------------------------ jednotky
func _couple(a := "A", b := "B") -> Object:
	var ro = Romance.new()
	ro.resolve_ask(a, b, MAN, WOMAN, 1.0, 0.0, 0.0)
	return ro


func _units() -> void:
	section("Flirt a jiskra")
	var ro = _couple()  # A + B spolu
	var inf = Infidelity.new()
	check(inf.resolve_flirt("A", "B", ro, true, 0.0, 0.99, 10.0) == "own_partner", "flirt s vlastním partnerem je vždy vítaný")
	check(inf.spark("A", "B", 10.0) == 0.0, "flirt s partnerem nezakládá „jiskru“ (ta je jen pro cizí)")
	check(inf.resolve_flirt("A", "C", ro, false, 0.9, 0.0, 20.0) == "uncomfortable", "nesoulad přitažlivosti: nepříjemné, bez ohledu na hod")
	check(inf.spark("A", "C", 20.0) == 0.0, "nepříjemný flirt jiskru nezaloží")
	check(inf.resolve_flirt("A", "C", ro, true, 0.5, 0.7, 30.0) == "brushed_off", "odbytí (hod nad šancí)")
	check(inf.resolve_flirt("A", "C", ro, true, 0.5, 0.2, 40.0) == "reciprocated", "opětovaný flirt")
	var s1: float = inf.spark("A", "C", 40.0)
	check(is_equal_approx(s1, Infidelity.SPARK_FLIRT), "jiskra po prvním opětovaném flirtu (%.2f)" % s1)
	inf.resolve_flirt("A", "C", ro, true, 0.5, 0.2, 50.0)
	check(inf.spark("A", "C", 50.0) <= s1 + 1.0e-9, "spam flirtů do %d min jiskru nepřidá" % int(Infidelity.FLIRT_GAP))
	inf.resolve_flirt("A", "C", ro, true, 0.5, 0.2, 200.0)
	var s2: float = inf.spark("A", "C", 200.0)
	check(s2 > s1 and s2 - s1 < Infidelity.SPARK_FLIRT, "další flirt po pauze přidá, ale s klesajícím výnosem (%.3f → %.3f)" % [s1, s2])
	check(inf.spark("A", "C", 200.0 + 7.0 * 1440.0) < s2 * 0.4, "jiskra bez kontaktu vyhasíná (τ 7 dní)")
	check(is_equal_approx(inf.spark("C", "A", 200.0), s2), "jiskra je symetrická")
	check(is_equal_approx(inf.spark("A", "C", 100.0), inf.sparks[Romance.key("A", "C")]["v"]), "zpětný čas (rewind) jiskru nezesílí ani nevymaže")
	var lo := Infidelity.flirt_p(-100.0, 0.0, -100.0, false, 0.0)
	var hi := Infidelity.flirt_p(100.0, 100.0, 100.0, false, 0.0)
	check(lo >= 0.02 and hi <= 0.92 and lo < hi, "šance opětovat v mezích (%.2f..%.2f)" % [lo, hi])
	check(Infidelity.flirt_p(80.0, 60.0, 0.0, true, 0.9) < Infidelity.flirt_p(80.0, 60.0, 0.0, true, 0.1),
		"věrný zadaný člověk flirt opětuje méně než nespokojený")
	check(Infidelity.flirt_p(80.0, 60.0, 0.0, true, 0.1) < Infidelity.flirt_p(80.0, 60.0, 0.0, false, 0.0), "zadaný méně než volný")
	var dist := {"reciprocated": 0, "brushed_off": 0}
	for i in 1000:
		var x = Infidelity.new()
		dist[x.resolve_flirt("X", "Y", null, true, 0.3, (float(i) + 0.5) / 1000.0, 0.0)] += 1
	var rb = Infidelity.new()
	rb.resolve_flirt("X", "Y", null, true, 0.5, 0.9, 100.0)
	check(rb.rebuffed("X", "Y", 200.0) and not rb.rebuffed("Y", "X", 200.0) and not rb.rebuffed("X", "Y", 100.0 + Infidelity.REBUFF_PAUSE),
		"odbytí se pamatuje (směrově, 3 dny) – AI pak nedotírá")
	var rb2 = Infidelity.new()
	rb2.from_dict(JSON.parse_string(JSON.stringify(rb.to_dict())))
	check(rb2.rebuffed("X", "Y", 200.0), "odbytí přežije uložení")
	check(dist["reciprocated"] == 300, "rozložení výsledků odpovídá šanci (opětováno %d/1000 při p=0,3)" % dist["reciprocated"])

	section("Kdo koho zrazuje")
	var bt: Dictionary = Infidelity.betrayals("A", "C", ro)
	check(String(bt["A"]) == "B" and String(bt["C"]) == "", "A je zadaný(á) s B, C je volný(á)")
	var ro2 = _couple("A", "B")
	ro2.resolve_ask("C", "D", MAN, WOMAN, 1.0, 0.0, 0.0)
	var bt2: Dictionary = Infidelity.betrayals("A", "C", ro2)
	check(String(bt2["A"]) == "B" and String(bt2["C"]) == "D", "oba zadaní: oba někoho zrazují")
	check(String(Infidelity.betrayals("A", "B", ro2)["A"]) == "", "s vlastním partnerem to zrada není")

	section("Tajná schůzka: brány")
	var free = Infidelity.new()
	check(free.date_block("X", "Y", Romance.new(), 0.0) == "free", "nikdo zadaný: to je obyčejné rande, ne tajná schůzka")
	check(free.date_block("A", "B", ro, 0.0) == "own_partner", "s vlastním partnerem není co tajit")
	check(free.date_block("A", "A", ro, 0.0) == "self", "sám se sebou ne")
	check(free.date_block("A", "C", ro, 0.0) == "no_spark", "bez jiskry „z ničeho nic“ nejde")
	inf.sparks[Romance.key("A", "C")] = {"v": 0.7, "t": 300.0, "last_flirt": 200.0}
	check(inf.date_block("A", "C", ro, 300.0) == "", "zadaný + jiskra: jde to")
	check(inf.resolve_date("A", "C", ro, false, 0.9, 0.0, 300.0) == "no", "cíl, kterého A nepřitahuje, odmítne vždy")
	check(inf.spark("A", "C", 300.0) < 0.7 * 0.61, "odmítnutí jiskru zchladí (%.2f)" % inf.spark("A", "C", 300.0))
	inf.sparks[Romance.key("A", "C")] = {"v": 0.7, "t": 300.0, "last_flirt": 200.0}
	check(inf.resolve_date("A", "C", ro, true, 0.5, 0.9, 300.0) == "no", "hod nad šancí: ne")
	inf.sparks[Romance.key("A", "C")] = {"v": 0.7, "t": 300.0, "last_flirt": 200.0}
	check(inf.resolve_date("A", "C", ro, true, 0.5, 0.1, 300.0) == "yes", "ano → tajná schůzka")
	check(inf.affair_dates("A", "C") == 1 and inf.secret_lover("A", "B") == "C", "románek zaznamenán, B o něm neví")
	check(inf.secret_lover("C", "B") == "", "C nikoho nezrazuje (je volný/á)")
	check(inf.date_block("A", "C", ro, 330.0) == "not_now", "hned další schůzka ne (2 h)")
	check(inf.resolve_date("A", "C", ro, true, 1.0, 0.0, 500.0) == "yes" and inf.affair_dates("A", "C") == 2, "druhá schůzka")
	check(float(inf.affairs[Romance.key("A", "C")]["last"]) == 500.0, "čas poslední schůzky")

	section("Intimita mimo vztah = nevěra")
	var ii = Infidelity.new()
	check(ii.note_intimacy("X", "Y", Romance.new(), 0.0).is_empty() and ii.affairs.is_empty(), "dva volní lidé: nic (není co evidovat)")
	check(ii.note_intimacy("A", "B", ro, 0.0).is_empty(), "s vlastním partnerem: nic")
	var bt3: Dictionary = ii.note_intimacy("A", "C", ro, 10.0)
	check(String(bt3.get("A", "")) == "B" and ii.secret_lover("A", "B") == "C" and int(ii.stats["intimate"]) == 1,
		"zadaný(á) s někým třetím: nevěra i bez předchozí jiskry")

	section("Podezření a důkazy")
	var su = Infidelity.new()
	var v1: float = su.notice("B", "A", 0.3, 0.2, "C", 0.0)
	var v2: float = su.notice("B", "A", 0.3, 0.2, "", 0.0)
	check(is_equal_approx(v1, 0.3) and is_equal_approx(v2, 1.0 - 0.7 * 0.7), "podezření se skládá (ne lineárně): %.2f → %.2f" % [v1, v2])
	check(su.hint_of("B", "A") == "C", "nápověda „s kým“ zůstane, prázdná ji nepřepíše")
	check(su.suspicion_of("B", "A", 21.0 * 1440.0) < v2 * 0.4, "bez nových podnětů podezření opadá (τ 21 dní)")
	check(su.evidence_of("B", "A", 21.0 * 1440.0) > su.evidence_of("B", "A", 0.0) * 0.7, "důkazy vyhasínají pomaleji (co člověk viděl, to viděl)")
	check(su.suspicion_of("B", "A", -500.0) == su.suspicion_of("B", "A", 0.0), "zpětný čas podezření nemění")
	su.notice("B", "A", 0.0, 0.0, "B", 0.0)
	su.notice("B", "A", 0.0, 0.0, "x|y", 0.0)
	check(su.hint_of("B", "A") == "C", "neplatná nápověda (sám, cizí znaky) se ignoruje")
	var ru = Infidelity.new()
	ru.on_rumor("B", "A", 0.8, "C", 0.0)
	check(is_equal_approx(ru.suspicion_of("B", "A", 0.0), Infidelity.SUSP_RUMOR * 0.8 * 0.75) and ru.hint_of("B", "A") == "C",
		"drb k partnerovi: podezření podle víry a důvěry (%.2f)" % ru.suspicion_of("B", "A", 0.0))
	var ru2 = Infidelity.new()
	ru2.on_rumor("B", "A", 0.8, "C", 0.0, 95.0)
	var ru3 = Infidelity.new()
	ru3.on_rumor("B", "A", 0.8, "C", 0.0, 10.0)
	check(ru2.suspicion_of("B", "A", 0.0) < ru3.suspicion_of("B", "A", 0.0) * 0.5,
		"kdo partnerovi hodně věří, drbu dá menší váhu (%.2f vs %.2f; Grok #551)" % [ru2.suspicion_of("B", "A", 0.0), ru3.suspicion_of("B", "A", 0.0)])
	var ev0: float = ru3.evidence_of("B", "A", 0.0)
	var v0: float = ru3.suspicion_of("B", "A", 0.0)
	ru3.reassure("B", "A", 0.0)
	check(is_equal_approx(ru3.suspicion_of("B", "A", 0.0), v0 * Infidelity.REASSURE) and is_equal_approx(ru3.evidence_of("B", "A", 0.0), ev0),
		"příjemný kontakt s partnerem podezření zmírní, důkazy ne")

	section("Konfrontace")
	check(inf.confront_block("B", "A", ro, 600.0) == "" and inf.confront_block("C", "A", ro, 600.0) == "not_partners",
		"konfrontovat jde jen vlastního partnera")
	var c1: Dictionary = inf.resolve_confront("B", "A", 0.5, 0.2, 0.99, 600.0)
	check(String(c1["outcome"]) == "denied" and String(c1["lover"]) == "C" and inf.secret_lover("A", "B") == "C",
		"bez důkazů a s vysokým hodem: zapře, dál tajné")
	check(inf.confront_block("B", "A", ro, 620.0) == "not_now", "hned znovu ne")
	inf.notice("B", "A", 0.5, 0.8, "C", 700.0)
	var c2: Dictionary = inf.resolve_confront("B", "A", 0.0, 0.0, 0.99, 700.0)
	check(String(c2["outcome"]) == "caught_lying", "s důkazy (%.2f) zapírání neprojde" % float(c2["evidence"]))
	check(inf.secret_lover("A", "B") == "" and (inf.affairs[Romance.key("A", "C")]["known_by"] as Array).has("B"), "teď to B ví")
	check(inf.suspicion_of("B", "A", 700.0) == 0.0 and inf.hint_of("B", "A") == "C", "po odhalení se podezření mění ve vědění (žádné další výslechy)")
	var c3: Dictionary = inf.resolve_confront("B", "A", 0.5, 0.5, 0.0, 800.0)
	check(String(c3["outcome"]) == "innocent", "o ničem dalším nikdo neví → „nevinný(á)“ (žárlivá scéna)")
	check(inf.suspicion_of("B", "A", 800.0) == 0.0 and inf.evidence_of("B", "A", 800.0) == 0.0, "po scéně bez důvodu nic nezůstane")
	var inn = Infidelity.new()
	inn.notice("B", "A", 0.8, 0.3, "C", 0.0)
	inn.resolve_confront("B", "A", 0.5, 0.5, 0.0, 10.0)
	check(inn.suspicion_of("B", "A", 10.0) < 0.5 and inn.evidence_of("B", "A", 10.0) == 0.0, "křivé podezření po scéně opadne (%.2f)" % inn.suspicion_of("B", "A", 10.0))
	var cf = Infidelity.new()
	cf.sparks[Romance.key("A", "C")] = {"v": 0.7, "t": 0.0, "last_flirt": 0.0}
	cf.resolve_date("A", "C", ro, true, 1.0, 0.0, 0.0)
	check(String(cf.resolve_confront("B", "A", 1.0, 1.0, 0.5, 10.0)["outcome"]) == "confess", "poctivý a s vinou se přizná")
	check(Infidelity.confess_p(0.0, 0.0, 0.0) < Infidelity.confess_p(1.0, 0.0, 0.0) and Infidelity.confess_p(1.0, 1.0, 1.0) <= 0.95,
		"šance přiznání roste s poctivostí, má strop")

	section("Pokušení (AI)")
	check(Infidelity.temptation(0.8, 0.8, 0.0) == 0.0, "spokojený a poctivý: žádné pokušení")
	check(Infidelity.temptation(0.2, 0.2, 1.0) > Infidelity.temptation(0.2, 0.8, 0.0), "nespokojenost + nízká poctivost + impulzivita")
	check(Infidelity.temptation(0.2, 0.5, 0.0) > Infidelity.temptation(0.6, 0.5, 0.0), "nižší spokojenost → víc pokušení")

	section("HUD (soukromé věty)")
	var hl = Infidelity.new()
	hl.sparks[Romance.key("A", "C")] = {"v": 0.7, "t": 0.0, "last_flirt": 0.0}
	hl.resolve_date("A", "C", ro, true, 1.0, 0.0, 0.0)
	hl.notice("B", "A", 0.5, 0.1, "", 0.0)
	var la: PackedStringArray = hl.private_lines("A", ro, 0.0)
	var lb: PackedStringArray = hl.private_lines("B", ro, 0.0)
	check(la.size() == 1 and la[0].begins_with("Tajný románek"), "nevěrník vidí svůj románek (%s)" % ", ".join(la))
	check(lb.size() == 1 and lb[0] == "Něco mi nesedí: A.", "zrazený vidí jen tušení, ne s kým (%s)" % ", ".join(lb))


# ------------------------------------------------------------------ fuzz uložení
func _fuzz() -> void:
	section("Uložení: round-trip a poškozená data")
	var ro = _couple()
	var inf = Infidelity.new()
	inf.resolve_flirt("A", "C", ro, true, 1.0, 0.0, 0.0)
	inf.sparks[Romance.key("A", "C")]["v"] = 0.8
	inf.resolve_date("A", "C", ro, true, 1.0, 0.0, 10.0)
	inf.notice("B", "A", 0.4, 0.3, "C", 20.0)
	inf.note_ai("A", "flirt", 5.0)
	var snap := JSON.stringify(inf.to_dict(), "", true)
	var back = Infidelity.new()
	back.from_dict(JSON.parse_string(JSON.stringify(inf.to_dict())))
	check(JSON.stringify(back.to_dict(), "", true) == snap, "JSON round-trip beze ztráty")
	check(back.secret_lover("A", "B") == "C" and is_equal_approx(back.suspicion_of("B", "A", 20.0), inf.suspicion_of("B", "A", 20.0)),
		"po načtení platí románek i podezření")
	var crashes := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var junk: Array = [null, 1, -1.0, NAN, INF, "x", [], {}, [1, 2], {"v": "a"}, "A|B|C", "a>b>c", "", "x".repeat(200), true]
	var over_limit := true
	for i in 300:
		var d := {}
		for k in ["sparks", "affairs", "suspicion", "last_ai", "stats"]:
			var m := {}
			for j in rng.randi_range(0, 6):
				var key = junk[rng.randi() % junk.size()]
				if rng.randf() < 0.5:
					key = "P%d|Q%d" % [rng.randi() % 4, rng.randi() % 4] if k != "suspicion" else "P%d>Q%d" % [rng.randi() % 4, rng.randi() % 4]
				if typeof(key) in [TYPE_STRING, TYPE_INT]:
					m[key] = {"v": junk[rng.randi() % junk.size()], "t": junk[rng.randi() % junk.size()],
						"betrays": {"P1": junk[rng.randi() % junk.size()], "P0": "Q3"}, "known_by": junk[rng.randi() % junk.size()],
						"dates": junk[rng.randi() % junk.size()], "hint": junk[rng.randi() % junk.size()],
						"ev": junk[rng.randi() % junk.size()], "last_confront": junk[rng.randi() % junk.size()]}
			d[k] = m if rng.randf() < 0.9 else junk[rng.randi() % junk.size()]
		var x = Infidelity.new()
		x.from_dict(d)
		x.from_dict(junk[i % junk.size()])
		x.from_dict(d)
		for k in x.sparks:
			var v = x.sparks[k]["v"]
			if not (is_finite(v) and v >= 0.0 and v <= 1.0):
				crashes += 1
		for k in x.suspicion:
			if not String(k).contains(">") or not is_finite(float(x.suspicion[k]["v"])):
				crashes += 1
		for k in x.affairs:
			if (x.affairs[k]["betrays"] as Dictionary).is_empty():
				crashes += 1
			for who in x.affairs[k]["betrays"]:
				if String(x.affairs[k]["betrays"][who]) in String(k).split("|"):
					crashes += 1
		if x.sparks.size() > Infidelity.MAX_SPARKS or x.affairs.size() > Infidelity.MAX_AFFAIRS:
			over_limit = false
	check(crashes == 0, "300 poškozených savů: hodnoty v mezích, žádná „zrada sebe sama“ (%d chyb)" % crashes)
	check(over_limit, "limity drženy")
	var big := {"sparks": {}, "affairs": {}, "suspicion": {}}
	for i in 600:
		big["sparks"]["a%d|b%d" % [i, i]] = {"v": 0.5, "t": 0.0, "last_flirt": 0.0}
		big["affairs"]["a%d|b%d" % [i, i]] = {"since": 0.0, "last": 0.0, "dates": 1, "betrays": {"a%d" % i: "p%d" % i}, "known_by": []}
		big["suspicion"]["p%d>a%d" % [i, i]] = {"v": 0.5, "ev": 0.1, "t": 0.0, "hint": "", "last_confront": 0.0}
	var bx = Infidelity.new()
	bx.from_dict(big)
	check(bx.sparks.size() == Infidelity.MAX_SPARKS and bx.affairs.size() == Infidelity.MAX_AFFAIRS and bx.suspicion.size() == Infidelity.MAX_SUSP,
		"nadměrný save se ořízne na limity (%d/%d/%d)" % [bx.sparks.size(), bx.affairs.size(), bx.suspicion.size()])
	var full = Infidelity.new()
	full.from_dict(big)
	full._add_spark("new1", "new2", 0.3, 1.0e6)
	check(full.sparks.size() <= Infidelity.MAX_SPARKS, "plná tabulka: úklid vyhaslých jisker uvolní místo, limit drží")
	var fresh = Infidelity.new()
	for i in Infidelity.MAX_SPARKS:
		fresh._add_spark("a%d" % i, "b%d" % i, 0.5 if i > 0 else 0.1, 0.0)
	fresh._add_spark("novy1", "novy2", 0.3, 0.0)
	check(fresh.sparks.size() == Infidelity.MAX_SPARKS and fresh.spark("novy1", "novy2", 0.0) > 0.0 and fresh.spark("a0", "b0", 0.0) == 0.0,
		"plná tabulka čerstvých jisker: nová vytlačí nejslabší (audit Gemini)")


# ------------------------------------------------------------------ drby
func _gossip_kinds() -> void:
	section("Drby o nevěře a rozchodech")
	check(GossipNetwork.KINDS.has("cheating") and GossipNetwork.KINDS.has("flirting") and GossipNetwork.KINDS.has("breakup"), "nové druhy drbů")
	check(GossipNetwork._impact("breakup", 1.0, 0.0, 0.0) == 0.0, "rozchod je novinka: vztah posluchače nemění")
	check(GossipNetwork._impact("cheating", 1.0, 0.0, 0.0) < 0.0, "nevěra je záporný drb")
	for k in ["cheating", "flirting", "breakup"]:
		check(not bool(GossipNetwork.KINDS[k]["fab"]), "„%s“ nejde smyslet (jen svědectví)" % k)
	var g = GossipNetwork.new(7)
	g.set_name("w", "Wanda Nová", "f")
	g.set_name("a", "Adam Malý", "m")
	var rid: int = g.observe("w", "a", "cheating", 0.0, {}, 1.0, "c")
	check(rid > 0 and String(g.rumors[rid]["whom"]) == "c", "svědectví nevěry s „kým“")
	check(g.line_for(rid).begins_with("Ty jo, víš, že Adam"), "replika (%s)" % g.line_for(rid))
	var rb: int = g.observe("w", "a", "breakup", 0.0, {}, 1.0, "c")
	check(g.line_for(rb).contains("skončil") and not g.line_for(rb).contains("{"), "replika o rozchodu v gramatice (%s)" % g.line_for(rb))
	check(GossipNetwork.validate_snapshot(g.to_dict()), "snapshot s novými druhy je platný")


# ------------------------------------------------------------------ scéna
func _world(seed: int, dir := "") -> Node:
	clock.total_minutes = 10.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "InfidelityWorld%d" % seed
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


## Počká, až `sim` provede akci `action` (last_infidelity se změní), max `minutes`.
func _wait_inf(sim: Node, action: String, minutes: int) -> bool:
	for i in minutes:
		clock.advance(1.0)
		if String(sim.last_infidelity.get("action", "")) == action:
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
	var w := _world(11, "user://test-infidelity-%d" % OS.get_process_id())
	var jana = _find(w, "Jana")      # žena, přitahují ji muži
	var petr = _find(w, "Petr")      # muž, přitahují ho ženy
	var eliska = _find(w, "Eliška")  # žena, přitahují ji ženy i muži
	# Čtvrtá postava (svědek) z kanonických dat Jany – jiné jméno a uid, jinak validní CharacterData.
	var wit = null
	if jana != null:
		var cd: Dictionary = w._character_records[String(jana.name)].to_dict()
		cd["uid"] = String(cd.get("uid", "a11ce0000000000a")).substr(0, String(cd.get("uid", "a11ce0000000000a")).length() - 2) + "5e"
		cd["identity"]["first_name"] = "Wanda"
		cd["identity"]["last_name"] = "Svědková"
		wit = w.spawn_character(cd, Vector3(5, 0, 5), 4242)
		if wit != null:
			wit.rng.seed = 99991
	check(jana != null and petr != null and eliska != null and wit != null, "Jana, Petr, Eliška + svědek (%s)" % (wit.first_name() if wit != null else "?"))
	if jana == null or petr == null or eliska == null or wit == null:
		return
	var ro = w.dynamics.romance
	var inf = w.dynamics.infidelity
	check(inf != null and inf.get_script() == Infidelity, "HouseholdDynamics.infidelity")
	check(ro.resolve_ask(petr.sim_name, jana.sim_name, petr.romance_profile(), jana.romance_profile(), 1.0, 0.0, clock.total_minutes) == "yes",
		"Petr a Jana spolu chodí")
	for pr in [[petr, eliska, 92.0], [eliska, petr, 95.0], [jana, petr, 80.0], [petr, jana, 70.0], [wit, petr, 20.0], [jana, wit, 40.0], [wit, jana, 40.0]]:
		pr[0].relationships[pr[1].sim_name] = pr[2]
	eliska.ledger.trust[petr.sim_name] = 85.0
	petr.ledger.trust[eliska.sim_name] = 80.0
	var hl: PackedStringArray = w.relationship_lines(petr)
	check(hl.size() >= 1 and hl[0].begins_with("Vztah: randí – Jana"), "HUD: řádek stavu vztahu (%s)" % ", ".join(hl))

	section("Flirt zadaného před svědkem (bez partnerky)")
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), wit: Vector3(4, 0, 0), jana: Vector3(40, 0, 0)})
	var flirt: Dictionary = ActionLibrary.get_action("flirt")
	check(not flirt.is_empty() and _wait_free(eliska, petr), "Eliška je volná")
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), wit: Vector3(4, 0, 0), jana: Vector3(40, 0, 0)})
	check(petr.command(flirt, eliska), "příkaz Flirtovat přijat")
	check(_wait_inf(petr, "flirt", 200), "flirt proběhl")
	var oc := String(petr.last_infidelity.get("outcome", ""))
	check(oc in ["reciprocated", "brushed_off"], "výsledek %s (šance %.2f)" % [oc, float(petr.last_infidelity.get("p", 0.0))])
	check(String(petr.last_infidelity["betrays"][petr.sim_name]) == jana.sim_name, "Petr je zadaný – flirt je riziko")
	if oc == "reciprocated":
		check(inf.spark(petr.sim_name, eliska.sim_name, clock.total_minutes) > 0.0, "jiskra vznikla")
		check(petr.ledger.guilt_of(jana.sim_name) > 0.0, "Petra hryže svědomí (vina vůči Janě)")
	var wk: String = SimAgent.memory_key(wit)
	var pk: String = SimAgent.memory_key(petr)
	var seen_flirt := false
	for rid in w.gossip.know.get(wk, {}):
		var r: Dictionary = w.gossip.rumors.get(rid, {})
		if not r.is_empty() and String(r["subject"]) == pk and String(r["kind"]) == "flirting":
			seen_flirt = true
	check(seen_flirt, "svědek má drb „flirtuje, i když s někým je“")
	check(inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes) == 0.0, "Jana u toho nebyla – zatím nic netuší")
	for i in 100:
		clock.advance(1.0)

	section("Flirt před vlastní partnerkou → žárlivost")
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(3, 0, 0), wit: Vector3(40, 0, 0)})
	var tries := 0
	var jealous_ok := false
	while tries < 5 and not jealous_ok:
		tries += 1
		petr.last_infidelity = {}
		check(_wait_free(eliska, petr), "Eliška je volná (pokus %d)" % tries)
		_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(3, 0, 0), wit: Vector3(40, 0, 0)})
		if jana._is_sleeping():
			for i in 200:
				clock.advance(1.0)
			continue
		var sat_before: float = ro.satisfaction(jana.sim_name, petr.sim_name)
		petr.command(flirt, eliska)
		if not _wait_inf(petr, "flirt", 200):
			continue
		if jana.mood.has_moodlet("zarli_flirt_" + String(petr.name)):
			jealous_ok = true
			check(inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes) > 0.0, "Jana začíná něco tušit (podezření %.2f)" % inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes))
			check(inf.hint_of(jana.sim_name, petr.sim_name) == eliska.sim_name, "a ví s kým")
			check(ro.satisfaction(jana.sim_name, petr.sim_name) < sat_before, "spokojenost Jany ve vztahu klesla")
		for i in 100:
			clock.advance(1.0)
	check(jealous_ok, "partnerka, která flirt viděla, žárlí (pokusů %d)" % tries)

	section("Drb o nevěře se donese k partnerce")
	var rid2: int = w.gossip_observe(wit, petr, "cheating", 1.0, eliska)
	check(rid2 > 0, "svědek má drb „zahýbá“")
	var s_before: float = inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes)
	w._apply_gossip_event({"type": "shared", "teller": wk, "listener": SimAgent.memory_key(jana), "subject": pk, "rid": rid2,
		"kind": "cheating", "fabricated": false, "truth": true, "belief": 0.8, "belief_gain": 0.8, "delta_rel": -4.0, "bond": 1.0},
		float(clock.total_minutes))
	var s_after: float = inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes)
	check(s_after > s_before + 0.2, "podezření vzrostlo (%.2f → %.2f)" % [s_before, s_after])
	check(inf.hint_of(jana.sim_name, petr.sim_name) == eliska.sim_name, "drb řekl i s kým")
	var jl: PackedStringArray = w.relationship_lines(jana)
	check(", ".join(jl).contains("tají") or ", ".join(jl).contains("nesedí"), "HUD Jany: soukromé tušení (%s)" % ", ".join(jl))
	# Pro další části: podezření zase stáhnout, ať AI Jana nekonfrontuje dřív než hráč (rozhoduje test).
	inf.suspicion.erase(Infidelity.susp_key(jana.sim_name, petr.sim_name))

	section("Tajná schůzka (partnerka daleko)")
	var date_act: Dictionary = ActionLibrary.get_action("secret_date")
	check(w.infidelity_date_block(petr, eliska) in ["", "no_spark"], "brána schůzky z main (%s)" % w.infidelity_date_block(petr, eliska))
	check(w.infidelity_date_block(petr, jana) == "own_partner" and w.infidelity_date_block(eliska, wit) in ["free", "no_spark"], "brány: s partnerkou / dva volní")
	var yes := false
	tries = 0
	while tries < 8 and not yes:
		tries += 1
		inf.sparks[Romance.key(petr.sim_name, eliska.sim_name)] = {"v": 0.9, "t": clock.total_minutes, "last_flirt": clock.total_minutes}
		petr.last_infidelity = {}
		_wait_free(eliska, petr)
		_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(40, 0, 0), wit: Vector3(-40, 0, 0)})
		petr.command(date_act, eliska)
		if _wait_inf(petr, "secret_date", 200) and String(petr.last_infidelity.get("outcome", "")) == "yes":
			yes = true
		for i in 130:
			clock.advance(1.0)
	check(yes, "Eliška kývla (pokusů %d)" % tries)
	check(inf.secret_lover(petr.sim_name, jana.sim_name) == eliska.sim_name and inf.affair_dates(petr.sim_name, eliska.sim_name) >= 1,
		"románek zaznamenán, Jana o něm neví")
	check(not bool(petr.last_infidelity.get("caught", true)), "nikdo je nepřistihl")
	check(petr.ledger.guilt_of(jana.sim_name) > 2.0, "výčitky (vina %.1f)" % petr.ledger.guilt_of(jana.sim_name))
	check(inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes) > 0.0, "Jana si všímá změn v chování (%.3f)" % inf.suspicion_of(jana.sim_name, petr.sim_name, clock.total_minutes))
	var pl: PackedStringArray = w.relationship_lines(petr)
	check(", ".join(pl).contains("Tajný románek: Eliška"), "HUD Petra: tajný románek (%s)" % ", ".join(pl))
	check(ro.status(petr.sim_name, jana.sim_name) == "dating" and ro.partner_of(eliska.sim_name) == "", "veřejný stav se nemění (monogamní model)")

	section("Server (handle_command) – validace")
	var net = w.get("net")
	check(net.handle_command(1, String(petr.name), "secret_date", String(jana.name)) != "", "tajná schůzka s vlastní partnerkou → odmítnuto")
	check(net.handle_command(1, String(eliska.name), "confront_cheating", String(petr.name)) != "", "konfrontace s někým, s kým nechodí → odmítnuto")
	check(net.handle_command(1, String(petr.name), "flirt", String(petr.name)) != "", "flirt sám se sebou → odmítnuto")
	var age0: int = eliska.intimacy.age
	eliska.intimacy.age = 17  # poškozená data: pojistka dospělosti
	check(net.handle_command(1, String(petr.name), "flirt", String(eliska.name)) != "" and net.handle_command(1, String(petr.name), "secret_date", String(eliska.name)) != "",
		"flirt / schůzka s postavou mladší 18 let → odmítnuto (pojistka)")
	eliska.intimacy.age = age0
	var old_mode: int = net.mode
	var old_players: Dictionary = net.players
	net.mode = 1
	net.players = {7: {"sim": String(eliska.name)}}
	check(net.handle_command(1, String(petr.name), "flirt", String(eliska.name)) != "", "flirt s postavou jiného hráče → odmítnuto (AI by odpovídala za něj)")
	check(eliska.romance_owned_by_player() and inf.ai_date_score(petr, eliska, 1.0, ro, clock.total_minutes) == 0.0, "AI nezve na schůzku postavu jiného hráče")
	net.mode = old_mode
	net.players = old_players
	var ok_flirt: String = net.handle_command(1, String(petr.name), "flirt", String(jana.name))
	check(ok_flirt == "", "flirt s vlastní partnerkou přijat (%s)" % ok_flirt)
	petr.command({"id": "cancel"}, null)

	section("AI skóre")
	var now := float(clock.total_minutes)
	jana.global_position = Vector3(1, 0, 0)
	petr.global_position = Vector3(0, 0, 0)
	inf._last_ai.clear()
	petr.hexaco["honesty"] = 0.8
	ro.pairs[Romance.key(petr.sim_name, jana.sim_name)]["sat"][petr.sim_name] = 0.85
	check(inf.ai_flirt_score(petr, eliska, 1.0, ro, now) == 0.0, "spokojený a poctivý Petr s jinými neflirtuje")
	check(inf.ai_flirt_score(petr, jana, 1.0, ro, now) > 0.0, "s vlastní partnerkou ano")
	petr.hexaco["honesty"] = -0.9
	ro.pairs[Romance.key(petr.sim_name, jana.sim_name)]["sat"][petr.sim_name] = 0.15
	check(inf.ai_flirt_score(petr, eliska, 1.0, ro, now) > 0.0, "nespokojený a nepoctivý: pokušení")
	inf.rebuffs[Infidelity.susp_key(petr.sim_name, eliska.sim_name)] = now - 10.0
	check(inf.ai_flirt_score(petr, eliska, 1.0, ro, now) == 0.0, "po odbytí AI 3 dny neflirtuje znovu (Grok #551)")
	inf.rebuffs.clear()
	if not jana._is_sleeping():
		check(inf.ai_date_score(petr, eliska, 1.0, ro, now) == 0.0, "AI si tajnou schůzku nedá, když je partnerka vedle (a vzhůru)")
	jana.global_position = Vector3(40, 0, 0)
	check(inf.ai_date_score(petr, eliska, 1.0, ro, now) > 0.0, "partnerka daleko: AI o schůzce uvažuje")
	eliska.relationships[jana.sim_name] = 70.0
	check(inf.ai_flirt_score(eliska, jana, 1.0, ro, now) == 0.0, "AI neflirtuje s tím, koho romanticky nezajímá (Jana: jen muži)")
	check(inf.ai_flirt_score(eliska, wit, 1.0, ro, now) >= 0.0, "(skóre vůči dalším je definované)")
	check(inf.ai_confront_score(jana, petr, 1.0, ro, now) == 0.0, "bez podezření žádná konfrontace")
	inf.notice(jana.sim_name, petr.sim_name, 0.6, 0.2, "", now)
	check(inf.ai_confront_score(jana, petr, 1.0, ro, now) > 0.0, "s podezřením AI konfrontuje")
	check(inf.ai_confront_score(eliska, petr, 1.0, ro, now) == 0.0, "nepartner nekonfrontuje")
	petr.hexaco["honesty"] = 0.0
	ro.pairs[Romance.key(petr.sim_name, jana.sim_name)]["sat"][petr.sim_name] = 0.6

	section("Konfrontace s důkazy → odhalení a zrada")
	inf.suspicion.erase(Infidelity.susp_key(jana.sim_name, petr.sim_name))
	var rel_before: float = float(jana.relationships.get(petr.sim_name, 0.0))
	var grudge_l: float = jana.ledger.grudge(eliska.sim_name)
	var trust_before: float = jana.ledger.trust_in(petr.sim_name)
	var guilt_before: float = petr.ledger.guilt_of(jana.sim_name)
	jana.last_infidelity = {}
	_wait_free(petr, jana)
	_place(w, {petr: Vector3(0, 0, 0), jana: Vector3(1.5, 0, 0), eliska: Vector3(40, 0, 0), wit: Vector3(-40, 0, 0)})
	# Důkazy až těsně před příkazem (jinak by AI Jana mohla konfrontovat sama dřív než hráč).
	inf.notice(jana.sim_name, petr.sim_name, 0.6, 0.9, eliska.sim_name, float(clock.total_minutes))
	check(jana.command(ActionLibrary.get_action("confront_cheating"), petr), "příkaz Konfrontovat přijat")
	var done := false
	for i in 200:
		clock.advance(1.0)
		if (inf.affairs.get(Romance.key(petr.sim_name, eliska.sim_name), {}).get("known_by", []) as Array).has(jana.sim_name):
			done = true
			break
	var co := String(jana.last_infidelity.get("outcome", ""))
	check(done, "Jana se to dozvěděla (%s)" % str(jana.last_infidelity))
	check(co in ["confess", "caught_lying"], "výsledek konfrontace: %s" % co)
	check(jana.mood.has_moodlet("zrada_" + String(petr.name)), "zrada bolí (moodlet)")
	check(float(jana.relationships.get(petr.sim_name, 0.0)) < rel_before - 15.0, "vztah k Petrovi se propadl (%.0f → %.0f)" % [rel_before, float(jana.relationships.get(petr.sim_name, 0.0))])
	check(jana.ledger.trust_in(petr.sim_name) < trust_before, "důvěra klesla")
	check(jana.ledger.grudge(eliska.sim_name) > grudge_l, "zášť i vůči Elišce")
	check(ro.satisfaction(jana.sim_name, petr.sim_name) < Romance.LOW + 0.05, "spokojenost Jany ve vztahu na dně (%.2f)" % ro.satisfaction(jana.sim_name, petr.sim_name))
	check(w.dynamics.cold_war.heat(petr.sim_name, jana.sim_name) > 0.4, "doma dusno (žár %.2f)" % w.dynamics.cold_war.heat(petr.sim_name, jana.sim_name))
	check(petr.ledger.guilt_of(jana.sim_name) > guilt_before and petr.mood.has_moodlet("prasklo_" + String(jana.name)), "Petr: vina a stud")
	check(ro.status(petr.sim_name, jana.sim_name) in ["dating", "partners", "ex"], "rozchod nevynucen – rozhodne hráč nebo AI (%s)" % ro.status(petr.sim_name, jana.sim_name))
	check(inf.secret_lover(petr.sim_name, jana.sim_name) == "", "už to není tajemství")
	var jk: String = SimAgent.memory_key(jana)
	var told := false
	for rid in w.gossip.know.get(jk, {}):
		var r2: Dictionary = w.gossip.rumors.get(rid, {})
		if not r2.is_empty() and String(r2["subject"]) == pk and String(r2["kind"]) == "cheating" and String(r2["origin"]) == jk:
			told = true
	check(told, "Jana to ví z první ruky – může to říct dál (drb)")
	for i in 70:
		clock.advance(1.0)

	section("Žárlivá scéna bez důvodu")
	if ro.together(petr.sim_name, jana.sim_name):
		jana.last_infidelity = {}
		var rel_p: float = float(petr.relationships.get(jana.sim_name, 0.0))
		_wait_free(petr, jana)
		_place(w, {petr: Vector3(0, 0, 0), jana: Vector3(1.5, 0, 0), eliska: Vector3(40, 0, 0), wit: Vector3(-40, 0, 0)})
		jana.command(ActionLibrary.get_action("confront_cheating"), petr)
		check(_wait_inf(jana, "confront_cheating", 200), "konfrontace proběhla")
		check(String(jana.last_infidelity.get("outcome", "")) == "innocent", "nic dalšího tajného → „nevinný“ (%s)" % str(jana.last_infidelity))
		check(petr.mood.has_moodlet("zarliva_scena_" + String(jana.name)) and float(petr.relationships.get(jana.sim_name, 0.0)) < rel_p,
			"křivé obvinění Petra zraní")
	else:
		check(true, "(AI se mezitím rozešla – scéna přeskočena)")

	section("Přistižení na schůzce")
	if ro.together(petr.sim_name, jana.sim_name):
		var caught := false
		tries = 0
		while tries < 8 and not caught:
			tries += 1
			inf.sparks[Romance.key(petr.sim_name, eliska.sim_name)] = {"v": 0.9, "t": clock.total_minutes, "last_flirt": clock.total_minutes}
			petr.last_infidelity = {}
			_wait_free(eliska, petr)
			_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(3, 0, 0), wit: Vector3(-40, 0, 0)})
			if jana._is_sleeping():
				for i in 200:
					clock.advance(1.0)
				continue
			jana.last_infidelity = {}
			petr.command(date_act, eliska)
			if _wait_inf(petr, "secret_date", 200) and bool(petr.last_infidelity.get("caught", false)):
				caught = true
			for i in 130:
				clock.advance(1.0)
		check(caught, "partnerka vedle → přistižení (pokusů %d)" % tries)
		check(String(jana.last_infidelity.get("outcome", "")) == "caught" or jana.mood.has_moodlet("zrada_" + String(petr.name)), "zrada zpracována (%s)" % str(jana.last_infidelity))
	else:
		check(true, "(AI se mezitím rozešla – přistižení přeskočeno)")

	section("Intimní chvíle mimo vztah (bez detailů)")
	var dates0: int = inf.affair_dates(petr.sim_name, eliska.sim_name)
	_place(w, {petr: Vector3(0, 0, 0), eliska: Vector3(1.5, 0, 0), jana: Vector3(40, 0, 0), wit: Vector3(-40, 0, 0)})
	var mem_before: int = petr.memories.size()
	petr._infidelity_after_intimacy(eliska)
	if ro.together(petr.sim_name, jana.sim_name):
		check(inf.affair_dates(petr.sim_name, eliska.sim_name) == dates0 + 1, "zadaný: počítá se jako nevěra")
	else:
		check(inf.affair_dates(petr.sim_name, eliska.sim_name) == dates0, "po rozchodu už to nevěra není")
	check(petr.memories.size() == mem_before, "žádná vzpomínka s intimním detailem")

	section("Rozchod je novinka (drb)")
	if ro.together(petr.sim_name, jana.sim_name):
		petr.last_romance = {}
		_wait_free(jana, petr)
		_place(w, {petr: Vector3(0, 0, 0), jana: Vector3(1.5, 0, 0), wit: Vector3(4, 0, 0), eliska: Vector3(40, 0, 0)})
		petr.command(ActionLibrary.get_action("break_up"), jana)
		for i in 200:
			clock.advance(1.0)
			if not petr.last_romance.is_empty():
				break
	check(ro.status(petr.sim_name, jana.sim_name) == "ex", "Petr a Jana jsou ex")
	var news := false
	for k in w.gossip.know:
		for rid in w.gossip.know[k]:
			var r3: Dictionary = w.gossip.rumors.get(rid, {})
			if not r3.is_empty() and String(r3["kind"]) == "breakup":
				news = true
	check(news or String(petr.last_romance.get("action", "")) != "break_up", "kdo byl u rozchodu, má novinku")
	var hl2: PackedStringArray = w.relationship_lines(petr)
	check(hl2.size() >= 1 and hl2[0].begins_with("Vztah: bez partnera"), "HUD po rozchodu (%s)" % ", ".join(hl2))

	section("Uložení hry")
	var snap := JSON.stringify(inf.to_dict(), "", true)
	var res: Dictionary = w.save_game("manual")
	check(res.get("ok", false), "save ok", str(res))
	inf.affairs.clear()
	inf.suspicion.clear()
	var ld: Dictionary = w.load_game("manual")
	check(ld.get("ok", false), "load ok", str(ld))
	check(JSON.stringify(w.dynamics.infidelity.to_dict(), "", true) == snap, "stav Infidelity po načtení = stav při uložení")
	w.queue_free()
	await get_tree().process_frame

	section("Výkon")
	var big = Infidelity.new()
	var ro_b = Romance.new()
	for i in 100:
		ro_b.resolve_ask("a%d" % i, "b%d" % i, MAN, WOMAN, 1.0, 0.0, 0.0)
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		var a := "a%d" % (i % 100)
		var c := "b%d" % ((i * 7 + 3) % 100)
		big.resolve_flirt(a, c, ro_b, true, 0.6, float(i % 10) / 10.0, float(i) * 100.0)
		big.notice("b%d" % (i % 100), a, 0.1, 0.05, c, float(i) * 100.0)
	var per := float(Time.get_ticks_usec() - t0) / 2000.0
	check(per < 500.0, "flirt + podezření: %.0f µs/operace (< 0,5 ms)" % per)
	check(big.sparks.size() <= Infidelity.MAX_SPARKS and big.suspicion.size() <= Infidelity.MAX_SUSP, "limity tabulek drženy (%d / %d)" % [big.sparks.size(), big.suspicion.size()])
