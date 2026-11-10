extends RefCounted
## Device-local portable recipe library. Filenames are hashes, never user input.
const Design=preload("res://scripts/clothing/garment_design.gd")
const DIR:="user://garments/"
const MAX_DESIGNS:=128
static func save_design(recipe:Dictionary, directory:String=DIR)->Dictionary:
	var checked:Dictionary=Design.validate(recipe)
	if not checked.ok:return checked
	var path:String=directory.path_join(Design.signature(checked.data)+".json")
	if not FileAccess.file_exists(path) and list_designs(directory).size()>=MAX_DESIGNS:
		return {"ok":false,"error":"Knihovna je plná (128 návrhů)."}
	var rc:int=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if rc!=OK:return {"ok":false,"error":"Složku návrhů nelze vytvořit."}
	var temp:String=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return {"ok":false,"error":"Návrh nelze uložit."}
	file.store_string(Design.to_json(checked.data))
	file.flush()
	var write_error:int=file.get_error()
	file.close()
	if write_error!=OK:return {"ok":false,"error":"Zápis návrhu selhal."}
	rc=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	return {"ok":rc==OK,"path":path,"error":"" if rc==OK else "Návrh nelze dokončit."}

static func list_designs(directory:String=DIR)->Array:
	var result:Array=[]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):return result
	var files:PackedStringArray=DirAccess.get_files_at(directory)
	files.sort()
	for name in files:
		if not name.ends_with(".json") or name.length()!=69:continue
		var path:String=directory.path_join(name)
		var f:=FileAccess.open(path,FileAccess.READ)
		if f==null:continue
		if f.get_length()>Design.MAX_BYTES:
			f.close()
			continue
		var parsed:Dictionary=Design.from_json(f.get_as_text())
		f.close()
		if parsed.ok:result.append({"path":path,"design":parsed.data})
		if result.size()>=MAX_DESIGNS:break
	return result
