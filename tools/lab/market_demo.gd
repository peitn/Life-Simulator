extends Node
## Fiktivní burza – headless demo: profil × scénář × seed -> tabulka v logu + CSV pro analýzu.
## Spuštění: godot --headless --path . res://tools/lab/market_demo.tscn -- --seeds=1,2,3 --per=6 --days=240 --out=/cesta [--margin] [--scenarios=crash,bear]
## CSV: market_runs.csv (seed×scénář×profil), market_population.csv (seed×scénář), market_summary.csv (průměry přes seedy).
## Vše je fiktivní mechanismový experiment (game_balance); nepředpovídá reálné trhy ani lidi (docs/economy_market.md).
const Lab := preload("res://scripts/sim/economy/market_lab.gd")
const MCat := preload("res://scripts/sim/economy/market_catalog.gd")

const RUN_COLS := ["n", "twr_pm", "mdd_pm", "pnl", "pnl_on_capital_pm", "fees", "volume", "trades", "sells", "dd_exit_sells",
	"panic_sell_share_pm", "distress_sells", "avg_equity_pm", "dividends", "pressure_pre", "pressure_post", "pressure_mtm_pre",
	"pressure_mtm_post", "poverty_pre_pm", "poverty_post_pm", "poverty_mtm_pre_pm", "poverty_mtm_post_pm", "debt_pre_pm",
	"debt_post_pm", "wealth_pre", "wealth_post", "wealth_change", "employed_post_pm"]
const POP_COLS := ["gini_pre_pm", "gini_post_pm", "index_pre", "index_min", "index_post", "index_trough_pm", "index_end_pm", "volume",
	"trades", "fees", "dd_exit_sells", "distress_sells", "margin_calls", "treasury"]


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var seeds: Array = [1, 2, 3]
	var per := 6
	var days := 240
	var out_dir := ""
	var margin := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = []
			for t in a.trim_prefix("--seeds=").split(",", false):
				seeds.append(int(t))
		elif a.begins_with("--per="):
			per = clampi(int(a.trim_prefix("--per=")), 1, 40)
		elif a.begins_with("--days="):
			days = clampi(int(a.trim_prefix("--days=")), 120, 2000)
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--scenarios="):
			for t in a.trim_prefix("--scenarios=").split(",", false):
				only.append(String(t))
		elif a == "--margin":
			margin = true
	var sc: Dictionary = Lab.load_scenarios()
	if not bool(sc["ok"]):
		printerr("market_demo: scénáře: ", sc["error"])
		get_tree().quit(2)
		return
	var scen: Array = []
	for s in sc["scenarios"]:
		if only.is_empty() or only.has(String(s["id"])):
			scen.append(s)
	var runs_csv := PackedStringArray(["seed,scenario,profile," + ",".join(RUN_COLS)])
	var pop_csv := PackedStringArray(["seed,scenario,hash12," + ",".join(POP_COLS) + ",conservation_ok,positions_ok"])
	var acc: Dictionary = {}     # "scenario|profile" -> {col -> [values]}
	var all_ok := true
	var t0 := Time.get_ticks_msec()
	for s in seeds:
		for sd in scen:
			var r: Dictionary = Lab.run(int(s), sd, {"per_profile": per, "days": days, "margin": margin})
			all_ok = all_ok and bool(r["conservation_ok"]) and bool(r["positions_ok"])
			var pop: Dictionary = r["pop"]
			var pv: Array = []
			for c in POP_COLS:
				pv.append(str(pop[c]))
			pop_csv.append("%d,%s,%s,%s,%d,%d" % [int(s), sd["id"], String(r["hash"]).substr(0, 12), ",".join(pv), 1 if r["conservation_ok"] else 0, 1 if r["positions_ok"] else 0])
			for p in MCat.PROFILE_IDS:
				var m: Dictionary = r["profiles"][p]
				var vals: Array = []
				for c in RUN_COLS:
					vals.append(str(m[c]))
					var key := "%s|%s" % [sd["id"], p]
					if not acc.has(key):
						acc[key] = {}
					if not (acc[key] as Dictionary).has(c):
						acc[key][c] = []
					(acc[key][c] as Array).append(int(m[c]))
				runs_csv.append("%d,%s,%s,%s" % [int(s), sd["id"], p, ",".join(vals)])
			print("MARKET seed=%d scenario=%s hash=%s conservation=%s positions=%s trades=%d index_trough=%.1f%% t=%.1fs" % [int(s), sd["id"],
				String(r["hash"]).substr(0, 12), str(r["conservation_ok"]), str(r["positions_ok"]), int(pop["trades"]),
				float(pop["index_trough_pm"]) / 10.0, float(Time.get_ticks_msec() - t0) / 1000.0])
	var sum_csv := PackedStringArray(["scenario,profile,seeds," + ",".join(RUN_COLS)])
	for sd in scen:
		for p in MCat.PROFILE_IDS:
			var key := "%s|%s" % [sd["id"], p]
			var row: Array = []
			for c in RUN_COLS:
				var arr: Array = acc[key][c]
				var tot := 0
				for v in arr:
					tot += int(v)
				row.append("%.1f" % (float(tot) / float(arr.size())))
			sum_csv.append("%s,%s,%d,%s" % [sd["id"], p, seeds.size(), ",".join(row)])
	_table("Průměrná časově vážená výnosnost investiční složky (promile)", "twr_pm", scen, acc)
	_table("Průměrný max drawdown (promile)", "mdd_pm", scen, acc)
	_table("Podíl panických (drawdown-exit) prodejů na všech prodejích (promile)", "panic_sell_share_pm", scen, acc)
	_table("Objem obchodů na agenta (kr)", "volume", scen, acc)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		for pair in [["market_runs.csv", runs_csv], ["market_population.csv", pop_csv], ["market_summary.csv", sum_csv]]:
			var f := FileAccess.open(out_dir.path_join(String(pair[0])), FileAccess.WRITE)
			if f == null:
				printerr("market_demo: nelze zapsat do ", out_dir)
				get_tree().quit(3)
				return
			for line in (pair[1] as PackedStringArray):
				f.store_line(line)
			f.close()
	print("MARKET_DONE ok=%s runs=%d seconds=%.1f" % [str(all_ok), seeds.size() * scen.size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(0 if all_ok else 1)


func _table(title: String, col: String, scen: Array, acc: Dictionary) -> void:
	print("\n== " + title)
	var head := "%-12s" % "profil"
	for sd in scen:
		head += " %13s" % String(sd["id"]).left(13)
	print(head)
	for p in MCat.PROFILE_IDS:
		var line := "%-12s" % p
		for sd in scen:
			var arr: Array = acc["%s|%s" % [sd["id"], p]][col]
			var tot := 0
			for v in arr:
				tot += int(v)
			line += " %13.1f" % (float(tot) / float(arr.size()))
		print(line)
