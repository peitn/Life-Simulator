extends "res://tests/test_base.gd"
## Plná domácnost (zátěžový test uživatelky 23. 10. 2026: 7 postav × 30 dní zkolabovalo).
## Jednotky: SensoryProfile (citlivost na hluk, tlačenici, radost, práh těšení, návyky), radost tlumená
## depresí a stresem, hluk jen jednou za cooldown na spáče, alkohol v klouzavém okně, prodlužující se
## refrakterní doba po opakovaných atakách, nouzový spánek. Dlouhý běh: 7 postav (zdraví / s
## predispozicemi) × 2 seedy × 14 dní – zdraví se nehroutí, deprese nezamrzne na maximu, hádky v mezích.

const Main := preload("res://main.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const SensoryProfile := preload("res://scripts/sim/sensory_profile.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const HouseholdDynamics := preload("res://scripts/sim/household_dynamics.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

const SEEDS := 2
const DAYS := 14

var clock: Node
var gs: Node


func _ready() -> void:
	watchdog_seconds = 900.0
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	_run.call_deferred()


func _run() -> void:
	_test_profile()
	_test_joy_and_threshold()
	_test_mental_limits()
	_test_noise_rules()
	await _test_long("household_healthy7", true)
	await _test_long("household_stress7", false)
	Main.household_override = []
	finish("test_crowded_household")


# ---------------------------------------------------------------- jednotky

func _test_profile() -> void:
	section("Individuální citlivosti (SensoryProfile)")
	var a := SensoryProfile.new()
	a.setup(["lenoch", "spolecensky"], {}, 1234)
	var b := SensoryProfile.new()
	b.setup(["uzkostlivy", "samotar"], {"anxiety": 0.8}, 1234)
	check(a.noise_sens < b.noise_sens, "lenoch a společenský snese hluk víc než úzkostlivý samotář",
		"%.2f vs %.2f" % [a.noise_sens, b.noise_sens])
	check(a.crowd_sens < b.crowd_sens, "tlačenice vadí samotáři víc než společenskému")
	var c := SensoryProfile.new()
	c.setup(["lenoch", "spolecensky"], {}, 1234)
	check(is_equal_approx(a.noise_sens, c.noise_sens) and is_equal_approx(a.anticip_thr, c.anticip_thr), "stejný seed a rysy → stejný profil")
	var d := SensoryProfile.new()
	d.setup(["lenoch", "spolecensky"], {}, 99)
	check(not is_equal_approx(a.noise_sens, d.noise_sens), "jiný seed → jiná individualita (nejen rysy)")
	var spread: Array = []
	for i in 200:
		var p := SensoryProfile.new()
		p.setup([], {}, i)
		spread.append(p.noise_sens)
		if p.noise_sens < 0.2 or p.noise_sens > 1.6 or p.anticip_thr < 0.0 or p.anticip_thr > 4.0:
			check(false, "meze profilu", str(p.to_dict()))
			return
	check(spread.max() - spread.min() > 0.3, "lidé bez rysů se liší (rozptyl citlivosti)", "%.2f–%.2f" % [spread.min(), spread.max()])
	var h := SensoryProfile.new()
	h.setup([], {}, 5)
	var f0 := h.noise_factor()
	for i in 200:
		h.expose_noise(1.0)
	check(h.noise_factor() < f0 * 0.6 and h.noise_habit <= SensoryProfile.HABIT_MAX + 1e-6, "na hluk se dá zvyknout (s horní mezí)",
		"%.2f → %.2f" % [f0, h.noise_factor()])
	h.tick(SensoryProfile.HABIT_TAU * 3.0)
	check(h.noise_habit < 0.05, "návyk bez podnětu vyprchá")


func _test_joy_and_threshold() -> void:
	section("Radost a práh těšení")
	var p := SensoryProfile.new()
	p.setup(["optimista"], {}, 7)
	var full := p.joy_capacity(1.0, 20.0)
	check(p.joy_capacity(0.3, 20.0) < full * 0.5, "anhedonie (nízké liking) tlumí radost")
	check(p.joy_capacity(1.0, 95.0) < full * 0.75, "vysoký stres tlumí radost z příjemných věcí")
	var cyn := SensoryProfile.new()
	cyn.setup(["cynik", "brucoun"], {}, 7)
	check(cyn.anticip_thr > p.anticip_thr, "cynik má vyšší práh těšení než optimista", "%.2f vs %.2f" % [cyn.anticip_thr, p.anticip_thr])
	check(p.anticipation_after_threshold(10.0, 0.0, 20.0) > cyn.anticipation_after_threshold(10.0, 0.0, 20.0),
		"stejná očekávaná radost táhne optimistu víc")
	check(p.anticipation_after_threshold(10.0, 0.8, 90.0) < p.anticipation_after_threshold(10.0, 0.0, 20.0),
		"pesimismus a stres práh zvedají")
	check(p.anticipation_after_threshold(10.0, 0.9, 100.0) > 0.0, "ani v depresi nic neklesne na nulu (žádný zákaz)")


func _test_mental_limits() -> void:
	section("Stres, alkohol, ataky")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var m := MentalState.new(rng, "f")
	m.stress = 60.0
	m.on_stressor("argue", 10.0)
	var low_gain := m.stress - 60.0
	m.stress = 92.0
	m.on_stressor("argue", 10.0)
	check(m.stress - 92.0 < low_gain * 0.5, "měkký strop: nad 70 se stres přidává jen částečně", "%.1f vs %.1f" % [m.stress - 92.0, low_gain])
	var d := MentalState.new(rng, "m")
	d.arousal = 70.0
	d.stress = 70.0
	var r1: Dictionary = d.apply_coping("drink", 1.0, {"now": 1000.0, "energy": 70.0, "hunger": 70.0, "day": 1})
	d.arousal = 70.0
	d.apply_coping("drink", 1.0, {"now": 1030.0, "energy": 70.0, "hunger": 70.0, "day": 1})
	d.arousal = 70.0
	var r3: Dictionary = d.apply_coping("drink", 1.0, {"now": 1060.0, "energy": 70.0, "hunger": 70.0, "day": 1})
	check(absf(float(r3["arousal"])) < absf(float(r1["arousal"])) * 0.6, "třetí pivo uleví mnohem méně než první",
		"%.1f → %.1f" % [-float(r1["arousal"]), -float(r3["arousal"])])
	check(d.coping_appeal("drink", 70.0, 70.0, 1070.0) < d.coping_appeal("drink", 70.0, 70.0, 1070.0 + MentalState.DRINK_WINDOW) * 0.5,
		"po několika dávkách pití láká méně, za den zase víc")
	var q := MentalState.new(rng, "f")
	q.conditions = {"anxiety": 0.9}
	q._now = 0.0
	var cds: Array = []
	for i in 4:
		q._now = float(i) * 400.0
		q._start_panic()
		q.end_panic()
		cds.append(q.panic_cooldown)
	check(cds[0] < cds[3] and cds[3] <= MentalState.PANIC_COOLDOWN_MAX, "opakované ataky prodlužují refrakterní dobu (6 → 24 h)", str(cds))
	check(q.panic_exhaust > 0.0, "po atace vyčerpání (nižší aktivace)")
	var calm := MentalState.new(rng, "m")
	calm.arousal = 10.0
	for i in 100:
		calm.tick(60.0, {"energy": 70.0, "hunger": 70.0, "needs": {}, "now": float(i) * 60.0, "cfg": {}})
	check(calm.surge_count == 0, "bez úzkostné predispozice žádné vlny úzkosti z čista jasna")
	var anx := MentalState.new(rng, "f")
	anx.conditions = {"anxiety": 0.9}
	for i in 30 * 24:
		anx.tick(60.0, {"energy": 70.0, "hunger": 70.0, "needs": {}, "now": float(i) * 60.0, "cfg": {}})
	check(anx.surge_count >= 1 and anx.surge_count <= 12, "těžká úzkost: pár vln za měsíc (ne každý den)", "%d" % anx.surge_count)
	var off := MentalState.new(rng, "f")
	off.conditions = {"anxiety": 0.9}
	for i in 30 * 24:
		off.tick(60.0, {"energy": 70.0, "hunger": 70.0, "needs": {}, "now": float(i) * 60.0, "cfg": {"conditions": false}})
	check(off.surge_count == 0 and off.panic_count == 0, "vypnutá témata → žádné vlny ani ataky")
	var sf := {}
	for a in ActionLibrary.ACTIONS:
		if a["id"] == "sleep_floor":
			sf = a
	check(not sf.is_empty() and String(sf.get("object", "x")) == "" and (sf.get("tags", []) as Array).has("sleep"),
		"nouzový spánek bez objektu existuje (plná domácnost)")


func _test_noise_rules() -> void:
	section("Hluk: jednou za cooldown na spáče")
	var hd := HouseholdDynamics.new()
	# can_friction a friction_weight pracují jen se jmény – stačí uzly se sim_name.
	var a := _fake("A")
	var b := _fake("B")
	var c := _fake("C")
	check(hd.can_friction(a, b, "noise", 0.0), "první hluk může naštvat")
	hd._last_friction["A>*>noise"] = 0.0
	check(not hd.can_friction(a, c, "noise", 60.0), "další zdroj hluku do cooldownu už ne (jeden spáč, mnoho zdrojů)")
	check(hd.can_friction(a, c, "noise", HouseholdDynamics.FRICTION_COOLDOWN["noise"] + 1.0), "po cooldownu zase ano")
	check(hd.friction_weight(a, 0.0) == 1.0, "první třenice dne má plnou váhu")
	hd._friction_day["A"] = [0, 5]
	check(hd.friction_weight(a, 100.0) < 0.3, "po pár třenicích za den to postava začne přecházet")
	check(hd.friction_weight(a, 1440.0 + 10.0) == 1.0, "nový den, nová trpělivost")
	for n in [a, b, c]:
		n.free()


func _fake(n: String) -> Node:
	var x := Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar sim_name := \"%s\"\n" % n
	sc.reload()
	x.set_script(sc)
	return x


# ---------------------------------------------------------------- dlouhý běh

func _make_world(file: String, seed_offset: int) -> Node3D:
	clock.total_minutes = 8.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/%s.json" % file))
	Main.household_override = parsed if typeof(parsed) == TYPE_ARRAY else []
	var w := Node3D.new()
	w.set_script(Main)
	w._seed_offset = seed_offset
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(w)
	return w


func _test_long(file: String, healthy: bool) -> void:
	section("Dlouhý běh: %s – 7 postav × %d seedy × %d dní" % [file, SEEDS, DAYS])
	for sd in SEEDS:
		var w := _make_world(file, 100 + sd)
		check(w.sims.size() == 7, "%s seed %d: 7 postav" % [file, sd], "%d" % w.sims.size())
		var sat := {}
		var lowavg := {}
		var hi := {}
		for s in w.sims:
			sat[s.sim_name] = 0
			lowavg[s.sim_name] = 0
			hi[s.sim_name] = 0
		for m in DAYS * 720:
			clock.advance(2.0)
			if m % 30 == 0:
				for s in w.sims:
					if s.mental.dep.burden >= 0.95:
						sat[s.sim_name] += 1
					if s.needs.average() < 20.0:
						lowavg[s.sim_name] += 1
					if s.mental.stress > 85.0:
						hi[s.sim_name] += 1
		var samples := DAYS * 24
		var rate: float = w.dynamics.argue_rate()
		var summary := PackedStringArray()
		var worst_hi := 0.0
		var collapsed := 0
		var drinks := 0
		var max_sat := 0.0
		for s in w.sims:
			var hf := float(hi[s.sim_name]) / samples
			worst_hi = maxf(worst_hi, hf)
			max_sat = maxf(max_sat, float(sat[s.sim_name]) / samples)
			drinks = maxi(drinks, int(s.mental.coping_counts.get("drink", 0)))
			if float(lowavg[s.sim_name]) / samples > 0.1:
				collapsed += 1
			summary.append("%s n%+.0f st%.0f B%.2f p%d" % [s.sim_name.split(" ")[0], s.mood.value, s.mental.stress, s.mental.dep.burden, s.mental.panic_count])
		print("  seed %d: hádky %.0f %%, %s" % [sd, rate * 100.0, " | ".join(summary)])
		check(rate >= 0.10 and rate <= 0.40, "%s seed %d: hádky 10–40 %% i v plném domě" % [file, sd], "%.0f %%" % (rate * 100.0))
		check(collapsed == 0, "%s seed %d: nikdo nemá potřeby trvale pod 20 (smyčka spánek/hlad)" % [file, sd], "%d" % collapsed)
		check(max_sat < 0.25, "%s seed %d: deprese nezamrzne na maximu" % [file, sd], "%.0f %% času" % (max_sat * 100.0))
		check(drinks <= DAYS * 2, "%s seed %d: pití nejvýš 2× za den" % [file, sd], "%d×" % drinks)
		if healthy:
			check(worst_hi < 0.15, "%s seed %d: zdraví nejsou dlouho v extrémním stresu" % [file, sd], "%.0f %%" % (worst_hi * 100.0))
		w.queue_free()
		await get_tree().process_frame
