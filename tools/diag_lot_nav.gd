extends Node
## Diagnostika B3: rozměry startovní parcely, vnitřek domu, statické obdélníky a body použití (pro test_lot_nav).

const Main := preload("res://main.gd")
const Catalog := preload("res://scripts/world/buy_catalog.gd")


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var clock := get_node("/root/GameClock")
	clock.running = false
	var w := Node3D.new()
	w.set_script(Main)
	w.net_config = {"mode": "offline", "audio": false, "camera": false, "visuals": false, "hud": false,
		"autoload": false, "autosave": false, "save_directory": "user://diag-lot-nav", "clock": clock}
	add_child(w)
	var lot = w.lot
	print("origin ", lot.origin, " gw ", lot.gw, " gh ", lot.gh, " world ", lot.world_rect())
	print("interior ", lot.interior_rects)
	print("static ", lot.static_rects.size(), " keepout ", lot.keepout_rects)
	for f in lot.fixed:
		print("fixed ", f["name"], " ", f["rect"], " ", f["access"])
	for s in w.sims:
		print("sim ", s.name, " ", s.global_position)
	for id in Catalog.ITEMS:
		var it: Dictionary = Catalog.ITEMS[id]
		print("item ", id, " ", it["w"], "x", it["d"], " ", it["place"], " ", it.get("layer", "solid"), " use ", it.get("use", []))
	# ASCII mapa průchodnosti po 2 buňkách (0,5 m): # zeď/static, o nábytek, . volno, k koridor
	for z in range(0, lot.gh, 2):
		var line := ""
		for x in range(0, lot.gw, 2):
			var i: int = lot._idx(x, z)
			if lot._keepout[i] == 1:
				line += "k"
			elif lot._static[i] == 1:
				line += "#"
			elif lot._solid[i] != 0:
				line += "o"
			elif lot._inside[i] == 1:
				line += ","
			else:
				line += "."
		print(line)
	get_tree().quit(0)
