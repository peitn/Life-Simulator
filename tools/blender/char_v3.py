
# Postava v3 (běh 5) – ZDROJ assets/src/character_head.lsx (hlava, oči, krátké a dlouhé vlasy).
# Od C2 (běh 8) se z ní při skládání modelu `character` berou jen skupiny head/hair_*; těla body_m/body_f
# nahradila jedna síť se shape keys (char.py → body.lsx). Ponecháno kvůli reprodukovatelnosti hlavy,
# dokud ji C3 (obličejové morfy) nenahradí. Export: export_lsx('character_head', [...], arm, ORDER, {'height': 1.78}).
reset()
SUBLEV = 1
BONES = [('hips', None, (0,0,0.95), (0,0,1.08)), ('spine','hips',(0,0,1.08),(0,0,1.28)), ('chest','spine',(0,0,1.28),(0,0,1.45)),
 ('neck','chest',(0,0,1.45),(0,0,1.56)), ('head','neck',(0,0,1.56),(0,0,1.78))]
for s, sx in (('l', 1), ('r', -1)):
    BONES += [('upper_arm_'+s,'chest',(0.19*sx,0,1.42),(0.25*sx,0.01,1.16)), ('forearm_'+s,'upper_arm_'+s,(0.25*sx,0.01,1.16),(0.29*sx,0,0.93)),
              ('hand_'+s,'forearm_'+s,(0.29*sx,0,0.93),(0.305*sx,-0.005,0.80)),
              ('thigh_'+s,'hips',(0.09*sx,0,0.93),(0.1*sx,-0.01,0.5)), ('shin_'+s,'thigh_'+s,(0.1*sx,-0.01,0.5),(0.1*sx,0.02,0.09)),
              ('foot_'+s,'shin_'+s,(0.1*sx,0.02,0.09),(0.1*sx,-0.12,0.025))]
ORDER = [b[0] for b in BONES]
bpy.ops.object.armature_add(location=(0,0,0))
arm = bpy.context.active_object; arm.name = 'rig'
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for b in list(eb): eb.remove(b)
for n, p, h, t in BONES:
    e = eb.new(n); e.head = h; e.tail = t
    if p: e.parent = eb[p]; e.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

M_SKIN = mat('skin_body', (0.78, 0.58, 0.47), 0.55)
M_SHIRT = mat('cloth_shirt', (0.35, 0.42, 0.5), 0.92)
M_PANTS = mat('cloth_pants', (0.16, 0.18, 0.22), 0.88)
M_SHOE = mat('shoe_leather', (0.12, 0.1, 0.09), 0.5)
M_HAIR = mat('hair_main', (0.2, 0.13, 0.08), 0.7)
M_EYE = mat('eye_dark', (0.04, 0.035, 0.03), 0.15)

def body(name, f):
    k = 0.92 if f else 1.0
    V = [((0,0,0.95), (0.17,0.11) if f else (0.155,0.10)), ((0,0,1.10), (0.12,0.085) if f else (0.135,0.09)),
         ((0,0,1.30), (0.15,0.118) if f else (0.168,0.108)), ((0,0,1.42), (0.13,0.085) if f else (0.15,0.09)),
         ((0,0,1.50), (0.05,0.05) if f else (0.057,0.057)), ((0,0,1.58), (0.045,0.045) if f else (0.05,0.05))]
    E = [(0,1),(1,2),(2,3),(3,4),(4,5)]
    for sx in (1, -1):
        b = len(V)
        V += [((0.18*sx,0,1.42),(0.056*k,0.056*k)), ((0.218*sx,0.005,1.29),(0.05*k,0.05*k)), ((0.25*sx,0.01,1.16),(0.041*k,0.041*k)),
              ((0.27*sx,0.004,1.05),(0.043*k,0.04*k)), ((0.29*sx,0,0.93),(0.031*k,0.028*k)),
              ((0.303*sx,-0.004,0.845),(0.03*k,0.034*k)), ((0.307*sx,-0.006,0.80),(0.022*k,0.024*k))]
        E += [(3,b),(b,b+1),(b+1,b+2),(b+2,b+3),(b+3,b+4),(b+4,b+5),(b+5,b+6)]
        c = len(V)
        V += [((0.09*sx,0,0.90),(0.098 if f else 0.092,)*2), ((0.097*sx,-0.004,0.72),(0.082 if f else 0.078,)*2), ((0.1*sx,-0.01,0.5),(0.058*k,0.058*k)),
              ((0.1*sx,0.006,0.33),(0.06*k,0.062*k)), ((0.1*sx,0.02,0.10),(0.04*k,0.04*k)),
              ((0.1*sx,-0.12,0.035),(0.044*k,0.03*k))]
        E += [(0,c),(c,c+1),(c+1,c+2),(c+2,c+3),(c+3,c+4),(c+4,c+5)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([v[0] for v in V], E, [])
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    sk = o.modifiers.new('skin', 'SKIN')
    sk.branch_smoothing = 0.6
    for i, v in enumerate(V):
        me.skin_vertices[0].data[i].radius = v[1]
    me.skin_vertices[0].data[0].use_root = True
    ss = o.modifiers.new('sub', 'SUBSURF'); ss.levels = SUBLEV
    apply_mods(o)
    bpy.ops.object.shade_smooth()
    o['lsx_group'] = name
    return o

def weight_auto(objs):
    for ob in bpy.context.selected_objects: ob.select_set(False)
    for o in objs: o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')

def weight_head(o):
    vg = o.vertex_groups.new(name='head')
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
    o.parent = arm
    am = o.modifiers.new('arm', 'ARMATURE'); am.object = arm

def paint_body(o):
    o.data.materials.clear()
    for m in (M_SKIN, M_SHIRT, M_PANTS, M_SHOE): o.data.materials.append(m)
    gn = {vg.index: vg.name for vg in o.vertex_groups}
    dom = []
    for v in o.data.vertices:
        best = max(v.groups, key=lambda e: e.weight, default=None)
        dom.append(gn.get(best.group, 'hips') if best else 'hips')
    for p in o.data.polygons:
        names = [dom[i] for i in p.vertices]
        n = max(set(names), key=names.count)
        z = p.center.z
        if n.startswith('foot'): mi = 3
        elif n.startswith('hand') or n.startswith('forearm') or n in ('neck', 'head'): mi = 0
        elif n.startswith('thigh') or n.startswith('shin'): mi = 2
        elif n == 'hips': mi = 2 if z < 1.0 else 1
        elif n == 'chest' and z > 1.465: mi = 0
        else: mi = 1
        p.material_index = mi

bm_ = body('body_m', False); bf_ = body('body_f', True)
weight_auto([bm_, bf_])
paint_body(bm_); paint_body(bf_)

# Hlava: elipsoid + nos + uši
bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=10, location=(0,0,1.665))
hd = bpy.context.active_object; hd.scale = (0.083, 0.098, 0.112)
bpy.ops.object.transform_apply(scale=True)
for v in hd.data.vertices:   # užší brada, plošší temeno vzadu
    if v.co.z < 1.64: v.co.x *= 0.85 - (1.64 - v.co.z) * 2.0; v.co.y *= 0.95
    if v.co.y > 0.04 and v.co.z > 1.66: v.co.y -= 0.008
set_mat(hd, M_SKIN)
ss = hd.modifiers.new('sub','SUBSURF'); ss.levels = 1
apply_mods(hd); bpy.ops.object.shade_smooth()
nose = rbox('nose', (0.022, 0.03, 0.045), (0, -0.095, 1.66), M_SKIN, 0.009, 2, rot=(math.radians(-12), 0, 0))
ears = []
for sx in (1, -1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, location=(0.083*sx, 0.004, 1.665))
    e = bpy.context.active_object; e.scale = (0.012, 0.022, 0.032); bpy.ops.object.transform_apply(scale=True)
    set_mat(e, M_SKIN); bpy.ops.object.shade_smooth(); ears.append(e)
head = join([hd, nose] + ears, 'head'); head['lsx_group'] = 'head'
eyes = []
for sx in (1, -1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.0115, location=(0.032*sx, -0.083, 1.69))
    e = bpy.context.active_object; set_mat(e, M_EYE); bpy.ops.object.shade_smooth(); eyes.append(e)
eye = join(eyes, 'eyes'); eye['lsx_group'] = 'head'

def hair_cap(name, lowfront, lowback):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=9, location=(0, 0.006, 1.672))
    h = bpy.context.active_object; h.name = name; h.scale = (0.092, 0.107, 0.12)
    bpy.ops.object.transform_apply(scale=True)
    bm = bmesh.new(); bm.from_mesh(h.data)
    kill = [v for v in bm.verts if v.co.z < (lowfront if v.co.y < 0.0 else lowfront + (lowback - lowfront) * min(1, v.co.y / 0.06))]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(h.data); bm.free()
    so = h.modifiers.new('sol', 'SOLIDIFY'); so.thickness = 0.012; so.offset = 1
    ss = h.modifiers.new('sub','SUBSURF'); ss.levels = 1
    set_mat(h, M_HAIR); apply_mods(h); bpy.ops.object.shade_smooth()
    return h
hs = hair_cap('hair_short', 1.70, 1.61); hs['lsx_group'] = 'hair_short'
hl = hair_cap('hair_long_cap', 1.67, 1.57)
back = rbox('hair_back', (0.17, 0.05, 0.25), (0, 0.075, 1.52), M_HAIR, 0.022, 3)
hl = join([hl, back], 'hair_long'); hl['lsx_group'] = 'hair_long'
for o in (head, eye, hs, hl): weight_head(o)
