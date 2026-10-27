extends RefCounted
## Undo/redo pro editor postavy. Ukládá celé kanonické slovníky (malé – jednotky kB),
## takže i náhodné generování se zámky je jeden krok zpět. Posuvník tažený myší se slučuje
## do jednoho kroku (`coalesce_key` – stejný klíč do COALESCE_MS = přepis posledního kroku).

const MAX_STEPS := 100
const COALESCE_MS := 600

var _undo: Array = []   # [{"data": Dictionary, "label": String}]
var _redo: Array = []
var _current: Dictionary = {}
var _last_key := ""
var _last_ms := -100000


func reset(initial: Dictionary) -> void:
	_undo.clear()
	_redo.clear()
	_current = initial.duplicate(true)
	_last_key = ""


func current() -> Dictionary:
	return _current.duplicate(true)


## Zaznamená nový stav. `now_ms` jde podstrčit v testech.
func push(state: Dictionary, label := "", coalesce_key := "", now_ms := -1) -> void:
	if state == _current:
		return
	var t := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var merge := coalesce_key != "" and coalesce_key == _last_key and t >= _last_ms and t - _last_ms <= COALESCE_MS and not _undo.is_empty()
	if not merge:
		_undo.append({"data": _current, "label": label})
		while _undo.size() > MAX_STEPS:
			_undo.pop_front()
	_current = state.duplicate(true)
	_redo.clear()
	_last_key = coalesce_key
	_last_ms = t


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Vrací stav po kroku zpět (nebo současný, když není kam).
func undo() -> Dictionary:
	if _undo.is_empty():
		return current()
	var e: Dictionary = _undo.pop_back()
	_redo.append({"data": _current, "label": e["label"]})
	_current = e["data"]
	_last_key = ""
	return current()


func redo() -> Dictionary:
	if _redo.is_empty():
		return current()
	var e: Dictionary = _redo.pop_back()
	_undo.append({"data": _current, "label": e["label"]})
	_current = e["data"]
	_last_key = ""
	return current()


func undo_label() -> String:
	return String(_undo[-1]["label"]) if not _undo.is_empty() else ""
