extends Node
## Test-only per-shell precomputed X/Y/Z triangle bounds with exact mesh parity; production untouched.
## Precomputed conservative bounds retain all possible <=0.08m closest matches.
## Test-only static cache retains shell references for process lifetime; not production-ready.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _fail(reason: String) -> void:
	push_error("H3_INDEX_PARITY_FAIL " + reason)
	get_tree().quit(1)

func _run() -> void:
	if not _synthetic_boundaries():
		_fail("boundary false negative")
		return
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		_fail("source SHA changed")
		return
	var original: GDScript = load(SOURCE)
	var code: String = FileAccess.get_file_as_string(SOURCE)

	var anchor := "\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]"
	var rim_anchor := "\tfor vi in rim:"
	if code.count(anchor)!=1 or code.count(rim_anchor)!=1:
		_fail("ambiguous source anchor")
		return
	code=code.replace("static func _stitch_sleeve(","static var __tri_bounds_cache: Dictionary = {}\n\nstatic func _stitch_sleeve(")
	var prelude := "\tvar __bounds: Array=[]\n\tif __tri_bounds_cache.has(shell):\n\t\t__bounds=__tri_bounds_cache[shell]\n\telse:\n\t\tfor __t in range(0,si.size(),3):\n\t\t\tvar __ids: Array=[si[__t],si[__t+1],si[__t+2]]\n\t\t\tvar __a: Vector3=sv[__ids[0]]\n\t\t\tvar __b: Vector3=sv[__ids[1]]\n\t\t\tvar __c: Vector3=sv[__ids[2]]\n\t\t\t__bounds.append([__ids,minf(__a.x,minf(__b.x,__c.x)),maxf(__a.x,maxf(__b.x,__c.x)),minf(__a.y,minf(__b.y,__c.y)),maxf(__a.y,maxf(__b.y,__c.y)),minf(__a.z,minf(__b.z,__c.z)),maxf(__a.z,maxf(__b.z,__c.z))])\n\t\t__tri_bounds_cache[shell]=__bounds\n"
	var replacement := "\t\tfor __entry in __bounds:\n\t\t\tvar ids: Array=__entry[0]\n\t\t\tif p.y<float(__entry[3])-.0001 or p.y>float(__entry[4])+.0001:\n\t\t\t\tcontinue\n\t\t\tif p.x<float(__entry[1])-.0801 or p.x>float(__entry[2])+.0801 or p.z<float(__entry[5])-.0801 or p.z>float(__entry[6])+.0801:\n\t\t\t\tcontinue"
	code=code.replace(rim_anchor,prelude+rim_anchor)
	code=code.replace(anchor,replacement)
	var candidate := GDScript.new()
	candidate.source_code = code
	if candidate.reload() != OK:
		_fail("candidate in-memory compilation failed")
		return
	var t0: int = Time.get_ticks_usec()
	var baseline_ms: float=0.0
	var candidate_ms: float=0.0
	var candidate_first: bool="--candidate-first" in OS.get_cmdline_user_args()
	if candidate_first:
		candidate.call("parts","top","tricko")
		candidate_ms=float(Time.get_ticks_usec()-t0)/1000.0
		t0=Time.get_ticks_usec()
		original.call("parts","top","tricko")
		baseline_ms=float(Time.get_ticks_usec()-t0)/1000.0
	else:
		original.call("parts","top","tricko")
		baseline_ms=float(Time.get_ticks_usec()-t0)/1000.0
		t0=Time.get_ticks_usec()
		candidate.call("parts","top","tricko")
		candidate_ms=float(Time.get_ticks_usec()-t0)/1000.0
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
	print("H3_INDEX_PARITY_PASS styles=",a.size()," meshes=",checked," surfaces=",surfaces," vertices=",vertices," blend_shapes=",blend_shapes," baseline_cold_ms=",baseline_ms," candidate_cold_ms=",candidate_ms," candidate_first=",candidate_first," exact_arrays=true")
	get_tree().quit(0)
func _synthetic_boundaries() -> bool:
	var rng:=RandomNumberGenerator.new()
	rng.seed=73131
	var count:=0
	for i in 500:
		var a:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
		var b:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
		var c:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
		var u:=rng.randf()
		var v:=rng.randf()*(1.0-u)
		var q:=a*u+b*v+c*(1.0-u-v)
		for delta in [Vector3.ZERO,Vector3(.07999,0,0),Vector3(-.07999,0,0),Vector3(0,0,.07999),Vector3(0,0,-.07999),Vector3(.056,0,.056)]:
			var p: Vector3=q+delta
			if p.distance_to(q)<=.08 and (p.y<minf(a.y,minf(b.y,c.y))-.0001 or p.y>maxf(a.y,maxf(b.y,c.y))+.0001 or p.x<minf(a.x,minf(b.x,c.x))-.0801 or p.x>maxf(a.x,maxf(b.x,c.x))+.0801 or p.z<minf(a.z,minf(b.z,c.z))-.0801 or p.z>maxf(a.z,maxf(b.z,c.z))+.0801):
				return false
			count+=1
	print("H3_INDEX_BOUNDARY_PASS checked=",count)
	return true