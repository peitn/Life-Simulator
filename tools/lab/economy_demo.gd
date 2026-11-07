extends Node
## Ekonomika E1 – headless demo: N agentů x D dní x několik seedů -> CSV pro laboratoř.
## Spuštění: godot --headless --path . res://tools/lab/economy_demo.tscn -- --seeds=1,2,3 --agents=8 --days=365 --out=/cesta/adresar
## CSV (jeden soubor na seed): day,agent,balance,debt,financial_pressure,employed,illegal_active,credit,in_poverty
## (day = konec herního dne 1..D; částky v krejcarech; financial_pressure 0..1 na 3 desetinná místa).
## Vše fiktivní; mechanismový pískoviště, ne předpověď reálných lidí (docs/economy.md).
const Economy := preload("res://scripts/sim/economy/economy.gd")
const CSV_HEADER := "day,agent,balance,debt,financial_pressure,employed,illegal_active,credit,in_poverty"


## Čistá funkce (použitelná i z testů): vrací {"seed","rows": PackedStringArray (CSV bez hlavičky),"hash","metrics","conservation","economy"}.
static func run_scenario(p_seed: int, n_agents: int, n_days: int, cfg: Dictionary = {}) -> Dictionary:
	var eco: RefCounted = Economy.new(p_seed, cfg)
	for i in n_agents:
		eco.add_agent("a%02d" % i)
	var rows := PackedStringArray()
	for d in n_days:
		eco.run_day()
		for id in eco.agent_order:
			var v: Dictionary = eco.agent_view(String(id))
			rows.append("%d,%s,%d,%d,%.3f,%d,%d,%d,%d" % [eco.day, id, v["balance"], v["debt"], v["financial_pressure"],
				1 if v["employed"] else 0, 1 if v["illegal_active"] else 0, v["credit"], 1 if v["in_poverty"] else 0])
	return {"seed": p_seed, "rows": rows, "hash": eco.state_hash(), "metrics": eco.metrics(),
		"conservation": eco.conservation_report(), "economy": eco}


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var seeds: Array = [1, 2, 3]
	var n_agents := 8
	var n_days := 365
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = []
			for t in a.trim_prefix("--seeds=").split(",", false):
				seeds.append(int(t))
		elif a.begins_with("--agents="):
			n_agents = clampi(int(a.trim_prefix("--agents=")), 1, 200)
		elif a.begins_with("--days="):
			n_days = clampi(int(a.trim_prefix("--days=")), 1, 3650)
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	var summary: Array = []
	var all_ok := true
	for s in seeds:
		var r: Dictionary = run_scenario(int(s), n_agents, n_days)
		var m: Dictionary = r["metrics"]
		var c: Dictionary = r["conservation"]
		var eco: RefCounted = r["economy"]
		print("ECON seed=%d hash=%s gini=%.3f poverty=%.3f pressure=%.3f supply=%d conservation=%s detections=%d loans=%d defaults=%d" % [
			int(s), String(r["hash"]).substr(0, 12), float(m["gini_pm"]) / 1000.0, float(m["poverty_rate_pm"]) / 1000.0,
			float(m["mean_pressure_pm"]) / 1000.0, int(m["money_supply"]), str(c["ok"]), int(eco.stats["detections"]),
			int(eco.stats["loans_issued"]), int(eco.stats["loans_defaulted"])])
		all_ok = all_ok and bool(c["ok"])
		summary.append({"seed": int(s), "hash": r["hash"], "metrics": m, "conservation_ok": c["ok"], "stats": eco.stats})
		if out_dir != "":
			DirAccess.make_dir_recursive_absolute(out_dir)
			var f := FileAccess.open(out_dir.path_join("economy_seed%d.csv" % int(s)), FileAccess.WRITE)
			if f == null:
				printerr("economy_demo: nelze zapsat do ", out_dir)
				get_tree().quit(3)
				return
			f.store_line(CSV_HEADER)
			for row in r["rows"]:
				f.store_line(row)
			f.close()
	if out_dir != "":
		var sf := FileAccess.open(out_dir.path_join("economy_summary.json"), FileAccess.WRITE)
		if sf != null:
			sf.store_string(JSON.stringify(summary, " ", true))
			sf.close()
	print("ECON_DONE ok=%s" % str(all_ok))
	get_tree().quit(0 if all_ok else 1)
