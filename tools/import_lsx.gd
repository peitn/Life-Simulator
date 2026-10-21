extends SceneTree
## Import assetů z „Blender bridge“:
##   1) res://assets/src/<jméno>.<k>.part  (přenesené části s CRC; jeden soubor může obsahovat
##      i víc částí za sebou, každá začíná řádkem "LSXC …")  →  res://assets/src/<jméno>.lsx
##   2) res://assets/src/<jméno>.lsx  →  scéna  →  res://assets/models/<jméno>.glb  (+ manifest.json)
## Složené assety (COMPOSE): model vznikne z hlavního .lsx a částí dalších .lsx se stejnou kostrou –
## postava = tělo (body.lsx, v4 se shape keys) + vlasy (character_head.lsx, v3) + od C3 procedurální hlava
## s obličejovými morfy ("assemble": CharacterAssembly – hlava, přenos morfů na vlasy, zúžení krku těla).
## Komponenty složených assetů se samostatně do GLB nepřevádějí.
## Spuštění: `load("res://tools/import_lsx.gd").run_all()` ze skriptu s `extends SceneTree`,
## nebo přímo: godot --headless --script res://tools/import_lsx.gd

const LSX := preload("res://scripts/assets/lsx_decoder.gd")
const CharacterAssembly := preload("res://scripts/assets/character_assembly.gd")
const SRC := "res://assets/src/"
const OUT := "res://assets/models/"

## model -> {"base": hlavní .lsx, "extra": [[.lsx, [vynechané skupiny]], …], "source": skript v tools/blender}
const COMPOSE := {
	"character": {"base": "body", "extra": [["character_head", ["body_m", "body_f", "head"]]],
		"source": "tools/blender/char.py + scripts/assets/head_builder.gd", "assemble": true},
}


func _init() -> void:
	var report := run_all()
	print(JSON.stringify(report, "  "))
	quit(0 if report.get("ok", false) else 1)


static func _list(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(f)
	out.sort()
	return out


## Rozdělí text souboru na jednotlivé části (každá začíná řádkem "LSXC").
static func split_chunks(text: String) -> Array:
	var out := []
	var cur := ""
	for line in text.split("\n"):
		if line.begins_with(LSX.CHUNK_HEADER + " "):
			if cur.strip_edges() != "":
				out.append(cur)
			cur = line + "\n"
		elif cur != "":
			cur += line + "\n"
	if cur.strip_edges() != "":
		out.append(cur)
	return out


## Spojí všechny kompletní sady částí. Neúplné/poškozené sady nechá být a nahlásí.
static func assemble_parts() -> Dictionary:
	var groups := {}
	var files := {}
	for f in _list(SRC, ".part"):
		var nm := f.get_slice(".", 0)
		if not groups.has(nm):
			groups[nm] = []
			files[nm] = []
		files[nm].append(f)
		groups[nm].append_array(split_chunks(FileAccess.get_file_as_string(SRC + f)))
	var done := []
	var errors := {}
	for nm in groups:
		var r := LSX.assemble(groups[nm])
		if not r["ok"]:
			errors[nm] = r["error"]
			continue
		if r.get("name", nm) != nm:
			errors[nm] = "jméno v hlavičce (%s) nesedí se souborem" % r.get("name", "")
			continue
		var fa := FileAccess.open(SRC + nm + ".lsx", FileAccess.WRITE)
		fa.store_string(r["data"])
		fa.close()
		for f in files[nm]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SRC + f))
		done.append(nm)
	return {"assembled": done, "errors": errors}


static func _decode_file(nm: String) -> Dictionary:
	if not FileAccess.file_exists(SRC + nm + ".lsx"):
		return {}
	return LSX.decode(FileAccess.get_file_as_string(SRC + nm + ".lsx"))


static func _write_glb(scene: Node3D, nm: String) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(scene, state)
	if err == OK:
		err = doc.write_to_filesystem(state, OUT + nm + ".glb")
	return err


static func _components() -> Array:
	var out := []
	for m in COMPOSE:
		out.append(String(COMPOSE[m]["base"]))
		for e in COMPOSE[m]["extra"]:
			out.append(String(e[0]))
	return out


static func convert_one(nm: String) -> Dictionary:
	var b64 := FileAccess.get_file_as_string(SRC + nm + ".lsx")
	var dec := LSX.decode(b64)
	if dec.is_empty():
		return {"ok": false, "error": "nelze dekódovat"}
	var scene := LSX.build_scene(dec)
	if scene == null:
		return {"ok": false, "error": "poškozená data části"}
	var err := _write_glb(scene, nm)
	scene.free()
	if err != OK:
		return {"ok": false, "error": "GLTF export selhal: %d" % err}
	var st := LSX.stats(dec)
	var head: Dictionary = dec["head"]
	return {"ok": true, "tris": st["tris"], "verts": st["verts"], "bones": st["bones"], "parts": st["parts"],
		"morphs": st["morphs"],
		"aabb_min": [st["aabb_min"].x, st["aabb_min"].y, st["aabb_min"].z],
		"aabb_max": [st["aabb_max"].x, st["aabb_max"].y, st["aabb_max"].z],
		"lsx_crc": "%08x" % LSX.crc32(b64.strip_edges().to_ascii_buffer()),
		"glb_bytes": FileAccess.get_file_as_bytes(OUT + nm + ".glb").size(),
		"meta": head.get("meta", {}), "source": "tools/blender/%s" % ("char.py" if st["bones"] > 0 else "furn.py")}


## Složený model (tělo + hlava…). Statistiky sčítají jen použité části.
static func convert_composed(model: String) -> Dictionary:
	var spec: Dictionary = COMPOSE[model]
	var base := _decode_file(String(spec["base"]))
	if base.is_empty():
		return {"ok": false, "error": "chybí nebo nejde dekódovat %s.lsx" % spec["base"]}
	var extra := []
	var crcs := {String(spec["base"]): "%08x" % LSX.crc32(FileAccess.get_file_as_string(SRC + String(spec["base"]) + ".lsx").strip_edges().to_ascii_buffer())}
	for e in spec["extra"]:
		var d := _decode_file(String(e[0]))
		if d.is_empty():
			return {"ok": false, "error": "chybí nebo nejde dekódovat %s.lsx" % e[0]}
		extra.append([d, e[1]])
		crcs[String(e[0])] = "%08x" % LSX.crc32(FileAccess.get_file_as_string(SRC + String(e[0]) + ".lsx").strip_edges().to_ascii_buffer())
	var scene := LSX.build_scene(base, extra)
	if scene == null:
		return {"ok": false, "error": "poškozená data nebo nesedí kostra"}
	var asm_meta := {}
	if bool(spec.get("assemble", false)):
		asm_meta = CharacterAssembly.attach_head(scene)
		if asm_meta.is_empty():
			scene.free()
			return {"ok": false, "error": "hlavu nejde připojit (chybí kostra head/neck nebo Skin)"}
	var tris := 0
	var verts := 0
	var parts := 0
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			tris += m.surface_get_array_index_len(s) / 3
			verts += m.surface_get_array_len(s)
		parts += 1
	var st := LSX.stats(base)
	var err := _write_glb(scene, model)
	scene.free()
	if err != OK:
		return {"ok": false, "error": "GLTF export selhal: %d" % err}
	var head: Dictionary = base["head"]
	var meta: Dictionary = (head.get("meta", {}) as Dictionary).duplicate(true)
	meta.merge(asm_meta, true)
	return {"ok": true, "tris": tris, "verts": verts, "bones": st["bones"], "parts": parts, "morphs": st["morphs"],
		"aabb_min": [st["aabb_min"].x, st["aabb_min"].y, st["aabb_min"].z],
		"aabb_max": [st["aabb_max"].x, st["aabb_max"].y, st["aabb_max"].z],
		"lsx_crc": crcs, "glb_bytes": FileAccess.get_file_as_bytes(OUT + model + ".glb").size(),
		"meta": meta, "source": spec.get("source", ""), "composed_from": crcs.keys()}


## `only` = převést jen tyto názvy (prázdné = všechny .lsx a složené modely).
static func run_all(only: Array = []) -> Dictionary:
	var asm := assemble_parts()
	var manifest := {}
	var mpath := OUT + "manifest.json"
	if FileAccess.file_exists(mpath):
		var old = JSON.parse_string(FileAccess.get_file_as_string(mpath))
		if typeof(old) == TYPE_DICTIONARY:
			manifest = old
	var results := {}
	var ok: bool = asm["errors"].is_empty()
	var comps := _components()
	for f in _list(SRC, ".lsx"):
		var nm := f.get_basename()
		if comps.has(nm) or (not only.is_empty() and not only.has(nm)):
			continue
		var r := convert_one(nm)
		results[nm] = r
		if r["ok"]:
			manifest[nm] = r
		else:
			ok = false
	for model in COMPOSE:
		if not only.is_empty() and not only.has(model):
			continue
		var r := convert_composed(model)
		results[model] = r
		if r["ok"]:
			manifest[model] = r
		else:
			ok = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var fa := FileAccess.open(mpath, FileAccess.WRITE)
	fa.store_string(JSON.stringify(manifest, "  "))
	fa.close()
	return {"ok": ok, "assembled": asm["assembled"], "part_errors": asm["errors"], "results": results}
