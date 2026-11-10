extends "res://tests/test_base.gd"
## Drby a pomluvy (GossipNetwork + adaptér v main.gd): vznik ze svědectví, šíření a víra, zkreslení,
## smyšlené pomluvy, odhalení zdroje, vyvracení zkušeností, vyhasínání, obsahová nastavení,
## determinismus, uložení (round-trip + fuzz) a integrace do skutečné offline domácnosti.

const Gossip := preload("res://scripts/sim/gossip_network.gd")
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const SA := preload("res://scripts/sim/sim_agent.gd")

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


static func prof(key: String, honesty := 0.5, extra := 0.5, rel := {}, grudge := {}, stigma := 0.0) -> Dictionary:
	return {"key": key, "honesty": honesty, "extraversion": extra, "rel": rel, "grudge": grudge, "stigma": stigma}


## Opakuje share, dokud se drb opravdu neřekne (RNG), max n pokusů.
static func share_until(g, t: Dictionary, l: Dictionary, now: float, content := ALL, facts := {}, n := 200) -> Array:
	for i in n:
		var ev: Array = g.share(t, l, now, content, facts)
		if not ev.is_empty():
			return ev
	return []


static func expose_until(g, i: Dictionary, s: Dictionary, now: float, content := ALL, n := 200) -> Array:
	for k in n:
		var ev: Array = g.expose(i, s, now, content)
		if not ev.is_empty():
			return ev
	return []


func _run() -> void:
	_unit_observe()
	_unit_share()
	_unit_fabrication()
	_unit_sensitive()
	_unit_expose_contact()
	_unit_time_limits()
	_unit_persistence()
	await _integration()
	finish("test_gossip")


# ---------------------------------------------------------------- jednotky

func _unit_observe() -> void:
	section("Svědectví: pravdivý drb vzniká jen z toho, co někdo viděl")
	var g = Gossip.new(7)
	var rid: int = g.observe("w", "s", "fight", 100.0, ALL)
	check(rid > 0 and g.rumors[rid]["truth"] == true and g.rumors[rid]["origin"] == "w", "hádka viděná svědkem = pravdivý drb s původcem")
	check(is_equal_approx(g.belief("w", rid), 1.0) and String(g.know["w"][rid]["from"]) == "", "svědek věří naplno a ví to z vlastních očí")
	check(g.observe("w", "s", "fight", 600.0, ALL) == rid and g.rumors.size() == 1, "stejné svědectví do jednoho dne jen obnoví (žádné duplikáty)")
	check(g.observe("w", "s", "fight", 100.0 + 1500.0, ALL) != rid, "po dni je to nová událost")
	check(g.observe("w", "w", "fight", 1.0, ALL) == 0, "nikdo není svědkem sám sebe")
	check(g.observe("", "s", "fight", 1.0, ALL) == 0 and g.observe("w", "s", "nonsense", 1.0, ALL) == 0, "prázdný klíč a neznámý druh odmítnuty")
	check(g.observe("w", "s", "steals", 1.0, ALL) == 0 and g.observe("w", "s", "badmouth", 1.0, ALL) == 0, "smyšlené druhy nejdou „vidět“")
	check(g.observe("w", "s", "fight", NAN, ALL) == 0 and g.observe("w", "s", "fight", INF, ALL) == 0, "NaN/INF čas odmítnut")
	check(g.observe("w", "x".repeat(65), "fight", 1.0, ALL) == 0, "příliš dlouhý klíč odmítnut")


func _unit_share() -> void:
	section("Šíření: víra = důvěra × věrohodnost, sociální důkaz, zkreslení, žádné farmení")
	var g = Gossip.new(11)
	var rid: int = g.observe("t", "s", "fight", 0.0, ALL)
	var t := prof("t", 0.0, 1.0)
	var l := prof("l", 0.5, 0.5)
	var ev: Array = share_until(g, t, l, 10.0)
	check(ev.size() == 1 and ev[0]["type"] == "shared" and int(ev[0]["rid"]) == rid, "povídavý nepoctivý vypravěč drb nakonec řekne")
	var e: Dictionary = g.know["l"][rid]
	var dist := 0.08 + 0.14
	var b_exp := 0.55 * 1.0 * (1.0 - 0.3 * dist)
	check(absf(float(e["belief"]) - b_exp) < 1e-6, "víra neutrálního posluchače = 0,55·(1−0,3·zkreslení)", "%.4f vs %.4f" % [e["belief"], b_exp])
	check(absf(float(e["dist"]) - dist) < 1e-6 and float(e["sev"]) > float(g.rumors[rid]["sev"]), "převyprávění přidá zkreslení a závažnost")
	var d_exp := -14.0 * b_exp * 0.3 * (1.0 + 0.6 * dist)
	check(absf(float(ev[0]["delta_rel"]) - d_exp) < 1e-4 and float(ev[0]["delta_rel"]) < 0.0, "vztah posluchače k subjektu klesne podle přírůstku víry", "%.3f vs %.3f" % [ev[0]["delta_rel"], d_exp])
	check(g.share(t, l, 20.0, ALL).is_empty() or g.share(t, l, 20.0, ALL)[0]["rid"] != rid, "stejný drb stejnému posluchači podruhé neřekne")
	check(share_until(g, t, prof("s"), 30.0, ALL, {}, 60).is_empty(), "subjektu jeho vlastní drb vypravěč neřekne")
	# Posluchač, který subjekt má rád, věří méně než ten, kdo ho nesnáší.
	var g2 = Gossip.new(12)
	var r2: int = g2.observe("t", "s", "insult", 0.0, ALL)
	share_until(g2, t, prof("fan", 0.5, 0.5, {"s": 80.0}), 1.0)
	share_until(g2, t, prof("hater", 0.5, 0.5, {"s": -60.0}), 1.0)
	check(g2.belief("fan", r2) < g2.belief("hater", r2), "kdo subjekt má rád, věří drbu méně", "%.3f < %.3f" % [g2.belief("fan", r2), g2.belief("hater", r2)])
	# Důvěra k vypravěči.
	var g3 = Gossip.new(13)
	var r3: int = g3.observe("t", "s", "fight", 0.0, ALL)
	share_until(g3, t, prof("friend", 0.5, 0.5, {"t": 90.0}), 1.0)
	share_until(g3, t, prof("foe", 0.5, 0.5, {"t": -90.0}), 1.0)
	check(g3.belief("friend", r3) > g3.belief("foe", r3), "kamarádovi vypravěče se věří víc než nepříteli")
	# Sociální důkaz: druhý nezávislý zdroj víru složí, stejný zdroj ne.
	var g4 = Gossip.new(14)
	var r4: int = g4.observe("a", "s", "fight", 0.0, ALL)
	share_until(g4, prof("a", 0.0, 1.0), prof("b", 0.0, 1.0), 1.0)
	share_until(g4, prof("a", 0.0, 1.0), prof("l2"), 2.0)
	var b1: float = g4.belief("l2", r4)
	var ev4: Array = share_until(g4, prof("b", 0.0, 1.0), prof("l2"), 3.0)
	check(ev4.size() == 1 and g4.belief("l2", r4) > b1, "druhý nezávislý zdroj víru zvýší (sociální důkaz)", "%.3f → %.3f" % [b1, g4.belief("l2", r4)])
	check((g4.know["l2"][r4]["sources"] as Array) == ["a", "b"], "zdroje se evidují")
	check(float(ev4[0]["delta_rel"]) <= 0.0 and absf(float(ev4[0]["delta_rel"])) < absf(-14.0 * b1 * 0.5), "druhý zdroj přidá jen dopad PŘÍRŮSTKU víry")
	# Řetěz: zkreslení roste s každým převyprávěním.
	var dist_c: float = g4.know["b"][r4]["dist"]
	# Bez důvěry víra s každým skokem slábne a drb pod hranicí 0,3 dál nejde; mezi přáteli dojde dál.
	share_until(g4, prof("b", 0.0, 1.0), prof("c", 0.5, 0.5, {"b": 90.0}), 4.0)
	share_until(g4, prof("c", 0.0, 1.0), prof("d", 0.5, 0.5, {"c": 90.0}), 5.0)
	check(g4.know.has("d") and g4.know["d"].has(r4), "mezi přáteli drb dojde přes tři převyprávění")
	if not (g4.know.has("d") and g4.know["d"].has(r4)):
		return
	var gw = Gossip.new(18)
	var rw: int = gw.observe("a", "s", "fight", 0.0, ALL)
	share_until(gw, prof("a", 0.0, 1.0), prof("b", 0.5, 0.5, {"a": -80.0}), 1.0)
	check(gw.belief("b", rw) < Gossip.SHARE_MIN_BELIEF and share_until(gw, prof("b", 0.0, 1.0), prof("c"), 2.0, ALL, {}, 100).is_empty(),
		"nedůvěryhodnému vypravěči se nevěří a drb dál nejde")
	check(float(g4.know["d"][r4]["dist"]) > float(g4.know["c"][r4]["dist"]) and float(g4.know["c"][r4]["dist"]) > dist_c, "zkreslení roste s délkou řetězu")
	check(float(g4.know["d"][r4]["sev"]) >= float(g4.know["c"][r4]["sev"]), "vnímaná závažnost se nafukuje")
	# Poctivý vypravěč zkresluje méně a povídá méně.
	var gh = Gossip.new(15)
	var rh: int = gh.observe("h", "s", "fight", 0.0, ALL)
	var shared_h := 0
	var shared_d := 0
	for i in 400:
		var gx = Gossip.new(1000 + i)
		gx.observe("h", "s", "fight", 0.0, ALL)
		if not gx.share(prof("h", 1.0, 0.0), prof("l"), 1.0, ALL).is_empty():
			shared_h += 1
		var gy = Gossip.new(1000 + i)
		gy.observe("h", "s", "fight", 0.0, ALL)
		if not gy.share(prof("h", 0.0, 1.0), prof("l"), 1.0, ALL).is_empty():
			shared_d += 1
	check(shared_d > shared_h * 2 and shared_h > 0, "nepoctivý povídavý šíří víc než poctivý introvert (%d vs %d ze 400)" % [shared_d, shared_h])
	share_until(gh, prof("h", 1.0, 0.0), prof("l"), 1.0, ALL, {}, 2000)
	check(gh.know.has("l") and float(gh.know["l"][rh]["dist"]) < 0.1, "poctivý vypravěč zkreslí jen málo")
	# Denní strop dopadu na dvojici (nedá se „ubít“ drby).
	var gc = Gossip.new(16)
	var total := 0.0
	for k in 12:
		var w := "w%d" % k
		gc.observe(w, "s", "insult", 0.0, ALL)
		var ev5: Array = share_until(gc, prof(w, 0.0, 1.0), prof("l", 0.5, 0.5, {w: 90.0, "s": -90.0}), 10.0)
		if not ev5.is_empty():
			total += float(ev5[0]["delta_rel"])
	check(total < 0.0 and absf(total) <= Gossip.DAILY_PAIR_CAP + 1e-6, "denní strop dopadu na dvojici posluchač–subjekt (%.2f)" % total)
	var ev6: Array = []
	gc.observe("w99", "s", "insult", 1450.0, ALL)
	ev6 = share_until(gc, prof("w99", 0.0, 1.0), prof("l", 0.5, 0.5, {"w99": 90.0, "s": -90.0}), 1450.0)
	check(not ev6.is_empty() and float(ev6[0]["delta_rel"]) < 0.0, "další den strop začíná znovu")
	# Sbližování drbáním má denní strop 3 body na dvojici.
	var gb = Gossip.new(19)
	var bond_sum := 0.0
	for k in 8:
		gb.observe("t", "s%d" % k, "fight", 0.0, ALL)
	for k in 8:
		var evb: Array = share_until(gb, prof("t", 0.0, 1.0), prof("l"), 5.0)
		if not evb.is_empty():
			bond_sum += float(evb[0]["bond"])
	check(int(gb.stats["shared"]) == 8 and absf(bond_sum - Gossip.BOND_DAILY_CAP) < 1e-6, "8 drbů za den: sblížení jen do stropu %.0f (%.1f)" % [Gossip.BOND_DAILY_CAP, bond_sum])
	# Pozitivní drb.
	var gp = Gossip.new(17)
	gp.observe("helped", "s", "kind", 0.0, ALL)
	var evp: Array = share_until(gp, prof("helped", 0.3, 1.0, {"s": 70.0}), prof("l"), 1.0)
	check(not evp.is_empty() and float(evp[0]["delta_rel"]) > 0.0, "„pomohl mi, když bylo zle“ zlepší pověst subjektu")
	check(String(gp.line_for(int(evp[0]["rid"]))).find("%") < 0, "replika je složená (žádné zbylé %s)")


func _unit_fabrication() -> void:
	section("Smyšlené pomluvy: jen nízká poctivost + zášť vůči třetí osobě")
	var honest := 0
	var liar := 0
	var calm := 0
	var steals_true := 0
	var badmouth_ok := true
	for i in 600:
		var g = Gossip.new(5000 + i)
		var ev: Array = g.share(prof("t", 0.9, 1.0, {"c": -95.0}, {"c": 90.0}), prof("l"), 1.0, ALL)
		honest += ev.size()
		var g2 = Gossip.new(5000 + i)
		var facts := {"rel": {"c": {"l": -60.0}}}
		var ev2: Array = g2.share(prof("t", 0.0, 1.0, {"c": -90.0}, {"c": 80.0}), prof("l"), 1.0, ALL, facts)
		if not ev2.is_empty():
			liar += 1
			var r: Dictionary = g2.rumors[int(ev2[0]["rid"])]
			if r["kind"] == "steals" and bool(r["truth"]):
				steals_true += 1
			if r["kind"] == "badmouth" and (not bool(r["truth"]) or r["whom"] != "l" or r["subject"] != "c"):
				badmouth_ok = false
			if not bool(ev2[0]["fabricated"]) or r["origin"] != "t":
				badmouth_ok = false
		var g3 = Gossip.new(5000 + i)
		calm += g3.share(prof("t", 0.0, 1.0, {"c": -20.0}, {"c": 10.0}), prof("l"), 1.0, ALL).size()
	check(honest == 0, "poctivý (H 0,9) si nevymýšlí ani při silné zášti (600 pokusů)")
	check(liar > 30 and liar < 400, "nepoctivý se zášť si občas vymyslí (%d/600)" % liar)
	check(calm == 0, "bez silné zášti (< 35) žádná smyšlenka")
	check(steals_true == 0, "„bral věci“ je vždy lež (krádeže ve hře zatím nejsou)")
	check(badmouth_ok, "„mluví o tobě za zády“: subjekt c, týká se posluchače, pravdivé jen když c posluchače opravdu nesnáší")
	var g4 = Gossip.new(77)
	var evf: Array = []
	for i in 300:
		evf = g4.share(prof("t", 0.0, 1.0, {"c": -90.0}, {"c": 80.0}), prof("l"), 1.0, ALL, {"rel": {"c": {"l": 50.0}}})
		if not evf.is_empty() and g4.rumors[int(evf[0]["rid"])]["kind"] == "badmouth":
			break
	check(not evf.is_empty() and not bool(g4.rumors[int(evf[0]["rid"])]["truth"]), "když c posluchače má rád, je „mluví za zády“ lež")


func _unit_sensitive() -> void:
	section("Citlivý obsah: psychika a závislosti podle nastavení, stigma podle posluchače")
	var g = Gossip.new(21)
	check(g.observe("w", "s", "panic", 0.0, NONE) == 0, "ataka paniky se při vypnutém/ztlumeném duševním zdraví nedrbe")
	check(g.observe("w", "s", "drinking", 0.0, NONE) == 0, "pití se nedrbe, když jsou závislosti vypnuté")
	var rp: int = g.observe("w", "s", "panic", 0.0, ALL)
	var rd: int = g.observe("w", "s", "drinking", 0.0, ALL)
	check(rp > 0 and rd > 0, "v plném režimu svědectví vznikne")
	check(share_until(g, prof("w", 0.0, 1.0), prof("l"), 1.0, NONE, {}, 100).is_empty(), "po vypnutí témat se už existující citlivé drby nešíří")
	var calm: Array = share_until(g, prof("w", 0.0, 1.0), prof("l", 0.5, 0.5, {}, {}, 0.0), 2.0)
	var calm_ev: Dictionary = calm[0] if not calm.is_empty() else {}
	check(not calm_ev.is_empty(), "v plném režimu se citlivý drb šíří")
	var g2 = Gossip.new(22)
	var rp2: int = g2.observe("w", "s", "panic", 0.0, ALL)
	var ok_kind := true
	var d_open := 0.0
	var d_stig := 0.0
	var ev_o: Array = share_until(g2, prof("w", 0.0, 1.0), prof("open", 0.5, 0.5, {}, {}, 0.0), 1.0)
	var ev_s: Array = share_until(g2, prof("w", 0.0, 1.0), prof("stig", 0.5, 0.5, {}, {}, 0.6), 1.0)
	if not ev_o.is_empty() and ev_o[0]["kind"] == "panic":
		d_open = float(ev_o[0]["delta_rel"])
	else:
		ok_kind = false
	if not ev_s.is_empty() and ev_s[0]["kind"] == "panic":
		d_stig = float(ev_s[0]["delta_rel"])
	else:
		ok_kind = false
	check(ok_kind and d_open == 0.0, "nestigmatizující posluchač si kvůli atace o subjektu nemyslí nic horšího")
	check(ok_kind and d_stig < 0.0, "stigmatizující posluchač ano (stigma je vlastnost posluchače, ne subjektu)")
	var line_p: String = g2.line_for(rp2)
	var line_d: String = g.line_for(rd)
	check(line_p.findn("panik") < 0 and line_p.findn("atak") < 0 and line_d.findn("pij") < 0 and line_d.findn("chlast") < 0,
		"repliky citlivých drbů nahlas neříkají detail (soukromí v MP)", line_p + " | " + line_d)


func _unit_expose_contact() -> void:
	section("Odhalení zdroje a vyvracení vlastní zkušeností")
	var g = Gossip.new(31)
	var rid: int = g.observe("src", "s", "insult", 0.0, ALL)
	share_until(g, prof("src", 0.0, 1.0), prof("inf"), 1.0)
	check(g.know.has("inf"), "informátor drb slyšel od zdroje")
	check(expose_until(g, prof("inf", 0.5, 0.5, {"s": 10.0}), prof("s"), 2.0, ALL, 100).is_empty(), "kdo subjekt nemá rád (< 20), neprozradí mu nic")
	check(expose_until(g, prof("src", 0.5, 0.5, {"s": 90.0}), prof("s"), 2.0, ALL, 100).is_empty(), "svědek sám nic „neprozrazuje“ (mluví jen o slyšeném)")
	var b_before: float = g.belief("inf", rid)
	var ev: Array = expose_until(g, prof("inf", 0.5, 0.5, {"s": 70.0}), prof("s"), 3.0)
	check(ev.size() == 1 and ev[0]["source"] == "src" and bool(ev[0]["origin_known"]), "subjekt se dozví bezprostřední zdroj (tady i původce)")
	check(float(ev[0]["delta_source"]) < -6.0 and bool(ev[0]["truth"]), "pravdivý drb: vztah ke zdroji klesne (stud, zmírněno ×0,7)")
	check(g.belief("inf", rid) < b_before and absf(g.belief("inf", rid) - b_before * 0.85) < 1e-6, "subjekt se brání → informátor pravdě věří o něco méně")
	check(expose_until(g, prof("inf", 0.5, 0.5, {"s": 90.0}), prof("s"), 4.0, ALL, 100).is_empty(), "stejný drb se subjektu neprozradí dvakrát")
	check(g.exposed_lines("s").size() == 1, "subjekt má soukromou větu, co se o něm povídá")
	# Lež bolí víc a informátor jí po obraně věří méně; původce zůstane skrytý, když je řetěz delší.
	var g2 = Gossip.new(32)
	var evf: Array = []
	for i in 400:
		evf = g2.share(prof("liar", 0.0, 1.0, {"c": -90.0}, {"c": 90.0}), prof("mid", 0.3, 0.5), 1.0, ALL, {"rel": {"c": {"mid": 40.0}}})
		if not evf.is_empty():
			break
	check(not evf.is_empty(), "lhář vypustí pomluvu")
	var rf: int = int(evf[0]["rid"])
	share_until(g2, prof("mid", 0.0, 1.0), prof("inf"), 2.0)
	var bf: float = g2.belief("inf", rf)
	var subj := String(g2.rumors[rf]["subject"])
	var ev2: Array = expose_until(g2, prof("inf", 0.5, 0.5, {subj: 80.0}), prof(subj), 3.0)
	check(ev2.size() == 1 and ev2[0]["source"] == "mid" and not bool(ev2[0]["origin_known"]), "delší řetěz: subjekt zná jen toho, kdo to šířil dál, ne lháře")
	check(not bool(ev2[0]["truth"]) and absf(g2.belief("inf", rf) - bf * 0.6) < 1e-6, "lež: obrana subjektu víru informátora sníží ×0,6")
	check(float(ev2[0]["delta_source"]) < -(Gossip.EXPOSE_BASE), "lež: vztah subjektu ke zdroji klesne naplno")
	# Kontakt: dobrá zkušenost vyvrací lež rychleji než pravdu.
	var g3 = Gossip.new(33)
	var rt: int = g3.observe("w", "s", "fight", 0.0, ALL)
	share_until(g3, prof("w", 0.0, 1.0), prof("l"), 1.0)
	var rl: int = g3._new_rumor("s", "steals", false, "w", 0.6, 1.0, "")
	g3.know["l"][rl] = Gossip._entry(g3.belief("l", rt), "w", 1.0, 0.6, 0.2)
	var bt0: float = g3.belief("l", rt)
	for i in 6:
		g3.contact("l", "s")
	check(g3.belief("l", rl) < g3.belief("l", rt), "šest dobrých rozhovorů: lži věří méně než pravdě")
	check(absf(g3.belief("l", rl) - bt0 * pow(0.85, 6)) < 1e-6 and absf(g3.belief("l", rt) - bt0 * pow(0.95, 6)) < 1e-6, "přesné koeficienty vyvracení (0,85 lež / 0,95 pravda)")
	check(g3.belief("w", rt) == 1.0, "co svědek viděl sám, mu rozhovor nevymluví")


func _unit_time_limits() -> void:
	section("Čas, zapomínání a limity")
	var a = Gossip.new(41)
	var b = Gossip.new(41)
	var ra: int = a.observe("w", "s", "fight", 0.0, ALL)
	b.observe("w", "s", "fight", 0.0, ALL)
	for i in 120:
		a.tick(30.0)
	b.tick(3600.0)
	check(absf(a.belief("w", ra) - b.belief("w", ra)) < 1e-6, "vyhasínání nezávisí na délce kroku")
	check(absf(a.belief("w", ra) - exp(-3600.0 / Gossip.BELIEF_TAU_MIN)) < 1e-6, "τ = 12 herních dní")
	a.tick(60.0 * 1440.0)
	check(a.rumors.is_empty() and a.know.is_empty() and int(a.stats["forgotten"]) == 1, "po dvou měsících zapomenuto a drb zmizel")
	var g = Gossip.new(42)
	for i in 300:
		g.observe("w%d" % (i % 7), "s%d" % (i % 13), "fight", float(i) * 2000.0, ALL)
	check(g.rumors.size() <= Gossip.MAX_RUMORS, "nejvýš %d drbů (%d)" % [Gossip.MAX_RUMORS, g.rumors.size()])
	var over := false
	for k in g.know:
		if g.know[k].size() > Gossip.MAX_KNOWN:
			over = true
	check(not over, "nejvýš %d znalostí na postavu" % Gossip.MAX_KNOWN)
	var g2 = Gossip.new(43)
	for i in 260:
		g2.observe("k%d" % i, "s", "fight", float(i), ALL)
	check(g2.know.size() <= Gossip.MAX_KNOWERS, "nejvýš %d znalců (%d)" % [Gossip.MAX_KNOWERS, g2.know.size()])
	for i in 300:
		g2.set_name("n%d" % i, "Jméno", "f")
	check(g2.names.size() <= Gossip.MAX_NAMES, "jmen nejvýš %d" % Gossip.MAX_NAMES)
	check(Gossip.validate_snapshot(g2.to_dict()), "i po zaplnění limitů je snímek platný")
	var gf = Gossip.new(44)
	gf.set_name("s", "Jana Nováková", "f")
	var rf: int = gf.observe("w", "s", "insult", 0.0, ALL)
	share_until(gf, prof("w", 0.0, 1.0), prof("inf"), 1.0)
	expose_until(gf, prof("inf", 0.5, 0.5, {"s": 80.0}), prof("s"), 2.0)
	var lines: PackedStringArray = gf.exposed_lines("s")
	check(lines.size() == 1 and lines[0].find("urazila") >= 0, "čeština podle gramatického rodu subjektu", ",".join(lines))
	check(gf.line_for(rf).begins_with("Jana ") and gf.line_for(rf).find("sjela") >= 0, "replika s křestním jménem a rodem: " + gf.line_for(rf))


func _unit_persistence() -> void:
	section("Determinismus, uložení a striktní validace")
	var a = _scenario(99)
	var b = _scenario(99)
	check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "stejný seed + stejné kroky = bit po bitu stejný stav")
	var c = _scenario(100)
	check(JSON.stringify(a.to_dict()) != JSON.stringify(c.to_dict()), "jiný seed = jiný průběh")
	var snap: Dictionary = a.to_dict()
	check(Gossip.validate_snapshot(snap), "snímek je platný")
	var bytes := var_to_bytes(snap)
	var r = Gossip.new(1)
	check(r.from_dict(bytes_to_var(bytes)), "načtení z binárního snímku (jako GameSave)")
	check(JSON.stringify(r.to_dict()) == JSON.stringify(snap), "round-trip beze ztráty")
	# Pokračování po načtení je identické (stav RNG).
	var cont_a: Array = []
	var cont_r: Array = []
	for i in 40:
		cont_a.append_array(a.share(prof("p%d" % (i % 5), 0.1, 0.9, {"p0": -60.0}, {"p0": 70.0}), prof("q%d" % (i % 3)), 50000.0 + i, ALL))
		cont_r.append_array(r.share(prof("p%d" % (i % 5), 0.1, 0.9, {"p0": -60.0}, {"p0": 70.0}), prof("q%d" % (i % 3)), 50000.0 + i, ALL))
	check(JSON.stringify(cont_a) == JSON.stringify(cont_r) and JSON.stringify(a.to_dict()) == JSON.stringify(r.to_dict()), "po načtení pokračuje stejně jako bez přerušení")
	# Fuzz / podvržené snímky.
	var bad: Array = []
	var m: Dictionary
	m = snap.duplicate(true); m["evil"] = 1; bad.append(["neznámý klíč", m])
	m = snap.duplicate(true); m["v"] = 2; bad.append(["verze", m])
	m = snap.duplicate(true); m["rng_state"] = 1.5; bad.append(["rng typ", m])
	m = snap.duplicate(true); m["rumors"][0]["truth"] = "yes"; bad.append(["truth typ", m])
	m = snap.duplicate(true); m["rumors"][0]["sev"] = 1.5; bad.append(["sev rozsah", m])
	m = snap.duplicate(true); m["rumors"][0]["sev"] = NAN; bad.append(["sev NaN", m])
	m = snap.duplicate(true); m["rumors"][0]["kind"] = "murder"; bad.append(["neznámý druh", m])
	m = snap.duplicate(true); m["rumors"][0]["id"] = 999999; bad.append(["id ≥ next_id", m])
	m = snap.duplicate(true); m["rumors"].append(m["rumors"][0].duplicate()); bad.append(["duplicitní id", m])
	m = snap.duplicate(true); m["rumors"][0]["kind"] = "steals"; m["rumors"][0]["truth"] = true; bad.append(["pravdivá krádež", m])
	m = snap.duplicate(true); m["rumors"][0]["subject"] = ""; bad.append(["prázdný subjekt", m])
	var k0: String = m["know"].keys()[0]
	m = snap.duplicate(true); m["know"][k0][0]["belief"] = 1.01; bad.append(["víra > 1", m])
	m = snap.duplicate(true); m["know"][k0][0]["rid"] = 424242; bad.append(["znalost neexistujícího drbu", m])
	m = snap.duplicate(true); m["know"][k0][0]["from"] = k0; bad.append(["slyšel to sám od sebe", m])
	m = snap.duplicate(true); m["know"][k0][0]["told"] = range(13).map(func(x): return "x%d" % x); bad.append(["told > limit", m])
	m = snap.duplicate(true); m["know"][k0][0]["sources"] = [1, 2]; bad.append(["sources typ", m])
	m = snap.duplicate(true); m["know"][k0][0].erase("applied"); bad.append(["chybí pole", m])
	m = snap.duplicate(true); m["know"][k0].append(m["know"][k0][0].duplicate(true)); bad.append(["duplicitní znalost", m])
	m = snap.duplicate(true); m["names"]["zz"] = {"n": "X", "g": "x"}; bad.append(["neplatný rod", m])
	m = snap.duplicate(true); m["names"]["zz"] = {"n": "X".repeat(41), "g": "m"}; bad.append(["dlouhé jméno", m])
	m = snap.duplicate(true); m["stats"]["hack"] = 1; bad.append(["neznámá statistika", m])
	m = snap.duplicate(true); m["exposed"] = {"s": {"abc": 1.0}}; bad.append(["exposed klíč není číslo", m])
	m = snap.duplicate(true); m["impact_day"] = {"a|b": [1, 99.0]}; bad.append(["denní dopad nad strop", m])
	m = snap.duplicate(true); m["rumors"] = range(161).map(func(x): return {}); bad.append(["příliš mnoho drbů", m])
	var all_rejected := true
	var leaked := ""
	for item in bad:
		if Gossip.validate_snapshot(item[1]):
			all_rejected = false
			leaked += String(item[0]) + "; "
	check(all_rejected, "%d podvržených snímků odmítnuto" % bad.size(), leaked)
	var probe = Gossip.new(5)
	var before := JSON.stringify(probe.to_dict())
	check(not probe.from_dict(bad[3][1]) and JSON.stringify(probe.to_dict()) == before, "neplatný snímek stav nezmění")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var crash_free := true
	var accepted := 0
	for i in 300:
		var junk: Variant
		match i % 4:
			0: junk = rng.randi()
			1: junk = {"v": 1, "rng_state": rng.randi(), "next_id": rng.randi_range(-5, 5), "rumors": [], "know": {}, "exposed": {}, "impact_day": {}, "names": {}, "stats": {}}
			2: junk = {"v": 1, "rng_state": 1, "next_id": 5, "rumors": [{"id": 1, "subject": "s", "kind": "fight", "truth": rng.randf() < 0.5, "origin": "o", "sev": rng.randf_range(-1.0, 2.0), "t": 0.0, "whom": ""}], "know": {"k": [{"rid": rng.randi_range(0, 3)}]}, "exposed": {}, "impact_day": {}, "names": {}, "stats": {}}
			3: junk = {"v": 1, "rumors": [{"id": rng.randi()}]}
		if Gossip.validate_snapshot(junk):
			accepted += 1
	check(crash_free and accepted <= 75, "300 náhodných vstupů bez pádu; přijaty jen strukturně platné prázdné snímky (%d)" % accepted)


func _scenario(seed: int):
	var g = Gossip.new(seed)
	for i in 30:
		g.observe("p%d" % (i % 5), "p%d" % ((i + 1) % 5), ["fight", "insult", "kind", "drinking"][i % 4], float(i) * 300.0, ALL)
	for i in 120:
		var t := "p%d" % (i % 5)
		var l := "p%d" % ((i * 3 + 1) % 5)
		if t == l:
			continue
		g.share(prof(t, float(i % 3) * 0.3, 0.8, {"p2": -50.0}, {"p2": 60.0}), prof(l, 0.5, 0.5, {t: 30.0}), 9000.0 + i * 10.0, ALL)
		g.expose(prof(l, 0.5, 0.5, {t: 60.0}), prof(t), 9000.0 + i * 10.0, ALL)
		if i % 7 == 0:
			g.contact(t, l)
		g.tick(10.0)
	return g


# ---------------------------------------------------------------- integrace

func _integration() -> void:
	section("Integrace: skutečná offline domácnost (main.gd + SimAgent)")
	var gs := get_node_or_null("/root/GameSettings")
	var saved_mh = null
	var saved_persist = null
	if gs != null:
		saved_mh = gs.values["mental_health"]
		saved_persist = gs.persist
		gs.persist = false
		gs.values["mental_health"] = "full"
	world = Node3D.new()
	world.set_script(Main)
	world.name = "GossipWorld"
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"save_directory": "user://test-lifesim-gossip-" + str(OS.get_process_id()), "autoload": false,
		"autosave": false, "clock": clock}
	add_child(world)
	await get_tree().process_frame
	check(world.sims.size() >= 3 and world.gossip != null, "svět má domácnost a síť drbů")
	var a = world.sims[0]
	var b = world.sims[1]
	var c = world.sims[2]
	check(typeof(a.hexaco) == TYPE_DICTIONARY and a.hexaco.has("honesty"), "postava má HEXACO z PsycheModel (poctivost pro drby)")
	for s in [a, b, c]:
		s.position = Vector3.ZERO
		s.global_position = Vector3.ZERO
	# Hádka a–b, c je svědek → c ví o hádce obou.
	a._social_outcome(b, -5.0, "argue")
	var kc: String = SA.memory_key(c)
	var ka: String = SA.memory_key(a)
	var kb: String = SA.memory_key(b)
	var fights := 0
	for rid in world.gossip.know.get(kc, {}):
		var r: Dictionary = world.gossip.rumors[rid]
		if r["kind"] == "fight" and r["origin"] == kc and (r["subject"] == ka or r["subject"] == kb):
			fights += 1
	check(fights == 2, "svědek hádky ví o obou stranách (hook _witness_conflict)")
	# c (nepoctivý povídálek) řekne a, co viděl(a) o b.
	c.hexaco = {"honesty": -1.0, "extraversion": 1.0}
	a.hexaco = {"honesty": 0.0, "extraversion": 0.0}
	a.relationships[c.sim_name] = 40.0
	a.relationships[b.sim_name] = 0.0
	var rel_ab0: float = a.relationships[b.sim_name]
	var shared: Dictionary = {}
	for i in 200:
		for ev in world.gossip_exchange(c, a):
			if ev["type"] == "shared" and ev["teller"] == kc and ev["listener"] == ka and ev["subject"] == kb:
				shared = ev
		if not shared.is_empty():
			break
	check(not shared.is_empty(), "při povedeném rozhovoru c řekne a drb o b")
	check(float(a.relationships[b.sim_name]) < rel_ab0, "a si o b myslí hůř (%.2f → %.2f)" % [rel_ab0, a.relationships[b.sim_name]])
	check(c.speech != "" and c.speech.find("hádal") >= 0, "c to řekne nahlas: " + c.speech)
	var heard := false
	for m in a.memories:
		if String(m.get("text", "")).begins_with("Drb od"):
			heard = true
	check(heard, "a si pamatuje, od koho drb slyšel(a)")
	# a má b rád → prozradí mu, že to šíří c.
	a.relationships[b.sim_name] = 70.0
	var rel_bc0: float = float(b.relationships.get(c.sim_name, 0.0))
	var exposed: Dictionary = {}
	for i in 300:
		for ev in world.gossip_exchange(a, b):
			if ev["type"] == "exposed" and ev["subject"] == kb and ev["informer"] == ka:
				exposed = ev
		if not exposed.is_empty():
			break
	check(not exposed.is_empty() and exposed["source"] == kc, "a prozradí b, že to o něm roznáší c")
	check(float(b.relationships.get(c.sim_name, 0.0)) < rel_bc0, "b má c rád(a) méně (%.1f → %.1f)" % [rel_bc0, b.relationships.get(c.sim_name, 0.0)])
	check(b.ledger.grudge(c.sim_name) > 0.0, "b chová vůči c zášť")
	check(b.mood.has_moodlet("drb_stud") or b.mood.has_moodlet("drb_pomluva"), "b to zasáhne (moodlet)")
	check(Array(b.psyche_private_lines()).any(func(x): return String(x).begins_with("Lidi si o mně povídají")), "b vidí v soukromém panelu, co se o něm povídá")
	check(not Array(c.psyche_private_lines()).any(func(x): return String(x).find("povídají") >= 0), "c tu větu nevidí (soukromé)")
	# Pomoc → pozitivní drb.
	c.receive_support_from(a)
	var kinds := 0
	for rid in world.gossip.know.get(kc, {}):
		if world.gossip.rumors[rid]["kind"] == "kind" and world.gossip.rumors[rid]["subject"] == ka:
			kinds += 1
	check(kinds == 1, "kdo zažil pomoc, ví o pomocníkovi dobrý drb (hook receive_support_from)")
	# Nastavení obsahu: ztlumené duševní zdraví → ataka se nedrbe.
	if gs != null:
		gs.values["mental_health"] = "muted"
		check(world.gossip_observe(c, a, "panic") == 0, "ztlumený režim: ataka se nedrbe (adaptér čte GameSettings)")
		gs.values["mental_health"] = "full"
		check(world.gossip_observe(c, a, "panic") > 0, "plný režim: svědectví ataky vznikne")
		c.mood.remove_moodlet("drbani")
		world.gossip = Gossip.new(5)
		var gp2 = world.gossip
		var rpanic: int = world.gossip_observe(c, b, "panic")
		var sp: Dictionary = {}
		for i in 200:
			var evs: Array = gp2.share(world.gossip_profile(c), world.gossip_profile(a), float(clock.total_minutes), world.gossip_content())
			if not evs.is_empty():
				sp = evs[0]
				break
		var had_mood := false
		if not sp.is_empty() and sp["kind"] == "panic":
			var before_m: bool = c.mood.has_moodlet("drbani")
			world._apply_gossip_event(sp, float(clock.total_minutes))
			had_mood = c.mood.has_moodlet("drbani") and not before_m
		check(rpanic > 0 and not had_mood, "za drb o atace nedostane vypravěč žádný dobrý pocit (nic se neodměňuje)")
		gs.values["addiction"] = false
		check(world.gossip_observe(c, a, "drinking") == 0, "vypnuté závislosti: pití se nedrbe")
		gs.values["addiction"] = true
	# Uložení hry: sekce gossip.
	var cap: Dictionary = SaveGame.capture(world)
	check(cap.get("ok", false) and cap["data"].has("gossip"), "GameSave ukládá drby")
	check(SaveGame.validate_data(cap["data"], world).get("ok", false), "uložená data projdou validací")
	var corrupt: Dictionary = cap["data"].duplicate(true)
	corrupt["gossip"]["v"] = 99
	check(SaveGame.validate_data(corrupt, world).get("reason", "") == "bad_gossip", "podvržená sekce drbů → bad_gossip (před smazáním domácnosti)")
	var snap_before := JSON.stringify(world.gossip.to_dict())
	var applied: Dictionary = SaveGame.apply(world, cap["data"])
	await get_tree().process_frame
	check(applied.get("ok", false) and JSON.stringify(world.gossip.to_dict()) == snap_before, "načtení hry obnoví drby přesně")
	var legacy: Dictionary = cap["data"].duplicate(true)
	legacy.erase("gossip")
	var applied2: Dictionary = SaveGame.apply(world, legacy)
	await get_tree().process_frame
	check(applied2.get("ok", false) and world.gossip.rumors.is_empty(), "starší uložená hra bez drbů: začne se s čistou sítí")
	# Krátká simulace: drby běží v domácnosti bez chyb.
	# Hook v SimAgent._social_outcome: povedený rozhovor spustí výměnu drbů (postavy jsou po načtení nové).
	a = world.sims[0]
	b = world.sims[1]
	c = world.sims[2]
	for s in [a, b, c]:
		s.global_position = Vector3.ZERO
	world.gossip = Gossip.new(3)
	c.hexaco = {"honesty": -1.0, "extraversion": 1.0}
	world.gossip_observe(c, b, "insult", 1.0, a)
	var via_hook := false
	for i in 120:
		c._social_outcome(a, 3.0, "chat")
		if int(world.gossip.stats["shared"]) > 0:
			via_hook = true
			break
	check(via_hook, "hook: povedený rozhovor (SimAgent._social_outcome) drby opravdu šíří")
	var before_n: int = int(world.gossip.stats["shared"])
	c._social_outcome(a, -3.0, "argue")
	check(int(world.gossip.stats["shared"]) == before_n, "při hádce se drby nevyměňují")
	world.gossip = Gossip.new(3)
	var t0 := Time.get_ticks_msec()
	clock.advance(5.0 * 1440.0)
	var ms := Time.get_ticks_msec() - t0
	var finite := true
	for s in world.sims:
		for k in s.relationships:
			if not is_finite(float(s.relationships[k])):
				finite = false
	check(finite, "po 5 herních dnech jsou vztahy konečné (%d ms, %s)" % [ms, JSON.stringify(world.gossip.stats)])
	check(Gossip.validate_snapshot(world.gossip.to_dict()), "stav sítě po simulaci je platný snímek")
	world.free()
	world = null
	if gs != null:
		gs.values["mental_health"] = saved_mh
		gs.persist = saved_persist
