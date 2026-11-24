extends "res://tests/test_base.gd"
## Drby (c) – konfrontace zdroje a popření (GossipNetwork v2 + adaptér main.gd + SimAgent + plánovač).
## Ověřuje pravděpodobnosti výsledku, odvolání při přiznání (lež ×0,5 / pravda ×0,8, strop RETRACT_MAX),
## zapření a hádku, popření (nothing / believed / doubted / caught / repeat, sociální důkaz, původce lži),
## spotřebu a expiraci podezření, uložení v2 (round-trip, fuzz, migrace v1), citlivý obsah,
## integraci ve skutečné offline domácnosti, utlumené drby svědků hádky z konfrontace, plánovač AI
## (jen se záští ≥ 20) a pětidenní zátěž bez explozivního růstu zášti.

const Gossip := preload("res://scripts/sim/gossip_network.gd")
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const SA := preload("res://scripts/sim/sim_agent.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

const ALL := {"mental_health": true, "addiction": true}
const NONE := {"mental_health": false, "addiction": false}

var clock: Node
var world: Node


func _ready() -> void:
	watchdog_seconds = 110.0
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	_run.call_deferred()


static func prof(key: String, honesty := 0.5, extra := 0.5, rel := {}, grudge := {}, stigma := 0.0, agree := 0.5) -> Dictionary:
	return {"key": key, "honesty": honesty, "extraversion": extra, "agreeableness": agree, "rel": rel,
		"grudge": grudge, "stigma": stigma}


## Pravdivý drb „src viděl, jak se s hádal“ řečený posluchačům `listeners` (víra nastavená přímo, bez RNG).
static func seed_rumor(g, src: String, subject: String, kind: String, truth: bool, listeners: Array, now := 0.0) -> int:
	var rid: int
	if truth:
		rid = g.observe(src, subject, kind, now, ALL)
	else:
		rid = g._new_rumor(subject, kind, false, src, float(Gossip.KINDS[kind]["sev"]), now, "")
		g._knows(src)[rid] = Gossip._entry(1.0, "", now, float(Gossip.KINDS[kind]["sev"]), 0.0)
		g.know[src][rid]["applied"] = 1.0
	for l in listeners:
		g._knows(l)[rid] = Gossip._entry(0.8, src, now + 1.0, float(Gossip.KINDS[kind]["sev"]), 0.2)
		g._knows(l)[rid]["applied"] = 0.8
		(g.know[src][rid]["told"] as Array).append(l)
	return rid


## Najde seed, pro který dá první hod RNG konfrontace požadovaný výsledek (výsledek závisí jen na 1. randf).
static func seed_for(outcome: String, odds: Dictionary, from := 1) -> int:
	for s in range(from, from + 5000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var x := r.randf()
		var o := "deny"
		if x < float(odds["admit"]):
			o = "admit"
		elif x < float(odds["admit"]) + float(odds["escalate"]):
			o = "escalate"
		if o == outcome:
			return s
	return -1


func _run() -> void:
	_unit_odds()
	_unit_suspects()
	_unit_admit()
	_unit_deny_escalate()
	_unit_denial()
	_unit_persistence()
	await _integration()
	await _soak()
	finish("test_gossip_confront")


# ---------------------------------------------------------------- jednotky

func _unit_odds() -> void:
	section("Pravděpodobnosti výsledku konfrontace")
	var ok_sum := true
	var ok_range := true
	for h in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for a in [0.0, 0.5, 1.0]:
			for sa in [0.0, 0.5, 1.0]:
				for lo in [false, true]:
					var o: Dictionary = Gossip.confront_odds(h, a, sa, lo)
					var s := float(o["admit"]) + float(o["escalate"]) + float(o["deny"])
					if absf(s - 1.0) > 1e-9:
						ok_sum = false
					for k in o:
						if float(o[k]) < 0.0 or float(o[k]) > 1.0:
							ok_range = false
	check(ok_sum and ok_range, "admit + escalate + deny = 1 a všechny v ⟨0; 1⟩ (90 kombinací)")
	check(float(Gossip.confront_odds(1.0, 0.5, 0.5, false)["admit"]) > float(Gossip.confront_odds(0.0, 0.5, 0.5, false)["admit"]),
		"poctivý obviněný přizná spíš než nepoctivý")
	check(float(Gossip.confront_odds(0.5, 1.0, 0.5, false)["admit"]) > float(Gossip.confront_odds(0.5, 0.0, 0.5, false)["admit"]),
		"přívětivý obviněný přizná spíš")
	check(float(Gossip.confront_odds(0.5, 0.5, 0.5, true)["admit"]) < float(Gossip.confront_odds(0.5, 0.5, 0.5, false)["admit"]),
		"kdo lež sám vymyslel, přiznává hůř")
	check(float(Gossip.confront_odds(0.3, 0.0, 0.0, false)["escalate"]) > float(Gossip.confront_odds(0.3, 1.0, 1.0, false)["escalate"]),
		"nepřívětivé strany se spíš pohádají")
	var extreme: Dictionary = Gossip.confront_odds(0.0, 0.0, 0.0, true)
	check(float(extreme["admit"]) >= 0.05 and float(extreme["deny"]) > 0.0, "ani nejhorší kombinace nemá jistý výsledek (přiznání ≥ 5 %)")
	var saint: Dictionary = Gossip.confront_odds(1.0, 1.0, 1.0, false)
	check(float(saint["admit"]) <= 0.9, "ani světec nepřizná se 100% jistotou (≤ 90 %)")
	# Empiricky: rozdělení výsledků sedí s vypočtenými šancemi.
	var counts := {"admit": 0, "deny": 0, "escalate": 0}
	var n := 1500
	var odds: Dictionary = Gossip.confront_odds(0.4, 0.3, 0.4, false)
	for i in n:
		var g = Gossip.new(9000 + i)
		seed_rumor(g, "src", "s", "fight", true, [])
		g._add_suspect("s", "src", g.rumors.keys()[0], 0.0)
		var ev: Dictionary = g.confront(prof("s", 0.5, 0.5, {}, {}, 0.0, 0.4), prof("src", 0.4, 0.5, {}, {}, 0.0, 0.3), 10.0)
		counts[ev["outcome"]] += 1
	var ok_emp := true
	for k in counts:
		if absf(float(counts[k]) / n - float(odds[k])) > 0.045:
			ok_emp = false
	check(ok_emp, "1500 konfrontací: četnosti odpovídají šancím ±4,5 %", "%s vs %s" % [JSON.stringify(counts), JSON.stringify(odds)])


func _unit_suspects() -> void:
	section("Podezřelí: vznik z odhalení, spotřeba, expirace, limity")
	var g = Gossip.new(3)
	check(g.confront(prof("s"), prof("src"), 1.0).is_empty(), "bez podezření konfrontace nic neudělá")
	var rid := seed_rumor(g, "src", "s", "insult", true, ["inf"])
	g.know["inf"][rid]["from"] = "src"
	var exp_ev: Array = []
	for i in 300:
		exp_ev = g.expose(prof("inf", 0.5, 0.5, {"s": 80.0}), prof("s"), 5.0, ALL)
		if not exp_ev.is_empty():
			break
	check(not exp_ev.is_empty() and g.can_confront("s", "src"), "odhalení zdroje → subjekt smí zdroj konfrontovat")
	check(not g.can_confront("s", "inf") and not g.can_confront("src", "s"), "informátor ani opačný směr podezřelí nejsou")
	var su: Dictionary = g.suspects["s"]["src"]
	check(int(su["rid"]) == rid and bool(su["truth"]) and bool(su["origin"]) and String(su["kind"]) == "insult", "podezření nese drb, pravdivost i to, zda je zdroj původcem")
	var lines: PackedStringArray = g.suspect_lines("s")
	check(lines.size() == 0, "bez známého jména žádná soukromá věta (nic neprozradí klíč)")
	g.set_name("src", "Karel Dvořák", "m")
	lines = g.suspect_lines("s")
	check(lines.size() == 1 and lines[0].find("Karel Dvořák") >= 0 and lines[0].find("src") < 0, "soukromá věta se jménem: " + ",".join(lines))
	var ev: Dictionary = g.confront(prof("s"), prof("src"), 6.0)
	check(not ev.is_empty() and not g.can_confront("s", "src"), "konfrontace podezření spotřebuje (žádný spam)")
	check(g.confront(prof("s"), prof("src"), 7.0).is_empty(), "podruhé už není co vyčítat")
	check(g.confront(prof("s"), prof("s"), 7.0).is_empty() and g.confront(prof(""), prof("src"), 7.0).is_empty()
		and g.confront(prof("s"), prof("src"), NAN).is_empty(), "sám se sebou / prázdný klíč / NaN čas odmítnuty")
	# Expirace podle herního času.
	var g2 = Gossip.new(4)
	var r2 := seed_rumor(g2, "src", "s", "fight", true, [])
	g2._add_suspect("s", "src", r2, 0.0)
	g2.tick(Gossip.SUSPECT_TTL_MIN - 120.0)
	check(g2.can_confront("s", "src"), "podezření platí do %d dní" % int(Gossip.SUSPECT_TTL_MIN / 1440.0))
	g2.tick(240.0)
	check(not g2.can_confront("s", "src") and g2.suspects.is_empty(), "po %d dnech podezření vyprší" % int(Gossip.SUSPECT_TTL_MIN / 1440.0))
	# Limit na subjekt: nejstarší vypadne.
	var g3 = Gossip.new(5)
	for i in Gossip.MAX_SUSPECTS + 3:
		var ri := seed_rumor(g3, "z%d" % i, "s", "fight", true, [], float(i))
		g3._add_suspect("s", "z%d" % i, ri, float(i))
	check(g3.suspects["s"].size() == Gossip.MAX_SUSPECTS and not g3.can_confront("s", "z0") and g3.can_confront("s", "z%d" % (Gossip.MAX_SUSPECTS + 2)),
		"nejvýš %d podezřelých na postavu, nejstarší vypadnou" % Gossip.MAX_SUSPECTS)
	# Postava odešla ze světa.
	g3.forget_knower("z%d" % (Gossip.MAX_SUSPECTS + 2))
	check(not g3.can_confront("s", "z%d" % (Gossip.MAX_SUSPECTS + 2)), "odchod postavy smaže podezření na ni")
	g3.forget_knower("s")
	check(not g3.suspects.has("s"), "odchod subjektu smaže jeho podezření")


func _unit_admit() -> void:
	section("Přiznání: odvolání u posluchačů, lež vs. pravda, strop")
	var odds_t: Dictionary = Gossip.confront_odds(0.5, 0.5, 0.5, false)
	var sd := seed_for("admit", odds_t)
	check(sd > 0, "existuje seed s přiznáním")
	# Pravda: posluchači věří dál ×0,8.
	var g = Gossip.new(sd)
	var rid := seed_rumor(g, "src", "s", "fight", true, ["l1", "l2"])
	g._add_suspect("s", "src", rid, 2.0)
	var ev: Dictionary = g.confront(prof("s"), prof("src"), 3.0)
	check(ev.get("outcome", "") == "admit" and int(ev["retracted"]) == 2, "pravdivý drb: přizná a odvolá u obou posluchačů")
	check(absf(g.belief("l1", rid) - 0.8 * 0.8) < 1e-9 and absf(g.belief("l2", rid) - 0.64) < 1e-9, "pravda: víra posluchačů ×0,8")
	check(is_equal_approx(g.belief("src", rid), 1.0), "pravda: svědek sám dál ví, co viděl")
	check(float(ev["delta_subject"]) > 0.0 and float(ev["guilt"]) > 0.0 and float(ev["delta_accused"]) == 0.0, "přiznání trochu spraví vztah, obviněný cítí vinu")
	check(int(g.stats["confronted"]) == 1 and int(g.stats["retracted"]) == 2, "statistiky konfrontací a odvolání")
	# Lež (původce): víra ×0,5 a vlastní lež ×0,3, vina větší.
	var odds_l: Dictionary = Gossip.confront_odds(0.5, 0.5, 0.5, true)
	var sdl := seed_for("admit", odds_l)
	var gl = Gossip.new(sdl)
	var rl := seed_rumor(gl, "liar", "s", "steals", false, ["l1", "l2", "l3"])
	gl._add_suspect("s", "liar", rl, 2.0)
	var evl: Dictionary = gl.confront(prof("s"), prof("liar"), 3.0)
	check(evl.get("outcome", "") == "admit" and bool(evl["origin"]) and not bool(evl["truth"]), "lhář-původce přizná (seed)")
	check(absf(gl.belief("l1", rl) - 0.4) < 1e-9 and absf(gl.belief("liar", rl) - 0.3) < 1e-9, "lež: víra posluchačů ×0,5, vlastní ×0,3")
	check(float(evl["guilt"]) > float(ev["guilt"]), "přiznaná vlastní lež = větší vina než přiznaná pravda")
	check(int(gl.stats["debunked"]) == 0 and gl.belief("l1", rl) >= Gossip.SHARE_MIN_BELIEF, "silně věřená lež (0,8) po odvolání ještě drží (0,4) – jedno přiznání nesmaže vše")
	var gw = Gossip.new(sdl)
	var rw := seed_rumor(gw, "liar", "s", "steals", false, ["l1"])
	gw.know["l1"][rw]["belief"] = 0.5
	gw._add_suspect("s", "liar", rw, 2.0)
	gw.confront(prof("s"), prof("liar"), 3.0)
	check(int(gw.stats["debunked"]) == 1 and gw.belief("l1", rw) < Gossip.SHARE_MIN_BELIEF, "slabší víra (0,5) po odvolání klesne pod hranici šíření (vyvráceno)")
	# Strop: odvolá jen u RETRACT_MAX posledních posluchačů.
	var gc = Gossip.new(sdl)
	var ls: Array = []
	for i in 9:
		ls.append("p%d" % i)
	var rc := seed_rumor(gc, "liar", "s", "steals", false, ls)
	gc._add_suspect("s", "liar", rc, 2.0)
	var evc: Dictionary = gc.confront(prof("s"), prof("liar"), 3.0)
	check(evc.get("outcome", "") == "admit" and int(evc["retracted"]) == Gossip.RETRACT_MAX, "odvolání nejvýš u %d posluchačů (%d)" % [Gossip.RETRACT_MAX, int(evc.get("retracted", -1))])
	var newest_cut := gc.belief("p8", rc) < 0.8 and gc.belief("p%d" % (9 - Gossip.RETRACT_MAX), rc) < 0.8
	var oldest_kept := is_equal_approx(gc.belief("p0", rc), 0.8) and is_equal_approx(gc.belief("p%d" % (8 - Gossip.RETRACT_MAX), rc), 0.8)
	check(newest_cut and oldest_kept, "odvolává u POSLEDNÍCH posluchačů; dřívějším už to nevezme")
	# Posluchač, který drb mezitím zapomněl, se nepočítá.
	var gf = Gossip.new(sd)
	var rf := seed_rumor(gf, "src", "s", "fight", true, ["l1", "l2"])
	gf.know["l2"].erase(rf)
	gf._add_suspect("s", "src", rf, 2.0)
	var evf: Dictionary = gf.confront(prof("s"), prof("src"), 3.0)
	check(evf.get("outcome", "") == "admit" and int(evf["retracted"]) == 1, "zapomenutý drb se neodvolává (počítají se jen skuteční posluchači)")
	# Drb, který mezitím vyhasl úplně: konfrontace pořád dává smysl (údaje v podezření), odvolání 0.
	var gx = Gossip.new(sd)
	var rx := seed_rumor(gx, "src", "s", "fight", true, ["l1"])
	gx._add_suspect("s", "src", rx, 2.0)
	gx.know["l1"][rx]["belief"] = 0.07
	gx.know["src"][rx]["belief"] = 0.07
	gx.tick(2.0 * 1440.0)
	check(gx.rumors.is_empty() and gx.can_confront("s", "src"), "(příprava) drb vyhasl a zmizel, podezření trvá")
	var evx: Dictionary = gx.confront(prof("s"), prof("src"), 3.0)
	check(not evx.is_empty() and evx["outcome"] == "admit" and int(evx["retracted"]) == 0 and String(evx["kind"]) == "fight",
		"vyhaslý drb: konfrontace proběhne z údajů podezření, odvolávat není co")


func _unit_deny_escalate() -> void:
	section("Zapření a hádka")
	var odds_d: Dictionary = Gossip.confront_odds(0.5, 0.5, 0.5, true)
	var sd := seed_for("deny", odds_d)
	var g = Gossip.new(sd)
	var rid := seed_rumor(g, "liar", "s", "badmouth", false, ["l1"])
	g._add_suspect("s", "liar", rid, 2.0)
	var ev: Dictionary = g.confront(prof("s"), prof("liar"), 3.0)
	check(ev.get("outcome", "") == "deny" and float(ev["delta_subject"]) < 0.0 and float(ev["delta_accused"]) < 0.0, "zapření: vztah klesne oběma směry")
	check(float(ev["guilt"]) > 0.0 and is_equal_approx(g.belief("l1", rid), 0.8), "lhář, který zapírá, cítí vinu; u posluchačů se nic neodvolá")
	var sdt := seed_for("deny", Gossip.confront_odds(0.5, 0.5, 0.5, false))
	var gt = Gossip.new(sdt)
	var rt := seed_rumor(gt, "src", "s", "fight", true, ["l1"])
	gt._add_suspect("s", "src", rt, 2.0)
	var evt: Dictionary = gt.confront(prof("s"), prof("src"), 3.0)
	check(evt.get("outcome", "") == "deny" and float(evt["guilt"]) == 0.0 and float(evt["delta_subject"]) > float(ev["delta_subject"]),
		"zapřená pravda bolí subjekt méně než zapřená lež a bez viny")
	var sde := seed_for("escalate", Gossip.confront_odds(0.5, 0.5, 0.5, false))
	var ge = Gossip.new(sde)
	var re := seed_rumor(ge, "src", "s", "fight", true, ["l1"])
	ge._add_suspect("s", "src", re, 2.0)
	var eve: Dictionary = ge.confront(prof("s"), prof("src"), 3.0)
	check(eve.get("outcome", "") == "escalate" and float(eve["delta_subject"]) == 0.0 and int(eve["retracted"]) == 0,
		"hádka: síť nic neodvolá, dopady řeší simulace postav (_social_outcome argue)")
	# Determinismus: stejné kroky → stejné výsledky i stav.
	var a = Gossip.new(77)
	var b = Gossip.new(77)
	for gg in [a, b]:
		for i in 6:
			var ri := seed_rumor(gg, "x%d" % i, "s", "fight", true, ["l"])
			gg._add_suspect("s", "x%d" % i, ri, float(i))
	var oa: Array = []
	var ob: Array = []
	for i in 6:
		oa.append(a.confront(prof("s"), prof("x%d" % i, 0.3), 10.0 + i))
		ob.append(b.confront(prof("s"), prof("x%d" % i, 0.3), 10.0 + i))
	check(JSON.stringify(oa) == JSON.stringify(ob) and JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "konfrontace je deterministická (stejný seed = stejné výsledky)")


func _unit_denial() -> void:
	section("Popření před posluchačem")
	var g = Gossip.new(8)
	var ev: Dictionary = g.deny(prof("s"), prof("l"), 10.0, ALL)
	check(ev.get("outcome", "") == "nothing" and int(ev["rid"]) == 0, "posluchač nic neví → „jaký řeči?“")
	var ev2: Dictionary = g.deny(prof("s"), prof("l"), 11.0, ALL)
	check(ev2.get("outcome", "") == "repeat", "podruhé za den u stejného posluchače → odbyto (žádný grind)")
	check(g.deny(prof("s"), prof("l"), 1440.0 * 2.0, ALL).get("outcome", "") == "nothing", "další den se dá zkusit znovu")
	check(g.deny(prof("s"), prof("s"), 1.0, ALL).is_empty() and g.deny(prof(""), prof("l"), 1.0, ALL).is_empty()
		and g.deny(prof("s"), prof("l"), INF, ALL).is_empty(), "neplatné vstupy odmítnuty")
	# Lež slyšená od jednoho zdroje, neutrální vztah: víra ×(1 − 0,6·0,4).
	var gl = Gossip.new(9)
	var rl := seed_rumor(gl, "liar", "s", "steals", false, ["l"])
	var evl: Dictionary = gl.deny(prof("s"), prof("l"), 5.0, ALL)
	var exp_b := 0.8 * (1.0 - 0.6 * 0.4)
	check(evl.get("outcome", "") == "doubted" and absf(gl.belief("l", rl) - exp_b) < 1e-9, "lež, neutrální vztah: víra klesne na %.3f (pochybuje)" % exp_b)
	check(float(evl["delta_rel"]) > 0.0 and float(evl["delta_rel"]) <= Gossip.EVENT_CAP * 0.5, "část dopadu na vztah se vrátí (strop %.0f)" % (Gossip.EVENT_CAP * 0.5))
	check(float(gl.know["l"][rl]["applied"]) <= gl.belief("l", rl) + 1e-9, "promítnutá víra nepřesáhne skutečnou (žádný dvojí návrat)")
	# Přítel věří víc.
	var gf = Gossip.new(10)
	var rf := seed_rumor(gf, "liar", "s", "steals", false, ["l"])
	gf.know["l"][rf]["belief"] = 0.5
	var evf: Dictionary = gf.deny(prof("s"), prof("l", 0.5, 0.5, {"s": 75.0}), 5.0, ALL)
	check(evf.get("outcome", "") == "believed" and gf.belief("l", rf) < Gossip.SHARE_MIN_BELIEF, "přítel subjektu popření lži uvěří (víra 0,5 → pod hranici šíření)")
	var gf2 = Gossip.new(10)
	var rf2 := seed_rumor(gf2, "liar", "s", "steals", false, ["l"])
	gf2.deny(prof("s"), prof("l", 0.5, 0.5, {"s": -60.0}), 5.0, ALL)
	check(gf2.belief("l", rf2) > 0.6, "kdo subjekt nemá rád, popření skoro nevěří (%.2f)" % gf2.belief("l", rf2))
	# Pravda slyšená z doslechu: popření účinkuje slaběji.
	var gt = Gossip.new(11)
	var rt := seed_rumor(gt, "w", "s", "fight", true, ["l"])
	gt.know["l"][rt]["belief"] = 0.5
	gt.deny(prof("s"), prof("l", 0.5, 0.5, {"s": 75.0}), 5.0, ALL)
	check(gt.belief("l", rt) > gf.belief("l", rf), "popřít pravdu jde hůř než lež (×0,25 vs ×0,6)")
	# Pravda viděná na vlastní oči → caught.
	var evc: Dictionary = gt.deny(prof("s"), prof("w"), 5.0, ALL)
	check(evc.get("outcome", "") == "caught" and float(evc["delta_rel"]) < 0.0 and is_equal_approx(gt.belief("w", rt), 1.0),
		"svědkovi pravdu popřít nejde → „lže mi do očí“ (vztah dolů, víra beze změny)")
	# Sociální důkaz: tři nezávislé zdroje → popření účinkuje méně.
	var g1 = Gossip.new(12)
	var g3 = Gossip.new(12)
	var r1 := seed_rumor(g1, "liar", "s", "steals", false, ["l"])
	var r3 := seed_rumor(g3, "liar", "s", "steals", false, ["l"])
	g3.know["l"][r3]["sources"] = ["liar", "x", "y"]
	g1.deny(prof("s"), prof("l"), 5.0, ALL)
	g3.deny(prof("s"), prof("l"), 5.0, ALL)
	var exp3 := 0.8 * (1.0 - 0.6 * 0.4 / (1.0 + Gossip.DENY_SOURCE_DAMP * 2.0))
	check(g3.belief("l", r3) > g1.belief("l", r1) and absf(g3.belief("l", r3) - exp3) < 1e-9,
		"tři nezávislé zdroje: popření ztlumené na 1/(1+%.1f·2) (%.3f vs %.3f)" % [Gossip.DENY_SOURCE_DAMP, g3.belief("l", r3), g1.belief("l", r1)])
	# Původce lži: popření mu nic nezmění.
	var go = Gossip.new(13)
	var ro := seed_rumor(go, "liar", "s", "steals", false, [])
	var evo: Dictionary = go.deny(prof("s"), prof("liar"), 5.0, ALL)
	check(evo.get("outcome", "") == "nothing" and is_equal_approx(go.belief("liar", ro), 1.0), "lhářovi, který to vymyslel, popření nic nezmění (dělá, že nic neví)")
	# Vybere nejsilnější záporný drb; pozitivní se nepopírá.
	var gp = Gossip.new(14)
	var rk := seed_rumor(gp, "h", "s", "kind", true, ["l"])
	var evp: Dictionary = gp.deny(prof("s"), prof("l"), 5.0, ALL)
	check(evp.get("outcome", "") == "nothing" and is_equal_approx(gp.belief("l", rk), 0.8), "dobrý drb se nepopírá")
	# Citlivý obsah: při vypnutém duševním zdraví se drb o atace nepopírá (nikdo ho nezmiňuje).
	var gs = Gossip.new(15)
	var rp := seed_rumor(gs, "w", "s", "panic", true, ["l"])
	var evs: Dictionary = gs.deny(prof("s"), prof("l"), 5.0, NONE)
	check(evs.get("outcome", "") == "nothing" and is_equal_approx(gs.belief("l", rp), 0.8), "vypnutá témata: citlivý drb se popřením neotevírá")
	var evs2: Dictionary = gs.deny(prof("s"), prof("l2"), 5.0, ALL)
	check(evs2.get("outcome", "") == "nothing", "(kontrola) jiný posluchač nic neví")
	var evs3: Dictionary = gs.deny(prof("s"), prof("l"), 1440.0 * 3.0, ALL)
	check(evs3.get("outcome", "") in ["believed", "doubted"] and float(evs3["delta_rel"]) == 0.0,
		"popření drbu o atace nevrací „dopad“ – nemoc není prohřešek, není co odčinit")
	# Svědek ataky: zapírání = stud, ne lež do očí – vztah ochladí jen stigmatizujícího svědka.
	var gw = Gossip.new(16)
	gw.observe("w", "s", "panic", 0.0, ALL)
	var evw: Dictionary = gw.deny(prof("s"), prof("w", 0.5, 0.5, {}, {}, 0.0), 5.0, ALL)
	var gw2 = Gossip.new(16)
	gw2.observe("w", "s", "panic", 0.0, ALL)
	var evw2: Dictionary = gw2.deny(prof("s"), prof("w", 0.5, 0.5, {}, {}, 0.6), 5.0, ALL)
	check(evw.get("outcome", "") == "caught" and float(evw["delta_rel"]) == 0.0 and absf(float(evw2["delta_rel"]) + 2.4) < 1e-9,
		"zapřená ataka před svědkem: nestigmatizující 0, stigmatizující −4·0,6 (žádný trest za nemoc)")


func _unit_persistence() -> void:
	section("Uložení v2: round-trip, migrace, fuzz podezřelých")
	var g = Gossip.new(21)
	for i in 4:
		var ri := seed_rumor(g, "x%d" % i, "s%d" % (i % 2), "fight" if i % 2 == 0 else "steals", i % 2 == 0, ["l"])
		g._add_suspect("s%d" % (i % 2), "x%d" % i, ri, float(i))
	g.tick(600.0)
	var snap: Dictionary = g.to_dict()
	check(int(snap["v"]) == 2 and Gossip.validate_snapshot(snap) and (snap["suspects"] as Dictionary).size() == 2, "snímek v2 s podezřelými je platný")
	var r = Gossip.new(1)
	check(r.from_dict(bytes_to_var(var_to_bytes(snap))) and JSON.stringify(r.to_dict()) == JSON.stringify(snap), "round-trip podezřelých beze ztráty (včetně stáří)")
	var oa: Dictionary = g.confront(prof("s0"), prof("x0", 0.2), 700.0)
	var orr: Dictionary = r.confront(prof("s0"), prof("x0", 0.2), 700.0)
	check(not oa.is_empty() and JSON.stringify(oa) == JSON.stringify(orr), "po načtení konfrontace dopadne stejně (RNG v uložení)")
	var bad: Array = []
	var m: Dictionary
	var s0: String = snap["suspects"].keys()[0]
	var src0: String = snap["suspects"][s0].keys()[0]
	m = snap.duplicate(true); m["v"] = 1; bad.append(["v1 se suspects", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["age"] = Gossip.SUSPECT_TTL_MIN + 1.0; bad.append(["stáří nad TTL", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["age"] = -1.0; bad.append(["záporné stáří", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["kind"] = "kind"; bad.append(["podezření z dobrého drbu", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["kind"] = "murder"; bad.append(["neznámý druh", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["truth"] = 1; bad.append(["truth typ", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["origin"] = "yes"; bad.append(["origin typ", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["rid"] = 999999; bad.append(["rid ≥ next_id", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["evil"] = 1; bad.append(["pole navíc", m])
	m = snap.duplicate(true); m["suspects"][s0][src0].erase("t"); bad.append(["chybí pole", m])
	m = snap.duplicate(true); m["suspects"][s0][s0] = m["suspects"][s0][src0].duplicate(); bad.append(["podezřelý sám sebe", m])
	m = snap.duplicate(true); m["suspects"][s0] = {}; bad.append(["prázdná mapa", m])
	m = snap.duplicate(true); m["suspects"]["x".repeat(65)] = m["suspects"][s0].duplicate(true); bad.append(["dlouhý klíč", m])
	m = snap.duplicate(true)
	for i in Gossip.MAX_SUSPECTS + 1:
		m["suspects"][s0]["q%d" % i] = m["suspects"][s0][src0].duplicate()
	bad.append(["příliš mnoho podezřelých", m])
	m = snap.duplicate(true); m["suspects"][s0][src0]["kind"] = "steals"; m["suspects"][s0][src0]["truth"] = true; bad.append(["pravdivá krádež", m])
	m = snap.duplicate(true); m["stats"]["confronted"] = -1; bad.append(["záporná statistika", m])
	m = snap.duplicate(true); m["suspects"] = []; bad.append(["suspects typ", m])
	var leaked := ""
	for item in bad:
		if Gossip.validate_snapshot(item[1]):
			leaked += String(item[0]) + "; "
	check(leaked == "", "%d podvržených snímků podezřelých odmítnuto" % bad.size(), leaked)
	var probe = Gossip.new(5)
	var before := JSON.stringify(probe.to_dict())
	check(not probe.from_dict(bad[1][1]) and JSON.stringify(probe.to_dict()) == before, "neplatný snímek stav nezmění")
	var legacy: Dictionary = snap.duplicate(true)
	legacy["v"] = 1
	legacy.erase("suspects")
	for k in ["confronted", "retracted", "denied"]:
		legacy["stats"].erase(k)
	var mg = Gossip.new(2)
	check(mg.from_dict(legacy) and mg.suspects.is_empty() and int(mg.stats["confronted"]) == 0 and int(mg.to_dict()["v"]) == 2,
		"uložení v1 (bez podezřelých a nových statistik) se načte a uloží jako v2")


# ---------------------------------------------------------------- integrace

func _setup_world(tag: String) -> void:
	world = Node3D.new()
	world.set_script(Main)
	world.name = "ConfrontWorld" + tag
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"save_directory": "user://test-lifesim-confront-" + tag + "-" + str(OS.get_process_id()), "autoload": false,
		"autosave": false, "clock": clock}
	add_child(world)
	await get_tree().process_frame


func _integration() -> void:
	section("Integrace: odhalení → konfrontace / popření ve skutečné domácnosti")
	var gs := get_node_or_null("/root/GameSettings")
	var saved_mh = null
	var saved_persist = null
	if gs != null:
		saved_mh = gs.values["mental_health"]
		saved_persist = gs.persist
		gs.persist = false
		gs.values["mental_health"] = "full"
	await _setup_world("i")
	check(world.sims.size() >= 3 and world.gossip != null and int(world.gossip.to_dict()["v"]) == 2, "svět má domácnost a síť drbů v2")
	var a = world.sims[0]
	var b = world.sims[1]
	var c = world.sims[2]
	for s in world.sims:
		s.global_position = Vector3(100.0, 0.0, 100.0)  # ostatní daleko (nejsou svědky)
	for s in [a, b, c]:
		s.global_position = Vector3.ZERO
	var ka: String = SA.memory_key(a)
	var kb: String = SA.memory_key(b)
	var kc: String = SA.memory_key(c)
	# Bez podezření: plánovač ani hradlo konfrontaci nedovolí.
	check(not world.gossip_can_confront(b, c), "bez odhalení b nemůže c nic vyčítat (hradlo serveru i HUD)")
	b.ledger.on_hurt_by(c.sim_name, 60.0, float(clock.total_minutes))
	check(Planner.confront_score(b, c, 1.0) == 0.0, "plánovač: bez podezření ani silná zášť konfrontaci nenabídne")
	# c viděl b urážet a, řekne to a; a má b rád → prozradí b, že to roznáší c.
	world.gossip_observe(c, b, "insult", 1.0, a)
	world._gossip_name(c)
	var rid := 0
	for r in world.gossip.know[kc]:
		rid = int(r)
	world.gossip._knows(ka)[rid] = Gossip._entry(0.9, kc, float(clock.total_minutes), 0.5, 0.1)
	(world.gossip.know[kc][rid]["told"] as Array).append(ka)
	a.relationships[b.sim_name] = 70.0
	var exposed := false
	for i in 300:
		for ev in world.gossip_exchange(a, b):
			if ev["type"] == "exposed" and ev["source"] == kc:
				exposed = true
		if exposed:
			break
	check(exposed and world.gossip_can_confront(b, c), "a prozradí b zdroj → b smí c konfrontovat")
	check(Array(b.psyche_private_lines()).any(func(x): return String(x).find(c.sim_name) >= 0 and String(x).begins_with("Ty řeči")),
		"b vidí v soukromém panelu, od koho řeči šly")
	check(not Array(c.psyche_private_lines()).any(func(x): return String(x).begins_with("Ty řeči")), "c tu větu nevidí")
	# Plánovač: se záští ≥ 20 konfrontaci nabídne, s menší ne.
	var g_now: float = b.ledger.grudge(c.sim_name)
	check(g_now >= Planner.CONFRONT_GRUDGE and Planner.confront_score(b, c, 1.0) > 0.0, "plánovač: podezření + zášť %.0f ≥ %.0f → chce si to vyříkat" % [g_now, Planner.CONFRONT_GRUDGE])
	var b_hx: Dictionary = b.hexaco.duplicate()
	b.hexaco["agreeableness"] = 1.0
	var sc_nice: float = Planner.confront_score(b, c, 1.0)
	b.hexaco["agreeableness"] = -1.0
	var sc_rough: float = Planner.confront_score(b, c, 1.0)
	b.hexaco = b_hx
	check(sc_rough > sc_nice, "nepřívětivý jde do konfrontace ochotněji než přívětivý")
	# Konfrontace skrze SimAgent (repliky, popisky, dopady v main).
	c.hexaco["honesty"] = 1.0
	c.hexaco["agreeableness"] = 1.0
	var odds: Dictionary = Gossip.confront_odds(1.0, 1.0, Main._gossip01(b.hexaco.get("agreeableness", 0.0)), false)
	var gseed := seed_for("admit", odds)
	var snap: Dictionary = world.gossip.to_dict()
	snap["rng_state"] = _state_for_seed(gseed)
	world.gossip.from_dict(snap)
	var rel_bc0: float = float(b.relationships.get(c.sim_name, 0.0))
	var guilt0: float = c.ledger.guilt_of(b.sim_name)
	b._start_gossip_talk(c, ActionLibrary.get_action("confront_gossip").duplicate(true))
	var ev: Dictionary = b.last_gossip_talk
	check(ev.get("outcome", "") == "admit", "poctivý a přívětivý c přizná (deterministický seed)")
	check(float(b.relationships.get(c.sim_name, 0.0)) > rel_bc0 and c.ledger.guilt_of(b.sim_name) > guilt0, "vztah b→c se trochu spraví, c cítí vinu")
	check(b.speech != "" and c.speech != "" and String(b.current_action.get("label", "")).begins_with("Vyříkává si drby"), "obě postavy mluví, akce má popisek: " + String(b.current_action.get("label", "")))
	check(c.social_partner == b, "c se do rozhovoru opravdu zapojí")
	check(not world.gossip_can_confront(b, c), "podezření spotřebováno")
	check(b.mood.has_moodlet("drb_vyjasneno") and c.mood.has_moodlet("drb_nacapan"), "nálady: vyjasněno / načapán(a)")
	# Hádka z konfrontace: svědek si odnese drb se sníženou závažností a násobič se vrátí na 1.
	for s in [a, b, c]:
		s.social_partner = null
		s.current_action = {}
		s.state = SA.State.IDLE
	world.gossip_observe(c, b, "fight", 1.0, a)
	var rid2 := 0
	for r in world.gossip.know[kc]:
		if world.gossip.rumors[r]["kind"] == "fight" and world.gossip.rumors[r]["subject"] == kb:
			rid2 = int(r)
	world.gossip._knows(ka)[rid2] = Gossip._entry(0.9, kc, float(clock.total_minutes), 0.3, 0.1)
	world.gossip._add_suspect(kb, kc, rid2, float(clock.total_minutes))
	c.hexaco["honesty"] = -1.0
	c.hexaco["agreeableness"] = -1.0
	b.hexaco["agreeableness"] = -1.0
	var odds_e: Dictionary = Gossip.confront_odds(0.0, 0.0, 0.0, false)
	var eseed := seed_for("escalate", odds_e)
	var snap2: Dictionary = world.gossip.to_dict()
	snap2["rng_state"] = _state_for_seed(eseed)
	world.gossip.from_dict(snap2)
	clock.total_minutes += 2000.0  # nový den: svědectví se neslije s dřívějším
	b._start_gossip_talk(c, ActionLibrary.get_action("confront_gossip").duplicate(true))
	check(b.last_gossip_talk.get("outcome", "") == "escalate", "nepoctivý a nepřívětivý c to vyhrotí v hádku (seed)")
	var wsev := -1.0
	for r in world.gossip.know.get(ka, {}):
		var rr: Dictionary = world.gossip.rumors[r]
		if rr["kind"] == "fight" and rr["origin"] == ka and float(rr["t"]) >= float(clock.total_minutes) - 1.0:
			wsev = float(rr["sev"])
	check(wsev > 0.0 and absf(wsev - Gossip.KINDS["fight"]["sev"] * SA.GOSSIP_ESCALATION_WITNESS_SEV) < 1e-6,
		"svědek a si z hádky o drbech odnese drb se závažností ×%.1f (%.3f)" % [SA.GOSSIP_ESCALATION_WITNESS_SEV, wsev])
	check(is_equal_approx(b._witness_sev_mult, 1.0), "násobič svědků se po hádce vrátí na 1 (běžné hádky nejsou tlumené)")
	check(String(b.current_action.get("label", "")).begins_with("Hádá se kvůli drbům"), "popisek hádky: " + String(b.current_action.get("label", "")))
	# Popření přes SimAgent: posluchač nic neví → krátká odpověď, bez zapojení.
	for s in [a, b, c]:
		s.social_partner = null
		s.current_action = {}
		s.state = SA.State.IDLE
	var d = world.sims[3] if world.sims.size() > 3 else null
	if d != null:
		d.global_position = Vector3.ZERO
		a._start_gossip_talk(d, ActionLibrary.get_action("deny_gossip").duplicate(true))
		check(a.last_gossip_talk.get("outcome", "") == "nothing" and d.social_partner == null and d.speech != "",
			"popření před někým, kdo nic neví: krátká odpověď, druhého nezabere do rozhovoru")
	var net_g0 = world.gossip
	# Popření před svědkem pravdy (c viděl urážku na vlastní oči) → caught, vztah dolů.
	for s in [a, b, c]:
		s.social_partner = null
		s.current_action = {}
		s.state = SA.State.IDLE
	var rel_cb0: float = float(c.relationships.get(b.sim_name, 0.0))
	b._start_gossip_talk(c, ActionLibrary.get_action("deny_gossip").duplicate(true))
	check(b.last_gossip_talk.get("outcome", "") == "caught" and float(c.relationships.get(b.sim_name, 0.0)) < rel_cb0,
		"b popírá před svědkem c → přistižen při lži, c si o b myslí hůř")
	for s in [a, b, c]:
		s.social_partner = null
		s.current_action = {}
		s.state = SA.State.IDLE
	b._start_gossip_talk(c, ActionLibrary.get_action("deny_gossip").duplicate(true))
	check(b.last_gossip_talk.get("outcome", "") == "repeat", "opakované popření týž den → odbyto")
	# Ataka viděná na vlastní oči: svědek reaguje laskavě a nepamatuje si to jako zradu důvěry.
	if gs != null:
		for s in [a, b, c]:
			s.social_partner = null
			s.current_action = {}
			s.state = SA.State.IDLE
		world.gossip = Gossip.new(4)
		world.gossip_observe(a, c, "panic")
		c._start_gossip_talk(a, ActionLibrary.get_action("deny_gossip").duplicate(true))
		check(c.last_gossip_talk.get("outcome", "") == "caught" and String(c.last_gossip_talk.get("kind", "")) == "panic"
			and (a.speech.find("stydět") >= 0 or a.speech.find("Stává se") >= 0) and c.mood.has_moodlet("drb_vi_o_tom") and not c.mood.has_moodlet("drb_nevericnost"),
			"zapřená ataka: svědek odpoví laskavě („%s“), žádné „lže mi do očí“" % a.speech)
		world.gossip = net_g0
	# Akce v knihovně: popření je jen hráčské, konfrontace i pro AI (ale jen přes plánovač s hradlem).
	check(bool(ActionLibrary.get_action("deny_gossip").get("player_only", false)) and not bool(ActionLibrary.get_action("confront_gossip").get("player_only", false)),
		"popření dělá jen hráč; konfrontaci i AI")
	# Uložení hry s podezřelými.
	world.gossip._add_suspect(ka, kc, rid2, float(clock.total_minutes))
	var cap: Dictionary = SaveGame.capture(world)
	check(cap.get("ok", false) and (cap["data"]["gossip"]["suspects"] as Dictionary).has(ka), "GameSave ukládá podezřelé")
	var snap_before := JSON.stringify(world.gossip.to_dict())
	var applied: Dictionary = SaveGame.apply(world, cap["data"])
	await get_tree().process_frame
	check(applied.get("ok", false) and JSON.stringify(world.gossip.to_dict()) == snap_before, "načtení hry obnoví podezřelé přesně")
	var a2 = world.sims[0]
	var c2 = world.sims[2]
	check(world.gossip_can_confront(a2, c2), "po načtení hry jde konfrontovat stejně (klíče postav = uid)")
	# Klient bez autority: nic nepočítá.
	var net_g = world.gossip
	world.gossip = null
	check(world.gossip_talk(a2, c2, "confront_gossip").is_empty() and not world.gossip_can_confront(a2, c2), "peer bez sítě drbů nic nepočítá ani nepovolí")
	world.gossip = net_g
	world.free()
	world = null
	if gs != null:
		gs.values["mental_health"] = saved_mh
		gs.persist = saved_persist


## Stav RNG po nastavení seedu (pro vložení do snímku – jen v testu).
static func _state_for_seed(s: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r.state


# ---------------------------------------------------------------- zátěž

func _soak() -> void:
	section("Zátěž: 5 herních dní intrik bez explozivní spirály")
	var gs := get_node_or_null("/root/GameSettings")
	var saved_persist = null
	if gs != null:
		saved_persist = gs.persist
		gs.persist = false
	await _setup_world("s")
	# Nepoctiví nepřívětiví povídálci, všichni na sebe naštvaní (zášť 25) a každý den znovu „ví“,
	# kdo o něm co roznáší (umělá maximální intrika) → AI konfrontuje, hádky z konfrontací plodí drby.
	for s in world.sims:
		s.hexaco["honesty"] = -0.8
		s.hexaco["extraversion"] = 0.8
		s.hexaco["agreeableness"] = -0.5
		for o in world.sims:
			if o != s:
				s.ledger.on_hurt_by(o.sim_name, 25.0, float(clock.total_minutes))
	var means: Array = []
	var t0 := Time.get_ticks_msec()
	for day in 5:
		for s in world.sims:
			for o in world.sims:
				if o != s:
					var rr: int = world.gossip_observe(o, s, "fight")
					if rr > 0:
						world.gossip._add_suspect(SA.memory_key(s), SA.memory_key(o), rr, float(clock.total_minutes))
		clock.advance(1440.0)
		var tot := 0.0
		var n := 0
		for s in world.sims:
			for o in world.sims:
				if o != s:
					tot += s.ledger.grudge(o.sim_name)
					n += 1
		means.append(tot / maxf(n, 1))
	var ms := Time.get_ticks_msec() - t0
	var st: Dictionary = world.gossip.stats
	print("    průměrná zášť po dnech: %s; stats %s; %d ms" % [str(means.map(func(x): return snappedf(x, 0.01))), JSON.stringify(st), ms])
	var finite := true
	for s in world.sims:
		for k in s.relationships:
			if not is_finite(float(s.relationships[k])):
				finite = false
	check(finite and Gossip.validate_snapshot(world.gossip.to_dict()), "vztahy konečné, stav sítě platný")
	check(int(st["confronted"]) >= 1, "AI si za 5 dní opravdu něco vyříkala (%d konfrontací)" % int(st["confronted"]))
	var explosive := false
	for i in range(2, means.size()):
		var d1: float = float(means[i - 1]) - float(means[i - 2])
		var d2: float = float(means[i]) - float(means[i - 1])
		if d1 > 1.0 and d2 > 2.0 * d1:
			explosive = true
	check(not explosive and float(means[-1]) < 60.0, "průměrná zášť neroste explozivně a zůstává pod 60 (%.1f)" % float(means[-1]))
	check(float(means[-1]) <= float(means[0]) * 1.5 + 5.0, "ani při maximální intrice zášť za 5 dní nevyletí (%.1f → %.1f)" % [float(means[0]), float(means[-1])])
	world.free()
	world = null
	if gs != null:
		gs.persist = saved_persist
