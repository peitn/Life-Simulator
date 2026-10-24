extends "res://tests/test_base.gd"

const CharacterData := preload("res://scripts/character/character_data.gd")
const Session := preload("res://scripts/character/character_edit_session.gd")
const Validator := preload("res://scripts/character/character_validator.gd")

var permitted := true

func allowed(_source: Resource) -> bool:
	return permitted


func _ready() -> void:
	var c := CharacterData.create()
	c.identity["first_name"] = "Alex"
	c.set_from_dict(Validator.repaired(c.to_dict()))
	var original: Dictionary = c.to_dict()
	var s := Session.new()
	check(not s.begin(null), "null source rejected")
	check(s.begin(c), "open valid resource")
	check(not s.begin(c), "opening twice cannot discard unsaved edits")
	var d := s.draft()
	d["identity"]["first_name"] = "Robin"
	check(s.draft() == original, "draft getter has no mutable alias")
	check(s.replace_draft(d, "Name"), "accept draft edit")
	d["identity"]["first_name"] = "External"
	check(s.draft()["identity"]["first_name"] == "Robin", "input is deep copied")
	check(c.to_dict() == original and s.is_dirty(), "editing leaves live character unchanged")
	check(s.undo() == original and not s.is_dirty(), "undo restores clean baseline")
	check(s.redo()["identity"]["first_name"] == "Robin", "redo restores edit")
	s.cancel()
	check(c.to_dict() == original and not s.is_open(), "cancel leaves source unchanged")
	check(s.draft().is_empty() and not s.can_undo() and not s.can_redo(), "cancel clears private draft and history")
	check(s.apply(allowed)["reason"] == "closed", "closed session cannot apply")
	s.begin(c)
	d = s.draft()
	d["body"]["height_cm"] = -1.0
	s.replace_draft(d)
	check(s.apply(allowed, {"mode": "repair"})["reason"] == "invalid", "apply enforces strict validation")
	check(c.to_dict() == original and s.is_dirty(), "invalid apply is atomic and retains draft")
	s.undo()
	d = s.draft()
	d["identity"]["first_name"] = "Robin"
	s.replace_draft(d)
	permitted = false
	check(s.apply(allowed)["reason"] == "forbidden", "permission revocation checked at apply")
	check(s.apply(Callable())["reason"] == "forbidden", "missing permission check fails closed")
	check(c.to_dict() == original, "denied writes leave character intact")
	permitted = true
	c.identity["last_name"] = "Novak"
	check(s.apply(allowed)["reason"] == "conflict", "concurrent live change is not overwritten")
	check(c.identity["last_name"] == "Novak" and s.is_dirty(), "conflict preserves live change and draft")
	s.cancel()
	s.begin(c)
	d = s.draft()
	d["uid"] = CharacterData.new_uid()
	check(not s.replace_draft(d), "cannot replace server identity")
	d = s.draft()
	d["v"] = 999
	check(not s.replace_draft(d), "cannot replace schema version")
	d = s.draft()
	d["identity"]["first_name"] = "Robin"
	d["personality"]["trait_levels"] = {"optimista": 0.49, "brucoun": 0.51}
	d["mind"]["predispositions"] = {"anxiety": 0.7}
	s.replace_draft(d)
	check(s.apply(allowed)["ok"], "apply validated changes")
	check(c.identity["first_name"] == "Robin" and c.uid == original["uid"], "apply preserves stable identity")
	check(c.personality["trait_levels"]["brucoun"] == 0.51, "continuous profile preserved")
	check(not c.public_snapshot().has("mind"), "commit preserves existing snapshot privacy")
	check(not s.is_dirty() and not s.can_undo(), "apply establishes new clean baseline")
	d = s.draft()
	d["identity"]["first_name"] = "Alex"
	s.replace_draft(d)
	s.cancel()
	check(c.identity["first_name"] == "Robin", "cancel after apply does not revert committed data")
	s.begin(c)
	d = s.draft()
	d["body"]["height_cm"] = 170.0
	s.replace_draft(d, "Height", "height", 100)
	d["body"]["height_cm"] = 171.0
	s.replace_draft(d, "Height", "height", 200)
	check(s.undo() == c.to_dict() and not s.can_undo(), "slider drag coalesces to one undo step")
	s.redo()
	d = s.draft()
	d["mind"]["predispositions"] = {"anxiety": 0.9}
	s.replace_draft(d)
	check(s.apply(allowed, {"mental_health": "off"})["ok"], "authoritative content policy accepted")
	check(c.mind["predispositions"].is_empty(), "disabled sensitive content stripped on commit")
	s.cancel()
	finish("test_character_edit_session")
