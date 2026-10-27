extends "res://tests/test_base.gd"
## Zátěžová matice domácnosti (běh 23, kritéria Groka v místnosti #157 a akceptace z #154):
## 4 / 6 / 8 postav × několik seedů × 30 dní (s mezisnímkem po 14 dnech). Pro každý běh měří hádky, stres,
## saturaci deprese, potřeby, pití, ataky a rozložení vztahů; vypíše průměr ± směrodatnou odchylku po velikostech
## a uloží report do res://previews/testlogs/household_matrix.json. Navíc determinismus: stejný seed → stejný stav.
## Pomalý test (~10–15 min na serveru): spouští se na pozadí (previews/testlogs/bg.sh), ne v rychlé regresi.
## Volby za „--“: --sizes 4,6,8  --seeds 4  --days 30  (zkrácený běh např. --sizes 4 --seeds 1 --days 3).

const Main := preload("res://main.gd")

var SIZES: Array = [4, 6, 8]
var SEEDS := 4
var DAYS := 30
const MID_DAY := 14
const SAMPLE_EVERY := 30          # kroků po 2 min → vzorek každou herní hodinu

var clock: Node
var gs: Node
var pool: Array = []
var report := {"runs": [], "sizes": {}}


func _ready() -> void:
	watchdog_seconds = 3600.0
	_parse_args()
	clock = get_node("/root/GameClock")
	clock.running = false
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	for f in ["household_stress7", "household_extra"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/%s.json" % f))
		if typeof(parsed) == TYPE_ARRAY:
			pool.append_array(parsed)
	_run.call_deferred()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--sizes")
	if i >= 0 and i + 1 < a.size():
		SIZES = []
		for s in a[i + 1].split(","):
			if s.is_valid_int():
				SIZES.append(clampi(int(s), 2, 8))
	i = a.find("--seeds")
	if i >= 0 and i + 1 < a.size() and a[i + 1].is_valid_int():
		SEEDS = clampi(int(a[i + 1]), 1, 16)
	i = a.find("--days")
	if i >= 0 and i + 1 < a.size() and a[i + 1].is_valid_int():
		DAYS = clampi(int(a[i + 1]), 1, 60)


func _run() -> void:
	check(pool.size() >= 8, "pool 8 testovacích postav (stress7 + extra)", "%d" % pool.size())
	await _test_determinism()
	for n in SIZES:
		var runs: Array = []
		for sd in SEEDS:
			runs.append(await _run_one(n, sd))
		_aggregate(n, runs)
	_tomas_summary()
	var f := FileAccess.open("res://previews/testlogs/household_matrix.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, " "))
		f.close()
	Main.household_override = []
	finish("test_household_matrix")


func _make_world(n: int, seed_offset: int) -> Node3D:
	clock.total_minutes = 8.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = pool.slice(0, n)
	var w := Node3D.new()
	w.set_script(Main)
	w._seed_offset = seed_offset
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false}
	add_child(w)
	return w


static func _healthy(entry: Dictionary) -> bool:
	var mind: Dictionary = entry.get("mind", {})
	return (mind.get("predispositions", {}) as Dictionary).is_empty() and (mind.get("traumas", []) as Array).is_empty()


func _fingerprint(w: Node3D) -> String:
	var parts := PackedStringArray()
	for s in w.sims:
		var rel := PackedStringArray()
		var keys: Array = s.relationships.keys()
		keys.sort()
		for k in keys:
			rel.append("%s:%.3f" % [k, float(s.relationships[k])])
		parts.append("%s m%.4f s%.4f b%.4f n%.4f p%d a%s r[%s]" % [s.sim_name, s.mood.value, s.mental.stress,
			s.mental.dep.burden, s.needs.average(), s.mental.panic_count, s.last_action_id, ",".join(rel)])
	parts.append("argue %.5f" % w.dynamics.argue_rate())
	return "\n".join(parts)


func _test_determinism() -> void:
	section("Determinismus: stejný seed → stejný stav (4 postavy × 3 dny, 2×)")
	var fps: Array = []
	for rep in 2:
		var w := _make_world(4, 777)
		for m in 3 * 720:
			clock.advance(2.0)
		fps.append(_fingerprint(w))
		w.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var same: bool = fps[0] == fps[1]
	check(same, "dva běhy se stejným seedem skončí ve stejném stavu", "" if same else _first_diff(fps[0], fps[1]))
	var w2 := _make_world(4, 778)
	for m in 3 * 720:
		clock.advance(2.0)
	check(_fingerprint(w2) != fps[0], "jiný seed → jiný průběh")
	w2.queue_free()
	await get_tree().process_frame


static func _first_diff(a: String, b: String) -> String:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			return "%s ≠ %s" % [la[i].substr(0, 120), lb[i].substr(0, 120)]
	return "délka"


func _run_one(n: int, sd: int) -> Dictionary:
	var w := _make_world(n, 200 + sd)
	var tag := "%d postav, seed %d" % [n, sd]
	section("Matice: %s × %d dní" % [tag, DAYS])
	check(w.sims.size() == n, "%s: počet postav" % tag, "%d" % w.sims.size())
	var st := {}
	var healthy := {}
	for i in w.sims.size():
		var s = w.sims[i]
		healthy[s.sim_name] = _healthy(pool[i])
		st[s.sim_name] = {"hi": 0, "streak": 0, "max_streak": 0, "sat": 0, "low": 0, "mood_sum": 0.0}
	var mid := {}
	var samples := 0
	for m in DAYS * 720:
		clock.advance(2.0)
		if m % SAMPLE_EVERY == 0:
			samples += 1
			for s in w.sims:
				var r: Dictionary = st[s.sim_name]
				if s.mental.stress > 85.0:
					r["hi"] += 1
					r["streak"] += 1
					r["max_streak"] = maxi(r["max_streak"], r["streak"])
				else:
					r["streak"] = 0
				if s.mental.dep.burden >= 0.95:
					r["sat"] += 1
				if s.needs.average() < 20.0:
					r["low"] += 1
				r["mood_sum"] += float(s.mood.value)
		if m == MID_DAY * 720 - 1 and DAYS > MID_DAY:
			mid = {"argue": w.dynamics.argue_rate(), "rel": _rel_stats(w)}
	var argue: float = w.dynamics.argue_rate()
	var unpleasant := unpleasant_rate(w.dynamics.stats)
	var rel := _rel_stats(w)
	var people: Array = []
	var line := PackedStringArray()
	var ok_low := true
	var ok_sat := true
	var ok_drink := true
	var ok_healthy := true
	var ok_streak := true
	var detail := PackedStringArray()
	for s in w.sims:
		var r: Dictionary = st[s.sim_name]
		var drinks := int(s.mental.coping_counts.get("drink", 0))
		var p := {
			"name": s.sim_name, "healthy": healthy[s.sim_name],
			"mood_mean": snappedf(r["mood_sum"] / maxf(1.0, samples), 0.1),
			"stress_hi_frac": snappedf(float(r["hi"]) / samples, 0.001), "stress_hi_max_h": r["max_streak"],
			"dep_sat_frac": snappedf(float(r["sat"]) / samples, 0.001), "dep_episodes": s.mental.dep.episode_count,
			"needs_low_frac": snappedf(float(r["low"]) / samples, 0.001), "panics": s.mental.panic_count,
			"drinks_per_day": snappedf(float(drinks) / DAYS, 0.01),
		}
		people.append(p)
		line.append("%s n%+.0f hi%.0f%%/%dh ep%d p%d d%.1f" % [s.sim_name.split(" ")[0], p["mood_mean"], p["stress_hi_frac"] * 100.0,
			p["stress_hi_max_h"], p["dep_episodes"], p["panics"], p["drinks_per_day"]])
		if p["needs_low_frac"] > 0.1:
			ok_low = false
			detail.append("%s potřeby" % s.sim_name)
		if p["dep_sat_frac"] >= 0.25:
			ok_sat = false
			detail.append("%s saturace" % s.sim_name)
		if p["drinks_per_day"] > 2.0:
			ok_drink = false
			detail.append("%s pití" % s.sim_name)
		if healthy[s.sim_name] and (p["stress_hi_frac"] >= 0.10 or p["stress_hi_max_h"] > 24):
			ok_healthy = false
			detail.append("%s stres" % s.sim_name)
		if p["stress_hi_max_h"] > 72:
			ok_streak = false
			detail.append("%s dlouhý stres" % s.sim_name)
	print("  hádky %.0f %% (nepříjemné rozhovory %.0f %%) | vztahy ⌀%+.0f sd %.0f, ≤−50: %.0f %% | %s" % [argue * 100.0, unpleasant * 100.0, rel["mean"], rel["sd"], rel["neg50"] * 100.0, " | ".join(line)])
	# Kritéria z běhu 23 (#164) vznikla před H5, kdy byl každý nepovedený rozhovor hádkou. Od H5 má rozhovor 4 výsledky
	# (dobrý / hádka / trapné ticho / nedorozumění), takže původní metrice odpovídá podíl NEPŘÍJEMNÝCH rozhovorů – ten drží
	# původní meze 10–45 % (běh) a 15–40 % (průměr velikosti). Skutečné hádky se hlídají zvlášť: nesmí zmizet (≥ 5 %)
	# ani převládnout (≤ 45 %). Jednotlivý běh smí být hádavější (skladba domácnosti: 2 bručouni ze 4).
	check(unpleasant >= 0.10 and unpleasant <= 0.45, "%s: nepříjemné rozhovory 10–45 %%" % tag, "%.0f %%" % (unpleasant * 100.0))
	check(argue >= 0.05 and argue <= 0.45, "%s: skutečné hádky 5–45 %% (konflikt nezmizí ani nepřeváží)" % tag, "%.0f %%" % (argue * 100.0))
	check(ok_low, "%s: nikdo nemá potřeby pod 20 víc než 10 %% času" % tag, ", ".join(detail))
	check(ok_sat, "%s: deprese nikomu nezamrzne na maximu (< 25 %% času)" % tag, ", ".join(detail))
	check(ok_drink, "%s: pití nejvýš 2× denně" % tag, ", ".join(detail))
	check(ok_healthy, "%s: zdraví: stres > 85 pod 10 %% času a nejdéle 24 h v kuse" % tag, ", ".join(detail))
	# Dlouhý těžký stav u postavy s predispozicí je přípustný jako menšinový výsledek (review ChatGPT #164) – hlídá se
	# četnost napříč seedy v _aggregate; u zdravých postav platí přísná mez výše vždy.
	check(rel["neg50"] < 0.5, "%s: žádná univerzální spirála (vztahů ≤ −50 méně než polovina)" % tag, "%.0f %%" % (rel["neg50"] * 100.0))
	check(rel["max"] - rel["min"] >= 15.0, "%s: vztahy se liší podle povah (rozpětí ≥ 15)" % tag, "%.0f–%.0f" % [rel["min"], rel["max"]])
	var run := {"size": n, "seed": sd, "days": DAYS, "argue": snappedf(argue, 0.001), "unpleasant": snappedf(unpleasant, 0.001), "rel": rel, "mid": mid, "people": people,
		"long_severe": not ok_streak}
	report["runs"].append(run)
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return run


## Podíl nepříjemných rozhovorů (hádka + trapné ticho + nedorozumění) ze statistik HouseholdDynamics.
static func unpleasant_rate(stats: Dictionary) -> float:
	var o: Dictionary = stats.get("outcomes", {})
	var bad := float(o.get("argue", 0)) + float(o.get("awkward", 0)) + float(o.get("misunderstanding", 0))
	return bad / maxf(1.0, float(stats.get("talks", 0)))


func _rel_stats(w: Node3D) -> Dictionary:
	var vals: Array = []
	for s in w.sims:
		for k in s.relationships:
			vals.append(float(s.relationships[k]))
	if vals.is_empty():
		return {"mean": 0.0, "sd": 0.0, "min": 0.0, "max": 0.0, "neg50": 0.0}
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var var_ := 0.0
	var neg := 0
	for v in vals:
		var_ += (v - mean) * (v - mean)
		if v <= -50.0:
			neg += 1
	return {"mean": snappedf(mean, 0.1), "sd": snappedf(sqrt(var_ / vals.size()), 0.1), "min": snappedf(vals.min(), 0.1),
		"max": snappedf(vals.max(), 0.1), "neg50": snappedf(float(neg) / vals.size(), 0.001)}


static func _ms(a: Array) -> String:
	if a.is_empty():
		return "–"
	var m := 0.0
	for v in a:
		m += float(v)
	m /= a.size()
	var v2 := 0.0
	for v in a:
		v2 += (float(v) - m) * (float(v) - m)
	return "%.2f ± %.2f" % [m, sqrt(v2 / a.size())]


func _aggregate(n: int, runs: Array) -> void:
	var argue: Array = []
	var mood_h: Array = []
	var mood_p: Array = []
	var hi_p: Array = []
	var rel_mean: Array = []
	for r in runs:
		argue.append(r["argue"])
		rel_mean.append(r["rel"]["mean"])
		for p in r["people"]:
			if p["healthy"]:
				mood_h.append(p["mood_mean"])
			else:
				mood_p.append(p["mood_mean"])
				hi_p.append(p["stress_hi_frac"])
	var agg := {"argue": _ms(argue), "mood_healthy": _ms(mood_h), "mood_predisposed": _ms(mood_p),
		"stress_hi_predisposed": _ms(hi_p), "relationship_mean": _ms(rel_mean)}
	var long_runs := 0
	var argue_mean := 0.0
	var unpleasant_mean := 0.0
	for r in runs:
		argue_mean += float(r["argue"]) / runs.size()
		unpleasant_mean += float(r.get("unpleasant", r["argue"])) / runs.size()
		if bool(r.get("long_severe", false)):
			long_runs += 1
	agg["long_severe_runs"] = long_runs
	report["sizes"][str(n)] = agg
	agg["unpleasant_mean"] = snappedf(unpleasant_mean, 0.001)
	check(unpleasant_mean >= 0.15 and unpleasant_mean <= 0.40, "%d postav: průměr nepříjemných rozhovorů přes seedy 15–40 %%" % n,
		"%.0f %% (z toho skutečné hádky %.0f %%)" % [unpleasant_mean * 100.0, argue_mean * 100.0])
	check(long_runs <= ceili(runs.size() * 0.25), "%d postav: stres > 85 déle než 72 h v kuse nanejvýš v ~čtvrtině běhů (menšinový těžký průběh)" % n,
		"%d z %d" % [long_runs, runs.size()])
	print("\n  SOUHRN %d postav (%d seedů): hádky %s | nálada zdraví %s, s predispozicí %s | stres>85 (predisp.) %s | vztahy ⌀ %s" % [
		n, runs.size(), agg["argue"], agg["mood_healthy"], agg["mood_predisposed"], agg["stress_hi_predisposed"], agg["relationship_mean"]])


## Otázka z #161: má těžká predispozice k depresi (Tomáš, 0,95 + 2 traumata) realistický počet epizod?
func _tomas_summary() -> void:
	section("Těžká predispozice k depresi (Tomáš) napříč běhy")
	var eps: Array = []
	for r in report["runs"]:
		for p in r["people"]:
			if String(p["name"]).begins_with("Tomáš"):
				eps.append(p["dep_episodes"])
	var with_ep := 0
	for e in eps:
		if int(e) > 0:
			with_ep += 1
	report["tomas_episodes"] = eps
	print("  epizody v jednotlivých bězích: %s → aspoň jedna epizoda v %d z %d běhů" % [str(eps), with_ep, eps.size()])
	check(not eps.is_empty(), "Tomáš je ve všech velikostech domácnosti (4+)")
