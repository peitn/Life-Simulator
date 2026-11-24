extends SceneTree
# Bounded network replication contract regression. This does not replace a two-peer ENet privacy test.
const NetSession = preload("res://scripts/net/net_session.gd")
var passed := 0
var failed := 0

func check(condition: bool, label: String) -> void:
 if condition:
  passed += 1
  print("PASS ", label)
 else:
  failed += 1
  printerr("FAIL ", label)

func _init() -> void:
 var sync := NetSession.make_synchronizer()
 var cfg := sync.replication_config
 var actual: Array = []
 for p in cfg.get_properties():
  actual.append(String(p))
 var expected: Array = []
 for p in NetSession.SYNC_PROPS:
  expected.append(".:" + String(p))
 check(actual.size() == expected.size(), "public property count exact")
 for p in expected:
  check(actual.has(p), "public allowlist " + p)
 var forbidden := ["mental_state", "psyche", "relationships", "memories", "needs", "rumination", "self_defectiveness", "withdrawal", "private_state", "psy", "betrayal", "net_detail", "net_needs"]
 for p in forbidden:
  check(not actual.has(".:" + p), "private field excluded " + p)
 check(not actual.has(".:character_data"), "character data excluded")
 check(cfg.get_properties().size() == NetSession.SYNC_PROPS.size(), "no extra replication property")
 sync.free()
 print("RESULT ",passed,"/",passed+failed)
 quit(0 if failed == 0 else 1)
