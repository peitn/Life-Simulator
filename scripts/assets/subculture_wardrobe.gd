extends RefCounted
## C5.1 outfit combinations, not stereotypes or personality assignments.
## Independent of character sex, body, identity and psyche.
const STYLES := {
	"punk": {"label":"Punk", "top":"punk_vesta", "bottom":"punk_kostka", "shoes":"punk_kanady", "top_color":"#a52335", "bottom_color":"#aa303c"},
	"metal": {"label":"Metal", "top":"metal_tricko", "bottom":"metal_dziny", "shoes":"metal_kanady", "top_color":"#161719", "bottom_color":"#1d1d21"},
	"emo": {"label":"Emo", "top":"emo_mikina", "bottom":"emo_dziny", "shoes":"emo_tenisky", "top_color":"#23212c", "bottom_color":"#171720"},
	"goth": {"label":"Goth", "top":"goth_korset", "bottom":"goth_sukne", "shoes":"goth_platformy", "top_color":"#201c29", "bottom_color":"#111015"},
	"kawaii": {"label":"Kawaii", "top":"kawaii_svetr", "bottom":"kawaii_sukne", "shoes":"kawaii_boty", "top_color":"#f4a7cf", "bottom_color":"#f2c8e6"},
	"harajuku": {"label":"Harajuku", "top":"harajuku_bunda", "bottom":"harajuku_sukne", "shoes":"harajuku_platformy", "top_color":"#75a3ec", "bottom_color":"#e883ce"},
	"kawaii_kocka": {"label":"Kawaii kočičí mikina", "top":"kawaii_kocici_mikina", "bottom":"kawaii_sukne", "shoes":"kawaii_boty", "top_color":"#f5a6d0", "bottom_color":"#efb9db"},
	"grunge": {"label":"Grunge", "top":"grunge_kosile", "bottom":"grunge_dziny", "shoes":"grunge_kanady", "top_color":"#625e4b", "bottom_color":"#3b3b45"},
	"visualkei": {"label":"Visual kei", "top":"visualkei_sako", "bottom":"visualkei_kalhoty", "shoes":"visualkei_boty", "top_color":"#39223f", "bottom_color":"#171820"},
}

static func names() -> Array:
	return STYLES.keys()

static func outfit(style: String) -> Dictionary:
	if not STYLES.has(style):
		return {}
	var copy: Dictionary = STYLES[style].duplicate(true)
	copy.erase("label")
	return copy

## Apply one look to an existing outfit slot (bezne, pracovni, spolecenske, spani, sport).
## User can freely replace each item after applying the preset.
static func apply_to_character(character: Dictionary, style: String, slot: String = "bezne") -> Dictionary:
	var Schema = load("res://scripts/character/character_schema.gd")
	if not STYLES.has(style) or not Schema.OUTFIT_CATEGORIES.has(slot):
		return character.duplicate(true)
	var result: Dictionary = character.duplicate(true)
	if not result.has("clothing") or typeof(result["clothing"]) != TYPE_DICTIONARY:
		result["clothing"] = Schema.default_outfits()
	var c: Dictionary = result["clothing"]
	var original: Dictionary = c.get(slot, Schema.default_outfits()[slot]).duplicate(true)
	original.merge(outfit(style), true)
	c[slot] = original
	c["active"] = slot
	return result
