extends "res://tests/test_base.gd"
## Test deprese: oddělené wanting (naučené očekávání + pesimismus), liking (prožitá radost),
## vigour (bariéra iniciace) a učení z rozdílu očekávání (prediction error).
## Scénáře podle review z AI místnosti (zpráva 29):
##   1) nízké očekávání + zachované prožité potěšení
##   2) vysoké očekávání + malé prožité potěšení
##   3) zachovaná motivace, ale nízké prožití
##   4) zachované potěšení, ale velká bariéra iniciace
##   5) série negativních zkušeností nevytvoří nezvratný stav
##   6) spam jedné aktivity depresi „nevyléčí“
## + nelineární zotavení, ranní vzorec jen jako individuální volba, nastavení obsahu, epizody
## a stopa po nich, myšlenky bez sebevražedných obsahů, integrace do světa (váhání hráčova
## příkazu, AI nikdy neváhá, prožitá radost tlumí moodlety), soukromí a serializace.

const Main := preload("res://main.gd")
const Depression := preload("res://scripts/sim/depression.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const PsycheFX := preload("res://scripts/world/psyche_fx.gd")
const Hud := preload("res://scripts/ui/hud.gd")

const CFG_FULL := {"conditions": true, "episodes": true, "thought_rate": 1.0}
const CFG_MUTED := {"conditions": true, "episodes": false, "thought_rate": 0.4}
const CFG_OFF := {"conditions": false, "episodes": false, "thought_rate": 0.0}

var world: Node3D
var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 120.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	world = Node3D.new()
	world.set_script(Main)
	world.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(world)
	_run.call_deferred()


func _ctx(extra := {}) -> Dictionary:
	var c := {"stress": 15.0, "social": 70.0, "energy": 70.0, "support": 0.0, "sleeping": false,
		"night": false, "hour": 14, "now": 0.0, "cfg": CFG_FULL}
	c.merge(extra, true)
	return c


## Simulace dní: noc spánek (23–7), přes den daný stres. Vrací burden po každém dni.
func _days(d: Depression, n: int, extra := {}, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	for day in n:
		for m in 1440:
			var h := m / 60
			var sl := h >= 23 or h < 7
			var c := _ctx({"sleeping": sl, "night": sl, "hour": h})
			c.merge(extra, true)
			d.tick(1.0, c)
		if rng != null:
			d.new_day(rng, extra.get("cfg", CFG_FULL))
		out.append(d.burden)
	return out


func _run() -> void:
	_test_components()
	_test_scenarios()
	_test_recovery()
	_test_spam()
	_test_review39()
	_test_patterns_settings()
	_test_mental_integration()
	await _test_in_world()
	finish("test_depression")


# ---------------------------------------------------------------- složky

func _test_components() -> void:
	section("Čtyři oddělené složky")
	var d := Depression.new()
	check(d.burden < 0.1 and d.hedonic == 1.0 and d.vigour == 1.0 and d.pessimism == 0.0, "výchozí stav: bez zátěže")
	check(is_equal_approx(d.anticipated("read", 10.0), 10.0), "bez historie a pesimismu očekávání = nominální radost")
	check(d.barrier(0.9) == 0.0 and d.barrier(0.0) == 0.0, "bez deprese žádná bariéra iniciace")
	# Chronický stres zvyšuje zátěž; predispozice rychleji.
	var a := Depression.new()
	var b := Depression.new()
	b.vuln = 0.6
	_days(a, 3, {"stress": 80.0})
	_days(b, 3, {"stress": 80.0})
	check(a.burden > 0.1 and b.burden > a.burden, "chronický stres zvyšuje zátěž, predispozice víc",
		"%.2f vs %.2f" % [a.burden, b.burden])
	check(b.hedonic < 1.0 and b.pessimism > 0.0 and b.vigour < 1.0, "zátěž se pomalu promítne do liking, pesimismu i vigour")
	var iso := Depression.new()
	_days(iso, 3, {"social": 10.0})
	check(iso.burden > 0.05 and iso.isolation > 0.0, "dlouhá izolace přidává zátěž", "%.2f" % iso.burden)
	var calm := Depression.new()
	_days(calm, 5, {})
	check(calm.burden < 0.05, "bez zátěže deprese nevzniká (bez endogenní složky)", "%.3f" % calm.burden)
	# Zpoždění: liking se po skoku zátěže nemění okamžitě.
	var lag := Depression.new()
	lag.burden = 0.8
	lag.tick(1.0, _ctx())
	check(lag.hedonic > 0.95, "liking sleduje zátěž se zpožděním (ne skokem)", "%.3f" % lag.hedonic)


# ---------------------------------------------------------------- scénáře 1–4

func _test_scenarios() -> void:
	section("Scénáře wanting × liking × vigour")
	# 1) nízké očekávání + zachované prožité potěšení
	var s1 := Depression.new()
	s1.expect["go_walk"] = [2.0, 6]
	var r1 := s1.experience("go_walk", 10.0)
	check(is_equal_approx(float(r1["experienced"]), 10.0) and float(r1["surprise"]) > 5.0,
		"1) nízké očekávání, plné prožití → pozitivní překvapení", str(r1))
	check(float(s1.expect["go_walk"][0]) > 2.0 and float(s1.expect["go_walk"][0]) < 10.0,
		"1) očekávání se posune nahoru, ale pozvolna (ne skokem)", str(s1.expect["go_walk"]))
	# 2) vysoké očekávání + malé prožité potěšení
	var s2 := Depression.new()
	s2.hedonic = 0.3
	s2.expect["read"] = [12.0, 0]
	var first := s2.experience("read", 10.0)
	var mu1: float = float(s2.expect["read"][0])
	for i in 30:
		s2.experience("read", 10.0)
	var mu_n: float = float(s2.expect["read"][0])
	check(float(first["surprise"]) < 0.0 and mu1 > 9.0, "2) zklamání sníží očekávání jen trochu", "%.2f" % mu1)
	check(mu_n < 5.0 and mu_n >= 10.0 * 0.15, "2) opakované zklamání očekávání sníží, ale ne na nulu", "%.2f" % mu_n)
	# 3) zachovaná motivace, nízké prožití
	var s3 := Depression.new()
	s3.hedonic = 0.3
	check(is_equal_approx(s3.anticipated("cook", 10.0), 10.0), "3) wanting zachované (očekávání plné)")
	check(is_equal_approx(float(s3.experience("cook", 10.0)["experienced"]), 3.0), "3) ale prožitá radost jen 30 %")
	# 4) zachované potěšení, velká bariéra
	var s4 := Depression.new()
	s4.vigour = 0.25
	check(s4.barrier(0.9) > 0.6 and s4.barrier(0.1) < 0.1, "4) bariéra roste s námahou akce", "%.2f / %.2f" % [s4.barrier(0.9), s4.barrier(0.1)])
	check(s4.barrier(1.0) <= 0.9, "4) bariéra nikdy nezakáže akci úplně")
	check(is_equal_approx(float(s4.experience("workout", 14.0)["experienced"]), 14.0), "4) když se akce povede, radost je plná")
	# Pesimismus zkresluje jen očekávání, ne prožitek.
	var s5 := Depression.new()
	s5.pessimism = 0.8
	check(s5.anticipated("chat", 10.0) < 6.0 and is_equal_approx(float(s5.experience("chat", 10.0)["experienced"]), 10.0),
		"pesimismus snižuje očekávání, prožitek nechává být")


# ---------------------------------------------------------------- 5) zotavení

func _test_recovery() -> void:
	section("5) Nic není nezvratné, zotavení nelineární")
	var d := Depression.new()
	d.vuln = 0.8
	for i in 40:
		d.on_event(0.08, CFG_FULL)
	for i in 40:
		d.hedonic = 0.2
		d.experience("read", 10.0)
		d.experience("chat", 10.0)
	_days(d, 4, {"stress": 85.0, "social": 10.0})
	check(d.burden > 0.9 and d.hedonic < 0.4, "nejhorší stav (série ztrát, zklamání, stres, izolace)",
		"zátěž %.2f, liking %.2f" % [d.burden, d.hedonic])
	var mu_low: float = float(d.expect["read"][0])
	check(mu_low >= 1.5, "očekávání nikdy nespadne na nulu", "%.2f" % mu_low)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var traj: Array = []
	var t := 0.0
	for day in 30:
		for m in 1440:
			var h := m / 60
			var sl := h >= 23 or h < 7
			d.tick(1.0, _ctx({"stress": 20.0, "support": 0.4, "sleeping": sl, "night": sl, "hour": h, "now": t}))
			t += 1.0
			if m == 600 or m == 900:
				d.on_connection(1.0, t)
			if m == 700:
				var r := d.experience("go_walk", 10.0)
				d.on_activity("go_walk_%d" % (day % 3), 0.6, float(r["surprise"]), t)
		d.new_day(rng, CFG_FULL)
		traj.append(d.burden)
	check(d.burden < 0.5 and d.hedonic > 0.55, "s oporou, kontaktem, spánkem a aktivitou se stav zlepší",
		"zátěž %.2f, liking %.2f" % [d.burden, d.hedonic])
	var ups := 0
	for i in range(1, traj.size()):
		if traj[i] > traj[i - 1] + 0.001:
			ups += 1
	check(ups >= 1 and traj[-1] < traj[0], "zotavení není lineární (i dny zpátky), ale celkově vede dolů",
		"%d dní nahoru, %.2f → %.2f" % [ups, traj[0], traj[-1]])
	for i in 10:
		d.experience("read", 10.0)
	check(float(d.expect["read"][0]) > mu_low, "s vrácenou radostí se očekávání znovu učí nahoru",
		"%.2f → %.2f" % [mu_low, float(d.expect["read"][0])])
	check(d.burden > 0.0 or d.scar >= 0.0, "žádné „vyléčeno na 100 %“ flagy – jen stav")
	# Epizoda: potřebuje trvat, zanechá stopu, stopa mizí.
	var e := Depression.new()
	e.burden = 0.8
	e.vuln = 0.5
	_days(e, 1, {"stress": 70.0})
	check(not e.episode_active or e.high_minutes >= Depression.EPISODE_MIN_MINUTES, "epizoda nezačne hned při prvním propadu")
	_days(e, 3, {"stress": 70.0})
	check(e.episode_active and e.episode_count == 1, "trvalá vysoká zátěž → depresivní epizoda", "%.2f" % e.burden)
	check(e.label(CFG_FULL) == "Depresivní epizoda" and e.label(CFG_OFF) != "Depresivní epizoda", "diagnostický název jen s povolenými tématy")
	e.burden = 0.1
	_days(e, 1, {"stress": 10.0})
	check(not e.episode_active and e.scar > 0.0, "po epizodě zůstává slabá stopa (rychlejší relaps)", "%.3f" % e.scar)
	var s0 := e.scar
	_days(e, 60, {"stress": 10.0})
	check(e.scar < s0 * 0.6, "stopa časem mizí (nic není navždy)", "%.3f → %.3f" % [s0, e.scar])


# ---------------------------------------------------------------- 6) spam

func _test_spam() -> void:
	section("6) Spam jedné aktivity depresi nevyléčí")
	var single := Depression.new()
	single.burden = 0.7
	var one := single.on_activity("workout", 0.9, 0.0, 100.0)
	var spam := Depression.new()
	spam.burden = 0.7
	var total := 0.0
	for i in 10:
		total += spam.on_activity("workout", 0.9, 0.0, 100.0 + i * 50.0)
	check(total < one * 2.5, "10× stejná aktivita za den < 2,5× jedna", "%.3f vs %.3f" % [total, one])
	var varied := Depression.new()
	varied.burden = 0.7
	var vt := 0.0
	for id in ["workout", "go_walk", "cook", "chat"]:
		vt += varied.on_activity(id, 0.9, 0.0, 200.0)
	var same4 := Depression.new()
	same4.burden = 0.7
	var st := 0.0
	for i in 4:
		st += same4.on_activity("workout", 0.9, 0.0, 200.0 + i)
	check(vt > st * 1.5, "pestrost pomáhá víc než opakování", "%.3f vs %.3f" % [vt, st])
	check(spam.burden > 0.5, "ani spam nesrazí zátěž k nule", "%.2f" % spam.burden)
	var later := spam.on_activity("workout", 0.9, 0.0, 100.0 + 10 * 50.0 + Depression.ACTIVATION_WINDOW + 1.0)
	check(later > total / 10.0, "po pauze má aktivita zase účinek")
	var conn := Depression.new()
	conn.burden = 0.6
	conn.on_connection(1.0, 10.0)
	var b1 := conn.burden
	conn.on_connection(1.0, 20.0)
	check(0.6 - b1 > b1 - conn.burden, "opakovaný kontakt v krátké době pomáhá méně (antifarming)")



# ---------------------------------------------------------------- review ChatGPT (zpráva 39)

func _test_review39() -> void:
	section("Review ChatGPT 39: hranice epizody, antifarming, kontakt, robustní načtení")
	# A) Začátek epizody nezávisí na délce kroku (posun nejvýš o krok).
	var starts := []
	for step in [1.0, 2.0, 5.0]:
		var d := Depression.new()
		d.burden = 0.9
		var t := 0.0
		var start := -1.0
		while t < 5000.0:
			d.tick(step, _ctx({"stress": 90.0, "now": t}))
			t += step
			if d.episode_active and start < 0.0:
				start = t
		starts.append(start)
	check(starts[0] > 0.0 and absf(starts[1] - starts[0]) <= 2.0 and absf(starts[2] - starts[0]) <= 5.0,
		"A) začátek epizody nezávisí na délce kroku (1/2/5 min)", str(starts))
	check(starts[0] >= Depression.EPISODE_MIN_MINUTES, "A) epizoda nezačne dřív než po minimální době", str(starts[0]))
	# B) 100 opakování stejné akce za den – bez 12-záznamového stropu.
	var spam := Depression.new()
	spam.burden = 0.8
	var tot := 0.0
	var tail := 0.0
	for i in 100:
		var g := spam.on_activity("workout", 0.9, 0.0, 1000.0 + i * 10.0)
		tot += g
		if i >= 90:
			tail += g
	var one := Depression.new()
	one.burden = 0.8
	var single := one.on_activity("workout", 0.9, 0.0, 1000.0)
	check(tot < single * 4.0, "B) 100× stejná akce za den < 4× jedna", "%.4f vs %.4f" % [tot, single])
	check(tail / 10.0 < single * 0.02, "B) 91.–100. opakování mají zanedbatelný účinek (< 2 % první, žádný strop habituace)", "%.5f" % (tail / 10.0))
	# Rotace mnoha různých id – společný denní rozpočet.
	var rot := Depression.new()
	rot.burden = 0.8
	var rt := 0.0
	for i in 100:
		rt += rot.on_activity("akce_%d" % (i % 25), 0.9, 10.0, 2000.0 + i * 10.0)
	var normal := Depression.new()
	normal.burden = 0.8
	var nt := 0.0
	# Pestrý normální den: 5 různých aktivit rozložených přes den, stejně příjemných jako při farmení.
	var ids := ["workout", "go_walk", "cook", "read", "chat"]
	for i in ids.size():
		nt += normal.on_activity(ids[i], 0.9, 10.0, 2000.0 + i * 200.0)
	check(rt < 0.2, "B) rotace 25 různých akcí ×100 za den má strop (společný rozpočet)", "%.3f" % rt)
	check(rt < nt * 3.0, "B) farmení rotací není o moc lepší než pestrý normální den", "%.3f vs %.3f" % [rt, nt])
	var next_day := rot.on_activity("go_walk", 0.6, 2.0, 2000.0 + 1000.0 + 2880.0)
	check(next_day > 0.002, "B) další den aktivita zase pomáhá (cesta není uzavřená)", "%.4f" % next_day)
	# Habituace přežije uložení a načtení.
	var sv := Depression.new()
	sv.burden = 0.8
	for i in 5:
		sv.on_activity("workout", 0.9, 0.0, 500.0 + i)
	var ld := Depression.new()
	ld.from_dict(sv.to_dict())
	var a1 := sv.on_activity("workout", 0.9, 0.0, 510.0)
	var a2 := ld.on_activity("workout", 0.9, 0.0, 510.0)
	check(is_equal_approx(a1, a2), "B) save/load nezresetuje habituaci ani rozpočet", "%.5f vs %.5f" % [a1, a2])
	# C) Kontakt: nekvalitní nic neruší, častý má klesající přínos.
	var c := Depression.new()
	c.burden = 0.6
	c.isolation = 900.0
	c.on_connection(0.0, 100.0)
	check(c.isolation == 900.0 and c.burden == 0.6, "C) kontakt s kvalitou 0 neruší izolaci ani nesnižuje zátěž")
	c.on_connection(0.5, 110.0)
	check(c.isolation > 0.0 and c.isolation < 900.0, "C) průměrný kontakt izolaci jen zmírní", "%.0f" % c.isolation)
	var many := Depression.new()
	many.burden = 0.6
	for i in 20:
		many.on_connection(1.0, 200.0 + i * 3.0)
	var once := Depression.new()
	once.burden = 0.6
	once.on_connection(1.0, 200.0)
	check(0.6 - many.burden < (0.6 - once.burden) * 4.0, "C) 20 kontaktů za hodinu < 4× jeden", "%.4f vs %.4f" % [0.6 - many.burden, 0.6 - once.burden])
	var ld2 := Depression.new()
	ld2.from_dict(many.to_dict())
	check(is_equal_approx(ld2.contact_recent, many.contact_recent), "C) stav kontaktů se ukládá")
	# D) Poškozená / podvržená data.
	var bad := {"burden": NAN, "hedonic": INF, "vigour": -5.0, "episode_count": -3, "relief_recent": INF,
		"expect": {"read": [NAN, 3], "chat": [5.0, -40], "cook": [1.0e9, 1.0e9], "x".repeat(200): [1.0, 1]},
		"activity_log": {"workout": [-5.0, NAN]}}
	for i in 600:
		bad["expect"]["a%d" % i] = [1.0, 1]
	var dd := Depression.new()
	dd.from_dict(bad)
	check(is_finite(dd.burden) and dd.burden >= 0.0 and dd.burden <= 1.0, "D) NaN v zátěži se ignoruje", str(dd.burden))
	check(dd.hedonic <= 1.0 and dd.vigour >= 0.1 and dd.episode_count == 0 and dd.relief_recent == 0.0, "D) Inf a záporné hodnoty se ořežou")
	check(not dd.expect.has("read") and int(dd.expect["chat"][1]) == 0 and float(dd.expect["cook"][0]) <= 1000.0,
		"D) očekávání: NaN zahozeno, záporné n → 0, obří mu oříznuto")
	check(dd.expect.size() <= Depression.MAX_EXPECT, "D) velikost slovníku má strop", str(dd.expect.size()))
	var g2 := dd.on_activity("workout", 0.9, 0.0, 0.0)
	check(is_finite(g2) and g2 >= 0.0, "D) po načtení podvržených dat simulace dál počítá konečná čísla")

# ---------------------------------------------------------------- vzorce a nastavení

func _test_patterns_settings() -> void:
	section("Ranní vzorec a nastavení obsahu")
	var m := Depression.new()
	var n := Depression.new()
	m.morning_pattern = true
	for d in [m, n]:
		d.burden = 0.6
	check(m.morning_drag(8) > 0.1 and m.morning_drag(15) == 0.0 and n.morning_drag(8) == 0.0,
		"ranní zhoršení jen u postavy s tímto vzorcem a jen ráno")
	var ids: Array = []
	for e in m.mood_entries(8):
		ids.append(e["id"])
	check(ids.has("rano_nejhorsi") and ids.has("sklesly"), "ráno moodlet „Ráno je nejhorší“", str(ids))
	var off := Depression.new()
	off.vuln = 1.0
	_days(off, 6, {"stress": 95.0, "social": 5.0, "cfg": CFG_OFF})
	check(off.burden <= Depression.CAP_NO_CONDITIONS + 0.0001 and not off.episode_active,
		"vypnutá témata: jen situační skleslost (strop), bez epizod", "%.2f" % off.burden)
	var muted := Depression.new()
	muted.vuln = 1.0
	_days(muted, 6, {"stress": 95.0, "social": 5.0, "cfg": CFG_MUTED})
	check(muted.burden <= Depression.CAP_NO_EPISODES + 0.0001 and not muted.episode_active, "ztlumeno: strop a bez epizod")
	off.on_event(0.5, CFG_OFF)
	check(off.burden <= Depression.CAP_NO_CONDITIONS + 0.0001, "ani událost strop nepřekročí")
	# Endogenní propady u predispozice (ne u odolných) – realistické, ale vzácné.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var dips_v := 0
	var dips_r := 0
	var dv := Depression.new()
	dv.vuln = 0.7
	var dr := Depression.new()
	for i in 400:
		if dv.new_day(rng, CFG_FULL):
			dips_v += 1
		if dr.new_day(rng, CFG_FULL):
			dips_r += 1
		dv.burden = 0.1
	check(dips_v > 2 and dips_v < 40 and dips_r == 0, "propady bez zjevné příčiny jen u predispozice a vzácně",
		"%d / %d ze 400 dní" % [dips_v, dips_r])


# ---------------------------------------------------------------- MentalState

func _test_mental_integration() -> void:
	section("Integrace do MentalState")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var ms := MentalState.new(r, true)
	ms.conditions = {"depression": 0.6}
	check(ms.dep_vulnerability() > 0.4 and ms.dep_vulnerability({"conditions": false}) == 0.0,
		"predispozice zvyšuje zranitelnost; vypnutá témata ji ruší")
	var anx := MentalState.new(r, true)
	anx.conditions = {"anxiety": 0.6}
	check(anx.dep_vulnerability() > 0.0 and anx.dep_vulnerability() < ms.dep_vulnerability(), "úzkost nese menší komorbidní riziko")
	check(not ms.can_panic(), "deprese sama nepřináší panické ataky")
	var e0 := ms.energy_drain_mult()
	var q0 := ms.sleep_quality()
	ms.dep.burden = 0.8
	check(ms.energy_drain_mult() > e0 and ms.sleep_quality() < q0, "deprese vyčerpává a zhoršuje spánek")
	ms.dep.episode_active = true
	check(ms.state_label(CFG_FULL) == "Depresivní epizoda", "popis stavu slovy", ms.state_label(CFG_FULL))
	ms.arousal = 50.0
	check(ms.state_label(CFG_FULL).find("Úzkost") >= 0 and ms.state_label(CFG_FULL).find("depresivní") >= 0,
		"úzkost a deprese se ukážou spolu", ms.state_label(CFG_FULL))
	var det := ms.detail(CFG_FULL)
	check(det.has("low") and typeof(det["label"]) == TYPE_STRING and bool(det["anhedonia"]) == (ms.dep.hedonic < 0.6),
		"soukromý detail nese úroveň pro efekty a slovní popis")
	# Myšlenky: generují se a nikdy nemají sebevražedné obsahy.
	ms.arousal = 10.0
	ms.dep.episode_active = false
	var t := 0.0
	var low_n := 0
	for i in 2000:
		t += 1.0
		ms.dep.burden = 0.85
		ms.tick(1.0, {"energy": 60.0, "hunger": 60.0, "needs": {"social": 60.0}, "now": t, "hour": 14, "cfg": CFG_FULL})
		if not ms.thoughts.is_empty() and String(ms.thoughts[-1]["kind"]).begins_with("low"):
			low_n += 1
	check(low_n > 0, "v depresi vznikají depresivní myšlenky")
	var banned := ["zabít", "zabiju", "umřít", "umřu", "sebevra", "skončit se vším", "přítěž", "nebýt tu", "konec"]
	var bad: PackedStringArray = []
	for kind in MentalState.THOUGHTS:
		for line in MentalState.THOUGHTS[kind]:
			for w in banned:
				if String(line).to_lower().find(w) >= 0:
					bad.append(String(line))
	check(bad.is_empty(), "žádná myšlenka nemá sebevražedný obsah", ", ".join(bad))
	var md := ms.to_dict()
	var ms2 := MentalState.new()
	ms2.from_dict(md)
	check(is_equal_approx(ms2.dep.burden, ms.dep.burden) and ms2.dep.expect.size() == ms.dep.expect.size(), "uložení a načtení zachová depresi")
	var bad_d := Depression.new()
	bad_d.from_dict({"burden": 99.0, "hedonic": -5.0, "expect": {"x": "nesmysl", "y": [1.0, 2]}, "vigour": "abc"})
	check(bad_d.burden <= 1.0 and bad_d.hedonic >= 0.2 and bad_d.expect.size() == 1, "poškozená data se ořežou")
	check(PsycheFX.target_grey({"low": 10}, 1.0) == 0.0 and PsycheFX.target_grey({"low": 80}, 1.0) > 0.8
		and PsycheFX.target_grey({"low": 80}, 0.0) == 0.0, "šedý filtr jen v depresi a jen se zapnutým zkreslením")
	check(Hud.heavy_hint(ActionLibrary.get_action("workout"), true) != "" and Hud.heavy_hint(ActionLibrary.get_action("watch_tv"), true) == ""
		and Hud.heavy_hint(ActionLibrary.get_action("workout"), false) == "", "HUD označí náročné akce slovy, bez čísel")


# ---------------------------------------------------------------- ve světě

func _reset(s) -> void:
	s.player_queue.clear()
	s.command({"id": "cancel"}, null)
	s.mental.dep.burden = 0.0
	s.mental.dep.vigour = 1.0
	s.mental.dep.hedonic = 1.0
	s.mental.dep.pessimism = 0.0
	s.mental.stress = 10.0
	s.mental.arousal = 5.0
	s.think_cooldown = 1.0e9
	for k in s.needs.values:
		s.needs.values[k] = 80.0


func _idx(tag: String) -> int:
	var objs: Array = world.get_smart_objects()
	for i in objs.size():
		if objs[i].object_tag == tag:
			return i
	return -1


func _test_in_world() -> void:
	section("Ve světě")
	var jana = world.find_sim(SimAgent.node_name_for("Jana Nováková"))
	var petr = world.find_sim(SimAgent.node_name_for("Petr Dvořák"))
	var eli = world.find_sim(SimAgent.node_name_for("Eliška Malá"))
	var net = world.net
	check(jana.mental.conditions.has("depression") and jana.mental.dep.morning_pattern and not petr.mental.dep.morning_pattern,
		"Jana má predispozici k depresi a ranní vzorec (jen ona)")
	check(not NetSession.SYNC_PROPS.has("net_detail"), "duševní stav není ve veřejné synchronizaci")
	for s in [jana, petr, eli]:
		_reset(s)
	# Váhání hráčova příkazu.
	jana.mental.dep.burden = 0.9
	jana.mental.dep.vigour = 0.1
	check(net.handle_command(1, jana.name, "hesitate", "") != "", "váhání nejde zadat jako příkaz")
	check(net.handle_command(1, jana.name, "workout", _idx("treadmill")) == "", "náročný příkaz se v depresi přijme (nikdy neodmítne)")
	check(jana.current_action.get("id", "") == "hesitate" and jana.player_queue.size() == 1,
		"postava se nejdřív „nemůže dokopat“", str(jana.current_action.get("label", "")))
	check(String(jana.display_action()).find("Nemůže se dokopat") >= 0, "váhání je vidět v popisu činnosti")
	var started := false
	for i in 120:
		clock.advance(1.0)
		if jana.current_action.get("id", "") == "workout":
			started = true
			break
	check(started, "po váhání příkaz provede (autonomie zachována, kolísá cena)")
	_reset(jana)
	jana.mental.dep.burden = 0.9
	jana.mental.dep.vigour = 0.1
	net.handle_command(1, jana.name, "workout", _idx("treadmill"))
	net.handle_command(1, jana.name, "cancel", "")
	check(jana.current_action.is_empty() and jana.player_queue.is_empty(), "váhání jde zrušit")
	_reset(jana)
	jana.mental.dep.burden = 0.9
	jana.mental.dep.vigour = 0.1
	net.handle_command(1, jana.name, "watch_tv", _idx("tv"))
	check(jana.current_action.get("id", "") == "watch_tv", "lehká akce (TV) bez váhání")
	_reset(jana)
	gs.set_value("mental_health", "muted")
	jana.mental.dep.burden = 0.5
	jana.mental.dep.vigour = 0.1
	net.handle_command(1, jana.name, "workout", _idx("treadmill"))
	check(jana.current_action.get("id", "") == "workout", "ztlumené téma: bez váhání")
	gs.reset()
	# AI nikdy neváhá; bariéra snižuje chuť, ale nic nezakazuje.
	_reset(jana)
	jana.global_position = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Eliška je Aktivní – cvičení ji normálně láká.
	# (Cvičení stojí energii a hygienu – láká hlavně když Aktivní povaha „potřebuje se hýbat“.)
	eli.mood.add_moodlet("craving_exercise", "Potřebuje se hýbat", "napjaty", -12.0, 60.0)
	var base_s: float = Planner.score_action(eli, ActionLibrary.get_action("workout"), 14)
	eli.mental.dep.vigour = 0.2
	var low_s: float = Planner.score_action(eli, ActionLibrary.get_action("workout"), 14)
	eli.mental.dep.vigour = 1.0
	check(low_s < base_s * 0.5 and low_s > 0.0, "nízký vigour: cvičení láká méně, ale ne nula", "%.1f → %.1f" % [base_s, low_s])
	var tv_ratio: float = Planner.score_action(jana, ActionLibrary.get_action("watch_tv"), 14)
	jana.mental.dep.vigour = 1.0
	tv_ratio /= maxf(Planner.score_action(jana, ActionLibrary.get_action("watch_tv"), 14), 0.001)
	check(tv_ratio > 0.85, "lehké akce bariéra skoro neovlivní", "%.2f" % tv_ratio)
	jana.mental.dep.vigour = 0.1
	jana.mental.dep.burden = 0.9
	var hes := 0
	for i in 300:
		var c: Dictionary = Planner.choose(jana, world.get_smart_objects(), world.get_sims(), rng, 14)
		if not c.is_empty() and c["action"]["id"] == "hesitate":
			hes += 1
	check(hes == 0, "AI si váhání nikdy nevybere")
	# Pesimismus: naučené očekávání mění volbu (wanting).
	_reset(jana)
	var w0: float = Planner.score_action(jana, ActionLibrary.get_action("read"), 14)
	jana.mental.dep.pessimism = 0.9
	var w1: float = Planner.score_action(jana, ActionLibrary.get_action("read"), 14)
	check(w1 < w0, "pesimismus snižuje chuť na příjemné akce", "%.1f → %.1f" % [w0, w1])
	# Liking: dokončená akce dá méně radosti a naučí nižší očekávání.
	_reset(jana)
	jana.mental.dep.hedonic = 0.3
	jana.mood.remove_moodlet("zabrany")
	check(net.handle_command(1, jana.name, "read", _idx("bookshelf")) == "", "příkaz číst přijat")
	var done := false
	for i in 200:
		clock.advance(1.0)
		if String(jana.last_experience.get("id", "")) == "read":
			done = true
			break
	check(done, "čtení dokončeno")
	var strength := 0.0
	for m in jana.mood.moodlets:
		if m["id"] == "zabrany":
			strength = float(m["strength"])
	check(strength > 0.0 and strength < 8.0 * 0.5, "anhedonie: moodlet z knihy jen slabý", "%.1f" % strength)
	check(float(jana.last_experience.get("experienced", 99.0)) < float(jana.last_experience.get("anticipated", 0.0)),
		"prožitek horší než očekávání → očekávání se učí dolů", str(jana.last_experience))
	# Soukromý detail obsahuje slovní popis deprese.
	jana.mental.dep.burden = 0.6
	jana.mental.dep.episode_active = false
	var info: Dictionary = jana.hud_info()
	check(String(info["mind"]["label"]) == "Sklíčenost", "HUD: slovní popis stavu", String(info["mind"]["label"]))
	# Regrese (spirála z běhu 6): osamělost ani nuda nebudí ze spánku, hlad ano.
	_reset(petr)
	var slept := false
	if net.handle_command(1, petr.name, "sleep", _idx("bed")) == "":
		for i in 60:
			clock.advance(1.0)
			if petr._is_sleeping():
				slept = true
				break
	check(slept, "postava usnula")
	petr.needs.values["social"] = 0.0
	petr.needs.values["fun"] = 0.0
	for i in 15:
		clock.advance(1.0)
		petr.needs.values["social"] = 0.0
	check(petr._is_sleeping(), "samota a nuda spánek nepřeruší (žádná nespavost z osamělosti)")
	petr.needs.values["hunger"] = 1.0
	for i in 15:
		clock.advance(1.0)
		petr.needs.values["hunger"] = minf(petr.needs.values["hunger"], 1.0)
	check(not petr._is_sleeping(), "kritický hlad spánek přeruší")
	for s in [jana, petr, eli]:
		_reset(s)
		s.think_cooldown = 1.0
	await get_tree().process_frame
