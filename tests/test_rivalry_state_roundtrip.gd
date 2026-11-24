extends SceneTree
const Rivalry = preload("res://scripts/sim/rivalry_pressure.gd")
func _initialize() -> void:
 var passed := 0
 var state := {"version": 1, "rivalry": Rivalry.rivalry(0.8, 0.4, 0.2), "rumor_credibility": 0.7, "boundaries": 0.5, "social_support": 0.4, "evidence_against": 0.9}
 var serialized := JSON.stringify(state)
 var parsed = JSON.parse_string(serialized)
 if typeof(parsed) != TYPE_DICTIONARY: push_error("JSON roundtrip invalid"); quit(1); return
 passed += 1
 for key in state.keys():
  if not parsed.has(key): push_error("missing "+key); quit(1); return
  passed += 1
  if absf(float(parsed[key]) - float(state[key])) > 0.000001: push_error("mismatch "+key); quit(1); return
  passed += 1
 var before := Rivalry.resolve_pressure(state.rivalry, state.rumor_credibility, state.boundaries, state.social_support, state.evidence_against)
 var after := Rivalry.resolve_pressure(float(parsed.rivalry), float(parsed.rumor_credibility), float(parsed.boundaries), float(parsed.social_support), float(parsed.evidence_against))
 for key in ["attempt", "defense", "impact"]:
  if absf(float(before[key]) - float(after[key])) > 0.000001: push_error("effect mismatch "+key); quit(1); return
  passed += 1
 if before.resisted != after.resisted: push_error("resistance mismatch"); quit(1); return
 passed += 1
 print("RIVALRY_STATE_ROUNDTRIP_PASS ", passed, "/", passed)
 quit(0)
