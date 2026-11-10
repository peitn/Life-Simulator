extends Node
## CPU-only projected triangle silhouette regression for authored H3 sleeve geometry.
## This is NOT a GPU/renderer/skin/morph visual certification.
const SOURCE := "res://scripts/assets/clothing_wardrobe.gd"
const SOURCE_SHA := "fe83a5725712f0f98a1a9e4e474e6a3a140d52704e371f7c4795a8f37d19312f"

func _ready() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	push_error("H3_CPU_SLEEVE_FAIL " + message)
	get_tree().quit(1)

func _edge(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (p.x-a.x)*(b.y-a.y)-(p.y-a.y)*(b.x-a.x)

func _mask(mesh: ArrayMesh, width: int, height: int, x_shift: float = 0.0) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width*height)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var projected: Array[Vector2] = []
	var scale: float = float(mini(width,height)) * 0.9
	for v in vertices:
		projected.append(Vector2(float(width)*0.5+(v.x+x_shift)*scale, float(height)*0.60-(v.y-1.1)*scale))
	for t in range(0,indices.size(),3):
		var a: Vector2 = projected[indices[t]]
		var b: Vector2 = projected[indices[t+1]]
		var c: Vector2 = projected[indices[t+2]]
		if absf(_edge(a,b,c))<0.00001:
			continue
		var x0: int = maxi(0,int(floor(minf(a.x,minf(b.x,c.x)))))
		var x1: int = mini(width-1,int(ceil(maxf(a.x,maxf(b.x,c.x)))))
		var y0: int = maxi(0,int(floor(minf(a.y,minf(b.y,c.y)))))
		var y1: int = mini(height-1,int(ceil(maxf(a.y,maxf(b.y,c.y)))))
		for y in range(y0,y1+1):
			for x in range(x0,x1+1):
				var p := Vector2(float(x)+0.5,float(y)+0.5)
				var e0: float = _edge(a,b,p)
				var e1: float = _edge(b,c,p)
				var e2: float = _edge(c,a,p)
				if (e0>=0 and e1>=0 and e2>=0) or (e0<=0 and e1<=0 and e2<=0):
					mask[y*width+x]=1
	return mask

func _candidate() -> GDScript:
	if FileAccess.get_sha256(SOURCE)!=SOURCE_SHA:
		return null
	var code: String=FileAccess.get_file_as_string(SOURCE)
	var anchor := "\t\tfor t in range(0,si.size(),3):\n\t\t\tvar ids: Array=[si[t],si[t+1],si[t+2]]"
	var rim_anchor := "\tfor vi in rim:"
	if code.count(anchor)!=1 or code.count(rim_anchor)!=1 or code.count("static func _stitch_sleeve(")!=1:
		return null
	code=code.replace("static func _stitch_sleeve(","static var __tri_bounds_cache: Dictionary = {}\n\nstatic func _stitch_sleeve(")
	var prelude := "\tvar __bounds: Array=[]\n\tif __tri_bounds_cache.has(shell):\n\t\t__bounds=__tri_bounds_cache[shell]\n\telse:\n\t\tfor __t in range(0,si.size(),3):\n\t\t\tvar __ids: Array=[si[__t],si[__t+1],si[__t+2]]\n\t\t\tvar __a: Vector3=sv[__ids[0]]\n\t\t\tvar __b: Vector3=sv[__ids[1]]\n\t\t\tvar __c: Vector3=sv[__ids[2]]\n\t\t\t__bounds.append([__ids,minf(__a.x,minf(__b.x,__c.x)),maxf(__a.x,maxf(__b.x,__c.x)),minf(__a.y,minf(__b.y,__c.y)),maxf(__a.y,maxf(__b.y,__c.y)),minf(__a.z,minf(__b.z,__c.z)),maxf(__a.z,maxf(__b.z,__c.z))])\n\t\t__tri_bounds_cache[shell]=__bounds\n"
	var replacement := "\t\tfor __entry in __bounds:\n\t\t\tvar ids: Array=__entry[0]\n\t\t\tif p.y<float(__entry[3])-.0001 or p.y>float(__entry[4])+.0001:\n\t\t\t\tcontinue\n\t\t\tif p.x<float(__entry[1])-.0801 or p.x>float(__entry[2])+.0801 or p.z<float(__entry[5])-.0801 or p.z>float(__entry[6])+.0801:\n\t\t\t\tcontinue"
	code=code.replace(rim_anchor,prelude+rim_anchor)
	code=code.replace(anchor,replacement)
	var candidate:=GDScript.new()
	candidate.source_code=code
	if candidate.reload()!=OK:
		return null
	return candidate

func _run() -> void:
	if FileAccess.get_sha256(SOURCE)!=SOURCE_SHA:
		_fail("production source SHA changed")
		return
	var candidate:=_candidate()
	if candidate==null:
		_fail("in-memory candidate compilation/anchor failed")
		return
	var original: GDScript=load(SOURCE)
	original.call("parts","top","mikina")
	candidate.call("parts","top","mikina")
	var aa: Dictionary=original.get("_loaded").get("top",{})
	var bb: Dictionary=candidate.get("_loaded").get("top",{})
	var checked:=0
	var negative:=0
	for style in ["mikina","kosile"]:
		if not aa.has(style) or not bb.has(style):
			_fail("missing authored style "+style)
			return
		for name in ["sleeve_-1","sleeve_1"]:
			var old_mesh: ArrayMesh=null
			var new_mesh: ArrayMesh=null
			for part in aa[style]:
				if part.get("name")==name:
					old_mesh=part["mesh"]
			for part in bb[style]:
				if part.get("name")==name:
					new_mesh=part["mesh"]
			if old_mesh==null or new_mesh==null:
				_fail("missing sleeve "+style+"/"+name)
				return
			if old_mesh.surface_get_arrays(0)!=new_mesh.surface_get_arrays(0) or old_mesh.surface_get_blend_shape_arrays(0)!=new_mesh.surface_get_blend_shape_arrays(0):
				_fail("exact mesh/morph mismatch "+style+"/"+name)
				return
			for size in [Vector2i(320,240),Vector2i(120,220)]:
				var before: PackedByteArray=_mask(old_mesh,size.x,size.y)
				var after: PackedByteArray=_mask(new_mesh,size.x,size.y)
				var altered: PackedByteArray=_mask(new_mesh,size.x,size.y,0.4)
				var fg:=0
				for px in before:
					if px!=0: fg+=1
				if fg<5 or before!=after:
					_fail("CPU silhouette mismatch or empty "+style+"/"+name+"/"+str(size)+" fg="+str(fg))
					return
				if before==altered:
					_fail("negative control blind "+style+"/"+name+"/"+str(size))
					return
				checked+=1
				negative+=1
				print("H3_CPU_SLEEVE_CASE_PASS ",style,"/",name," size=",size," fg=",fg)
	if checked!=8 or negative!=8:
		_fail("wrong coverage")
		return
	print("H3_CPU_SLEEVE_PARITY_PASS 8/8 negative_controls=8/8 exact_mesh_and_morph=true GPU_CERTIFICATION=PENDING")
	get_tree().quit(0)
