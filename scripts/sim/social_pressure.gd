extends RefCounted
## Nonsexual abuse and boundary events. NEVER increases or supplies consent.
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
	actor.last_tag_time[key] = when
	# Shared AI cooldown across tactics; per-person spam protection remains.
	actor.last_tag_time["pressure"] = when
	var loss: float = float(SEVERITY[kind])
	actor.relationships[target.sim_name] = clampf(float(actor.relationships.get(target.sim_name, 0.0)) - loss * 0.25, -100.0, 100.0)
	target.relationships[actor.sim_name] = clampf(float(target.relationships.get(actor.sim_name, 0.0)) - loss, -100.0, 100.0)
	target.ledger.on_hurt_by(actor.sim_name, loss, when)
	actor.ledger.on_hurt_other(target.sim_name, loss * 0.35)
	for axis in REACTIONS[kind]:
		target.emotions.shift(axis, float(REACTIONS[kind][axis]), actor.sim_name)
	# Boundary: perceived non-free consent cannot turn abuse into access.
	if kind in ["guilt_trip", "blame_shift", "emotional_blackmail"]:
		target.intimacy.pressure_from(String(actor.name), when)
		actor.intimacy.pressure_from(String(target.name), when)
	actor._detail_dirty = true
	target._detail_dirty = true
	return true
