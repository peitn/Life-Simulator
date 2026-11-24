extends RefCounted
## Server-only deterministic rivalry/social-pressure calculation (pure functions, no state).
## Used by scripts/sim/rivalry.gd (listener reaction to slander) and scripts/sim/social_pressure.gd
## (target's defense against manipulation). Callers enforce server authority and apply the effects.
## validate_state() checks the standalone v1 test-state shape (tests/test_rivalry_state_*.gd); the live
## game state is persisted by Rivalry (dynamics.rivalry, its own versioned snapshot).

const MAX_PRESSURE := 1.0
const MIN_DEFENSE := 0.0

static func _unit(v: float) -> float:
	if not is_finite(v):
		return 0.0
	return clampf(v, 0.0, 1.0)

## Rivalry grows with competing goals and repeated conflict; trust attenuates it.
static func rivalry(competing_goal: float, conflict: float, trust: float) -> float:
	var c := _unit(competing_goal)
	var f := _unit(conflict)
	var t := _unit(trust)
	return clampf((0.65 * c + 0.35 * f) * (1.0 - 0.5 * t), 0.0, 1.0)

## Pressure is not mind control: boundaries, support and evidence reduce impact.
## An attempted rumor is not accepted as true; credibility is an explicit input.
static func resolve_pressure(rivalry_level: float, rumor_credibility: float,
		boundaries: float, social_support: float, evidence_against: float) -> Dictionary:
	var r := _unit(rivalry_level)
	var rumor := _unit(rumor_credibility)
	var defense := clampf(0.4 * _unit(boundaries) + 0.35 * _unit(social_support)
		+ 0.25 * _unit(evidence_against), MIN_DEFENSE, 1.0)
	var raw := r * rumor
	var impact := clampf(raw * (1.0 - defense), 0.0, MAX_PRESSURE)
	return {"attempt": raw, "defense": defense, "impact": impact,
		"resisted": raw > 0.0 and impact <= raw * 0.5}

static func validate_state(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var state: Dictionary = value
	var allowed := ["version", "rivalry", "rumor_credibility", "boundaries", "social_support", "evidence_against"]
	if state.size() != allowed.size():
		return false
	for key in state.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return false
	if not state.has("version"):
		return false
	if typeof(state["version"]) != TYPE_INT and typeof(state["version"]) != TYPE_FLOAT:
		return false
	if float(state["version"]) != 1.0:
		return false
	for key in ["rivalry", "rumor_credibility", "boundaries", "social_support", "evidence_against"]:
		if not state.has(key):
			return false
		var v: Variant = state[key]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
		var n := float(v)
		if not is_finite(n) or n < 0.0 or n > 1.0:
			return false
	return true
