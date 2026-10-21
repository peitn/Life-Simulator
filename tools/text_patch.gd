extends RefCounted
## TextPatch – nástroj pro vývoj (ne hra): aplikuje textové záplaty na soubor projektu.
## Formát záplaty: bloky
##   @@@OLD
##   <přesný původní text>
##   @@@NEW
##   <nový text>
##   @@@END
## Každý OLD se musí v souboru vyskytovat PRÁVĚ jednou, jinak se nic nezapíše (vše nebo nic).

static func apply(target: String, patch_path: String) -> Dictionary:
	var src := FileAccess.get_file_as_string(target)
	if src == "":
		return {"ok": false, "error": "prázdný nebo chybějící cíl"}
	var lines := FileAccess.get_file_as_string(patch_path).split("\n")
	var blocks: Array = []
	var mode := ""
	var old := PackedStringArray()
	var new := PackedStringArray()
	for l in lines:
		if l == "@@@OLD":
			mode = "old"
			old = PackedStringArray()
			new = PackedStringArray()
		elif l == "@@@NEW":
			mode = "new"
		elif l == "@@@END":
			blocks.append(["\n".join(old), "\n".join(new)])
			mode = ""
		elif mode == "old":
			old.append(l)
		elif mode == "new":
			new.append(l)
	var out := src
	for i in blocks.size():
		var o: String = blocks[i][0]
		var c := out.count(o)
		if c != 1:
			return {"ok": false, "error": "blok %d: výskytů %d" % [i, c], "head": o.left(80)}
		out = out.replace(o, blocks[i][1])
	var f := FileAccess.open(target, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	return {"ok": true, "blocks": blocks.size(), "bytes": out.length()}
