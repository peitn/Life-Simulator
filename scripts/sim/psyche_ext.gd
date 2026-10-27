extends RefCounted
## PsycheExt – rozšíření psychiky (27. 10. 2026 a dál) nad existujícím MentalState / Depression / emocemi.
## Jeden koordinátor, který SimAgent volá na pár pevných místech (krok, výběr akce, výběr partnera,
## konec akce, sociální výsledek, uložení). Jednotlivé osy jsou samostatné čisté moduly:
##   neuro  – neurodivergentní profil (psychika A)
##   memory – sociální a afektivní paměť se schopnostmi paměti (psychika B)
##   mood   – průběh nálady v čase: epizody nahoru/dolů, dlouhodobě nízká nálada (psychika C)
##   voice  – vnitřní hlas: smyčky ruminace a naděje z dat (psychika I); běží u každého s tématy zapnutými
##   accents – osobnostní akcenty se zvýrazněnými rysy (psychika D), volitelný soukromý výklad
##
## Společné zásady (konvence projektu):
##   - diagnóza = predispozice nad dimenzemi, žádné nálepky ani šablony; dvě stejné nálepky ≠ stejné chování;
##   - symptomy mohou být mimovolné, ale hráč není nikdy zamčený (příkaz se neodmítne);
##   - režim obsahu: k = 1 (full), 0,5 (muted), 0 (off – žádný účinek, násobiče přesně 1);
##   - vlastní RNG (seed z postavy), takže výchozí postava bez posuvníků nespotřebuje jediné číslo
##     z hlavního RNG a chování starých testů zůstane bitově stejné;
##   - soukromé: nic z toho nejde do veřejného snapshotu, spawnu ani net_detail (jen offline hud_info).

const NeuroProfile := preload("res://scripts/sim/neuro_profile.gd")
const SocialMemory := preload("res://scripts/sim/social_memory.gd")
const MoodCycle := preload("res://scripts/sim/mood_cycle.gd")
const InnerVoice := preload("res://scripts/sim/inner_voice.gd")
const PersonalityAccents := preload("res://scripts/sim/personality_accents.gd")
const OcdLoop := preload("res://scripts/sim/ocd_loop.gd")
const SAVE_KEYS := ["neuro", "memory", "mood", "voice", "ocd", "rng_state", "mode"]

var neuro = NeuroProfile.new()
## Sociální a afektivní paměť (psychika B) – běží u každé postavy (je to běžné poznávání, ne téma
## duševního zdraví); režim obsahu tlumí jen individuální odchylku schopností paměti.
var memory = SocialMemory.new()
var _memory_cfg := {}
## Průběh nálady (psychika C): bipolární spektrum, cyklotymní a dystymní průběh.
var mood = MoodCycle.new()
## Vnitřní hlas (psychika I): ruminace, starosti, sebekritika, naděje; opt-in pasivní beznaděj.
var voice = InnerVoice.new()
## Osobnostní akcenty (psychika D): váhy rysů acc_* a háčky do vztahových systémů.
var accents = PersonalityAccents.new()
var _accent_cfg := {}
var _accent_labels := false
## OCD smyčka (psychika E) a závažnost sociální úzkosti (predispozice).
var ocd = OcdLoop.new()
var social_anxiety := 0.0
var rng := RandomNumberGenerator.new()
## Poslední známý režim obsahu ("full" / "muted" / "off").
var mode := "full"


static func mode_k(m: String) -> float:
	match m:
		"off":
			return 0.0
		"muted":
			return 0.5
	return 1.0


func k() -> float:
	return mode_k(mode)


## Konfigurace ze soukromého `mind` a dispozic D (PsycheModel). keep_state = živá úprava v editoru
## (naučený stav se nemaže), jinak čistý start (spawn).
func configure(mind: Dictionary, _d: Dictionary, seed: int, keep_state: bool) -> void:
	if not keep_state:
		rng.seed = (int(seed) * 0x2545F491 + 0x1F3D5B79) & 0x7FFFFFFFFFFFFFFF
	var mc = mind.get("memory", {})
	_memory_cfg = (mc as Dictionary).duplicate() if typeof(mc) == TYPE_DICTIONARY else {}
	memory.configure(_memory_cfg, k())
	if not keep_state:
		memory = SocialMemory.new()
		memory.configure(_memory_cfg, k())
	mood.configure(mind.get("mood", {}), keep_state)
	if not keep_state:
		voice = InnerVoice.new()
	voice.configure(mind.get("thoughts", {}))
	var ac = mind.get("accents", {})
	_accent_cfg = (ac as Dictionary).duplicate() if typeof(ac) == TYPE_DICTIONARY else {}
	_accent_labels = bool(mind.get("accent_labels", false)) if typeof(mind.get("accent_labels", false)) == TYPE_BOOL else false
	accents.configure(_accent_cfg, _accent_labels, k())
	var preds = mind.get("predispositions", {})
	if typeof(preds) != TYPE_DICTIONARY:
		preds = {}
	ocd.configure(preds.get("ocd", 0.0), mind.get("ocd_theme", "checking"), keep_state)
	var sa = preds.get("social_anxiety", 0.0)
	social_anxiety = clampf(float(sa), 0.0, 1.0) if typeof(sa) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(sa)) else 0.0
	var explicit = mind.get("dispositions", {})
	neuro.configure(mind.get("neuro", {}), mind.get("interest_focus", "reading"),
		explicit if typeof(explicit) == TYPE_DICTIONARY else {}, keep_state)


## Režim obsahu se změnil (přepnutí za běhu): přepočítá, co na něm závisí.
func set_mode(m: String) -> void:
	mode = m
	memory.configure(_memory_cfg, k())
	accents.configure(_accent_cfg, _accent_labels, k())


## Je NEURO část pro tuto postavu neutrální (žádný posuvník)? Pak SimAgent nemusí nic počítat.
## (Sociální paměť běží vždy a má vlastní, omezené účinky.)
func is_neutral() -> bool:
	return neuro.is_empty() and mood.is_empty() and accents.is_empty() and ocd.is_empty() and social_anxiety <= 0.0


## Pro OCD váhy (pocit zvládání a opora z MentalState) – nastavuje SimAgent před dotazem.
var _mastery := 0.5
var _support := 0.0


func action_weight(act: Dictionary, hour: int) -> float:
	var kk := k()
	if kk <= 0.0:
		return 1.0
	return clampf(neuro.action_weight(act, hour, kk) * mood.action_weight(act, hour, kk) * voice.action_weight(act, kk) * accents.action_weight(act) * ocd.action_weight(act, kk, float(_mastery), float(_support)), 0.2, 8.0)


## Výběr partnera: neuro (maskování) × sociální paměť (jen chat a svěření).
func target_weight(rel: float, act: Dictionary, who_uid: String = "") -> float:
	var w := 1.0
	var kk := k()
	if kk > 0.0 and not neuro.is_empty():
		w *= neuro.target_weight(rel, act, kk)
	# Sociální úzkost: méně blízcí lidé jsou náročnější partneři (nikdy zákaz).
	if kk > 0.0 and social_anxiety > 0.0 and (act.get("tags", []) as Array).has("social"):
		w *= clampf(1.0 - 0.3 * social_anxiety * kk * clampf(1.0 - rel / 60.0, 0.0, 1.0), 0.7, 1.0)
	var id := String(act.get("id", ""))
	if who_uid != "" and (id == "chat" or id == "confide"):
		w *= memory.target_weight(who_uid, id)
	return w


func to_dict() -> Dictionary:
	return {"neuro": neuro.to_dict(), "memory": memory.to_dict(), "mood": mood.to_dict(), "voice": voice.to_dict(), "ocd": ocd.to_dict(), "rng_state": rng.state, "mode": mode}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 32:
		return false
	for key in d:
		if typeof(key) != TYPE_STRING or not SAVE_KEYS.has(key):
			return false
	if d.has("neuro") and not NeuroProfile.validate_snapshot(d["neuro"]):
		return false
	if d.has("memory") and not SocialMemory.validate_snapshot(d["memory"]):
		return false
	if d.has("mood") and not MoodCycle.validate_snapshot(d["mood"]):
		return false
	if d.has("voice") and not InnerVoice.validate_snapshot(d["voice"]):
		return false
	if d.has("ocd") and not OcdLoop.validate_snapshot(d["ocd"]):
		return false
	if d.has("rng_state") and typeof(d["rng_state"]) != TYPE_INT:
		return false
	if d.has("mode") and (typeof(d["mode"]) != TYPE_STRING or not String(d["mode"]) in ["full", "muted", "off"]):
		return false
	return true


func from_dict(d: Variant) -> bool:
	if not validate_snapshot(d):
		return false
	if d.has("neuro"):
		neuro.from_dict(d["neuro"])
	if d.has("memory"):
		memory.from_dict(d["memory"])
	if d.has("mood"):
		mood.from_dict(d["mood"])
	if d.has("voice"):
		voice.from_dict(d["voice"])
	if d.has("ocd"):
		ocd.from_dict(d["ocd"])
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	if d.has("mode"):
		set_mode(String(d["mode"]))
	return true
