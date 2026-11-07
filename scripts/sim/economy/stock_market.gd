extends RefCounted
## FIKTIVNÍ akciová burza nad izolovanou ekonomikou (economy.gd). Žádná reálná firma, ticker ani data; vše `game_balance`.
## Mechanismové pískoviště: ukazuje, co se v modelu stane při daných pravidlech; NENÍ to předpověď reálných trhů ani finanční rada.
##
## Zásady:
##  - Determinismus: vlastní RandomNumberGenerator (seed odvozený ze seedu ekonomiky), žádné globální náhody, žádný float ve stavu.
##    Ceny v millikr (1 kr = 1000), výnosy v ppm, váhy v pm, poplatky v bp; celočíselné dělení s ořezem k nule.
##  - Každá peněžní transakce jde přes ledger ekonomiky: trade_buy / trade_sell (protistrana `market:maker`), market_fee
##    (poplatek = propad `sink:market_fee`), tax_trade, dividend, tax_dividend. Dividendy se financují z účtu firmy (`firm:<ticker>`)
##    doplněného mintem (obdoba mzdových fondů zaměstnavatelů). Zákon zachování a hash-řetězec knihy zůstávají v platnosti.
##  - Počty akcií jsou celá čísla; žádný short, žádná páka (kromě volitelné marginové půjčky přes existující loan systém).
##  - Pozice jdou zpětně rekonstruovat z knihy (memo "TICKER|počet|cena") => audit_positions() odhalí ruční úpravu portfolia.
##  - Napojení na psychiku jen přes view() / Economy.agent_view; modul nikdy sám nespouští jednání agentů mimo obchodní pravidla.

const Ledger := preload("res://scripts/sim/economy/economy_ledger.gd")
const MCat := preload("res://scripts/sim/economy/market_catalog.gd")

const ACC_MAKER := "market:maker"
const SINK_FEE := "sink:market_fee"
const MODEL_VERSION := "market-m1-0.1"
const PX_SCALE := 1000          # millikr na kr
const PPM := 1000000
const HIST_MAX := 61
const EVENT_TYPES := ["path", "vol", "div_cut", "rates", "layoffs"]

var _eco: WeakRef
var rng := RandomNumberGenerator.new()
var cfg: Dictionary = {}
var firms: Array = []            # Array[Dictionary]
var firm_index: Dictionary = {}  # ticker -> pozice
var index_ppm: int = PPM         # rovnoměrně vážený index firem
var index_hist: Array = []
var portfolios: Dictionary = {}  # agent id -> Dictionary
var day: int = 0
var stats: Dictionary = {}
var manual_profiles: Dictionary = {}   # agent id -> profile id (předvolba před prvním dnem)


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


static func _blank_stats() -> Dictionary:
	return {"trades": 0, "buys": 0, "sells": 0, "volume": 0, "fees": 0, "trade_tax": 0, "dividends_gross": 0, "dividend_tax": 0,
		"dividends_net": 0, "rejected": 0, "dd_exit_sells": 0, "distress_sells": 0, "margin_calls": 0, "margin_loans": 0, "layoffs": 0}


func _init(p_eco: RefCounted = null, p_cfg: Dictionary = {}, p_bootstrap: bool = true) -> void:
	if p_eco != null:
		_eco = weakref(p_eco)
	cfg = (MCat.DEFAULT_CONFIG as Dictionary).duplicate(true)
	for k in p_cfg:
		cfg[k] = p_cfg[k]
	stats = _blank_stats()
	if not p_bootstrap:
		return
	var seed_value: int = 1
	if p_eco != null:
		seed_value = int(p_eco.seed_value)
	rng.seed = seed_value * 1000003 + 977
	var base: Array = cfg.get("firms", MCat.FIRMS)
	for f in base:
		var fd: Dictionary = (f as Dictionary).duplicate(true)
		fd["px_u"] = int(fd["px0_kr"]) * PX_SCALE
		fd["hist"] = [int(fd["px_u"])]
		fd["flow"] = 0
		firms.append(fd)
	_reindex()
	index_hist = [PPM]
	if p_eco != null:
		var cap: int = int(cfg["maker_capital"])
		if cap > 0:
			p_eco.ledger.post(0, "mint_market_capital", "world:mint", ACC_MAKER, cap, "market maker capital")


func attach(p_eco: RefCounted) -> void:
	_eco = weakref(p_eco)


func _e() -> RefCounted:
	return _eco.get_ref()


func _reindex() -> void:
	firm_index = {}
	for i in firms.size():
		firm_index[String((firms[i] as Dictionary)["id"])] = i


func _ci(key: String) -> int:
	return int(cfg[key])


# ---------------------------------------------------------------- ceny a signály

func tickers() -> Array:
	var out: Array = []
	for f in firms:
		out.append(String((f as Dictionary)["id"]))
	return out


func firm(tid: String) -> Dictionary:
	var i: int = int(firm_index.get(tid, -1))
	return {} if i < 0 else firms[i]


func price(tid: String) -> int:
	var i: int = int(firm_index.get(tid, -1))
	if i < 0:
		return 0
	return maxi(1, idiv(int((firms[i] as Dictionary)["px_u"]), PX_SCALE))


## Změna ceny firmy za posledních `window` dní v promilích (0, pokud historie chybí).
func firm_return_pm(tid: String, window: int) -> int:
	var f: Dictionary = firm(tid)
	if f.is_empty():
		return 0
	var h: Array = f["hist"]
	var last: int = int(h[h.size() - 1])
	var ref: int = int(h[maxi(0, h.size() - 1 - window)])
	return idiv((last - ref) * 1000, maxi(1, ref))


## Pokles od maxima za posledních `window` dní v promilích (0 = na maximu).
func firm_drawdown_pm(tid: String, window: int) -> int:
	var f: Dictionary = firm(tid)
	if f.is_empty():
		return 0
	var h: Array = f["hist"]
	var hi: int = 0
	for i in range(maxi(0, h.size() - 1 - window), h.size()):
		hi = maxi(hi, int(h[i]))
	return idiv((hi - int(h[h.size() - 1])) * 1000, maxi(1, hi))


func index_return_pm(window: int) -> int:
	var last: int = int(index_hist[index_hist.size() - 1])
	var ref: int = int(index_hist[maxi(0, index_hist.size() - 1 - window)])
	return idiv((last - ref) * 1000, maxi(1, ref))


## Přibližně normální náhoda se SD 1000 (součet čtyř rovnoměrných; celočíselně).
func _z() -> int:
	var s: int = 0
	for i in 4:
		s += rng.randi_range(-866, 866)
	return s


## Cesta šoku: v den k z n je kumulativní změna lineární (total_ppm * k / n) a denní výnos je podíl sousedních bodů,
## takže po n dnech je součin přesně (1 + total) až na zaokrouhlení.
static func path_step_ppm(total_ppm: int, n: int, k: int) -> int:
	if n <= 0 or k < 1 or k > n:
		return 0
	var c_prev: int = idiv(total_ppm * (k - 1), n)
	var c_now: int = idiv(total_ppm * k, n)
	return idiv((PPM + c_now) * PPM, maxi(1, PPM + c_prev)) - PPM


func _scope_hits(scope: String, f: Dictionary) -> bool:
	return scope == "" or scope == "market" or scope == String(f["sector"]) or scope == String(f["id"])


func _event_ppm(f: Dictionary, d: int) -> int:
	var sum: int = 0
	for evv in cfg["events"]:
		var ev: Dictionary = evv
		var t: String = String(ev["type"])
		var start: int = int(ev["day"])
		if t == "path":
			var n: int = int(ev["days"])
			if d >= start and d < start + n and _scope_hits(String(ev.get("scope", "market")), f):
				sum += path_step_ppm(int(ev["total_pm"]) * 1000, n, d - start + 1)
		elif (t == "rates" or t == "div_cut") and d == start and int(ev.get("price_pm", 0)) != 0 and _scope_hits(String(ev.get("scope", "market")), f):
			sum += int(ev["price_pm"]) * 1000
	return sum


func _vol_mult_pm(d: int) -> int:
	var m: int = 1000
	for evv in cfg["events"]:
		var ev: Dictionary = evv
		if String(ev["type"]) == "vol" and d >= int(ev["day"]) and d < int(ev["day"]) + int(ev["days"]):
			m = idiv(m * int(ev["mult_pm"]), 1000)
	return m


func _div_cut_pm(f: Dictionary, d: int) -> int:
	var keep: int = 1000
	for evv in cfg["events"]:
		var ev: Dictionary = evv
		if String(ev["type"]) != "div_cut" or d < int(ev["day"]):
			continue
		var days: int = int(ev.get("days", 0))
		if days > 0 and d >= int(ev["day"]) + days:
			continue
		if _scope_hits(String(ev.get("scope", "market")), f):
			keep = idiv(keep * (1000 - clampi(int(ev["cut_pm"]), 0, 1000)), 1000)
	return 1000 - keep


## Jednorázové události (dopad na konfiguraci ekonomiky / burzy). Volá se na začátku dne burzy.
func _oneshot_events() -> void:
	var eco: RefCounted = _e()
	for evv in cfg["events"]:
		var ev: Dictionary = evv
		if int(ev["day"]) != day:
			continue
		var t: String = String(ev["type"])
		if t == "rates":
			var add: int = int(ev.get("loan_rate_add_bp", 0))
			if add != 0 and eco != null:
				var tbl: Array = []
				for row in eco.config["loan_rate_table"]:
					tbl.append([int(row[0]), maxi(0, int(row[1]) + add)])
				eco.config["loan_rate_table"] = tbl
			if ev.has("trade_tax_bp"):
				cfg["trade_tax_bp"] = int(ev["trade_tax_bp"])
			if ev.has("div_tax_bp"):
				cfg["div_tax_bp"] = int(ev["div_tax_bp"])
			if ev.has("fee_bp"):
				cfg["fee_bp"] = int(ev["fee_bp"])
		elif t == "layoffs" and eco != null:
			_layoffs(eco, int(ev["share_pm"]))


## Vlna propouštění: deterministicky podle otisku (seed, id) se propustí podíl zaměstnaných. Volitelný spill-over scénáře.
func _layoffs(eco: RefCounted, share_pm: int) -> void:
	var ranked: Array = []
	for id in eco.agent_order:
		if String(eco.legal_job_of(String(id))) != "":
			ranked.append([_hash_pm(String(id), "layoff", 0), String(id)])
	ranked.sort()
	var n: int = idiv(ranked.size() * clampi(share_pm, 0, 1000), 1000)
	for i in n:
		var id2: String = String((ranked[i] as Array)[1])
		var j: String = String(eco.legal_job_of(id2))
		if j != "" and bool(eco.leave_job(id2, j)["ok"]):
			stats["layoffs"] = int(stats["layoffs"]) + 1


func _hash_pm(id: String, salt: String, slot: int) -> int:
	var seed_value: int = int(_e().seed_value) if _e() != null else 1
	var hx: String = Ledger.sha256_hex("market|%d|%s|%s" % [seed_value, id, salt])
	return idiv(("0x" + hx.substr(slot * 4, 4)).hex_to_int() * 1000, 65536)


func _update_prices() -> void:
	var vol: int = _vol_mult_pm(day)
	var z_m: int = _z()
	var z_s: Dictionary = {}
	for s in MCat.SECTORS:
		z_s[s] = _z()
	var m_ppm: int = idiv(idiv(_ci("market_sd_ppm") * z_m, 1000) * vol, 1000)
	var sum_r: int = 0
	var cap: int = _ci("impact_cap_ppm")
	for fv in firms:
		var f: Dictionary = fv
		var z_i: int = _z()
		var s_ppm: int = idiv(idiv(_ci("sector_sd_ppm") * int(z_s.get(String(f["sector"]), 0)), 1000) * vol, 1000)
		var i_ppm: int = idiv(idiv(int(f["idio_sd_ppm"]) * z_i, 1000) * vol, 1000)
		var impact: int = clampi(idiv(int(f["flow"]) * 100 * _ci("impact_pm_per_pct") * 1000, maxi(1, int(f["float"]))), -cap, cap)
		f["flow"] = 0
		var r: int = int(f["drift_ppm"]) + idiv(int(f["beta_pm"]) * m_ppm, 1000) + s_ppm + i_ppm + _event_ppm(f, day) + impact
		r = clampi(r, -500000, 500000)
		f["px_u"] = maxi(PX_SCALE, idiv(int(f["px_u"]) * (PPM + r), PPM))
		var h: Array = f["hist"]
		h.append(int(f["px_u"]))
		while h.size() > HIST_MAX:
			h.pop_front()
		sum_r += r
	index_ppm = idiv(index_ppm * (PPM + idiv(sum_r, maxi(1, firms.size()))), PPM)
	index_hist.append(index_ppm)
	while index_hist.size() > HIST_MAX:
		index_hist.pop_front()


# ---------------------------------------------------------------- portfolia a obchody

func _new_portfolio(id: String) -> Dictionary:
	return {"profile": "", "t_risk": 0, "t_impulse": 0, "t_lossav": 0, "t_indep": 0, "t_part": 0, "active": false, "offset": 0,
		"shares": {}, "basis": {}, "idx": PPM, "idx_peak": PPM, "mdd": 0, "idx_hist": [PPM], "pv_last": 0, "panic_until": 0,
		"entered": false, "cash_in": 0, "cash_out": 0, "div_net": 0, "realized": 0, "buy_value": 0, "sell_value": 0,
		"fees": 0, "taxes": 0, "buys": 0, "sells": 0, "sells_dd_exit": 0, "sells_distress": 0, "sells_margin": 0,
		"sells_other": 0, "dd_exit_events": 0, "basis_days": 0, "equity_days": 0, "days": 0, "margin_loans": [], "first_invest_day": 0}


func has_portfolio(id: String) -> bool:
	return portfolios.has(id)


func ensure_agent(id: String) -> Dictionary:
	if portfolios.has(id):
		return portfolios[id]
	var pf: Dictionary = _new_portfolio(id)
	var eco: RefCounted = _e()
	var a: Dictionary = eco.agents[id]
	var risk: int = _hash_pm(id, "traits", 0)
	var imp: int = _hash_pm(id, "traits", 1)
	var la: int = _hash_pm(id, "traits", 2)
	var ind: int = _hash_pm(id, "traits", 3)
	var part: int = _hash_pm(id, "traits", 4)
	# Vstupy, které ekonomika už má (kvalifikace, kredit, bydlení, záznam o odhalení, nelegální činnost) jen posouvají vlohy.
	risk += (int(a["skill"]) - 1) * 40 + idiv(int(a["credit"]) - 600, 8) + (50 if String(a["tier"]) == "house" else (-50 if String(a["tier"]) == "shared" else 0))
	imp += 60 * mini(3, int(a["record"]))
	if String(eco.illegal_job_of(id)) != "":
		risk += 150
		imp += 120
	pf["t_risk"] = clampi(risk, 0, 999)
	pf["t_impulse"] = clampi(imp, 0, 999)
	pf["t_lossav"] = la
	pf["t_indep"] = ind
	pf["t_part"] = part
	pf["offset"] = idiv(_hash_pm(id, "offset", 0) * 30, 1000)
	var prof: String = String(manual_profiles.get(id, ""))
	if prof == "":
		prof = derive_profile(pf)
	pf["profile"] = prof
	pf["active"] = true if manual_profiles.has(id) else (part < 750)
	portfolios[id] = pf
	return pf


## Pravidla odvození profilu z vloh (pm). Pořadí větví je dokumentované v docs/economy_market.md.
static func derive_profile(pf: Dictionary) -> String:
	var risk: int = int(pf["t_risk"])
	var imp: int = int(pf["t_impulse"])
	var la: int = int(pf["t_lossav"])
	var ind: int = int(pf["t_indep"])
	if imp >= 650 and risk >= 600:
		return "momentum"
	if imp >= 650:
		return "panic"
	if risk < 350:
		return "cautious"
	if imp < 250:
		return "passive"
	if ind >= 650 and risk >= 450:
		return "contrarian"
	if la >= 650:
		return "disposition"
	return "balanced"


## Předvolba profilu (před prvním dnem burzy). Agent se zároveň označí jako účastník.
func set_profile(id: String, profile_id: String) -> bool:
	if not (MCat.PROFILES as Dictionary).has(profile_id):
		return false
	manual_profiles[id] = profile_id
	if portfolios.has(id):
		(portfolios[id] as Dictionary)["profile"] = profile_id
		(portfolios[id] as Dictionary)["active"] = true
	return true


func profile_of(id: String) -> String:
	return String(ensure_agent(id)["profile"])


func shares_of(id: String, tid: String) -> int:
	if not portfolios.has(id):
		return 0
	return int(((portfolios[id] as Dictionary)["shares"] as Dictionary).get(tid, 0))


func portfolio_value(id: String) -> int:
	if not portfolios.has(id):
		return 0
	var v: int = 0
	var sh: Dictionary = (portfolios[id] as Dictionary)["shares"]
	for tid in sh:
		v += int(sh[tid]) * price(String(tid))
	return v


func portfolio_basis(id: String) -> int:
	if not portfolios.has(id):
		return 0
	var b: int = 0
	var bs: Dictionary = (portfolios[id] as Dictionary)["basis"]
	for tid in bs:
		b += int(bs[tid])
	return b


func fee_of(value: int) -> int:
	if value <= 0:
		return 0
	return maxi(_ci("fee_min"), idiv(value * _ci("fee_bp") + 9999, 10000))


func tax_of(value: int) -> int:
	return idiv(value * _ci("trade_tax_bp"), 10000)


func _reject(reason: String) -> Dictionary:
	stats["rejected"] = int(stats["rejected"]) + 1
	return {"ok": false, "reason": reason, "qty": 0, "price": 0, "fee": 0}


## Nákup `qty` celých akcií za denní cenu. Odmítne: neznámý agent/ticker, qty <= 0, nedostatek peněz (cena + poplatek + daň).
func buy(id: String, tid: String, qty: int, reason: String = "manual") -> Dictionary:
	var eco: RefCounted = _e()
	if eco == null or not eco.agents.has(id):
		return _reject("unknown_agent")
	if not firm_index.has(tid):
		return _reject("unknown_ticker")
	if qty <= 0:
		return _reject("bad_qty")
	var px: int = price(tid)
	var cost: int = px * qty
	var fee: int = fee_of(cost)
	var tax: int = tax_of(cost)
	if int(eco.balance(id)) < cost + fee + tax:
		return _reject("insufficient_funds")
	var pf: Dictionary = ensure_agent(id)
	var acc: String = eco.acct(id)
	var memo: String = "%s|%d|%d" % [tid, qty, px]
	eco.ledger.post(eco.day, "trade_buy", acc, ACC_MAKER, cost, memo)
	if fee > 0:
		eco.ledger.post(eco.day, "market_fee", acc, SINK_FEE, fee, memo)
	if tax > 0:
		eco.ledger.post(eco.day, "tax_trade", acc, "treasury", tax, memo)
	var sh: Dictionary = pf["shares"]
	var bs: Dictionary = pf["basis"]
	sh[tid] = int(sh.get(tid, 0)) + qty
	bs[tid] = int(bs.get(tid, 0)) + cost + fee + tax
	pf["cash_out"] = int(pf["cash_out"]) + cost + fee + tax
	pf["buy_value"] = int(pf["buy_value"]) + cost
	pf["fees"] = int(pf["fees"]) + fee
	pf["taxes"] = int(pf["taxes"]) + tax
	pf["buys"] = int(pf["buys"]) + 1
	if int(pf["first_invest_day"]) == 0:
		pf["first_invest_day"] = eco.day
	(firms[int(firm_index[tid])] as Dictionary)["flow"] = int((firms[int(firm_index[tid])] as Dictionary)["flow"]) + qty
	stats["trades"] = int(stats["trades"]) + 1
	stats["buys"] = int(stats["buys"]) + 1
	stats["volume"] = int(stats["volume"]) + cost
	stats["fees"] = int(stats["fees"]) + fee
	stats["trade_tax"] = int(stats["trade_tax"]) + tax
	return {"ok": true, "reason": "", "qty": qty, "price": px, "fee": fee}


## Prodej `qty` akcií, které agent drží (žádný short). Odmítne: nulová/nedostatečná pozice, qty <= 0, tvůrce trhu bez likvidity.
func sell(id: String, tid: String, qty: int, reason: String = "manual") -> Dictionary:
	var eco: RefCounted = _e()
	if eco == null or not eco.agents.has(id):
		return _reject("unknown_agent")
	if not firm_index.has(tid):
		return _reject("unknown_ticker")
	if qty <= 0:
		return _reject("bad_qty")
	var have: int = shares_of(id, tid)
	if have <= 0 or qty > have:
		return _reject("insufficient_shares")
	var px: int = price(tid)
	var proceeds: int = px * qty
	var fee: int = fee_of(proceeds)
	var tax: int = tax_of(proceeds)
	if fee + tax > proceeds:
		return _reject("fee_exceeds_proceeds")
	if int(eco.ledger.balance(ACC_MAKER)) < proceeds:
		if bool(cfg["maker_mint_on_shortfall"]):
			eco.ledger.post(eco.day, "mint_market_capital", "world:mint", ACC_MAKER, proceeds - int(eco.ledger.balance(ACC_MAKER)), "shortfall")
		else:
			return _reject("market_illiquid")
	var pf: Dictionary = portfolios[id]
	var acc: String = eco.acct(id)
	var memo: String = "%s|%d|%d" % [tid, qty, px]
	eco.ledger.post(eco.day, "trade_sell", ACC_MAKER, acc, proceeds, memo)
	if fee > 0:
		eco.ledger.post(eco.day, "market_fee", acc, SINK_FEE, fee, memo)
	if tax > 0:
		eco.ledger.post(eco.day, "tax_trade", acc, "treasury", tax, memo)
	var sh: Dictionary = pf["shares"]
	var bs: Dictionary = pf["basis"]
	var basis_all: int = int(bs.get(tid, 0))
	var basis_out: int = basis_all if qty == have else idiv(basis_all * qty, have)
	bs[tid] = basis_all - basis_out
	sh[tid] = have - qty
	pf["cash_in"] = int(pf["cash_in"]) + proceeds - fee - tax
	pf["realized"] = int(pf["realized"]) + proceeds - fee - tax - basis_out
	pf["sell_value"] = int(pf["sell_value"]) + proceeds
	pf["fees"] = int(pf["fees"]) + fee
	pf["taxes"] = int(pf["taxes"]) + tax
	pf["sells"] = int(pf["sells"]) + 1
	var rk: String = "sells_other"
	if reason == "dd_exit":
		rk = "sells_dd_exit"
		stats["dd_exit_sells"] = int(stats["dd_exit_sells"]) + 1
	elif reason == "distress":
		rk = "sells_distress"
		stats["distress_sells"] = int(stats["distress_sells"]) + 1
	elif reason == "margin":
		rk = "sells_margin"
	pf[rk] = int(pf[rk]) + 1
	(firms[int(firm_index[tid])] as Dictionary)["flow"] = int((firms[int(firm_index[tid])] as Dictionary)["flow"]) - qty
	stats["trades"] = int(stats["trades"]) + 1
	stats["sells"] = int(stats["sells"]) + 1
	stats["volume"] = int(stats["volume"]) + proceeds
	stats["fees"] = int(stats["fees"]) + fee
	stats["trade_tax"] = int(stats["trade_tax"]) + tax
	return {"ok": true, "reason": "", "qty": qty, "price": px, "fee": fee}


func _sell_all(id: String, reason: String) -> int:
	var n: int = 0
	for tid in tickers():
		var q: int = shares_of(id, tid)
		if q > 0 and bool(sell(id, tid, q, reason)["ok"]):
			n += 1
	return n


# ---------------------------------------------------------------- dividendy

func _pay_dividends() -> void:
	var eco: RefCounted = _e()
	var period: int = _ci("div_period")
	for i in firms.size():
		var f: Dictionary = firms[i]
		if day <= 0 or (day + i * 11) % period != 0:
			continue
		var cut: int = _div_cut_pm(f, day)
		var dps_u: int = idiv(idiv(int(f["px_u"]) * int(f["div_yield_pm"]) * period, 1000 * 365) * (1000 - cut), 1000)
		if dps_u <= 0:
			continue
		var facc: String = "firm:" + String(f["id"])
		for id in eco.agent_order:
			var q: int = shares_of(String(id), String(f["id"]))
			if q <= 0:
				continue
			var gross: int = idiv(q * dps_u, PX_SCALE)
			if gross <= 0:
				continue
			var tax: int = idiv(gross * _ci("div_tax_bp"), 10000)
			var net: int = gross - tax
			if int(eco.ledger.balance(facc)) < gross:
				eco.ledger.post(day, "mint_dividend_fund", "world:mint", facc, gross - int(eco.ledger.balance(facc)), String(f["id"]))
			var memo: String = "%s|%d" % [String(f["id"]), q]
			if net > 0:
				eco.ledger.post(day, "dividend", facc, eco.acct(String(id)), net, memo)
			if tax > 0:
				eco.ledger.post(day, "tax_dividend", facc, "treasury", tax, memo)
			eco._income(eco.agents[String(id)], net)
			var pf: Dictionary = portfolios[String(id)]
			pf["div_net"] = int(pf["div_net"]) + net
			pf["cash_in"] = int(pf["cash_in"]) + net
			pf["taxes"] = int(pf["taxes"]) + tax
			stats["dividends_gross"] = int(stats["dividends_gross"]) + gross
			stats["dividend_tax"] = int(stats["dividend_tax"]) + tax
			stats["dividends_net"] = int(stats["dividends_net"]) + net


# ---------------------------------------------------------------- rozhodování agentů

func _weights(kind: String, mom_regime: int, id: String = "") -> Dictionary:
	var w: Dictionary = {}
	var tk: Array = tickers()
	if kind == "defensive":
		var tot: int = 0
		for tid in tk:
			var v: int = maxi(100, 1600 - int(firm(tid)["beta_pm"]))
			w[tid] = v
			tot += v
		var acc: int = 0
		for tid in tk:
			w[tid] = idiv(int(w[tid]) * 1000, tot)
			acc += int(w[tid])
		w[tk[0]] = int(w[tk[0]]) + 1000 - acc
		return w
	if kind == "momentum":
		var pos: Array = []
		# Hystereze ±20 pm: nová pozice jen při výnosu > +2 %, držená pozice se opouští až při < −2 % (méně zbytečného obchodování).
		for tid in tk:
			var rr: int = firm_return_pm(tid, _ci("momentum_window"))
			if rr > 20 or (id != "" and shares_of(id, tid) > 0 and rr > -20):
				pos.append(tid)
		for tid in pos:
			w[tid] = idiv(1000, pos.size())
		return w
	if kind == "dip" and mom_regime < 0:
		var falls: Array = []
		var tot2: int = 0
		for tid in tk:
			var d: int = firm_drawdown_pm(tid, _ci("dip_window"))
			if d >= 100:
				falls.append([tid, d])
				tot2 += d
		if not falls.is_empty():
			for p in falls:
				w[String((p as Array)[0])] = idiv(int((p as Array)[1]) * 1000, tot2)
			return w
	for tid in tk:
		w[tid] = idiv(1000, tk.size())
	return w


## Rebalancování k cílovému podílu akcií. Nejdřív prodeje (jen je-li allow_sell), pak nákupy v pořadí tickerů.
func _rebalance(id: String, prm: Dictionary, target_pm: int, weights: Dictionary, allow_sell: bool, allow_margin: bool) -> void:
	var eco: RefCounted = _e()
	var burn: int = int(eco.daily_burn(id))
	var reserve: int = int(prm["reserve_days"]) * burn
	var bal: int = int(eco.balance(id))
	var pv: int = portfolio_value(id)
	var liquid: int = bal + pv
	var tgt_total: int = mini(idiv(liquid * target_pm, 1000), maxi(0, liquid - reserve))
	var band: int = maxi(100, idiv(liquid * _ci("rebalance_band_pm"), 1000))
	var tk: Array = tickers()
	if allow_sell:
		for tid in tk:
			var have: int = shares_of(id, tid)
			if have <= 0:
				continue
			var px: int = price(tid)
			var want: int = idiv(tgt_total * int(weights.get(tid, 0)), 1000)
			var diff: int = want - have * px
			if int(weights.get(tid, 0)) == 0:
				sell(id, tid, have, "rebalance")
			elif -diff > band:
				sell(id, tid, mini(have, idiv(-diff, px)), "rebalance")
	bal = int(eco.balance(id))
	pv = portfolio_value(id)
	var needs: Array = []
	var total_need: int = 0
	for tid in tk:
		var want2: int = idiv(tgt_total * int(weights.get(tid, 0)), 1000)
		var diff2: int = want2 - shares_of(id, tid) * price(tid)
		if diff2 > band:
			needs.append([tid, diff2])
			total_need += diff2
	if needs.is_empty():
		return
	var avail: int = int(eco.balance(id)) - reserve
	if allow_margin and bool(cfg["margin_enabled"]) and total_need > avail:
		var want_loan: int = mini(_ci("margin_borrow_cap"), total_need - maxi(0, avail))
		if want_loan >= 1000:
			var rl: Dictionary = eco.request_loan(id, want_loan)
			if bool(rl["ok"]):
				(portfolios[id]["margin_loans"] as Array).append(int(rl["loan_id"]))
				stats["margin_loans"] = int(stats["margin_loans"]) + 1
				avail = int(eco.balance(id)) - reserve
	for nd in needs:
		var tid2: String = String((nd as Array)[0])
		var px2: int = price(tid2)
		var q: int = idiv(int((nd as Array)[1]), px2)
		var unit: int = px2 + idiv(px2 * (_ci("fee_bp") + _ci("trade_tax_bp")), 10000) + 1
		q = mini(q, idiv(maxi(0, int(eco.balance(id)) - reserve), unit))
		var tries: int = 0
		while q > 0 and tries < 3:
			if bool(buy(id, tid2, q, "rebalance")["ok"]):
				break
			q -= 1
			tries += 1


func _distress(id: String) -> void:
	var eco: RefCounted = _e()
	var burn: int = int(eco.daily_burn(id))
	if int(eco.balance(id)) >= _ci("distress_days") * burn or portfolio_value(id) <= 0:
		return
	var tk: Array = tickers()
	var order: Array = []
	for tid in tk:
		var v: int = shares_of(id, tid) * price(tid)
		if v > 0:
			order.append([-v, tid])
	order.sort()
	for o in order:
		var need: int = _ci("restore_days") * burn - int(eco.balance(id))
		if need <= 0:
			break
		var tid2: String = String((o as Array)[1])
		var px: int = price(tid2)
		var q: int = mini(shares_of(id, tid2), idiv(need * 10000, maxi(1, px * (10000 - _ci("fee_bp") - _ci("trade_tax_bp")))) + 1)
		sell(id, tid2, q, "distress")


func _margin_check(id: String) -> void:
	var eco: RefCounted = _e()
	var pf: Dictionary = portfolios[id]
	var ml: Array = pf["margin_loans"]
	if ml.is_empty():
		return
	var keep: Array = []
	for lid in ml:
		var loan: Dictionary = {}
		for l in eco.loans:
			if int((l as Dictionary)["id"]) == int(lid):
				loan = l
		if loan.is_empty() or String(loan["status"]) == "paid":
			continue
		var owed: int = int(eco.loan_owed(loan))
		if portfolio_value(id) < idiv(owed * _ci("margin_call_pm"), 1000):
			stats["margin_calls"] = int(stats["margin_calls"]) + 1
			_sell_all(id, "margin")
			eco.repay_loan(id, int(lid), int(eco.balance(id)))
			if String(loan["status"]) == "paid":
				continue
		keep.append(lid)
	pf["margin_loans"] = keep


func _profile_step(id: String, pf: Dictionary, prm: Dictionary) -> void:
	var eco: RefCounted = _e()
	var held: bool = false
	for tid in tickers():
		if shares_of(id, tid) > 0:
			held = true
	# Výprodejní pravidlo (panika / stop): pokles hodnoty portfolia od maxima za okno => prodej všeho.
	var dd_pm: int = int(prm["dd_exit_pm"])
	if dd_pm > 0 and held and day >= int(pf["panic_until"]):
		var h: Array = pf["idx_hist"]
		var hi: int = 0
		for i in range(maxi(0, h.size() - 1 - _ci("dd_window")), h.size()):
			hi = maxi(hi, int(h[i]))
		var cur: int = int(h[h.size() - 1])
		if idiv((hi - cur) * 1000, maxi(1, hi)) >= dd_pm:
			_sell_all(id, "dd_exit")
			pf["dd_exit_events"] = int(pf["dd_exit_events"]) + 1
			pf["panic_until"] = day + int(prm.get("reenter_days", 30))
			return
	if day < int(pf["panic_until"]):
		return
	var cad: int = int(prm["cadence"])
	var due: bool = (not bool(pf["entered"])) if cad == 0 else ((day + int(pf["offset"])) % cad == 0)
	if not due:
		return
	if int(eco.balance(id)) + portfolio_value(id) < _ci("min_wealth_to_invest"):
		return
	var mom: int = index_return_pm(_ci("momentum_window"))
	var kind: String = String(prm["weights"])
	var target: int = int(prm["target_pm"])
	var regime: int = 0
	if prm.has("fomo_up_pm"):
		if mom >= int(prm["fomo_up_pm"]):
			target = int(prm["fomo_target_pm"])
			regime = 1
		elif mom <= int(prm["fomo_down_pm"]):
			target = int(prm["fear_target_pm"])
			regime = -1
	var pid: String = String(pf["profile"])
	if pid == "panic" and int(pf["dd_exit_events"]) > 0 and mom < 0 and not held:
		return   # po výprodeji se vrací až při nezáporném 20denním výnosu indexu
	if pid == "momentum":
		var w: Dictionary = _weights("momentum", regime, id)
		if w.is_empty():
			target = mini(target, int(prm["fear_target_pm"]))
		_rebalance(id, prm, target, w, true, regime > 0)
	elif pid == "contrarian":
		_rebalance(id, prm, target, _weights("dip", regime), true, false)
	elif pid == "disposition":
		for tid in tickers():
			var q: int = shares_of(id, tid)
			var b: int = int(pf["basis"].get(tid, 0))
			if q > 0 and b > 0 and idiv((q * price(tid) - b) * 1000, b) >= int(prm["take_profit_pm"]):
				sell(id, tid, q, "take_profit")
		_rebalance(id, prm, target, _weights("equal", 0), false, false)
	elif pid == "passive":
		_rebalance(id, prm, target, _weights("equal", 0), false, false)
		var any: bool = false
		for tid in tickers():
			if shares_of(id, tid) > 0:
				any = true
		pf["entered"] = any
	else:
		_rebalance(id, prm, target, _weights(kind, 0), true, false)


func _agent_mark(id: String, pf: Dictionary, div_before: int) -> void:
	# Časově vážená výnosnost „investiční složky“: hodnota dnes (před obchody) + dividendy / hodnota po včerejších obchodech.
	var pre: int = portfolio_value(id) + (int(pf["div_net"]) - div_before)
	var den: int = int(pf["pv_last"])
	if den > 0:
		pf["idx"] = idiv(int(pf["idx"]) * pre, den)
	pf["idx_peak"] = maxi(int(pf["idx_peak"]), int(pf["idx"]))
	pf["mdd"] = maxi(int(pf["mdd"]), idiv((int(pf["idx_peak"]) - int(pf["idx"])) * 1000, maxi(1, int(pf["idx_peak"]))))
	var h: Array = pf["idx_hist"]
	h.append(int(pf["idx"]))
	while h.size() > _ci("dd_window") + 1:
		h.pop_front()


func run_day() -> void:
	var eco: RefCounted = _e()
	if eco == null:
		return
	day = int(eco.day)
	if day < _ci("start_day"):
		return
	_oneshot_events()
	_update_prices()
	for id in eco.agent_order:
		ensure_agent(String(id))
	var divs0: Dictionary = {}
	for id in eco.agent_order:
		divs0[String(id)] = int((portfolios[String(id)] as Dictionary)["div_net"])
	_pay_dividends()
	for id in eco.agent_order:
		var sid: String = String(id)
		var pf: Dictionary = portfolios[sid]
		_agent_mark(sid, pf, int(divs0[sid]))
		if not bool(pf["active"]):
			continue
		_margin_check(sid)
		_distress(sid)
		_profile_step(sid, pf, (MCat.PROFILES as Dictionary)[String(pf["profile"])])
		var pv: int = portfolio_value(sid)
		pf["pv_last"] = pv
		pf["days"] = int(pf["days"]) + 1
		pf["basis_days"] = int(pf["basis_days"]) + portfolio_basis(sid)
		pf["equity_days"] = int(pf["equity_days"]) + idiv(pv * 1000, maxi(1, pv + int(eco.balance(sid))))


# ---------------------------------------------------------------- pohledy, metriky, audit

## Pro Economy.agent_view / psychiku: jen čtení.
func view(id: String) -> Dictionary:
	var pv: int = portfolio_value(id)
	var b: int = portfolio_basis(id)
	var eco: RefCounted = _e()
	var liq: int = pv + int(eco.balance(id))
	var pf: Dictionary = portfolios.get(id, {})
	var dd: int = 0
	if not pf.is_empty():
		var h: Array = pf["idx_hist"]
		var hi: int = 0
		for x in h:
			hi = maxi(hi, int(x))
		dd = idiv((hi - int(h[h.size() - 1])) * 1000, maxi(1, hi))
	return {"portfolio_value": pv, "equity_share_pm": idiv(pv * 1000, maxi(1, liq)),
		"unrealized_pm": idiv((pv - b) * 1000, b) if b > 0 else 0, "drawdown_pm": dd, "profile": String(pf.get("profile", ""))}


func net_wealth_mtm(id: String) -> int:
	var eco: RefCounted = _e()
	return int(eco.balance(id)) + portfolio_value(id) - int(eco.total_debt(id))


func in_poverty_mtm(id: String) -> bool:
	var eco: RefCounted = _e()
	return net_wealth_mtm(id) < int(eco.config["poverty_runway_days"]) * int(eco.daily_burn(id))


## Alternativní pohled na tlak: do rezervy se počítá i hodnota portfolia (hotovost + akcie). Herní konstrukt, ne validovaná míra.
func pressure_mtm_pm(id: String) -> int:
	var eco: RefCounted = _e()
	var c: Dictionary = eco.pressure_components(id)
	var runway: int = clampi(1000 - idiv((int(c["balance"]) + portfolio_value(id)) * 1000, int(c["daily_burn"]) * int(eco.config["pressure_runway_days"])), 0, 1000)
	var wr: int = int(eco.config["pressure_w_runway"])
	var wd: int = int(eco.config["pressure_w_debt"])
	var wm: int = int(eco.config["pressure_w_missed"])
	return clampi(idiv(wr * runway + wd * int(c["debt_pm"]) + wm * int(c["missed_pm"]), wr + wd + wm), 0, 1000)


## Pozice rekonstruované z knihy (trade_buy / trade_sell) porovná s evidencí portfolií a s protistranou.
func audit_positions() -> Dictionary:
	var eco: RefCounted = _e()
	var led: Dictionary = {}
	var maker_net: Dictionary = {}
	for en in eco.ledger.entries:
		var e: Dictionary = en
		var k: String = String(e["kind"])
		if k != "trade_buy" and k != "trade_sell":
			continue
		var parts: PackedStringArray = String(e["memo"]).split("|")
		if parts.size() != 3:
			return {"ok": false, "error": "bad_memo"}
		var sign: int = 1 if k == "trade_buy" else -1
		var acc: String = String(e["from"]) if k == "trade_buy" else String(e["to"])
		if not acc.begins_with("agent:"):
			return {"ok": false, "error": "bad_counterparty"}
		var aid: String = acc.substr(6)
		if not led.has(aid):
			led[aid] = {}
		var m: Dictionary = led[aid]
		m[parts[0]] = int(m.get(parts[0], 0)) + sign * int(parts[1])
	for aid in portfolios:
		var sh: Dictionary = (portfolios[aid] as Dictionary)["shares"]
		for tid in sh:
			var l: int = int((led.get(aid, {}) as Dictionary).get(tid, 0))
			if int(sh[tid]) != l:
				return {"ok": false, "error": "position_mismatch_%s_%s" % [aid, tid]}
			if int(sh[tid]) < 0:
				return {"ok": false, "error": "negative_position"}
	for aid in led:
		for tid in (led[aid] as Dictionary):
			var held: int = shares_of(String(aid), String(tid))
			if int((led[aid] as Dictionary)[tid]) != held:
				return {"ok": false, "error": "ledger_position_missing_%s_%s" % [aid, tid]}
	return {"ok": true, "error": ""}


## Souhrn + metriky jednoho agenta (celočíselně): pnl, TWR, drawdown, podíl panických prodejů…
func agent_summary(id: String) -> Dictionary:
	var pf: Dictionary = portfolios.get(id, {})
	if pf.is_empty():
		return {}
	var pv: int = portfolio_value(id)
	var sells: int = int(pf["sells"])
	var days: int = maxi(1, int(pf["days"]))
	return {"profile": pf["profile"], "pnl": pv + int(pf["cash_in"]) - int(pf["cash_out"]), "twr_pm": idiv((int(pf["idx"]) - PPM) * 1000, PPM),
		"mdd_pm": pf["mdd"], "pv": pv, "fees": pf["fees"], "taxes": pf["taxes"], "dividends": pf["div_net"], "buys": pf["buys"], "sells": sells,
		"dd_exit_sells": pf["sells_dd_exit"], "distress_sells": pf["sells_distress"], "margin_sells": pf["sells_margin"],
		"volume": int(pf["buy_value"]) + int(pf["sell_value"]), "avg_equity_pm": idiv(int(pf["equity_days"]), days),
		"avg_basis": idiv(int(pf["basis_days"]), days), "realized": pf["realized"]}


# ---------------------------------------------------------------- scénáře: kontrola

## Vrátí prázdný řetězec, když je seznam událostí platný; jinak popis chyby.
static func validate_events(events: Array) -> String:
	for i in events.size():
		if typeof(events[i]) != TYPE_DICTIONARY:
			return "event %d: není slovník" % i
		var ev: Dictionary = events[i]
		if not ev.has("type") or not EVENT_TYPES.has(String(ev["type"])):
			return "event %d: neznámý typ" % i
		if not ev.has("day") or int(ev["day"]) < 1:
			return "event %d: chybí day >= 1" % i
		var t: String = String(ev["type"])
		if t == "path" and (not ev.has("days") or int(ev["days"]) < 1 or not ev.has("total_pm") or int(ev["total_pm"]) <= -1000):
			return "event %d: path potřebuje days >= 1 a total_pm > -1000" % i
		if t == "vol" and (not ev.has("days") or int(ev["days"]) < 1 or not ev.has("mult_pm") or int(ev["mult_pm"]) < 100):
			return "event %d: vol potřebuje days >= 1 a mult_pm >= 100" % i
		if t == "div_cut" and not ev.has("cut_pm"):
			return "event %d: div_cut potřebuje cut_pm" % i
		if t == "layoffs" and not ev.has("share_pm"):
			return "event %d: layoffs potřebuje share_pm" % i
	return ""


# ---------------------------------------------------------------- serializace

func to_dict() -> Dictionary:
	return {"version": MODEL_VERSION, "cfg": cfg.duplicate(true), "rng_state": str(rng.state), "day": day, "firms": firms.duplicate(true),
		"index": index_ppm, "index_hist": index_hist.duplicate(), "portfolios": portfolios.duplicate(true), "stats": stats.duplicate(true),
		"manual_profiles": manual_profiles.duplicate(true)}


static func from_dict(d0: Dictionary, p_eco: RefCounted) -> RefCounted:
	var d: Dictionary = _norm(d0)
	var m: RefCounted = (load("res://scripts/sim/economy/stock_market.gd") as GDScript).new(p_eco, {}, false)
	m.cfg = d["cfg"]
	m.rng.seed = int(p_eco.seed_value) * 1000003 + 977
	m.rng.state = String(d["rng_state"]).to_int()
	m.day = int(d["day"])
	m.firms = d["firms"]
	m.index_ppm = int(d["index"])
	m.index_hist = d["index_hist"]
	m.portfolios = d["portfolios"]
	m.stats = d["stats"]
	m.manual_profiles = d.get("manual_profiles", {})
	m._reindex()
	return m
