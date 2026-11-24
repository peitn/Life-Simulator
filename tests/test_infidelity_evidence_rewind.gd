extends SceneTree
const Infidelity = preload("res://scripts/sim/infidelity.gd")
func _init():
	var a = Infidelity.new()
	a.notice("B","A",0.8,0.6,"C",300.0)
	var original = a.to_dict()
	var b = Infidelity.new()
	b.from_dict(JSON.parse_string(JSON.stringify(original)))
	var at300 = b.evidence_of("B","A",300.0)
	var at100 = b.evidence_of("B","A",100.0)
	var at301 = b.evidence_of("B","A",301.0)
	var at600 = b.evidence_of("B","A",600.0)
	var checks = [
		at300 > 0.0,
		is_equal_approx(at100,at300),
		at301 < at300,
		at600 < at301,
		b.hint_of("B","A") == "C",
		b.to_dict() == original
	]
	var passed=0
	for c in checks:
		if c: passed+=1
	print("INFIDELITY_EVIDENCE_REWIND ",passed,"/",checks.size())
	quit(0 if passed==checks.size() else 1)
