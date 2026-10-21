extends SceneTree
## Offline render všech zvuků do res://audio/.
## Spuštění: godot --headless -s res://tools/build_audio.gd -- [id ...]
## Bez argumentů vyrenderuje vše (hudba trvá nejdéle).

const MusicData := preload("res://scripts/audio/music_data.gd")
const Recipes := preload("res://scripts/audio/sound_recipes.gd")


func _init() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = MusicData.SONGS.keys() + Recipes.AMBIENCE + Recipes.OBJECT_LOOPS + Recipes.UI
	build(ids)
	quit()


static func build(ids: Array) -> void:
	DirAccess.make_dir_recursive_absolute("res://audio/music")
	DirAccess.make_dir_recursive_absolute("res://audio/sfx")
	for id in ids:
		var t := Time.get_ticks_msec()
		var syn
		var path: String
		var loop := true
		if MusicData.SONGS.has(id):
			syn = MusicData.render(id)
			path = "res://audio/music/%s.wav" % id
		else:
			syn = Recipes.render(id)
			path = "res://audio/sfx/%s.wav" % id
			loop = Recipes.is_loop(id)
		if syn == null:
			continue
		var err: int = syn.save(path, loop)
		print("%s -> %s (%.1f s zvuku, %d ms, err=%d)" % [id, path, float(syn.length) / syn.sr, Time.get_ticks_msec() - t, err])
