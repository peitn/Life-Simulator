extends "res://tests/test_base.gd"
## Jednotkové testy síťového protokolu: sanitizace, unikátní jména, validace, rate limit, rychlost.

const P := preload("res://scripts/net/net_protocol.gd")


func _ready() -> void:
	section("Sanitizace textu")
	check(P.sanitize_chat("  Ahoj   světe  ") == "Ahoj světe", "slije mezery a ořízne okraje")
	var ctrl := "a" + String.chr(10) + "b" + String.chr(9) + "c" + String.chr(7) + "d"
	check(P.sanitize_chat(ctrl) == "a b c d", "řídicí znaky → mezera", P.sanitize_chat(ctrl))
	check(P.sanitize_chat("[b]tučně[/b]") == "(b)tučně(/b)", "BBCode závorky neutralizované", P.sanitize_chat("[b]tučně[/b]"))
	check(P.sanitize_chat("zlo" + String.chr(0x202E) + "olz") == "zloolz", "bidi přepínač odstraněn")
	check(P.sanitize_chat("x" + String.chr(0x200B) + "y") == "xy", "neviditelná mezera odstraněna")
	check(P.sanitize_chat("a".repeat(500)).length() == P.MAX_CHAT_LEN, "délka chatu omezená na %d" % P.MAX_CHAT_LEN)
	check(P.sanitize_chat(12345) == "", "ne-String → prázdné")
	check(P.sanitize_chat(["x"]) == "", "pole → prázdné")
	check(P.sanitize_chat("Kurva, to je den.") == "Kurva, to je den.", "sprostá slova se necenzurují (dospělý tón)")
	check(P.sanitize_name("") == P.DEFAULT_PLAYER_NAME, "prázdné jméno → výchozí")
	check(P.sanitize_name("   " + String.chr(10) + " ") == P.DEFAULT_PLAYER_NAME, "jen bílé znaky → výchozí")
	check(P.sanitize_name("Velmi dlouhé jméno hráče, které nikdo nečte").length() <= P.MAX_NAME_LEN, "délka jména omezená")
	check(P.sanitize_name(null) == P.DEFAULT_PLAYER_NAME, "null jméno → výchozí")

	section("Unikátní jména")
	check(P.unique_name("Hráč", []) == "Hráč", "volné jméno zůstane")
	check(P.unique_name("Hráč", ["Hráč"]) == "Hráč 2", "duplicita → přípona 2")
	check(P.unique_name("hráč", ["Hráč", "Hráč 2"]) == "hráč 3", "bez ohledu na velikost písmen")
	var long_name := "x".repeat(P.MAX_NAME_LEN)
	var u := P.unique_name(long_name, [long_name])
	check(u.length() <= P.MAX_NAME_LEN and u != long_name, "přípona se vejde do limitu", u)

	section("Validace")
	check(P.valid_id("watch_tv"), "platné id")
	check(not P.valid_id(""), "prázdné id")
	check(not P.valid_id(5), "číslo není id")
	check(not P.valid_id("a".repeat(100)), "příliš dlouhé id")
	check(P.valid_int(3, 0, 4), "int v rozsahu")
	check(not P.valid_int(5, 0, 4), "int mimo rozsah")
	check(not P.valid_int(2.0, 0, 4), "float není int")
	check(not P.valid_int("2", 0, 4), "String není int")

	section("Rychlost času")
	check(P.effective_speed([], 0) == 0, "bez hlasů → fallback")
	check(P.effective_speed([4, 3, 4], 0) == 4, "většina rozhoduje (dolní medián)")
	check(P.effective_speed([4, 0], 1) == 0, "při remíze vyhrává pomalejší")
	check(P.effective_speed([0, 3, 3, 3], 1) == 3, "jeden troll s pauzou nezastaví 3 hráče")
	check(P.effective_speed([2], 1) == 2, "jediný hráč rozhoduje sám")

	section("Rate limiter")
	var rl := P.RateLimiter.new(3.0, 1.0, 100.0)
	var ok := 0
	for i in 10:
		if rl.allow(100.0):
			ok += 1
	check(ok == 3, "burst omezen kapacitou", str(ok))
	check(not rl.allow(100.5), "po půl sekundě ještě nic")
	check(rl.allow(101.1), "po doplnění tokenu znovu povoleno")
	check(not rl.allow(50.0), "čas jdoucí pozpátku nic nepřidá")
	finish("test_net_protocol")
