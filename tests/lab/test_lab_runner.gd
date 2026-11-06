extends "res://tests/test_base.gd"
## Laboratoř M1a: stejný seed = shodný hash, jiný seed = jiný průběh, validace scénáře, tvar snímků.
const Runner := preload("res://tools/lab/lab_runner.gd")


func _ready() -> void:
	watchdog_seconds = 100.0
	_run.call_deferred()


func _run() -> void:
	section("Validace scénáře")
	check(not Runner.validate({"seed": 1, "days": 2}).size() > 0, "platný scénář")
	check(Runner.validate({"seed": "x", "days": 2}).size() == 1, "seed musí být celé číslo")
	check(Runner.validate({"seed": 101.0, "days": 14.0, "snapshot_hours": 24.0}).is_empty(), "celá čísla z JSON (float) projdou")
	check(Runner.validate({"seed": 1.5, "days": 2}).size() == 1, "seed 1.5 je neplatný")
	check(Runner.validate({"seed": 1, "days": 0}).size() == 1, "days 0 je neplatné")
	check(Runner.validate({"seed": 1, "days": 99}).size() == 1, "days 99 je neplatné")
	check(Runner.validate({"seed": 1, "days": 2, "snapshot_hours": 7}).size() == 1, "snapshot_hours musí dělit 24")
	var bad: Dictionary = await Runner.run(self, {"seed": 1, "days": 0})
	check(not bad["ok"], "neplatný scénář se nespustí")

	section("Opakovatelnost (3 dny, 3 agenti)")
	var sc := {"name": "t", "seed": 3, "days": 3, "snapshot_hours": 12}
	var a: Dictionary = await Runner.run(self, sc)
	var b: Dictionary = await Runner.run(self, sc)
	var c: Dictionary = await Runner.run(self, {"name": "t", "seed": 4, "days": 3, "snapshot_hours": 12})
	check(a["ok"] and b["ok"] and c["ok"], "tři běhy proběhly")
	check(a["agents"].size() == 3, "výchozí domácnost má 3 agenty", str(a["agents"]))
	check(a["final_hash"] == b["final_hash"], "stejný seed → shodný hash konečného stavu")
	check(JSON.stringify(a["snapshots"]) == JSON.stringify(b["snapshots"]), "stejný seed → shodné všechny snímky")
	check(a["final_hash"] != c["final_hash"], "jiný seed → jiný průběh")

	section("Tvar snímků a rozumné hodnoty")
	var snaps: Array = a["snapshots"]
	check(snaps.size() == 1 + 3 * 2, "snímek na začátku + každých 12 h (7)", str(snaps.size()))
	check(float(snaps[-1]["day"]) == 3.0, "poslední snímek je v den 3")
	var finite := true
	for s in snaps:
		for nm in s["agents"]:
			var ag: Dictionary = s["agents"][nm]
			for key in ["stress", "mood"]:
				var v := float(ag[key])
				finite = finite and not is_nan(v) and not is_inf(v)
			for k in ag["emotions"]:
				var v := float(ag["emotions"][k])
				finite = finite and not is_nan(v) and not is_inf(v)
	check(finite, "žádné NaN ani nekonečno ve stresu, náladě a emocích")
	check(int(a["stats"].get("talks", 0)) > 0, "proběhly rozhovory", str(a["stats"].get("talks", 0)))
	check(a["model"]["version"] == Runner.MODEL_VERSION, "výsledek nese verzi modelu")

	section("Běh nezanechává stopy ve hře")
	check(Runner.Main.household_override.is_empty(), "household_override je vrácen")
	finish("test_lab_runner")
