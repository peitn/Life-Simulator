extends Node
## GameSettings (autoload „GameSettings“) – nastavení obsahu a prezentace.
##
## Citlivá témata jdou ztlumit nebo vypnout. V multiplayeru rozhoduje o SIMULACI (vznikají
## panické ataky? je dostupný alkohol?) nastavení serveru; o PREZENTACI (zobrazení rušivých
## myšlenek, zkreslení obrazu/zvuku, cenzura sprostých slov) nastavení každého klienta.
## Ukládá se do user://settings.cfg (v testech lze ukládání vypnout přes `persist = false`).

signal changed(key: String)

const PATH := "user://settings.cfg"

## Krizová pomoc – zobrazuje se v úvodním varování a v menu.
const CRISIS_LINES := [
	["Linka první psychické pomoci (ČR)", "116 123", "nonstop, zdarma, anonymně"],
	["Mezinárodní přehled linek pomoci", "findahelpline.com", "vyhledá linku ve tvé zemi"],
	["Bezprostřední ohrožení života", "112 / 155", "tísňové volání a záchranná služba"],
]
const HELPLINE_URL := "https://findahelpline.com"

const CONTENT_WARNING := """Life Simulator je hra pro dospělé. Zobrazuje syrový život včetně temných stránek:
konflikty a hádky, sprostou mluvu, nevěru, chudobu a dluhy, závislosti (alkohol, hazard),
drobnou kriminalitu, nemoc a smrt.

Postavy mohou prožívat duševní potíže – stres, úzkost, panické ataky, depresi a později i další stavy.
Snažíme se je zobrazovat citlivě a realisticky: jako stavy, které se mění, mají spouštěče
a dobré i špatné dny. Hra umožňuje hledat podporu a zotavovat se – ne vždy rychle a ne v přímé
linii, ale ta možnost se nikdy neuzavře. Hra neodměňuje sebeubližování
a sebevražda není hratelná akce.

Všechna citlivá témata můžeš kdykoli ztlumit nebo vypnout v Nastavení (Esc)."""

## Režimy témat duševního zdraví.
const MH_FULL := "full"
const MH_MUTED := "muted"
const MH_OFF := "off"
const MH_MODES := [MH_FULL, MH_MUTED, MH_OFF]
const MH_LABELS := {"full": "Plně", "muted": "Ztlumeně", "off": "Vypnuto"}
## Intenzita rušivých myšlenek: 0 vypnuto … 3 silná.
const THOUGHT_LABELS := ["Vypnuto", "Jemně", "Normálně", "Silně"]
const THOUGHT_RATE := [0.0, 0.4, 1.0, 1.6]

const DEFAULTS := {
	"mental_health": "full",
	"intrusive_thoughts": 2,
	"distortion_fx": true,
	"distortion_strength": 1.0,
	"addiction": true,
	"profanity": true,
	## Sebepoškozování a poruchy příjmu potravy – zatím se ve hře nevyskytují; až přibudou,
	## budou se zobrazovat jen přes emoce, vztahy a důsledky. Výchozí stav: skrýt.
	"sh_ed_topics": false,
	"warning_ack": false,
}

## Sprostá slova pro cenzuru (kmeny; porovnává se začátek slova bez diakritiky na malých písmenech).
const PROFANITY := ["kurv", "prdel", "kreten", "debil", "vole", "kokot", "sracka", "hovn", "zasran", "pica", "jebat", "jeba", "poser", "posra", "do haje"]

var values := DEFAULTS.duplicate()
var persist := true


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	values = DEFAULTS.duplicate()
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cfg.has_section_key("content", k):
			set_value(k, cfg.get_value("content", k), false)


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("content", k, values[k])
	cfg.save(PATH)


## Nastaví hodnotu s validací typu a rozsahu. Neplatné hodnoty ignoruje.
func set_value(key: String, v: Variant, save := true) -> bool:
	if not DEFAULTS.has(key):
		return false
	var def: Variant = DEFAULTS[key]
	var nv: Variant
	match key:
		"mental_health":
			if typeof(v) != TYPE_STRING or not MH_MODES.has(String(v)):
				return false
			nv = String(v)
		"intrusive_thoughts":
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return false
			nv = clampi(int(v), 0, 3)
		"distortion_strength":
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return false
			nv = clampf(float(v), 0.0, 1.0)
		_:
			if typeof(v) != typeof(def):
				return false
			nv = v
	values[key] = nv
	changed.emit(key)
	if save:
		save_settings()
	return true


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func reset() -> void:
	values = DEFAULTS.duplicate()
	for k in values:
		changed.emit(k)


# ---------------------------------------------------------------- dotazy pro simulaci

func mental_health_mode() -> String:
	return String(values["mental_health"])


## Mohou vznikat panické ataky a jiné výrazné epizody?
func allows_episodes() -> bool:
	return mental_health_mode() == MH_FULL


## Projevují se diagnózy (predispozice) vůbec? Při „vypnuto“ zůstává jen běžný životní stres.
func allows_conditions() -> bool:
	return mental_health_mode() != MH_OFF


## Násobič četnosti rušivých myšlenek (0 = žádné).
func thought_rate() -> float:
	if mental_health_mode() == MH_OFF:
		return 0.0
	var r: float = THOUGHT_RATE[clampi(int(values["intrusive_thoughts"]), 0, 3)]
	if mental_health_mode() == MH_MUTED:
		r *= 0.4
	return r


func allows_addiction() -> bool:
	return bool(values["addiction"])


func distortion_strength() -> float:
	if not bool(values["distortion_fx"]) or mental_health_mode() == MH_OFF:
		return 0.0
	var s: float = float(values["distortion_strength"])
	if mental_health_mode() == MH_MUTED:
		s *= 0.4
	return s


## Je akce s daným obsahovým štítkem povolená? (štítky v ActionLibrary: "content")
func allows_content(tag: String) -> bool:
	match tag:
		"":
			return true
		"addiction":
			return allows_addiction()
		"mental_health":
			return allows_conditions()
		"sh_ed":
			return bool(values["sh_ed_topics"])
	return true


# ---------------------------------------------------------------- dotazy pro prezentaci

## Cenzura sprostých slov (když je hráč vypnul). Zachová délku slova (k***a).
func filter_profanity(text: String) -> String:
	if bool(values["profanity"]) or text == "":
		return text
	return censor(text)


static func censor(text: String) -> String:
	var out := text
	var plain := _fold(text.to_lower())
	for stem in PROFANITY:
		var from := 0
		while true:
			var i := plain.find(stem, from)
			if i < 0:
				break
			# Jen začátek slova (ať se necenzuruje „svoleno“ apod.).
			if i > 0 and _is_letter(plain[i - 1]):
				from = i + 1
				continue
			var end := i
			while end < plain.length() and (_is_letter(plain[end]) or plain[end] == " " and end < i + stem.length()):
				end += 1
			if end - i >= 2:
				var masked := out.substr(i, 1) + "*".repeat(end - i - 1)
				out = out.substr(0, i) + masked + out.substr(end)
			from = end
	return out


static func _is_letter(c: String) -> bool:
	return c.to_upper() != c.to_lower()


## Odstraní diakritiku (stejná délka řetězce – jen české znaky 1:1).
static func _fold(s: String) -> String:
	const FROM := "áčďéěíňóřšťúůýž"
	const TO := "acdeeinorstuuyz"
	var out := s
	for i in FROM.length():
		out = out.replace(FROM[i], TO[i])
	return out
