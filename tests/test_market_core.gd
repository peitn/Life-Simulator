extends "res://tests/test_base.gd"
## Fiktivní burza – jádro: obchody přes knihu, poplatky jako propad, dividendy, zachování peněz, determinismus,
## save/load se shodným hashem, detekce manipulace (kniha i portfolia), odmítnutí neplatných obchodů.
const Economy := preload("res://scripts/sim/economy/economy.gd")
const Ledger := preload("res://scripts/sim/economy/economy_ledger.gd")
const StockMarket := preload("res://scripts/sim/economy/stock_market.gd")
const MCat := preload("res://scripts/sim/economy/market_catalog.gd")


func _ready() -> void:
	watchdog_seconds = 150.0
	_run.call_deferred()


func _eco(p_seed: int = 7, mcfg: Dictionary = {}, ecfg: Dictionary = {}) -> Economy:
	var c := {"auto_policy": false, "recycle_sinks": false, "market_enabled": true, "market": mcfg}
	for k in ecfg:
		c[k] = ecfg[k]
	return Economy.new(p_seed, c)


func _agent(e: Economy, id: String, endow: int, tier: String = "flat", job: String = "") -> void:
	e.add_agent(id, {"tier": tier, "endowment": endow, "job": job, "illegal": "", "skill": 3, "shift_off": 6})


## Agent bez automatických obchodů (jen ruční buy/sell).
func _manual(e: Economy, id: String, endow: int) -> void:
	_agent(e, id, endow)
	e.market.ensure_agent(id)
	(e.market.portfolios[id] as Dictionary)["active"] = false


func _run() -> void:
	_test_disabled_default()
	_test_buy_sell()
	_test_rejections()
	_test_fee_sink_and_tax()
	_test_dividends()
	_test_price_process()
	_test_profiles()
	_test_conservation_long()
	_test_determinism()
	_test_save_load()
	_test_tamper()
	_test_margin()
	_test_view_and_pressure()
	finish("test_market_core")


func _test_disabled_default() -> void:
	section("Burza je ve výchozím stavu vypnutá a nemění ekonomiku")
	var e := Economy.new(5, {"auto_policy": false})
	_agent(e, "a", 10000, "flat", "clerk")
	e.run_days(20)
	check(e.market == null, "market == null bez market_enabled")
	check(not e.to_dict().has("market"), "to_dict neobsahuje klíč market")
	check(not e.agent_view("a").has("market"), "agent_view nemá klíč market")
	var kinds := {}
	for en in e.ledger.entries:
		kinds[String(en["kind"])] = true
	check(not kinds.has("trade_buy") and not kinds.has("mint_market_capital"), "žádné burzovní záznamy v knize")
	check(MCat.FIRMS.size() >= 6 and MCat.FIRMS.size() <= 10, "6–10 fiktivních firem (%d)" % MCat.FIRMS.size())
	var secs := {}
	for f in MCat.FIRMS:
		secs[f["sector"]] = true
	var all_g := true
	for f in MCat.FIRMS:
		if not String(f["id"]).ends_with("-G"):
			all_g = false
	check(all_g, "všechny tickery nesou příponu -G (herní, vymyšlené)")
	check(secs.size() >= 3, "firmy ve více sektorech (%d)" % secs.size())


func _test_buy_sell() -> void:
	section("Nákup a prodej přes knihu")
	var e := _eco()
	_manual(e, "a", 100000)
	var m: StockMarket = e.market
	var px: int = m.price("ZLE-G")
	check(px == 640, "počáteční cena je celé číslo kr (%d)" % px)
	var bal0: int = e.balance("a")
	var maker0: int = e.ledger.balance(StockMarket.ACC_MAKER)
	var n0: int = e.ledger.size()
	var r: Dictionary = m.buy("a", "ZLE-G", 10)
	var cost: int = px * 10
	var fee: int = m.fee_of(cost)
	check(bool(r["ok"]), "nákup 10 akcií proběhl")
	check(e.balance("a") == bal0 - cost - fee, "zůstatek klesl o cenu + poplatek (%d)" % (cost + fee))
	check(m.shares_of("a", "ZLE-G") == 10, "držba je celé číslo 10")
	check(e.ledger.balance(StockMarket.ACC_MAKER) == maker0 + cost, "protistrana obdržela cenu")
	check(e.ledger.balance(StockMarket.SINK_FEE) == fee and fee == maxi(3, (cost * 50 + 9999) / 10000), "poplatek %d kr je v propadu sink:market_fee" % fee)
	check(e.ledger.size() == n0 + 2, "nákup = 2 záznamy knihy (obchod + poplatek)")
	check(e.ledger.verify() and bool(e.conservation_report()["ok"]), "kniha ověřena a peníze zachovány")
	check(bool(m.audit_positions()["ok"]), "pozice z knihy sedí s evidencí")
	var bal1: int = e.balance("a")
	var rs: Dictionary = m.sell("a", "ZLE-G", 4)
	var proceeds: int = px * 4
	var fee2: int = m.fee_of(proceeds)
	check(bool(rs["ok"]) and m.shares_of("a", "ZLE-G") == 6, "prodej 4 ze 10 -> zbývá 6")
	check(e.balance("a") == bal1 + proceeds - fee2, "zůstatek vzrostl o výnos − poplatek")
	var rs2: Dictionary = m.sell("a", "ZLE-G", 6)
	check(bool(rs2["ok"]) and m.shares_of("a", "ZLE-G") == 0, "prodej zbytku vyčistí pozici")
	check(m.portfolio_basis("a") == 0, "po úplném prodeji je nákladová báze 0")
	check(e.ledger.balance(StockMarket.SINK_FEE) == int(m.stats["fees"]), "součet poplatků v propadu == statistika poplatků")
	check(bool(e.conservation_report()["ok"]), "zachování i po prodejích")


func _test_rejections() -> void:
	section("Neplatné obchody se odmítnou beze změny stavu")
	var e := _eco()
	_manual(e, "poor", 500)
	_manual(e, "rich", 100000)
	var m: StockMarket = e.market
	var n0: int = e.ledger.size()
	var h0: String = e.state_hash()
	var r1: Dictionary = m.sell("rich", "ZLE-G", 1)
	check(not bool(r1["ok"]) and r1["reason"] == "insufficient_shares", "nulové akcie nelze prodat")
	var r2: Dictionary = m.buy("poor", "NVX-G", 1)
	check(not bool(r2["ok"]) and r2["reason"] == "insufficient_funds", "nelze koupit bez peněz (cena 1450 > 500)")
	var r3: Dictionary = m.buy("poor", "ZLE-G", 1)
	check(not bool(r3["ok"]), "ani jedna akcie za 640 + poplatek při zůstatku 500")
	check(m.buy("rich", "ZLE-G", 0)["reason"] == "bad_qty" and m.buy("rich", "ZLE-G", -3)["reason"] == "bad_qty", "nulový a záporný počet odmítnut")
	check(m.buy("rich", "XXX-G", 1)["reason"] == "unknown_ticker" and m.sell("rich", "XXX-G", 1)["reason"] == "unknown_ticker", "neznámý ticker")
	check(m.buy("ghost", "ZLE-G", 1)["reason"] == "unknown_agent", "neznámý agent")
	check(m.sell("rich", "ZLE-G", -1)["reason"] == "bad_qty", "záporný prodej odmítnut (žádný short)")
	m.buy("rich", "ZLE-G", 3)
	check(m.sell("rich", "ZLE-G", 4)["reason"] == "insufficient_shares", "prodej více, než agent drží, odmítnut")
	check(m.shares_of("rich", "ZLE-G") == 3, "držba beze změny po odmítnutém prodeji")
	check(int(m.stats["rejected"]) >= 8, "odmítnutí se počítají (%d)" % int(m.stats["rejected"]))
	# odmítnuté obchody nepřidaly nic do knihy: jediné nové záznamy jsou 2 záznamy platného nákupu 3 akcií
	check(e.ledger.size() == n0 + 2, "kniha obsahuje jen platný nákup (%d nových záznamů)" % (e.ledger.size() - n0))
	check(h0 != e.state_hash(), "platný nákup změnil stav (kontrola citlivosti hashe)")
	check(e.balance("poor") == 500 and m.portfolio_value("poor") == 0, "chudý agent beze změny")
	# nelikvidní tvůrce trhu
	var e2 := _eco(3, {"maker_capital": 0})
	_manual(e2, "x", 100000)
	e2.market.buy("x", "ZLE-G", 10)
	(e2.market.firms[0] as Dictionary)["px_u"] = 10 * 640 * 1000     # cena 10x
	var rl: Dictionary = e2.market.sell("x", "ZLE-G", 10)
	check(not bool(rl["ok"]) and rl["reason"] == "market_illiquid", "prodej nad likviditu tvůrce trhu odmítnut (market_illiquid)")
	check(e2.market.shares_of("x", "ZLE-G") == 10 and bool(e2.conservation_report()["ok"]), "po odmítnutí stav i zachování v pořádku")


func _test_fee_sink_and_tax() -> void:
	section("Poplatky jsou propad (sink), daň z obchodu jde do pokladny")
	var e := _eco(9, {"trade_tax_bp": 100, "fee_bp": 80})
	_manual(e, "a", 200000)
	var m: StockMarket = e.market
	var t0: int = e.ledger.balance("treasury")
	m.buy("a", "MRK-G", 50)
	m.sell("a", "MRK-G", 20)
	var cost: int = 480 * 50
	var proc: int = 480 * 20
	var tax_expected: int = (cost * 100) / 10000 + (proc * 100) / 10000
	check(e.ledger.balance("treasury") - t0 == tax_expected, "daň z obchodu %d kr přišla do pokladny" % tax_expected)
	var fees: int = m.fee_of(cost) + m.fee_of(proc)
	check(e.ledger.balance(StockMarket.SINK_FEE) == fees, "poplatky %d kr v propadu" % fees)
	var rep: Dictionary = e.conservation_report()
	check(bool(rep["ok"]) and int(rep["sinks"]) >= fees, "conservation_report počítá poplatek mezi propady (sinks=%d)" % int(rep["sinks"]))
	var sum_all := 0
	for k in e.ledger.accounts:
		sum_all += int(e.ledger.accounts[k])
	check(sum_all == 0, "součet všech zůstatků včetně world:* je 0")
	var kinds := {}
	for en in e.ledger.entries:
		kinds[String(en["kind"])] = true
	check(kinds.has("trade_buy") and kinds.has("trade_sell") and kinds.has("market_fee") and kinds.has("tax_trade"),
		"všechny transakce (nákup, prodej, poplatek, daň) jsou v knize")


func _test_dividends() -> void:
	section("Dividendy přes knihu, daň z dividend, škrt dividend")
	var base := {}
	var a := _eco(11, base)
	var b := _eco(11, {"events": [{"type": "div_cut", "day": 1, "days": 0, "cut_pm": 800}], "div_tax_bp": 1500})
	for e in [a, b]:
		_manual(e, "h", 400000)
		for t in MCat.FIRMS:
			e.market.buy("h", String(t["id"]), 100)
		e.run_days(200)
	var sum_a := 0
	var sum_b := 0
	var tax_b := 0
	for en in a.ledger.entries:
		if String(en["kind"]) == "dividend":
			sum_a += int(en["amount"])
	for en in b.ledger.entries:
		if String(en["kind"]) == "dividend":
			sum_b += int(en["amount"])
		if String(en["kind"]) == "tax_dividend":
			tax_b += int(en["amount"])
	check(sum_a > 0, "dividendy se vyplácejí (celkem %d kr za 200 dní)" % sum_a)
	check(sum_b < sum_a / 2, "škrt o 80 %% + daň sníží výplatu (%d vs %d kr)" % [sum_b, sum_a])
	check(tax_b > 0, "daň z dividend přišla do pokladny (%d kr)" % tax_b)
	check(bool(a.conservation_report()["ok"]) and bool(b.conservation_report()["ok"]), "zachování peněz s dividendami")
	check(a.ledger.balance("firm:ZLE-G") == 0, "účet firmy po výplatě je vyčerpán (mint přesně na výplatu)")
	check(int(a.market.stats["dividends_net"]) == sum_a, "statistika dividend sedí s knihou")
	check(bool(a.market.audit_positions()["ok"]), "audit pozic po dividendách")


func _test_price_process() -> void:
	section("Cenový proces: celočíselné ceny, cesta šoku, signály")
	var e := _eco(21)
	e.run_days(200)
	var m: StockMarket = e.market
	var ok_px := true
	for t in m.tickers():
		if m.price(t) < 1:
			ok_px = false
	check(ok_px, "všechny ceny >= 1 kr")
	check(m.index_hist.size() == StockMarket.HIST_MAX and int(m.firm("ZLE-G")["hist"].size()) == StockMarket.HIST_MAX, "historie je oříznutá na %d" % StockMarket.HIST_MAX)
	var prod := StockMarket.PPM
	for k in range(1, 4):
		prod = (prod * (StockMarket.PPM + StockMarket.path_step_ppm(-300000, 3, k))) / StockMarket.PPM
	check(absi(prod - 700000) <= 5, "cesta -30 %% za 3 dny dává součin %d ppm (cíl 700000)" % prod)
	var prod2 := StockMarket.PPM
	for k in range(1, 41):
		prod2 = (prod2 * (StockMarket.PPM + StockMarket.path_step_ppm(600000, 40, k))) / StockMarket.PPM
	check(absi(prod2 - 1600000) <= 200, "cesta +60 %% za 40 dní dává %d ppm (cíl 1600000)" % prod2)
	check(StockMarket.path_step_ppm(-300000, 3, 0) == 0 and StockMarket.path_step_ppm(-300000, 3, 4) == 0, "mimo okno je krok 0")
	check(StockMarket.validate_events([{"type": "path", "day": 5, "days": 3, "total_pm": -300}]) == "", "platná událost projde")
	check(StockMarket.validate_events([{"type": "zzz", "day": 5}]) != "", "neznámý typ události je odmítnut")
	check(StockMarket.validate_events([{"type": "path", "day": 0, "days": 3, "total_pm": -300}]) != "", "den < 1 odmítnut")
	check(StockMarket.validate_events([{"type": "path", "day": 5, "days": 3, "total_pm": -1000}]) != "", "pokles o 100 %% odmítnut")


func _test_profiles() -> void:
	section("Investorské profily odvozené ze seedu a vlastností")
	var e := _eco(31, {}, {"illegal_share_bp": 0})
	for i in 200:
		e.add_agent("n%03d" % i)
		e.market.ensure_agent("n%03d" % i)
	var seen := {}
	for id in e.agent_order:
		seen[e.market.profile_of(String(id))] = int(seen.get(e.market.profile_of(String(id)), 0)) + 1
	check(seen.size() >= 6, "z 200 agentů vzniká >= 6 různých profilů (%s)" % str(seen))
	for k in seen:
		check(MCat.PROFILES.has(k), "profil %s existuje v katalogu" % k)
	var e2 := _eco(31, {}, {"illegal_share_bp": 0})
	for i in 200:
		e2.add_agent("n%03d" % i)
		e2.market.ensure_agent("n%03d" % i)
	var same := true
	for id in e.agent_order:
		if e.market.profile_of(String(id)) != e2.market.profile_of(String(id)):
			same = false
	check(same, "stejný seed -> stejné profily")
	var e3 := _eco(32, {}, {"illegal_share_bp": 0})
	for i in 200:
		e3.add_agent("n%03d" % i)
		e3.market.ensure_agent("n%03d" % i)
	var diff := 0
	for id in e.agent_order:
		if e.market.profile_of(String(id)) != e3.market.profile_of(String(id)):
			diff += 1
	check(diff > 20, "jiný seed -> jiné rozdělení profilů (%d rozdílů)" % diff)
	check(e.market.set_profile("n000", "panic") and e.market.profile_of("n000") == "panic", "ruční předvolba profilu")
	check(not e.market.set_profile("n000", "neexistuje"), "neznámý profil odmítnut")
	var tr := true
	for id in e.agent_order:
		var pf: Dictionary = e.market.portfolios[String(id)]
		for key in ["t_risk", "t_impulse", "t_lossav", "t_indep"]:
			if int(pf[key]) < 0 or int(pf[key]) > 999:
				tr = false
	check(tr, "vlohy jsou v rozsahu 0..999 pm")


func _test_conservation_long() -> void:
	section("Zachování peněz a nezáporné pozice – 365 dní, 20 agentů, 3 seedy, odvozené profily")
	for s in [1, 2, 3]:
		var e := Economy.new(s, {"market_enabled": true})
		for i in 20:
			e.add_agent("a%02d" % i)
		e.run_days(365)
		var rep: Dictionary = e.conservation_report()
		var neg := false
		for k in e.ledger.accounts:
			if not Ledger.is_world(String(k)) and int(e.ledger.accounts[k]) < 0:
				neg = true
		var negsh := false
		for id in e.market.portfolios:
			for t in (e.market.portfolios[id]["shares"] as Dictionary):
				if int(e.market.portfolios[id]["shares"][t]) < 0:
					negsh = true
		check(bool(rep["ok"]), "seed %d: zachování a řetězec (entries=%d, trades=%d)" % [s, int(rep["entries"]), int(e.market.stats["trades"])])
		check(not neg and not negsh, "seed %d: žádný záporný účet ani pozice" % s)
		check(bool(e.market.audit_positions()["ok"]), "seed %d: pozice z knihy sedí" % s)
		check(e.ledger.balance(StockMarket.SINK_FEE) == int(e.market.stats["fees"]), "seed %d: propad poplatků == součet poplatků" % s)
		check(int(e.market.stats["trades"]) > 20, "seed %d: dochází k obchodům (%d)" % [s, int(e.market.stats["trades"])])


func _test_determinism() -> void:
	section("Determinismus")
	var hs: Array = []
	for s in [4, 4, 5]:
		var e := Economy.new(s, {"market_enabled": true})
		for i in 12:
			e.add_agent("a%02d" % i)
		e.run_days(200)
		hs.append(e.state_hash())
	check(hs[0] == hs[1], "stejný seed -> stejný hash (%s)" % String(hs[0]).substr(0, 12))
	check(hs[0] != hs[2], "jiný seed -> jiný hash")
	# zapnutí burzy nemění náhodu ekonomiky: bez obchodů je mzdová stránka stejná
	var a := Economy.new(6, {"auto_policy": false})
	var b := Economy.new(6, {"auto_policy": false, "market_enabled": true})
	for e in [a, b]:
		e.add_agent("x", {"job": "clerk", "skill": 3, "illegal": ""})
		if e.market != null:
			e.market.ensure_agent("x")
			(e.market.portfolios["x"] as Dictionary)["active"] = false
		e.run_days(40)
	check(a.balance("x") == b.balance("x"), "burza bez obchodů nemění mzdy ani povinnosti ekonomiky")


func _test_save_load() -> void:
	section("Uložení a obnova (JSON) se shodným hashem")
	var e := Economy.new(8, {"market_enabled": true})
	for i in 14:
		e.add_agent("a%02d" % i)
	e.run_days(120)
	var d: Dictionary = e.to_dict()
	check(d.has("market"), "to_dict obsahuje market")
	var e2: Economy = Economy.from_dict(d)
	check(e2.state_hash() == e.state_hash(), "state_hash po round tripu shodný")
	var e3: Economy = Economy.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(e3.state_hash() == e.state_hash(), "state_hash shodný i po průchodu přes JSON text")
	check(e3.market != null and bool(e3.market.audit_positions()["ok"]), "po obnově audit pozic v pořádku")
	e.run_days(90)
	e3.run_days(90)
	check(e3.state_hash() == e.state_hash(), "po obnově běh pokračuje identicky (rng burzy se uložil)")
	check(e3.ledger.head == e.ledger.head and bool(e3.conservation_report()["ok"]), "hlava řetězce shodná, zachování platí")


func _test_tamper() -> void:
	section("Detekce manipulace")
	var e := Economy.new(12, {"market_enabled": true})
	for i in 10:
		e.add_agent("a%02d" % i)
	e.run_days(150)
	var d: Dictionary = e.to_dict()
	var idx := -1
	for i in e.ledger.entries.size():
		if String(e.ledger.entries[i]["kind"]) == "trade_buy":
			idx = i
			break
	check(idx >= 0, "v knize je obchod k manipulaci")
	var t1: Economy = Economy.from_dict(d)
	check(t1.ledger.verify(), "kopie před úpravou projde verify()")
	t1.ledger.entries[idx]["amount"] = int(t1.ledger.entries[idx]["amount"]) + 1
	check(not t1.ledger.verify() and not bool(t1.conservation_report()["ok"]), "změna částky obchodu odhalena")
	var t2: Economy = Economy.from_dict(d)
	t2.ledger.entries.remove_at(idx)
	check(not t2.ledger.verify(), "smazání záznamu obchodu odhaleno")
	var t3: Economy = Economy.from_dict(d)
	t3.ledger.accounts[StockMarket.ACC_MAKER] = int(t3.ledger.accounts[StockMarket.ACC_MAKER]) + 1000
	check(not t3.ledger.verify(), "ruční úprava zůstatku tvůrce trhu odhalena")
	var t4: Economy = Economy.from_dict(d)
	var victim := ""
	var tk := ""
	for id in t4.market.portfolios:
		var shh: Dictionary = t4.market.portfolios[id]["shares"]
		for t in shh:
			if int(shh[t]) > 0 and victim == "":
				victim = String(id)
				tk = String(t)
	check(victim != "", "existuje agent s kladnou pozicí")
	var sh: Dictionary = t4.market.portfolios[victim]["shares"]
	sh[tk] = int(sh[tk]) + 5
	check(t4.ledger.verify() and not bool(t4.market.audit_positions()["ok"]), "přidání akcií do portfolia mimo knihu odhaleno auditem pozic")
	var t5: Economy = Economy.from_dict(d)
	var sh5: Dictionary = t5.market.portfolios[victim]["shares"]
	sh5[tk] = 0
	check(not bool(t5.market.audit_positions()["ok"]), "smazání pozice mimo knihu odhaleno auditem")
	var t6: Economy = Economy.from_dict(d)
	check(bool(t6.market.audit_positions()["ok"]) and t6.state_hash() == e.state_hash(), "neupravená kopie je čistá a shodná")


func _test_margin() -> void:
	section("Marginová půjčka (volitelný příznak) a margin call")
	var e := _eco(41, {"margin_enabled": true})
	_manual(e, "m", 60000)
	var m: StockMarket = e.market
	var rl: Dictionary = e.request_loan("m", 5000)
	check(bool(rl["ok"]), "půjčka z existujícího loan systému schválena")
	(m.portfolios["m"]["margin_loans"] as Array).append(int(rl["loan_id"]))
	m.buy("m", "NVX-G", 40)
	check(m.shares_of("m", "NVX-G") == 40, "nákup za půjčené peníze")
	m._margin_check("m")
	check(m.shares_of("m", "NVX-G") == 40 and int(m.stats["margin_calls"]) == 0, "bez poklesu cen se margin call nespustí")
	(m.firm("NVX-G"))["px_u"] = 100 * 1000     # pád ceny z 1450 na 100
	m._margin_check("m")
	check(int(m.stats["margin_calls"]) == 1 and m.shares_of("m", "NVX-G") == 0, "po poklesu pod hranici nucený prodej")
	check(e.loan_debt("m") == 0, "výnos z nuceného prodeje splatil půjčku (dluh %d)" % e.loan_debt("m"))
	check(bool(e.conservation_report()["ok"]) and bool(m.audit_positions()["ok"]), "zachování a audit po margin callu")
	# bez příznaku se nepůjčuje
	var e2 := _eco(42, {"margin_enabled": false})
	_agent(e2, "z", 5000, "flat", "clerk")
	e2.market.set_profile("z", "momentum")
	e2.run_days(120)
	check(int(e2.market.stats["margin_loans"]) == 0, "margin_enabled=false -> žádné marginové půjčky")


func _test_view_and_pressure() -> void:
	section("Rozhraní pro psychiku: financial_pressure / agent_view")
	var e := _eco(51)
	_agent(e, "v", 80000, "flat", "clerk")
	e.market.ensure_agent("v")
	(e.market.portfolios["v"] as Dictionary)["active"] = false
	e.market.buy("v", "HBT-G", 20)
	e.run_days(10)
	var v: Dictionary = e.agent_view("v")
	check(v.has("market") and v["market"].has("portfolio_value") and v["market"].has("drawdown_pm"), "agent_view obsahuje blok market (jen čtení)")
	check(v["financial_pressure"] == e.financial_pressure("v"), "financial_pressure je beze změny definice")
	var p0: int = e.pressure_pm("v")
	(e.market.firm("HBT-G"))["px_u"] = 100 * 1000
	check(e.pressure_pm("v") == p0, "pokles ceny akcií sám financial_pressure nemění (jen hotovost, dluh, zmeškané povinnosti)")
	check(e.market.pressure_mtm_pm("v") >= 0 and e.market.pressure_mtm_pm("v") <= 1000, "alternativní pohled pressure_mtm je v 0..1000")
	check(e.market.net_wealth_mtm("v") == e.balance("v") + e.market.portfolio_value("v") - e.total_debt("v"), "net_wealth_mtm = hotovost + portfolio − dluh")
