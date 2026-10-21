extends Resource
## CharacterData – JEDINÝ zdroj pravdy o postavě: vzhled, identita, povaha, historie.
## Verzované (VERSION ve schématu), serializovatelné (slovník / JSON / sdílecí kód přes
## CharacterCodec), validované přes CharacterValidator. Vzhled je explicitní atribut postavy –
## nikdy se neodvozuje ze jména (změna jména nemění kůži, hlas ani tělo).
##
## Skupiny (viz character_schema.gd): identity, body, face, skin, hair, eyes, makeup, aids,
## clothing, voice, personality, story, mind (soukromé, citlivé – obsahový štítek).
##
## Veřejný snapshot (`public_snapshot()`) obsahuje jen to, co ostatní hráči potřebují
## k vykreslení a oslovení postavy; orientace, genderová identita, aspirace, příběh
## a duševní predispozice jsou soukromé.

const Schema := preload("res://scripts/character/character_schema.gd")
const Grammar := preload("res://scripts/core/grammar_cs.gd")

@export var version: int = Schema.VERSION
## Stabilní interní ID (128 bit z kryptografického generátoru, 32 hex); nemění se se jménem. Neposílá se
## ostatním hráčům. NENÍ to autentizace: v multiplayeru server klientské uid zahodí a přidělí vlastní.
@export var uid: String = ""
@export var identity: Dictionary = {}
@export var body: Dictionary = {}
@export var face: Dictionary = {}
@export var skin: Dictionary = {}
@export var hair: Dictionary = {}
@export var eyes: Dictionary = {}
@export var makeup: Dictionary = {}
@export var aids: Dictionary = {}
@export var clothing: Dictionary = {}
@export var voice: Dictionary = {}
@export var personality: Dictionary = {}
@export var story: Dictionary = {}
@export var mind: Dictionary = {}

const GROUP_PROPS := ["identity", "body", "face", "skin", "hair", "eyes", "makeup", "aids", "clothing",
	"voice", "personality", "story", "mind"]


## Nová postava s výchozími hodnotami (jméno je prázdné – editor/generátor ho doplní).
static func create() -> Resource:
	var cd = load("res://scripts/character/character_data.gd").new()
	cd.set_from_dict(Schema.defaults())
	cd.uid = new_uid()
	return cd


static func new_uid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Kanonický slovník (deep copy). Vstup pro kodek a validátor.
func to_dict() -> Dictionary:
	var d := {"v": version, "uid": uid}
	for g in GROUP_PROPS:
		d[g] = (get(g) as Dictionary).duplicate(true)
	return d


## Nastaví skupiny ze slovníku BEZ validace (volající používá CharacterValidator).
func set_from_dict(d: Dictionary) -> void:
	version = int(d.get("v", Schema.VERSION))
	uid = String(d.get("uid", uid))
	for g in GROUP_PROPS:
		var v = d.get(g, {})
		set(g, (v as Dictionary).duplicate(true) if typeof(v) == TYPE_DICTIONARY else {})


func clone() -> Resource:
	var cd = get_script().new()
	cd.set_from_dict(to_dict())
	return cd


func display_name() -> String:
	return ("%s %s" % [String(identity.get("first_name", "")), String(identity.get("last_name", ""))]).strip_edges()


func first_name() -> String:
	return String(identity.get("first_name", ""))


func grammar() -> String:
	return Grammar.norm(identity.get("grammar", "m"))


func traits() -> Array:
	return (personality.get("traits", []) as Array).duplicate()


## Veřejná část – replikuje se všem peerům (vykreslení + oslovení). Review ChatGPT 48:
##  - STRIKTNÍ ALLOWLIST: jen pole, která schéma označí jako veřejná; jizvy a tetování jen jako parametry
##    vykreslení (zóna, velikost / motiv, barva) a jen ty, které vlastník neskryl (hidden),
##  - výsledek projde validátorem v režimu public_only (opravném), takže i z poškozených dat v editoru
##    (set_path_value bez validace) vznikne vždy kanonický snapshot ve správných rozsazích.
func public_snapshot() -> Dictionary:
	var d := {"v": Schema.VERSION}
	for g in GROUP_PROPS:
		if g == "clothing":
			d[g] = clothing.duplicate(true)
			continue
		if not Schema.GROUPS.has(g):
			continue
		var src: Dictionary = get(g)
		var fs: Dictionary = Schema.fields(g)
		var out := {}
		for k in fs:
			if Schema.is_public(g, k) and src.has(k):
				var v = src[k]
				out[k] = v.duplicate(true) if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY else v
		if g == "skin":
			out["scars"] = _visible_items(src.get("scars", []), ["zone", "size"])
			out["tattoos"] = _visible_items(src.get("tattoos", []), ["zone", "design", "color"])
		if not out.is_empty():
			d[g] = out
	var V = load("res://scripts/character/character_validator.gd")
	return V.repaired(d, {"public_only": true})


static func _visible_items(list, keys: Array) -> Array:
	var res: Array = []
	if typeof(list) != TYPE_ARRAY:
		return res
	for it in list:
		if typeof(it) != TYPE_DICTIONARY or bool(it.get("hidden", false)):
			continue
		var o := {}
		for k in keys:
			if it.has(k):
				o[k] = it[k]
		res.append(o)
	return res


## Soukromá část – jen vlastník a server (orientace, identita, aspirace, příběh, duševní predispozice).
func private_part() -> Dictionary:
	var d := {}
	for g in GROUP_PROPS:
		if g == "clothing" or not Schema.GROUPS.has(g):
			continue
		var src: Dictionary = get(g)
		var out := {}
		for k in src:
			# Jizvy a tetování (i skryté) zůstávají vlastníkovi v plných datech; private_part nese jen
			# skupiny/pole, která nejsou veřejná vůbec.
			if not Schema.is_public(g, String(k)) and not (g == "skin" and (k == "scars" or k == "tattoos")):
				out[k] = src[k] if typeof(src[k]) != TYPE_ARRAY and typeof(src[k]) != TYPE_DICTIONARY else src[k].duplicate(true)
		if not out.is_empty():
			d[g] = out
	return d


## Predispozice pro MentalState ({"anxiety": 0.6, ...}).
func conditions() -> Dictionary:
	return (mind.get("predispositions", {}) as Dictionary).duplicate()


func patterns() -> Dictionary:
	return {"morning_worse": bool(mind.get("morning_worse", false))}


## Hodnota podle cesty "skupina.pole" (pro zámky, editor a testy).
func get_path_value(path: String) -> Variant:
	var parts := path.split(".")
	if parts.size() != 2 or not GROUP_PROPS.has(parts[0]):
		return null
	return (get(parts[0]) as Dictionary).get(parts[1])


## Zápis bez validace (editor během tažení posuvníku). Před exportem, uložením nebo odesláním na server
## se data vždy prohánějí validátorem (CharacterCodec / public_snapshot), takže sem nepatří kontrola.
func set_path_value(path: String, v: Variant) -> void:
	var parts := path.split(".")
	if parts.size() != 2 or not GROUP_PROPS.has(parts[0]):
		return
	var g: Dictionary = get(parts[0])
	g[parts[1]] = v
