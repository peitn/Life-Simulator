extends RefCounted
const Traits := preload("res://scripts/sim/traits.gd")
## Individuální citlivosti postavy (ladění po zátěžovém testu 7 postav × 30 dní, 23. 10. 2026).
##
## Ne každému vadí hluk stejně a ne každého potěší totéž stejně. Profil je čistý a deterministický:
## vychází z rysů povahy, predispozic a z vlastního seedu postavy (nikdy ze jména ani z identity).
##   hypersensitivity – obecná citlivost na zvuk/dav/jas/dotyk (z privátní dimenze D)
##   noise_sens   – individuální sluchová složka, zachovává se kvůli starým simulacím
##   crowd_sens   – jak moc vyčerpává tlačenice: samotář hodně, společenský skoro vůbec
##   joy_sens     – citlivost na příjemné (rozhovor, ranní světlo, dobré jídlo): optimista víc, cynik méně
##   light_sens   – jak moc potěší ranní světlo
##   anticip_thr  – práh těšení: jak velká musí být očekávaná radost, aby postavu vůbec táhla.
##                  Nízký práh = těší se snadno (optimista, hravý), vysoký = „stejně to nebude stát za nic“.
## Návyky (habituace) se učí za běhu: kdo spí každou noc vedle televize, časem ji přestane vnímat.

const NOISE := {"lenoch": -0.3, "spolecensky": -0.15, "hravy": -0.1, "pedant": 0.2, "uzkostlivy": 0.3,
	"samotar": 0.2, "vznetlivy": 0.15, "brucoun": 0.1}
const CROWD := {"samotar": 0.6, "spolecensky": -0.45, "uzkostlivy": 0.3, "knihomol": 0.15, "hravy": -0.15,
	"brucoun": 0.15, "aktivni": -0.1}
const JOY := {"optimista": 0.2, "hravy": 0.15, "gurman": 0.05, "spolecensky": 0.05, "cynik": -0.25, "brucoun": -0.15}
const LIGHT := {"aktivni": 0.2, "optimista": 0.15, "lenoch": -0.15}
const THRESHOLD := {"optimista": -0.7, "hravy": -0.4, "impulzivni": -0.3, "spolecensky": -0.2, "cynik": 1.5,
	"brucoun": 1.0, "lenoch": 0.5}

## Maximální návyk (kolik podnětu postava „přestane vnímat“).
const HABIT_MAX := 0.7
## Doba, za kterou návyk vyprchá, když podnět přestane (min).
const HABIT_TAU := 14400.0

var hypersensitivity := 0.5
var noise_sens := 0.8
var crowd_sens := 0.6
var joy_sens := 1.0
var light_sens := 1.0
var anticip_thr := 1.0
var noise_habit := 0.0
var crowd_habit := 0.0
## Citlivost po kanálech z neurodivergentního profilu (mind.neuro.sens_*): kanál → zisk ≥ 0, násobí
## sensory_factor (1 + zisk). Prázdné = beze změny. Odvozené z CharacterData, neukládá se.
var channel_gain := {}


static func _sum(table: Dictionary, traits: Variant) -> float:
	var s := 0.0
	for t in (traits.keys() if typeof(traits) == TYPE_DICTIONARY else traits):
		s += float(table.get(String(t), 0.0)) * Traits.weight(traits, String(t))
	return s


## Spočítá profil. conditions = {"anxiety": 0..1, "depression": 0..1}, seed = seed postavy.
func setup(traits: Variant, conditions: Dictionary, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	# Explicitní míchání seedu (Gemini, běh 23): nezávisí na implementaci hash() pro pole, takže profil
	# zůstane stejný i po změně verze enginu (uložené hry, server × klient).
	r.seed = (seed * 0x9E3779B1 + 0x5E5E5017) & 0x7FFFFFFFFFFFFFFF
	var anx := float(conditions.get("anxiety", 0.0))
	noise_sens = clampf(0.8 + _sum(NOISE, traits) + anx * 0.3 + r.randfn(0.0, 0.15), 0.2, 1.6)
	crowd_sens = clampf(0.6 + _sum(CROWD, traits) + anx * 0.4 + r.randfn(0.0, 0.15), 0.05, 1.6)
	joy_sens = clampf(1.0 + _sum(JOY, traits) + r.randfn(0.0, 0.1), 0.6, 1.4)
	light_sens = clampf(1.0 + _sum(LIGHT, traits) + r.randfn(0.0, 0.2), 0.3, 1.6)
	anticip_thr = clampf(1.0 + _sum(THRESHOLD, traits) + r.randfn(0.0, 0.4), 0.0, 4.0)


## Kolik radosti postava právě dokáže prožít (0..1.4): anhedonie (liking z deprese) a stres ji tlumí.
func joy_capacity(hedonic: float, stress: float) -> float:
	var st := clampf((stress - 50.0) / 50.0, 0.0, 1.0)
	return joy_sens * clampf(hedonic, 0.0, 1.0) * (1.0 - 0.45 * st)


## Účinný práh těšení: pesimismus a stres ho zvedají („nic mě nebaví“).
func threshold(pessimism: float, stress: float) -> float:
	return anticip_thr * (1.0 + pessimism) + maxf(stress - 60.0, 0.0) / 20.0


## Očekávaná radost po prahu: pod prahem táhne jen málo, nad ním naplno.
func anticipation_after_threshold(ant: float, pessimism: float, stress: float) -> float:
	if ant <= 0.0:
		return ant
	var thr := threshold(pessimism, stress)
	return maxf(ant - thr, 0.0) + 0.3 * minf(ant, thr)


## D.sensory_sensitivity is a broad hypersensitivity slider (0..1), while
## noise_sens/crowd_sens preserve older individual baselines and habituation.
## Neutral slider 0.5 exactly preserves legacy behaviour.
func configure(d: Dictionary) -> void:
	hypersensitivity = clampf(float(d.get("sensory_sensitivity", 0.5)), 0.0, 1.0)


func sensory_factor(channel: String) -> float:
	var w := 0.0
	match channel:
		"noise": w = 0.45
		"crowd": w = 0.35
		"bright_light": w = 0.55
		"touch": w = 0.45
		_: return 1.0
	var f := clampf(1.0 + (hypersensitivity - 0.5) * 2.0 * w, 0.45, 1.55)
	if not channel_gain.is_empty():
		f *= 1.0 + clampf(float(channel_gain.get(channel, 0.0)), 0.0, 1.0)
	return f


## Kolik potěší ranní světlo: u citlivosti na světlo méně (ostré světlo spíš unavuje), nikdy záporně.
func morning_light_factor() -> float:
	var g := clampf(float(channel_gain.get("bright_light", 0.0)), 0.0, 1.0)
	return light_sens * (1.0 - 0.85 * g)


## Hluk je jedna dílčí složka hypersenzitivity, stále s vlastním návykem.
func noise_factor() -> float:
	return noise_sens * (1.0 - noise_habit) * sensory_factor("noise")


func crowd_factor() -> float:
	return crowd_sens * (1.0 - crowd_habit) * sensory_factor("crowd")


## Postava byla vystavena hluku (habituace roste pomalu, nejvýš HABIT_MAX).
func expose_noise(amount: float) -> void:
	noise_habit = clampf(noise_habit + 0.02 * amount * (HABIT_MAX - noise_habit), 0.0, HABIT_MAX)


func expose_crowd(dm: float) -> void:
	crowd_habit = clampf(crowd_habit + 0.0004 * dm * (HABIT_MAX - crowd_habit), 0.0, HABIT_MAX)


func tick(dm: float) -> void:
	var k := exp(-dm / HABIT_TAU)
	noise_habit *= k
	crowd_habit *= k


func to_dict() -> Dictionary:
	return {"hypersensitivity": hypersensitivity, "noise_sens": noise_sens, "crowd_sens": crowd_sens, "joy_sens": joy_sens, "light_sens": light_sens,
		"anticip_thr": anticip_thr, "noise_habit": noise_habit, "crowd_habit": crowd_habit}
