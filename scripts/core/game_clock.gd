extends Node
## Globální herní čas (autoload „GameClock“).
## Simulace běží v herních minutách. Všechny systémy poslouchají `time_advanced`,
## takže čas lze zrychlit, pozastavit i ručně krokovat (testy, později autoritativní server).

signal time_advanced(delta_minutes: float)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal speed_changed(index: int)

const SPEEDS: Array[float] = [0.0, 1.0, 3.0, 12.0, 60.0]
const SPEED_NAMES: Array[String] = ["Pauza", "Normální", "Rychle", "Velmi rychle", "Ultra"]
const WEEKDAYS: Array[String] = ["Pondělí", "Úterý", "Středa", "Čtvrtek", "Pátek", "Sobota", "Neděle"]
const MINUTES_PER_DAY := 1440.0
## Maximální délka jednoho simulačního kroku (stabilita při vysoké rychlosti).
const MAX_STEP := 2.0

## Kolik reálných sekund trvá jedna herní minuta při rychlosti „Normální“.
var real_seconds_per_game_minute := 1.0
var speed_index := 1
var total_minutes := 8.0 * 60.0  # Den 1, 8:00
## false = čas se neposouvá sám (headless testy, klient v multiplayeru).
var running := true

var _last_hour := -1
var _last_day := -1


func _ready() -> void:
	_last_hour = get_hour()
	_last_day = get_day()


func _process(delta: float) -> void:
	if not running:
		return
	advance(delta / real_seconds_per_game_minute * SPEEDS[speed_index])


## Posune čas o daný počet herních minut (rozdělí na menší kroky).
func advance(minutes: float) -> void:
	var remaining := minutes
	while remaining > 0.0:
		var step := minf(remaining, MAX_STEP)
		remaining -= step
		total_minutes += step
		time_advanced.emit(step)
		var h := get_hour()
		if h != _last_hour:
			_last_hour = h
			hour_changed.emit(h)
		var d := get_day()
		if d != _last_day:
			_last_day = d
			day_changed.emit(d)


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	speed_changed.emit(speed_index)


func toggle_pause() -> void:
	set_speed(1 if speed_index == 0 else 0)


func get_day() -> int:
	return int(total_minutes / MINUTES_PER_DAY) + 1


func get_hour() -> int:
	return int(fmod(total_minutes, MINUTES_PER_DAY) / 60.0)


func get_minute() -> int:
	return int(fmod(total_minutes, 60.0))


## 0.0 = půlnoc, 0.5 = poledne.
func day_fraction() -> float:
	return fmod(total_minutes, MINUTES_PER_DAY) / MINUTES_PER_DAY


func weekday_name() -> String:
	return WEEKDAYS[(get_day() - 1) % 7]


func phase_name() -> String:
	var h := get_hour()
	if h < 5:
		return "Noc"
	if h < 8:
		return "Svítání"
	if h < 12:
		return "Dopoledne"
	if h < 17:
		return "Odpoledne"
	if h < 21:
		return "Večer"
	return "Noc"


func is_night() -> bool:
	var h := get_hour()
	return h >= 22 or h < 6


func time_string() -> String:
	return "%s, den %d  %02d:%02d" % [weekday_name(), get_day(), get_hour(), get_minute()]
