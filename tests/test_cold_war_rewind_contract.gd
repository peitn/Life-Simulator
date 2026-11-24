extends RefCounted
## Regression contract for ColdWar when game time is rewound.
## This documents current behavior, including the unresolved stage/cooldown policy.
const ColdWar = preload("res://scripts/sim/cold_war.gd")
func run() -> Dictionary:
	var failures: Array = []
	var checks := 0
	var w = ColdWar.new()
	w.note("A", "B", "argue", 200.0)
	w.note("A", "B", "argue", 201.0)
	checks += 1
	if w.stage("A", "B") != 1: failures.append("two arguments must create tension")
	checks += 1
	if w.recent_argues("A", "B", 100.0) != 0: failures.append("future arguments must not count at rewind time")
	w.decay(10.0, 100.0)
	checks += 1
	if w.stage("A", "B") != 1: failures.append("current policy retains previously established stage on rewind")
	checks += 1
	if w.recent_argues("A", "B", 201.0) != 2: failures.append("future stamps must survive rewind for catch-up")
	checks += 1
	if w.stage("A", "B") != 1: failures.append("catch-up must preserve tension")
	var c = ColdWar.new()
	c.note("A", "B", "argue", 900.0)
	c.note("A", "B", "argue", 901.0)
	c.resolve_clear_air("A", "B", 0.0, 1.0, 1000.0)
	checks += 1
	if c.clear_air_block("A", "B", 100.0) != "not_now": failures.append("documented future-dated cooldown policy changed")
	checks += 1
	if c.clear_air_block("A", "B", 1000.0) != "not_now": failures.append("cooldown must apply at original time")
	checks += 1
	if c.clear_air_block("A", "B", 1000.0 + ColdWar.CLEAR_COOLDOWN) != "": failures.append("cooldown must expire at boundary")
	return {"passed":checks-failures.size(),"total":checks,"failures":failures,"policy":"CURRENT behavior, not acceptance of rewind semantics"}
