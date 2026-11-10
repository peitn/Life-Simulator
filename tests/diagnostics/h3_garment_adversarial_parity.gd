extends Node
## Test-only adversarial exact parity for original vs precomputed XYZ sleeve AABB filter.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	push_error("H3_ADVERSARIAL_FAIL " + message)
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
	var code:=FileAccess.get_file_as_string(SOURCE)
	var anchor: String="\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]"
	var rim_anchor: String="\tfor vi in rim:"
	if code.count(anchor)!=1 or code.count(rim_anchor)!=1 or code.count("static func _stitch_sleeve(")!=1:
		return null
	code=code.replace("static func _stitch_sleeve(","static var __tri_bounds_cache: Dictionary = {}\n\nstatic func _stitch_sleeve(")
	var prelude: String="\tvar __bounds: Array=[]\n\tif __tri_bounds_cache.has(shell):\n\t\t__bounds=__tri_bounds_cache[shell]\n\telse:\n\t\tfor __t in range(0,si.size(),3):\n\t\t\tvar __ids: Array=[si[__t],si[__t+1],si[__t+2]]\n\t\t\tvar __a: Vector3=sv[__ids[0]]\n\t\t\tvar __b: Vector3=sv[__ids[1]]\n\t\t\tvar __c: Vector3=sv[__ids[2]]\n\t\t\t__bounds.append([__ids,minf(__a.x,minf(__b.x,__c.x)),maxf(__a.x,maxf(__b.x,__c.x)),minf(__a.y,minf(__b.y,__c.y)),maxf(__a.y,maxf(__b.y,__c.y)),minf(__a.z,minf(__b.z,__c.z)),maxf(__a.z,maxf(__b.z,__c.z))])\n\t\t__tri_bounds_cache[shell]=__bounds\n"
	var replacement: String="\t\tfor __entry in __bounds:\n\t\t\tvar ids: Array=__entry[0]\n\t\t\tif p.y<float(__entry[3])-.0001 or p.y>float(__entry[4])+.0001:\n\t\t\t\tcontinue\n\t\t\tif p.x<float(__entry[1])-.0801 or p.x>float(__entry[2])+.0801 or p.z<float(__entry[5])-.0801 or p.z>float(__entry[6])+.0801:\n\t\t\t\tcontinue"
	code=code.replace(rim_anchor,prelude+rim_anchor).replace(anchor,replacement)
	var result:=GDScript.new()
	result.source_code=code
	if result.reload()!=OK:
		return null
	return result

func _run() -> void:
	var candidate:=_candidate()
	if candidate==null:
		_fail("source SHA/anchor/compile")
		return
	var original: GDScript=load(SOURCE)
	var total:=0
	var changed:=0
	for kind in ["crossing","horizontal","sliver","threshold_inside","threshold_outside","ties","degenerate","negative","large","sloped"]:
		var offset: float=10000.0 if kind=="large" else 0.0
		var shell:=_make_shell(kind,offset)
		if shell.get_surface_count()!=1:
			_fail("shell invalid "+kind)
			return
		var a:=_make_sleeve(offset)
		var b:=a.duplicate(true)
		var blend_a: Array=[a.duplicate(true)]
		var blend_b: Array=[b.duplicate(true)]
		original.call("_stitch_sleeve",a,blend_a,shell)
		candidate.call("_stitch_sleeve",b,blend_b,shell)
		if a!=b or blend_a!=blend_b:
			_fail("EXACT PARITY "+kind)
			return
		var out: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		if out[0]!=Vector3(offset,1.209,0):
			changed+=1
		total+=1
		print("H3_ADVERSARIAL_CASE_PASS ",kind," changed=",out[0]!=Vector3(offset,1.209,0))
	print("H3_ADVERSARIAL_PASS cases=",total," changed_cases=",changed," exact_arrays_and_blends=true")
	get_tree().quit(0)