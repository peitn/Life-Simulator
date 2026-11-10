extends "res://tests/test_base.gd"
## Most ekonomika -> psychika (scripts/sim/economy_bridge.gd, HouseholdDynamics._economy_day, GameSave, lab_runner):
## výchozí vypnuto = beze změny (hash z kódu PŘED mostem), zapnuto = determinismus, krach zvedá stres víc než klid,
## uložení/načtení se zapnutým mostem (i staré savy), finanční tíseň nevyvolá žádnou akci, mapování je ohraničené a konečné.
const Bridge := preload("res://scripts/sim/economy_bridge.gd")
const Runner := preload("res://tools/lab/lab_runner.gd")
const Main := preload("res://main.gd")
const SaveGame := preload("res://scripts/save/game_save.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

## final_hash běhu {"name":"h","seed":7,"days":3,"snapshot_hours":24} spuštěného na kódu PŘED mostem (commit a544f5d).
const BASELINE_HASH_SEED7_3D := "dc75b1e9850540442b867e7d73c7e28f21036c037526dff16019ae826cee1a8f"
const NAMES3 := ["Jana Nováková", "Petr Dvořák", "Eliška Malá"]
const CRASH := [{"type": "path", "day": 1, "days": 2, "total_pm": -400, "scope": "market"}]

var clock: Node


func _ready() -> void:
	watchdog_seconds = 420.0
	clock = get_node("/root/GameClock")
	_run.call_deferred()


func _run() -> void:
	_unit_config()
	_unit_bounds()
	_unit_crash_vs_calm()
	_unit_persistence()
	_unit_no_actions()
	await _lab_runs()
	await _world_wiring()
	await _world_save()
	finish("test_economy_bridge")


func _fx_total(b: RefCounted, names: Array, days: int) -> float:
	var s := 0.0
	b.step_day(1, names)
	for d in range(2, 2 + days):
		var fx: Dictionary = b.step_day(d, names)
		for k in fx:
			s += float(fx[k]["stress"])
	return s


## Kanonický JSON: celá čísla zapsaná jako float se normalizují (stejně jako při načtení), plná přesnost.
func _canon(d: Dictionary) -> String:
	return JSON.stringify(Bridge.Economy._norm(d), "", true, true)


func check_keys_equal(a: Dictionary, b: Dictionary) -> void:
	if a.keys() != b.keys():
		check(false, "stejní agenti dostávají vstupy po obnově z JSONu", str(a.keys()) + " vs " + str(b.keys()))


func _unit_config() -> void:
	section("Konfigurace a validace")
	check(Bridge.validate_config({}).is_empty(), "prázdná konfigurace je platná")
	check(Bridge.validate_config(Bridge.default_config()).is_empty(), "výchozí BALANCE je platná")
	check(Bridge.validate_config({"nesmysl": 1}).size() == 1, "neznámý klíč")
	check(Bridge.validate_config({"pressure_floor": 1.5}).size() == 1, "práh mimo rozsah")
	check(Bridge.validate_config({"acute_gain": NAN}).size() == 1, "NaN je neplatné")
	check(Bridge.validate_config({"mood_per_pressure": 3.0}).size() == 1, "kladná síla moodletu je neplatná (most nálady jen snižuje)")
	check(Bridge.validate_config({"market": "ano"}).size() == 1, "market musí být bool")
	check(Bridge.validate_config({"events": [{"type": "x"}]}).size() == 1, "neplatná událost burzy")
	check(Bridge.validate_config({"events": CRASH, "market": true, "seed": 5}).is_empty(), "platný krach")
	var d: Dictionary = Bridge.default_config()
	check(int(d["economy"]["illegal_share_bp"]) == 0, "výchozí ekonomika mostu nemá agenty s (abstraktní) nelegální prací")
	var b: RefCounted = Bridge.new({})
	check(b.last_day == -1 and b.step_day(5, NAMES3).is_empty() and b.last_day == 5, "první volání jen ukotví den, nic nevrací")
	check(b.step_day(5, NAMES3).is_empty(), "stejný den podruhé: nic")
	check(b.step_day(4, NAMES3).is_empty(), "den zpět: nic")


func _unit_bounds() -> void:
	section("Ohraničenost a konečnost mapování")
	var names8: Array = []
	for i in 8:
		names8.append("A%d" % i)
	var cfgs := [
		{"seed": 3, "market": true, "events": CRASH},
		{"seed": 4, "market": true, "events": CRASH, "chronic_stress_per_day": 20.0, "acute_gain": 20.0, "acute_stress_per_day": 20.0,
			"acute_impulse": 2.0, "stress_dose_cap": 30.0, "mood_per_pressure": -20.0, "mood_per_worry": -20.0, "mood_cap": -20.0,
			"pressure_floor": 0.0, "economy": {"endowment_min": 0, "endowment_max": 100, "illegal_share_bp": 0}},
	]
	var ok_finite := true
	var ok_range := true
	var ok_keys := true
	var max_stress := 0.0
	var min_mood := 0.0
	var n_fx := 0
	for c in cfgs:
		var b: RefCounted = Bridge.new(c)
		var cap_s: float = float(b.cfg["stress_dose_cap"])
		var cap_m: float = float(b.cfg["mood_cap"])
		b.step_day(1, names8)
		for d in range(2, 92):
			var fx: Dictionary = b.step_day(d, names8)
			for nm in fx:
				n_fx += 1
				var e: Dictionary = fx[nm]
				if e.keys().size() != 3 or not (e.has("stress") and e.has("mood") and e.has("mood_minutes")):
					ok_keys = false
				for k in e:
					if not is_finite(float(e[k])):
						ok_finite = false
				if float(e["stress"]) < 0.0 or float(e["stress"]) > cap_s + 1e-9 or float(e["mood"]) > 0.0 or float(e["mood"]) < cap_m - 1e-9:
					ok_range = false
				max_stress = maxf(max_stress, float(e["stress"]))
				min_mood = minf(min_mood, float(e["mood"]))
			for nm in names8:
				var w: float = float((b.state["sim:" + nm] as Dictionary)["worry"])
				if not is_finite(w) or w < 0.0 or w > float(b.cfg["acute_cap"]) + 1e-9:
					ok_range = false
	check(n_fx > 20, "extrémní konfigurace skutečně produkuje vstupy (%d)" % n_fx)
	check(ok_finite, "všechny vstupy jsou konečné (90 dní, 2 konfigurace, 8 agentů)")
	check(ok_range, "stres v [0, strop dávky], nálada v [strop, 0], starost v [0, acute_cap]")
	check(ok_keys, "vstup má jen klíče stress, mood, mood_minutes (žádná akce, žádný příkaz)", str(max_stress))
	check(max_stress <= 30.0 and min_mood >= -20.0, "i extrémní nastavení zůstává pod tvrdými stropy (%.1f / %.1f)" % [max_stress, min_mood])


func _unit_crash_vs_calm() -> void:
	section("Krach vs klid (samotný most, 20 seedů × 3 jména)")
	var wins := 0
	var ties := 0
	var diffs: Array = []
	for sd in range(1, 21):
		var calm: float = _fx_total(Bridge.new({"seed": sd, "market": true}), NAMES3, 4)
		var crash: float = _fx_total(Bridge.new({"seed": sd, "market": true, "events": CRASH}), NAMES3, 4)
		diffs.append(crash - calm)
		if crash > calm + 1e-9:
			wins += 1
		elif absf(crash - calm) <= 1e-9:
			ties += 1
	var mean_d := 0.0
	var min_d := 1.0e9
	for x in diffs:
		mean_d += float(x) / diffs.size()
		min_d = minf(min_d, float(x))
	check(wins >= 8, "krach zvedl součet stresu v %d z 20 seedů (zbytek: žádná expozice)" % wins)
	check(min_d >= -2.0, "krach nikde nesnížil stres výrazně (min. rozdíl %.2f; drobné rozdíly dělá změna obchodování)" % min_d)
	check(mean_d > 3.0, "průměrný rozdíl krach − klid je kladný a znatelný (%.2f)" % mean_d)
	# Bez burzy žádná akutní složka.
	var b: RefCounted = Bridge.new({"seed": 9, "market": false})
	b.step_day(1, NAMES3)
	var worry := 0.0
	for d in range(2, 40):
		b.step_day(d, NAMES3)
		for nm in NAMES3:
			worry += float((b.state["sim:" + nm] as Dictionary)["worry"])
	check(worry == 0.0, "bez burzy nevzniká starost z portfolia")
	# Doznívání: po krachu starost klesá (poločas), nezůstává navždy.
	var b2: RefCounted = Bridge.new({"seed": 9, "market": true, "events": CRASH})
	b2.step_day(1, NAMES3)
	var peak := 0.0
	var at_end := 0.0
	for d in range(2, 80):
		b2.step_day(d, NAMES3)
		var tot := 0.0
		for nm in NAMES3:
			tot += float((b2.state["sim:" + nm] as Dictionary)["worry"])
		peak = maxf(peak, tot)
		at_end = tot
	check(peak > 0.3 and at_end < peak * 0.35, "starost po krachu vrcholí a doznívá (%.2f -> %.2f)" % [peak, at_end])


func _unit_persistence() -> void:
	section("Uložení a obnova mostu (JSON i binárně)")
	var b: RefCounted = Bridge.new({"seed": 9, "market": true, "events": CRASH})
	b.step_day(1, NAMES3)
	for d in range(2, 14):
		b.step_day(d, NAMES3)
	var d0: Dictionary = b.to_dict()
	var viaj: Variant = JSON.parse_string(JSON.stringify(d0, "", true, true))
	var b2: RefCounted = Bridge.from_dict(viaj)
	var b3: RefCounted = Bridge.from_dict(bytes_to_var(var_to_bytes(d0)))
	check(b2 != null and b3 != null, "obnova z JSONu i z var_to_bytes")
	check(b2.eco.state_hash() == b.eco.state_hash() and b3.eco.state_hash() == b.eco.state_hash(), "stav ekonomiky a burzy se shoduje")
	var fx1 := ""
	var fx3 := ""
	var max_dj := 0.0
	var n_cmp := 0
	for d in range(14, 40):
		var f1: Dictionary = b.step_day(d, NAMES3)
		var f2: Dictionary = b2.step_day(d, NAMES3)
		var f3: Dictionary = b3.step_day(d, NAMES3)
		fx1 += JSON.stringify(f1, "", true, true)
		fx3 += JSON.stringify(f3, "", true, true)
		check_keys_equal(f1, f2)
		for k in f1:
			if f2.has(k):
				max_dj = maxf(max_dj, absf(float(f1[k]["stress"]) - float(f2[k]["stress"])))
				n_cmp += 1
	check(fx1 == fx3 and fx1.length() > 10, "po obnově z var_to_bytes běh pokračuje bit-identicky (26 dní)")
	check(n_cmp > 10 and max_dj < 1e-9, "po obnově z JSON textu (text float v Godotu není bit-přesný) běh pokračuje shodně do 1e-9 (%s)" % str(max_dj))
	check(_canon(b.to_dict()) == _canon(b3.to_dict()), "konečný stav po binární obnově je bit-identický (po normalizaci 2.0 -> 2)")
	check(Bridge.from_dict(null) == null and Bridge.from_dict({}) == null, "neplatná sekce → null")
	var bad: Dictionary = d0.duplicate(true)
	bad["cfg"]["pressure_floor"] = 7.0
	check(Bridge.from_dict(bad) == null, "podvržená konfigurace → null")
	var bad2: Dictionary = d0.duplicate(true)
	bad2["names"] = "x"
	check(Bridge.from_dict(bad2) == null, "špatný typ names → null")


func _unit_no_actions() -> void:
	section("Finanční tíseň nevybírá ani nevynucuje žádnou akci")
	var src := FileAccess.get_file_as_string("res://scripts/sim/economy_bridge.gd")
	var code := ""
	for line in src.split("\n"):
		var l := String(line)
		var h := l.find("#")
		code += (l if h < 0 else l.substr(0, h)) + "\n"
	var bad_tokens := ["command(", "current_action", "ActionLibrary", "queue", "gamble", "steal", "attack", "fight", "weapon", "kill", "self_harm", "set_target"]
	var found: Array = []
	for t in bad_tokens:
		if code.find(t) >= 0:
			found.append(t)
	check(found.is_empty(), "kód mostu nezná žádnou akci ani příkaz", str(found))
	var hd := FileAccess.get_file_as_string("res://scripts/sim/household_dynamics.gd")
	var i0 := hd.find("func _economy_day")
	var i1 := hd.find("\nfunc ", i0 + 10)
	var body := hd.substr(i0, i1 - i0)
	check(body.find("command(") < 0 and body.find("current_action") < 0 and body.find(".act(") < 0 and body.find("queue") < 0, "aplikace vstupů nevolá žádný příkaz ani akci")
	check(body.find("on_stressor(\"life\"") > 0 and body.find("add_moodlet") > 0, "aplikace jde jen přes mental.on_stressor a moodlet")
	var forbidden := ["illegal", "crime", "violence", "weapon", "steal", "self_harm"]
	var lib_bad := 0
	for a in ActionLibrary.ACTIONS:
		for t in a.get("tags", []):
			if forbidden.has(String(t)):
				lib_bad += 1
	check(lib_bad == 0, "knihovna akcí neobsahuje žádnou nelegální/násilnou akci, kterou by tíseň mohla odemknout")


func _lab_runs() -> void:
	section("Laboratoř: validace scénáře a běhy")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "seed": 3, "shock": {"day": 1, "total_pm": -300, "days": 3}}}).is_empty(), "platný blok economy")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": false}}).is_empty(), "economy.enabled=false je platné")
	check(Runner.validate({"seed": 1, "days": 4, "economy": 5}).size() == 1, "economy musí být objekt")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": 1}}).size() == 1, "enabled musí být bool")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "x": 1}}).size() == 1, "neznámý klíč")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "shock": {"day": 1, "total_pm": -300, "days": 3}}}).size() >= 1, "shock vyžaduje market")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "shock": {"day": 9, "total_pm": -300, "days": 3}}}).size() == 1, "shock.day mimo 1..days")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "shock": {"day": 1, "total_pm": 300, "days": 3}}}).size() == 1, "shock.total_pm musí být záporný (krach)")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "shock": {"day": 1, "total_pm": -1000, "days": 3}}}).size() == 1, "shock.total_pm > -1000")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "shock": {"day": 1, "total_pm": -300, "days": 99}}}).size() == 1, "shock.days 1..30")
	check(Runner.validate({"seed": 1, "days": 4, "economy": {"enabled": true, "market": true, "seed": 1.5}}).size() == 1, "economy.seed celé číslo")
	var bad: Dictionary = await Runner.run(self, {"seed": 1, "days": 4, "economy": {"enabled": "ano"}})
	check(not bad["ok"], "neplatný blok economy se nespustí")

	section("Vypnuto = beze změny (hash z kódu před mostem)")
	var sc := {"name": "h", "seed": 7, "days": 3, "snapshot_hours": 24}
	var off: Dictionary = await Runner.run(self, sc)
	check(off["ok"] and off["final_hash"] == BASELINE_HASH_SEED7_3D, "bez bloku economy je final_hash shodný se základem", String(off.get("final_hash", "")))
	var sc2: Dictionary = sc.duplicate(true)
	sc2["economy"] = {"enabled": false, "market": true, "seed": 5}
	var off2: Dictionary = await Runner.run(self, sc2)
	check(off2["ok"] and off2["final_hash"] == BASELINE_HASH_SEED7_3D, "economy.enabled=false: shodný hash")
	check(JSON.stringify(off["snapshots"]) == JSON.stringify(off2["snapshots"]) and not off2.has("economy"), "vypnuto: shodné snímky a ve výsledku není sekce economy")
	check(not (off["snapshots"][1]["agents"].values()[0] as Dictionary).has("economy"), "vypnuto: snímky nemají klíč economy")

	section("Zapnuto: determinismus a krach vs klid ve světě")
	var calm_sc := {"name": "e", "seed": 9, "days": 4, "snapshot_hours": 24, "economy": {"enabled": true, "market": true}}
	var crash_sc := {"name": "e", "seed": 9, "days": 4, "snapshot_hours": 24,
		"economy": {"enabled": true, "market": true, "shock": {"day": 1, "total_pm": -400, "days": 2}}}
	var c1: Dictionary = await Runner.run(self, calm_sc)
	var c2: Dictionary = await Runner.run(self, calm_sc)
	var k1: Dictionary = await Runner.run(self, crash_sc)
	check(c1["ok"] and c2["ok"] and k1["ok"], "tři běhy proběhly")
	check(c1["final_hash"] == c2["final_hash"] and JSON.stringify(c1["snapshots"]) == JSON.stringify(c2["snapshots"]), "zapnuto: stejný seed → shodný hash i snímky")
	var h9: Dictionary = await Runner.run(self, {"name": "e", "seed": 9, "days": 4, "snapshot_hours": 24})
	check(h9["ok"] and c1["final_hash"] != h9["final_hash"], "zapnuto se běh liší od vypnutého")
	check((c1["snapshots"][1]["agents"].values()[0] as Dictionary).has("economy"), "zapnuto: snímky nesou pressure/worry/portfolio")
	var s_calm: float = float(c1["economy"]["stats"]["stress_sum"])
	var s_crash: float = float(k1["economy"]["stats"]["stress_sum"])
	check(s_crash > s_calm + 3.0, "krach dodal víc stresových vstupů než klid (%.2f vs %.2f)" % [s_crash, s_calm])
	check(float(k1["summary"]["mean_stress_post"]) > 0.0 and float(k1["economy"]["stats"]["mood_min"]) <= 0.0, "souhrn počítá stres po šoku")


## Drát: HouseholdDynamics._economy_day aplikuje vstupy mostu jen přes mental.on_stressor a moodlet.
class StubBridge:
	extends RefCounted
	var fx: Dictionary = {}
	var calls: Array = []
	func step_day(day: int, names: Array) -> Dictionary:
		calls.append([day, names.duplicate()])
		return fx


func _new_world(cfg_extra: Dictionary) -> Node:
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "EcoBridgeWorld"
	var cfg := {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"save_directory": "user://test-lifesim-ecobridge-" + str(OS.get_process_id()), "autoload": false, "autosave": false, "clock": clock}
	for k in cfg_extra:
		cfg[k] = cfg_extra[k]
	w.net_config = cfg
	add_child(w)
	return w


func _reset_clock() -> void:
	clock.running = false
	clock.total_minutes = 480.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()


func _world_wiring() -> void:
	section("Drát ve světě: přepínač net_config a aplikace vstupů")
	var gs := get_node_or_null("/root/GameSettings")
	var persist_before = gs.persist if gs != null else null
	if gs != null:
		gs.persist = false
	_reset_clock()
	var w0: Node = _new_world({})
	await get_tree().process_frame
	check(w0.dynamics.economy_bridge == null, "výchozí hra: most vypnutý")
	w0.free()
	await get_tree().process_frame
	_reset_clock()
	var wbad: Node = _new_world({"economy_psyche": {"pressure_floor": 9.0}})
	await get_tree().process_frame
	check(wbad.dynamics.economy_bridge == null, "neplatná konfigurace: most zůstane vypnutý")
	wbad.free()
	await get_tree().process_frame
	_reset_clock()
	var w: Node = _new_world({"economy_psyche": true})
	await get_tree().process_frame
	check(w.dynamics.economy_bridge != null, "net_config.economy_psyche=true zapne most")
	var stub := StubBridge.new()
	w.dynamics.economy_bridge = stub
	var s0 = w.sims[0]
	var s1 = w.sims[1]
	s0.mental.stress = 10.0
	s1.mental.stress = 10.0
	stub.fx = {String(s0.sim_name): {"stress": 5.0, "mood": -4.0, "mood_minutes": 600.0}}
	var before_s: float = s0.mental.stress
	var src_before: float = float(s0.mental.stress_sources.get("life", 0.0))
	w.dynamics._economy_day(w.sims, 3)
	check(stub.calls.size() == 1 and int(stub.calls[0][0]) == 3 and stub.calls[0][1].size() == w.sims.size(), "most dostane den a jména všech živých postav")
	check(s0.mental.stress > before_s + 1.0 and s0.mental.stress <= before_s + 5.0 + 1e-6, "příjemce dostane stres přes on_stressor (%.2f -> %.2f)" % [before_s, s0.mental.stress])
	check(float(s0.mental.stress_sources.get("life", 0.0)) > src_before, "zdroj stresu je existující druh \"life\"")
	check(s0.mood.has_moodlet("financni_starost"), "příjemce dostane moodlet")
	check(absf(s1.mental.stress - 10.0) < 1e-9 and not s1.mood.has_moodlet("financni_starost"), "postava bez vstupu zůstane beze změny")
	var rem := 1.0e9
	for m in s0.mood.moodlets:
		if m["id"] == "financni_starost":
			rem = float(m["remaining"])
	check(rem <= 600.0 and float(s0.mood.moodlets.filter(func(m): return m["id"] == "financni_starost")[0]["strength"]) == -4.0, "moodlet má omezené trvání (%.0f min) a danou sílu" % rem)
	stub.fx = {}
	w.dynamics._economy_day(w.sims, 4)
	w.free()
	await get_tree().process_frame
	# Skutečný most v živé domácnosti: pár dnů, nic nespadne, hodnoty konečné, akce jen z knihovny.
	_reset_clock()
	var wl: Node = _new_world({"economy_psyche": {"seed": 9, "market": true, "events": CRASH,
		"economy": {"endowment_min": 0, "endowment_max": 100, "illegal_share_bp": 0}}})
	await get_tree().process_frame
	check(wl.dynamics.economy_bridge != null, "živý svět s extrémně chudou ekonomikou")
	var seen := {}
	var finite := true
	for i in 3 * 24 * 6:
		clock.advance(10.0)
		for s in wl.sims:
			if not s.current_action.is_empty():
				seen[String(s.current_action.get("id", ""))] = true
	for s in wl.sims:
		finite = finite and is_finite(s.mental.stress) and is_finite(s.get_mood_value())
	var known := true
	for id in seen:
		if id != "" and ActionLibrary.get_action(id).is_empty():
			known = false
	check(finite and wl.dynamics.economy_bridge.stats["days"] >= 2, "3 dny v extrémní chudobě: stres i nálada konečné, most běžel (%d dní)" % int(wl.dynamics.economy_bridge.stats["days"]))
	check(known and seen.size() > 2, "pozorované akce (%d druhů) jsou jen z existující knihovny" % seen.size())
	wl.free()
	await get_tree().process_frame
	if gs != null:
		gs.persist = persist_before


func _world_save() -> void:
	section("GameSave se zapnutým mostem")
	var gs := get_node_or_null("/root/GameSettings")
	var persist_before = gs.persist if gs != null else null
	if gs != null:
		gs.persist = false
	_reset_clock()
	var w: Node = _new_world({"economy_psyche": {"seed": 9, "market": true, "events": CRASH}})
	await get_tree().process_frame
	for i in 3 * 24 * 6:
		clock.advance(10.0)
	var cap: Dictionary = SaveGame.capture(w)
	check(cap["ok"] and cap["data"].has("economy"), "uložená hra má sekci economy, když je most zapnutý")
	check(SaveGame.validate_data(cap["data"], w).get("ok", false), "uložená data projdou validací")
	var before := _canon(w.dynamics.economy_bridge.to_dict())
	var applied: Dictionary = SaveGame.apply(w, cap["data"])
	await get_tree().process_frame
	check(applied.get("ok", false) and w.dynamics.economy_bridge != null, "načtení hry obnoví most")
	check(_canon(w.dynamics.economy_bridge.to_dict()) == before, "stav mostu po načtení je bit-identický")
	var bytes: PackedByteArray = var_to_bytes(cap["data"])
	var applied_b: Dictionary = SaveGame.apply(w, bytes_to_var(bytes))
	await get_tree().process_frame
	check(applied_b.get("ok", false) and _canon(w.dynamics.economy_bridge.to_dict()) == before, "i přes binární snímek (formát souboru)")
	# Starý save bez sekce, ale přepínač zapnutý: čerstvý most se stejnou konfigurací.
	var legacy: Dictionary = cap["data"].duplicate(true)
	legacy.erase("economy")
	var applied2: Dictionary = SaveGame.apply(w, legacy)
	await get_tree().process_frame
	check(applied2.get("ok", false) and w.dynamics.economy_bridge != null and w.dynamics.economy_bridge.last_day == -1, "starý save bez sekce se načte (čerstvý most, stejná konfigurace)")
	var corrupt: Dictionary = cap["data"].duplicate(true)
	corrupt["economy"] = {"version": "x"}
	var applied3: Dictionary = SaveGame.apply(w, corrupt)
	await get_tree().process_frame
	check(applied3.get("ok", false) and w.dynamics.economy_bridge != null, "poškozená sekce economy se ignoruje (hra se načte)")
	w.free()
	await get_tree().process_frame
	# Vypnuto: formát uložené hry beze změny.
	_reset_clock()
	var w2: Node = _new_world({})
	await get_tree().process_frame
	var cap2: Dictionary = SaveGame.capture(w2)
	check(cap2["ok"] and not cap2["data"].has("economy"), "vypnuto: uložená hra nemá žádnou novou sekci")
	var keys: Array = cap2["data"].keys()
	keys.sort()
	check(keys == ["clock", "dynamics", "gossip", "objects", "selected", "sims", "version"], "vypnuto: stejné klíče nejvyšší úrovně jako dřív", str(keys))
	var applied4: Dictionary = SaveGame.apply(w2, cap2["data"])
	await get_tree().process_frame
	check(applied4.get("ok", false) and w2.dynamics.economy_bridge == null, "vypnuto: načtení nezapne most")
	w2.free()
	await get_tree().process_frame
	if gs != null:
		gs.persist = persist_before
