extends SceneTree
## Isolated infidelity rewind/JSON regression. No disk/GameClock integration.
const Infidelity = preload("res://scripts/sim/infidelity.gd")
func _init():
	var x = Infidelity.new()
	# Notice at game minute 300: suspicion 0.8, evidence 0.6, lover hint C.
	x.notice("B","A",0.8,0.6,"C",300.0)
	var v = x.suspicion_of("B","A",300.0)
	var ev = x.evidence_of("B","A",300.0)
	var y = Infidelity.new()
	y.from_dict(JSON.parse_string(JSON.stringify(x.to_dict())))
	var tests = [
		is_equal_approx(y.suspicion_of("B","A",100.0),v),
		is_equal_approx(y.evidence_of("B","A",100.0),ev),
		y.hint_of("B","A")=="C",
		y.suspicion_of("B","A",301.0)<v,
		y.suspicion_of("B","A",300.0)==v,
		y.suspicion_of("B","A",100.0)==v
	]
	var passed=0
	for t in tests:
		if t: passed+=1
	print("INFIDELITY_REWIND ",passed,"/",tests.size())
	quit(0 if passed==tests.size() else 1)
