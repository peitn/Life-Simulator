extends "res://tests/test_base.gd"
## Server-owned, non-graphic adult intimacy and coercive social behavior.
## Eight entirely fictional adult characters, no real user's personal history.
const Main := preload("res://main.gd")
const Intimacy := preload("res://scripts/sim/intimacy_state.gd")
const Adult := preload("res://scripts/sim/adult_intimacy_action.gd")
const Pressure := preload("res://scripts/sim/social_pressure.gd")
const Save := preload("res://scripts/save/game_save.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const Planner := preload("res://scripts/sim/utility_planner.gd")
const Actions := preload("res://scripts/sim/action_library.gd")
var gs
var clock
var w

func _ready() -> void:
	watchdog_seconds = 90.0
	gs = get_node("/root/GameSettings")
	gs.persist = false
	gs.reset()
	clock = get_node("/root/GameClock")
	clock.running = false
	_run.call_deferred()


func _make_world() -> void:
	Main.household_override = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/data/extreme_profiles_fictional8.json"))
	clock.total_minutes = 480.0
	clock._last_hour = clock.get_hour()
	clock._last_day = clock.get_day()
	w = Node3D.new()
	w.name = "FictionalAdultSocialTest"
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "hud": false, "camera": false,
		"visuals": false, "autoload": false, "autosave": false, "clock": clock}
	add_child(w)


func _run() -> void:
	section("Independent orientation, sexual drive, transitory arousal")
	var asx := Intimacy.new()
	var low := Intimacy.new()
	check(asx.configure({"age": 26, "asexual": true, "aromantic": false,
		"libido": 0.95, "drive_dysregulation": 0.0}),
		"asexual adult with high libido is a valid independent profile")
	check(asx.asexual and asx.libido_baseline > 0.9 and asx.drive_dysregulation == 0.0,
		"asexuality does not imply low libido or dysregulated sexuality")
	check(low.configure({"age": 34, "asexual": false, "libido": 0.05,
		"drive_dysregulation": 0.85}),
		"non-asexual low-libido character can separately have intrusive preoccupation")
	low.tick(40.0, {"stress": 80.0})
	check(low.sexual_preoccupation > 0.0 and low.sexual_arousal < 15.0,
		"dysregulation never automatically initiates arousal or sex")
	check(not asx.configure({"age": 17, "libido": 0.8}) and asx.age == 26,
		"minors cannot be configured, failed update leaves adult state intact")
	asx.tick(70.0, {"stress": 20.0, "energy": 90.0, "safety": 0.7})
	check(asx.sexual_arousal > 0.0 and asx.sexual_arousal <= 100.0,
		"transient sexual arousal is private and independently dynamic")
	check(not asx.offer_consent("X", 5.0, false, true)
		and not asx.offer_consent("X", 5.0, true, false),
		"arousal and drive cannot create consent against someone's will/capacity")
	check(asx.offer_consent("X", 5.0, true, true)
		and not asx.mutual_consent(low, "A", "X", 6.0, true),
		"consent must come independently from both participants")
	low.pressure_from("A", 5.0)
	check(not low.offer_consent("A", 6.0, true, true),
		"emotional pressure imposes a time-limited safety barrier")
	asx.revoke_consent("X")
	check(not asx.has_consent("X", 6.0), "consent can be revoked immediately")
	var copy := asx.to_dict()
	var loaded := Intimacy.new()
	check(Intimacy.validate_snapshot(copy) and loaded.from_dict(copy)
		and loaded.to_dict() == copy,
		"private sexuality state round-trips exactly")
	copy["sexual_arousal"] = NAN
	check(not Intimacy.validate_snapshot(copy), "non-finite intimate save refused")
	section("Actual eight-adult world, authoritative player commands and consent")
	_make_world()
	var a = w.find_sim("Iris_North")
	var b = w.find_sim("Ash_Solace")
	var c = w.find_sim("Raven_Vale")
	var d = w.find_sim("Sable_Wraith")
	check(w.sims.size() == 8 and a != null and b != null and c != null and d != null,
		"real adult fixture and four known participants spawned")
	check(a.intimacy.age == 29 and b.intimacy.age == 26,
		"private sexuality is derived from actual CharacterData age")
	check(gs.get_value("adult_intimacy") == false
		and w.net.handle_command(1, String(a.name), "intimacy_offer", String(b.name)) != "",
		"default-off adult content blocks requested offers")
	gs.set_value("adult_intimacy", true, false)
	check(w.net.handle_command(1, String(a.name), "adult_consensual_sex", String(b.name)) != "",
		"even after opt-in, sex requires separate offers from both")
	check(a.intimacy.sexual_arousal < 50.0
		and not Adult.check(w, a, b, clock.total_minutes, true).get("ok", false),
		"sexual arousal is NOT equivalent to voluntary consent")
	var real_age = w._character_records[String(b.name)].body["age"]
	w._character_records[String(b.name)].body["age"] = 17
	check(not Adult.eligible_pair(w, a, b, clock.total_minutes, true).get("ok", false),
		"authoritative underage record blocks sex even if private ages were forged")
	w._character_records[String(b.name)].body["age"] = real_age
	b.relationships[a.sim_name] = 90.0
	a.relationships[b.sim_name] = 90.0
	b.ledger.trust[a.sim_name] = 90.0
	a.ledger.trust[b.sim_name] = 90.0
	check(Adult.npc_willing(w, b, a, clock.total_minutes),
		"unowned NPC can independently evaluate high-trust willingness")
	check(w.net.handle_command(1, String(a.name), "intimacy_offer", String(b.name)) == "",
		"authenticated adult can offer intimacy without forcing NPC consent")
	check(Adult.check(w, a, b, clock.total_minutes, true).get("ok", false),
		"two genuinely independent current offers allow private encounter")
	var pre_last: float = a.intimacy.last_intimacy
	check(w.net.handle_command(1, String(a.name), "adult_consensual_sex", String(b.name)) == "",
		"the real catalog/player action starts a server-approved encounter")
	# Actual HUD (not a mocked image) obscures the scene during the act
	# while leaving control buttons available for consent withdrawal.
	w.selected = w.sims.find(a)
	var ui = HUD.new()
	ui.main = w
	add_child(ui)
	var fade_seen := false
	var started := false
	for step in 42:
		clock.advance(2.0)
		if a.current_action.get("id", "") == "adult_consensual_sex":
			started = true
			if a.state == a.State.ACTING:
				ui._refresh = -1.0
				ui._process(1.0)
				fade_seen = fade_seen or ui._intimacy_fade.visible
	check(fade_seen,
		"real offline player HUD fades the scene during private intimacy")
	ui._refresh = -1.0
	ui._process(1.0)
	check(not ui._intimacy_fade.visible,
		"the fade clears automatically when private action finishes")
	ui.free()
	check(started and a.intimacy.last_intimacy > pre_last
		and b.intimacy.last_intimacy == a.intimacy.last_intimacy,
		"actual two-participant, forty-five-minute sex action completed offscreen")
	check(not a.intimacy.has_consent(String(b.name), clock.total_minutes)
		and not b.intimacy.has_consent(String(a.name), clock.total_minutes),
		"consent is consumed after completion; never valid forever")
	check(not a._build_detail().has("sexual_arousal")
		and not b.net_detail.has("libido"),
		"sexual preferences, arousal and consent not broadcast in net_detail")

	section("Rescind consent while encounter is in progress")
	a.needs.values["energy"] = 80.0
	b.needs.values["energy"] = 80.0
	a.mental.stress = 15.0
	b.mental.stress = 15.0
	a.mental.panic_active = false
	b.mental.panic_active = false
	b.relationships[a.sim_name] = 90.0
	b.ledger.trust[a.sim_name] = 90.0
	check(w.net.handle_command(1, String(a.name), "intimacy_offer", String(b.name)) == "",
		"partners may make a new and fresh separate decision")
	check(w.net.handle_command(1, String(a.name), "adult_consensual_sex", String(b.name)) == "",
		"second encounter is not automatically granted without a new offer")
	var moment: float = a.intimacy.last_intimacy
	var underway := false
	for step in 35:
		clock.advance(2.0)
		if a.current_action.get("id", "") == "adult_consensual_sex" and a.state == a.State.ACTING:
			underway = true
			break
	check(underway, "second encounter genuinely begins before withdrawal")
	check(w.net.handle_command(1, String(a.name), "intimacy_withdraw", String(b.name)) == "",
		"player can instantly withdraw via authenticated server command")
	for step in 30:
		clock.advance(2.0)
	check(a.intimacy.last_intimacy == moment and b.intimacy.last_intimacy == moment,
		"withdrawn consent cancels completion for both; no nonconsensual fallback")
	check(a.current_action.get("id", "") != "adult_consensual_sex"
		and b.current_action.get("id", "") != "adult_consensual_sex",
		"both participants have left the private encounter after withdrawal")

	section("Real negative social interactions cannot manufacture consent")
	var now: float = clock.total_minutes
	c.needs.values["energy"] = 80.0
	d.needs.values["energy"] = 80.0
	var trust_before: float = float(d.ledger.trust_in(c.sim_name))
	check(Pressure.apply("emotional_blackmail", c, d, now),
		"emotional blackmail is an actual simulated social event")
	check(d.ledger.trust_in(c.sim_name) < trust_before
		and d.emotions.towards(c.sim_name, "fear") > 0.0,
		"blackmail damages directional trust and generates fear")
	check(d.intimacy.is_under_pressure(String(c.name), now)
		and c.intimacy.is_under_pressure(String(d.name), now),
		"coercion blocks intimate permission for both participants")
	check(not d.intimacy.offer_consent(String(c.name), now + 1.0, true, true)
		and not c.intimacy.offer_consent(String(d.name), now + 1.0, true, true),
		"neither side can turn sexual coercion into valid consent")
	check(Pressure.apply("reproach", c, d, now + 2.0)
		and Pressure.apply("guilt_trip", c, d, now + 3.0)
		and Pressure.apply("blame_shift", c, d, now + 4.0)
		and Pressure.apply("stonewalling", c, d, now + 5.0),
		"five distinct nonsexual social-pressure behaviors are implemented")
	check(not Pressure.apply("unexpected", c, d, now + 8.0),
		"unknown manipulation actions are ignored")
	# A separate recipient is required: repeated coercion against Sable is
	# deliberately cooldown-blocked, not a fresh successful tactic.
	var orion = w.find_sim("Orion_Voss")
	c.command({"id": "cancel"}, null)
	orion.command({"id": "cancel"}, null)
	c.global_position = orion.global_position + Vector3(0.5, 0.0, 0.0)
	check(w.net.handle_command(1, String(c.name), "emotional_blackmail", String(orion.name)) == "",
		"actual authoritative ActionLibrary+NetSession accepts a fresh abuse action")
	for step in 15:
		clock.advance(2.0)
	check(c.action_counts.get("emotional_blackmail", 0) > 0,
		"real SimAgent starts the requested negative social action")
	var pressure_stats: Dictionary = w.dynamics.stats
	var regular_outcomes: Dictionary = pressure_stats["outcomes"]
	var counted := 0
	for kind in ["chat", "argue", "awkward", "misunderstanding"]:
		counted += int(regular_outcomes.get(kind, 0))
	check(counted == int(pressure_stats["talks"]),
		"manipulative events never distort genuine conversation/fight statistics")
	check(int(pressure_stats.get("pressure", 0)) > 0 and
		int(pressure_stats.get("pressure_outcomes", {}).get("emotional_blackmail", 0)) > 0,
		"harmful tactics are tracked separately by exact subtype")
	check(not Pressure.apply("emotional_blackmail", c, d, clock.total_minutes),
		"repeated coercive tactic against same NPC has a real persistent cooldown")
	check(c.last_tag_time.has("pressure"),
		"AI-wide social pressure cooldown is persisted with per-target cooldown")
	section("Severe psychological manipulation is rare but can emerge from AI")
	var severe := Actions.get_action("emotional_blackmail")
	check(not bool(severe.get("player_only", false)),
		"severe social tactic exists in the autonomous planning catalog")
	c.ledger.grudges[d.sim_name] = 75.0
	c.emotions.shift("anger", -100.0)
	c.last_tag_time["pressure"] = now - 1000.0
	check(Planner.score_action(c, severe, 14) == 0.0,
		"NPC with ordinary anger does not spontaneously blackmail somebody")
	c.emotions.shift("anger", 100.0)
	check(Planner.score_action(c, severe, 14) > 0.0,
		"rare high anger plus real grievance permits but does not force an NPC candidate")
	c.last_tag_time["pressure"] = clock.total_minutes
	check(Planner.score_action(c, severe, 14) == 0.0,
		"shared seven-hundred-twenty-minute cooldown prevents repeated AI abuse")

	section("Strict private H4 persistence and safe legacy load")
	var saved = Save.capture(w)
	check(saved.get("ok", false) and Save.validate_data(saved["data"], w).get("ok", false),
		"complete household with sexual/social state saves under strict H4")
	var original = saved["data"].duplicate(true)
	var broken = original.duplicate(true)
	broken["sims"][0]["state"]["intimacy"]["sexual_arousal"] = NAN
	check(Save.validate_data(broken, w).get("reason", "") == "bad_intimacy",
		"invalid sexual arousal is caught before household rebuild")
	broken = original.duplicate(true)
	broken["sims"][0]["state"]["intimacy"]["age"] = 17
	check(Save.validate_data(broken, w).get("reason", "") == "bad_intimacy",
		"underage intimacy snapshot is refused before load")
	check(Save.apply(w, original).get("ok", false)
		and Save.capture(w)["data"] == original,
		"actual whole-household cold restore keeps private sexual history bit-exact")
	var old = original.duplicate(true)
	for it in old["sims"]:
		it["state"].erase("intimacy")
	check(Save.validate_data(old, w).get("ok", false)
		and Save.apply(w, old).get("ok", false),
		"old save without sexuality data still loads with safe character defaults")
	gs.set_value("adult_intimacy", false, false)
	var restored = w.find_sim("Iris_North")
	check(not restored.hud_info().has("sexual_arousal"),
		"disabled content hides private sexual HUD even offline")
	w.free()
	Main.household_override = []
	gs.reset()
	clock.running = false
	finish("test_adult_social_integration")
