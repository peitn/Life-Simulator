extends RefCounted
## Career – práce, výkon, šéf, povýšení a rivalita v práci (K1, 24. 11. 2026).
##
## Proč: práce je velká část dospělého života a zdroj tlaku, hrdosti i špíny. Šéf má náladu, kolegové
## soupeří o stejné místo, někdo si přivlastní tvoje zásluhy. Deprese a úzkost práci nezakazují, ale
## berou sílu (kapacita, ne trest); kdo nemůže, může zavolat, že je nemocný – a šéf to vezme podle
## toho, jaký je. Vyhazov bolí a hledání nové práce s čerstvým vyhazovem je těžší. Hra za intriky nic
## neodměňuje jistě: někdy vyjdou, někdy tě chytí, oběť se to může dozvědět.
##
## Model (jen autorita, uvnitř HouseholdDynamics; náhodu dodává volající jako pole hodů 0..1):
## - OBOR (track) × ÚROVEŇ 0..4: název pozice podle gramatického rodu, mzda za směnu, začátek, délka
##   a pracovní dny v týdnu (0 = pondělí). Péče má víkendy, gastro začíná pozdě, sklad brzy.
## - ZÁZNAM postavy: obor ("" = bez práce), úroveň, výkon 0..100, názor šéfa −100..100, výtky 0..3,
##   vyhoření (strain 0..1), nemocenské dny, směny na úrovni, soupeření (race), napětí vůči NPC kolegům.
## - SMĚNA: začne (begin_shift), postava je mimo parcelu, po skončení resolve_shift spočítá výkon
##   (režim × kapacita z deprese/stresu/únavy/vyhoření + kvalita dne), šéfa, stres, mzdu, událost v práci
##   a případně intriku proti konkurenci. Odchod dřív: šéf podle důvodu (panika = pochopení, nebo stigma).
## - DOCHÁZKA: pracovní den bez směny a bez omluvy = absence → výtka. 3 výtky = vyhazov. Čistá řada
##   směn výtku časem smaže.
## - POVÝŠENÍ: dobrý výkon a odpracované směny otevřou souboj s kolegou na stejné úrovni – skutečnou
##   postavou (jiný hráč / AI) nebo NPC kolegou. Body sbírá každá směna; po RACE_DAYS rozhodne skóre.
##   Prohra živí rivalitu „o postavení“ (skutečná postava přes Rivalry, NPC přes npc_heat).
## - INTRIKA (režim „scheme“): jen během souboje; může vyjít (soupeř ztratí body), nebo prasknout (výtka,
##   šéf dolů). Oběť – skutečná postava – může zjistit, kdo za tím je. Strop: jedna škoda na oběť za den.
##
## Rewind (zpětný chod času): nic se neopakuje ani nevrací – směna i absence se počítají jen pro den
## POZDĚJŠÍ než poslední zapsaný (stejná zásada jako Rivalry/ColdWar).
##
## Data jsou soukromá: nereplikují se, vlastník je vidí v soukromých řádcích HUD bez čísel.

const VERSION := 1
const DAY := 1440.0

## Obory. levels: [[mužský, ženský, neutrální opis], mzda za celou směnu v kr]. days: dny v týdnu (0 = po).
## care = jak chápavý je typický šéf k nemoci a duševnímu zdraví (0..1); stress = zátěž oboru.
const TRACKS := {
	"retail": {"name": "Obchod", "start": 8, "hours": 8, "days": [0, 1, 2, 3, 4], "stress": 0.9, "care": 0.35,
		"levels": [[["pokladní", "pokladní", "osoba na pokladně"], 900], [["prodavač", "prodavačka", "osoba v prodeji"], 1050],
			[["zkušený prodavač", "zkušená prodavačka", "zkušená osoba v prodeji"], 1200],
			[["zástupce vedoucí", "zástupkyně vedoucí", "osoba zastupující vedení"], 1450], [["vedoucí prodejny", "vedoucí prodejny", "vedoucí prodejny"], 1800]]},
	"office": {"name": "Kancelář", "start": 9, "hours": 8, "days": [0, 1, 2, 3, 4], "stress": 0.8, "care": 0.55,
		"levels": [[["asistent", "asistentka", "asistující osoba"], 1000], [["referent", "referentka", "referentská pozice"], 1150],
			[["specialista", "specialistka", "specializovaná osoba"], 1400], [["vedoucí týmu", "vedoucí týmu", "vedoucí týmu"], 1750],
			[["manažer oddělení", "manažerka oddělení", "osoba ve vedení oddělení"], 2200]]},
	"care": {"name": "Péče", "start": 7, "hours": 8, "days": [0, 1, 3, 5, 6], "stress": 1.25, "care": 0.7,
		"levels": [[["pomocník v domově", "pomocnice v domově", "pomocná síla v domově"], 900], [["pečovatel", "pečovatelka", "pečující osoba"], 1050],
			[["zkušený pečovatel", "zkušená pečovatelka", "zkušená pečující osoba"], 1250],
			[["staniční", "staniční", "osoba vedoucí stanici"], 1500], [["vrchní", "vrchní", "osoba ve vrchní funkci"], 1850]]},
	"kitchen": {"name": "Gastro", "start": 11, "hours": 8, "days": [1, 2, 3, 4, 5], "stress": 1.15, "care": 0.2,
		"levels": [[["pomocná síla v kuchyni", "pomocná síla v kuchyni", "pomocná síla v kuchyni"], 850], [["kuchař", "kuchařka", "osoba u plotny"], 1050],
			[["kuchař směny", "kuchařka směny", "osoba vedoucí směnu v kuchyni"], 1250],
			[["zástupce šéfkuchaře", "zástupkyně šéfkuchaře", "osoba zastupující šéfkuchaře"], 1500], [["šéfkuchař", "šéfkuchařka", "osoba v čele kuchyně"], 1900]]},
	"warehouse": {"name": "Sklad", "start": 6, "hours": 8, "days": [0, 1, 2, 3, 4], "stress": 0.95, "care": 0.4,
		"levels": [[["skladník", "skladnice", "osoba ve skladu"], 950], [["řidič VZV", "řidička VZV", "osoba řídící VZV"], 1100],
			[["předák", "předačka", "osoba v čele party"], 1300], [["vedoucí směny", "vedoucí směny", "vedoucí směny"], 1550],
			[["vedoucí skladu", "vedoucí skladu", "vedoucí skladu"], 1900]]},
}
const TRACK_IDS := ["care", "kitchen", "office", "retail", "warehouse"]
## Minulá práce z příběhu postavy (CharacterData.story.past_work) → obor na začátku.
const PAST_WORK := {"gastro": "kitchen", "sklad": "warehouse", "doprava": "warehouse", "it": "office", "studium": "office",
	"kancelar": "office", "obchod": "retail", "prodej": "retail", "pece": "care", "zdravotnictvi": "care", "socialni": "care"}
## NPC kolegové v každém oboru: [jméno, ambice 0..1, poctivost 0..1]. Nejsou to postavy světa.
const COLLEAGUES := {
	"retail": [["Klára Hrubá", 0.75, 0.3], ["Ondřej Malý", 0.45, 0.8], ["Hana Vávrová", 0.6, 0.55]],
	"office": [["Marek Vlk", 0.85, 0.25], ["Petra Benešová", 0.55, 0.75], ["Jiří Kos", 0.4, 0.6]],
	"care": [["Lucie Pokorná", 0.5, 0.85], ["Radek Šimek", 0.65, 0.45], ["Věra Křížová", 0.35, 0.7]],
	"kitchen": [["Tomáš Kolář", 0.8, 0.35], ["Jana Dvořáková", 0.5, 0.65], ["Filip Mráz", 0.6, 0.4]],
	"warehouse": [["Pavel Čermák", 0.7, 0.4], ["Eva Holubová", 0.45, 0.8], ["Luboš Kratochvíl", 0.55, 0.3]],
}
const MODES := ["normal", "hard", "slack", "scheme"]
## Akce směny (ActionLibrary) → režim.
const SHIFT_ACTIONS := {"work_shift": "normal", "work_hard": "hard", "work_slack": "slack", "work_scheme": "scheme"}
const CAREER_ACTIONS := ["work_shift", "work_hard", "work_slack", "work_scheme", "call_in_sick", "job_search", "quit_job"]

## Okno příchodu: do práce lze vyrazit hodinu před začátkem až dvě hodiny po něm (pozdní příchod od +30 min).
const EARLY := 60.0
const LATE_FROM := 30.0
const LATE_UNTIL := 120.0
## Cesta na chodník trvá pár minut: začátek směny (begin_shift) toleruje BEGIN_GRACE po konci okna příkazu
## a kontrola absence čeká, dokud tahle tolerance neuplyne (audit Gemini 24. 11. #6).
const BEGIN_GRACE := 20.0
## Výkon a šéf.
const PERF_START := 50.0
const MODE_PERF := {"normal": 2.0, "hard": 4.5, "slack": -2.5, "scheme": 0.5}
const MODE_BOSS := {"normal": 1.0, "hard": 2.5, "slack": 0.0, "scheme": 0.0}
const MODE_STRAIN := {"normal": 0.04, "hard": 0.1, "slack": -0.02, "scheme": 0.05}
const MODE_STRESS := {"normal": 1.0, "hard": 1.4, "slack": 0.6, "scheme": 1.2}
const SHIFT_STRESS := 4.0
const STRAIN_DAY_OFF := 0.06
const STRAIN_HIGH := 0.6
const SLACK_CAUGHT_P := 0.3
const EARLY_LEAVE_PERF := 4.0
const EARLY_LEAVE_BOSS := 8.0
const LATE_PERF := 1.0
const LATE_BOSS := 3.0
## Docházka a výtky.
const ABSENCE_BOSS := 10.0
const MAX_WARNINGS := 3
const CLEAN_SHIFTS_FORGIVE := 10
const FIRE_PERF := 12.0
const FIRE_BOSS := -50.0
const SLACK_WARN_BOSS := -25.0
## Nemocenská: kolik omluvených dnů za SICK_WINDOW dní.
const SICK_BUDGET := 2
const SICK_WINDOW := 14
const MAX_SICK_LOG := 8
## Povýšení.
const PROMO_PERF := 65.0
const PROMO_SHIFTS := [4, 6, 8, 10]
const RACE_DAYS := 5
const PROMO_PERF_RESET := 55.0
const RACE_LOST_HEAT := 0.3
## Intrika.
const SCHEME_GAIN := 3.0
const SCHEME_HIT := 3.0
const SCHEME_VICTIM_PERF := 2.0
const SCHEME_CAUGHT_P := 0.25
const SCHEME_LEARN_P := 0.2
const SCHEME_CAUGHT_BOSS := 12.0
const SCHEME_CAUGHT_POINTS := 4.0
## Hledání práce.
const SEARCH_GAP := 240.0
const SEARCH_BASE := 0.3
const SEARCH_FIRED_DAYS := 7
## Události v práci.
const EVENT_P := 0.4
## Limity (hostile save / server).
const MAX_JOBS := 256
const MAX_RACES := 128
const MAX_NAME := 64
const MAX_NPC_HEAT := 8
const MAX_SCHEME_LOG := 256
const DAY_MIN := -1000000
const DAY_MAX := 100000000
const T_MIN := -1.0e9
const T_MAX := 1.0e12
const STAT_KEYS := ["shifts", "hard", "slack", "schemes", "schemes_caught", "absences", "sick", "fired", "hired",
	"searches", "quits", "races", "promotions", "events", "wages"]
const RECORD_KEYS := ["track", "level", "perf", "boss", "warnings", "level_shifts", "clean_shifts", "last_shift_day",
	"checked_day", "hired_day", "fired_day", "sick", "strain", "last_search", "race", "npc_heat", "last_track",
	"absences", "promotions", "ai_day", "ai_pick"]
const RACE_KEYS := ["a", "b", "npc", "pa", "pb", "until", "track", "level"]

var jobs := {}        # jméno postavy -> záznam (RECORD_KEYS)
var races := {}       # "id" -> souboj o povýšení (RACE_KEYS)
var next_race := 1
var schemed := {}     # "oběť>den" -> 1 (strop škody na oběť za den)
var stats := {}
## Poslední načtení: "" = v pořádku / prázdné, jinak důvod zahození sekce ("future_version", "type"…).
var load_note := ""


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {}
	for k in STAT_KEYS:
		stats[k] = 0


static func _valid_name(n) -> bool:
	return typeof(n) == TYPE_STRING and String(n) != "" and String(n).length() <= MAX_NAME \
		and not String(n).contains(">") and not String(n).contains("|")


static func _fin(v, lo: float, hi: float, dflt: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return dflt
	var f := float(v)
	if not is_finite(f):
		return dflt
	return clampf(f, lo, hi)


static func _int(v, lo: int, hi: int, dflt: int) -> int:
	if typeof(v) == TYPE_INT:
		return clampi(int(v), lo, hi)
	if typeof(v) == TYPE_FLOAT and is_finite(v) and floorf(v) == v:
		return clampi(int(v), lo, hi)
	return dflt


static func day_of(now: float) -> int:
	return int(floorf(now / DAY)) + 1


static func minute_of(now: float) -> float:
	return fposmod(now, DAY)


static func weekday_of(day: int) -> int:
	return posmod(day - 1, 7)


## Deterministický „hod“ 0..1 z textu (NPC kolegové, kteří nemají vlastní rng).
static func det(seed: String) -> float:
	return float(seed.hash() & 0xFFFF) / 65535.0


static func blank_record() -> Dictionary:
	return {"track": "", "level": 0, "perf": PERF_START, "boss": 0.0, "warnings": 0, "level_shifts": 0,
		"clean_shifts": 0, "last_shift_day": DAY_MIN, "checked_day": DAY_MIN, "hired_day": DAY_MIN,
		"fired_day": DAY_MIN, "sick": [], "strain": 0.0, "last_search": -1.0e9, "race": 0, "npc_heat": {},
		"last_track": "", "absences": 0, "promotions": 0, "ai_day": DAY_MIN, "ai_pick": ""}


# ------------------------------------------------------------------ katalog

static func job_title(track: String, level: int, grammar_col: int) -> String:
	if not TRACKS.has(track):
		return ""
	var lv: Array = TRACKS[track]["levels"]
	var row: Array = lv[clampi(level, 0, lv.size() - 1)]
	return String(row[0][clampi(grammar_col, 0, 2)])


static func shift_wage(track: String, level: int) -> int:
	if not TRACKS.has(track):
		return 0
	var lv: Array = TRACKS[track]["levels"]
	return int(lv[clampi(level, 0, lv.size() - 1)][1])


static func is_workday(track: String, day: int) -> bool:
	return TRACKS.has(track) and (TRACKS[track]["days"] as Array).has(weekday_of(day))


static func shift_start(track: String) -> float:
	return float(TRACKS[track]["start"]) * 60.0 if TRACKS.has(track) else 0.0


static func shift_minutes(track: String) -> float:
	return float(TRACKS[track]["hours"]) * 60.0 if TRACKS.has(track) else 0.0


## Obor z minulé práce v příběhu postavy; "" = bez práce.
static func track_from_story(past_work) -> String:
	if typeof(past_work) != TYPE_ARRAY:
		return ""
	for w in past_work:
		var k := String(w).to_lower()
		if PAST_WORK.has(k):
			return String(PAST_WORK[k])
	return ""


# ------------------------------------------------------------------ záznamy

func has_job(n: String) -> bool:
	return jobs.has(n) and String(jobs[n]["track"]) != ""


func record(n: String) -> Dictionary:
	return jobs.get(n, {})


## Zaregistruje postavu (jednou). Dospělá postava s minulou prací v příběhu začíná v tom oboru na nejnižší
## úrovni, ostatní bez práce. Vrací true, když přibyl nový záznam.
func ensure(n: String, past_work, age: int, now: float) -> bool:
	if jobs.has(n) or not _valid_name(n) or jobs.size() >= MAX_JOBS:
		return false
	var r := blank_record()
	var tr := track_from_story(past_work) if age >= 18 else ""
	if tr != "":
		r["track"] = tr
		r["last_track"] = tr
		r["hired_day"] = day_of(now)
	jobs[n] = r
	return true


func forget(n: String) -> void:
	if not jobs.has(n):
		return
	var rid := int(jobs[n]["race"])
	if rid != 0:
		_drop_race(rid)
	jobs.erase(n)


func hire(n: String, track: String, level: int, now: float) -> bool:
	if not jobs.has(n) or not TRACKS.has(track):
		return false
	var r: Dictionary = jobs[n]
	_leave_race(n)
	r["track"] = track
	r["last_track"] = track
	r["level"] = clampi(level, 0, 4)
	r["perf"] = PERF_START
	r["boss"] = 0.0
	r["warnings"] = 0
	r["level_shifts"] = 0
	r["clean_shifts"] = 0
	r["hired_day"] = day_of(now)
	r["checked_day"] = day_of(now)
	r["npc_heat"] = {}
	stats["hired"] += 1
	return true


func _unemploy(n: String) -> void:
	var r: Dictionary = jobs[n]
	_leave_race(n)
	if String(r["track"]) != "":
		r["last_track"] = r["track"]
	r["track"] = ""
	r["warnings"] = 0
	r["level_shifts"] = 0
	r["clean_shifts"] = 0
	r["npc_heat"] = {}


# ------------------------------------------------------------------ rozvrh a blokace

## Pracoval(a) už dnes (nebo v den pozdější – po rewindu se nic neopakuje)?
func worked_today(n: String, day: int) -> bool:
	return jobs.has(n) and int(jobs[n]["last_shift_day"]) >= day


func sick_today(n: String, day: int) -> bool:
	return jobs.has(n) and (jobs[n]["sick"] as Array).has(day)


## Stav příchodu: "" (teď ne), "early" (dá se vyrazit, ještě ne začátek), "on_time", "late".
func arrival(n: String, now: float) -> String:
	if not has_job(n):
		return ""
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	var tr := String(r["track"])
	if not is_workday(tr, day) or worked_today(n, day) or sick_today(n, day):
		return ""
	var m := minute_of(now) - shift_start(tr)
	if m < -EARLY or m > LATE_UNTIL:
		return ""
	if m < 0.0:
		return "early"
	return "late" if m > LATE_FROM else "on_time"


func sick_used(n: String, day: int) -> int:
	var c := 0
	for d in jobs.get(n, {}).get("sick", []):
		if day - int(d) < SICK_WINDOW and int(d) <= day:
			c += 1
	return c


func in_race(n: String) -> bool:
	return jobs.has(n) and int(jobs[n]["race"]) != 0 and races.has(str(jobs[n]["race"]))


## Proč teď nejde kariérní akce ("" = jde). Kódy přeloží block_text.
func command_block(n: String, action_id: String, now: float, grace: float = 0.0) -> String:
	if not CAREER_ACTIONS.has(action_id):
		return "unknown"
	if not jobs.has(n):
		return "no_record"
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	match action_id:
		"job_search":
			if has_job(n):
				return "employed"
			var ls := float(r["last_search"])
			if now - ls < SEARCH_GAP and ls <= now:
				return "search_cooldown"
			return ""
		"quit_job":
			return "" if has_job(n) else "no_job"
	if not has_job(n):
		return "no_job"
	var tr := String(r["track"])
	if not is_workday(tr, day):
		return "not_workday"
	if worked_today(n, day):
		return "already_worked"
	if sick_today(n, day):
		return "sick_today"
	var m := minute_of(now) - shift_start(tr)
	if action_id == "call_in_sick":
		return "" if m <= LATE_UNTIL else "too_late"
	if m < -EARLY:
		return "too_early"
	if m > LATE_UNTIL + clampf(grace, 0.0, BEGIN_GRACE):
		return "too_late"
	if action_id == "work_scheme" and not in_race(n):
		return "no_race"
	return ""


static func block_text(code: String) -> String:
	return {"no_record": "Tahle postava nemá pracovní záznam.", "unknown": "Neznámá pracovní akce.",
		"employed": "Práci už máš.", "search_cooldown": "Na další obvolávání je moc brzo.",
		"no_job": "Nemáš práci.", "not_workday": "Dnes nemáš směnu.", "already_worked": "Dnešní směnu už máš za sebou.",
		"sick_today": "Dnes jsi na nemocenské.", "too_early": "Na směnu je ještě moc brzo.",
		"too_late": "Na dnešní směnu je pozdě.", "no_race": "Teď o nic nesoupeříš – není proti komu intrikovat."}.get(code, "Tohle teď nejde.")


# ------------------------------------------------------------------ směna

## Začátek směny (postava odchází z parcely). Vrací {"ok", "late"}.
func begin_shift(n: String, mode: String, now: float) -> Dictionary:
	var act := "work_shift"
	for k in SHIFT_ACTIONS:
		if String(SHIFT_ACTIONS[k]) == mode:
			act = k
	var b := command_block(n, act, now, BEGIN_GRACE)
	if b != "":
		return {"ok": false, "reason": b, "late": false}
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	r["last_shift_day"] = day
	var late := minute_of(now) - shift_start(String(r["track"])) > LATE_FROM
	return {"ok": true, "reason": "", "late": late}


static func make_rolls(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in 6:
		out.append(rng.randf())
	return out


## Kapacita 0,25..1: deprese (dep 0..1), stres 0..100, energie 0..100, vyhoření. Ne trest – co dnes jde.
static func capacity(dep: float, stress: float, energy: float, strain: float) -> float:
	var c := 1.0 - 0.55 * _fin(dep, 0.0, 1.0, 0.0) - 0.35 * maxf(0.0, (_fin(stress, 0.0, 100.0, 0.0) - 45.0) / 55.0) \
		- 0.25 * maxf(0.0, (40.0 - _fin(energy, 0.0, 100.0, 70.0)) / 40.0) - 0.2 * _fin(strain, 0.0, 1.0, 0.0)
	return clampf(c, 0.25, 1.0)


## Konec směny. inp: {"mode", "fraction" 0..1, "late", "reason" ("" | "panic" | "needs" | "cancel"),
## "dep", "stress", "energy", "honesty", "now"}. rolls: 6 čísel 0..1 (make_rolls).
## Vrací událost pro volajícího (main aplikuje moodlety, stres, mzdu, vztahy, rivalitu).
func resolve_shift(n: String, inp: Dictionary, rolls: Array) -> Dictionary:
	if not has_job(n):
		return {}
	var r: Dictionary = jobs[n]
	var now := _fin(inp.get("now"), T_MIN, T_MAX, 0.0)
	var day := day_of(now)
	var mode := String(inp.get("mode", "normal"))
	if not mode in MODES:
		mode = "normal"
	var rl: Array = []
	for i in 6:
		rl.append(_fin(rolls[i] if i < rolls.size() else 0.5, 0.0, 1.0, 0.5))
	var frac := _fin(inp.get("fraction"), 0.0, 1.0, 1.0)
	var reason := String(inp.get("reason", ""))
	var tr := String(r["track"])
	var care: float = float(TRACKS[tr]["care"])
	var ev := {"kind": "shift", "name": n, "track": tr, "level": int(r["level"]), "mode": mode, "fraction": frac,
		"wage": 0, "perf_delta": 0.0, "boss_delta": 0.0, "stress": 0.0, "event": "", "npc": "", "late": bool(inp.get("late", false)),
		"slack_caught": false, "scheme": "", "victim": "", "victim_learned": false, "warning": false, "fired": false,
		"left_early": frac < 0.95, "reason": reason, "stigma": "", "coworkers": [], "promotion": {}, "strain_high": false}
	var cap := capacity(_fin(inp.get("dep"), 0.0, 1.0, 0.0), _fin(inp.get("stress"), 0.0, 100.0, 0.0),
		_fin(inp.get("energy"), 0.0, 100.0, 70.0), float(r["strain"]))
	var base := float(MODE_PERF[mode])
	var pd := (base * cap if base > 0.0 else base) * frac
	pd += (float(rl[0]) - 0.5) * 3.0
	var bd := float(MODE_BOSS[mode]) * frac
	if bool(ev["late"]):
		pd -= LATE_PERF
		bd -= LATE_BOSS
	if bool(ev["left_early"]):
		var miss := 1.0 - frac
		pd -= EARLY_LEAVE_PERF * miss
		if reason == "panic":
			# Panická ataka v práci: chápavý šéf skoro nic, nechápavý to bere jako selhání (stigma).
			bd -= EARLY_LEAVE_BOSS * miss * (1.0 - care)
			ev["stigma"] = "understood" if care >= 0.5 else "stigma"
		else:
			bd -= EARLY_LEAVE_BOSS * miss
	if mode == "slack" and float(rl[1]) < SLACK_CAUGHT_P:
		ev["slack_caught"] = true
		bd -= 8.0
	# Intrika proti konkurenci v souboji o povýšení.
	var rid := int(r["race"])
	var race: Dictionary = races.get(str(rid), {})
	if mode == "scheme" and not race.is_empty():
		var me_a := String(race["a"]) == n
		var opp := String(race["b"]) if me_a else String(race["a"])
		ev["victim"] = opp
		stats["schemes"] += 1
		if float(rl[4]) < SCHEME_CAUGHT_P:
			ev["scheme"] = "caught"
			stats["schemes_caught"] += 1
			bd -= SCHEME_CAUGHT_BOSS
			_race_add(race, me_a, -SCHEME_CAUGHT_POINTS)
			ev["warning"] = true
			ev["victim_learned"] = not bool(race["npc"])
		else:
			ev["scheme"] = "worked"
			bd += 2.0
			_race_add(race, me_a, SCHEME_GAIN)
			if not bool(race["npc"]) and jobs.has(opp):
				# Strop: skutečná oběť přijde o body souboje i o výkon nejvýš jednou za den (obrana do hloubky –
				# směna je beztak jedna denně).
				var ck := opp + ">" + str(day)
				if not schemed.has(ck):
					if schemed.size() >= MAX_SCHEME_LOG:
						_prune_schemed(day)
					schemed[ck] = 1
					_race_add(race, not me_a, -SCHEME_HIT)
					jobs[opp]["perf"] = clampf(float(jobs[opp]["perf"]) - SCHEME_VICTIM_PERF, 0.0, 100.0)
				ev["victim_learned"] = float(rl[5]) < SCHEME_LEARN_P
			else:
				_race_add(race, not me_a, -SCHEME_HIT)
				var nh: Dictionary = r["npc_heat"]
				if not nh.has(opp) and nh.size() >= MAX_NPC_HEAT:
					_evict_npc_heat(nh)
				nh[opp] = clampf(float(nh.get(opp, 0.0)) + 0.1, 0.0, 1.0)
	# Body do souboje: výkon a šéf ze směny.
	if not race.is_empty():
		var me_a2 := String(race["a"]) == n
		_race_add(race, me_a2, maxf(pd, 0.0) + 0.5 * bd)
	# Událost v práci.
	if float(rl[2]) < EVENT_P and frac > 0.3:
		_work_event(r, ev, cap, float(rl[3]), _fin(inp.get("dep"), 0.0, 1.0, 0.0))
	pd += float(ev.get("event_perf", 0.0))
	bd += float(ev.get("event_boss", 0.0))
	# Zápis.
	r["perf"] = clampf(float(r["perf"]) + pd, 0.0, 100.0)
	r["boss"] = clampf(float(r["boss"]) + bd, -100.0, 100.0)
	r["strain"] = clampf(float(r["strain"]) + float(MODE_STRAIN[mode]) * frac, 0.0, 1.0)
	ev["strain_high"] = float(r["strain"]) >= STRAIN_HIGH
	var st := SHIFT_STRESS * float(TRACKS[tr]["stress"]) * float(MODE_STRESS[mode]) * frac + float(ev.get("event_stress", 0.0))
	if bool(ev["strain_high"]):
		st += 5.0
	ev["stress"] = st
	ev["perf_delta"] = pd
	ev["boss_delta"] = bd
	ev["wage"] = int(round(float(shift_wage(tr, int(r["level"]))) * frac))
	stats["wages"] += int(ev["wage"])
	stats["shifts"] += 1
	if mode == "hard":
		stats["hard"] += 1
	elif mode == "slack":
		stats["slack"] += 1
	r["level_shifts"] = int(r["level_shifts"]) + (1 if frac >= 0.5 else 0)
	if mode == "slack" and bool(ev["slack_caught"]) and float(r["boss"]) < SLACK_WARN_BOSS:
		ev["warning"] = true
	if bool(ev["warning"]):
		r["warnings"] = mini(int(r["warnings"]) + 1, MAX_WARNINGS)
		r["clean_shifts"] = 0
	else:
		r["clean_shifts"] = int(r["clean_shifts"]) + 1
		if int(r["clean_shifts"]) >= CLEAN_SHIFTS_FORGIVE and int(r["warnings"]) > 0:
			r["warnings"] = int(r["warnings"]) - 1
			r["clean_shifts"] = 0
			ev["forgiven"] = true
	# Kolegové – skutečné postavy stejného oboru, které dnes taky pracovaly.
	var cw: Array = []
	var ks: Array = jobs.keys()
	ks.sort()
	for o in ks:
		if o != n and String(jobs[o]["track"]) == tr and int(jobs[o]["last_shift_day"]) == day:
			cw.append(o)
	ev["coworkers"] = cw
	if _should_fire(r):
		ev["fired"] = true
		_fire(n, day)
	else:
		_maybe_open_race(n, now)
	return ev


func _work_event(r: Dictionary, ev: Dictionary, cap: float, roll: float, dep: float) -> void:
	var tr := String(r["track"])
	var cols: Array = COLLEAGUES[tr]
	# Nejméně poctivý kolega (shoda → první v seznamu) – ten si spíš přivlastní zásluhy nebo shodí vinu.
	var shady: Array = cols[0]
	for c in cols:
		if float(c[2]) < float(shady[2]):
			shady = c
	var weights := {
		"praise": (1.0 + float(r["perf"]) / 50.0) * (0.0 if String(ev["mode"]) == "slack" else 1.0) * cap,
		"credit_stolen": 0.8 * (1.0 - float(shady[2])),
		"blamed": 0.6 * (1.0 - float(shady[2])),
		"boss_yelled": 0.5 + (0.8 if float(r["boss"]) < 0.0 else 0.0),
		"support": 0.3 + 1.5 * clampf(dep, 0.0, 1.0),
		"small_talk": 0.8,
		"burnout_moment": 1.0 if float(r["strain"]) >= STRAIN_HIGH else 0.0,
	}
	var order := ["praise", "credit_stolen", "blamed", "boss_yelled", "support", "small_talk", "burnout_moment"]
	var total := 0.0
	for k in order:
		total += float(weights[k])
	if total <= 0.0:
		return
	var pick := clampf(roll, 0.0, 0.999999) * total
	var kind := ""
	for k in order:
		pick -= float(weights[k])
		if pick < 0.0:
			kind = k
			break
	if kind == "":
		kind = "small_talk"
	ev["event"] = kind
	stats["events"] += 1
	match kind:
		"praise":
			ev["event_perf"] = 1.0
			ev["event_boss"] = 3.0
		"credit_stolen":
			ev["npc"] = String(shady[0])
			ev["event_perf"] = -2.0
			ev["event_stress"] = 3.0
			var nh: Dictionary = r["npc_heat"]
			if not nh.has(String(shady[0])) and nh.size() >= MAX_NPC_HEAT:
				_evict_npc_heat(nh)
			nh[String(shady[0])] = clampf(float(nh.get(String(shady[0]), 0.0)) + 0.2, 0.0, 1.0)
		"blamed":
			ev["npc"] = String(shady[0])
			ev["event_boss"] = -3.0
			ev["event_stress"] = 4.0
		"boss_yelled":
			ev["event_stress"] = 5.0
		"support":
			ev["npc"] = String(cols[0][0]) if float(cols[0][2]) >= 0.5 else String(cols[1][0])
		"burnout_moment":
			ev["event_stress"] = 6.0


func _should_fire(r: Dictionary) -> bool:
	return int(r["warnings"]) >= MAX_WARNINGS or (float(r["perf"]) < FIRE_PERF and float(r["boss"]) < FIRE_BOSS)


func _fire(n: String, day: int) -> void:
	var r: Dictionary = jobs[n]
	r["fired_day"] = day
	stats["fired"] += 1
	_unemploy(n)


# ------------------------------------------------------------------ docházka, nemocenská, hledání práce

## Kontrola absence po skončení okna příchodu. Vrací událost {"kind": "absent", …} nebo {}.
func check_absence(n: String, now: float) -> Dictionary:
	if not has_job(n):
		return {}
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	if int(r["checked_day"]) >= day:
		return {}
	var tr := String(r["track"])
	if minute_of(now) - shift_start(tr) <= LATE_UNTIL + BEGIN_GRACE:
		return {}
	r["checked_day"] = day
	if not is_workday(tr, day) or worked_today(n, day) or sick_today(n, day) or int(r["hired_day"]) >= day:
		return {}
	r["warnings"] = mini(int(r["warnings"]) + 1, MAX_WARNINGS)
	r["clean_shifts"] = 0
	r["boss"] = clampf(float(r["boss"]) - ABSENCE_BOSS, -100.0, 100.0)
	r["absences"] = int(r["absences"]) + 1
	stats["absences"] += 1
	var ev := {"kind": "absent", "name": n, "track": tr, "warnings": int(r["warnings"]), "fired": false}
	if _should_fire(r):
		ev["fired"] = true
		_fire(n, day)
	return ev


## Zavolá, že je nemocný(á). mental = důvodem je psychika (jen pro reakci šéfa; nikam se neukládá).
## Vrací {"ok", "excused", "stigma": "" | "understood" | "stigma", "reason"}.
func call_in_sick(n: String, mental: bool, now: float) -> Dictionary:
	var b := command_block(n, "call_in_sick", now)
	if b != "":
		return {"ok": false, "reason": b, "excused": false, "stigma": ""}
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	var care: float = float(TRACKS[String(r["track"])]["care"])
	var excused := sick_used(n, day) < SICK_BUDGET
	var lg: Array = r["sick"]
	lg.append(day)
	while lg.size() > MAX_SICK_LOG:
		lg.pop_front()
	var bd := -1.0 if excused else -6.0
	var stig := ""
	if mental:
		stig = "understood" if care >= 0.5 else "stigma"
		if stig == "stigma":
			bd -= 2.0
	r["boss"] = clampf(float(r["boss"]) + bd, -100.0, 100.0)
	stats["sick"] += 1
	return {"ok": true, "reason": "", "excused": excused, "stigma": stig, "boss_delta": bd}


## Obvolávání inzerátů. roll 0..1, dep 0..1 (deprese ubírá jiskru v pohovoru), pref = preferovaný obor.
## Vrací {"ok", "hired", "track", "level", "reason"}.
func job_search(n: String, roll: float, dep: float, pref: String, now: float) -> Dictionary:
	var b := command_block(n, "job_search", now)
	if b != "":
		return {"ok": false, "hired": false, "reason": b, "track": "", "level": 0}
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	r["last_search"] = now
	stats["searches"] += 1
	var p := SEARCH_BASE + (0.1 if String(r["last_track"]) != "" else 0.0) - 0.1 * clampf(dep, 0.0, 1.0)
	var fresh_fire := day - int(r["fired_day"]) < SEARCH_FIRED_DAYS and int(r["fired_day"]) <= day
	if fresh_fire:
		p -= 0.18
	p = clampf(p, 0.05, 0.8)
	if _fin(roll, 0.0, 1.0, 1.0) >= p:
		return {"ok": true, "hired": false, "reason": "", "track": "", "level": 0, "p": p}
	var tr := pref if TRACKS.has(pref) else (String(r["last_track"]) if TRACKS.has(String(r["last_track"])) else "")
	if tr == "":
		tr = String(TRACK_IDS[int(det(n + "|track") * TRACK_IDS.size()) % TRACK_IDS.size()])
	var lvl := 0
	if not fresh_fire and String(r["last_track"]) == tr:
		lvl = maxi(0, int(r["level"]) - 1)
	hire(n, tr, lvl, now)
	return {"ok": true, "hired": true, "reason": "", "track": tr, "level": lvl, "p": p}


func quit(n: String) -> Dictionary:
	if not has_job(n):
		return {"ok": false, "reason": "no_job"}
	var strain := float(jobs[n]["strain"])
	_unemploy(n)
	stats["quits"] += 1
	return {"ok": true, "reason": "", "relief": strain >= STRAIN_HIGH}


# ------------------------------------------------------------------ souboj o povýšení

func _race_add(race: Dictionary, side_a: bool, amount: float) -> void:
	var k := "pa" if side_a else "pb"
	race[k] = clampf(float(race[k]) + amount, -1000.0, 1000.0)


func _maybe_open_race(n: String, now: float) -> void:
	var r: Dictionary = jobs[n]
	var lvl := int(r["level"])
	if lvl >= 4 or int(r["race"]) != 0 or float(r["perf"]) < PROMO_PERF or int(r["warnings"]) > 1:
		return
	if int(r["level_shifts"]) < int(PROMO_SHIFTS[lvl]) or races.size() >= MAX_RACES:
		return
	var tr := String(r["track"])
	# Soupeř: skutečná postava stejného oboru a úrovně bez souboje (nejlepší výkon, shoda → abecedně),
	# jinak NPC kolega s největší ambicí.
	var best := ""
	var best_p := -1.0
	var ks: Array = jobs.keys()
	ks.sort()
	for o in ks:
		if o == n:
			continue
		var orc: Dictionary = jobs[o]
		if String(orc["track"]) != tr or int(orc["level"]) != lvl or int(orc["race"]) != 0:
			continue
		if float(orc["perf"]) > best_p:
			best_p = float(orc["perf"])
			best = o
	var npc := best == ""
	if npc:
		var cols: Array = COLLEAGUES[tr]
		var top: Array = cols[0]
		for c in cols:
			if float(c[1]) > float(top[1]):
				top = c
		best = String(top[0])
	var rid := next_race
	next_race += 1
	races[str(rid)] = {"a": n, "b": best, "npc": npc, "pa": 0.0, "pb": 0.0, "until": day_of(now) + RACE_DAYS,
		"track": tr, "level": lvl}
	r["race"] = rid
	if not npc:
		jobs[best]["race"] = rid
	stats["races"] += 1


func race_of(n: String) -> Dictionary:
	if not in_race(n):
		return {}
	var race: Dictionary = races[str(jobs[n]["race"])]
	var me_a := String(race["a"]) == n
	return {"vs": String(race["b"]) if me_a else String(race["a"]), "npc": bool(race["npc"]) and me_a,
		"until": int(race["until"]), "ahead": float(race["pa"] if me_a else race["pb"]) >= float(race["pb"] if me_a else race["pa"])}


func _leave_race(n: String) -> void:
	if not jobs.has(n):
		return
	var rid := int(jobs[n]["race"])
	if rid != 0:
		_drop_race(rid)


func _drop_race(rid: int) -> void:
	var race: Dictionary = races.get(str(rid), {})
	races.erase(str(rid))
	for k in ["a", "b"]:
		var who := String(race.get(k, ""))
		if jobs.has(who) and int(jobs[who]["race"]) == rid:
			jobs[who]["race"] = 0


## Jednou za den (a při každém kroku levně): uzavře souboje po termínu, vyhoření polevuje ve dny bez
## směny. Vrací seznam událostí {"kind": "race", "winner", "loser", "npc_winner"/"npc_loser", …}.
func day_tick(now: float) -> Array:
	var out: Array = []
	var day := day_of(now)
	var ids: Array = races.keys()
	ids.sort_custom(func(x, y): return int(x) < int(y))
	for k in ids:
		var race: Dictionary = races[k]
		if day <= int(race["until"]):
			continue
		out.append(_resolve_race(int(k), race, now))
	return out


## Den bez směny (volá se při přechodu dne pro každou postavu): vyhoření polevuje.
func rest_day(n: String, day: int) -> void:
	if not jobs.has(n):
		return
	var r: Dictionary = jobs[n]
	if int(r["last_shift_day"]) < day - 1 or not has_job(n):
		r["strain"] = clampf(float(r["strain"]) - STRAIN_DAY_OFF, 0.0, 1.0)


func _resolve_race(rid: int, race: Dictionary, now: float) -> Dictionary:
	var a := String(race["a"])
	var b := String(race["b"])
	var npc := bool(race["npc"])
	var pa := float(race["pa"])
	var pb := float(race["pb"])
	var ra: Dictionary = jobs.get(a, {})
	var sa := pa + (float(ra.get("perf", 0.0)) / 10.0 + float(ra.get("boss", 0.0)) / 25.0 if not ra.is_empty() else -1000.0)
	var sb := 0.0
	if npc:
		# NPC kolega: body podle ambice a deterministického „štěstí“ souboje.
		var amb := 0.5
		for c in COLLEAGUES.get(String(race["track"]), []):
			if String(c[0]) == b:
				amb = float(c[1])
		sb = pb + float(RACE_DAYS) * (1.2 + 1.6 * amb) * (0.75 + 0.5 * det("%d|%s" % [rid, b])) + (60.0 + 20.0 * amb) / 10.0
	else:
		var rb: Dictionary = jobs.get(b, {})
		sb = pb + (float(rb.get("perf", 0.0)) / 10.0 + float(rb.get("boss", 0.0)) / 25.0 if not rb.is_empty() else -1000.0)
	_drop_race(rid)
	var a_wins := sa > sb or (sa == sb and a < b)
	var winner := a if a_wins else b
	var loser := b if a_wins else a
	var ev := {"kind": "race", "winner": winner, "loser": loser, "npc": npc, "npc_winner": npc and not a_wins,
		"npc_loser": npc and a_wins, "track": String(race["track"]), "level": int(race["level"]), "score_a": sa, "score_b": sb}
	if jobs.has(winner) and String(jobs[winner]["track"]) == String(race["track"]):
		_promote(winner)
		ev["new_level"] = int(jobs[winner]["level"])
	if jobs.has(loser):
		var lr: Dictionary = jobs[loser]
		lr["level_shifts"] = int(float(lr["level_shifts"]) / 2.0)
		if npc and not a_wins:
			var nh: Dictionary = lr["npc_heat"]
			if not nh.has(winner) and nh.size() >= MAX_NPC_HEAT:
				_evict_npc_heat(nh)
			nh[winner] = clampf(float(nh.get(winner, 0.0)) + RACE_LOST_HEAT + 0.1, 0.0, 1.0)
	return ev


func _promote(n: String) -> void:
	var r: Dictionary = jobs[n]
	r["level"] = mini(int(r["level"]) + 1, 4)
	r["perf"] = PROMO_PERF_RESET
	r["level_shifts"] = 0
	r["promotions"] = int(r["promotions"]) + 1
	stats["promotions"] += 1


func _evict_npc_heat(nh: Dictionary) -> void:
	var worst := ""
	var wv := INF
	var ks: Array = nh.keys()
	ks.sort()
	for k in ks:
		if float(nh[k]) < wv:
			wv = float(nh[k])
			worst = k
	if worst != "":
		nh.erase(worst)


func _prune_schemed(day: int) -> void:
	for k in schemed.keys():
		var parts: PackedStringArray = String(k).split(">")
		if parts.size() != 2 or not parts[1].is_valid_int() or int(parts[1]) < day - 1 or int(parts[1]) > day:
			schemed.erase(k)
	if schemed.size() >= MAX_SCHEME_LOG:
		schemed.clear()


# ------------------------------------------------------------------ AI

## Potřebuje AI dnes nové rozhodnutí (je v okně příchodu a dnes ještě nerozhodla)? Volající podle toho
## teprve počítá vstupy včetně hodu z rng postavy (jinak se rng zbytečně nečerpá).
func ai_pending(n: String, now: float) -> bool:
	return has_job(n) and arrival(n, now) != "" and int(jobs[n]["ai_day"]) != day_of(now)


## Rozhodnutí AI na dnešek (jednou denně, uloží se – po načtení hry stejné). inp: {"dep", "barrier" 0..1
## (bariéra iniciace z deprese), "stress", "energy", "honesty", "lazy" (rys Lenoch), "panic_recent",
## "roll"}. Vrací id akce nebo "" (nic / nedokázal(a) se zvednout).
func ai_choice(n: String, inp: Dictionary, now: float) -> String:
	if not jobs.has(n):
		return ""
	var r: Dictionary = jobs[n]
	var day := day_of(now)
	if not has_job(n):
		return "job_search" if command_block(n, "job_search", now) == "" and float(r["last_search"]) <= now - DAY else ""
	var arr := arrival(n, now)
	if arr == "" or arr == "early" and minute_of(now) - shift_start(String(r["track"])) < -30.0:
		return ""
	if int(r["ai_day"]) == day:
		var pick := String(r["ai_pick"])
		return pick if command_block(n, pick, now) == "" else ""
	var dep := _fin(inp.get("dep"), 0.0, 1.0, 0.0)
	var barrier := _fin(inp.get("barrier"), 0.0, 1.0, 0.0)
	var stress := _fin(inp.get("stress"), 0.0, 100.0, 0.0)
	var energy := _fin(inp.get("energy"), 0.0, 100.0, 70.0)
	var hon := _fin(inp.get("honesty"), 0.0, 1.0, 0.5)
	var roll := _fin(inp.get("roll"), 0.0, 1.0, 0.5)
	var pick := "work_shift"
	var sick_left := sick_used(n, day) < SICK_BUDGET
	if (dep > 0.6 or bool(inp.get("panic_recent", false)) or energy < 12.0 or stress > 85.0) and sick_left:
		pick = "call_in_sick"
	elif barrier > 0.7 and roll < 0.25:
		# Bariéra iniciace: když zbývá omluvená nemocenská, postava aspoň zavolá (symptom není kázeňský přestupek).
		# Teprve s vyčerpanou nemocenskou se nezvedne ani nezavolá – absence pak má reálné následky (audit #4).
		pick = "call_in_sick" if sick_left else ""
	elif in_race(n) and hon < 0.35 and roll < 0.6:
		pick = "work_scheme"
	elif bool(inp.get("lazy", false)) or energy < 30.0 or float(r["strain"]) > 0.7:
		pick = "work_slack"
	elif energy > 55.0 and stress < 55.0 and float(r["strain"]) < STRAIN_HIGH and (in_race(n) or roll < 0.35):
		pick = "work_hard"
	r["ai_day"] = day
	r["ai_pick"] = pick
	return pick if pick == "" or command_block(n, pick, now) == "" else ""


# ------------------------------------------------------------------ pohledy

## Soukromé věty pro vlastníka (HUD; bez čísel).
func private_lines(n: String, grammar_col: int, now: float) -> PackedStringArray:
	var out := PackedStringArray()
	if not jobs.has(n):
		return out
	var r: Dictionary = jobs[n]
	if not has_job(n):
		var day := day_of(now)
		var fresh := day - int(r["fired_day"]) < SEARCH_FIRED_DAYS and int(r["fired_day"]) <= day
		out.append("Práce: bez práce" + (" (čerstvě po vyhazovu)" if fresh else ""))
		return out
	var tr := String(r["track"])
	var perf := float(r["perf"])
	var boss := float(r["boss"])
	var perf_t := "výborný" if perf >= 75.0 else ("dobrý" if perf >= 55.0 else ("průměrný" if perf >= 35.0 else "slabý"))
	var boss_t := "šéf tě má rád" if boss >= 40.0 else ("šéf je spokojený" if boss >= 10.0 else ("šéf je neutrální" if boss > -15.0 else ("šéf je naštvaný" if boss > -45.0 else "šéf tě nesnáší")))
	var w := int(r["warnings"])
	var wt := "" if w == 0 else (", jedna výtka" if w == 1 else ", dvě výtky – další znamená vyhazov")
	out.append("Práce: %s (%s) – výkon %s, %s%s" % [job_title(tr, int(r["level"]), grammar_col), String(TRACKS[tr]["name"]), perf_t, boss_t, wt])
	var rc := race_of(n)
	if not rc.is_empty():
		out.append("Povýšení: souboj o místo (%s) – %s" % [String(rc["vs"]).split(" ")[0], "vedeš" if bool(rc["ahead"]) else "ztrácíš"])
	if float(r["strain"]) >= STRAIN_HIGH:
		out.append("Práce: jsi na hraně vyhoření")
	var nh: Dictionary = r["npc_heat"]
	var worst := ""
	var wv := 0.29
	var ks: Array = nh.keys()
	ks.sort()
	for k in ks:
		if float(nh[k]) > wv:
			wv = float(nh[k])
			worst = k
	if worst != "":
		out.append("V práci tě štve: %s" % worst.split(" ")[0])
	return out


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {"version": VERSION, "jobs": jobs.duplicate(true), "races": races.duplicate(true), "next_race": next_race,
		"schemed": schemed.duplicate(true), "stats": stats.duplicate(true)}


static func _num(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func _intlike(v) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and floorf(v) == v)


static func _valid_record(r) -> bool:
	if typeof(r) != TYPE_DICTIONARY or r.size() != RECORD_KEYS.size():
		return false
	for k in r.keys():
		if typeof(k) != TYPE_STRING or not RECORD_KEYS.has(k):
			return false
	if typeof(r["track"]) != TYPE_STRING or (String(r["track"]) != "" and not TRACKS.has(String(r["track"]))):
		return false
	if typeof(r["last_track"]) != TYPE_STRING or (String(r["last_track"]) != "" and not TRACKS.has(String(r["last_track"]))):
		return false
	if typeof(r["ai_pick"]) != TYPE_STRING or not (String(r["ai_pick"]) == "" or CAREER_ACTIONS.has(String(r["ai_pick"]))):
		return false
	var ints := {"level": [0, 4], "warnings": [0, MAX_WARNINGS], "level_shifts": [0, 100000], "clean_shifts": [0, 100000],
		"last_shift_day": [DAY_MIN, DAY_MAX], "checked_day": [DAY_MIN, DAY_MAX], "hired_day": [DAY_MIN, DAY_MAX],
		"fired_day": [DAY_MIN, DAY_MAX], "race": [0, 1000000000], "absences": [0, 1000000], "promotions": [0, 1000],
		"ai_day": [DAY_MIN, DAY_MAX]}
	for k in ints:
		if not _intlike(r[k]) or int(r[k]) < int(ints[k][0]) or int(r[k]) > int(ints[k][1]):
			return false
	var nums := {"perf": [0.0, 100.0], "boss": [-100.0, 100.0], "strain": [0.0, 1.0], "last_search": [T_MIN, T_MAX]}
	for k in nums:
		if not _num(r[k]) or float(r[k]) < float(nums[k][0]) or float(r[k]) > float(nums[k][1]):
			return false
	if typeof(r["sick"]) != TYPE_ARRAY or r["sick"].size() > MAX_SICK_LOG:
		return false
	for d in r["sick"]:
		if not _intlike(d) or int(d) < DAY_MIN or int(d) > DAY_MAX:
			return false
	if typeof(r["npc_heat"]) != TYPE_DICTIONARY or r["npc_heat"].size() > MAX_NPC_HEAT:
		return false
	for k in r["npc_heat"].keys():
		if not _valid_name(k) or not _num(r["npc_heat"][k]) or float(r["npc_heat"][k]) < 0.0 or float(r["npc_heat"][k]) > 1.0:
			return false
	return true


## Striktní kontrola tvaru snapshotu (testy, nástroje, server): přesné klíče, typy, rozsahy, limity a
## vzájemná konzistence soubojů. Hra ukládá jen to, co projde; from_dict je tolerantní.
static func validate_snapshot(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var top := ["version", "jobs", "races", "next_race", "schemed", "stats"]
	if d.size() != top.size():
		return false
	for k in d.keys():
		if typeof(k) != TYPE_STRING or not top.has(k):
			return false
	if not _intlike(d["version"]) or int(d["version"]) != VERSION:
		return false
	if not _intlike(d["next_race"]) or int(d["next_race"]) < 1 or int(d["next_race"]) > 1000000000:
		return false
	if typeof(d["jobs"]) != TYPE_DICTIONARY or d["jobs"].size() > MAX_JOBS:
		return false
	for n in d["jobs"].keys():
		if not _valid_name(n) or not _valid_record(d["jobs"][n]):
			return false
	if typeof(d["races"]) != TYPE_DICTIONARY or d["races"].size() > MAX_RACES:
		return false
	for k in d["races"].keys():
		if typeof(k) != TYPE_STRING or not String(k).is_valid_int() or int(k) < 1 or int(k) >= int(d["next_race"]):
			return false
		var rc = d["races"][k]
		if typeof(rc) != TYPE_DICTIONARY or rc.size() != RACE_KEYS.size():
			return false
		for f in rc.keys():
			if typeof(f) != TYPE_STRING or not RACE_KEYS.has(f):
				return false
		if not _valid_name(rc["a"]) or not _valid_name(rc["b"]) or rc["a"] == rc["b"] or typeof(rc["npc"]) != TYPE_BOOL:
			return false
		if not _num(rc["pa"]) or not _num(rc["pb"]) or absf(float(rc["pa"])) > 1000.0 or absf(float(rc["pb"])) > 1000.0:
			return false
		if not _intlike(rc["until"]) or int(rc["until"]) < DAY_MIN or int(rc["until"]) > DAY_MAX:
			return false
		if typeof(rc["track"]) != TYPE_STRING or not TRACKS.has(String(rc["track"])) or not _intlike(rc["level"]) \
				or int(rc["level"]) < 0 or int(rc["level"]) > 3:
			return false
		# Konzistence: účastníci jsou zaměstnaní v tom oboru a odkazují na tento souboj.
		var ja = d["jobs"].get(rc["a"])
		if ja == null or int(ja["race"]) != int(k):
			return false
		if not bool(rc["npc"]):
			var jb = d["jobs"].get(rc["b"])
			if jb == null or int(jb["race"]) != int(k):
				return false
	for n in d["jobs"].keys():
		var rid := int(d["jobs"][n]["race"])
		if rid != 0 and not d["races"].has(str(rid)):
			return false
	if typeof(d["schemed"]) != TYPE_DICTIONARY or d["schemed"].size() > MAX_SCHEME_LOG:
		return false
	for k in d["schemed"].keys():
		if typeof(k) != TYPE_STRING:
			return false
		var p2: PackedStringArray = String(k).split(">")
		if p2.size() != 2 or not _valid_name(p2[0]) or not p2[1].is_valid_int() or not _intlike(d["schemed"][k]):
			return false
	if typeof(d["stats"]) != TYPE_DICTIONARY:
		return false
	for k in d["stats"].keys():
		if typeof(k) != TYPE_STRING or not STAT_KEYS.has(k) or not _num(d["stats"][k]) or float(d["stats"][k]) < 0.0:
			return false
	return true


## Obnova z uložené hry. Starý save bez sekce = nikdo nemá záznam (postavy se zaregistrují znovu podle
## příběhu). Budoucí verze se zahodí celá. Jinak tolerantně: vadné záznamy se zahodí, souboje bez
## platných účastníků se zruší.
func from_dict(d) -> void:
	jobs = {}
	races = {}
	next_race = 1
	schemed = {}
	load_note = ""
	reset_stats()
	if typeof(d) != TYPE_DICTIONARY:
		load_note = "type"
		return
	if d.is_empty():
		return
	var ver := int(_fin(d.get("version"), -1.0, 1.0e6, -1.0))
	if ver > VERSION:
		load_note = "future_version"
		return
	if ver < 1:
		load_note = "legacy_unversioned"
		return
	var js = d.get("jobs", {})
	if typeof(js) == TYPE_DICTIONARY:
		var ks: Array = js.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for n in ks:
			if jobs.size() >= MAX_JOBS or not _valid_name(n) or typeof(js[n]) != TYPE_DICTIONARY:
				continue
			jobs[n] = _sanitize_record(js[n])
	next_race = _int(d.get("next_race"), 1, 1000000000, 1)
	var rs = d.get("races", {})
	if typeof(rs) == TYPE_DICTIONARY:
		var rk: Array = rs.keys()
		rk.sort_custom(func(x, y): return str(x) < str(y))
		for k in rk:
			if races.size() >= MAX_RACES or typeof(k) != TYPE_STRING or not String(k).is_valid_int():
				continue
			var rc = rs[k]
			if typeof(rc) != TYPE_DICTIONARY:
				continue
			var a = rc.get("a")
			var b = rc.get("b")
			var npc = rc.get("npc")
			var tr = rc.get("track")
			if not _valid_name(a) or not _valid_name(b) or a == b or typeof(npc) != TYPE_BOOL or typeof(tr) != TYPE_STRING \
					or not TRACKS.has(String(tr)) or not jobs.has(a) or int(jobs[a]["race"]) != int(k):
				continue
			if not bool(npc) and (not jobs.has(b) or int(jobs[b]["race"]) != int(k)):
				continue
			races[str(int(k))] = {"a": String(a), "b": String(b), "npc": bool(npc), "pa": _fin(rc.get("pa"), -1000.0, 1000.0, 0.0),
				"pb": _fin(rc.get("pb"), -1000.0, 1000.0, 0.0), "until": _int(rc.get("until"), DAY_MIN, DAY_MAX, 0),
				"track": String(tr), "level": _int(rc.get("level"), 0, 3, 0)}
			next_race = maxi(next_race, int(k) + 1)
	# Odkazy na neexistující souboje zrušit.
	for n in jobs.keys():
		if int(jobs[n]["race"]) != 0 and not races.has(str(jobs[n]["race"])):
			jobs[n]["race"] = 0
	var sc = d.get("schemed", {})
	if typeof(sc) == TYPE_DICTIONARY:
		for k in sc.keys():
			if schemed.size() >= MAX_SCHEME_LOG or typeof(k) != TYPE_STRING:
				continue
			var p2: PackedStringArray = String(k).split(">")
			if p2.size() == 2 and _valid_name(p2[0]) and p2[1].is_valid_int():
				schemed[k] = 1
	var st = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in STAT_KEYS:
			if st.has(k):
				stats[k] = int(_fin(st[k], 0.0, 1.0e12, 0.0))


static func _sanitize_record(s: Dictionary) -> Dictionary:
	var r := blank_record()
	var tr = s.get("track", "")
	r["track"] = String(tr) if typeof(tr) == TYPE_STRING and TRACKS.has(String(tr)) else ""
	var lt = s.get("last_track", "")
	r["last_track"] = String(lt) if typeof(lt) == TYPE_STRING and TRACKS.has(String(lt)) else r["track"]
	r["level"] = _int(s.get("level"), 0, 4, 0)
	r["perf"] = _fin(s.get("perf"), 0.0, 100.0, PERF_START)
	r["boss"] = _fin(s.get("boss"), -100.0, 100.0, 0.0)
	r["warnings"] = _int(s.get("warnings"), 0, MAX_WARNINGS, 0)
	r["level_shifts"] = _int(s.get("level_shifts"), 0, 100000, 0)
	r["clean_shifts"] = _int(s.get("clean_shifts"), 0, 100000, 0)
	for k in ["last_shift_day", "checked_day", "hired_day", "fired_day", "ai_day"]:
		r[k] = _int(s.get(k), DAY_MIN, DAY_MAX, DAY_MIN)
	var sk = s.get("sick", [])
	if typeof(sk) == TYPE_ARRAY:
		for x in sk:
			if (r["sick"] as Array).size() < MAX_SICK_LOG and _intlike(x):
				(r["sick"] as Array).append(clampi(int(x), DAY_MIN, DAY_MAX))
	r["strain"] = _fin(s.get("strain"), 0.0, 1.0, 0.0)
	r["last_search"] = _fin(s.get("last_search"), T_MIN, T_MAX, -1.0e9)
	r["race"] = _int(s.get("race"), 0, 1000000000, 0)
	var nh = s.get("npc_heat", {})
	if typeof(nh) == TYPE_DICTIONARY:
		var ks: Array = nh.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for k in ks:
			if (r["npc_heat"] as Dictionary).size() < MAX_NPC_HEAT and _valid_name(k):
				r["npc_heat"][k] = _fin(nh[k], 0.0, 1.0, 0.0)
	r["absences"] = _int(s.get("absences"), 0, 1000000, 0)
	r["promotions"] = _int(s.get("promotions"), 0, 1000, 0)
	var ap = s.get("ai_pick", "")
	r["ai_pick"] = String(ap) if typeof(ap) == TYPE_STRING and CAREER_ACTIONS.has(String(ap)) else ""
	if r["track"] == "":
		r["race"] = 0
	return r
