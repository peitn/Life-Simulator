extends Node
## Test-only spatial rejection in C5 sleeve matching. Original production source is untouched.
## An X/Z triangle AABB expanded by the original 0.08 m distance limit is a
## conservative filter: any accepted same-height projected point lies inside it.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _fail(reason: String) -> void:
	push_error("H3_BBOX_PARITY_FAIL " + reason)
	get_tree().quit(1)

func _run() -> void:
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		_fail("source SHA changed")
		return
	var original: GDScript = load(SOURCE)
	var code: String = FileAccess.get_file_as_string(SOURCE)
	var anchor := "\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]"
	if code.count(anchor) != 1:
		_fail("missing or ambiguous exact search anchor")
		return
	var replacement := "\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]\n\t\t\tvar __a: Vector3=sv[ids[0]]\n\t\t\tvar __b: Vector3=sv[ids[1]]\n\t\t\tvar __c: Vector3=sv[ids[2]]\n\t\t\tvar __min_x: float=minf(__a.x,minf(__b.x,__c.x))-.08001\n\t\t\tvar __max_x: float=maxf(__a.x,maxf(__b.x,__c.x))+.08001\n\t\t\tvar __min_z: float=minf(__a.z,minf(__b.z,__c.z))-.08001\n\t\t\tvar __max_z: float=maxf(__a.z,maxf(__b.z,__c.z))+.08001\n\t\t\tif p.x<__min_x or p.x>__max_x or p.z<__min_z or p.z>__max_z:\n\t\t\t\tcontinue"
	var candidate := GDScript.new()
	candidate.source_code = code.replace(anchor,replacement)
	if candidate.reload() != OK:
		_fail("candidate in-memory compilation failed")
		return
	var t0: int = Time.get_ticks_usec()
	original.call("parts","top","tricko")
	var baseline_ms: float = float(Time.get_ticks_usec()-t0)/1000.0
	t0 = Time.get_ticks_usec()
	candidate.call("parts","top","tricko")
	var candidate_ms: float = float(Time.get_ticks_usec()-t0)/1000.0
	var orig_loaded: Dictionary = original.get("_loaded")
	var test_loaded: Dictionary = candidate.get("_loaded")
	if not orig_loaded.has("top") or not test_loaded.has("top"):
		_fail("top garments not loaded")
		return
	var a: Dictionary = orig_loaded["top"]
	var b: Dictionary = test_loaded["top"]
	if a.size()!=b.size() or a.size()<20:
		_fail("top style count mismatch")
		return
	var checked: int = 0
	var surfaces: int = 0
	var vertices: int = 0
	var blend_shapes: int = 0
	for style in a.keys():
		if not b.has(style) or a[style].size()!=b[style].size():
			_fail("style/part mismatch "+str(style))
			return
		for k in a[style].size():
			var old_part: Dictionary=a[style][k]
			var new_part: Dictionary=b[style][k]
			for key in ["name","material","category"]:
				if old_part.get(key)!=new_part.get(key):
					_fail("metadata mismatch "+str(style)+" "+str(k)+" "+key)
					return
			var old_mesh: ArrayMesh=old_part["mesh"]
			var new_mesh: ArrayMesh=new_part["mesh"]
			if old_mesh.get_surface_count()!=new_mesh.get_surface_count() or old_mesh.get_blend_shape_count()!=new_mesh.get_blend_shape_count():
				_fail("surface/shape count mismatch "+str(style)+" "+str(k))
				return
			for s in old_mesh.get_surface_count():
				var old_arrays: Array=old_mesh.surface_get_arrays(s)
				var new_arrays: Array=new_mesh.surface_get_arrays(s)
				for channel in old_arrays.size():
					if old_arrays[channel]!=new_arrays[channel]:
						_fail("ARRAY mismatch style="+str(style)+" part="+str(k)+" surface="+str(s)+" channel="+str(channel))
						return
				var old_blends: Array=old_mesh.surface_get_blend_shape_arrays(s)
				var new_blends: Array=new_mesh.surface_get_blend_shape_arrays(s)
				if old_blends.size()!=new_blends.size():
					_fail("blend count mismatch")
					return
				for j in old_blends.size():
					for channel in old_blends[j].size():
						if old_blends[j][channel]!=new_blends[j][channel]:
							_fail("BLEND mismatch style="+str(style)+" part="+str(k)+" target="+str(j)+" channel="+str(channel))
							return
				surfaces+=1
				vertices+=old_mesh.surface_get_array_len(s)
			blend_shapes+=old_mesh.get_blend_shape_count()
			checked+=1
	print("H3_BBOX_PARITY_PASS styles=",a.size()," meshes=",checked," surfaces=",surfaces," vertices=",vertices," blend_shapes=",blend_shapes," baseline_cold_ms=",baseline_ms," candidate_cold_ms=",candidate_ms," exact_arrays=true")
	get_tree().quit(0)
