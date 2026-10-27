extends RefCounted
## NON-EXPLICIT consensual adult intimacy. No coercion, rewards or animations.
const MIN_AGE := 18
const ACTION_ID := "adult_consensual_sex"
const LABEL := "Tráví spolu soukromou intimní chvíli"

static func _record_age(world, sim) -> int:
	if not world._character_records.has(String(sim.name)):
		return -1
	return int(world._character_records[String(sim.name)].body.get("age", -1))


static func capable(sim) -> bool:
	return sim != null and is_instance_valid(sim) and sim.mental != null and not sim.mental.panic_active \
		and float(sim.needs.values["energy"]) >= 20.0 and float(sim.mental.stress) < 90.0 \
		and not bool(sim.current_action.get("involuntary", false))


static func eligible_pair(world, a, b, now: float, enabled: bool) -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "opt_in_required"}
	if world == null or a == null or b == null or a == b or not is_instance_valid(a) or not is_instance_valid(b) or not is_finite(now):
		return {"ok": false, "reason": "invalid_pair"}
	if world.net == null or not world.net.is_authority() or not world.sims.has(a) or not world.sims.has(b):
		return {"ok": false, "reason": "server_only"}
	var years_a := _record_age(world, a)
	var years_b := _record_age(world, b)
	if years_a < MIN_AGE or years_b < MIN_AGE:
		return {"ok": false, "reason": "age_gate"}
	if a.intimacy == null or b.intimacy == null or a.intimacy.age != years_a or b.intimacy.age != years_b:
		return {"ok": false, "reason": "private_state_mismatch"}
	if not capable(a) or not capable(b):
		return {"ok": false, "reason": "cannot_consent_now"}
	return {"ok": true, "reason": "both_adults_capable"}


static func check(world, a, b, now: float, enabled: bool) -> Dictionary:
	var eligible := eligible_pair(world, a, b, now, enabled)
	if not bool(eligible.get("ok", false)):
		return eligible
	if not a.intimacy.mutual_consent(b.intimacy, String(a.name), String(b.name), now, true):
		return {"ok": false, "reason": "no_mutual_consent"}
	return {"ok": true, "reason": "mutual_freely_given_consent"}


## NPC autonomy is evaluated from *its own* safety/trust/preferences. Arousal
## is not a proxy for consent. Asexuality never becomes a hard prohibition.
static func npc_willing(world, npc, other, now: float) -> bool:
	if not bool(eligible_pair(world, npc, other, now, true).get("ok", false)):
		return false
	if npc.intimacy.is_under_pressure(String(other.name), now) or other.intimacy.is_under_pressure(String(npc.name), now):
		return false
	if npc.intimacy.refusal_until.get(String(other.name), -1.0e12) > now:
		return false
	var relation: float = float(npc.relationships.get(other.sim_name, 0.0))
	var trust: float = npc.ledger.trust_in(other.sim_name)
	if relation < 62.0 or trust < 70.0 or npc.emotions.towards(other.sim_name, "fear") > 24.0:
		return false
	if npc.intimacy.libido_baseline < 0.15 and relation < 90.0:
		return false
	# Only explicitly configured sexual target groups constrain this voluntary
	# NPC preference. No gender is inferred from sexed anatomy or grammar.
	var targets: Array = npc.intimacy.sexual_attraction
	if not targets.is_empty() and not npc.intimacy.asexual:
		var identity: Dictionary = world._character_records[String(other.name)].identity
		var gender: String = String(identity.get("gender_identity", "neuvedeno"))
		var group := "muzi" if gender == "muz" else ("zeny" if gender == "zena" else ("nebinarni" if gender in ["nebinarni", "agender"] else ""))
		if not targets.has(group):
			return false
	return true


static func commit(world, a, b, now: float, enabled: bool) -> Dictionary:
	var result: Dictionary = check(world, a, b, now, enabled)
	if not bool(result.get("ok", false)):
		return result
	if not a.intimacy.complete(b.intimacy, String(a.name), String(b.name), now, true):
		return {"ok": false, "reason": "consent_withdrawn"}
	return {"ok": true, "kind": "consensual_adult_intimacy", "presentation": "fade_to_black",
		"duration": 45.0, "private": true, "label": LABEL}
