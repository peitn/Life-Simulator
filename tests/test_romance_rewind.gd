extends RefCounted
## Regression contract for future-dated romance events after a GameClock rewind.
## Characterization only: does not define a full rewind policy.
const Romance = preload("res://scripts/sim/romance.gd")
const MAN = {"age":35,"aromantic":false,"attracted_to":["zeny"],"group":"muzi"}
const WOMAN = {"age":30,"aromantic":false,"attracted_to":["muzi"],"group":"zeny"}

static func run() -> Dictionary:
	var failures: Array = []
	var r = Romance.new()
	if r.resolve_ask("A","B",MAN,WOMAN,1.0,0.0,200.0) != "yes":
		failures.append("setup dating")
	if r.breakup("A","B",300.0).is_empty():
		failures.append("setup breakup")
	if r.ask_block("A","B",100.0) != "":
		failures.append("future breakup should not block before it happens")
	if r.ask_block("A","B",301.0) != "not_now":
		failures.append("breakup cooldown after event")
	var saved = JSON.parse_string(JSON.stringify(r.to_dict()))
	var restored = Romance.new()
	restored.from_dict(saved)
	if restored.ask_block("A","B",100.0) != "":
		failures.append("rewind after JSON save")
	if restored.ask_block("A","B",301.0) != "not_now":
		failures.append("cooldown after JSON save")
	return {"passed":6-failures.size(),"total":6,"failures":failures}
