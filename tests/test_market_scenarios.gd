extends "res://tests/test_base.gd"
## Fiktivní burza – scénáře šoků a chování investorských profilů (mechanismus, ne předpověď).
const Lab := preload("res://scripts/sim/economy/market_lab.gd")
const MCat := preload("res://scripts/sim/economy/market_catalog.gd")
const StockMarket := preload("res://scripts/sim/economy/stock_market.gd")

const SEED := 2
const OPTS := {"per_profile": 3, "days": 200}

var _sc: Dictionary = {}
var _runs: Dictionary = {}


func _ready() -> void:
	watchdog_seconds = 240.0
	_run.call_deferred()


func _r(sid: String, p_seed: int = SEED) -> Dictionary:
	var key := "%s_%d" % [sid, p_seed]
	if not _runs.has(key):
		_runs[key] = Lab.run(p_seed, Lab.scenario_by_id(_sc, sid), OPTS)
	return _runs[key]


func _run() -> void:
	_test_scenario_file()
	_test_crash()
	_test_profiles_in_crash()
	_test_shapes()
	_test_other_shocks()
	_test_determinism()
	_test_all_scenarios_conserve()
	_test_margin_option()
	finish("test_market_scenarios")


func _test_scenario_file() -> void:
	section("Scénáře (JSON) se načtou a zvalidují")
	_sc = Lab.load_scenarios()
	check(bool(_sc["ok"]), "market_scenarios.json je platný (%s)" % _sc["error"])
	var ids: Array = []
	for s in _sc["scenarios"]:
		ids.append(String(s["id"]))
	for need in ["baseline", "crash", "crash_rebound", "bubble", "bear", "highvol", "sector", "divcut", "rates", "crash_layoffs"]:
		check(ids.has(need), "scénář %s existuje" % need)
	check(String(_sc["tag"]) == "game_balance", "soubor je označen game_balance")
	check(Lab.scenario_by_id(_sc, "baseline")["events"].is_empty(), "baseline nemá žádné události")
	check(StockMarket.validate_events([{"type": "path", "day": 3}]) != "", "neúplná událost je odmítnuta")


func _test_crash() -> void:
	section("Šok sníží ceny")
	var b: Dictionary = _r("baseline")
	var c: Dictionary = _r("crash")
	var ib: int = int((b["pop"] as Dictionary)["index_post"])
	var ic: int = int((c["pop"] as Dictionary)["index_post"])
	check(ic * 1000 / ib <= 800, "index po krachu je >= 20 %% pod baseline (%d vs %d ppm)" % [ic, ib])
	check(int((c["pop"] as Dictionary)["index_trough_pm"]) <= -250, "propad indexu od předšokového dne ≈ -30 %% (%d pm)" % int((c["pop"] as Dictionary)["index_trough_pm"]))
	var sb: Array = b["series"]
	var sc: Array = c["series"]
	var same := true
	for i in 98:
		if sb[i] != sc[i]:
			same = false
	check(same, "před šokem jsou cenové cesty obou scénářů shodné (společné náhodné veličiny)")
	check(sc[102] * 1000 / sc[98] <= 760, "do 3 dnů po šoku index klesl o ≥ 24 %% (%d → %d)" % [sc[98], sc[102]])
	check(sb[102] * 1000 / sb[98] >= 900, "bez šoku se index za stejné 3 dny tolik nehnul")
	for sid in ["bubble", "bear", "sector"]:
		check(int((_r(sid)["pop"] as Dictionary)["index_post"]) < ib, "%s: konečný index pod baseline" % sid)


func _test_profiles_in_crash() -> void:
	section("Chování profilů při krachu")
	var c: Dictionary = _r("crash")
	var b: Dictionary = _r("baseline")
	var pc: Dictionary = c["profiles"]
	var pb: Dictionary = b["profiles"]
	check(pc.size() == 7, "všech 7 profilů je zastoupeno")
	for p in pc:
		check(int(pc[p]["n"]) == 3, "profil %s: 3 agenti" % p)
	check(int(pc["panic"]["dd_exit_sells"]) > int(pc["passive"]["dd_exit_sells"]), "panický profil prodává panicky víc než pasivní (%d vs %d)" % [int(pc["panic"]["dd_exit_sells"]), int(pc["passive"]["dd_exit_sells"])])
	check(int(pc["panic"]["panic_sell_share_pm"]) > int(pc["passive"]["panic_sell_share_pm"]), "podíl panických prodejů: panický > pasivní")
	check(int(pc["panic"]["sells"]) > int(pc["passive"]["sells"]), "panický profil prodává celkově víc než pasivní (%d vs %d)" % [int(pc["panic"]["sells"]), int(pc["passive"]["sells"])])
	check(int(pc["passive"]["dd_exit_sells"]) == 0 and int(pc["balanced"]["dd_exit_sells"]) == 0, "pasivní a vyvážený nemají výprodejní pravidlo")
	check(int(pb["panic"]["dd_exit_sells"]) == 0, "bez šoku panický profil panicky neprodává")
	check(int(pc["momentum"]["trades"]) > int(pc["balanced"]["trades"]), "momentum obchoduje víc než vyvážený (%d vs %d)" % [int(pc["momentum"]["trades"]), int(pc["balanced"]["trades"])])
	check(int(pc["momentum"]["fees"]) > int(pc["balanced"]["fees"]), "a platí víc poplatků")
	for p in pc:
		check(int(pc[p]["mdd_pm"]) >= int(pb[p]["mdd_pm"]), "%s: max drawdown po krachu >= bez šoku" % p)
	check(int(pc["balanced"]["twr_pm"]) < int(pb["balanced"]["twr_pm"]), "vyvážený: výnos po krachu horší než bez šoku")
	var rb: Dictionary = _r("crash_rebound")["profiles"]
	check(int(rb["panic"]["dd_exit_sells"]) > 0 and int(rb["passive"]["dd_exit_sells"]) == 0, "i při odrazu (V) panický profil nejdřív panicky prodá, pasivní ne")
	print("  info (znaménko rozdílu panický − pasivní závisí na seedu a tvaru šoku; viz docs/economy_market.md): V-odraz twr panic=%d pasivní=%d pm" % [int(rb["panic"]["twr_pm"]), int(rb["passive"]["twr_pm"])])


func _test_shapes() -> void:
	section("Tvary scénářů: bublina, medvěd, volatilita")
	var s: Array = _r("bubble")["series"]
	check(s[98] * 1000 / s[58] >= 1300, "bublina: index za 40 dní vyrostl o ≥ 30 %% (%d → %d)" % [s[58], s[98]])
	check(s[104] * 1000 / s[98] <= 650, "splasknutí: ≥ 35 %% pokles za 5 dní (%d → %d)" % [s[98], s[104]])
	var bear: Array = _r("bear")["series"]
	check(bear[218 - 19] * 1000 / bear[98] <= 800, "medvěd: po 120 dnech index o ≥ 20 %% níž (%d → %d)" % [bear[98], bear[199]])
	var hv: Array = _r("highvol")["series"]
	var bs: Array = _r("baseline")["series"]
	var calm := 0
	var wild := 0
	var calm_b := 0
	var wild_b := 0
	for i in range(40, 99):
		calm += absi(hv[i] - hv[i - 1]) * 10000 / hv[i - 1]
	for i in range(101, 160):
		wild += absi(hv[i] - hv[i - 1]) * 10000 / hv[i - 1]
		wild_b += absi(bs[i] - bs[i - 1]) * 10000 / bs[i - 1]
	check(wild > calm * 2, "vysoká volatilita: průměrný denní pohyb > 2x (%d vs %d)" % [wild / 59, calm / 59])
	check(wild > wild_b * 2, "a > 2x proti baseline ve stejném období (%d vs %d)" % [wild / 59, wild_b / 59])


func _test_other_shocks() -> void:
	section("Sektorový šok, dividendový škrt, posun sazeb a daní, vlna propouštění")
	var e: RefCounted = _r("sector")["economy"]
	var b: RefCounted = _r("baseline")["economy"]
	var m: StockMarket = e.market
	var mb: StockMarket = b.market
	var hn: Array = m.firm("NVX-G")["hist"]
	var hz: Array = m.firm("ZLE-G")["hist"]
	var hnb: Array = mb.firm("NVX-G")["hist"]
	check(hn[hn.size() - 1] * 1000 / hnb[hnb.size() - 1] <= 650, "technologie po šoku o ≥ 35 %% níž než baseline")
	var hzb: Array = mb.firm("ZLE-G")["hist"]
	check(absi(hz[hz.size() - 1] * 1000 / hzb[hzb.size() - 1] - 1000) <= 150, "mimo sektor se cena od baseline příliš neliší (±15 %%)")
	var d_base := 0
	var d_cut := 0
	for en in b.ledger.entries:
		if String(en["kind"]) == "dividend" and int(en["day"]) > 100:
			d_base += int(en["amount"])
	for en in _r("divcut")["economy"].ledger.entries:
		if String(en["kind"]) == "dividend" and int(en["day"]) > 100:
			d_cut += int(en["amount"])
	check(d_base > 0 and d_cut * 2 <= d_base, "dividendy po škrtu ≤ 50 %% baseline (%d vs %d kr)" % [d_cut, d_base])
	var re: RefCounted = _r("rates")["economy"]
	var tax_after := 0
	var tax_before := 0
	for en in re.ledger.entries:
		if String(en["kind"]) == "tax_trade":
			if int(en["day"]) >= 100:
				tax_after += int(en["amount"])
			else:
				tax_before += int(en["amount"])
	check(tax_before == 0 and tax_after > 0, "daň z obchodu se vybírá až po zásahu (%d kr)" % tax_after)
	check(int(re.config["loan_rate_table"][0][1]) == int(b.config["loan_rate_table"][0][1]) + 500, "sazby půjček posunuty o +500 bp")
	check(int(re.market.cfg["div_tax_bp"]) == 1500, "daň z dividend nastavena")
	var cl: Dictionary = _r("crash_layoffs")
	check(int(cl["economy"].market.stats["layoffs"]) == 5, "vlna propouštění zasáhla 25 %% z 21 zaměstnaných (5)")
	var cp: Dictionary = cl["profiles"]
	var c0: Dictionary = _r("crash")["profiles"]
	var sum_debt_l := 0
	var sum_debt_c := 0
	for p in cp:
		sum_debt_l += int(cp[p]["debt_post_pm"])
		sum_debt_c += int(c0[p]["debt_post_pm"])
	check(sum_debt_l >= sum_debt_c, "po propouštění je podíl zadlužených agentů >= než bez něj (%d vs %d)" % [sum_debt_l, sum_debt_c])


func _test_determinism() -> void:
	section("Scénáře jsou deterministické")
	var a: Dictionary = Lab.run(5, Lab.scenario_by_id(_sc, "crash"), OPTS)
	var b: Dictionary = Lab.run(5, Lab.scenario_by_id(_sc, "crash"), OPTS)
	check(a["hash"] == b["hash"], "stejný seed + scénář -> stejný hash (%s)" % String(a["hash"]).substr(0, 12))
	check(JSON.stringify(a["profiles"]) == JSON.stringify(b["profiles"]) and JSON.stringify(a["pop"]) == JSON.stringify(b["pop"]), "stejné metriky všech profilů i populace")
	var c: Dictionary = Lab.run(6, Lab.scenario_by_id(_sc, "crash"), OPTS)
	check(a["hash"] != c["hash"], "jiný seed -> jiný hash")
	var d: Dictionary = Lab.run(5, Lab.scenario_by_id(_sc, "bear"), OPTS)
	check(a["hash"] != d["hash"], "jiný scénář -> jiný hash")


func _test_all_scenarios_conserve() -> void:
	section("Všechny scénáře: zachování peněz, řetězec knihy, pozice z knihy")
	for s in _sc["scenarios"]:
		var r: Dictionary = _r(String(s["id"]))
		check(bool(r["conservation_ok"]) and bool(r["positions_ok"]), "%s: zachování + pozice (obchodů %d, objem %d kr)" % [s["id"], int(r["pop"]["trades"]), int(r["pop"]["volume"])])
		var g: int = int(r["pop"]["gini_post_pm"])
		check(g >= 0 and g <= 1000, "%s: Gini v 0..1000 pm (%d)" % [s["id"], g])


func _test_margin_option() -> void:
	section("Volitelná marginová půjčka ve scénáři bubliny")
	var o: Dictionary = OPTS.duplicate()
	o["margin"] = true
	var r: Dictionary = Lab.run(SEED, Lab.scenario_by_id(_sc, "bubble"), o)
	check(bool(r["conservation_ok"]) and bool(r["positions_ok"]), "s marginou: zachování a pozice v pořádku")
	var plain: Dictionary = _r("bubble")
	check(int(plain["economy"].market.stats["margin_loans"]) == 0, "bez příznaku margin žádné marginové půjčky")
	print("  info: marginové půjčky=%d, margin cally=%d" % [int(r["economy"].market.stats["margin_loans"]), int(r["pop"]["margin_calls"])])
