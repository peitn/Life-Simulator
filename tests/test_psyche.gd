extends "res://tests/test_base.gd"
## Běh 20 – 1. osa psychiky (PsycheModel): profily jako data a jejich limity, acyklický graf vazeb, výpočet P a D,
## reziduum individuality (bez dvojího započtení s dnešními mechanikami), háčky MentalState, nastavení obsahu,
## rozmanitost (stejný profil → měřitelně jiné chování), kontext, stabilita 16 seedů × 14 dní, agency,
## schéma v5 (soukromí, validace, migrace, round-trip), integrace se SimAgent a výkon.

const PM := preload("res://scripts/psyche/psyche_model.gd")
const MentalState := preload("res://scripts/sim/mental_state.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const Codec := preload("res://scripts/character/character_codec.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const Randomizer := preload("res://scripts/character/character_randomizer.gd")
const SimAgentScript := preload("res://scripts/sim/sim_agent.gd")

## Čísla diagnóz před během 20 (dřív konstanta v mental_state.gd) – data musí dát přesně totéž.
const LEGACY_REF := {
	"anxiety": {"sensitivity": 0.35, "threat_bias": 0.5, "social": 0.6, "panic": true, "dep": 0.25},
	"depression": {"sensitivity": 0.05, "threat_bias": 0.1, "social": 0.15, "panic": false, "dep": 0.8},
}
const COPING_IDS := ["breathe", "walk", "journal", "confide", "doomscroll", "hide", "drink"]


func _ready() -> void:
	watchdog_seconds = 240.0
	_test_profiles()
	_test_graph()
	_test_compute()
	_test_individuality()
	_test_hooks_and_mental()
	_test_content_settings()
	_test_synthetic_profiles()
	_test_diversity()
	_test_context()
	_test_stability()
	_test_agency()
	_test_schema_v5()
	_test_integration()
	_test_performance()
	finish("test_psyche")


func _cd(traits: Array, seed: int, preds := {}, hexaco := {}) -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = "Alex"
	d["personality"]["traits"] = traits
	d["personality"]["psyche_seed"] = seed
	d["personality"]["hexaco"] = hexaco
	d["mind"]["predispositions"] = preds
	return d


# ---------------------------------------------------------------- profily

func _test_profiles() -> void:
	section("Profily stavů jako data")
	var errs := PM.load_errors()
	check(errs.is_empty(), "profily v res://data/conditions se načtou bez chyb", str(errs))
	var profs := PM.profiles()
	check(profs.has("anxiety") and profs.has("depression"), "úzkost i deprese jsou datové profily")
	var same := true
	for id in LEGACY_REF:
		var c: Dictionary = MentalState.CONDITIONS.get(id, {})
		for k in LEGACY_REF[id]:
			if c.get(k) != LEGACY_REF[id][k]:
				same = false
	check(same, "MentalState.CONDITIONS = dřívější čísla (sensitivity, threat_bias, social, panic, dep)")
	check(String(MentalState.CONDITIONS["anxiety"]["label"]) == "Úzkostná porucha" and String(MentalState.CONDITIONS["depression"]["desc"]) != "",
		"popisky a popisy z dat")
	var ok_limits := true
	var ok_why := true
	for id in profs:
		for m in profs[id]["modulations"]:
			if String(m.get("why", "")).strip_edges().length() < 6:
				ok_why = false
			match String(m["op"]):
				"add":
					ok_limits = ok_limits and absf(float(m["amount"])) <= PM.MAX_ADD
				"mul":
					ok_limits = ok_limits and float(m["amount"]) >= PM.MUL_MIN and float(m["amount"]) <= PM.MUL_MAX
				"threshold":
					ok_limits = ok_limits and absf(float(m["amount"])) <= PM.MAX_THRESHOLD
				"couple":
					ok_limits = ok_limits and absf(float(m["w"])) <= PM.MAX_COUPLE
	check(ok_why, "každá modulace má srozumitelné „why“")
	check(ok_limits, "všechny modulace drží limity (add ≤ 0,3, mul 0,5–2, práh ≤ 0,2, vazba ≤ 0,5)")
	var tags_ok := true
	for id in profs:
		tags_ok = tags_ok and String(profs[id]["content_tag"]) == "mental_health"
	check(tags_ok, "všechny profily mají obsahový štítek mental_health")
	check(not profs.has("self_harm") and not profs.has("eating_disorder"), "sebepoškozování ani PPP nejsou hratelné profily")
	# Validace nevalidních profilů (fuzz).
	var base: Dictionary = (profs["anxiety"] as Dictionary).duplicate(true)
	var bad := []
	var b1 := base.duplicate(true)
	b1["modulations"][0]["amount"] = 0.5
	bad.append(b1)
	var b2 := base.duplicate(true)
	b2["modulations"][0]["why"] = ""
	bad.append(b2)
	var b3 := base.duplicate(true)
	b3["modulations"][0]["target"] = "D.neexistuje"
	bad.append(b3)
	var b4 := base.duplicate(true)
	b4["modulations"].append({"target": "D.impulsivity", "op": "mul", "amount": 3.0, "why": "příliš silné násobení"})
	bad.append(b4)
	var b5 := base.duplicate(true)
	b5["modulations"].append({"target": "S.stress", "op": "couple", "from": "S.stress", "w": 0.2, "why": "vazba sama na sebe"})
	bad.append(b5)
	var b6 := base.duplicate(true)
	b6["content_tag"] = ""
	bad.append(b6)
	var b7 := base.duplicate(true)
	b7["modulations"].append({"target": "action.talk.remove", "op": "add", "amount": 0.1, "why": "zakázat hovor"})
	bad.append(b7)
	var b8 := base.duplicate(true)
	b8["modulations"].append({"target": "D.threat_sensitivity", "op": "add", "amount": NAN, "why": "NaN v datech"})
	bad.append(b8)
	var b9 := base.duplicate(true)
	b9["modulations"].append({"target": "D.threat_sensitivity", "op": "set", "amount": 1.0, "why": "přímé nastavení"})
	bad.append(b9)
	var b10 := base.duplicate(true)
	b10["modulations"].append({"target": "D.social_threat", "op": "couple", "from": "S.stress", "w": 0.2, "why": "vazba nesmí měnit dispozici"})
	bad.append(b10)
	var b11 := base.duplicate(true)
	b11["severity"] = [0.5, 0.2]
	bad.append(b11)
	var b12 := base.duplicate(true)
	b12["legacy"]["panic"] = "ano"
	bad.append(b12)
	var rejected := 0
	for b in bad:
		if not PM.validate_profile(b).is_empty():
			rejected += 1
	check(rejected == bad.size(), "nevalidní profily odmítnuty (%d/%d)" % [rejected, bad.size()])
	check(PM.validate_profile(base).is_empty() and PM.validate_profile("text").size() > 0 and PM.validate_profile(null).size() > 0,
		"platný profil projde, jiný typ ne")


# ---------------------------------------------------------------- graf vazeb

func _test_graph() -> void:
	section("Graf vazeb: acykličnost a pevné pořadí")
	var chain := [
		{"from": "S.arousal", "target": "S.stress", "w": 0.2, "op": "couple"},
		{"from": "D.threat_sensitivity", "target": "S.arousal", "w": 0.1, "op": "couple"},
		{"from": "S.stress", "target": "S.burden", "w": 0.1, "op": "couple"},
	]
	var o := PM.order_edges(chain)
	var order: Array = []
	for e in o["order"]:
		order.append("%s>%s" % [e["from"], e["target"]])
	check(bool(o["ok"]) and order == ["D.threat_sensitivity>S.arousal", "S.arousal>S.stress", "S.stress>S.burden"],
		"řetěz se seřadí topologicky (%s)" % ", ".join(order))
	var o2 := PM.order_edges([chain[2], chain[0], chain[1]])
	check(str(o2["order"]) == str(o["order"]), "pořadí nezávisí na pořadí v datech (deterministické)")
	var cyc := [{"from": "S.stress", "target": "S.arousal", "w": 0.2}, {"from": "S.arousal", "target": "S.stress", "w": 0.2}]
	var oc := PM.order_edges(cyc)
	check(not bool(oc["ok"]) and (oc["cycle"] as Array).has("S.stress"), "cyklus se odhalí (%s)" % str(oc["cycle"]))
	# Soubor s cyklem: profil se načte, ale vazby se zahodí (nic nemůže oscilovat).
	var dir := "user://test_psyche_profiles"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	var pa := {"id": "cyc_a", "label_cs": "Test A", "content_tag": "mental_health", "severity": [0.0, 1.0], "modulations": [
		{"target": "S.arousal", "op": "couple", "from": "S.stress", "w": 0.2, "why": "test vazby A"}]}
	var pb := {"id": "cyc_b", "label_cs": "Test B", "content_tag": "mental_health", "severity": [0.0, 1.0], "modulations": [
		{"target": "S.stress", "op": "couple", "from": "S.arousal", "w": 0.2, "why": "test vazby B"},
		{"target": "D.impulsivity", "op": "add", "amount": 0.1, "why": "test přidání"}]}
	for p in [pa, pb]:
		var fh := FileAccess.open(dir.path_join(String(p["id"]) + ".json"), FileAccess.WRITE)
		fh.store_string(JSON.stringify(p))
		fh.close()
	var fh2 := FileAccess.open(dir.path_join("rozbity.json"), FileAccess.WRITE)
	fh2.store_string("{ tohle není json")
	fh2.close()
	var r := PM.load_profiles_from(dir)
	var any_couple := false
	for id in r["profiles"]:
		for m in r["profiles"][id]["modulations"]:
			if String(m["op"]) == "couple":
				any_couple = true
	check((r["profiles"] as Dictionary).size() == 2 and not any_couple and (r["profiles"]["cyc_b"]["modulations"] as Array).size() == 1,
		"cyklus mezi profily: vazby zahozeny, ostatní modulace zůstanou")
	check((r["errors"] as PackedStringArray).size() == 2, "chyby: poškozený JSON + cyklus (%s)" % str(r["errors"]))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))


# ---------------------------------------------------------------- výpočet

func _test_compute() -> void:
	section("Výpočet P a D")
	var p := PM.traits_personality(["vznetlivy", "uzkostlivy"])
	check(is_equal_approx(float(p["agreeableness"]), -0.5) and is_equal_approx(float(p["emotionality"]), 0.8), "osobnost z rysů (vznětlivý + úzkostlivý)")
	var all_traits: Array = PM.TRAIT_P.keys()
	check(all_traits.size() == 15 and Schema.TRAIT_COST.size() == 15, "každý rys má překlad na osobnost")
	var r := PM.compute(_cd(["optimista"], 7))
	var in_range := true
	for dim in PM.DIMS:
		in_range = in_range and float(r["D"][dim]) >= 0.0 and float(r["D"][dim]) <= 1.0
	check(in_range and (r["D"] as Dictionary).size() == 9, "9 dimenzí v 0..1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	var bad := 0
	for n in 300:
		var d := Randomizer.generate(rng, {}, [], {"include_mind": true})
		var hx := {}
		for a in Schema.HEXACO:
			if rng.randf() < 0.5:
				hx[a] = snappedf(rng.randf_range(-1.0, 1.0), 0.001)
		d["personality"]["hexaco"] = hx
		var rr := PM.compute(d)
		for dim in PM.DIMS:
			var v := float(rr["D"][dim])
			if is_nan(v) or v < 0.0 or v > 1.0:
				bad += 1
		var h := PM.hooks(rr)
		for k in ["arousal_decay_tau", "threat_gain", "crowd_gain", "unhealthy_appeal"]:
			if float(h[k]) < PM.HOOK_MIN or float(h[k]) > PM.HOOK_MAX:
				bad += 1
	check(bad == 0, "300 náhodných postav (i s HEXACO a predispozicemi): D v mezích, háčky 0,7–1,3 (%d chyb)" % bad)
	# Nic se nezapočítá dvakrát: bez individuality a bez explicitní osobnosti je reziduum přesně 0.
	var zero := true
	rng.seed = 77
	for n in 60:
		var d := Randomizer.generate(rng, {}, [], {"include_mind": true})
		var rr := PM.compute(d, {"individual": false})
		for dim in PM.DIMS:
			if absf(float(rr["residual"][dim])) > 1e-9:
				zero = false
	check(zero, "bez individuality a explicitní osobnosti je reziduum 0 (dnešní mechaniky nesou rysy i diagnózy)")
	# Explain: co, o kolik, proč.
	var ra := PM.compute(_cd(["uzkostlivy"], 1, {"anxiety": 0.8}))
	var ex := PM.explain(ra, "threat_sensitivity")
	var joined := "\n".join(ex)
	check(ex.size() >= 4 and joined.contains("Citlivost na hrozbu") and joined.contains("Úzkostná porucha") and joined.contains("rys Úzkostlivý")
		and joined.contains("osobnost emocionalita"), "explain uvádí dimenzi, úroveň a každý zdroj s důvodem")
	check(ex[1].begins_with("  +"), "nejsilnější vliv je první a má znaménko (%s)" % ex[1].strip_edges())
	check(PM.explain(ra, "neexistuje").is_empty(), "neznámá dimenze → prázdné vysvětlení")
	var neutral := PM.compute({}, {"individual": false})
	var all_half := true
	for dim in PM.DIMS:
		all_half = all_half and is_equal_approx(float(neutral["D"][dim]), 0.5)
	check(all_half, "bez rysů, profilů a individuality = průměr populace (0,5)")
	var junk := PM.compute({"personality": {"traits": "x", "hexaco": [1], "psyche_seed": "abc"}, "mind": 5})
	check((junk["D"] as Dictionary).size() == 9, "poškozená data nespadnou (výchozí hodnoty)")


func _test_individuality() -> void:
	section("Individualita a determinismus")
	var d := _cd(["uzkostlivy", "impulzivni"], 4242, {"anxiety": 0.6})
	var r1 := PM.compute(d)
	var r2 := PM.compute(d.duplicate(true))
	check(str(r1["D"]) == str(r2["D"]), "stejná data → stejné D")
	var code := Codec.encode_code(d)
	var dec := Codec.decode_code(code, {"mode": "strict"})
	var r3 := PM.compute(dec["data"])
	check(bool(dec["ok"]) and str(r3["D"]) == str(r1["D"]), "po sdílecím kódu a striktní validaci stejné D (server × klient)", str(dec["errors"]))
	var d2 := d.duplicate(true)
	d2["identity"]["first_name"] = "Karel"
	d2["identity"]["grammar"] = "f"
	d2["identity"]["gender_identity"] = "zena"
	check(str(PM.compute(d2)["D"]) == str(r1["D"]), "jméno, rod ani identita psychiku nemění")
	var d3 := d.duplicate(true)
	d3["personality"]["psyche_seed"] = 4243
	var r4 := PM.compute(d3)
	var diff := 0.0
	for dim in PM.DIMS:
		diff = maxf(diff, absf(float(r4["D"][dim]) - float(r1["D"][dim])))
	check(diff > 0.01, "jiný seed → jiná individualita (max. rozdíl %.3f)" % diff)
	# Velikost individuality je omezená.
	var worst := 0.0
	for s in 200:
		var rr := PM.compute(_cd(["uzkostlivy", "impulzivni"], s * 97, {"anxiety": 1.0}))
		for dim in PM.DIMS:
			worst = maxf(worst, absf(float(rr["residual"][dim])))
	check(worst < 0.25 and worst > 0.05, "individualita: znatelná, ale omezená (max |reziduum| %.3f)" % worst)
	# Explicitní osobnost, která se liší od rysů, se projeví.
	var calm := PM.hooks(PM.compute(_cd(["uzkostlivy"], 5, {}, {"emotionality": -0.8}), {"individual": false}))
	var reactive := PM.hooks(PM.compute(_cd(["optimista"], 5, {}, {"emotionality": 0.9}), {"individual": false}))
	check(float(calm["threat_gain"]) < 1.0 and float(reactive["threat_gain"]) > 1.0,
		"zadaná emocionalita proti rysům mění citlivost na hrozbu (%.2f / %.2f)" % [float(calm["threat_gain"]), float(reactive["threat_gain"])])
	check(float(reactive["arousal_decay_tau"]) > 1.0, "vyšší emocionalita → pomalejší doznívání aktivace (%.2f)" % float(reactive["arousal_decay_tau"]))


# ---------------------------------------------------------------- háčky v MentalState

func _ms(seed: int, conds := {}) -> MentalState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := MentalState.new(rng, "m")
	m.conditions = conds.duplicate()
	m.sensitivity = m.baseline_sensitivity()
	return m


func _ctx(now: float, cfg := {}) -> Dictionary:
	return {"energy": 70.0, "hunger": 70.0, "needs": {"energy": 70.0, "hunger": 70.0, "social": 70.0}, "sleeping": false,
		"night": false, "now": now, "cfg": cfg, "hour": 14}


func _test_hooks_and_mental() -> void:
	section("Háčky MentalState a neutrální regrese")
	# Bez set_psyche a s neutrálními háčky / háčky bez individuality: přesně stejný průběh.
	var a := _ms(11, {"anxiety": 0.6})
	var b := _ms(11, {"anxiety": 0.6})
	b.set_psyche({"full": PM.neutral_hooks(), "muted": PM.neutral_hooks(), "off": PM.neutral_hooks()})
	var c := _ms(11, {"anxiety": 0.6})
	var cd := _cd(["uzkostlivy"], 9, {"anxiety": 0.6})
	var hc := {}
	for mode in ["full", "muted", "off"]:
		hc[mode] = PM.hooks(PM.compute(cd, {"mode": mode, "individual": false}))
	c.set_psyche(hc)
	var same := true
	for step in 600:
		var now := float(step)
		if step % 90 == 0:
			for m in [a, b, c]:
				m.on_stressor("argue", 18.0)
		for m in [a, b, c]:
			m.tick(1.0, _ctx(now))
		if a.arousal != b.arousal or a.arousal != c.arousal or a.threat != c.threat or a.stress != c.stress:
			same = false
	check(same, "bez CharacterData, s neutrálními háčky i s daty bez individuality: bit po bitu stejný průběh")
	check(a.social_difficulty() == c.social_difficulty() and a.coping_appeal("drink", 50.0, 50.0, 600.0) == c.coping_appeal("drink", 50.0, 50.0, 600.0, false, {}),
		"náročnost hovorů i lákavost copingů beze změny")
	# Háčky působí správným směrem.
	var h_lo := PM.neutral_hooks()
	h_lo["arousal_decay_tau"] = 1.3
	h_lo["threat_gain"] = 1.3
	h_lo["social_cost"] = 0.15
	h_lo["unhealthy_appeal"] = 1.3
	h_lo["healthy_appeal"] = 0.85
	var x := _ms(3, {"anxiety": 0.5})
	var y := _ms(3, {"anxiety": 0.5})
	y.set_psyche({"full": h_lo})
	x.on_stressor("argue", 20.0)
	y.on_stressor("argue", 20.0)
	check(y.threat > x.threat * 1.25, "threat_gain zvětší vnímanou hrozbu (%.3f → %.3f)" % [x.threat, y.threat])
	x.arousal = 70.0
	y.arousal = 70.0
	x.threat = 0.0
	y.threat = 0.0
	x.stress = 10.0
	y.stress = 10.0
	for i in 40:
		x.tick(1.0, _ctx(100.0 + i))
		y.tick(1.0, _ctx(100.0 + i))
	check(y.arousal > x.arousal + 1.0, "pomalejší doznívání aktivace (%.1f vs %.1f po 40 min)" % [y.arousal, x.arousal])
	check(y.social_difficulty() > x.social_difficulty(), "vyšší sociální hrozba → náročnější hovory")
	x.arousal = 60.0
	y.arousal = 60.0
	check(y.coping_appeal("drink", 50.0, 50.0, 500.0) > x.coping_appeal("drink", 50.0, 50.0, 500.0) * 1.25
		and y.coping_appeal("breathe", 50.0, 50.0, 500.0) < x.coping_appeal("breathe", 50.0, 50.0, 500.0),
		"impulzivita: nezdravé copingy lákají víc, zdravé o trochu míň")
	var cr := _ms(3)
	var cr2 := _ms(3)
	var hcr := PM.neutral_hooks()
	hcr["crowd_gain"] = 0.7
	cr2.set_psyche({"full": hcr})
	cr.on_stressor("crowd", 6.0)
	cr2.on_stressor("crowd", 6.0)
	check(cr2.threat < cr.threat, "nižší sociální hrozba → dav vadí méně")


func _test_content_settings() -> void:
	section("Nastavení obsahu: plně / ztlumeně / vypnuto")
	var cd := _cd(["optimista"], 31, {"anxiety": 1.0, "depression": 1.0})
	var full := PM.compute(cd, {"mode": "full"})
	var muted := PM.compute(cd, {"mode": "muted"})
	var off := PM.compute(cd, {"mode": "off"})
	var cond_off := 0
	for rec in off["records"]:
		if String(rec["source"]).begins_with("cond:"):
			cond_off += 1
	check(cond_off == 0, "vypnuto: profily nemají žádný vliv")
	var sf := 0.0
	var sm := 0.0
	for rec in full["records"]:
		if String(rec["source"]).begins_with("cond:"):
			sf += absf(float(rec["delta"]))
	for rec in muted["records"]:
		if String(rec["source"]).begins_with("cond:"):
			sm += absf(float(rec["delta"]))
	check(sf > 0.0 and absf(sm - sf * 0.5) < 1e-6, "ztlumeno: závažnost nejvýš 0,5 (vliv %.3f → %.3f)" % [sf, sm])
	check(is_equal_approx(float(off["D"]["reward_sensitivity"]), float(PM.compute(_cd(["optimista"], 31), {"mode": "full"})["D"]["reward_sensitivity"])),
		"vypnuto = jako bez predispozic")
	# MentalState si vybírá háčky podle aktuálního nastavení (přepnutí za běhu).
	var m := _ms(5)
	var hf := PM.neutral_hooks()
	hf["threat_gain"] = 1.3
	var ho := PM.neutral_hooks()
	m.set_psyche({"full": hf, "muted": hf, "off": ho})
	check(MentalState.cfg_mode({"conditions": false, "episodes": false}) == "off" and MentalState.cfg_mode({"conditions": true, "episodes": false}) == "muted"
		and MentalState.cfg_mode({}) == "full" and MentalState.cfg_mode({"mode": "muted"}) == "muted", "režim obsahu se pozná z cfg")
	m.on_stressor("argue", 20.0, {"conditions": false, "episodes": false})
	var t_off := m.threat
	m.threat = 0.0
	m.on_stressor("argue", 20.0, {})
	check(m.threat > t_off * 1.25, "přepnutí na „vypnuto“ za běhu vypne i háčky profilů")
	# Validátor: při vypnutých tématech zmizí predispozice, osobnost a seed zůstanou (nejsou citlivé).
	var d := _cd(["optimista"], 99, {"anxiety": 0.5}, {"openness": 0.4})
	var rv := Validator.validate(d, {"mental_health": "off"})
	check(bool(rv["ok"]) and (rv["data"]["mind"]["predispositions"] as Dictionary).is_empty() and int(rv["data"]["personality"]["psyche_seed"]) == 99
		and float(rv["data"]["personality"]["hexaco"]["openness"]) == 0.4, "vypnuto na serveru: predispozice pryč, osobnost zůstane")


func _with_profiles(extra: Dictionary, fn: Callable) -> void:
	var saved: Dictionary = PM.profiles().duplicate(true)
	var merged := saved.duplicate(true)
	merged.merge(extra, true)
	PM._profiles = merged
	fn.call()
	PM._profiles = saved


func _test_synthetic_profiles() -> void:
	section("Profily bez „legacy“ (budoucí osy), komorbidita, práh a vazby")
	var future := {"id": "future_x", "label_cs": "Testovací stav", "content_tag": "mental_health", "severity": [0.0, 1.0], "modulations": [
		{"target": "D.impulsivity", "op": "add", "amount": 0.2, "scale": "severity", "why": "test: nová osa působí přes D"},
		{"target": "D.threat_sensitivity", "op": "add", "amount": 0.3, "scale": "severity", "why": "test: komorbidita 1"},
		{"target": "D.regulation_capacity", "op": "mul", "amount": 2.0, "scale": "severity", "why": "test: násobení odchylky"},
		{"target": "T.panic", "op": "threshold", "amount": -0.1, "scale": "severity", "why": "test: nižší práh ataky"},
		{"target": "S.burden", "op": "couple", "from": "S.arousal", "w": 0.3, "scale": "severity", "why": "test: chronická aktivace zatěžuje"}]}
	var future2 := {"id": "future_y", "label_cs": "Testovací stav 2", "content_tag": "mental_health", "severity": [0.0, 1.0], "modulations": [
		{"target": "D.threat_sensitivity", "op": "add", "amount": 0.3, "scale": "severity", "why": "test: komorbidita 2"},
		{"target": "T.panic", "op": "threshold", "amount": -0.2, "scale": "severity", "why": "test: práh 2"}]}
	check(PM.validate_profile(future).is_empty() and PM.validate_profile(future2).is_empty(), "testovací profily jsou platné")
	_with_profiles({"future_x": future, "future_y": future2}, func():
		var r := PM.compute(_cd(["optimista"], 1, {"future_x": 1.0}), {"individual": false})
		check(float(r["residual"]["impulsivity"]) > 0.19, "profil bez legacy se projeví v reziduu (+%.2f impulzivity)" % float(r["residual"]["impulsivity"]))
		var h := PM.hooks(r)
		check(float(h["unhealthy_appeal"]) > 1.3 - 1e-6, "…a v háčku (ořez na 1,3)")
		check(is_equal_approx(float(h["panic_shift"]), -10.0) and (h["couples"] as Array).size() == 1, "práh ataky −10 bodů, jedna vazba")
		var r2 := PM.compute(_cd(["optimista"], 1, {"future_x": 1.0, "future_y": 1.0}), {"individual": false})
		check(float(r2["D"]["threat_sensitivity"]) - float(PM.compute(_cd(["optimista"], 1), {"individual": false})["D"]["threat_sensitivity"]) <= PM.MAX_ADD + 1e-6,
			"komorbidita: dva profily dohromady nepřekročí limit jednoho (+0,3)")
		check(absf(float(r2["thresholds"]["T.panic"])) <= PM.MAX_THRESHOLD + 1e-9, "součet prahů ořezaný na 0,2")
		var rm := PM.compute(_cd(["uzkostlivy"], 1, {"future_x": 1.0}), {"individual": false})
		var base := PM.compute(_cd(["uzkostlivy"], 1), {"individual": false})
		var dev_b := float(base["D"]["regulation_capacity"]) - 0.5
		var dev_m := float(rm["D"]["regulation_capacity"]) - 0.5
		check(dev_b < 0.0 and absf(dev_m - 2.0 * dev_b) < 1e-6, "mul násobí odchylku od průměru (%.3f → %.3f)" % [dev_b, dev_m])
		# Vazba v MentalState: jednou za hodinu, deterministicky, ve stavu 0..1.
		var m := _ms(8)
		m.set_psyche({"full": h, "muted": h, "off": PM.neutral_hooks()})
		var m0 := _ms(8)
		for i in 180:
			m.arousal = 60.0
			m0.arousal = 60.0
			m.tick(1.0, _ctx(float(i)))
			m0.tick(1.0, _ctx(float(i)))
		check(m.dep.burden > m0.dep.burden + 0.03, "vazba aktivace → zátěž se projeví (%.3f vs %.3f)" % [m.dep.burden, m0.dep.burden])
		check(m.dep.burden <= 1.0 and not is_nan(m.dep.burden), "stav vazby zůstává v mezích")
	)


# ---------------------------------------------------------------- rozmanitost, kontext, stabilita

## Týden života jedné postavy: stresory podle plánu, volba copingu váženě podle lákavosti (stejná náhoda pro všechny).
func _week(hooks: Dictionary, seed_env: int, env := "neutral") -> Dictionary:
	var m := _ms(seed_env, {"anxiety": 0.6})
	m.trait_vuln = 0.22
	m.sensitivity = m.baseline_sensitivity()
	if not hooks.is_empty():
		m.set_psyche(hooks)
	var pick := RandomNumberGenerator.new()
	pick.seed = seed_env * 31 + 7
	var hist := {}
	var high := 0.0
	var stress_sum := 0.0
	var ar_sum := 0.0
	var n := 0
	for minute in 7 * 1440:
		var now := float(minute)
		var hour := (minute / 60) % 24
		var sleeping := hour < 7 or hour >= 23
		var ctx := _ctx(now)
		ctx["sleeping"] = sleeping
		ctx["hour"] = hour
		ctx["night"] = sleeping
		if minute % 1440 == 0:
			m.new_day()
		if not sleeping and minute % 120 == 37:
			var k := pick.randf()
			if env == "conflict" or (env == "neutral" and k < 0.35):
				m.on_stressor("argue", 14.0 + pick.randf() * 8.0)
			elif k < 0.6:
				m.on_stressor("crowd", 6.0)
			if env == "support" and k > 0.4:
				m.receive_support(60.0, 1.0, now)
		m.tick(1.0, ctx)
		if not sleeping and minute % 30 == 0:
			var tot := 0.0
			var ap := {}
			for id in COPING_IDS:
				var v := m.coping_appeal(id, 60.0, 60.0, now)
				ap[id] = v
				tot += v
			if tot > 1.0:
				var r := pick.randf() * tot
				for id in COPING_IDS:
					r -= float(ap[id])
					if r <= 0.0:
						hist[id] = int(hist.get(id, 0)) + 1
						m.apply_coping(id, 1.0, {"now": now, "energy": 60.0, "hunger": 60.0, "day": minute / 1440, "rel": 40.0})
						break
		if m.arousal > 50.0:
			high += 1.0
		stress_sum += m.stress
		ar_sum += m.arousal
		n += 1
	return {"hist": hist, "high_min": high, "stress": stress_sum / n, "arousal": ar_sum / n, "m": m}


func _tv(h1: Dictionary, h2: Dictionary) -> float:
	var t1 := 0.0
	var t2 := 0.0
	for id in COPING_IDS:
		t1 += float(h1.get(id, 0))
		t2 += float(h2.get(id, 0))
	if t1 <= 0.0 or t2 <= 0.0:
		return 1.0
	var s := 0.0
	for id in COPING_IDS:
		s += absf(float(h1.get(id, 0)) / t1 - float(h2.get(id, 0)) / t2)
	return 0.5 * s


func _test_diversity() -> void:
	section("Rozmanitost: 5 postav se stejným profilem")
	var res: Array = []
	for i in 5:
		var cd := _cd(["uzkostlivy", "impulzivni"], 1000 + i * 7919, {"anxiety": 0.6})
		res.append(_week(PM.hooks_by_mode(cd), 5, "conflict"))   # stejné (napjaté) prostředí i náhoda, liší se jen individualita
	var tvs: Array = []
	var highs: Array = []
	var ars: Array = []
	var pairs_same := 0
	for i in 5:
		highs.append(int(res[i]["high_min"]))
		ars.append(snappedf(float(res[i]["arousal"]), 0.01))
		for j in range(i + 1, 5):
			var tv := _tv(res[i]["hist"], res[j]["hist"])
			tvs.append(tv)
			var da := absf(float(res[i]["arousal"]) - float(res[j]["arousal"])) / maxf(float(res[i]["arousal"]), 1.0)
			if tv < 0.02 and da < 0.01:
				pairs_same += 1
	var mean_tv := 0.0
	for t in tvs:
		mean_tv += float(t)
	mean_tv /= tvs.size()
	var distinct := {}
	for a in ars:
		distinct[a] = true
	var min_tv := 1.0
	for t in tvs:
		min_tv = minf(min_tv, float(t))
	print("    průměrná aktivace: %s, minuty nad 50: %s, vzdálenost histogramů copingů průměr %.3f / min %.3f" % [str(ars), str(highs), mean_tv, min_tv])
	check(distinct.size() == 5, "všech 5 postav má jiný průběh aktivace (průměry %s)" % str(ars))
	var spread := (float(ars.max()) - float(ars.min())) / maxf(float(ars.max()), 1.0)
	check(spread > 0.05, "rozdíl průměrné aktivace je měřitelný (%.1f %%)" % (spread * 100.0))
	check(pairs_same == 0, "každá z 10 dvojic se liší volbou copingů (vzdálenost ≥ 0,02) nebo aktivací (≥ 1 %%) – shodných %d" % pairs_same)
	check(mean_tv > 0.03, "histogramy copingů se liší (průměrná vzdálenost %.3f > 0,03)" % mean_tv)
	# A bez individuality by byly klony.
	var c1 := _week({}, 5)
	var c2 := _week({}, 5)
	check(int(c1["high_min"]) == int(c2["high_min"]) and _tv(c1["hist"], c2["hist"]) == 0.0, "bez individuality stejný průběh (kontrola testu)")


func _test_context() -> void:
	section("Kontext: opora × neutrální × konflikt")
	var cd := _cd(["uzkostlivy"], 555, {"anxiety": 0.6})
	var hk := PM.hooks_by_mode(cd)
	var sup := _week(hk, 9, "support")
	var neu := _week(hk, 9, "neutral")
	var con := _week(hk, 9, "conflict")
	print("    průměrný stres: opora %.1f, neutrální %.1f, konflikt %.1f" % [float(sup["stress"]), float(neu["stress"]), float(con["stress"])])
	check(float(sup["stress"]) < float(neu["stress"]) and float(neu["stress"]) < float(con["stress"]), "stejná postava: opora < neutrální < konflikt (stres)")
	check(float(con["high_min"]) > float(sup["high_min"]), "v konfliktu víc času ve vysoké aktivaci")


func _test_stability() -> void:
	section("Stabilita: 16 seedů × 14 dní")
	var nan := 0
	var runaway := 0
	var recover_fail := 0
	var osc := 0
	for s in 16:
		var hx := {}
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		for a in Schema.HEXACO:
			hx[a] = [-1.0, 1.0][rng.randi_range(0, 1)]
		var cd := _cd(["uzkostlivy", "vznetlivy", "impulzivni"], s * 131, {"anxiety": 1.0, "depression": 1.0}, hx)
		var m := _ms(s, {"anxiety": 1.0, "depression": 1.0})
		m.set_psyche(PM.hooks_by_mode(cd))
		var hi_streak := 0
		var crossings := 0
		var above := false
		for minute in 14 * 1440:
			var hour := (minute / 60) % 24
			var sleeping := hour < 7 or hour >= 23
			var ctx := _ctx(float(minute))
			ctx["sleeping"] = sleeping
			ctx["hour"] = hour
			if minute % 1440 == 0:
				m.new_day()
			if not sleeping and minute % 45 == 0 and rng.randf() < 0.5:
				m.on_stressor(["argue", "insulted", "crowd", "stigma"][rng.randi_range(0, 3)], rng.randf_range(4.0, 20.0))
			m.tick(1.0, ctx)
			for v in [m.stress, m.arousal, m.threat, m.sensitivity, m.dep.burden]:
				if is_nan(float(v)) or is_inf(float(v)):
					nan += 1
			hi_streak = hi_streak + 1 if m.stress > 97.0 else 0
			if hi_streak > 1440:
				runaway += 1
				hi_streak = 0
			if minute % 60 == 0:
				var a := m.arousal > 60.0
				if a != above:
					crossings += 1
					above = a
		if crossings > 14 * 24 * 0.8:
			osc += 1
		# Klid 12 hodin (spánek, jídlo, žádné stresory) → aktivace se vrátí dolů.
		for minute in 720:
			var ctx2 := _ctx(20160.0 + minute)
			ctx2["sleeping"] = minute > 120
			m.tick(1.0, ctx2)
		if m.arousal > 40.0:
			recover_fail += 1
	check(nan == 0, "žádné NaN ani nekonečno")
	check(runaway == 0, "žádný stav neuteče (stres > 97 nejvýš den v kuse)")
	check(osc == 0, "žádné oscilace (aktivace nepřeskakuje hodinu co hodinu)")
	check(recover_fail == 0, "po 12 h klidu se aktivace vrátí pod 40 u všech 16 seedů (%d ne)" % recover_fail)


func _test_agency() -> void:
	section("Agency: nic se neodebere, nic se nevynutí")
	var extreme := PM.neutral_hooks()
	extreme["threat_gain"] = PM.HOOK_MAX
	extreme["arousal_decay_tau"] = PM.HOOK_MAX
	extreme["social_cost"] = PM.SOCIAL_COST_MAX
	extreme["unhealthy_appeal"] = PM.HOOK_MAX
	extreme["healthy_appeal"] = 0.85
	var m := _ms(2, {"anxiety": 1.0})
	m.set_psyche({"full": extreme})
	m.arousal = 95.0
	m.stress = 95.0
	m.threat = 1.0
	var all_pos := true
	for id in COPING_IDS:
		all_pos = all_pos and m.coping_appeal(id, 20.0, 20.0, 0.0) > 0.0
	check(all_pos, "v nejhorším stavu s krajními háčky lákají všechny copingy (žádný nezmizí)")
	var diff := m.social_difficulty()
	check(diff <= 1.0 and 1.0 - diff * 0.5 >= 0.5, "sociální akce zůstanou volitelné (plánovač je tlumí nejvýš na polovinu)")
	var ok_hooks := true
	for k in ["arousal_decay_tau", "threat_gain", "crowd_gain", "unhealthy_appeal", "healthy_appeal"]:
		ok_hooks = ok_hooks and float(extreme[k]) > 0.0
	check(ok_hooks, "háčky jsou kladné násobiče (mění cenu, nikdy neruší akci)")
	var ops_ok := true
	for op in PM.OPS:
		ops_ok = ops_ok and not String(op).contains("remove") and not String(op).contains("force")
	check(ops_ok and PM.OPS.size() == 4, "profil umí jen add / mul / threshold / couple (žádné „odeber akci“)")


# ---------------------------------------------------------------- schéma v5

func _test_schema_v5() -> void:
	section("Schéma v5: osobnost, seed, soukromí, migrace")
	check(Schema.VERSION >= 5 and Schema.HEXACO.size() == 6, "verze ≥ 5 (aktuálně %d), 6 os osobnosti" % Schema.VERSION)
	check(not Schema.is_public("personality", "hexaco") and not Schema.is_public("personality", "psyche_seed")
		and Schema.is_public("personality", "traits"), "osobnost a seed jsou soukromé (rysy veřejné jako dřív)")
	var c = CharacterData.create()
	c.set_path_value("personality.hexaco", {"emotionality": 0.7})
	c.set_path_value("personality.psyche_seed", 321)
	var pub: Dictionary = c.public_snapshot()
	check(not (pub.get("personality", {}) as Dictionary).has("hexaco") and not (pub.get("personality", {}) as Dictionary).has("psyche_seed"),
		"veřejný snapshot je neobsahuje")
	var leak := pub.duplicate(true)
	leak["personality"]["hexaco"] = {"openness": 0.1}
	check(not bool(Validator.validate(leak, {"public_only": true})["ok"]), "podstrčená osobnost ve veřejném snapshotu = chyba")
	var priv: Dictionary = c.private_part()
	check(priv.get("personality", {}).has("hexaco") and priv["personality"].has("psyche_seed"), "soukromá část je nese (vlastník/server)")
	# Validace.
	var bad_vals := [{"emotionality": 1.5}, {"emotionality": NAN}, {"emotionality": "vysoká"}, {"neexistuje": 0.1}, [0.1], "x", {"openness": INF}, {"honesty": null}]
	var rejected := 0
	var repaired_ok := 0
	for bv in bad_vals:
		var d := _cd(["optimista"], 1)
		d["personality"]["hexaco"] = bv
		if not bool(Validator.validate(d)["ok"]):
			rejected += 1
		var rr := Validator.validate(d, {"mode": "repair"})
		var hx = rr["data"]["personality"]["hexaco"]
		var good := typeof(hx) == TYPE_DICTIONARY
		if good:
			for k in hx:
				good = good and Schema.HEXACO.has(k) and float(hx[k]) >= -1.0 and float(hx[k]) <= 1.0
		if good:
			repaired_ok += 1
	check(rejected == bad_vals.size(), "server odmítne všech %d nevalidních osobností (%d)" % [bad_vals.size(), rejected])
	check(repaired_ok == bad_vals.size(), "opravný režim vrátí vždy platnou osobnost")
	var seeds_bad := [-1, 65536, 3.5, "7", NAN, null]
	var srej := 0
	for sv in seeds_bad:
		var d := _cd(["optimista"], 1)
		d["personality"]["psyche_seed"] = sv
		if not bool(Validator.validate(d)["ok"]):
			srej += 1
	check(srej == seeds_bad.size(), "neplatný psyche_seed odmítnut (%d/%d)" % [srej, seeds_bad.size()])
	var okd := _cd(["optimista"], 65535, {}, {"emotionality": 0.123456, "openness": -1.0})
	var rok := Validator.validate(okd)
	check(bool(rok["ok"]) and float(rok["data"]["personality"]["hexaco"]["emotionality"]) == 0.123, "platná osobnost projde (kvantovaná na 1/1000)", str(rok["errors"]))
	# Migrace v4 → v5.
	var v4 := _cd(["hravy"], 0)
	v4["v"] = 4
	(v4["personality"] as Dictionary).erase("hexaco")
	(v4["personality"] as Dictionary).erase("psyche_seed")
	var m4 := Codec.from_dict(v4.duplicate(true))
	check(bool(m4["ok"]) and int(m4["from_version"]) == 4 and int(m4["data"]["v"]) == Schema.VERSION, "v4 se načte jako aktuální verze", str(m4["errors"]))
	check((m4["data"]["personality"]["hexaco"] as Dictionary).is_empty(), "hexaco {} = osobnost z rysů (chování beze změny)")
	var renamed := v4.duplicate(true)
	renamed["identity"]["first_name"] = "Jiný"
	var m4b := Codec.from_dict(renamed)
	check(int(m4b["data"]["personality"]["psyche_seed"]) == int(m4["data"]["personality"]["psyche_seed"]), "seed z uid, ne ze jména (přejmenování ho nezmění)")
	var other := v4.duplicate(true)
	other["uid"] = CharacterData.new_uid()
	check(int(Codec.from_dict(other)["data"]["personality"]["psyche_seed"]) != int(m4["data"]["personality"]["psyche_seed"]), "jiné uid → jiný seed")
	var keep := v4.duplicate(true)
	keep["personality"]["psyche_seed"] = 77
	keep["personality"]["hexaco"] = {"honesty": 0.5}
	var mk := Codec.from_dict(keep)
	check(int(mk["data"]["personality"]["psyche_seed"]) == 77 and float(mk["data"]["personality"]["hexaco"]["honesty"]) == 0.5, "existující hodnoty migrace nepřepíše")
	var v0 := {"name": "Stará Postava", "female": true, "traits": ["optimista"]}
	var m0 := Codec.from_dict(v0)
	check(bool(m0["ok"]) and int(m0["data"]["v"]) == Schema.VERSION and m0["data"]["personality"].has("psyche_seed"), "v0 → aktuální verze (s psyche_seed)", str(m0["errors"]))
	# Round-trip.
	var rt := _cd(["knihomol"], 1234, {}, {"openness": 0.9, "extraversion": -0.3})
	var dec := Codec.decode_code(Codec.encode_code(rt), {"mode": "strict"})
	check(bool(dec["ok"]) and dec["data"]["personality"]["hexaco"] == rt["personality"]["hexaco"] and int(dec["data"]["personality"]["psyche_seed"]) == 1234,
		"sdílecí kód zachová osobnost i seed")
	# Generátor.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seeds := {}
	var valid := true
	for n in 200:
		var g := Randomizer.generate(rng)
		valid = valid and bool(Validator.validate(g)["ok"])
		seeds[int(g["personality"]["psyche_seed"])] = true
	check(valid and seeds.size() > 190, "generátor: platné postavy, seed se losuje (%d různých z 200)" % seeds.size())
	var base := Randomizer.generate(rng)
	base["personality"]["psyche_seed"] = 4321
	check(int(Randomizer.generate(rng, base, ["personality.psyche_seed"])["personality"]["psyche_seed"]) == 4321, "zámek seedu funguje")


func _test_integration() -> void:
	section("Integrace: SimAgent z CharacterData")
	var agent = SimAgentScript.new()
	agent.setup("Alex Test", "m", ["uzkostlivy", "impulzivni"], Color(0.4, 0.5, 0.6), 7, null)
	check(agent.mental.psy_hooks.is_empty(), "bez CharacterData neutrální háčky")
	var cd := _cd(["uzkostlivy", "impulzivni"], 2468, {"anxiety": 0.6})
	agent.apply_character_private(cd)
	var hk: Dictionary = agent.mental.psy_hooks
	check(hk.has("full") and hk.has("muted") and hk.has("off"), "apply_character_private nastaví háčky pro všechny režimy obsahu")
	check(str(hk["full"]["D"]) == str(PM.compute(cd)["D"]), "háčky odpovídají PsycheModel.compute")
	check(agent.mental.conditions.has("anxiety"), "predispozice dál nastavené (stávající cesta)")
	agent.free()


func _test_performance() -> void:
	section("Výkon")
	var cd := _cd(["uzkostlivy", "impulzivni", "knihomol"], 99, {"anxiety": 0.7, "depression": 0.4}, {"openness": 0.5})
	var t0 := Time.get_ticks_usec()
	for i in 100:
		PM.compute(cd)
	var ms := float(Time.get_ticks_usec() - t0) / 100000.0
	check(ms < 2.0, "compute %.3f ms (< 2 ms)" % ms)
	var t1 := Time.get_ticks_usec()
	PM.hooks_by_mode(cd)
	var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
	check(ms2 < 6.0, "háčky pro 3 režimy %.3f ms (< 6 ms, jednou při vstupu postavy)" % ms2)
