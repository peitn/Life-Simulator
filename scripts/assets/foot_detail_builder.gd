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
        for toe_id in 5:
            _toe(skin,nails,side,center_x,bone,toe_id)
    var skin_mesh:ArrayMesh=HandBuilder._bake(skin,src,pos,morphs,"foot")
    var nail_mesh:ArrayMesh=HandBuilder._bake(nails,src,pos,morphs,"foot")
    if skin_mesh==null or nail_mesh==null or skin_mesh.get_surface_count()==0 or nail_mesh.get_surface_count()==0:
        return {}
    _skin_mesh=skin_mesh
    _nails_mesh=nail_mesh
    return {"skin":_skin_mesh,"nails":_nails_mesh}

## Continuous heel/instep/ankle surface. A separate capped ankle cylinder
## produced visible circular ridges. These elliptical sections share vertices.
static func _sole(dst:Dictionary, center_x:float, bone:int) -> void:
    # y, center-z, transverse radius, longitudinal radius.
    var sections: Array=[
        [.225,.000,.027,.027], [.180,.000,.026,.027],
        [.130,.002,.025,.031], [.095,.014,.030,.049],
        [.065,.037,.042,.081], [.039,.044,.047,.088],
        [.017,.044,.043,.083], [.008,.044,.033,.069]]
    var start:int=(dst["vertices"] as PackedVector3Array).size()
    for j in sections.size():
        var row:Array=sections[j]
        for k in RING_SIDES:
            var angle:float=TAU*float(k)/RING_SIDES
            var c:float=cos(angle)
            var sn:float=sin(angle)
            var point:=Vector3(center_x+c*float(row[2]),float(row[0]),float(row[1])+sn*float(row[3]))
            var normal:=Vector3(c,0.0,sn).normalized()
            var vi:int=HandBuilder._vertex(dst,point,normal,bone,Vector2(float(k)/RING_SIDES,float(j)/(sections.size()-1)))
            # Upper shaft follows shin, lower foot follows foot; blend at ankle.
            var shin:float=smoothstep(.075,.145,point.y)
            var ids:PackedInt32Array=dst["bones"]
            var ws:PackedFloat32Array=dst["weights"]
            ids[vi*4+1]=bone-1
            ws[vi*4]=1.0-shin
            ws[vi*4+1]=shin
            dst["bones"]=ids
            dst["weights"]=ws
    for j in sections.size()-1:
        for k in RING_SIDES:
            var a:int=start+j*RING_SIDES+k
            var b:int=start+j*RING_SIDES+(k+1)%RING_SIDES
            HandBuilder._tri(dst,a,b,a+RING_SIDES)
            HandBuilder._tri(dst,b,b+RING_SIDES,a+RING_SIDES)
    var top:int=HandBuilder._vertex(dst,Vector3(center_x,.225,0),Vector3.UP,bone-1,Vector2(.5,0))
    var bottom:int=HandBuilder._vertex(dst,Vector3(center_x,.008,.044),Vector3.DOWN,bone,Vector2(.5,1))
    for k in RING_SIDES:
        var a:int=start+k
        var b:int=start+(k+1)%RING_SIDES
        HandBuilder._tri(dst,a,top,b)
        var c:int=start+(sections.size()-1)*RING_SIDES+k
        var d:int=start+(sections.size()-1)*RING_SIDES+(k+1)%RING_SIDES
        HandBuilder._tri(dst,c,d,bottom)
    # Normals of the unified surface, including tapered instep and plantar arch.
    var verts:PackedVector3Array=dst["vertices"]
    var indices:PackedInt32Array=dst["indices"]
    var normals:PackedVector3Array=dst["normals"]
    for i in range(start,normals.size()): normals[i]=Vector3.ZERO
    for i in range(0,indices.size(),3):
        if indices[i]<start: continue
        var a:int=indices[i]
        var b:int=indices[i+1]
        var c:int=indices[i+2]
        var n:Vector3=(verts[b]-verts[a]).cross(verts[c]-verts[a])
        normals[a]+=n
        normals[b]+=n
        normals[c]+=n
    for i in range(start,normals.size()): normals[i]=normals[i].normalized()
    dst["normals"]=normals

static func _toe(dst:Dictionary, nails:Dictionary, side:float,
        center_x:float, bone:int, index:int) -> void:
    var root:=Vector3(center_x+side*TOES_X[index],.034,.125-absf(float(index)-2.0)*.003)
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
