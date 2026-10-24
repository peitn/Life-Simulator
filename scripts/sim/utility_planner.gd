extends RefCounted
## Plánovač akcí (utility AI).
## Pro každou dostupnou akci spočítá užitek = snížení naléhavosti potřeb × váhy
## + očekávaný emoční zážitek (moodlet) + uspokojení tužeb povahy, upravený rysy,
## emocí, denní dobou, novostí a vzdáleností. Poté vybere náhodně z nejlepších
## kandidátů (postavy nejsou roboti). Akce `player_only` (např. urážka) AI nevybírá,
## mimovolné stavy (`involuntary`, panická ataka) spouští simulace, ne plánovač.
## Copingy láká duševní stav (MentalState.coping_appeal); úzkost dělá sociální akce
## méně lákavé, ale nikdy je nezakáže.
##
## Deprese (MentalState.dep) odděluje: očekávanou radost (wanting – naučené očekávání se
## pesimismem; podle něj se volí), bariéru iniciace (vigour × námaha akce) a prožitou radost
## (liking – uplatní se až při dokončení v SimAgent). Nic se tím nezakazuje.
## Omluvu AI volí z viny vůči konkrétní postavě (pýcha ji tlumí).

const Needs := preload("res://scripts/sim/needs.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const ActionLibrary := preload("res://scripts/sim/action_library.gd")

const TOP_RATIO := 0.75
const TOP_COUNT := 3
const DISTANCE_SCALE := 15.0
## Jak moc postavu láká očekávaný pozitivní pocit z akce.
const ANTICIPATION := 0.8
## Bonus za akci, která uspokojí aktivní touhu povahy.
const CRAVING_BONUS := 28.0
## Večerní tah do postele.
const BEDTIME_PULL := 40.0
## Vina, od které AI začne uvažovat o omluvě.
const APOLOGY_GUILT := 15.0
## AI se stejné postavě znovu omlouvá nejdřív po 12 herních hodinách (hráč smí kdykoli).
const APOLOGY_COOLDOWN := 720.0
## Kritický hlad: pod touto hodnotou ztrácí lákavost všechno, co hlad neřeší (i spánek).
const HUNGER_CRITICAL := 15.0
const HUNGER_CRITICAL_MULT := 0.25
const ENERGY_CRITICAL := 12.0
const ENERGY_CRITICAL_MULT := 0.3


static func expected_effects(a: Dictionary) -> Dictionary:
	var e: Dictionary = a.get("effects", {}).duplicate()
	var rate: Dictionary = a.get("rate", {})
	var hours: float = float(a.get("duration", 30.0)) / 60.0
	for k in rate:
		e[k] = float(e.get(k, 0.0)) + float(rate[k]) * hours
	return e


static func score_action(sim, a: Dictionary, hour: int) -> float:
	var eff := expected_effects(a)
	var gain := 0.0
	for k in eff:
		var v: float = sim.needs.values[k]
		var nv := clampf(v + float(eff[k]), 0.0, 100.0)
		gain += float(Needs.WEIGHTS[k]) * (Needs.urgency(v) - Needs.urgency(nv))
	gain += float(a.get("base_appeal", 1.5))
	var tags: Array = a.get("tags", [])
	var coping: String = a.get("coping", "")
	if coping != "" and sim.mental != null:
		var ca: float = sim.mental.coping_appeal(coping, sim.needs.values["energy"], sim.needs.values["hunger"],
			sim.now(), Traits.flag_strength(sim.trait_profile, "impulsive"), sim.mental_cfg())
		if ca <= 0.0 and not bool(a.get("leisure", false)):
			return 0.0
		gain += ca
	if a["id"] == "apologize":
		# Bez viny se nikdo neomlouvá; konkrétní cíl řeší choose() / apology_score().
		if sim.ledger == null or sim.ledger.max_guilt() < APOLOGY_GUILT:
			return 0.0
		gain = maxf(gain, 1.0)
	# Těšení se na zážitek (wanting): naučené očekávání radosti, zesílené rysy (gurmán u vaření…)
	# a zkreslené pesimismem v depresi.
	var ml: Array = a.get("moodlet", [])
	if ml.size() != 5 or not sim.mood.has_moodlet(ml[0]):
		var prior := ActionLibrary.hedonic_prior(a) * Traits.moodlet_multiplier(sim.trait_profile, tags)
		if prior > 0.0:
			var ant := prior
			if sim.mental != null:
				ant = sim.mental.dep.anticipated(String(a["id"]), prior)
				# Práh těšení: pod ním věc táhne jen málo (cynik, stres, pesimismus ho zvedají).
				if sim.get("sensory") != null:
					ant = sim.sensory.anticipation_after_threshold(ant, sim.mental.dep.pessimism, sim.mental.stress)
			gain += ant * ANTICIPATION
	for t in tags:
		if sim.mood.has_moodlet("craving_" + t):
			gain += CRAVING_BONUS
	if gain <= 0.0:
		return 0.0
	var mult := 1.0
	for t in tags:
		mult *= Traits.tag_multiplier(sim.trait_profile, t)
		mult *= Mood.emotion_tag_multiplier(sim.mood.emotion, t)
	# Tělo má přednost: při kritickém hladu se nedá usnout ani se soustředit na zábavu
	# (jinak smyčka „usnu → hlad mě vzbudí → televize → zase spát“ a vyčerpání bez konce).
	var hunger: float = sim.needs.values["hunger"]
	if hunger < HUNGER_CRITICAL and not eff.has("hunger"):
		mult *= lerpf(HUNGER_CRITICAL_MULT, 1.0, hunger / HUNGER_CRITICAL)
	# Totéž u vyčerpání: kdo se sotva drží na nohou, nekouká do noci na televizi (výjimka: jídlo).
	var energy: float = sim.needs.values["energy"]
	if energy < ENERGY_CRITICAL and not eff.has("energy") and not eff.has("hunger"):
		mult *= lerpf(ENERGY_CRITICAL_MULT, 1.0, energy / ENERGY_CRITICAL)
	var night := hour >= 23 or hour < 6
	# Cirkadiánní rytmus – v noci se spí, přes den jen když je postava opravdu vyčerpaná.
	if tags.has("sleep"):
		if hour >= 22 or hour < 6:
			# Večerka – silný tah do postele (synchronizace denního rytmu).
			gain += BEDTIME_PULL * (1.0 - sim.needs.values["energy"] / 140.0)
			mult *= 1.8
		elif hour >= 8 and hour < 21 and sim.needs.values["energy"] > 30.0:
			mult *= 0.1
	elif night:
		mult *= 0.6 if tags.has("rest") else 0.4
	# Šlofík jen když je postava opravdu ospalá a ne v noci (to se jde spát).
	if a["id"] == "nap":
		if sim.needs.values["energy"] > 45.0:
			mult *= 0.3
		if hour >= 21 or hour < 6:
			mult *= 0.2
	# Deprese: bariéra iniciace (čím náročnější začít, tím méně lákavé – nikdy 0) a únava táhne k odpočinku.
	if sim.mental != null:
		mult *= 1.0 - sim.mental.dep.barrier(ActionLibrary.effort(a))
		if tags.has("rest") and not tags.has("sleep"):
			mult *= sim.mental.dep.rest_pull()
	# Úzkost: sociální akce jsou náročnější (méně lákavé), ale ne zakázané.
	if tags.has("social") and sim.mental != null:
		var diff: float = sim.mental.social_difficulty(sim.mental_cfg())
		mult *= 1.0 - diff * (0.3 if coping != "" else 0.5)
	# Novost – stejnou věc dvakrát po sobě dělá nerad (impulzivní méně).
	if a["id"] == sim.last_action_id:
		mult *= 0.6 / Traits.mult_param(sim.trait_profile, "novelty")
	return gain * mult


## Chuť omluvit se konkrétní postavě: vina × pýcha povahy; hned po konfliktu (ještě to vře)
## a u blízkých vztahů bez křivdy méně. base = obecné násobiče akce (nálada, deprese, úzkost).
static func apology_score(sim, other, base: float, friendship: float) -> float:
	var g: float = sim.ledger.guilt_of(other.sim_name)
	if g < APOLOGY_GUILT:
		return 0.0
	if sim.now() - float(sim.ledger.apologized_to.get(other.sim_name, -1.0e9)) < APOLOGY_COOLDOWN:
		return 0.0
	var s := g * 0.8 * Traits.mult_param(sim.trait_profile, "pride") * base
	if friendship > 50.0:
		s *= 0.4  # vztah je v pořádku, není co spravovat
	var since: float = sim.now() - float(other.ledger.hurt_at.get(sim.sim_name, -1.0e9))
	if since < 40.0:
		s *= 0.2
	return s


## Vrátí {"action": Dictionary, "target": Node3D|null, "score": float} nebo {}.
static func choose(sim, objects: Array, sims: Array, rng: RandomNumberGenerator, hour: int) -> Dictionary:
	var cands: Array = []
	for a in ActionLibrary.ACTIONS:
		if bool(a.get("player_only", false)) or bool(a.get("involuntary", false)) or bool(a.get("system", false)):
			continue
		if not sim.content_allowed(String(a.get("content", ""))):
			continue
		var obj_tag: String = a.get("object", "")
		var base := score_action(sim, a, hour)
		if base <= 0.0:
			continue
		if obj_tag == "":
			cands.append({"action": a, "target": null, "score": base})
		elif obj_tag == "sim":
			for other in sims:
				if other == sim or not other.can_join_social(sim):
					continue
				var friendship: float = float(sim.relationships.get(other.sim_name, 0.0))
				if a["id"] == "apologize":
					var sa := apology_score(sim, other, base, friendship)
					if sa > 0.0:
						cands.append({"action": a, "target": other,
							"score": sa / (1.0 + sim.global_position.distance_to(other.global_position) / DISTANCE_SCALE)})
					continue
				var s: float = base * (1.0 + friendship / 200.0)
				# Nepřátelům se lidé vyhýbají; svěřují se jen tomu, komu věří.
				if friendship < -40.0:
					s *= 0.35
				if String(a.get("coping", "")) == "confide":
					s *= clampf(0.2 + friendship / 60.0, 0.05, 1.3)
				s /= 1.0 + sim.global_position.distance_to(other.global_position) / DISTANCE_SCALE
				if s > 0.0:
					cands.append({"action": a, "target": other, "score": s})
		else:
			var best_obj: Node3D = null
			var best_d := INF
			for o in objects:
				if o.object_tag == obj_tag and o.is_available(sim):
					var d: float = sim.global_position.distance_to(o.global_position)
					if d < best_d:
						best_d = d
						best_obj = o
			if best_obj != null:
				cands.append({"action": a, "target": best_obj, "score": base / (1.0 + best_d / DISTANCE_SCALE)})
	if cands.is_empty():
		return {}
	cands.sort_custom(func(x, y): return x["score"] > y["score"])
	var top: float = cands[0]["score"]
	var pool: Array = []
	var total := 0.0
	for c in cands:
		if c["score"] >= top * TOP_RATIO and pool.size() < TOP_COUNT:
			pool.append(c)
			total += c["score"]
	var r := rng.randf() * total
	for c in pool:
		r -= c["score"]
		if r <= 0.0:
			return c
	return pool[0]
