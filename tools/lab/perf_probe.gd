extends Node
## Měření výkonu laboratoře: rozloží čas herního dne na části (sim_tick agentů, HouseholdDynamics, ostatní).
## godot --headless --path . res://tools/lab/perf_probe.tscn -- --scenario=cesta.json [--minutes=720] [--out=perf.json]
## Scénář: stejný formát jako lab_cli (household inline nebo household_file). Nic nezapisuje do hry.
const Main := preload("res://main.gd")
const Runner := preload("res://tools/lab/lab_runner.gd")


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var scen_path := ""
	var out_path := ""
	var minutes := 720.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scen_path = a.trim_prefix("--scenario=")
		elif a.begins_with("--minutes="):
			minutes = float(a.trim_prefix("--minutes="))
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	var sc = JSON.parse_string(FileAccess.get_file_as_string(scen_path))
	if typeof(sc) != TYPE_DICTIONARY:
		printerr("perf_probe: chybí --scenario")
		get_tree().quit(2)
		return
	var res: Dictionary = await Runner.probe(self, sc, minutes)
	print("PERF ", JSON.stringify(res))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
	get_tree().quit(0)
