extends RefCounted
## H2b anatomical hand pass: five actual fingers per hand (four digits and a
## splayed thumb), shaped nail plates, skinned to EXISTING hand bones.
## Explicitly NOT independent phalange rigs or finger animation yet.
## Geometry is built once from the exact 10 torso morphs of the authored skin
## mesh, then reused by every actor. No identity/sex/age assumptions.
static var _skin_mesh: ArrayMesh
static var _nail_mesh: ArrayMesh
const SIDES := [-1.0, 1.0]
const CIRCUMFERENCE := 10
## Ten independent GPU morphs: five curls per hand, not a new 30-bone rig.
const DIGIT_COUNT := 10
const SKIN_PER_DIGIT := 51
const NAIL_PER_DIGIT := 9
const RINGS := [0.0, 0.24, 0.5, 0.77, 0.92]
const RADII := [0.95, 1.0, 0.94, 0.78, 0.53]
const DIGIT_LENGTHS := [0.048, 0.060, 0.065, 0.056]
const DIGIT_X := [-0.015, -0.005, 0.006, 0.016]
const DIGIT_RADIUS := [0.0054, 0.0057, 0.0059, 0.0051]

static func clear_cache() -> void:
    _skin_mesh = null
    _nail_mesh = null

static func build(source: MeshInstance3D) -> Dictionary:
    if _skin_mesh != null and _nail_mesh != null:
        return {"skin":_skin_mesh,"nails":_nail_mesh}
    if source==null or source.mesh==null or source.mesh.get_surface_count()!=1:
        return {}
    var ref: Mesh = source.mesh
    if ref.get_blend_shape_count()!=10:
        return {}
    var source_arrays: Array=ref.surface_get_arrays(0)
    var original: PackedVector3Array=source_arrays[Mesh.ARRAY_VERTEX]
    var blends: Array=ref.surface_get_blend_shape_arrays(0)
    if original.is_empty() or blends.size()!=10:
        return {}
    var skin_data:=_blank()
    var nail_data:=_blank()
    var digits:=0
    for side in SIDES:
        var center_x: float = side * 0.307
        var bind: int = 7 if side>0.0 else 13
        for finger in 4:
            var origin:=Vector3(center_x+side*DIGIT_X[finger], 0.815, -0.004)
            var tip:=Vector3(origin.x+side*(float(finger)-1.5)*0.00075,
                origin.y-DIGIT_LENGTHS[finger],origin.z+0.0015)
            _finger(skin_data,nail_data,origin,tip,DIGIT_RADIUS[finger],
                bind,side,false)
            digits+=1
        # Independent thumb sweeps outward from the thenar area.
        var thumb_origin:=Vector3(center_x+side*0.020,0.838,-0.008)
        var thumb_tip:=Vector3(center_x+side*0.043,0.802,0.008)
        _finger(skin_data,nail_data,thumb_origin,thumb_tip,0.0062,
            bind,side,true)
        digits+=1
    if digits!=10:
        return {}
    var faces_mesh:ArrayMesh=_bake(skin_data,ref,original,blends)
    var nail_mesh:ArrayMesh=_bake(nail_data,ref,original,blends)
    if faces_mesh==null or nail_mesh==null:
        return {}
    _skin_mesh=faces_mesh
    _nail_mesh=nail_mesh
    return {"skin":_skin_mesh,"nails":_nail_mesh}

static func _blank() -> Dictionary:
    return {"vertices":PackedVector3Array(), "normals":PackedVector3Array(),
        "uv":PackedVector2Array(), "bones":PackedInt32Array(),
        "weights":PackedFloat32Array(), "indices":PackedInt32Array()}

static func _vertex(dst: Dictionary, point: Vector3, normal: Vector3,
        bone: int, uv: Vector2) -> int:
    var verts: PackedVector3Array=dst["vertices"]
    var idx: int=verts.size()
    verts.append(point)
    dst["vertices"]=verts
    var norm: PackedVector3Array=dst["normals"]
    norm.append(normal.normalized())
    dst["normals"]=norm
    var uv_array: PackedVector2Array=dst["uv"]
    uv_array.append(uv)
    dst["uv"]=uv_array
    var bones: PackedInt32Array=dst["bones"]
    bones.append_array(PackedInt32Array([bone,0,0,0]))
    dst["bones"]=bones
    var weights: PackedFloat32Array=dst["weights"]
    weights.append_array(PackedFloat32Array([1.0,0.0,0.0,0.0]))
    dst["weights"]=weights
    return idx

static func _tri(dst: Dictionary, a: int, b: int, c: int) -> void:
    var indices: PackedInt32Array=dst["indices"]
    indices.append_array(PackedInt32Array([a,b,c]))
    dst["indices"]=indices

static func _finger(skin: Dictionary, nail: Dictionary,
        origin: Vector3, tip: Vector3, r: float,
        bone: int, side: float, thumb: bool) -> void:
    var axis: Vector3=(tip-origin).normalized()
    var u:=Vector3.FORWARD.cross(axis).normalized()
    var v:=axis.cross(u).normalized()
    var start: int=(skin["vertices"] as PackedVector3Array).size()
    var distance: float=origin.distance_to(tip)
    for ring in RINGS.size():
        var t: float=RINGS[ring]
        var center: Vector3=origin.lerp(tip,t)
        for j in CIRCUMFERENCE:
            var angle:=TAU*float(j)/float(CIRCUMFERENCE)
            var c:=cos(angle)
            var s:=sin(angle)
            var radial:Vector3=(u*c+v*s)
            var radius: float=r*RADII[ring]
            var point:=center+radial*radius
            var normal: Vector3=(radial+axis*0.10*(t-.5)).normalized()
            _vertex(skin,point,normal,bone,Vector2(float(j)/CIRCUMFERENCE,t))
    for ring in RINGS.size()-1:
        for j in CIRCUMFERENCE:
            var a:=start+ring*CIRCUMFERENCE+j
            var b:=start+ring*CIRCUMFERENCE+(j+1)%CIRCUMFERENCE
            var c:=a+CIRCUMFERENCE
            var d:=b+CIRCUMFERENCE
            _tri(skin,a,b,c)
            _tri(skin,b,d,c)
    # Rounded end: cap fan, no zero-width ring with degenerate triangles.
    var cap:=_vertex(skin,tip,axis,bone,Vector2(.5,1.0))
    for j in CIRCUMFERENCE:
        var a:=start+(RINGS.size()-1)*CIRCUMFERENCE+j
        var b:=start+(RINGS.size()-1)*CIRCUMFERENCE+(j+1)%CIRCUMFERENCE
        _tri(skin,a,b,cap)
    # Five physically modeled nail plates per side (rounded polygon), following
    # the distal digit skin and exactly the same hand bone / ten body morphs.
    # The thumb uses a shorter, wider nail, with no categorical gender options.
    var plate_center:=origin.lerp(tip,.835)
    var nail_length:float=distance*(0.18 if thumb else 0.21)
    var nail_half_width:float=r*(.68 if thumb else .72)
    var plate_front:Vector3=v*r*.91
    var offsets: Array=[
        Vector2(-.78,-1.0),Vector2(0,-1.12),Vector2(.78,-1.0),
        Vector2(1,.48),Vector2(.65,1.0),Vector2(0,1.07),
        Vector2(-.65,1.0),Vector2(-1,.48)]
    var center_id:=_vertex(nail,plate_center+plate_front*1.08,v,bone,Vector2(.5,.5))
    var rim_ids: Array=[]
    for o in offsets:
        var x:float=float(o.x)
        var y:float=float(o.y)
        var pos:=plate_center+u*x*nail_half_width+axis*y*nail_length*.5
        pos+=plate_front*(1.08-0.08*x*x)
        rim_ids.append(_vertex(nail,pos,v,bone,Vector2((x+1.0)*.5,(y+1.12)/2.2)))
    for k in rim_ids.size():
        _tri(nail,center_id,int(rim_ids[(k+1)%rim_ids.size()]),int(rim_ids[k]))

## A genuine compatible array mesh, with ten nearest-skin interpolated body
## delta fields; no new server schema and zero morph after default snapshot.
static func _bake(dst: Dictionary, source: Mesh, original: PackedVector3Array,
        source_blends: Array, region: String = "hand") -> ArrayMesh:
    var vertices: PackedVector3Array=dst["vertices"]
    var n:int=vertices.size()
    if n<3:
        return null
    var output:=ArrayMesh.new()
    # The source model uses normalized absolute targets; this new procedural
    # mesh uses additive RELATIVE deltas, including the ten body keys.
    output.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_RELATIVE
    for j in source.get_blend_shape_count():
        output.add_blend_shape(source.get_blend_shape_name(j))
    if region == "hand":
        if n != DIGIT_COUNT*SKIN_PER_DIGIT and n != DIGIT_COUNT*NAIL_PER_DIGIT:
            return null
        for digit in DIGIT_COUNT:
            output.add_blend_shape(curl_key(digit))
        # C14: additional independent proximal/distal bend morphs per
        # finger, including matching nails, without changing the 17-bone rig.
        for digit in DIGIT_COUNT:
            for segment in ["proximal","distal"]:
                output.add_blend_shape(joint_key(digit,segment))
    var arrays:Array=[]
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    arrays[Mesh.ARRAY_NORMAL]=dst["normals"]
    arrays[Mesh.ARRAY_TEX_UV]=dst["uv"]
    arrays[Mesh.ARRAY_BONES]=dst["bones"]
    arrays[Mesh.ARRAY_WEIGHTS]=dst["weights"]
    arrays[Mesh.ARRAY_INDEX]=dst["indices"]
    var target_coords: Array=[]
    for j in source_blends.size():
        target_coords.append(PackedVector3Array())
    # Only use nearby *skin hand region* vertices on the correct side.
    # Weighted 4-neighbor displacement respects published body morphs while
    # extending geometry slightly beyond the original rounded palm ends.
    for vtx in vertices:
        var near:Array=[]
        for i in original.size():
            var ref:Vector3=original[i]
            if ref.x*vtx.x<0.0:
                continue
            if region == "hand":
                if absf(ref.x)<.26 or ref.y<.77 or ref.y>.93:
                    continue
            elif region == "foot":
                if absf(ref.x)<.045 or absf(ref.x)>.17 or ref.y<.0 or ref.y>.145:
                    continue
            elif region == "torso":
                # The small nipple/areola/navel extras interpolate only the
                # forward-facing surface so back-side geometry doesn't influence
                # their authored protrusions and pigments.
                if ref.z < .015 or absf(ref.x) > .20 or ref.y < .99 or ref.y > 1.52:
                    continue
            elif region == "torso_shell":
                # The NEW full circumferential surface has an actual back
                # as well. Morph it from real back shirt vertices, not by
                # incorrectly projecting the forward breast morph onto the back.
                if absf(ref.x) > .235 or ref.y < .97 or ref.y > 1.54:
                    continue
            else:
                return null
            var dis:float=vtx.distance_squared_to(ref)
            if near.size()<4:
                near.append([dis,i])
                near.sort_custom(func(a,b):return a[0]<b[0])
            elif dis<near[3][0]:
                near[3]=[dis,i]
                near.sort_custom(func(a,b):return a[0]<b[0])
        if near.size()!=4:
            return null
        var ws:Array=[]
        var wtotal:=0.0
        for entry in near:
            var w:float=1.0/maxf(float(entry[0]),.000025)
            ws.append(w)
            wtotal+=w
        for target_id in target_coords.size():
            var delta:=Vector3.ZERO
            var target:PackedVector3Array=source_blends[target_id][Mesh.ARRAY_VERTEX]
            for k in near.size():
                var vert_index:int=int(near[k][1])
                delta+=(target[vert_index]-original[vert_index])*float(ws[k])/wtotal
            var target_points: PackedVector3Array = target_coords[target_id]
            # Relative blend shapes encode displacement, not absolute positions.
            target_points.append(delta)
            target_coords[target_id] = target_points
    var morphs:Array=[]
    for target_id in target_coords.size():
        var shaped:Array=[]
        shaped.resize(Mesh.ARRAY_MAX)
        shaped[Mesh.ARRAY_VERTEX]=target_coords[target_id]
        var neutral_normals:=PackedVector3Array()
        neutral_normals.resize(n)
        shaped[Mesh.ARRAY_NORMAL]=neutral_normals
        morphs.append(shaped)
    if region == "hand":
        var chunk_size:int=SKIN_PER_DIGIT if n==DIGIT_COUNT*SKIN_PER_DIGIT else NAIL_PER_DIGIT
        var base_normals:PackedVector3Array=dst["normals"]
        for digit in DIGIT_COUNT:
            var shape_vertices:=PackedVector3Array()
            shape_vertices.resize(n)
            var shape_normals:=PackedVector3Array()
            shape_normals.resize(n)
            var start:int=digit*chunk_size
            for k in chunk_size:
                var idx:int=start+k
                var result:Dictionary=curl_geometry(vertices[idx],base_normals[idx],digit)
                shape_vertices[idx]=(result["position"] as Vector3)-vertices[idx]
                shape_normals[idx]=(result["normal"] as Vector3)-base_normals[idx]
            var shape:Array=[]
            shape.resize(Mesh.ARRAY_MAX)
            shape[Mesh.ARRAY_VERTEX]=shape_vertices
            shape[Mesh.ARRAY_NORMAL]=shape_normals
            morphs.append(shape)
        # Two separately weighted knuckle-like hinge regions per digit.
        # These blend deltas are independent edit channels, not true
        # collision-detecting phalange bones. Same topology for skin+nails.
        for digit in DIGIT_COUNT:
            for segment in ["proximal","distal"]:
                var segment_vertices := PackedVector3Array()
                segment_vertices.resize(n)
                var segment_normals := PackedVector3Array()
                segment_normals.resize(n)
                var start:int=digit*chunk_size
                for k in chunk_size:
                    var idx:int=start+k
                    var result:Dictionary=joint_geometry(
                        vertices[idx],base_normals[idx],digit,segment)
                    segment_vertices[idx]=(result["position"] as Vector3)-vertices[idx]
                    segment_normals[idx]=(result["normal"] as Vector3)-base_normals[idx]
                var segment_shape:Array=[]
                segment_shape.resize(Mesh.ARRAY_MAX)
                segment_shape[Mesh.ARRAY_VERTEX]=segment_vertices
                segment_shape[Mesh.ARRAY_NORMAL]=segment_normals
                morphs.append(segment_shape)
    output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,morphs)
    return output

## C14 paired independent visual hinges for real GPU skin and nail meshes.
static func joint_key(digit:int, segment:String) -> StringName:
    if digit<0 or digit>=DIGIT_COUNT or segment not in ["proximal","distal"]:
        return &""
    return StringName("finger_joint_"+str(digit)+"_"+segment)


static func joint_geometry(point:Vector3,normal:Vector3,
        digit:int,segment:String) -> Dictionary:
    var endpoints:Dictionary=finger_endpoints(digit)
    if endpoints.is_empty() or segment not in ["proximal","distal"]:
        return {"position":point,"normal":normal}
    var root:Vector3=endpoints["root"]
    var tip:Vector3=endpoints["tip"]
    var length:float=root.distance_to(tip)
    var axis:Vector3=(tip-root).normalized()
    var t:float=clampf((point-root).dot(axis)/length,0.0,1.0)
    if segment=="proximal":
        var angle:float=-.76*smoothstep(.24,.64,t)
        var hinge:Vector3=root+axis*length*.29
        var q:=Quaternion(Vector3.RIGHT,angle)
        return {"position":hinge+q*(point-hinge),
            "normal":(q*normal).normalized()}
    var distal_angle:float=-.68*smoothstep(.62,.91,t)
    var hinge2:Vector3=root+axis*length*.67
    var q2:=Quaternion(Vector3.RIGHT,distal_angle)
    return {"position":hinge2+q2*(point-hinge2),
        "normal":(q2*normal).normalized()}

## Global digit order: right-hand fingers 0..4, left-hand 5..9; within
## each hand: index, middle, ring, little, thumb. No identity dependence.
static func curl_key(digit:int) -> StringName:
    return StringName("finger_curl_"+str(digit))

static func finger_endpoints(digit:int) -> Dictionary:
    if digit<0 or digit>=DIGIT_COUNT:
        return {}
    var side:float=-1.0 if digit<5 else 1.0
    var local:int=digit%5
    var cx:float=side*.307
    if local==4:
        return {
            "root":Vector3(cx+side*.020,.838,-.008),
            "tip":Vector3(cx+side*.043,.802,.008)
        }
    var origin:=Vector3(cx+side*DIGIT_X[local],.815,-.004)
    return {
        "root":origin,
        "tip":Vector3(origin.x+side*(float(local)-1.5)*.00075,
            origin.y-DIGIT_LENGTHS[local],origin.z+.0015)
    }

## Two soft bend regions approximate knuckle + middle joint via per-digit
## morphs. This genuinely changes positions/normals of *only* the requested
## digit, and nail plates use the same function to stay attached. It is not
## yet independent skeletal phalange deformation or physical collision.
static func curl_geometry(point:Vector3, normal:Vector3, digit:int) -> Dictionary:
    var endpoints:Dictionary=finger_endpoints(digit)
    if endpoints.is_empty():
        return {"position":point,"normal":normal}
    var root:Vector3=endpoints["root"]
    var tip:Vector3=endpoints["tip"]
    var length:float=root.distance_to(tip)
    var axis:Vector3=(tip-root).normalized()
    var t:float=clampf((point-root).dot(axis)/length,0.0,1.0)
    var a1:float=-.76*smoothstep(.24,.64,t)
    var a2:float=-.68*smoothstep(.62,.91,t)
    var q1:=Quaternion(Vector3.RIGHT,a1)
    var q2:=Quaternion(Vector3.RIGHT,a2)
    var hinge1:Vector3=root+axis*length*.29
    var hinge2:Vector3=root+axis*length*.67
    var moved1:Vector3=hinge1+q1*(point-hinge1)
    var hinge2_moved:Vector3=hinge1+q1*(hinge2-hinge1)
    var moved2:Vector3=hinge2_moved+q2*(moved1-hinge2_moved)
    return {"position":moved2,"normal":((q2*q1)*normal).normalized()}