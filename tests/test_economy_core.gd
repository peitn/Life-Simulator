extends "res://tests/test_base.gd"
## Ekonomika E1 – jádro: hlavní kniha + hash řetězec, daně, půjčky, povinnosti, vynucování, tlak, metriky, serializace.
const Economy := preload("res://scripts/sim/economy/economy.gd")
const Ledger := preload("res://scripts/sim/economy/economy_ledger.gd")


func _ready() -> void:
	watchdog_seconds = 100.0
	_run.call_deferred()


## Ekonomika bez náhodných vlivů: žádná autopolitika, žádné tvrdé povinnosti navíc, ruční agenti.
func _quiet(cfg: Dictionary = {}) -> Economy:
	var c := {"auto_policy": false, "recycle_sinks": false}
	for k in cfg:
		c[k] = cfg[k]
	return Economy.new(7, c)


func _agent(e: Economy, id: String, endow: int, tier: String = "flat", job: String = "") -> void:
	e.add_agent(id, {"tier": tier, "endowment": endow, "job": job, "illegal": "", "skill": 3, "shift_off": 6})


func _run() -> void:
	_test_ledger()
	_test_tamper()
	_test_tax()
	_test_wages_and_obligations()
	_test_loans()
	_test_enforcement()
	_test_pressure()
	_test_metrics()
	_test_serialization()
	finish("test_economy_core")


func _test_ledger() -> void:
	section("Hlavní kniha: dvojitý zápis, záporné zůstatky, mint/burn")
	var l := Ledger.new()
	check(l.post(1, "mint", "world:mint", "agent:a", 1000, "m")["ok"], "mint na účet agenta")
	check(l.balance("agent:a") == 1000 and l.balance("world:mint") == -1000, "zůstatky odpovídají dvojitému zápisu")
	check(l.post(1, "t", "agent:a", "agent:b", 400)["ok"], "převod a -> b")
	check(not l.post(1, "t", "agent:a", "agent:b", 601)["ok"], "převod nad zůstatek je odmítnut")
	check(l.post(1, "t", "agent:a", "agent:b", 601)["reason"] == "insufficient_funds", "důvod: insufficient_funds")
	check(not l.post(1, "t", "agent:a", "agent:b", 0)["ok"] and not l.post(1, "t", "agent:a", "agent:b", -5)["ok"], "nulová a záporná částka odmítnuta")
	check(not l.post(1, "t", "agent:a", "agent:a", 5)["ok"], "převod sám sobě odmítnut")
	check(not l.post(1, "t", "agent:a", "world:mint", 5)["ok"], "do world:mint nelze vracet")
	check(not l.post(1, "t", "world:burn", "agent:a", 5)["ok"], "z world:burn nelze čerpat")
	var neg := false
	for k in l.accounts:
		if not Ledger.is_world(String(k)) and int(l.accounts[k]) < 0:
			neg = true
	check(not neg, "žádný běžný účet není záporný")
	check(l.post(2, "burn", "agent:b", "world:burn", 100)["ok"], "burn z účtu")
	check(l.circulating() == 900 and int(l.minted_burned_from_entries()["net"]) == 900, "oběh 900 == vytvořeno − zničeno")
	var sum := 0
	for k in l.accounts:
		sum += int(l.accounts[k])
	check(sum == 0, "součet všech zůstatků včetně world:* je 0")
	check(l.verify(), "čistá kniha projde verify()")
	check(l.size() == 3, "odmítnuté převody se nezapisují (3 záznamy)", str(l.size()))


func _test_tamper() -> void:
	section("Hash řetězec: detekce manipulace")
	var base := Ledger.new()
	base.post(1, "mint", "world:mint", "agent:a", 5000, "x")
	base.post(1, "t", "agent:a", "agent:b", 1200, "y")
	base.post(2, "t", "agent:b", "agent:c", 300, "z")
	base.post(3, "t", "agent:a", "agent:c", 700, "w")
	var head := base.head
	check(base.verify(head), "verify s očekávanou hlavou")
	var variants := {}
	var d := base.to_dict()
	variants["amount"] = func(x: Dictionary) -> void: ((x["entries"] as Array)[1] as Dictionary)["amount"] = 1300
	variants["memo"] = func(x: Dictionary) -> void: ((x["entries"] as Array)[2] as Dictionary)["memo"] = "jiné"
	variants["to"] = func(x: Dictionary) -> void: ((x["entries"] as Array)[1] as Dictionary)["to"] = "agent:d"
	variants["day"] = func(x: Dictionary) -> void: ((x["entries"] as Array)[0] as Dictionary)["day"] = 9
	variants["delete"] = func(x: Dictionary) -> void: (x["entries"] as Array).remove_at(1)
	variants["swap"] = func(x: Dictionary) -> void:
		var arr: Array = x["entries"]
		var t: Variant = arr[1]
		arr[1] = arr[2]
		arr[2] = t
	variants["hash_only"] = func(x: Dictionary) -> void: ((x["entries"] as Array)[3] as Dictionary)["hash"] = "f".repeat(64)
	variants["balance"] = func(x: Dictionary) -> void: (x["accounts"] as Dictionary)["agent:a"] = 99999
	variants["append_fake"] = func(x: Dictionary) -> void: (x["entries"] as Array).append({"id": 5, "day": 4, "kind": "t", "from": "world:mint", "to": "agent:a", "amount": 10, "memo": "", "prev": x["head"], "hash": "0".repeat(64)})
	for name in variants:
		var copy: Dictionary = base.to_dict()
		(variants[name] as Callable).call(copy)
		var tl := Ledger.from_dict(copy)
		check(not tl.verify(), "manipulace '%s' je odhalena" % name)
	# útočník, který přepočítá CELÝ řetězec po úpravě: verify() bez kotvy projde, s kotvou (head) ne
	var forged := base.to_dict()
	var ents: Array = forged["entries"]
	(ents[1] as Dictionary)["amount"] = 1300
	var prev := Ledger.GENESIS
	var bal := {}
	for e in ents:
		var ed: Dictionary = e
		ed["prev"] = prev
		ed["hash"] = Ledger.hash_entry(ed)
		prev = String(ed["hash"])
		bal[ed["from"]] = int(bal.get(ed["from"], 0)) - int(ed["amount"])
		bal[ed["to"]] = int(bal.get(ed["to"], 0)) + int(ed["amount"])
	forged["head"] = prev
	forged["accounts"] = bal
	var fl := Ledger.from_dict(forged)
	check(fl.verify(), "(limit) plně přepočítaný řetězec je sám o sobě konzistentní")
	check(not fl.verify(head), "ale externí kotva (původní head) ho odhalí")
	var rt := Ledger.from_dict(JSON.parse_string(JSON.stringify(base.to_dict())))
	check(rt.verify(head), "kniha po průchodu JSON (float čísla) stále projde verify")


func _test_tax() -> void:
	section("Daně: pásma a zaokrouhlení")
	var e := _quiet()
	check(e.tax_on(0) == 0 and e.tax_on(8000) == 0, "do 8000 kr/týden 0 %")
	check(e.tax_on(20000) == 1800, "20000 -> 12000 * 15 % = 1800", str(e.tax_on(20000)))
	check(e.tax_on(30000) == 4600, "30000 -> 1800 + 10000 * 28 % = 4600", str(e.tax_on(30000)))
	check(e.tax_on(8001) == 0 and e.tax_on(8007) == 1, "zaokrouhlení dolů: 8001 -> 0, 8007 -> 1")
	var mono := true
	var prev_t := 0
	for g in range(0, 60001, 37):
		var t := e.tax_on(g)
		if t < prev_t or t > g:
			mono = false
		prev_t = t
	check(mono, "daň je neklesající a nikdy vyšší než příjem (rastr po 37 kr)")
	var f := _quiet({"tax_mode": "flat", "flat_rate_bp": 1800})
	check(f.tax_on(10000) == 1800 and f.tax_on(5) == 0 and f.tax_on(6) == 1, "rovná daň 18 %: 10000 -> 1800, 6 -> 1")
	check(_quiet({"tax_mode": "none"}).tax_on(99999) == 0, "tax_mode none")
	# kumulativní srážka: součet daní za týden == tax_on(hrubý týden), bez ohledu na četnost výplat
	var w := _quiet()
	_agent(w, "p", 0, "flat", "courier")
	w.run_days(6)   # směny dny 1..5 (shift_off 6), den 7 by vynuloval týdenní čítač
	var a: Dictionary = w.agents["p"]
	var gross_w: int = int(a["week_gross"])
	check(gross_w == 5 * 8 * 330, "kurýr: týdenní hrubá mzda 13200", str(gross_w))
	check(int(a["week_tax"]) == w.tax_on(gross_w), "denní výplaty: součet srážek == daň z týdenního hrubého", "%d vs %d" % [a["week_tax"], w.tax_on(gross_w)])
	check(int(w.ledger.balance("treasury")) >= int(a["week_tax"]), "daň skončila v pokladně")


func _test_wages_and_obligations() -> void:
	section("Mzdy a povinnosti (jídlo, nájem, energie)")
	var e := _quiet()
	_agent(e, "w", 100000, "shared", "cleaner")
	e.run_days(6)
	var a: Dictionary = e.agents["w"]
	var gross: int = 5 * 8 * 300
	var tax := e.tax_on(gross)
	var spent: int = 6 * 400 + 4500 + 1000
	check(e.balance("w") == 100000 + gross - tax - spent, "zůstatek po týdnu = start + čistá mzda − povinnosti", "%d" % e.balance("w"))
	check(e.ledger.balance("employer:services") >= 0, "zaměstnavatelský účet nezáporný")
	check(int(e.conservation_report()["circulating"]) == e.ledger.circulating(), "oběh sedí")
	check(e.conservation_report()["ok"], "zachování peněz po týdnu")
	# chudák: nájem se nezaplatí => nedoplatek + zmeškaná povinnost
	var p := _quiet()
	_agent(p, "x", 1000, "shared")
	p.run_days(2)
	var ax: Dictionary = p.agents["x"]
	check(int(ax["arrears"]["rent"]) == 4500, "nájem v den 1 nezaplacen -> nedoplatek 4500", str(ax["arrears"]))
	check((ax["missed_log"] as Array).size() >= 1, "zmeškaná povinnost zapsána")
	check(p.balance("x") >= 0, "zůstatek nikdy záporný")
	# splacení nedoplatku po příjmu přes rezervu
	p.mint(Economy.acct("x"), 20000, "dar", "mint_test")
	p.run_days(2)
	check(int(ax["arrears"]["rent"]) == 0, "nedoplatek se splatí po dodání peněz")


func _test_loans() -> void:
	section("Půjčky: úrok celými čísly, minimální splátka, selhání = jen skóre")
	var e := _quiet({"loan_rate_table": [[0, 3650]], "loan_min_floor": 500, "loan_starter_cap": 100000})
	_agent(e, "d", 100000, "shared")
	var r := e.request_loan("d", 50000)
	check(bool(r["ok"]), "půjčka schválena", str(r))
	var l: Dictionary = e.loans[0]
	check(int(l["rate_bp"]) == 3650, "sazba 36,5 %/rok")
	e._accrue_interest(l)
	check(int(l["accrued"]) == 50, "denní úrok 50000 * 3650 / (10000*365) = 50", str(l["accrued"]))
	for i in 9:
		e._accrue_interest(l)
	check(int(l["accrued"]) == 500, "10 dní = 500")
	# zbytek se přenáší: balance 1001, 3650 bp => 10 kr za 10 dní by bez carry ztratilo; s carry přesně floor(1001*365*...)
	var e2 := _quiet({"loan_rate_table": [[0, 3650]], "loan_starter_cap": 100000})
	_agent(e2, "c", 5000, "shared")
	e2.request_loan("c", 1001)
	var l2: Dictionary = e2.loans[0]
	for i in 365:
		e2._accrue_interest(l2)
	check(int(l2["accrued"]) == (1001 * 3650) / 10000, "365 dní s carry = floor(1001*36,5 %) = 365", str(l2["accrued"]))
	check(e2.min_payment(l2) >= 500 or e2.min_payment(l2) == e2.loan_owed(l2), "minimální splátka respektuje spodní mez")
	# selhání platit -> 3x zmeškáno -> default, bez zabavení, jen skóre
	var f := _quiet({"loan_rate_table": [[0, 2000]], "food_daily": 0})
	_agent(f, "z", 0, "shared")
	f.mint("bank", 1, "x")
	var rr := f.request_loan("z", 5000)
	check(bool(rr["ok"]), "půjčka pro agenta bez příjmu (starter cap)", str(rr))
	var fa: Dictionary = f.agents["z"]
	var credit0: int = int(fa["credit"])
	# agent hned vyčerpá peníze, nemá z čeho platit
	f.transfer(Economy.acct("z"), "sink:food", f.balance("z"), "spend", "")
	f.run_days(95)
	var fl: Dictionary = f.loans[0]
	check(String(fl["status"]) == "default", "po 3 zmeškaných splátkách status default", String(fl["status"]))
	check(int(fl["missed_total"]) == 3, "3 zmeškané splátky", str(fl["missed_total"]))
	check(int(fa["credit"]) == credit0 + 3 * -20 - 150, "následek je jen pokles skóre (−20×3 −150)", str(fa["credit"]))
	check(f.balance("z") >= 0, "bez zabavení a bez záporného zůstatku")
	check(f.total_debt("z") >= 5000, "dluh dál eviduje")
	var acc_before := int(fl["accrued"])
	f.run_days(40)
	check(int(fl["accrued"]) == acc_before, "úrok po defaultu zmrazen")
	check(not bool(f.request_loan("z", 1000)["ok"]), "po defaultu další půjčka odmítnuta (skóre/limit)")
	# dobrovolné splacení
	f.mint(Economy.acct("z"), 100000, "dar", "mint_test")
	var owed := f.loan_owed(fl)
	var pr := f.repay_loan("z", int(fl["id"]), owed + 999)
	check(int(pr["paid"]) == owed and String(fl["status"]) == "paid", "splacení uzavře půjčku, přeplatek se nestrhne")
	check(f.conservation_report()["ok"], "zachování peněz s půjčkami")
	# odmítnutí
	var g := _quiet({"bank_capital": 1000})
	_agent(g, "q", 0, "shared")
	check(g.request_loan("q", 2000)["reason"] == "bank_liquidity", "nedostatek likvidity banky")
	check(g.request_loan("q", 0)["reason"] == "bad_amount", "špatná částka")
	check(g.request_loan("q", 999999)["reason"] == "bad_amount", "nad loan_max")
	var h := _quiet()
	_agent(h, "q", 0, "shared")
	h.request_loan("q", 3000)
	h.request_loan("q", 2000)
	check(h.request_loan("q", 100)["reason"] in ["too_many_loans", "over_debt_cap"], "limit počtu/dluhu")


func _test_enforcement() -> void:
	section("Vynucování: odhalení nelegálního příjmu")
	var jobs := {"sure_gig": {"title": "t", "legal": false, "sector": "underground", "shifts_per_week": 7, "income_min": 1000, "income_max": 1000, "detect_bp": 10000, "fine_pct": 150, "cooldown_days": 5},
		"never_gig": {"title": "t", "legal": false, "sector": "underground", "shifts_per_week": 7, "income_min": 500, "income_max": 500, "detect_bp": 0, "fine_pct": 100, "cooldown_days": 5}}
	var e := _quiet({"extra_jobs": jobs, "residual_detect_bp": 0, "detect_cap_bp": 10000})
	_agent(e, "i", 0, "shared")
	e.assign_job("i", "sure_gig")
	e.run_day()
	var a: Dictionary = e.agents["i"]
	check(int(a["detections"]) == 1, "jistě odhaleno hned první den", str(a["detections"]))
	check(int(a["cooldown_until"]) == 1 + 5 and int(a["exposure"]) == 0, "pozastavení 5 dní, expozice vynulována")
	var fine_entry := {}
	for en in e.ledger.entries:
		if String(en["kind"]) == "fine":
			fine_entry = en
	check(not fine_entry.is_empty(), "pokuta/zabavení je v knize")
	check(int(fine_entry.get("amount", 0)) <= 1000, "zabavení nepřesáhne zůstatek (příjem dne 1000, nájem a jídlo předtím?)")
	var fine_total: int = 1000 * 150 / 100
	check(int(e.stats["fines_levied"]) == fine_total, "pokuta = 150 % neodhaleného příjmu", str(e.stats["fines_levied"]))
	check(int(a["arrears"]["fine"]) + int(e.stats["fines_paid"]) == fine_total, "zbytek pokuty = nedoplatek (žádný záporný zůstatek)")
	check(e.balance("i") >= 0, "zůstatek nezáporný")
	var before := int(a["detections"])
	e.run_days(3)
	check(int(a["detections"]) == before and int(a["exposure"]) == 0, "během pozastavení žádný nový příjem ani odhalení")
	check(int(a["credit"]) == 600 - 30, "skóre −30 za odhalení")
	check(e.detection_bp("i") == 0, "bez expozice nulová šance odhalení")
	e.run_days(8)
	check(int(a["record"]) >= 2, "po konci pozastavení zase pracuje a je znovu odhalen (záznam roste)", str(a["record"]))
	check(e.conservation_report()["ok"], "zachování peněz s pokutami")
	# žádné odhalení při detect_bp 0
	var n := _quiet({"extra_jobs": jobs, "residual_detect_bp": 0})
	_agent(n, "n", 0, "shared")
	n.assign_job("n", "never_gig")
	n.run_days(200)
	check(int(n.agents["n"]["detections"]) == 0 and int(n.agents["n"]["exposure"]) > 0, "detect_bp 0: za 200 dní žádné odhalení, expozice roste")
	# statistická kontrola: ~1,2 %/den => za 4000 agent-dní desítky odhalení, ne 0 a ne všechny
	var s := _quiet({"extra_jobs": {"g": {"title": "t", "legal": false, "sector": "underground", "shifts_per_week": 7, "income_min": 100, "income_max": 100, "detect_bp": 120, "fine_pct": 0, "cooldown_days": 0}}, "residual_detect_bp": 0, "detect_record_bonus_pct": 0, "bank_capital": 0})
	for i in 20:
		_agent(s, "s%d" % i, 1000000, "shared")
		s.assign_job("s%d" % i, "g")
	s.run_days(200)
	var det: int = int(s.stats["detections"])
	check(det > 20 and det < 80, "frekvence odhalení řádově odpovídá 1,2 %/den (20×200 agent-dní)", str(det))


func _test_pressure() -> void:
	section("financial_pressure: vzorec, meze a monotonie")
	var e := _quiet()
	_agent(e, "rich", 10000000, "shared", "engineer")
	_agent(e, "poor", 0, "house")
	_agent(e, "mid", 40000, "flat")
	var comps: Dictionary = e.pressure_components("rich")
	check(int(comps["runway_pm"]) == 0 and int(comps["debt_pm"]) == 0 and int(comps["missed_pm"]) == 0, "bohatý bez dluhu: všechny složky 0")
	check(e.financial_pressure("rich") == 0.0, "financial_pressure bohatého = 0")
	check(e.financial_pressure("poor") >= 0.449 and e.financial_pressure("poor") <= 0.451, "nula na účtu: složka runway = 1000 -> 0,45", str(e.financial_pressure("poor")))
	var burn: int = e.daily_burn("mid")
	var expect_pm: int = clampi(1000 - 40000 * 1000 / (burn * 30), 0, 1000)
	check(int(e.pressure_components("mid")["runway_pm"]) == expect_pm, "runway_pm == 1000 − zůstatek*1000/(výdaje*30)", "%d vs %d" % [e.pressure_components("mid")["runway_pm"], expect_pm])
	# monotonie: víc peněz => menší tlak
	var last := 2.0
	var mono := true
	var prb := _quiet()
	_agent(prb, "m", 0, "flat")
	for i in 12:
		var p := prb.financial_pressure("m")
		if p > last:
			mono = false
		last = p
		prb.mint(Economy.acct("m"), 5000, "x", "mint_test")
	check(mono, "tlak neroste s přibývajícími penězi")
	# dluh zvedá tlak
	var d := _quiet()
	_agent(d, "d", 50000, "flat", "clerk")
	d.run_days(30)
	var p0 := d.financial_pressure("d")
	d.request_loan("d", 50000)
	d.transfer(Economy.acct("d"), "sink:food", 50000, "spend", "")
	var p1 := d.financial_pressure("d")
	check(p1 > p0, "půjčka (dluh) + vyčerpané peníze zvedá tlak", "%f -> %f" % [p0, p1])
	# zmeškané povinnosti zvedají tlak
	var m := _quiet()
	_agent(m, "m", 0, "shared")
	var pm0: int = m.pressure_pm("m")
	m.run_days(10)
	check(int(m.pressure_components("m")["missed_pm"]) > 0 and m.pressure_pm("m") > pm0 - 1, "zmeškané povinnosti zvedají složku missed")
	m.run_days(10)
	check(int(m.pressure_components("m")["missed_pm"]) == 1000, "po ≥6 zmeškaných složka 1000")
	check(m.financial_pressure("m") > 0.7, "bez peněz, s nedoplatky a zmeškanými povinnostmi vysoký tlak", str(m.financial_pressure("m")))
	var inb := true
	for id in e.agent_order:
		var v := e.financial_pressure(id)
		inb = inb and v >= 0.0 and v <= 1.0
	check(inb, "všude v mezích 0..1")
	# žádné automatické škodlivé jednání: vysoký tlak nezmění nelegální práci (auto_policy zapnutá)
	var np := Economy.new(11, {"illegal_share_bp": 0})
	for i in 10:
		np.add_agent("n%d" % i, {"endowment": 0, "illegal": "", "job": ""})
	np.run_days(120)
	var any_illegal := false
	for id in np.agent_order:
		if np.illegal_job_of(id) != "":
			any_illegal = true
	check(not any_illegal, "tíseň sama nikoho nepřivede k nelegální práci (jen tlak)")


func _test_metrics() -> void:
	section("Metriky: Gini, chudoba, domácnosti")
	check(Economy.gini_pm([0, 0, 0, 100]) == 750, "Gini [0,0,0,100] = 0,75")
	check(Economy.gini_pm([50, 50, 50, 50]) == 0, "Gini rovnoměrně = 0")
	check(Economy.gini_pm([]) == 0 and Economy.gini_pm([0, 0]) == 0, "Gini prázdno / samé nuly = 0")
	check(Economy.gini_pm([1, 2, 3, 4]) == 250, "Gini [1,2,3,4] = 0,25")
	var e := _quiet()
	e.add_agent("r", {"tier": "shared", "endowment": 1000000, "job": "", "illegal": "", "household": "H1"})
	e.add_agent("p", {"tier": "shared", "endowment": 0, "job": "", "illegal": "", "household": "H1"})
	e.add_agent("q", {"tier": "shared", "endowment": 0, "job": "", "illegal": "", "household": "H2"})
	var m := e.metrics()
	check(int(m["agents"]) == 3 and int(m["poverty_rate_pm"]) == 666, "2 ze 3 v chudobě", str(m["poverty_rate_pm"]))
	check(int(m["gini_pm"]) == 666, "Gini [1000000,0,0] = 2/3", str(m["gini_pm"]))
	check(int(m["median_balance"]) == 0, "medián 0")
	var hm := e.household_metrics()
	check(not bool(hm["H1"]["in_poverty"]) and bool(hm["H2"]["in_poverty"]), "domácnost H1 (pooled) mimo chudobu, H2 v chudobě")
	check(int(hm["H1"]["members"]) == 2, "H1 má 2 členy")
	check(int(m["money_supply"]) == int(e.conservation_report()["ledger_total"]), "money_supply == ledger_total")


func _test_serialization() -> void:
	section("to_dict / from_dict / JSON / stav po obnově")
	var e := Economy.new(21, {})
	for i in 8:
		e.add_agent("a%d" % i)
	e.run_days(120)
	var d := e.to_dict()
	var e2: Economy = Economy.from_dict(d)
	check(JSON.stringify(e2.to_dict(), "", true) == JSON.stringify(d, "", true), "round trip bez JSON je bit-identický")
	check(e2.state_hash() == e.state_hash(), "state_hash po round tripu shodný")
	var viaj: Variant = JSON.parse_string(JSON.stringify(d))
	var e3: Economy = Economy.from_dict(viaj)
	check(e3.state_hash() == e.state_hash(), "state_hash shodný i po průchodu přes JSON text")
	check(e3.ledger.verify(), "kniha po JSON round tripu projde verify")
	e.run_days(60)
	e3.run_days(60)
	check(e3.state_hash() == e.state_hash(), "po obnově z JSONu běh pokračuje identicky (rng stav se uložil)")
	check(e.conservation_report()["ok"], "zachování peněz po 180 dnech")
