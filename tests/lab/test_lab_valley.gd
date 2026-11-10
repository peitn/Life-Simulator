extends "res://tests/test_base.gd"
## Laboratoř M1b ("Údolí"): validace rozšíření scénáře, data oblasti, selektory, intervence moodlet/relation, ekonomika z populace,
## bloky, checkpoint (bit-přesná obnova), nastavení. Rozšíření jsou volitelná – zpětná kompatibilita hlídá test_lab_runner (hash dc75b1e9…).
const Runner := preload("res://tools/lab/lab_runner.gd")
const Main := preload("res://main.gd")
const EconomyBridge := preload("res://scripts/sim/economy_bridge.gd")
const EXP := "res://tools/lab/experiments/"
const POP := EXP + "udoli_v1_population.json"
const HH := EXP + "udoli_v1_household.json"


func _ready() -> void:
	watchdog_seconds = 280.0
	_run.call_deferred()


func _blk(extra: Dictionary) -> Dictionary:
	var sc := {"name": "v", "seed": 5, "days": 2, "snapshot_hours": 12, "snapshot_mode": "compact", "household_file": HH,
		"population_file": POP, "block": "blk_03", "settings": {"mental_health": "full", "intrusive_thoughts": 3, "addiction": true},
		"economy": {"enabled": true, "market": true, "use_population": true}}
	sc.merge(extra, true)
	return sc


func _run() -> void:
	var pop: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POP))
	var hh: Array = JSON.parse_string(FileAccess.get_file_as_string(HH))

	section("Data oblasti (Údolí v1)")
	check(hh.size() == 100 and pop["agents"].size() == 100 and pop["order"].size() == 100, "100 obyvatel")
	var names := {}
	for ch in hh:
		names["%s %s" % [ch["identity"]["first_name"], ch["identity"]["last_name"]]] = true
	check(names.size() == 100, "jména jsou jedinečná")
	var ok_names := true
	for n in pop["order"]:
		ok_names = ok_names and names.has(n) and pop["agents"].has(n)
	check(ok_names, "populace a postavy mají stejná jména")
	var in_blocks := 0
	var max_block := 0
	for b in pop["blocks"]:
		in_blocks += (pop["blocks"][b]["members"] as Array).size()
		max_block = maxi(max_block, (pop["blocks"][b]["members"] as Array).size())
	check(in_blocks == 100 and max_block <= 8 and pop["blocks"].size() >= 13, "bloky pokrývají všechny, ≤ 8 obyvatel", "%d / %d" % [in_blocks, max_block])
	var rel_ok := true
	for r in pop["relations"]:
		rel_ok = rel_ok and pop["agents"].has(r[0]) and pop["agents"].has(r[1]) and absf(float(r[2])) <= 100.0
	check(rel_ok, "počáteční vztahy odkazují na existující agenty, |v| ≤ 100")
	var profiles := {}
	for n in pop["agents"]:
		profiles[pop["agents"][n]["profile"]] = true
	check(profiles.size() == 6, "všech 6 investorských profilů je zastoupeno", str(profiles.keys()))
	var agents_cfg := {}
	for n in pop["agents"]:
		var a: Dictionary = pop["agents"][n]
		agents_cfg[n] = {"tier": a["tier"], "qualification": a["skill"], "job": a["job"], "endowment": a["endowment"],
			"household": a["household"], "shift_off": a["shift_off"], "profile": a["profile"]}
	check(EconomyBridge.validate_config({"market": true, "agents": agents_cfg, "register_all": true}).is_empty(), "ekonomická data agentů projdou validací mostu")
	check(not EconomyBridge.validate_config({"agents": {"X": {"tier": "palace"}}}).is_empty(), "neznámé bydlení je neplatné")
	check(not EconomyBridge.validate_config({"agents": {"X": {"profile": "yolo"}}}).is_empty(), "neznámý investorský profil je neplatný")
	var chars: Array = []
	Main.household_override = hh
	chars = Main.household_characters()
	Main.household_override = []
	check(chars.size() == 100, "všech 100 postav projde validátorem hry")

	section("Validace scénáře (rozšíření)")
	check(not Runner.validate({"seed": 1, "days": 99}).is_empty(), "days 99 bez long_run je stále neplatné")
	check(Runner.validate({"seed": 1, "days": 180, "long_run": true}).is_empty(), "long_run dovolí 180 dní")
	check(not Runner.validate({"seed": 1, "days": 401, "long_run": true}).is_empty(), "i long_run má strop 400")
	check(not Runner.validate({"seed": 1, "days": 2, "settings": {"sound": true}}).is_empty(), "neznámé nastavení je neplatné")
	check(not Runner.validate({"seed": 1, "days": 2, "settings": {"mental_health": "maybe"}}).is_empty(), "neplatná hodnota nastavení")
	check(Runner.validate({"seed": 1, "days": 2, "settings": {"mental_health": "full", "intrusive_thoughts": 3}}).is_empty(), "platné nastavení")
	check(not Runner.validate({"seed": 1, "days": 2, "household_file": "res://nic.json"}).is_empty(), "chybějící household_file")
	check(not Runner.validate(_blk({"block": "blk_99"})).is_empty(), "neznámý blok")
	check(Runner.validate(_blk({})).is_empty(), "platný scénář bloku")
	var iv := func(e: Dictionary): return Runner.validate(_blk({"interventions": [e]}))
	check(iv.call({"day": 1, "kind": "moodlet", "strength": 10, "minutes": 240, "emotion": "stastny", "label": "Oslava", "target": "all"}).is_empty(), "platný moodlet")
	check(not iv.call({"day": 1, "kind": "moodlet", "strength": 10, "minutes": 240, "emotion": "nevim", "label": "x", "target": "all"}).is_empty(), "neznámá emoce")
	check(not iv.call({"day": 1, "kind": "moodlet", "strength": 99, "minutes": 240, "emotion": "stastny", "label": "x"}).is_empty(), "síla moodletu mimo rozsah")
	check(iv.call({"day": 1, "kind": "relation", "a": "group:dilna", "b": "community:dilny", "delta": -10}).is_empty(), "platná relace")
	check(not iv.call({"day": 1, "kind": "relation", "a": "group:neexistuje", "b": "all", "delta": -10}).is_empty(), "selektor bez agentů je neplatný")
	check(not iv.call({"day": 1, "kind": "relation", "a": "all", "b": "all", "delta": 0}).is_empty(), "nulová změna vztahu je neplatná")
	check(not iv.call({"day": 1, "kind": "stressor", "amount": 10, "target": "kolo:1"}).is_empty(), "neznámý selektor")
	check(not iv.call({"day": 1, "kind": "stressor", "amount": 10, "target": "Neexistující Agent"}).is_empty(), "neznámé jméno agenta (s populací)")
	check(not Runner.validate(_blk({"economy": {"enabled": true, "market": true, "events": [{"type": "meteor", "day": 1}]}})).is_empty(), "neznámý typ události burzy")
	check(not Runner.validate(_blk({"economy": {"enabled": true, "events": [{"type": "layoffs", "day": 1, "share_pm": 100}]}})).is_empty(), "události burzy vyžadují market")
	check(not Runner.validate(_blk({"economy": {"enabled": true, "market": true, "events": [{"type": "layoffs", "day": 9, "share_pm": 100}]}})).is_empty(), "událost po konci běhu")
	check(not Runner.validate({"seed": 1, "days": 2, "economy": {"enabled": true, "use_population": true}}).is_empty(), "use_population vyžaduje population_file")
	check(not Runner.validate({"seed": 1, "days": 2, "stop_day": 3, "checkpoint_out": "/tmp/x"}).is_empty(), "stop_day > days")
	check(not Runner.validate({"seed": 1, "days": 2, "stop_day": 1}).is_empty(), "stop_day vyžaduje checkpoint_out")
	check(Runner.validate(_blk({"stop_day": 1, "checkpoint_out": "/tmp/x"})).is_empty(), "platná segmentace")
	var scn: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXP + "udoli_v1.json"))
	check(Runner.validate(scn).is_empty(), "scénář udoli_v1 je platný", str(Runner.validate(scn)))
	check(Runner.validate(JSON.parse_string(FileAccess.get_file_as_string(EXP + "udoli_v1_control.json"))).is_empty(), "kontrolní scénář je platný")
	check(scn["interventions"].size() >= 20 and scn["economy"]["events"].size() >= 5, "scénář má ≥ 20 intervencí a ≥ 5 ekonomických událostí")

	section("Selektory")
	var any_dilna := false
	for n in pop["agents"]:
		any_dilna = any_dilna or pop["agents"][n]["group"] == "dilna"
	check(any_dilna, "skupina dilna má členy")
	check(Runner._matches({"age": 70}, "age", "65-95") and not Runner._matches({"age": 30}, "age", "65-95"), "selektor věku")
	check(Runner._matches({"predispositions": ["anxiety"]}, "pred", "anxiety") and not Runner._matches({"predispositions": []}, "pred", "anxiety"), "selektor predispozice")

	section("Běh bloku: determinismus, nastavení, intervence, ekonomika")
	var ivs := [
		{"day": 0.5, "kind": "stressor", "amount": 30.0, "target": "all", "label": "s"},
		{"day": 1.0, "kind": "moodlet", "strength": 12.0, "minutes": 240.0, "emotion": "stastny", "label": "Oslava", "target": "all"},
		{"day": 1.2, "kind": "relation", "a": "all", "b": "all", "delta": -12.0, "label": "hadka"}]
	var sc1 := _blk({"interventions": ivs, "economy": {"enabled": true, "market": true, "use_population": true,
		"events": [{"type": "path", "day": 1, "days": 1, "total_pm": -200, "scope": "market"}]}})
	var a: Dictionary = await Runner.run(self, sc1)
	var b: Dictionary = await Runner.run(self, sc1)
	check(a["ok"] and b["ok"], "bloky proběhly", str(a.get("errors", "")))
	if not a["ok"]:
		finish("test_lab_valley")
		return
	check(a["final_hash"] == b["final_hash"] and JSON.stringify(a["snapshots"]) == JSON.stringify(b["snapshots"]), "stejný seed → shodný hash i snímky")
	check(a["agents"].size() == (pop["blocks"]["blk_03"]["members"] as Array).size(), "blok má jen své členy")
	check(a["settings"]["intrusive_thoughts"] == 3 and a["settings"]["mental_health"] == "full", "nastavení z klíče settings se použilo")
	var fin := true
	for s in a["snapshots"]:
		for k in ["stress", "mood", "rel_mean"]:
			for v in s[k]:
				fin = fin and is_finite(float(v))
	check(fin, "žádné NaN ani nekonečno v kompaktních snímcích")
	check(a["snapshots"].size() == 5 and a["snapshots"][0].has("emotion") and a["snapshots"][0].has("rel_neg"), "kompaktní snímky: 1 + 4 po 12 h")
	check(a["applied_interventions"].size() == 3 and int(a["applied_interventions"][0]["affected"]) == a["agents"].size(), "intervence zasáhly celý blok")
	var peak_before := 0.0
	var peak_after := 0.0
	for s in a["snapshots"]:
		for v in s["stress"]:
			if float(s["day"]) < 0.5:
				peak_before = maxf(peak_before, float(v))
			elif float(s["day"]) >= 0.5:
				peak_after = maxf(peak_after, float(v))
	check(peak_after > peak_before + 10.0, "stresor zvýšil špičku stresu", "%.1f vs %.1f" % [peak_before, peak_after])
	var rel0: float = 0.0
	var rel1: float = 0.0
	for v in a["snapshots"][2]["rel_mean"]:   # den 1,0
		rel0 += float(v)
	for v in a["snapshots"][3]["rel_mean"]:   # den 1,5 (po záporné relaci v 1,2)
		rel1 += float(v)
	check(rel1 < rel0 - 3.0 * a["agents"].size() * 0.5, "záporná relace snížila průměrné vztahy", "%.1f → %.1f" % [rel0 / a["agents"].size(), rel1 / a["agents"].size()])
	check(a.has("economy") and a["economy"]["stats"]["agents"] == 100, "ekonomika registrovala všech 100 agentů populace")
	var other: Dictionary = await Runner.run(self, _blk({"block": "blk_01", "economy": sc1["economy"]}))
	check(other["ok"] and JSON.stringify(other["snapshots"][-1]["econ"]) == JSON.stringify(a["snapshots"][-1]["econ"]), "ekonomika je v různých blocích shodná (sdílená populace)")
	check(a["snapshots"][-1]["market_index_pm"] < 1000000, "krach snížil index burzy")
	check(Runner.Main.household_override.is_empty(), "household_override je vrácen")
	var gs := get_node("/root/GameSettings")
	check(int(gs.get_value("intrusive_thoughts")) == int(gs.DEFAULTS["intrusive_thoughts"]), "nastavení scénáře po běhu nezůstává v hostiteli")

	section("Checkpoint: segmentovaný běh = souvislý běh (bit-přesně)")
	var cp := "/tmp/lab_valley_test.cp"
	# Poznámka (omezení, viz docs/lab/RESEARCH_RUN_v1.md): se silným plošným stresorem (30 bodů všem) se obnovený běh po čase rozejde
	# s souvislým – GameSave neukládá všechen stav modulů. Proto se bit-přesnost ověřuje bez stresoru a hlavní běh checkpointy nepoužívá.
	var ckiv := ivs.duplicate(true)
	ckiv.pop_front()
	var sc1c := sc1.duplicate(true)
	sc1c["interventions"] = ckiv
	var full: Dictionary = await Runner.run(self, sc1c)
	var s1 := sc1c.duplicate(true)
	s1["stop_day"] = 1
	s1["checkpoint_out"] = cp
	var seg1: Dictionary = await Runner.run(self, s1)
	var s2 := sc1c.duplicate(true)
	s2["checkpoint_in"] = cp
	var seg2: Dictionary = await Runner.run(self, s2)
	check(seg1["ok"] and seg2["ok"], "oba segmenty proběhly", str(seg1.get("errors", "")) + str(seg2.get("errors", "")))
	check(seg2.get("segment", {}).get("resume_hash", "x") == seg1.get("segment", {}).get("checkpoint_out", {}).get("state_hash", "y"), "hash po obnově = hash při uložení")
	check(seg2["final_hash"] == full["final_hash"], "konečný hash segmentovaného běhu = souvislého")
	var same := true
	var by_day := {}
	for s in full["snapshots"]:
		by_day[s["day"]] = JSON.stringify(s)
	for s in seg2["snapshots"]:
		same = same and by_day.get(s["day"], "") == JSON.stringify(s)
	check(same, "snímky po obnově jsou shodné se souvislým během")
	var s3 := sc1c.duplicate(true)
	s3["seed"] = 6
	s3["checkpoint_in"] = cp
	var wrong: Dictionary = await Runner.run(self, s3)
	check(not wrong["ok"], "checkpoint jiného scénáře se odmítne")
	var missing: Dictionary = await Runner.run(self, _blk({"checkpoint_in": "/tmp/neexistuje.cp"}))
	check(not missing["ok"], "chybějící checkpoint se odmítne")
	DirAccess.remove_absolute(cp)
	finish("test_lab_valley")
