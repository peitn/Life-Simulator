extends "res://tests/test_base.gd"
## Ekonomika E1 – dlouhý běh: 365 dní, 8–20 agentů, zachování peněz, determinismus, CSV demo.
const Economy := preload("res://scripts/sim/economy/economy.gd")
const Demo := preload("res://tools/lab/economy_demo.gd")


func _ready() -> void:
	watchdog_seconds = 100.0
	_run.call_deferred()


func _build(p_seed: int, n: int, cfg: Dictionary = {}) -> Economy:
	var e := Economy.new(p_seed, cfg)
	for i in n:
		e.add_agent("a%02d" % i)
	return e


func _run() -> void:
	section("Zachování peněz: 365 dní, 8 / 14 / 20 agentů, více seedů")
	for cfgi in [[8, 1], [8, 2], [14, 3], [20, 4], [20, 5]]:
		var n: int = cfgi[0]
		var sd: int = cfgi[1]
		var e := _build(sd, n)
		var neg := false
		var bad_pressure := false
		var cons_every_week := true
		for d in 365:
			e.run_day()
			for id in e.agent_order:
				if e.balance(id) < 0:
					neg = true
				var p := e.financial_pressure(id)
				if p < 0.0 or p > 1.0 or is_nan(p):
					bad_pressure = true
			if d % 52 == 0 and not bool(e.conservation_report()["ok"]):
				cons_every_week = false
		var rep := e.conservation_report()
		var tag := "[n=%d seed=%d]" % [n, sd]
		check(bool(rep["ok"]), tag + " sum(zůstatky)+propady == ledger_total po 365 dnech", str(rep))
		check(int(rep["agents"]) + int(rep["sinks"]) + int(rep["institutions"]) == int(rep["ledger_total"]), tag + " agenti+propady+instituce == vytvořeno−zničeno")
		check(cons_every_week, tag + " zachování platilo i průběžně")
		check(not neg, tag + " žádný záporný zůstatek agenta")
		check(not bad_pressure, tag + " financial_pressure vždy v 0..1")
		check(e.ledger.verify(e.ledger.head), tag + " hash řetězec sedí (%d záznamů)" % e.ledger.size())
		var kinds := {}
		for en in e.ledger.entries:
			kinds[String(en["kind"])] = true
		check(kinds.has("wage") and kinds.has("tax_income") and kinds.has("obl_rent"), tag + " proběhly mzdy, daně, nájem")

	section("Zachování peněz s burn pokladny a bez recyklace/mintu")
	var eb := _build(9, 12, {"treasury_burn_above": 20000, "recycle_sinks": false})
	eb.run_days(365)
	var rb := eb.conservation_report()
	check(bool(rb["ok"]) and int(rb["burned"]) > 0, "burn pokladny: oběh == vytvořeno − zničeno (zničeno > 0)", str(rb))
	var en2 := _build(10, 12, {"mint_on_shortfall": false})
	en2.run_days(365)
	check(bool(en2.conservation_report()["ok"]), "bez mintu na doplnění mezd zachování platí")
	check(int(en2.conservation_report()["minted"]) == int(en2.conservation_report()["ledger_total"]) + int(en2.conservation_report()["burned"]), "minted − burned == total")

	section("Determinismus")
	var a := _build(42, 8)
	a.run_days(365)
	var b := _build(42, 8)
	b.run_days(365)
	var c := _build(43, 8)
	c.run_days(365)
	check(a.state_hash() == b.state_hash(), "stejný seed -> stejný hash (%s)" % a.state_hash().substr(0, 12))
	check(JSON.stringify(a.to_dict(), "", true) == JSON.stringify(b.to_dict(), "", true), "stejný seed -> bit-identický to_dict (JSON)")
	check(a.ledger.head == b.ledger.head, "stejná hlava hash řetězce")
	check(a.state_hash() != c.state_hash(), "jiný seed -> jiný hash")
	check(a.ledger.head != c.ledger.head, "jiný seed -> jiná hlava řetězce")
	var r1: Dictionary = Demo.run_scenario(5, 8, 365)
	var r2: Dictionary = Demo.run_scenario(5, 8, 365)
	check(r1["hash"] == r2["hash"] and r1["rows"] == r2["rows"], "demo: stejný seed -> shodný hash i CSV řádky")
	# kontrolní bod uprostřed
	var half := _build(77, 10)
	half.run_days(150)
	var resumed: Economy = Economy.from_dict(JSON.parse_string(JSON.stringify(half.to_dict())))
	half.run_days(215)
	resumed.run_days(215)
	check(half.state_hash() == resumed.state_hash(), "uložit v den 150 přes JSON, obnovit, dojet do 365 == nepřerušený běh")

	section("Demo CSV pro laboratoř (8 agentů x 365 dní x 3 seedy)")
	var seeds_with_pressure := 0
	var any_detect := 0
	var any_default := 0
	var any_loan := 0
	var hashes := {}
	for s in [1, 2, 3]:
		var r: Dictionary = Demo.run_scenario(s, 8, 365)
		var rows: PackedStringArray = r["rows"]
		check(rows.size() == 8 * 365, "seed %d: %d řádků (8×365)" % [s, rows.size()])
		var cols := rows[0].split(",")
		check(cols.size() == Demo.CSV_HEADER.split(",").size(), "seed %d: počet sloupců odpovídá hlavičce" % s)
		check(rows[rows.size() - 1].begins_with("365,a07,"), "seed %d: poslední řádek je den 365, agent a07" % s)
		check(bool(r["conservation"]["ok"]), "seed %d: zachování peněz" % s)
		var eco: Economy = r["economy"]
		if int(r["metrics"]["mean_pressure_pm"]) > 0:
			seeds_with_pressure += 1
		any_detect += int(eco.stats["detections"])
		any_default += int(eco.stats["loans_defaulted"])
		any_loan += int(eco.stats["loans_issued"])
		hashes[r["hash"]] = true
	check(hashes.size() == 3, "tři seedy -> tři různé hashe")
	check(seeds_with_pressure == 3 and any_loan > 0 and any_detect > 0 and any_default > 0, "scénáře vykazují tlak, půjčky, odhalení i selhání půjček", "pressure=%d loans=%d detect=%d default=%d" % [seeds_with_pressure, any_loan, any_detect, any_default])

	section("Ledger totals a metriky po roce")
	var m := a.metrics()
	check(int(m["gini_pm"]) >= 0 and int(m["gini_pm"]) <= 1000, "Gini v 0..1")
	check(int(m["poverty_rate_pm"]) >= 0 and int(m["poverty_rate_pm"]) <= 1000, "míra chudoby v 0..1")
	check(int(m["money_supply"]) == int(a.conservation_report()["ledger_total"]), "money_supply == ledger_total")
	finish("test_economy_sim")
