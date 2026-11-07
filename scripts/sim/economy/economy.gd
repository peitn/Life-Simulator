extends RefCounted
## Jádro fiktivní ekonomiky (E0/E1): izolovaný, deterministický modul bez vazby na zbytek hry.
## Měna: fiktivní krejcar (kr), celá čísla. Hlavní kniha s řetězcem SHA-256 (economy_ledger.gd).
## Obsah: účty agentů, povolání (legální + abstraktní nelegální), povinnosti (jídlo/nájem/energie), půjčky a dluh
## (celočíselný úrok, minimální splátka, selhání = jen pokles kreditního skóre), daně (pásmové/rovné), vynucování
## (pravděpodobnost odhalení nelegálního příjmu -> pokuta/zabavení), metriky chudoby, financial_pressure().
##
## Determinismus: vlastní RandomNumberGenerator se seedem; žádné globální randf/randi, žádné float ve stavu.
## Finanční tíseň smí jen zvýšit tlak (financial_pressure); NIKDY sama nespouští škodlivé jednání agentů.
## Je to mechanismový pískoviště, ne předpověď reálné ekonomiky ani lidí (viz docs/economy.md).

const Ledger := preload("res://scripts/sim/economy/economy_ledger.gd")
const Catalog := preload("res://scripts/sim/economy/economy_catalog.gd")

const ACC_TREASURY := "treasury"
const ACC_BANK := "bank"
const ACC_UNDERGROUND := "underground"
const ACC_MINT := "world:mint"
const ACC_BURN := "world:burn"
const MODEL_VERSION := "economy-e1-0.1"
const LOG_DAYS := 28
const ARREARS_CATS := ["fine", "rent", "utilities"]

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var config: Dictionary = {}
var ledger: Ledger = Ledger.new()
var day: int = 0
var agents: Dictionary = {}       # id -> Dictionary
var agent_order: Array = []       # pořadí vložení (deterministická iterace)
var loans: Array = []             # Array[Dictionary]
var next_loan_id: int = 1
var stats: Dictionary = {}


@warning_ignore("integer_division")
static func idiv(a: int, b: int) -> int:
	return a / b


static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var o: Dictionary = {}
			for k in v:
				o[k] = _norm(v[k])
			return o
		TYPE_ARRAY:
			var arr: Array = []
			for x in v:
				arr.append(_norm(x))
			return arr
		TYPE_FLOAT:
			if is_finite(v) and floorf(v) == v:
				return int(v)
			return v
	return v


func _init(p_seed: int = 1, p_config: Dictionary = {}, p_bootstrap: bool = true) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	config = (Catalog.DEFAULT_CONFIG as Dictionary).duplicate(true)
	for k in p_config:
		config[k] = p_config[k]
	stats = _blank_stats()
	if p_bootstrap:
		var cap: int = _ci("bank_capital")
		if cap > 0:
			ledger.post(0, "mint_bank_capital", ACC_MINT, ACC_BANK, cap, "bank capital")


static func _blank_stats() -> Dictionary:
	return {"wages_paid": 0, "tax_collected": 0, "fines_levied": 0, "fines_paid": 0, "detections": 0, "loans_issued": 0,
		"loans_defaulted": 0, "loans_paid_off": 0, "missed_obligations": 0, "benefits_paid": 0, "hires": 0, "layoffs": 0,
		"loan_refused": 0, "underground_income": 0}


func _ci(key: String) -> int:
	return int(config[key])


# ---------------------------------------------------------------- katalog

func jobs_catalog() -> Dictionary:
	var j: Dictionary = (Catalog.JOBS as Dictionary).duplicate(true)
	var extra: Dictionary = config.get("extra_jobs", {})
	for k in extra:
		j[k] = extra[k]
	return j


func _job(job_id: String) -> Dictionary:
	var extra: Dictionary = config.get("extra_jobs", {})
	if extra.has(job_id):
		return extra[job_id]
	return (Catalog.JOBS as Dictionary).get(job_id, {})


func legal_job_ids() -> Array:
	var out: Array = []
	var c: Dictionary = jobs_catalog()
	var ks: Array = c.keys()
	ks.sort()
	for k in ks:
		if bool((c[k] as Dictionary)["legal"]):
			out.append(k)
	return out


func illegal_job_ids() -> Array:
	var out: Array = []
	var c: Dictionary = jobs_catalog()
	var ks: Array = c.keys()
	ks.sort()
	for k in ks:
		if not bool((c[k] as Dictionary)["legal"]):
			out.append(k)
	return out


func sectors() -> Array:
	var s: Dictionary = {}
	for jid in legal_job_ids():
		s[String(_job(jid)["sector"])] = true
	var out: Array = s.keys()
	out.sort()
	return out


static func acct(id: String) -> String:
	return "agent:" + id


# ---------------------------------------------------------------- účetní primitiva

func transfer(from_acc: String, to_acc: String, amount: int, kind: String = "transfer", memo: String = "") -> Dictionary:
	return ledger.post(day, kind, from_acc, to_acc, amount, memo)


func mint(to_acc: String, amount: int, memo: String = "", kind: String = "mint") -> Dictionary:
	return ledger.post(day, kind, ACC_MINT, to_acc, amount, memo)


func burn(from_acc: String, amount: int, memo: String = "", kind: String = "burn") -> Dictionary:
	return ledger.post(day, kind, from_acc, ACC_BURN, amount, memo)


func balance(id: String) -> int:
	return ledger.balance(acct(id))


func has_agent(id: String) -> bool:
	return agents.has(id)


# ---------------------------------------------------------------- agenti

## Přidá agenta. Volby (vše volitelné; náhodné hodnoty se losují VŽDY ve stejném pořadí => stabilní rng):
## household, tier ("shared"/"flat"/"house"), skill 0..3, shift_off 0..6, endowment (kr), job ("" = žádné), illegal ("" = žádné).
func add_agent(id: String, opts: Dictionary = {}) -> Dictionary:
	if id == "" or agents.has(id):
		return {"ok": false, "reason": "bad_or_duplicate_id"}
	var tier_i: int = rng.randi_range(0, Catalog.TIERS.size() - 1)
	var skill: int = rng.randi_range(0, 3)
	var endow: int = rng.randi_range(idiv(_ci("endowment_min"), 100), idiv(_ci("endowment_max"), 100)) * 100
	var employed_roll: bool = rng.randi_range(0, 9999) < _ci("employed_start_bp")
	var legal_ids: Array = legal_job_ids()
	var job_pick: int = rng.randi_range(0, legal_ids.size() - 1)
	var illegal_roll: bool = rng.randi_range(0, 9999) < _ci("illegal_share_bp")
	var ill_ids: Array = illegal_job_ids()
	var ill_pick: int = rng.randi_range(0, maxi(0, ill_ids.size() - 1))
	var shift_off: int = rng.randi_range(0, 6)
	var tier: String = String(opts.get("tier", Catalog.TIERS[tier_i]))
	if not (Catalog.HOUSING as Dictionary).has(tier):
		return {"ok": false, "reason": "bad_tier"}
	skill = int(opts.get("skill", skill))
	shift_off = int(opts.get("shift_off", shift_off))
	endow = int(opts.get("endowment", endow))
	var a: Dictionary = {
		"id": id, "household": String(opts.get("household", "h_" + id)), "tier": tier, "skill": skill,
		"shift_off": shift_off, "jobs": [], "wage_accrued": {}, "credit": _ci("credit_start"),
		"arrears": {"fine": 0, "rent": 0, "utilities": 0}, "exposure": 0, "record": 0, "cooldown_until": 0,
		"detections": 0, "income_log": [], "income_today": 0, "missed_log": [], "week_gross": 0, "week_tax": 0,
		"food_missed": 0,
	}
	agents[id] = a
	agent_order.append(id)
	if endow > 0:
		mint(acct(id), endow, "endowment", "mint_endowment")
	var want_job: String = ""
	if opts.has("job"):
		want_job = String(opts["job"])
	elif employed_roll:
		want_job = String(legal_ids[job_pick])
	if want_job != "":
		assign_job(id, want_job)
	var want_ill: String = ""
	if opts.has("illegal"):
		want_ill = String(opts["illegal"])
	elif illegal_roll and not ill_ids.is_empty():
		want_ill = String(ill_ids[ill_pick])
	if want_ill != "":
		assign_job(id, want_ill)
	return {"ok": true, "reason": ""}


func assign_job(id: String, job_id: String) -> Dictionary:
	if not agents.has(id):
		return {"ok": false, "reason": "unknown_agent"}
	var j: Dictionary = _job(job_id)
	if j.is_empty():
		return {"ok": false, "reason": "unknown_job"}
	var a: Dictionary = agents[id]
	var jobs: Array = a["jobs"]
	if jobs.has(job_id):
		return {"ok": false, "reason": "already_has_job"}
	for other in jobs:
		if bool(_job(String(other))["legal"]) == bool(j["legal"]):
			return {"ok": false, "reason": "already_has_job_of_that_kind"}
	if bool(j["legal"]) and int(a["skill"]) < int(j["skill_min"]):
		return {"ok": false, "reason": "skill_too_low"}
	jobs.append(job_id)
	if bool(j["legal"]):
		(a["wage_accrued"] as Dictionary)[job_id] = 0
	return {"ok": true, "reason": ""}


func leave_job(id: String, job_id: String) -> Dictionary:
	if not agents.has(id):
		return {"ok": false, "reason": "unknown_agent"}
	var a: Dictionary = agents[id]
	var jobs: Array = a["jobs"]
	if not jobs.has(job_id):
		return {"ok": false, "reason": "no_such_job"}
	if bool(_job(job_id)["legal"]):
		var acc: int = int((a["wage_accrued"] as Dictionary).get(job_id, 0))
		if acc > 0:
			_pay_wage(a, job_id, acc)
		(a["wage_accrued"] as Dictionary).erase(job_id)
	jobs.erase(job_id)
	return {"ok": true, "reason": ""}


func legal_job_of(id: String) -> String:
	for j in (agents[id] as Dictionary)["jobs"]:
		if bool(_job(String(j))["legal"]):
			return String(j)
	return ""


func illegal_job_of(id: String) -> String:
	for j in (agents[id] as Dictionary)["jobs"]:
		if not bool(_job(String(j))["legal"]):
			return String(j)
	return ""


# ---------------------------------------------------------------- daně

## Daň z hrubého příjmu za týden. Pravidlo zaokrouhlení: součet (úsek * sazba_bp) přes všechna pásma se dělí
## 10000 CELOČÍSELNĚ s oříznutím směrem k nule (floor) JEDNOU na konci => daň nikdy není vyšší než přesná hodnota.
func tax_on(gross: int) -> int:
	if gross <= 0:
		return 0
	var mode: String = String(config["tax_mode"])
	if mode == "none":
		return 0
	if mode == "flat":
		return idiv(gross * _ci("flat_rate_bp"), 10000)
	var lower: int = 0
	var sum_bp: int = 0
	for b in config["tax_brackets"]:
		var limit: int = int(b[0])
		var rate: int = int(b[1])
		var upper: int = gross if limit < 0 else mini(limit, gross)
		if upper > lower:
			sum_bp += (upper - lower) * rate
			lower = upper
		if limit < 0 or lower >= gross:
			break
	return idiv(sum_bp, 10000)


# ---------------------------------------------------------------- příjmy

func _income(a: Dictionary, amount: int) -> void:
	a["income_today"] = int(a["income_today"]) + amount


func _fund(acc: String, needed: int, kind: String) -> bool:
	var bal: int = ledger.balance(acc)
	if bal >= needed:
		return true
	if not bool(config["mint_on_shortfall"]):
		return false
	return bool(mint(acc, needed - bal, acc, kind)["ok"])


## Vyplatí hrubou mzdu; daň se strhává kumulativně v rámci týdne (součet daní za týden == tax_on(hrubý týden)).
func _pay_wage(a: Dictionary, job_id: String, gross: int) -> bool:
	if gross <= 0:
		return false
	var emp: String = "employer:" + String(_job(job_id)["sector"])
	if not _fund(emp, gross, "mint_wage_fund"):
		return false
	var new_total: int = tax_on(int(a["week_gross"]) + gross)
	var tax: int = maxi(0, new_total - int(a["week_tax"]))
	var net: int = gross - tax
	var id: String = String(a["id"])
	if net > 0:
		ledger.post(day, "wage", emp, acct(id), net, job_id + " gross=" + str(gross))
	if tax > 0:
		ledger.post(day, "tax_income", emp, ACC_TREASURY, tax, id)
	a["week_gross"] = int(a["week_gross"]) + gross
	a["week_tax"] = int(a["week_tax"]) + tax
	_income(a, net)
	stats["wages_paid"] = int(stats["wages_paid"]) + net
	stats["tax_collected"] = int(stats["tax_collected"]) + tax
	return true


func _work_day(a: Dictionary, shifts: int) -> bool:
	return (day + int(a["shift_off"])) % 7 < shifts


func _process_income(a: Dictionary) -> void:
	var id: String = String(a["id"])
	var dow: int = day % 7
	for jid in (a["jobs"] as Array).duplicate():
		var j: Dictionary = _job(String(jid))
		if bool(j["legal"]):
			var acc_d: Dictionary = a["wage_accrued"]
			if _work_day(a, int(j["shifts_per_week"])):
				acc_d[jid] = int(acc_d.get(jid, 0)) + int(j["hours_per_shift"]) * int(j["wage_per_hour"])
			var due: bool = String(j["pay_period"]) == "day" or dow == 6
			if due and int(acc_d.get(jid, 0)) > 0:
				if _pay_wage(a, String(jid), int(acc_d[jid])):
					acc_d[jid] = 0
		else:
			if day >= int(a["cooldown_until"]) and _work_day(a, int(j["shifts_per_week"])):
				var inc: int = rng.randi_range(int(j["income_min"]), int(j["income_max"]))
				if _fund(ACC_UNDERGROUND, inc, "mint_underground_fund"):
					ledger.post(day, "illegal_income", ACC_UNDERGROUND, acct(id), inc, String(jid))
					a["exposure"] = int(a["exposure"]) + inc
					_income(a, inc)
					stats["underground_income"] = int(stats["underground_income"]) + inc


# ---------------------------------------------------------------- vynucování

func _detect_params(a: Dictionary) -> Dictionary:
	var bp: int = -1
	var fine_pct: int = _ci("residual_fine_pct")
	var cd: int = _ci("residual_cooldown_days")
	for jid in a["jobs"]:
		var j: Dictionary = _job(String(jid))
		if not bool(j["legal"]):
			if int(j["detect_bp"]) > bp:
				bp = int(j["detect_bp"])
				fine_pct = int(j["fine_pct"])
				cd = int(j["cooldown_days"])
	if bp < 0:
		bp = _ci("residual_detect_bp")
	return {"bp": bp, "fine_pct": fine_pct, "cooldown": cd}


## Denní šance odhalení v bp pro agenta (0, pokud nemá neodhalený nelegální příjem).
func detection_bp(id: String) -> int:
	var a: Dictionary = agents[id]
	if int(a["exposure"]) <= 0:
		return 0
	var p: Dictionary = _detect_params(a)
	var bp: int = idiv(int(p["bp"]) * (100 + _ci("detect_record_bonus_pct") * int(a["record"])), 100)
	return mini(bp, maxi(_ci("detect_cap_bp"), int(p["bp"])))


func _process_enforcement(a: Dictionary) -> void:
	if int(a["exposure"]) <= 0:
		return
	var id: String = String(a["id"])
	var bp: int = detection_bp(id)
	if bp <= 0 or rng.randi_range(0, 9999) >= bp:
		return
	var p: Dictionary = _detect_params(a)
	var fine: int = idiv(int(a["exposure"]) * int(p["fine_pct"]), 100)
	var seized: int = mini(ledger.balance(acct(id)), fine)
	if seized > 0:
		ledger.post(day, "fine", acct(id), ACC_TREASURY, seized, "seizure exposure=" + str(a["exposure"]))
	var rest: int = fine - seized
	if rest > 0:
		var ar: Dictionary = a["arrears"]
		ar["fine"] = int(ar["fine"]) + rest
	a["exposure"] = 0
	a["record"] = int(a["record"]) + 1
	a["detections"] = int(a["detections"]) + 1
	a["cooldown_until"] = day + int(p["cooldown"])
	_credit(a, _ci("credit_fine"))
	stats["detections"] = int(stats["detections"]) + 1
	stats["fines_levied"] = int(stats["fines_levied"]) + fine
	stats["fines_paid"] = int(stats["fines_paid"]) + seized


func _credit(a: Dictionary, delta: int) -> void:
	a["credit"] = clampi(int(a["credit"]) + delta, 0, 1000)


# ---------------------------------------------------------------- povinnosti

func daily_burn(id: String) -> int:
	var h: Dictionary = (Catalog.HOUSING as Dictionary)[(agents[id] as Dictionary)["tier"]]
	return maxi(1, _ci("food_daily") + idiv(int(h["rent_weekly"]) + int(h["utilities_weekly"]), 7))


func _miss(a: Dictionary) -> void:
	(a["missed_log"] as Array).append(day)
	stats["missed_obligations"] = int(stats["missed_obligations"]) + 1


func _process_obligations(a: Dictionary) -> void:
	var id: String = String(a["id"])
	var dow: int = day % 7
	var h: Dictionary = (Catalog.HOUSING as Dictionary)[a["tier"]]
	var food: int = _ci("food_daily")
	if food > 0:
		if ledger.balance(acct(id)) >= food:
			ledger.post(day, "obl_food", acct(id), "sink:food", food, "")
		else:
			a["food_missed"] = int(a["food_missed"]) + 1
			_miss(a)
	if dow == _ci("rent_due_dow"):
		_pay_obligation(a, "rent", int(h["rent_weekly"]), "sink:rent")
	if dow == _ci("utilities_due_dow"):
		_pay_obligation(a, "utilities", int(h["utilities_weekly"]), "sink:utilities")


func _pay_obligation(a: Dictionary, cat: String, amount: int, sink: String) -> void:
	var id: String = String(a["id"])
	if ledger.balance(acct(id)) >= amount:
		ledger.post(day, "obl_" + cat, acct(id), sink, amount, "")
	else:
		var ar: Dictionary = a["arrears"]
		ar[cat] = int(ar[cat]) + amount
		_miss(a)


## Nedoplatky se splácejí jen z částky nad rezervou (arrears_reserve_days * denní výdaje), aby nevytlačily jídlo.
func _process_arrears(a: Dictionary) -> void:
	var id: String = String(a["id"])
	var ar: Dictionary = a["arrears"]
	for cat in ARREARS_CATS:
		var owed: int = int(ar[cat])
		if owed <= 0:
			continue
		var avail: int = ledger.balance(acct(id)) - _ci("arrears_reserve_days") * daily_burn(id)
		var pay: int = mini(avail, owed)
		if pay <= 0:
			continue
		var sink: String = ACC_TREASURY if cat == "fine" else "sink:" + cat
		ledger.post(day, "arrears_" + cat, acct(id), sink, pay, "")
		ar[cat] = owed - pay
		if cat == "fine":
			stats["fines_paid"] = int(stats["fines_paid"]) + pay


# ---------------------------------------------------------------- půjčky

func loans_of(id: String) -> Array:
	var out: Array = []
	for l in loans:
		if String((l as Dictionary)["borrower"]) == id:
			out.append(l)
	return out


func loan_owed(l: Dictionary) -> int:
	return int(l["balance"]) + int(l["accrued"])


func loan_debt(id: String) -> int:
	var s: int = 0
	for l in loans:
		var ld: Dictionary = l
		if String(ld["borrower"]) == id and String(ld["status"]) != "paid":
			s += loan_owed(ld)
	return s


func arrears_total(id: String) -> int:
	var s: int = 0
	for cat in ARREARS_CATS:
		s += int(((agents[id] as Dictionary)["arrears"] as Dictionary)[cat])
	return s


func total_debt(id: String) -> int:
	return loan_debt(id) + arrears_total(id)


func income28(id: String) -> int:
	var log: Array = (agents[id] as Dictionary)["income_log"]
	var s: int = 0
	for v in log:
		s += int(v)
	return idiv(s * LOG_DAYS, maxi(7, log.size()))


func loan_rate_bp(credit: int) -> int:
	for row in config["loan_rate_table"]:
		if credit >= int(row[0]):
			return int(row[1])
	return int((config["loan_rate_table"] as Array)[-1][1])


func loan_cap(id: String) -> int:
	return maxi(_ci("loan_starter_cap"), _ci("loan_income_multiple") * idiv(income28(id), 4))


func request_loan(id: String, amount: int) -> Dictionary:
	if not agents.has(id):
		return {"ok": false, "reason": "unknown_agent", "loan_id": 0}
	var a: Dictionary = agents[id]
	var reason: String = ""
	var active: int = 0
	for l in loans_of(id):
		if String((l as Dictionary)["status"]) == "active":
			active += 1
	if amount <= 0 or amount > _ci("loan_max"):
		reason = "bad_amount"
	elif int(a["credit"]) < _ci("loan_min_credit"):
		reason = "credit_too_low"
	elif active >= _ci("loan_max_active"):
		reason = "too_many_loans"
	elif total_debt(id) + amount > loan_cap(id):
		reason = "over_debt_cap"
	elif ledger.balance(ACC_BANK) < amount:
		reason = "bank_liquidity"
	if reason != "":
		stats["loan_refused"] = int(stats["loan_refused"]) + 1
		return {"ok": false, "reason": reason, "loan_id": 0}
	var lid: int = next_loan_id
	next_loan_id += 1
	loans.append({"id": lid, "borrower": id, "principal": amount, "balance": amount, "accrued": 0, "carry": 0,
		"rate_bp": loan_rate_bp(int(a["credit"])), "day": day, "next_due": day + _ci("loan_period_days"),
		"missed_consec": 0, "missed_total": 0, "status": "active", "paid_total": 0})
	ledger.post(day, "loan_disburse", ACC_BANK, acct(id), amount, "loan " + str(lid))
	stats["loans_issued"] = int(stats["loans_issued"]) + 1
	return {"ok": true, "reason": "", "loan_id": lid}


func _loan_pay(l: Dictionary, amount: int) -> int:
	var id: String = String(l["borrower"])
	var pay: int = mini(amount, loan_owed(l))
	pay = mini(pay, ledger.balance(acct(id)))
	if pay <= 0:
		return 0
	var interest: int = mini(pay, int(l["accrued"]))
	var principal: int = pay - interest
	if interest > 0:
		ledger.post(day, "loan_interest", acct(id), ACC_BANK, interest, "loan " + str(l["id"]))
	if principal > 0:
		ledger.post(day, "loan_principal", acct(id), ACC_BANK, principal, "loan " + str(l["id"]))
	l["accrued"] = int(l["accrued"]) - interest
	l["balance"] = int(l["balance"]) - principal
	l["paid_total"] = int(l["paid_total"]) + pay
	return pay


## Dobrovolná splátka (i částečná). Vrací skutečně zaplacenou částku.
func repay_loan(id: String, loan_id: int, amount: int) -> Dictionary:
	for l in loans:
		var ld: Dictionary = l
		if int(ld["id"]) == loan_id and String(ld["borrower"]) == id and String(ld["status"]) != "paid":
			var paid: int = _loan_pay(ld, amount)
			if loan_owed(ld) == 0:
				_close_loan(ld, paid > 0)
			return {"ok": true, "paid": paid}
	return {"ok": false, "paid": 0}


func _close_loan(l: Dictionary, bonus: bool) -> void:
	l["status"] = "paid"
	if bonus:
		_credit(agents[String(l["borrower"])], _ci("credit_paid_off"))
	stats["loans_paid_off"] = int(stats["loans_paid_off"]) + 1


func min_payment(l: Dictionary) -> int:
	var owed: int = loan_owed(l)
	var m: int = maxi(_ci("loan_min_floor"), idiv(owed * _ci("loan_min_pct_bp") + 9999, 10000))
	return mini(owed, m)


## Úrok: balance * rate_bp / (10000 * 365) denně, zbytek se přenáší (carry) => žádná ztráta zaokrouhlením.
func _accrue_interest(l: Dictionary) -> void:
	if String(l["status"]) != "active":
		return
	var total: int = int(l["balance"]) * int(l["rate_bp"]) + int(l["carry"])
	var den: int = 10000 * 365
	l["accrued"] = int(l["accrued"]) + idiv(total, den)
	l["carry"] = total % den


func _process_loans() -> void:
	for l in loans:
		var ld: Dictionary = l
		var st: String = String(ld["status"])
		if st == "paid":
			continue
		_accrue_interest(ld)
		if st != "active" or day < int(ld["next_due"]):
			continue
		var a: Dictionary = agents[String(ld["borrower"])]
		var due: int = min_payment(ld)
		if due > 0 and ledger.balance(acct(String(ld["borrower"]))) >= due:
			_loan_pay(ld, due)
			ld["missed_consec"] = 0
			_credit(a, _ci("credit_ontime"))
			if loan_owed(ld) == 0:
				_close_loan(ld, true)
		elif due > 0:
			ld["missed_consec"] = int(ld["missed_consec"]) + 1
			ld["missed_total"] = int(ld["missed_total"]) + 1
			_credit(a, _ci("credit_missed"))
			_miss(a)
			if int(ld["missed_consec"]) >= _ci("loan_default_after"):
				# Důsledek selhání = POUZE pokles skóre a zmrazení úroku; žádné zabavení, žádné jednání agenta.
				ld["status"] = "default"
				_credit(a, _ci("credit_default"))
				stats["loans_defaulted"] = int(stats["loans_defaulted"]) + 1
		ld["next_due"] = int(ld["next_due"]) + _ci("loan_period_days")


# ---------------------------------------------------------------- tlak, chudoba, metriky

## financial_pressure v promilích (0..1000), čistě celočíselně:
##   runway_pm = clamp(1000 - zůstatek*1000 / (denní_výdaje * pressure_runway_days), 0, 1000)
##   debt_pm   = clamp((dluh*1000 / příjem28) * 100 / pressure_debt_saturation_pct, 0, 1000)  (dluh>0 a příjem28=0 => 1000)
##   missed_pm = clamp(zmeškané_povinnosti_za_28_dní * 1000 / pressure_missed_saturation, 0, 1000)
##   total_pm  = (w_runway*runway_pm + w_debt*debt_pm + w_missed*missed_pm) / (w_runway+w_debt+w_missed)
func pressure_components(id: String) -> Dictionary:
	var a: Dictionary = agents[id]
	var burn: int = daily_burn(id)
	var bal: int = ledger.balance(acct(id))
	var runway_pm: int = clampi(1000 - idiv(bal * 1000, burn * _ci("pressure_runway_days")), 0, 1000)
	var debt: int = total_debt(id)
	var inc: int = income28(id)
	var debt_pm: int = 0
	if debt > 0:
		if inc <= 0:
			debt_pm = 1000
		else:
			debt_pm = clampi(idiv(idiv(debt * 1000, inc) * 100, _ci("pressure_debt_saturation_pct")), 0, 1000)
	var missed_n: int = 0
	for d in a["missed_log"]:
		if day - int(d) < LOG_DAYS:
			missed_n += 1
	var missed_pm: int = clampi(idiv(missed_n * 1000, _ci("pressure_missed_saturation")), 0, 1000)
	var wsum: int = _ci("pressure_w_runway") + _ci("pressure_w_debt") + _ci("pressure_w_missed")
	var total_pm: int = idiv(_ci("pressure_w_runway") * runway_pm + _ci("pressure_w_debt") * debt_pm + _ci("pressure_w_missed") * missed_pm, wsum)
	return {"runway_pm": runway_pm, "debt_pm": debt_pm, "missed_pm": missed_pm, "total_pm": clampi(total_pm, 0, 1000),
		"balance": bal, "debt": debt, "income28": inc, "missed_28d": missed_n, "daily_burn": burn}


func pressure_pm(id: String) -> int:
	return int(pressure_components(id)["total_pm"])


## 0..1 – vstup pro psychologii (jen tlak; nikdy automatické škodlivé jednání).
func financial_pressure(id: String) -> float:
	return float(pressure_pm(id)) / 1000.0


func net_wealth(id: String) -> int:
	return balance(id) - total_debt(id)


func in_poverty(id: String) -> bool:
	return net_wealth(id) < _ci("poverty_runway_days") * daily_burn(id)


## Giniho koeficient v promilích pro nezáporné celé číslo (vzestupné řazení): (2*Σ i*x_i − (n+1)*S) * 1000 / (n*S).
static func gini_pm(values: Array) -> int:
	var xs: Array = values.duplicate()
	xs.sort()
	var n: int = xs.size()
	var s: int = 0
	var w: int = 0
	for i in n:
		s += int(xs[i])
		w += (i + 1) * int(xs[i])
	if n == 0 or s <= 0:
		return 0
	return idiv((2 * w - (n + 1) * s) * 1000, n * s)


func metrics() -> Dictionary:
	var bals: Array = []
	var pov: int = 0
	var deep: int = 0
	var hi: int = 0
	var psum: int = 0
	var debt_sum: int = 0
	for id in agent_order:
		var b: int = balance(id)
		bals.append(b)
		if in_poverty(id):
			pov += 1
		if net_wealth(id) <= 0:
			deep += 1
		var p: int = pressure_pm(id)
		psum += p
		if p >= _ci("high_pressure_pm"):
			hi += 1
		debt_sum += total_debt(id)
	var n: int = agent_order.size()
	var sorted: Array = bals.duplicate()
	sorted.sort()
	var med: int = 0
	if n > 0:
		med = sorted[idiv(n, 2)] if n % 2 == 1 else idiv(int(sorted[idiv(n, 2) - 1]) + int(sorted[idiv(n, 2)]), 2)
	return {"agents": n, "gini_pm": gini_pm(bals), "poverty_rate_pm": idiv(pov * 1000, maxi(1, n)),
		"deep_poverty_rate_pm": idiv(deep * 1000, maxi(1, n)), "high_pressure_share_pm": idiv(hi * 1000, maxi(1, n)),
		"mean_pressure_pm": idiv(psum, maxi(1, n)), "median_balance": med, "total_agent_balance": _sum(bals),
		"total_debt": debt_sum, "money_supply": ledger.circulating(), "treasury": ledger.balance(ACC_TREASURY),
		"bank": ledger.balance(ACC_BANK)}


static func _sum(arr: Array) -> int:
	var s: int = 0
	for v in arr:
		s += int(v)
	return s


## Domácnosti: sdružený zůstatek/dluh, čisté jmění na hlavu a chudoba (na hlavu < poverty_runway_days * průměr denních výdajů).
func household_metrics() -> Dictionary:
	var hh: Dictionary = {}
	for id in agent_order:
		var hid: String = String((agents[id] as Dictionary)["household"])
		if not hh.has(hid):
			hh[hid] = {"members": 0, "balance": 0, "debt": 0, "burn": 0}
		var h: Dictionary = hh[hid]
		h["members"] = int(h["members"]) + 1
		h["balance"] = int(h["balance"]) + balance(id)
		h["debt"] = int(h["debt"]) + total_debt(id)
		h["burn"] = int(h["burn"]) + daily_burn(id)
	var out: Dictionary = {}
	for hid in hh:
		var h2: Dictionary = hh[hid]
		var m: int = int(h2["members"])
		var net: int = int(h2["balance"]) - int(h2["debt"])
		out[hid] = {"members": m, "balance": h2["balance"], "debt": h2["debt"], "net_per_capita": idiv(net, m),
			"in_poverty": idiv(net, m) < _ci("poverty_runway_days") * idiv(int(h2["burn"]), m)}
	return out


## Kontrola zachování peněz: peníze v oběhu (součet všech zůstatků mimo world:*) == vytvořeno − zničeno
## (nezávisle sečteno z historie) a přepočet zůstatků z řetězce sedí. Rozpad: agenti / instituce / propady (sinks).
func conservation_report() -> Dictionary:
	var agents_sum: int = 0
	var sinks_sum: int = 0
	var inst_sum: int = 0
	var world_sum: int = 0
	for k in ledger.accounts:
		var ks: String = String(k)
		var v: int = int(ledger.accounts[k])
		if Ledger.is_world(ks):
			world_sum += v
		elif ks.begins_with("agent:"):
			agents_sum += v
		elif ks.begins_with("sink:"):
			sinks_sum += v
		else:
			inst_sum += v
	var mb: Dictionary = ledger.minted_burned_from_entries()
	var circ: int = agents_sum + sinks_sum + inst_sum
	var vr: Dictionary = ledger.verify_report()
	return {"ok": circ == int(mb["net"]) and world_sum + circ == 0 and bool(vr["ok"]) and circ == ledger.circulating(),
		"agents": agents_sum, "sinks": sinks_sum, "institutions": inst_sum, "circulating": circ,
		"minted": mb["minted"], "burned": mb["burned"], "ledger_total": mb["net"], "world_sum": world_sum,
		"verify": vr["ok"], "entries": ledger.size()}


# ---------------------------------------------------------------- denní krok

func run_day() -> Dictionary:
	day += 1
	var dow: int = day % 7
	if dow == 0:
		for id in agent_order:
			var a0: Dictionary = agents[id]
			a0["week_gross"] = 0
			a0["week_tax"] = 0
	for id in agent_order:
		_process_income(agents[id])
	for id in agent_order:
		_process_enforcement(agents[id])
	for id in agent_order:
		_process_obligations(agents[id])
	for id in agent_order:
		_process_arrears(agents[id])
	_process_loans()
	if dow == 6:
		_weekly_state()
	if bool(config["auto_policy"]):
		for id in agent_order:
			_policy(agents[id])
	for id in agent_order:
		var a: Dictionary = agents[id]
		var lg: Array = a["income_log"]
		lg.append(int(a["income_today"]))
		a["income_today"] = 0
		while lg.size() > LOG_DAYS:
			lg.pop_front()
		var ml: Array = a["missed_log"]
		while not ml.is_empty() and day - int(ml[0]) >= LOG_DAYS:
			ml.pop_front()
	return {"day": day, "circulating": ledger.circulating(), "entries": ledger.size()}


func run_days(n: int) -> void:
	for i in n:
		run_day()


## Týdenní tok: dávka nezaměstnaným z pokladny, recyklace propadů do zaměstnavatelských účtů, volitelné spálení přebytku.
func _weekly_state() -> void:
	var ben: int = _ci("benefit_weekly")
	if ben > 0:
		for id in agent_order:
			var a: Dictionary = agents[id]
			if (a["jobs"] as Array).is_empty():
				var pay: int = mini(ben, ledger.balance(ACC_TREASURY))
				if pay > 0:
					ledger.post(day, "benefit", ACC_TREASURY, acct(id), pay, "unemployment")
					_income(a, pay)
					stats["benefits_paid"] = int(stats["benefits_paid"]) + pay
	if bool(config["recycle_sinks"]):
		var secs: Array = sectors()
		for s in Catalog.SINKS:
			var bal: int = ledger.balance(String(s))
			if bal <= 0 or secs.is_empty():
				continue
			var share: int = idiv(bal, secs.size())
			var rem: int = bal - share * secs.size()
			for i in secs.size():
				var amt: int = share + (rem if i == 0 else 0)
				if amt > 0:
					ledger.post(day, "recycle", String(s), "employer:" + String(secs[i]), amt, "")
	var cap: int = _ci("treasury_burn_above")
	if cap > 0 and ledger.balance(ACC_TREASURY) > cap:
		burn(ACC_TREASURY, ledger.balance(ACC_TREASURY) - cap, "treasury surplus", "burn_treasury")


## Jednoduchá sandbox politika (nahraditelná rozhodováním sim_agent): hledání/ztráta práce, půjčka při nízké rezervě,
## splácení zmrazené půjčky z přebytku. Finanční tíseň sama NEVYVOLÁVÁ žádné škodlivé jednání (ani vstup do nelegální práce).
func _policy(a: Dictionary) -> void:
	var id: String = String(a["id"])
	var legal: String = legal_job_of(id)
	if legal == "":
		if rng.randi_range(0, 9999) < _ci("hire_bp"):
			var ids: Array = legal_job_ids()
			var pick: int = rng.randi_range(0, ids.size() - 1)
			if assign_job(id, String(ids[pick]))["ok"]:
				stats["hires"] = int(stats["hires"]) + 1
	elif rng.randi_range(0, 9999) < _ci("layoff_bp"):
		leave_job(id, legal)
		stats["layoffs"] = int(stats["layoffs"]) + 1
	var burn_d: int = daily_burn(id)
	if balance(id) < _ci("borrow_runway_days") * burn_d:
		request_loan(id, mini(_ci("loan_max"), _ci("borrow_days_of_cost") * burn_d))
	var surplus: int = balance(id) - _ci("surplus_repay_days") * burn_d
	if surplus > 0:
		for l in loans_of(id):
			var ld: Dictionary = l
			if String(ld["status"]) == "default" and surplus > 0:
				surplus -= int(repay_loan(id, int(ld["id"]), surplus)["paid"])


# ---------------------------------------------------------------- serializace

func to_dict() -> Dictionary:
	var ags: Array = []
	for id in agent_order:
		ags.append((agents[id] as Dictionary).duplicate(true))
	return {"version": MODEL_VERSION, "seed": seed_value, "rng_state": str(rng.state), "config": config.duplicate(true),
		"day": day, "agents": ags, "loans": loans.duplicate(true), "next_loan_id": next_loan_id,
		"stats": stats.duplicate(true), "ledger": ledger.to_dict()}


static func from_dict(d0: Dictionary) -> RefCounted:
	var d: Dictionary = _norm(d0)
	var e: RefCounted = (load("res://scripts/sim/economy/economy.gd") as GDScript).new(int(d["seed"]), {}, false)
	e.config = d["config"]
	e.rng.seed = int(d["seed"])
	e.rng.state = String(d["rng_state"]).to_int()
	e.day = int(d["day"])
	for a in d["agents"]:
		e.agents[String(a["id"])] = a
		e.agent_order.append(String(a["id"]))
	e.loans = d["loans"]
	e.next_loan_id = int(d["next_loan_id"])
	e.stats = d["stats"]
	e.ledger = Ledger.from_dict(d["ledger"])
	return e


## Stabilní otisk stavu: SHA-256 z (hlava řetězce + počet záznamů + kanonický JSON všeho ostatního).
func state_hash() -> String:
	var d: Dictionary = to_dict()
	var led: Dictionary = d["ledger"]
	d["ledger"] = {"accounts": led["accounts"], "head": led["head"], "count": (led["entries"] as Array).size()}
	return Ledger.sha256_hex(JSON.stringify(d, "", true))


## Řádek pro CSV / pohled pro sim_agent.
func agent_view(id: String) -> Dictionary:
	var c: Dictionary = pressure_components(id)
	var a: Dictionary = agents[id]
	return {"balance": c["balance"], "debt": c["debt"], "financial_pressure": float(c["total_pm"]) / 1000.0,
		"pressure_pm": c["total_pm"], "runway_pm": c["runway_pm"], "debt_pm": c["debt_pm"], "missed_pm": c["missed_pm"],
		"employed": legal_job_of(id) != "", "illegal_active": illegal_job_of(id) != "" and day >= int(a["cooldown_until"]),
		"credit": a["credit"], "in_poverty": in_poverty(id), "arrears": arrears_total(id)}
