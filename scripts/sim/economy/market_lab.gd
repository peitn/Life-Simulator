extends RefCounted
## Spouštěč scénářů fiktivní burzy (laboratoř): kohorty agentů po investorských profilech × scénář × seed -> metriky.
## Vše jsou mechanismové experimenty nad vymyšlenými daty (game_balance); výsledky NEPLATÍ pro reálné trhy ani lidi.
##
## Návrh: pro každý profil stejný počet agentů se stejným jměním, povoláním a bydlením (kohorty se liší jen chováním).
## Seed ekonomiky řídí i tržní náhodu: scénáře téhož seedu sdílejí stejný šum cen (společné náhodné veličiny),
## takže rozdíly proti scénáři "baseline" jsou párové a způsobuje je jen šok (+ zpětná vazba obchodů).

const Economy := preload("res://scripts/sim/economy/economy.gd")
const MCat := preload("res://scripts/sim/economy/market_catalog.gd")
const StockMarket := preload("res://scripts/sim/economy/stock_market.gd")
const SCENARIO_PATH := "res://scripts/sim/economy/market_scenarios.json"
const ENDOWMENTS := [30000, 45000, 60000, 80000, 120000, 50000]
const JOBS := ["clerk", "craftsman", "cleaner", "engineer", "courier", "shop_assistant"]
const TIERS := ["flat", "shared", "house", "flat", "shared", "flat"]


static func load_scenarios(path: String = SCENARIO_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot_open", "scenarios": []}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("scenarios"):
		return {"ok": false, "error": "bad_json", "scenarios": []}
	var d: Dictionary = StockMarket._norm(parsed)
	var ids: Dictionary = {}
	for s in d["scenarios"]:
		var sd: Dictionary = s
		if not sd.has("id") or ids.has(String(sd["id"])):
			return {"ok": false, "error": "bad_or_duplicate_id", "scenarios": []}
		ids[String(sd["id"])] = true
		var err: String = StockMarket.validate_events(sd.get("events", []))
		if err != "":
			return {"ok": false, "error": String(sd["id"]) + ": " + err, "scenarios": []}
	d["ok"] = true
	d["error"] = ""
	return d


static func scenario_by_id(d: Dictionary, sid: String) -> Dictionary:
	for s in d["scenarios"]:
		if String((s as Dictionary)["id"]) == sid:
			return s
	return {}


static func _gini(values: Array) -> int:
	var xs: Array = []
	var lo: int = 0
	for v in values:
		lo = mini(lo, int(v))
	for v in values:
		xs.append(int(v) - lo)     # Gini je definováno pro nezáporná čísla: posun o minimum (u kladného majetku je posun 0)
	return Economy.gini_pm(xs)


static func _snapshot(eco: RefCounted, ids: Array) -> Dictionary:
	var out: Dictionary = {}
	var m: RefCounted = eco.market
	for id in ids:
		var sid: String = String(id)
		out[sid] = {"pressure": int(eco.pressure_pm(sid)), "pressure_mtm": int(m.pressure_mtm_pm(sid)), "pov": 1 if eco.in_poverty(sid) else 0,
			"pov_mtm": 1 if m.in_poverty_mtm(sid) else 0, "debt": 1 if int(eco.total_debt(sid)) > 0 else 0,
			"wealth": int(m.net_wealth_mtm(sid)), "cash": int(eco.balance(sid)), "pv": int(m.portfolio_value(sid)),
			"employed": 1 if String(eco.legal_job_of(sid)) != "" else 0}
	return out


static func _mean(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var s: int = 0
	for v in arr:
		s += int(v)
	return Economy.idiv(s, arr.size())


## Spustí jeden běh. opts: per_profile (6), days (240), margin (false), profiles (výchozí všech 7).
static func run(p_seed: int, scenario: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var per: int = int(opts.get("per_profile", 6))
	var days: int = int(opts.get("days", 240))
	var profiles: Array = opts.get("profiles", MCat.PROFILE_IDS)
	var shock_day: int = int(scenario.get("shock_day", 100))
	var pre_day: int = shock_day - 1
	var mcfg: Dictionary = {"events": scenario.get("events", []), "margin_enabled": bool(opts.get("margin", false))}
	var extra: Dictionary = opts.get("market_cfg", {})
	for k in extra:
		mcfg[k] = extra[k]
	var eco: RefCounted = Economy.new(p_seed, {"auto_policy": true, "hire_bp": 100, "layoff_bp": 0, "illegal_share_bp": 0,
		"market_enabled": true, "market": mcfg})
	var members: Dictionary = {}
	var all_ids: Array = []
	for p in profiles:
		members[p] = []
	for slot in per:
		for p in profiles:
			var id: String = "%s_%02d" % [String(p), slot]
			eco.add_agent(id, {"tier": TIERS[slot % TIERS.size()], "skill": 3, "endowment": ENDOWMENTS[slot % ENDOWMENTS.size()],
				"job": JOBS[slot % JOBS.size()], "illegal": "", "shift_off": slot % 7})
			eco.market.set_profile(id, String(p))
			(members[p] as Array).append(id)
			all_ids.append(id)
	var pre: Dictionary = {}
	var idx_pre: int = 0
	var idx_min: int = StockMarket.PPM * 10
	var idx_series: Array = []
	for d in days:
		eco.run_day()
		var m: RefCounted = eco.market
		idx_series.append(int(m.index_ppm))
		if eco.day >= shock_day:
			idx_min = mini(idx_min, int(m.index_ppm))
		if eco.day == pre_day:
			pre = _snapshot(eco, all_ids)
			idx_pre = int(m.index_ppm)
	if pre.is_empty():
		pre = _snapshot(eco, all_ids)
		idx_pre = int(eco.market.index_ppm)
	var post: Dictionary = _snapshot(eco, all_ids)
	var res_profiles: Dictionary = {}
	for p in profiles:
		var ids: Array = members[p]
		var cols: Dictionary = {}
		for key in ["twr", "mdd", "pnl", "fees", "volume", "trades", "sells", "dd_exit", "distress", "equity", "dividends",
				"p_pre", "p_post", "pm_pre", "pm_post", "pov_pre", "pov_post", "povm_pre", "povm_post", "debt_pre", "debt_post",
				"w_pre", "w_post", "dw", "emp_post"]:
			cols[key] = []
		var sum_pnl: int = 0
		var sum_basis: int = 0
		var sum_sells: int = 0
		var sum_dd: int = 0
		for id in ids:
			var s: Dictionary = eco.market.agent_summary(String(id))
			var a0: Dictionary = pre[String(id)]
			var a1: Dictionary = post[String(id)]
			(cols["twr"] as Array).append(int(s["twr_pm"]))
			(cols["mdd"] as Array).append(int(s["mdd_pm"]))
			(cols["pnl"] as Array).append(int(s["pnl"]))
			(cols["fees"] as Array).append(int(s["fees"]))
			(cols["volume"] as Array).append(int(s["volume"]))
			(cols["trades"] as Array).append(int(s["buys"]) + int(s["sells"]))
			(cols["sells"] as Array).append(int(s["sells"]))
			(cols["dd_exit"] as Array).append(int(s["dd_exit_sells"]))
			(cols["distress"] as Array).append(int(s["distress_sells"]))
			(cols["equity"] as Array).append(int(s["avg_equity_pm"]))
			(cols["dividends"] as Array).append(int(s["dividends"]))
			(cols["p_pre"] as Array).append(int(a0["pressure"]))
			(cols["p_post"] as Array).append(int(a1["pressure"]))
			(cols["pm_pre"] as Array).append(int(a0["pressure_mtm"]))
			(cols["pm_post"] as Array).append(int(a1["pressure_mtm"]))
			(cols["pov_pre"] as Array).append(int(a0["pov"]) * 1000)
			(cols["pov_post"] as Array).append(int(a1["pov"]) * 1000)
			(cols["povm_pre"] as Array).append(int(a0["pov_mtm"]) * 1000)
			(cols["povm_post"] as Array).append(int(a1["pov_mtm"]) * 1000)
			(cols["debt_pre"] as Array).append(int(a0["debt"]) * 1000)
			(cols["debt_post"] as Array).append(int(a1["debt"]) * 1000)
			(cols["w_pre"] as Array).append(int(a0["wealth"]))
			(cols["w_post"] as Array).append(int(a1["wealth"]))
			(cols["dw"] as Array).append(int(a1["wealth"]) - int(a0["wealth"]))
			(cols["emp_post"] as Array).append(int(a1["employed"]) * 1000)
			sum_pnl += int(s["pnl"])
			sum_basis += int(s["avg_basis"])
			sum_sells += int(s["sells"])
			sum_dd += int(s["dd_exit_sells"])
		res_profiles[p] = {"n": ids.size(), "twr_pm": _mean(cols["twr"]), "mdd_pm": _mean(cols["mdd"]), "pnl": _mean(cols["pnl"]),
			"pnl_on_capital_pm": Economy.idiv(sum_pnl * 1000, maxi(1, sum_basis)), "fees": _mean(cols["fees"]),
			"volume": _mean(cols["volume"]), "trades": _mean(cols["trades"]), "sells": _mean(cols["sells"]),
			"dd_exit_sells": _mean(cols["dd_exit"]), "panic_sell_share_pm": Economy.idiv(sum_dd * 1000, maxi(1, sum_sells)),
			"distress_sells": _mean(cols["distress"]), "avg_equity_pm": _mean(cols["equity"]), "dividends": _mean(cols["dividends"]),
			"pressure_pre": _mean(cols["p_pre"]), "pressure_post": _mean(cols["p_post"]),
			"pressure_mtm_pre": _mean(cols["pm_pre"]), "pressure_mtm_post": _mean(cols["pm_post"]),
			"poverty_pre_pm": _mean(cols["pov_pre"]), "poverty_post_pm": _mean(cols["pov_post"]),
			"poverty_mtm_pre_pm": _mean(cols["povm_pre"]), "poverty_mtm_post_pm": _mean(cols["povm_post"]),
			"debt_pre_pm": _mean(cols["debt_pre"]), "debt_post_pm": _mean(cols["debt_post"]),
			"wealth_pre": _mean(cols["w_pre"]), "wealth_post": _mean(cols["w_post"]), "wealth_change": _mean(cols["dw"]),
			"employed_post_pm": _mean(cols["emp_post"])}
	var w_pre: Array = []
	var w_post: Array = []
	for id in all_ids:
		w_pre.append(int((pre[String(id)] as Dictionary)["wealth"]))
		w_post.append(int((post[String(id)] as Dictionary)["wealth"]))
	var cons: Dictionary = eco.conservation_report()
	var aud: Dictionary = eco.market.audit_positions()
	return {"seed": p_seed, "scenario": String(scenario["id"]), "hash": eco.state_hash(), "conservation_ok": bool(cons["ok"]),
		"positions_ok": bool(aud["ok"]), "profiles": res_profiles,
		"pop": {"gini_pre_pm": _gini(w_pre), "gini_post_pm": _gini(w_post), "index_pre": idx_pre, "index_min": idx_min,
			"index_post": int(eco.market.index_ppm), "index_trough_pm": Economy.idiv((idx_min - idx_pre) * 1000, maxi(1, idx_pre)),
			"index_end_pm": Economy.idiv((int(eco.market.index_ppm) - idx_pre) * 1000, maxi(1, idx_pre)),
			"volume": int(eco.market.stats["volume"]), "trades": int(eco.market.stats["trades"]), "fees": int(eco.market.stats["fees"]),
			"dd_exit_sells": int(eco.market.stats["dd_exit_sells"]), "distress_sells": int(eco.market.stats["distress_sells"]),
			"margin_calls": int(eco.market.stats["margin_calls"]), "treasury": int(eco.ledger.balance("treasury"))},
		"series": idx_series, "economy": eco}
