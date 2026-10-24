extends RefCounted
## Transactional editor state. This is not an RPC or an authorization boundary.
## The server/controller must supply a fresh ownership check and propagate a successful
## commit to SimAgent/SimVisual. Never trust a client-supplied permission callback.

const History := preload("res://scripts/character/character_history.gd")
const Validator := preload("res://scripts/character/character_validator.gd")

var _history := History.new()
var _source: Resource
var _baseline: Dictionary = {}


func begin(source: Resource) -> bool:
	if is_open() or source == null or not source.has_method("to_dict") or not source.has_method("set_from_dict"):
		return false
	_source = source
	_baseline = source.to_dict().duplicate(true)
	_history.reset(_baseline)
	return true


func is_open() -> bool:
	return _source != null


func draft() -> Dictionary:
	return _history.current() if is_open() else {}


func is_dirty() -> bool:
	return is_open() and draft() != _baseline


## Permit invalid intermediate form values; Apply reports validation errors without
## silently repairing them. Identity/version cannot be replaced by an editor panel.
func replace_draft(data: Dictionary, label := "", coalesce_key := "", now_ms := -1) -> bool:
	if not is_open() or data.get("uid") != _baseline.get("uid") or data.get("v") != _baseline.get("v"):
		return false
	_history.push(data, label, coalesce_key, now_ms)
	return true


func can_undo() -> bool:
	return is_open() and _history.can_undo()


func can_redo() -> bool:
	return is_open() and _history.can_redo()


func undo() -> Dictionary:
	return _history.undo() if is_open() else {}


func redo() -> Dictionary:
	return _history.redo() if is_open() else {}


func cancel() -> void:
	_source = null
	_baseline.clear()
	_history.reset({})


## Synchronous commit: permission is checked again at Apply, then the original
## snapshot is compared to live data. A rejected commit keeps the draft for recovery.
## options come from the authoritative controller, including content settings.
func apply(can_edit: Callable, options: Dictionary = {}) -> Dictionary:
	if not is_open():
		return _error("closed")
	if not can_edit.is_valid() or can_edit.call(_source) != true:
		return _error("forbidden")
	if _source.to_dict() != _baseline:
		return _error("conflict")
	var opts := options.duplicate(true)
	opts["mode"] = "strict"
	opts["public_only"] = false
	var result := Validator.validate(draft(), opts)
	if not result["ok"]:
		result["reason"] = "invalid"
		return result
	_source.set_from_dict(result["data"])
	# Continue editing after Apply; Cancel now discards only subsequent changes.
	_baseline = _source.to_dict().duplicate(true)
	_history.reset(_baseline)
	return {"ok": true, "reason": "applied", "warnings": result["warnings"]}


func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
