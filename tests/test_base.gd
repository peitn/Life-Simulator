extends Node
## Společný základ testů: check(), čekání na podmínku, souhrn a ukončení s kódem.
## Testy jsou scény v res://tests/ (spuštění: godot_run scene=res://tests/<test>.tscn).

## Pojistka: když test uvázne (např. chyba skriptu v korutině), ukončí se s chybou.
var watchdog_seconds := 60.0
var _passed := 0
var _failed := 0
var _failures: PackedStringArray = []


func _enter_tree() -> void:
	# Odloženě: podtřída nastavuje watchdog_seconds až v _ready() (dřív tu platilo vždy 60 s).
	_start_watchdog.call_deferred()


func _start_watchdog() -> void:
	get_tree().create_timer(watchdog_seconds, true, false, true).timeout.connect(_on_watchdog)


func _on_watchdog() -> void:
	print("\n!! WATCHDOG: test neskončil do %.0f s (uvázl nebo spadl skript)" % watchdog_seconds)
	_failed += 1
	_failures.append("watchdog")
	finish(name)


func check(cond: bool, label: String, detail := "") -> bool:
	if cond:
		_passed += 1
		print("  ✔ " + label)
	else:
		_failed += 1
		_failures.append(label)
		print("  ✘ " + label + ("  [" + detail + "]" if detail != "" else ""))
	return cond


func section(title: String) -> void:
	print("\n== " + title)


## Čeká (reálný čas), dokud `cond` nevrátí true nebo nevyprší `timeout`. Vrací výsledek.
func wait_until(cond: Callable, timeout := 5.0) -> bool:
	# This Node does not run _process, so get_process_delta_time() may stay
	# zero indefinitely. A monotonic real-time deadline guarantees termination.
	var deadline_usec := Time.get_ticks_usec() + int(maxf(0.0, timeout) * 1000000.0)
	while Time.get_ticks_usec() < deadline_usec:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func wait_seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func finish(test_name: String) -> void:
	print("\n%s: %d prošlo, %d selhalo" % [test_name, _passed, _failed])
	if _failed > 0:
		print("SELHALO: " + ", ".join(_failures))
	print("TEST %s" % ("OK" if _failed == 0 else "SELHAL"))
	get_tree().quit(0 if _failed == 0 else 1)
