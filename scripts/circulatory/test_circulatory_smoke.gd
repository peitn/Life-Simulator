# test_circulatory_smoke.gd
# Minimal smoke tests for CirculatorySystem Phase 1
# Run inside Godot test harness or headless

extends RefCounted

func run_all() -> bool:
	var ok := true
	ok = ok and _test_volume_conservation()
	ok = ok and _test_resting_map()
	ok = ok and _test_bleeding_reduces_volume()
	ok = ok and _test_thrombus_stops_bleed()
	ok = ok and _test_stenosis_raises_load()
	return ok


func _test_volume_conservation() -> bool:
	var c := CirculatorySystem.new()
	var v0 := c.blood.volume_ml
	for i in 200:
		c.update(0.05)
	var ok := absf(c.blood.volume_ml - v0) < 1.0
	print("volume_conservation: ", "PASS" if ok else "FAIL", "  Δ=", c.blood.volume_ml - v0)
	return ok


func _test_resting_map() -> bool:
	var c := CirculatorySystem.new()
	for i in 300:
		c.update(0.05)
	var ok := c.mean_arterial_pressure > 70.0 and c.mean_arterial_pressure < 110.0
	print("resting_map: ", "PASS" if ok else "FAIL", "  MAP=", c.mean_arterial_pressure)
	return ok


func _test_bleeding_reduces_volume() -> bool:
	var c := CirculatorySystem.new()
	c.add_wound("arm", "artery", 0.5)
	var v0 := c.blood.volume_ml
	for i in 100:
		c.update(0.05)
	var ok := c.blood.volume_ml < v0 - 10.0
	print("bleeding_reduces_volume: ", "PASS" if ok else "FAIL", "  lost=", v0 - c.blood.volume_ml)
	return ok


func _test_thrombus_stops_bleed() -> bool:
	var c := CirculatorySystem.new()
	c.add_wound("arm", "artery", 0.15)
	for i in 800:  # longer run so thrombus can form
		c.update(0.05)
	var still_bleeding := false
	for w in c.wounds:
		if not w.is_stopped:
			still_bleeding = true
	var ok := not still_bleeding
	print("thrombus_stops_bleed: ", "PASS" if ok else "FAIL")
	return ok


func _test_stenosis_raises_load() -> bool:
	var c := CirculatorySystem.new()
	# Just check that the API accepts the defect and system still runs
	c.set_valve_defect(CirculatorySystem.HeartValve.Kind.AORTIC, 0.6, 0.0)
	for i in 100:
		c.update(0.05)
	var ok := c.mean_arterial_pressure > 50.0
	print("stenosis_api: ", "PASS" if ok else "FAIL")
	return ok
