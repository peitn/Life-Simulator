extends "res://tests/test_base.gd"
## Test duševního zdraví a nastavení obsahu:
## stres, tři složky úzkosti, panická ataka (mimovolná, ale hráč není zamčený), copingy
## s kompromisy (žádný není dominantní napříč kontexty), anti-farming v krátkém i delším
## horizontu, vyhýbání a alkohol s dlouhodobou cenou, expozice, cesta k zotavení nikdy
## uzavřená, rušivé myšlenky jako subjektivní interpretace, svědci (pomoc/stigma),
## žárlivost, soukromí a to, že nastavení obsahu skutečně filtruje texty i události.

const Main := preload("res://main.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const PsycheFX := preload("res://scripts/world/psyche_fx.gd")

var world: Node3D
var clock: Node
var gs: Node
const CFG_FULL := {"conditions": true, "episodes": true, "thought_rate": 1.0}
const NEEDS_OK := {"hunger": 70.0, "energy": 70.0, "hygiene": 70.0, "fun": 70.0, "social": 70.0, "comfort": 70.0}


func _ready() -> void:
	watchdog_seconds = 90.0
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


func _ctx(now: float, extra := {}) -> Dictionary:
	var c := {"energy": 70.0, "hunger": 70.0, "needs": NEEDS_OK, "sleeping": false, "night": false,
		"now": now, "cfg": CFG_FULL}
	c.merge(extra, true)
	return c


func _anxious(seed_v := 1, severity := 0.6) -> MentalState:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var m := MentalState.new(r, true)
	m.conditions = {"anxiety": severity}
	m.sensitivity = m.baseline_sensitivity()
	return m


func _run_ticks(m: MentalState, minutes: int, start: float, extra := {}) -> float:
	var t := start
	for i in minutes:
		t += 1.0
		m.tick(1.0, _ctx(t, extra))
	return t


func _run() -> void:
	_test_settings()
	_test_dynamics()
	_test_panic_model()
	_test_agency_matrix()
	_test_antifarming()
	_test_avoidance_alcohol()
	_test_exposure_recovery()
	_test_thoughts_ui()
	await _test_in_world()
	finish("test_mental_health")


# ---------------------------------------------------------------- nastavení

func _test_settings() -> void:
	section("Nastavení obsahu")
	check(gs.get_value("mental_health") == "full" and gs.thought_rate() == 1.0, "výchozí: plně, normální myšlenky")
	check(not gs.set_value("mental_health", "hardcore"), "neplatný režim odmítnut")
	check(not gs.set_value("addiction", "ano"), "špatný typ odmítnut")
	check(not gs.set_value("neexistuje", 1), "neznámý klíč odmítnut")
	gs.set_value("intrusive_thoughts", 99)
	check(gs.get_value("intrusive_thoughts") == 3, "intenzita oříznuta do 0–3")
	gs.set_value("mental_health", "muted")
	check(not gs.allows_episodes() and gs.allows_conditions() and gs.thought_rate() < 1.0, "ztlumeno: bez atak, méně myšlenek")
	gs.set_value("mental_health", "off")
	check(not gs.allows_conditions() and gs.thought_rate() == 0.0 and gs.distortion_strength() == 0.0, "vypnuto: bez diagnóz, myšlenek i zkreslení")
	gs.reset()
	gs.set_value("addiction", false)
	check(not gs.allows_content("addiction") and gs.allows_content(""), "závislosti vypnuté → obsah 'addiction' zakázán")
	gs.reset()
	check(gs.CRISIS_LINES.size() >= 2 and String(gs.CRISIS_LINES[0][1]) == "116 123", "krizová linka 116 123 v nastavení")
	check(gs.CONTENT_WARNING.find("sebevražda není hratelná akce") >= 0, "varování zmiňuje, že sebevražda není hratelná")
	var c: String = gs.censor("Kurva, to je ale prdel, ty vole.")
	check(c.find("Kurva") < 0 and c.find("prdel") < 0 and c.find("vole") < 0 and c.begins_with("K****"), "cenzura sprostých slov", c)
	check(gs.censor("Bylo to svoleno a vole­no.").begins_with("Bylo to svoleno"), "cenzura nezasahuje doprostřed slov")
	gs.set_value("profanity", false)
	check(gs.filter_profanity("Táhni do prdele.") != "Táhni do prdele.", "filtr podle nastavení hráče")
	gs.reset()
	check(gs.filter_profanity("Táhni do prdele.") == "Táhni do prdele.", "se zapnutou sprostou mluvou beze změny")


# ---------------------------------------------------------------- dynamika

func _test_dynamics() -> void:
	section("Stres a tři složky úzkosti")
	var calm := MentalState.new()
	var anx := _anxious()
	check(anx.vulnerability() > calm.vulnerability() and anx.baseline_sensitivity() > calm.baseline_sensitivity(),
		"predispozice zvyšuje zranitelnost a výchozí citlivost")
	check(anx.vulnerability({"conditions": false}) == 0.0, "s vypnutými diagnózami zranitelnost 0")
	var s0 := anx.stress
	anx.on_stressor("argue", 10.0, CFG_FULL)
	calm.on_stressor("argue", 10.0, CFG_FULL)
	check(anx.stress > s0 and anx.threat > calm.threat, "hádka přidá stres; úzkostné postavě víc vnímané hrozby",
		"%.2f vs %.2f" % [anx.threat, calm.threat])
	var a0 := anx.arousal
	var t := _run_ticks(anx, 10, 0.0)
	var peak := anx.arousal
	check(peak > a0 + 5.0, "aktivace rychle stoupne", "%.1f → %.1f" % [a0, peak])
	# Asymetrie: nahoru za minuty, dolů za desítky minut.
	var m2 := _anxious(3)
	m2.threat = 1.0
	var rise := 0
	while m2.arousal < 50.0 and rise < 300:
		m2.threat = 1.0
		m2.tick(1.0, _ctx(rise))
		rise += 1
	m2.threat = 0.0
	var fall := 0
	while m2.arousal > 30.0 and fall < 600:
		m2.tick(1.0, _ctx(rise + fall))
		fall += 1
	check(rise < fall, "aktivace stoupá rychleji, než klesá", "nahoru %d min, dolů %d min" % [rise, fall])
	t = _run_ticks(anx, 600, t)
	check(anx.arousal < peak and anx.threat < 0.05, "bez spouštěčů se postava zklidní", "%.1f" % anx.arousal)
	var hungry := MentalState.new()
	var st0 := hungry.stress
	for i in 120:
		hungry.tick(1.0, _ctx(i, {"needs": {"hunger": 5.0, "energy": 10.0}, "hunger": 5.0, "energy": 10.0}))
	check(hungry.stress > st0 + 5.0, "neuspokojené potřeby přidávají stres", "%.1f → %.1f" % [st0, hungry.stress])
	check(hungry.regulation(10.0, 5.0) < hungry.regulation(90.0, 90.0), "únava a hlad snižují regulační kapacitu")
	var night := _anxious()
	night.arousal = 70.0
	check(night.sleep_quality() < 0.9 and night.energy_drain_mult() > 1.0, "úzkost zhoršuje spánek a vyčerpává")
	check(night.social_difficulty(CFG_FULL) > MentalState.new().social_difficulty(CFG_FULL), "sociální akce jsou v úzkosti náročnější")


# ---------------------------------------------------------------- ataka

func _panic_duration(grounding: bool) -> int:
	var m := _anxious(11)
	m._start_panic()
	var n := 0
	while m.panic_active and n < 60:
		m.tick(1.0, _ctx(n, {"grounding": grounding}))
		n += 1
	return n


func _test_panic_model() -> void:
	section("Panická ataka (model)")
	var m := _anxious(5, 0.8)
	m.sensitivity = 0.8
	var t := 0.0
	var started := false
	for i in 240:
		m.threat = 1.0
		t += 1.0
		m.tick(1.0, _ctx(t))
		if m.panic_active:
			started = true
			break
	check(started and m.panic_count == 1, "vysoká aktivace u predispozice → ataka", "aktivace %.0f" % m.arousal)
	var dur := 0
	while m.panic_active and dur < 60:
		t += 1.0
		m.tick(1.0, _ctx(t))
		dur += 1
	check(not m.panic_active and dur <= MentalState.PANIC_MAX_MINUTES + 1, "ataka sama odezní (minuty, ne hodiny)", "%d min" % dur)
	check(m.panic_cooldown > 0.0, "po atace je ochranná pauza (žádná smyčka atak)")
	var calm := MentalState.new()
	calm.arousal = 95.0
	for i in 120:
		calm.threat = 1.0
		calm.tick(1.0, _ctx(i))
	check(calm.panic_count == 0, "bez predispozice ataky nevznikají (stres ano)")
	var off := _anxious(5, 0.8)
	off.sensitivity = 0.9
	for i in 240:
		off.threat = 1.0
		off.tick(1.0, _ctx(i, {"cfg": {"conditions": true, "episodes": false, "thought_rate": 1.0}}))
	check(off.panic_count == 0, "nastavení „ztlumeně“ ataky vypne")
	var d_free := _panic_duration(false)
	var d_ground := _panic_duration(true)
	check(d_ground < d_free, "dýchání / opora ataku zkrátí (ale nezruší okamžitě)", "%d vs %d min" % [d_ground, d_free])
	check(d_ground >= MentalState.PANIC_MIN_MINUTES, "ani s pomocí neskončí hned")
	# Pravděpodobnost ataky nezávisí na délce simulačního kroku (1 min vs 2 min, víc seedů).
	var hits_1 := 0
	var hits_2 := 0
	for sd in 400:
		for step in [1.0, 2.0]:
			var mm := _anxious(1000 + sd, 0.8)
			mm.sensitivity = 0.7
			mm.arousal = 85.0
			var tt := 0.0
			while tt < 20.0 and not mm.panic_active:
				mm.threat = 0.91  # cíl aktivace ≈ 85 → aktivace se mezi kroky nemění
				mm.arousal = 85.0
				mm.tick(step, _ctx(tt, {"needs": NEEDS_OK}))
				tt += step
			if mm.panic_active:
				if step == 1.0:
					hits_1 += 1
				else:
					hits_2 += 1
	check(absf(hits_1 - hits_2) < 400 * 0.08, "hazard ataky nezávisí na délce kroku", "1 min: %d, 2 min: %d ze 400" % [hits_1, hits_2])


# ---------------------------------------------------------------- agency

## Metriky jedné volby v daném kontextu (vyšší = lepší u všech kromě uvedených).
func _measure(id: String, ctx_kind: String) -> Dictionary:
	var m := _anxious(21)
	m.arousal = 85.0 if ctx_kind == "peak" else 65.0
	m.stress = 60.0
	var energy := 15.0 if ctx_kind == "tired" else 70.0
	var c := {"now": 100.0, "energy": energy, "hunger": 70.0, "day": 1, "rel": 55.0, "dismissed": false}
	if ctx_kind == "low_trust":
		c["rel"] = -20.0
		c["dismissed"] = true
	var s0 := m.sensitivity
	var ma0 := m.mastery
	var res := m.apply_coping(id, 1.0, c)
	var short_relief := -float(res.get("arousal", 0.0)) - float(res.get("stress", 0.0)) * 0.5
	# Další den: průměrná aktivace v čase 12–24 h (rebound alkoholu, citlivost…)
	var sum := 0.0
	for i in 1440:
		m.tick(1.0, _ctx(100.0 + i, {"energy": energy}))
		if i >= 720:
			sum += m.arousal
	var act: Dictionary = {}
	for a in ActionLibrary.ACTIONS:
		if String(a.get("coping", "")) == id:
			act = a
	var cost := -minf(float(act.get("effects", {}).get("energy", 0.0)), 0.0)
	if String(act.get("object", "")) == "sim":
		cost += 6.0  # potřebuje druhého člověka a nese riziko odbytí
	return {"executed": not res.is_empty(), "short": short_relief, "sens": -(m.sensitivity - s0) * 1000.0,
		"mastery": (m.mastery - ma0) * 1000.0, "next_day": -sum / 720.0, "cost": -cost}


## Vrátí id volby, která je ve všech metrikách alespoň tak dobrá jako všechny ostatní, jinak "".
func _dominant(ids: Array, table: Dictionary, keys: Array) -> String:
	for x in ids:
		var dom := true
		for y in ids:
			if x == y:
				continue
			for k in keys:
				if float(table[y][k]) > float(table[x][k]) + 0.001:
					dom = false
		if dom:
			return x
	return ""


func _test_agency_matrix() -> void:
	section("Agency: stejný stav, různé volby (žádná není dominantní)")
	var ids: Array = MentalState.COPINGS.keys()
	var contexts := ["normal", "peak", "tired", "low_trust"]
	var avg := {}
	var per_ctx := {}
	var all_exec := true
	for ck in contexts:
		per_ctx[ck] = {}
	for id in ids:
		var acc := {"short": 0.0, "sens": 0.0, "mastery": 0.0, "next_day": 0.0, "cost": 0.0}
		for ck in contexts:
			var r := _measure(id, ck)
			all_exec = all_exec and bool(r["executed"])
			per_ctx[ck][id] = r
			for k in acc:
				acc[k] += float(r[k]) / contexts.size()
		avg[id] = acc
	# Nedominance i v každém kontextu zvlášť (ne jen v průměru).
	var ctx_dom: PackedStringArray = []
	for ck in contexts:
		var d := _dominant(ids, per_ctx[ck], ["short", "sens", "mastery", "next_day", "cost"])
		if d != "":
			ctx_dom.append("%s:%s" % [ck, d])
	check(ctx_dom.is_empty(), "ani v jednotlivém kontextu není žádná volba nejlepší ve všem", ", ".join(ctx_dom))
	check(all_exec, "každá volba je proveditelná v každém kontextu")
	var dominated_by_none := true
	var dominant := ""
	for x in ids:
		# x je dominantní, pokud je ve všech metrikách alespoň tak dobrá jako všechny ostatní
		var dom := true
		for y in ids:
			if x == y:
				continue
			for k in avg[x]:
				if float(avg[y][k]) > float(avg[x][k]) + 0.001:
					dom = false
		if dom:
			dominated_by_none = false
			dominant = x
	var table: PackedStringArray = []
	for id in ids:
		var a: Dictionary = avg[id]
		table.append("%s[úleva %.1f, citl %.1f, zvl %.1f, zítra %.1f, cena %.1f]" % [id, a["short"], a["sens"], a["mastery"], a["next_day"], a["cost"]])
	print("    " + "\n    ".join(table))
	check(dominated_by_none, "žádná volba není nejlepší ve všech metrikách", dominant)
	check(float(avg["hide"]["short"]) > float(avg["breathe"]["short"]) and float(avg["hide"]["sens"]) < float(avg["breathe"]["sens"]),
		"vyhýbání: silnější okamžitá úleva, horší dlouhodobě")
	check(float(avg["drink"]["next_day"]) < float(avg["walk"]["next_day"]), "alkohol: druhý den horší než procházka")
	var trust := _measure("confide", "normal")
	var distrust := _measure("confide", "low_trust")
	check(float(trust["short"]) > 0.0 and float(distrust["short"]) < 0.0, "svěřit se pomůže jen u důvěry; odbytí ublíží")
	# Přerušené svěření s odbytím: následky úměrné tomu, kolik rozhovoru proběhlo.
	var md := _anxious(77)
	md.arousal = 50.0
	var a_before := md.arousal
	var r0 := md.apply_coping("confide", 0.0, {"now": 10.0, "dismissed": true, "rel": -20.0})
	check(absf(float(r0["arousal"])) < 0.001 and md.arousal == a_before, "nedokončené svěření (fraction 0) samo nic nezhorší")
	var mf := _anxious(78)
	var sups: Array = []
	for i in 4:
		sups.append(float(mf.apply_coping("confide", 1.0, {"now": 100.0 + i * 20.0, "rel": 80.0})["support"]))
	check(sups[3] < sups[0] * 0.5, "opakované svěřování nefarmí oporu (habituace)", str(sups))
	var peak := _measure("breathe", "peak")
	var norm := _measure("breathe", "normal")
	check(float(peak["short"]) < float(norm["short"]), "dýchání ve špičce funguje hůř než včas")


# ---------------------------------------------------------------- anti-farming

func _test_antifarming() -> void:
	section("Anti-farming (krátký i delší horizont)")
	var m := _anxious(31)
	var gains: Array = []
	for i in 5:
		m.arousal = 70.0
		var r := m.apply_coping("breathe", 1.0, {"now": 100.0 + i * 12.0, "energy": 70.0, "hunger": 70.0, "day": 1})
		gains.append(-float(r["arousal"]))
	var decreasing := true
	for i in range(1, gains.size()):
		if gains[i] >= gains[i - 1]:
			decreasing = false
	check(decreasing and gains[4] < gains[0] * 0.5, "opakované dýchání během hodiny má klesající účinek", str(gains))
	m.arousal = 70.0
	var later := m.apply_coping("breathe", 1.0, {"now": 100.0 + 60.0 + MentalState.HABITUATION_WINDOW, "energy": 70.0, "hunger": 70.0, "day": 1})
	check(-float(later["arousal"]) >= gains[0] * 0.9, "po delší pauze se účinek obnoví", "%.1f vs %.1f" % [-float(later["arousal"]), gains[0]])
	var j := _anxious(32)
	j.arousal = 50.0
	var j1 := j.apply_coping("journal", 1.0, {"now": 10.0, "energy": 70.0, "hunger": 70.0, "day": 3})
	var j2 := j.apply_coping("journal", 1.0, {"now": 10.0 + MentalState.HABITUATION_WINDOW + 1.0, "energy": 70.0, "hunger": 70.0, "day": 3})
	var j3 := j.apply_coping("journal", 1.0, {"now": 1440.0 * 3, "energy": 70.0, "hunger": 70.0, "day": 4})
	check(absf(float(j2["sens"])) < absf(float(j1["sens"])) * 0.3 and absf(float(j3["sens"])) > absf(float(j2["sens"])),
		"deník: dlouhodobý přínos jen 1× denně, další den znovu")
	# Opakování na stejném místě nedává lineární bonus: 10 dechových cvičení za sebou ≠ 10× účinek.
	var lin := _anxious(33)
	var total := 0.0
	for i in 10:
		lin.arousal = 70.0
		total += -float(lin.apply_coping("breathe", 1.0, {"now": 500.0 + i * 10.0, "energy": 70.0, "hunger": 70.0, "day": 1})["arousal"])
	check(total < gains[0] * 4.0, "10 opakování dá míň než 4× jedno použití (žádný grind)", "%.1f" % total)


# ---------------------------------------------------------------- vyhýbání a alkohol

func _test_avoidance_alcohol() -> void:
	section("Vyhýbání a alkohol – dlouhodobé důsledky")
	var hide := _anxious(41)
	var breathe := _anxious(41)
	var t := 0.0
	for day in 7:
		for m in [hide, breathe]:
			m.arousal = 65.0
		hide.apply_coping("hide", 1.0, {"now": t, "energy": 70.0, "hunger": 70.0, "day": day})
		breathe.apply_coping("breathe", 1.0, {"now": t, "energy": 70.0, "hunger": 70.0, "day": day})
		for i in 1440:
			t += 1.0
			hide.tick(1.0, _ctx(t))
			breathe.tick(1.0, _ctx(t))
	check(hide.sensitivity > breathe.sensitivity and hide.mastery < breathe.mastery,
		"týden vyhýbání: vyšší citlivost a nižší pocit zvládnutelnosti", "citl %.3f vs %.3f, zvl %.3f vs %.3f" % [
			hide.sensitivity, breathe.sensitivity, hide.mastery, breathe.mastery])
	var d := _anxious(42)
	d.arousal = 65.0
	var first := d.apply_coping("drink", 1.0, {"now": 0.0, "energy": 70.0, "hunger": 70.0, "day": 1})
	check(d.alcohol > 0.2, "pivo zvýší hladinu alkoholu")
	var tt := _run_ticks(d, 600, 0.0)
	check(d.rebound > 0.1, "po odbourání alkoholu přichází úzkostný rebound", "%.2f" % d.rebound)
	var has_rebound := false
	for e in d.mood_entries():
		if e["id"] == "rebound":
			has_rebound = true
	check(has_rebound or d.rebound > 0.1, "rebound se projeví v náladě / aktivaci")
	var last := {}
	for i in 6:
		d.arousal = 65.0
		last = d.apply_coping("drink", 1.0, {"now": tt + (i + 1) * 700.0, "energy": 70.0, "hunger": 70.0, "day": 2 + i})
		tt = _run_ticks(d, 10, tt + (i + 1) * 700.0)
	check(d.tolerance > 0.15 and -float(last["arousal"]) < -float(first["arousal"]), "tolerance: stejná dávka uleví méně",
		"%.1f → %.1f" % [-float(first["arousal"]), -float(last["arousal"])])
	var lo := d.coping_appeal("drink", 70.0, 70.0, tt + 5000.0)
	var fresh := _anxious(42)
	fresh.arousal = d.arousal
	fresh.stress = d.stress
	check(lo >= fresh.coping_appeal("drink", 70.0, 70.0, 0.0), "návyk: s tolerancí pití láká víc")


# ---------------------------------------------------------------- expozice a zotavení

func _test_exposure_recovery() -> void:
	section("Expozice a cesta k zotavení")
	var m := _anxious(51)
	var s0 := m.sensitivity
	var ma0 := m.mastery
	m.on_social_completed(true, 60.0, "Jana Nováková", true, 10.0, CFG_FULL)
	check(m.mastery > ma0 and m.sensitivity < s0, "zvládnutý hovor ve vysokém napětí: zkušenost (+zvládnutelnost)")
	var m2 := _anxious(51)
	m2.on_social_completed(false, 60.0, "Petr Dvořák", false, 10.0, CFG_FULL)
	check(m2.mastery > ma0 and m2.mastery - ma0 < m.mastery - ma0, "nepovedený hovor: jen malý zisk, žádná garantovaná odměna")
	var worst := _anxious(52, 1.0)
	worst.sensitivity = 1.0
	worst.mastery = 0.0
	var t := 0.0
	for i in 14:
		worst.on_social_completed(true, 60.0, "Jana", true, t, CFG_FULL)
		worst.receive_support(70.0)
		worst.apply_coping("walk", 1.0, {"now": t, "energy": 70.0, "hunger": 70.0, "day": i})
		t = _run_ticks(worst, 720, t)
	check(worst.sensitivity < 0.9 and worst.mastery > 0.1, "i z nejhoršího stavu vede cesta zpět (nic není uzavřené)",
		"citl %.2f, zvl %.2f" % [worst.sensitivity, worst.mastery])
	check(worst.sensitivity > 0.0 and not ("cured" in worst), "žádné „vyléčeno na 100 %“ – zranitelnost zůstává")
	var good := 0
	var bad := 0
	var r := _anxious(53)
	for i in 60:
		r.new_day()
		if r.day_factor > 0.35:
			good += 1
		elif r.day_factor < -0.35:
			bad += 1
	check(good > 3 and bad > 3, "dobré i špatné dny se střídají", "%d dobrých, %d špatných z 60" % [good, bad])


# ---------------------------------------------------------------- myšlenky a UI

func _test_thoughts_ui() -> void:
	section("Rušivé myšlenky jako subjektivní interpretace")
	var m := _anxious(61)
	var t := 0.0
	for i in 400:
		m.threat = 0.8
		m.stress = 70.0
		t += 1.0
		m.tick(1.0, _ctx(t))
	check(m.thoughts.size() > 0, "v napětí vznikají rušivé myšlenky", str(m.thoughts.size()))
	var silent := _anxious(61)
	for i in 400:
		silent.threat = 0.8
		silent.stress = 70.0
		silent.tick(1.0, _ctx(i, {"cfg": {"conditions": true, "episodes": true, "thought_rate": 0.0}}))
	check(silent.thoughts.is_empty(), "intenzita 0 → žádné myšlenky")
	var txt: String = Hud.format_thought("Všichni mě nesnášejí.")
	check(txt.find("myšlenka, ne fakt") >= 0, "UI označí myšlenku jako myšlenku, ne fakt", txt)
	var mind := {"thoughts": [[t - 10.0, "Proč se vždycky všechno posere zrovna mně?"]]}
	check(Hud.visible_thoughts(mind, t, gs).size() == 1, "myšlenka se zobrazí")
	gs.set_value("intrusive_thoughts", 0)
	check(Hud.visible_thoughts(mind, t, gs).is_empty(), "klient s vypnutými myšlenkami je nevidí")
	gs.reset()
	gs.set_value("profanity", false)
	var vis: Array = Hud.visible_thoughts(mind, t, gs)
	check(String(vis[0][0]).find("posere") < 0, "sprostá slova v myšlenkách se cenzurují podle nastavení", String(vis[0][0]))
	gs.reset()
	check(Hud.visible_thoughts({"thoughts": [[t - 1000.0, "stará"]]}, t, gs).is_empty(), "staré myšlenky zmizí")
	check(Hud.visible_thoughts({"thoughts": ["zlý typ", [1]]}, t, gs).is_empty(), "poškozená data myšlenek nespadnou")
	var after := _anxious(62, 1.0)
	after.arousal = 70.0
	var got := ""
	for i in 30:
		got = after.on_social_completed(true, 20.0, "Petr Dvořák", false, float(i), CFG_FULL)
		if got != "":
			break
	check(got != "" and (got.find("Asi") >= 0 or got.find("Petr") >= 0 or got.find("Mluvila") >= 0),
		"úzkostná interpretace i po dobrém hovoru (subjektivní)", got)
	check(PsycheFX.target_level({"arousal": 90, "panic": true}, 1.0) > 0.8 and PsycheFX.target_level({"arousal": 90}, 0.0) == 0.0
		and PsycheFX.target_level({"arousal": 20}, 1.0) == 0.0, "zkreslení obrazu jen při úzkosti a jen když je zapnuté")


# ---------------------------------------------------------------- ve světě

func _idx(tag: String) -> int:
	var objs: Array = world.get_smart_objects()
	for i in objs.size():
		if objs[i].object_tag == tag:
			return i
	return -1


func _reset_all() -> void:
	for s in world.get_sims():
		s.player_queue.clear()
		if s._in_panic_action():
			s.mental.end_panic()
			s._finish(false)
		s.command({"id": "cancel"}, null)
		s.mental.panic_active = false
		s.mental.panic_cooldown = 0.0
		s.mental.arousal = 10.0
		s.mental.threat = 0.0
		s.mental.stress = 15.0
		s.think_cooldown = 1.0e9
		s._helping_me = 0


func _force_panic(s) -> void:
	s.mental._start_panic()
	clock.advance(1.0)


func _test_in_world() -> void:
	section("Ve světě: panická ataka, příkazy, svědci")
	var jana = world.find_sim(SimAgent.node_name_for("Jana Nováková"))
	var petr = world.find_sim(SimAgent.node_name_for("Petr Dvořák"))
	var eli = world.find_sim(SimAgent.node_name_for("Eliška Malá"))
	var net = world.net
	check(eli.mental.conditions.has("anxiety") and not jana.mental.conditions.has("anxiety") and petr.mental.conditions.is_empty(),
		"predispozice k úzkosti jen Elišce (Jana má od Dne 6 predispozici k depresi, Petr nic)")
	check(not Main.HOUSEHOLD[2].has("node_name") and Main.HOUSEHOLD[2]["mind"]["predispositions"].has("anxiety"), "domácnost má predispozici v datech serveru")
	check(not NetSession.SYNC_PROPS.has("net_detail") and not NetSession.SYNC_PROPS.has("mind"), "duševní stav není ve veřejné synchronizaci")
	var info: Dictionary = eli.hud_info()
	check(info.has("mind") and info["mind"].has("label") and info["mind"]["conditions"].size() == 1, "soukromý detail obsahuje duševní stav")
	_reset_all()
	for s in [jana, petr]:
		s.global_position = eli.global_position + Vector3(30, 0, 0)  # mimo dosah svědků
	_force_panic(eli)
	check(eli._in_panic_action() and eli.display_action() == "Panická ataka", "ataka přeruší činnost (mimovolně)")
	check(net.handle_command(1, eli.name, "panic", "") != "", "ataku nejde zadat jako příkaz")
	check(net.handle_command(1, eli.name, "watch_tv", _idx("tv")) == "" and eli._in_panic_action() and eli.player_queue.size() == 1,
		"běžný příkaz během ataky počká ve frontě")
	net.handle_command(1, eli.name, "cancel", "")
	check(eli._in_panic_action() and eli.player_queue.is_empty(), "zrušit symptom nejde, jen frontu")
	net.handle_command(1, eli.name, "watch_tv", _idx("tv"))
	net.handle_command(1, eli.name, "read", _idx("bookshelf"))
	net.handle_command(1, eli.name, "snack", _idx("fridge"))
	check(eli.player_queue.size() == 3, "fronta je plná")
	check(net.handle_command(1, eli.name, "breathe", "") == "" and eli.current_action.get("id", "") == "breathe",
		"dýchání jde zadat i během ataky – i s plnou frontou (hráč není zamčený)")
	check(eli.player_queue.size() <= 3, "fronta nepřeteče")
	eli.player_queue.clear()
	var steps := 0
	while eli.mental.panic_active and steps < 40:
		clock.advance(1.0)
		steps += 1
	check(not eli.mental.panic_active, "ataka během dýchání odezní", "%d min" % steps)
	check(not eli._in_panic_action(), "po atace se postava k atace nevrací")
	var mem_ok := false
	for e in eli.memories:
		if String(e["text"]).find("Panická ataka") >= 0:
			mem_ok = true
	check(mem_ok, "ataka zůstává v paměti")

	section("Svědci: pomoc a stigma")
	_reset_all()
	jana.relationships[eli.sim_name] = 90.0
	jana.trait_ids = ["spolecensky", "gurman"]
	petr.global_position = eli.global_position + Vector3(30, 0, 0)
	var helped := false
	for attempt in 6:
		_reset_all()
		jana.global_position = eli.global_position + Vector3(3, 0, 0)
		_force_panic(eli)
		for i in 30:
			clock.advance(1.0)
			if eli.mood.has_moodlet("pomoc_" + String(jana.name)):
				helped = true
				break
		if helped:
			break
	check(helped, "blízká postava přijde pomoct (vztah, povaha)")
	check(float(eli.relationships.get(jana.sim_name, 0.0)) > 0.0, "pomoc posílí vztah")
	# Pomocníka někdo pozve k hovoru → počítadlo pomoci se nesmí „zaseknout“.
	if jana.state == SimAgent.State.ACTING and jana.current_action.get("approach_only", false):
		jana.join_social(petr, ActionLibrary.get_action("chat").duplicate(true))
		jana.social_partner = null
		jana.command({"id": "cancel"}, null)
	check(eli._helping_me == 0, "přerušená pomoc nenechá viset počítadlo podpory", str(eli._helping_me))
	_reset_all()
	jana.trait_ids = ["spolecensky", "gurman", "zarlivy"]
	jana.global_position = eli.global_position + Vector3(30, 0, 0)
	petr.relationships[eli.sim_name] = -80.0
	var stigma := false
	for attempt in 8:
		_reset_all()
		petr.global_position = eli.global_position + Vector3(3, 0, 0)
		var rel0: float = float(eli.relationships.get(petr.sim_name, 0.0))
		_force_panic(eli)
		if eli.mood.has_moodlet("stigma_" + String(petr.name)):
			stigma = float(eli.relationships.get(petr.sim_name, 0.0)) < rel0
			break
	check(stigma, "bručoun s špatným vztahem reaguje stigmatem → bolí, vztah klesne")
	check(net.handle_command(1, jana.name, "comfort_panic", String(petr.name)) != "", "uklidňovat jde jen postavu v atace")
	_reset_all()

	section("Svěřit se a žárlivost")
	jana.global_position = eli.global_position + Vector3(1.5, 0, 0)
	eli.relationships[jana.sim_name] = 70.0
	jana.relationships[eli.sim_name] = 70.0
	eli.mental.stress = 70.0
	eli.mental.arousal = 60.0
	check(net.handle_command(1, eli.name, "confide", String(jana.name)) == "", "svěření přijato")
	var confided := false
	for i in 60:
		clock.advance(1.0)
		if int(eli.mental.coping_counts.get("confide", 0)) > 0:
			confided = true
			break
	check(confided, "svěření proběhlo a započítalo se jako coping")
	check(not jana.mental.coping_counts.has("confide"), "úlevu z copingu má jen ten, kdo se svěřuje")
	_reset_all()
	jana.relationships[eli.sim_name] = 60.0
	jana.global_position = Vector3.ZERO
	petr.global_position = Vector3(1, 0, 0)
	eli.global_position = Vector3(-1, 0, 0)
	petr._social_outcome(eli, 5.0, "chat")
	check(jana.mood.has_moodlet("zarli_" + String(petr.name)) or jana.mood.has_moodlet("zarli_" + String(eli.name)),
		"žárlivá postava nese těžce, když se její blízká baví s jiným")

	section("Nastavení filtruje události")
	_reset_all()
	gs.set_value("addiction", false)
	check(net.handle_command(1, petr.name, "drink", _idx("fridge")) != "", "server odmítne pití při vypnutých závislostech")
	petr.mental.stress = 90.0
	petr.mental.arousal = 80.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var drinks := 0
	for i in 300:
		var c: Dictionary = Planner.choose(petr, world.get_smart_objects(), world.get_sims(), rng, 20)
		if not c.is_empty() and c["action"]["id"] == "drink":
			drinks += 1
	check(drinks == 0, "AI si při vypnutých závislostech nevybere alkohol", str(drinks))
	gs.reset()
	petr.needs.values["energy"] = 30.0
	var sc: float = Planner.score_action(petr, ActionLibrary.get_action("drink"), 17)
	var sc_calm := 0.0
	petr.mental.stress = 10.0
	petr.mental.arousal = 5.0
	sc_calm = Planner.score_action(petr, ActionLibrary.get_action("drink"), 17)
	check(sc > 0.0 and sc_calm == 0.0, "se zapnutými závislostmi pití láká jen ve stresu (ne jako zábava)", "%.1f / %.1f" % [sc, sc_calm])
	gs.set_value("mental_health", "off")
	_reset_all()
	eli.mental.sensitivity = 0.9
	var pc0: int = eli.mental.panic_count
	for i in 120:
		eli.mental.threat = 1.0
		clock.advance(1.0)
	check(eli.mental.panic_count == pc0 and not eli._in_panic_action(), "duševní zdraví vypnuto → žádná nová ataka")
	var mind_off: Dictionary = eli.hud_info()["mind"]
	check(mind_off["conditions"].is_empty(), "vypnuto → diagnózy se nezobrazují")
	gs.reset()
	_reset_all()
	var picked := 0
	for i in 200:
		var c: Dictionary = Planner.choose(eli, world.get_smart_objects(), world.get_sims(), rng, 14)
		if not c.is_empty() and (c["action"]["id"] == "panic" or c["action"]["id"] == "comfort_panic"):
			picked += 1
	check(picked == 0, "plánovač nikdy nevybere ataku ani systémovou pomoc")
	await get_tree().process_frame
