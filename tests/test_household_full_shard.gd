extends "res://tests/test_household_dynamics.gd"
## Full 16-seed social household matrix, sharded for remote 120-second tool cap.
## No new production mechanics and no modification to the canonical 16-seed test.
## Each shard captures the original _one_run seed, all social outcome counts,
## mental stress, relationships, event/mood statistics, and determinism hash.
func _run() -> void:
	var start := 0
	var count := 4
	var repeat_seed := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="):
			start = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--repeat="):
			repeat_seed = int(arg.trim_prefix("--repeat="))
	if count < 1 or count > 4 or start < 0 or start + count > SEEDS:
		check(false, "invalid bounded batch start/count")
		finish("test_household_full_shard")
		return
	section("Full sixteen-seed household — %d through %d inclusive" % [start, start+count-1])
	var results := []
	for seed in range(start, start+count):
		var r: Dictionary = await _one_run(seed, DAYS)
		var stats: Dictionary = r["stats"]
		var hist: Dictionary = stats.get("outcomes", {})
		var sum_outcomes := 0
		for key in ["chat", "argue", "awkward", "misunderstanding"]:
			sum_outcomes += int(hist.get(key, 0))
		var rate: float = float(r["argue"])
		var max_hi := 0.0
		for h in r["hi"].values():
			max_hi = maxf(max_hi, float(h) / float(DAYS*1440))
		var item := {
			"seed": seed, "days": DAYS, "sims": r["sims"],
			"talks": r["talks"], "argues": int(stats["argues"]), "rate": rate,
			"outcomes": hist.duplicate(true), "deescalated": int(stats["deescalated"]),
			"complaint_talks": int(stats["complaint_talks"]),
			"complaint_argues": int(stats["complaint_argues"]),
			"by_mood": stats["by_mood"].duplicate(true),
			"friction": stats["friction"].duplicate(true),
			"shared": stats["shared"].duplicate(true),
			"events": stats["events"].duplicate(true),
			"relationships": r["rels"], "pairs": r["pairs"],
			"high_stress_min": r["hi"].values(), "max_high_stress_fraction": max_hi,
			"crit_need_minutes": int(r["crit"]), "sig_hash": String(r["sig"]).sha256_text()}
		results.append(item)
		print("FULL_SHARD_SEED_JSON "+JSON.stringify(item))
		check(int(r["sims"]) == 3 and int(r["talks"]) >= DAYS * 2,
			"seed%d: three canonical autonomous NPCs converse over full 14 days" % seed)
		check(sum_outcomes == int(r["talks"]) and int(hist.get("argue",0))==int(stats["argues"]),
			"seed%d: every talk has one outcome; only actual fights counted" % seed)
		check(rate >= 0.08 and rate <= 0.6,
			"seed%d: real arguments in wide per-seed acceptance range" % seed, "%.3f" % rate)
		check(int(r["crit"])==0, "seed%d: no critical needs sustained" % seed)
		check(not (stats["friction"] as Dictionary).is_empty() and not (stats["shared"] as Dictionary).is_empty(),
			"seed%d: home frictions and positive shared moments both exist" % seed)
	if repeat_seed >= 0:
		var initial = results.filter(func(v): return int(v["seed"]) == repeat_seed)
		if initial.is_empty():
			check(false, "repeat seed must be contained in current batch")
		else:
			var replay: Dictionary = await _one_run(repeat_seed,DAYS)
			var digest: String = String(replay["sig"]).sha256_text()
			var same: bool = digest == String(initial[0]["sig_hash"])
			check(same, "seed%d: full 14-day social and mood trajectory reproducible" % repeat_seed)
			print("FULL_SHARD_REPLAY_JSON "+JSON.stringify({"seed": repeat_seed, "same": same, "hash": digest}))
	print("FULL_SHARD_DONE "+JSON.stringify({"start":start,"count":count,"days":DAYS,"results":results.size()}))
	gs.reset()
	finish("test_household_full_shard")
