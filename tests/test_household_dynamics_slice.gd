extends "res://tests/test_household_dynamics.gd"
## Four-seed slice of the 16-seed matrix. Real baseline unit checks plus
## social nuance distribution and same-seed replay, within remote tool cap.

func _run() -> void:
	world = _make_world()
	_test_units()
	world.queue_free()
	await get_tree().process_frame
	section("Four 14-day household runs with explicit non-argument outcomes")
	var aggregate := {"chat": 0, "argue": 0, "awkward": 0, "misunderstanding": 0}
	var total := 0
	for k in [0, 1, 2, 3]:
		var r: Dictionary = await _one_run(k, 14)
		runs.append(r)
		total += int(r["talks"])
		for key in aggregate:
			aggregate[key] += int(r["stats"]["outcomes"].get(key, 0))
		print("SLICE seed=%d talks=%d rate=%.2f outcomes=%s" % [
			k, int(r["talks"]), float(r["argue"]), JSON.stringify(r["stats"]["outcomes"])])
	var outcomes_sum := 0
	for key in aggregate:
		outcomes_sum += int(aggregate[key])
	check(outcomes_sum == total and total > 200,
		"all four scenario conversations account for one outcome each")
	check(aggregate["awkward"] > 0 and aggregate["misunderstanding"] > 0
		and aggregate["argue"] > 0,
		"awkward silence, misunderstanding and arguments all emerge in household life")
	var avg: float = _mean(runs.map(func(r): return float(r["argue"])))
	check(avg >= ARGUE_MIN and avg <= ARGUE_MAX,
		"actual-argument mean stays within post-nuance 10–40% acceptance range",
		"%.3f" % avg)
	check(runs.all(func(r): return r["talks"] >= 28),
		"all four simulated homes produce sufficient conversations")
	var repeat: Dictionary = await _one_run(3, 14)
	check(repeat["sig"] == runs[3]["sig"],
		"same 14-day household seed repeats the complete social/mental signature")
	finish("test_household_dynamics_slice")
