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
## Hygiene needs a little lead time: the NPC must finish/walk to a shower,
## and both decay and object reservation continue during that delay.
## Do not change the strict <10 acceptance threshold to hide the problem.
const HYGIENE_SHOWER_PRIORITY := 24.0
const HYGIENE_INTERRUPT_AT := 20.0


## Deterministic, bounded early-care choice. It never displaces a critical
## hunger/energy requirement, an unavailable shower, or player commands.
## Called when an NPC is idle and when an interruptible job risks neglect.
static func urgent_hygiene_plan(sim, objects: Array) -> Dictionary:
	if float(sim.needs.values.get("hygiene", 100.0)) >= HYGIENE_SHOWER_PRIORITY:
		return {}
	if float(sim.needs.values.get("hunger", 100.0)) < HUNGER_CRITICAL \
			or float(sim.needs.values.get("energy", 100.0)) < ENERGY_CRITICAL:
		return {}
	var shower: Dictionary = ActionLibrary.get_action("shower")
	if shower.is_empty() or not sim.content_allowed(String(shower.get("content", ""))):
		return {}
	var best_obj: Node3D = null
	var best_distance := INF
	for obj in objects:
		if obj.object_tag != "shower" or not obj.is_available(sim):
			continue
		var distance: float = sim.global_position.distance_to(obj.global_position)
		if distance < best_distance:
			best_obj = obj
			best_distance = distance
	if best_obj == null:
		return {}
	return {"action": shower, "target": best_obj, "score": 1.0e5}



## Trust influences willingness to confide, but it never forbids the action.
static func confide_trust_weight(value: float) -> float:
	return clampf((value + 10.0) / 70.0, 0.12, 1.55)


static func expected_effects(a: Dictionary) -> Dictionary:
	var e: Dictionary = a.get("effects", {}).duplicate()
	var rate: Dictionary = a.get("rate", {})
	var hours: float = float(a.get("duration", 30.0)) / 60.0
	for k in rate:
		e[k] = float(e.get(k, 0.0)) + float(rate[k]) * hours
	return e


static func score_action(sim, a: Dictionary, hour: int) -> float:
	# Akce rozšíření psychiky s bránou (např. vyhledat pomoc): AI je volí jen s důvodem; hráč vždy může.
	if a.has("psyche_gate") and (not sim.has_method("psyche_gate") or float(sim.psyche_gate(String(a["psyche_gate"]))) <= 0.0):
		return 0.0
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
	if a.has("pressure_kind"):
		var grievance := 0.0
		for v in sim.ledger.grudges.values():
			grievance = maxf(grievance, float(v))
		var anger: float = float(sim.emotions.level("anger"))
		# Most NPCs will NOT use coercive behavior: rare escalating
		# circumstances and a long shared cooldown are needed, not diagnoses
		# or fixed personality categories. No gain from sexual consequences.
		var min_anger := 48.0
		var min_grudge := 12.0
		match String(a["pressure_kind"]):
			"guilt_trip":
				min_anger = 65.0
				min_grudge = 24.0
			"blame_shift":
				min_anger = 70.0
				min_grudge = 28.0
			"emotional_blackmail":
				min_anger = 88.0
				min_grudge = 48.0
		if anger < min_anger or grievance < min_grudge \
				or sim.now() - float(sim.last_tag_time.get("pressure", -1.0e12)) < 720.0:
			return 0.0
		gain += (anger - min_anger) * 0.11
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
	# Stažení do sebe v depresivní epizodě (podle stupně): méně společnosti a náročných povinností,
	# víc samoty a klidu. Svěřit se je těžší jen mírně (cesta k podpoře zůstává otevřená).
	if sim.mental != null:
		var w: float = sim.mental.dep.withdrawal()
		if w > 0.0:
			if tags.has("social") and not tags.has("pressure"):
				mult *= 1.0 - w * (0.4 if coping == "confide" else 1.0)
			if tags.has("exercise") or tags.has("repair") or tags.has("cooking"):
				mult *= 1.0 - 0.5 * w
			if coping == "hide" or tags.has("quiet"):
				mult *= 1.0 + w
	# Novost – stejnou věc dvakrát po sobě dělá nerad (impulzivní méně).
	if a["id"] == sim.last_action_id:
		mult *= 0.6 / Traits.mult_param(sim.trait_profile, "novelty")
	# Emotions add only a small preference shift. Needs, diagnosis and mood retain
	# their own independent effects; no emotion ever forces an action.
	if sim.has_method("emotional_action_weight"):
		mult *= sim.emotional_action_weight(String(a["id"]), tags)
	# Rozšíření psychiky (neuro profil a další osy): omezený spojitý násobič, neutrální postava = 1,0.
	if sim.has_method("psyche_action_weight"):
		mult *= sim.psyche_action_weight(a)
	return gain * mult


## Ve stresu nebo v depresi se postava radši vyhne člověku, na kterého má pifku (křivda, čerstvá
## výtka), než aby šla do další třenice. Omluvy a nátlak (mají vlastní pravidla) se netýká.
static func avoidance_weight(sim, other, a: Dictionary) -> float:
	if sim.mental == null or a.has("pressure_kind") or String(a.get("id", "")) == "apologize":
		return 1.0
	var av: float = sim.mental.avoidance(sim.mental_cfg())
	if av <= 0.0:
		return 1.0
	var sore: float = float(sim.ledger.grudge(other.sim_name)) / 30.0 if sim.ledger != null else 0.0
	if sim.pending_complaints.has(other.sim_name):
		sore += 0.5
	return 1.0 - av * clampf(sore, 0.0, 1.0)


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
	# Emergency prevention: choose a free shower while there is still enough
	# time to walk there. This does NOT force a player-controlled NPC.
	var early_care := urgent_hygiene_plan(sim, objects)
	if not early_care.is_empty():
		return early_care
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
				if a.has("pressure_kind") and sim.ledger.grudge(other.sim_name) < 12.0:
					continue
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
				s *= avoidance_weight(sim, other, a)
				if sim.has_method("emotional_target_weight"):
					s *= sim.emotional_target_weight(other.sim_name, String(a["id"]))
				if sim.has_method("psyche_target_weight"):
					s *= sim.psyche_target_weight(other, a)
				if String(a.get("coping", "")) == "confide":
					# Liking alone is insufficient to feel safe sharing vulnerabilities.
					var trust_value: float = sim.ledger.trust_in(other.sim_name)
					s *= clampf(0.2 + friendship / 60.0, 0.05, 1.3)
					s *= confide_trust_weight(trust_value)
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
