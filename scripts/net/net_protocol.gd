extends RefCounted
## Síťový protokol – konstanty a čisté (testovatelné) validační funkce.
## Server NIKDY nevěří datům od klienta: každý vstup projde přes funkce tady.

## 2 = duševní stav v soukromém detailu, nové akce (copingy, panická ataka, pomoc).
## 3 = vlastní postava (CharacterData) v hello, vzhled ve spawn datech místo hashe jména.
const VERSION := 3
const DEFAULT_PORT := 24565
const MAX_CLIENTS := 8
const MAX_NAME_LEN := 20
const MAX_CHAT_LEN := 200
const MAX_ID_LEN := 48
## Nejvyšší počet postav vytvořených hráči (vlastní postavy z editoru) na serveru.
const MAX_PLAYER_CHARACTERS := 8
## Do kolika sekund musí klient poslat hello, jinak ho server odpojí.
const HELLO_TIMEOUT := 5.0
## Token bucket: [kapacita, doplnění za sekundu]
const CHAT_BUCKET := [4.0, 0.5]
const COMMAND_BUCKET := [6.0, 3.0]
const VOTE_BUCKET := [4.0, 2.0]
const DEFAULT_PLAYER_NAME := "Hráč"
## Nouzová pauza: každý hráč může zastavit čas na pár sekund, pak má cooldown.
const EMERGENCY_PAUSE := 30.0
const EMERGENCY_COOLDOWN := 180.0


## Odstraní řídicí a neviditelné znaky (vč. bidi přepínačů, které umí převrátit text),
## znaky BBCode hranatých závorek nahradí, slije mezery a ořízne délku.
static func clean_text(raw, max_len: int) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var s: String = raw
	if s.length() > max_len * 4:
		s = s.substr(0, max_len * 4)
	var out := ""
	var last_space := false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0):
			c = 32
		elif (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			continue
		elif c == 0x5B:  # [
			c = 0x28  # (
		elif c == 0x5D:  # ]
			c = 0x29  # )
		if c == 32:
			if last_space:
				continue
			last_space = true
		else:
			last_space = false
		out += String.chr(c)
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len).strip_edges()
	return out


static func sanitize_name(raw) -> String:
	var s := clean_text(raw, MAX_NAME_LEN)
	return s if s != "" else DEFAULT_PLAYER_NAME


static func sanitize_chat(raw) -> String:
	return clean_text(raw, MAX_CHAT_LEN)


## Jméno unikátní mezi `taken` (porovnání bez ohledu na velikost písmen).
static func unique_name(wanted: String, taken: Array) -> String:
	var lower: Array = []
	for t in taken:
		lower.append(String(t).to_lower())
	if not lower.has(wanted.to_lower()):
		return wanted
	var n := 2
	while true:
		var suffix := " %d" % n
		var base := wanted.substr(0, MAX_NAME_LEN - suffix.length())
		var cand := base + suffix
		if not lower.has(cand.to_lower()):
			return cand
		n += 1
	return wanted


## Krátký identifikátor (id akce, jméno uzlu) – jen typ String a rozumná délka.
static func valid_id(raw) -> bool:
	var t := typeof(raw)
	if t != TYPE_STRING and t != TYPE_STRING_NAME:
		return false
	var n := String(raw).length()
	return n > 0 and n <= MAX_ID_LEN


static func valid_int(raw, lo: int, hi: int) -> bool:
	return typeof(raw) == TYPE_INT and int(raw) >= lo and int(raw) <= hi


## Efektivní rychlost času = dolní medián hlasů: rozhoduje většina, při remíze
## vyhrává pomalejší volba. Jeden troll tak hru natrvalo nezastaví (na krizové
## chvíle je nouzová pauza). Bez hlasů: `fallback`.
static func effective_speed(votes: Array, fallback: int) -> int:
	if votes.is_empty():
		return fallback
	var s: Array = []
	for v in votes:
		s.append(int(v))
	s.sort()
	return s[(s.size() - 1) / 2]


## Jednoduchý token bucket (rate limit) – `now` v sekundách.
class RateLimiter:
	var capacity: float
	var refill: float
	var tokens: float
	var last: float

	func _init(p_capacity: float, p_refill: float, now: float) -> void:
		capacity = p_capacity
		refill = p_refill
		tokens = p_capacity
		last = now

	func allow(now: float) -> bool:
		tokens = minf(capacity, tokens + maxf(now - last, 0.0) * refill)
		last = now
		if tokens >= 1.0:
			tokens -= 1.0
			return true
		return false
