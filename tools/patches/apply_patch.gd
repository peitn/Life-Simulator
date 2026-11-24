extends SceneTree
## Nástroj automatizace: aplikuje soubor náhrad (@@@FILE cesta / @@@OLD / @@@NEW / @@@END) – každý OLD musí
## být v souboru PRÁVĚ JEDNOU, jinak se nic nezapíše. Použití: godot --script tools/patches/apply_patch.gd -- res://cesta.patch

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else ""
	print(apply(path))
	quit()


static func apply(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	if src == "":
		return "PATCH ERROR: prázdný soubor " + path
	var files := {}
	var order: Array = []
	var cur_file := ""
	var blocks := src.split("@@@")
	var pending_old := ""
	var have_old := false
	var errors: Array = []
	var applied := 0
	for b in blocks:
		if b.begins_with("FILE "):
			cur_file = b.substr(5).strip_edges()
			if not files.has(cur_file):
				files[cur_file] = FileAccess.get_file_as_string(cur_file)
				order.append(cur_file)
		elif b.begins_with("OLD\n"):
			pending_old = b.substr(4)
			have_old = true
		elif b.begins_with("NEW\n"):
			if not have_old or cur_file == "":
				errors.append("NEW bez OLD/FILE")
				continue
			var nw := b.substr(4)
			var text: String = files[cur_file]
			var cnt := text.count(pending_old)
			if cnt != 1:
				errors.append("%s: OLD nalezen %dx: %s" % [cur_file, cnt, pending_old.substr(0, 90).replace("\n", "⏎")])
			else:
				files[cur_file] = text.replace(pending_old, nw)
				applied += 1
			have_old = false
	if not errors.is_empty():
		return "PATCH ERROR (nic nezapsáno):\n" + "\n".join(errors)
	for f in order:
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_string(files[f])
		fa.close()
	return "PATCH OK: %d náhrad v %d souborech" % [applied, order.size()]
