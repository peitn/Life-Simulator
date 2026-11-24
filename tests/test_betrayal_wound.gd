extends "res://tests/test_base.gd"
## BetrayalWound (scripts/sim/betrayal_wound.gd): psychické následky zrady – ruminace, stažení,
## sebehodnota, jizva v důvěře, zotavení; integrace do SimAgent / PsycheExt / main (drb), uložení a soukromí.
## Spuštění: godot_run scene=res://tests/test_betrayal_wound.tscn
const BetrayalWound := preload("res://scripts/sim/betrayal_wound.gd")
const PsycheExt := preload("res://scripts/sim/psyche_ext.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")
const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const GameSave := preload("res://scripts/save/game_save.gd")
const Main := preload("res://main.gd")
var clock: Node
var settings: Node


func _ready() -> void:
	watchdog_seconds = 110.0
	clock = get_node("/root/GameClock")
	clock.running = false
	settings = get_node("/root/GameSettings")
	settings.persist = false
	settings.reset()
	_run.call_deferred()


func _run() -> void:
	_units()
	_behaviour()
	_fuzz()
	await _scene()
	settings.reset()
	clock.running = false
	finish("test_betrayal_wound")


static func _no_digits(lines: PackedStringArray) -> bool:
	var re := RegEx.new()
	re.compile("\\d")
	for l in lines:
		if re.search(l) != null:
			return false
	return true


# ------------------------------------------------------------------ jednotky
func _units() -> void:
	section("Otevření rány")
	var b = BetrayalWound.new()
	check(b.is_empty() and b.open("", "X", "", "", 1.0, 0.0, 0.0).is_empty(), "prázdný klíč → nic")
	var w: Dictionary = b.open("u_petr", "Petr Novák", "u_eli", "Eliška Malá", 1.0, 0.0, 0.0)
	check(is_equal_approx(float(w["acute"]), 0.95) and is_equal_approx(float(w["scar"]), 0.7), "sev 1: akutní 0,95, jizva 0,7 (%.3f / %.3f)" % [w["acute"], w["scar"]])
	check(String(w["lover"]) == "u_eli" and int(w["count"]) == 1, "milenka/milenec zapsán, počet 1")
	var b2 = BetrayalWound.new()
	var w2: Dictionary = b2.open("u_a", "A", "", "", 0.6, 0.0, 0.0)
	check(is_equal_approx(float(w2["acute"]), 0.79) and is_equal_approx(float(w2["scar"]), 0.54), "sev 0,6: 0,79 / 0,54")
	w2["processed"] = 0.6
	b2.open("u_a", "A", "", "", 0.6, 0.0, 0.0)
	check(is_equal_approx(float(w2["acute"]), 1.0 - 0.21 * 0.21) and is_equal_approx(float(w2["scar"]), 0.64),
		"opakovaná zrada od stejného člověka bolí víc (%.4f) a jizva se prohloubí (%.2f)" % [w2["acute"], w2["scar"]])
	check(is_equal_approx(float(w2["processed"]), 0.3) and int(w2["count"]) == 2 and b2.wounds.size() == 1,
		"… a srazí dosavadní zpracování na polovinu; pořád jedna rána")
	var b3 = BetrayalWound.new()
	check(String(b3.open("u_x", "X", "u_x", "X", 0.5, 0.0, 0.0)["lover"]) == "", "milenec = ten, kdo zradil → ignorováno")

	section("Hojení v čase (líně, deterministicky)")
	var h = BetrayalWound.new()
	h.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	h.tick(20160.0)
	check(absf(float(h.wounds[0]["acute"]) - 0.95 * exp(-1.0)) < 1e-6, "po 14 dnech akutní × e⁻¹ (%.4f)" % h.wounds[0]["acute"])
	var hp = BetrayalWound.new()
	hp.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	hp.wounds[0]["processed"] = 0.5
	hp.tick(20160.0)
	check(float(hp.wounds[0]["acute"]) < float(h.wounds[0]["acute"]) * 0.6, "zpracování hojí rychleji (%.3f)" % hp.wounds[0]["acute"])
	var before := float(h.wounds[0]["acute"])
	h.tick(100.0)
	check(is_equal_approx(float(h.wounds[0]["acute"]), before), "zpětný chod času (rewind) nic nevrací ani nezhoršuje")
	h.tick(60.0 * 1440.0)
	check(float(h.wounds[0]["acute"]) < 0.02 and float(h.wounds[0]["scar"]) > 0.4 and h.suspicion_mult(1.0) > 1.2,
		"po 60 dnech akutní bolest odezněla, jizva zůstává (%.2f) → hypervigilance %.2f" % [h.wounds[0]["scar"], h.suspicion_mult(1.0)])
	check(h.suspicion_mult(0.0) == 1.0, "vypnutá témata: násobič podezření přesně 1")
	h.tick(900.0 * 1440.0)
	check(h.is_empty(), "cesta k zotavení není uzavřená: po letech i jizva vybledne (rána zmizí)")

	section("Alkohol: otupí, pak se vrátí")
	var n = BetrayalWound.new()
	n.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	check(n.on_numb(0.0), "otupení při akutní bolesti")
	check(is_equal_approx(n.felt(n.wounds[0], 10.0), 0.475), "pocitově poloviční (%.3f)" % n.felt(n.wounds[0], 10.0))
	n.tick(200.0)
	var pure := 0.95 * exp(-200.0 / BetrayalWound.ACUTE_TAU)
	check(float(n.wounds[0]["acute"]) > pure + 0.004 and float(n.wounds[0]["rebound"]) == 0.0,
		"po 3 h rebound: bolest vyšší než bez pití (%.4f > %.4f), jednorázově" % [n.wounds[0]["acute"], pure])
	var nn = BetrayalWound.new()
	nn.open("u_p", "Petr", "", "", 0.0, 0.0, 0.0)
	nn.wounds[0]["acute"] = 0.1
	check(not nn.on_numb(0.0), "slabou bolest není co otupovat")
	var ch = BetrayalWound.new()
	ch.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	var reliefs := []
	for i in 5:
		ch.on_numb(60.0 * i)
		reliefs.append(ch.felt(ch.wounds[0], 60.0 * i + 1.0) / float(ch.wounds[0]["acute"]))
	check(reliefs[0] < reliefs[1] and reliefs[1] < reliefs[2] and reliefs[4] >= 0.999 and float(ch.wounds[0]["rebound"]) > 0.25,
		"řetězení pití: tolerance (úleva %s), rebound se sčítá (%.2f) – zapít to natrvalo nejde" % [str(reliefs), ch.wounds[0]["rebound"]])
	ch.tick(60.0 * 4 + 200.0)
	check(float(ch.wounds[0]["rebound"]) == 0.0 and int(ch.wounds[0]["numb_n"]) == 0, "po odeznění rebound dopadne naplno a tolerance se vynuluje")
	var na = BetrayalWound.new()
	na.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	na.tick(NAN)
	na.on_reminder("u_p", 0.2, NAN)
	na.on_numb(INF)
	na.on_support(1.0, NAN)
	na.on_repair("u_p", true, NAN)
	check(is_equal_approx(float(na.wounds[0]["acute"]), 0.95) and BetrayalWound.validate_snapshot(na.to_dict()) and na.intrusive_thought(NAN, true, 1.0).is_empty(),
		"NaN/INF čas: žádná změna, stav zůstává platný (audit Gemini)")

	section("Spouštěče, opora, omluva")
	var r = BetrayalWound.new()
	r.open("u_p", "Petr", "u_e", "Eliška", 0.6, 0.0, 0.0)
	r.wounds[0]["acute"] = 0.3
	check(r.on_reminder("u_p", 0.15, 1000.0) and float(r.wounds[0]["acute"]) > 0.3, "vidět ho/ji: rána se rozdře")
	check(not r.on_reminder("u_e", 0.15, 1100.0), "do 6 h podruhé ne (ani přes milence)")
	check(r.on_reminder("u_e", 0.15, 1400.0), "po 6 h ano – i milenec je spouštěč")
	check(not r.on_reminder("u_jiny", 0.15, 5000.0), "cizí člověk nic nespustí")
	var a0 := float(r.wounds[0]["acute"])
	check(not r.on_support(0.5, 1500.0, "u_p") and float(r.wounds[0]["processed"]) == 0.0, "svěřit se tomu, kdo zradil, se nepočítá")
	check(r.on_support(0.5, 1500.0, "u_friend") and is_equal_approx(float(r.wounds[0]["processed"]), 0.09), "svěření kamarádce: zpracování 0,09")
	check(float(r.wounds[0]["acute"]) < a0, "… a akutní bolest povolí")
	var rp = BetrayalWound.new()
	rp.open("u_p", "Petr", "", "", 0.6, 0.0, 0.0)
	var rq = BetrayalWound.new()
	rq.open("u_p", "Petr", "", "", 0.6, 0.0, 0.0)
	rp.on_repair("u_p", true, 0.0)
	rq.on_repair("u_p", false, 0.0)
	check(float(rp.wounds[0]["processed"]) > float(rq.wounds[0]["processed"]) and float(rq.wounds[0]["processed"]) > 0.0,
		"přijatá omluva zpracuje víc než částečně přijatá")
	check(float(rp.wounds[0]["scar"]) > 0.45, "odpuštění neznamená zapomenout (jizva %.2f)" % rp.wounds[0]["scar"])
	check(not rp.on_repair("u_nikdo", true, 0.0), "omluva od někoho, kdo nezradil, nic nemění")

	section("Rušivé otázky a obrácení proti sobě")
	var t = BetrayalWound.new()
	t.open("u_p", "Petr Novák", "u_e", "Eliška", 1.0, 0.0, 0.0)
	check(t.intrusive_thought(600.0, true, 0.0).is_empty(), "vypnutá témata: žádné myšlenky")
	var th: Dictionary = t.intrusive_thought(600.0, true, 1.0)
	check(not th.is_empty() and not String(th["text"]).contains("{name}") and not String(th["text"]).contains("{lover}"), "otázka: „%s“" % th.get("text", ""))
	check(t.intrusive_thought(630.0, true, 1.0).is_empty(), "nejvýš jednou za hodinu")
	var blame0 := 0
	var blame1 := 0
	var t1 = BetrayalWound.new()
	t1.open("u_p", "Petr", "", "", 1.0, 0.0, 0.9)
	for i in 60:
		var x: Dictionary = t.intrusive_thought(660.0 + 60.0 * i, true, 1.0)
		if not x.is_empty() and bool(x["self_blame"]):
			blame0 += 1
		var y: Dictionary = t1.intrusive_thought(660.0 + 60.0 * i, true, 1.0)
		if not y.is_empty() and bool(y["self_blame"]):
			blame1 += 1
	for s in BetrayalWound.SELF_BLAME:
		check(String(s).contains("?") and (String(s).contains("vnucuje") or String(s).contains("myšlenka")), "sebeobviňování s odstupem, ne jako pravda: „%s“" % s)
	check(blame0 == 0 and blame1 > 5, "sebeobviňování jen při vnitřním přesvědčení (%d vs %d ze 60)" % [blame0, blame1])
	check(t1.self_worth_hit(0.0) > t.self_worth_hit(0.0) * 2.0, "zásah do sebehodnoty škáluje přesvědčení (%.2f vs %.2f)" % [t1.self_worth_hit(0.0), t.self_worth_hit(0.0)])
	var weak = BetrayalWound.new()
	weak.open("u_p", "Petr", "", "", 0.0, 0.0, 0.0)
	weak.wounds[0]["acute"] = 0.45
	check(weak.intrusive_thought(600.0, false, 1.0).is_empty() and not weak.intrusive_thought(600.0, true, 1.0).is_empty(),
		"v rozptýlení se střední bolest nevtírá, v nečinnosti ano")


func _behaviour() -> void:
	section("Chování: stažení, coping, vyhýbání (omezené násobiče)")
	var b = BetrayalWound.new()
	b.open("u_p", "Petr", "u_e", "Eliška", 1.0, 0.0, 0.0)
	var ids := ["confide", "chat", "flirt", "drink", "journal", "seek_help", "ask_out", "doomscroll", "watch_tv", "sleep"]
	var all_one := true
	for id in ids:
		var act: Dictionary = ActionLibrary.get_action(id)
		if b.action_weight(act, 0.0, 0.0) != 1.0:
			all_one = false
	check(all_one, "vypnutá témata: všechny násobiče přesně 1")
	var conf := b.action_weight(ActionLibrary.get_action("confide"), 1.0, 0.0)
	var chat := b.action_weight(ActionLibrary.get_action("chat"), 1.0, 0.0)
	var flirt := b.action_weight(ActionLibrary.get_action("flirt"), 1.0, 0.0)
	var drink := b.action_weight(ActionLibrary.get_action("drink"), 1.0, 0.0)
	var tv := b.action_weight(ActionLibrary.get_action("watch_tv"), 1.0, 0.0)
	check(conf > 1.4 and chat < 0.8 and flirt < 0.6 and drink > 1.2, "svěřit se %.2f↑, povídat %.2f↓, flirt %.2f↓, pití %.2f↑" % [conf, chat, flirt, drink])
	check(tv == 1.0, "nesouvisející akce beze změny")
	var lo := INF
	var hi := -INF
	for id in ids:
		var v := b.action_weight(ActionLibrary.get_action(id), 1.0, 0.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(lo >= 0.4 and hi <= 2.0, "nic se nevynucuje ani nezakazuje (%.2f..%.2f)" % [lo, hi])
	var chat_a: Dictionary = ActionLibrary.get_action("chat")
	var conf_a: Dictionary = ActionLibrary.get_action("confide")
	check(b.target_weight("u_p", conf_a, 1.0, 0.0) < 0.35 and b.target_weight("u_p", chat_a, 1.0, 0.0) < 0.55,
		"toho, kdo zradil, se straní (svěřit %.2f, povídat %.2f)" % [b.target_weight("u_p", conf_a, 1.0, 0.0), b.target_weight("u_p", chat_a, 1.0, 0.0)])
	check(b.target_weight("u_e", chat_a, 1.0, 0.0) < 0.5 and b.target_weight("u_friend", chat_a, 1.0, 0.0) == 1.0, "milenky/milence taky; ostatních ne")
	check(b.target_weight("u_p", chat_a, 0.0, 0.0) == 1.0, "vypnutá témata: výběr lidí beze změny")
	check(b.help_need(0.0) > 0.4 and b.sleep_quality_mult(1.0, 0.0) < 0.9 and b.sleep_quality_mult(0.0, 0.0) == 1.0,
		"silná nezpracovaná bolest: potřeba pomoci %.2f, horší spánek" % b.help_need(0.0))
	b.wounds[0]["processed"] = 1.0
	check(b.help_need(0.0) == 0.0, "zpracovaná rána už k terapii netlačí")
	b.wounds[0]["processed"] = 0.0
	var me: Array = b.mood_entries(1.0, 0.0)
	check(me.size() >= 1 and String(me[0]["id"]) == "bw_zrada" and float(me[0]["strength"]) < 0.0, "moodlet „Zrada pořád bolí“")
	check(b.mood_entries(0.0, 0.0).is_empty(), "vypnutá témata: žádný moodlet")
	var bb = BetrayalWound.new()
	bb.open("u_p", "Petr", "", "", 1.0, 0.0, 0.9)
	var ids2 := []
	for e in bb.mood_entries(0.5, 0.0):
		ids2.append(String(e["id"]))
	check(ids2.has("bw_sebehodnota"), "silné přesvědčení: moodlet „Jako by chyba byla ve mně“")
	var pl: PackedStringArray = bb.private_lines(1.0, 0.0)
	check(pl.size() >= 2 and pl[0].begins_with("Zrada (Petr)") and _no_digits(pl), "soukromé věty jen slovy: %s" % " | ".join(pl))
	check(", ".join(pl).contains("neznamená to, že je to pravda"), "zkreslené přesvědčení se nepotvrzuje")
	check(bb.private_lines(0.0, 0.0).is_empty(), "vypnutá témata: žádné věty")
	var ev = BetrayalWound.new()
	for i in 4:
		ev.open("u%d" % i, "N%d" % i, "", "", 1.0 if i > 0 else 0.0, 0.0, 0.0)
	ev.open("u4", "N4", "", "", 1.0, 0.0, 0.0)
	var abouts := []
	for wd in ev.wounds:
		abouts.append(String(wd["about"]))
	check(ev.wounds.size() == BetrayalWound.MAX_WOUNDS and not abouts.has("u0") and abouts.has("u4"), "limit 4 ran, vytlačí se nejslabší (%s)" % ",".join(abouts))


func _fuzz() -> void:
	section("Uložení: round-trip a nevalidní data")
	var b = BetrayalWound.new()
	b.open("u_p", "Petr", "u_e", "Eliška", 0.8, 100.0, 0.4)
	b.on_numb(150.0)
	var j = JSON.parse_string(JSON.stringify(b.to_dict()))
	check(BetrayalWound.validate_snapshot(j), "uložený stav je platný")
	var c = BetrayalWound.new()
	check(c.from_dict(j) and c.wounds.size() == 1, "načtení")
	var same := true
	for k in BetrayalWound.W_KEYS:
		if typeof(b.wounds[0][k]) == TYPE_STRING:
			same = same and String(b.wounds[0][k]) == String(c.wounds[0][k])
		else:
			same = same and is_equal_approx(float(b.wounds[0][k]), float(c.wounds[0][k]))
	check(same, "round-trip beze změny (všech %d polí)" % BetrayalWound.W_KEYS.size())
	var good: Dictionary = b.to_dict()
	var bad := []
	bad.append(null)
	bad.append([1])
	bad.append({"wounds": [], "x": 1})
	bad.append({"wounds": "no"})
	var many := []
	for i in 5:
		var w: Dictionary = good["wounds"][0].duplicate()
		w["about"] = "u%d" % i
		many.append(w)
	bad.append({"wounds": many})
	for mut in [["about", ""], ["about", "x".repeat(65)], ["about", 5], ["acute", 1.5], ["acute", NAN], ["acute", "0.5"],
			["scar", -0.1], ["rebound", 0.5], ["t", 1.0e14], ["t", INF], ["name", "y".repeat(100)], ["evil", 1], ["count", 150],
			["processed", INF], ["lover", 7]]:
		var w2: Dictionary = good["wounds"][0].duplicate()
		w2[mut[0]] = mut[1]
		bad.append({"wounds": [w2]})
	var rejected := 0
	for d in bad:
		if not BetrayalWound.validate_snapshot(d):
			rejected += 1
	check(rejected == bad.size(), "odmítnuto %d/%d nevalidních snapshotů" % [rejected, bad.size()])
	var keep = BetrayalWound.new()
	keep.open("u_k", "K", "", "", 0.5, 0.0, 0.0)
	check(not keep.from_dict({"wounds": "x"}) and keep.wounds.size() == 1, "nevalidní load nic nepřepíše")
	var dup: Dictionary = good["wounds"][0].duplicate()
	var dd = BetrayalWound.new()
	check(dd.from_dict({"wounds": [dup, dup.duplicate()]}) and dd.wounds.size() == 1, "duplicitní rána se zahodí")
	var self_lover: Dictionary = good["wounds"][0].duplicate()
	self_lover["lover"] = String(self_lover["about"])
	var sl = BetrayalWound.new()
	sl.from_dict({"wounds": [self_lover]})
	check(String(sl.wounds[0]["lover"]) == "" and String(sl.wounds[0]["lover_name"]) == "", "milenec = zrádce v savu → vyčištěno")

	section("PsycheExt: osa betrayal v uložení")
	var p = PsycheExt.new()
	p.betrayal.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	# PsycheExt se ukládá binárně (GameSave, var_to_bytes) – rng_state je int, proto bez JSON.
	var pd: Dictionary = p.to_dict().duplicate(true)
	check(PsycheExt.validate_snapshot(pd) and pd.has("betrayal"), "snapshot obsahuje betrayal")
	var q = PsycheExt.new()
	check(q.from_dict(pd) and q.betrayal.wounds.size() == 1, "obnova rány z PsycheExt")
	var old: Dictionary = pd.duplicate(true)
	old.erase("betrayal")
	check(q.from_dict(old) and q.betrayal.is_empty(), "starší uložení bez klíče: žádná rána (ne zbytek z paměti)")
	var badp: Dictionary = pd.duplicate(true)
	badp["betrayal"] = {"wounds": [{"about": ""}]}
	check(not PsycheExt.validate_snapshot(badp), "nevalidní rána → celý snapshot psychiky odmítnut")
	var cfg = PsycheExt.new()
	cfg.betrayal.open("u_p", "Petr", "", "", 1.0, 0.0, 0.0)
	cfg.configure({}, {}, 7, true)
	check(cfg.betrayal.wounds.size() == 1, "živá úprava postavy v editoru ránu nesmaže")
	cfg.configure({}, {}, 7, false)
	check(cfg.betrayal.is_empty(), "čistý spawn začíná bez ran")


# ------------------------------------------------------------------ scéna
func _world(seed: int) -> Node:
	clock.total_minutes = 10.0 * 60.0
	clock._last_day = clock.get_day()
	clock._last_hour = clock.get_hour()
	Main.household_override = []
	var w := Node3D.new()
	w.set_script(Main)
	w.name = "BetrayalWorld%d" % seed
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false, "visuals": false,
		"autosave": false, "autoload": false, "clock": clock, "save_directory": "user://test-betrayal-%d" % OS.get_process_id()}
	add_child(w)
	var n := 0
	for sim in w.sims:
		sim.rng.seed = seed * 7919 + n * 104729 + 13
		n += 1
	return w


func _find(w: Node, first: String) -> Node:
	for s in w.sims:
		if s.first_name() == first:
			return s
	return null


func _hour_dm() -> float:
	return fmod(float(clock.total_minutes), 60.0) + 0.5


func _scene() -> void:
	section("Scéna: zrada odhalena")
	var w := _world(21)
	var jana = _find(w, "Jana")
	var petr = _find(w, "Petr")
	var eliska = _find(w, "Eliška")
	check(jana != null and petr != null and eliska != null, "Jana, Petr, Eliška")
	if jana == null or petr == null or eliska == null:
		return
	var ro = w.dynamics.romance
	ro.resolve_ask(petr.sim_name, jana.sim_name, petr.romance_profile(), jana.romance_profile(), 1.0, 0.0, clock.total_minutes)
	for s in [jana, petr, eliska]:
		for o in [jana, petr, eliska]:
			if s != o:
				s.relationships[o.sim_name] = 50.0
	var chat: Dictionary = ActionLibrary.get_action("chat")
	var conf: Dictionary = ActionLibrary.get_action("confide")
	var chat0: float = jana.psyche_action_weight(chat)
	var conf0: float = jana.psyche_action_weight(conf)
	var tw0: float = jana.psyche_target_weight(petr, chat)
	var help0: float = jana.psyche_gate("help")
	var detail_keys0: Array = jana._build_detail().keys()
	detail_keys0.sort()
	check(jana.betrayal_suspicion_mult() == 1.0 and jana.psy.betrayal.is_empty(), "před zradou: žádná rána, násobič 1")
	jana.on_betrayal(petr, eliska, "caught")
	var b = jana.psy.betrayal
	var pk: String = SimAgent.memory_key(petr)
	var ek: String = SimAgent.memory_key(eliska)
	check(b.wounds.size() == 1 and String(b.wounds[0]["about"]) == pk and String(b.wounds[0]["lover"]) == ek,
		"rána na Petra (uid), s kým: Eliška (uid)")
	check(float(b.wounds[0]["acute"]) > 0.8 and is_equal_approx(float(b.wounds[0]["belief"]), jana.self_defectiveness_belief),
		"akutní bolest %.2f; vnitřní přesvědčení jen přečteno (%.2f)" % [b.wounds[0]["acute"], jana.self_defectiveness_belief])
	var loop_ok := false
	for l in jana.psy.voice.loops:
		if String(l["topic"]) == "grievance" and String(l["about"]) == pk:
			loop_ok = true
	check(loop_ok, "vnitřní hlas: smyčka křivdy o Petrovi (ruminace)")
	check(jana.psyche_action_weight(chat) < chat0 and jana.psyche_action_weight(conf) > conf0,
		"stažení: povídat %.2f → %.2f, svěřit se %.2f → %.2f" % [chat0, jana.psyche_action_weight(chat), conf0, jana.psyche_action_weight(conf)])
	check(jana.psyche_target_weight(petr, chat) < tw0 * 0.6, "Petrovi se vyhýbá (%.2f → %.2f)" % [tw0, jana.psyche_target_weight(petr, chat)])
	check(jana.psyche_gate("help") > help0, "brána „vyhledat pomoc“ se otevírá (%.2f → %.2f)" % [help0, jana.psyche_gate("help")])
	check(jana.betrayal_suspicion_mult() > 1.2, "hypervigilance %.2f" % jana.betrayal_suspicion_mult())
	var ext_ids := []
	for e in jana._extra_moodlets():
		ext_ids.append(String(e["id"]))
	check(ext_ids.has("bw_zrada"), "moodlet „Zrada pořád bolí“ v náladě")
	var pl: PackedStringArray = jana.psyche_private_lines()
	check(", ".join(pl).contains("Zrada (Petr)") and _no_digits(pl), "soukromé věty vlastníka (slovy)")
	var sd: float = jana.self_defectiveness_belief
	check(jana.self_defectiveness_belief == sd, "posuvník self_defectiveness se nemění")

	section("Rušivé otázky (hodinově) a hojení v kroku simulace")
	var th0: int = jana.mental.thoughts.size()
	jana._betrayal_tick(_hour_dm())
	var got := false
	for x in jana.mental.thoughts.slice(th0):
		if String(x["kind"]) == "inner_betrayal":
			got = true
	check(got, "rušivá otázka v soukromém proudu myšlenek")
	var t_before := float(b.wounds[0]["t"])
	var a_before := float(b.wounds[0]["acute"])
	for i in 30:
		clock.advance(1.0)
	check(not b.is_empty() and float(b.wounds[0]["t"]) > t_before and float(b.wounds[0]["acute"]) <= a_before + 1e-9,
		"krok simulace ránu vyvíjí (čas %.0f → %.0f)" % [t_before, float(b.wounds[0]["t"])])

	section("Spouštěče: drb, vidět je spolu")
	var rid: int = w.gossip_observe(eliska, petr, "cheating", 1.0, eliska)
	b.wounds[0]["acute"] = 0.4
	b.wounds[0]["last_reminder"] = -1.0e12
	if rid > 0:
		w._apply_gossip_event({"type": "shared", "teller": SimAgent.memory_key(eliska), "listener": SimAgent.memory_key(jana),
			"subject": pk, "rid": rid, "kind": "cheating", "fabricated": false, "truth": true, "belief": 0.9,
			"belief_gain": 0.9, "delta_rel": -2.0, "bond": 0.0}, float(clock.total_minutes))
	check(rid > 0 and float(b.wounds[0]["acute"]) > 0.4, "drb o Petrově nevěře ránu znovu otevře (%.3f)" % b.wounds[0]["acute"])
	b.wounds[0]["last_reminder"] = -1.0e12  # test: oddělit od drbu (jinak 6h pauza)
	jana.global_position = Vector3(0, 0, 0)
	petr.global_position = Vector3(6, 0, 0)
	eliska.global_position = Vector3(7, 0, 0)
	var a1 := float(b.wounds[0]["acute"])
	if petr._is_sleeping() or jana._is_sleeping():
		check(false, "Petr/Jana spí – nelze ověřit")
	else:
		jana._betrayal_tick(_hour_dm())
		check(jana.mood.has_moodlet("bw_spolu_" + String(petr.name)) and float(b.wounds[0]["acute"]) > a1,
			"vidět Petra s Eliškou: moodlet a rozdřená rána")
	check(String(jana.net_label).find("Zrada") < 0 and String(jana.net_label).find("Viděl") < 0, "veřejný popisek akce nic neprozrazuje")

	section("Zotavení: svěření, omluva")
	# Čtvrtá postava (kamarádka) z kanonických dat Jany – jiné jméno a uid.
	var cd: Dictionary = w._character_records[String(jana.name)].to_dict()
	cd["uid"] = String(cd.get("uid", "a11ce0000000000a")).substr(0, String(cd.get("uid", "a11ce0000000000a")).length() - 2) + "7f"
	cd["identity"]["first_name"] = "Wanda"
	cd["identity"]["last_name"] = "Kamarádová"
	var wit = w.spawn_character(cd, Vector3(30, 0, 30), 4243)
	check(wit != null, "kamarádka Wanda")
	var p0 := float(b.wounds[0]["processed"])
	jana._betrayal_support(0.5, petr)
	check(is_equal_approx(float(b.wounds[0]["processed"]), p0), "svěřit se Petrovi se nepočítá")
	if wit != null:
		jana._betrayal_support(0.5, wit)
	check(float(b.wounds[0]["processed"]) > p0, "svěření jinému člověku: zpracování %.2f → %.2f" % [p0, b.wounds[0]["processed"]])
	var p1 := float(b.wounds[0]["processed"])
	var apol: Dictionary = ActionLibrary.get_action("apologize").duplicate(true)
	petr._start_apology(jana, apol)
	var oc := String(petr.last_apology.get("outcome", ""))
	if oc in ["accepted", "partial"]:
		check(float(b.wounds[0]["processed"]) > p1, "omluva (%s) pomohla zpracovat" % oc)
	else:
		check(is_equal_approx(float(b.wounds[0]["processed"]), p1), "omluva (%s) nic nezpracovala" % oc)

	section("Agency: hráč není nikdy zamčený (Grok #557)")
	if wit != null:
		b.wounds[0]["acute"] = 0.95
		b.wounds[0]["scar"] = 0.9
		var free_ok := false
		for i in 300:
			if wit.can_join_social(jana) and not wit._is_sleeping() and not jana._is_sleeping():
				free_ok = true
				break
			clock.advance(1.0)
		jana.global_position = Vector3(0, 0, 0)
		wit.global_position = Vector3(1.5, 0, 0)
		var pc0 := float(b.wounds[0]["processed"])
		var accepted: bool = jana.command(conf, wit)
		check(free_ok and accepted, "silná rána i jizva: příkaz „Svěřit se“ přijat (nic se nezakazuje)")
		var done := false
		for i in 240:
			clock.advance(1.0)
			if String(jana.last_coping_result.get("id", "")) == "confide":
				done = true
				break
		check(done, "svěření proběhlo")
		if done:
			if jana._confide_dismissed:
				check(is_equal_approx(float(b.wounds[0]["processed"]), pc0), "kamarádka to odbyla → bez zpracování (realisticky)")
			else:
				check(float(b.wounds[0]["processed"]) > pc0, "hráčem zadané svěření zpracuje (%.2f → %.2f)" % [pc0, b.wounds[0]["processed"]])
		check(jana.psyche_action_weight(ActionLibrary.get_action("ask_out")) >= 0.4 * 0.2, "pozvání na rande: jen nižší chuť AI, nikdy nula")

	section("Soukromí (offline vlastník vs. replikovaná data)")
	var dk: Array = jana._build_detail().keys()
	dk.sort()
	check(dk == detail_keys0, "net_detail (jen vlastníkovi) má stejné klíče jako před zradou: %s" % ",".join(dk))
	var dj := JSON.stringify(jana._build_detail())
	check(dj.find("\"acute\"") < 0 and dj.find("\"scar\"") < 0 and dj.find("betrayal") < 0 and dj.find(pk) < 0,
		"ani vlastník nedostává čísla ani uid rány")
	var hi: Dictionary = jana.hud_info()
	check(", ".join(hi.get("psyche_lines", PackedStringArray())).contains("Zrada"), "offline HUD vlastníka: soukromé věty ano")

	section("Uložení hry")
	var cap: Dictionary = GameSave.capture(w)
	check(bool(cap.get("ok", false)), "capture ok")
	var js := JSON.stringify(cap)
	check(js.find("\"betrayal\"") >= 0 and js.find(pk) >= 0, "uložení obsahuje ránu (uid zrádce)")
	var saved_acute := float(b.wounds[0]["acute"])
	jana.psy.betrayal.wounds.clear()
	var ap: Dictionary = GameSave.apply(w, cap.get("data", cap))
	# apply může postavy znovu vytvořit – znovu je najít podle jména.
	jana = _find(w, "Jana")
	petr = _find(w, "Petr")
	var b2 = jana.psy.betrayal
	check(bool(ap.get("ok", false)) and b2.wounds.size() == 1 and absf(float(b2.wounds[0]["acute"]) - saved_acute) < 1e-6,
		"obnova po load: rána zpět (%s)" % str(ap.get("reason", "ok")))

	section("Nastavení obsahu: témata vypnutá")
	settings.set_value("mental_health", "off", false)
	clock.advance(1.0)
	check(jana.psy.k() == 0.0, "režim off dorazil do psychiky")
	# Pozn.: sociální paměť (běžné poznávání, ne téma duševního zdraví) běží dál i ve vypnutém režimu,
	# proto se výběr lidí porovnává jen za osu rány.
	check(jana.psyche_action_weight(conf) == 1.0 and jana.psy.betrayal.target_weight(SimAgent.memory_key(petr), chat, jana.psy.k(), clock.total_minutes) == 1.0 \
		and jana.betrayal_suspicion_mult() == 1.0, "násobiče rány přesně 1 (akce %.3f)" % jana.psyche_action_weight(conf))
	var off_ids := []
	for e in jana._extra_moodlets():
		off_ids.append(String(e["id"]))
	check(not off_ids.has("bw_zrada") and not ", ".join(jana.psyche_private_lines()).contains("Zrada"), "žádný moodlet ani věty")
	check(not jana.psy.betrayal.is_empty(), "stav zůstává (čas hojí dál, jen se neprojevuje)")
	settings.set_value("mental_health", "full", false)
	clock.advance(1.0)
	w.queue_free()
	await get_tree().process_frame
