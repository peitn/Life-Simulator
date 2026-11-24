extends RefCounted
## Nonsexual abuse and boundary events. NEVER increases or supplies consent.
##
## Manipulace není ovládání mysli: cíl se brání (RivalryPressure.resolve_pressure). Hranice = zdravá
## sebehodnota (1 − soukromá self_defectiveness, jen se ČTE, nikdy nemění), podpora = nejsilnější přátelský
## vztah k někomu jinému, rozpoznání vzorce = zášť vůči manipulátorovi (kdo už byl zraněn, pozná to).
## Obrana tlumí vinu, stud, strach a nejistotu (to, čím manipulace „funguje“). Vztah a důvěra k manipulátorovi
## utrpí VŽDY – i odražená manipulace je zneužití a hra ji nijak neodměňuje.
const RivalryPressure := preload("res://scripts/sim/rivalry_pressure.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")

const KINDS := ["reproach", "guilt_trip", "blame_shift", "emotional_blackmail", "stonewalling"]
const SEVERITY := {"reproach": 3.5, "guilt_trip": 6.0, "blame_shift": 7.0,
	"emotional_blackmail": 15.0, "stonewalling": 5.0}
const REACTIONS := {
	"reproach": {"anger": 5.0, "guilt": 7.0, "uncertainty": 4.0},
	"guilt_trip": {"guilt": 14.0, "shame": 8.0, "anger": 7.0},
	"blame_shift": {"anger": 14.0, "frustration": 11.0, "uncertainty": 6.0},
	"emotional_blackmail": {"fear": 17.0, "anger": 15.0, "uncertainty": 15.0, "safety": -17.0},
	"stonewalling": {"sadness": 8.0, "uncertainty": 10.0, "loneliness": 9.0}
}
## Osy, na které obrana působí (manipulace jimi „funguje“). Hněv, frustrace, smutek a osamělost zůstávají.
const DEFENDED_AXES := ["guilt", "shame", "fear", "uncertainty", "safety"]
## I nejsilnější obrana nechá část zásahu (minimum 25 %): zneužití bolí vždycky.
const MIN_HIT := 0.25
const GRUDGE_RECOGNIZE := 60.0


## Obrana cíle proti manipulaci od `actor` (0..1 vstupy + výsledek resolve_pressure). Čistě čte stav.
static func defense_for(actor, target) -> Dictionary:
	var self_def := 0.0
	var sd = target.get("self_defectiveness_belief")
	if typeof(sd) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(sd)):
		self_def = clampf(float(sd), 0.0, 1.0)
	var support := 0.0
	var rels = target.get("relationships")
	if typeof(rels) == TYPE_DICTIONARY:
		var ks: Array = rels.keys()
		ks.sort()
		for k in ks:
			if String(k) == String(actor.sim_name):
				continue
			var v = rels[k]
			if typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)):
				support = maxf(support, clampf(float(v) / 100.0, 0.0, 1.0))
	var recognize := 0.0
	if target.get("ledger") != null:
		recognize = clampf(float(target.ledger.grudge(actor.sim_name)) / GRUDGE_RECOGNIZE, 0.0, 1.0)
	var boundaries := 1.0 - self_def
	var res: Dictionary = RivalryPressure.resolve_pressure(1.0, 1.0, boundaries, support, recognize)
	return {"boundaries": boundaries, "support": support, "recognize": recognize,
		"defense": float(res["defense"]), "impact": float(res["impact"]), "resisted": bool(res["resisted"])}


static func apply(kind: String, actor, target, when: float) -> bool:
	if kind not in KINDS or actor == null or target == null or actor == target or not is_finite(when):
		return false
	if not is_instance_valid(actor) or not is_instance_valid(target) or actor.intimacy == null or target.intimacy == null:
		return false
	# Repeated identical tactics against one person cannot be spammed for
	# unlimited instant relationship damage (also survives H4 save/load).
	var key: String = "pressure:" + kind + ":" + String(target.name)
	if when - float(actor.last_tag_time.get(key, -1.0e12)) < 120.0:
		return false
	# Obrana se počítá z hodnot PŘED tímto zásahem (zášť z tohoto zásahu ji nesmí hned posílit).
	var dfn := defense_for(actor, target)
	actor.last_tag_time[key] = when
	# Shared AI cooldown across tactics; per-person spam protection remains.
	actor.last_tag_time["pressure"] = when
	var loss: float = float(SEVERITY[kind])
	actor.relationships[target.sim_name] = clampf(float(actor.relationships.get(target.sim_name, 0.0)) - loss * 0.25, -100.0, 100.0)
	target.relationships[actor.sim_name] = clampf(float(target.relationships.get(actor.sim_name, 0.0)) - loss, -100.0, 100.0)
	target.ledger.on_hurt_by(actor.sim_name, loss, when)
	actor.ledger.on_hurt_other(target.sim_name, loss * 0.35)
	var hit := maxf(MIN_HIT, float(dfn["impact"]))
	for axis in REACTIONS[kind]:
		var v: float = float(REACTIONS[kind][axis])
		if axis in DEFENDED_AXES:
			v *= hit
		target.emotions.shift(axis, v, actor.sim_name)
	if bool(dfn["resisted"]) and target.get("mood") != null and actor.get("mood") != null:
		target.mood.add_moodlet("ustal_" + String(actor.name), "Nenechal(a) jsem se zmanipulovat".replace("(a)", Grammar.past(String(target.grammar))), "spokojeny", 3.0, 240.0)
		actor.mood.add_moodlet("nezabralo_" + String(target.name), "Nezabralo to", "nastvany", -3.0, 180.0)
	target.set_meta("last_pressure_defense", dfn.merged({"kind": kind, "from": String(actor.sim_name), "t": when, "hit": hit}))
	# Boundary: perceived non-free consent cannot turn abuse into access.
	if kind in ["guilt_trip", "blame_shift", "emotional_blackmail"]:
		target.intimacy.pressure_from(String(actor.name), when)
		actor.intimacy.pressure_from(String(target.name), when)
	actor._detail_dirty = true
	target._detail_dirty = true
	return true
