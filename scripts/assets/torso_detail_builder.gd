extends RefCounted
## Surface anatomy for *all* adult character bodies, independent of sex/gender.
## Torso is derived from the 10-morph authored Blender shirt silhouette,
## because legacy character.glb skin_body has only hands/neck, NO trunk.
## Adds symmetrical 3D areola+nipple surfaces and a ringed navel dimple.
## Only visible with no top garment, or explicit local skin/anatomy mode.
## The navel relief is an inset VISUAL (unmodified torso topology), not a
## physiological umbilical cavity. No gameplay sexuality or physics data.
const Helper := preload("res://scripts/assets/hand_detail_builder.gd")
static var _meshes: Dictionary = {}
const RING := 16

static func clear_cache() -> void:
    _meshes.clear()


static func build(shirt: MeshInstance3D) -> Dictionary:
    if not _meshes.is_empty():
        return _meshes
    if shirt == null or shirt.mesh == null or shirt.skin == null:
        return {}
    var src: Mesh = shirt.mesh
    if src.get_surface_count() != 1 or src.get_blend_shape_count() != 10:
        return {}
    var arr: Array = src.surface_get_arrays(0)
    var source_positions: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var source_blends: Array = src.surface_get_blend_shape_arrays(0)
    if source_positions.size() < 300 or source_blends.size() != 10:
        return {}
    # The exact authored Blender shirt's mesh vertices + body morph shapes
    # are the best currently available close-fitting torso proxy.
    var surface: Mesh = src
    var areola := Helper._blank()
    var nipple := Helper._blank()
    var navel_rim := Helper._blank()
    var navel_dark := Helper._blank()
    for s in [-1.0,1.0]:
        var center_x: float = s * .103
        var center_y := 1.351
        var center_z: float = _anterior_z(source_positions,center_x,center_y)
        if center_z < 0.02:
            return {}
        # Shallow areola surface at local anterior skin curvature.
        _disc(areola,Vector3(center_x,center_y,center_z+.0020),
            .0190,.0130,.0017,2)
        # Rounded, projecting central papilla: similar shape for all bodies,
        # no assumptions based on chromosomes, gender or hormonal treatment.
        _disc(nipple,Vector3(center_x,center_y,center_z+.0036),
            .0060,.0053,.0050,2)
    var navel_z:float=_anterior_z(source_positions,0.0,1.088)
    if navel_z < .02:
        return {}
    # Oval navel rim with shallow negative relief. The dark base keeps the
    # recess visually readable even when the original base torso mesh remains.
    _disc(navel_rim,Vector3(0,1.088,navel_z+.0017),
        .0110,.0150,.0018,1)
    _disc(navel_dark,Vector3(0,1.087,navel_z+.00315),
        .0040,.0070,.00065,1)
    var parts := {
        "surface":surface,
        "areola":Helper._bake(areola,src,source_positions,source_blends,"torso"),
        "nipple":Helper._bake(nipple,src,source_positions,source_blends,"torso"),
        "navel_rim":Helper._bake(navel_rim,src,source_positions,source_blends,"torso"),
        "navel_dark":Helper._bake(navel_dark,src,source_positions,source_blends,"torso")
    }
    for key in parts:
        if parts[key] == null or (parts[key] as Mesh).get_blend_shape_count()!=10:
            return {}
    _meshes = parts
    return _meshes


## Weighted positive-Z anterior surface from closest authored shirt vertices.
## Only sample front-facing chest or abdomen: back triangles are never used.
static func _anterior_z(pts:PackedVector3Array,x:float,y:float) -> float:
    var nearest:Array=[]
    for p in pts:
        if p.z < .025 or p.y < .99 or p.y > 1.5 or absf(p.x) > .24:
            continue
        var distance:float=(p.x-x)*(p.x-x)+(p.y-y)*(p.y-y)
        if nearest.size()<5:
            nearest.append([distance,p.z])
            nearest.sort_custom(func(a,b):return a[0]<b[0])
        elif distance < float(nearest[4][0]):
            nearest[4]=[distance,p.z]
            nearest.sort_custom(func(a,b):return a[0]<b[0])
    if nearest.size()!=5 or float(nearest[0][0])>.012:
        return -1.0
    var num:=0.0
    var den:=0.0
    var envelope_z:float=-1.0
    for entry in nearest:
        var w:float=1.0/maxf(float(entry[0]),.00002)
        num+=float(entry[1])*w
        den+=w
        envelope_z=maxf(envelope_z,float(entry[1]))
    # Use the anterior envelope rather than mean mid-torso Z. Averaging
    # neighboring skirt/shirt patch vertices put the papilla UNDER the skin
    # at high-chest morphs; a weighted envelope prevents self-occlusion.
    return .2*num/den+.8*envelope_z


## A finite, capped, convex radial surface; the navel uses two separate
## materials and a shallow dark inset rather than claiming a true hole.
static func _disc(dst:Dictionary,center:Vector3,
        half_x:float,half_y:float,projection:float,bone:int) -> void:
    var middle:int=Helper._vertex(dst,center+Vector3(0,0,projection),
        Vector3.FORWARD,bone,Vector2(.5,.5))
    var prev_rim:int=-1
    for ring in 2:
        var r:float=.56 if ring==0 else 1.0
        var z:float=projection*(.72 if ring==0 else 0.03)
        var offset:int=(dst["vertices"] as PackedVector3Array).size()
        for j in RING:
            var angle:float=TAU*j/RING
            var cx:float=cos(angle)
            var cy:float=sin(angle)
            var pos:Vector3=center+Vector3(cx*half_x*r,cy*half_y*r,z)
            var normal:=Vector3(cx*.13,cy*.13,1).normalized()
            Helper._vertex(dst,pos,normal,bone,
                Vector2(.5+cx*.5*r,.5+cy*.5*r))
            if ring == 0:
                Helper._tri(dst,middle,offset+j,offset+(j+1)%RING)
            else:
                var a:int=prev_rim+j
                var b:int=prev_rim+(j+1)%RING
                Helper._tri(dst,a,offset+j,b)
                Helper._tri(dst,b,offset+j,offset+(j+1)%RING)
        prev_rim=offset