extends RefCounted
## PsycheExt – rozšíření psychiky (27. 10. 2026 a dál) nad existujícím MentalState / Depression / emocemi.
## Jeden koordinátor, který SimAgent volá na pár pevných místech (krok, výběr akce, výběr partnera,
## konec akce, sociální výsledek, uložení). Jednotlivé osy jsou samostatné čisté moduly:
##   neuro – neurodivergentní profil (psychika A)
##
## Společné zásady (konvence projektu):
##   - diagnóza = predispozice nad dimenzemi, žádné nálepky ani šablony; dvě stejné nálepky ≠ stejné chování;
##   - symptomy mohou být mimovolné, ale hráč není nikdy zamčený (příkaz se neodmítne);
##   - režim obsahu: k = 1 (full), 0,5 (muted), 0 (off – žádný účinek, násobiče přesně 1);
##   - vlastní RNG (seed z postavy), takže výchozí postava bez posuvníků nespotřebuje jediné číslo
##     z hlavního RNG a chování starých testů zůstane bitově stejné;
##   - soukromé: nic z toho nejde do veřejného snapshotu, spawnu ani net_detail (jen offline hud_info).

const NeuroProfile := preload("res://scripts/sim/neuro_profile.gd")
const SAVE_KEYS := ["neuro", "rng_state", "mode"]

var neuro = NeuroProfile.new()
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
	var explicit = mind.get("dispositions", {})
	neuro.configure(mind.get("neuro", {}), mind.get("interest_focus", "reading"),
		explicit if typeof(explicit) == TYPE_DICTIONARY else {}, keep_state)


## Je rozšíření pro tuto postavu úplně neutrální (žádný posuvník)? Pak SimAgent nemusí nic počítat.
func is_neutral() -> bool:
	return neuro.is_empty()


func action_weight(act: Dictionary, hour: int) -> float:
	var kk := k()
	if kk <= 0.0:
		return 1.0
	return neuro.action_weight(act, hour, kk)


func target_weight(rel: float, act: Dictionary) -> float:
	var kk := k()
	if kk <= 0.0:
		return 1.0
	return neuro.target_weight(rel, act, kk)


func to_dict() -> Dictionary:
	return {"neuro": neuro.to_dict(), "rng_state": rng.state, "mode": mode}


static func validate_snapshot(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.size() > 32:
		return false
	for key in d:
		if typeof(key) != TYPE_STRING or not SAVE_KEYS.has(key):
			return false
	if d.has("neuro") and not NeuroProfile.validate_snapshot(d["neuro"]):
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
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	if d.has("mode"):
		mode = String(d["mode"])
	return true
