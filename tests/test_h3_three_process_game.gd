extends "res://tests/diagnostics/h3_three_process.FAILING.gd"
## H3 regression (7 Nov 2026): the full creator -> owner-private -> spectator -> reconnect flow in three
## separate Godot OS processes, with the REAL authored character model and the GAME's asset path
## (Main `async_character_assets`: background hair + C5 wardrobe, client prewarm before connecting).
## Same 17 acceptance gates as the diagnostic; only the fixture mode is fixed. The diagnostic
## default (synchronous assets) stays available as the worst case.

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4 and args[0] == "worker":
		await super._run()
		return
	_game_assets_test = true
	await _parent()
