extends SceneTree
const Rivalry = preload("res://scripts/sim/rivalry_pressure.gd")
func _initialize() -> void:
	var state := {"version":1,"rivalry":0.4,"rumor_credibility":0.3,"boundaries":0.5,"social_support":0.8,"evidence_against":0.7}
	var passed := 0
	if not Rivalry.validate_state(state):
		push_error("valid rejected")
		quit(1)
		return
	passed += 1
	for key in state.keys():
		var bad := state.duplicate(true)
		bad.erase(key)
		if Rivalry.validate_state(bad):
			push_error("missing "+key)
			quit(1)
			return
		passed += 1
	for key in ["rivalry","rumor_credibility","boundaries","social_support","evidence_against"]:
		for v in [-0.1,1.1,"invalid",NAN,INF]:
			var bad := state.duplicate(true)
			bad[key]=v
			if Rivalry.validate_state(bad):
				push_error("invalid "+key)
				quit(1)
				return
			passed += 1
	for v in [0,2,"1",NAN]:
		var bad := state.duplicate(true)
		bad["version"]=v
		if Rivalry.validate_state(bad):
			push_error("version")
			quit(1)
			return
		passed += 1
	for extra in ["unexpected", 123]:
		var bad := state.duplicate(true)
		bad[extra] = 0.5
		if Rivalry.validate_state(bad):
			push_error("extra key accepted")
			quit(1)
			return
		passed += 1
	if Rivalry.validate_state([]):
		push_error("array")
		quit(1)
		return
	passed += 1
	if not Rivalry.validate_state(JSON.parse_string(JSON.stringify(state))):
		push_error("json")
		quit(1)
		return
	passed += 1
	print("RIVALRY_STATE_VALIDATION_PASS ",passed,"/",passed)
	quit(0)
