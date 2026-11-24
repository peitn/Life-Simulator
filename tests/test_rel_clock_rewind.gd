extends RefCounted
const Ledger = preload("res://scripts/sim/rel_ledger.gd")
static func run() -> Dictionary:
	var passed := 0
	var failures: Array[String] = []
	var a = Ledger.new()
	a.on_hurt_by("NPC", 40.0, 180.0)
	a.receive_apology("NPC", "partial", 200.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b = Ledger.new()
	b.from_dict(saved)
	if b.to_dict() == a.to_dict(): passed += 1
	else: failures.append("JSON roundtrip")
	if is_equal_approx(b.sincerity("NPC", 100.0), 1.0): passed += 1
	else: failures.append("future apology counted")
	if b.evaluate_apology("NPC", 100.0, 0.0, 0.0, 0.0, 0.5).outcome != "spam": passed += 1
	else: failures.append("future apology spam")
	if b.evaluate_apology("NPC", 100.0, 0.0, 0.0, 0.0, 0.5).reason != "příliš brzy": passed += 1
	else: failures.append("future hurt too soon")
	if b.evaluate_apology("NPC", 210.0, 0.0, 0.0, 0.0, 0.5).outcome == "spam": passed += 1
	else: failures.append("spam window lost")
	if is_equal_approx(b.sincerity("NPC", 210.0), 0.7): passed += 1
	else: failures.append("sincerity lost")
	return {"passed":passed,"total":6,"failures":failures,"policy":"rewind allowed; future events ignored until clock catches up"}
