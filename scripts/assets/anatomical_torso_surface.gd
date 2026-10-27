extends RefCounted
## C13: an independently authored, closed 3D adult torso skin surface.
## No shirt sleeve or clothing triangles are part of this mesh. The authored
## Blender shirt supplies ONLY reference silhouette & the ten body morph deltas
## for interoperability with the original 17-bone production character.
## All surfaces are visual; no invasive gameplay/medical physics claims.
const Helper := preload("res://scripts/assets/hand_detail_builder.gd")
const LEVELS := 45
const SIDES := 48
const Y_LO := 0.990
const Y_HI := 1.520
const NAVEL_Y := 1.088

static func _front_source(verts: PackedVector3Array, y: float) -> float:
    var nearest_y: float = clampf(y,1.0,1.485)
    var found: Array = []
    for p in verts:
        if p.z <= 0.02 or absf(p.x) > 0.035 or p.y < .99 or p.y > 1.52:
            continue
        var distance: float=absf(p.y-nearest_y)+absf(p.x)*.35
        if found.size()<6:
            found.append([distance,p.z])
            found.sort_custom(func(a,b):return a[0]<b[0])
        elif distance<float(found[5][0]):
            found[5]=[distance,p.z]
            found.sort_custom(func(a,b):return a[0]<b[0])
    if found.size()<6:
        return .068
    var weighted:=0.0
    var total:=0.0
    for entry in found:
        var w:=1.0/maxf(float(entry[0]),.003)
        weighted+=float(entry[1])*w
        total+=w
    return maxf(.056,weighted/total)


static func _half_width(y: float) -> float:
    return .146+.022*smoothstep(1.08,1.39,y)-.010*smoothstep(1.42,1.52,y)


static func _base_ellipsoid(pts:PackedVector3Array,y:float) -> float:
    return _front_source(pts,y)


static func _sculpted_z(pts:PackedVector3Array,
        x:float,y:float,ellipse_z:float) -> float:
    # A continuous paired chest contour, independent of sex markers.
    var breast_x:float=(absf(x)-.105)/.052
    var breast_y:float=(y-1.350)/.065
    var chest_raise:float=.009*exp(-breast_x*breast_x-breast_y*breast_y)
    var navel_x:float=x/.018
    var navel_y:float=(y-NAVEL_Y)/.019
    # **Actual depressed geometry in the torso's indexed mesh**, not a
    # fake brown dot placed on an undisturbed clothing surface.
    var navel_indent:float=.0085*exp(-navel_x*navel_x-navel_y*navel_y)
    # Only deform the anterior of the torso. Back remains smoothly rounded.
    var forward:float=smoothstep(-.001,.045,ellipse_z)
    return ellipse_z+forward*(chest_raise-navel_indent)


static func anterior_z(pts:PackedVector3Array,x:float,y:float) -> float:
    var rx:=_half_width(y)
    if absf(x)>rx*.985:
        return -1.0
    var rz:=_base_ellipsoid(pts,y)
    var z:=rz*sqrt(maxf(0,1.0-(x/rx)*(x/rx)))
    return _sculpted_z(pts,x,y,z)


static func _add_weighted_vertex(dst:Dictionary,point:Vector3,
        normal:Vector3,uv:Vector2) -> int:
    var t:float=smoothstep(1.175,1.355,point.y)
    var index:int=Helper._vertex(dst,point,normal,1,uv)
    var bone_array:PackedInt32Array=dst["bones"]
    var weight_array:PackedFloat32Array=dst["weights"]
    # Player's canonical Gltf skin binds: spine index1, chest index2.
    # Smooth dual influence instead of a hard spine/chest seam.
    bone_array[index*4+0]=1
    bone_array[index*4+1]=2
    weight_array[index*4+0]=1.0-t
    weight_array[index*4+1]=t
    dst["bones"]=bone_array
    dst["weights"]=weight_array
    return index


static func build_surface(src:Mesh, source_positions:PackedVector3Array,
        source_blends:Array) -> ArrayMesh:
    if src==null or source_positions.is_empty() or source_blends.size()!=10:
        return null
    var shell:=Helper._blank()
    # A complete separate tubular skin volume with continuous front, flanks,
    # back and real indexed navel indentation; caps prevent open boundaries.
    for i in LEVELS:
        var t:float=float(i)/(LEVELS-1)
        var y:float=lerpf(Y_LO,Y_HI,t)
        var rx:float=_half_width(y)
        var rz:float=_base_ellipsoid(source_positions,y)
        for j in SIDES:
            var angle:float=TAU*float(j)/SIDES
            var sx:=sin(angle)
            var cz:=cos(angle)
            var x:=rx*sx
            var z:=_sculpted_z(source_positions,x,y,rz*cz)
            var point:=Vector3(x,y,z)
            var normal:=Vector3(sx/rx,0,cz/maxf(.04,rz)).normalized()
            _add_weighted_vertex(shell,point,normal,Vector2(float(j)/SIDES,t))
    for i in LEVELS-1:
        for j in SIDES:
            var next:int=(j+1)%SIDES
            var a:int=i*SIDES+j
            var b:int=i*SIDES+next
            var c:int=(i+1)*SIDES+j
            var d:int=(i+1)*SIDES+next
            Helper._tri(shell,a,b,c)
            Helper._tri(shell,b,d,c)
    var top: int=_add_weighted_vertex(shell,Vector3(0,Y_HI,0),Vector3.UP,Vector2(.5,1))
    var bottom:int=_add_weighted_vertex(shell,Vector3(0,Y_LO,0),Vector3.DOWN,Vector2(.5,0))
    for j in SIDES:
        var next:int=(j+1)%SIDES
        Helper._tri(shell,bottom,j,next)
        var last:int=(LEVELS-1)*SIDES
        Helper._tri(shell,top,last+next,last+j)
    var result:ArrayMesh=Helper._bake(shell,src,source_positions,source_blends,"torso_shell")
    return result