extends Node
## Test-only adversarial exact parity for original vs precomputed XYZ sleeve AABB filter.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	push_error("H3_CACHE_LIFECYCLE_FAIL " + message)
	get_tree().quit(1)

func _make_arrays(v: PackedVector3Array, ix: PackedInt32Array) -> Array:
	var a: Array=[]
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=v
	a[Mesh.ARRAY_INDEX]=ix
	var normals:=PackedVector3Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	for i in v.size():
		normals.append(Vector3.UP)
		bones.append_array(PackedInt32Array([0,1,2,3]))
		weights.append_array(PackedFloat32Array([0.7,0.2,0.1,0.0]))
	a[Mesh.ARRAY_NORMAL]=normals
	a[Mesh.ARRAY_BONES]=bones
	a[Mesh.ARRAY_WEIGHTS]=weights
	return a

func _triangles(kind: String, offset: float) -> PackedVector3Array:
	var v:=PackedVector3Array()
	match kind:
		"crossing":
			v.append_array(PackedVector3Array([Vector3(-.03,1.10,0),Vector3(.03,1.30,0),Vector3(.03,1.10,.03)]))
		"horizontal":
			v.append_array(PackedVector3Array([Vector3(-.03,1.209,0),Vector3(.03,1.209,0),Vector3(0,1.209,.03)]))
		"sliver":
			v.append_array(PackedVector3Array([Vector3(.03,1.10,0),Vector3(.0300001,1.30,0),Vector3(.0300002,1.20,.000001)]))
		"threshold_inside":
			v.append_array(PackedVector3Array([Vector3(.07999,1.10,0),Vector3(.07999,1.30,0),Vector3(.07999,1.20,.03)]))
		"threshold_outside":
			v.append_array(PackedVector3Array([Vector3(.08001,1.10,0),Vector3(.08001,1.30,0),Vector3(.08001,1.20,.03)]))
		"ties":
			for i in 2:
				v.append_array(PackedVector3Array([Vector3(.02,1.10,0),Vector3(.02,1.30,0),Vector3(.02,1.20,.03)]))
		"degenerate":
			v.append_array(PackedVector3Array([Vector3(0,1.209,0),Vector3(0,1.209,0),Vector3(0,1.209,0)]))
		"negative":
			v.append_array(PackedVector3Array([Vector3(-.07,1.10,0),Vector3(-.07,1.30,0),Vector3(-.07,1.20,.03)]))
		"large":
			v.append_array(PackedVector3Array([Vector3(.03,1.10,0),Vector3(.03,1.30,0),Vector3(.03,1.20,.03)]))
		"sloped":
			v.append_array(PackedVector3Array([Vector3(-1.0,1.10,-1.0),Vector3(1.0,1.30,1.0),Vector3(0,1.20,.02)]))
	for i in v.size():
		v[i]=v[i]+Vector3(offset,0,0)
	return v

func _make_shell(kind: String, offset: float) -> ArrayMesh:
	var v:=_triangles(kind,offset)
	var ix:=PackedInt32Array()
	for i in v.size():
		ix.append(i)
	var a:=_make_arrays(v,ix)
	var blend: Array=a.duplicate(true)
	var bv: PackedVector3Array=blend[Mesh.ARRAY_VERTEX]
	for i in bv.size():
		bv[i]=bv[i]+Vector3(0,.005,0)
	blend[Mesh.ARRAY_VERTEX]=bv
	blend[Mesh.ARRAY_INDEX]=null
	blend[Mesh.ARRAY_BONES]=null
	blend[Mesh.ARRAY_WEIGHTS]=null
	var mesh:=ArrayMesh.new()
	mesh.add_blend_shape("test_morph")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[blend])
	return mesh

func _make_sleeve(offset: float) -> Array:
	var v:=PackedVector3Array()
	var ix:=PackedInt32Array()
	for i in 70:
		var y:=1.209 if i<14 else 1.4+float(i/14)*.1
		v.append(Vector3(offset, y, 0))
	for i in range(1,69):
		ix.append_array(PackedInt32Array([0,i,i+1]))
	return _make_arrays(v,ix)


func _candidate() -> GDScript:
	if FileAccess.get_sha256(SOURCE)!=SOURCE_SHA:
		return null
	var code: String=FileAccess.get_file_as_string(SOURCE)
	var anchor: String="\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]"
	var rim_anchor: String="\tfor vi in rim:"
	if code.count(anchor)!=1 or code.count(rim_anchor)!=1 or code.count("static func _stitch_sleeve(")!=1:
		return null
	code=code.replace("static func _stitch_sleeve(","static var __tri_bounds_cache: Dictionary = {}\n\nstatic func _stitch_sleeve(")
	code=code.replace(rim_anchor,"\tvar __bounds: Array=[]\n\tvar __key: int=shell.get_instance_id()\n\tfor __old_key in __tri_bounds_cache.keys():\n\t\tvar __old_ref: WeakRef=__tri_bounds_cache[__old_key].get('ref') as WeakRef\n\t\tif __old_ref==null or __old_ref.get_ref()==null:\n\t\t\t__tri_bounds_cache.erase(__old_key)\n\tvar __cached: Dictionary=__tri_bounds_cache.get(__key,{})\n\tvar __ref: WeakRef=__cached.get('ref') as WeakRef\n\tif __ref!=null and __ref.get_ref()==shell and __cached.get('vertices')==sv and __cached.get('indices')==si:\n\t\t__bounds=__cached['bounds']\n\telse:\n\t\tfor __t in range(0,si.size(),3):\n\t\t\tvar __ids: Array=[si[__t],si[__t+1],si[__t+2]]\n\t\t\tvar __a: Vector3=sv[__ids[0]]\n\t\t\tvar __b: Vector3=sv[__ids[1]]\n\t\t\tvar __c: Vector3=sv[__ids[2]]\n\t\t\t__bounds.append([__ids,minf(__a.x,minf(__b.x,__c.x)),maxf(__a.x,maxf(__b.x,__c.x)),minf(__a.y,minf(__b.y,__c.y)),maxf(__a.y,maxf(__b.y,__c.y)),minf(__a.z,minf(__b.z,__c.z)),maxf(__a.z,maxf(__b.z,__c.z))])\n\t\t__tri_bounds_cache[__key]={'ref':weakref(shell),'vertices':sv.duplicate(),'indices':si.duplicate(),'bounds':__bounds}\n"+rim_anchor)
	code=code.replace(anchor,"\t\tfor __entry in __bounds:\n\t\t\tvar ids: Array=__entry[0]\n\t\t\tif p.y<float(__entry[3])-.0001 or p.y>float(__entry[4])+.0001:\n\t\t\t\tcontinue\n\t\t\tif p.x<float(__entry[1])-.0801 or p.x>float(__entry[2])+.0801 or p.z<float(__entry[5])-.0801 or p.z>float(__entry[6])+.0801:\n\t\t\t\tcontinue")
	var result:=GDScript.new()
	result.source_code=code
	if result.reload()!=OK:
		return null
	return result

func _compare(stage: String, original: GDScript, candidate: GDScript, shell: ArrayMesh) -> bool:
	var a:=_make_sleeve(0.0)
	var b:=a.duplicate(true)
	var blend_a: Array=[a.duplicate(true)]
	var blend_b: Array=[b.duplicate(true)]
	original.call("_stitch_sleeve",a,blend_a,shell)
	candidate.call("_stitch_sleeve",b,blend_b,shell)
	if a!=b or blend_a!=blend_b:
		_fail("parity "+stage)
		return false
	print("H3_CACHE_STAGE_PASS ",stage," moved=",a[Mesh.ARRAY_VERTEX][0]!=Vector3(0,1.209,0))
	return true

func _run() -> void:
	var candidate:=_candidate()
	if candidate==null:
		_fail("source SHA/anchor/compile")
		return
	var original: GDScript=load(SOURCE)
	var shell: ArrayMesh=_make_shell("crossing",0.4)
	if not _compare("far_initial",original,candidate,shell): return
	if not _compare("far_cache_hit",original,candidate,shell): return
	var near: ArrayMesh=_make_shell("crossing",0.0)
	shell.surface_remove(0)
	shell.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,near.surface_get_arrays(0),near.surface_get_blend_shape_arrays(0))
	if not _compare("near_same_resource_mutated",original,candidate,shell): return
	if not _compare("near_cache_hit",original,candidate,shell): return
	var far: ArrayMesh=_make_shell("crossing",0.4)
	shell.surface_remove(0)
	shell.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,far.surface_get_arrays(0),far.surface_get_blend_shape_arrays(0))
	if not _compare("far_same_resource_mutated_again",original,candidate,shell): return
	var ref: WeakRef=weakref(shell)
	shell=null
	if ref.get_ref()!=null:
		_fail("cache holds strong shell reference")
		return
	var second: ArrayMesh=_make_shell("crossing",0.0)
	if not _compare("second_resource_and_gc",original,candidate,second): return
	var cache: Dictionary=candidate.get("__tri_bounds_cache")
	if cache.size()!=1:
		_fail("dead weakref not purged size="+str(cache.size()))
		return
	print("H3_CACHE_LIFECYCLE_PASS exact_arrays=true mutations=2 weak_cleanup=true stages=6")
	get_tree().quit(0)
