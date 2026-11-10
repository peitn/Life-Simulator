extends Node
## Příkazový řádek laboratoře: godot --headless --path . res://tools/lab/lab_cli.tscn -- --scenario=cesta.json --out=vysledek.json
## Jeden scénář = jeden proces (kvůli limitům nástrojů a izolaci). Vstup/výstup jsou obyčejné JSON soubory.
const Runner := preload("res://tools/lab/lab_runner.gd")


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var scen_path := ""
	var out_path := ""
	var extra := {}   # přepisy scénáře z příkazového řádku (segmentace dlouhých běhů, průběžný výpis)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scen_path = a.trim_prefix("--scenario=")
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--checkpoint-in="):
			extra["checkpoint_in"] = a.trim_prefix("--checkpoint-in=")
		elif a.begins_with("--checkpoint-out="):
			extra["checkpoint_out"] = a.trim_prefix("--checkpoint-out=")
		elif a.begins_with("--stop-day="):
			extra["stop_day"] = int(a.trim_prefix("--stop-day="))
		elif a == "--progress":
			extra["progress"] = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(scen_path)) if scen_path != "" and FileAccess.file_exists(scen_path) else null
	if typeof(parsed) != TYPE_DICTIONARY or out_path == "":
		printerr("lab_cli: chybí --scenario=<json> nebo --out=<json>")
		get_tree().quit(2)
		return
	for k in extra:
		parsed[k] = extra[k]
	var res: Dictionary = await Runner.run(self, parsed)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("lab_cli: nelze zapsat ", out_path)
		get_tree().quit(3)
		return
	f.store_string(JSON.stringify(res, " ", true, true))
	f.close()
	print("LAB_DONE ", res.get("scenario", ""), " seed=", res.get("seed", -1), " ok=", res.get("ok", false), " hash=", res.get("final_hash", ""))
	get_tree().quit(0 if bool(res.get("ok", false)) else 1)
