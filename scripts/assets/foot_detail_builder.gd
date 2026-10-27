extends RefCounted
## C8 anatomical barefoot mesh: rounded plantar surface, five toes on
## each foot, and physically modeled nail plates. Uses EXISTING foot_l/r
## bone binds, not a complete articulated toe skeleton yet.
## Barefoot-only visibility; does not poke through closed shoes.
const HandBuilder := preload("res://scripts/assets/hand_detail_builder.gd")
static var _skin_mesh: ArrayMesh
static var _nails_mesh: ArrayMesh
const TOES_X := [-0.028,-0.013,0.0,0.013,0.027]
const TOES_LENGTH := [0.052,0.043,0.038,0.032,0.025]
const TOES_RADIUS := [0.0100,0.0084,0.0072,0.0064,0.0057]
const RING_SIDES := 12

static func clear_cache() -> void:
    _skin_mesh = null
    _nails_mesh = null

static func build(shoe_source: MeshInstance3D) -> Dictionary:
    if _skin_mesh!=null and _nails_mesh!=null:
        return {"skin":_skin_mesh,"nails":_nails_mesh}
    if shoe_source==null or shoe_source.mesh==null:
        return {}
    var src:Mesh=shoe_source.mesh
    if src.get_surface_count()!=1 or src.get_blend_shape_count()!=10:
        return {}
    var pos:PackedVector3Array=src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var morphs:Array=src.surface_get_blend_shape_arrays(0)
    var skin:Dictionary=HandBuilder._blank()
    var nails:Dictionary=HandBuilder._blank()
    for side in [-1.0,1.0]:
        var bone:int=10 if side>0 else 16
        var center_x:float=side*.100
        _sole(skin,center_x,bone)
        _ankle(skin,center_x,bone)
        for toe_id in 5:
            _toe(skin,nails,side,center_x,bone,toe_id)
    var skin_mesh:ArrayMesh=HandBuilder._bake(skin,src,pos,morphs,"foot")
    var nail_mesh:ArrayMesh=HandBuilder._bake(nails,src,pos,morphs,"foot")
    if skin_mesh==null or nail_mesh==null or skin_mesh.get_surface_count()==0 or nail_mesh.get_surface_count()==0:
        return {}
    _skin_mesh=skin_mesh
    _nails_mesh=nail_mesh
    return {"skin":_skin_mesh,"nails":_nails_mesh}

## Closes the otherwise visible dark circular hole where the legacy
## shoe shell was hidden and the authored pants/shin meet a barefoot sole.
## The shaft overlaps both the plantar volume and the trouser hem.
static func _ankle(dst:Dictionary, center_x:float, bone:int) -> void:
    var sections: Array=[
        [0.045,-.012,.028,.031],
        [0.068,-.008,.029,.029],
        [0.094,-.003,.028,.028],
        [0.118,.001,.025,.025],
        [0.133,.002,.023,.023]]
    var start:int=(dst["vertices"] as PackedVector3Array).size()
    for j in sections.size():
        var section:Array=sections[j]
        for k in RING_SIDES:
            var angle:float=TAU*float(k)/RING_SIDES
            var c:float=cos(angle)
            var sn:float=sin(angle)
            var pt:=Vector3(center_x+c*float(section[2]),
                float(section[0]),float(section[1])+sn*float(section[3]))
            HandBuilder._vertex(dst,pt,Vector3(c,.05,sn).normalized(),bone,
                Vector2(float(k)/RING_SIDES,float(j)/(sections.size()-1)))
    for j in sections.size()-1:
        for k in RING_SIDES:
            var a:int=start+j*RING_SIDES+k
            var b:int=start+j*RING_SIDES+(k+1)%RING_SIDES
            HandBuilder._tri(dst,a,a+RING_SIDES,b)
            HandBuilder._tri(dst,b,a+RING_SIDES,b+RING_SIDES)
    var lower:int=HandBuilder._vertex(dst,Vector3(center_x,.045,-.012),
        Vector3.DOWN,bone,Vector2(.5,0))
    var upper:int=HandBuilder._vertex(dst,Vector3(center_x,.133,.002),
        Vector3.UP,bone,Vector2(.5,1))
    for k in RING_SIDES:
        var a:int=start+k
        var b:int=start+(k+1)%RING_SIDES
        HandBuilder._tri(dst,a,b,lower)
        var c:int=start+(sections.size()-1)*RING_SIDES+k
        var d:int=start+(sections.size()-1)*RING_SIDES+(k+1)%RING_SIDES
        HandBuilder._tri(dst,c,upper,d)


static func _sole(dst:Dictionary, center_x:float, bone:int) -> void:
    var rings: Array=[
        [-.032,.055,.65,.67],
        [-.012,.057,.83,1.0],
        [.038,.051,.96,1.0],
        [.086,.042,1.09,.91],
        [.119,.037,1.11,.79],
        [.140,.035,.81,.70]
    ]
    var start:int=(dst["vertices"] as PackedVector3Array).size()
    for i in rings.size():
        var r:Array=rings[i]
        for j in RING_SIDES:
            var angle:float=TAU*float(j)/RING_SIDES
            var ct:float=cos(angle)
            var st:float=sin(angle)
            var x:float=center_x+ct*.043*float(r[2])
            var y:float=float(r[1])+st*.037*float(r[3])
            var z:float=float(r[0])
            var normal:=Vector3(ct*.85,st,0.08 if i==0 else .02).normalized()
            HandBuilder._vertex(dst,Vector3(x,y,z),normal,bone,Vector2(float(j)/RING_SIDES,float(i)/(rings.size()-1)))
    for r in rings.size()-1:
        for j in RING_SIDES:
            var a:int=start+r*RING_SIDES+j
            var b:int=start+r*RING_SIDES+(j+1)%RING_SIDES
            HandBuilder._tri(dst,a,b,a+RING_SIDES)
            HandBuilder._tri(dst,b,b+RING_SIDES,a+RING_SIDES)
    var rear:=HandBuilder._vertex(dst,Vector3(center_x,.055,-.034),
        Vector3.BACK,bone,Vector2(.5,0))
    var fore:=HandBuilder._vertex(dst,Vector3(center_x,.035,.141),
        Vector3.FORWARD,bone,Vector2(.5,1))
    for j in RING_SIDES:
        var a:int=start+j
        var b:int=start+(j+1)%RING_SIDES
        HandBuilder._tri(dst,rear,a,b)
        var c:int=start+(rings.size()-1)*RING_SIDES+j
        var d:int=start+(rings.size()-1)*RING_SIDES+(j+1)%RING_SIDES
        HandBuilder._tri(dst,c,fore,d)

static func _toe(dst:Dictionary, nails:Dictionary, side:float,
        center_x:float, bone:int, index:int) -> void:
    var root:=Vector3(center_x+side*TOES_X[index],.034,.118-absf(float(index)-2.0)*.003)
    var tip:=root+Vector3(side*(float(index)-2.0)*.0015,-.003,TOES_LENGTH[index])
    var forward:Vector3=(tip-root).normalized()
    var across:=Vector3.UP.cross(forward).normalized()
    var up:=forward.cross(across).normalized()
    var base:int=(dst["vertices"] as PackedVector3Array).size()
    var ts: Array=[0.0,.27,.57,.83,.94]
    var taper: Array=[1.0,1.02,.95,.75,.46]
    for r in ts.size():
        var center:Vector3=root.lerp(tip,float(ts[r]))
        for j in RING_SIDES:
            var angle:float=TAU*float(j)/RING_SIDES
            var n:Vector3=(across*cos(angle)+up*sin(angle)).normalized()
            var radius:float=TOES_RADIUS[index]*float(taper[r])
            HandBuilder._vertex(dst,center+n*radius,n,bone,Vector2(float(j)/RING_SIDES,float(ts[r])))
    for ring in ts.size()-1:
        for j in RING_SIDES:
            var a:int=base+ring*RING_SIDES+j
            var b:int=base+ring*RING_SIDES+(j+1)%RING_SIDES
            HandBuilder._tri(dst,a,b,a+RING_SIDES)
            HandBuilder._tri(dst,b,b+RING_SIDES,a+RING_SIDES)
    var tip_index:int=HandBuilder._vertex(dst,tip,forward,bone,Vector2(.5,1))
    for j in RING_SIDES:
        var a:int=base+(ts.size()-1)*RING_SIDES+j
        var b:int=base+(ts.size()-1)*RING_SIDES+(j+1)%RING_SIDES
        HandBuilder._tri(dst,a,b,tip_index)
    # Visible toenail plate as a small curved cap on dorsal (+Y) surface.
    var plate_center:Vector3=root.lerp(tip,.805)+up*TOES_RADIUS[index]*.98
    var nail_width:float=TOES_RADIUS[index]*.67
    var nail_length:float=TOES_LENGTH[index]*.19
    var center:int=HandBuilder._vertex(nails,plate_center+up*.00045,up,bone,Vector2(.5,.5))
    var ring: Array=[]
    for xy in [Vector2(-.79,-1.0),Vector2(0,-1.14),Vector2(.79,-1.0),
        Vector2(1,.5),Vector2(.63,1.0),Vector2(0,1.07),
        Vector2(-.63,1.0),Vector2(-1,.5)]:
        var point: Vector3=plate_center+across*float(xy.x)*nail_width+forward*float(xy.y)*nail_length*.5
        point+=up*(.0004-.0003*xy.x*xy.x)
        ring.append(HandBuilder._vertex(nails,point,up,bone,Vector2((xy.x+1)*.5,(xy.y+1.14)/2.28)))
    for j in ring.size():
        HandBuilder._tri(nails,center,int(ring[(j+1)%ring.size()]),int(ring[j]))