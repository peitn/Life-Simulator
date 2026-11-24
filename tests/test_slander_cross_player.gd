extends "res://tests/test_base.gd"
## Pomluva přes hranici hráčů (23. 11. 2026): SlanderPolicy (scripts/net/slander_policy.gd) + main.rivalry_slander
## / rivalry_slander_verdict + NetSession (RPC verdiktu, soukromý seznam, vypršení) – uzavírá otevřený nález
## auditu rivality „posluchač může být postava jiného hráče“.
## Ověřuje: jednotky politiky (vlastnictví, typy, limity, TTL, rewind, strop na oběť, sanitizace klientského
## seznamu), fuzz, offline beze změny, skutečné ENet (dedikovaný server + 2 klienti): odložený dopad, soukromé
## doručení jen vlastníkovi, podvržené verdikty, verdikty believe/tell/default, strop na oběť přes handle_command.
## Spuštění: godot_run scene=res://tests/test_slander_cross_player.tscn

const Main := preload("res://main.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const GameClockScript := preload("res://scripts/core/game_clock.gd")
const SlanderPolicy := preload("res://scripts/net/slander_policy.gd")
const Rivalry := preload("res://scripts/sim/rivalry.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")

var clock: Node
var port := 0
var notices := {}


func _ready() -> void:
	watchdog_seconds = 110.0
	randomize()
	port = 27800 + randi() % 600
	clock = get_node("/root/GameClock")
	clock.running = false
	clock.set_speed(0)
	clock.total_minutes = 2000.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	_units()
	_fuzz()
	_offline()
	await _multiplayer()
	clock.running = false
	finish("test_slander_cross_player")


# ------------------------------------------------------------------ jednotky
func _units() -> void:
	section("SlanderPolicy: verdikty, vlastnictví, typy")
	var pol = SlanderPolicy.new()
	var d := {"author_name": "Eva", "rival_name": "Jan", "line": "Jan prý krade.", "author_node": "SimA",
		"listener_node": "SimB", "rival_node": "SimR"}
	var r1: Dictionary = pol.open("SimB", d, 100.0)
	check(int(r1["vid"]) == 1 and (r1["dropped"] as Array).is_empty(), "otevřený verdikt vid 1")
	check(int(pol.open("", d, 100.0)["vid"]) == 0, "bez vlastníka se neotevře")
	check(int(pol.open("SimB", d, NAN)["vid"]) == 0, "NaN čas se odmítne")
	check(pol.pending_count("SimB") == 1 and pol.pending_count() == 1, "počet čekajících")
	check(String(pol.resolve("SimC", 1, "believe")["reason"]) == "owner" and pol.pending_count() == 1,
		"cizí postava verdikt nevyřídí (owner) a nic nezmizí")
	check(String(pol.resolve("SimB", 1.0, "believe")["reason"]) == "type", "vid jako float → type")
	check(String(pol.resolve("SimB", "1", "believe")["reason"]) == "type", "vid jako String → type")
	check(String(pol.resolve("SimB", 1, 3)["reason"]) == "type", "volba jako int → type")
	check(String(pol.resolve("SimB", 1, "default")["reason"]) == "choice", "„default“ klient poslat nesmí (choice)")
	check(String(pol.resolve("SimB", 99, "believe")["reason"]) == "unknown", "neexistující vid → unknown")
	check(String(pol.resolve("", 1, "believe")["reason"]) == "owner", "prázdný vlastník → owner")
	var ok: Dictionary = pol.resolve("SimB", 1, "tell")
	check(bool(ok["ok"]) and String(ok["entry"]["owner"]) == "SimB" and String(ok["entry"]["data"]["line"]) == "Jan prý krade.",
		"vlastník verdikt vyřídí a dostane data")
	check(String(pol.resolve("SimB", 1, "tell")["reason"]) == "unknown", "dvojí vyřízení nejde")
	d["author_name"] = "Změněno"
	check(String(ok["entry"]["data"]["author_name"]) == "Eva", "data se při otevření hluboce kopírují")

	section("SlanderPolicy: limit na hráče, TTL a rewind")
	var pl = SlanderPolicy.new()
	var first := 0
	for i in SlanderPolicy.MAX_PENDING_PER_PEER:
		var v := int(pl.open("SimB", {"line": str(i)}, 100.0 + i)["vid"])
		if i == 0:
			first = v
	var over: Dictionary = pl.open("SimB", {"line": "navíc"}, 120.0)
	check((over["dropped"] as Array).size() == 1 and int(over["dropped"][0]["vid"]) == first,
		"přetečení uzavře NEJSTARŠÍ verdikt (vrácen k výchozímu vyhodnocení)")
	check(pl.pending_count("SimB") == SlanderPolicy.MAX_PENDING_PER_PEER, "hráč má nejvýš %d čekajících" % SlanderPolicy.MAX_PENDING_PER_PEER)
	pl.open("SimC", {"line": "c"}, 100.0)
	check(pl.pending_for("SimB").size() == SlanderPolicy.MAX_PENDING_PER_PEER and pl.pending_for("SimC").size() == 1,
		"seznam pro vlastníka obsahuje jen jeho verdikty")
	var pt = SlanderPolicy.new()
	pt.open("SimB", {"line": "a"}, 100.0)
	pt.open("SimB", {"line": "b"}, 500.0)
	check(pt.expire(100.0 + SlanderPolicy.VERDICT_TTL - 0.1).is_empty(), "těsně před lhůtou nic nevyprší")
	var ex: Array = pt.expire(100.0 + SlanderPolicy.VERDICT_TTL)
	check(ex.size() == 1 and String(ex[0]["data"]["line"]) == "a", "přesně po 12 h vyprší (hranice včetně)")
	check(pt.expire(200.0).is_empty() and pt.pending_count() == 1, "rewind: verdikt „z budoucnosti“ nevyprší ani nezmizí")
	check(pt.expire(NAN).is_empty(), "NaN čas nic nevyprší")
	var dropped: Array = pt.drop_owner("SimB")
	check(dropped.size() == 1 and pt.pending_count() == 0, "odchod postavy uzavře její verdikty")
	var long_name := "x".repeat(300)
	var ps = SlanderPolicy.new()
	ps.open("SimB", {"author_name": long_name, "rival_name": long_name, "line": long_name}, 1.0)
	var it: Array = ps.pending_for("SimB")[0]
	check(String(it[1]).length() == SlanderPolicy.MAX_NAME_LEN and String(it[3]).length() == SlanderPolicy.MAX_LINE_LEN,
		"shrnutí pro klienta je délkově omezené")
	check(ps.vids_mentioning("SimB").size() == 0, "vids_mentioning hledá jen v uzlech postav (ne jménech)")

	section("SlanderPolicy: strop pomluv na oběť")
	var pv = SlanderPolicy.new()
	for i in SlanderPolicy.VICTIM_DAILY_CAP:
		check(not pv.victim_capped("SimR", 1000.0 + i), "pomluva %d/%d ještě projde" % [i + 1, SlanderPolicy.VICTIM_DAILY_CAP])
		pv.note_victim("SimR", 1000.0 + i)
	check(pv.victim_capped("SimR", 1010.0), "po %d pomluvách za den je oběť „vyčerpaná“" % SlanderPolicy.VICTIM_DAILY_CAP)
	check(not pv.victim_capped("SimQ", 1010.0), "strop je na oběť, ne globální")
	check(pv.victim_capped("SimR", 1000.0 + SlanderPolicy.DAY - 0.5), "strop drží do konce okna 24 h")
	check(not pv.victim_capped("SimR", 1002.0 + SlanderPolicy.DAY), "po 24 h od poslední se okno uvolní")
	var pr = SlanderPolicy.new()
	for i in 3:
		pr.note_victim("SimR", 5000.0)
	check(not pr.victim_capped("SimR", 4000.0) and pr.victim_count("SimR", 4000.0) == 0, "rewind: budoucí záznamy se nepočítají")
	check(pr.victim_capped("SimR", 5000.0), "…a začnou platit, až čas dožene")
	var pm = SlanderPolicy.new()
	for i in SlanderPolicy.MAX_VICTIMS + 20:
		pm.note_victim("Sim%d" % i, float(i))
	check(pm._victims.size() <= SlanderPolicy.MAX_VICTIMS, "paměť obětí omezená (%d)" % pm._victims.size())
	for i in 50:
		pm.note_victim("SimSpam", 9000.0)
	check((pm._victims["SimSpam"] as Array).size() <= SlanderPolicy.VICTIM_DAILY_CAP * 2, "záznamy jedné oběti omezené")

	section("Klient: sanitizace seznamu verdiktů")
	var clean: Array = SlanderPolicy.sanitize_inbox([[1, "E\u202Eva\u0000", "Jan\u200B", "Řekl\u0007a \u2066mi\u2069 to."], [0, "x", "y", "z"],
		[2, "", "Jan", "a"], [3, 5, "Jan", "a"], "špatně", [4, "A", "B"], [5.0, "A", "B", "c"]])
	check(clean.size() == 1 and String(clean[0][1]) == "Eva" and String(clean[0][2]) == "Jan" and String(clean[0][3]) == "Řekla mi to.",
		"řídicí a bidi znaky pryč, neplatné položky zahozené", str(clean))
	check(SlanderPolicy.sanitize_inbox("x").is_empty() and SlanderPolicy.sanitize_inbox(null).is_empty(), "ne-pole → prázdný seznam")
	var many: Array = []
	for i in 30:
		many.append([i + 1, "A", "B", "c"])
	check(SlanderPolicy.sanitize_inbox(many).size() == SlanderPolicy.MAX_PENDING_PER_PEER, "nejvýš %d položek" % SlanderPolicy.MAX_PENDING_PER_PEER)


func _fuzz() -> void:
	section("Fuzz: resolve a sanitizace na náhodných datech")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pol = SlanderPolicy.new()
	for i in 5:
		pol.open("SimB", {"line": "x"}, 10.0)
	var junk := [null, 1, -1, 0, 3.5, NAN, INF, "1", "believe", "", "tell\u0000", [], {}, [1], Vector2.ONE, true, 2147483647, -2147483648]
	var bad_ok := 0
	for i in 400:
		var v = junk[rng.randi() % junk.size()]
		var c = junk[rng.randi() % junk.size()]
		var owner: String = ["SimB", "SimX", ""][rng.randi() % 3]
		var r: Dictionary = pol.resolve(owner, v, c)
		if bool(r["ok"]):
			# Platné je jen (SimB, int 1..5, believe/dismiss/tell) – junk obsahuje jen "believe" a int 1.
			if not (owner == "SimB" and typeof(v) == TYPE_INT and typeof(c) == TYPE_STRING and String(c) in SlanderPolicy.CHOICES):
				bad_ok += 1
	check(bad_ok == 0, "žádné neplatné (vlastník/typ/volba) vyřízení neprošlo z 400 pokusů")
	var crashes := 0
	for i in 300:
		var pkt: Array = []
		for j in rng.randi_range(0, 12):
			var item: Array = []
			for k in rng.randi_range(0, 5):
				item.append(junk[rng.randi() % junk.size()])
			pkt.append(item if rng.randf() < 0.8 else junk[rng.randi() % junk.size()])
		var s: Array = SlanderPolicy.sanitize_inbox(pkt)
		for e in s:
			if typeof(e[0]) != TYPE_INT or int(e[0]) <= 0 or typeof(e[1]) != TYPE_STRING or String(e[1]) == "":
				crashes += 1
	check(crashes == 0, "sanitizovaný seznam vždy jen platné položky (300 paketů)")


# ------------------------------------------------------------------ offline beze změny
func _offline() -> void:
	section("Offline: pomluva vyhodnocená AI jako dřív (bez verdiktů)")
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "SlanderOffline"
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false, "clock": clock}
	add_child(w)
	check(w._slander_policy() == null, "offline žádná politika mezi hráči")
	var s: Array = w.sims
	if s.size() < 3:
		check(false, "domácnost má aspoň 3 postavy")
		w.queue_free()
		return
	var a = s[0]
	var l = s[1]
	var r = s[2]
	w.dynamics.rivalry.feel(a.sim_name, r.sim_name, "status", 0.7, float(clock.total_minutes))
	check(w.rivalry_slander_block(a, l) == "", "offline: autor smí pomlouvat")
	var ev: Dictionary = w.rivalry_slander(a, l)
	check(String(ev.get("outcome", "")) in ["swayed", "doubted", "saw_through"], "offline: AI výsledek (%s), žádné pending" % String(ev.get("outcome", "")))
	w.queue_free()


# ------------------------------------------------------------------ skutečné ENet
func _branch(bname: String, cfg: Dictionary) -> Node3D:
	var holder := Node.new()
	holder.name = bname
	add_child(holder)
	get_tree().set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	if cfg.get("mode", "") == "client":
		var c := Node.new()
		c.set_script(GameClockScript)
		c.name = "Clock"
		holder.add_child(c)
		cfg["clock"] = c
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "World"
	w.net_config = cfg
	holder.add_child(w)
	notices[bname] = []
	w.net.notice.connect(func(tx: String): notices[bname].append(tx))
	return w


func _client(bname: String, player_name: String) -> Node3D:
	return _branch(bname, {"mode": "client", "address": "127.0.0.1", "port": port, "name": player_name,
		"audio": false, "hud": false, "camera": false, "visuals": false})


func _peer_of(server: Node3D, sim_node: String) -> int:
	return int(server.net.owner_peer_of(sim_node))


func _rel(s: Node, o: Node) -> float:
	return float(s.relationships.get(o.sim_name, 0.0))


func _multiplayer() -> void:
	section("ENet: dedikovaný server + 2 klienti")
	Main.household_override = []
	var server := _branch("SlanderServer", {"mode": "server", "port": port, "clock": clock, "audio": false,
		"hud": false, "camera": false, "visuals": false, "autosave": false, "autoload": false})
	check(server.net.mode == NetSession.Mode.DEDICATED, "dedikovaný server běží")
	var ca := _client("SlanderClientA", "Autorka")
	check(await wait_until(func(): return ca.net.my_sim != "", 6.0), "klient A přivítán s postavou")
	var cb := _client("SlanderClientB", "Posluchač")
	check(await wait_until(func(): return cb.net.my_sim != "", 6.0), "klient B přivítán s postavou")
	var sa: Node = server._real_sim(ca.net.my_sim)
	var sb: Node = server._real_sim(cb.net.my_sim)
	# Domácnost má málo postav (dvě převzali hráči) → přidat AI postavy z kopie záznamu (jako test_rivalry).
	if sa != null and server._character_records.has(String(sa.name)):
		for i in 3:
			var cd: Dictionary = server._character_records[String(sa.name)].to_dict()
			var uid := String(cd.get("uid", "a11ce0000000000a"))
			cd["uid"] = uid.substr(0, uid.length() - 2) + "%02x" % (0x50 + i)
			cd["identity"]["first_name"] = ["Rudolf", "Xenie", "Oto"][i]
			cd["identity"]["last_name"] = "Testovací"
			server.spawn_character(cd, Vector3(6 + 2 * i, 0, 6), 5150 + i)
	var ai: Array = []
	for s in server.sims:
		if is_instance_valid(s) and s.has_method("command") and s != sa and s != sb:
			ai.append(s)
	check(sa != null and sb != null and sa != sb and ai.size() >= 2, "postavy hráčů A, B a aspoň 2 AI postavy")
	if sa == null or sb == null or ai.size() < 2:
		await _teardown([ca, cb, server])
		return
	var pid_a := _peer_of(server, String(sa.name))
	var pid_b := _peer_of(server, String(sb.name))
	check(pid_a > 1 and pid_b > 1 and pid_a != pid_b, "server zná vlastníky postav (%d, %d)" % [pid_a, pid_b])
	check(server._slander_policy() != null, "na serveru je politika aktivní")
	var r1: Node = ai[0]
	var x: Node = ai[1]
	var rv = server.dynamics.rivalry
	var pol = server.net.slander_policy
	await wait_seconds(0.8)

	section("Posluchač patří jinému hráči → odložený dopad + soukromý verdikt")
	var now := float(clock.total_minutes)
	rv.feel(sa.sim_name, r1.sim_name, "status", 0.8, now)
	var b_r0 := _rel(sb, r1)
	var b_a0 := _rel(sb, sa)
	var mem0: int = sb.memories.size() if sb.get("memories") != null else 0
	notices["SlanderClientB"].clear()
	notices["SlanderClientA"].clear()
	var ev: Dictionary = server.rivalry_slander(sa, sb)
	check(String(ev.get("outcome", "")) == "pending" and int(ev.get("vid", 0)) > 0, "výsledek pending, vid %d" % int(ev.get("vid", 0)), str(ev.get("block", "")))
	var vid1 := int(ev.get("vid", 0))
	check(is_equal_approx(_rel(sb, r1), b_r0) and is_equal_approx(_rel(sb, sa), b_a0), "vztahy posluchače zatím beze změny (AI za hráče nerozhodla)")
	check(sb.get("memories") == null or sb.memories.size() > mem0, "posluchač si drb pamatuje")
	check(pol.pending_count(String(sb.name)) == 1 and pol.pending_count(String(sa.name)) == 0, "verdikt patří postavě B")
	check(int(rv.stats["doubted"]) >= 1, "rivalita zapsala pomluvu předběžně jako doubted (schéma beze změny)")
	check(await wait_until(func(): return cb.net.slander_inbox.size() == 1, 3.0), "klient B dostal soukromý seznam (1)")
	if cb.net.slander_inbox.size() == 1:
		var item: Array = cb.net.slander_inbox[0]
		check(int(item[0]) == vid1 and String(item[1]) == sa.first_name() and String(item[2]) == r1.first_name(),
			"položka: vid, autor %s, sok %s" % [String(item[1]), String(item[2])])
	check(await wait_until(func(): return notices["SlanderClientB"].size() > 0, 3.0) and String(notices["SlanderClientB"][0]).contains("řeči"),
		"klient B dostal upozornění", str(notices["SlanderClientB"]))
	await wait_seconds(0.6)
	check(ca.net.slander_inbox.is_empty(), "klient A (autor) seznam posluchače NEVIDÍ")
	check(not notices["SlanderClientA"].any(func(t): return String(t).contains("vykládá řeči")), "klient A upozornění posluchače nedostal")

	section("Podvržené verdikty přes ENet")
	var rej0: int = int(server.net.stats["rejected"])
	ca.net._c2s_slander_verdict.rpc_id(1, vid1, "believe")
	check(await wait_until(func(): return int(server.net.stats["rejected"]) >= rej0 + 1, 3.0) and pol.pending_count(String(sb.name)) == 1,
		"klient A (autor) verdikt posluchače nevyřídí ani se správným vid")
	cb.net._c2s_slander_verdict.rpc_id(1, str(vid1), "believe")
	cb.net._c2s_slander_verdict.rpc_id(1, vid1, 7)
	check(await wait_until(func(): return int(server.net.stats["rejected"]) >= rej0 + 3, 3.0), "špatné typy odmítnuty")
	await wait_seconds(1.0)
	cb.net._c2s_slander_verdict.rpc_id(1, vid1, "default")
	cb.net._c2s_slander_verdict.rpc_id(1, vid1 + 999, "believe")
	cb.net._c2s_slander_verdict.rpc_id(1, float(vid1), "tell")
	check(await wait_until(func(): return int(server.net.stats["rejected"]) >= rej0 + 6, 3.0), "neznámá volba / vid / float vid odmítnuty")
	check(pol.pending_count(String(sb.name)) == 1 and is_equal_approx(_rel(sb, r1), b_r0), "nic z toho stav nezměnilo")
	await wait_seconds(1.0)

	section("Verdikt „říct to oběti“")
	var held: Dictionary = pol._pending[vid1]["data"]["held"] if pol._pending.has(vid1) else {}
	cb.net.request_slander_verdict(vid1, "tell")
	check(await wait_until(func(): return pol.pending_count(String(sb.name)) == 0, 3.0), "server verdikt vyřídil")
	check(_rel(sb, sa) < b_a0, "posluchač si o autorce myslí hůř (%.1f → %.1f)" % [b_a0, _rel(sb, sa)])
	check(_rel(sb, r1) >= b_r0 + float(held.get("delta_rel", 0.0)) * 0.2 - 0.01, "dopad na oběť jen zbytkový (×0,2)")
	check(server.gossip_can_confront(r1, sa), "oběť se dozvěděla zdroj → může autorku konfrontovat")
	check(rv.heat(r1.sim_name, sa.sim_name, float(clock.total_minutes)) > 0.0, "rivalita oplátkou (oběť → autorka)")
	check(await wait_until(func(): return cb.net.slander_inbox.is_empty(), 3.0), "seznam klienta B je prázdný")

	section("Verdikt „věřím tomu“ (AI autor)")
	for i in 130:
		clock.advance(1.0)
	now = float(clock.total_minutes)
	rv.feel(x.sim_name, r1.sim_name, "status", 0.8, now)
	var b_r1 := _rel(sb, r1)
	var ev2: Dictionary = server.rivalry_slander(x, sb)
	var vid2 := int(ev2.get("vid", 0))
	check(String(ev2.get("outcome", "")) == "pending" and vid2 > vid1, "AI autor → posluchač-hráč: taky pending (vid %d)" % vid2, str(ev2))
	var held2: Dictionary = pol._pending[vid2]["data"]["held"] if pol._pending.has(vid2) else {}
	check(await wait_until(func(): return cb.net.slander_inbox.size() == 1, 3.0), "klient B má nový verdikt")
	cb.net.request_slander_verdict(vid2, "believe")
	check(await wait_until(func(): return pol.pending_count(String(sb.name)) == 0, 3.0), "server uvěření vyřídil")
	var drel := float(held2.get("delta_rel", 0.0))
	check(drel >= 0.0 or _rel(sb, r1) <= b_r1 + drel + 0.01, "uvěřil(a): plný dopad na vztah k oběti (%.1f → %.1f, Δ %.1f)" % [b_r1, _rel(sb, r1), drel])

	section("Výchozí verdikt po 12 herních hodinách")
	for i in 130:
		clock.advance(1.0)
	now = float(clock.total_minutes)
	var r2: Node = ai[0] if ai.size() < 3 else ai[2]
	if r2 == r1 and ai.size() >= 3:
		r2 = ai[2]
	rv.feel(sa.sim_name, r2.sim_name, "status", 0.95, now)
	rv.feel(sa.sim_name, r1.sim_name, "status", 0.0, now)
	var ev3: Dictionary = server.rivalry_slander(sa, sb)
	var vid3 := int(ev3.get("vid", 0))
	check(String(ev3.get("outcome", "")) == "pending" and vid3 > 0, "další pending (sok %s)" % String(ev3.get("rival", "")), str(ev3))
	check(await wait_until(func(): return cb.net.slander_inbox.size() == 1, 3.0), "klient B ho má v seznamu")
	clock.total_minutes = now + SlanderPolicy.VERDICT_TTL - 1.0
	await wait_seconds(0.7)
	check(pol.pending_count(String(sb.name)) == 1, "minutu před lhůtou stále čeká")
	clock.total_minutes = now + SlanderPolicy.VERDICT_TTL + 1.0
	check(await wait_until(func(): return pol.pending_count(String(sb.name)) == 0, 3.0), "po lhůtě server uzavřel výchozím verdiktem")
	check(await wait_until(func(): return cb.net.slander_inbox.is_empty(), 3.0), "a klientovi B zmizel ze seznamu")
	check(int(pol.stats["expired"]) >= 1, "statistika expired")

	section("Strop pomluv na oběť-hráče (handle_command)")
	now = float(clock.total_minutes)
	for i in 3:
		clock.advance(130.0)
	now = float(clock.total_minutes)
	rv.feel(sa.sim_name, sb.sim_name, "status", 0.99, now)
	for k in rv.rivals.keys():
		if String(k).begins_with(sa.sim_name + ">") and String(k) != Rivalry.key(sa.sim_name, sb.sim_name):
			rv.rivals[k]["love"] = 0.0
			rv.rivals[k]["status"] = 0.0
	var listener: Node = x
	check(server.rivalry_slander_block(sa, listener) == "", "A smí pomlouvat B před AI postavou")
	for i in SlanderPolicy.VICTIM_DAILY_CAP:
		pol.note_victim(String(sb.name), now)
	check(server.rivalry_slander_block(sa, listener) == "victim_cap", "po %d pomluvách o B za den: victim_cap" % SlanderPolicy.VICTIM_DAILY_CAP)
	var msg: String = server.net.handle_command(pid_a, String(sa.name), "slander_rival", String(listener.name))
	check(msg.contains("kdekdo"), "server příkaz odmítl s vysvětlením", msg)
	var evc: Dictionary = server.rivalry_slander(sa, listener)
	check(String(evc.get("outcome", "")) == "blocked" and String(evc.get("block", "")) == "victim_cap", "i přímé vyhodnocení blokuje")
	clock.total_minutes = now + SlanderPolicy.DAY + 1.0
	check(server.rivalry_slander_block(sa, listener) == "", "po dni se strop uvolní")
	var vc0: int = pol.victim_count(String(sb.name), float(clock.total_minutes))
	var evd: Dictionary = server.rivalry_slander(sa, listener)
	check(String(evd.get("outcome", "")) in ["swayed", "doubted", "saw_through"], "posluchač AI → běžný AI výsledek (%s)" % String(evd.get("outcome", "")))
	check(pol.victim_count(String(sb.name), float(clock.total_minutes)) == vc0 + 1, "proběhlá pomluva o hráči se počítá do stropu")

	section("Server: žádost od neznámého peeru")
	check(server.net.handle_slander_verdict(99999, 1, "believe") == "Neznámý hráč.", "neznámý peer odmítnut")
	await _teardown([ca, cb, server])
	await _host_mode()


## Listen server: hostitel (peer 1) je zároveň hráč – jeho seznam verdiktů žije lokálně (bez RPC).
func _host_mode() -> void:
	section("Hostitel (listen server): verdikt hostitelovy postavy")
	port += 1
	Main.household_override = []
	var host := _branch("SlanderHost", {"mode": "host", "port": port, "clock": clock, "name": "Hostitel", "audio": false,
		"hud": false, "camera": false, "visuals": false, "autosave": false, "autoload": false})
	check(host.net.mode == NetSession.Mode.HOST and host.net.my_sim != "", "hostitel hraje za postavu %s" % host.net.my_sim)
	var cc := _client("SlanderHostClient", "Host-klient")
	check(await wait_until(func(): return cc.net.my_sim != "", 6.0), "klient přivítán")
	var sh: Node = host._real_sim(host.net.my_sim)
	var sc: Node = host._real_sim(cc.net.my_sim)
	var others: Array = []
	for s in host.sims:
		if is_instance_valid(s) and s.has_method("command") and s != sh and s != sc:
			others.append(s)
	check(sh != null and sc != null and others.size() >= 1, "postava hostitele, klienta a aspoň 1 AI")
	if sh == null or sc == null or others.is_empty():
		await _teardown([cc, host])
		return
	var victim: Node = others[0]
	host.dynamics.rivalry.feel(sc.sim_name, victim.sim_name, "status", 0.8, float(clock.total_minutes))
	notices["SlanderHost"].clear()
	var ev: Dictionary = host.rivalry_slander(sc, sh)
	var vid := int(ev.get("vid", 0))
	check(String(ev.get("outcome", "")) == "pending" and vid > 0, "klient pomlouvá před hostitelem → pending", str(ev))
	check(host.net.slander_inbox.size() == 1 and int(host.net.slander_inbox[0][0]) == vid, "hostitel má verdikt lokálně v seznamu")
	check(notices["SlanderHost"].any(func(t): return String(t).contains("řeči")), "hostitel dostal lokální upozornění", str(notices["SlanderHost"]))
	await wait_seconds(0.7)
	check(cc.net.slander_inbox.is_empty(), "klient (autor) hostitelův seznam nevidí")
	var h_c0 := _rel(sh, sc)
	host.net.request_slander_verdict(vid, "dismiss")
	check(host.net.slander_policy.pending_count() == 0 and host.net.slander_inbox.is_empty(), "hostitel verdikt vyřídil, seznam prázdný")
	check(_rel(sh, sc) < h_c0, "nevěřil(a): horší vztah k autorovi (%.1f → %.1f)" % [h_c0, _rel(sh, sc)])
	host.net.request_slander_verdict(vid, "dismiss")
	check(notices["SlanderHost"].any(func(t): return String(t).contains("vyřízené")), "druhé vyřízení odmítnuto s vysvětlením")
	await _teardown([cc, host])


func _teardown(ws: Array) -> void:
	for w in ws:
		w.net.shutdown()
	await wait_seconds(0.3)
	for w in ws:
		w.get_parent().queue_free()
	await wait_seconds(0.2)
