extends Node
## H3 test-only sleeve nested search/blend/normals profiler; real meshes; SHA guarded.
## Instruments a SHA-verified in-memory copy, never writes production sources.
## CPU wall-clock stages are NOT frame-time, GPU, or H3 networking certification.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("H3 stage profiler stale source hash; refusing test")
		get_tree().quit(2)
		return
	var src: String = FileAccess.get_file_as_string(SOURCE)
	var replacements: Array = [["\t_loaded[kind] = {}","\tvar __h3_load_t0: int = Time.get_ticks_usec()\n\t_loaded[kind] = {}"],["\tvar decoded := LSX.decode(FileAccess.get_file_as_string(path))","\tvar __h3_read_t0: int = Time.get_ticks_usec()\n\tvar __h3_payload: String = FileAccess.get_file_as_string(path)\n\tvar __h3_read_ms: float = float(Time.get_ticks_usec() - __h3_read_t0) / 1000.0\n\tvar __h3_decode_t0: int = Time.get_ticks_usec()\n\tvar decoded := LSX.decode(__h3_payload)\n\tvar __h3_decode_ms: float = float(Time.get_ticks_usec() - __h3_decode_t0) / 1000.0"],["\tvar scene := LSX.build_scene(decoded)","\tvar __h3_scene_t0: int = Time.get_ticks_usec()\n\tvar scene := LSX.build_scene(decoded)\n\tvar __h3_scene_ms: float = float(Time.get_ticks_usec() - __h3_scene_t0) / 1000.0"],["\tvar shells: Dictionary={}","\tvar __h3_mesh_ms: float = 0.0\n\tvar __h3_mesh_count: int = 0\n\tvar shells: Dictionary={}"],["\t\tvar mesh := _textured_mesh(mi.mesh as ArrayMesh, mat_name, String(tokens[4]), shells.get(style))","\t\tvar __h3_mesh_t0: int = Time.get_ticks_usec()\n\t\tvar mesh := _textured_mesh(mi.mesh as ArrayMesh, mat_name, String(tokens[4]), shells.get(style))\n\t\t__h3_mesh_ms += float(Time.get_ticks_usec() - __h3_mesh_t0) / 1000.0\n\t\t__h3_mesh_count += 1"],["\tscene.free()","\tscene.free()\n\tprint(\"H3_GARMENT_STAGE kind=\", kind, \" read_ms=\", __h3_read_ms, \" decode_ms=\", __h3_decode_ms, \" scene_ms=\", __h3_scene_ms, \" mesh_ms=\", __h3_mesh_ms, \" total_ms=\", float(Time.get_ticks_usec() - __h3_load_t0) / 1000.0, \" mesh_count=\", __h3_mesh_count, \" thread_id=\", OS.get_thread_caller_id())"]]
	replacements.append(["\t\tvar arrays := source.surface_get_arrays(s)","\t\tvar __h3_t: int = Time.get_ticks_usec()\n\t\tvar arrays := source.surface_get_arrays(s)"])
	replacements.append(["\t\tvar blend := source.surface_get_blend_shape_arrays(s)","\t\tvar blend := source.surface_get_blend_shape_arrays(s)\n\t\tvar __h3_fetch_ms: float = float(Time.get_ticks_usec()-__h3_t)/1000.0\n\t\t__h3_t = Time.get_ticks_usec()"])
	replacements.append(["\t\tarrays[Mesh.ARRAY_BONES] = bones","\t\tarrays[Mesh.ARRAY_BONES] = bones\n\t\tvar __h3_fit_remap_ms: float = float(Time.get_ticks_usec()-__h3_t)/1000.0\n\t\t__h3_t = Time.get_ticks_usec()"])
	replacements.append(["\t\tverts = arrays[Mesh.ARRAY_VERTEX]","\t\tvar __h3_stitch_ms: float = float(Time.get_ticks_usec()-__h3_t)/1000.0\n\t\t__h3_t = Time.get_ticks_usec()\n\t\tverts = arrays[Mesh.ARRAY_VERTEX]"])
	replacements.append(["\t\tarrays[Mesh.ARRAY_TANGENT] = tangents","\t\tarrays[Mesh.ARRAY_TANGENT] = tangents\n\t\tvar __h3_uv_ms: float = float(Time.get_ticks_usec()-__h3_t)/1000.0\n\t\t__h3_t = Time.get_ticks_usec()"])
	replacements.append(["\t\tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)","\t\tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend)\n\t\tvar __h3_upload_ms: float = float(Time.get_ticks_usec()-__h3_t)/1000.0\n\t\t__h3_t = Time.get_ticks_usec()"])
	replacements.append(["\t\tm.surface_set_material(s, _mat(mat_name))","\t\tm.surface_set_material(s, _mat(mat_name))\n\t\tprint(\"H3_MESH_PIECE piece=\",piece,\" vertices=\",verts.size(),\" fetch_ms=\",__h3_fetch_ms,\" fit_remap_ms=\",__h3_fit_remap_ms,\" stitch_ms=\",__h3_stitch_ms,\" uv_ms=\",__h3_uv_ms,\" upload_ms=\",__h3_upload_ms,\" material_ms=\",float(Time.get_ticks_usec()-__h3_t)/1000.0)"])
	replacements.append(["\tvar rim: Array=[]", "\tvar __h3_total_t0: int = Time.get_ticks_usec()\n\tvar __h3_search_us: int = 0\n\tvar __h3_blend_us: int = 0\n\tvar __h3_tri_tests: int = 0\n\tvar rim: Array=[]"])
	replacements.append(["\t\tfor t in range(0,si.size(),3):", "\t\tvar __h3_search_t0: int = Time.get_ticks_usec()\n\t\t__h3_tri_tests += si.size()/3\n\t\tfor t in range(0,si.size(),3):"])
	replacements.append(["\t\tif tri.is_empty() or best>.08*.08: continue", "\t\t__h3_search_us += Time.get_ticks_usec() - __h3_search_t0\n\t\tif tri.is_empty() or best>.08*.08: continue"])
	replacements.append(["\t\tvar q:=Vector3.ZERO", "\t\tvar __h3_blend_t0: int = Time.get_ticks_usec()\n\t\tvar q:=Vector3.ZERO"])
	replacements.append(["\t\t\tweights[vi*4+k]=float(influences[ids[k]])/total if k<ids.size() else 0.0", "\t\t\tweights[vi*4+k]=float(influences[ids[k]])/total if k<ids.size() else 0.0\n\t\t__h3_blend_us += Time.get_ticks_usec() - __h3_blend_t0"])
	replacements.append(["\tarrays[Mesh.ARRAY_VERTEX]=points", "\tvar __h3_normals_t0: int = Time.get_ticks_usec()\n\tarrays[Mesh.ARRAY_VERTEX]=points"])
	replacements.append(["\tfor target in blends: _rebuild_vertex_normals(target,arrays[Mesh.ARRAY_INDEX])", "\tfor target in blends: _rebuild_vertex_normals(target,arrays[Mesh.ARRAY_INDEX])\n\tprint('H3_STITCH_SPLIT triangles=',__h3_tri_tests,' rim=',rim.size(),' search_ms=',float(__h3_search_us)/1000.0,' blend_ms=',float(__h3_blend_us)/1000.0,' normals_ms=',float(Time.get_ticks_usec()-__h3_normals_t0)/1000.0,' total_ms=',float(Time.get_ticks_usec()-__h3_total_t0)/1000.0)"])
	for pair in replacements:
		var anchor: String = pair[0]
		if src.count(anchor) != 1:
			push_error("H3 stage profiler missing/ambiguous anchor: " + anchor.strip_edges())
			get_tree().quit(2)
			return
		src = src.replace(anchor, pair[1])
	src = src.replace("\t\tprint(\"H3_MESH_PIECE piece=\",piece", "\t\tif piece.begins_with(\"sleeve_\"):\n\t\t\tprint(\"H3_MESH_PIECE piece=\",piece")
	var instrumented := GDScript.new()
	instrumented.source_code = src
	if instrumented.reload() != OK:
		push_error("H3 stage profiler in-memory GDScript compilation failed")
		get_tree().quit(2)
		return
	var lp: Dictionary = {"outfit_top": "tricko", "outfit_bottom": "dziny", "outfit_shoes": "tenisky"}
	var start: int = Time.get_ticks_usec()
	var cold: Variant = instrumented.call("active_parts", lp)
	var cold_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var warm: Variant = instrumented.call("active_parts", lp)
	var warm_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	if not (cold is Array and warm is Array) or cold.size() < 3 or cold.size() != warm.size():
		push_error("H3 stage profiler missing real C5 mesh parts")
		get_tree().quit(1)
		return
	var surfaces: int = 0
	var vertices: int = 0
	for part in cold:
		var mesh: Mesh = part.get("mesh")
		if mesh == null:
			push_error("H3 stage profiler encountered null garment mesh")
			get_tree().quit(1)
			return
		surfaces += mesh.get_surface_count()
		for i in mesh.get_surface_count():
			vertices += mesh.surface_get_array_len(i)
	print("H3_GARMENT_SUMMARY cold_ms=", cold_ms, " warm_ms=", warm_ms,
		" parts=", cold.size(), " surfaces=", surfaces, " vertices=", vertices,
		" main_thread_id=", OS.get_thread_caller_id())
	get_tree().quit(0)